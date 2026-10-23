extends SceneTree
## Fixed public-purchase fixtures; keyboard events exercise the real shop controls.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.size = Vector2i(1280, 720)
	_check(RunState.new().has_method("purchase_error"), "The shop has a formal read-only purchase rejection query")
	await _test_render_is_read_only()
	await _test_blocked_keyboard_actions()
	await _test_balance_and_sold_refresh()
	await _test_weapon_sale_frees_capacity()
	await _test_rune_capacity_remedies()
	await _test_mixed_full_layout()
	print("ShopAvailability: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _new_run() -> RunState:
	var state := RunState.new()
	state.begin(8721, "bone")
	state.collect_souls(10000)
	return state


func _offer(kind: String, id: String, price: int = -1) -> Dictionary:
	var definition: ContentDef = _definition(kind, id)
	return {"kind": kind, "id": id, "price": definition.price if price < 0 else price, "sold": false}


func _mixed_offers() -> Array[Dictionary]:
	return [_offer("weapon", "frost"), _offer("rune", "bounce"), _offer("relic", "damage"), _offer("relic", "vitality")]


func _definition(kind: String, id: String) -> ContentDef:
	match kind:
		"weapon": return GameCatalog.weapon(id)
		"rune": return GameCatalog.rune(id)
	return GameCatalog.relic(id)


func _purchase(state: RunState, kind: String, id: String) -> bool:
	var definition: ContentDef = _definition(kind, id)
	state.offers = [_offer(kind, id, state.shop_price(definition))]
	return state.buy_offer(0)


func _fill_weapons(state: RunState) -> bool:
	var success: bool = true
	for id: String in ["frost", "ember", "scatter"]:
		success = _purchase(state, "weapon", id) and success
	return success and state.loadout.size() == 4


func _fill_reserve(state: RunState) -> bool:
	var success: bool = true
	for id: String in ["pierce", "bounce", "blast", "pierce"]:
		success = _purchase(state, "rune", id) and success
	return success and state.rune_bag.size() == 4


func _fill_relic(state: RunState, id: String) -> bool:
	var success: bool = true
	for layer: int in 3:
		success = _purchase(state, "relic", id) and success
	return success and int(state.relic_counts.get(id, 0)) == 3


func _new_ui(state: RunState) -> GameUI:
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_shop()
	await _settle()
	return ui


func _test_render_is_read_only() -> void:
	var state: RunState = _new_run()
	_check(_fill_weapons(state) and _fill_reserve(state) and _fill_relic(state, "damage"), "The read-only fixture fills all capacities through real purchases")
	state.offers = _mixed_offers()
	state.last_error = "保留真实操作的错误"
	var before: Dictionary = _snapshot(state)
	var changes: Array[int] = [0]
	var observer: Callable = func() -> void: changes[0] += 1
	state.changed.connect(observer)
	var ui: GameUI = await _new_ui(state)
	_check(_snapshot(state) == before and changes[0] == 0, "Showing capacity labels neither mutates the run or last_error nor emits changed")
	_assert_offer(ui, state, 0, "法器槽已满", "法器槽已满，请先出售一件法器。")
	_assert_offer(ui, state, 1, "备用符文已满", "备用符文已满，请先装备或出售。")
	_assert_offer(ui, state, 2, "遗物已满3层", "该遗物已达到3层上限。")
	_assert_offer(ui, state, 3, "", "")
	ui.show_shop()
	await _settle()
	_check(_snapshot(state) == before and changes[0] == 0, "Rebuilding every card repeatedly preserves RNG, cached upgrades, balances and inventory")
	state.gold = 0
	before = _snapshot(state)
	ui.show_shop()
	await _settle()
	for index: int in state.offers.size():
		_assert_offer(ui, state, index, "魂屑不足", "魂屑不足。")
	_check(_snapshot(state) == before and changes[0] == 0, "Insufficient-currency display takes precedence without performing a rejected transaction")
	state.changed.disconnect(observer)
	await _dispose(ui)


func _test_blocked_keyboard_actions() -> void:
	for mode: String in ["money", "weapon", "rune", "relic"]:
		var state: RunState = _new_run()
		var kind: String = "weapon"
		var id: String = "frost"
		var label: String = "魂屑不足"
		var reason: String = "魂屑不足。"
		match mode:
			"money": state.gold = 0
			"weapon":
				_check(_fill_weapons(state), "Weapon refusal fixture legally fills four slots")
				label = "法器槽已满"
				reason = "法器槽已满，请先出售一件法器。"
			"rune":
				_check(_fill_reserve(state), "Rune refusal fixture legally buys four reserve runes")
				kind = "rune"
				id = "bounce"
				label = "备用符文已满"
				reason = "备用符文已满，请先装备或出售。"
			"relic":
				_check(_fill_relic(state, "damage"), "Relic refusal fixture legally buys all three layers")
				kind = "relic"
				id = "damage"
				label = "遗物已满3层"
				reason = "该遗物已达到3层上限。"
		state.offers = [_offer("relic", "magnet"), _offer(kind, id)]
		var ui: GameUI = await _new_ui(state)
		var sounds: Array[String] = []
		ui.feedback.connect(func(sound: String) -> void: sounds.append(sound))
		_assert_offer(ui, state, 1, label, reason)
		var target: Button = _raw_buy(ui, 1)
		_check(target != null and _tab_reaches(ui, target), "Real Tab can reach a blocked unsold card: " + mode)
		var before: Dictionary = _snapshot(state)
		_key(KEY_ENTER)
		await _settle()
		_check(state.last_error == reason and ui._toast.visible and ui._toast.text == reason, "Return retains the exact formal purchase refusal: " + mode)
		var after: Dictionary = _snapshot(state)
		after["last_error"] = before["last_error"]
		_check(after == before, "Rejected Return preserves inventory, money, UID allocation, options and RNG: " + mode)
		_check(sounds.is_empty(), "A rejected purchase plays no successful buy feedback: " + mode)
		_check(_focus_id() == "buy:1", "A rejected purchase restores the same actionable card focus: " + mode)
		_assert_offer(ui, state, 1, label, reason)
		await _dispose(ui)


func _test_balance_and_sold_refresh() -> void:
	var state: RunState = _new_run()
	state.gold = 0
	state.offers = _mixed_offers()
	var ui: GameUI = await _new_ui(state)
	_assert_offer(ui, state, 0, "魂屑不足", "魂屑不足。")
	var price: int = int(state.offers[0]["price"])
	state.collect_souls(price)
	await _settle()
	_assert_offer(ui, state, 0, "", "")
	await _press_shop(ui, "buy:0")
	_check(state.gold == 0 and bool(state.offers[0]["sold"]) and state.loadout.size() == 2, "The exact earned balance purchases once through Return at the real displayed price")
	var sold: Button = _raw_buy(ui, 0)
	_check(sold != null and sold.disabled and sold.text == "已购买", "Only a sold offer becomes disabled and explicitly purchased")
	_check(not _tab_reaches(ui, sold), "Real Tab skips the disabled sold offer")
	_assert_offer(ui, state, 1, "魂屑不足", "魂屑不足。")
	state.collect_souls(50)
	await _settle()
	_assert_offer(ui, state, 1, "", "")
	state.offers = [_offer("relic", "magnet", 60)]
	ui.show_shop()
	await _settle()
	_assert_offer(ui, state, 0, "魂屑不足", "魂屑不足。")
	await _press_shop(ui, "sell_weapon:1")
	_check(state.gold == 50 + int(floorf(float(price) * 0.5)), "A real weapon sale changes the available wallet by its actual refund")
	_assert_offer(ui, state, 0, "", "")
	await _dispose(ui)


func _test_weapon_sale_frees_capacity() -> void:
	var state: RunState = _new_run()
	_check(_fill_weapons(state), "Capacity recovery starts from four legitimately owned weapons")
	state.offers = _mixed_offers()
	var ui: GameUI = await _new_ui(state)
	_assert_offer(ui, state, 0, "法器槽已满", "法器槽已满，请先出售一件法器。")
	await _press_shop(ui, "sell_weapon:3")
	_check(state.loadout.size() == 3, "Return on the real weapon sale frees one slot")
	_assert_offer(ui, state, 0, "", "")
	await _press_shop(ui, "buy:0")
	_check(state.loadout.size() == 4 and bool(state.offers[0]["sold"]), "The formerly full-slot offer can then be purchased normally")
	await _dispose(ui)


func _test_rune_capacity_remedies() -> void:
	var state: RunState = _new_run()
	_check(_fill_reserve(state), "Rune recovery starts from four legitimately owned reserves")
	state.offers = _mixed_offers()
	var ui: GameUI = await _new_ui(state)
	_assert_offer(ui, state, 1, "备用符文已满", "备用符文已满，请先装备或出售。")
	var first_uid: int = int(state.rune_bag[0]["uid"])
	await _press_shop(ui, "rune:%d" % first_uid)
	await _press_shop(ui, "equip:0")
	_check(state.rune_bag.size() == 3 and int(state.loadout[0]["rune"].get("uid", -1)) == first_uid, "Installing into an actually empty rune slot frees one reserve place")
	_assert_offer(ui, state, 1, "", "")
	await _press_shop(ui, "buy:1")
	_check(state.rune_bag.size() == 4 and bool(state.offers[1]["sold"]), "The freed reserve place permits one real rune purchase")
	state.offers = _mixed_offers()
	ui.show_shop()
	await _settle()
	var swapped_uid: int = int(state.rune_bag[0]["uid"])
	await _press_shop(ui, "rune:%d" % swapped_uid)
	await _press_shop(ui, "equip:0")
	_check(state.rune_bag.size() == 4 and int(state.loadout[0]["rune"].get("uid", -1)) == swapped_uid and _has_uid(state, first_uid), "Swapping into an occupied rune slot returns the old UID and leaves the reserve full")
	_assert_offer(ui, state, 1, "备用符文已满", "备用符文已满，请先装备或出售。")
	await _press_shop(ui, "sell_rune:%d" % first_uid)
	_check(state.rune_bag.size() == 3 and not _has_uid(state, first_uid), "A real reserve sale frees capacity after an occupied-slot swap did not")
	_assert_offer(ui, state, 1, "", "")
	await _dispose(ui)


func _test_mixed_full_layout() -> void:
	var state: RunState = _new_run()
	_check(_fill_weapons(state), "The layout fixture fills all four weapons through purchases")
	for index: int in 4:
		_check(_purchase(state, "rune", "pierce") and state.equip_rune(0, index), "The layout fixture legitimately equips rune slot %d" % index)
	_check(_fill_reserve(state), "The layout fixture owns four additional reserve runes")
	for definition: ContentDef in GameCatalog.relics():
		_check(_fill_relic(state, definition.id), "The layout fixture legally buys three layers of " + definition.id)
	state.offers = [_offer("weapon", "scatter"), _offer("rune", "blast"), _offer("relic", "damage"), _offer("relic", "haste")]
	var ui: GameUI = await _new_ui(state)
	_assert_offer(ui, state, 0, "法器槽已满", "法器槽已满，请先出售一件法器。")
	_assert_offer(ui, state, 1, "备用符文已满", "备用符文已满，请先装备或出售。")
	_assert_offer(ui, state, 2, "遗物已满3层", "该遗物已达到3层上限。")
	_assert_offer(ui, state, 3, "遗物已满3层", "该遗物已达到3层上限。")
	_check(state.relic_counts.size() == 10 and state.rune_bag.size() == 4 and state.loadout.size() == 4, "Mixed cards are verified against a complete ten-relic, four-weapon and four-reserve build")
	_check(_controls_fit(ui), "Every visible label and button, including long refusal labels, fits inside 1280 by 720 without minimum-size clipping")
	await _dispose(ui)


func _assert_offer(ui: GameUI, state: RunState, index: int, status: String, reason: String) -> void:
	var button: Button = _raw_buy(ui, index)
	var price: int = int(state.offers[index]["price"])
	var expected: String = "购买  %d 魂屑" % price if status.is_empty() else "%s · %d魂屑" % [status, price]
	_check(button != null and button.text == expected, "The visible buy label reflects formal availability: " + expected)
	_check(button != null and not button.disabled and button.focus_mode == Control.FOCUS_ALL, "An unsold offer remains enabled and keyboard focusable: " + expected)
	var formal_reason: String = str(state.call("purchase_error", index)) if state.has_method("purchase_error") else reason
	_check(button != null and (formal_reason.is_empty() or button.tooltip_text.contains(formal_reason)), "The tooltip carries the formal purchase rejection without substituting another rule: " + status)
	if status == "备用符文已满":
		_check(button != null and button.tooltip_text.contains("装入") and (button.tooltip_text.contains("空") or button.tooltip_text.contains("无符文")) and button.tooltip_text.contains("出售"), "Full-reserve guidance explicitly names an empty installation slot or sale, rather than implying any swap frees capacity")


func _snapshot(state: RunState) -> Dictionary:
	return {"summary": state.summary(), "offers": state.offers.duplicate(true), "last_error": state.last_error,
		"rng_state": state.rng.state, "rng_seed": state.rng.seed, "next_uid": state.get("_next_rune_uid"),
		"bonuses": state.get("_upgrade_bonuses").duplicate(true), "options": state.get("_upgrade_options").duplicate(true),
		"wave_income": state.get("_wave_income"), "wave_finished": state.get("_wave_finished"), "rerolls": state.rerolls}


func _raw_buy(ui: GameUI, index: int, node: Node = null) -> Button:
	var current: Node = ui._page if node == null else node
	if current is Button and str(current.get_meta("shop_focus_id", "")) == "buy:%d" % index:
		return current as Button
	for child: Node in current.get_children():
		var found: Button = _raw_buy(ui, index, child)
		if found != null:
			return found
	return null


func _tab_reaches(ui: GameUI, target: Button) -> bool:
	if target == null:
		return false
	var limit: int = _button_count(ui._page) + 2
	for index: int in limit:
		_key(KEY_TAB)
		if root.gui_get_focus_owner() == target:
			return true
	return false


func _button_count(node: Node) -> int:
	var count: int = 1 if node is Button else 0
	for child: Node in node.get_children():
		count += _button_count(child)
	return count


func _press_shop(ui: GameUI, id: String) -> void:
	var button: Button = ui._shop_focus_button(id)
	_check(button != null, "The current shop exposes its intended action: " + id)
	if button != null:
		button.grab_focus()
		_key(KEY_ENTER)
	await _settle()


func _has_uid(state: RunState, uid: int) -> bool:
	for entry: Dictionary in state.rune_bag:
		if int(entry["uid"]) == uid:
			return true
	return false


func _controls_fit(node: Node) -> bool:
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		var control: Control = node
		var rect: Rect2 = control.get_global_rect()
		var minimum: Vector2 = control.get_minimum_size()
		if rect.position.x < -1.0 or rect.position.y < -1.0 or rect.end.x > 1281.0 or rect.end.y > 721.0 or control.size.x + 1.0 < minimum.x or control.size.y + 1.0 < minimum.y:
			return false
	for child: Node in node.get_children():
		if not _controls_fit(child):
			return false
	return true


func _focus_id() -> String:
	var owner: Control = root.gui_get_focus_owner()
	return "" if owner == null else str(owner.get_meta("shop_focus_id", ""))


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, false)


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _dispose(ui: GameUI) -> void:
	ui.queue_free()
	await _settle()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
