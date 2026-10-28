extends SceneTree
## Runs the shipped simulation and inventory rules without rendering or privileged rewards.

const DELTA: float = 1.0 / 60.0
const POLICY_VERSION: String = "orbit-avoid-v1/backpack-shop-v2/upgrade-timing-v2/rogue-choices-v1"
const SHOP_OBSERVATION_SCHEMA_VERSION: String = "shop-observations-v1"
const POLICY_CHANGE_NOTE: String = "Explicit core/route/altar choices use shipped transactions before normal space-aware shopping. Relic adjacency affects real damage; this policy does not optimize placement. Movement and upgrade priorities unchanged; not a legacy trajectory-equivalence run."
const RUNES: Array[String] = ["pierce", "bounce", "blast"]
const MAX_REROLLS: int = 3

var _seed: int = 2026
var _count: int = 1
var _rune: String = "all"
var _require_win: bool = false
var _balance_version: String = ""
var _policy_version: String = ""
var _core: String = "none"
var _route: String = "balanced"
var _altar: String = "skip"
var _arena: String = "reliquary"
var _pulse_policy: bool = false

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
		elif argument == "--pulse-policy":
			_pulse_policy = true
		elif argument.begins_with("--core="):
			_core = argument.trim_prefix("--core=")
		elif argument.begins_with("--route="):
			_route = argument.trim_prefix("--route=")
		elif argument.begins_with("--altar="):
			_altar = argument.trim_prefix("--altar=")
		elif argument.begins_with("--arena="):
			_arena = argument.trim_prefix("--arena=")
	if not ArenaCatalog.IDS.has(_arena):
		push_error("--arena must be reliquary, mire, glacier, or ashland")
		quit(2)
		return
	if _core not in ["none", "frostfire", "bone_chorus"] or RogueRules.route(_route).is_empty() or _altar not in ["accept", "skip"]:
		push_error("Use --core=none|frostfire|bone_chorus --route=balanced|swarm|bulwark --altar=accept|skip")
		quit(2)
		return
	if _rune != "all" and not RUNES.has(_rune):
		push_error("--rune must be all, pierce, bounce, or blast")
		quit(2)
		return
	_balance_version = _content_version()
	var policy_source: String = FileAccess.get_file_as_string("res://scripts/combat/bot_policy.gd") + FileAccess.get_file_as_string("res://tests/simulate_runs.gd")
	_policy_version = POLICY_VERSION + ("/pulse-peel-v1" if _pulse_policy else "") + "/%s/%s/%s+" % [_core, _route, _altar] + policy_source.sha256_text().left(12)
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
	var sources: Array[String] = ["res://scripts/core/run_state.gd", "res://scripts/core/backpack_inventory.gd", "res://scripts/core/backpack_resonance.gd", "res://scripts/combat/combat_sim.gd", "res://scripts/data/content_def.gd", "res://scripts/data/game_catalog.gd", "res://scripts/data/rune_rules.gd", "res://scripts/data/rogue_rules.gd", "res://scripts/main.gd"]
	var definitions: Array[ContentDef] = GameCatalog.weapons()
	sources.append_array(["res://scripts/core/arena_catalog.gd", "res://data/arenas.json", "res://scripts/data/dash_rules.gd", "res://scripts/data/pulse_rules.gd"])
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
	state.begin(seed_value, "bone", _arena)
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
			"weapon_count": state.loadout.size(), "backpack_used_cells": state.backpack_snapshot()["used_cells"],
			"core_activations": simulation.core_activations.duplicate(true),
			"resonant_weapon_count": state.loadout.filter(func(item: Dictionary) -> bool: return float(item.get("resonance_bonus", 0.0)) > 0.0).size(),
		})
		if _pulse_policy:
			wave_results[-1]["pulses_used"] = simulation.pulses_used
			wave_results[-1]["pulse_affected"] = simulation.pulse_affected
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
		_choose_rogue_options(state, rune_id, trace)
		_shop(state, rune_id, trace, shop_observations)
		_claim_rogue_reward(state, rune_id, trace)
		state.next_wave()
	var equipped_runes: int = 0
	for weapon: Dictionary in state.loadout:
		if str((weapon.get("rune", {}) as Dictionary).get("id", "")) == rune_id:
			equipped_runes += 1
	var result: Dictionary = {
		"seed": seed_value, "balance_version": _balance_version, "policy_version": _policy_version,
		"policy_change_note": POLICY_CHANGE_NOTE, "shop_observation_schema_version": SHOP_OBSERVATION_SCHEMA_VERSION,
		"rune": rune_id, "wave": state.wave, "won": won, "kills": state.kills, "gold": state.gold,
		"arena_id": state.arena_id,
		"elapsed": snappedf(state.elapsed, 0.001), "reason": reason,
		"equipped_target_runes": equipped_runes, "loadout": state.loadout.duplicate(true),
		"relic_counts": state.relic_counts.duplicate(true), "wave_results": wave_results, "trace": trace,
		"shop_observations": shop_observations,
		"backpack": state.backpack_snapshot(),
		"rogue": state.rogue_choices(), "requested_core": _core, "requested_route": _route, "requested_altar": _altar,
	}
	if _pulse_policy:
		result["skill_policy"] = "pulse-peel-v1: cast when at least three eligible enemies are within 100 pixels; no automatic dash"
		result["policy_change_note"] = POLICY_CHANGE_NOTE + " Explicit pulse-peel-v1 changes trajectories and random consumption through real crowd control; it grants no rewards or damage."
	return result

func _choose_rogue_options(state: RunState, rune_id: String, trace: Array[Dictionary]) -> void:
	var choices: Dictionary = state.rogue_choices()
	if bool(choices["can_choose_core"]) and _core != "none":
		var success: bool = state.choose_core(_core)
		trace.append({"wave": state.wave, "action": "choose_core", "id": _core, "success": success, "error": state.last_error})
	if bool(choices["altar_available"]):
		var success: bool = state.choose_altar(_altar == "accept")
		trace.append({"wave": state.wave, "action": "choose_altar", "choice": _altar, "success": success, "error": state.last_error})
	if bool(choices["can_choose_route"]):
		var success: bool = state.choose_route(_route)
		trace.append({"wave": state.wave, "action": "choose_route", "id": _route, "success": success, "error": state.last_error})
	_claim_rogue_reward(state, rune_id, trace)

func _claim_rogue_reward(state: RunState, rune_id: String, trace: Array[Dictionary]) -> void:
	if not state.rune_reward_pending:
		return
	var success: bool = state.claim_altar_rune(rune_id)
	trace.append({"wave": state.wave, "action": "claim_altar_rune", "id": rune_id, "success": success, "error": state.last_error})

func _advance_combat_tick(simulation: CombatSim, state: RunState, trace: Array[Dictionary]) -> void:
	if simulation.complete:
		return
	if _pulse_policy:
		simulation.step(DELTA, BotPolicy.movement(simulation), false, _wants_pulse(simulation))
	else:
		simulation.step(DELTA, BotPolicy.movement(simulation))
	if not simulation.complete and state.pending_upgrades > 0:
		_choose_upgrades(state, trace, "combat", simulation.elapsed)

func _wants_pulse(simulation: CombatSim) -> bool:
	if not bool(simulation.pulse_snapshot()["ready"]):
		return false
	var nearby: int = 0
	for enemy: CombatSim.Enemy in simulation.enemies:
		if enemy.active and enemy.health > 0.0 and not enemy.hunter and enemy.definition.id != "boss" and enemy.position.distance_squared_to(simulation.player_position) <= 10000.0:
			nearby += 1
			if nearby >= 3:
				return true
	return false

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
	_manage_backpack(state, rune_id, trace)
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
				if _expand_for_offer(state, rune_id, trace):
					_observe_shop(state, rune_id, observations, "expanded", "expand_for_eligible_offer")
					continue
				_observe_shop(state, rune_id, observations, "stop_buying", "no_eligible_offer", evaluations)
				break
			var offer: Dictionary = state.offers[best_index].duplicate(true)
			if not state.buy_offer(best_index):
				trace.append({"wave": state.wave, "action": "purchase_rejected", "id": offer["id"], "error": state.last_error})
				_observe_shop(state, rune_id, observations, "purchase_rejected", "runtime_purchase_rejected")
				return
			trace.append({"wave": state.wave, "action": "buy", "kind": offer["kind"], "id": offer["id"], "paid": offer["price"], "gold": state.gold})
			_manage_backpack(state, rune_id, trace)
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

func _evaluate_offer(state: RunState, offer: Dictionary, rune_id: String, ignore_space: bool = false) -> Dictionary:
	# Preference limits are policy choices; the game itself uses physical backpack space.
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
	var kind: String = str(offer["kind"])
	var price: int = int(offer["price"])
	match kind:
		"weapon":
			if _weapon_power(state) >= _desired_weapon_power(state):
				evaluation["reason"] = "weapon_power_target_met"
			else:
				evaluation["score"] = 110.0 + _weapon_affinity(id, rune_id) - float(price) * 0.04
		"rune":
			if id != rune_id:
				evaluation["reason"] = "target_rune_mismatch"
			elif not _needs_rune(state, rune_id):
				evaluation["reason"] = "rune_rank_target_met"
			else:
				evaluation["score"] = 100.0 if _empty_slots(state) > 0 else 87.0
		"relic":
			if int(state.relic_counts.get(id, 0)) >= _relic_policy_limit(id):
				evaluation["reason"] = "relic_policy_target_met"
			elif id == "vitality" and state.health < state.stat("max_health") * 0.6:
				evaluation["score"] = 150.0
			else:
				var rune_reserve: int = state.shop_price(GameCatalog.rune(rune_id)) if _empty_slots(state) > 0 else 0
				evaluation["required_reserve"] = rune_reserve
				if state.gold - price < rune_reserve:
					evaluation["reason"] = "reserve_target_rune_budget"
				else:
					var priorities: Dictionary = {"damage": 80.0, "haste": 75.0, "vitality": 65.0, "armor": 60.0, "speed": 55.0,
						"magnet": 42.0, "moon_charm": 84.0, "pilgrim": 56.0, "bulwark": 70.0,
						"hourglass": 66.0, "blood_pact": 68.0, "grave_candle": 45.0}
					if priorities.has(id):
						evaluation["score"] = float(priorities[id])
					else:
						evaluation["reason"] = "relic_not_prioritized"
	if evaluation["score"] != null:
		if not ignore_space and not state.backpack.can_add(kind, id):
			evaluation["score"] = null
			evaluation["reason"] = "backpack_full"
		else:
			evaluation["reason"] = "eligible"
	return evaluation

func _weapon_power(state: RunState) -> int:
	var total: int = 0
	for equipped: Dictionary in state.loadout:
		total += int(BackpackInventory.rank_multiplier(int(equipped.get("rank", 1))))
	return total

func _desired_weapon_power(state: RunState) -> int:
	return mini(12, 3 + state.wave)

func _desired_rune_rank(state: RunState) -> int:
	return mini(3, 1 + int((state.wave - 1) / 3))

func _needs_rune(state: RunState, rune_id: String) -> bool:
	for equipped: Dictionary in state.loadout:
		var rune: Dictionary = equipped.get("rune", {})
		if str(rune.get("id", "")) != rune_id or int(rune.get("rank", 1)) < _desired_rune_rank(state):
			return true
	return false

func _relic_policy_limit(id: String) -> int:
	return int({"speed": 2, "magnet": 2, "pilgrim": 2, "hourglass": 2,
		"blood_pact": 2, "grave_candle": 1, "moon_charm": 4, "bulwark": 4}.get(id, 8))

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
		"backpack": state.backpack_snapshot(),
	})

func _search_reserve(state: RunState, rune_id: String) -> int:
	if _weapon_power(state) < _desired_weapon_power(state) and state.backpack.can_add("weapon", "bone"):
		return state.shop_price(GameCatalog.weapon("bone"))
	if _needs_rune(state, rune_id) and state.backpack.can_add("rune", rune_id):
		return state.shop_price(GameCatalog.rune(rune_id))
	for id: String in ["damage", "haste", "vitality", "armor"]:
		if int(state.relic_counts.get(id, 0)) < _relic_policy_limit(id) and state.backpack.can_add("relic", id):
			return state.shop_price(GameCatalog.relic(id))
	var snapshot: Dictionary = state.backpack_snapshot()
	if int(snapshot["height"]) < int(snapshot["max_height"]) and _weapon_power(state) < _desired_weapon_power(state):
		return int(snapshot["expansion_cost"]) + state.shop_price(GameCatalog.weapon("bone"))
	return -1

func _empty_slots(state: RunState) -> int:
	var count: int = 0
	for weapon: Dictionary in state.loadout:
		if (weapon.get("rune", {}) as Dictionary).is_empty():
			count += 1
	return count

func _equip_owned_runes(state: RunState, rune_id: String, trace: Array[Dictionary]) -> int:
	var bag_index: int = 0
	var equipped_count: int = 0
	while bag_index < state.rune_bag.size():
		if str(state.rune_bag[bag_index]["id"]) != rune_id:
			bag_index += 1
			continue
		var chosen: int = -1
		var best_affinity: float = -INF
		var incoming_rank: int = int(state.rune_bag[bag_index].get("rank", 1))
		for index: int in range(state.loadout.size()):
			var current: Dictionary = state.loadout[index].get("rune", {})
			if not current.is_empty() and (str(current.get("id", "")) != rune_id or int(current.get("rank", 1)) >= incoming_rank):
				continue
			var affinity: float = _weapon_affinity(str(state.loadout[index]["id"]), rune_id) + (100.0 if current.is_empty() else 0.0)
			if affinity > best_affinity:
				chosen = index
				best_affinity = affinity
		if chosen < 0:
			bag_index += 1
			continue
		if not state.equip_rune(bag_index, chosen):
			break
		equipped_count += 1
		trace.append({"wave": state.wave, "action": "equip", "rune": rune_id, "rune_rank": incoming_rank, "weapon": state.loadout[chosen]["id"], "slot": chosen})
	return equipped_count

func _manage_backpack(state: RunState, rune_id: String, trace: Array[Dictionary]) -> void:
	# Each merge consumes an item, and every swap strictly raises a socket's rank.
	for cycle: int in 72:
		var merged: int = _merge_owned_items(state, trace)
		var equipped: int = _equip_owned_runes(state, rune_id, trace)
		if merged == 0 and equipped == 0:
			return

func _merge_owned_items(state: RunState, trace: Array[Dictionary]) -> int:
	var merged: int = 0
	for attempt: int in 72:
		var snapshot: Dictionary = state.backpack_snapshot()
		var items: Array = snapshot["items"]
		var source_uid: int = -1
		var target_uid: int = -1
		var target: Dictionary = {}
		for first: int in items.size():
			var candidate: Dictionary = items[first]
			if int(candidate.get("rank", 1)) >= 3:
				continue
			for second: int in range(first + 1, items.size()):
				var other: Dictionary = items[second]
				if candidate["kind"] != other["kind"] or candidate["id"] != other["id"] or candidate["rank"] != other["rank"]:
					continue
				target_uid = int(candidate["uid"])
				source_uid = int(other["uid"])
				target = candidate
				if str(candidate["kind"]) == "weapon" and int((other.get("rune", {}) as Dictionary).get("rank", 0)) > int((candidate.get("rune", {}) as Dictionary).get("rank", 0)):
					target_uid = int(other["uid"])
					source_uid = int(candidate["uid"])
					target = other
				if bool(state.merge_preview(source_uid, target_uid).get("can_merge", false)):
					break
				source_uid = -1
				target_uid = -1
			if source_uid >= 0:
				break
		if source_uid < 0 or not state.merge_items(source_uid, target_uid):
			return merged
		merged += 1
		trace.append({"wave": state.wave, "action": "merge", "kind": target["kind"], "id": target["id"],
			"source_uid": source_uid, "target_uid": target_uid,
			"from_rank": target["rank"], "to_rank": state.backpack_item(target_uid)["rank"],
			"used_cells_before": snapshot["used_cells"], "used_cells_after": state.backpack_snapshot()["used_cells"]})
	return merged

func _expand_for_offer(state: RunState, rune_id: String, trace: Array[Dictionary]) -> bool:
	var snapshot: Dictionary = state.backpack_snapshot()
	if int(snapshot["height"]) >= int(snapshot["max_height"]):
		return false
	var cost: int = int(snapshot["expansion_cost"])
	for offer: Dictionary in state.offers:
		var evaluation: Dictionary = _evaluate_offer(state, offer, rune_id, true)
		if evaluation["score"] == null or state.gold < cost + int(offer["price"]):
			continue
		if state.backpack.can_add(str(offer["kind"]), str(offer["id"])):
			continue
		if not state.expand_backpack():
			return false
		trace.append({"wave": state.wave, "action": "expand_backpack", "paid": cost,
			"height_before": snapshot["height"], "height_after": state.backpack_snapshot()["height"], "gold": state.gold})
		return true
	return false

func _weapon_affinity(weapon_id: String, rune_id: String) -> float:
	var preferences: Dictionary = {
		"pierce": {"scatter": 8.0, "bone": 6.0, "frost": 4.0, "ember": 2.0},
		"bounce": {"bone": 8.0, "frost": 6.0, "ember": 4.0, "scatter": 2.0},
		"blast": {"ember": 8.0, "scatter": 6.0, "bone": 4.0, "frost": 2.0},
	}
	return float((preferences[rune_id] as Dictionary).get(weapon_id, 0.0))

