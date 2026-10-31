class_name WeaponEffectRuntime
extends RefCounted
## Per-wave equipment events stay keyed by inventory UID across layout changes.

const MAX_HASTE_BONUS: float = 2.0
const MAX_DAMAGE_BONUS: float = 8.0

class MainCastToken:
	extends RefCounted
	var issuer: WeakRef
	var payload: Dictionary
	var used: bool = false
	func _init(runtime: WeaponEffectRuntime, value: Dictionary) -> void:
		issuer = weakref(runtime)
		payload = value.duplicate(true)

var _run: RunState
var _epoch: int = 0
var _run_epoch: int = -1
var _cast_generation: int = 0
var _has_party_cast_equipment: bool = false
var _revision: int = -1
var _records: Dictionary = {}
var _equipped: Array[Dictionary] = []
var _player_sources: Dictionary = {}
var _haste_bonus: float = 0.0
var _healing_damage_bonus: float = 0.0
var _pinball_damage_bonus: float = 0.0
var _ball_damage_bonus: float = 0.0
var _break_damage_bonus: float = 0.0
var _has_impact_bonus: bool = false
var _rescues: int = 0
var _healing_received: float = 0.0
var _last_heal_event_count: int = 0


func begin(run: RunState) -> void:
	clear()
	_run = run
	if _run == null:
		return
	_run_epoch = _run.run_epoch
	_last_heal_event_count = _run.healing_events
	for definition: ContentDef in GameCatalog.weapons():
		_player_sources[definition.id] = true
	for definition: ContentDef in GameCatalog.skills():
		_player_sources["skill:" + definition.id] = true
	for hero_id: String in HeroCatalog.IDS:
		_player_sources["skill:hero_" + hero_id] = true
	_player_sources["skill:pinball"] = true
	_sync_inventory()


func clear() -> void:
	_epoch += 1
	_run_epoch = -1
	_cast_generation = 0
	_has_party_cast_equipment = false
	_run = null
	_revision = -1
	_records.clear()
	_equipped.clear()
	_player_sources.clear()
	_haste_bonus = 0.0
	_healing_damage_bonus = 0.0
	_pinball_damage_bonus = 0.0
	_ball_damage_bonus = 0.0
	_break_damage_bonus = 0.0
	_has_impact_bonus = false
	_rescues = 0
	_healing_received = 0.0
	_last_heal_event_count = 0


func advance(sim: CombatSim, delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	observe_health(sim)


func observe_health(sim: CombatSim) -> void:
	if not _valid_sim(sim):
		return
	_sync_inventory()
	_consume_healing_events()
	var maximum: float = _run.stat("max_health")
	if not is_finite(maximum) or maximum <= 0.0:
		return
	for item: Dictionary in _equipped:
		var state: Dictionary = _records[int(item["uid"])]
		if bool(state["rescued"]):
			continue
		for effect: Dictionary in item["effects"]:
			if str(effect.get("kind", "")) != "rescue":
				continue
			var threshold: float = clampf(_number(effect.get("health_ratio")), 0.0, 1.0)
			var healing: float = clampf(_number(effect.get("heal_ratio")) * float(item["weight"]), 0.0, 0.8)
			if _run.health / maximum >= threshold or healing <= 0.0:
				continue
			var actual: float = _run.heal(maximum * healing)
			if actual > 0.0:
				state["rescued"] = true
				_rescues += 1
				_healing_received += actual
			break
	_consume_healing_events()


func on_hero_cast(sim: CombatSim) -> void:
	if not _valid_sim(sim):
		return
	_sync_inventory()
	_consume_healing_events()
	for item: Dictionary in _equipped:
		for effect: Dictionary in item["effects"]:
			if str(effect.get("kind", "")) == "cast_haste":
				var state: Dictionary = _records[int(item["uid"])]
				state["cast_stacks"] = mini(1024, int(state["cast_stacks"]) + 1)
				break
	_refresh_totals()


func haste_bonus() -> float:
	_sync_inventory()
	return _haste_bonus

func preview_main_cast(sim: CombatSim) -> Dictionary:
	if not _valid_sim(sim):
		return {}
	var plan: Dictionary = _party_cast_plan(sim, true)
	if plan.is_empty():
		return {}
	return {"party_skill_damage": plan["bonus"], "token": MainCastToken.new(self, _cast_payload(sim, plan))}

func current_party_skill_damage(sim: CombatSim) -> float:
	var plan: Dictionary = _party_cast_plan(sim, false)
	return float(plan.get("bonus", 0.0))

func commit_main_cast(sim: CombatSim, candidate: Variant) -> bool:
	if not candidate is MainCastToken or not _valid_sim(sim):
		return false
	var token: MainCastToken = candidate
	if token.used or token.issuer == null or token.issuer.get_ref() != self or not sim.player_position.is_finite() or float(sim._hero_skill_clock.get("remaining", 0.0)) > 0.0:
		return false
	var plan: Dictionary = _party_cast_plan(sim, true)
	if plan.is_empty() or token.payload != _cast_payload(sim, plan):
		return false
	_sync_inventory()
	for update: Dictionary in plan["updates"]:
		var state: Dictionary = _records.get(int(update["uid"]), {})
		if state.get("id", "") != update["id"] or int(state.get("party_cast_stacks", 0)) != int(update["from"]):
			return false
	for update: Dictionary in plan["updates"]:
		_records[int(update["uid"])]["party_cast_stacks"] = int(update["to"])
	token.used = true
	_cast_generation += 1
	return true

func _cast_payload(sim: CombatSim, plan: Dictionary) -> Dictionary:
	return {"epoch": _epoch, "run_epoch": _run_epoch, "run_id": _run.get_instance_id(),
		"generation": _cast_generation, "inventory_revision": _run.inventory_revision,
		"hero_id": _run.hero_id, "sim_id": sim.get_instance_id(), "plan": plan}

func _party_cast_plan(sim: CombatSim, prospective: bool) -> Dictionary:
	if _run == null or sim == null or sim.run != _run or _run.run_epoch != _run_epoch:
		return {}
	if _revision == _run.inventory_revision and not _has_party_cast_equipment:
		return {}
	var bonus: float = 0.0
	var updates: Array[Dictionary] = []
	var signature: Array = []
	for item: Dictionary in _run.backpack.snapshot()["items"]:
		if item.get("kind", "") != "weapon":
			continue
		var definition: ContentDef = GameCatalog.weapon(str(item.get("id", "")))
		var rule: Dictionary = _party_cast_rule(definition, item)
		if rule.is_empty():
			continue
		var uid: int = int(item.get("uid", -1))
		var state: Dictionary = _records.get(uid, {})
		var before: int = clampi(int(state.get("party_cast_stacks", 0)), 0, int(rule["max_stacks"]))
		var after: int = mini(before + 1, int(rule["max_stacks"])) if prospective else before
		bonus += float(rule["amount"]) * after
		updates.append({"uid": uid, "id": definition.id, "from": before, "to": after})
		signature.append([item, definition.equipment_owner, definition.equipment_effects])
	if updates.is_empty():
		return {}
	return {"bonus": clampf(bonus, 0.0, MAX_DAMAGE_BONUS), "updates": updates, "signature": JSON.stringify(signature).sha256_text()}

static func _party_cast_rule(definition: ContentDef, item: Dictionary) -> Dictionary:
	if definition == null or definition.equipment_owner != "main" or int(item.get("uid", -1)) <= 0:
		return {}
	var owner: Variant = item.get("owner_ref", {})
	if not owner is Dictionary or EquipmentScopeRules.actor_key(owner) != "main":
		return {}
	var matches: Array[Dictionary] = []
	for effect: Dictionary in definition.equipment_effects:
		if effect.get("kind", "") == "cast_party_skill_damage":
			matches.append(effect)
	if matches.size() != 1:
		return {}
	var effect: Dictionary = matches[0]
	var maximum: Variant = effect.get("max_stacks", 0)
	var same_cast: Variant = effect.get("applies_to_current_cast", false)
	if not maximum is int or int(maximum) < 1 or int(maximum) > 4 or not same_cast is bool or not bool(same_cast):
		return {}
	var amount: float = EquipmentScopeRules.amount_for_rank(effect, int(item.get("rank", 1)))
	return {"amount": amount, "max_stacks": int(maximum)} if amount > 0.0 else {}


func damage_multiplier(sim: CombatSim, source: String, target: CombatSim.Enemy) -> float:
	if _run == null:
		return 1.0
	if _revision != _run.inventory_revision:
		_sync_inventory()
	if _equipped.is_empty():
		return 1.0
	if not _has_impact_bonus and _last_heal_event_count == _run.healing_events:
		return 1.0
	if not _player_sources.has(source):
		return 1.0
	if not _valid_sim(sim) or target == null or not target.active:
		return 1.0
	_consume_healing_events()
	var bonus: float = _healing_damage_bonus
	# A final swept ball hit is still a real ball hit after its step consumes the clock.
	if sim._pinball_time_left > 0.0 or source == "skill:pinball":
		bonus += _pinball_damage_bonus
	if source == "skill:pinball":
		bonus += _ball_damage_bonus
	if _break_damage_bonus > 0.0 and target == sim.boss and sim.boss_encounter._phase == "break":
		bonus += _break_damage_bonus
	return 1.0 + clampf(bonus, 0.0, MAX_DAMAGE_BONUS)


func snapshot() -> Dictionary:
	var states: Array[Dictionary] = []
	for item: Dictionary in _equipped:
		var value: Dictionary = _records[int(item["uid"])].duplicate(true)
		value["uid"] = item["uid"]
		value["rank"] = item["rank"]
		states.append(value)
	var result: Dictionary = {"active": _run != null, "equipped": _equipped.size(), "stored_uids": _records.size(),
		"haste_bonus": _haste_bonus, "healing_damage_bonus": _healing_damage_bonus,
		"pinball_damage_bonus": _pinball_damage_bonus, "ball_damage_bonus": _ball_damage_bonus,
		"break_damage_bonus": _break_damage_bonus, "rescues": _rescues,
		"rescue_healing": _healing_received, "items": states}
	if _has_party_cast_equipment:
		var bonus: float = 0.0
		for item: Dictionary in _equipped:
			var definition: ContentDef = GameCatalog.weapon(str(item["id"]))
			var rule: Dictionary = _party_cast_rule(definition, item)
			if not rule.is_empty():
				bonus += float(rule["amount"]) * int(_records[int(item["uid"])].get("party_cast_stacks", 0))
		result["party_skill_damage"] = clampf(bonus, 0.0, MAX_DAMAGE_BONUS)
	return result


func _valid_sim(sim: CombatSim) -> bool:
	return _run != null and sim != null and sim.run == _run and _run.run_epoch == _run_epoch and not sim.complete and is_finite(_run.health) and _run.health > 0.0


func _sync_inventory() -> void:
	if _run == null or _revision == _run.inventory_revision:
		return
	var held: Dictionary = {}
	for item: Dictionary in _equipped:
		held[int(item["uid"])] = true
	_equipped.clear()
	_has_party_cast_equipment = false
	for item: Dictionary in _run.loadout:
		var uid: int = int(item.get("uid", -1))
		var definition: ContentDef = GameCatalog.weapon(str(item.get("id", "")))
		if uid < 0 or definition == null or definition.equipment_effects.is_empty():
			continue
		if not _records.has(uid):
			_records[uid] = {"id": definition.id, "cast_stacks": 0, "heal_stacks": 0,
				"heal_seen": _run.healing_events, "rescued": false}
		elif not held.has(uid):
			_records[uid]["heal_seen"] = _run.healing_events
		var equipped: Dictionary = {"uid": uid, "id": definition.id, "rank": int(item.get("rank", 1)),
			"weight": BackpackInventory.rank_multiplier(int(item.get("rank", 1))),
			"effects": definition.equipment_effects.duplicate(true)}
		if not definition.equipment_owner.is_empty():
			var owner: Variant = item.get("owner_ref", {})
			equipped["owner_ref"] = owner.duplicate(true) if owner is Dictionary else {}
		if not _party_cast_rule(definition, equipped).is_empty():
			_has_party_cast_equipment = true
			if not _records[uid].has("party_cast_stacks"):
				_records[uid]["party_cast_stacks"] = 0
		_equipped.append(equipped)
	_revision = _run.inventory_revision
	_refresh_totals()


func _consume_healing_events() -> void:
	if _last_heal_event_count == _run.healing_events:
		return
	_last_heal_event_count = _run.healing_events
	var changed: bool = false
	for item: Dictionary in _equipped:
		var state: Dictionary = _records[int(item["uid"])]
		var events: int = maxi(0, _run.healing_events - int(state["heal_seen"]))
		state["heal_seen"] = _run.healing_events
		if events == 0:
			continue
		for effect: Dictionary in item["effects"]:
			if str(effect.get("kind", "")) == "heal_damage":
				state["heal_stacks"] = mini(1024, int(state["heal_stacks"]) + events)
				changed = true
				break
	if changed:
		_refresh_totals()


func _refresh_totals() -> void:
	_haste_bonus = 0.0
	_healing_damage_bonus = 0.0
	_pinball_damage_bonus = 0.0
	_ball_damage_bonus = 0.0
	_break_damage_bonus = 0.0
	for item: Dictionary in _equipped:
		var state: Dictionary = _records[int(item["uid"])]
		var weight: float = float(item["weight"])
		for effect: Dictionary in item["effects"]:
			var amount: float = maxf(0.0, _number(effect.get("amount"))) * weight
			match str(effect.get("kind", "")):
				"cast_haste": _haste_bonus += minf(amount * int(state["cast_stacks"]), maxf(0.0, _number(effect.get("cap"))) * weight)
				"heal_damage": _healing_damage_bonus += minf(amount * int(state["heal_stacks"]), maxf(0.0, _number(effect.get("cap"))) * weight)
				"pinball_damage": _pinball_damage_bonus += amount
				"ball_damage": _ball_damage_bonus += amount
				"break_damage": _break_damage_bonus += amount
	_haste_bonus = clampf(_haste_bonus, 0.0, MAX_HASTE_BONUS)
	_healing_damage_bonus = clampf(_healing_damage_bonus, 0.0, MAX_DAMAGE_BONUS)
	_pinball_damage_bonus = clampf(_pinball_damage_bonus, 0.0, MAX_DAMAGE_BONUS)
	_ball_damage_bonus = clampf(_ball_damage_bonus, 0.0, MAX_DAMAGE_BONUS)
	_break_damage_bonus = clampf(_break_damage_bonus, 0.0, MAX_DAMAGE_BONUS)
	_has_impact_bonus = _healing_damage_bonus > 0.0 or _pinball_damage_bonus > 0.0 or _ball_damage_bonus > 0.0 or _break_damage_bonus > 0.0


static func _number(value: Variant) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else 0.0
