extends SceneTree
## Real ConfigFile migration, isolated diagnostics and the actual Main start guard.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var directory: DirAccess = DirAccess.create_temp("broxy-rogue-progress", true)
	_check(directory != null, "A unique temporary profile directory is available")
	if directory == null:
		_finish()
		return
	var folder: String = directory.get_current_dir()
	directory = null
	var path: String = folder.path_join("profile.cfg")
	var store := GameStore.new(path)
	_check(store.unlocked_starters == ["bone", "ember"], "Fresh profiles expose only the two original starters")
	_check(not store.starter_unlocked("frost") and not store.starter_unlocked("scatter") and not store.starter_unlocked("missing"), "Locked and unknown starters are rejected")
	var run := RunState.new()
	run.begin(20261026, "bone")
	run.wave = 3
	store.record_run(run, false)
	_check(not store.starter_unlocked("frost"), "Dying during wave three does not count as completing it")
	run.wave = 4
	store.record_run(run, false)
	_check(store.starter_unlocked("frost") and store.last_unlocks == ["frost"], "Reaching wave four unlocks frost without changing run stats")
	run.altar_choice = "accepted"
	run.altar_wave = 3
	run.wave = 3
	run.record_hunter_defeat()
	store.record_run(run, false)
	_check(store.starter_unlocked("scatter") and store.last_unlocks == ["scatter"], "A formally recorded hunter kill earns the alternative scatter starter")
	store.record_run(run, false)
	_check(store.last_unlocks.is_empty(), "Recording another run does not re-announce previously earned starters")
	var loaded := GameStore.new(path)
	loaded.load_profile()
	_check(loaded.starter_unlocked("frost") and loaded.starter_unlocked("scatter"), "Both horizontal unlocks survive actual ConfigFile reload")
	_check(loaded.settings == store.settings and loaded.best == store.best, "Progress persistence preserves settings and best-record schema")
	var config := ConfigFile.new()
	config.set_value("best", "wave", 5)
	config.set_value("progress", "starters", ["bone", "missing", "scatter", "scatter"])
	_check(config.save(path) == OK, "A legacy profile fixture is saved")
	loaded = GameStore.new(path)
	loaded.load_profile()
	_check(loaded.unlocked_starters == ["bone", "ember", "scatter", "frost"], "Loading restores base starters, filters unknown/duplicate IDs, and migrates wave progress")
	config.set_value("progress", "starters", 42)
	_check(config.save(path) == OK, "A malformed optional progress field can be isolated")
	loaded = GameStore.new(path)
	loaded.load_profile()
	_check(loaded.unlocked_starters == ["bone", "ember", "frost"], "Malformed progress is ignored while legacy achievements remain usable")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var diagnostic := GameStore.new(path)
	diagnostic.persistent = false
	diagnostic.load_profile()
	_check(diagnostic.unlocked_starters == ["bone", "ember"], "Diagnostic stores do not import personal unlocks")
	diagnostic.record_run(run, false)
	_check(diagnostic.starter_unlocked("scatter") and FileAccess.get_file_as_bytes(path) == before, "Diagnostic unlocks stay in memory and leave the real profile bytes intact")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.store = GameStore.new(path)
	main.store.persistent = false
	root.add_child(main)
	main.set_process(false)
	main.world.set_physics_process(false)
	main._start_run("scatter")
	_check(main.screen == main.Screen.TITLE and main.run.wave == 1, "The actual Main refuses a locked start even when called directly")
	main.store.unlocked_starters.append("scatter")
	main._title()
	var card: Button = main.ui.find_child("Starter_scatter", true, false)
	_check(card != null and not card.disabled, "Main passes current unlocks into the actual title screen")
	main._start_run("scatter")
	_check(main.screen == main.Screen.COMBAT and main.run.loadout[0]["id"] == "scatter", "An unlocked Main start uses the selected alternative weapon")
	_check(main.run.stat("max_health") == 100.0 and main.run.stat("damage") == 1.0, "Unlocks add no permanent health or damage bonuses")
	await _test_main_choices(main)
	main.queue_free()
	for frame: int in 3:
		await process_frame
	_check(FileAccess.get_file_as_bytes(path) == before, "The actual nonpersistent Main session preserves profile bytes")
	_check(DirAccess.remove_absolute(path) == OK and DirAccess.remove_absolute(folder) == OK, "The temporary profile fixture is removed")
	_finish()

func _test_main_choices(main: Node) -> void:
	main.store.unlocked_starters.assign(["bone", "ember"])
	main._start_run("bone")
	await _finish_main_wave(main)
	_check(main.screen == main.Screen.SHOP and main.run.rogue_choices()["can_choose_core"], "Actual wave-end settlement opens a shop with a core available")
	await _press(main.ui, "OpenRogueChoices")
	await _press(main.ui, "RogueCore_bone_chorus")
	_check(main.run.core_id == "bone_chorus" and main.run.loadout.size() == 2, "The real core button commits its one-time kit through Main's shop")
	main.ui.handle_back()
	main._next_wave()
	_check(main.run.wave == 2 and main.world.sim.run.core_id == "bone_chorus", "The next real CombatSim receives the selected core")
	await _finish_main_wave(main)
	await _press(main.ui, "OpenRogueChoices")
	await _press(main.ui, "RogueAltarAccept")
	await _press(main.ui, "RogueRoute_swarm")
	main.ui.handle_back()
	main._next_wave()
	_check(main.run.wave == 3 and main.run.active_route == "swarm" and main.world.sim.hunter != null, "The actual next wave consumes the selected route and creates the contract hunter")
	var hunter: CombatSim.Enemy = main.world.sim.hunter
	main.world.sim.apply_damage(hunter, hunter.health, "bone")
	await _finish_main_wave(main)
	_check(main.run.hunter_defeated and main.run.rune_reward_pending, "A real hunter kill reaches wave-end reward settlement")
	await _press(main.ui, "OpenRogueChoices")
	await _press(main.ui, "RogueReward_blast")
	_check(not main.run.rune_reward_pending and main.run.rune_bag.size() == 1 and main.run.rune_bag[0]["id"] == "blast", "The actual reward button grants exactly the chosen rune")
	main.ui.handle_back()
	main._next_wave()
	main.run.health = 0.0
	main.world.sim.step(1.0 / 60.0, Vector2.ZERO)
	await _settle()
	_check(main.screen == main.Screen.RESULT and main.store.starter_unlocked("frost") and main.store.starter_unlocked("scatter"), "Actual terminal settlement unlocks the completed-wave and hunter challenges")

func _finish_main_wave(main: Node) -> void:
	# Advance only the timer boundary: this tests wiring, not ordinary-wave survival.
	main.world.sim.elapsed = main.world.sim.duration
	main.world.sim.step(1.0 / 60.0, Vector2.ZERO)
	await _settle()

func _press(ui: Node, name: String) -> void:
	var button: Button = ui.find_child(name, true, false) as Button
	_check(button != null and not button.disabled, "An enabled actual UI action exists: " + name)
	if button != null and not button.disabled:
		button.pressed.emit()
	await _settle()

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _finish() -> void:
	print("RogueProgress: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
