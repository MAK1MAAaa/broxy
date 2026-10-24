extends SceneTree
## Real inventory transactions and GUI input exercise the grid-backed shop.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_ui = GameUI.new()
	root.add_child(_ui)
	await _test_keyboard_placement()
	await _test_failed_action_preserves_keyboard_placement()
	await _test_native_rotation_anchor_and_edge_merge()
	await _test_merge_and_runes()
	await _test_same_page_stale_details()
	await _test_capacity_expansion_and_sales()
	await _test_stale_actions_and_layout()
	print("BackpackUI: %d assertions, %d failures" % [_checks, _failures])
	_ui.queue_free()
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261024, "bone")
	state.gold = 10000
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	_check(state.buy_offer(0), "The fixture buys through the real backpack transaction: " + id)
	var items: Array = state.backpack_snapshot()["items"]
	return int(items.back()["uid"])

func _show(state: RunState) -> void:
	state.generate_shop()
	_ui.bind(state)
	_ui.show_shop()
	await _settle()

func _grid() -> Control:
	return _ui.find_child("BackpackGrid", true, false) as Control

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	root.push_input(event)
	await process_frame

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _test_keyboard_placement() -> void:
	var state: RunState = _state()
	_buy(state, "weapon", "frost")
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	_ui._bp_select(uid, _ui._shop_epoch)
	var move := _ui.find_child("MoveBackpackItem", true, false) as Button
	_check(move != null, "Selected boxes expose a keyboard-accessible move action")
	move.pressed.emit()
	await _settle()
	_check(_grid().held_uid == uid and root.gui_get_focus_owner() == _grid(), "Picking up moves focus to the grid instead of removing the item")
	await _key(KEY_R)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	var gold: int = state.gold
	await _key(KEY_ENTER)
	await _settle()
	var placed: Dictionary = state.backpack_item(uid)
	_check(placed["x"] == 0 and placed["y"] == 3 and placed["rotated"], "Arrow keys, R and Enter rotate the three-cell weapon into the final row")
	_check(state.gold == gold and _grid().held_uid < 0 and state.loadout[0]["uid"] == uid, "Manual placement changes neither money nor stable weapon identity/order")
	_ui._bp_select(uid, _ui._shop_epoch)
	_ui._bp_pick_up(uid)
	var before: String = JSON.stringify(state.backpack_snapshot())
	await _key(KEY_R)
	await _key(KEY_ENTER)
	_check(JSON.stringify(state.backpack_snapshot()) == before and _grid().held_uid == uid, "An invalid rotated footprint remains held without changing inventory")
	_check(str(_ui.find_child("BackpackHint", true, false).text).contains("超出"), "Invalid placement provides an explicit reason")
	await _key(KEY_ESCAPE)
	_check(_grid().held_uid < 0 and JSON.stringify(state.backpack_snapshot()) == before, "Esc cancels placement while keeping the original box intact")

func _test_merge_and_runes() -> void:
	var state: RunState = _state()
	var first: int = _buy(state, "relic", "damage")
	var second: int = _buy(state, "relic", "damage")
	var rune_first: int = _buy(state, "rune", "pierce")
	var rune_second: int = _buy(state, "rune", "pierce")
	await _show(state)
	_ui._bp_select(second, _ui._shop_epoch)
	var merge := _ui.find_child("MergeBackpackItem%d" % first, true, false) as Button
	_check(merge != null, "Same-name/same-rank boxes expose an explicit merge target")
	var gold: int = state.gold
	var damage: float = state.stat("damage")
	merge.pressed.emit()
	await _settle()
	_check(state.backpack_item(second).is_empty() and state.backpack_item(first)["rank"] == 2, "Manual merge consumes the selected source and promotes the target UID")
	_check(state.gold == gold and is_equal_approx(state.stat("damage"), damage), "Two relics become one rank-two box without charging or inventing attributes")
	_ui._bp_select(rune_second, _ui._shop_epoch)
	var grid: Control = _grid()
	grid.begin_placement(rune_second)
	var target: Dictionary = state.backpack_item(rune_first)
	var point := Vector2(int(target["x"]), int(target["y"])) * 50.0 + Vector2(10, 10)
	var payload: Dictionary = {"type": "embers_backpack", "uid": rune_second, "epoch": _ui._shop_epoch}
	_check(not grid.accept_drop(point, {"type": "embers_backpack", "uid": rune_second, "epoch": _ui._shop_epoch - 1}), "A native drop payload from an earlier shop page is rejected")
	_check(grid.accept_drop(point, payload) and grid.placement_at(Vector2i(target["x"], target["y"]))["kind"] == "merge", "Drop preview recognizes an intentional same-rune merge")
	grid.drop_at(point, payload)
	await _settle()
	_check(state.backpack_item(rune_first)["rank"] == 2 and state.backpack_item(rune_second).is_empty(), "The drop transaction preserves the promoted rune rank")
	_ui._bp_select(rune_first, _ui._shop_epoch)
	grid = _grid()
	grid.begin_placement(rune_first)
	var weapon: Dictionary = state.backpack_item(int(state.loadout[0]["uid"]))
	point = Vector2(int(weapon["x"]), int(weapon["y"])) * 50.0 + Vector2(10, 10)
	payload = {"type": "embers_backpack", "uid": rune_first, "epoch": _ui._shop_epoch}
	_check(grid.accept_drop(point, payload), "Loose runes can be dropped on a weapon instead of occupying another equipment list")
	grid.drop_at(point, payload)
	await _settle()
	_check(state.rune_bag.is_empty() and state.loadout[0]["rune"]["rank"] == 2, "Installing a promoted rune frees its cell and retains its rank")
	_ui._bp_select(int(state.loadout[0]["uid"]), _ui._shop_epoch)
	var detach := _ui.find_child("UnequipBackpackRune", true, false) as Button
	detach.pressed.emit()
	await _settle()
	_check(state.rune_bag.size() == 1 and state.rune_bag[0]["rank"] == 2 and state.loadout[0]["rune"].is_empty(), "Detach uses the real free-cell transaction and preserves the rune")

func _test_failed_action_preserves_keyboard_placement() -> void:
	var state: RunState = _state()
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	_ui._bp_select(uid, _ui._shop_epoch)
	_ui._bp_pick_up(uid)
	var sale := _ui.find_child("SellBackpackItem", true, false) as Button
	sale.grab_focus()
	var old_epoch: int = _ui._shop_epoch
	sale.pressed.emit()
	await _settle()
	_check(_ui._shop_epoch > old_epoch and not state.last_error.is_empty(), "A refused last-weapon sale exercises an actual failed transaction and shop rebuild")
	_check(_grid().held_uid == uid and root.gui_get_focus_owner() == _grid(), "Held placement regains grid focus instead of the stale failed action")
	await _key(KEY_DOWN)
	await _key(KEY_R)
	await _key(KEY_ENTER)
	await _settle()
	var placed: Dictionary = state.backpack_item(uid)
	_check(placed["x"] == 0 and placed["y"] == 1 and placed["rotated"] and _grid().held_uid < 0, "Keyboard placement can continue directly after the rejected transaction")

func _test_native_rotation_anchor_and_edge_merge() -> void:
	var state: RunState = _state()
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	_ui._bp_select(uid, _ui._shop_epoch)
	var grid: Control = _grid()
	_check(grid._native_grab_cell(Vector2(48, 48)) == Vector2i(1, 1) and grid._native_grab_cell(Vector2(47.9, 47.9)) == Vector2i.ZERO, "Native grab cells include the two-pixel box inset at cell boundaries")
	grid.begin_placement(uid)
	grid._native_dragging = true
	grid._grab_offset = grid._native_grab_cell(Vector2(20, 70))
	var point := Vector2(225, 75)
	var payload: Dictionary = {"type": "embers_backpack", "uid": uid, "epoch": _ui._shop_epoch}
	_check(grid.accept_drop(point, payload) and grid.cursor == Vector2i(4, 0), "A native grab from the second source cell follows the mouse's actual anchor")
	await _key(KEY_R)
	var ghost_origin: Vector2i = grid.cursor
	_check(ghost_origin == Vector2i(3, 1) and grid._grab_offset == Vector2i(1, 0), "Native R rotation keeps the grabbed cell under the stationary mouse")
	_check(grid.accept_drop(point, payload) and grid.cursor == ghost_origin, "Rechecking a drop at the same mouse point does not shift the rotated ghost")
	var edge_point := Vector2(25, 75)
	_check(not grid.accept_drop(edge_point, payload) and grid.cursor == Vector2i(-1, 1), "A rotated native source can retain its negative out-of-bounds origin without clamping the ghost")
	await _key(KEY_R)
	_check(grid.cursor == Vector2i(0, 0) and grid.accept_drop(edge_point, payload), "Rotating back restores the same anchored native source to a legal edge position")
	await _key(KEY_R)
	_check(grid.cursor == Vector2i(-1, 1) and not grid.accept_drop(edge_point, payload), "Native key handling preserves the invalid edge ghost until the mouse moves")
	_check(grid.accept_drop(point, payload) and grid.cursor == ghost_origin, "Moving the native drag back restores its previously valid ghost origin")
	grid.drop_at(point, payload)
	await _settle()
	var placed: Dictionary = state.backpack_item(uid)
	_check(placed["x"] == ghost_origin.x and placed["y"] == ghost_origin.y and placed["rotated"], "Native drop commits the exact origin previously shown by its rotated ghost")
	state = _state()
	var target_uid: int = int(state.loadout[0]["uid"])
	_check(state.move_item(target_uid, Vector2i(5, 0), false), "The edge-merge fixture moves its target through a legal transaction")
	var source_uid: int = _buy(state, "weapon", "bone")
	await _show(state)
	_ui._bp_select(source_uid, _ui._shop_epoch)
	await _settle()
	var merge_action := _ui.find_child("MergeBackpackItem%d" % target_uid, true, false) as Button
	var details := _ui.find_child("BackpackDetailsScroll", true, false) as ScrollContainer
	_check(merge_action != null and details.get_global_rect().encloses(merge_action.get_global_rect()), "A weapon's first merge action remains visible before long behavior descriptions at 720p")
	_check(_ui.find_child("BackpackWeaponStats", true, false) != null and not str(_ui.find_child("BackpackItemEffect", true, false).text).contains("每枚"), "Weapon details present their ranked damage and interval only once")
	grid = _grid()
	grid.begin_placement(source_uid)
	grid.rotate_held()
	grid.cursor = Vector2i(5, 0)
	var preview: Dictionary = grid.placement_at(grid.cursor)
	_check(preview.get("valid", false) and preview.get("kind", "") == "merge" and preview.get("target", -1) == target_uid, "An edge merge targets the surviving box before rejecting the source's rotated footprint")
	grid.commit_placement()
	await _settle()
	var target: Dictionary = state.backpack_item(target_uid)
	_check(state.backpack_item(source_uid).is_empty() and target["rank"] == 2 and target["x"] == 5 and not target["rotated"], "Edge merging preserves the target position and orientation instead of placing the source shape")

func _test_same_page_stale_details() -> void:
	var state: RunState = _state()
	var first: int = _buy(state, "relic", "damage")
	var second: int = _buy(state, "relic", "damage")
	var rune: int = _buy(state, "rune", "pierce")
	await _show(state)
	_ui._bp_select(second, _ui._shop_epoch)
	await _settle()
	var old_merge := _ui.find_child("MergeBackpackItem%d" % first, true, false) as Button
	var details_scroll := _ui.find_child("BackpackDetailsScroll", true, false) as ScrollContainer
	_check(old_merge != null and details_scroll.get_global_rect().encloses(old_merge.get_global_rect()), "The first merge action is visible in the initial 720p details viewport")
	var epoch: int = _ui._shop_epoch
	_ui._bp_select(int(state.loadout[0]["uid"]), epoch)
	var signature: String = JSON.stringify(state.backpack_snapshot())
	old_merge.pressed.emit()
	_check(_ui._shop_epoch == epoch and JSON.stringify(state.backpack_snapshot()) == signature, "A detached old merge button cannot consume its former source after same-page selection changes")
	_ui._bp_select(rune, epoch)
	await _settle()
	var old_equip: Button = _ui._shop_focus_button("bag_equip:%d" % int(state.loadout[0]["uid"]))
	_check(old_equip != null, "The selected loose rune provides an equip action")
	_ui._bp_select(first, epoch)
	signature = JSON.stringify(state.backpack_snapshot())
	old_equip.pressed.emit()
	_check(JSON.stringify(state.backpack_snapshot()) == signature and state.rune_index_for_uid(rune) >= 0, "A detached old equip button cannot install a rune after another source is selected")
	await _settle()

func _test_capacity_expansion_and_sales() -> void:
	var state: RunState = _state()
	var rune: int = _buy(state, "rune", "blast")
	_check(state.equip_rune(state.rune_index_for_uid(rune), 0), "The capacity fixture attaches a rune before filling its storage")
	var last_uid: int = -1
	for count: int in 40:
		state.offers = [{"kind": "relic", "id": "armor", "price": 1, "sold": false}]
		if not state.purchase_error(0).is_empty():
			break
		_check(state.buy_offer(0), "A one-cell relic fills a real available cell")
		last_uid = int((state.backpack_snapshot()["items"] as Array).back()["uid"])
	await _show(state)
	_check(state.backpack_snapshot()["used_cells"] == state.backpack_snapshot()["total_cells"], "The fixture reaches the real full-grid condition")
	var weapon_uid: int = int(state.loadout[0]["uid"])
	_ui._bp_select(weapon_uid, _ui._shop_epoch)
	var signature: String = JSON.stringify(state.backpack_snapshot())
	var detach := _ui.find_child("UnequipBackpackRune", true, false) as Button
	detach.pressed.emit()
	await _settle()
	_check(JSON.stringify(state.backpack_snapshot()) == signature and state.rune_bag.is_empty(), "Full-grid detachment refuses without losing or replacing a box")
	var expansion := _ui.find_child("ExpandBackpack", true, false) as Button
	var gold: int = state.gold
	expansion.pressed.emit()
	await _settle()
	_check(state.backpack_snapshot()["height"] == 5 and state.gold == gold - 32, "The first expansion pays the advertised cost and unlocks one row")
	_ui._bp_select(weapon_uid, _ui._shop_epoch)
	detach = _ui.find_child("UnequipBackpackRune", true, false) as Button
	detach.pressed.emit()
	await _settle()
	_check(state.rune_bag.size() == 1, "The same detach succeeds after real space is purchased")
	_ui._bp_select(last_uid, _ui._shop_epoch)
	var sale := _ui.find_child("SellBackpackItem", true, false) as Button
	sale.pressed.emit()
	await _settle()
	_check(state.backpack_item(last_uid).is_empty(), "Relics can be sold from the unified inventory")
	_ui._bp_select(weapon_uid, _ui._shop_epoch)
	gold = state.gold
	sale = _ui.find_child("SellBackpackItem", true, false) as Button
	sale.pressed.emit()
	await _settle()
	_check(not state.backpack_item(weapon_uid).is_empty() and state.gold == gold, "The shop cannot sell away its last weapon")

func _test_stale_actions_and_layout() -> void:
	var state: RunState = _state()
	_check(state.expand_backpack() and state.expand_backpack(), "The layout fixture legally unlocks the full six-row backpack")
	for index: int in 9:
		_buy(state, "weapon", "bone")
	await _show(state)
	var old_epoch: int = _ui._shop_epoch
	var uid: int = int(state.loadout[0]["uid"])
	var before: String = JSON.stringify(state.backpack_snapshot())
	_ui._reroll()
	await _settle()
	_ui._bp_move(uid, Vector2i(4, 0), false, old_epoch)
	_check(JSON.stringify(state.backpack_snapshot()) == before, "A stale placement callback cannot move the new shop's live inventory")
	var panel := _ui.find_child("BackpackPanel", true, false) as Control
	var scroll := _ui.find_child("BackpackDetailsScroll", true, false) as ScrollContainer
	_check(panel != null and _enclosed(panel) and _enclosed(_grid()) and _enclosed(scroll), "The full six-row grid and scrollable details remain inside the 720p viewport")
	_ui.show_hud()
	_ui.update_hud({"loadout": state.loadout, "health": state.health, "max_health": state.stat("max_health")})
	await _settle()
	_check(_ui.find_child("AdditionalWeapons", true, false) != null and str(_ui._hud["bag_info"].text).contains("10件"), "HUD reports all ten active weapons instead of keeping a false four-slot cap")
	_ui.show_result(false, "背包排版固定验证", {})
	await _settle()
	_check(_ui.find_child("ResultBuildScroll", true, false) != null and _enclosed(_ui.find_child("ResultBuildScroll", true, false)), "Long ranked builds remain in a bounded result scroll area")
	var gold: int = state.gold
	_ui._bp_expand()
	_check(state.gold == gold, "Backpack actions are rejected outside the shop")

func _enclosed(control: Control) -> bool:
	var rect: Rect2 = control.get_global_rect()
	return rect.position.x >= -0.1 and rect.position.y >= -0.1 and rect.end.x <= 1280.1 and rect.end.y <= 720.1
