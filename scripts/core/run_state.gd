class_name RunState
extends RefCounted

signal changed

const WEAPON_CAP: int = BackpackInventory.WIDTH * BackpackInventory.MAX_HEIGHT
const RUNE_BAG_CAP: int = BackpackInventory.WIDTH * BackpackInventory.MAX_HEIGHT
const RELIC_CAP: int = 3
const SHOP_LOCK_CAP: int = 2
const BASE_STATS: Dictionary = {
	"max_health": 100.0,
	"damage": 1.0,
	"attack_speed": 1.0,
	"move_speed": 220.0,
	"armor": 0.0,
	"pickup_radius": 76.0,
}
const UPGRADE_POOL: Array[Dictionary] = [
	{"id": "damage", "name": "秘术精通", "description": "伤害 +12%", "stat": "damage", "amount": 0.12},
	{"id": "haste", "name": "咒速精通", "description": "攻击速度 +10%", "stat": "attack_speed", "amount": 0.10},
	{"id": "speed", "name": "轻盈步伐", "description": "移动速度 +12", "stat": "move_speed", "amount": 12.0},
	{"id": "vitality", "name": "生命灌注", "description": "生命上限 +12，并回复12生命", "stat": "max_health", "amount": 12.0},
	{"id": "armor", "name": "符文护体", "description": "护甲 +1", "stat": "armor", "amount": 1.0},
	{"id": "magnet", "name": "灵魂牵引", "description": "拾取范围 +12", "stat": "pickup_radius", "amount": 12.0},
]

var wave: int = 1
var gold: int = 0
var xp: int = 0
var level: int = 1
var pending_upgrades: int = 0
var health: float = 100.0
var kills: int = 0
var elapsed: float = 0.0
var damage_dealt_by_weapon: Dictionary = {}
var damage_taken: float = 0.0
var hits_taken: int = 0
var last_hit: Dictionary = {}
var backpack: BackpackInventory = BackpackInventory.new()
var loadout: Array[Dictionary] = []
var rune_bag: Array[Dictionary] = []
var relic_counts: Dictionary = {}
var offers: Array[Dictionary] = []
var rerolls: int = 0
var last_error: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var core_id: String = ""
var altar_choice: String = ""
var altar_wave: int = -1
var hunter_defeated: bool = false
var rune_reward_pending: bool = false
var next_route: String = "balanced"
var active_route: String = "balanced"

var _run_seed: int = 0
var _next_rune_uid: int = 1
var _wave_income: int = 0
var _wave_finished: bool = false
var _upgrade_bonuses: Dictionary = {}
var _upgrade_options: Array[Dictionary] = []
var _locked_offers: Dictionary = {}

func begin(seed_value: int, starter: String) -> void:
	_run_seed = seed_value
	rng.seed = seed_value
	wave = 1
	gold = 0
	xp = 0
	level = 1
	pending_upgrades = 0
	health = 100.0
	kills = 0
	elapsed = 0.0
	damage_dealt_by_weapon.clear()
	damage_taken = 0.0
	hits_taken = 0
	last_hit.clear()
	loadout.clear()
	rune_bag.clear()
	relic_counts.clear()
	offers.clear()
	rerolls = 0
	last_error = ""
	core_id = ""
	altar_choice = ""
	altar_wave = -1
	hunter_defeated = false
	rune_reward_pending = false
	next_route = "balanced"
	active_route = "balanced"
	_next_rune_uid = 1
	_wave_income = 0
	_wave_finished = false
	_upgrade_bonuses.clear()
	_upgrade_options.clear()
	_locked_offers.clear()
	backpack.reset()
	var starting_weapon: String = starter if GameCatalog.weapon(starter) != null else "bone"
	backpack.add("weapon", starting_weapon)
	_sync_backpack_projection()
	changed.emit()

func stat(key: String) -> float:
	return _stat_with_projected_relic(key)

func choose_core(id: String) -> bool:
	if not _wave_finished or wave < 1 or wave >= GameCatalog.WAVE_DEFS.size() or not core_id.is_empty():
		return _fail("请在波间选择一个尚未选定的核心。")
	var definition: Dictionary = RogueRules.core(id)
	if definition.is_empty():
		return _fail("未知的秘术核心。")
	# Build on a detached inventory so a multi-weapon grant either commits in full
	# or preserves every original item, UID and layout when capacity is insufficient.
	var before: Dictionary = backpack.snapshot()
	var work := BackpackInventory.new()
	work.height = int(before["height"])
	work._items.assign((before["items"] as Array).duplicate(true))
	work._next_uid = int(before["next_uid"])
	for weapon_id: String in definition["weapons"]:
		var owned: bool = false
		for weapon: Dictionary in loadout:
			owned = owned or str(weapon["id"]) == weapon_id
		if (not owned or bool(definition.get("always_grant", false))) and work.add("weapon", weapon_id, 0).is_empty():
			return _fail("背包放不下核心赠送的法器；请先整理，再选择核心。")
	backpack = work
	core_id = id
	_sync_backpack_projection()
	last_error = ""
	changed.emit()
	return true

func choose_altar(accept: bool) -> bool:
	if not _wave_finished or wave != 2 or not altar_choice.is_empty():
		return _fail("追猎契约仅在第2波后的祭坛选择一次。")
	altar_choice = "accepted" if accept else "declined"
	altar_wave = 3 if accept else -1
	last_error = ""
	changed.emit()
	return true

func choose_route(id: String) -> bool:
	if not _wave_finished or wave < 1 or wave >= GameCatalog.WAVE_DEFS.size() - 1:
		return _fail("仅能在普通波之间选择下一波路线；首领战沿用原途。")
	if RogueRules.route(id).is_empty():
		return _fail("未知的试炼路线。")
	if next_route == id:
		return true
	next_route = id
	last_error = ""
	changed.emit()
	return true

func record_hunter_defeat() -> void:
	if _wave_finished or altar_choice != "accepted" or wave != altar_wave or hunter_defeated:
		return
	hunter_defeated = true
	rune_reward_pending = true

func claim_altar_rune(id: String) -> bool:
	if not _wave_finished or not rune_reward_pending:
		return _fail("请在完成追猎契约后，于波间领取符文。")
	if GameCatalog.rune(id) == null:
		return _fail("请选择有效的奖励符文。")
	if backpack.add("rune", id, 0).is_empty():
		return _fail("背包空间不足；奖励会保留，请整理后领取。")
	rune_reward_pending = false
	_sync_backpack_projection()
	last_error = ""
	changed.emit()
	return true

func linked_weapon_uids() -> Array[int]:
	var result: Array[int] = []
	var entries: Array = backpack.snapshot()["items"]
	for candle: Dictionary in entries:
		if str(candle["kind"]) != "relic" or str(candle["id"]) != "grave_candle":
			continue
		var candle_size: Vector2i = BackpackInventory.size_for("relic", "grave_candle", bool(candle["rotated"]))
		for weapon: Dictionary in entries:
			if str(weapon["kind"]) != "weapon" or result.has(int(weapon["uid"])):
				continue
			var weapon_size: Vector2i = BackpackInventory.size_for("weapon", str(weapon["id"]), bool(weapon["rotated"]))
			if int(weapon["y"]) + weapon_size.y == int(candle["y"]) and int(weapon["x"]) < int(candle["x"]) + candle_size.x and int(candle["x"]) < int(weapon["x"]) + weapon_size.x:
				result.append(int(weapon["uid"]))
	result.sort()
	return result

func rogue_choices() -> Dictionary:
	return {"core_id": core_id, "core_options": RogueRules.cores(),
		"can_choose_core": _wave_finished and wave >= 1 and wave < GameCatalog.WAVE_DEFS.size() and core_id.is_empty(),
		"altar_available": _wave_finished and wave == 2 and altar_choice.is_empty(),
		"altar_choice": altar_choice, "altar_wave": altar_wave, "hunter_defeated": hunter_defeated,
		"reward_pending": rune_reward_pending, "can_claim_reward": _wave_finished and rune_reward_pending,
		"can_choose_route": _wave_finished and wave >= 1 and wave < GameCatalog.WAVE_DEFS.size() - 1,
		"route": next_route, "active_route": active_route, "route_options": RogueRules.routes(),
		"linked_weapons": linked_weapon_uids()}

func projected_upgrade_stat(key: String, amount: float) -> float:
	return _stat_with_projected_relic(key, null, amount)

func _stat_with_projected_relic(key: String, additional: ContentDef = null, upgrade_delta: float = 0.0) -> float:
	var value: float = float(BASE_STATS.get(key, 0.0)) + float(_upgrade_bonuses.get(key, 0.0)) + upgrade_delta
	for relic_id: String in relic_counts:
		var definition: ContentDef = GameCatalog.relic(relic_id)
		if definition == null:
			continue
		var count: int = int(relic_counts[relic_id])
		if additional != null and additional.id == relic_id:
			count += 1
		if definition.stat == key:
			value += definition.amount * count
		if definition.bonus_stat == key:
			value += definition.bonus_amount * count
	if additional != null and not relic_counts.has(additional.id):
		if additional.stat == key:
			value += additional.amount
		if additional.bonus_stat == key:
			value += additional.bonus_amount
	return _clamp_stat(key, value)

static func _clamp_stat(key: String, value: float) -> float:
	match key:
		"damage", "attack_speed": return maxf(0.25, value)
		"move_speed": return maxf(60.0, value)
		"max_health": return maxf(1.0, value)
		"pickup_radius": return maxf(16.0, value)
		"armor": return maxf(0.0, value)
	return value

func backpack_snapshot() -> Dictionary:
	var result: Dictionary = backpack.snapshot()
	var error: String = backpack_expansion_error()
	result["can_expand"] = error.is_empty()
	result["expansion_error"] = error
	result["linked_weapons"] = linked_weapon_uids()
	return result

func backpack_item(uid: int) -> Dictionary:
	return backpack.item(uid)

func weapon_index_for_uid(uid: int) -> int:
	for index: int in loadout.size():
		if int(loadout[index].get("uid", -1)) == uid:
			return index
	return -1

func rune_index_for_uid(uid: int) -> int:
	for index: int in rune_bag.size():
		if int(rune_bag[index].get("uid", -1)) == uid:
			return index
	return -1

func move_item(uid: int, cell: Vector2i, rotated: bool) -> bool:
	if not backpack.move(uid, cell, rotated):
		return _fail(backpack.last_error)
	_sync_backpack_projection()
	last_error = ""
	changed.emit()
	return true

func merge_preview(source_uid: int, target_uid: int) -> Dictionary:
	var source: Dictionary = backpack.item(source_uid)
	var target: Dictionary = backpack.item(target_uid)
	var error: String = backpack.merge_error(source_uid, target_uid)
	var result_rank: int = mini(BackpackInventory.MAX_RANK, int(target.get("rank", 1)) + 1)
	var result: Dictionary = {"source_uid": source_uid, "target_uid": target_uid,
		"source_rank": int(source.get("rank", 0)), "target_rank": int(target.get("rank", 0)),
		"result_rank": result_rank, "rank_after": result_rank, "can_merge": error.is_empty(), "error": error,
		"returned_rune": {}, "stat_changes": [], "damage_before": 0.0, "damage_after": 0.0}
	if source.is_empty() or target.is_empty():
		return result
	var definition: ContentDef = BackpackInventory.definition(str(target["kind"]), str(target["id"]))
	result["id"] = target["id"]
	result["kind"] = target["kind"]
	result["paid_after"] = int(source["paid"]) + int(target["paid"])
	result["cells_freed"] = _item_area(source) if error.is_empty() else 0
	if not (source.get("rune", {}) as Dictionary).is_empty() and not (target.get("rune", {}) as Dictionary).is_empty():
		result["returned_rune"] = (source["rune"] as Dictionary).duplicate(true)
		var returned_size: Vector2i = BackpackInventory.size_for("rune", str(source["rune"]["id"]))
		result["cells_freed"] = maxi(0, int(result["cells_freed"]) - returned_size.x * returned_size.y) if error.is_empty() else 0
	if definition.kind == "weapon":
		result["damage_before"] = definition.damage * stat("damage") * BackpackInventory.rank_multiplier(int(target["rank"]))
		result["damage_after"] = definition.damage * stat("damage") * BackpackInventory.rank_multiplier(result_rank)
		result["combined_damage_before"] = float(result["damage_before"]) * 2.0
		result["interval"] = definition.cooldown / stat("attack_speed")
	elif definition.kind == "relic":
		var changes: Array[Dictionary] = []
		for key: String in [definition.stat, definition.bonus_stat]:
			if key.is_empty():
				continue
			var amount: float = definition.amount if key == definition.stat else definition.bonus_amount
			changes.append({"key": key, "before": amount * BackpackInventory.rank_multiplier(int(target["rank"])), "combined_before": amount * BackpackInventory.rank_multiplier(int(target["rank"])) * 2.0, "after": amount * BackpackInventory.rank_multiplier(result_rank)})
		result["stat_changes"] = changes
	elif definition.kind == "rune":
		result["extra_hits_before"] = RuneRules.extra_hits(int(target["rank"]))
		result["extra_hits_after"] = RuneRules.extra_hits(result_rank)
		result["blast_radius_before"] = RuneRules.blast_radius(int(target["rank"]))
		result["blast_radius_after"] = RuneRules.blast_radius(result_rank)
		result["blast_multiplier_before"] = RuneRules.blast_factor(int(target["rank"]))
		result["blast_multiplier_after"] = RuneRules.blast_factor(result_rank)
	return result

func merge_items(source_uid: int, target_uid: int) -> bool:
	if not backpack.merge(source_uid, target_uid):
		return _fail(backpack.last_error)
	_sync_backpack_projection()
	health = minf(health, stat("max_health"))
	last_error = ""
	changed.emit()
	return true

func sell_item(uid: int) -> bool:
	var removed: Dictionary = backpack.remove(uid)
	if removed.is_empty():
		return _fail(backpack.last_error)
	gold += int(floorf(float(removed["paid"]) * 0.5))
	_sync_backpack_projection()
	health = minf(health, stat("max_health"))
	last_error = ""
	changed.emit()
	return true

func backpack_expansion_error() -> String:
	if backpack.height >= BackpackInventory.MAX_HEIGHT:
		return "背包已扩容至上限。"
	if gold < backpack.expansion_cost():
		return "魂屑不足。"
	return ""

func expand_backpack() -> bool:
	var error: String = backpack_expansion_error()
	if not error.is_empty():
		return _fail(error)
	var cost: int = backpack.expansion_cost()
	if not backpack.expand():
		return _fail(backpack.last_error)
	gold -= cost
	last_error = ""
	changed.emit()
	return true

func _sync_backpack_projection() -> void:
	loadout.clear()
	rune_bag.clear()
	relic_counts.clear()
	var entries: Array = backpack.snapshot()["items"]
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	for entry: Dictionary in entries:
		match str(entry["kind"]):
			"weapon": loadout.append({"uid": entry["uid"], "id": entry["id"], "rank": entry["rank"], "paid": entry["paid"], "rune": (entry["rune"] as Dictionary).duplicate(true)})
			"rune": rune_bag.append({"uid": entry["uid"], "id": entry["id"], "rank": entry["rank"], "paid": entry["paid"]})
			"relic": relic_counts[entry["id"]] = int(relic_counts.get(entry["id"], 0)) + int(BackpackInventory.rank_multiplier(int(entry["rank"])))
	_next_rune_uid = int(backpack.snapshot()["next_uid"])

static func _item_area(entry: Dictionary) -> int:
	var size: Vector2i = BackpackInventory.size_for(str(entry["kind"]), str(entry["id"]), bool(entry.get("rotated", false)))
	return size.x * size.y

func collect_souls(value: int) -> void:
	if value <= 0:
		return
	gold += value
	_wave_income += value
	xp += value
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		pending_upgrades += 1
	changed.emit()

func xp_to_next_level() -> int:
	return 42 + (level - 1) * 18

func take_damage(amount: float, source_id: String = "enemy", kind: String = "contact") -> float:
	if amount <= 0.0 or health <= 0.0:
		return 0.0
	# Each armor point adds 10% effective health, without a hard immunity threshold.
	var actual_damage: float = amount * 100.0 / (100.0 + maxf(0.0, stat("armor")) * 10.0)
	actual_damage = minf(health, actual_damage)
	if actual_damage <= 0.0:
		return 0.0
	health = maxf(0.0, health - actual_damage)
	damage_taken += actual_damage
	hits_taken += 1
	last_hit = {"amount": actual_damage, "source_id": source_id, "kind": kind, "wave": wave, "elapsed": elapsed}
	changed.emit()
	return actual_damage

func heal(amount: float) -> void:
	health = clampf(health + maxf(0.0, amount), 0.0, stat("max_health"))
	changed.emit()

func finish_wave() -> void:
	if _wave_finished:
		return
	_wave_finished = true
	# Guarantee a usable budget without double-paying successful collection.
	var minimum_income: int = 28 + (wave - 1) * 6
	gold += maxi(0, minimum_income - _wave_income)
	gold += int(RogueRules.route(active_route).get("reward", 0))
	# The altar restores health between waves; only won waves reach this settlement.
	health = stat("max_health")
	last_error = ""
	changed.emit()

func next_wave() -> void:
	wave += 1
	active_route = next_route if wave < GameCatalog.WAVE_DEFS.size() else "balanced"
	next_route = "balanced"
	rerolls = 0
	offers.clear()
	_wave_income = 0
	_wave_finished = false
	last_error = ""
	changed.emit()

func generate_shop() -> void:
	_prune_locked_offers()
	offers.clear()
	var guaranteed_kind: String = "weapon" if wave == 1 else "rune" if wave == 2 else ""
	var guarantee_satisfied: bool = false
	for locked: Dictionary in _locked_offers.values():
		if str(locked.get("kind", "")) == guaranteed_kind:
			guarantee_satisfied = true
	for index: int in range(4):
		if _locked_offers.has(index):
			var retained: Dictionary = (_locked_offers[index] as Dictionary).duplicate(true)
			retained["price"] = shop_price(_offer_definition(retained))
			offers.append(retained)
			_locked_offers[index] = retained.duplicate(true)
			continue
		var kind: String = _random_offer_kind()
		if not guaranteed_kind.is_empty() and not guarantee_satisfied:
			kind = guaranteed_kind
			guarantee_satisfied = true
		offers.append(_make_offer(kind))
	last_error = ""
	changed.emit()

func is_offer_locked(index: int) -> bool:
	if index < 0 or index >= offers.size() or not _locked_offers.has(index):
		return false
	var retained: Dictionary = _locked_offers[index]
	return _valid_locked_offer(retained) and not bool(offers[index].get("sold", false)) and _same_offer(offers[index], retained)

func locked_offer_count() -> int:
	var count: int = 0
	for retained: Dictionary in _locked_offers.values():
		if _valid_locked_offer(retained):
			count += 1
	return count

func shop_lock_error(index: int) -> String:
	if index < 0 or index >= offers.size():
		return "无效的商品。"
	var offer: Dictionary = offers[index]
	if bool(offer.get("sold", false)):
		return "已售商品无法锁定。"
	if _offer_definition(offer) == null:
		return "商品不存在，无法锁定。"
	if not is_offer_locked(index) and locked_offer_count() >= SHOP_LOCK_CAP:
		return "最多锁定2件商品，请先解锁一件。"
	return ""

func set_offer_locked(index: int, locked: bool) -> bool:
	if index < 0 or index >= offers.size():
		return _fail("无效的商品。")
	if not locked:
		if not _locked_offers.has(index):
			return true
		_locked_offers.erase(index)
	elif is_offer_locked(index):
		return true
	else:
		var error: String = shop_lock_error(index)
		if not error.is_empty():
			return _fail(error)
		_prune_locked_offers()
		_locked_offers[index] = offers[index].duplicate(true)
	last_error = ""
	changed.emit()
	return true

func _offer_definition(offer: Dictionary) -> ContentDef:
	var id: String = str(offer.get("id", ""))
	match str(offer.get("kind", "")):
		"weapon":
			return GameCatalog.weapon(id)
		"rune":
			return GameCatalog.rune(id)
		"relic":
			return GameCatalog.relic(id)
	return null

func _valid_locked_offer(offer: Dictionary) -> bool:
	if bool(offer.get("sold", false)) or _offer_definition(offer) == null:
		return false
	return true

static func _same_offer(first: Dictionary, second: Dictionary) -> bool:
	return str(first.get("kind", "")) == str(second.get("kind", "")) and str(first.get("id", "")) == str(second.get("id", "")) and int(first.get("price", 0)) == int(second.get("price", 0))

func _prune_locked_offers() -> void:
	for index: int in _locked_offers.keys():
		var retained: Dictionary = _locked_offers[index]
		var invalid: bool = not _valid_locked_offer(retained)
		if index >= 0 and index < offers.size():
			invalid = invalid or bool(offers[index].get("sold", false)) or not _same_offer(offers[index], retained)
		if invalid:
			_locked_offers.erase(index)

func purchase_error(index: int) -> String:
	# UI previews share the transaction checks without emitting or changing state.
	if index < 0 or index >= offers.size():
		return "无效的商品。"
	var offer: Dictionary = offers[index]
	if bool(offer.get("sold", false)):
		return "这件商品已售出。"
	var price: int = int(offer.get("price", 0))
	if price < 0:
		return "无效的商品价格。"
	if gold < price:
		return "魂屑不足。"
	var item_id: String = str(offer.get("id", ""))
	var kind: String = str(offer.get("kind", ""))
	if kind == "weapon":
		if GameCatalog.weapon(item_id) == null:
			return "法器不存在。"
	elif kind == "rune":
		if GameCatalog.rune(item_id) == null:
			return "符文不存在。"
	elif kind == "relic":
		if GameCatalog.relic(item_id) == null:
			return "遗物不存在。"
	else:
		return "未知的商品类型。"
	if not backpack.can_add(kind, item_id):
		return "背包空间不足。"
	return ""

func relic_purchase_preview(index: int) -> Dictionary:
	if index < 0 or index >= offers.size():
		return {}
	var offer: Dictionary = offers[index]
	if str(offer.get("kind", "")) != "relic":
		return {}
	var id: String = str(offer.get("id", ""))
	var definition: ContentDef = GameCatalog.relic(id)
	if definition == null:
		return {}
	var error: String = purchase_error(index)
	var can_buy: bool = error.is_empty()
	var price: int = int(offer.get("price", 0))
	var count: int = int(relic_counts.get(id, 0))
	var has_projection: bool = not bool(offer.get("sold", false))
	var stat_changes: Array[Dictionary] = []
	var weapon_changes: Array[Dictionary] = []
	var projected_health: float = health
	if has_projection:
		var keys: Array[String] = []
		for key: String in [definition.stat, definition.bonus_stat]:
			if key.is_empty() or keys.has(key):
				continue
			keys.append(key)
			var before: float = stat(key)
			var after: float = _stat_with_projected_relic(key, definition)
			stat_changes.append({"key": key, "before": before, "after": after, "delta": after - before})
		projected_health = _health_after_relic_purchase(health, stat("max_health"), _stat_with_projected_relic("max_health", definition))
		var damage_before: float = stat("damage")
		var damage_after: float = _stat_with_projected_relic("damage", definition)
		var speed_before: float = stat("attack_speed")
		var speed_after: float = _stat_with_projected_relic("attack_speed", definition)
		for slot: int in loadout.size():
			var weapon_id: String = str(loadout[slot].get("id", ""))
			var weapon: ContentDef = GameCatalog.weapon(weapon_id)
			if weapon == null:
				continue
			var rank: int = int(loadout[slot].get("rank", 1))
			var rank_scale: float = BackpackInventory.rank_multiplier(rank)
			weapon_changes.append({
				"slot": slot, "id": weapon_id, "rank": rank, "shots": weapon.shots,
				"damage_before": weapon.damage * rank_scale * damage_before, "damage_after": weapon.damage * rank_scale * damage_after,
				"interval_before": weapon.cooldown / speed_before, "interval_after": weapon.cooldown / speed_after,
			})
	return {
		"id": id, "can_buy": can_buy, "error": error, "price": price,
		"gold_before": gold, "gold_after": gold - price if can_buy else gold, "shortfall": maxi(0, price - gold),
		"stack_before": count, "stack_after": count + 1 if has_projection else count, "has_projection": has_projection,
		"stat_changes": stat_changes, "health_before": health, "health_after": projected_health,
		"weapon_changes": weapon_changes,
	}

static func _health_after_relic_purchase(current_health: float, previous_max: float, next_max: float) -> float:
	return minf(next_max, current_health + next_max - previous_max)

func buy_offer(index: int) -> bool:
	var error: String = purchase_error(index)
	if not error.is_empty():
		return _fail(error)
	var offer: Dictionary = offers[index]
	var price: int = int(offer.get("price", 0))
	var item_id: String = str(offer.get("id", ""))
	var kind: String = str(offer.get("kind", ""))
	var previous_max: float = stat("max_health")
	if backpack.add(kind, item_id, price).is_empty():
		return _fail(backpack.last_error)
	gold -= price
	_sync_backpack_projection()
	if kind == "relic":
		health = _health_after_relic_purchase(health, previous_max, stat("max_health"))
	offer["sold"] = true
	_locked_offers.erase(index)
	_prune_locked_offers()
	last_error = ""
	changed.emit()
	return true

func sell_weapon(index: int) -> bool:
	if index < 0 or index >= loadout.size():
		return _fail("无效的法器。")
	return sell_item(int(loadout[index].get("uid", -1)))

func sell_rune(index: int) -> bool:
	if index < 0 or index >= rune_bag.size():
		return _fail("无效的符文。")
	return sell_item(int(rune_bag[index].get("uid", -1)))

func rune_equip_preview(bag_index: int, weapon_index: int) -> Dictionary:
	if bag_index < 0 or bag_index >= rune_bag.size() or weapon_index < 0 or weapon_index >= loadout.size():
		return {}
	var weapon_id: String = str(loadout[weapon_index].get("id", ""))
	var weapon: ContentDef = GameCatalog.weapon(weapon_id)
	var incoming: Dictionary = rune_bag[bag_index]
	var rune_id: String = str(incoming.get("id", ""))
	var rune_rank: int = int(incoming.get("rank", 1))
	var previous: Dictionary = loadout[weapon_index].get("rune", {})
	if weapon == null or GameCatalog.rune(rune_id) == null:
		return {}
	if not previous.is_empty() and GameCatalog.rune(str(previous.get("id", ""))) == null:
		return {}
	var trigger_hit: int = 1 + weapon.innate_pierce
	var max_direct_targets: int = trigger_hit
	var bounce_scales: Array[float] = []
	if rune_id == "pierce" or rune_id == "bounce":
		max_direct_targets += RuneRules.extra_hits(rune_rank)
	if rune_id == "bounce":
		for hit: int in trigger_hit:
			bounce_scales.append(1.0)
		var scale: float = 1.0
		for jump: int in RuneRules.extra_hits(rune_rank):
			scale *= RuneRules.BOUNCE_DAMAGE_FACTOR
			bounce_scales.append(scale)
	var returns_to_player: bool = weapon.return_delay > 0.0
	return {
		"weapon_index": weapon_index, "weapon_id": weapon_id, "rune_id": rune_id,
		"weapon_rank": int(loadout[weapon_index].get("rank", 1)), "rune_rank": rune_rank,
		"incoming_rune": incoming.duplicate(true), "returned_rune": previous.duplicate(true),
		"bag_before": rune_bag.size(), "bag_after": rune_bag.size() - 1 + (0 if previous.is_empty() else 1),
		"shots": weapon.shots, "innate_pierce": weapon.innate_pierce, "trigger_hit": trigger_hit,
		"max_direct_targets": max_direct_targets, "bounce_scales": bounce_scales,
		"blast_radius": RuneRules.blast_radius(rune_rank) if rune_id == "blast" else 0.0,
		"blast_multiplier": RuneRules.blast_factor(rune_rank) if rune_id == "blast" else 0.0,
		"bounce_range": RuneRules.BOUNCE_RANGE if rune_id == "bounce" else 0.0,
		"returns_to_player": returns_to_player, "return_delay": weapon.return_delay,
		"return_speed": (weapon.return_speed if weapon.return_speed > 0.0 else weapon.projectile_speed) if returns_to_player else 0.0,
		"return_lifetime": (weapon.return_lifetime if weapon.return_lifetime > 0.0 else weapon.range / maxf(1.0, weapon.projectile_speed) + 1.2) if returns_to_player else 0.0,
		"return_tracks_player": returns_to_player, "shared_flight_hit_ids": true,
		"return_cancelled_by_bounce": returns_to_player and rune_id == "bounce",
		"return_consumed_on_blast": returns_to_player and rune_id == "blast",
		"cooldown_waits_for_return": false,
	}

func equip_rune(bag_index: int, weapon_index: int) -> bool:
	if bag_index < 0 or bag_index >= rune_bag.size():
		return _fail("无效的符文。")
	if weapon_index < 0 or weapon_index >= loadout.size():
		return _fail("无效的法器。")
	if not backpack.equip(int(rune_bag[bag_index].get("uid", -1)), int(loadout[weapon_index].get("uid", -1))):
		return _fail(backpack.last_error)
	_sync_backpack_projection()
	last_error = ""
	changed.emit()
	return true

func unequip_rune(weapon_index: int) -> bool:
	if weapon_index < 0 or weapon_index >= loadout.size():
		return _fail("无效的法器。")
	if not backpack.unequip(int(loadout[weapon_index].get("uid", -1))):
		return _fail(backpack.last_error)
	_sync_backpack_projection()
	last_error = ""
	changed.emit()
	return true

func reroll_shop() -> bool:
	var cost: int = reroll_cost()
	if gold < cost:
		return _fail("魂屑不足，无法刷新。")
	gold -= cost
	rerolls += 1
	generate_shop()
	return true

func reroll_cost() -> int:
	return 3 + (wave - 1) * 2 + rerolls * 2

func shop_price(definition: ContentDef) -> int:
	return int(roundf(float(definition.price) * (1.0 + float(wave - 1) * 0.12)))

func upgrade_choices() -> Array[Dictionary]:
	if pending_upgrades <= 0:
		return []
	if _upgrade_options.is_empty():
		var pool: Array[Dictionary] = UPGRADE_POOL.duplicate(true)
		for index: int in range(3):
			var chosen_index: int = rng.randi_range(0, pool.size() - 1)
			var option: Dictionary = pool[chosen_index]
			option["display_name"] = option["name"]
			option["icon"] = option["id"]
			option["color"] = GameCatalog.relic(str(option["id"])).color
			_upgrade_options.append(option)
			pool.remove_at(chosen_index)
	return _upgrade_options.duplicate(true)

func choose_upgrade(id: String) -> bool:
	if pending_upgrades <= 0:
		return _fail("当前没有待选强化。")
	var choices: Array[Dictionary] = upgrade_choices()
	for option: Dictionary in choices:
		if str(option["id"]) != id:
			continue
		var key: String = str(option["stat"])
		var amount: float = float(option["amount"])
		_upgrade_bonuses[key] = float(_upgrade_bonuses.get(key, 0.0)) + amount
		if key == "max_health":
			health = minf(stat("max_health"), health + amount)
		pending_upgrades -= 1
		_upgrade_options.clear()
		last_error = ""
		changed.emit()
		return true
	return _fail("请选择当前提供的强化。")

func summary() -> Dictionary:
	return {
		"seed": _run_seed,
		"wave": wave,
		"gold": gold,
		"xp": xp,
		"level": level,
		"pending_upgrades": pending_upgrades,
		"health": health,
		"max_health": stat("max_health"),
		"kills": kills,
		"elapsed": elapsed,
		"damage_dealt_by_weapon": damage_dealt_by_weapon.duplicate(true),
		"damage_taken": damage_taken,
		"hits_taken": hits_taken,
		"last_hit": last_hit.duplicate(true),
		"loadout": loadout.duplicate(true),
		"rune_bag": rune_bag.duplicate(true),
		"relic_counts": relic_counts.duplicate(true),
		"backpack": backpack_snapshot(),
		"rogue": rogue_choices(),
	}

func _random_offer_kind() -> String:
	var roll: float = rng.randf()
	if roll < 0.4:
		return "weapon"
	if roll < 0.65:
		return "rune"
	return "relic"

func _make_offer(kind: String) -> Dictionary:
	var pool: Array[ContentDef] = []
	if kind == "weapon":
		pool = GameCatalog.weapons()
	elif kind == "rune":
		pool = GameCatalog.runes()
	else:
		pool = GameCatalog.relics()
	var definition: ContentDef = pool[rng.randi_range(0, pool.size() - 1)]
	var price: int = shop_price(definition)
	return {"id": definition.id, "kind": kind, "price": price, "sold": false}

func _fail(message: String) -> bool:
	last_error = message
	changed.emit()
	return false
