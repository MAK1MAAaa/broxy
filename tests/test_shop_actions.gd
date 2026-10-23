extends SceneTree
## Deliberate same-frame input/signal fixtures, not a claim of human OS reproduction.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test.call_deferred()

func _test() -> void:
	root.size = Vector2i(1280, 720)
	await _test_reroll_stale_buy()
	await _test_repeated_rune_sale()
	await _test_repeated_weapon_sale()
	await _test_swap_stale_uid_sale()
	await _test_reopened_shop()
	await _test_overlay_actions()
	await _test_pending_transition_and_other_screen()
	await _test_failed_transaction_and_valid_swap()
	await _test_same_frame_keyboard()
	print("ShopActions: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(seed_value: int = 4) -> RunState:
	var state: RunState = RunState.new()
	state.begin(seed_value, "bone")
	state.gold = 500
	return state

func _buy_item(state: RunState, kind: String, id: String) -> bool:
	var definition: ContentDef = GameCatalog.rune(id) if kind == "rune" else GameCatalog.weapon(id)
	state.offers = [{"id": id, "kind": kind, "price": state.shop_price(definition), "sold": false}]
	return state.buy_offer(0)

func _new_ui(state: RunState) -> GameUI:
	state.generate_shop()
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_shop()
	await _settle()
	return ui

func _settle() -> void:
	for frame: int in 3:
		await process_frame

func _dispose(ui: GameUI) -> void:
	ui.queue_free()
	await _settle()

func _snapshot(state: RunState, ui: GameUI) -> Dictionary:
	return {"summary": state.summary(), "offers": state.offers.duplicate(true),
		"rerolls": state.rerolls, "rng": state.rng.state,
		"next_uid": state.get("_next_rune_uid"), "last_error": state.last_error,
		"selected": ui._selected_rune, "focus_request": ui._requested_shop_focus,
		"screen": ui._screen, "overlay": ui._overlay_mode, "refresh_queued": ui._refresh_queued}

func _button(ui: GameUI, id: String) -> Button:
	var result: Button = ui._shop_focus_button(id)
	_check(result != null, "Fixture has the current actionable button: " + id)
	return result

func _emit(button: Button) -> void:
	if is_instance_valid(button):
		button.pressed.emit()

func _uids(state: RunState) -> Array[int]:
	var result: Array[int] = []
	for entry: Dictionary in state.rune_bag:
		result.append(int(entry["uid"]))
	for weapon: Dictionary in state.loadout:
		var rune: Dictionary = weapon.get("rune", {})
		if not rune.is_empty():
			result.append(int(rune["uid"]))
	result.sort()
	return result

func _current_buy(ui: GameUI, state: RunState) -> void:
	var index: int = -1
	for candidate: int in state.offers.size():
		if not state.offers[candidate]["sold"]:
			index = candidate
			break
	_check(index >= 0, "A rebuilt shop retains a fresh unsold offer")
	if index < 0:
		return
	var price: int = int(state.offers[index]["price"])
	var gold_before: int = state.gold
	var rng_before: int = state.rng.state
	_emit(_button(ui, "buy:%d" % index))
	_check(state.offers[index]["sold"] and state.gold == gold_before - price, "A current rebuilt offer can be purchased at its displayed price")
	_check(state.rng.state == rng_before, "A normal purchase does not draw random numbers")

func _test_reroll_stale_buy() -> void:
	var state: RunState = _state()
	var ui: GameUI = await _new_ui(state)
	var stale_buy: Button = _button(ui, "buy:0")
	var previous_offer: Dictionary = state.offers[0].duplicate(true)
	var gold_before: int = state.gold
	var cost: int = state.reroll_cost()
	_emit(_button(ui, "reroll"))
	_check(state.gold == gold_before - cost and state.rerolls == 1, "The first current reroll charges exactly once")
	_check(previous_offer["id"] == "ember" and state.offers[0]["id"] == "scatter" and previous_offer["price"] != state.offers[0]["price"], "Seed four exposes a changed item and changed price in the same slot")
	var after_reroll: Dictionary = _snapshot(state, ui)
	_emit(stale_buy)
	_check(_snapshot(state, ui) == after_reroll, "A still-live old buy card cannot purchase the refreshed item or price before rebuilding")
	await _settle()
	_current_buy(ui, state)
	await _dispose(ui)

func _test_repeated_rune_sale() -> void:
	var state: RunState = _state()
	for id: String in ["pierce", "bounce", "blast"]:
		_check(_buy_item(state, "rune", id), "Rune sale fixture buys legal inventory")
	var ui: GameUI = await _new_ui(state)
	var stale_sell: Button = _button(ui, "sell_rune:1")
	var initial_gold: int = state.gold
	_emit(stale_sell)
	_check(_uids(state) == [2, 3] and state.gold == initial_gold + 9, "First rune sale removes only its advertised UID and refunds the actual price")
	var after_first: Dictionary = _snapshot(state, ui)
	_emit(stale_sell)
	_check(_snapshot(state, ui) == after_first, "Repeating an old rune-sale button cannot sell the rune shifted into its index")
	await _settle()
	var gold_before: int = state.gold
	_emit(_button(ui, "sell_rune:3"))
	_check(state.gold == gold_before + 11 and not _uids(state).has(3), "A rebuilt rune-sale button still sells its current UID normally")
	await _dispose(ui)

func _test_repeated_weapon_sale() -> void:
	var state: RunState = _state()
	for id: String in ["frost", "ember", "scatter"]:
		_check(_buy_item(state, "weapon", id), "Weapon sale fixture legally fills four slots")
	var ui: GameUI = await _new_ui(state)
	var stale_sell: Button = _button(ui, "sell_weapon:1")
	var initial_gold: int = state.gold
	_emit(stale_sell)
	_check(state.loadout.size() == 3 and state.loadout[1]["id"] == "ember" and state.gold == initial_gold + 12, "The first sale removes frost and refunds half its actual purchase price")
	var after_first: Dictionary = _snapshot(state, ui)
	_emit(stale_sell)
	_check(_snapshot(state, ui) == after_first, "Repeating an old weapon-sale button cannot sell the weapon shifted into its index")
	await _settle()
	var gold_before: int = state.gold
	_emit(_button(ui, "sell_weapon:%d" % (state.loadout.size() - 1)))
	_check(state.gold == gold_before + 13, "A new weapon-sale button can still sell the remaining scatter at the right refund")
	await _dispose(ui)

func _test_swap_stale_uid_sale() -> void:
	var state: RunState = _state()
	_check(_buy_item(state, "rune", "pierce") and state.equip_rune(0, 0), "Swap fixture legally equips its first rune")
	_check(_buy_item(state, "rune", "bounce") and _buy_item(state, "rune", "blast"), "Swap fixture has two legal reserve UIDs")
	var ui: GameUI = await _new_ui(state)
	_emit(_button(ui, "rune:3"))
	await _settle()
	var stale_sell: Button = _button(ui, "sell_rune:3")
	var before_gold: int = state.gold
	_emit(_button(ui, "equip:0"))
	_check(state.loadout[0]["rune"]["uid"] == 3 and _uids(state) == [1, 2, 3] and state.gold == before_gold, "Current swap preserves all UIDs and is free")
	var after_swap: Dictionary = _snapshot(state, ui)
	_emit(stale_sell)
	_check(_snapshot(state, ui) == after_swap, "An old blast sale cannot sell the pierce UID returned to its former index")
	await _settle()
	_emit(_button(ui, "unequip:0"))
	_check(state.loadout[0]["rune"].is_empty() and _uids(state).has(3), "A fresh unequip button returns the actual currently equipped UID")
	await _dispose(ui)

func _test_reopened_shop() -> void:
	var state: RunState = _state()
	_check(_buy_item(state, "rune", "pierce"), "Reopen fixture owns a reserve rune")
	var ui: GameUI = await _new_ui(state)
	var stale: Array[Button] = [_button(ui, "buy:0"), _button(ui, "reroll"), _button(ui, "sell_rune:1")]
	ui.show_shop()
	_check(is_instance_valid(stale[0]) and not stale[0].is_inside_tree(), "Reopened-shop fixture retains a live detached old button before deletion")
	for button: Button in stale:
		var before: Dictionary = _snapshot(state, ui)
		_emit(button)
		_check(_snapshot(state, ui) == before, "A previous shop epoch rejects its still-live old action")
	await _settle()
	_current_buy(ui, state)
	await _dispose(ui)

func _test_overlay_actions() -> void:
	for overlay: String in ["pause", "settings"]:
		var state: RunState = _state()
		_check(_buy_item(state, "rune", "pierce"), "Overlay fixture owns a reserve rune")
		var ui: GameUI = await _new_ui(state)
		var actions: Array[Button] = [_button(ui, "buy:0"), _button(ui, "reroll"), _button(ui, "sell_rune:1"), _button(ui, "next_wave")]
		var requests: Array[int] = [0]
		ui.next_wave_requested.connect(func() -> void: requests[0] += 1)
		if overlay == "pause":
			ui.show_pause()
		else:
			ui._show_settings(false)
		_check(not ui._overlay_mode.is_empty(), "Fixture has a real production overlay: " + overlay)
		for button: Button in actions:
			var before: Dictionary = _snapshot(state, ui)
			_emit(button)
			_check(_snapshot(state, ui) == before, "An overlay blocks all stale underlying shop state actions: " + overlay)
		_check(requests[0] == 0, "An underlying next-wave button emits no transition through the overlay")
		ui.hide_pause()
		await _settle()
		_current_buy(ui, state)
		await _dispose(ui)

func _test_pending_transition_and_other_screen() -> void:
	var state: RunState = _state()
	var ui: GameUI = await _new_ui(state)
	var stale_next: Button = _button(ui, "next_wave")
	var requests: Array[int] = [0]
	ui.next_wave_requested.connect(func() -> void: requests[0] += 1)
	_emit(_button(ui, "reroll"))
	var after_reroll: Dictionary = _snapshot(state, ui)
	_emit(stale_next)
	_check(requests[0] == 0 and _snapshot(state, ui) == after_reroll, "Pending shop rebuilding blocks next-wave requests until the current view is ready")
	await _settle()
	var requests_before: int = requests[0]
	_emit(_button(ui, "next_wave"))
	_check(requests[0] == requests_before + 1, "The rebuilt current next-wave button still emits normally")
	var stale_reroll: Button = _button(ui, "reroll")
	var stale_buy: Button = _button(ui, "buy:0")
	state.next_wave()
	ui.show_hud()
	var after_transition: Dictionary = _snapshot(state, ui)
	_emit(stale_reroll)
	_emit(stale_buy)
	_check(_snapshot(state, ui) == after_transition and state.offers.is_empty(), "Old shop controls cannot charge gold or generate/buy offers after entering combat")
	await _dispose(ui)

func _test_failed_transaction_and_valid_swap() -> void:
	var state: RunState = _state()
	_check(_buy_item(state, "rune", "pierce") and state.equip_rune(0, 0), "Full-bag fixture owns an equipped rune")
	for index: int in 4:
		_check(_buy_item(state, "rune", "bounce"), "Full-bag fixture reaches capacity legally")
	var ui: GameUI = await _new_ui(state)
	var stale_buy: Button = _button(ui, "buy:0")
	var before_summary: Dictionary = state.summary()
	var before_offers: Array[Dictionary] = state.offers.duplicate(true)
	var before_rng: int = state.rng.state
	_emit(_button(ui, "unequip:0"))
	_check(state.summary() == before_summary and state.offers == before_offers and state.rng.state == before_rng and not state.last_error.is_empty(), "A full-reserve failure preserves wallet, inventory, UIDs, offers and RNG")
	var after_failure: Dictionary = _snapshot(state, ui)
	_emit(stale_buy)
	_check(_snapshot(state, ui) == after_failure, "Even a failed transaction invalidates old actions while its feedback refresh is pending")
	await _settle()
	var all_uids: Array[int] = _uids(state)
	var gold_before: int = state.gold
	_emit(_button(ui, "rune:2"))
	await _settle()
	_emit(_button(ui, "equip:0"))
	_check(state.loadout[0]["rune"]["uid"] == 2 and state.rune_bag.size() == 4 and _uids(state) == all_uids and state.gold == gold_before, "Current rebuilt controls allow a free full-reserve swap without losing any UID")
	await _dispose(ui)

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, false)

func _focus_id() -> String:
	var owner: Control = root.gui_get_focus_owner()
	return "" if owner == null else str(owner.get_meta("shop_focus_id", ""))

func _test_same_frame_keyboard() -> void:
	var state: RunState = _state()
	for id: String in ["pierce", "bounce", "blast"]:
		_check(_buy_item(state, "rune", id), "Keyboard fixture buys three distinct reserve UIDs")
	var ui: GameUI = await _new_ui(state)
	_button(ui, "sell_rune:1").grab_focus()
	_key(KEY_ENTER)
	_check(not _uids(state).has(1) and _uids(state) == [2, 3], "A real Return input sells the focused first UID")
	var after_sale: Dictionary = _snapshot(state, ui)
	_key(KEY_TAB)
	_check(_focus_id() == "rune:2", "Same-frame Tab visibly focuses the old second-rune button")
	_key(KEY_ENTER)
	_check(_snapshot(state, ui) == after_sale and ui._selected_rune == -1, "A second same-frame Return cannot select the wrong UID through an old index")
	await _settle()
	_button(ui, "rune:2").grab_focus()
	_key(KEY_ENTER)
	await _settle()
	_check(ui._selected_rune >= 0 and state.rune_bag[ui._selected_rune]["uid"] == 2, "After rebuilding Return selects the actual currently focused UID")
	_key(KEY_ENTER)
	_check(state.loadout[0]["rune"].get("uid", -1) == 2 and _uids(state) == [2, 3], "A subsequent current Return equips that UID and preserves the other rune")
	await _dispose(ui)
