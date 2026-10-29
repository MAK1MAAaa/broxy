extends SceneTree
## Native UI checks for definition-driven return flight and the two new relic tradeoffs.

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
	_test_return_facts()
	await _test_shop_and_tooltips(ui)
	for rune: String in ["pierce", "bounce", "blast"]:
		await _test_rune_preview(ui, rune)
	await _test_relic_tradeoffs(ui)
	await _test_eight_source_results(ui)
	ui.queue_free()
	escape.queue_free()
	await _settle()
	print("ReturnRingUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


static func make_fixture(incoming: String = "bounce") -> RunState:
	var state := RunState.new()
	state.begin(20261027, "bone")
	var purchases: Array[Dictionary] = []
	for id: String in ["return_ring", "crescent"]:
		purchases.append({"kind": "weapon", "definition": GameCatalog.weapon(id), "equip": -1})
	for slot: int in 3:
		var rune: String = "blast" if slot == 1 else "bounce" if slot == 2 else "pierce"
		purchases.append({"kind": "rune", "definition": GameCatalog.rune(rune), "equip": slot})
	for id: String in [incoming, "pierce", "blast"]:
		purchases.append({"kind": "rune", "definition": GameCatalog.rune(id), "equip": -1})
	for definition: ContentDef in GameCatalog.relics():
		purchases.append({"kind": "relic", "definition": definition, "equip": -1})
	var budget: int = 200
	for purchase: Dictionary in purchases:
		var definition: ContentDef = purchase["definition"]
		budget += definition.price
	state.collect_souls(budget)
	if not state.expand_backpack() or not state.expand_backpack():
		push_error("Return-ring UI fixture must pay for its six-row backpack")
		return null
	for purchase: Dictionary in purchases:
		var definition: ContentDef = purchase["definition"]
		state.offers = [{"kind": purchase["kind"], "id": definition.id, "price": definition.price, "sold": false}]
		if not state.buy_offer(0):
			push_error("Return-ring UI fixture purchase failed: " + state.last_error)
			return null
		if int(purchase["equip"]) >= 0 and not state.equip_rune(0, int(purchase["equip"])):
			push_error("Return-ring UI fixture equip failed: " + state.last_error)
			return null
	state.wave = 4
	state.pending_upgrades = 0
	state.offers.clear()
	for entry: Array in [["weapon", "return_ring"], ["relic", "blood_pact"], ["relic", "grave_candle"], ["rune", "blast"]]:
		var kind: String = str(entry[0])
		var definition: ContentDef = GameCatalog.weapon(str(entry[1])) if kind == "weapon" else GameCatalog.relic(str(entry[1])) if kind == "relic" else GameCatalog.rune(str(entry[1]))
		state.offers.append({"kind": kind, "id": definition.id, "price": state.shop_price(definition), "sold": false})
	return state


func _test_return_facts() -> void:
	var weapon: ContentDef = GameCatalog.weapon("return_ring")
	var blast_description: String = GameCatalog.rune("blast").description
	_check(blast_description.contains("额外穿透型法器") and blast_description.contains("第二次直接命中"), "The shared blast tooltip identifies weapons that require a second direct hit by their actual behavior")
	for rune: String in ["pierce", "bounce", "blast"]:
		var state: RunState = make_fixture(rune)
		var before: String = _signature(state)
		var preview: Dictionary = state.rune_equip_preview(0, 1)
		_check(preview["returns_to_player"] and preview["return_tracks_player"] and preview["shared_flight_hit_ids"], "Return preview describes one shared-history flight tracking the current player: " + rune)
		_check(is_equal_approx(preview["return_delay"], weapon.return_delay) and is_equal_approx(preview["return_speed"], weapon.return_speed) and is_equal_approx(preview["return_lifetime"], weapon.return_lifetime), "Flight timing, speed and total lifetime come from the weapon definition: " + rune)
		_check(preview["trigger_hit"] == 1 + weapon.innate_pierce and not preview["cooldown_waits_for_return"], "Native penetration precedes rune effects while firing cooldown remains independent: " + rune)
		_check(preview["return_cancelled_by_bounce"] == (rune == "bounce") and preview["return_consumed_on_blast"] == (rune == "blast"), "Only the selected rune exposes its return takeover or consumption rule: " + rune)
		_check(_signature(state) == before, "Flight facts preserve state, rune identities, purchase values and both RNG ownership records: " + rune)
		var ordinary: Dictionary = state.rune_equip_preview(0, 0)
		_check(not ordinary["returns_to_player"] and ordinary["return_delay"] == 0.0 and ordinary["return_speed"] == 0.0 and ordinary["return_lifetime"] == 0.0, "A normal weapon keeps zero return defaults: " + rune)


func _test_shop_and_tooltips(ui: GameUI) -> void:
	var state: RunState = make_fixture()
	await _show(ui, state)
	_check(state.loadout.size() == 3 and state.rune_bag.size() == 3 and state.relic_counts.size() == GameCatalog.relics().size() and state.backpack_snapshot()["used_cells"] == 36 and _controls_fit(ui._page), "Three weapons, loose runes and every relic occupy the legal 36-cell backpack inside the native shop")
	var offer: Control = ui.find_child("Offer1", true, false)
	var description: Label = offer.find_child("OfferDescription", true, false)
	var definition: ContentDef = GameCatalog.weapon("return_ring")
	_check(description.text.contains("法器") and description.text.contains("往返穿透") and description.tooltip_text == definition.description and description.tooltip_text.contains("%.2f秒" % definition.return_delay) and description.tooltip_text.contains("第二个直接命中") and description.tooltip_text.contains("成功弹射"), "The compact return-flight trait retains definition-driven return timing and second-hit rules in its full tooltip")
	_check(root.get_visible_rect().encloses(offer.get_global_rect()), "The concise return card remains inside the native two-row stock grid")
	for id: String in ["return_ring", "blood_pact", "grave_candle"]:
		var content: ContentDef = GameCatalog.weapon(id) if id == "return_ring" else GameCatalog.relic(id)
		var icon: Texture2D = ui._icon_texture(content)
		_check(icon != null and icon.get_width() == 64 and icon.get_height() == 64, "New content resolves its original native-size icon: " + id)
	var tooltip: String = ui._equipment_tooltip(state.loadout[1])
	_check(tooltip.contains("当前玩家") and tooltip.contains("不等待回收") and tooltip.contains("第2次直接命中") and tooltip.contains("爆破后弹体消失"), "Equipped return-ring tooltips explain real return tracking, timing and blast consumption")
	await _accept(ui, "bag:%d" % int(state.rune_bag[0]["uid"]))
	var guide: Label = ui.find_child("RuneGuide", true, false)
	_check(guide != null and guide.text.contains(GameCatalog.rune("bounce").display_name) and guide.text.contains("+%d跳" % RuneRules.extra_hits(1)) and guide.tooltip_text.contains("最多追加%d跳" % RuneRules.extra_hits(1)) and not guide.text.contains("月镰"), "The selected rune shows its real extra jumps and retains full ranked rules in its tooltip")


func _test_rune_preview(ui: GameUI, rune: String) -> void:
	var state: RunState = make_fixture(rune)
	await _show(ui, state)
	await _accept(ui, "bag:%d" % int(state.rune_bag[0]["uid"]))
	var incoming: Dictionary = state.rune_bag[0].duplicate(true)
	var before: String = _signature(state)
	var source: Button = ui._shop_focus_button("rune_preview:1")
	if rune == "blast":
		source.grab_focus()
		await _settle()
		_click(source)
		await _settle()
	else:
		await _accept(ui, "rune_preview:1")
	_check(ui._overlay_mode == "rune_equip_comparison" and ui._selected_rune == 0, "Native input opens a return-ring preview while keeping the chosen rune: " + rune)
	var trigger: Label = ui.find_child("RuneEquipTrigger", true, false)
	var flight: Label = ui.find_child("RuneEquipReturnFlight", true, false)
	var cooldown: Label = ui.find_child("RuneEquipReturnCooldown", true, false)
	_check(trigger != null and trigger.text.contains("第2次直接命中"), "Every return-ring rune starts after its native first penetration: " + rune)
	_check(flight != null and flight.text.contains("0.60秒") and flight.text.contains("460") and flight.text.contains("2.4秒") and flight.text.contains("同一目标不重复"), "The return preview exposes real timing, total lifetime and shared hit exclusions: " + rune)
	_check(cooldown != null and cooldown.text.contains("冷却独立") and cooldown.text.contains("不等待回收"), "The preview does not imply that catching gates the next cast: " + rune)
	if rune == "bounce":
		var takeover: Label = ui.find_child("RuneEquipBounceTakeover", true, false)
		var scales: Label = ui.find_child("RuneEquipBounceScales", true, false)
		_check(takeover != null and takeover.text.contains("永久取消返航") and takeover.text.contains("当时的速度"), "Successful bounce permanently takes over the return trajectory")
		_check(scales != null and scales.text.contains("100% → 100% → 75% → 56.25%"), "Return-ring bounce keeps two native full hits before shared decay")
	elif rune == "blast":
		var consumed: Label = ui.find_child("RuneEquipBlastConsumesReturn", true, false)
		var delayed: Label = ui.find_child("RuneEquipDelayedBlast", true, false)
		_check(consumed != null and consumed.text.contains("消失") and consumed.text.contains("不再返航"), "Blast consumes the return projectile")
		_check(delayed != null and delayed.text.contains("只命中1个目标不会爆破"), "A lone target never triggers return-ring blast")
	else:
		_check(ui.find_child("RuneEquipBounceTakeover", true, false) == null and ui.find_child("RuneEquipBlastConsumesReturn", true, false) == null, "Pierce preview does not inherit another rune's takeover rules")
	_check(_signature(state) == before, "Reading return behavior remains a pure preview: " + rune)
	var scroll: ScrollContainer = ui.find_child("RuneEquipScroll", true, false)
	var close: Button = ui.find_child("CloseRuneEquipComparison", true, false)
	_check(scroll != null and close != null and root.get_visible_rect().encloses(scroll.get_global_rect()) and root.get_visible_rect().encloses(close.get_global_rect()), "Long flight and rune rules keep their viewport and return action inside 720p: " + rune)
	if scroll != null:
		scroll.grab_focus()
		_key(KEY_END)
		await _settle()
		var scope: Label = ui.find_child("RuneEquipScope", true, false)
		_check(scope != null and scroll.get_global_rect().grow(1).encloses(scope.get_global_rect()), "Keyboard End reaches the scope and no-DPS notice even when flight details overflow: " + rune)
	_key(KEY_ESCAPE)
	await _settle()
	_check(ui._overlay_mode.is_empty() and root.gui_get_focus_owner() == source and ui._selected_rune == 0, "Escape restores the return-ring source and reserve selection: " + rune)
	await _accept(ui, "bag_equip:%d" % int(state.loadout[1]["uid"]))
	_check(state.loadout[1]["rune"] == incoming and state.rune_bag.size() == 3 and ui._selected_rune == -1 and state.backpack_snapshot()["used_cells"] == 36, "The return-ring rune swaps from the full backpack with its original UID, paid record and occupied cells: " + rune)


func _test_relic_tradeoffs(ui: GameUI) -> void:
	var state: RunState = make_fixture()
	var sold: int = 0
	for item: Dictionary in state.backpack_snapshot()["items"]:
		if str(item["kind"]) == "relic" and str(item["id"]) in ["fold_clasp", "echo_stone"]:
			_check(state.sell_item(int(item["uid"])), "The tradeoff fixture legally sells each new single-cell skill relic before showing the shop")
			sold += 1
	_check(sold == 2 and int(state.backpack_snapshot()["used_cells"]) == 34 and state.purchase_error(1).is_empty(), "Two real sales free contiguous cells for the blood pact's actual two-cell footprint")
	await _show(ui, state)
	var before: String = _signature(state)
	await _accept(ui, "compare:1")
	var damage: Label = ui.find_child("ComparisonStat_damage", true, false)
	var speed: Label = ui.find_child("ComparisonStat_attack_speed", true, false)
	var weapon: Label = ui.find_child("ComparisonWeapon1Interval", true, false)
	_check(damage != null and damage.text == "增加约 0.30 倍" and damage.get_theme_color("font_color").is_equal_approx(GameUI.CYAN), "Blood pact advertises its rounded positive damage change")
	_check(speed != null and speed.text == "减少约 0.10 倍" and speed.get_theme_color("font_color").is_equal_approx(GameUI.RED), "Blood pact advertises its rounded negative attack-speed change")
	_check(weapon != null and weapon.text.contains("更慢") and weapon.get_theme_color("font_color").is_equal_approx(GameUI.RED), "The existing return weapon shows the actual slower nominal interval")
	_check(_signature(state) == before, "The blood-pact comparison never purchases or slows the current build")
	_key(KEY_ESCAPE)
	await _settle()
	await _accept(ui, "compare:2")
	var pickup: Label = ui.find_child("ComparisonStat_pickup_radius", true, false)
	var move: Label = ui.find_child("ComparisonStat_move_speed", true, false)
	_check(pickup != null and pickup.text.contains("增加 38") and pickup.get_theme_color("font_color").is_equal_approx(GameUI.CYAN), "Grave candle exposes its increased pickup range")
	_check(move != null and move.text.contains("减少 8") and move.get_theme_color("font_color").is_equal_approx(GameUI.RED), "Grave candle exposes its movement-speed tradeoff")
	_check(_signature(state) == before, "The grave-candle comparison does not move currency or attributes")
	_key(KEY_ESCAPE)
	await _settle()
	var projected: Dictionary = state.relic_purchase_preview(1)
	await _accept(ui, "buy:1")
	_check(ui._overlay_mode.is_empty() and state.gold == int(projected["gold_after"]) and int(state.relic_counts["blood_pact"]) == int(projected["stack_after"]), "Direct blood-pact purchase still completes without another confirmation")


func _test_eight_source_results(ui: GameUI) -> void:
	var state: RunState = make_fixture()
	state.damage_dealt_by_weapon.clear()
	for index: int in GameCatalog.weapons().size():
		state.damage_dealt_by_weapon[GameCatalog.weapons()[index].id] = float(index + 1) * 10.0
	ui.bind(state)
	ui.show_result(false, "归魂环与遗物扩充的八来源结算夹具。", {})
	await _settle()
	_check(_controls_fit(ui._page), "Every recorded weapon contribution and result action fits in the eight-source 720p layout")
	for definition: ContentDef in GameCatalog.weapons():
		_check(ui.find_child("Damage_" + definition.id, true, false) != null, "The result retains a real recorded contribution row for " + definition.id)


func _show(ui: GameUI, state: RunState) -> void:
	ui.bind(state)
	ui.show_shop()
	await _settle()


func _accept(ui: GameUI, focus_id: String) -> Button:
	var button: Button = ui._shop_focus_button(focus_id)
	_check(button != null, "The native fixture exposes " + focus_id)
	if button != null:
		button.grab_focus()
		_key(KEY_ENTER)
		await _settle()
	return button


func _controls_fit(node: Node) -> bool:
	if node is ScrollContainer:
		return root.get_visible_rect().grow(1).encloses(node.get_global_rect())
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		if not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
			return false
		if node is Label and node.size.y + 1.0 < node.get_minimum_size().y:
			return false
	for child: Node in node.get_children():
		if not _controls_fit(child):
			return false
	return true


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
