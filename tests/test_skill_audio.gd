extends SceneTree
## Real WAV/player scheduling and native playback progress; audible mix review is a separate artifact.

var _checks: int = 0
var _failures: int = 0
var _bank: SoundBank
var _host: Node
var _headless: bool = false
var _original_mute: bool = false
var _original_volume_db: float = 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_original_mute = AudioServer.is_bus_mute(0)
	_original_volume_db = AudioServer.get_bus_volume_db(0)
	_headless = DisplayServer.get_name() == "headless"
	_host = Node.new()
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_host)
	_bank = SoundBank.new()
	_host.add_child(_bank)
	if _prepare():
		_test_cancellation_and_cleanup()
		await _test_simultaneous_and_flood()
		await _test_full_protection_and_priority()
		await _test_real_tail_beyond_wall_deadline()
		await _test_pause_tail()
		await _test_mute_no_queue()
	_bank.shutdown()
	_host.queue_free()
	for frame: int in 3:
		await process_frame
	await create_timer(0.10, true).timeout
	AudioServer.set_bus_volume_db(0, _original_volume_db)
	AudioServer.set_bus_mute(0, _original_mute)
	print("SkillAudio: %d assertions, %d failures; native playback progress=%s; explicit headless injection=%s; scheduling/progress only, not hardware hearing" % [_checks, _failures, not _headless, _headless])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _prepare() -> bool:
	if _headless:
		_check(_bank.streams.is_empty() and _bank.voices.is_empty() and not is_instance_valid(_bank.ambience), "Production headless startup remains silent with no implicit players or audio loads")
		_load_streams()
		for index: int in 12:
			var voice := AudioStreamPlayer.new()
			voice.bus = "Master"
			_bank.add_child(voice)
			_bank.voices.append(voice)
	else:
		_check(_bank.voices.size() == 12 and _bank.streams.size() == 13, "Native startup loads thirteen actual SFX into the unchanged twelve-player pool")
		_check(is_instance_valid(_bank.ambience) and _bank.ambience.playing and _bank.ambience.stream is AudioStreamWAV, "Native ambience is an actual independently playing WAV")
	var valid: bool = _bank.voices.size() == 12 and _bank.streams.size() == 13
	for name: String in SoundBank.NAMES:
		var stream: AudioStreamWAV = _bank.streams.get(name) as AudioStreamWAV
		_check(stream != null and stream.resource_path == "res://assets/audio/%s.wav" % name and stream.get_length() > 0.0 and not stream.data.is_empty(), "Every scheduling source is its nonempty real imported WAV: " + name)
		valid = valid and stream != null and stream.get_length() > 0.0
	var distinct: Dictionary = {}
	for name: String in ["dash", "pulse", "pulse_hit", "evade"]:
		var stream: AudioStreamWAV = _bank.streams.get(name) as AudioStreamWAV
		if stream != null:
			distinct[stream.data.hex_encode().sha256_text()] = true
	_check(distinct.size() == 4, "The four skill cues contain distinct real imported audio data, not renamed copies of rune")
	_check(_bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return voice.is_inside_tree() and voice.bus == "Master"), "Every SFX voice is a real in-tree Master player")
	_bank.set_volume(0.25)
	return valid

func _load_streams() -> void:
	for name: String in SoundBank.NAMES:
		_bank.streams[name] = load("res://assets/audio/%s.wav" % name)

func _reset() -> void:
	_bank.shutdown()
	_load_streams()
	_bank.set_volume(0.25)

func _voice(name: String) -> AudioStreamPlayer:
	for voice: AudioStreamPlayer in _bank.voices:
		if voice.stream == _bank.streams.get(name):
			return voice
	return null

func _snapshot() -> Array:
	var result: Array = []
	for voice: AudioStreamPlayer in _bank.voices:
		result.append([voice.get_instance_id(), voice.stream, voice.volume_db])
	return result

func _test_cancellation_and_cleanup() -> void:
	_bank.play("buy", -26.0)
	_bank.play_cue("dash", -26.0, "dash")
	_bank.play_cue("pulse_hit", -26.0, "pulse")
	_bank.play_cue("evade", -26.0, "dash_evasion")
	_bank.play("hurt", -26.0)
	var buy: AudioStreamPlayer = _voice("buy")
	var dash: AudioStreamPlayer = _voice("dash")
	var pulse: AudioStreamPlayer = _voice("pulse_hit")
	var evade: AudioStreamPlayer = _voice("evade")
	var hurt: AudioStreamPlayer = _voice("hurt")
	_check(buy != null and dash != null and pulse != null and evade != null and hurt != null and buy.playing and dash.playing and pulse.playing and evade.playing and hurt.playing, "UI, activation, successful control, evasion and damage each dispatch to a real playing voice")
	var stamps: Dictionary = _bank.last_played.duplicate()
	_bank.cancel_cue("dash_evasion")
	_check(evade != null and evade.stream == null and not evade.playing, "Canceling the evasion tag actually stops and detaches its playing stream")
	_check(dash != null and pulse != null and hurt != null and buy != null and dash.playing and pulse.playing and hurt.playing and buy.playing and _bank.last_played == stamps, "Tag cancellation leaves other playing cues and their existing throttle records intact")
	var before: Array = _snapshot()
	_bank.cancel_cue("")
	_check(_snapshot() == before, "An empty cancellation tag cannot stop unrelated ordinary sounds")
	var ambience: AudioStream = _bank.ambience.stream if is_instance_valid(_bank.ambience) else null
	_bank.stop_combat_cues()
	_check(dash != null and pulse != null and hurt != null and dash.stream == null and pulse.stream == null and hurt.stream == null and not dash.playing and not pulse.playing and not hurt.playing, "Combat cleanup stops all real positive-priority streams")
	_check(buy != null and buy.stream == _bank.streams["buy"] and buy.playing and _bank.voices.size() == 12, "Combat cleanup preserves the ordinary UI sound and fixed voice-node budget")
	if not _headless:
		_check(_bank.ambience.stream == ambience and _bank.ambience.playing, "Combat cleanup preserves the independently playing native ambience")

func _test_simultaneous_and_flood() -> void:
	_reset()
	var ids: Array = _bank.voices.map(func(voice: AudioStreamPlayer) -> int: return voice.get_instance_id())
	_bank.play("rune", -26.0)
	_bank.play_cue("dash", -26.0, "dash")
	_bank.play_cue("pulse", -26.0, "pulse")
	_bank.play_cue("evade", -26.0, "dash_evasion")
	var critical: Array[AudioStreamPlayer] = []
	for name: String in ["dash", "pulse", "evade"]:
		var voice: AudioStreamPlayer = _voice(name)
		_check(voice != null and voice.playing and voice.stream == _bank.streams[name], "A same-tick skill keeps its own real playing resource after ordinary rune audio: " + name)
		if voice != null:
			critical.append(voice)
	_check(critical.size() == 3 and critical[0] != critical[1] and critical[1] != critical[2] and critical[0] != critical[2], "Dash, Q and confirmed evasion cannot throttle or overwrite one another on the same tick")
	var streams: Array = critical.map(func(voice: AudioStreamPlayer) -> AudioStream: return voice.stream)
	var positions: Array[float] = []
	for voice: AudioStreamPlayer in critical:
		positions.append(voice.get_playback_position())
	var stamp: Variant = _bank.last_played.get("cue:dash:dash")
	var before: Array = _snapshot()
	_bank.play_cue("dash", -5.0, "dash")
	_check(_bank.last_played.get("cue:dash:dash") == stamp and _snapshot() == before, "A same-tag duplicate cannot restart or amplify the active cue inside its own throttle interval")
	for request: int in 96:
		_bank.play_cue(["shoot", "hit", "death"][request % 3], -30.0, "ordinary_flood_%d" % request)
	_check(critical.size() == 3 and critical.map(func(voice: AudioStreamPlayer) -> AudioStream: return voice.stream) == streams and critical.all(func(voice: AudioStreamPlayer) -> bool: return voice.playing), "An ordinary ninety-six-request flood cannot overwrite or stop the three protected playing skills")
	await create_timer(0.045, true).timeout
	_check(critical.size() == 3 and critical.map(func(voice: AudioStreamPlayer) -> AudioStream: return voice.stream) == streams and critical.all(func(voice: AudioStreamPlayer) -> bool: return voice.playing), "Protected streams remain genuinely playing while audio time advances after the flood")
	if not _headless:
		for index: int in critical.size():
			_check(critical[index].get_playback_position() > positions[index] and critical[index].get_playback_position() > 0.0, "Native protected player playback actually advances rather than only holding a stream property")
	_check(_bank.voices.size() == 12 and ids == _bank.voices.map(func(voice: AudioStreamPlayer) -> int: return voice.get_instance_id()), "Flooding reuses exactly the original twelve real players")

func _test_full_protection_and_priority() -> void:
	_reset()
	_bank.play_cue("pulse_hit", -30.0, "oldest_skill")
	var oldest: AudioStreamPlayer = _voice("pulse_hit")
	await create_timer(0.012, true).timeout
	for index: int in 11:
		_bank.play_cue("pulse_hit", -30.0, "protected_%d" % index)
	var original: Array = _snapshot()
	_check(_bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return voice.stream == _bank.streams["pulse_hit"] and voice.playing), "Twelve accepted skill cues fill and genuinely play the entire protected voice pool")
	_bank.play_cue("hit", -26.0, "blocked_ordinary")
	_bank.play_cue("pulse", -26.0, "blocked_equal")
	_check(_snapshot() == original and not _bank.last_played.has("cue:blocked_ordinary:hit") and not _bank.last_played.has("cue:blocked_equal:pulse"), "Ordinary and equal-priority overflow is dropped without voice changes, stamps or a hidden replay queue")
	_bank.play_cue("evade", -26.0, "priority_upgrade")
	_check(oldest != null and oldest.stream == _bank.streams["evade"] and oldest.playing, "A higher-priority evasion replaces the oldest real lowest-priority skill voice")
	_bank.play("hurt", -26.0)
	var hurt: AudioStreamPlayer = _voice("hurt")
	_check(hurt != null and hurt != oldest and hurt.playing and oldest.stream == _bank.streams["evade"] and oldest.playing, "Actual hurt audio takes a lower-priority voice without erasing the still-protected evasion cue")
	await create_timer(0.48, true).timeout
	_check(_bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return not voice.playing) and not _bank.last_played.has("cue:blocked_ordinary:hit") and not _bank.last_played.has("cue:blocked_equal:pulse"), "Expired tails finish naturally and dropped overflow does not reappear later")
	_bank.play_cue("hit", -26.0, "blocked_ordinary")
	_check(_voice("hit") != null and _voice("hit").playing and _bank.last_played.has("cue:blocked_ordinary:hit"), "A fresh deliberate request can use a released voice after all protection expires")

func _test_pause_tail() -> void:
	_reset()
	_bank.play_cue("pulse_hit", -26.0, "pulse")
	var voice: AudioStreamPlayer = _voice("pulse_hit")
	var stamps: Dictionary = _bank.last_played.duplicate()
	_check(voice != null and voice.playing, "The pause fixture starts a real skill tail first")
	paused = true
	await create_timer(0.50, true).timeout
	_check(voice != null and not voice.playing and _bank.last_played == stamps, "As under Main's always-processing audio parent, a short tail expires on wall time while combat is paused")
	paused = false
	await create_timer(0.045, true).timeout
	_check(voice != null and not voice.playing and _bank.last_played == stamps, "Resuming cannot replay an already expired skill tail")

func _test_real_tail_beyond_wall_deadline() -> void:
	_reset()
	_check(_bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return is_equal_approx(voice.pitch_scale, 1.0)), "The delayed-tail fixture starts with ordinary production pitch on every player")
	var slow: AudioStreamPlayer = _bank.voices[0]
	var normal_pitch: float = slow.pitch_scale
	slow.pitch_scale = 0.5
	var started: int = Time.get_ticks_msec()
	_bank.play_cue("pulse_hit", -30.0, "slow_real_tail")
	var stream: AudioStream = _bank.streams["pulse_hit"]
	_check(slow.stream == stream and slow.playing, "Only this independent test voice plays the real control-hit WAV at half pitch")
	await create_timer(stream.get_length() + 0.08, true).timeout
	_check(Time.get_ticks_msec() - started > ceili(stream.get_length() * 1000.0) and slow.stream == stream and slow.playing, "The actual half-speed stream remains playing beyond its original dispatch duration without editing a protection deadline")
	var position: float = slow.get_playback_position()
	for request: int in 96:
		_bank.play_cue("hit", -30.0, "late_tail_flood_%d" % request)
	_check(slow.stream == stream and slow.playing, "Ordinary flooding cannot crop the genuinely playing tail after its wall-clock protection deadline")
	await create_timer(0.045, true).timeout
	if not _headless:
		_check(slow.stream == stream and slow.playing and slow.get_playback_position() > position, "Native playback continues to advance through the late tail after the flood")
	await create_timer(stream.get_length() * 2.0 + 0.12, true).timeout
	_check(not slow.playing, "The extended real stream eventually finishes naturally without cancellation or metadata changes")
	slow.pitch_scale = normal_pitch
	for request: int in 24:
		_bank.play_cue("hit", -30.0, "released_tail_flood_%d" % request)
	_check(slow.stream == _bank.streams["hit"] and slow.playing and _bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return is_equal_approx(voice.pitch_scale, 1.0)), "After natural completion the same actual player is reusable and every fixture pitch is restored")

func _test_mute_no_queue() -> void:
	_reset()
	_bank.set_volume(0.0)
	var before: Array = _snapshot()
	var stamps: Dictionary = _bank.last_played.duplicate()
	for name: String in ["dash", "pulse", "pulse_hit", "evade", "hurt", "buy"]:
		_bank.play_cue(name, -26.0, "muted_" + name)
	_check(AudioServer.is_bus_mute(0) and _snapshot() == before and _bank.last_played == stamps and _bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return not voice.playing), "Master mute drops real sound requests without allocation, stamps or playback")
	_bank.set_volume(0.25)
	await create_timer(0.06, true).timeout
	_check(_snapshot() == before and _bank.last_played == stamps and _bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return not voice.playing), "Unmuting cannot drain a nonexistent queued cue backlog")
	_bank.play_cue("dash", -26.0, "muted_dash")
	_check(_voice("dash") != null and _voice("dash").playing and _bank.last_played.has("cue:muted_dash:dash"), "Only a new unmuted deliberate request starts the actual dash WAV")
