extends SceneTree
## Inspect real shop controls and compare displayed weapon values to live combat shots.

const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	root.size = Vector2i(1280, 720)
	var ui := GameUI.new()
	root.add_child(ui)
	await _test_unequip_and_equip(ui)
	await _test_weapon_details(ui)
	ui.queue_free()
	await _settle()
	print("ShopDetails: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_unequip_and_equip(ui: GameUI) -> void:
	var state := RunState.new()
	state.begin(20261022, "bone")
	state.collect_souls(1000)
	var bought: bool = _purchase(state, "rune", "pierce")
	bought = state.equip_rune(0, 0) and bought
	for id: String in ["bounce", "blast", "pierce", "bounce"]:
		bought = _purchase(state, "rune", id) and bought
	_check(bought and state.rune_bag.size() == 4, "Legal purchases create an equipped rune and a full reserve")
	var equipped_uid: int = int(state.loadout[0]["rune"]["uid"])
	var sold_uid: int = int(state.rune_bag[0]["uid"])
	state.offers = _weapon_offers()
	ui.bind(state)
	ui.show_shop()
	await _settle()
	var unequip: Button = _shop_button(ui, "unequip:0")
	_check(unequip != null, "The equipped weapon exposes its unequip action")
	if unequip == null:
		return
	unequip.grab_focus()
	var before: Dictionary = state.summary()
	_key(KEY_ENTER)
	await _settle()
	_check(state.summary() == before, "A rejected full-reserve unequip preserves inventory, currency and rune ownership")
	_check(ui._toast.visible and ui._toast.text == "备用符文已满。", "A full-reserve unequip shows its real rejection reason")
	_check(_focus_id() == "unequip:0", "A rejected unequip keeps keyboard focus on the original action")
	var sell: Button = _shop_button(ui, "sell_rune:%d" % sold_uid)
	_check(sell != null, "The full reserve has an available rune sale action")
	if sell == null:
		return
	sell.grab_focus()
	_key(KEY_ENTER)
	await _settle()
	unequip = _shop_button(ui, "unequip:0")
	if unequip == null:
		_check(false, "Freeing reserve capacity preserves the equipped weapon action")
		return
	unequip.grab_focus()
	_key(KEY_ENTER)
	await _settle()
	_check(state.loadout[0]["rune"].is_empty() and state.rune_bag.size() == 4, "An unequip succeeds after one reserve slot is freed")
	_check(_focus_id() == "rune:%d" % equipped_uid, "A successful unequip focuses the exact returned rune UID")
	_check(_bag_has_uid(state, equipped_uid) and not _bag_has_uid(state, sold_uid), "Unequip returns the original rune without reviving the sold reserve item")
	_key(KEY_ENTER)
	await _settle()
	_check(_focus_id() == "equip:0", "Selecting the returned rune offers its actual equipment target")
	_key(KEY_ENTER)
	await _settle()
	_check(int(state.loadout[0]["rune"].get("uid", -1)) == equipped_uid, "The returned rune can be equipped through the real Return path")
	var expected: String = "%s已装入%s。" % [GameCatalog.rune("pierce").display_name, GameCatalog.weapon("bone").display_name]
	_check(ui._toast.text.begins_with(expected), "Equip confirmation names the rune as the item installed into the weapon")
	_check(_focus_id() == "unequip:0", "Successful equip restores the changed weapon's unequip action")


func _test_weapon_details(ui: GameUI) -> void:
	var state := RunState.new()
	state.begin(90310, "bone")
	state.collect_souls(1000)
	var bought: bool = true
	for id: String in ["frost", "ember", "scatter"]:
		bought = _purchase(state, "weapon", id) and bought
	for id: String in ["damage", "haste", "damage", "haste"]:
		bought = _purchase(state, "relic", id) and bought
	var upgrades_chosen: int = 0
	while state.pending_upgrades > 0:
		var choices: Array[Dictionary] = state.upgrade_choices()
		var choice: Dictionary = choices[0]
		for option: Dictionary in choices:
			if str(option["id"]) == "damage" or str(option["id"]) == "haste":
				choice = option
				break
		if not state.choose_upgrade(str(choice["id"])):
			break
		upgrades_chosen += 1
	_check(bought and state.loadout.size() == 4 and upgrades_chosen > 0 and state.pending_upgrades == 0, "Weapon details use legally bought relics and actually offered level upgrades")
	var first: Array[Dictionary] = _combat_readings(state)
	state.offers = _weapon_offers()
	ui.bind(state)
	ui.show_shop()
	await _settle()
	_assert_visible_details(ui, first)
	_check(_controls_fit(ui), "All four detailed offers and equipment rows remain inside the 1280 by 720 shop")
	var rune_bought: bool = _purchase(state, "rune", "bounce")
	var equipped: bool = state.equip_rune(0, 0)
	state.offers = _weapon_offers()
	await _settle()
	_check(rune_bought and equipped, "A legal rune purchase upgrades the same equipment fixture")
	var bone_name: Label = _equipment_name(ui, 0, GameCatalog.weapon("bone").display_name)
	var bone_stats: String = str(first[0]["text"])
	_check(bone_name != null and bone_name.tooltip_text.contains(GameCatalog.weapon("bone").description) and bone_name.tooltip_text.contains(bone_stats) and bone_name.tooltip_text.contains(GameCatalog.rune("bounce").description), "An equipped weapon name retains its base behavior, current numbers and rune behavior in one tooltip")
	var increased: bool = _purchase(state, "relic", "damage")
	increased = _purchase(state, "relic", "haste") and increased
	var second: Array[Dictionary] = _combat_readings(state)
	state.offers = _weapon_offers()
	await _settle()
	_check(increased and float(second[0]["damage"]) > float(first[0]["damage"]) and float(second[0]["interval"]) < float(first[0]["interval"]), "Subsequent legal relic purchases change actual projectile damage and weapon cooldown")
	_assert_visible_details(ui, second)
	_check(_controls_fit(ui), "Refreshed weapon numbers keep all shop controls and descriptions readable")


func _combat_readings(state: RunState) -> Array[Dictionary]:
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(0.0)
	var target: CombatSim.Enemy = sim.spawn_enemy("tank", Vector2(1000, 365))
	target.health = 100000.0
	target.max_health = target.health
	sim.step(STEP, Vector2.ZERO)
	var result: Array[Dictionary] = []
	for index: int in state.loadout.size():
		var id: String = str(state.loadout[index]["id"])
		var damage: float = 0.0
		var pellets: int = 0
		for shot: CombatSim.Shot in sim.shots:
			if shot.active and not shot.hostile and shot.source == id:
				damage = shot.damage
				pellets += 1
		var interval: float = sim._cooldowns[index]
		_check(pellets > 0 and damage > GameCatalog.weapon(id).damage and interval < GameCatalog.weapon(id).cooldown, "The formal combat step fires a buffed weapon with an accelerated cooldown: " + id)
		result.append({"id": id, "damage": damage, "pellets": pellets, "interval": interval,
			"text": "每枚 %.1f伤害 · %d枚/次 · 间隔 %.2f秒" % [damage, pellets, interval]})
	return result


func _assert_visible_details(ui: GameUI, readings: Array[Dictionary]) -> void:
	for index: int in readings.size():
		var reading: Dictionary = readings[index]
		var definition: ContentDef = GameCatalog.weapon(str(reading["id"]))
		var offer: Node = ui.find_child("Offer%d" % (index + 1), true, false)
		var numbers: String = str(reading["text"])
		_check(offer != null and _has_label(offer, numbers), "The visible offer matches live per-projectile damage, volley count and cooldown: " + definition.id)
		var name_label: Label = _equipment_name(ui, index, definition.display_name)
		_check(name_label != null and name_label.tooltip_text.contains(definition.description) and name_label.tooltip_text.contains(numbers), "Every equipment name exposes its base description and current numbers: " + definition.id)
		_check(name_label != null and name_label.focus_mode == Control.FOCUS_NONE and name_label.mouse_filter != Control.MOUSE_FILTER_IGNORE, "Equipment detail tooltips work without taking keyboard focus: " + definition.id)


func _purchase(state: RunState, kind: String, id: String) -> bool:
	var definition: ContentDef
	match kind:
		"weapon": definition = GameCatalog.weapon(id)
		"rune": definition = GameCatalog.rune(id)
		"relic": definition = GameCatalog.relic(id)
	if definition == null:
		return false
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	return state.buy_offer(0)


func _weapon_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for id: String in ["bone", "frost", "ember", "scatter"]:
		var definition: ContentDef = GameCatalog.weapon(id)
		offers.append({"kind": "weapon", "id": definition.id, "price": definition.price, "sold": false})
	return offers


func _bag_has_uid(state: RunState, uid: int) -> bool:
	for rune: Dictionary in state.rune_bag:
		if int(rune["uid"]) == uid:
			return true
	return false


func _shop_button(ui: GameUI, focus_id: String) -> Button:
	return ui._shop_focus_button(focus_id)


func _equipment_name(ui: GameUI, index: int, text: String) -> Label:
	var sell: Button = _shop_button(ui, "sell_weapon:%d" % index)
	return null if sell == null else _find_label(sell.get_parent(), text)


func _find_label(node: Node, text: String) -> Label:
	if node is Label and node.is_visible_in_tree() and node.text == text:
		return node as Label
	for child: Node in node.get_children():
		var found: Label = _find_label(child, text)
		if found != null:
			return found
	return null


func _has_label(node: Node, text: String) -> bool:
	return _find_label(node, text) != null


func _controls_fit(node: Node) -> bool:
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		var control: Control = node
		var rect: Rect2 = control.get_global_rect()
		if rect.position.x < -1.0 or rect.position.y < -1.0 or rect.end.x > 1281.0 or rect.end.y > 721.0 or control.size.y + 1.0 < control.get_minimum_size().y:
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


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
