class_name WorldMapCatalog
extends RefCounted
## Source-bound JP terrain layers share native artwork and geometry.

const SOURCE_PATH: String = "res://data/worldflipper/map_library.json"
const PAGE_SIZE: int = 6

static var _entries: Dictionary = {}
static var _geometries: Dictionary = {}
static var _groups: Array[Dictionary] = []
static var _ids: Array[String] = []
static var _loaded: bool = false


static func contains(id: String) -> bool:
	if not id.begins_with("wf_"):
		return false
	_ensure_loaded()
	return _entries.has(id) and bool(_entries[id].get("playable", false))


static func ids() -> Array[String]:
	_ensure_loaded()
	return _ids.duplicate()


static func groups() -> Array[Dictionary]:
	_ensure_loaded()
	return _groups.duplicate(true)


static func entry(id: String) -> Dictionary:
	_ensure_loaded()
	return (_entries.get(id, {}) as Dictionary).duplicate(true)


static func geometry(id: String) -> Dictionary:
	_ensure_loaded()
	if not contains(id):
		return {}
	return (_geometries[str(_entries[id]["geometry_ref"])] as Dictionary).duplicate(true)


static func group_ids(group: String) -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	for id: String in _ids:
		if str(_entries[id]["group"]) == group:
			result.append(id)
	return result


static func definition(id: String) -> Dictionary:
	var item: Dictionary = entry(id)
	if not contains(id):
		return {}
	return {"id": id, "name": item["name"], "texture": item["texture_path"],
		"preview_color": item.get("preview_color", "729799"), "terrain_name": "", "move_multiplier": 1.0,
		"legacy_zone_count": 0, "zones": [], "obstacles": [], "crates": [],
		"stage": item["stage"].duplicate(true)}


static func play_bounds(id: String) -> Rect2:
	_ensure_loaded()
	return _rect(_entries[id]["play_bounds"])


static func source_rect(id: String) -> Rect2:
	return _rect(entry(id)["source_rect"])


static func preview_texture(id: String) -> Texture2D:
	if not contains(id):
		return null
	var item: Dictionary = entry(id)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(str(item["texture_path"])) as Texture2D
	atlas.region = _rect(item["source_rect"])
	atlas.filter_clip = true
	return atlas


static func walls(id: String) -> Array[Dictionary]:
	var shape: Dictionary = geometry(id)
	var result: Array[Dictionary] = []
	if shape.is_empty():
		return result
	var item: Dictionary = entry(id)
	var scale: float = float(item["logic_scale"])
	var offset: Array = item["logic_offset"]
	for wall: Dictionary in shape["walls"]:
		result.append({"id": wall["id"], "object_id": wall["object_id"],
			"a": [float(wall["a"][0]) * scale + float(offset[0]), float(wall["a"][1]) * scale + float(offset[1])],
			"b": [float(wall["b"][0]) * scale + float(offset[0]), float(wall["b"][1]) * scale + float(offset[1])]})
	return result


static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	assert(parsed is Dictionary and int(parsed.get("schema_version", 0)) == 1, "Missing compiled JP map library")
	_geometries = parsed["geometries"]
	for row: Dictionary in parsed["entries"]:
		var id: String = str(row["id"])
		assert(not _entries.has(id), "Duplicate JP map layer: " + id)
		_entries[id] = row
		if bool(row.get("playable", false)):
			assert(_geometries.has(str(row["geometry_ref"])), "Map layer has no verified geometry: " + id)
			_ids.append(id)
	for row: Dictionary in parsed["groups"]:
		_groups.append(row.duplicate(true))
	_loaded = true
