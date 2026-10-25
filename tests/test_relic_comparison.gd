extends SceneTree
## Real input checks the read-only shop comparison, modal lifecycle and projections.

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
	await _test_tradeoff_and_focus(ui)
	await _test_bulwark(ui)
	await _test_ranked_sold_and_poor(ui)
	await _test_epoch_and_rebuild(ui)
	ui.queue_free()
	escape.queue_free()
	await _settle()
	print("RelicComparison: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _show(ui: GameUI, state: RunState) -> void:
	ui.bind(state)
	ui.show_shop()
	await _settle()


func _make_state(case_name: String) -> RunState:
	var state := RunState.new()
	state.begin(20261024, "bone")
	state.gold = 4000
	_check(state.expand_backpack() and state.expand_backpack(), "The comparison fixture pays for a legal six-by-six backpack")
	for id: String in ["frost", "ember", "scatter"]:
		_purchase(state, "weapon", id)
	for index: int in 3:
		_purchase(state, "rune", ["blast", "pierce", "bounce"][index])
		_check(state.equip_rune(0, index + 1), "The comparison fixture installs a formally purchased rune")
	for definition: ContentDef in GameCatalog.relics():
		var uid: int = _purchase(state, "relic", definition.id)
		if case_name == "ranked" and definition.id == "hourglass":
			var second: int = _purchase(state, "relic", definition.id)
			var third: int = _purchase(state, "relic", definition.id)
			var fourth: int = _purchase(state, "relic", definition.id)
			_check(state.merge_items(second, uid) and state.merge_items(fourth, third) and state.merge_items(third, uid), "Explicit merges create the ranked relic without expanding its footprint")
	_check(state.backpack_snapshot()["used_cells"] == 32, "Four real weapon boxes and all twelve relic kinds occupy thirty-two cells")
	state.gold = 7 if case_name == "poor" else 120
	state.wave = 4
	if case_name == "bulwark":
		state.take_damage(37.0, "chaser", "contact")
	var target: String = "bulwark" if case_name == "bulwark" else "hourglass"
	state.offers.clear()
	for entry: Array in [["relic", target], ["weapon", "crescent"], ["relic", "moon_charm"], ["relic", "bulwark"]]:
		var definition: ContentDef = BackpackInventory.definition(str(entry[0]), str(entry[1]))
		state.offers.append({"kind": str(entry[0]), "id": definition.id, "price": definition.price, "sold": false})
	return state


func _purchase(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	var purchased: bool = state.buy_offer(0)
	_check(purchased, "The comparison fixture buys its physical inventory through RunState: " + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1 if purchased else -1


func _open(ui: GameUI) -> Button:
	var source: Button = ui._shop_focus_button("compare:0")
	_check(source != null, "The relic offer exposes a focusable comparison action")
	if source != null:
		source.grab_focus()
		_key(KEY_ENTER)
		await _settle()
	return source


func _test_tradeoff_and_focus(ui: GameUI) -> void:
	var state: RunState = _make_state("tradeoff")
	_check(state.loadout.size() == 4 and state.relic_counts.size() == GameCatalog.relics().size(), "Formal purchases construct a legal four-weapon backpack with every catalog relic")
	if state == null:
		return
	await _show(ui, state)
	_check(ui._shop_focus_button("compare:1") == null and ui._shop_focus_button("compare:2") != null, "Only relic cards receive comparison actions")
	var buy: Button = ui._shop_focus_button("buy:0")
	var compare: Button = ui._shop_focus_button("compare:0")
	_check(buy != null and compare != null and buy.get_parent() == compare.get_parent() and is_equal_approx(buy.get_global_rect().position.y, compare.get_global_rect().position.y), "Comparison shares the purchase row without replacing direct purchase")
	var before: String = _signature(state)
	var source: Button = await _open(ui)
	_check(ui._overlay_mode == "relic_comparison", "Real ui_accept opens the relic comparison")
	_check(ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED and _overlay_owns_focus(ui), "The comparison isolates keyboard focus from underlying shop actions")
	for press: int in 4:
		_key(KEY_TAB)
		await process_frame
		_check(_overlay_owns_focus(ui), "Native Tab remains inside the relic comparison focus fence")
	var loss: Label = ui.find_child("ComparisonStat_damage", true, false)
	var gain: Label = ui.find_child("ComparisonStat_attack_speed", true, false)
	_check(loss != null and loss.text.contains("减少") and loss.get_theme_color("font_color").is_equal_approx(GameUI.RED), "The damage tradeoff has explicit negative text and color")
	_check(gain != null and gain.text.contains("增加") and gain.get_theme_color("font_color").is_equal_approx(GameUI.CYAN), "The attack-speed gain has explicit positive text and color")
	for slot: int in 4:
		var damage: Label = ui.find_child("ComparisonWeapon%dDamage" % slot, true, false)
		var interval: Label = ui.find_child("ComparisonWeapon%dInterval" % slot, true, false)
		_check(damage != null and damage.text.contains("→") and damage.text.contains("减少约"), "Every equipped weapon marks its rounded per-projectile damage reduction: %d" % slot)
		_check(interval != null and interval.text.contains("更快") and interval.text.contains("秒"), "Every equipped weapon shows its shorter nominal interval: %d" % slot)
	var scope: Label = ui.find_child("ComparisonScope", true, false)
	_check(scope != null and scope.text.contains("未计符文追加命中") and scope.text.contains("不是 DPS"), "The comparison states its rune and DPS limits")
	_check(_signature(state) == before, "Opening and reading the comparison preserves currency, RNG, stock and inventory")
	buy.pressed.emit()
	ui._shop_focus_button("reroll").pressed.emit()
	ui._shop_focus_button("next_wave").pressed.emit()
	var sale: Button = ui._shop_focus_button("bag_sell:%d" % int(state.loadout[0]["uid"]))
	_check(sale != null, "The underlying backpack exposes its selected item's transaction action")
	if sale != null:
		sale.pressed.emit()
	await _settle()
	_check(_signature(state) == before and _next_waves == 0, "Underlying purchase, backpack sale, reroll and next-wave callbacks remain blocked while comparing")
	var scroll: ScrollContainer = ui.find_child("ComparisonScroll", true, false)
	var close: Button = ui.find_child("CloseRelicComparison", true, false)
	_check(scroll != null and close != null and root.get_visible_rect().encloses(scroll.get_global_rect()) and root.get_visible_rect().encloses(close.get_global_rect()), "A full build keeps the bounded table and return action inside 720p")
	if scroll != null:
		_check(scroll.get_child(0).get_combined_minimum_size().x <= scroll.size.x + 1.0, "The comparison tables fit without horizontal clipping")
		scroll.grab_focus()
		_key(KEY_PAGEDOWN)
		await _settle()
		_check(scroll.scroll_vertical > 0, "Keyboard PageDown scrolls the long full-build table")
	if close != null:
		close.grab_focus()
		_key(KEY_ENTER)
		await _settle()
	_check(ui._overlay_mode.is_empty() and root.gui_get_focus_owner() == source, "Real ui_accept closes comparison and restores its exact source focus")
	await _open(ui)
	_key(KEY_ESCAPE)
	await _settle()
	_check(ui._overlay_mode.is_empty() and root.gui_get_focus_owner() == source, "Escape returns to the original relic comparison action")
	buy.grab_focus()
	_key(KEY_ENTER)
	await _settle()
	_check(ui._overlay_mode.is_empty() and int(state.relic_counts["hourglass"]) == 2 and state.gold == 96 and bool(state.offers[0]["sold"]), "Direct purchase still completes immediately without a comparison or confirmation step")


func _test_bulwark(ui: GameUI) -> void:
	var state: RunState = _make_state("bulwark")
	await _show(ui, state)
	var before: String = _signature(state)
	var source: Button = ui._shop_focus_button("compare:0")
	if source != null:
		_click(source)
		await _settle()
	_check(ui._overlay_mode == "relic_comparison", "Mouse input opens the same comparison dialog")
	var health: Label = ui.find_child("ComparisonHealthGain", true, false)
	_check(health != null and health.text == "实际补充 12.0 生命", "The bone shield preview shows actual health restored by purchase")
	_check(ui.find_child("ComparisonStat_armor", true, false) != null and ui.find_child("ComparisonStat_max_health", true, false) != null, "Both bone shield attributes have current and projected rows")
	var unchanged: Label = ui.find_child("ComparisonWeapon1Damage", true, false)
	_check(unchanged != null and unchanged.text.contains("保持不变"), "A defensive relic leaves weapon damage explicitly unchanged")
	_check(_signature(state) == before, "A health-restoration preview never heals or changes combat accounting")
	_key(KEY_ESCAPE)
	await _settle()


func _test_ranked_sold_and_poor(ui: GameUI) -> void:
	var state: RunState = _make_state("ranked")
	await _show(ui, state)
	var ranked_before: String = _signature(state)
	await _open(ui)
	var layers: Label = ui.find_child("ComparisonLayers", true, false)
	_check(layers != null and layers.text.contains("属性权重") and layers.text.contains("4 → 5"), "A third-rank owned relic projects another independent box using its true stat weight")
	_check(ui.find_child("ComparisonNoProjection", true, false) == null and ui.find_child("ComparisonStat_damage", true, false) != null and ui.find_child("ComparisonWeapon0Damage", true, false) != null and _signature(state) == ranked_before, "An available cell permits an honest read-only projection beyond the obsolete three-layer cap")
	_key(KEY_ESCAPE)
	await _settle()
	state = _make_state("tradeoff")
	_check(state.buy_offer(0), "The sold-offer fixture is produced by a formal purchase")
	await _show(ui, state)
	_check(ui._shop_focus_button("compare:0") != null, "A sold relic can still explain why the same offer cannot be bought again")
	await _open(ui)
	var sold: Label = ui.find_child("ComparisonNoProjection", true, false)
	_check(sold != null and sold.text.contains("已售出") and ui.find_child("ComparisonStat_damage", true, false) == null, "A sold offer explains its status without projecting another purchase")
	_key(KEY_ESCAPE)
	await _settle()
	state = _make_state("poor")
	await _show(ui, state)
	var before: String = _signature(state)
	await _open(ui)
	var status: Label = ui.find_child("ComparisonStatus", true, false)
	var balance: Label = ui.find_child("ComparisonBalance", true, false)
	_check(status != null and status.text.contains("效果预览") and status.text.contains("尚缺 17 魂屑") and not status.text.contains("已购买"), "Insufficient currency is labelled as an unpaid hypothetical effect preview")
	_check(balance != null and balance.text.contains("当前余额 7") and balance.text.contains("不扣款"), "An unaffordable preview shows the real unchanged balance")
	_check(ui.find_child("ComparisonStat_damage", true, false) != null and _signature(state) == before, "An affordable layer projection remains readable without spending missing currency")
	_key(KEY_ESCAPE)
	await _settle()


func _test_epoch_and_rebuild(ui: GameUI) -> void:
	var state: RunState = _make_state("tradeoff")
	await _show(ui, state)
	var old_source: Button = ui._shop_focus_button("compare:0")
	ui._build_shop()
	old_source.pressed.emit()
	_check(ui._overlay_mode.is_empty(), "An old comparison action cannot address a newly rebuilt shop epoch")
	await _settle()
	var source: Button = ui._shop_focus_button("compare:0")
	state.offers[0] = {"kind": "relic", "id": "moon_charm", "price": 24, "sold": false}
	source.pressed.emit()
	_check(ui._overlay_mode.is_empty(), "An offer snapshot rejects changed stock even before a rebuild")
	state = _make_state("tradeoff")
	await _show(ui, state)
	await _open(ui)
	var stale_close: Button = ui.find_child("CloseRelicComparison", true, false)
	var stale_close_action: Callable = stale_close.pressed.get_connections()[0]["callable"]
	state.collect_souls(1)
	_check(ui._overlay_mode.is_empty(), "Official state changes close the now-stale balance comparison immediately")
	await _settle()
	await _open(ui)
	var status: Label = ui.find_child("ComparisonBalance", true, false)
	_check(status != null and status.text.contains("余额 121 → 97"), "Reopening after a rebuild reads the current balance")
	stale_close_action.call()
	_check(ui._overlay_mode == "relic_comparison", "A stale close callback cannot close a later comparison epoch")
	ui._build_shop()
	_check(ui._overlay_mode.is_empty(), "A direct shop rebuild also invalidates the open comparison")
	await _settle()


func _overlay_owns_focus(ui: GameUI) -> bool:
	var owner: Control = root.gui_get_focus_owner()
	return owner != null and ui._overlay.is_ancestor_of(owner)


static func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, state.rng.state, state.last_error, state._next_rune_uid])


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
