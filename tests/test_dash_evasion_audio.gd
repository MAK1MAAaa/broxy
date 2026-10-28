extends SceneTree
## Real SoundBank scheduling checks pool allocation, not audible hardware output.

const EVASION_KEY: String = "cue:dash_evasion:rune"
var _checks: int = 0
var _failures: int = 0
var _bank: SoundBank
var _native_loaded_voices: bool = false
var _headless_injected_fixture: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_bank = SoundBank.new()
	root.add_child(_bank)
	if _prepare_voices():
		_test_activation_and_cue()
		_test_source_throttling()
		_test_invalid_requests()
		_test_voice_budget()
		_test_shutdown()
	_bank.queue_free()
	for frame: int in 2:
		await process_frame
	# Playback stops are consumed by the audio thread after scene-node deletion.
	await create_timer(0.10, true).timeout
	print("DashEvasionAudio: %d assertions, %d failures; native loaded voices=%s; headless injected fixture=%s; scheduling only" % [_checks, _failures, _native_loaded_voices, _headless_injected_fixture])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _prepare_voices() -> bool:
	var headless: bool = DisplayServer.get_name() == "headless"
	if headless:
		_check(_bank.voices.is_empty() and _bank.streams.is_empty(), "The production headless ready path never silently enables audio")
		for sound: String in SoundBank.NAMES:
			_bank.streams[sound] = load("res://assets/audio/%s.wav" % sound)
		for index: int in 12:
			var voice := AudioStreamPlayer.new()
			voice.bus = "Master"
			_bank.add_child(voice)
			_bank.voices.append(voice)
		_headless_injected_fixture = true
	else:
		_native_loaded_voices = _bank.voices.size() == 12 and _bank.streams.has("rune")
		_check(_native_loaded_voices, "Native SoundBank ready loads its actual twelve voices and rune resource")
	var resources_valid: bool = true
	for sound: String in SoundBank.NAMES:
		resources_valid = resources_valid and _bank.streams.get(sound) is AudioStreamWAV
	_check(resources_valid, "The scheduling fixture uses the existing real WAV resources")
	_check(_bank.voices.size() == 12 and _bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return voice.is_inside_tree() and voice.bus == "Master"), "Every scheduling voice belongs to the existing twelve-slot Master pool")
	return resources_valid and _bank.voices.size() == 12

func _busy(key: String) -> int:
	var stamp: int = Time.get_ticks_msec() + 60000
	_bank.last_played[key] = stamp
	return stamp

func _test_activation_and_cue() -> void:
	var rune: AudioStream = _bank.streams["rune"]
	_bank.play("rune", -20.0)
	_check(_bank.cursor == 1 and _bank.voices[0].stream == rune and is_equal_approx(_bank.voices[0].volume_db, -20.0), "Ordinary activation dispatches rune to the first real voice at its requested level")
	_check(_bank.last_played.has("rune") and not _bank.last_played.has(EVASION_KEY), "The original play API retains last_played indexed directly by sound")
	var ordinary_stamp: int = _busy("rune")
	_bank.play_cue("rune", -22.0, "dash_evasion")
	_check(_bank.cursor == 2 and _bank.voices[1].stream == rune and is_equal_approx(_bank.voices[1].volume_db, -22.0), "A confirmation immediately after activation still allocates its own real rune voice")
	_check(_bank.last_played["rune"] == ordinary_stamp and _bank.last_played.has(EVASION_KEY), "Confirmation records an independent cue key without changing ordinary rune throttling")
	var cue_stamp: int = _busy(EVASION_KEY)
	var before: Dictionary = _bank.last_played.duplicate()
	_bank.play_cue("rune", -2.0, "dash_evasion")
	_check(_bank.cursor == 2 and _bank.last_played == before and is_equal_approx(_bank.voices[1].volume_db, -22.0), "Repeated same-cue requests are throttled without advancing or changing a voice")
	_bank.play("rune", -2.0)
	_check(_bank.cursor == 2 and _bank.last_played == before, "Independent cue acceptance does not bypass a busy ordinary sound key")
	_bank.last_played.erase("rune")
	_bank.play("rune", -16.0)
	_check(_bank.cursor == 3 and _bank.voices[2].stream == rune and is_equal_approx(_bank.voices[2].volume_db, -16.0) and _bank.last_played[EVASION_KEY] == cue_stamp, "An available ordinary sound stays independent of a busy confirmation cue")
	_busy("rune")
	_bank.play_cue("rune", -18.0, "another_cue")
	_check(_bank.cursor == 4 and _bank.voices[3].stream == rune and is_equal_approx(_bank.voices[3].volume_db, -18.0) and _bank.last_played[EVASION_KEY] == cue_stamp, "A different cue using the same sound has its own throttle while sharing the voice pool")
	_bank.play_cue("hurt", -12.0, "dash_evasion")
	_check(_bank.cursor == 5 and _bank.voices[4].stream == _bank.streams["hurt"] and _bank.last_played.has("cue:dash_evasion:hurt"), "One cue namespace keeps different source sounds independently throttled")

func _test_source_throttling() -> void:
	for sound: String in ["rune", "hurt", "shoot", "hit", "death"]:
		var cue_id: String = "interval_" + sound
		var key: String = "cue:%s:%s" % [cue_id, sound]
		var before: int = _bank.cursor
		var cue_stamp: int = _busy(key)
		_bank.play_cue(sound, -22.0, cue_id)
		_check(_bank.cursor == before and _bank.last_played[key] == cue_stamp, "A busy cue rejects the request without changing its source sound's throttle: " + sound)
		_bank.last_played.erase(key)
		_bank.play_cue(sound, -22.0, cue_id)
		_check(_bank.cursor == (before + 1) % 12 and _bank.voices[before].stream == _bank.streams[sound], "An available cue dispatches its existing source resource through the shared pool: " + sound)
		before = _bank.cursor
		var ordinary_stamp: int = _busy(sound)
		_bank.play(sound)
		_check(_bank.cursor == before and _bank.last_played[sound] == ordinary_stamp, "The original ordinary sound key still rejects a deterministically busy timestamp: " + sound)
		_bank.last_played.erase(sound)
		_bank.play(sound)
		_check(_bank.cursor == (before + 1) % 12 and is_equal_approx(_bank.voices[before].volume_db, -10.0), "An available ordinary sound retains the original default loudness API: " + sound)

func _test_invalid_requests() -> void:
	var before: int = _bank.cursor
	var stamps: Dictionary = _bank.last_played.duplicate()
	var child_count: int = _bank.get_child_count()
	_bank.play("unknown")
	_bank.play_cue("unknown", -22.0, "dash_evasion")
	_check(_bank.cursor == before and _bank.last_played == stamps and _bank.get_child_count() == child_count, "Unknown sounds do not consume a voice, add a node or create a throttle key")
	var empty := SoundBank.new()
	empty.streams["rune"] = _bank.streams["rune"]
	empty.play("rune")
	empty.play_cue("rune", -22.0, "dash_evasion")
	_check(empty.cursor == 0 and empty.voices.is_empty() and empty.last_played.is_empty() and empty.get_child_count() == 0, "Known sounds without an allocated voice pool are safe no-ops for both APIs")
	empty.free()

func _test_voice_budget() -> void:
	var ids: Array = _bank.voices.map(func(voice: AudioStreamPlayer) -> int: return voice.get_instance_id())
	var before: int = _bank.cursor
	var child_count: int = _bank.get_child_count()
	for index: int in 12:
		_bank.play_cue("rune", -22.0, "budget_%d" % index)
	_check(_bank.cursor == before and _bank.voices.size() == 12 and _bank.get_child_count() == child_count, "Twelve independent cues wrap the existing pool without allocating extra audio players")
	_check(ids == _bank.voices.map(func(voice: AudioStreamPlayer) -> int: return voice.get_instance_id()) and _bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return voice.stream == _bank.streams["rune"] and is_equal_approx(voice.volume_db, -22.0)), "Cue allocation reuses each original real voice with the expected resource and level")
	_bank.play_cue("rune", -24.0, "budget_wrap")
	_check(_bank.cursor == (before + 1) % 12 and is_equal_approx(_bank.voices[before].volume_db, -24.0) and _bank.voices.size() == 12, "The next cue uses ordinary round-robin replacement within the same twelve-voice budget")

func _test_shutdown() -> void:
	_bank.shutdown()
	_check(_bank.streams.is_empty() and _bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return voice.stream == null and not voice.playing), "Shutdown stops every scheduled voice and releases its stream")
	_check(not is_instance_valid(_bank.ambience) or (_bank.ambience.stream == null and not _bank.ambience.playing), "Native ambience is also stopped and detached during shutdown")
	var before: int = _bank.cursor
	var stamps: Dictionary = _bank.last_played.duplicate()
	_bank.play("rune")
	_bank.play_cue("rune", -22.0, "after_shutdown")
	_check(_bank.cursor == before and _bank.last_played == stamps and _bank.voices.size() == 12, "Post-shutdown requests neither restart audio nor allocate replacement voices")
