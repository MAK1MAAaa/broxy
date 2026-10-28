extends SceneTree
## Actual input propagation, per-device stick edges and connection signals drive hint selection only.

class InputProbe extends Node:
	var received: int = 0
	var unhandled: int = 0
	func _input(_event: InputEvent) -> void:
		received += 1
	func _unhandled_input(_event: InputEvent) -> void:
		unhandled += 1

var _checks: int = 0
var _failures: int = 0
var _tracker: InputDeviceTracker
var _probe: InputProbe
var _changes: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var personal_existed: bool = FileAccess.file_exists(GameStore.PATH)
	var personal_before: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if personal_existed else PackedByteArray()
	var map_before: Dictionary = _input_map_signature()
	_probe = InputProbe.new()
	_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_probe)
	_tracker = InputDeviceTracker.new()
	_tracker.device_changed.connect(func(device_kind: String, device: int) -> void: _changes.append({"kind": device_kind, "gamepad_id": device}))
	root.add_child(_tracker)
	_check(_tracker.snapshot() == {"kind": "keyboard", "gamepad_id": -1} and _tracker.process_mode == Node.PROCESS_MODE_ALWAYS, "A ready tracker starts with keyboard hints and observes input while paused")
	var detached: Dictionary = _tracker.snapshot()
	detached["kind"] = "corrupt"
	detached["gamepad_id"] = 77
	_check(_tracker.snapshot() == {"kind": "keyboard", "gamepad_id": -1} and _changes.is_empty(), "Snapshot mutation cannot change the tracker or emit device signals")
	await _test_buttons_and_keyboard()
	await _test_axis_edges()
	await _test_multiple_devices()
	await _test_pause_and_propagation()
	_check(_input_map_signature() == map_before, "Device observation does not add, erase or change any gameplay or menu input binding")
	_check(FileAccess.file_exists(GameStore.PATH) == personal_existed and (not personal_existed or FileAccess.get_file_as_bytes(GameStore.PATH) == personal_before), "Hint selection and connection events preserve the personal profile byte for byte")
	_tracker.queue_free()
	_probe.queue_free()
	await process_frame
	print("InputDevices: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _key(code: int, down: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	event.echo = echo
	return event

func _button(button: int, device: int = 0, down: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = down
	return event

func _axis(axis: int, value: float, device: int = 0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event

func _mouse(button: int, down: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	return event

func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _is_device(device_kind: String, device: int = -1) -> bool:
	return _tracker.kind == device_kind and _tracker.gamepad_id == device and _tracker.snapshot() == {"kind": device_kind, "gamepad_id": device}

func _test_buttons_and_keyboard() -> void:
	for button: int in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		_tracker.reset()
		var before: int = _changes.size()
		await _send(_button(button, 3))
		_check(_is_device("gamepad", 3) and _changes.size() == before + 1 and _changes.back() == {"kind": "gamepad", "gamepad_id": 3}, "A supported pressed gamepad button chooses its exact device and emits one change: " + str(button))
		await _send(_button(button, 3, false))
		_check(_is_device("gamepad", 3) and _changes.size() == before + 1, "A released button does not switch hints or repeat its signal")
	var before: int = _changes.size()
	await _send(_key(KEY_E, false))
	await _send(_key(KEY_E, true, true))
	for modifier: int in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		await _send(_key(modifier))
		await _send(_key(modifier, false))
	await _send(_key(KEY_NONE))
	await _send(InputEventMouseMotion.new())
	await _send(_mouse(MOUSE_BUTTON_LEFT, false))
	_check(_is_device("gamepad", 3) and _changes.size() == before, "Keyboard releases, echoes, pure modifiers, absent keys, mouse motion and mouse releases never steal gamepad hints")
	await _send(_key(KEY_E))
	_check(_is_device("keyboard") and _changes.size() == before + 1, "An intentional ordinary key press selects keyboard hints")
	await _send(_key(KEY_E, false))
	before = _changes.size()
	await _send(_key(KEY_ENTER))
	await _send(_key(KEY_ENTER, false))
	_check(_is_device("keyboard") and _changes.size() == before, "Further keyboard activity does not emit redundant device changes")
	var fallback := InputEventKey.new()
	fallback.keycode = KEY_Q
	fallback.pressed = true
	await _send(_button(JOY_BUTTON_X, 0))
	await _send(fallback)
	_check(_is_device("keyboard"), "A logical key fallback without a physical code is still real keyboard activity")
	fallback.pressed = false
	await _send(fallback)
	for button: int in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		await _send(_button(JOY_BUTTON_A, 0))
		await _send(_mouse(button))
		_check(_is_device("keyboard"), "A deliberate mouse press, including scrolling, selects keyboard-and-mouse hints: " + str(button))
		await _send(_mouse(button, false))
	_tracker.reset()
	for button: int in [JOY_BUTTON_BACK, JOY_BUTTON_GUIDE, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]:
		await _send(_button(button, 1))
		_check(_is_device("keyboard"), "An unrelated gamepad button does not switch hint mode: " + str(button))
	_tracker.observe(_button(JOY_BUTTON_A, -1))
	_check(_is_device("keyboard"), "An invalid negative gamepad device cannot become the active hint device")

func _test_axis_edges() -> void:
	_tracker.reset()
	for amount: float in [0.0, 0.10, -0.20, 0.34, -0.34]:
		await _send(_axis(JOY_AXIS_LEFT_X, amount, 4))
		_check(_is_device("keyboard"), "Stick drift and values below the activation threshold cannot switch hints")
	await _send(_axis(JOY_AXIS_LEFT_X, 0.35, 4))
	_check(_is_device("gamepad", 4), "An exact positive activation threshold selects that gamepad")
	await _send(_key(KEY_Q))
	await _send(_key(KEY_Q, false))
	var before: int = _changes.size()
	for amount: float in [0.36, 0.90, 0.28, 0.34, 0.70]:
		await _send(_axis(JOY_AXIS_LEFT_X, amount, 4))
		_check(_is_device("keyboard") and _changes.size() == before, "A stick still held in the same direction cannot reclaim hints after keyboard activity")
	await _send(_axis(JOY_AXIS_LEFT_X, 0.20, 4))
	_check(_is_device("keyboard"), "Returning to the exact neutral threshold rearms the stick without changing hints")
	await _send(_axis(JOY_AXIS_LEFT_X, 0.35, 4))
	_check(_is_device("gamepad", 4), "A newly rearmed same-direction stick action can select the gamepad again")
	await _send(_key(KEY_Q))
	await _send(_key(KEY_Q, false))
	await _send(_axis(JOY_AXIS_LEFT_X, -0.35, 4))
	_check(_is_device("gamepad", 4), "A direct opposite-direction threshold crossing counts as a new intentional action")
	await _send(_key(KEY_Q))
	await _send(_key(KEY_Q, false))
	before = _changes.size()
	await _send(_axis(JOY_AXIS_LEFT_X, -0.90, 4))
	await _send(_axis(JOY_AXIS_LEFT_X, -0.21, 4))
	await _send(_axis(JOY_AXIS_LEFT_X, -0.35, 4))
	_check(_is_device("keyboard") and _changes.size() == before, "A value outside the release threshold preserves the previous direction latch")
	await _send(_axis(JOY_AXIS_LEFT_Y, -0.60, 4))
	_check(_is_device("gamepad", 4), "The second left-stick axis has its own independent edge latch")
	await _send(_key(KEY_Q))
	await _send(_key(KEY_Q, false))
	for axis: int in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		await _send(_axis(axis, 1.0, 4))
		_check(_is_device("keyboard"), "Right-stick and trigger axes never choose the active hint device")
	for value: float in [NAN, INF, -INF]:
		_tracker.observe(_axis(JOY_AXIS_LEFT_X, value, 4))
		_check(_is_device("keyboard"), "Nonfinite stick values do not alter hints or latches")
	_tracker.observe(_axis(JOY_AXIS_LEFT_X, 1.0, -1))
	_check(_is_device("keyboard"), "An invalid device axis cannot choose gamepad hints")
	_tracker.reset()
	await _send(_axis(JOY_AXIS_LEFT_X, 0.60, 4))
	_check(_is_device("gamepad", 4), "Explicit reset clears held-stick latches as well as the active device")

func _test_multiple_devices() -> void:
	_tracker.reset()
	await _send(_axis(JOY_AXIS_LEFT_X, 0.70, 5))
	_check(_is_device("gamepad", 5), "A left-stick edge records its exact gamepad identifier")
	await _send(_axis(JOY_AXIS_LEFT_X, 0.70, 6))
	_check(_is_device("gamepad", 6), "Another device owns a separate latch and can become the active gamepad")
	var before: int = _changes.size()
	await _send(_axis(JOY_AXIS_LEFT_X, 0.90, 5))
	_check(_is_device("gamepad", 6) and _changes.size() == before, "A still-held inactive gamepad does not steal the current gamepad's hints")
	Input.joy_connection_changed.emit(9, true)
	_check(_is_device("gamepad", 6) and _changes.size() == before, "Merely connecting a controller does not switch hint mode")
	Input.joy_connection_changed.emit(5, false)
	_check(_is_device("gamepad", 6) and _changes.size() == before, "Disconnecting an inactive gamepad does not switch the current hints")
	Input.joy_connection_changed.emit(6, false)
	_check(_is_device("keyboard") and _changes.size() == before + 1, "Disconnecting the active gamepad switches to keyboard and emits exactly once")
	Input.joy_connection_changed.emit(6, true)
	_check(_is_device("keyboard") and _changes.size() == before + 1, "Reconnecting the old active gamepad waits for intentional input")
	await _send(_axis(JOY_AXIS_LEFT_X, 0.70, 6))
	_check(_is_device("gamepad", 6), "A disconnected device's cleared axis latch permits a fresh action after reconnecting")
	await _send(_button(JOY_BUTTON_Y, 8))
	_check(_is_device("gamepad", 8), "An intentional supported button can select a new device independently of stick latches")
	_tracker.reset()
	before = _changes.size()
	_tracker.reset()
	_check(_is_device("keyboard") and _changes.size() == before, "Reset in the default state remains signal-free")

func _test_pause_and_propagation() -> void:
	_tracker.reset()
	var received: int = _probe.received
	var unhandled: int = _probe.unhandled
	await _send(_button(JOY_BUTTON_X, 2))
	_check(_is_device("gamepad", 2) and _probe.received > received and _probe.unhandled > unhandled, "Device observation leaves button events available to later input and unhandled-input receivers")
	paused = true
	await _send(_key(KEY_E))
	await _send(_key(KEY_E, false))
	_check(_is_device("keyboard") and paused, "A paused tree still observes keyboard activity without resuming the game")
	await _send(_button(JOY_BUTTON_START, 7))
	_check(_is_device("gamepad", 7) and paused, "A paused tree still observes intentional gamepad activity without consuming Start")
	Input.joy_connection_changed.emit(7, false)
	_check(_is_device("keyboard") and paused, "Active-controller disconnect fallback works while paused and leaves pause state untouched")
	paused = false
	await process_frame

func _input_map_signature() -> Dictionary:
	var result: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		var events: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.as_text())
		result[str(action)] = {"deadzone": InputMap.action_get_deadzone(action), "events": events}
	return result
