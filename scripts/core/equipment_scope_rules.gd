class_name EquipmentScopeRules
extends RefCounted
## Pure equipment ownership and beneficiary projection over a detached inventory.

const MODIFIER_STATS: Array[String] = ["damage", "skill_damage", "max_health_ratio"]

static func default_owner(definition: ContentDef) -> Dictionary:
	return {"kind": "main"} if definition != null and definition.equipment_owner == "main" else {}

static func actor_key(actor_ref: Dictionary) -> String:
	if actor_ref.get("kind", "") == "main":
		return "main"
	var uid: Variant = actor_ref.get("skill_uid", -1)
	if actor_ref.get("kind", "") == "rear" and uid is int and int(uid) > 0:
		return "rear:%d" % int(uid)
	return ""

static func rear_actor_ref(item: Dictionary, entries: Array) -> Dictionary:
	var uid: Variant = item.get("uid", -1)
	if not uid is int or int(uid) <= 0 or str(item.get("kind", "skill")) != "skill":
		return {}
	for entry: Dictionary in entries:
		if str(entry.get("kind", "")) == "skill" and int(entry.get("uid", -1)) == int(uid):
			if str(entry.get("id", "")) != str(item.get("id", "")) or HeroCatalog.rear_for_skill(str(entry.get("id", ""))) == null:
				return {}
			return {"kind": "rear", "skill_uid": int(uid)}
	return {}

static func actor_context(actor_ref: Dictionary, main_hero: String, entries: Array) -> Dictionary:
	var key: String = actor_key(actor_ref)
	var hero: HeroDef
	var reference: Dictionary
	if key == "main" and HeroCatalog.IDS.has(main_hero):
		hero = HeroCatalog.definition(main_hero)
		reference = {"kind": "main"}
	elif key.begins_with("rear:"):
		for entry: Dictionary in entries:
			if str(entry.get("kind", "")) == "skill" and int(entry.get("uid", -1)) == int(actor_ref["skill_uid"]):
				hero = HeroCatalog.rear_for_skill(str(entry.get("id", "")))
				reference = {"kind": "rear", "skill_uid": int(entry["uid"])}
				break
	if hero == null:
		return {}
	return {"actor_ref": reference, "hero_id": hero.id, "source_id": hero.source_id, "element": hero.element}

static func amount_for_rank(modifier: Dictionary, rank: int) -> float:
	var values: Variant = modifier.get("amount_by_rank", [])
	if not values is Array or values.size() != BackpackInventory.MAX_RANK or rank < 1 or rank > BackpackInventory.MAX_RANK:
		return 0.0
	for value: Variant in values:
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
			return 0.0
	return float(values[rank - 1])

static func project(entries: Array, main_hero: String, definitions: Dictionary = {}) -> Dictionary:
	var actors: Array[Dictionary] = []
	var seen: Dictionary = {}
	var main: Dictionary = actor_context({"kind": "main"}, main_hero, entries)
	if not main.is_empty():
		actors.append(main)
		seen["main"] = true
	for entry: Dictionary in entries:
		if str(entry.get("kind", "")) == "skill":
			var rear: Dictionary = actor_context({"kind": "rear", "skill_uid": entry.get("uid", -1)}, main_hero, entries)
			if not rear.is_empty() and not seen.has(actor_key(rear["actor_ref"])):
				actors.append(rear)
				seen[actor_key(rear["actor_ref"])] = true
	var result: Dictionary = {}
	for entry: Dictionary in entries:
		if str(entry.get("kind", "")) != "weapon":
			continue
		var id: String = str(entry.get("id", ""))
		var source: Variant = definitions.get(id) if definitions.has(id) else GameCatalog.weapon(id)
		if not source is ContentDef:
			continue
		var definition: ContentDef = source
		if definition.equipment_modifiers.is_empty():
			continue
		var owner_value: Variant = entry.get("owner_ref", {})
		if not owner_value is Dictionary or definition.equipment_owner != "main" or actor_key(owner_value) != "main":
			continue
		var owner: Dictionary = actor_context(owner_value, main_hero, entries)
		if owner.is_empty():
			continue
		for modifier: Dictionary in definition.equipment_modifiers:
			var stat: String = str(modifier.get("stat", ""))
			if not MODIFIER_STATS.has(stat):
				continue
			var amount: float = amount_for_rank(modifier, int(entry.get("rank", 1)))
			if amount <= 0.0:
				continue
			for actor: Dictionary in actors:
				if not _benefits(modifier, actor, owner):
					continue
				var key: String = actor_key(actor["actor_ref"])
				var bonuses: Dictionary = result.get(key, {})
				var total: float = float(bonuses.get(stat, 0.0)) + amount
				if is_finite(total):
					bonuses[stat] = total
					result[key] = bonuses
	return result

static func modifier_stat_keys(definition: ContentDef) -> Array[String]:
	var result: Array[String] = []
	if definition == null:
		return result
	for modifier: Dictionary in definition.equipment_modifiers:
		var stat: String = str(modifier.get("stat", ""))
		if not MODIFIER_STATS.has(stat):
			continue
		var key: String = "max_health" if stat == "max_health_ratio" else stat
		if not result.has(key):
			result.append(key)
	return result

static func _benefits(modifier: Dictionary, actor: Dictionary, owner: Dictionary) -> bool:
	match str(modifier.get("target", "")):
		"owner": return actor["actor_ref"] == owner["actor_ref"]
		"party": return true
		"party_element": return not str(modifier.get("element", "")).is_empty() and str(actor["element"]) == str(modifier["element"])
	return false
