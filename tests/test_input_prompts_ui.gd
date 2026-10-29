extends SceneTree
## Real synthetic input changes device hints; no physical controller is implied.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI
var _state: RunState
var _controls_emissions: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_state = _new_state()
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	_ui.controls_changed.connect(func(_bindings: Dictionary) -> void: _controls_emissions += 1)
	await _test_observation_and_title()
	await _test_hud_and_pause()
	await _test_capture_isolation()
	await _test_backpack_prompts()
	_check(_controls_emissions == 0, "Device prompt changes and refused captures never emit a binding-save request")
	paused = false
	_ui.queue_free()
	await process_frame
	print("InputPromptsUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _new_state() -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone", "mire")
	state.gold = 10000
	return state

func _buy(state: RunState, id: String) -> void:
	state.offers = [{"kind": "relic", "id": id, "price": 22, "sold": false}]
	_check(state.buy_offer(0), "The prompt fixture acquires its real skill-modifying relic: " + id)

func _key(code: Key, options: Dictionary = {}) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.echo = pressed and bool(options.get("echo", false))
		Input.parse_input_event(event)
		await process_frame

func _joy(button: JoyButton = JOY_BUTTON_Y, device: int = 7) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 7
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	Input.parse_input_event(event)
	await process_frame

func _pointer(point: Vector2, click: bool) -> void:
	if not click:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		Input.parse_input_event(motion)
		await process_frame
		return
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _kind() -> String:
	return str(_ui.input_device_snapshot().get("kind", ""))

func _title_note() -> Label:
	return _ui.find_child("TitleControls", true, false) as Label

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

func _state_signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.offers, state.rng.state, _ui._controls, _ui._settings])

func _test_observation_and_title() -> void:
	_ui.show_title({})
	await _settle()
	var tracker := _ui.find_child("InputDeviceTracker", false, false) as InputDeviceTracker
	_check(tracker != null and _ui.get_child(_ui.get_child_count() - 1) == tracker and tracker.process_mode == Node.PROCESS_MODE_ALWAYS, "The always-processing observer is the UI's last child so GUI-consumed input is observed first")
	_check(_kind() == "keyboard" and _title_note() == null and _ui._controls == ControlBindings.defaults(), "Fresh UI retains the default keyboard mapping without adding title instructions")
	var snapshot: Dictionary = _ui.input_device_snapshot()
	snapshot["kind"] = "gamepad"
	_check(_kind() == "keyboard", "The public device snapshot is detached from its observer state")
	var settings: Button = _find_text(_ui._page, "设置")
	_check(settings != null, "The title fixture exposes its real settings action")
	if settings == null:
		return
	settings.grab_focus()
	await _joy(JOY_BUTTON_A)
	await _settle()
	_check(_kind() == "gamepad" and int(_ui.input_device_snapshot().get("gamepad_id", -1)) == 7 and _ui._overlay_mode == "settings_title", "A real A event updates the device even when the GUI consumes it to open settings")
	_check(_title_note() == null and _ui._screen == "title" and root.gui_get_focus_owner() != null and _ui._overlay.is_ancestor_of(root.gui_get_focus_owner()), "Device observation preserves the real settings focus without recreating title instructions")
	var focus: Control = root.gui_get_focus_owner()
	var before: String = _state_signature(_state)
	await _pointer(Vector2(15, 15), false)
	await _axis(0.1)
	await _key(KEY_F13, {"echo": true})
	await _key(KEY_SHIFT)
	_check(_kind() == "gamepad" and root.gui_get_focus_owner() == focus and _state_signature(_state) == before, "Mouse movement, stick drift, keyboard echo and pure modifiers cannot replace gamepad hints or change modal focus/state")
	await _pointer(Vector2(15, 15), true)
	_check(_kind() == "keyboard" and root.gui_get_focus_owner() == focus and _ui._overlay_mode == "settings_title", "A real mouse click restores keyboard hints without changing the existing modal focus")
	_ui.hide_pause()
	var long_bindings: Dictionary = {"move_up": KEY_SCROLLLOCK, "move_down": KEY_BACKSPACE, "move_left": KEY_KP_MULTIPLY, "move_right": KEY_KP_SUBTRACT, "dash": KEY_PAGEDOWN, "pulse": KEY_CAPSLOCK, "skill_secondary": KEY_PAGEUP, "hero_skill": KEY_NUMLOCK}
	_ui.set_controls(long_bindings)
	_ui._show_settings(false)
	_ui._show_controls(false)
	await _settle()
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		await _settle()
		var panel := _ui.find_child("ControlsPanel", true, false) as Control
		await _joy()
		_check(_kind() == "gamepad" and _title_note() == null and panel != null and root.get_visible_rect().encloses(panel.get_global_rect()), "Gamepad observation keeps the actual controls panel in the scaled viewport without title copy: " + str(physical_size))
		await _key(KEY_F13)
		await _settle()
		_check(_kind() == "keyboard" and _ui._controls == long_bindings and panel != null and root.get_visible_rect().encloses(panel.get_global_rect()), "Returning to keyboard preserves the real configured controls and panel bounds: " + str(physical_size))
		for action: String in ControlBindings.ACTIONS:
			var binding := _button("Bind_" + action)
			_check(binding != null and binding.text == ControlBindings.key_label(int(long_bindings[action])) and binding.size.x + 0.1 >= binding.get_minimum_size().x and root.get_visible_rect().encloses(binding.get_global_rect()), "Returning from gamepad retains the complete key in its actual settings button: " + action)
	_ui.hide_pause()
	_ui.set_controls(ControlBindings.defaults())
	root.size = Vector2i(1280, 720)

func _test_hud_and_pause() -> void:
	_buy(_state, "fold_clasp")
	_buy(_state, "echo_stone")
	_state.offers = [{"kind": "skill", "id": "pulse", "price": 0}, {"kind": "skill", "id": "arc_slash", "price": 0}]
	_check(_state.buy_offer(0) and _state.buy_offer(1), "The prompt fixture acquires both real backpack skill slots")
	var sim := CombatSim.new()
	sim.begin(_state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	_ui.show_hud()
	_ui.update_hud(sim.snapshot())
	await _settle()
	var dash_label: Label = _ui._hud["dash_label"]
	var pulse_label: Label = _ui._hud["pulse_label"]
	var pulse_key: Label = _ui._hud["pulse_key"]
	var secondary_key: Label = _ui._hud["secondary_key"]
	var hero_key: Label = _ui._hud["hero_key"]
	var focus: Control = root.gui_get_focus_owner()
	await _joy()
	_check(dash_label.text == "冲刺 · A" and pulse_label.text == GameCatalog.skill("pulse").display_name and pulse_key.text == "X" and secondary_key.text == "Y" and hero_key.text == "RB" and root.gui_get_focus_owner() == focus, "Gamepad input changes every equipped rear and main skill key without creating or focusing gameplay controls")
	var dash_tip: String = (_ui._hud["dash"] as Control).tooltip_text
	var pulse_tip: String = (_ui._hud["pulse"] as Control).tooltip_text
	_check(dash_tip.begins_with("A：") and dash_tip.contains("冷却2.1秒") and pulse_tip.contains("X ·") and pulse_tip.contains("范围162") and pulse_tip.contains("冷却8.8秒"), "Gamepad tooltips preserve actual relic-modified skill parameters")
	var custom: Dictionary = ControlBindings.defaults()
	custom["dash"] = KEY_SCROLLLOCK
	custom["pulse"] = KEY_CAPSLOCK
	custom["skill_secondary"] = KEY_PAGEUP
	custom["hero_skill"] = KEY_NUMLOCK
	_ui.set_controls(custom)
	_check(dash_label.text == "冲刺 · A" and pulse_label.text == GameCatalog.skill("pulse").display_name and pulse_key.text == "X" and secondary_key.text == "Y" and hero_key.text == "RB", "Loading keyboard rebinds never replaces the active gamepad's fixed skill labels")
	await _key(KEY_F13)
	_check(dash_label.text == "冲刺 · " + ControlBindings.key_label(KEY_SCROLLLOCK) and pulse_label.text == GameCatalog.skill("pulse").display_name and pulse_key.text == ControlBindings.key_label(KEY_CAPSLOCK) and secondary_key.text == ControlBindings.key_label(KEY_PAGEUP) and hero_key.text == ControlBindings.key_label(KEY_NUMLOCK), "Keyboard activity restores every complete configured rear and main skill key name")
	sim.step(1.0 / 60.0, Vector2.ZERO, true, true)
	for frame: int in 15:
		sim.step(1.0 / 60.0, Vector2.ZERO)
	_check(sim.try_hero_skill(), "The prompt fixture starts the real independent main-character cooldown")
	_ui.update_hud(sim.snapshot())
	var clocks: Array = [sim.dash_snapshot(), sim.active_skill_snapshots(), sim.hero_skill_snapshot(), (_ui._hud["dash_bar"] as ProgressBar).value, (_ui._hud["pulse_bar"] as ProgressBar).value, (_ui._hud["secondary_bar"] as ProgressBar).value, (_ui._hud["hero_bar"] as ProgressBar).value]
	var before: String = _state_signature(_state)
	await _joy()
	await _key(KEY_F13)
	_check(clocks == [sim.dash_snapshot(), sim.active_skill_snapshots(), sim.hero_skill_snapshot(), (_ui._hud["dash_bar"] as ProgressBar).value, (_ui._hud["pulse_bar"] as ProgressBar).value, (_ui._hud["secondary_bar"] as ProgressBar).value, (_ui._hud["hero_bar"] as ProgressBar).value] and _state_signature(_state) == before, "Two prompt switches cannot advance Q/E/R cooldowns, rescale their bars or alter the build")
	_ui.show_pause()
	paused = true
	await _settle()
	focus = root.gui_get_focus_owner()
	await _joy()
	_check(_kind() == "gamepad" and paused and _ui._overlay_mode == "pause" and root.gui_get_focus_owner() == focus, "Device observation remains active during pause without changing its menu or focus")
	await _key(KEY_F13)
	_check(_kind() == "keyboard" and paused and root.gui_get_focus_owner() == focus and clocks == [sim.dash_snapshot(), sim.active_skill_snapshots(), sim.hero_skill_snapshot(), (_ui._hud["dash_bar"] as ProgressBar).value, (_ui._hud["pulse_bar"] as ProgressBar).value, (_ui._hud["secondary_bar"] as ProgressBar).value, (_ui._hud["hero_bar"] as ProgressBar).value], "Keyboard hints return during pause without progressing dash or Q/E/R authoritative skill clocks")
	_ui.hide_pause()
	paused = false
	_ui.set_controls(ControlBindings.defaults())
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		for boss_alive: bool in [false, true]:
			var value: Dictionary = sim.snapshot()
			value["boss_health"] = 100.0 if boss_alive else 0.0
			value["boss_max_health"] = 200.0 if boss_alive else 0.0
			_ui.update_hud(value)
			await _joy()
			await _settle()
			var boss: Control = _ui._hud["boss"]
			for key: String in ["dash", "pulse", "secondary", "hero"]:
				var skill: Control = _ui._hud[key]
				var expected_width: float = 106.0 if key == "dash" else 112.0
				_check(root.get_visible_rect().encloses(skill.get_global_rect()) and absf(skill.size.x - expected_width) <= 0.1 and skill.focus_mode == Control.FOCUS_NONE and (not boss_alive or not boss.get_global_rect().intersects(skill.get_global_rect())), "Device prompts retain the actual compact dash/Q/E/R widths and non-overlapping Boss layout in the scaled window")
			_ui.notify("设备提示不恢复战斗通知")
			_check(not _ui._toast.visible and not _ui._hud.has("bag_info") and _ui.find_child("HUDMapInfo", true, false) == null, "Device prompts leave the removed combat notification and lower-right descriptions absent")
	await _key(KEY_F13)
	root.size = Vector2i(1280, 720)

func _test_capture_isolation() -> void:
	_ui.show_title({})
	_ui._show_settings(false)
	_ui._show_controls(false)
	await _settle()
	var binding: Button = _button("Bind_dash")
	binding.grab_focus()
	await _key(KEY_ENTER)
	await _settle()
	_check(_ui._capture_action == "dash", "A real Enter starts the capture fixture before switching its prompt device")
	var focus: Control = root.gui_get_focus_owner()
	var before: String = _state_signature(_state)
	await _joy()
	_check(_kind() == "gamepad" and _ui._capture_action == "dash" and root.gui_get_focus_owner() == focus and _state_signature(_state) == before, "GUI-consumed gamepad input is observed without ending capture, moving focus or changing bindings")
	await _key(KEY_Q)
	_check(_kind() == "keyboard" and _ui._capture_action == "dash" and root.gui_get_focus_owner() == focus and _state_signature(_state) == before, "A refused conflicting keyboard input returns keyboard prompts while preserving capture and state")
	await _key(KEY_ESCAPE)
	_check(_ui._capture_action.is_empty() and _ui._overlay_mode == "controls_title", "Capture cancellation retains the existing controls-page semantics")
	_ui.show_title({})
	await _settle()

func _holding_signature(grid: Control) -> Array:
	var children: Array[int] = []
	for child: Node in grid.get_children():
		children.append(child.get_instance_id())
	return [grid.get_instance_id(), children, grid.held_uid, grid.selected_uid, grid.held_rotated, grid.cursor, grid._native_dragging, _ui._bag_held_uid, _ui._bag_held_rotated, _ui._bag_cursor, root.gui_get_focus_owner()]

func _test_backpack_prompts() -> void:
	_state = _new_state()
	_state.generate_shop()
	_ui.bind(_state)
	await _key(KEY_F13)
	_ui.show_shop()
	await _settle()
	var uid: int = int(_state.loadout[0]["uid"])
	_ui._bp_select(uid, _ui._shop_epoch)
	await _settle()
	var grid: Control = _ui._bag_grid
	var hint := _ui.find_child("BackpackHint", true, false) as Label
	var move: Button = _button("MoveBackpackItem")
	var rotate: Button = _button("RotateBackpackItem")
	_check(hint.text == "拖拽整理 · R旋转 · Esc取消" and rotate.text == "旋转 R" and move.tooltip_text.contains("Enter放置"), "A newly built keyboard backpack retains its established instructions")
	var before: String = _state_signature(_state)
	var focus: Control = root.gui_get_focus_owner()
	var identity: int = grid.get_instance_id()
	await _joy()
	_check(hint.text == "A拿起 · X旋转 · B取消" and rotate.text == "旋转 X" and move.tooltip_text.contains("A放置"), "An idle backpack shows concise controller actions and the matching rotation label")
	_check(_ui._bag_grid.get_instance_id() == identity and grid.held_uid < 0 and _state_signature(_state) == before and root.gui_get_focus_owner() == focus, "Idle prompt switching neither begins fake placement nor rebuilds inventory controls or moves focus")
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		await _settle()
		_check(root.get_visible_rect().encloses(hint.get_global_rect()) and hint.size.y + 0.1 >= hint.get_minimum_size().y and root.get_visible_rect().encloses(rotate.get_global_rect()), "The controller backpack hint and rotation action fit the actual scaled window")
	_ui._bp_pick_up(uid)
	await _settle()
	var held: Array = _holding_signature(grid)
	before = _state_signature(_state)
	await _key(KEY_F13)
	_check(_holding_signature(grid) == held and _state_signature(_state) == before and hint.text.contains("Enter") and hint.text.contains("R旋转"), "Returning to keyboard updates the current placement instructions without changing its held item, position or focus")
	await _joy()
	_check(_holding_signature(grid) == held and _state_signature(_state) == before and hint.text.contains("A") and hint.text.contains("X旋转") and hint.text.contains("B取消"), "Returning to gamepad preserves the held placement and shows its matching A/X/B actions")
	grid.cancel_placement()
	_ui._bp_hint("保留这条实际交易拒绝原因。", _ui._shop_epoch)
	await _key(KEY_F13)
	await _joy()
	_check(hint.text == "保留这条实际交易拒绝原因。" and grid.held_uid < 0, "An idle device switch never replaces a real transaction error with a fake placement or generic instruction")
	_ui.show_title({})
	await _settle()
	var inherited_gamepad: bool = _kind() == "gamepad" and _title_note() == null
	var inherited_bindings: Dictionary = _ui._controls.duplicate(true)
	var replacement_sim := CombatSim.new()
	replacement_sim.begin(_state)
	var ready_clocks: Array = [replacement_sim.dash_snapshot(), replacement_sim.pulse_snapshot()]
	_ui.show_hud()
	_ui.update_hud(replacement_sim.snapshot())
	await _settle()
	_check(inherited_gamepad and inherited_bindings == ControlBindings.defaults() and _ui._controls == inherited_bindings and (_ui._hud["dash_label"] as Label).text == "冲刺 · A" and (_ui._hud["pulse_label"] as Label).text == "空槽" and (_ui._hud["pulse_key"] as Label).text == "X" and (_ui._hud["secondary_key"] as Label).text == "Y" and ready_clocks == [replacement_sim.dash_snapshot(), replacement_sim.pulse_snapshot()], "A replacement screen inherits its device and bindings while preserving the real build's empty skill slots")
	await _key(KEY_F13)
	_check(_kind() == "keyboard" and _ui._controls == inherited_bindings and (_ui._hud["dash_label"] as Label).text == "冲刺 · 空格" and (_ui._hud["pulse_label"] as Label).text == "空槽" and (_ui._hud["pulse_key"] as Label).text == "Q" and (_ui._hud["secondary_key"] as Label).text == "E" and ready_clocks == [replacement_sim.dash_snapshot(), replacement_sim.pulse_snapshot()], "Keyboard activity updates empty-slot keys without granting a missing skill or changing its clock")
	root.size = Vector2i(1280, 720)
