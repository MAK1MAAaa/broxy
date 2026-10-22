class_name GameStore
extends RefCounted

const PATH: String = "user://profile.cfg"
var settings: Dictionary = {"volume": 0.65, "shake": true, "flash": true}
var best: Dictionary = {"wave": 0, "kills": 0, "wins": 0, "runs": 0}
var persistent: bool = true
var _profile_path: String

func _init(profile_path: String = PATH) -> void:
	_profile_path = profile_path

func load_profile() -> void:
	if not persistent:
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(_profile_path) != OK:
		return
	settings["volume"] = clampf(float(config.get_value("settings", "volume", 0.65)), 0.0, 1.0)
	settings["shake"] = bool(config.get_value("settings", "shake", true))
	settings["flash"] = bool(config.get_value("settings", "flash", true))
	for key: String in best:
		best[key] = maxi(0, int(config.get_value("best", key, 0)))

func save_profile() -> Error:
	if not persistent:
		return OK
	var config: ConfigFile = ConfigFile.new()
	for key: String in settings:
		config.set_value("settings", key, settings[key])
	for key: String in best:
		config.set_value("best", key, best[key])
	return config.save(_profile_path)

func record_run(run: RunState, victory: bool) -> void:
	best["wave"] = maxi(int(best["wave"]), run.wave)
	best["kills"] = maxi(int(best["kills"]), run.kills)
	best["runs"] = int(best["runs"]) + 1
	if victory:
		best["wins"] = int(best["wins"]) + 1
	save_profile()
