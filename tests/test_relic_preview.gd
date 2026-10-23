extends SceneTree
## Purchase forecasts must agree with the real transaction without spending or rolling.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_catalog_projections()
	_test_tradeoff_values()
	_test_projection_boundaries()
	_test_health_projection()
	_test_merged_attribute()
	_test_invalid_offers()
	print("RelicPreview: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _offer(definition: ContentDef) -> Dictionary:
	return {"kind": "relic", "id": definition.id, "price": definition.price, "sold": false}

func _buy(state: RunState, kind: String, id: String) -> bool:
	var definition: ContentDef = GameCatalog.weapon(id) if kind == "weapon" else GameCatalog.rune(id) if kind == "rune" else GameCatalog.relic(id)
	state.offers = [{"kind": kind, "id": id, "price": definition.price, "sold": false}]
	return state.buy_offer(0)

func _fixture(id: String, layers: int, upgraded: bool) -> RunState:
	var state: RunState = RunState.new()
	state.begin(20261023, "bone")
	state.collect_souls(4000)
	if upgraded:
		for option: Dictionary in RunState.UPGRADE_POOL:
			state._upgrade_options = [option.duplicate(true)]
			_check(state.choose_upgrade(str(option["id"])), "Fixture legally applies each existing upgrade: " + str(option["id"]))
	for weapon: String in ["storm", "comet", "crescent"]:
		_check(_buy(state, "weapon", weapon), "Fixture legally fills a weapon slot: " + weapon)
	_check(_buy(state, "rune", "pierce") and state.equip_rune(0, 0) and _buy(state, "rune", "bounce"), "Fixture retains both equipped and reserve rune identities")
	for relic: String in ["damage", "haste", "vitality", "pilgrim"]:
		if relic != id:
			_check(_buy(state, "relic", relic), "Fixture combines other relic effects: " + relic)
	for layer: int in layers:
		_check(_buy(state, "relic", id), "Fixture obtains target stacks through real purchases: " + id)
	state.offers = [_offer(GameCatalog.relic(id))]
	state.health = state.stat("max_health") * 0.45
	state.upgrade_choices()
	state.last_error = "保留前次操作错误"
	return state

func _snapshot(state: RunState) -> Dictionary:
	var stats: Dictionary = {}
	for key: String in RunState.BASE_STATS:
		stats[key] = state.stat(key)
	return {
		"summary": state.summary(), "stats": stats, "offers": state.offers.duplicate(true),
		"rng_state": state.rng.state, "rng_seed": state.rng.seed, "uid": state._next_rune_uid,
		"bonuses": state._upgrade_bonuses.duplicate(true), "choices": state._upgrade_options.duplicate(true),
		"wave_income": state._wave_income, "wave_finished": state._wave_finished,
		"rerolls": state.rerolls, "error": state.last_error,
	}

func _query(state: RunState, index: int = 0) -> Dictionary:
	var before: Dictionary = _snapshot(state)
	var emissions: Array[int] = [0]
	var observe: Callable = func() -> void: emissions[0] += 1
	state.changed.connect(observe)
	var preview: Dictionary = state.relic_purchase_preview(index)
	var stable: bool = true
	for repetition: int in 3:
		stable = state.relic_purchase_preview(index) == preview and stable
	_check(stable and _snapshot(state) == before and emissions[0] == 0, "Repeated forecasts preserve every state field, cached choices, both RNG fields, rune UID and changed signal")
	state.changed.disconnect(observe)
	return preview

func _stat_change(preview: Dictionary, key: String) -> Dictionary:
	for change: Dictionary in preview["stat_changes"]:
		if str(change["key"]) == key:
			return change
	return {}

func _test_catalog_projections() -> void:
	for definition: ContentDef in GameCatalog.relics():
		for layers: int in 3:
			for upgraded: bool in [false, true]:
				_compare_purchase(definition.id, layers, upgraded)

func _compare_purchase(id: String, layers: int, upgraded: bool) -> void:
	var state: RunState = _fixture(id, layers, upgraded)
	var oracle: RunState = _fixture(id, layers, upgraded)
	_check(_snapshot(state) == _snapshot(oracle), "Forecast and transaction fixtures begin independently with identical state")
	var before: Dictionary = _snapshot(state)
	var preview: Dictionary = _query(state)
	var label: String = "%s/%d/upgraded=%s" % [id, layers, upgraded]
	_check(preview["id"] == id and preview["can_buy"] and preview["error"] == state.purchase_error(0) and preview["has_projection"], "Affordable forecasts retain formal eligibility and content identity: " + label)
	_check(int(preview["stack_before"]) == layers and int(preview["stack_after"]) == layers + 1 and int(preview["shortfall"]) == 0, "Forecast exposes the next permitted layer and zero shortfall: " + label)
	_check(oracle.buy_offer(0), "Independent real purchase succeeds: " + label)
	_check(int(preview["price"]) == int(state.offers[0]["price"]) and int(preview["gold_before"]) == state.gold and int(preview["gold_after"]) == oracle.gold, "Forecast wallet matches the actual transaction: " + label)
	_check(float(preview["health_before"]) == state.health and float(preview["health_after"]) == oracle.health, "Forecast health exactly matches the production max-health transaction: " + label)
	var expected_keys: Dictionary = {}
	var definition: ContentDef = GameCatalog.relic(id)
	for key: String in [definition.stat, definition.bonus_stat]:
		if not key.is_empty():
			expected_keys[key] = true
	_check((preview["stat_changes"] as Array).size() == expected_keys.size(), "Only the primary and secondary affected keys appear, merged once: " + label)
	for key: String in RunState.BASE_STATS:
		var change: Dictionary = _stat_change(preview, key)
		if expected_keys.has(key):
			_check(not change.is_empty() and float(change["before"]) == state.stat(key) and float(change["after"]) == oracle.stat(key) and is_equal_approx(float(change["delta"]), oracle.stat(key) - state.stat(key)), "Forecast property agrees with the real purchase after all upgrades and relics: " + label + "/" + key)
		else:
			_check(change.is_empty() and state.stat(key) == oracle.stat(key), "Unrelated properties are neither advertised nor modified: " + label + "/" + key)
	_check((preview["weapon_changes"] as Array).size() == state.loadout.size(), "Every real weapon slot receives a projection: " + label)
	for slot: int in state.loadout.size():
		var change: Dictionary = preview["weapon_changes"][slot]
		var weapon_id: String = str(state.loadout[slot]["id"])
		var weapon: ContentDef = GameCatalog.weapon(weapon_id)
		_check(int(change["slot"]) == slot and change["id"] == weapon_id and int(change["shots"]) == weapon.shots, "Weapon projections retain slot identity and configured volley size: " + label)
		_check(float(change["damage_before"]) == weapon.damage * state.stat("damage") and float(change["damage_after"]) == weapon.damage * oracle.stat("damage"), "Per-projectile damage uses the same real multiplier as CombatSim: " + label)
		_check(float(change["interval_before"]) == weapon.cooldown / state.stat("attack_speed") and float(change["interval_after"]) == weapon.cooldown / oracle.stat("attack_speed"), "Nominal intervals use the real cooldown division rather than a DPS estimate: " + label)
	_check(_snapshot(state) == before, "Reading every forecast result never mutates the source run: " + label)

func _test_tradeoff_values() -> void:
	var state: RunState = RunState.new()
	state.begin(123, "comet")
	state.collect_souls(300)
	_check(_buy(state, "relic", "damage") and _buy(state, "relic", "haste"), "Tradeoff example obtains existing offensive relics legally")
	state.offers = [_offer(GameCatalog.relic("hourglass"))]
	var preview: Dictionary = _query(state)
	var damage: Dictionary = _stat_change(preview, "damage")
	var speed: Dictionary = _stat_change(preview, "attack_speed")
	_check(is_equal_approx(float(damage["before"]), 1.15) and is_equal_approx(float(damage["after"]), 1.09) and is_equal_approx(float(speed["before"]), 1.12) and is_equal_approx(float(speed["after"]), 1.34), "Hourglass shows additive positive and negative changes rather than multiplying current bonuses")
	var weapon: Dictionary = preview["weapon_changes"][0]
	_check(is_equal_approx(float(weapon["damage_before"]), 62.1) and is_equal_approx(float(weapon["damage_after"]), 58.86) and is_equal_approx(float(weapon["interval_before"]), 1.55 / 1.12) and is_equal_approx(float(weapon["interval_after"]), 1.55 / 1.34), "Hourglass exposes Comet's actual per-hit reduction and nominal interval improvement")
	state.offers = [_offer(GameCatalog.relic("pilgrim"))]
	preview = _query(state)
	_check(_stat_change(preview, "move_speed")["after"] == 232.0 and _stat_change(preview, "pickup_radius")["after"] == 90.0, "Pilgrim exposes both mobility and collection changes")

func _test_projection_boundaries() -> void:
	var poor: RunState = _fixture("hourglass", 1, true)
	poor.gold = 3
	var oracle: RunState = _fixture("hourglass", 1, true)
	oracle.gold = GameCatalog.relic("hourglass").price
	var preview: Dictionary = _query(poor)
	_check(not preview["can_buy"] and preview["error"] == poor.purchase_error(0) and preview["has_projection"] and int(preview["shortfall"]) == 21, "An unaffordable unsold relic has a clearly hypothetical projection and formal shortfall")
	_check(preview["gold_before"] == 3 and preview["gold_after"] == 3 and preview["stack_before"] == 1 and preview["stack_after"] == 2, "A hypothetical next stack never advertises nonexistent spending")
	_check(oracle.buy_offer(0) and float(_stat_change(preview, "damage")["after"]) == oracle.stat("damage") and float(_stat_change(preview, "attack_speed")["after"]) == oracle.stat("attack_speed"), "Poor-run hypothetical effects agree with the independently funded real transaction")
	for sold: bool in [false, true]:
		for empty_wallet: bool in [false, true]:
			var state: RunState = _fixture("bulwark", 1 if sold else 3, false)
			state.offers[0]["sold"] = sold
			if empty_wallet:
				state.gold = 0
			preview = _query(state)
			_check(not preview["can_buy"] and not preview["has_projection"] and preview["error"] == state.purchase_error(0), "Sold and capped forecasts retain the exact formal rejection order")
			_check(preview["stack_after"] == preview["stack_before"] and preview["gold_after"] == state.gold and preview["health_after"] == state.health and (preview["stat_changes"] as Array).is_empty() and (preview["weapon_changes"] as Array).is_empty(), "Sold or capped relics never project another stack, healing, weapon changes or spending")
	var free: RunState = _fixture("moon_charm", 0, false)
	free.gold = 0
	free.offers = [{"kind": "relic", "id": "moon_charm"}]
	preview = _query(free)
	_check(preview["can_buy"] and preview["price"] == 0 and preview["gold_after"] == 0 and preview["shortfall"] == 0 and preview["has_projection"], "Missing optional offer fields retain the production free-unsold defaults")

func _test_health_projection() -> void:
	for id: String in ["vitality", "bulwark", "hourglass"]:
		for full_health: bool in [false, true]:
			var state: RunState = _fixture(id, 2, true)
			var oracle: RunState = _fixture(id, 2, true)
			state.health = state.stat("max_health") if full_health else 20.0
			oracle.health = state.health
			var preview: Dictionary = _query(state)
			_check(oracle.buy_offer(0) and float(preview["health_after"]) == oracle.health and oracle.health <= oracle.stat("max_health"), "Full or wounded health projects exactly the legal maximum-health increment: " + id)
	var poor: RunState = _fixture("bulwark", 0, false)
	poor.gold = 0
	poor.health = 20.0
	var preview: Dictionary = _query(poor)
	_check(preview["health_before"] == 20.0 and preview["health_after"] == 32.0 and poor.health == 20.0, "Unfunded bulwark shows hypothetical healing without actually restoring health")

func _test_merged_attribute() -> void:
	# A temporary resource fixture exercises the generic two-fields/one-key rule.
	var definition: ContentDef = GameCatalog.relic("moon_charm")
	var original_key: String = definition.bonus_stat
	definition.bonus_stat = definition.stat
	_compare_purchase("moon_charm", 1, true)
	var state: RunState = _fixture("moon_charm", 0, false)
	var preview: Dictionary = _query(state)
	_check((preview["stat_changes"] as Array).size() == 1 and is_equal_approx(float(_stat_change(preview, "damage")["delta"]), 0.14), "Coincident primary and bonus keys merge into one cumulative change")
	definition.bonus_stat = original_key

func _test_invalid_offers() -> void:
	var state: RunState = _fixture("moon_charm", 0, true)
	_check(_query(state, -1).is_empty() and _query(state, 1).is_empty(), "Out-of-range offer indices have no preview")
	for offer: Dictionary in [
		{}, {"kind": "weapon", "id": "bone", "price": 18},
		{"kind": "rune", "id": "pierce", "price": 18},
		{"kind": "unknown", "id": "moon_charm"},
		{"kind": "relic", "id": "missing"}, {"kind": "relic"},
	]:
		state.offers = [offer]
		_check(_query(state).is_empty(), "Non-relic and unknown catalog offers return an empty read-only projection")
	state.offers.clear()
	_check(_query(state).is_empty(), "An empty shop has no forecast")
