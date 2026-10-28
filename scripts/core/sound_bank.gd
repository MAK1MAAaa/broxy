class_name SoundBank
extends Node

const NAMES: Array[String] = ["shoot", "hit", "hurt", "death", "buy", "rune", "level", "victory", "defeat", "dash", "pulse", "pulse_hit", "evade"]
const PRIORITIES: Dictionary = {"dash": 1, "pulse": 1, "pulse_hit": 1, "evade": 2, "hurt": 3}
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var cursor: int = 0
var last_played: Dictionary = {}
var ambience: AudioStreamPlayer
var voice_priorities: Array[int] = []
var voice_protected_until: Array[int] = []
var voice_tags: Array[String] = []
var voice_started_at: Array[int] = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for sound: String in NAMES:
		var path: String = "res://assets/audio/%s.wav" % sound
		if ResourceLoader.exists(path):
			streams[sound] = load(path)
	for index: int in 12:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.bus = "Master"
		add_child(voice)
		voices.append(voice)
	_ensure_voice_state()
	var ambient_path: String = "res://assets/audio/ambience.wav"
	if ResourceLoader.exists(ambient_path):
		ambience = AudioStreamPlayer.new()
		var loop: AudioStreamWAV = (load(ambient_path) as AudioStreamWAV).duplicate()
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_end = int(loop.get_length() * float(loop.mix_rate))
		ambience.stream = loop
		ambience.volume_db = -21.0
		add_child(ambience)
		ambience.play()

func shutdown() -> void:
	_ensure_voice_state()
	for index: int in voices.size():
		_stop_voice(index)
	if is_instance_valid(ambience):
		ambience.stop()
		ambience.stream = null
	streams.clear()
	last_played.clear()
	cursor = 0

func _exit_tree() -> void:
	shutdown()

func set_volume(value: float) -> void:
	if not is_finite(value):
		return
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, value)))
	AudioServer.set_bus_mute(0, value < 0.001)

func play(sound: String, loudness: float = -10.0) -> void:
	_play(sound, loudness, sound, "")

func play_cue(sound: String, loudness: float, cue_id: String) -> void:
	_play(sound, loudness, "cue:%s:%s" % [cue_id, sound], cue_id)

func cancel_cue(cue_id: String) -> void:
	if cue_id.is_empty():
		return
	_ensure_voice_state()
	for index: int in voices.size():
		if voice_tags[index] == cue_id:
			_stop_voice(index)

func stop_combat_cues() -> void:
	_ensure_voice_state()
	for index: int in voices.size():
		if voice_priorities[index] > 0:
			_stop_voice(index)

func _ensure_voice_state() -> void:
	voice_priorities.resize(voices.size())
	voice_protected_until.resize(voices.size())
	voice_tags.resize(voices.size())
	voice_started_at.resize(voices.size())

func _stop_voice(index: int) -> void:
	if is_instance_valid(voices[index]):
		voices[index].stop()
		voices[index].stream = null
	voice_priorities[index] = 0
	voice_protected_until[index] = 0
	voice_tags[index] = ""
	voice_started_at[index] = 0

func _available_voice(priority: int, now: int) -> int:
	var start: int = posmod(cursor, voices.size())
	for offset: int in voices.size():
		var index: int = (start + offset) % voices.size()
		if is_instance_valid(voices[index]) and not _voice_is_protected(index, now):
			return index
	var candidate: int = -1
	for offset: int in voices.size():
		var index: int = (start + offset) % voices.size()
		if not is_instance_valid(voices[index]) or priority <= voice_priorities[index]:
			continue
		if candidate < 0 or voice_priorities[index] < voice_priorities[candidate] or (voice_priorities[index] == voice_priorities[candidate] and voice_started_at[index] < voice_started_at[candidate]):
			candidate = index
	return candidate

func _voice_is_protected(index: int, now: int) -> bool:
	return voice_priorities[index] > 0 and (voice_protected_until[index] > now or voices[index].playing)

func _play(sound: String, loudness: float, throttle_key: String, cue_id: String) -> void:
	if voices.is_empty() or not is_finite(loudness) or AudioServer.is_bus_mute(0):
		return
	var stream: Variant = streams.get(sound)
	if not stream is AudioStream:
		return
	var now: int = Time.get_ticks_msec()
	var interval: int = 100 if sound == "shoot" or sound == "hit" or sound == "death" else 35
	if now - int(last_played.get(throttle_key, -1000)) < interval:
		return
	var priority: int = int(PRIORITIES.get(sound, 0))
	var protected_ms: int = 0
	if priority > 0:
		var duration_ms: float = stream.get_length() * 1000.0
		if not is_finite(duration_ms) or duration_ms <= 0.0:
			return
		protected_ms = maxi(1, ceili(duration_ms))
	_ensure_voice_state()
	var index: int = _available_voice(priority, now)
	if index < 0:
		return
	last_played[throttle_key] = now
	var voice: AudioStreamPlayer = voices[index]
	cursor = (index + 1) % voices.size()
	voice_priorities[index] = priority
	voice_protected_until[index] = now + protected_ms
	voice_tags[index] = cue_id
	voice_started_at[index] = now
	voice.stream = stream
	voice.volume_db = loudness
	voice.play()
