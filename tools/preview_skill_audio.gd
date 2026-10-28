extends SceneTree
## Isolated engine-mixed listening sample; no Main, profile, microphone or system loopback.

const DURATION: float = 6.0
const MIX_GAIN: float = 0.65
const PHASES: Array[Dictionary] = [
	{"at": 0.10, "name": "legacy-rune", "sounds": [["rune", -20.0, ""]]},
	{"at": 0.85, "name": "dash", "sounds": [["dash", -20.0, "dash"]]},
	{"at": 1.55, "name": "empty-pulse", "sounds": [["pulse", -20.0, "pulse"]]},
	{"at": 2.25, "name": "affected-pulse", "sounds": [["pulse_hit", -20.0, "pulse"]]},
	{"at": 2.95, "name": "successful-evasion", "sounds": [["evade", -22.0, "dash_evasion"]]},
	{"at": 3.65, "name": "dual-skills-and-ordinary", "sounds": [["dash", -20.0, "dash"], ["pulse_hit", -20.0, "pulse"], ["shoot", -24.0, ""], ["hit", -24.0, ""], ["death", -22.0, ""]]},
	{"at": 3.74, "name": "evasion-during-dense-audio", "sounds": [["evade", -22.0, "dash_evasion"]]},
	{"at": 3.86, "name": "ordinary-burst", "sounds": [["shoot", -24.0, ""], ["hit", -24.0, ""], ["death", -22.0, ""]]},
	{"at": 3.88, "name": "actual-hurt-priority", "sounds": [["hurt", -7.0, ""]], "cancel_evasion": true},
	{"at": 3.98, "name": "ordinary-after-hurt-1", "sounds": [["shoot", -24.0, ""], ["hit", -24.0, ""], ["death", -22.0, ""]]},
	{"at": 4.10, "name": "ordinary-after-hurt-2", "sounds": [["shoot", -24.0, ""], ["hit", -24.0, ""], ["death", -22.0, ""]]},
	{"at": 4.22, "name": "ordinary-after-hurt-3", "sounds": [["shoot", -24.0, ""], ["hit", -24.0, ""], ["death", -22.0, ""]]},
	{"at": 4.34, "name": "ordinary-after-hurt-4", "sounds": [["shoot", -24.0, ""], ["hit", -24.0, ""], ["death", -22.0, ""]]},
]

var _bank: SoundBank
var _host: Node
var _capture: AudioEffectCapture
var _bus_name: String
var _master: Dictionary = {}
var _solo_states: Dictionary = {}
var _frames: PackedVector2Array = PackedVector2Array()
var _events: Array[Dictionary] = []
var _started_usec: int = 0
var _baseline_pushed: int = 0
var _baseline_discarded: int = 0
var _restored: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output: String = "res://reports/skill-feedback/engine-mix.wav"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		else:
			push_error("Use native preview_skill_audio.gd [--output=path.wav]")
			quit(2)
			return
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy" or output.is_empty() or not output.to_lower().ends_with(".wav"):
		push_error("Skill audio preview requires native audio and a WAV output path")
		quit(2)
		return
	root.title = "秘术余烬 · 原符文 / 冲刺 / 空脉冲 / 命中脉冲 / 闪避 / 密集混音（引擎采样）"
	if not _prepare_audio():
		_restore_audio()
		quit(1)
		return
	var source: Dictionary = _source_fingerprint()
	await _wait_and_drain(0.15)
	_capture.clear_buffer()
	_frames.clear()
	_baseline_pushed = _capture.get_pushed_frames()
	_baseline_discarded = _capture.get_discarded_frames()
	_started_usec = Time.get_ticks_usec()
	var next_phase: int = 0
	while float(Time.get_ticks_usec() - _started_usec) / 1000000.0 < DURATION:
		_drain()
		var elapsed: float = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
		while next_phase < PHASES.size() and elapsed >= float(PHASES[next_phase]["at"]):
			_dispatch(PHASES[next_phase])
			next_phase += 1
		await process_frame
	_bank.shutdown()
	await _wait_and_drain(0.12)
	_drain()
	var report: Dictionary = _write_mix(output, source)
	_restore_audio()
	report["audio_state_restored"] = _audio_state_restored()
	report["passed"] = bool(report.get("passed", false)) and bool(report["audio_state_restored"])
	var report_path: String = ProjectSettings.globalize_path(output).get_basename() + ".json"
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write engine mix report: " + report_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("SKILL_AUDIO_MIX ", JSON.stringify({"passed": report["passed"], "wav": ProjectSettings.globalize_path(output), "report": report_path, "frames": _frames.size(), "sample_rate": report["sample_rate"], "peak": report["peak"], "rms": report["rms"], "discarded_frames": report["discarded_frames"], "phases": _events.size(), "capture": "isolated engine bus after explicit 0.65 gain; not system loopback"}))
	quit(0 if bool(report["passed"]) else 1)

func _prepare_audio() -> bool:
	_master = {"volume_db": AudioServer.get_bus_volume_db(0), "mute": AudioServer.is_bus_mute(0), "bypass": AudioServer.is_bus_bypassing_effects(0)}
	for index: int in AudioServer.bus_count:
		var name: String = AudioServer.get_bus_name(index)
		_solo_states[name] = AudioServer.is_bus_solo(index)
		AudioServer.set_bus_solo(index, false)
	AudioServer.set_bus_volume_db(0, 0.0)
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_bypass_effects(0, true)
	_bus_name = "SkillAudioPreview_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	AudioServer.add_bus()
	var bus: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, _bus_name)
	AudioServer.set_bus_send(bus, "Master")
	AudioServer.set_bus_volume_db(bus, 0.0)
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_bypass_effects(bus, false)
	var gain := AudioEffectAmplify.new()
	gain.volume_linear = MIX_GAIN
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 8.0
	AudioServer.add_bus_effect(bus, gain)
	AudioServer.add_bus_effect(bus, _capture)
	_host = Node.new()
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_host)
	_bank = SoundBank.new()
	_host.add_child(_bank)
	if _bank.voices.size() != 12 or _bank.streams.size() != SoundBank.NAMES.size():
		push_error("The listening fixture requires all thirteen real SFX streams and the native twelve-voice pool")
		return false
	for voice: AudioStreamPlayer in _bank.voices:
		voice.bus = _bus_name
	if is_instance_valid(_bank.ambience):
		_bank.ambience.bus = _bus_name
	return true

func _wait_and_drain(seconds: float) -> void:
	var deadline: int = Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		_drain()
		await process_frame

func _drain() -> void:
	if _capture == null:
		return
	var available: int = _capture.get_frames_available()
	if available > 0:
		_frames.append_array(_capture.get_buffer(available))

func _dispatch(phase: Dictionary) -> void:
	var requests: Array[Dictionary] = []
	for entry: Array in phase["sounds"]:
		var sound: String = str(entry[0])
		var level: float = float(entry[1])
		var cue: String = str(entry[2])
		var key: String = sound if cue.is_empty() else "cue:%s:%s" % [cue, sound]
		var before: int = int(_bank.last_played.get(key, -1))
		if cue.is_empty():
			_bank.play(sound, level)
		else:
			_bank.play_cue(sound, level, cue)
		requests.append({"sound": sound, "volume_db": level, "cue": cue, "accepted": int(_bank.last_played.get(key, -1)) != before})
	if bool(phase.get("cancel_evasion", false)):
		_bank.cancel_cue("dash_evasion")
	var event: Dictionary = {"phase": phase["name"], "scheduled_seconds": phase["at"], "dispatch_wall_seconds": float(Time.get_ticks_usec() - _started_usec) / 1000000.0, "captured_frames_before_dispatch": _frames.size(), "requests": requests, "cancel_evasion": bool(phase.get("cancel_evasion", false))}
	_events.append(event)
	root.title = "秘术余烬 · 音效试听 / %s（孤立引擎混音，不保存档案）" % str(phase["name"])
	print("SKILL_AUDIO_PHASE ", JSON.stringify(event))

func _write_mix(output: String, source: Dictionary) -> Dictionary:
	var path: String = ProjectSettings.globalize_path(output)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var pcm := PackedByteArray()
	pcm.resize(_frames.size() * 4)
	var peak: float = 0.0
	var energy: float = 0.0
	var clipped: int = 0
	var nonfinite: int = 0
	for index: int in _frames.size():
		for channel: int in 2:
			var value: float = _frames[index][channel]
			if not is_finite(value):
				nonfinite += 1
				value = 0.0
			peak = maxf(peak, absf(value))
			energy += value * value
			clipped += 1 if absf(value) >= 1.0 else 0
			pcm.encode_s16(index * 4 + channel * 2, int(roundf(clampf(value, -1.0, 1.0) * 32767.0)))
	var sample_rate: int = int(AudioServer.get_mix_rate())
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = sample_rate
	wave.stereo = true
	wave.data = pcm
	var save_error: Error = wave.save_to_wav(path) if directory_error == OK else directory_error
	var discarded: int = _capture.get_discarded_frames() - _baseline_discarded
	var rms: float = sqrt(energy / float(maxi(1, _frames.size() * 2)))
	var all_accepted: bool = true
	for phase: Dictionary in _events:
		for request: Dictionary in phase["requests"]:
			all_accepted = all_accepted and bool(request["accepted"])
	return {
		"scenario": "isolated-skill-audio-listening-mix",
		"engine": Engine.get_version_info(), "os": OS.get_name(),
		"driver": AudioServer.get_driver_name(), "speaker_mode": AudioServer.get_speaker_mode(),
		"sample_rate": sample_rate, "channels": 2, "format": "signed-16-bit-little-endian-PCM",
		"frames": _frames.size(), "duration_seconds": float(_frames.size()) / float(sample_rate),
		"peak": peak, "rms": rms, "clipped_samples": clipped, "nonfinite_samples": nonfinite,
		"discarded_frames": discarded, "pushed_frames": _capture.get_pushed_frames() - _baseline_pushed,
		"wav_save_error": save_error, "wav_sha256": FileAccess.get_sha256(path) if save_error == OK else "",
		"gain": {
			"method": "dedicated unity bus with ordered AudioEffectAmplify then AudioEffectCapture",
			"explicit_linear_gain": MIX_GAIN, "master_linear_gain": 1.0,
			"master_effects_bypassed_during_diagnostic": true,
			"nominal_equivalence": "0.65 default Master gain for this isolated bank in a linear no-other-effects mix",
			"includes_default_ambience": is_instance_valid(_bank.ambience),
		},
		"scope": "Actual engine bus samples from explicit diagnostic SoundBank requests, not a game run, hardware hearing test, microphone or system loopback; dispatch markers precede audio-thread playback and are not sample-accurate boundaries.",
		"phases": _events, "all_requests_accepted": all_accepted, "source": source,
		"passed": save_error == OK and _frames.size() > sample_rate * 5 and rms > 0.00001 and peak < 1.0 and nonfinite == 0 and discarded == 0 and _events.size() == PHASES.size() and all_accepted,
	}

func _source_fingerprint() -> Dictionary:
	var files: Dictionary = {}
	var paths: Array[String] = ["res://scripts/core/sound_bank.gd", get_script().resource_path]
	for sound: String in SoundBank.NAMES + ["ambience"]:
		paths.append("res://assets/audio/%s.wav" % sound)
	for path: String in paths:
		files[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "unavailable"
	var pcm: Dictionary = {}
	for name: String in SoundBank.NAMES:
		var stream := _bank.streams[name] as AudioStreamWAV
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(stream.data)
		pcm[name] = {"sha256": hash.finish().hex_encode(), "format": stream.format, "mix_rate": stream.mix_rate, "stereo": stream.stereo, "length_seconds": stream.get_length()}
	return {"files": files, "loaded_sfx_pcm": pcm}

func _restore_audio() -> void:
	if _restored:
		return
	if is_instance_valid(_bank):
		_bank.shutdown()
	if not _bus_name.is_empty():
		var bus: int = AudioServer.get_bus_index(_bus_name)
		if bus >= 0:
			AudioServer.remove_bus(bus)
	if not _master.is_empty():
		AudioServer.set_bus_volume_db(0, float(_master["volume_db"]))
		AudioServer.set_bus_mute(0, bool(_master["mute"]))
		AudioServer.set_bus_bypass_effects(0, bool(_master["bypass"]))
	for name: String in _solo_states:
		var bus: int = AudioServer.get_bus_index(name)
		if bus >= 0:
			AudioServer.set_bus_solo(bus, bool(_solo_states[name]))
	_restored = true

func _audio_state_restored() -> bool:
	if _master.is_empty() or AudioServer.get_bus_index(_bus_name) >= 0 or AudioServer.bus_count != _solo_states.size():
		return false
	if not is_equal_approx(AudioServer.get_bus_volume_db(0), float(_master["volume_db"])) or AudioServer.is_bus_mute(0) != bool(_master["mute"]) or AudioServer.is_bus_bypassing_effects(0) != bool(_master["bypass"]):
		return false
	for name: String in _solo_states:
		var bus: int = AudioServer.get_bus_index(name)
		if bus < 0 or AudioServer.is_bus_solo(bus) != bool(_solo_states[name]):
			return false
	return true

func _finalize() -> void:
	_restore_audio()
