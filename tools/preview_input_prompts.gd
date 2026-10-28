extends SceneTree
## Fixed Main input hints, actual GUI drag and no personal profile IO.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const CASES: PackedStringArray = ["keyboard", "gamepad", "keyboard_return", "paused", "backpack", "drag", "interactive"]
const STEP: float = 1.0 / 60.0
var _app: Node
var _case: String = "gamepad"
var _output: String = "res://reports/input-prompts/gamepad.png"
var _hold: bool = false
var _drag_active: bool = false

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			_case = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			_output = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			_hold = true
		else:
			_invalid()
			return
	if DisplayServer.get_name() == "headless" or _case not in CASES or not _output.to_lower().ends_with(".png"):
		_invalid()
		return
	root.size = Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	_app.sound.set_volume(0.0)
	_app.ui.set_selected_arena("mire")
	var bindings: Dictionary = ControlBindings.defaults()
	bindings["dash"] = KEY_F
	bindings["pulse"] = KEY_R
	_app._controls_changed(bindings)
	_app._begin_run("bone", 20261028)
	if _app.run.backpack.add("skill", "pulse").is_empty():
		_fail("The input preview could not place its pulse skill box")
		return
	_app.run._sync_backpack_projection()
	_app.world.set_physics_process(false)
	_app.world.sim.sandbox = true
	_app.world.sim._cooldowns.fill(9999.0)
	_app.ui.update_hud(_app.world.hud_snapshot())
	_app.ui.get_node("InputDeviceTracker").device_changed.connect(func(_kind: String, _device: int) -> void:
		print("PROMPT_DEVICE ", JSON.stringify(_summary())))
	await _settle()
	if _case in ["backpack", "drag"]:
		_app.world.sim.sandbox = false
		_app.world.sim.elapsed = _app.world.sim.duration - STEP * 0.5
		_app.world._physics_process(STEP)
		await _settle()
		if _app.screen != MAIN_SCRIPT.Screen.SHOP:
			_fail("The real completed wave did not reach the shop")
			return
		_app.run.gold = 500
		_app.run.generate_shop()
		_app.ui.show_shop()
		await _settle()
		var uid: int = int(_app.run.loadout[0]["uid"])
		_app.ui._bp_select(uid, _app.ui._shop_epoch)
		await _settle()
		if _case == "backpack":
			var pickup: Button = _app.ui._shop_focus_button("bag_move:%d" % uid)
			if pickup == null:
				_fail("Missing real inventory pickup button")
				return
			pickup.grab_focus()
			await _joy(JOY_BUTTON_A)
			await _joy(JOY_BUTTON_DPAD_RIGHT)
		else:
			var button := _app.ui.find_child("BackpackItem%d" % uid, true, false) as Button
			if button == null:
				_fail("Missing actual draggable item")
				return
			var point: Vector2 = button.get_global_rect().get_center()
			await _motion(point, Vector2.ZERO, false)
			await _mouse(point, true)
			await _motion(point + Vector2(24, 12), Vector2(24, 12), true)
			await _settle()
			_drag_active = root.gui_is_dragging()
			if not _drag_active:
				_fail("The parsed mouse gesture did not start an engine GUI drag")
				return
			var target: Vector2 = _app.ui._bag_grid.global_position + Vector2(2.5, 1.5) * BackpackGrid.CELL
			await _motion(target, target - point, true)
			var before: Dictionary = _app.run.backpack_snapshot()
			await _joy(JOY_BUTTON_Y)
			if _app.run.backpack_snapshot() != before or not _app.ui._bag_grid._native_preview_label.text.contains("松手确认"):
				_fail("Input-device hints changed a native drag's real inventory or release wording")
				return
	elif _case != "keyboard":
		await _joy(JOY_BUTTON_Y)
		if _case == "keyboard_return":
			await _key(KEY_F6)
		elif _case == "paused":
			_app._pause()
			var frozen: Array = [_app.world.sim.snapshot(), _app.world.pulse_feedback_snapshot()]
			await _key(KEY_F6)
			await _joy(JOY_BUTTON_Y)
			if frozen != [_app.world.sim.snapshot(), _app.world.pulse_feedback_snapshot()]:
				_fail("Prompt switching progressed the paused simulation")
				return
	await _settle()
	root.title = "秘术余烬 · 输入提示验证 / %s（固定场景，不保存档案）" % _case
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(_output)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var summary: Dictionary = _summary()
	summary["case"] = _case
	summary["capture_result"] = result
	summary["engine_native_drag"] = _drag_active
	summary["synthetic_gamepad_events"] = _case != "keyboard"
	print("PROMPT_PREVIEW ", JSON.stringify(summary))
	if _drag_active:
		await _motion(Vector2(320, 600), Vector2.ZERO, true)
		await _mouse(Vector2(320, 600), false)
	if result != OK or not _hold:
		_app._quit_game(0 if result == OK else 1)

func _summary() -> Dictionary:
	var label_dash: Label = null
	var label_pulse: Label = null
	if _app.ui._screen == "hud":
		label_dash = _app.ui._hud.get("dash_label") as Label
		label_pulse = _app.ui._hud.get("pulse_label") as Label
	var hint := _app.ui.find_child("BackpackHint", true, false) as Label
	return {"device": _app.ui.input_device_snapshot(), "bindings": _app.store.controls,
		"persistent_profile": _app.store.persistent, "connected_gamepads": Array(Input.get_connected_joypads()),
		"screen": _app.screen, "paused": paused, "dash_label": label_dash.text if is_instance_valid(label_dash) else "",
		"pulse_label": label_pulse.text if is_instance_valid(label_pulse) else "", "backpack_hint": hint.text if hint != null else "",
		"dash": _app.world.sim.dash_snapshot(), "pulse": _app.world.sim.pulse_snapshot(), "backpack": _app.run.backpack_snapshot()}

func _joy(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _motion(point: Vector2, relative: Vector2, left: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if left else 0
	Input.parse_input_event(event)
	await process_frame

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _fail(message: String) -> void:
	push_error(message)
	_app._quit_game(1)

func _invalid() -> void:
	push_error("Use native --case=keyboard|gamepad|keyboard_return|paused|backpack|drag|interactive [--capture=path.png] [--hold]")
	quit(2)
