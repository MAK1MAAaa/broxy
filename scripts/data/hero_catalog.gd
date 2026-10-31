class_name HeroCatalog
extends RefCounted
## Main characters and backpack companions share one explicit character identity.

const LEGACY_IDS: Array[String] = ["alk", "clarisse", "celtie", "hanabi"]
const PROFILE_IDS: Array[String] = ["nasir", "mordiga", "falsche"]
const IDS: Array[String] = ["alk", "clarisse", "celtie", "hanabi", "nasir", "mordiga", "falsche"]
const HERO_DEFS: Array[HeroDef] = [
	preload("res://data/heroes/alk.tres"),
	preload("res://data/heroes/clarisse.tres"),
	preload("res://data/heroes/celtie.tres"),
	preload("res://data/heroes/hanabi.tres"),
	preload("res://data/heroes/nasir.tres"),
	preload("res://data/heroes/mordiga.tres"),
	preload("res://data/heroes/falsche.tres"),
]
const REAR_IDS: Dictionary = {"pulse": "clarisse", "starfall": "hanabi", "arc_slash": "celtie"}
const REAR_BONUSES: Dictionary = {
	"pulse": {"damage": 0.08},
	"starfall": {"max_health": 12.0},
	"arc_slash": {"attack_speed": 0.06},
}

static func normalize_id(id: String) -> String:
	return id if IDS.has(id) else "alk"

static func definition(id: String) -> HeroDef:
	var normalized: String = normalize_id(id)
	for hero: HeroDef in HERO_DEFS:
		if hero.id == normalized:
			return hero
	return HERO_DEFS[0]

static func rear_for_skill(skill_id: String) -> HeroDef:
	return definition(str(REAR_IDS[skill_id])) if REAR_IDS.has(skill_id) else null

static func rear_bonuses(skill_id: String, rank: int) -> Dictionary:
	var result: Dictionary = (REAR_BONUSES.get(skill_id, {}) as Dictionary).duplicate(true)
	var weight: float = BackpackInventory.rank_multiplier(rank)
	for key: String in result:
		result[key] = float(result[key]) * weight
	return result

static func hero_skill_parameters(id: String, stats: Dictionary) -> Dictionary:
	var hero: HeroDef = definition(id)
	var result: Dictionary = hero.main_skill.duplicate(true)
	var raw_multiplier: Variant = stats.get("damage", 1.0)
	var multiplier: float = float(raw_multiplier) if raw_multiplier is float or raw_multiplier is int else 1.0
	if not is_finite(multiplier):
		multiplier = 1.0
	result["damage"] = float(result.get("damage", 0.0)) * maxf(0.0, multiplier)
	var raw_haste: Variant = stats.get("skill_haste", 0.0)
	var haste: float = float(raw_haste) if raw_haste is float or raw_haste is int else 0.0
	haste = clampf(haste, 0.0, 2.0) if is_finite(haste) else 0.0
	result["cooldown"] = float(result.get("cooldown", 1.0)) / (1.0 + haste)
	if result.get("delivery", "instant") == "bombs":
		var raw_summon: Variant = stats.get("summon_damage", 1.0)
		var summon: float = float(raw_summon) if raw_summon is float or raw_summon is int else 1.0
		result["damage"] *= maxf(0.0, summon) if is_finite(summon) else 1.0
	result["hero_id"] = hero.id
	result["rank"] = 1
	result["source_skill_name"] = hero.source_skill_name
	result["source_skill_weight"] = hero.source_skill_weight
	result["adapted"] = true
	return result
