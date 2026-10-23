class_name SoundBank
extends Node

const NAMES: Array[String] = ["shoot", "hit", "hurt", "death", "buy", "rune", "level", "victory", "defeat"]
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var cursor: int = 0
var last_played: Dictionary = {}
var ambience: AudioStreamPlayer

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
	for voice: AudioStreamPlayer in voices:
		voice.stop()
		voice.stream = null
	if is_instance_valid(ambience):
		ambience.stop()
		ambience.stream = null
	streams.clear()

func _exit_tree() -> void:
	shutdown()

func set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, value)))
	AudioServer.set_bus_mute(0, value < 0.001)

func play(sound: String, loudness: float = -10.0) -> void:
	if not streams.has(sound) or voices.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var interval: int = 100 if sound == "shoot" or sound == "hit" or sound == "death" else 35
	if now - int(last_played.get(sound, -1000)) < interval:
		return
	last_played[sound] = now
	var voice: AudioStreamPlayer = voices[cursor]
	cursor = (cursor + 1) % voices.size()
	voice.stream = streams[sound]
	voice.volume_db = loudness
	voice.play()
