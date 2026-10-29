extends SceneTree
## Synthetic keyboard and joypad events exercise UI capture; this is not hardware validation.

class BackBridge:
	extends Node
	var ui: GameUI

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and ui.handle_back():
			get_viewport().set_input_as_handled()

class InputProbe:
	extends Node
	var keys: Array[int] = []
	var clicks: int = 0
	var joy_buttons: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			keys.append(int(event.physical_keycode))
		elif event is InputEventMouseButton and event.pressed:
			clicks += 1
		elif event is InputEventJoypadButton and event.pressed:
			joy_buttons += 1

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI
var _state: RunState
var _probe: InputProbe
var _emissions: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_state = RunState.new()
	_state.begin(20261028, "bone")
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	_ui.controls_changed.connect(func(bindings: Dictionary) -> void:
		_emissions.append(bindings.duplicate(true))
		bindings["dash"] = KEY_Z)
	_probe = InputProbe.new()
	root.add_child(_probe)
	var back := BackBridge.new()
	back.ui = _ui
	root.add_child(back)
	var input_map_before: Dictionary = _input_map_signature()
	await _test_capture_and_back_stack()
	await _test_layout_restore_and_stale_callbacks()
	await _test_paused_joypad_navigation()
	await _test_mapped_hud()
	await _test_long_bindings_in_settings()
	_check(_input_map_signature() == input_map_before, "UI editing and synthetic navigation never install or modify global gameplay or ui_* InputMap actions")
	paused = false
	_ui.queue_free()
	_probe.queue_free()
	back.queue_free()
	await process_frame
	print("ControlsUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _key(code: Key, options: Dictionary = {}) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = int(options.get("logical", code))
		event.physical_keycode = int(options.get("physical", code))
		event.ctrl_pressed = bool(options.get("ctrl", false))
		event.alt_pressed = bool(options.get("alt", false))
		event.meta_pressed = bool(options.get("meta", false))
		event.shift_pressed = bool(options.get("shift", false))
		event.echo = pressed and bool(options.get("echo", false))
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _joy(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await process_frame

func _click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _button(name: String) -> Button:
	return _ui.find_child(name, true, false) as Button

func _find_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_text(child, text)
		if found != null:
			return found
	return null

func _enter_button(button: Button) -> void:
	_check(button != null, "The intended UI action exists before keyboard activation")
	if button != null:
		await _settle()
		button.grab_focus()
		await _key(KEY_ENTER)
		await _settle()

func _capture(action: String) -> void:
	await _enter_button(_button("Bind_" + action))
	_check(_ui._capture_action == action, "Real Enter begins a single keyboard rebind: " + action)

func _overlay_owns_focus() -> bool:
	var focus: Control = root.gui_get_focus_owner()
	return focus != null and _ui._overlay.is_ancestor_of(focus) and not _ui._page.is_ancestor_of(focus)

func _test_capture_and_back_stack() -> void:
	_ui.show_title({})
	await _settle()
	var source: Button = _find_text(_ui._page, "设置")
	await _enter_button(source)
	_check(_ui._overlay_mode == "settings_title", "The title settings retain the existing first-level modal")
	await _enter_button(_button("ControlsSettings"))
	_check(_ui._overlay_mode == "controls_title" and _overlay_owns_focus(), "The controls entry opens its own focus-isolated child page")
	for action: String in ControlBindings.ACTIONS:
		_check(_button("Bind_" + action) != null and _button("Bind_" + action).text == ControlBindings.key_label(int(ControlBindings.defaults()[action])), "Every action exposes its actual default main key: " + action)
	await _capture("dash")
	var count: int = _emissions.size()
	var probe_before: Array = [_probe.keys.duplicate(), _probe.clicks, _probe.joy_buttons]
	await _key(KEY_Q)
	var status := _ui.find_child("BindingStatus", true, false) as Label
	_check(_ui._capture_action == "dash" and status.text == ControlBindings.binding_error(_ui._controls, "dash", KEY_Q) and status.get_theme_color("font_color").is_equal_approx(GameUI.RED), "A conflicting key reports the exact refusal and keeps capture active")
	await _key(KEY_E)
	_check(_ui._capture_action == "dash" and status.text == ControlBindings.binding_error(_ui._controls, "dash", KEY_E), "The second active skill's E binding is also protected from conflicting reassignment")
	await _key(KEY_TAB)
	_check(_ui._capture_action == "dash" and _overlay_owns_focus(), "A reserved Tab cannot leave capture or focus an underlying control")
	await _key(KEY_G, {"ctrl": true})
	_check(_ui._capture_action == "dash" and status.text.contains("修饰键"), "A modifier combination is refused without committing a replacement")
	await _key(KEY_F, {"echo": true})
	_check(_ui._capture_action == "dash" and _emissions.size() == count, "Keyboard echo cannot complete a rebind")
	await _click(_button("RestoreControls"))
	await _joy(JOY_BUTTON_X)
	_check(_ui._capture_action == "dash" and _emissions.size() == count and _ui._controls == ControlBindings.defaults(), "Mouse buttons and noncancel joypad presses are consumed while waiting for a keyboard key")
	_check(probe_before == [_probe.keys, _probe.clicks, _probe.joy_buttons], "Capture never forwards refused keys, pointer clicks or joypad buttons into unhandled gameplay input")
	await _joy(JOY_BUTTON_B)
	_check(_ui._capture_action.is_empty() and _ui._overlay_mode == "controls_title" and _emissions.size() == count, "Synthetic gamepad B cancels only the active capture and preserves its old binding")
	await _capture("dash")
	await _key(KEY_F, {"logical": KEY_G})
	_check(_ui._capture_action.is_empty() and int(_ui._controls["dash"]) == KEY_F and _button("Bind_dash").text == "F", "Successful capture prefers the physical key and refreshes the displayed binding")
	_check(_emissions.size() == count + 1 and int(_emissions.back()["dash"]) == KEY_F and int(_ui._controls["dash"]) == KEY_F, "A successful rebind emits one detached dictionary that subscribers cannot mutate back into UI state")
	await _capture("move_up")
	await _key(KEY_I, {"physical": KEY_NONE})
	_check(int(_ui._controls["move_up"]) == KEY_I, "A keyboard source without a physical code falls back to its logical key")
	await _capture("skill_secondary")
	await _key(KEY_H)
	_check(int(_ui._controls["skill_secondary"]) == KEY_H and _button("Bind_skill_secondary").text == "H", "The second active skill supports the same real capture path as the original actions")
	await _capture("pulse")
	await _key(KEY_ESCAPE)
	_check(_ui._capture_action.is_empty() and _ui._overlay_mode == "controls_title", "The first real Escape cancels capture without leaving the controls page")
	await _key(KEY_ESCAPE)
	await _settle()
	_check(_ui._overlay_mode == "settings_title" and root.gui_get_focus_owner() == _button("ControlsSettings"), "The second real Escape returns one level and restores the controls entry focus")
	await _key(KEY_ESCAPE)
	await _settle()
	_check(_ui._overlay_mode.is_empty() and root.gui_get_focus_owner() == source, "The third real Escape restores the exact original title settings source")

func _test_layout_restore_and_stale_callbacks() -> void:
	_ui._show_settings(false)
	await _enter_button(_button("ControlsSettings"))
	_check(_ui._overlay_mode == "controls_title", "The layout fixture opens the actual controls child before measuring it (mode=%s)" % _ui._overlay_mode)
	if _ui._overlay_mode != "controls_title":
		_ui.hide_pause()
		return
	_check(root.gui_get_focus_owner() == _button("Bind_move_up"), "The controller navigation fixture starts at the controls page's actual initial focus")
	await _joy(JOY_BUTTON_DPAD_DOWN)
	_check(root.gui_get_focus_owner() == _button("Bind_move_down"), "A real synthetic D-pad press moves menu focus to the next binding row")
	await _axis(JOY_AXIS_LEFT_Y, 1.0)
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	_check(root.gui_get_focus_owner() == _button("Bind_move_left"), "A left-stick menu deflection moves to the next row and then returns to neutral")
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		await _settle()
		var panel := _ui.find_child("ControlsPanel", true, false) as Control
		_check(panel != null and root.get_visible_rect().encloses(panel.get_global_rect()), "The complete controls modal fits the actual reference-scaled window: %s (mode=%s, panel=%s, viewport=%s)" % [physical_size, _ui._overlay_mode, panel.get_global_rect() if panel != null else Rect2(), root.get_visible_rect()])
		for name: String in ["Bind_move_up", "Bind_move_down", "Bind_move_left", "Bind_move_right", "Bind_dash", "Bind_pulse", "Bind_skill_secondary", "Bind_hero_skill", "RestoreControls", "CloseControls"]:
			var button: Button = _button(name)
			_check(panel != null and button != null and panel.get_global_rect().encloses(button.get_global_rect()) and button.size.x + 0.1 >= button.get_minimum_size().x, "Every rebind and return action remains visible without clipping: %s (mode=%s)" % [name, _ui._overlay_mode])
		for step: int in 10:
			await _key(KEY_TAB)
			_check(_overlay_owns_focus(), "Tab navigation remains inside the child modal after wrapping")
	var guide := _ui.find_child("ControllerGuide", true, false) as Label
	_check(guide != null and guide.text.contains("A 冲刺") and guide.text.contains("X / Y 后排") and guide.text.contains("RB 主角") and guide.text.contains("Start 暂停") and guide.text.contains("B 返回") and guide.text.contains("X 旋转"), "The controls page shows the actual rear, main-character, movement and menu button mappings")
	var count: int = _emissions.size()
	var restore: Button = _button("RestoreControls")
	_check(restore != null, "The measured controls page retains its default-restore action")
	if restore == null:
		_ui.hide_pause()
		return
	restore.grab_focus()
	await _joy(JOY_BUTTON_A)
	await _settle()
	_check(_ui._controls == ControlBindings.defaults() and _emissions.size() == count + 1 and _emissions.back() == ControlBindings.defaults(), "Synthetic gamepad A restores defaults through the real focused action and emits once")
	var stale: Button = _button("Bind_pulse")
	var stale_restore: Button = _button("RestoreControls")
	_ui._show_settings(false)
	_ui._show_controls(false)
	count = _emissions.size()
	stale.pressed.emit()
	stale_restore.pressed.emit()
	_check(_ui._capture_action.is_empty() and _emissions.size() == count, "Deferred outgoing controls cannot capture or reset a newer controls page")
	await _settle()
	await _capture("pulse")
	_ui.show_title({})
	await _settle()
	_check(_ui._capture_action.is_empty() and _ui._overlay_mode.is_empty() and _ui.find_child("ControlsPanel", true, false) == null, "Replacing the screen clears capture, modal state and stale control nodes")
	var custom: Dictionary = ControlBindings.defaults()
	custom["dash"] = KEY_F
	_ui.set_controls(custom)
	custom["dash"] = KEY_Z
	var title_has_no_copy: bool = _ui.find_child("TitleControls", true, false) == null
	_ui._show_settings(false)
	_ui._show_controls(false)
	await _settle()
	_check(title_has_no_copy and _button("Bind_dash").text == "F" and int(_ui._controls["dash"]) == KEY_F and _emissions.size() == count, "Loading detached controls updates the actual settings button without title copy or an unsolicited save signal")
	root.size = Vector2i(1280, 720)

func _test_paused_joypad_navigation() -> void:
	_ui.show_hud()
	_ui.show_pause()
	paused = true
	await _settle()
	var settings: Button = _find_text(_ui._overlay, "设置")
	_check(settings != null, "The paused fixture exposes the real settings button")
	if settings == null:
		_ui.hide_pause()
		paused = false
		return
	settings.grab_focus()
	await _joy(JOY_BUTTON_A)
	await _settle()
	_check(_ui._overlay_mode == "settings_pause" and paused and _overlay_owns_focus(), "Synthetic gamepad A can open settings while the real scene tree is paused")
	var entry: Button = _button("ControlsSettings")
	_check(entry != null, "The paused settings page exposes its controls child action")
	if entry == null:
		_ui.hide_pause()
		paused = false
		return
	entry.grab_focus()
	await _joy(JOY_BUTTON_A)
	await _settle()
	_check(_ui._overlay_mode == "controls_pause" and paused and _overlay_owns_focus(), "The paused controls child remains keyboard and gamepad reachable")
	await _joy(JOY_BUTTON_B)
	await _settle()
	_check(_ui._overlay_mode == "settings_pause" and paused and root.gui_get_focus_owner() == _button("ControlsSettings"), "Gamepad B returns from paused controls to its exact settings entry")
	await _joy(JOY_BUTTON_B)
	await _settle()
	_check(_ui._overlay_mode == "pause" and paused and root.gui_get_focus_owner() == _find_text(_ui._overlay, "设置"), "Another B returns to the pause menu without resuming combat")
	_ui.hide_pause()
	paused = false
	await _settle()

func _test_mapped_hud() -> void:
	await _key(KEY_F6)
	_state.offers = [{"kind": "skill", "id": "pulse", "price": 0}, {"kind": "skill", "id": "arc_slash", "price": 0}]
	_check(_state.buy_offer(0) and _state.buy_offer(1), "The mapped-HUD fixture equips two actual backpack skills")
	var sim := CombatSim.new()
	sim.begin(_state)
	_ui.set_controls(ControlBindings.defaults())
	_ui.show_hud()
	_ui.update_hud(sim.snapshot())
	await _settle()
	var dash_label: Label = _ui._hud["dash_label"]
	var pulse_label: Label = _ui._hud["pulse_label"]
	var pulse_key: Label = _ui._hud["pulse_key"]
	var secondary_key: Label = _ui._hud["secondary_key"]
	_check(dash_label.text == "冲刺 · 空格" and pulse_label.text == GameCatalog.skill("pulse").display_name and pulse_key.text == "Q" and secondary_key.text == "E", "Default controls expose independent dash and both equipped skill keys")
	_check((_ui._hud["dash"] as Control).tooltip_text == "空格：向当前移动方向冲刺；静止时沿面向。\n短冲距离约132，冷却2.4秒；起始短暂闪避，可冲离减速地形。", "Default controls preserve the exact existing dash tooltip")
	var custom: Dictionary = ControlBindings.defaults()
	custom["dash"] = KEY_F
	custom["pulse"] = KEY_G
	custom["skill_secondary"] = KEY_H
	_ui.set_controls(custom)
	_check(dash_label.text == "冲刺 · F" and pulse_label.text == GameCatalog.skill("pulse").display_name and pulse_key.text == "G" and secondary_key.text == "H" and (_ui._hud["dash"] as Control).tooltip_text.begins_with("F：") and (_ui._hud["pulse"] as Control).tooltip_text.contains("G ·"), "An event-driven mapping update immediately refreshes all keys and tooltips without another simulation tick")
	var progress: Array = [(_ui._hud["dash_bar"] as ProgressBar).value, (_ui._hud["pulse_bar"] as ProgressBar).value, (_ui._hud["secondary_bar"] as ProgressBar).value]
	custom["dash"] = KEY_SCROLLLOCK
	_ui.set_controls(custom)
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		await _settle()
		for key: String in ["dash", "pulse", "secondary"]:
			var skill: Control = _ui._hud[key]
			var maximum_width: float = 108.0 if skill == _ui._hud["dash"] else 112.0
			_check(skill.size.x >= 100.0 and skill.size.x <= maximum_width + 0.1 and root.get_visible_rect().encloses(skill.get_global_rect()) and skill.focus_mode == Control.FOCUS_NONE, "Even a long valid key name respects the compact HUD width and input behavior")
	_check((_ui._hud["dash"] as Control).tooltip_text.begins_with(ControlBindings.key_label(KEY_SCROLLLOCK) + "：") and progress == [(_ui._hud["dash_bar"] as ProgressBar).value, (_ui._hud["pulse_bar"] as ProgressBar).value, (_ui._hud["secondary_bar"] as ProgressBar).value], "The full long key remains available in the tooltip without changing skill timing")
	_ui.notify("键位提示不应恢复战斗通知")
	_check(not _ui._toast.visible and not _ui._hud.has("bag_info") and _ui.find_child("HUDMapInfo", true, false) == null, "Control hints do not restore removed battle notifications or lower-right descriptions")
	_ui.set_controls(ControlBindings.defaults())

func _test_long_bindings_in_settings() -> void:
	await _key(KEY_F6)
	var bindings: Dictionary = {"move_up": KEY_SCROLLLOCK, "move_down": KEY_BACKSPACE, "move_left": KEY_KP_MULTIPLY, "move_right": KEY_KP_SUBTRACT, "dash": KEY_PAGEDOWN, "pulse": KEY_CAPSLOCK, "skill_secondary": KEY_PAGEUP, "hero_skill": KEY_NUMLOCK}
	_check(ControlBindings.normalize(bindings) == bindings, "The settings-width fixture uses eight distinct formally valid long key names")
	_ui.set_controls(bindings)
	_ui.show_title({})
	await _settle()
	_ui._show_settings(false)
	_ui._show_controls(false)
	await _settle()
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		await _settle()
		var panel := _ui.find_child("ControlsPanel", true, false) as Control
		_check(_ui.find_child("TitleControls", true, false) == null and panel != null and root.get_visible_rect().encloses(panel.get_global_rect()), "Long bindings remain in the actual settings panel, without a title hint: " + str(physical_size))
		for action: String in ControlBindings.ACTIONS:
			var binding := _button("Bind_" + action)
			_check(binding != null and binding.text == ControlBindings.key_label(int(bindings[action])) and binding.size.x + 0.1 >= binding.get_minimum_size().x and root.get_visible_rect().encloses(binding.get_global_rect()), "The actual binding button retains its complete configured long key name: " + action)
	_ui.hide_pause()
	_ui.set_controls(ControlBindings.defaults())
	root.size = Vector2i(1280, 720)

func _input_map_signature() -> Dictionary:
	var result: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		var events: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.as_text())
		result[str(action)] = events
	return result
