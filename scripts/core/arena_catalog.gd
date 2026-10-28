class_name ArenaCatalog
extends RefCounted
## Artwork generation and combat both read the same authored ellipse boundaries.

const IDS: Array[String] = ["reliquary", "mire", "glacier", "ashland"]
const SOURCE_PATH: String = "res://data/arenas.json"
const WORLD_BOUNDS: Rect2 = Rect2(-1082, -535, 3444, 1800)
const MAX_VIEW_SIZE: Vector2 = Vector2(1280, 720)
const BORDER_SIZE: float = 64.0
const ART_MARGIN_LEFT: float = 64.0
const ART_MARGIN_TOP: float = 144.0
const ART_MARGIN_RIGHT: float = 272.0
const ART_MARGIN_BOTTOM: float = 160.0

static var _definitions: Dictionary = {}


static func normalize_id(id: String) -> String:
	return id if IDS.has(id) else IDS[0]


static func definition(id: String) -> Dictionary:
	_ensure_loaded()
	return (_definitions[normalize_id(id)] as Dictionary).duplicate(true)


static func art_rect() -> Rect2:
	var offset := Vector2(ART_MARGIN_LEFT, ART_MARGIN_TOP)
	var extension := Vector2(ART_MARGIN_LEFT + ART_MARGIN_RIGHT, ART_MARGIN_TOP + ART_MARGIN_BOTTOM)
	return Rect2(WORLD_BOUNDS.position - offset, WORLD_BOUNDS.size + extension)


static func texture_path(id: String) -> String:
	return "res://assets/starfall/maps/expanded/%s.svg" % normalize_id(id)


static func camera_center(point: Vector2, view_size: Vector2 = MAX_VIEW_SIZE) -> Vector2:
	var half: Vector2 = _safe_view_size(view_size) * 0.5
	var bounds: Rect2 = art_rect()
	var target: Vector2 = point if point.is_finite() else WORLD_BOUNDS.get_center()
	return Vector2(clampf(target.x, bounds.position.x + half.x, bounds.end.x - half.x), clampf(target.y, bounds.position.y + half.y, bounds.end.y - half.y))


static func visible_rect(point: Vector2, view_size: Vector2 = MAX_VIEW_SIZE) -> Rect2:
	var size: Vector2 = _safe_view_size(view_size)
	return Rect2(camera_center(point, size) - size * 0.5, size)


static func _safe_view_size(value: Vector2) -> Vector2:
	if not value.is_finite() or value.x <= 0.0 or value.y <= 0.0:
		return MAX_VIEW_SIZE
	return Vector2(minf(value.x, MAX_VIEW_SIZE.x), minf(value.y, MAX_VIEW_SIZE.y))


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
