extends SceneTree
## Real input verifies locked stock, stale-action protection and unchanged shop flows.

const FULL_FIXTURE = preload("res://tools/preview_rune_equip.gd")

class EscapeRouter:
	extends Node
	var ui: GameUI

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and ui.handle_back():
			get_viewport().set_input_as_handled()

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	root.size = Vector2i(1280, 720)
	var ui := GameUI.new()
	root.add_child(ui)
	var escape := EscapeRouter.new()
	escape.ui = ui
	root.add_child(escape)
	await _test_keyboard_mouse_and_cap(ui)
	await _test_stale_callbacks(ui)
	await _test_refresh_cross_wave_and_purchase(ui)
	await _test_full_shop_and_existing_flows(ui)
	await _test_unaffordable_and_sold(ui)
	ui.queue_free()
	escape.queue_free()
	await _settle()
	print("ShopLockUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261026, "bone")
	state.collect_souls(600)
	state.pending_upgrades = 0
	for entry: Array in [["weapon", "comet"], ["rune", "blast"], ["relic", "hourglass"], ["relic", "moon_charm"]]:
		var kind: String = str(entry[0])
		var id: String = str(entry[1])
		var definition: ContentDef = GameCatalog.weapon(id) if kind == "weapon" else GameCatalog.rune(id) if kind == "rune" else GameCatalog.relic(id)
		state.offers.append({"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false})
	return state


func _show(ui: GameUI, state: RunState) -> void:
	ui.bind(state)
	ui.show_shop()
	await _settle()


func _accept(ui: GameUI, focus_id: String) -> Button:
	var button: Button = ui._shop_focus_button(focus_id)
	_check(button != null, "The current shop exposes an actionable control: " + focus_id)
	if button != null:
		button.grab_focus()
		_key(KEY_ENTER)
		await _settle()
	return button


func _test_keyboard_mouse_and_cap(ui: GameUI) -> void:
	var state := _state()
	await _show(ui, state)
	var before: String = _economy_signature(state)
	var first: Button = ui._shop_focus_button("lock:0")
	_click(first)
	await _settle()
	_check(state.is_offer_locked(0) and state.locked_offer_count() == 1, "Mouse input locks the first offer")
	_check(_economy_signature(state) == before, "Locking changes no offers, gold, inventory, purchase values or RNG")
	var marker: Label = ui.find_child("OfferLockMarker0", true, false)
	_check(marker != null and marker.text == "已锁" and ui._shop_focus_button("lock:0").text == "解锁", "Locked stock has an explicit text marker and an unlock action")
	_check(root.gui_get_focus_owner() == ui._shop_focus_button("lock:0"), "Lock rebuilding restores focus to the same card action")
	await _accept(ui, "lock:1")
	_check(state.locked_offer_count() == RunState.SHOP_LOCK_CAP and state.is_offer_locked(1), "Real ui_accept locks the second offer")
	var count: Label = ui.find_child("ShopLockCount", true, false)
	_check(count != null and count.text.contains("2 / 2"), "The stock heading exposes the current two-item lock limit")
	_check(ui._shop_focus_button("reroll").text.begins_with("刷新未锁"), "Refresh explicitly targets only unlocked stock")
	var third: Button = ui._shop_focus_button("lock:2")
	_check(third != null and not third.disabled and third.focus_mode == Control.FOCUS_ALL, "A third lock attempt remains keyboard accessible for its limit explanation")
	var capped: String = _economy_signature(state)
	await _accept(ui, "lock:2")
	_check(not state.is_offer_locked(2) and state.locked_offer_count() == 2 and _economy_signature(state) == capped, "A third lock is rejected without changing stock or economic state")
	_check(ui._toast.visible and not ui._toast.text.is_empty() and root.gui_get_focus_owner() == ui._shop_focus_button("lock:2"), "The limit reason is visible and keeps the attempted source focused")
	await _accept(ui, "lock:0")
	_check(not state.is_offer_locked(0) and state.locked_offer_count() == 1, "A locked offer can always be unlocked at the cap")
	await _accept(ui, "lock:2")
	_check(state.is_offer_locked(2) and state.locked_offer_count() == 2, "Unlocking one offer makes room for another lock")
	_check(not state.offers[2].has("locked"), "UI lock state remains independent of offer dictionaries")


func _test_stale_callbacks(ui: GameUI) -> void:
	var state := _state()
	await _show(ui, state)
	var old: Button = ui._shop_focus_button("lock:0")
	var old_action: Callable = old.pressed.get_connections()[0]["callable"]
	old.pressed.emit()
	old.pressed.emit()
	await _settle()
	_check(state.is_offer_locked(0) and state.locked_offer_count() == 1, "Two same-frame signals produce only one lock transition")
	var before: String = _economy_signature(state)
	old_action.call()
	_check(state.is_offer_locked(0) and _economy_signature(state) == before, "An old epoch cannot toggle the replacement lock button")
	ui._toggle_offer_lock(0, ui._shop_epoch, state.offers[0].duplicate(true), false)
	_check(state.is_offer_locked(0), "A stale original lock state is rejected even when its offer and epoch match")
	var source: Button = ui._shop_focus_button("lock:1")
	var price: int = int(state.offers[1]["price"])
	state.offers[1]["price"] = price + 1
	source.pressed.emit()
	_check(not state.is_offer_locked(1), "A changed offer price invalidates its old lock callback before rebuilding")
	state.offers[1]["price"] = price
	ui._build_shop()
	await _settle()
	old_action.call()
	_check(state.locked_offer_count() == 1, "A direct rebuild also invalidates retained old lock callbacks")


func _test_refresh_cross_wave_and_purchase(ui: GameUI) -> void:
	var state := _state()
	await _show(ui, state)
	await _accept(ui, "lock:0")
	await _accept(ui, "lock:1")
	var old_price: int = int(state.offers[0]["price"])
	var old_gold: int = state.gold
	var refresh_cost: int = state.reroll_cost()
	await _accept(ui, "reroll")
	var weapon_index: int = _locked_index(state, "weapon", "comet")
	var rune_index: int = _locked_index(state, "rune", "blast")
	_check(weapon_index >= 0 and rune_index >= 0 and state.offers.size() == 4 and state.locked_offer_count() == 2, "UI refresh keeps both chosen locked items among four offers")
	_check(weapon_index >= 0 and int(state.offers[weapon_index]["price"]) == old_price and state.gold == old_gold - refresh_cost, "Same-wave refresh preserves the locked price and charges only its normal refresh fee")
	state.next_wave()
	state.generate_shop()
	ui.show_shop()
	await _settle()
	weapon_index = _locked_index(state, "weapon", "comet")
	var new_price: int = state.shop_price(GameCatalog.weapon("comet"))
	_check(weapon_index >= 0 and new_price > old_price and int(state.offers[weapon_index]["price"]) == new_price, "The retained weapon is repriced for its new wave rather than price-locked")
	var guide: Label = ui.find_child("ShopLockGuide", true, false)
	_check(guide != null and guide.text.contains("跨波保留") and guide.text.contains("价格随波次调整"), "The shop states the cross-wave retention and repricing rule")
	if weapon_index < 0:
		return
	var gold_before: int = state.gold
	await _accept(ui, "buy:%d" % weapon_index)
	var purchased: Dictionary = state.loadout.back()
	_check(str(purchased["id"]) == "comet" and int(purchased["paid"]) == new_price and state.gold == gold_before - new_price, "Direct purchase uses the visible new-wave price and records its real paid value")
	_check(not state.is_offer_locked(weapon_index) and state.locked_offer_count() == 1, "Buying locked stock consumes that lock immediately")
	var sold: Button = ui.find_child("OfferLock%d" % weapon_index, true, false)
	_check(sold != null and sold.disabled and sold.focus_mode == Control.FOCUS_NONE and sold.text == "已售", "A purchased card exposes no actionable lock")


func _test_full_shop_and_existing_flows(ui: GameUI) -> void:
	var state: RunState = FULL_FIXTURE.make_state("shop")
	await _show(ui, state)
	await _accept(ui, "rune:%d" % int(state.rune_bag[0]["uid"]))
	var incoming: Dictionary = state.rune_bag[0].duplicate(true)
	await _accept(ui, "lock:0")
	await _accept(ui, "lock:1")
	_check(state.loadout.size() == 4 and state.rune_bag.size() == 4 and state.relic_counts.size() == GameCatalog.relics().size() and ui._selected_rune == 0, "Locking full-capacity weapon and rune stock preserves the selected reserve rune")
	_check(_controls_inside(ui._page), "Full 720p stock, names and actions fit with two locks, four equipped weapons, four reserve runes and every catalog relic")
	for index: int in 4:
		var title: Control = ui.find_child("OfferLock%d" % index, true, false).get_parent()
		_check(title.size.y <= 30.1, "The small title-row lock does not add card height: %d" % index)
	var buy: Button = ui._shop_focus_button("buy:2")
	var compare: Button = ui._shop_focus_button("compare:2")
	_check(buy != null and compare != null and buy.get_parent() == compare.get_parent(), "Relic direct purchase and comparison remain together in the original bottom row")
	await _accept(ui, "compare:2")
	var before: String = _economy_signature(state)
	var locks: int = state.locked_offer_count()
	ui._shop_focus_button("lock:0").pressed.emit()
	_check(ui._overlay_mode == "relic_comparison" and state.locked_offer_count() == locks and _economy_signature(state) == before, "Relic comparison blocks underlying lock callbacks")
	_key(KEY_ESCAPE)
	await _settle()
	await _accept(ui, "rune_preview:1")
	ui._shop_focus_button("lock:0").pressed.emit()
	_check(ui._overlay_mode == "rune_equip_comparison" and state.locked_offer_count() == locks and ui._selected_rune == 0, "Rune equip preview also blocks locks and keeps the selected rune")
	_key(KEY_ESCAPE)
	await _settle()
	await _accept(ui, "equip:1")
	_check(state.loadout[1]["rune"] == incoming and state.rune_bag.size() == 4 and ui._selected_rune == -1, "Direct rune equip still swaps immediately after using stock locks and previews")
	await _accept(ui, "compare:2")
	state.set_offer_locked(0, false)
	_check(ui._overlay_mode.is_empty(), "An official external lock change invalidates an already-open comparison")
	await _settle()
	var count_before: int = int(state.relic_counts["hourglass"])
	var gold_before: int = state.gold
	var price: int = int(state.offers[2]["price"])
	await _accept(ui, "buy:2")
	_check(ui._overlay_mode.is_empty() and int(state.relic_counts["hourglass"]) == count_before + 1 and state.gold == gold_before - price, "The independent lock control adds no confirmation to direct relic purchase")


func _test_unaffordable_and_sold(ui: GameUI) -> void:
	var state := _state()
	state.gold = 0
	await _show(ui, state)
	await _accept(ui, "lock:0")
	_check(state.is_offer_locked(0) and state.gold == 0, "An unaffordable unsold item can be retained without payment")
	state = _state()
	_check(state.buy_offer(0), "The sold boundary fixture is produced by a real purchase")
	await _show(ui, state)
	var sold: Button = ui.find_child("OfferLock0", true, false)
	_check(sold != null and sold.disabled and ui._shop_focus_button("lock:0") == null, "Already-sold stock has no keyboard lock action")
	if sold != null:
		_click(sold)
		await _settle()
	_check(state.locked_offer_count() == 0 and not state.is_offer_locked(0), "Mouse input cannot lock a sold offer")


static func _locked_index(state: RunState, kind: String, id: String) -> int:
	for index: int in state.offers.size():
		if state.is_offer_locked(index) and str(state.offers[index]["kind"]) == kind and str(state.offers[index]["id"]) == id:
			return index
	return -1


static func _economy_signature(state: RunState) -> String:
	return JSON.stringify([state.gold, state.health, state.wave, state.rerolls, state.loadout, state.rune_bag,
		state.relic_counts, state.offers, state.rng.state, state._next_rune_uid])


func _controls_inside(node: Node) -> bool:
	if node is Control and node.is_visible_in_tree() and (node is Button or node is Label):
		if not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
			return false
		if node is Label and node.size.y + 1.0 < node.get_minimum_size().y:
			return false
	for child: Node in node.get_children():
		if not _controls_inside(child):
			return false
	return true


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
