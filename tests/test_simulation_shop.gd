extends "res://tests/simulate_runs.gd"
## Observation regression: frozen shop-v1 decisions plus inspectable rejection fixtures.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_offer_evaluations()
	_test_vitality_exception()
	_test_snapshots_and_ties()
	_test_reroll_stops()
	_test_legacy_equivalence()
	print("ShopObservation: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _new_state(seed_value: int = 2026) -> RunState:
	var state: RunState = RunState.new()
	state.begin(seed_value, "bone")
	state.gold = 1000
	return state

func _offer(kind: String, id: String, price: int = 20, sold: bool = false) -> Dictionary:
	return {"kind": kind, "id": id, "price": price, "sold": sold}

func _four_weapons(state: RunState, rune_id: String = "") -> void:
	state.loadout.clear()
	for index: int in range(4):
		var rune: Dictionary = {} if rune_id.is_empty() else {"id": rune_id, "paid": 20, "uid": index + 1}
		state.loadout.append({"id": "bone", "paid": 20, "rune": rune})

func _deny(state: RunState, offer: Dictionary, reason: String) -> void:
	var evaluation: Dictionary = _evaluate_offer(state, offer, "pierce")
	_check(evaluation["score"] == null and evaluation["reason"] == reason, "Offer rejection is explicit: " + reason)
	_check(_offer_score(state, offer, "pierce") == -INF, "Rejected observation preserves -INF selection: " + reason)

func _test_offer_evaluations() -> void:
	var state: RunState = _new_state()
	_deny(state, _offer("weapon", "bone", 2000, true), "sold")
	_deny(state, _offer("rune", "bounce", 2000), "unaffordable")
	_deny(state, _offer("rune", "bounce"), "target_rune_mismatch")
	_deny(state, _offer("relic", "damage"), "prioritize_weapon_slots")
	_deny(state, _offer("unknown", "bone"), "unsupported_kind")
	var weapon: Dictionary = _evaluate_offer(state, _offer("weapon", "bone"), "pierce")
	_check(is_equal_approx(float(weapon["score"]), 115.2) and weapon["reason"] == "eligible", "Weapon score retains affinity and price weighting")
	_check(_evaluate_offer(state, _offer("rune", "pierce"), "pierce")["score"] == 100.0, "Target rune keeps score 100")
	state.rune_bag.append({"id": "bounce", "paid": 20, "uid": 1})
	_deny(state, _offer("rune", "pierce"), "rune_slots_reserved_by_bag")
	for index: int in range(1, 4):
		state.rune_bag.append({"id": "bounce", "paid": 20, "uid": index + 1})
	_deny(state, _offer("rune", "pierce"), "rune_bag_full")
	_four_weapons(state, "pierce")
	state.rune_bag.clear()
	_deny(state, _offer("weapon", "bone"), "weapon_slots_full")
	_deny(state, _offer("rune", "pierce"), "no_empty_rune_slot")
	state.relic_counts["damage"] = 3
	_deny(state, _offer("relic", "damage"), "relic_stack_full")
	state.relic_counts["speed"] = 1
	_deny(state, _offer("relic", "speed"), "speed_policy_cap")
	_deny(state, _offer("relic", "magnet"), "relic_not_prioritized")
	state.loadout[0]["rune"] = {}
	state.gold = 20
	_deny(state, _offer("relic", "haste"), "reserve_target_rune_budget")
	var reserve: Dictionary = _evaluate_offer(state, _offer("relic", "haste"), "pierce")
	_check(reserve["required_reserve"] == state.shop_price(GameCatalog.rune("pierce")), "Relic rejection reports the actual target rune reserve")
	state.gold = 1000
	_check(_evaluate_offer(state, _offer("relic", "haste"), "pierce")["score"] == 75.0, "Affordable relic preserves its old priority")
	var before: Dictionary = _snapshot(state)
	var observations: Array[Dictionary] = []
	_observe_shop(state, "pierce", observations, "decision", "test_read_only")
	_check(before == _snapshot(state), "Taking an observation does not mutate state or consume RNG")
	_check(JSON.parse_string(JSON.stringify(observations)) != null, "Null rejected scores form valid JSON")

func _test_vitality_exception() -> void:
	var state: RunState = _new_state()
	state.health = 20.0
	state.gold = 20
	_check(_evaluate_offer(state, _offer("relic", "vitality"), "pierce")["score"] == 150.0, "Low-health vitality bypasses the four-weapon prerequisite")
	_four_weapons(state)
	_check(_evaluate_offer(state, _offer("relic", "vitality"), "pierce")["score"] == 150.0, "Low-health vitality bypasses rune budget reservation")
	state.relic_counts["vitality"] = 3
	_deny(state, _offer("relic", "vitality"), "relic_stack_full")

func _sold_offers(state: RunState) -> void:
	state.offers = [_offer("weapon", "bone", 20, true), _offer("rune", "pierce", 20, true), _offer("relic", "damage", 20, true), _offer("relic", "armor", 20, true)]

func _test_snapshots_and_ties() -> void:
	var state: RunState = _new_state()
	state.gold = 20
	state.rerolls = 3
	state.rune_bag.append({"id": "pierce", "paid": 20, "uid": 1})
	state.offers = [_offer("weapon", "bone"), _offer("weapon", "bone"), _offer("relic", "damage", 20, true), _offer("rune", "bounce")]
	var trace: Array[Dictionary] = []
	var observations: Array[Dictionary] = []
	_shop(state, "pierce", trace, observations)
	var initial: Dictionary = observations[0]
	var decision: Dictionary = observations[1]
	_check(initial["phase"] == "initial" and initial["offers"].size() == 4, "Initial observation captures all four offers")
	_check(initial["rune_bag"].size() == 1 and initial["loadout"][0]["rune"].is_empty(), "Initial snapshot precedes automatic owned-rune equipment")
	_check(decision["rune_bag"].is_empty() and decision["loadout"][0]["rune"]["id"] == "pierce", "Decision snapshot sees the actual post-equipment inventory")
	_check(decision["wallet"] == 20 and decision["selected_offer_index"] == 0, "Before-purchase wallet and original earliest-slot tie break are recorded")
	_check(initial["offers"][0]["sold"] == false and decision["offers"][0]["sold"] == false and state.offers[0]["sold"], "Later purchases cannot rewrite earlier sold snapshots")
	_check(observations[2]["evaluations"][0]["reason"] == "sold", "Next decision records a completed purchase as sold")
	_check(observations.back()["phase"] == "stop_reroll" and observations.back()["reason"] == "reroll_limit", "The shop logs its final stopping condition")
	var parsed: Variant = JSON.parse_string(JSON.stringify(observations))
	_check(parsed != null and str(parsed).find("inf") == -1, "Full observations serialize without Infinity")
	for event: Dictionary in observations:
		_check(event["offers"].size() == 4 and event["evaluations"].size() == 4, "Every observation includes all offers and evaluations")
		_check(event.has("reserve") and event.has("reroll_cost") and event.has("relic_counts"), "Every snapshot includes reserve, cost and relics")

func _stop_reason(state: RunState) -> Dictionary:
	_sold_offers(state)
	var trace: Array[Dictionary] = []
	var observations: Array[Dictionary] = []
	_shop(state, "pierce", trace, observations)
	_check(observations[1]["phase"] == "decision" and observations[2]["phase"] == "stop_buying", "No eligible candidate logs both selection and stop buying")
	_check(observations[2]["reason"] == "no_eligible_offer", "Stopping purchase has an explicit reason")
	return observations.back()

func _test_reroll_stops() -> void:
	var state: RunState = _new_state()
	state.gold = 0
	_check(_stop_reason(state)["reason"] == "insufficient_reroll_funds", "Wallet below refresh cost is explicit")
	state = _new_state()
	state.gold = state.reroll_cost()
	var budget_stop: Dictionary = _stop_reason(state)
	_check(budget_stop["reason"] == "reserve_budget" and budget_stop["reserve"] > 0, "Refresh affordable alone can still violate purchase reserve")
	state = _new_state()
	_four_weapons(state, "pierce")
	for id: String in ["damage", "haste", "vitality", "armor"]:
		state.relic_counts[id] = 3
	var saturated: Dictionary = _stop_reason(state)
	_check(saturated["reason"] == "policy_saturated" and saturated["reserve"] == -1, "Old policy saturation is explicit even when speed could remain available")
	state.rerolls = MAX_REROLLS
	_check(_stop_reason(state)["reason"] == "reroll_limit", "Refresh cap takes precedence over saturation")
	state = _new_state(37)
	state.rerolls = MAX_REROLLS - 1
	_sold_offers(state)
	var cost: int = state.reroll_cost()
	var trace: Array[Dictionary] = []
	var observations: Array[Dictionary] = []
	_shop(state, "pierce", trace, observations)
	var refreshes: int = 0
	for event: Dictionary in observations:
		if event["phase"] == "reroll":
			refreshes += 1
			_check(event["paid"] == cost and event["rerolls"] == MAX_REROLLS, "Refresh records the paid old cost and incremented count")
			_check(event["reroll_cost"] > cost and event["offers"].size() == 4, "Refresh snapshot contains all newly priced offers and next cost")
	_check(refreshes == 1 and observations.back()["reason"] == "reroll_limit", "Exactly one affordable refresh remains below the cap")

func _scenario(seed_value: int, scenario: int) -> RunState:
	var state: RunState = _new_state(seed_value)
	state.wave = 1 + scenario
	match scenario:
		0:
			state.gold = 28
		1:
			_four_weapons(state)
			state.gold = 100
		2:
			_four_weapons(state, "pierce")
			state.gold = 1000
			state.relic_counts = {"damage": 2, "haste": 1, "speed": 1}
		3:
			state.rune_bag.append({"id": "bounce", "paid": 20, "uid": 1})
			state.gold = 60
		4:
			state.health = 20.0
			state.gold = 50
	state.generate_shop()
	return state

func _snapshot(state: RunState) -> Dictionary:
	return {"gold": state.gold, "health": state.health, "loadout": state.loadout.duplicate(true), "rune_bag": state.rune_bag.duplicate(true), "relic_counts": state.relic_counts.duplicate(true), "offers": state.offers.duplicate(true), "rerolls": state.rerolls, "rng": state.rng.state, "last_error": state.last_error}

func _test_legacy_equivalence() -> void:
	# Deliberately independent reference scoring/control flow freezes pre-observation
	# shop-v1. Comparing trace and RNG catches a logging-induced strategy change.
	for seed_value: int in [0, 37, 71, 2026, 2027, 2028, 2032]:
		for rune_id: String in RUNES:
			for scenario: int in range(5):
				var current: RunState = _scenario(seed_value, scenario)
				var legacy: RunState = _scenario(seed_value, scenario)
				var current_trace: Array[Dictionary] = []
				var legacy_trace: Array[Dictionary] = []
				var observations: Array[Dictionary] = []
				_shop(current, rune_id, current_trace, observations)
				_legacy_shop(legacy, rune_id, legacy_trace)
				var label: String = "%d/%s/%d" % [seed_value, rune_id, scenario]
				_check(current_trace == legacy_trace, "Observation preserves exact legacy shopping trace: " + label)
				_check(_snapshot(current) == _snapshot(legacy), "Observation preserves inventory, wallet and RNG state: " + label)
				_check(JSON.parse_string(JSON.stringify(observations)) != null, "Seeded observations are valid JSON: " + label)

func _legacy_shop(state: RunState, rune_id: String, trace: Array[Dictionary]) -> void:
	_equip_owned_runes(state, rune_id, trace)
	while true:
		while true:
			var best_index: int = -1
			var best_score: float = -INF
			for index: int in range(state.offers.size()):
				var score: float = _legacy_offer_score(state, state.offers[index], rune_id)
				if score > best_score:
					best_score = score
					best_index = index
			if best_index < 0 or best_score < 0.0:
				break
			var offer: Dictionary = state.offers[best_index].duplicate(true)
			if not state.buy_offer(best_index):
				trace.append({"wave": state.wave, "action": "purchase_rejected", "id": offer["id"], "error": state.last_error})
				return
			trace.append({"wave": state.wave, "action": "buy", "kind": offer["kind"], "id": offer["id"], "paid": offer["price"], "gold": state.gold})
			_equip_owned_runes(state, rune_id, trace)
		if state.rerolls >= MAX_REROLLS:
			break
		var reserve: int = _search_reserve(state, rune_id)
		if reserve < 0 or state.gold < state.reroll_cost() + reserve:
			break
		var cost: int = state.reroll_cost()
		if not state.reroll_shop():
			break
		trace.append({"wave": state.wave, "action": "reroll", "paid": cost, "gold": state.gold})

func _legacy_offer_score(state: RunState, offer: Dictionary, rune_id: String) -> float:
	if bool(offer.get("sold", false)) or int(offer["price"]) > state.gold:
		return -INF
	var id: String = str(offer["id"])
	var price: int = int(offer["price"])
	match str(offer["kind"]):
		"weapon":
			if state.loadout.size() >= RunState.WEAPON_CAP:
				return -INF
			return 110.0 + _weapon_affinity(id, rune_id) - float(price) * 0.04
		"rune":
			if id != rune_id or _empty_slots(state) <= state.rune_bag.size():
				return -INF
			return 100.0
		"relic":
			if int(state.relic_counts.get(id, 0)) >= RunState.RELIC_CAP:
				return -INF
			if id == "vitality" and state.health < state.stat("max_health") * 0.6:
				return 150.0
			if state.loadout.size() < RunState.WEAPON_CAP:
				return -INF
			var rune_reserve: int = state.shop_price(GameCatalog.rune(rune_id)) if _empty_slots(state) > 0 else 0
			if state.gold - price < rune_reserve:
				return -INF
			var priorities: Dictionary = {"damage": 80.0, "haste": 75.0, "vitality": 65.0, "armor": 60.0, "speed": 55.0}
			if id == "speed" and int(state.relic_counts.get(id, 0)) >= 1:
				return -INF
			return float(priorities.get(id, -INF))
	return -INF
