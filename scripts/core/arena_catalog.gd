class_name ArenaCatalog
extends RefCounted
## Artwork generation and combat both read the same authored ellipse boundaries.

const IDS: Array[String] = ["reliquary", "mire", "glacier", "ashland"]
const SOURCE_PATH: String = "res://data/arenas.json"

static var _definitions: Dictionary = {}


static func normalize_id(id: String) -> String:
	return id if IDS.has(id) else IDS[0]


static func definition(id: String) -> Dictionary:
	_ensure_loaded()
	return (_definitions[normalize_id(id)] as Dictionary).duplicate(true)


static func movement_multiplier(id: String, point: Vector2) -> float:
	# The original arena skips every zone query, retaining its old arithmetic/RNG.
	if id == IDS[0] or not IDS.has(id) or not point.is_finite():
		return 1.0
	_ensure_loaded()
	var arena: Dictionary = _definitions[id]
	return float(arena["move_multiplier"]) if _inside_zone(arena, point) else 1.0


static func terrain_name(id: String, point: Vector2) -> String:
	if id == IDS[0] or not IDS.has(id) or not point.is_finite():
		return ""
	_ensure_loaded()
	var arena: Dictionary = _definitions[id]
	return str(arena["terrain_name"]) if _inside_zone(arena, point) else ""


static func _inside_zone(arena: Dictionary, point: Vector2) -> bool:
	for zone: Dictionary in arena["zones"]:
		var center: Array = zone["center"]
		var radius: Array = zone["radius"]
		var x: float = (point.x - float(center[0])) / float(radius[0])
		var y: float = (point.y - float(center[1])) / float(radius[1])
		if x * x + y * y <= 1.0:
			return true
	return false


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if parsed is Array:
		for item: Dictionary in parsed:
			_definitions[str(item["id"])] = item
	# Missing exported configuration is a build error, rather than an invisible
	# switch to a different arena or movement rule.
	assert(_definitions.size() == IDS.size(), "The arena catalog must contain all four authored maps")
	for id: String in IDS:
		assert(_definitions.has(id), "Missing arena: " + id)
