class_name ArenaObstacles
extends RefCounted
## Deterministic circular ground collision and cached routes; flying attacks ignore it.

const SKIN: float = 0.05
const ROUTE_CLEARANCE: float = 8.0
const ROUTE_SIDES: int = 8
const MAX_SLIDES: int = 3
const MAX_OBSTACLES: int = 32
const INDEX_CELL: float = 128.0
const INDEX_BODY_RADIUS: float = 64.0
const SEGMENT_CACHE_LIMIT: int = 4096

class ProjectedGoal:
	var source: Vector2 = Vector2.INF
	var position: Vector2 = Vector2.ZERO
	var cell: Vector2i = Vector2i.ZERO
	var open_sources: Dictionary = {}

var bounds: Rect2 = ArenaCatalog.WORLD_BOUNDS
var _items: Array[Dictionary] = []
var _centers: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat64Array = PackedFloat64Array()
var _all_ids: PackedInt32Array = PackedInt32Array()
var _empty_ids: PackedInt32Array = PackedInt32Array()
var _cells: Dictionary = {}
var _segment_cells: Dictionary = {}
var _projected_goals: Dictionary = {}
var _graphs: Dictionary = {}
var _routes: Dictionary = {}


func _init(rows: Array = []) -> void:
	configure(rows)


func configure(rows: Array) -> void:
	_items.clear()
	_centers.clear()
	_radii.clear()
	_all_ids.clear()
	_empty_ids = PackedInt32Array()
	_cells.clear()
	_segment_cells.clear()
	_projected_goals.clear()
	_graphs.clear()
	_routes.clear()
	for value: Variant in rows:
		if _items.size() >= MAX_OBSTACLES:
			break
		if not value is Dictionary:
			continue
		var center: Vector2 = _read_point(value.get("center"))
		var radius_value: Variant = value.get("radius", 0.0)
		if not (radius_value is float or radius_value is int):
			continue
		var radius: float = float(radius_value)
		if not center.is_finite() or not is_finite(radius) or radius <= 0.0 or radius > 256.0:
			continue
		if not bounds.encloses(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)):
			continue
		_items.append({"id": str(value.get("id", "obstacle_%d" % _items.size())),
			"center": center, "radius": radius, "art_id": str(value.get("art_id", "monument"))})
		var index: int = _centers.size()
		_centers.append(center)
		_radii.append(radius)
		_all_ids.append(index)
		var extent: Vector2 = Vector2.ONE * (radius + INDEX_BODY_RADIUS + SKIN)
		var first: Vector2i = _cell(center - extent)
		var last: Vector2i = _cell(center + extent)
		for x: int in range(first.x, last.x + 1):
			for y: int in range(first.y, last.y + 1):
				var key := Vector2i(x, y)
				var bucket: PackedInt32Array = _cells[key] if _cells.has(key) else PackedInt32Array()
				bucket.append(index)
				_cells[key] = bucket


static func _read_point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.INF


func snapshot() -> Array[Dictionary]:
	return _items.duplicate(true)


static func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / INDEX_CELL), floori(point.y / INDEX_CELL))


func _point_candidates(point: Vector2, body_radius: float) -> PackedInt32Array:
	return _cells.get(Vector2i((point / INDEX_CELL).floor()), _empty_ids) if body_radius <= INDEX_BODY_RADIUS else _all_ids


func _segment_candidates(start: Vector2, end: Vector2, body_radius: float) -> PackedInt32Array:
	if body_radius <= INDEX_BODY_RADIUS:
		var first := Vector2i((start / INDEX_CELL).floor())
		var last := Vector2i((end / INDEX_CELL).floor())
		if first == last:
			return _cells.get(first, _empty_ids)
		var key := Vector4i(first.x, first.y, last.x, last.y)
		if _segment_cells.has(key):
			return _segment_cells[key]
		var low: Vector2 = Vector2(first.min(last)) * INDEX_CELL
		var high: Vector2 = Vector2(first.max(last) + Vector2i.ONE) * INDEX_CELL
		var candidates := PackedInt32Array()
		for index: int in _all_ids:
			var center: Vector2 = _centers[index]
			var radius: float = _radii[index] + INDEX_BODY_RADIUS + SKIN
			if center.x >= low.x - radius and center.x <= high.x + radius and center.y >= low.y - radius and center.y <= high.y + radius:
				candidates.append(index)
		if _segment_cells.size() >= SEGMENT_CACHE_LIMIT:
			_segment_cells.clear()
		_segment_cells[key] = candidates
		return candidates
	return _all_ids


func is_free(point: Vector2, body_radius: float = 0.0, inset: float = 0.0) -> bool:
	if not point.is_finite() or not is_finite(body_radius) or body_radius < 0.0:
		return false
	var area: Rect2 = bounds.grow(-maxf(0.0, inset))
	if point.x < area.position.x or point.y < area.position.y or point.x > area.end.x or point.y > area.end.y:
		return false
	for index: int in _point_candidates(point, body_radius):
		var clearance: float = _radii[index] + body_radius
		var offset: Vector2 = point - _centers[index]
		if absf(offset.x) < clearance and absf(offset.y) < clearance and offset.length_squared() < clearance * clearance - 0.0001:
			return false
	return true


func _clamp(point: Vector2, inset: float) -> Vector2:
	var area: Rect2 = bounds if inset <= 0.0 else bounds.grow(-inset)
	var safe: Vector2 = point if point.is_finite() else area.get_center()
	return Vector2(clampf(safe.x, area.position.x, area.end.x), clampf(safe.y, area.position.y, area.end.y))


func free_point(point: Vector2, body_radius: float = 0.0, inset: float = 0.0) -> Vector2:
	var result: Vector2 = _clamp(point, inset)
	var radius: float = maxf(0.0, body_radius) if is_finite(body_radius) else 0.0
	if _centers.is_empty():
		return result
	var candidates: PackedInt32Array = _point_candidates(result, radius)
	for iteration: int in _centers.size() + 1:
		if candidates.is_empty():
			return result
		var changed: bool = false
		for index: int in candidates:
			var center: Vector2 = _centers[index]
			var clearance: float = _radii[index] + radius
			var offset: Vector2 = result - center
			var threshold: float = clearance + SKIN * 0.5
			if absf(offset.x) >= threshold or absf(offset.y) >= threshold or offset.length_squared() >= threshold * threshold:
				continue
			var direction: Vector2 = offset.normalized() if offset.length_squared() > 0.000001 else Vector2.RIGHT
			result = _clamp(center + direction * (clearance + SKIN), inset)
			changed = true
		if not changed:
			break
		candidates = _point_candidates(result, radius)
	return result


static func _entry_t(start: Vector2, movement: Vector2, center: Vector2, radius: float) -> float:
	var offset: Vector2 = start - center
	var outside: float = offset.length_squared() - radius * radius
	var projection: float = offset.dot(movement)
	if outside <= 0.0001:
		return 0.0 if projection < -0.0001 else INF
	var squared: float = movement.length_squared()
	if squared <= 0.000001 or projection >= 0.0:
		return INF
	var discriminant: float = projection * projection - squared * outside
	if discriminant < 0.0:
		return INF
	var entry: float = (-projection - sqrt(discriminant)) / squared
	return entry if entry >= 0.0 and entry <= 1.0 else INF


func move_body(start: Vector2, movement: Vector2, body_radius: float, inset: float = 0.0, slide: bool = true) -> Vector2:
	var area: Rect2 = bounds if inset <= 0.0 else bounds.grow(-inset)
	var position: Vector2 = start if start.is_finite() else area.get_center()
	if not area.has_point(position):
		position = Vector2(clampf(position.x, area.position.x, area.end.x), clampf(position.y, area.position.y, area.end.y))
	if not movement.is_finite():
		return free_point(position, body_radius, inset)
	var proposed: Vector2 = position + movement
	if not area.has_point(proposed):
		proposed = Vector2(clampf(proposed.x, area.position.x, area.end.x), clampf(proposed.y, area.position.y, area.end.y))
	if _centers.is_empty():
		return proposed
	var candidates: PackedInt32Array = _segment_candidates(position, proposed, body_radius)
	if candidates.is_empty():
		return proposed
	var adjusted: Vector2 = free_point(position, body_radius, inset)
	if adjusted != position:
		position = adjusted
		proposed = _clamp(position + movement, inset)
		candidates = _segment_candidates(position, proposed, body_radius)
	var remaining: Vector2 = proposed - position
	for iteration: int in MAX_SLIDES:
		if remaining.length_squared() <= 0.000001:
			break
		var nearest: float = INF
		var hit_center: Vector2 = Vector2.ZERO
		var end: Vector2 = position + remaining
		var low: Vector2 = position.min(end)
		var high: Vector2 = position.max(end)
		for index: int in candidates:
			var center: Vector2 = _centers[index]
			var radius: float = _radii[index] + body_radius
			if center.x < low.x - radius or center.x > high.x + radius or center.y < low.y - radius or center.y > high.y + radius:
				continue
			var entry: float = _entry_t(position, remaining, center, radius)
			if entry < nearest:
				nearest = entry
				hit_center = center
		if not is_finite(nearest):
			return end
		position += remaining * nearest
		var normal: Vector2 = (position - hit_center).normalized()
		position += normal * SKIN
		if not slide:
			break
		remaining *= 1.0 - nearest
		remaining -= normal * minf(0.0, remaining.dot(normal))
		var slide_end: Vector2 = position + remaining
		slide_end = Vector2(clampf(slide_end.x, area.position.x, area.end.x), clampf(slide_end.y, area.position.y, area.end.y))
		remaining = slide_end - position
		candidates = _segment_candidates(position, slide_end, body_radius)
	return free_point(position, body_radius, inset)


func segment_clear(start: Vector2, end: Vector2, body_radius: float = 0.0) -> bool:
	if not start.is_finite() or not end.is_finite() or not is_finite(body_radius) or body_radius < 0.0:
		return false
	if start.x < bounds.position.x or start.y < bounds.position.y or start.x > bounds.end.x or start.y > bounds.end.y \
		or end.x < bounds.position.x or end.y < bounds.position.y or end.x > bounds.end.x or end.y > bounds.end.y:
		return false
	if _centers.is_empty():
		return true
	return _clear_candidates(start, end, body_radius, _segment_candidates(start, end, body_radius))


func _clear_candidates(start: Vector2, end: Vector2, body_radius: float, candidates: PackedInt32Array) -> bool:
	if candidates.is_empty():
		return true
	var movement: Vector2 = end - start
	var low: Vector2 = start.min(end)
	var high: Vector2 = start.max(end)
	for index: int in candidates:
		var center: Vector2 = _centers[index]
		var radius: float = _radii[index] + body_radius
		if center.x < low.x - radius or center.x > high.x + radius or center.y < low.y - radius or center.y > high.y + radius:
			continue
		var squared_radius: float = radius * radius - 0.0001
		if start.distance_squared_to(center) < squared_radius or end.distance_squared_to(center) < squared_radius:
			return false
		if is_finite(_entry_t(start, movement, center, radius)):
			return false
	return true


func clear_routes() -> void:
	_routes.clear()


func forget_agent(agent_id: int) -> void:
	_routes.erase(agent_id)


func next_target(start: Vector2, target: Vector2, body_radius: float, agent_id: int) -> Vector2:
	var projection: ProjectedGoal = _projected_goals.get(body_radius) as ProjectedGoal
	if projection == null:
		projection = ProjectedGoal.new()
		projection.source = target
		projection.position = free_point(target, body_radius)
		projection.cell = Vector2i((projection.position / INDEX_CELL).floor())
		_projected_goals[body_radius] = projection
	if projection.source != target:
		projection.source = target
		projection.position = free_point(target, body_radius)
		var cell := Vector2i((projection.position / INDEX_CELL).floor())
		if cell != projection.cell:
			projection.cell = cell
			projection.open_sources.clear()
	var goal: Vector2 = projection.position
	var direct: bool = false
	if start.is_finite() and bounds.has_point(start):
		var source_cell := Vector2i((start / INDEX_CELL).floor())
		if projection.open_sources.has(source_cell):
			_routes.erase(agent_id)
			return goal
		var candidates: PackedInt32Array = _segment_candidates(start, goal, body_radius)
		if candidates.is_empty():
			direct = true
			if bounds.encloses(Rect2(Vector2(source_cell) * INDEX_CELL, Vector2.ONE * INDEX_CELL)):
				projection.open_sources[source_cell] = true
		else:
			direct = _clear_candidates(start, goal, body_radius, candidates)
	else:
		direct = segment_clear(start, goal, body_radius)
	if direct:
		_routes.erase(agent_id)
		return goal
	var route: Dictionary = _routes.get(agent_id, {})
	var path: PackedVector2Array = route.get("path", PackedVector2Array())
	var index: int = int(route.get("index", 0))
	var old_goal: Vector2 = route.get("goal", Vector2.INF)
	while index < path.size() and start.distance_squared_to(path[index]) <= 64.0:
		index += 1
	if index >= path.size() or old_goal.distance_squared_to(goal) > 48.0 * 48.0 or not segment_clear(start, path[index], body_radius):
		path = _build_route(start, goal, body_radius)
		index = 1 if path.size() > 1 else 0
		old_goal = goal
	_routes[agent_id] = {"path": path, "index": index, "goal": old_goal}
	return path[index] if index < path.size() else start


func _graph(body_radius: float) -> AStar2D:
	if _graphs.has(body_radius):
		return _graphs[body_radius] as AStar2D
	var graph := AStar2D.new()
	for item: Dictionary in _items:
		var center: Vector2 = item["center"]
		var radius: float = (float(item["radius"]) + body_radius + ROUTE_CLEARANCE) / cos(PI / float(ROUTE_SIDES))
		for index: int in ROUTE_SIDES:
			var point: Vector2 = center + Vector2.from_angle(TAU * float(index) / float(ROUTE_SIDES)) * radius
			if is_free(point, body_radius):
				graph.add_point(graph.get_point_count(), point)
	var ids: PackedInt64Array = graph.get_point_ids()
	for first: int in ids.size():
		for second: int in range(first + 1, ids.size()):
			if segment_clear(graph.get_point_position(ids[first]), graph.get_point_position(ids[second]), body_radius):
				graph.connect_points(ids[first], ids[second])
	_graphs[body_radius] = graph
	return graph


func _build_route(start: Vector2, goal: Vector2, body_radius: float) -> PackedVector2Array:
	var graph: AStar2D = _graph(body_radius)
	var ids: PackedInt64Array = graph.get_point_ids()
	var start_id: int = graph.get_point_count()
	var goal_id: int = start_id + 1
	graph.add_point(start_id, start)
	graph.add_point(goal_id, goal)
	for id: int in ids:
		var point: Vector2 = graph.get_point_position(id)
		if segment_clear(start, point, body_radius):
			graph.connect_points(start_id, id)
		if segment_clear(goal, point, body_radius):
			graph.connect_points(goal_id, id)
	var path: PackedVector2Array = graph.get_point_path(start_id, goal_id)
	graph.remove_point(goal_id)
	graph.remove_point(start_id)
	return path


func clear_spawn_segments(segments: Array[Rect2], body_radius: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for segment: Rect2 in segments:
		var length: float = segment.size.length()
		if length <= 0.0001:
			continue
		var direction: Vector2 = segment.size / length
		var intervals: Array[Vector2] = [Vector2(0.0, length)]
		for item: Dictionary in _items:
			var offset: Vector2 = (item["center"] as Vector2) - segment.position
			var along: float = offset.dot(direction)
			var perpendicular_squared: float = maxf(0.0, offset.length_squared() - along * along)
			var radius: float = float(item["radius"]) + body_radius + SKIN
			if perpendicular_squared >= radius * radius:
				continue
			var half_width: float = sqrt(radius * radius - perpendicular_squared)
			var low: float = along - half_width
			var high: float = along + half_width
			var retained: Array[Vector2] = []
			for interval: Vector2 in intervals:
				if high <= interval.x or low >= interval.y:
					retained.append(interval)
				else:
					if low > interval.x:
						retained.append(Vector2(interval.x, minf(low, interval.y)))
					if high < interval.y:
						retained.append(Vector2(maxf(high, interval.x), interval.y))
			intervals = retained
		for interval: Vector2 in intervals:
			if interval.y - interval.x > 0.0001:
				result.append(Rect2(segment.position + direction * interval.x, direction * (interval.y - interval.x)))
	return result
