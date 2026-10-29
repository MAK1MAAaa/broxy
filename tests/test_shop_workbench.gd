extends SceneTree
## Real inventory fixtures verify the trading workbench in a fixed logical canvas.

const LOGICAL_SIZE := Vector2i(1280, 720)
const SECTION_NAMES: PackedStringArray = ["ShopHeader", "ShopShelf", "BackpackPanel", "BackpackInspector", "ShopFooter"]
var _checks: int = 0
var _failures: int = 0
var _ui: GameUI
var _state: RunState


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = LOGICAL_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_state = RunState.new()
	_state.begin(20261029, "bone")
	_state.gold = 10000
	_check(_state.expand_backpack() and _state.expand_backpack(), "The fixture purchases both backpack expansions through RunState")
	for pair: Array in [["weapon", "frost"], ["skill", "starfall"], ["relic", "echo_stone"], ["rune", "bounce"]]:
		_buy(str(pair[0]), str(pair[1]))
	_state.offers.assign([_offer("weapon", "bone"), _offer("skill", "pulse"), _offer("relic", "grave_candle"), _offer("rune", "blast")])
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	var before: String = _state_signature()
	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1600, 900)]:
		root.size = window_size
		_ui.show_shop()
		await _settle()
		_test_layout(window_size)
		_test_goods()
		_test_passive_art()
		_check(_state_signature() == before, "Rebuilding or resizing the workbench preserves inventory, economy and random state")
	await _test_offer_records()
	await _test_owned_weapon_record()
	await _test_live_actions()
	await _test_stale_record_button()
	_ui.queue_free()
	await process_frame
	print("ShopWorkbench: %d assertions, %d failures; 1280x720 logical canvas, three physical window sizes" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame: int in 5:
		await process_frame


func _offer(kind: String, id: String) -> Dictionary:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	return {"kind": kind, "id": id, "price": _state.shop_price(definition), "sold": false}


func _buy(kind: String, id: String) -> void:
	_state.offers.assign([_offer(kind, id)])
	_check(_state.buy_offer(0), "The fixture uses the real automatic-placement purchase for " + id)


func _state_signature() -> String:
	return JSON.stringify([_state.summary(), _state.backpack_snapshot(), str(_state.rng.state)])


func _control(name: String) -> Control:
	return _ui.find_child(name, true, false) as Control


func _inside_canvas(control: Control) -> bool:
	return control != null and Rect2(Vector2(-1, -1), Vector2(LOGICAL_SIZE) + Vector2(2, 2)).encloses(control.get_global_rect())


func _test_layout(window_size: Vector2i) -> void:
	_check(root.size == window_size, "The physical window uses the requested size: " + str(window_size))
	_check(root.content_scale_size == LOGICAL_SIZE and root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "Every window preserves the reference canvas and aspect policy")
	_check(root.get_visible_rect().size.is_equal_approx(Vector2(LOGICAL_SIZE)), "Layout measurements remain in logical pixels rather than physical window pixels")
	var sections: Array[Control] = []
	var distinct: Dictionary = {}
	for name: String in SECTION_NAMES:
		var section: Control = _control(name)
		_check(section != null and section.is_visible_in_tree() and _inside_canvas(section), "The independent workbench region fits the logical canvas: " + name)
		if section != null:
			sections.append(section)
			distinct[section.get_instance_id()] = true
	_check(distinct.size() == SECTION_NAMES.size(), "Header, stock, backpack, inspector and footer are separate controls")
	if sections.size() != SECTION_NAMES.size():
		return
	var header: Rect2 = sections[0].get_global_rect()
	var shelf: Rect2 = sections[1].get_global_rect()
	var bag: Rect2 = sections[2].get_global_rect()
	var inspector: Rect2 = sections[3].get_global_rect()
	var footer: Rect2 = sections[4].get_global_rect()
	_check(shelf.end.x <= bag.position.x and bag.end.x <= inspector.position.x, "Stock, inventory and inspection form distinct left-to-right regions")
	_check(not shelf.intersects(bag) and not bag.intersects(inspector), "The stock and inspector never cover the backpack interaction area")
	_check(header.end.y <= shelf.position.y and header.end.y <= bag.position.y and footer.position.y >= bag.end.y, "Header and footer remain outside the work area")
	var grid := _control("BackpackGrid") as BackpackGrid
	_check(grid != null and _inside_canvas(grid), "The entire backpack grid stays visible at every physical window size")
	if grid != null:
		var full_grid := Rect2(grid.get_global_rect().position, Vector2.ONE * BackpackGrid.CELL * 6.0)
		_check(int(_state.backpack_snapshot()["height"]) == 6 and grid.get_global_rect().encloses(full_grid) and bag.encloses(full_grid), "The legally unlocked six-by-six grid is fully inside the backpack panel")
	var scroll := _control("BackpackDetailsScroll") as ScrollContainer
	_check(scroll != null and scroll.follow_focus and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and _inside_canvas(scroll), "The inspector retains bounded, focus-following vertical reading")
	if scroll != null:
		_check(inspector.encloses(scroll.get_global_rect()), "Scrollable item details belong to the inspector rather than overlapping the inventory")
	_check(_control("ShopLockGuide") == null, "The workbench has no persistent automatic-placement explanation label")


func _test_goods() -> void:
	var stock := _control("ShopStockGrid") as GridContainer
	_check(stock != null and stock.get_child_count() == 4, "The stock presents all four actual offers")
	for index: int in 4:
		var card: Control = _control("Offer%d" % (index + 1))
		_check(card != null and _inside_canvas(card), "Each real offer has a visible bounded card")
		if card == null:
			continue
		var well := card.find_child("OfferIconWell", true, false) as Control
		var icons: Array[Node] = well.find_children("*", "TextureRect", true, false) if well != null else []
		var icon: TextureRect = icons[0] as TextureRect if not icons.is_empty() else null
		_check(well != null and icon != null and icon.texture != null and icon.size.x >= 48.0 and icon.size.y >= 48.0, "An offer keeps a readable large item icon")
		var footprint := card.find_child("OfferFootprint", true, false) as Control
		var offer: Dictionary = _state.offers[index]
		var price := card.find_child("OfferPrice", true, false) as Label
		_check(price != null and price.is_visible_in_tree() and price.text == "%d 魂屑" % int(offer["price"]) and card.get_global_rect().encloses(price.get_global_rect()), "Offer prices stay complete and separate from purchase availability text")
		var definition: ContentDef = BackpackInventory.definition(str(offer["kind"]), str(offer["id"]))
		_check(footprint != null and footprint.get_meta("dimensions", Vector2i.ZERO) == definition.inventory_size and card.get_global_rect().encloses(footprint.get_global_rect()), "The compact footprint represents the actual offered item's dimensions")
		for action: String in ["lock", "buy", "offer_record"]:
			var button: Button = _ui._shop_focus_button("%s:%d" % [action, index])
			_check(button != null and button.is_visible_in_tree() and not button.disabled and button.focus_mode == Control.FOCUS_ALL and _inside_canvas(button), "The offer's " + action + " action remains visible and keyboard reachable")
			if button != null:
				button.grab_focus()
				_check(root.gui_get_focus_owner() == button, "Focus can reach the real " + action + " action")


func _test_passive_art() -> void:
	var backdrop: Control = _control("ShopWorkbenchBackdrop")
	_check(backdrop != null and backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE and backdrop.focus_mode == Control.FOCUS_NONE and not backdrop.is_processing(), "The workbench backdrop never consumes input or polls per frame")
	var finishes: Array[Node] = _ui.find_children("WorkbenchSurfaceFinish", "Control", true, false)
	var passive: bool = not finishes.is_empty()
	for node: Node in finishes:
		var finish := node as Control
		passive = passive and finish.mouse_filter == Control.MOUSE_FILTER_IGNORE and finish.focus_mode == Control.FOCUS_NONE and not finish.is_processing()
	_check(passive, "All workbench surface ornaments remain input-transparent and event-driven")


func _test_live_actions() -> void:
	var lock: Button = _ui._shop_focus_button("lock:0")
	if lock == null:
		_check(false, "The live lock action exists")
		return
	lock.grab_focus()
	lock.pressed.emit()
	await _settle()
	_check(_state.is_offer_locked(0), "The reachable lock button updates the actual offer")
	var before_gold: int = _state.gold
	var before_count: int = (_state.backpack_snapshot()["items"] as Array).size()
	var price: int = int(_state.offers[0]["price"])
	var buy: Button = _ui._shop_focus_button("buy:0")
	if buy == null:
		_check(false, "The live buy action exists after locking")
		return
	buy.grab_focus()
	buy.pressed.emit()
	await _settle()
	_check(_state.gold == before_gold - price and (_state.backpack_snapshot()["items"] as Array).size() == before_count + 1, "The reachable buy button charges the visible price and stores a real item")
	_check(bool(_state.offers[0].get("sold", false)) and not _state.is_offer_locked(0), "The purchased card reflects sold stock and releases its lock")


func _test_offer_records() -> void:
	for index: int in _state.offers.size():
		var offer: Dictionary = _state.offers[index].duplicate(true)
		var kind: String = str(offer["kind"])
		var definition: ContentDef = BackpackInventory.definition(kind, str(offer["id"]))
		var source: Button = _ui._shop_focus_button("offer_record:%d" % index)
		_check(source != null, "Every offered category has its own detail action: " + kind)
		if source == null:
			continue
		source.grab_focus()
		var before: String = _state_signature()
		source.pressed.emit()
		await _settle()
		_test_record_surface()
		var text := _control("ItemRecordEffect") as Label
		_check(text != null, "The offered item record contains its actual effect text")
		if text != null:
			if kind in ["weapon", "relic"]:
				_check(text.text.contains(definition.description), "An offer record preserves the full catalog effect without requiring an owned item's coordinates: " + definition.id)
			elif kind == "rune":
				_check(text.text.contains(_ui._rune_rank_text(definition.id, int(offer.get("rank", 1)))), "A rune record describes the actual offered rank")
			elif kind == "skill":
				var parameters: Dictionary = _state.active_skill_parameters(offer)
				_check(text.text.contains(definition.description) and text.text.contains("范围 " + _number(float(parameters["radius"]))) and text.text.contains("冷却 " + _number(float(parameters["cooldown"]))), "A skill record includes its current projected radius and cooldown")
		_check(_state_signature() == before, "Opening an offered item record never changes inventory, balance or random state")
		await _close_record(source)
		_check(_state_signature() == before, "Returning from an offered item record remains a read-only operation")


func _test_owned_weapon_record() -> void:
	var uid: int = int(_state.loadout[0]["uid"])
	var source_uid: int = -1
	for item: Dictionary in _state.backpack_snapshot()["items"]:
		if str(item["kind"]) == "relic" and str(item["id"]) == "echo_stone":
			source_uid = int(item["uid"])
	_check(source_uid >= 0 and _state.move_item(source_uid, Vector2i(0, 3), false), "The owned record fixture establishes a real adjacent relic through a formal move")
	await _settle()
	var grid := _control("BackpackGrid") as BackpackGrid
	if grid == null:
		_check(false, "The owned-record inventory grid exists")
		return
	grid.select_item(uid)
	await _settle()
	var source: Button = _ui._shop_focus_button("bag_record:%d" % uid)
	_check(source != null, "The selected owned weapon exposes its UID-bound detail action")
	if source == null:
		return
	var weapon: Dictionary = _state.loadout[_state.weapon_index_for_uid(uid)].duplicate(true)
	var actual_damage: float = _state.weapon_damage(weapon)
	var before: String = _state_signature()
	source.grab_focus()
	source.pressed.emit()
	await _settle()
	_test_record_surface()
	var text := _control("ItemRecordEffect") as Label
	var relic: Dictionary = _state.backpack_item(source_uid)
	_check(text != null and text.text.contains("每枚 %.1f伤害" % actual_damage), "An owned weapon record uses the actual current weapon damage")
	_check(source_uid in weapon.get("resonance_sources", []) and text != null and text.text.contains("来源：") and text.text.contains(GameCatalog.relic(str(relic["id"])).display_name) and text.text.contains("#%d" % source_uid), "An owned weapon record identifies the real adjacent relic source")
	await _exercise_record_keys()
	_check(_state_signature() == before and int(_ui._bag_selected_uid) == uid, "Inspecting an owned weapon preserves its UID, selection and complete state")
	await _close_record(source)
	_check(_state_signature() == before and int(_ui._bag_selected_uid) == uid, "Returning from the owned record preserves source identity and inventory state")
	source.reparent(root)
	source.visible = false
	grid.select_item(source_uid)
	await _settle()
	before = _state_signature()
	source.pressed.emit()
	await _settle()
	_check(_ui._overlay_mode.is_empty() and int(_ui._bag_selected_uid) == source_uid and _state_signature() == before, "A queued owned-detail callback cannot reopen the previous selection in the same shop epoch")
	source.queue_free()


func _test_record_surface() -> void:
	var body: Control = _control("ItemRecord")
	var scroll := _control("ItemRecordScroll") as ScrollContainer
	var close := _control("CloseItemRecord") as Button
	var grid := _control("BackpackGrid") as BackpackGrid
	_check(_ui._overlay_mode == "item_record" and body != null and _inside_canvas(body) and close != null and _inside_canvas(close), "Item details open in their bounded top-level record surface")
	_check(scroll != null and scroll.follow_focus and _ui._gamepad_reading_target() == scroll, "Gamepad reading targets the current item-record scroll view")
	_check(grid != null and not grid.interaction_enabled, "Opening item details disables inventory interaction underneath")
	_check(close != null and root.gui_get_focus_owner() == close, "The record opens with a reachable return action focused")


func _close_record(source: Button) -> void:
	var back := InputEventJoypadButton.new()
	back.device = 0
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	root.push_input(back, false)
	await _settle()
	_check(_ui._overlay_mode.is_empty(), "The real gamepad back action closes an open item record")
	var grid := _control("BackpackGrid") as BackpackGrid
	_check(_ui._overlay_mode.is_empty() and _control("ItemRecord") == null and grid != null and grid.interaction_enabled, "Returning removes the record and restores inventory interaction")
	_check(root.gui_get_focus_owner() == source, "Returning restores the exact item-detail source button")


func _exercise_record_keys() -> void:
	var scroll := _control("ItemRecordScroll") as ScrollContainer
	scroll.grab_focus()
	for key: Key in [KEY_END, KEY_HOME]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		root.push_input(event, false)
		await _settle()
		var limit: int = maxi(0, int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page))
		_check(scroll.scroll_vertical == (limit if key == KEY_END else 0), "Focused item records consume the actual end/home reading key")
	var shoulder := InputEventJoypadButton.new()
	shoulder.device = 0
	shoulder.button_index = JOY_BUTTON_RIGHT_SHOULDER
	shoulder.pressed = true
	root.push_input(shoulder, false)
	await _settle()
	var limit: int = maxi(0, int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page))
	_check(root.gui_get_focus_owner() == scroll and scroll.scroll_vertical == mini(maxi(1, int(scroll.size.y * 0.8)), limit), "The real RB event pages the current item record without moving focus")


func _test_stale_record_button() -> void:
	var stale: Button = _ui._shop_focus_button("offer_record:1")
	_check(stale != null, "The stale-record fixture captures a real offer detail button")
	if stale == null:
		return
	stale.reparent(root)
	stale.visible = false
	var old_epoch: int = _ui._shop_epoch
	_ui._reroll()
	await _settle()
	_check(_ui._shop_epoch > old_epoch, "A real reroll replaces the offer page and advances its epoch")
	var before: String = _state_signature()
	stale.pressed.emit()
	await _settle()
	_check(_ui._overlay_mode.is_empty() and _control("ItemRecord") == null and _state_signature() == before, "A retained detail button from the earlier offer page cannot open a new record or change state")
	stale.queue_free()


func _number(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")
