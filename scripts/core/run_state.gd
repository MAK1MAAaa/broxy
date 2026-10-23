class_name RunState
extends RefCounted

signal changed

const WEAPON_CAP: int = 4
const RUNE_BAG_CAP: int = 4
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
var loadout: Array[Dictionary] = []
var rune_bag: Array[Dictionary] = []
var relic_counts: Dictionary = {}
var offers: Array[Dictionary] = []
var rerolls: int = 0
var last_error: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

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
	_next_rune_uid = 1
	_wave_income = 0
	_wave_finished = false
	_upgrade_bonuses.clear()
	_upgrade_options.clear()
	_locked_offers.clear()
	var starting_weapon: String = starter if GameCatalog.weapon(starter) != null else "bone"
	loadout.append({"id": starting_weapon, "paid": 0, "rune": {}})
	changed.emit()

func stat(key: String) -> float:
	return _stat_with_projected_relic(key)

func _stat_with_projected_relic(key: String, additional: ContentDef = null) -> float:
	var value: float = float(BASE_STATS.get(key, 0.0)) + float(_upgrade_bonuses.get(key, 0.0))
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
	return value

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
	# The altar restores health between waves; only won waves reach this settlement.
	health = stat("max_health")
	last_error = ""
	changed.emit()

func next_wave() -> void:
	wave += 1
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
	if str(offer.get("kind", "")) == "relic" and int(relic_counts.get(str(offer.get("id", "")), 0)) >= RELIC_CAP:
		return "该遗物已达到3层上限。"
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
	return str(offer.get("kind", "")) != "relic" or int(relic_counts.get(str(offer.get("id", "")), 0)) < RELIC_CAP

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
	if gold < price:
		return "魂屑不足。"
	var item_id: String = str(offer.get("id", ""))
	var kind: String = str(offer.get("kind", ""))
	if kind == "weapon":
		if GameCatalog.weapon(item_id) == null:
			return "法器不存在。"
		if loadout.size() >= WEAPON_CAP:
			return "法器槽已满，请先出售一件法器。"
	elif kind == "rune":
		if GameCatalog.rune(item_id) == null:
			return "符文不存在。"
		if rune_bag.size() >= RUNE_BAG_CAP:
			return "备用符文已满，请先装备或出售。"
	elif kind == "relic":
		if GameCatalog.relic(item_id) == null:
			return "遗物不存在。"
		if int(relic_counts.get(item_id, 0)) >= RELIC_CAP:
			return "该遗物已达到3层上限。"
	else:
		return "未知的商品类型。"
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
	var has_projection: bool = not bool(offer.get("sold", false)) and count < RELIC_CAP
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
			weapon_changes.append({
				"slot": slot, "id": weapon_id, "shots": weapon.shots,
				"damage_before": weapon.damage * damage_before, "damage_after": weapon.damage * damage_after,
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
	gold -= price
	if kind == "weapon":
		loadout.append({"id": item_id, "paid": price, "rune": {}})
	elif kind == "rune":
		rune_bag.append({"id": item_id, "paid": price, "uid": _next_rune_uid})
		_next_rune_uid += 1
	else:
		var previous_max: float = stat("max_health")
		relic_counts[item_id] = int(relic_counts.get(item_id, 0)) + 1
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
	if loadout.size() <= 1:
		return _fail("必须保留至少一件法器。")
	var entry: Dictionary = loadout[index]
	var equipped_rune: Dictionary = entry.get("rune", {})
	if not equipped_rune.is_empty() and rune_bag.size() >= RUNE_BAG_CAP:
		return _fail("备用符文已满，无法收回法器上的符文。")
	if not equipped_rune.is_empty():
		rune_bag.append(equipped_rune)
	gold += int(floorf(float(entry.get("paid", 0)) * 0.5))
	loadout.remove_at(index)
	last_error = ""
	changed.emit()
	return true

func sell_rune(index: int) -> bool:
	if index < 0 or index >= rune_bag.size():
		return _fail("无效的符文。")
	gold += int(floorf(float(rune_bag[index].get("paid", 0)) * 0.5))
	rune_bag.remove_at(index)
	last_error = ""
	changed.emit()
	return true

func rune_equip_preview(bag_index: int, weapon_index: int) -> Dictionary:
	if bag_index < 0 or bag_index >= rune_bag.size() or weapon_index < 0 or weapon_index >= loadout.size():
		return {}
	var weapon_id: String = str(loadout[weapon_index].get("id", ""))
	var weapon: ContentDef = GameCatalog.weapon(weapon_id)
	var incoming: Dictionary = rune_bag[bag_index]
	var rune_id: String = str(incoming.get("id", ""))
	var previous: Dictionary = loadout[weapon_index].get("rune", {})
	if weapon == null or GameCatalog.rune(rune_id) == null:
		return {}
	if not previous.is_empty() and GameCatalog.rune(str(previous.get("id", ""))) == null:
		return {}
	var trigger_hit: int = 1 + weapon.innate_pierce
	var max_direct_targets: int = trigger_hit
	var bounce_scales: Array[float] = []
	if rune_id == "pierce" or rune_id == "bounce":
		max_direct_targets += RuneRules.EXTRA_HITS
	if rune_id == "bounce":
		for hit: int in trigger_hit:
			bounce_scales.append(1.0)
		var scale: float = 1.0
		for jump: int in RuneRules.EXTRA_HITS:
			scale *= RuneRules.BOUNCE_DAMAGE_FACTOR
			bounce_scales.append(scale)
	return {
		"weapon_index": weapon_index, "weapon_id": weapon_id, "rune_id": rune_id,
		"incoming_rune": incoming.duplicate(true), "returned_rune": previous.duplicate(true),
		"bag_before": rune_bag.size(), "bag_after": rune_bag.size() - 1 + (0 if previous.is_empty() else 1),
		"shots": weapon.shots, "innate_pierce": weapon.innate_pierce, "trigger_hit": trigger_hit,
		"max_direct_targets": max_direct_targets, "bounce_scales": bounce_scales,
		"blast_radius": RuneRules.BLAST_RADIUS if rune_id == "blast" else 0.0,
		"blast_multiplier": RuneRules.BLAST_DAMAGE_FACTOR if rune_id == "blast" else 0.0,
		"bounce_range": RuneRules.BOUNCE_RANGE if rune_id == "bounce" else 0.0,
	}

func equip_rune(bag_index: int, weapon_index: int) -> bool:
	if bag_index < 0 or bag_index >= rune_bag.size():
		return _fail("无效的符文。")
	if weapon_index < 0 or weapon_index >= loadout.size():
		return _fail("无效的法器。")
	var previous_rune: Dictionary = loadout[weapon_index].get("rune", {})
	var next_rune: Dictionary = rune_bag[bag_index]
	rune_bag.remove_at(bag_index)
	loadout[weapon_index]["rune"] = next_rune
	if not previous_rune.is_empty():
		rune_bag.append(previous_rune)
	last_error = ""
	changed.emit()
	return true

func unequip_rune(weapon_index: int) -> bool:
	if weapon_index < 0 or weapon_index >= loadout.size():
		return _fail("无效的法器。")
	var equipped_rune: Dictionary = loadout[weapon_index].get("rune", {})
	if equipped_rune.is_empty():
		return _fail("这件法器没有装备符文。")
	if rune_bag.size() >= RUNE_BAG_CAP:
		return _fail("备用符文已满。")
	rune_bag.append(equipped_rune)
	loadout[weapon_index]["rune"] = {}
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
		for definition: ContentDef in GameCatalog.relics():
			if int(relic_counts.get(definition.id, 0)) < RELIC_CAP:
				pool.append(definition)
		if pool.is_empty():
			kind = "weapon"
			pool = GameCatalog.weapons()
	var definition: ContentDef = pool[rng.randi_range(0, pool.size() - 1)]
	var price: int = shop_price(definition)
	return {"id": definition.id, "kind": kind, "price": price, "sold": false}

func _fail(message: String) -> bool:
	last_error = message
	changed.emit()
	return false
