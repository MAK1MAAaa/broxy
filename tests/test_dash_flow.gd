extends SceneTree
## Real Main input and modal transitions consume each dash edge once without profile writes.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0
var _app: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _key(code: Key, echo: bool = false, control: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	event.ctrl_pressed = control
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	root.push_input(event)
	await _settle()

func _start() -> CombatSim:
	_app._begin_run("bone", 20261028)
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var focus: Control = root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	return sim

func _tick(frames: int = 1) -> void:
	for frame: int in frames:
		_app.world._physics_process(STEP)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	await _settle()
	var sim: CombatSim = _start()
	var origin: Vector2 = sim.player_position
	await _key(KEY_SPACE)
	_check(sim.dashes_used == 0, "Space queues a request until a real physics step")
	_tick()
	_check(sim.dashes_used == 1 and sim.player_position.x > origin.x, "Main Space reaches World and the shipped fixed-step dash")
	_check(_app.world.hud_snapshot()["dash"]["active"], "The real HUD snapshot reports the active skill")
	await _key(KEY_SPACE)
	_tick(150)
	_check(sim.dashes_used == 1 and sim.dash_snapshot()["ready"], "A press during cooldown is dropped instead of firing after it expires")
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, false, true)
	_tick()
	_check(sim.dashes_used == 1, "Repeat and modified Space events do not trigger a new dash")
	await _key(KEY_SPACE)
	_app._pause()
	_check(_app.paused and paused, "Manual pause still uses the real SceneTree pause")
	_app.world.set_physics_process(true)
	var frozen: Dictionary = sim.dash_snapshot()
	await _settle()
	_check(sim.dash_snapshot() == frozen, "Skill timers and uses freeze while the tree is paused")
	_app.world.set_physics_process(false)
	_app._resume()
	_tick()
	_check(sim.dashes_used == 1, "A queued request cleared by pause cannot fire on resume")
	_app._pause()
	_app.ui._show_settings(true)
	await _settle()
	await _key(KEY_SPACE)
	_check(sim.dashes_used == 1, "Space in paused settings cannot activate the combat skill")
	_app._resume()
	_tick()
	_check(sim.dashes_used == 1, "Closing settings does not leave a buffered skill request")
	await _key(KEY_SPACE)
	_app.args = PackedStringArray()
	_app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(_app.paused and paused, "Normal focus loss pauses before an unconsumed request can run")
	_app.args = PackedStringArray(["--autoplay"])
	_app._resume()
	_tick()
	_check(sim.dashes_used == 1, "Restoring window focus does not produce a ghost dash")
	await _key(KEY_SPACE)
	_app.run.collect_souls(_app.run.xp_to_next_level() - _app.run.xp)
	await _settle()
	_check(_app.screen == MAIN_SCRIPT.Screen.UPGRADE and paused, "A real experience threshold still opens the live upgrade screen")
	await _key(KEY_SPACE)
	await _settle()
	if _app.run.pending_upgrades > 0:
		_app.run.choose_upgrade(str(_app.run.upgrade_choices()[0]["id"]))
		_app._upgrades_finished()
	await _settle()
	_check(_app.screen == MAIN_SCRIPT.Screen.COMBAT and not paused, "Upgrade keyboard selection returns to the same live battle")
	_tick()
	_check(sim.dashes_used == 1, "Upgrade entry and UI Space do not carry a request into resumed combat")
	_app._benchmark = true
	await _key(KEY_SPACE)
	_app._benchmark = false
	_tick()
	_check(sim.dashes_used == 1, "Benchmark input cannot change the measured skill state")
	await _key(KEY_SPACE)
	_app._title()
	_check(not _app.world.active, "Returning to title stops the skill-bearing world")
	sim = _start()
	_tick()
	_check(sim.dashes_used == 0 and sim.dash_snapshot()["ready"], "A new run resets skill state without consuming old title input")
	sim._finish(false, "dash flow fixture")
	await _settle()
	await _key(KEY_SPACE)
	_check(sim.dashes_used == 0, "Terminal and result screens do not dispatch the old battle's dash")
	_app._title()
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile), "Dash input and modal fixtures never modify the personal profile")
	print("DashFlow: %d assertions, %d failures" % [_checks, _failures])
	_app._quit_game(0 if _failures == 0 else 1)
