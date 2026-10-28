extends SceneTree
## One initial focus setup; every subsequent step uses actual input without selecting or refocusing items.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
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
	root.size = Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	_app.sound.set_volume(0.0)
	await _test_continuous_move()
	await _test_cancel_loop()
	await _test_merge_loop()
	await _test_rune_loop()
	await _test_direct_detail_actions()
	await _test_unequip_and_sales()
	await _test_expansion_focus()
	await _test_modal_and_screen_guards()
	await _test_same_frame_new_screen()
	await _test_old_epoch_new_shop()
	await _test_cancel_reentrancy()
	if DisplayServer.get_name() != "headless":
		await _test_native_drag_focus()
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile), "Continuous inventory input leaves the personal profile unchanged")
	paused = false
	_app.queue_free()
	await _settle()
	print("BackpackFocus: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

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

func _key(code: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await _settle()

func _new_state(expanded: bool = true) -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone")
	state.collect_souls(1000)
	if expanded:
		_check(state.expand_backpack() and state.expand_backpack(), "The focus fixture pays for its real six-row backpack")
	state.pending_upgrades = 0
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	var wallet: int = state.gold
	state.offers.assign([{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}])
	_check(state.buy_offer(0) and state.gold == wallet - state.shop_price(definition), "The focus fixture acquires its real paid inventory source: " + id)
	return uid

func _show(state: RunState) -> void:
	paused = false
	_app.paused = false
	state.generate_shop()
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

func _grid() -> BackpackGrid:
	return _app.ui.find_child("BackpackGrid", true, false) as BackpackGrid

func _action(id: String) -> Button:
	for node: Node in _app.ui.find_children("*", "Button", true, false):
		if str(node.get_meta("shop_focus_id", "")) == id:
			return node as Button
	return null

func _initial_focus(uid: int) -> void:
	await _initial_action(uid, "bag_move:%d" % uid)

func _initial_action(uid: int, id: String) -> void:
	_app.ui._bp_select(uid, _app.ui._shop_epoch)
	var action: Button = _action(id)
	_check(action != null, "The initially selected item exposes its intended actual action")
	if action != null:
		action.grab_focus()
	await _settle()

func _move_focus(uid: int) -> bool:
	var move: Button = _action("bag_move:%d" % uid)
	return move != null and root.gui_get_focus_owner() == move and int(_app.ui._bag_selected_uid) == uid and _grid().selected_uid == uid and _grid().held_uid < 0

func _held(uid: int) -> bool:
	return _grid().held_uid == uid and root.gui_get_focus_owner() == _grid()

func _stable_state() -> Array:
	return [_app.run.backpack_snapshot(), _app.run.loadout.duplicate(true), _app.run.gold, _app.run.rng.state, _app.run.rng.seed, _app.world.sim.dash_snapshot(), _app.world.sim.pulse_snapshot(), _app.world.sim.elapsed]

func _test_continuous_move() -> void:
	var state: RunState = _new_state()
	_buy(state, "weapon", "frost")
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	await _initial_focus(uid)
	await _joy(JOY_BUTTON_A)
	_check(_held(uid), "Initial A picks up the source and transfers focus to the grid")
	var gold: int = state.gold
	var rng: int = state.rng.state
	for step: int in 3:
		await _joy(JOY_BUTTON_DPAD_DOWN)
	await _joy(JOY_BUTTON_A)
	var placed: Dictionary = state.backpack_item(uid)
	_check(int(placed["x"]) == 0 and int(placed["y"]) == 3 and state.gold == gold and state.rng.state == rng, "A places the same paid source at the requested legal cell without shopping or rolling")
	_check(_move_focus(uid), "After placement the surviving selected item owns pickup focus instead of a stock card")
	await _joy(JOY_BUTTON_A)
	_check(_held(uid), "The very next A picks the placed item up again without a test selecting or refocusing it")
	for step: int in 3:
		await _joy(JOY_BUTTON_DPAD_UP)
	await _joy(JOY_BUTTON_A)
	placed = state.backpack_item(uid)
	_check(int(placed["x"]) == 0 and int(placed["y"]) == 0 and _move_focus(uid), "A second uninterrupted move returns the same identity to the header and restores its pickup focus")

func _test_cancel_loop() -> void:
	var state: RunState = _new_state()
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	await _initial_focus(uid)
	var before: Array = _stable_state()
	await _joy(JOY_BUTTON_A)
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	await _joy(JOY_BUTTON_B)
	_check(_move_focus(uid) and _stable_state() == before and _cancel_hint(), "B cancels manual holding back to pickup focus, keeps its cancellation hint and preserves inventory/clocks")
	await _joy(JOY_BUTTON_A)
	_check(_held(uid), "A can pick the same item up immediately after B cancellation")
	await _key(KEY_ESCAPE)
	_check(_move_focus(uid) and _stable_state() == before and _cancel_hint(), "Escape cancellation preserves the selected-item pickup focus and the same cancellation hint as B")
	await _key(KEY_ENTER)
	_check(_held(uid), "The existing keyboard accept key can also restart pickup without a focus repair")
	for step: int in 5:
		await _joy(JOY_BUTTON_DPAD_DOWN)
	var cursor: Vector2i = _grid().cursor
	await _joy(JOY_BUTTON_A)
	_check(_held(uid) and _grid().cursor == cursor and _stable_state() == before, "An invalid placement retains the held grid, cursor and exact economic state")
	await _joy(JOY_BUTTON_B)
	_check(_move_focus(uid), "Canceling after a refused placement restores the original pickup action")

func _test_merge_loop() -> void:
	var state: RunState = _new_state()
	var target: int = int(state.loadout[0]["uid"])
	var source: int = _buy(state, "weapon", "bone")
	await _show(state)
	await _initial_focus(source)
	await _joy(JOY_BUTTON_A)
	await _joy(JOY_BUTTON_DPAD_LEFT)
	await _joy(JOY_BUTTON_A)
	_check(state.backpack_item(source).is_empty() and int(state.backpack_item(target)["rank"]) == 2, "An uninterrupted held-item A confirmation performs the intended same-rank merge")
	_check(_move_focus(target), "After source consumption the merge target remains selected with pickup focus")
	await _joy(JOY_BUTTON_A)
	_check(_held(target), "The next A organizes the actual upgraded target rather than a removed source or stock offer")
	await _joy(JOY_BUTTON_B)
	_check(_move_focus(target), "Canceling the merged target preserves its continuous pickup focus")

func _test_rune_loop() -> void:
	var state: RunState = _new_state()
	var target: int = _buy(state, "weapon", "frost")
	var source: int = _buy(state, "rune", "pierce")
	await _show(state)
	await _initial_focus(source)
	await _joy(JOY_BUTTON_A)
	await _joy(JOY_BUTTON_DPAD_LEFT)
	await _joy(JOY_BUTTON_A)
	_check(state.backpack_item(source).is_empty() and int(state.backpack_item(target)["rune"].get("uid", -1)) == source, "A installs the paid held rune into the intended non-first weapon")
	_check(_move_focus(target) and int(_app.ui._selected_rune) == -1, "Consuming a loose rune selects its actual weapon target and focuses that weapon's pickup action")
	await _joy(JOY_BUTTON_A)
	_check(_held(target), "The next A picks up the equipped target without selecting the starter or a stock card")
	await _joy(JOY_BUTTON_B)
	_check(_move_focus(target), "Canceling the equipped weapon returns to that same target pickup action")

func _test_direct_detail_actions() -> void:
	var state: RunState = _new_state()
	var target: int = int(state.loadout[0]["uid"])
	var source: int = _buy(state, "weapon", "bone")
	await _show(state)
	await _initial_action(source, "bag_merge:%d" % target)
	await _joy(JOY_BUTTON_A)
	_check(state.backpack_item(source).is_empty() and int(state.backpack_item(target)["rank"]) == 2 and _move_focus(target), "The direct detail merge button selects and focuses the surviving target pickup action")
	await _joy(JOY_BUTTON_A)
	_check(_held(target), "The next A continues organizing after a direct detail merge")
	await _joy(JOY_BUTTON_B)
	state = _new_state()
	target = _buy(state, "weapon", "frost")
	source = _buy(state, "rune", "pierce")
	await _show(state)
	await _initial_action(source, "bag_equip:%d" % target)
	await _joy(JOY_BUTTON_A)
	_check(state.backpack_item(source).is_empty() and int(state.backpack_item(target)["rune"].get("uid", -1)) == source and _move_focus(target), "The direct detail install button selects the actual non-first weapon and its pickup action")
	await _joy(JOY_BUTTON_A)
	_check(_held(target), "The next A continues organizing after a direct rune installation")
	await _joy(JOY_BUTTON_B)

func _test_unequip_and_sales() -> void:
	var state: RunState = _new_state()
	var target: int = _buy(state, "weapon", "frost")
	var rune: int = _buy(state, "rune", "pierce")
	_check(state.equip_rune(state.rune_index_for_uid(rune), state.weapon_index_for_uid(target)), "The detach fixture formally installs its purchased rune")
	await _show(state)
	await _initial_action(target, "bag_unequip:%d" % target)
	await _joy(JOY_BUTTON_A)
	_check((state.backpack_item(target)["rune"] as Dictionary).is_empty() and state.rune_index_for_uid(rune) >= 0 and _move_focus(target), "Detaching retains the original weapon selection and pickup focus rather than its sale button")
	await _joy(JOY_BUTTON_A)
	_check(_held(target), "A immediately picks the same weapon up after detaching its rune")
	await _joy(JOY_BUTTON_B)
	state = _new_state()
	var sold: int = _buy(state, "weapon", "frost")
	var successor: int = _buy(state, "weapon", "ember")
	await _show(state)
	await _initial_action(sold, "bag_sell:%d" % sold)
	var wallet: int = state.gold
	var refund: int = int(floorf(float(state.backpack_item(sold)["paid"]) * 0.5))
	await _joy(JOY_BUTTON_A)
	_check(state.backpack_item(sold).is_empty() and state.gold == wallet + refund and _selected_item_focus(successor), "Selling a middle item selects its real successor and leaves focus within that item's inventory controls")
	state = _new_state()
	sold = _buy(state, "weapon", "frost")
	var predecessor: int = int(state.loadout[0]["uid"])
	await _show(state)
	await _initial_action(sold, "bag_sell:%d" % sold)
	await _joy(JOY_BUTTON_A)
	_check(state.backpack_item(sold).is_empty() and _selected_item_focus(predecessor), "Selling the final UID selects its existing predecessor rather than a shop offer")
	state = _new_state()
	sold = _buy(state, "weapon", "frost")
	rune = _buy(state, "rune", "pierce")
	_check(state.equip_rune(state.rune_index_for_uid(rune), state.weapon_index_for_uid(sold)), "The sale-return fixture formally equips the last paid weapon")
	await _show(state)
	await _initial_action(sold, "bag_sell:%d" % sold)
	await _joy(JOY_BUTTON_A)
	_check(state.backpack_item(sold).is_empty() and state.rune_index_for_uid(rune) >= 0 and _selected_item_focus(rune) and int(_app.ui._selected_rune) == state.rune_index_for_uid(rune), "A sold weapon's returned rune participates in the post-sale list and owns the original list position's inventory focus")
	state = _new_state()
	target = int(state.loadout[0]["uid"])
	await _show(state)
	await _initial_action(target, "bag_sell:%d" % target)
	var before: Array = _stable_state()
	await _joy(JOY_BUTTON_A)
	_check(_stable_state() == before and root.gui_get_focus_owner() == _action("bag_sell:%d" % target), "A refused last-weapon sale keeps the original sale action and exact inventory state")

func _selected_item_focus(uid: int) -> bool:
	var focus: Control = root.gui_get_focus_owner()
	return focus != null and int(_app.ui._bag_selected_uid) == uid and _grid().selected_uid == uid and str(focus.get_meta("shop_focus_id", "")) in ["bag:%d" % uid, "bag_move:%d" % uid]

func _cancel_hint() -> bool:
	var hint := _app.ui.find_child("BackpackHint", true, false) as Label
	return hint != null and hint.text.contains("已取消")

func _test_expansion_focus() -> void:
	var state: RunState = _new_state(false)
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	await _initial_action(uid, "bag_expand")
	await _joy(JOY_BUTTON_A)
	_check(int(state.backpack_snapshot()["height"]) == 5 and root.gui_get_focus_owner() == _action("bag_expand"), "A paid expansion keeps the still-enabled expansion action focused")
	await _joy(JOY_BUTTON_A)
	_check(int(state.backpack_snapshot()["height"]) == 6 and _move_focus(uid), "Reaching maximum expansion falls back to the selected item's pickup action")
	await _joy(JOY_BUTTON_A)
	_check(_held(uid), "A continues into manual organization after maximum expansion")
	await _joy(JOY_BUTTON_B)
	state = _new_state(false)
	await _show(state)
	uid = int(state.loadout[0]["uid"])
	await _initial_focus(uid)
	await _joy(JOY_BUTTON_A)
	var cursor: Vector2i = _grid().cursor
	var expand: Button = _action("bag_expand")
	_check(expand != null, "A held-item expansion uses the actual visible expansion button")
	if expand != null:
		await _click(expand.get_global_rect().get_center())
	_check(int(state.backpack_snapshot()["height"]) == 5 and _held(uid) and _grid().cursor == cursor, "Clicking expansion during manual holding rebuilds the grid without losing the held source or grid focus")
	await _joy(JOY_BUTTON_A)
	_check(_move_focus(uid), "The preserved held item can still be placed with the next A after expansion")

func _test_modal_and_screen_guards() -> void:
	var state: RunState = _new_state()
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	await _initial_focus(uid)
	await _joy(JOY_BUTTON_A)
	var rogue: Button = _action("rogue")
	_check(rogue != null, "The modal race uses the actual shop secret-art button")
	if rogue != null:
		await _click(rogue.get_global_rect().get_center())
	var focus: Control = root.gui_get_focus_owner()
	await _settle()
	_check(_app.ui._overlay_mode == "rogue_choices" and focus != null and _app.ui._overlay.is_ancestor_of(focus) and root.gui_get_focus_owner() == focus, "Opening a real modal while holding cancels its preview without an old pickup callback stealing modal focus")
	await _joy(JOY_BUTTON_B)
	_check(_move_focus(uid), "Returning from the modal restores the original held source's pickup action")
	await _joy(JOY_BUTTON_A)
	var before: Array = _stable_state()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	rogue = _action("rogue")
	if is_instance_valid(rogue):
		rogue.pressed.emit()
	await _settle()
	focus = root.gui_get_focus_owner()
	_check(_app.ui._overlay_mode == "rogue_choices" and focus != null and _app.ui._overlay.is_ancestor_of(focus) and _stable_state() == before, "A same-frame cancel followed by a real modal callback preserves modal focus and inventory")
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await _joy(JOY_BUTTON_B)
	_check(root.gui_get_focus_owner() == _action("rogue") and _grid().held_uid < 0, "A modal opened after explicit cancellation returns to its actual Rogue button source, without reviving holding")

func _test_same_frame_new_screen() -> void:
	var state: RunState = _new_state()
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	await _initial_focus(uid)
	await _joy(JOY_BUTTON_A)
	var accept := InputEventJoypadButton.new()
	accept.device = 0
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	Input.parse_input_event(accept)
	Input.flush_buffered_events()
	_app._title()
	await _settle()
	var focus: Control = root.gui_get_focus_owner()
	_check(_app.screen == MAIN_SCRIPT.Screen.TITLE and focus != null and _app.ui._page.is_ancestor_of(focus) and _action("bag_move:%d" % uid) == null, "A completed transaction's old epoch cannot rebuild or steal focus from a same-frame new title screen")
	await _settle()
	_check(root.gui_get_focus_owner() == focus, "Delayed old inventory work leaves the new screen's focus stable")
	accept = accept.duplicate() as InputEventJoypadButton
	accept.pressed = false
	Input.parse_input_event(accept)

func _test_cancel_reentrancy() -> void:
	var state: RunState = _new_state()
	var next: int = _buy(state, "weapon", "frost")
	await _show(state)
	var original: int = int(state.loadout[0]["uid"])
	await _initial_focus(original)
	await _joy(JOY_BUTTON_A)
	var grid: BackpackGrid = _grid()
	var switched: Array[bool] = [false]
	grid.holding_changed.connect(func(uid: int, _rotated: bool, _cell: Vector2i) -> void:
		if uid < 0 and not switched[0]:
			switched[0] = true
			grid.select_item(next)
			grid.begin_placement(next))
	await _joy(JOY_BUTTON_B)
	_check(switched[0] and _held(next) and int(_app.ui._bag_selected_uid) == next, "A reentrant holding listener starting a new source cannot have its grid focus stolen by the older cancellation request")

func _test_old_epoch_new_shop() -> void:
	var old_state: RunState = _new_state()
	var old_uid: int = _buy(old_state, "weapon", "frost")
	await _show(old_state)
	var old_epoch: int = _app.ui._shop_epoch
	var focus_id: String = "bag:%d" % old_uid
	var delayed_restore: Callable = _app.ui._restore_shop_focus.bind(focus_id, old_epoch)
	var new_state: RunState = _new_state()
	var new_uid: int = _buy(new_state, "weapon", "frost")
	await _show(new_state)
	var focus: Control = root.gui_get_focus_owner()
	var before: Array = _stable_state()
	_check(new_uid == old_uid and _app.ui._shop_epoch != old_epoch and _action(focus_id) != null and _action(focus_id) != focus, "The new shop contains a valid same-UID stale target distinct from its real current focus")
	delayed_restore.call_deferred()
	await _settle()
	_check(root.gui_get_focus_owner() == focus and _stable_state() == before and _app.screen == MAIN_SCRIPT.Screen.SHOP, "An actual restore callable carrying an old epoch cannot steal focus within a newer shop or alter its state")

func _click(point: Vector2) -> void:
	for down: bool in [true, false]:
		await _sync_native_mouse(point)
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await _settle()

func _motion(point: Vector2, down: bool) -> void:
	var previous: Vector2 = root.get_mouse_position()
	await _sync_native_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - previous
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _settle()

func _sync_native_mouse(point: Vector2) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.warp_mouse(point)
	await process_frame
	await _settle()
	_check(root.get_mouse_position().distance_to(point) <= 1.1, "Engine-warped software mouse position agrees with the parsed event within desktop pixel precision; no physical-input claim")

func _start_drag(uid: int) -> bool:
	var button := _app.ui.find_child("BackpackItem%d" % uid, true, false) as Button
	_check(button != null, "A native drag starts from the actual paid item button")
	if button == null:
		return false
	var point: Vector2 = button.get_global_rect().get_center()
	await _motion(point, false)
	await _sync_native_mouse(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _settle()
	await _motion(point + Vector2(24, 12), true)
	_check(root.gui_is_dragging(), "The mouse gesture activates the engine's native GUI drag")
	return root.gui_is_dragging()

func _test_native_drag_focus() -> void:
	print("NATIVE_MOUSE_MODE engine_warp_plus_parsed_software_events; no physical mouse input")
	var state: RunState = _new_state()
	var uid: int = _buy(state, "weapon", "frost")
	await _show(state)
	await _initial_focus(uid)
	if await _start_drag(uid):
		var cell := Vector2i(2, 2)
		var point: Vector2 = _grid().global_position + (Vector2(cell + _grid()._grab_offset) + Vector2(0.5, 0.5)) * BackpackGrid.CELL
		await _motion(point, true)
		var grid: BackpackGrid = _grid()
		var mouse: Vector2 = root.get_mouse_position()
		var bounds: Rect2 = grid.get_global_rect()
		print("NATIVE_DROP_BEFORE_RELEASE ", JSON.stringify({"uid": uid, "cursor": [grid.cursor.x, grid.cursor.y], "drop_target_cell": [grid._drop_target_cell.x, grid._drop_target_cell.y], "grab_offset": [grid._grab_offset.x, grid._grab_offset.y], "placement": grid.placement_at(grid.cursor), "native_dragging": grid._native_dragging, "gui_is_dragging": root.gui_is_dragging(), "mouse_position": [mouse.x, mouse.y], "release_point": [point.x, point.y], "grid_rect": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]}))
		await _sync_native_mouse(point)
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _settle()
		var item: Dictionary = state.backpack_item(uid)
		var moved: bool = int(item["x"]) == cell.x and int(item["y"]) == cell.y and _grid().held_uid < 0 and not root.gui_is_dragging()
		var focused: bool = int(_app.ui._bag_selected_uid) == uid and root.gui_get_focus_owner() == _action("bag:%d" % uid)
		if not moved or not focused:
			var focus: Control = root.gui_get_focus_owner()
			print("NATIVE_DROP_DIAGNOSTIC ", JSON.stringify({"uid": uid, "expected_cell": [cell.x, cell.y], "item_cell": [item.get("x", -1), item.get("y", -1)], "held_uid": _grid().held_uid, "gui_is_dragging": root.gui_is_dragging(), "selected_uid": _app.ui._bag_selected_uid, "grid_selected_uid": _grid().selected_uid, "focus": focus.name if focus != null else "", "focus_id": focus.get_meta("shop_focus_id", "") if focus != null else "", "requested_focus": _app.ui._requested_shop_focus}))
		_check(moved, "The real native mouse release commits the intended cell and ends both holding and the engine drag")
		_check(focused, "A successful native mouse transaction focuses its surviving item box without entering manual pickup")
		var before: Array = _stable_state()
		await _joy(JOY_BUTTON_A)
		_check(_grid().held_uid < 0 and _stable_state() == before, "Mouse-drop focus preserves item selection semantics instead of making A pick it up automatically")
	state = _new_state()
	uid = _buy(state, "weapon", "frost")
	await _show(state)
	await _initial_focus(uid)
	if await _start_drag(uid):
		var before: Array = _stable_state()
		await _motion(Vector2(5, 5), true)
		await _sync_native_mouse(Vector2(5, 5))
		var event := InputEventMouseButton.new()
		event.position = Vector2(5, 5)
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		var focus: Control = root.gui_get_focus_owner()
		await _settle()
		_check(not root.gui_is_dragging() and _grid().held_uid < 0 and _stable_state() == before, "An aborted native drop preserves the original inventory and cancels its held preview")
		_check(root.gui_get_focus_owner() == focus and root.gui_get_focus_owner() != _action("bag_move:%d" % uid), "Aborting a native drag does not schedule a new manual pickup focus request")
