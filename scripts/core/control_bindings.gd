class_name ControlBindings
extends RefCounted
## Isolated gameplay actions; menu bindings remain owned by Godot's ui_* actions.

const ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right", "dash", "pulse", "skill_secondary"]
const LEGACY_ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right", "dash", "pulse"]
const DEADZONE: float = 0.20
const PREFIX: String = "broxy_"

static var _installed: Dictionary = {}

static func defaults() -> Dictionary:
	return {"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "dash": KEY_SPACE, "pulse": KEY_Q, "skill_secondary": KEY_E}

static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return defaults()
	var result: Dictionary = {}
	var occupied: Dictionary = {}
	for action: String in LEGACY_ACTIONS:
		var candidate: Variant = value.get(action)
		if not candidate is int or not _key_error(int(candidate)).is_empty() or occupied.has(candidate):
			return defaults()
		result[action] = int(candidate)
		occupied[candidate] = true
	var secondary: Variant = value.get("skill_secondary", KEY_NONE)
	if secondary is int and _key_error(int(secondary)).is_empty() and not occupied.has(secondary):
		result["skill_secondary"] = int(secondary)
	else:
		for candidate: int in [KEY_E, KEY_R, KEY_F, KEY_C, KEY_V, KEY_1, KEY_2]:
			if not occupied.has(candidate):
				result["skill_secondary"] = candidate
				break
	return result

static func binding_error(bindings: Dictionary, action: String, keycode: int) -> String:
	if action not in ACTIONS:
		return "未知的操作。"
	var error: String = _key_error(keycode)
	if not error.is_empty():
		return error
	var current: Dictionary = normalize(bindings)
	for other: String in ACTIONS:
		if other != action and int(current[other]) == keycode:
			return "该按键已用于“%s”。" % action_label(other)
	return ""

static func key_label(keycode: int) -> String:
	return "空格" if keycode == KEY_SPACE else OS.get_keycode_string(keycode)

static func action_label(id: String) -> String:
	return str({"move_up": "向上移动", "move_down": "向下移动", "move_left": "向左移动", "move_right": "向右移动", "dash": "冲刺", "pulse": "技能1", "skill_secondary": "技能2", "pause": "暂停"}.get(id, id))

static func install(bindings: Dictionary) -> void:
	_installed = normalize(bindings)
	for action: String in ACTIONS + ["pause"]:
		var input_action: String = PREFIX + action
		if not InputMap.has_action(input_action):
			InputMap.add_action(input_action, DEADZONE)
		Input.action_release(input_action)
		InputMap.action_set_deadzone(input_action, DEADZONE)
		InputMap.action_erase_events(input_action)
		_add_key(input_action, KEY_ESCAPE if action == "pause" else int(_installed[action]))
	for entry: Array in [["move_up", KEY_UP, JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0], ["move_down", KEY_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0], ["move_left", KEY_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0], ["move_right", KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0]]:
		var input_action: String = PREFIX + str(entry[0])
		_add_key(input_action, int(entry[1]))
		_add_button(input_action, int(entry[2]))
		var axis := InputEventJoypadMotion.new()
		axis.device = -1
		axis.axis = int(entry[3])
		axis.axis_value = float(entry[4])
		InputMap.action_add_event(input_action, axis)
	_add_button(PREFIX + "dash", JOY_BUTTON_A)
	_add_button(PREFIX + "pulse", JOY_BUTTON_X)
	_add_button(PREFIX + "skill_secondary", JOY_BUTTON_Y)
	_add_button(PREFIX + "pause", JOY_BUTTON_START)

static func ensure_installed() -> void:
	for action: String in ACTIONS + ["pause"]:
		if not InputMap.has_action(PREFIX + action):
			install(_installed if not _installed.is_empty() else defaults())
			return
	if _installed.is_empty():
		install(defaults())

static func movement() -> Vector2:
	ensure_installed()
	return Input.get_vector(PREFIX + "move_left", PREFIX + "move_right", PREFIX + "move_up", PREFIX + "move_down", DEADZONE)

static func pressed(event: InputEvent, action: String) -> bool:
	if action not in ACTIONS and action != "pause":
		return false
	ensure_installed()
	if event is InputEventKey:
		if not event.pressed or event.echo or event.alt_pressed or event.ctrl_pressed or event.meta_pressed:
			return false
		var code: int = int(event.physical_keycode) if event.physical_keycode != KEY_NONE else int(event.keycode)
		var expected: int = KEY_ESCAPE if action == "pause" else int(_installed[action])
		if code == expected:
			return true
		return code == int({"move_up": KEY_UP, "move_down": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT}.get(action, KEY_NONE)) and code != KEY_NONE
	if event is InputEventJoypadButton:
		if not event.pressed:
			return false
		var button: int = int({"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN, "move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT, "dash": JOY_BUTTON_A, "pulse": JOY_BUTTON_X, "skill_secondary": JOY_BUTTON_Y, "pause": JOY_BUTTON_START}.get(action, -1))
		return event.button_index == button
	return false

static func _add_key(action: String, keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)

static func _add_button(action: String, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	InputMap.action_add_event(action, event)

static func _key_error(keycode: int) -> String:
	if keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_F11, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return "该按键保留给暂停、菜单或系统操作。"
	if (keycode >= KEY_A and keycode <= KEY_Z) or (keycode >= KEY_0 and keycode <= KEY_9) or (keycode >= KEY_F1 and keycode <= KEY_F35) or (keycode >= KEY_KP_MULTIPLY and keycode <= KEY_KP_9):
		return ""
	if keycode in [KEY_SPACE, KEY_APOSTROPHE, KEY_COMMA, KEY_MINUS, KEY_PERIOD, KEY_SLASH, KEY_SEMICOLON, KEY_EQUAL, KEY_BRACKETLEFT, KEY_BACKSLASH, KEY_BRACKETRIGHT, KEY_QUOTELEFT, KEY_BACKSPACE, KEY_INSERT, KEY_DELETE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_PAUSE, KEY_PRINT, KEY_SCROLLLOCK, KEY_NUMLOCK, KEY_CAPSLOCK, KEY_MENU]:
		return ""
	return "请选择有效的键盘按键。"
