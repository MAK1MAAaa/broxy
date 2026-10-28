extends SceneTree
## Real shoulder input reads natural inventory content without moving focus or changing transactions.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const FIXTURE = preload("res://tools/preview_gamepad_reading.gd")
const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0
var _app: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	_app.sound.set_volume(0.0)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = size
		await _test_modal_reading()
		await _test_backpack_and_result()
	root.size = Vector2i(1280, 720)
	await _test_disabled_contexts()
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile), "Shoulder-button reading and its diagnostic fixtures leave the personal profile unchanged")
	paused = false
	_app.queue_free()
	await _settle()
	print("GamepadReading: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _joy(button: int, down: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = down
	_send(event)
	await process_frame
	if down:
		event = event.duplicate() as InputEventJoypadButton
		event.pressed = false
		_send(event)
	await _settle()

func _key(code: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		_send(event)
		await process_frame
	await _settle()

func _mouse(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	_send(event)
	await _settle()

func _motion(point: Vector2, relative: Vector2, down: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_send(event)
	await _settle()

func _action(id: String) -> Button:
	for node: Node in _app.ui.find_children("*", "Button", true, false):
		if str(node.get_meta("shop_focus_id", "")) == id:
			return node as Button
	return null

func _text_button(text: String) -> Button:
	for node: Node in _app.ui.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.text == text:
			return button
	return null

func _activate(button: Button) -> void:
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "The intended reading action is a real visible enabled button")
	if button == null:
		return
	button.grab_focus()
	await _joy(JOY_BUTTON_A)

func _scroll(name: String) -> ScrollContainer:
	return _app.ui.find_child(name, true, false) as ScrollContainer

func _limit(scroll: ScrollContainer) -> int:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	return maxi(0, int(bar.max_value - bar.page))

func _signature() -> Array:
	return [_app.run.summary(), _app.run.offers.duplicate(true), _app.run.rng.state, _app.run.rng.seed, _app.world.sim.snapshot(), _app.world.dash_evasion_feedback_snapshot(), _app.world.pulse_feedback_snapshot(), _app.store.controls.duplicate(true)]

func _show_shop() -> void:
	paused = false
	_app.paused = false
	var state: RunState = FIXTURE.make_fixture()
	_check(state != null, "The long reading fixture constructs all items through priced purchases and valid merges")
	if state == null:
		return
	_check(state.loadout.size() == 10 and state.rune_bag.size() == 1 and int(state.rune_bag[0]["rank"]) == 3 and int(state.backpack_snapshot()["used_cells"]) == 34, "Ten actual weapons, a rank-III loose rune and a physical relic form the legal 34-cell reading build")
	_app.run = state
	_app.ui.bind(state)
	_app.screen = MAIN_SCRIPT.Screen.SHOP
	_app.world.begin(state)
	_app.world.set_physics_process(false)
	_app.world.sim.sandbox = true
	_app.world.sim._cooldowns.fill(9999.0)
	_app.world.sim.step(STEP, Vector2.ZERO, true, true)
	_app.world.stop()
	_app.ui.show_shop()
	await _settle()
	_check(float(_app.world.sim.dash_snapshot()["cooldown_left"]) > 0.0 and float(_app.world.sim.pulse_snapshot()["cooldown_left"]) > 0.0, "Reading invariants include real already-started positive skill cooldowns")

func _exercise(scroll: ScrollContainer, require_overflow: bool, lower: ScrollContainer = null) -> void:
	_check(scroll != null and scroll.is_visible_in_tree(), "The active page exposes its real reading viewport")
	if scroll == null:
		return
	await _key(KEY_F6)
	var initial_guide: Label = (_app.ui._overlay if not _app.ui._overlay_mode.is_empty() else _app.ui._page).find_child("ReadingGuide", true, false) as Label
	var initial_focus: Control = root.gui_get_focus_owner()
	var initial_signature: Array = _signature()
	scroll.scroll_vertical = mini(17, _limit(scroll))
	await _settle()
	var initial_position: int = scroll.scroll_vertical
	var direct := InputEventJoypadButton.new()
	direct.device = 0
	direct.button_index = JOY_BUTTON_RIGHT_SHOULDER
	direct.pressed = true
	_send(direct)
	_check(initial_guide != null and initial_guide.text.contains("LB / RB") and root.gui_get_focus_owner() == initial_focus and scroll.scroll_vertical == mini(initial_position + maxi(1, int(scroll.size.y * 0.8)), _limit(scroll)), "One direct RB press from keyboard mode switches the existing guide and pages from the already-read position without moving focus")
	direct = direct.duplicate() as InputEventJoypadButton
	direct.pressed = false
	_send(direct)
	await _settle()
	_check(_signature() == initial_signature, "The direct keyboard-to-shoulder reading path cannot modify inventory, RNG or live cooldown values")
	scroll.scroll_vertical = 0
	await _settle()
	var limit: int = _limit(scroll)
	var exact_limit: float = maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
	_check(limit > 0 if require_overflow else limit >= 0, "Natural purchased content provides overflow where the reading scenario requires it")
	var focus: Control = root.gui_get_focus_owner()
	var before: Array = _signature()
	var lower_position: int = lower.scroll_vertical if lower != null else 0
	var page: int = maxi(1, int(scroll.size.y * 0.8))
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scroll.scroll_vertical == mini(page, limit), "RB advances exactly eighty percent of the actual viewport, bounded by its content")
	_check(root.gui_get_focus_owner() == focus, "Shoulder paging keeps the existing focused action")
	var after_press: int = scroll.scroll_vertical
	await _joy(JOY_BUTTON_RIGHT_SHOULDER, false)
	_check(scroll.scroll_vertical == after_press, "A released shoulder button never turns another page")
	for turn: int in 32:
		if is_equal_approx(scroll.get_v_scroll_bar().value, exact_limit):
			break
		await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scroll.scroll_vertical == limit and is_equal_approx(scroll.get_v_scroll_bar().value, exact_limit), "Repeated RB presses reach the real final content line, including fractional scrollbar limits")
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	_check(scroll.scroll_vertical == limit, "RB at the tail cannot overscroll")
	for turn: int in 32:
		if scroll.scroll_vertical == 0:
			break
		await _joy(JOY_BUTTON_LEFT_SHOULDER)
	_check(scroll.scroll_vertical == 0, "Repeated LB presses return to the content header")
	await _joy(JOY_BUTTON_LEFT_SHOULDER)
	_check(scroll.scroll_vertical == 0 and root.gui_get_focus_owner() == focus, "LB at the header remains bounded and preserves focus")
	_check(_signature() == before, "Reading pages preserve inventory, UID projections, money, RNG, bindings and positive skill clocks")
	_check(lower == null or lower.scroll_vertical == lower_position, "A top-level reading modal never scrolls the backpack underneath")
	_check(root.get_visible_rect().grow(1).encloses(scroll.get_global_rect()) and scroll.get_child(0).get_combined_minimum_size().x <= scroll.size.x + 1.0, "The actual reading viewport and its content width fit the scaled window")
	var surface: Control = _app.ui._overlay if not _app.ui._overlay_mode.is_empty() else _app.ui._page
	var guide := surface.find_child("ReadingGuide", true, false) as Label
	_check(guide != null and guide.text.contains("LB / RB") and root.get_visible_rect().grow(1).encloses(guide.get_global_rect()), "The active shoulder-reading guide remains visible inside either window size")

func _test_modal_reading() -> void:
	await _show_shop()
	var lower: ScrollContainer = _scroll("BackpackDetailsScroll")
	await _activate(_action("compare:0"))
	_check(_app.ui._overlay_mode == "relic_comparison", "Actual A confirmation opens the relic comparison")
	await _exercise(_scroll("ComparisonScroll"), true, lower)
	await _test_keyboard_pages(_scroll("ComparisonScroll"))
	await _joy(JOY_BUTTON_B)
	await _activate(_action("bag:%d" % int(_app.run.rune_bag[0]["uid"])))
	await _activate(_action("rune_preview:9"))
	_check(_app.ui._overlay_mode == "rune_equip_comparison", "A real rank-III loose-rune action opens its returning-weapon comparison")
	await _exercise(_scroll("RuneEquipScroll"), true, lower)
	await _test_keyboard_pages(_scroll("RuneEquipScroll"))
	await _joy(JOY_BUTTON_B)
	await _activate(_action("rogue"))
	_check(_app.ui._overlay_mode == "rogue_choices", "A real shop button opens the secret-art choices")
	await _exercise(_scroll("RogueChoicesScroll"), false, lower)
	await _test_keyboard_pages(_scroll("RogueChoicesScroll"))
	await _joy(JOY_BUTTON_B)

func _test_keyboard_pages(scroll: ScrollContainer) -> void:
	var before: Array = _signature()
	scroll.grab_focus()
	scroll.scroll_vertical = 0
	await _settle()
	await _key(KEY_PAGEDOWN)
	_check(scroll.scroll_vertical > 0 if _limit(scroll) > 0 else scroll.scroll_vertical == 0, "The existing focused PageDown path still reads the same real content")
	await _key(KEY_PAGEUP)
	_check(scroll.scroll_vertical == 0 and _signature() == before, "The existing PageUp path returns to the header without a transaction")

func _test_backpack_and_result() -> void:
	await _show_shop()
	await _activate(_action("bag:%d" % int(_app.run.rune_bag[0]["uid"])))
	var rune_guide := _app.ui.find_child("RuneGuide", true, false) as Label
	_check(rune_guide != null and rune_guide.is_visible_in_tree(), "The six-row shop reading fixture keeps the real selected loose-rune guide visible")
	var outside: Button = _action("reroll")
	if outside != null:
		outside.grab_focus()
	await _settle()
	_check(_controls_fit(_app.ui._page), "The full six-row shop, selected loose-rune guide and actual controls fit the physical window")
	await _exercise(_scroll("BackpackDetailsScroll"), true)
	var result_state: RunState = FIXTURE.make_result_fixture()
	_check(result_state != null, "The tight result fixture legally purchases all eight weapon families and records real collision damage")
	if result_state == null:
		return
	_check(result_state.loadout.size() == 8 and result_state.damage_dealt_by_weapon.size() == 8 and not result_state.last_hit.is_empty() and int(result_state.backpack_snapshot()["used_cells"]) == 36, "Eight real damage sources, the final hit and an exactly full backpack coexist in the result layout")
	_app.run = result_state
	_app.ui.bind(result_state)
	_app.screen = MAIN_SCRIPT.Screen.RESULT
	_app.ui.show_result(false, "实际购买构筑的结算阅读验证。", {})
	await _settle()
	_check(_controls_fit(_app.ui._page), "Eight actual damage contributions, last hit, reading guide and result actions fit the physical window")
	await _exercise(_scroll("ResultBuildScroll"), false)
	for name: String in ["LastHit", "DamageContribution"]:
		var control := _app.ui.find_child(name, true, false) as Control
		_check(control != null and root.get_visible_rect().grow(1).encloses(control.get_global_rect()), "The result retains its last-hit and eight-source contribution areas inside either physical window size")
	for caption: String in ["再次试炼", "返回主菜单"]:
		var button: Button = _text_button(caption)
		_check(button != null and root.get_visible_rect().grow(1).encloses(button.get_global_rect()), "Result reading never pushes its actual restart or return action outside the window")

func _test_disabled_contexts() -> void:
	await _show_shop()
	var rune_uid: int = int(_app.run.rune_bag[0]["uid"])
	await _activate(_action("bag:%d" % rune_uid))
	await _activate(_action("bag_move:%d" % rune_uid))
	var details: ScrollContainer = _scroll("BackpackDetailsScroll")
	var before: Array = _signature()
	var position: int = details.scroll_vertical
	var held: int = _app.ui._bag_grid.held_uid
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	await _joy(JOY_BUTTON_LEFT_SHOULDER)
	_check(held > 0 and _app.ui._bag_grid.held_uid == held and details.scroll_vertical == position and _signature() == before, "Shoulders cannot scroll details or move/commit a manually held item")
	await _joy(JOY_BUTTON_B)
	await _show_shop()
	if DisplayServer.get_name() != "headless":
		rune_uid = int(_app.run.rune_bag[0]["uid"])
		await _activate(_action("bag:%d" % rune_uid))
		var item := _app.ui.find_child("BackpackItem%d" % rune_uid, true, false) as Button
		_check(item != null, "The native drag fixture uses the actual purchased item button")
		if item != null:
			var point: Vector2 = item.get_global_rect().get_center()
			await _motion(point, Vector2.ZERO, false)
			await _mouse(point, true)
			await _motion(point + Vector2(24, 12), Vector2(24, 12), true)
			_check(root.gui_is_dragging(), "A parsed mouse gesture starts a real engine GUI drag")
			details = _scroll("BackpackDetailsScroll")
			position = details.scroll_vertical
			before = _signature()
			await _joy(JOY_BUTTON_RIGHT_SHOULDER)
			await _joy(JOY_BUTTON_LEFT_SHOULDER)
			_check(root.gui_is_dragging() and details.scroll_vertical == position and _signature() == before, "Shoulders leave a native GUI drag and its underlying reading position untouched")
			await _motion(Vector2(5, 5), Vector2.ZERO, true)
			await _mouse(Vector2(5, 5), false)
	_app._title()
	await _settle()
	await _activate(_text_button("设置"))
	await _activate(_app.ui.find_child("ControlsSettings", true, false) as Button)
	await _activate(_app.ui.find_child("Bind_dash", true, false) as Button)
	var bindings: Dictionary = _app.store.controls.duplicate(true)
	var focus: Control = root.gui_get_focus_owner()
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	await _joy(JOY_BUTTON_LEFT_SHOULDER)
	_check(_app.ui.find_child("ControlsPanel", true, false) != null and _app.store.controls == bindings and root.gui_get_focus_owner() == focus, "Captured shoulder events cannot bind a keyboard action, leave settings or move focus")
	await _joy(JOY_BUTTON_B)
	_app._begin_run("bone", 20261028)
	_app.world.set_physics_process(false)
	_app.world.sim.sandbox = true
	_app.world.sim._cooldowns.fill(9999.0)
	before = _signature()
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	await _joy(JOY_BUTTON_LEFT_SHOULDER)
	_check(_signature() == before and not _app.world._dash_pending and not _app.world._pulse_pending, "Combat shoulder input cannot create reading actions or queue either skill")

func _controls_fit(node: Node) -> bool:
	if node is ScrollContainer:
		return root.get_visible_rect().grow(1).encloses(node.get_global_rect())
	if node is Control and node.is_visible_in_tree() and (node is Button or node is Label):
		if not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
			return false
		if node.size.y + 1.0 < node.get_combined_minimum_size().y or node.size.x + 1.0 < node.get_combined_minimum_size().x:
			return false
	for child: Node in node.get_children():
		if not _controls_fit(child):
			return false
	return true
