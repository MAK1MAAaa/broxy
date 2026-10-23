extends SceneTree
## Each CLI mode gets real ConfigFile IO in a unique temporary directory, never user://.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const DIAGNOSTIC_FLAGS: Array[String] = ["--smoke", "--autoplay", "--shop-preview", "--benchmark", "--capture-only"]
const SAVED_SETTINGS: Dictionary = {"volume": 0.35, "shake": false, "flash": false}
const SAVED_BEST: Dictionary = {"wave": 5, "kills": 731, "wins": 3, "runs": 9}
const DEFAULT_SETTINGS: Dictionary = {"volume": 0.65, "shake": true, "flash": true}
const DEFAULT_BEST: Dictionary = {"wave": 0, "kills": 0, "wins": 0, "runs": 0}

var _checks: int = 0
var _failures: int = 0
var _mode: String = "normal"


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	var selected: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument in DIAGNOSTIC_FLAGS:
			selected.append(argument)
	_check(selected.size() <= 1, "Run one production CLI mode per process")
	if not selected.is_empty():
		_mode = selected[0].trim_prefix("--")
	var diagnostic: bool = not selected.is_empty()
	var temporary: DirAccess = DirAccess.create_temp("broxy-profile-mode", true)
	_check(temporary != null, "The test creates a unique system temporary profile directory")
	if temporary == null:
		quit(1)
		return
	var directory: String = temporary.get_current_dir()
	temporary = null
	var path: String = directory.path_join("profile.cfg")
	var seed_profile := ConfigFile.new()
	for key: String in SAVED_SETTINGS:
		seed_profile.set_value("settings", key, SAVED_SETTINGS[key])
	for key: String in SAVED_BEST:
		seed_profile.set_value("best", key, SAVED_BEST[key])
	_check(seed_profile.save(path) == OK, "The test writes a distinguishable temporary profile")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	_check(not original.is_empty(), "The seeded profile has real file content before Main starts")
	var app = MAIN.instantiate()
	app.store = GameStore.new(path)
	root.add_child(app)
	# Stop both clocks before the first idle/physics frame: smoke capture and
	# benchmark reports must not run, and no combat completion is simulated here.
	app.set_process(false)
	app.world.set_physics_process(false)
	_check(app.args == OS.get_cmdline_user_args(), "The real Main receives this process's actual user arguments")
	if diagnostic:
		_check(not app.store.persistent, "Diagnostic mode disables persistence before profile loading")
		_check(app.store.settings == DEFAULT_SETTINGS, "Diagnostic mode never imports personal settings from the seeded file")
		_check(app.store.best == DEFAULT_BEST, "Diagnostic mode never imports personal best records from the seeded file")
		_check(root.title.contains("不保存设置与成绩"), "Every diagnostic window labels its nonpersistent settings and records")
	else:
		_check(app.store.persistent, "Ordinary Main keeps persistence enabled for its injected profile")
		_check(app.store.settings == SAVED_SETTINGS, "Ordinary Main loads stored settings")
		_check(app.store.best == SAVED_BEST, "Ordinary Main loads stored best records")
		_check(root.title == "秘术余烬", "An ordinary persistent session retains the normal game title")
	_check(FileAccess.get_file_as_bytes(path) == original, "Starting the selected mode does not rewrite its profile")
	app._setting_changed("volume", 0.8)
	app._setting_changed("shake", false)
	_check(is_equal_approx(float(app.store.settings["volume"]), 0.8) and not bool(app.store.settings["shake"]), "Settings still take effect in the current session")
	if diagnostic:
		_check(FileAccess.get_file_as_bytes(path) == original, "Diagnostic setting changes leave the existing profile byte-for-byte unchanged")
	else:
		var settings_after := ConfigFile.new()
		_check(settings_after.load(path) == OK, "Ordinary settings changes produce a readable profile")
		_check(is_equal_approx(float(settings_after.get_value("settings", "volume", -1.0)), 0.8) and not bool(settings_after.get_value("settings", "shake", true)), "Ordinary setting changes persist through the real Main save path")
	var result := RunState.new()
	result.begin(422, "bone")
	result.wave = 8
	result.kills = 1777
	app.store.record_run(result, true)
	_check(app.store.save_profile() == OK, "Explicit save requests remain safe in the selected mode")
	if diagnostic:
		_check(FileAccess.get_file_as_bytes(path) == original, "Diagnostic result recording and explicit saves never alter the seeded best records")
	else:
		var result_after := ConfigFile.new()
		_check(result_after.load(path) == OK, "Ordinary result recording leaves a readable profile")
		_check(int(result_after.get_value("best", "runs", -1)) == 10 and int(result_after.get_value("best", "wins", -1)) == 4, "Ordinary result recording persists exactly one run and win")
		_check(int(result_after.get_value("best", "wave", -1)) == 8 and int(result_after.get_value("best", "kills", -1)) == 1777, "Ordinary result recording updates the actual best wave and kill count")
		_check(is_equal_approx(float(result_after.get_value("settings", "volume", -1.0)), 0.8), "Recording a result preserves the saved settings")
		await _test_existing_nonpersistent_fixture(path, result)
	app.queue_free()
	for frame: int in 3:
		await process_frame
	_check(DirAccess.remove_absolute(path) == OK, "The temporary profile is removed after Main is freed")
	_check(DirAccess.remove_absolute(directory) == OK, "The test leaves no temporary profile directory")
	print("ProfileModes: %d assertions, %d failures; mode=%s" % [_checks, _failures, _mode])
	quit(0 if _failures == 0 else 1)


func _test_existing_nonpersistent_fixture(path: String, result: RunState) -> void:
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var fixture = MAIN.instantiate()
	fixture.store = GameStore.new(path)
	fixture.store.persistent = false
	root.add_child(fixture)
	fixture.set_process(false)
	fixture.world.set_physics_process(false)
	_check(not fixture.store.persistent, "Ordinary flags preserve a fixture's preconfigured nonpersistent store")
	_check(fixture.store.settings == DEFAULT_SETTINGS, "An explicitly nonpersistent ordinary fixture never loads stored settings")
	_check(fixture.store.best == DEFAULT_BEST, "An explicitly nonpersistent ordinary fixture never loads stored records")
	_check(root.title.contains("不保存设置与成绩"), "An explicitly nonpersistent ordinary fixture also labels its validation window")
	fixture._setting_changed("volume", 0.25)
	fixture.store.record_run(result, true)
	_check(FileAccess.get_file_as_bytes(path) == before, "Ordinary flags never re-enable writes for an explicitly nonpersistent fixture")
	fixture.queue_free()
	for frame: int in 3:
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
