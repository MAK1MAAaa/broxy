extends SceneTree
## Q shares the real Main modal/input lifecycle while both skills stay independent.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0
var _app: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
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
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", sim.player_position + Vector2(60, 0))
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	var before: Vector2 = enemy.position
	await _key(KEY_Q)
	_check(sim.pulses_used == 0, "Q queues its edge instead of running simulation in input dispatch")
	_tick()
	_check(sim.pulses_used == 1 and enemy.position.distance_to(before) > 69.0 and enemy.pulse_hinder_timer > 0.0, "Real Main Q reaches actual enemy control through the World fixed step")
	_check(_app.ui._hud["pulse"].visible and sim.last_pulse_affected == 1, "Main publishes the ready skill's accepted cast and actual affected count")
	await _key(KEY_Q)
	_tick(481)
	_check(sim.pulses_used == 1 and sim.pulse_snapshot()["ready"], "Cooldown input is discarded and never replayed at readiness")
	await _key(KEY_Q, true)
	await _key(KEY_Q, false, true)
	_tick()
	_check(sim.pulses_used == 1, "Repeated and modified Q cannot activate a fresh pulse")
	await _key(KEY_Q)
	await _key(KEY_SPACE)
	_app._pause()
	var frozen: Array = [sim.pulse_snapshot(), sim.dash_snapshot()]
	_app.world.set_physics_process(true)
	await _settle()
	_check(paused and frozen == [sim.pulse_snapshot(), sim.dash_snapshot()], "Real pause freezes both skill clocks")
	_app.world.set_physics_process(false)
	_app._resume()
	_tick()
	_check(sim.pulses_used == 1 and sim.dashes_used == 0, "Pause cancels both queued skills before resume")
	sim = _start()
	var origin: Vector2 = sim.player_position
	var casts: Array[Vector2] = []
	sim.pulse_cast.connect(func(point: Vector2, _affected: int) -> void: casts.append(point))
	await _key(KEY_Q)
	await _key(KEY_SPACE)
	_tick()
	_check(sim.pulses_used == 1 and sim.dashes_used == 1 and casts == [origin] and sim.player_position.x > origin.x, "Simultaneous edges cast at the step's starting position before dash movement")
	sim = _start()
	await _key(KEY_Q)
	_app.args = PackedStringArray()
	_app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(_app.paused and paused, "Normal focus loss pauses before pending Q is consumed")
	_app.args = PackedStringArray(["--autoplay"])
	_app._resume()
	_tick()
	_check(sim.pulses_used == 0, "Restoring focus cannot replay the old Q edge")
	await _key(KEY_Q)
	_app.run.collect_souls(_app.run.xp_to_next_level() - _app.run.xp)
	await _settle()
	_check(_app.screen == MAIN_SCRIPT.Screen.UPGRADE and paused, "A real experience threshold still pauses the same battle for upgrade selection")
	await _key(KEY_Q)
	_check(sim.pulses_used == 0, "Q on an upgrade screen cannot control the paused battle")
	_app.run.choose_upgrade(str(_app.run.upgrade_choices()[0]["id"]))
	_app._upgrades_finished()
	await _settle()
	_tick()
	_check(_app.screen == MAIN_SCRIPT.Screen.COMBAT and not paused and sim.pulses_used == 0, "Upgrade completion clears pending Q and resumes the same simulation")
	_app._pause()
	_app.ui._show_settings(true)
	await _key(KEY_Q)
	_app._resume()
	_tick()
	_check(sim.pulses_used == 0, "Settings input cannot become a deferred pulse")
	_app._benchmark = true
	await _key(KEY_Q)
	_app._benchmark = false
	_tick()
	_check(sim.pulses_used == 0, "Performance diagnostics ignore physical skill input")
	await _key(KEY_Q)
	_app._title()
	sim = _start()
	_tick()
	_check(sim.pulses_used == 0 and sim.pulse_snapshot()["ready"], "Title and new-run transitions discard old input and reset pulse readiness")
	sim._finish(false, "pulse flow terminal fixture")
	await _settle()
	await _key(KEY_Q)
	_check(sim.pulses_used == 0, "Terminal and result screens reject Q")
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile), "Pulse input fixtures preserve personal profile bytes")
	print("PulseFlow: %d assertions, %d failures" % [_checks, _failures])
	_app._quit_game(0 if _failures == 0 else 1)
