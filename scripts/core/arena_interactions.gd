class_name ArenaInteractions
extends RefCounted
## Breakable scenery owns a separate random stream and leaves rewards for explicit collection.

const MAX_CRATES: int = 12
const MAX_PICKUPS: int = 24
const DROP_CHANCE: float = 0.60
const INDEX_CELL: float = 128.0
const INDEX_PADDING: float = 64.0
const REGION_CACHE_LIMIT: int = 1024

var _crates: Array[Dictionary] = []
var _crate_centers: PackedVector2Array = PackedVector2Array()
var _crate_radii: PackedFloat64Array = PackedFloat64Array()
var _crate_active: PackedByteArray = PackedByteArray()
var _crate_ids: PackedInt32Array = PackedInt32Array()
var _empty_ids: PackedInt32Array = PackedInt32Array()
var _crate_cells: Dictionary = {}
var _region_cache: Dictionary = {}
var _active_crates: int = 0
var _pickups: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _obstacles: ArenaObstacles
var _next_pickup_uid: int = 1
var _version: int = 0

func configure(arena: Dictionary, seed_value: int, wave: int, obstacles: ArenaObstacles) -> void:
	_crates.clear()
	_crate_centers.clear()
	_crate_radii.clear()
	_crate_active.clear()
	_crate_ids.clear()
	_empty_ids = PackedInt32Array()
	_crate_cells.clear()
	_region_cache.clear()
	_active_crates = 0
	_pickups.clear()
	_next_pickup_uid = 1
	_obstacles = obstacles
	_rng.seed = ("%d:%s:%d:environment" % [seed_value, str(arena.get("id", "reliquary")), wave]).hash()
	var authored_obstacles: Variant = arena.get("obstacles", [])
	var rows: Array = authored_obstacles.duplicate(true) if authored_obstacles is Array else []
	var authored_crates: Variant = arena.get("crates", [])
	var crate_rows: Array = authored_crates if authored_crates is Array else []
	var known_ids: Dictionary = {}
	var collider_ids: Dictionary = {}
	for row: Variant in rows:
		if row is Dictionary:
			collider_ids[str(row.get("id", ""))] = true
	for value: Variant in crate_rows:
		if _crates.size() >= MAX_CRATES or rows.size() >= ArenaObstacles.MAX_OBSTACLES:
			break
		if not value is Dictionary:
			continue
		var id: String = str(value.get("id", "crate_%d" % _crates.size()))
		var center: Vector2 = ArenaObstacles._read_point(value.get("center"))
		var radius_value: Variant = value.get("radius", 18.0)
		var health_value: Variant = value.get("max_health", 24.0)
		if not (radius_value is int or radius_value is float) or not (health_value is int or health_value is float):
			continue
		var radius: float = float(radius_value)
		var max_health: float = float(health_value)
		if id.is_empty() or known_ids.has(id) or collider_ids.has("crate:" + id) or not center.is_finite() or not is_finite(radius) or radius <= 0.0 or radius > 64.0 or not is_finite(max_health) or max_health <= 0.0:
			continue
		if not obstacles.bounds.encloses(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)):
			continue
		var art_id: String = str(value.get("art_id", "barrel"))
		if art_id not in ["barrel", "chest"]:
			continue
		known_ids[id] = true
		var index: int = _crates.size()
		_crates.append({"id": id, "uid": index + 1, "index": index, "position": center, "center": center,
			"radius": radius, "art_id": art_id, "health": max_health, "max_health": max_health, "active": true, "break_age": 0.0})
		_crate_centers.append(center)
		_crate_radii.append(radius)
		_crate_active.append(1)
		_crate_ids.append(index)
		_active_crates += 1
		var extent: Vector2 = Vector2.ONE * (radius + INDEX_PADDING)
		var first: Vector2i = _cell(center - extent)
		var last: Vector2i = _cell(center + extent)
		for x: int in range(first.x, last.x + 1):
			for y: int in range(first.y, last.y + 1):
				var key := Vector2i(x, y)
				var bucket: PackedInt32Array = _crate_cells.get(key, PackedInt32Array())
				bucket.append(index)
				_crate_cells[key] = bucket
		rows.append({"id": "crate:" + id, "center": center, "radius": radius, "art_id": art_id})
	_obstacles.configure(rows)
	_version += 1

func snapshot() -> Dictionary:
	return {"crates": _crates.duplicate(true), "pickups": _pickups.duplicate(true), "version": _version}

func damage_crate(index: int, amount: float) -> Dictionary:
	if index < 0 or index >= _crates.size() or not is_finite(amount) or amount <= 0.0:
		return {"hit": false, "broke": false, "drop": {}}
	var crate: Dictionary = _crates[index]
	if not bool(crate["active"]):
		return {"hit": false, "broke": false, "position": crate["position"], "id": crate["id"], "drop": {}}
	crate["health"] = maxf(0.0, float(crate["health"]) - amount)
	var broke: bool = float(crate["health"]) <= 0.0
	var drop: Dictionary = {}
	if broke:
		crate["active"] = false
		_crate_active[index] = 0
		_active_crates -= 1
		crate["break_age"] = 0.0
		_obstacles.set_active("crate:" + str(crate["id"]), false)
		drop = _roll_drop(crate["position"])
	_version += 1
	return {"hit": true, "broke": broke, "position": crate["position"], "id": crate["id"], "drop": drop.duplicate(true)}

func _roll_drop(position: Vector2) -> Dictionary:
	if _pickups.size() >= MAX_PICKUPS or _rng.randf() >= DROP_CHANCE:
		return {}
	var kind: String = ["gold", "health", "charge"][_rng.randi_range(0, 2)]
	var value: float = float(_rng.randi_range(1, 3)) if kind == "gold" else 8.0 if kind == "health" else 1.5
	var drop: Dictionary = {"uid": _next_pickup_uid, "kind": kind, "position": position, "value": value, "age": 0.0}
	_next_pickup_uid += 1
	_pickups.append(drop)
	return drop

func first_crate_hit(start: Vector2, end: Vector2, padding: float = 0.0) -> Dictionary:
	if _active_crates == 0 or not start.is_finite() or not end.is_finite() or not is_finite(padding) or padding < 0.0:
		return {}
	var movement: Vector2 = end - start
	if not movement.is_finite() or movement.length_squared() <= 0.000001:
		return {}
	var candidates: PackedInt32Array = _crate_ids if padding > INDEX_PADDING else _region_candidates(_cell(start), _cell(end))
	var nearest: float = INF
	var nearest_index: int = -1
	for index: int in candidates:
		if _crate_active[index] == 0:
			continue
		var entry: float = ArenaObstacles._entry_t(start, movement, _crate_centers[index], _crate_radii[index] + padding)
		if entry < nearest:
			nearest = entry
			nearest_index = index
	return {"index": nearest_index, "t": nearest, "position": start + movement * nearest} if nearest_index >= 0 else {}

func has_active_crates() -> bool:
	return _active_crates > 0

func damage_candidates(origin: Vector2, reach: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _active_crates == 0 or not origin.is_finite() or not is_finite(reach) or reach < 0.0:
		return result
	var candidates: PackedInt32Array = _crate_ids
	if reach <= INDEX_CELL * 8.0:
		var extent: Vector2 = Vector2.ONE * reach
		candidates = _region_candidates(_cell(origin - extent), _cell(origin + extent))
	for index: int in candidates:
		if _crate_active[index] == 0:
			continue
		var radius: float = reach + _crate_radii[index]
		if origin.distance_squared_to(_crate_centers[index]) <= radius * radius + 0.01:
			result.append({"index": index, "position": _crate_centers[index]})
	return result

static func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / INDEX_CELL), floori(point.y / INDEX_CELL))

func _region_candidates(first_cell: Vector2i, last_cell: Vector2i) -> PackedInt32Array:
	if first_cell == last_cell:
		return _crate_cells.get(first_cell, _empty_ids)
	var first: Vector2i = first_cell.min(last_cell)
	var last: Vector2i = first_cell.max(last_cell)
	var key := Vector4i(first.x, first.y, last.x, last.y)
	if _region_cache.has(key):
		return _region_cache[key]
	var low: Vector2 = Vector2(first) * INDEX_CELL
	var high: Vector2 = Vector2(last + Vector2i.ONE) * INDEX_CELL
	var candidates: PackedInt32Array = PackedInt32Array()
	for index: int in _crate_ids:
		var center: Vector2 = _crate_centers[index]
		var radius: float = _crate_radii[index] + INDEX_PADDING
		if center.x >= low.x - radius and center.x <= high.x + radius and center.y >= low.y - radius and center.y <= high.y + radius:
			candidates.append(index)
	if _region_cache.size() >= REGION_CACHE_LIMIT:
		_region_cache.clear()
	_region_cache[key] = candidates
	return candidates

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var changed: bool = false
	for crate: Dictionary in _crates:
		if not bool(crate["active"]):
			crate["break_age"] = float(crate["break_age"]) + delta
			changed = true
	for pickup: Dictionary in _pickups:
		pickup["age"] = float(pickup["age"]) + delta
		changed = true
	if changed:
		_version += 1

func pickup_candidates(player_position: Vector2, pickup_radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not player_position.is_finite() or not is_finite(pickup_radius) or pickup_radius < 0.0:
		return result
	for pickup: Dictionary in _pickups:
		if player_position.distance_squared_to(pickup["position"]) <= pickup_radius * pickup_radius:
			result.append(pickup.duplicate(true))
	return result

func consume_pickup(uid: int) -> bool:
	for index: int in _pickups.size():
		if int(_pickups[index]["uid"]) == uid:
			_pickups.remove_at(index)
			_version += 1
			return true
	return false
