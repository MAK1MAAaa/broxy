class_name InputDeviceTracker
extends Node
## Input hints follow intentional device activity without changing or consuming that input.

signal device_changed(kind: String, device: int)

const AXIS_PRESS_THRESHOLD: float = 0.35
const AXIS_RELEASE_THRESHOLD: float = 0.20
const GAMEPAD_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]

var kind: String = "keyboard"
var gamepad_id: int = -1

var _axis_directions: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _input(event: InputEvent) -> void:
	observe(event)

func observe(event: InputEvent) -> void:
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		var keycode: int = int(event.physical_keycode) if event.physical_keycode != KEY_NONE else int(event.keycode)
		if keycode <= KEY_NONE or keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return
		_set_device("keyboard", -1)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index >= MOUSE_BUTTON_LEFT and event.button_index <= MOUSE_BUTTON_XBUTTON2:
			_set_device("keyboard", -1)
	elif event is InputEventJoypadButton:
		if event.device >= 0 and event.pressed and int(event.button_index) in GAMEPAD_BUTTONS:
			_set_device("gamepad", event.device)
	elif event is InputEventJoypadMotion:
		_observe_axis(event)

func snapshot() -> Dictionary:
	return {"kind": kind, "gamepad_id": gamepad_id}

func reset() -> void:
	_axis_directions.clear()
	_set_device("keyboard", -1)

func _observe_axis(event: InputEventJoypadMotion) -> void:
	if event.device < 0 or event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] or not is_finite(event.axis_value):
		return
	var axes: Dictionary = _axis_directions.get(event.device, {})
	var magnitude: float = absf(event.axis_value)
	if magnitude <= AXIS_RELEASE_THRESHOLD or is_equal_approx(magnitude, AXIS_RELEASE_THRESHOLD):
		axes[event.axis] = 0
		_axis_directions[event.device] = axes
		return
	if magnitude < AXIS_PRESS_THRESHOLD and not is_equal_approx(magnitude, AXIS_PRESS_THRESHOLD):
		return
	var direction: int = 1 if event.axis_value > 0.0 else -1
	if int(axes.get(event.axis, 0)) == direction:
		return
	axes[event.axis] = direction
	_axis_directions[event.device] = axes
	_set_device("gamepad", event.device)

func _set_device(next_kind: String, device: int) -> void:
	if kind == next_kind and gamepad_id == device:
		return
	kind = next_kind
	gamepad_id = device
	device_changed.emit(kind, gamepad_id)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	_axis_directions.erase(device)
	if kind == "gamepad" and gamepad_id == device:
		_set_device("keyboard", -1)
