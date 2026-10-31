class_name ActiveSkillRules
extends RefCounted
## Pure rank and stat projections shared by inventory forecasts and combat casts.

const LIMIT: int = 2
const MAX_RANK: int = 3

static func parameters(id: String, rank: int, stats: Dictionary) -> Dictionary:
	var result: Dictionary = _parameters(id, rank, stats)
	if not result.is_empty():
		result["cooldown"] = float(result["cooldown"]) / (1.0 + clampf(_stat(stats, "skill_haste", 0.0), 0.0, 2.0))
		result["element"] = "wind" if id == "arc_slash" else "fire"
	var hero: HeroDef = HeroCatalog.rear_for_skill(id)
	if hero != null and not result.is_empty():
		result["skill_name"] = result["name"]
		result["name"] = hero.display_name
		result["hero_id"] = hero.id
		result["rear_bonuses"] = HeroCatalog.rear_bonuses(id, rank)
	return result

static func _parameters(id: String, rank: int, stats: Dictionary) -> Dictionary:
	var tier: int = clampi(rank, 1, MAX_RANK)
	var index: int = tier - 1
	var multiplier: float = maxf(0.0, _stat(stats, "damage", 1.0))
	match id:
		"pulse":
			return {"id": id, "name": "秘术脉冲", "rank": tier,
				"radius": PulseRules.clamp_radius(_stat(stats, "pulse_radius", PulseRules.RADIUS) + float(index) * 12.0),
				"damage": 0.0, "cooldown": PulseRules.clamp_cooldown(_stat(stats, "pulse_cooldown", PulseRules.COOLDOWN)),
				"push_distance": PulseRules.PUSH_DISTANCE, "hinder_factor": PulseRules.HINDER_FACTOR,
				"hinder_seconds": PulseRules.HINDER_SECONDS}
		"starfall":
			var starfall_damage: Array[float] = [32.0, 48.0, 72.0]
			return {"id": id, "name": "落星", "rank": tier, "radius": 112.0 + float(index) * 8.0,
				"damage": starfall_damage[index] * multiplier, "cooldown": 10.0}
		"arc_slash":
			var slash_damage: Array[float] = [24.0, 36.0, 54.0]
			return {"id": id, "name": "月弧", "rank": tier, "radius": 148.0 + float(index) * 8.0,
				"damage": slash_damage[index] * multiplier, "cooldown": 6.0, "half_angle_radians": deg_to_rad(50.0)}
	return {}

static func _stat(stats: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = stats.get(key, fallback)
	if not value is float and not value is int:
		return fallback
	var number: float = float(value)
	return number if is_finite(number) else fallback
