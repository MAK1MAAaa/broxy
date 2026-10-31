class_name ArenaCatalog
extends RefCounted
## Shared world geometry, authored terrain and source-art resource paths.

const LEGACY_IDS: Array[String] = ["reliquary", "mire", "glacier", "ashland", "town", "throne", "tower_peak"]
const ORIGINAL_STAGE_IDS: Array[String] = ["jp_sand_2_9_5", "jp_shrine_6_6_2", "jp_ship_3_6_2"]
const IDS: Array[String] = ["reliquary", "mire", "glacier", "ashland", "town", "throne", "tower_peak", "jp_sand_2_9_5", "jp_shrine_6_6_2", "jp_ship_3_6_2"]
const SOURCE_PATH: String = "res://data/arenas.json"
const LAYOUT_PATH: String = "res://data/worldflipper/layouts.json"
const WORLD_BOUNDS: Rect2 = Rect2(-1082, -535, 3444, 1800)
const MAX_VIEW_SIZE: Vector2 = Vector2(1280, 720)
const BORDER_SIZE: float = 64.0
const ART_MARGIN_LEFT: float = 64.0
const ART_MARGIN_TOP: float = 232.0
const ART_MARGIN_RIGHT: float = 272.0
const ART_MARGIN_BOTTOM: float = 160.0
const TERRAIN_CELL_SIZE: float = 128.0

class TerrainIndex extends RefCounted:
	var multiplier: float = 1.0
	var terrain_name: String = ""
	var centers_x: PackedFloat64Array = PackedFloat64Array()
	var centers_y: PackedFloat64Array = PackedFloat64Array()
	var radii_x: PackedFloat64Array = PackedFloat64Array()
	var radii_y: PackedFloat64Array = PackedFloat64Array()
	var cells: Dictionary = {}
	var empty_ids: PackedInt32Array = PackedInt32Array()
	var minimum_x: float = INF
	var minimum_y: float = INF
	var maximum_x: float = -INF
	var maximum_y: float = -INF

	func _init(arena: Dictionary) -> void:
		multiplier = float(arena["move_multiplier"])
		terrain_name = str(arena["terrain_name"])
		for zone: Dictionary in arena["zones"]:
			var center: Array = zone["center"]
			var radius: Array = zone["radius"]
			var cx: float = float(center[0])
			var cy: float = float(center[1])
			var rx: float = float(radius[0])
			var ry: float = float(radius[1])
			var index: int = centers_x.size()
			centers_x.append(cx)
			centers_y.append(cy)
			radii_x.append(rx)
			radii_y.append(ry)
			minimum_x = minf(minimum_x, cx - rx)
			minimum_y = minf(minimum_y, cy - ry)
			maximum_x = maxf(maximum_x, cx + rx)
			maximum_y = maxf(maximum_y, cy + ry)
			var first := Vector2i(floori((cx - rx) / TERRAIN_CELL_SIZE), floori((cy - ry) / TERRAIN_CELL_SIZE))
			var last := Vector2i(floori((cx + rx) / TERRAIN_CELL_SIZE), floori((cy + ry) / TERRAIN_CELL_SIZE))
			for x: int in range(first.x, last.x + 1):
				for y: int in range(first.y, last.y + 1):
					var key := Vector2i(x, y)
					var ids: PackedInt32Array = cells.get(key, PackedInt32Array())
					ids.append(index)
					cells[key] = ids

	func contains(point: Vector2) -> bool:
		if point.x < minimum_x or point.x > maximum_x or point.y < minimum_y or point.y > maximum_y:
			return false
		var key := Vector2i(floori(point.x / TERRAIN_CELL_SIZE), floori(point.y / TERRAIN_CELL_SIZE))
		var ids: PackedInt32Array = cells.get(key, empty_ids)
		for index: int in ids:
			var x: float = (point.x - centers_x[index]) / radii_x[index]
			var y: float = (point.y - centers_y[index]) / radii_y[index]
			if x * x + y * y <= 1.0:
				return true
		return false

static var _definitions: Dictionary = {}
static var _terrain_indices: Dictionary = {}
static var _wall_geometry: Dictionary = {}


static func normalize_id(id: String) -> String:
	return id if contains(id) else IDS[0]


static func contains(id: String) -> bool:
	return IDS.has(id) or WorldMapCatalog.contains(id)


static func is_source_stage(id: String) -> bool:
	return ORIGINAL_STAGE_IDS.has(id) or WorldMapCatalog.contains(id)


static func definition(id: String) -> Dictionary:
	_ensure_loaded()
	var known: String = normalize_id(id)
	if not _definitions.has(known):
		_definitions[known] = WorldMapCatalog.definition(known)
	return (_definitions[known] as Dictionary).duplicate(true)


static func art_rect() -> Rect2:
	var offset := Vector2(ART_MARGIN_LEFT, ART_MARGIN_TOP)
	var extension := Vector2(ART_MARGIN_LEFT + ART_MARGIN_RIGHT, ART_MARGIN_TOP + ART_MARGIN_BOTTOM)
	return Rect2(WORLD_BOUNDS.position - offset, WORLD_BOUNDS.size + extension)


static func texture_path(id: String) -> String:
	var known: String = normalize_id(id)
	if WorldMapCatalog.contains(known):
		return str(WorldMapCatalog.entry(known)["texture_path"])
	return "res://assets/worldflipper/%s/%s.png" % ["stages" if ORIGINAL_STAGE_IDS.has(known) else "maps", known]

static func preview_path(id: String) -> String:
	var known: String = normalize_id(id)
	if WorldMapCatalog.contains(known):
		return texture_path(known)
	return "res://assets/worldflipper/%s/previews/%s.png" % ["stages" if ORIGINAL_STAGE_IDS.has(known) else "maps", known]


static func stage_info(id: String) -> Dictionary:
	return (definition(id).get("stage", {}) as Dictionary).duplicate(true)


static func play_bounds(id: String) -> Rect2:
	if WorldMapCatalog.contains(id):
		return WorldMapCatalog.play_bounds(id)
	if not is_source_stage(id):
		return WORLD_BOUNDS
	var rect: Array = stage_info(id)["play_bounds"]
	return Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))


static func wall_geometry(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if WorldMapCatalog.contains(id):
		return WorldMapCatalog.walls(id)
	if not ORIGINAL_STAGE_IDS.has(id):
		return result
	_ensure_loaded()
	_ensure_walls_loaded()
	for row: Dictionary in _wall_geometry[id]:
		result.append(row.duplicate(true))
	return result


static func _ensure_walls_loaded() -> void:
	if not _wall_geometry.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	assert(parsed is Dictionary and parsed.get("layouts") is Array, "Original stages require their verified terrain geometry")
	var layouts: Dictionary = {}
	for layout: Dictionary in parsed["layouts"]:
		layouts[str(layout["id"])] = layout
	for id: String in ORIGINAL_STAGE_IDS:
		var stage: Dictionary = _definitions[id]["stage"]
		var source: Dictionary = layouts[str(stage["layout_id"])]
		assert(source["field_id"] == stage["field_id"], "Stage background and terrain field must match")
		var rows: Array[Dictionary] = []
		var scale: float = float(stage["logic_scale"])
		var offset: Array = stage["logic_offset"]
		for layer: Dictionary in source["layers"]:
			if int(layer["index"]) != int(stage["layer_index"]):
				continue
			for wall: Dictionary in layer["walls"]:
				rows.append({"id": wall["id"], "object_id": wall["object_id"],
					"a": [float(wall["a"][0]) * scale + float(offset[0]), float(wall["a"][1]) * scale + float(offset[1])],
					"b": [float(wall["b"][0]) * scale + float(offset[0]), float(wall["b"][1]) * scale + float(offset[1])]})
		assert(rows.size() == int(stage["wall_segment_count"]), "Stage wall count must match its source layer")
		_wall_geometry[id] = rows


static func camera_center(point: Vector2, view_size: Vector2 = MAX_VIEW_SIZE) -> Vector2:
	var half: Vector2 = _safe_view_size(view_size) * 0.5
	var bounds: Rect2 = art_rect()
	var target: Vector2 = point if point.is_finite() else WORLD_BOUNDS.get_center()
	return Vector2(clampf(target.x, bounds.position.x + half.x, bounds.end.x - half.x), clampf(target.y, bounds.position.y + half.y, bounds.end.y - half.y))


static func visible_rect(point: Vector2, view_size: Vector2 = MAX_VIEW_SIZE) -> Rect2:
	var size: Vector2 = _safe_view_size(view_size)
	return Rect2(camera_center(point, size) - size * 0.5, size)

static func camera_center_for(id: String, point: Vector2, view_size: Vector2 = MAX_VIEW_SIZE) -> Vector2:
	if not is_source_stage(id):
		return camera_center(point, view_size)
	var play: Rect2 = play_bounds(id)
	var size: Vector2 = _safe_view_size(view_size)
	var half: Vector2 = size * 0.5
	var frame: Rect2 = play.grow_individual(ART_MARGIN_LEFT, ART_MARGIN_TOP, ART_MARGIN_RIGHT, ART_MARGIN_BOTTOM)
	var target: Vector2 = point if point.is_finite() else play.get_center()
	return Vector2(play.get_center().x if frame.size.x <= size.x else clampf(target.x, frame.position.x + half.x, frame.end.x - half.x),
		play.get_center().y if frame.size.y <= size.y else clampf(target.y, frame.position.y + half.y, frame.end.y - half.y))

static func visible_rect_for(id: String, point: Vector2, view_size: Vector2 = MAX_VIEW_SIZE) -> Rect2:
	var size: Vector2 = _safe_view_size(view_size)
	return Rect2(camera_center_for(id, point, size) - size * 0.5, size)


static func _safe_view_size(value: Vector2) -> Vector2:
	if not value.is_finite() or value.x <= 0.0 or value.y <= 0.0:
		return MAX_VIEW_SIZE
	return Vector2(minf(value.x, MAX_VIEW_SIZE.x), minf(value.y, MAX_VIEW_SIZE.y))


static func movement_multiplier(id: String, point: Vector2) -> float:
	# The original arena skips every zone query, retaining its old arithmetic/RNG.
	if id == IDS[0] or not IDS.has(id) or not point.is_finite():
		return 1.0
	_ensure_loaded()
	var terrain: TerrainIndex = _terrain_indices[id]
	return terrain.multiplier if terrain.contains(point) else 1.0


static func terrain_name(id: String, point: Vector2) -> String:
	if id == IDS[0] or not IDS.has(id) or not point.is_finite():
		return ""
	_ensure_loaded()
	var terrain: TerrainIndex = _terrain_indices[id]
	return terrain.terrain_name if terrain.contains(point) else ""


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if parsed is Array:
		for item: Dictionary in parsed:
			_definitions[str(item["id"])] = item
	# Missing exported configuration is a build error, rather than an invisible
	# switch to a different arena or movement rule.
	assert(_definitions.size() == IDS.size(), "The arena catalog must contain every registered authored map")
	for id: String in IDS:
		assert(_definitions.has(id), "Missing arena: " + id)
		_terrain_indices[id] = TerrainIndex.new(_definitions[id])
