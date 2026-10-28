extends SceneTree
## Real gameplay InputMap events and an isolated ConfigFile; never touches the personal profile.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_validation()
	_test_installed_events()
	_test_pressed_edges()
	_test_movement()
	_test_profile_roundtrip()
	ControlBindings.install(ControlBindings.defaults())
	print("ControlBindings: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _custom() -> Dictionary:
	return {"move_up": KEY_I, "move_down": KEY_K, "move_left": KEY_J, "move_right": KEY_L, "dash": KEY_R, "pulse": KEY_F, "skill_secondary": KEY_E}

func _legacy_custom() -> Dictionary:
	return {"move_up": KEY_I, "move_down": KEY_K, "move_left": KEY_J, "move_right": KEY_L, "dash": KEY_E, "pulse": KEY_Q}

func _key(code: int, down: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	return event

func _button(index: int, down: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = down
	return event

func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event

func _parse(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _test_validation() -> void:
	var defaults: Dictionary = ControlBindings.defaults()
	_check(defaults == {"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "dash": KEY_SPACE, "pulse": KEY_Q, "skill_secondary": KEY_E}, "Defaults retain WASD and Space while the two active slots use Q and E")
	defaults["dash"] = KEY_E
	_check(int(ControlBindings.defaults()["dash"]) == KEY_SPACE, "Returned defaults cannot mutate the next caller's bindings")
	_check(ControlBindings.normalize(_custom()) == _custom(), "Seven distinct custom physical keys remain valid")
	var legacy: Dictionary = _legacy_custom()
	var migrated: Dictionary = legacy.duplicate(true)
	migrated["skill_secondary"] = KEY_R
	_check(ControlBindings.normalize(legacy) == migrated and legacy == _legacy_custom(), "A legacy six-key map keeps its E dash and gains a free R secondary binding without mutating input")
	for secondary: Variant in [true, null, KEY_E, KEY_ESCAPE, NAN]:
		var repaired: Dictionary = legacy.duplicate(true)
		repaired["skill_secondary"] = secondary
		_check(ControlBindings.normalize(repaired) == migrated, "An invalid or occupied secondary binding preserves all six legacy keys and selects the first free key")
	for invalid: Variant in [null, true, 7, "bad", [], Vector2.ONE, {}]:
		_check(ControlBindings.normalize(invalid) == ControlBindings.defaults(), "Malformed or incomplete configuration falls back as one complete binding set")
	var extra: Dictionary = _custom()
	extra["unknown_future_action"] = {"invalid": true}
	_check(ControlBindings.normalize(extra) == _custom(), "Unknown extra fields do not pollute or invalidate the seven recognized keys")
	for bad: Variant in [true, 42.0, "E", null, -1, KEY_NONE, MOUSE_BUTTON_LEFT, 999999999, KEY_E | KEY_MASK_SHIFT]:
		var value: Dictionary = _custom()
		value["dash"] = bad
		_check(ControlBindings.normalize(value) == ControlBindings.defaults(), "Noninteger, mouse, masked and unknown key values fall back atomically")
	for reserved: int in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_F11, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		var value: Dictionary = _custom()
		value["dash"] = reserved
		_check(not ControlBindings.binding_error(_custom(), "dash", reserved).is_empty() and ControlBindings.normalize(value) == ControlBindings.defaults(), "Reserved navigation, pause and modifier keys cannot become gameplay primary bindings")
	var duplicate: Dictionary = _custom()
	duplicate["dash"] = duplicate["pulse"]
	_check(ControlBindings.normalize(duplicate) == ControlBindings.defaults(), "Duplicate primary keys reject the complete saved set")
	_check(ControlBindings.binding_error(_custom(), "dash", KEY_F).contains("技能1") and ControlBindings.binding_error(_custom(), "dash", KEY_E).contains("技能2"), "A conflict identifies the active slot already using the key")
	_check(ControlBindings.binding_error(_custom(), "dash", KEY_R).is_empty() and ControlBindings.binding_error(_custom(), "dash", KEY_G).is_empty(), "Keeping a key or choosing a free valid key is allowed")
	_check(not ControlBindings.binding_error(_custom(), "unknown", KEY_E).is_empty() and not ControlBindings.binding_error(_custom(), "dash", 1).is_empty(), "Unknown actions and mouse button integers are rejected")
	_check(ControlBindings.key_label(KEY_SPACE) == "空格" and ControlBindings.key_label(KEY_E) == OS.get_keycode_string(KEY_E), "Key labels use Chinese Space and the operating-system key names")
	for action: String in ControlBindings.ACTIONS:
		_check(ControlBindings.action_label(action) != action and not ControlBindings.action_label(action).is_empty(), "Every configurable action has a localized label: " + action)

func _menu_signature() -> Dictionary:
	var result: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		if not str(action).begins_with("ui_"):
			continue
		var events: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.as_text())
		result[str(action)] = events
	return result

func _test_installed_events() -> void:
	for code: int in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		var event: InputEventKey = _key(code)
		event.physical_keycode = KEY_NONE
		_check(InputMap.event_is_action(event, "ui_accept"), "Project menu confirmation retains its original Enter, keypad Enter and Space keyboard events")
	var escape: InputEventKey = _key(KEY_ESCAPE)
	escape.physical_keycode = KEY_NONE
	_check(InputMap.event_is_action(escape, "ui_cancel"), "Project menu cancellation retains its original Escape keyboard event")
	_check(InputMap.event_is_action(_button(JOY_BUTTON_A), "ui_accept"), "The project explicitly maps controller A to the real menu-confirm action")
	_check(InputMap.event_is_action(_button(JOY_BUTTON_B), "ui_cancel"), "The project explicitly maps controller B to the real menu-cancel action")
	_check(not InputMap.event_is_action(_button(JOY_BUTTON_B), "ui_accept") and not InputMap.event_is_action(_button(JOY_BUTTON_A), "ui_cancel"), "Menu confirm and cancel keep distinct controller buttons")
	var menu_before: Dictionary = _menu_signature()
	ControlBindings.install(_custom())
	_check(_menu_signature() == menu_before, "Installing gameplay controls preserves every built-in menu event")
	_check(InputMap.event_is_action(_button(JOY_BUTTON_A), "ui_accept") and InputMap.event_is_action(_button(JOY_BUTTON_B), "ui_cancel"), "Gameplay remapping preserves the project's explicit controller menu actions")
	for action: String in ControlBindings.ACTIONS + ["pause"]:
		var name: String = "broxy_" + action
		_check(InputMap.has_action(name) and is_equal_approx(InputMap.action_get_deadzone(name), 0.20), "Each namespaced gameplay action exists with the explicit deadzone: " + action)
		var physical: Array[int] = []
		var buttons: Array[int] = []
		var axes: Array[InputEventJoypadMotion] = []
		for event: InputEvent in InputMap.action_get_events(name):
			if event is InputEventKey:
				physical.append(int(event.physical_keycode))
				_check(event.keycode == KEY_NONE, "Keyboard mappings use physical rather than layout-dependent logical codes")
			elif event is InputEventJoypadButton:
				buttons.append(int(event.button_index))
				_check(event.device == -1, "Fixed controller buttons accept any connected gamepad")
			elif event is InputEventJoypadMotion:
				axes.append(event)
				_check(event.device == -1, "Fixed controller axes accept any connected gamepad")
		var primary: int = KEY_ESCAPE if action == "pause" else int(_custom()[action])
		_check(primary in physical and InputMap.event_is_action(_key(primary), name), "The live InputMap recognizes the exact installed primary physical key")
		if action.begins_with("move_"):
			var arrow: int = int({"move_up": KEY_UP, "move_down": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT}[action])
			_check(physical.size() == 2 and arrow in physical and buttons.size() == 1 and axes.size() == 1, "Movement keeps one primary key, a fixed arrow, a D-pad direction and a left-stick half axis")
		else:
			var expected: int = int({"dash": JOY_BUTTON_A, "pulse": JOY_BUTTON_X, "skill_secondary": JOY_BUTTON_Y, "pause": JOY_BUTTON_START}[action])
			_check(physical.size() == 1 and buttons == [expected] and axes.is_empty(), "Skills and pause have exactly their fixed A/X/Y/Start controller mapping")
	_check(not InputMap.event_is_action(_key(KEY_SPACE), "broxy_dash") and not InputMap.event_is_action(_key(KEY_W), "broxy_move_up"), "Rebinding removes the previous primary keys from the real InputMap")
	InputMap.erase_action("broxy_pulse")
	ControlBindings.ensure_installed()
	_check(InputMap.has_action("broxy_pulse") and ControlBindings.pressed(_key(KEY_F), "pulse"), "Ensuring a missing action restores the installed custom configuration")
	ControlBindings.install(_custom())
	_check(InputMap.action_get_events("broxy_move_up").size() == 4 and InputMap.action_get_events("broxy_dash").size() == 2 and _menu_signature() == menu_before, "Repeated installation replaces gameplay events without duplicates or menu changes")

func _test_pressed_edges() -> void:
	ControlBindings.install(_custom())
	var key: InputEventKey = _key(KEY_R)
	_check(ControlBindings.pressed(key, "dash") and not ControlBindings.pressed(key, "pulse"), "A keyboard press triggers only its exact configured action")
	_check(ControlBindings.pressed(_key(KEY_E), "skill_secondary") and not ControlBindings.pressed(_key(KEY_E), "dash") and not ControlBindings.pressed(_key(KEY_E), "pulse"), "The second active-slot key remains distinct from both dash and slot one")
	key.echo = true
	_check(not ControlBindings.pressed(key, "dash"), "Keyboard autorepeat cannot retrigger a skill")
	key.echo = false
	key.pressed = false
	_check(not ControlBindings.pressed(key, "dash"), "A keyboard release cannot trigger a skill")
	key.pressed = true
	for modifier: String in ["alt_pressed", "ctrl_pressed", "meta_pressed"]:
		key.set(modifier, true)
		_check(not ControlBindings.pressed(key, "dash"), "Alt/Ctrl/Meta chords do not request gameplay skills")
		key.set(modifier, false)
	key.shift_pressed = true
	_check(ControlBindings.pressed(key, "dash"), "Shift does not change the configured physical action")
	key.shift_pressed = false
	key.keycode = KEY_Q
	_check(ControlBindings.pressed(key, "dash") and not ControlBindings.pressed(key, "pulse"), "Physical key identity takes priority over the current keyboard layout")
	key.physical_keycode = KEY_NONE
	key.keycode = KEY_R
	_check(ControlBindings.pressed(key, "dash"), "Logical fallback supports existing synthesized keyboard events without a physical code")
	_check(not ControlBindings.pressed(_key(KEY_SPACE), "dash") and not ControlBindings.pressed(_key(KEY_Q), "pulse"), "The old skill keys stop requesting actions after a custom rebind")
	for pair: Array in [[JOY_BUTTON_A, "dash"], [JOY_BUTTON_X, "pulse"], [JOY_BUTTON_Y, "skill_secondary"], [JOY_BUTTON_START, "pause"], [JOY_BUTTON_DPAD_UP, "move_up"]]:
		var event: InputEventJoypadButton = _button(int(pair[0]))
		_check(ControlBindings.pressed(event, str(pair[1])) and not ControlBindings.pressed(_button(int(pair[0]), false), str(pair[1])), "Only pressed controller-button edges request their matching action")
	_check(not ControlBindings.pressed(_button(JOY_BUTTON_B), "dash") and not ControlBindings.pressed(_button(JOY_BUTTON_B), "pulse"), "The controller cancel button does not request either skill")
	_check(not ControlBindings.pressed(_axis(JOY_AXIS_LEFT_X, 1.0), "dash") and not ControlBindings.pressed(InputEventMouseButton.new(), "dash"), "Axis and mouse events cannot masquerade as a skill press")
	_check(ControlBindings.pressed(_key(KEY_ESCAPE), "pause") and ControlBindings.pressed(_key(KEY_UP), "move_up") and not ControlBindings.pressed(key, "ui_accept"), "Pause, fixed arrows and action-name boundaries remain explicit")

func _test_movement() -> void:
	ControlBindings.install(_custom())
	_check(ControlBindings.movement() == Vector2.ZERO, "A fresh action set has no stuck movement")
	_parse(_key(KEY_W))
	_check(ControlBindings.movement() == Vector2.ZERO, "The previous W binding no longer moves a customized player")
	_parse(_key(KEY_W, false))
	_parse(_key(KEY_I))
	_check(ControlBindings.movement().is_equal_approx(Vector2.UP), "The custom physical up key produces actual movement")
	_parse(_key(KEY_L))
	_check(ControlBindings.movement().is_equal_approx(Vector2(1.0, -1.0).normalized()), "Diagonal keyboard input is normalized without a speed boost")
	_parse(_key(KEY_I, false))
	_parse(_key(KEY_L, false))
	_parse(_key(KEY_LEFT))
	_check(ControlBindings.movement().is_equal_approx(Vector2.LEFT), "Arrow movement remains available after remapping the primary keys")
	_parse(_key(KEY_LEFT, false))
	_parse(_button(JOY_BUTTON_DPAD_DOWN))
	_check(ControlBindings.movement().is_equal_approx(Vector2.DOWN), "The fixed controller D-pad feeds the same movement vector")
	_parse(_button(JOY_BUTTON_DPAD_DOWN, false))
	for amount: float in [0.0, 0.10, 0.19]:
		_parse(_axis(JOY_AXIS_LEFT_X, amount))
		_check(ControlBindings.movement() == Vector2.ZERO, "Stick motion below the radial deadzone remains still")
	_parse(_axis(JOY_AXIS_LEFT_X, 0.60))
	var partial: Vector2 = ControlBindings.movement()
	_check(partial.x > 0.0 and partial.x < 1.0 and is_equal_approx(partial.y, 0.0) and is_equal_approx(partial.length(), 0.50), "A partial stick deflection retains analog strength after the 0.20 circular deadzone")
	_parse(_axis(JOY_AXIS_LEFT_Y, 0.60))
	var diagonal: Vector2 = ControlBindings.movement()
	_check(diagonal.x > 0.0 and diagonal.y > 0.0 and diagonal.length() < 1.0 and is_equal_approx(diagonal.x, diagonal.y), "Partial diagonal stick motion uses a circular deadzone instead of forcing full speed")
	_parse(_axis(JOY_AXIS_LEFT_X, 1.0))
	_parse(_axis(JOY_AXIS_LEFT_Y, 1.0))
	_check(ControlBindings.movement().is_equal_approx(Vector2.ONE.normalized()), "A fully deflected diagonal stick cannot exceed unit movement speed")
	_parse(_axis(JOY_AXIS_LEFT_X, 0.0))
	_parse(_axis(JOY_AXIS_LEFT_Y, 0.0))
	_check(ControlBindings.movement() == Vector2.ZERO, "Releasing both stick axes clears movement")
	_parse(_button(JOY_BUTTON_A))
	_check(Input.is_action_pressed("broxy_dash"), "A real parsed controller A event reaches the installed skill action")
	_parse(_button(JOY_BUTTON_A, false))
	_check(not Input.is_action_pressed("broxy_dash"), "A controller button release clears its action state")

func _test_profile_roundtrip() -> void:
	var personal_existed: bool = FileAccess.file_exists(GameStore.PATH)
	var personal_before: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if personal_existed else PackedByteArray()
	var path: String = "user://control-bindings-test-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(not FileAccess.file_exists(path), "The profile test selects a fresh isolated path")
	var store := GameStore.new(path)
	store.controls = _custom()
	store.settings = {"volume": 0.25, "shake": false, "flash": true, "controls": "ignored"}
	store.best["wave"] = 5
	_check(store.save_profile() == OK, "An isolated ConfigFile saves custom controls and existing profile sections")
	var config := ConfigFile.new()
	_check(config.load(path) == OK and config.get_section_keys("settings").size() == 3 and config.get_section_keys("controls").size() == 7, "Controls use their own seven-key section while settings retains only its original three keys")
	var loaded := GameStore.new(path)
	loaded.load_profile()
	_check(loaded.controls == _custom() and loaded.settings == {"volume": 0.25, "shake": false, "flash": true} and int(loaded.best["wave"]) == 5, "Custom controls, settings and records survive a real independent profile reload")
	config.erase_section("controls")
	_check(config.save(path) == OK, "A legacy fixture omits the new controls section")
	loaded = GameStore.new(path)
	loaded.load_profile()
	_check(loaded.controls == ControlBindings.defaults() and int(loaded.best["wave"]) == 5, "Old profiles gain default controls without losing existing records")
	for action: String in ControlBindings.LEGACY_ACTIONS:
		config.set_value("controls", action, _legacy_custom()[action])
	_check(config.save(path) == OK, "A legacy six-field configuration is serialized without a secondary action")
	loaded = GameStore.new(path)
	loaded.load_profile()
	var expected_legacy: Dictionary = _legacy_custom()
	expected_legacy["skill_secondary"] = KEY_R
	_check(loaded.controls == expected_legacy and loaded.best["wave"] == 5, "Loading a real legacy profile preserves its E dash, all other original keys and records while choosing R for slot two")
	_check(loaded.save_profile() == OK, "The migrated profile saves its expanded binding set")
	var reloaded := GameStore.new(path)
	reloaded.load_profile()
	_check(reloaded.controls == expected_legacy, "Saving and reloading does not remap the migrated player's controls again")
	for action: String in ControlBindings.ACTIONS:
		config.set_value("controls", action, _custom()[action])
	config.set_value("controls", "dash", KEY_F)
	_check(config.save(path) == OK, "A malformed saved configuration can be tested independently")
	loaded = GameStore.new(path)
	loaded.load_profile()
	_check(loaded.controls == ControlBindings.defaults(), "Conflicting saved keys sanitize to the entire default set on load")
	loaded.controls = {"move_up": KEY_ESCAPE}
	loaded.settings["volume"] = NAN
	_check(loaded.save_profile() == OK and loaded.controls == ControlBindings.defaults() and loaded.settings["volume"] == 0.65, "Save sanitization removes partial controls and nonfinite settings before serialization")
	store.controls = _custom()
	_check(store.save_profile() == OK, "The isolation fixture restores a nondefault on-disk control set")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var diagnostic := GameStore.new(path)
	diagnostic.persistent = false
	diagnostic.load_profile()
	_check(diagnostic.controls == ControlBindings.defaults() and diagnostic.settings == {"volume": 0.65, "shake": true, "flash": true}, "A nonpersistent store does not read controls or settings from an existing profile")
	diagnostic.controls = _custom()
	diagnostic.settings["volume"] = 0.0
	_check(diagnostic.save_profile() == OK and FileAccess.get_file_as_bytes(path) == before, "A nonpersistent save leaves existing profile bytes intact")
	var absent: String = path + ".absent"
	var memory_only := GameStore.new(absent)
	memory_only.persistent = false
	memory_only.load_profile()
	_check(memory_only.save_profile() == OK and not FileAccess.file_exists(absent), "A nonpersistent store never creates a missing profile")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "The isolated test removes only its own temporary profile")
	_check(FileAccess.file_exists(GameStore.PATH) == personal_existed and (not personal_existed or FileAccess.get_file_as_bytes(GameStore.PATH) == personal_before), "Binding tests preserve the personal profile byte for byte")
