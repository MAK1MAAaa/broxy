class_name GameStore
extends RefCounted

const PATH: String = "user://profile.cfg"
const STARTERS: Array[String] = ["bone", "ember", "frost", "scatter"]
var settings: Dictionary = {"volume": 0.65, "shake": true, "flash": true}
var controls: Dictionary = ControlBindings.defaults()
var best: Dictionary = {"wave": 0, "kills": 0, "wins": 0, "runs": 0}
var unlocked_starters: Array[String] = ["bone", "ember"]
var last_unlocks: Array[String] = []
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
	settings = _normalize_settings({"volume": config.get_value("settings", "volume", 0.65), "shake": config.get_value("settings", "shake", true), "flash": config.get_value("settings", "flash", true)})
	var saved_controls: Dictionary = {}
	for action: String in ControlBindings.ACTIONS:
		if config.has_section_key("controls", action):
			saved_controls[action] = config.get_value("controls", action)
	controls = ControlBindings.normalize(saved_controls)
	for key: String in best:
		best[key] = maxi(0, int(config.get_value("best", key, 0)))
	var saved: Variant = config.get_value("progress", "starters", [])
	unlocked_starters = ["bone", "ember"]
	if saved is Array or saved is PackedStringArray:
		for id: String in STARTERS:
			if id in saved and id not in unlocked_starters:
				unlocked_starters.append(id)
	# Existing records earn the same horizontal unlock without a forced save.
	if int(best["wave"]) >= 4 and "frost" not in unlocked_starters:
		unlocked_starters.append("frost")

func starter_unlocked(id: String) -> bool:
	return id in STARTERS and id in unlocked_starters

func save_profile() -> Error:
	if not persistent:
		return OK
	settings = _normalize_settings(settings)
	controls = ControlBindings.normalize(controls)
	var config: ConfigFile = ConfigFile.new()
	for key: String in settings:
		config.set_value("settings", key, settings[key])
	for key: String in best:
		config.set_value("best", key, best[key])
	for action: String in ControlBindings.ACTIONS:
		config.set_value("controls", action, controls[action])
	var safe_starters: Array[String] = []
	for id: String in STARTERS:
		if starter_unlocked(id) or id in ["bone", "ember"]:
			safe_starters.append(id)
	config.set_value("progress", "starters", safe_starters)
	return config.save(_profile_path)

static func _normalize_settings(value: Dictionary) -> Dictionary:
	var volume: Variant = value.get("volume", 0.65)
	var safe_volume: float = 0.65
	if (volume is int or volume is float) and is_finite(float(volume)):
		safe_volume = clampf(float(volume), 0.0, 1.0)
	var shake: Variant = value.get("shake", true)
	var flash: Variant = value.get("flash", true)
	return {"volume": safe_volume, "shake": shake if shake is bool else true, "flash": flash if flash is bool else true}

func record_run(run: RunState, victory: bool) -> void:
	last_unlocks.clear()
	if run.wave >= 4:
		_unlock("frost")
	if run.hunter_defeated:
		_unlock("scatter")
	best["wave"] = maxi(int(best["wave"]), run.wave)
	best["kills"] = maxi(int(best["kills"]), run.kills)
	best["runs"] = int(best["runs"]) + 1
	if victory:
		best["wins"] = int(best["wins"]) + 1
	save_profile()

func _unlock(id: String) -> void:
	if id in STARTERS and id not in unlocked_starters:
		unlocked_starters.append(id)
		last_unlocks.append(id)
