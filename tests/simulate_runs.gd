extends SceneTree
## Runs the shipped simulation and inventory rules without rendering or privileged rewards.

const DELTA: float = 1.0 / 60.0
const POLICY_VERSION: String = "orbit-avoid-v1/shop-v1/upgrade-timing-v2"
const SHOP_OBSERVATION_SCHEMA_VERSION: String = "shop-observations-v1"
const POLICY_CHANGE_NOTE: String = "Apply the existing upgrade priorities after each live combat tick; retain intermission fallback. Movement, shop priorities and resource values are unchanged."
const RUNES: Array[String] = ["pierce", "bounce", "blast"]
const MAX_REROLLS: int = 3

var _seed: int = 2026
var _count: int = 1
var _rune: String = "all"
var _require_win: bool = false
var _balance_version: String = ""
var _policy_version: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--count="):
			_count = clampi(argument.trim_prefix("--count=").to_int(), 1, 100)
		elif argument.begins_with("--rune="):
			_rune = argument.trim_prefix("--rune=")
		elif argument == "--require-win":
			_require_win = true
	if _rune != "all" and not RUNES.has(_rune):
		push_error("--rune must be all, pierce, bounce, or blast")
		quit(2)
		return
	_balance_version = _content_version()
	var policy_source: String = FileAccess.get_file_as_string("res://scripts/combat/bot_policy.gd") + FileAccess.get_file_as_string("res://tests/simulate_runs.gd")
	_policy_version = POLICY_VERSION + "+" + policy_source.sha256_text().left(12)
	var all_won: bool = true
	for offset: int in range(_count):
		for rune_id: String in RUNES:
			if _rune != "all" and _rune != rune_id:
				continue
			var result: Dictionary = _play_run(_seed + offset, rune_id)
			print(JSON.stringify(result))
			all_won = all_won and bool(result["won"])
	quit(1 if _require_win and not all_won else 0)

func _content_version() -> String:
	var sources: Array[String] = ["res://scripts/core/run_state.gd", "res://scripts/combat/combat_sim.gd", "res://scripts/data/rune_rules.gd", "res://scripts/main.gd"]
	var definitions: Array[ContentDef] = GameCatalog.weapons()
	definitions.append_array(GameCatalog.runes())
	definitions.append_array(GameCatalog.relics())
	definitions.append_array(GameCatalog.enemies())
	definitions.append_array(GameCatalog.waves())
	for definition: ContentDef in definitions:
		sources.append(definition.resource_path)
	sources.sort()
	var content: String = ""
	for path: String in sources:
		content += path + "\n" + FileAccess.get_file_as_string(path) + "\n"
	return "prototype-0.1.0+" + content.sha256_text().left(12)

func _play_run(seed_value: int, rune_id: String) -> Dictionary:
	var state: RunState = RunState.new()
	state.begin(seed_value, "bone")
	var trace: Array[Dictionary] = []
	var shop_observations: Array[Dictionary] = []
	var wave_results: Array[Dictionary] = []
	var won: bool = false
	var reason: String = ""
	for number: int in range(1, GameCatalog.waves().size() + 1):
		var simulation: CombatSim = CombatSim.new()
		simulation.begin(state)
		var start_gold: int = state.gold
		var start_kills: int = state.kills
		var start_health: float = state.health
		# A small ceiling beyond the real timer catches simulation hangs as failures.
		var frame_limit: int = int(ceilf((simulation.duration + 1.0) / DELTA))
		for frame: int in range(frame_limit):
			if simulation.complete:
				break
			_advance_combat_tick(simulation, state, trace)
		wave_results.append({
			"wave": number, "won": simulation.complete and simulation.victory,
			"kills": state.kills - start_kills, "collected": state.gold - start_gold,
			"health_before": snappedf(start_health, 0.001), "health_after": snappedf(state.health, 0.001),
			"elapsed": snappedf(simulation.elapsed, 0.001),
		})
		reason = simulation.end_reason if simulation.complete else "Simulation exceeded its frame budget"
		if not simulation.complete or not simulation.victory:
			break
		if number == GameCatalog.waves().size():
			won = true
			break
		var before_minimum: int = state.gold
		state.finish_wave()
		trace.append({"wave": state.wave, "action": "wave_income", "top_up": state.gold - before_minimum, "gold": state.gold})
		_choose_upgrades(state, trace)
		state.generate_shop()
		_shop(state, rune_id, trace, shop_observations)
		state.next_wave()
	var equipped_runes: int = 0
	for weapon: Dictionary in state.loadout:
		if str((weapon.get("rune", {}) as Dictionary).get("id", "")) == rune_id:
			equipped_runes += 1
	return {
		"seed": seed_value, "balance_version": _balance_version, "policy_version": _policy_version,
		"policy_change_note": POLICY_CHANGE_NOTE, "shop_observation_schema_version": SHOP_OBSERVATION_SCHEMA_VERSION,
		"rune": rune_id, "wave": state.wave, "won": won, "kills": state.kills, "gold": state.gold,
		"elapsed": snappedf(state.elapsed, 0.001), "reason": reason,
		"equipped_target_runes": equipped_runes, "loadout": state.loadout.duplicate(true),
		"relic_counts": state.relic_counts.duplicate(true), "wave_results": wave_results, "trace": trace,
		"shop_observations": shop_observations,
	}

func _advance_combat_tick(simulation: CombatSim, state: RunState, trace: Array[Dictionary]) -> void:
	if simulation.complete:
		return
	simulation.step(DELTA, BotPolicy.movement(simulation))
	if not simulation.complete and state.pending_upgrades > 0:
		_choose_upgrades(state, trace, "combat", simulation.elapsed)

func _choose_upgrades(state: RunState, trace: Array[Dictionary], context: String = "intermission", wave_elapsed: float = -1.0) -> void:
	while state.pending_upgrades > 0:
		var choices: Array[Dictionary] = state.upgrade_choices()
		var chosen: Dictionary = choices[0]
		var best: float = -INF
		for option: Dictionary in choices:
			var priorities: Dictionary = {"damage": 100.0, "haste": 90.0, "vitality": 75.0, "armor": 65.0, "speed": 55.0, "magnet": 40.0}
			var score: float = float(priorities.get(str(option["id"]), 0.0))
			if str(option["id"]) == "vitality" and state.health < state.stat("max_health") * 0.6:
				score = 130.0
			if score > best:
				best = score
				chosen = option
		var id: String = str(chosen["id"])
		if not state.choose_upgrade(id):
			trace.append({"wave": state.wave, "action": "upgrade_rejected", "id": id, "error": state.last_error})
			break
		trace.append({"wave": state.wave, "action": "upgrade", "id": id, "offered": [choices[0]["id"], choices[1]["id"], choices[2]["id"]], "context": context, "wave_elapsed": snappedf(wave_elapsed, 0.001)})

func _shop(state: RunState, rune_id: String, trace: Array[Dictionary], observations: Array[Dictionary] = []) -> void:
	_observe_shop(state, rune_id, observations, "initial", "shop_generated")
	_equip_owned_runes(state, rune_id, trace)
	while true:
		while true:
			var best_index: int = -1
			var best_score: float = -INF
			var evaluations: Array[Dictionary] = []
			for index: int in range(state.offers.size()):
				var evaluation: Dictionary = _evaluate_offer(state, state.offers[index], rune_id)
				evaluation["index"] = index
				evaluations.append(evaluation)
				var score: float = float(evaluation["score"]) if evaluation["score"] != null else -INF
				if score > best_score:
					best_score = score
					best_index = index
			_observe_shop(state, rune_id, observations, "decision", "select_best_offer", evaluations, best_index)
			if best_index < 0 or best_score < 0.0:
				_observe_shop(state, rune_id, observations, "stop_buying", "no_eligible_offer", evaluations)
				break
			var offer: Dictionary = state.offers[best_index].duplicate(true)
			if not state.buy_offer(best_index):
				trace.append({"wave": state.wave, "action": "purchase_rejected", "id": offer["id"], "error": state.last_error})
				_observe_shop(state, rune_id, observations, "purchase_rejected", "runtime_purchase_rejected")
				return
			trace.append({"wave": state.wave, "action": "buy", "kind": offer["kind"], "id": offer["id"], "paid": offer["price"], "gold": state.gold})
			_equip_owned_runes(state, rune_id, trace)
		if state.rerolls >= MAX_REROLLS:
			_observe_shop(state, rune_id, observations, "stop_reroll", "reroll_limit")
			break
		var reserve: int = _search_reserve(state, rune_id)
		if reserve < 0 or state.gold < state.reroll_cost() + reserve:
			var stop_reason: String = "policy_saturated" if reserve < 0 else ("insufficient_reroll_funds" if state.gold < state.reroll_cost() else "reserve_budget")
			_observe_shop(state, rune_id, observations, "stop_reroll", stop_reason)
			break
		var cost: int = state.reroll_cost()
		if not state.reroll_shop():
			_observe_shop(state, rune_id, observations, "stop_reroll", "runtime_reroll_rejected")
			break
		trace.append({"wave": state.wave, "action": "reroll", "paid": cost, "gold": state.gold})
		_observe_shop(state, rune_id, observations, "reroll", "shop_rerolled", [], -1, cost)

func _offer_score(state: RunState, offer: Dictionary, rune_id: String) -> float:
	var evaluation: Dictionary = _evaluate_offer(state, offer, rune_id)
	return float(evaluation["score"]) if evaluation["score"] != null else -INF

func _evaluate_offer(state: RunState, offer: Dictionary, rune_id: String) -> Dictionary:
	# This is the single source for both selection and reporting. Preserve shop-v1's
	# rejection order and its low-health vitality exception; observation never draws RNG.
	var evaluation: Dictionary = {
		"id": str(offer["id"]), "kind": str(offer["kind"]), "price": int(offer["price"]),
		"sold": bool(offer.get("sold", false)), "score": null, "reason": "unsupported_kind", "required_reserve": 0,
	}
	if bool(offer.get("sold", false)):
		evaluation["reason"] = "sold"
		return evaluation
	if int(offer["price"]) > state.gold:
		evaluation["reason"] = "unaffordable"
		return evaluation
	var id: String = str(offer["id"])
	var price: int = int(offer["price"])
	match str(offer["kind"]):
		"weapon":
			if state.loadout.size() >= RunState.WEAPON_CAP:
				evaluation["reason"] = "weapon_slots_full"
			else:
				evaluation["score"] = 110.0 + _weapon_affinity(id, rune_id) - float(price) * 0.04
		"rune":
			if id != rune_id:
				evaluation["reason"] = "target_rune_mismatch"
			elif _empty_slots(state) <= state.rune_bag.size():
				if state.rune_bag.size() >= RunState.RUNE_BAG_CAP:
					evaluation["reason"] = "rune_bag_full"
				elif _empty_slots(state) == 0:
					evaluation["reason"] = "no_empty_rune_slot"
				else:
					evaluation["reason"] = "rune_slots_reserved_by_bag"
			else:
				evaluation["score"] = 100.0
		"relic":
			if int(state.relic_counts.get(id, 0)) >= RunState.RELIC_CAP:
				evaluation["reason"] = "relic_stack_full"
			elif id == "vitality" and state.health < state.stat("max_health") * 0.6:
				evaluation["score"] = 150.0
			elif state.loadout.size() < RunState.WEAPON_CAP:
				evaluation["reason"] = "prioritize_weapon_slots"
			else:
				var rune_reserve: int = state.shop_price(GameCatalog.rune(rune_id)) if _empty_slots(state) > 0 else 0
				evaluation["required_reserve"] = rune_reserve
				if state.gold - price < rune_reserve:
					evaluation["reason"] = "reserve_target_rune_budget"
				elif id == "speed" and int(state.relic_counts.get(id, 0)) >= 1:
					evaluation["reason"] = "speed_policy_cap"
				else:
					var priorities: Dictionary = {"damage": 80.0, "haste": 75.0, "vitality": 65.0, "armor": 60.0, "speed": 55.0}
					if priorities.has(id):
						evaluation["score"] = float(priorities[id])
					else:
						evaluation["reason"] = "relic_not_prioritized"
	if evaluation["score"] != null:
		evaluation["reason"] = "eligible"
	return evaluation

func _observe_shop(state: RunState, rune_id: String, observations: Array[Dictionary], phase: String, reason: String, evaluations: Array[Dictionary] = [], selected_index: int = -1, paid: int = -1) -> void:
	var event_evaluations: Array[Dictionary] = evaluations.duplicate(true)
	if event_evaluations.is_empty():
		for index: int in range(state.offers.size()):
			var evaluation: Dictionary = _evaluate_offer(state, state.offers[index], rune_id)
			evaluation["index"] = index
			event_evaluations.append(evaluation)
	observations.append({
		"wave": state.wave, "phase": phase, "reason": reason, "wallet": state.gold,
		"offers": state.offers.duplicate(true), "evaluations": event_evaluations,
		"selected_offer_index": selected_index if selected_index >= 0 else null,
		"rerolls": state.rerolls, "reroll_cost": state.reroll_cost(), "reserve": _search_reserve(state, rune_id),
		"loadout": state.loadout.duplicate(true), "rune_bag": state.rune_bag.duplicate(true),
		"relic_counts": state.relic_counts.duplicate(true), "paid": paid if paid >= 0 else null,
	})

func _search_reserve(state: RunState, rune_id: String) -> int:
	if state.loadout.size() < RunState.WEAPON_CAP:
		return state.shop_price(GameCatalog.weapon("bone"))
	if _empty_slots(state) > 0:
		return state.shop_price(GameCatalog.rune(rune_id))
	for id: String in ["damage", "haste", "vitality", "armor"]:
		if int(state.relic_counts.get(id, 0)) < RunState.RELIC_CAP:
			return state.shop_price(GameCatalog.relic(id))
	return -1

func _empty_slots(state: RunState) -> int:
	var count: int = 0
	for weapon: Dictionary in state.loadout:
		if (weapon.get("rune", {}) as Dictionary).is_empty():
			count += 1
	return count

func _equip_owned_runes(state: RunState, rune_id: String, trace: Array[Dictionary]) -> void:
	var bag_index: int = 0
	while bag_index < state.rune_bag.size():
		if str(state.rune_bag[bag_index]["id"]) != rune_id:
			bag_index += 1
			continue
		var chosen: int = -1
		var best_affinity: float = -INF
		for index: int in range(state.loadout.size()):
			if not (state.loadout[index].get("rune", {}) as Dictionary).is_empty():
				continue
			var affinity: float = _weapon_affinity(str(state.loadout[index]["id"]), rune_id)
			if affinity > best_affinity:
				chosen = index
				best_affinity = affinity
		if chosen < 0:
			break
		if not state.equip_rune(bag_index, chosen):
			break
		trace.append({"wave": state.wave, "action": "equip", "rune": rune_id, "weapon": state.loadout[chosen]["id"], "slot": chosen})

func _weapon_affinity(weapon_id: String, rune_id: String) -> float:
	var preferences: Dictionary = {
		"pierce": {"scatter": 8.0, "bone": 6.0, "frost": 4.0, "ember": 2.0},
		"bounce": {"bone": 8.0, "frost": 6.0, "ember": 4.0, "scatter": 2.0},
		"blast": {"ember": 8.0, "scatter": 6.0, "bone": 4.0, "frost": 2.0},
	}
	return float((preferences[rune_id] as Dictionary).get(weapon_id, 0.0))

