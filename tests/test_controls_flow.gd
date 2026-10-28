extends SceneTree
## Parsed keyboard and joypad events reach the shipped Main, World and fixed-step skills.

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

func _key_state(code: Key, down: bool, echo: bool = false, control: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.echo = echo
	event.ctrl_pressed = control
	Input.parse_input_event(event)
	await process_frame

func _key(code: Key, echo: bool = false, control: bool = false) -> void:
	await _key_state(code, true, echo, control)
	await _key_state(code, false)

func _button_state(button: JoyButton, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame

func _button(button: JoyButton) -> void:
	await _button_state(button, true)
	await _button_state(button, false)

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await process_frame

func _start() -> CombatSim:
	_app._begin_run("bone", 20261028)
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var focused: Control = root.gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	return sim

func _tick(frames: int = 1) -> void:
	for frame: int in frames:
		_app.world._physics_process(STEP)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var original: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	ControlBindings.install(ControlBindings.defaults())
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	await _settle()
	await _test_rebinding()
	await _test_movement()
	await _test_light_stick_dash()
	await _test_gamepad_skills()
	await _test_pause_and_disconnect()
	await _test_screen_isolation()
	await _axis(JOY_AXIS_LEFT_X, 0.0)
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	_app._title()
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == original), "Real input integration never reads or rewrites the player's profile in the nonpersistent fixture")
	ControlBindings.install(ControlBindings.defaults())
	print("ControlsFlow: %d assertions, %d failures" % [_checks, _failures])
	_app._quit_game(0 if _failures == 0 else 1)

func _test_rebinding() -> void:
	var sim: CombatSim = _start()
	await _key(KEY_SPACE)
	_check(sim.dashes_used == 0 and _app.world._dash_pending, "Parsed default Space queues exactly one real World request before a physics step")
	_tick()
	_check(sim.dashes_used == 1 and sim.dash_time_left > 0.0, "The default binding still reaches the original fixed-step dash")
	var bindings: Dictionary = ControlBindings.defaults()
	bindings["move_up"] = KEY_I
	bindings["dash"] = KEY_E
	bindings["pulse"] = KEY_F
	_app.ui.controls_changed.emit(bindings)
	_check(_app.store.controls == ControlBindings.normalize(bindings) and not _app.world._dash_pending and not _app.world._pulse_pending, "The real controls signal installs and stores normalized bindings while clearing pending actions")
	sim = _start()
	await _key(KEY_SPACE)
	await _key(KEY_Q)
	_tick()
	_check(sim.dashes_used == 0 and sim.pulses_used == 0, "Old keyboard skill keys no longer trigger after their bindings change")
	await _key(KEY_E)
	await _key(KEY_F)
	_check(sim.dashes_used == 0 and sim.pulses_used == 0 and _app.world._dash_pending and _app.world._pulse_pending, "Both new keyboard bindings queue once without advancing the simulation")
	_tick()
	_check(sim.dashes_used == 1 and sim.pulses_used == 1, "Rebound inputs reach both shipped skills through the same Main and World gates")
	_tick(10)
	_check(sim.dashes_used == 1 and sim.pulses_used == 1, "Holding no new event cannot automatically repeat either skill")
	sim = _start()
	await _key(KEY_E, true)
	await _key(KEY_E, false, true)
	await _key(KEY_F, false, true)
	_tick()
	_check(sim.dashes_used == 0 and sim.pulses_used == 0, "Keyboard echo and Ctrl shortcuts cannot become rebound combat skills")
	await _key(KEY_E)
	_app.ui.controls_changed.emit(ControlBindings.defaults())
	_tick()
	_check(sim.dashes_used == 0 and not _app.world._dash_pending, "Changing bindings cancels an already queued old-map request")
	_app.ui.controls_changed.emit(bindings)

func _test_movement() -> void:
	_start()
	await _key_state(KEY_W, true)
	_check(_app.world._movement() == Vector2.ZERO, "The old primary movement key becomes inactive after rebinding")
	await _key_state(KEY_W, false)
	await _key_state(KEY_I, true)
	_check(_app.world._movement().is_equal_approx(Vector2.UP), "Parsed rebound physical movement drives the real World movement vector")
	await _key_state(KEY_D, true)
	_check(is_equal_approx(_app.world._movement().length(), 1.0) and _app.world._movement().x > 0.0 and _app.world._movement().y < 0.0, "Keyboard diagonal movement retains normalized speed")
	await _key_state(KEY_I, false)
	await _key_state(KEY_D, false)
	await _key_state(KEY_UP, true)
	_check(_app.world._movement().is_equal_approx(Vector2.UP), "Fixed arrow-key movement remains available beside the new primary bindings")
	await _key_state(KEY_UP, false)
	await _axis(JOY_AXIS_LEFT_X, 0.1)
	await _axis(JOY_AXIS_LEFT_Y, -0.1)
	_check(_app.world._movement() == Vector2.ZERO, "Parsed left-stick drift inside the circular deadzone cannot move the player")
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	await _axis(JOY_AXIS_LEFT_X, 0.6)
	var partial: Vector2 = _app.world._movement()
	_check(partial.x > 0.0 and partial.x < 1.0 and partial.y == 0.0, "A partial left-stick tilt preserves analog movement strength")
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	await _axis(JOY_AXIS_LEFT_Y, 1.0)
	_check(is_equal_approx(_app.world._movement().length(), 1.0) and _app.world._movement().x > 0.0 and _app.world._movement().y > 0.0, "Full diagonal stick movement is limited to the ordinary maximum speed")
	await _axis(JOY_AXIS_LEFT_X, 0.0)
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	await _button_state(JOY_BUTTON_DPAD_LEFT, true)
	_check(_app.world._movement().is_equal_approx(Vector2.LEFT), "The parsed joypad directional pad also drives the real World vector")
	await _button_state(JOY_BUTTON_DPAD_LEFT, false)
	_check(_app.world._movement() == Vector2.ZERO, "Releasing the pad restores neutral movement without stale axis state")

func _test_gamepad_skills() -> void:
	var sim: CombatSim = _start()
	await _button(JOY_BUTTON_A)
	await _button(JOY_BUTTON_X)
	_check(_app.world._dash_pending and _app.world._pulse_pending and sim.dashes_used == 0 and sim.pulses_used == 0, "Parsed A and X queue the two real skills even after keyboard rebinding")
	_tick()
	_check(sim.dashes_used == 1 and sim.pulses_used == 1, "One fixed step consumes each gamepad skill once without keyboard callback duplication")
	await _button(JOY_BUTTON_A)
	await _button(JOY_BUTTON_X)
	_tick(500)
	_check(sim.dashes_used == 1 and sim.pulses_used == 1 and sim.dash_snapshot()["ready"] and sim.pulse_snapshot()["ready"], "Cooldown button presses are dropped and never replayed when readiness returns")
	await _button(JOY_BUTTON_A)
	await _button(JOY_BUTTON_X)
	_tick()
	_check(sim.dashes_used == 2 and sim.pulses_used == 2, "A fresh gamepad press works after the cooldown finishes")

func _test_light_stick_dash() -> void:
	for stick: Vector2 in [Vector2(0.0, -0.24), Vector2(0.17, -0.17)]:
		var sim: CombatSim = _start()
		await _axis(JOY_AXIS_LEFT_X, stick.x)
		await _axis(JOY_AXIS_LEFT_Y, stick.y)
		var movement: Vector2 = _app.world._movement()
		_check(movement.length() > 0.0 and movement.length() < 0.1, "A real light stick deflection survives the input deadzone below the former facing threshold")
		var origin: Vector2 = sim.player_position
		_tick()
		_check(sim.player_position.distance_to(origin + movement * sim.run.stat("move_speed") * STEP) < 0.003 and sim.player_direction.is_equal_approx(movement.normalized()), "The real World preserves light analog speed while facing its actual movement")
		origin = sim.player_position
		await _button(JOY_BUTTON_A)
		_tick()
		_check(sim.dashes_used == 1 and sim.dash_direction.is_equal_approx(movement.normalized()) and sim.player_position.distance_to(origin + movement.normalized() * 11.0) < 0.003, "A from the same parsed light stick input dashes along the current direction instead of the old rightward facing")
		await _axis(JOY_AXIS_LEFT_X, 0.0)
		await _axis(JOY_AXIS_LEFT_Y, 0.0)
	var neutral: CombatSim = _start()
	neutral.player_direction = Vector2.UP
	await _axis(JOY_AXIS_LEFT_X, 0.1)
	await _axis(JOY_AXIS_LEFT_Y, -0.1)
	await _button(JOY_BUTTON_A)
	_tick()
	_check(_app.world._movement() == Vector2.ZERO and neutral.dash_direction == Vector2.UP, "Actual stick drift inside the deadzone still produces a stationary dash along the previous facing")
	await _axis(JOY_AXIS_LEFT_X, 0.0)
	await _axis(JOY_AXIS_LEFT_Y, 0.0)

func _test_pause_and_disconnect() -> void:
	var sim: CombatSim = _start()
	await _button(JOY_BUTTON_A)
	await _button(JOY_BUTTON_START)
	_check(_app.paused and paused and not _app.world._dash_pending and sim.dashes_used == 0, "Start pauses the real tree and cancels the queued A request")
	await _button(JOY_BUTTON_X)
	_tick()
	_check(sim.pulses_used == 0 and not _app.world._pulse_pending, "A paused gamepad skill cannot leak into the fixed-step simulation")
	_app.ui._show_settings(true)
	await _settle()
	await _button(JOY_BUTTON_B)
	_check(_app.paused and paused and _app.ui._overlay_mode == "pause", "B returns from settings to the paused parent menu")
	await _button(JOY_BUTTON_B)
	_check(not _app.paused and not paused and _app.ui._overlay_mode.is_empty(), "A second B resumes from the parent pause menu")
	_tick()
	_check(sim.dashes_used == 0 and sim.pulses_used == 0, "Resuming cannot replay either earlier paused or canceled skill")
	await _button(JOY_BUTTON_START)
	await _button(JOY_BUTTON_START)
	_check(not _app.paused and not paused, "Two deliberate Start presses pause and resume through the ordinary state machine")
	await _button(JOY_BUTTON_A)
	Input.joy_connection_changed.emit(91, false)
	_check(_app.paused and paused and not _app.world._dash_pending and not _app.world._pulse_pending, "The actual connection-change signal pauses combat and clears pending actions for any disconnected device")
	Input.joy_connection_changed.emit(91, true)
	_check(_app.paused and paused, "Reconnecting a device never silently resumes the trial")
	await _button(JOY_BUTTON_B)
	_tick()
	_check(not _app.paused and sim.dashes_used == 0, "Deliberate resume after a disconnect keeps the canceled input discarded")
	var focus_elapsed: float = sim.elapsed
	_app.args = PackedStringArray()
	_app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(_app.paused and paused and sim.elapsed == focus_elapsed, "The existing ordinary focus-loss rule still pauses gamepad-driven combat")
	_app.args = PackedStringArray(["--autoplay"])
	await _button(JOY_BUTTON_B)

func _test_screen_isolation() -> void:
	var sim: CombatSim = _start()
	_app.run.health = 0.0
	await _button(JOY_BUTTON_X)
	await _key(KEY_E)
	_check(not _app.world._pulse_pending and not _app.world._dash_pending and sim.pulses_used == 0, "A dead player cannot queue either device's skills")
	sim = _start()
	_app.run.collect_souls(42)
	await _settle()
	_check(_app.screen == MAIN_SCRIPT.Screen.UPGRADE and paused, "Real experience reaches the existing paused in-combat upgrade page")
	await _button(JOY_BUTTON_X)
	_check(sim.pulses_used == 0 and not _app.world._pulse_pending, "An upgrade choice page cannot pass a gamepad combat action through to World")
	_app._title()
	await _button(JOY_BUTTON_X)
	await _button(JOY_BUTTON_B)
	_check(_app.screen == MAIN_SCRIPT.Screen.TITLE and not _app.paused and not paused and not _app.world.active, "Title inputs neither start combat skills nor create an invisible pause")
	sim = _start()
	_tick()
	_check(sim.dashes_used == 0 and sim.pulses_used == 0, "A fresh trial begins without queued actions from title or upgrade screens")
