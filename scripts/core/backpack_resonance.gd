class_name BackpackResonance
extends RefCounted
## Pure grid geometry shared by inventory forecasts, combat projections and the shop.

const BONUS_PER_WEIGHT: float = 0.03
const MAX_BONUS: float = 0.18

static func evaluate(items: Array) -> Dictionary:
	var weapons: Dictionary = {}
	var relics: Dictionary = {}
	for value: Variant in items:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var uid: int = int(entry.get("uid", -1))
		if uid <= 0 or _rectangle(entry).size == Vector2i.ZERO:
			continue
		match str(entry.get("kind", "")):
			"weapon": weapons[uid] = entry
			"relic": relics[uid] = entry
	var result: Dictionary = {}
	for uid: int in weapons:
		var sources: Array[int] = []
		var weight: int = 0
		for relic_uid: int in relics:
			if relic_uid == uid or contact_segment(weapons[uid], relics[relic_uid]).is_empty():
				continue
			sources.append(relic_uid)
			weight += int(BackpackInventory.rank_multiplier(int(relics[relic_uid].get("rank", 1))))
		sources.sort()
		var raw_bonus: float = float(weight) * BONUS_PER_WEIGHT
		result[uid] = {"bonus": minf(MAX_BONUS, raw_bonus), "raw_bonus": raw_bonus, "weight": weight, "source_uids": sources}
	return result

static func contact_segment(a: Dictionary, b: Dictionary) -> PackedVector2Array:
	var first: Rect2i = _rectangle(a)
	var second: Rect2i = _rectangle(b)
	if first.size == Vector2i.ZERO or second.size == Vector2i.ZERO:
		return PackedVector2Array()
	var top: int = maxi(first.position.y, second.position.y)
	var bottom: int = mini(first.end.y, second.end.y)
	if top < bottom and (first.end.x == second.position.x or second.end.x == first.position.x):
		var x: int = first.end.x if first.end.x == second.position.x else first.position.x
		return PackedVector2Array([Vector2(x, top), Vector2(x, bottom)])
	var left: int = maxi(first.position.x, second.position.x)
	var right: int = mini(first.end.x, second.end.x)
	if left < right and (first.end.y == second.position.y or second.end.y == first.position.y):
		var y: int = first.end.y if first.end.y == second.position.y else first.position.y
		return PackedVector2Array([Vector2(left, y), Vector2(right, y)])
	return PackedVector2Array()

static func _rectangle(entry: Dictionary) -> Rect2i:
	var size: Vector2i = BackpackInventory.size_for(str(entry.get("kind", "")), str(entry.get("id", "")), bool(entry.get("rotated", false)))
	if size.x <= 0 or size.y <= 0:
		return Rect2i()
	return Rect2i(Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))), size)
