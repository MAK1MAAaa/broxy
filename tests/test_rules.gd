extends SceneTree

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_catalog()
	_test_income_and_seed()
	_test_weapon_transactions()
	_test_rune_inventory()
	_test_relic_limits_and_damage()
	_test_damage_history()
	_test_upgrades()
	print("Rules: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _new_run(seed_value: int = 2026) -> RunState:
	var state: RunState = RunState.new()
	state.begin(seed_value, "bone")
	return state

func _buy(state: RunState, kind: String, id: String, price: int = 20) -> bool:
	state.offers = [{"id": id, "kind": kind, "price": price, "sold": false}]
	return state.buy_offer(0)

func _test_catalog() -> void:
	_check(GameCatalog.weapons().size() == 4, "Catalog has four weapons")
	_check(GameCatalog.runes().size() == 3, "Catalog has three runes")
	_check(GameCatalog.relics().size() == 6, "Catalog has six relics")
	_check(GameCatalog.enemies().size() == 5, "Catalog has four enemies and one boss")
	_check(GameCatalog.waves().size() == 8, "Catalog has eight waves")
	var groups: Array = [GameCatalog.weapons(), GameCatalog.runes(), GameCatalog.relics(), GameCatalog.enemies(), GameCatalog.waves()]
	var identifiers: Dictionary = {}
	for group: Array in groups:
		for definition: ContentDef in group:
			_check(not definition.id.is_empty() and not definition.display_name.is_empty(), "Content has an id and display name")
			_check(not identifiers.has(definition.id), "Content ids are unique: " + definition.id)
			identifiers[definition.id] = true
	for definition: ContentDef in GameCatalog.weapons():
		_check(definition.price <= 28 and definition.damage > 0.0 and definition.cooldown > 0.0, "Every first-wave weapon is affordable and functional")
	for number: int in range(1, 9):
		var definition: ContentDef = GameCatalog.wave(number)
		_check(definition.duration == (90.0 if number == 8 else 45.0), "Wave duration matches prototype contract")
		_check(definition.boss_wave == (number == 8), "Only the final wave is a boss wave")
		_check(not definition.spawn_weights.is_empty(), "Wave has enemy spawn weights")
		for enemy_id: String in definition.spawn_weights:
			_check(GameCatalog.enemy(enemy_id) != null, "Wave references an existing enemy")
	_check(GameCatalog.weapon("missing") == null, "Unknown weapon returns null")
	_check(GameCatalog.wave(0) == null and GameCatalog.wave(9) == null, "Out-of-range waves return null")
	var copy: Array[ContentDef] = GameCatalog.weapons()
	copy.clear()
	_check(GameCatalog.weapons().size() == 4, "Catalog list callers cannot clear the catalog")

func _test_income_and_seed() -> void:
	var state: RunState = _new_run()
	state.finish_wave()
	_check(state.gold == 28, "Zero-kill first wave guarantees 28 souls")
	state.finish_wave()
	_check(state.gold == 28, "Finishing a wave twice does not duplicate income")
	state.generate_shop()
	_check(state.offers.size() == 4, "Shop has four offers")
	_check(state.offers[0]["kind"] == "weapon", "First shop guarantees a weapon")
	_check(state.buy_offer(0), "Zero-kill income buys the guaranteed weapon")
	state.next_wave()
	state.generate_shop()
	_check(state.offers[0]["kind"] == "rune", "Second shop guarantees a rune")
	var with_collection: RunState = _new_run()
	with_collection.collect_souls(10)
	with_collection.finish_wave()
	_check(with_collection.gold == 28, "Minimum income tops up collected souls")
	with_collection.next_wave()
	with_collection.collect_souls(50)
	with_collection.finish_wave()
	_check(with_collection.gold == 78, "Strong collection is not double-paid a minimum bonus")
	var recovered: RunState = _new_run()
	recovered.gold = 100
	_check(_buy(recovered, "relic", "vitality"), "Recovery scenario increases maximum health legally")
	recovered.health = 4.0
	recovered.finish_wave()
	_check(recovered.health == 120.0, "Altar restores the actual maximum health after a wave")
	recovered.health = 17.0
	recovered.finish_wave()
	_check(recovered.health == 17.0, "Repeated settlement cannot be used for repeated healing")
	var first: RunState = _new_run(71)
	var second: RunState = _new_run(71)
	first.generate_shop()
	second.generate_shop()
	_check(first.offers == second.offers, "Same seed produces the same first shop")
	first.gold = 500
	second.gold = 500
	var previous_cost: int = first.reroll_cost()
	_check(first.reroll_shop() and second.reroll_shop(), "Funded shops can reroll")
	_check(first.offers == second.offers, "Same actions and seed reproduce rerolls")
	_check(first.gold == 500 - previous_cost, "Reroll charges its displayed price")
	_check(first.reroll_cost() > previous_cost, "Consecutive rerolls become more expensive")
	first.next_wave()
	_check(first.rerolls == 0, "Reroll count resets each wave")
	first.gold = 0
	var previous_offers: Array[Dictionary] = first.offers.duplicate(true)
	_check(not first.reroll_shop() and first.offers == previous_offers, "Unaffordable reroll leaves the shop unchanged")

func _test_weapon_transactions() -> void:
	var state: RunState = _new_run()
	_check(not state.sell_weapon(0), "Last weapon cannot be sold")
	state.gold = 500
	_check(_buy(state, "weapon", "frost", 31), "A weapon can be bought")
	var before_sale: int = state.gold
	_check(state.sell_weapon(1) and state.gold == before_sale + 15, "Weapon sells for floor of half actual paid price")
	_check(_buy(state, "weapon", "ember"), "Second weapon buys")
	_check(_buy(state, "weapon", "scatter"), "Third weapon buys")
	_check(_buy(state, "weapon", "bone"), "Fourth weapon buys")
	var before_reject: int = state.gold
	_check(not _buy(state, "weapon", "bone"), "Fifth weapon is rejected")
	_check(state.gold == before_reject and state.loadout.size() == 4, "Full weapon purchase is atomic")
	state.sell_weapon(3)
	_check(_buy(state, "weapon", "frost"), "A freed weapon slot accepts a purchase")
	var after_purchase: int = state.gold
	_check(not state.buy_offer(0) and state.gold == after_purchase, "A sold offer cannot be purchased twice")
	_check(not state.buy_offer(-1) and not state.sell_weapon(99), "Invalid indices are rejected safely")

func _rune_uids(state: RunState) -> Array[int]:
	var identifiers: Array[int] = []
	for entry: Dictionary in state.rune_bag:
		identifiers.append(int(entry["uid"]))
	for entry: Dictionary in state.loadout:
		var rune: Dictionary = entry.get("rune", {})
		if not rune.is_empty():
			identifiers.append(int(rune["uid"]))
	identifiers.sort()
	return identifiers

func _test_rune_inventory() -> void:
	var state: RunState = _new_run()
	state.gold = 1000
	_check(_buy(state, "weapon", "frost"), "Rune scenario has two weapons")
	_check(_buy(state, "rune", "pierce", 21), "Rune buys into the reserve bag")
	_check(state.equip_rune(0, 0), "Rune equips from bag")
	_check(state.rune_bag.is_empty() and state.loadout[0]["rune"]["id"] == "pierce", "Equipped rune has a single owner")
	for index: int in range(4):
		_check(_buy(state, "rune", "bounce"), "Bag fills up to four runes")
	var before_reject: int = state.gold
	_check(not _buy(state, "rune", "blast"), "Fifth reserve rune is rejected")
	_check(state.gold == before_reject and state.rune_bag.size() == 4, "Full reserve purchase is atomic")
	var before_swap: Array[int] = _rune_uids(state)
	var before_swap_gold: int = state.gold
	_check(state.equip_rune(0, 0), "A full reserve can swap with an equipped rune")
	_check(_rune_uids(state) == before_swap and state.gold == before_swap_gold, "Free rune swap preserves every uid and currency")
	_check(state.rune_bag.size() == 4, "Swap preserves reserve capacity")
	var before_unequip: Dictionary = state.summary()
	_check(not state.unequip_rune(0), "Unequipping into a full reserve is rejected")
	_check(state.summary() == before_unequip, "Failed unequip leaves inventory untouched")
	_check(not state.sell_weapon(0), "Selling a rune-bearing weapon with a full reserve is rejected")
	_check(state.summary() == before_unequip, "Failed weapon sale preserves weapon, rune, and currency")
	var refund: int = int(floorf(float(state.rune_bag[0]["paid"]) * 0.5))
	var before_rune_sale: int = state.gold
	_check(state.sell_rune(0) and state.gold == before_rune_sale + refund, "Reserve rune refunds half actual price")
	_check(state.sell_weapon(0), "Selling a rune-bearing weapon succeeds when reserve has room")
	_check(state.loadout.size() == 1 and state.rune_bag.size() == 4, "Weapon sale returns its rune instead of destroying it")
	var unique: Dictionary = {}
	for uid: int in _rune_uids(state):
		unique[uid] = true
	_check(unique.size() == _rune_uids(state).size(), "Rune transactions never duplicate a uid")

func _test_relic_limits_and_damage() -> void:
	var state: RunState = _new_run()
	state.gold = 1000
	for index: int in range(3):
		_check(_buy(state, "relic", "damage"), "Relic stacks up to three")
	_check(is_equal_approx(state.stat("damage"), 1.45), "Damage relics add to the base multiplier")
	var before_cap: int = state.gold
	_check(not _buy(state, "relic", "damage") and state.gold == before_cap, "Fourth relic stack is rejected without a charge")
	state.health = 50.0
	_check(_buy(state, "relic", "vitality"), "Vitality relic can be purchased")
	_check(state.stat("max_health") == 120.0 and state.health == 70.0, "Vitality increases maximum and current health together")
	_check(_buy(state, "relic", "armor"), "Armor relic can be purchased")
	var dealt: float = state.take_damage(12.0)
	_check(is_equal_approx(dealt, 10.0) and is_equal_approx(state.health, 60.0), "Armor applies exactly once using the documented formula")
	_check(state.take_damage(-10.0) == 0.0, "Negative damage cannot heal")
	state.heal(1000.0)
	_check(state.health == 120.0, "Healing clamps at maximum health")
	state.take_damage(10000.0)
	_check(state.health == 0.0 and state.take_damage(10.0) == 0.0, "Lethal damage clamps to zero")

func _test_upgrades() -> void:
	var state: RunState = _new_run(88)
	_check(state.upgrade_choices().is_empty(), "No upgrade choices before earning a level")
	state.collect_souls(41)
	_check(state.level == 1 and state.pending_upgrades == 0, "Experience below threshold does not level")
	state.collect_souls(1)
	_check(state.level == 2 and state.pending_upgrades == 1 and state.xp == 0, "Level threshold creates one pending upgrade")
	var choices: Array[Dictionary] = state.upgrade_choices()
	_check(choices.size() == 3, "Level-up offers three choices")
	_check(choices == state.upgrade_choices(), "Repeated rendering does not reroll upgrade choices")
	var unique: Dictionary = {}
	for option: Dictionary in choices:
		unique[option["id"]] = true
	_check(unique.size() == 3, "Upgrade choices are distinct")
	_check(not state.choose_upgrade("invalid") and state.pending_upgrades == 1, "Invalid upgrade does not consume pending credit")
	var selected: Dictionary = choices[0]
	var previous_stat: float = state.stat(str(selected["stat"]))
	_check(state.choose_upgrade(str(selected["id"])), "An offered upgrade can be selected")
	_check(is_equal_approx(state.stat(str(selected["stat"])), previous_stat + float(selected["amount"])), "Selected upgrade changes its advertised stat")
	_check(state.pending_upgrades == 0, "Upgrade consumes exactly one pending credit")
	_check(not state.choose_upgrade(str(selected["id"])), "A resolved upgrade cannot be selected twice")
	state.collect_souls(300)
	var initial_pending: int = state.pending_upgrades
	_check(initial_pending > 1, "A large experience pickup preserves every earned upgrade")
	for index: int in range(initial_pending):
		var next_choices: Array[Dictionary] = state.upgrade_choices()
		_check(state.choose_upgrade(str(next_choices[0]["id"])), "Multiple wave-end upgrades resolve one at a time")
	_check(state.pending_upgrades == 0, "All accumulated upgrades can be resolved")
	var same: RunState = _new_run(88)
	same.collect_souls(42)
	_check(same.upgrade_choices() == choices, "Upgrade choices reproduce from the same seed")
	state.begin(3, "not-a-weapon")
	_check(state.loadout[0]["id"] == "bone" and state.level == 1 and state.gold == 0 and state.rune_bag.is_empty(), "New run resets progression and safely falls back to the starter")

func _test_damage_history() -> void:
	var state: RunState = _new_run()
	_check(state.damage_dealt_by_weapon.is_empty() and state.damage_taken == 0.0 and state.hits_taken == 0 and state.last_hit.is_empty(), "New runs start with empty damage history")
	state.gold = 100
	_check(_buy(state, "relic", "armor"), "Damage history scenario acquires armor legally")
	state.wave = 4
	state.elapsed = 17.25
	state.health = 50.0
	var notifications: Array[int] = [0]
	state.changed.connect(func() -> void: notifications[0] += 1)
	var actual: float = state.take_damage(12.0, "caster", "projectile")
	_check(is_equal_approx(actual, 10.0) and is_equal_approx(state.damage_taken, 10.0), "Damage history records post-armor health loss")
	_check(state.hits_taken == 1 and state.last_hit == {"amount": 10.0, "source_id": "caster", "kind": "projectile", "wave": 4, "elapsed": 17.25}, "Last hit records source, type, wave, and elapsed time")
	_check(notifications[0] == 1, "Recording a hit does not add another changed notification")
	state.heal(20.0)
	_check(state.damage_taken == 10.0 and state.hits_taken == 1, "Healing does not erase damage history")
	state.take_damage(1000.0, "boss", "ritual")
	_check(is_equal_approx(state.damage_taken, 70.0) and state.hits_taken == 2 and state.last_hit["amount"] == 60.0, "Lethal overkill records only the remaining health")
	var history: Dictionary = state.last_hit.duplicate(true)
	state.take_damage(0.0)
	state.take_damage(-50.0)
	state.take_damage(20.0)
	_check(state.damage_taken == 70.0 and state.hits_taken == 2 and state.last_hit == history, "Zero, negative, and postmortem damage do not alter history")
	state.damage_dealt_by_weapon["bone"] = 9.0
	var snapshot: Dictionary = state.summary()
	(snapshot["damage_dealt_by_weapon"] as Dictionary)["bone"] = 999.0
	(snapshot["last_hit"] as Dictionary)["source_id"] = "altered"
	_check(state.damage_dealt_by_weapon["bone"] == 9.0 and state.last_hit["source_id"] == "boss", "Summary damage dictionaries are independent copies")
	state.next_wave()
	_check(state.damage_taken == 70.0 and state.hits_taken == 2 and state.damage_dealt_by_weapon["bone"] == 9.0 and state.last_hit["wave"] == 4, "Wave transitions preserve cumulative damage and last-hit provenance")
	state.begin(42, "bone")
	_check(state.damage_dealt_by_weapon.is_empty() and state.damage_taken == 0.0 and state.hits_taken == 0 and state.last_hit.is_empty(), "Starting another run resets every damage statistic")
