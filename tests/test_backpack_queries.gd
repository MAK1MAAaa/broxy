extends SceneTree
## Forecasts are checked against actual spatial purchases and rune transactions.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_relic_forecasts()
	_test_ranked_weapon_forecast()
	_test_rune_forecasts()
	print("BackpackQueries: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(starter: String = "bone") -> RunState:
	var state := RunState.new()
	state.begin(20261024, starter)
	state.gold = 10000
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var previous: Dictionary = {}
	for item: Dictionary in state.backpack_snapshot()["items"]:
		previous[int(item["uid"])] = true
	state.offers = [{"kind": kind, "id": id, "price": 17, "sold": false}]
	if not state.buy_offer(0):
		_check(false, "The formal fixture purchase fits: " + kind + "/" + id)
		return -1
	for item: Dictionary in state.backpack_snapshot()["items"]:
		if not previous.has(int(item["uid"])):
			return int(item["uid"])
	return -1

func _ranked(state: RunState, kind: String, id: String, rank: int) -> int:
	var current: Array[int] = []
	for copy: int in (1 << (rank - 1)):
		current.append(_buy(state, kind, id))
	for stage: int in range(1, rank):
		var merged: Array[int] = []
		for index: int in range(0, current.size(), 2):
			_check(state.merge_items(current[index + 1], current[index]), "The fixture ranks up through a real manual merge")
			merged.append(current[index])
		current = merged
	return current[0]

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.offers, str(state.rng.state), state._next_rune_uid, state.last_error])

func _test_relic_forecasts() -> void:
	for definition: ContentDef in GameCatalog.relics():
		for rank: int in range(1, 4):
			var state: RunState = _state()
			_ranked(state, "relic", definition.id, rank)
			state.health = state.stat("max_health") * 0.47
			state.offers = [{"kind": "relic", "id": definition.id, "price": 23, "sold": false}]
			var before: String = _signature(state)
			var notifications: Array[int] = [0]
			state.changed.connect(func() -> void: notifications[0] += 1)
			var preview: Dictionary = state.relic_purchase_preview(0)
			_check(not preview.is_empty() and preview["has_projection"] and preview["can_buy"], "A held relic of every rank has a spatial purchase forecast: %s/%d" % [definition.id, rank])
			_check(_signature(state) == before and notifications[0] == 0, "Forecasting does not alter layout, RNG, UID, currency, errors or notifications")
			_check(state.buy_offer(0), "The forecasted relic purchase commits")
			_check(state.gold == int(preview["gold_after"]) and is_equal_approx(state.health, float(preview["health_after"])), "Actual wallet and health match the forecast")
			for change: Dictionary in preview["stat_changes"]:
				_check(is_equal_approx(state.stat(str(change["key"])), float(change["after"])), "The actual rank-weighted and clamped property equals its forecast: " + str(change["key"]))
			for change: Dictionary in preview["weapon_changes"]:
				var slot: int = int(change["slot"])
				var equipped: Dictionary = state.loadout[slot]
				var weapon: ContentDef = GameCatalog.weapon(str(equipped["id"]))
				var expected: float = weapon.damage * BackpackInventory.rank_multiplier(int(equipped.get("rank", 1))) * state.stat("damage")
				_check(is_equal_approx(float(change["damage_after"]), expected), "The weapon forecast includes the stored weapon rank")
				_check(is_equal_approx(float(change["interval_after"]), weapon.cooldown / state.stat("attack_speed")), "The interval forecast uses the same safe attack-speed stat")

func _test_ranked_weapon_forecast() -> void:
	for weapon: ContentDef in GameCatalog.weapons():
		for rank: int in [2, 3]:
			var state: RunState = _state(weapon.id)
			_check(state.expand_backpack() and state.expand_backpack(), "The fixture funds real backpack expansion for large weapon copies")
			var uid: int = _ranked(state, "weapon", weapon.id, rank)
			state.offers = [{"kind": "relic", "id": "damage", "price": 19, "sold": false}]
			var preview: Dictionary = state.relic_purchase_preview(0)
			_check(state.buy_offer(0), "The rank-aware forecast is checked against an actual relic purchase")
			var found: bool = false
			for change: Dictionary in preview["weapon_changes"]:
				var slot: int = int(change["slot"])
				if int(state.loadout[slot]["uid"]) == uid:
					found = true
					_check(is_equal_approx(float(change["damage_after"]), weapon.damage * BackpackInventory.rank_multiplier(rank) * state.stat("damage")), "The relic forecast retains a merged weapon's true rank multiplier")
			_check(found, "The merged weapon is present in the forecast by its stable UID")

func _test_rune_forecasts() -> void:
	for weapon: ContentDef in GameCatalog.weapons():
		for rune: ContentDef in GameCatalog.runes():
			for rank: int in range(1, 4):
				var state: RunState = _state(weapon.id)
				var incoming_uid: int = _ranked(state, "rune", rune.id, rank)
				var previous_uid: int = _buy(state, "rune", "bounce")
				_check(state.equip_rune(state.rune_index_for_uid(previous_uid), 0), "A real socket fixture first equips the previous rune")
				var bag_index: int = state.rune_index_for_uid(incoming_uid)
				var before: String = _signature(state)
				var notifications: Array[int] = [0]
				state.changed.connect(func() -> void: notifications[0] += 1)
				var preview: Dictionary = state.rune_equip_preview(bag_index, 0)
				_check(not preview.is_empty() and int(preview["incoming_rune"]["rank"]) == rank, "Every weapon forecasts each rune's actual stored rank")
				_check(_signature(state) == before and notifications[0] == 0, "Rune forecasting is read-only including spatial ownership and RNG")
				var expected_targets: int = 1 + weapon.innate_pierce + (RuneRules.extra_hits(rank) if rune.id in ["pierce", "bounce"] else 0)
				_check(int(preview["max_direct_targets"]) == expected_targets, "The forecast uses rank-specific direct-target budgets")
				if rune.id == "blast":
					_check(is_equal_approx(float(preview["blast_radius"]), RuneRules.blast_radius(rank)) and is_equal_approx(float(preview["blast_multiplier"]), RuneRules.blast_factor(rank)), "Blast forecasts share production rank-specific radius and damage")
				_check(state.equip_rune(bag_index, 0), "The spatial rune replacement actually commits")
				_check(int(state.loadout[0]["rune"]["uid"]) == incoming_uid and int(state.loadout[0]["rune"]["rank"]) == rank, "The chosen rank and UID reach the weapon socket")
				_check(state.rune_index_for_uid(previous_uid) >= 0 and state.rune_index_for_uid(incoming_uid) == -1, "Replacement returns the previous rune to real backpack space without duplicating the incoming UID")
				_check(state.rune_bag.size() == int(preview["bag_after"]), "The actual loose-rune count equals the forecast")
