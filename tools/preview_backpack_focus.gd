extends SceneTree
## One initial focus setup followed by an uninterrupted parsed-input organization loop.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const CASES: PackedStringArray = ["move", "merge", "rune", "cancel"]

var _app: Node

static func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	state.offers.assign([{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}])
	return uid if state.buy_offer(0) else -1

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var case_name: String = "move"
	var output: String = ""
	var hold: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			hold = true
		else:
			quit(2)
			return
	if DisplayServer.get_name() == "headless" or case_name not in CASES or (not output.is_empty() and not output.to_lower().ends_with(".png")):
		push_error("Use native --case=move|merge|rune|cancel [--capture=path.png] [--hold]")
		quit(2)
		return
	if output.is_empty():
		output = "res://reports/backpack-focus/%s.png" % case_name
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	_app.sound.set_volume(0.0)
	_app.world.stop()
	_app.world.set_physics_process(false)
	var state := RunState.new()
	state.begin(20261028, "bone")
	state.collect_souls(1000)
	if not state.expand_backpack() or not state.expand_backpack():
		_fail("The focus preview could not purchase backpack expansion")
		return
	state.pending_upgrades = 0
	var target: int = int(state.loadout[0]["uid"])
	var source: int = target
	if case_name == "merge":
		source = _buy(state, "weapon", "bone")
	elif case_name == "rune":
		target = _buy(state, "weapon", "frost")
		source = _buy(state, "rune", "pierce")
	elif case_name == "move":
		if _buy(state, "weapon", "frost") < 0:
			_fail("The focus preview could not purchase its neighboring weapon")
			return
	if source < 0 or target < 0:
		_fail("The focus preview could not purchase its actual transaction source")
		return
	state.generate_shop()
	_app.run = state
	_app.ui.bind(state)
	_app.screen = MAIN_SCRIPT.Screen.SHOP
	_app.ui.show_shop()
	await _settle()
	_app.ui._bp_select(source, _app.ui._shop_epoch)
	var pickup: Button = _action("bag_move:%d" % source)
	if pickup == null:
		_fail("The initially selected source has no pickup action")
		return
	pickup.grab_focus()
	await _settle()
	var wallet: int = state.gold
	var rng: int = state.rng.state
	await _joy(JOY_BUTTON_A)
	if case_name == "move":
		for step: int in 3:
			await _joy(JOY_BUTTON_DPAD_DOWN)
		await _joy(JOY_BUTTON_A)
	elif case_name == "cancel":
		await _joy(JOY_BUTTON_DPAD_RIGHT)
		await _joy(JOY_BUTTON_B)
	else:
		await _joy(JOY_BUTTON_DPAD_LEFT)
		await _joy(JOY_BUTTON_A)
	var result_uid: int = source if case_name in ["move", "cancel"] else target
	var result: Dictionary = state.backpack_item(result_uid)
	var valid_result: bool = not result.is_empty() and int(_app.ui._bag_selected_uid) == result_uid
	if case_name == "move":
		valid_result = valid_result and int(result.get("x", -1)) == 0 and int(result.get("y", -1)) == 3
	elif case_name == "merge":
		valid_result = valid_result and state.backpack_item(source).is_empty() and int(result.get("rank", 0)) == 2
	elif case_name == "rune":
		valid_result = valid_result and state.backpack_item(source).is_empty() and int((result.get("rune", {}) as Dictionary).get("uid", -1)) == source
	var continued: bool = false
	if valid_result:
		await _joy(JOY_BUTTON_A)
		continued = _app.ui._bag_grid.held_uid == result_uid and root.gui_get_focus_owner() == _app.ui._bag_grid
		if continued:
			await _joy(JOY_BUTTON_B)
	var focus: Control = root.gui_get_focus_owner()
	var passed: bool = valid_result and continued and focus == _action("bag_move:%d" % result_uid) and state.gold == wallet and state.rng.state == rng
	var before_wait: Dictionary = state.backpack_snapshot()
	if not _app.ui._toast_timer.is_stopped():
		await _app.ui._toast_timer.timeout
	await _settle()
	passed = passed and state.backpack_snapshot() == before_wait and state.gold == wallet and state.rng.state == rng and root.gui_get_focus_owner() == focus and not _app.ui._toast.visible
	root.title = "秘术余烬 · 连续背包整理 / %s（固定流程，不保存档案）" % case_name
	await _settle()
	await RenderingServer.frame_post_draw
	var capture: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	if capture == OK:
		capture = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	var hint := _app.ui.find_child("BackpackHint", true, false) as Label
	print("BACKPACK_FOCUS_PREVIEW ", JSON.stringify({"case": case_name, "capture_result": capture, "fixture_passed": passed, "persistent_profile": false, "synthetic_gamepad_events": true, "connected_gamepads": Input.get_connected_joypads(), "source_uid": source, "result_uid": result_uid, "selected_uid": _app.ui._bag_selected_uid, "held_uid": _app.ui._bag_grid.held_uid, "focus": focus.name if focus != null else "", "focus_id": focus.get_meta("shop_focus_id", "") if focus != null else "", "continued_without_focus_repair": continued, "backpack_hint": hint.text if hint != null else "", "backpack": state.backpack_snapshot(), "wallet_unchanged": state.gold == wallet, "rng_unchanged": state.rng.state == rng, "toast_visible": _app.ui._toast.visible, "toast_timer_stopped": _app.ui._toast_timer.is_stopped()}))
	if not hold or capture != OK or not passed:
		_app._quit_game(0 if capture == OK and passed else 1)

func _action(id: String) -> Button:
	for node: Node in _app.ui.find_children("*", "Button", true, false):
		if str(node.get_meta("shop_focus_id", "")) == id:
			return node as Button
	return null

func _joy(button: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await _settle()

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _fail(message: String) -> void:
	push_error(message)
	_app._quit_game(1)
