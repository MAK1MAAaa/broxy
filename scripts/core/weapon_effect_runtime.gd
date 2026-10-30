class_name WeaponEffectRuntime
extends RefCounted
## Per-wave equipment events stay keyed by inventory UID across layout changes.

const MAX_HASTE_BONUS: float = 2.0
const MAX_DAMAGE_BONUS: float = 8.0

var _run: RunState
var _revision: int = -1
var _records: Dictionary = {}
var _equipped: Array[Dictionary] = []
var _player_sources: Dictionary = {}
var _haste_bonus: float = 0.0
var _healing_damage_bonus: float = 0.0
var _pinball_damage_bonus: float = 0.0
var _ball_damage_bonus: float = 0.0
var _break_damage_bonus: float = 0.0
var _rescues: int = 0
var _healing_received: float = 0.0
var _last_heal_event_count: int = 0


func begin(run: RunState) -> void:
	clear()
	_run = run
	if _run == null:
		return
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


func damage_multiplier(sim: CombatSim, source: String, target: CombatSim.Enemy) -> float:
	if _run == null:
		return 1.0
	if _revision != _run.inventory_revision:
		_sync_inventory()
	if _equipped.is_empty() or not _player_sources.has(source):
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
	return {"active": _run != null, "equipped": _equipped.size(), "stored_uids": _records.size(),
		"haste_bonus": _haste_bonus, "healing_damage_bonus": _healing_damage_bonus,
		"pinball_damage_bonus": _pinball_damage_bonus, "ball_damage_bonus": _ball_damage_bonus,
		"break_damage_bonus": _break_damage_bonus, "rescues": _rescues,
		"rescue_healing": _healing_received, "items": states}


func _valid_sim(sim: CombatSim) -> bool:
	return _run != null and sim != null and sim.run == _run and not sim.complete and is_finite(_run.health) and _run.health > 0.0


func _sync_inventory() -> void:
	if _run == null or _revision == _run.inventory_revision:
		return
	var held: Dictionary = {}
	for item: Dictionary in _equipped:
		held[int(item["uid"])] = true
	_equipped.clear()
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
		_equipped.append({"uid": uid, "id": definition.id, "rank": int(item.get("rank", 1)),
			"weight": BackpackInventory.rank_multiplier(int(item.get("rank", 1))),
			"effects": definition.equipment_effects.duplicate(true)})
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


static func _number(value: Variant) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else 0.0
