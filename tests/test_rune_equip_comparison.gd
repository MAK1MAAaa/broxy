extends SceneTree
## Real input exercises per-weapon rune facts, read-only previews and swap identity.

class EscapeRouter:
	extends Node
	var ui: GameUI

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and ui.handle_back():
			get_viewport().set_input_as_handled()

var _checks: int = 0
var _failures: int = 0
var _next_waves: int = 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	root.size = Vector2i(1280, 720)
	var ui := GameUI.new()
	root.add_child(ui)
	var escape := EscapeRouter.new()
	escape.ui = ui
	root.add_child(escape)
	ui.next_wave_requested.connect(func() -> void: _next_waves += 1)
	await _test_crescent_blast(ui)
	await _test_bounce_and_full_swap(ui)
	await _test_volley(ui)
	await _test_epoch_and_selection(ui)
	ui.queue_free()
	escape.queue_free()
	await _settle()
	print("RuneEquipComparison: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _show_selected(ui: GameUI, state: RunState) -> void:
	ui.bind(state)
	ui.show_shop()
	await _settle()
	var source: Button = ui._shop_focus_button("bag:%d" % int(state.rune_bag[0]["uid"]))
	_check(source != null, "Formal purchases expose the incoming rune in the reserve")
	if source != null:
		source.grab_focus()
		_key(KEY_ENTER)
		await _settle()
	_check(ui._selected_rune == 0, "Real ui_accept selects the incoming reserve rune")


func _make_state(case_name: String) -> RunState:
	var state := RunState.new()
	state.begin(20261025, "bone")
	state.gold = 4000
	_check(state.expand_backpack() and state.expand_backpack(), "Rune preview fixtures purchase all thirty-six storage cells")
	for id: String in ["crescent", "storm", "scatter"]:
		_purchase(state, "weapon", id)
	for slot: int in 4:
		if slot == 1 and case_name == "crescent-blast":
			continue
		var id: String = "blast" if slot == 1 else "bounce" if slot == 3 else "pierce"
		_purchase(state, "rune", id)
		_check(state.equip_rune(0, slot), "The rune preview fixture formally equips its purchased socket rune")
	var incoming: String = "blast" if case_name in ["crescent-blast", "volley"] else "bounce"
	for id: String in [incoming, "pierce", "blast", "bounce"]:
		_purchase(state, "rune", id)
	for id: String in ["damage", "haste", "speed", "vitality", "armor", "magnet", "moon_charm", "pilgrim", "bulwark", "armor"]:
		_purchase(state, "relic", id)
	_check(state.backpack_snapshot()["used_cells"] == 36, "Four shaped weapon boxes, four loose runes and thirteen relic cells form a legal full grid")
	state.gold = 120
	state.wave = 4
	state.offers.clear()
	for entry: Array in [["weapon", "crescent"], ["rune", "blast"], ["relic", "hourglass"], ["relic", "moon_charm"]]:
		var definition: ContentDef = BackpackInventory.definition(str(entry[0]), str(entry[1]))
		state.offers.append({"kind": str(entry[0]), "id": definition.id, "price": definition.price, "sold": false})
	return state


func _purchase(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	var purchased: bool = state.buy_offer(0)
	_check(purchased, "The rune comparison fixture obtains its physical box through a real purchase: " + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1 if purchased else -1


func _open(ui: GameUI, slot: int) -> Button:
	var source: Button = ui._shop_focus_button("rune_preview:%d" % slot)
	_check(source != null, "A selected rune exposes the weapon-specific preview action: %d" % slot)
	if source != null:
		source.grab_focus()
		_key(KEY_ENTER)
		await _settle()
	return source


func _test_crescent_blast(ui: GameUI) -> void:
	var state: RunState = _make_state("crescent-blast")
	_check(state.loadout.size() == 4 and state.rune_bag.size() == 4 and state.backpack_snapshot()["used_cells"] == state.backpack_snapshot()["total_cells"], "Legal purchases create a genuinely full grid for the 720p rune preview fixture")
	if state == null:
		return
	await _show_selected(ui, state)
	for slot: int in 4:
		var equip: Button = ui._shop_focus_button("bag_equip:%d" % int(state.loadout[slot]["uid"]))
		var preview: Button = ui._shop_focus_button("rune_preview:%d" % slot)
		_check(equip != null and preview != null and equip.get_parent() == preview.get_parent() and preview.get_parent().size.y <= 44.1, "Direct equip and preview share a compact row inside backpack details: %d" % slot)
	_check(_buttons_inside(ui._page), "All full-build shop buttons remain inside 1280x720 with rune preview actions")
	var guide: Label = ui.find_child("RuneGuide", true, false)
	_check(guide != null and guide.text.contains(GameCatalog.rune("blast").display_name) and guide.tooltip_text.contains(ui._rune_rank_text("blast", 1)), "The selected loose rune shows its identity and preserves current-rank rules in its contextual tooltip")
	var before: String = _signature(state)
	var inventory: String = _inventory_signature(state)
	var incoming: Dictionary = state.rune_bag[0].duplicate(true)
	var source: Button = await _open(ui, 1)
	_check(ui._overlay_mode == "rune_equip_comparison" and ui._selected_rune == 0, "Real ui_accept opens a read-only preview without clearing the selected rune")
	var trigger: Label = ui.find_child("RuneEquipTrigger", true, false)
	var delayed: Label = ui.find_child("RuneEquipDelayedBlast", true, false)
	var blast: Label = ui.find_child("RuneEquipBlast", true, false)
	var exclusions: Label = ui.find_child("RuneEquipBlastExclusions", true, false)
	_check(trigger != null and trigger.text.contains("第2次直接命中") and trigger.text.contains("第1次"), "Moon-scythe rune timing comes from its second direct hit")
	_check(delayed != null and delayed.text.contains("只命中1个目标不会爆破"), "A single moon-scythe target is explicitly insufficient to trigger blast")
	_check(blast != null and blast.text.contains("半径 68") and blast.text.contains("55%"), "The blast radius and damage ratio use the production preview facts")
	_check(exclusions != null and exclusions.text.contains("已经直接命中") and exclusions.text.contains("不再承受") and exclusions.text.contains("不会再次触发"), "Blast explains its prior-hit exclusions and nonrecursive secondary damage")
	var capacity: Label = ui.find_child("RuneEquipBag", true, false)
	_check(capacity != null and capacity.text.contains("4 → 3件") and capacity.text.contains("不额外占格"), "An empty socket projects the real four-to-three loose-rune count and freed cell")
	_check(_signature(state) == before, "Reading all rune facts preserves state, RNG, stock, UIDs and purchase values")
	ui._shop_focus_button("bag_equip:%d" % int(state.loadout[1]["uid"])).pressed.emit()
	ui._shop_focus_button("next_wave").pressed.emit()
	await _settle()
	_check(_signature(state) == before and _next_waves == 0, "Underlying direct equip and next-wave callbacks are isolated by the preview")
	var scroll: ScrollContainer = ui.find_child("RuneEquipScroll", true, false)
	var close: Button = ui.find_child("CloseRuneEquipComparison", true, false)
	_check(scroll != null and close != null and root.get_visible_rect().encloses(scroll.get_global_rect()) and root.get_visible_rect().encloses(close.get_global_rect()), "The full moon-scythe details and return action stay bounded inside 720p")
	for press: int in 4:
		_key(KEY_TAB)
		await process_frame
		_check(_overlay_owns_focus(ui), "Tab stays inside the rune preview")
	if scroll != null:
		var content: Control = scroll.get_child(0)
		var scope: Label = ui.find_child("RuneEquipScope", true, false)
		var original_minimum: Vector2 = content.custom_minimum_size
		var original_range: float = maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
		scroll.grab_focus()
		_key(KEY_PAGEDOWN)
		await _settle()
		_check(scroll.scroll_vertical > 0 if original_range > 0.0 else scope != null and scroll.get_global_rect().encloses(scope.get_global_rect()), "Real rule text is fully reachable, including when it already fits without scrolling")
		content.custom_minimum_size.y = scroll.size.y * 2.0
		await _settle()
		_key(KEY_PAGEDOWN)
		await _settle()
		_check(scroll.scroll_vertical > 0, "Real keyboard PageDown scrolls an explicitly overflowing content fixture")
		content.custom_minimum_size = original_minimum
		await _settle()
		_check(scroll.scroll_vertical <= ceili(original_range), "Restoring the actual rule content clamps the temporary scroll offset")
	if close != null:
		close.grab_focus()
		_key(KEY_ENTER)
		await _settle()
	_check(ui._overlay_mode.is_empty() and root.gui_get_focus_owner() == source and ui._selected_rune == 0, "Real ui_accept returns to the exact source and retains rune selection")
	await _open(ui, 1)
	_key(KEY_ESCAPE)
	await _settle()
	_check(ui._overlay_mode.is_empty() and root.gui_get_focus_owner() == source, "Escape also restores the original weapon preview focus")
	var equip: Button = ui._shop_focus_button("bag_equip:%d" % int(state.loadout[1]["uid"]))
	equip.grab_focus()
	_key(KEY_ENTER)
	await _settle()
	_check(ui._overlay_mode.is_empty() and state.rune_bag.size() == 3 and ui._selected_rune == -1 and state.backpack_snapshot()["used_cells"] == 35, "Direct equip immediately frees its actual backpack cell after closing preview")
	_check(state.loadout[1]["rune"] == incoming and _inventory_signature(state) == inventory, "Equipping an empty socket preserves every rune UID and original paid value")


func _test_bounce_and_full_swap(ui: GameUI) -> void:
	var state: RunState = _make_state("full-swap")
	await _show_selected(ui, state)
	var inventory: String = _inventory_signature(state)
	var incoming: Dictionary = state.rune_bag[0].duplicate(true)
	var returned: Dictionary = state.loadout[1]["rune"].duplicate(true)
	var before: String = _signature(state)
	await _open(ui, 1)
	var sequence: Label = ui.find_child("RuneEquipBounceScales", true, false)
	_check(sequence != null and sequence.text.contains("100% → 100% → 75% → 56.25%"), "Moon-scythe bounce preserves both full-damage native hits before its decay sequence")
	var capacity: Label = ui.find_child("RuneEquipBag", true, false)
	var returns: Label = ui.find_child("RuneEquipReturn", true, false)
	_check(capacity != null and capacity.text.contains("4 → 4件"), "Replacing a socket in the full grid projects four loose runes before and after")
	_check(returns != null and returns.text.contains(GameCatalog.rune(str(returned["id"])).display_name) and returns.text.contains("腾出的格子") and returns.text.contains("保留阶级与原购买价值"), "The preview identifies the previous rune and preserves its rank and purchase value")
	_check(_signature(state) == before, "A full-bag replacement preview remains pure")
	_key(KEY_ESCAPE)
	await _settle()
	ui._shop_focus_button("bag_equip:%d" % int(state.loadout[1]["uid"])).grab_focus()
	_key(KEY_ENTER)
	await _settle()
	_check(state.loadout[1]["rune"] == incoming and state.rune_bag.has(returned) and state.rune_bag.size() == 4 and state.backpack_snapshot()["used_cells"] == 36, "The immediate real swap conserves all thirty-six occupied cells and returns the original rune")
	_check(_inventory_signature(state) == inventory, "The full-bag swap conserves all UID, id and paid tuples")


func _test_volley(ui: GameUI) -> void:
	var state: RunState = _make_state("volley")
	await _show_selected(ui, state)
	var source: Button = ui._shop_focus_button("rune_preview:2")
	source.grab_focus()
	await _settle()
	var details: ScrollContainer = ui.find_child("BackpackDetailsScroll", true, false)
	_check(details != null and details.get_global_rect().grow(1).encloses(source.get_global_rect()), "Keyboard focus brings the mouse preview source into the visible backpack details viewport")
	_click(source)
	await _settle()
	_check(ui._overlay_mode == "rune_equip_comparison", "A mouse click opens the same weapon preview")
	var trigger: Label = ui.find_child("RuneEquipTrigger", true, false)
	var targets: Label = ui.find_child("RuneEquipTargets", true, false)
	var independent: Label = ui.find_child("RuneEquipIndependent", true, false)
	_check(trigger != null and trigger.text.contains("第1次直接命中"), "The storm lantern activates its selected rune on the first direct hit")
	_check(targets != null and targets.text.contains("每次发射 2 枚"), "The storm lantern preview reports its true two-projectile volley")
	_check(independent != null and independent.text.contains("分别记录与排重") and independent.text.contains("独立触发"), "Multishot explains per-projectile exclusions and independent rune triggers")
	_key(KEY_ESCAPE)
	await _settle()
	await _open(ui, 3)
	targets = ui.find_child("RuneEquipTargets", true, false)
	_check(targets != null and targets.text.contains("每次发射 3 枚"), "Scatter reports three independent projectiles without promising a combined hit count")
	var scope: Label = ui.find_child("RuneEquipScope", true, false)
	_check(scope != null and scope.text.contains("足够实际目标") and scope.text.contains("不代表实战DPS"), "Theoretical limits require actual targets and are not a DPS promise")
	_key(KEY_ESCAPE)
	await _settle()


func _test_epoch_and_selection(ui: GameUI) -> void:
	var state: RunState = _make_state("full-swap")
	await _show_selected(ui, state)
	var old_source: Button = ui._shop_focus_button("rune_preview:1")
	var old_action: Callable = old_source.pressed.get_connections()[0]["callable"]
	ui._build_shop()
	old_action.call()
	_check(ui._overlay_mode.is_empty(), "A preview callback from an old shop epoch cannot address a rebuilt slot")
	await _settle()
	var source: Button = ui._shop_focus_button("rune_preview:1")
	var original_uid: int = int(state.rune_bag[0]["uid"])
	state.rune_bag[0]["uid"] = original_uid + 10000
	source.pressed.emit()
	_check(ui._overlay_mode.is_empty(), "A changed incoming UID invalidates a preview even without a shop rebuild")
	state.rune_bag[0]["uid"] = original_uid
	var original_paid: int = int(state.rune_bag[0]["paid"])
	state.rune_bag[0]["paid"] = original_paid + 1
	source.pressed.emit()
	_check(ui._overlay_mode.is_empty(), "The incoming rune snapshot also protects its original paid value")
	state.rune_bag[0]["paid"] = original_paid
	var socket_uid: int = int(state.loadout[1]["rune"]["uid"])
	state.loadout[1]["rune"]["uid"] = socket_uid + 10000
	source.pressed.emit()
	_check(ui._overlay_mode.is_empty(), "Changed socket contents invalidate the old preview callback")
	state.loadout[1]["rune"]["uid"] = socket_uid
	ui._selected_rune = 1
	source.pressed.emit()
	_check(ui._overlay_mode.is_empty(), "Selecting another reserve UID rejects the former rune preview")
	ui._selected_rune = 0
	await _open(ui, 1)
	var close: Button = ui.find_child("CloseRuneEquipComparison", true, false)
	var stale_close: Callable = close.pressed.get_connections()[0]["callable"]
	state.collect_souls(1)
	_check(ui._overlay_mode.is_empty(), "A real state change closes the stale rune preview immediately")
	await _settle()
	await _open(ui, 1)
	stale_close.call()
	_check(ui._overlay_mode == "rune_equip_comparison", "An old close callback cannot dismiss a later preview epoch")
	ui._build_shop()
	_check(ui._overlay_mode.is_empty() and ui._selected_rune == 0, "A direct shop rebuild closes rune preview while preserving a valid selection")
	await _settle()
	var relic: Button = ui._shop_focus_button("compare:2")
	relic.grab_focus()
	_key(KEY_ENTER)
	await _settle()
	_check(ui._overlay_mode == "relic_comparison", "Relic comparison remains available while a reserve rune is selected")
	state.collect_souls(1)
	_check(ui._overlay_mode.is_empty(), "The shared lifecycle also invalidates stale relic comparisons")
	await _settle()


func _buttons_inside(node: Node) -> bool:
	if node is ScrollContainer and node.is_visible_in_tree() and not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
		return false
	if node is Button and node.is_visible_in_tree() and not _inside_scroll(node) and not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
		return false
	for child: Node in node.get_children():
		if not _buttons_inside(child):
			return false
	return true


func _inside_scroll(node: Node) -> bool:
	var ancestor: Node = node.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return true
		ancestor = ancestor.get_parent()
	return false


func _overlay_owns_focus(ui: GameUI) -> bool:
	var owner: Control = root.gui_get_focus_owner()
	return owner != null and ui._overlay.is_ancestor_of(owner)


static func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, state.rng.state, state.last_error, state._next_rune_uid])


static func _inventory_signature(state: RunState) -> String:
	var runes: Array[Dictionary] = state.rune_bag.duplicate(true)
	for weapon: Dictionary in state.loadout:
		var rune: Dictionary = weapon.get("rune", {})
		if not rune.is_empty():
			runes.append(rune.duplicate(true))
	runes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left["uid"]) < int(right["uid"]))
	return JSON.stringify(runes)


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, false)


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event, false)


func _settle() -> void:
	for frame: int in 4:
		await process_frame
