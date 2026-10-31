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
const LOCAL_ROUTE_CANDIDATES: int = 16
const LOCAL_ROUTE_LINKS: int = 6
const ROUTE_QUERY_CACHE_LIMIT: int = 1024
const CURVE_CELL_SIZE: float = 64.0
const WALL_CORRIDOR_CELL_SIZE: float = 64.0
const MAX_CURVE_CELL_COORDINATE: float = 2147483000.0

class ProjectedGoal:
	var source: Vector2 = Vector2.INF
	var position: Vector2 = Vector2.ZERO
	var cell: Vector2i = Vector2i.ZERO
	var open_sources: Dictionary = {}
	var checked_corridors: Dictionary = {}

class NavigationRoute:
	var path: PackedVector2Array = PackedVector2Array()
	var index: int = 0
	var goal: Vector2 = Vector2.INF
	var start: Vector2 = Vector2.INF
	var radius: float = -1.0
	var bounds: Rect2 = Rect2()
	var unreachable: bool = false
	var wall_hint: int = -1

class CombinedCurves:
	var area: Rect2 = Rect2()
	var curves: Array[Dictionary] = []
	var low_x: PackedFloat64Array = PackedFloat64Array()
	var low_y: PackedFloat64Array = PackedFloat64Array()
	var high_x: PackedFloat64Array = PackedFloat64Array()
	var high_y: PackedFloat64Array = PackedFloat64Array()
	var intersections: Array[Array] = []
	var cells: Dictionary = {}
	var cell_queries: Dictionary = {}
	var indices: PackedInt32Array = PackedInt32Array()
	var full_order: bool = false
	var query_results: Dictionary = {}
	var known_free_points: Dictionary = {}

class SafeMoveCells:
	var area: Rect2 = Rect2()
	var proofs: Dictionary = {}

class ClosedBarrier:
	var x: PackedFloat64Array = PackedFloat64Array()
	var y: PackedFloat64Array = PackedFloat64Array()
	var minimum_x: float = INF
	var minimum_y: float = INF
	var maximum_x: float = -INF
	var maximum_y: float = -INF

class GoalCellProofs:
	var area: Rect2 = Rect2()
	var cells: Dictionary = {}

class StartVisibilityLinks:
	var tested: PackedInt64Array = PackedInt64Array()
	var local_ids: PackedInt64Array = PackedInt64Array()
	var fallback_ids: PackedInt64Array = PackedInt64Array()
	var has_fallback: bool = false

class GraphVisibilityCache:
	var area: Rect2 = Rect2()
	var goals: Dictionary = {}
	var starts: Dictionary = {}

var bounds: Rect2 = ArenaCatalog.WORLD_BOUNDS
var walls: TerrainWalls = TerrainWalls.new()
var _wall_rows: Array[Dictionary] = []
var _items: Array[Dictionary] = []
var _centers: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat64Array = PackedFloat64Array()
var _all_ids: PackedInt32Array = PackedInt32Array()
var _active: PackedByteArray = PackedByteArray()
var _indices_by_id: Dictionary = {}
var _empty_ids: PackedInt32Array = PackedInt32Array()
var _cells: Dictionary = {}
var _segment_cells: Dictionary = {}
var _projected_goals: Dictionary = {}
var _graphs: Dictionary = {}
var _graph_point_ids: Dictionary = {}
var _graph_goals: Dictionary = {}
var _routes: Dictionary = {}
var _route_queries: Dictionary = {}
var _wall_curve_cache: Dictionary = {}
var _combined_curve_cache: Dictionary = {}
var _navigation_bounds: Rect2 = ArenaCatalog.WORLD_BOUNDS
var _safe_move_cells: Dictionary = {}
var _closed_barrier_cache: Dictionary = {}
var _goal_cell_proofs: Dictionary = {}
var _graph_visibility: Dictionary = {}
var _navigation_graphs_built: int = 0
var _navigation_graph_checks: int = 0
var _navigation_route_builds: int = 0
var _navigation_goal_refreshes: int = 0
var _navigation_goal_checks: int = 0
var _navigation_start_checks: int = 0
var _navigation_fallbacks: int = 0
var _navigation_tail_retargets: int = 0
var _navigation_query_cache_hits: int = 0
var _navigation_unreachable_cache_hits: int = 0
var _combined_curve_builds: int = 0
var _combined_intersections_solved: int = 0
var _combined_projection_tests: int = 0
var _combined_query_hits: int = 0
var _combined_queries_solved: int = 0
var _known_free_hits: int = 0
var _known_free_points_recorded: int = 0
var _safe_cell_move_hits: int = 0
var _safe_cell_proofs_checked: int = 0
var _proven_sweep_move_hits: int = 0
var _barrier_route_rejections: int = 0
var _goal_cell_proof_hits: int = 0
var _wall_hint_hits: int = 0
var _goal_cell_proofs_checked: int = 0
var _visible_goal_cache_hits: int = 0
var _start_link_cache_hits: int = 0


func _init(rows: Array = []) -> void:
	configure(rows)


func configure(rows: Array) -> void:
	walls.clear()
	_wall_rows.clear()
	_items.clear()
	_centers.clear()
	_radii.clear()
	_all_ids.clear()
	_active.clear()
	_indices_by_id.clear()
	_empty_ids = PackedInt32Array()
	_cells.clear()
	_segment_cells.clear()
	_projected_goals.clear()
	_graphs.clear()
	_graph_point_ids.clear()
	_graph_goals.clear()
	_routes.clear()
	_route_queries.clear()
	_wall_curve_cache.clear()
	_combined_curve_cache.clear()
	_safe_move_cells.clear()
	_closed_barrier_cache.clear()
	_goal_cell_proofs.clear()
	_graph_visibility.clear()
	_navigation_bounds = bounds
	reset_navigation_stats()
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
		var id: String = str(value.get("id", "obstacle_%d" % _items.size()))
		if _indices_by_id.has(id):
			continue
		_indices_by_id[id] = _items.size()
		_items.append({"id": id,
			"center": center, "radius": radius, "art_id": str(value.get("art_id", "monument"))})
		var index: int = _centers.size()
		_centers.append(center)
		_radii.append(radius)
		_all_ids.append(index)
		_active.append(1)
		var extent: Vector2 = Vector2.ONE * (radius + INDEX_BODY_RADIUS + SKIN)
		var first: Vector2i = _cell(center - extent)
		var last: Vector2i = _cell(center + extent)
		for x: int in range(first.x, last.x + 1):
			for y: int in range(first.y, last.y + 1):
				var key := Vector2i(x, y)
				var bucket: PackedInt32Array = _cells[key] if _cells.has(key) else PackedInt32Array()
				bucket.append(index)
				_cells[key] = bucket


func configure_walls(rows: Array) -> bool:
	if not walls.configure(rows):
		return false
	_wall_rows = walls.snapshot()
	_projected_goals.clear()
	_graphs.clear()
	_graph_point_ids.clear()
	_graph_goals.clear()
	_routes.clear()
	_route_queries.clear()
	_wall_curve_cache.clear()
	_combined_curve_cache.clear()
	_safe_move_cells.clear()
	_closed_barrier_cache.clear()
	_goal_cell_proofs.clear()
	_graph_visibility.clear()
	return true


static func _read_point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.INF


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in _items.size():
		if _active[index] != 0:
			result.append(_items[index].duplicate(true))
	return result


func set_active(id: String, active: bool) -> bool:
	if not _indices_by_id.has(id):
		return false
	var index: int = int(_indices_by_id[id])
	if bool(_active[index]) == active:
		return true
	_active[index] = 1 if active else 0
	_graphs.clear()
	_graph_point_ids.clear()
	_graph_goals.clear()
	_routes.clear()
	_route_queries.clear()
	_combined_curve_cache.clear()
	_safe_move_cells.clear()
	_closed_barrier_cache.clear()
	_goal_cell_proofs.clear()
	_graph_visibility.clear()
	for projection: ProjectedGoal in _projected_goals.values():
		projection.open_sources.clear()
	_projected_goals.clear()
	return true


static func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / INDEX_CELL), floori(point.y / INDEX_CELL))


func _point_candidates(point: Vector2, body_radius: float) -> PackedInt32Array:
	if _centers.is_empty():
		return _empty_ids
	return _cells.get(Vector2i((point / INDEX_CELL).floor()), _empty_ids) if body_radius <= INDEX_BODY_RADIUS else _all_ids


func _segment_candidates(start: Vector2, end: Vector2, body_radius: float) -> PackedInt32Array:
	if _centers.is_empty():
		return _empty_ids
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
	if not _wall_rows.is_empty() and not walls.is_free(point, body_radius):
		return false
	if _centers.is_empty():
		return true
	for index: int in _point_candidates(point, body_radius):
		if _active[index] == 0:
			continue
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
	if not _wall_rows.is_empty():
		return _free_combined(point, body_radius, inset)
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
			if _active[index] == 0:
				continue
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


func first_hit(start: Vector2, movement: Vector2, body_radius: float, inset: float = 0.0, filter_prefix: String = "", include_bounds: bool = true) -> Dictionary:
	if not start.is_finite() or not movement.is_finite() or not is_finite(body_radius) or body_radius < 0.0 or not is_finite(inset):
		return {}
	var area: Rect2 = bounds.grow(-maxf(0.0, inset))
	if area.size.x <= 0.0 or area.size.y <= 0.0 or movement.length_squared() <= 0.000001:
		return {}
	var result: Dictionary = _boundary_hit(start, movement, area) if include_bounds else {}
	var nearest: float = float(result.get("t", INF))
	for index: int in _segment_candidates(start, start + movement, body_radius):
		if _active[index] == 0:
			continue
		if not filter_prefix.is_empty() and not str(_items[index]["id"]).begins_with(filter_prefix):
			continue
		var center: Vector2 = _centers[index]
		var entry: float = _entry_t(start, movement, center, _radii[index] + body_radius)
		if not is_finite(entry) or entry >= nearest:
			continue
		var normal: Vector2 = start + movement * entry - center
		normal = normal.normalized() if not normal.is_zero_approx() else -movement.normalized()
		result = {"t": entry, "normal": normal, "id": _items[index]["id"], "center": center,
			"art_id": _items[index]["art_id"], "index": index}
		nearest = entry
	if not _wall_rows.is_empty() and (filter_prefix.is_empty() or "wall:".begins_with(filter_prefix)):
		var wall: Dictionary = walls.first_hit(start, start + movement, body_radius)
		if not wall.is_empty() and float(wall["t"]) < nearest:
			wall["source_id"] = wall["id"]
			wall["id"] = "wall:" + str(wall["id"])
			wall["center"] = wall["wall_point"]
			wall["art_id"] = "wall"
			wall["index"] = -1
			result = wall
	return result


static func _boundary_hit(start: Vector2, movement: Vector2, area: Rect2) -> Dictionary:
	var nearest: float = INF
	var normal: Vector2 = Vector2.ZERO
	for axis: int in 2:
		var speed: float = movement[axis]
		if is_zero_approx(speed):
			continue
		var edge: float = area.end[axis] if speed > 0.0 else area.position[axis]
		var entry: float = (edge - start[axis]) / speed
		var outward: bool = start[axis] >= edge if speed > 0.0 else start[axis] <= edge
		if outward:
			entry = 0.0
		if entry < 0.0 or entry > 1.0:
			continue
		var candidate_normal: Vector2 = Vector2.ZERO
		candidate_normal[axis] = -1.0 if speed > 0.0 else 1.0
		if absf(entry - nearest) < 0.000001:
			normal += candidate_normal
		elif entry < nearest:
			nearest = entry
			normal = candidate_normal
	if not is_finite(nearest):
		return {}
	return {"t": nearest, "normal": normal.normalized(), "id": "boundary", "center": start + movement * nearest,
		"art_id": "wall", "index": -1}


func move_body(start: Vector2, movement: Vector2, body_radius: float, inset: float = 0.0, slide: bool = true) -> Vector2:
	if not _wall_rows.is_empty():
		if _safe_cell_movement(start, movement, body_radius, inset):
			_safe_cell_move_hits += 1
			return start + movement
		if _centers.is_empty() and _proven_wall_movement(start, movement, body_radius, inset):
			_proven_sweep_move_hits += 1
			return start if movement.length_squared() <= 0.000001 else start + movement
		return _move_combined(start, movement, body_radius, inset, slide)
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
			if _active[index] == 0:
				continue
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
		return walls.navigation_clear(start, end, body_radius) if not _wall_rows.is_empty() else true
	return _clear_candidates(start, end, body_radius, _segment_candidates(start, end, body_radius))


func _clear_candidates(start: Vector2, end: Vector2, body_radius: float, candidates: PackedInt32Array) -> bool:
	if not _wall_rows.is_empty() and not walls.navigation_clear(start, end, body_radius):
		return false
	if candidates.is_empty():
		return true
	var movement: Vector2 = end - start
	var low: Vector2 = start.min(end)
	var high: Vector2 = start.max(end)
	for index: int in candidates:
		if _active[index] == 0:
			continue
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
	_route_queries.clear()


func forget_agent(agent_id: int) -> void:
	_routes.erase(agent_id)


func navigation_stats() -> Dictionary:
	return {"graphs_built": _navigation_graphs_built, "graph_visibility_checks": _navigation_graph_checks,
		"route_builds": _navigation_route_builds, "goal_refreshes": _navigation_goal_refreshes,
		"goal_visibility_checks": _navigation_goal_checks, "start_visibility_checks": _navigation_start_checks,
		"full_scan_fallbacks": _navigation_fallbacks, "tail_retargets": _navigation_tail_retargets,
		"query_cache_hits": _navigation_query_cache_hits, "unreachable_cache_hits": _navigation_unreachable_cache_hits,
		"combined_curve_builds": _combined_curve_builds, "combined_intersections_solved": _combined_intersections_solved,
		"combined_projection_tests": _combined_projection_tests, "combined_query_hits": _combined_query_hits,
		"combined_queries_solved": _combined_queries_solved, "known_free_hits": _known_free_hits,
		"known_free_points_recorded": _known_free_points_recorded, "safe_cell_move_hits": _safe_cell_move_hits,
		"safe_cell_proofs_checked": _safe_cell_proofs_checked, "proven_sweep_move_hits": _proven_sweep_move_hits,
		"barrier_route_rejections": _barrier_route_rejections, "goal_cell_proof_hits": _goal_cell_proof_hits, "wall_hint_hits": _wall_hint_hits,
		"goal_cell_proofs_checked": _goal_cell_proofs_checked,
		"visible_goal_cache_hits": _visible_goal_cache_hits, "start_link_cache_hits": _start_link_cache_hits}


func reset_navigation_stats() -> void:
	_navigation_graphs_built = 0
	_navigation_graph_checks = 0
	_navigation_route_builds = 0
	_navigation_goal_refreshes = 0
	_navigation_goal_checks = 0
	_navigation_start_checks = 0
	_navigation_fallbacks = 0
	_navigation_tail_retargets = 0
	_navigation_query_cache_hits = 0
	_navigation_unreachable_cache_hits = 0
	_visible_goal_cache_hits = 0
	_start_link_cache_hits = 0
	_combined_curve_builds = 0
	_combined_intersections_solved = 0
	_combined_projection_tests = 0
	_combined_query_hits = 0
	_combined_queries_solved = 0
	_known_free_hits = 0
	_known_free_points_recorded = 0
	_safe_cell_move_hits = 0
	_safe_cell_proofs_checked = 0
	_proven_sweep_move_hits = 0
	_barrier_route_rejections = 0
	_goal_cell_proof_hits = 0
	_wall_hint_hits = 0
	_goal_cell_proofs_checked = 0


func next_target(start: Vector2, target: Vector2, body_radius: float, agent_id: int) -> Vector2:
	_sync_navigation_bounds()
	var corridor_size: float = WALL_CORRIDOR_CELL_SIZE if not _wall_rows.is_empty() else INDEX_CELL
	var projection: ProjectedGoal = _projected_goals.get(body_radius) as ProjectedGoal
	if projection == null:
		projection = ProjectedGoal.new()
		projection.source = target
		projection.position = free_point(target, body_radius)
		projection.cell = Vector2i((projection.position / corridor_size).floor())
		_projected_goals[body_radius] = projection
	if projection.source != target:
		projection.source = target
		projection.position = free_point(target, body_radius)
		var cell := Vector2i((projection.position / corridor_size).floor())
		if cell != projection.cell:
			projection.cell = cell
			projection.open_sources.clear()
			projection.checked_corridors.clear()
	var goal: Vector2 = projection.position
	var route: NavigationRoute = _routes.get(agent_id) as NavigationRoute
	if not _wall_rows.is_empty() and route != null and route.unreachable and route.start == start \
		and route.goal == goal and route.radius == body_radius and route.bounds == bounds:
		_navigation_unreachable_cache_hits += 1
		return start
	var direct: bool = false
	var wall_hint: int = route.wall_hint if route != null else -1
	if not _wall_rows.is_empty():
		if start.is_finite() and bounds.has_point(start):
			var source_cell := Vector2i((start / WALL_CORRIDOR_CELL_SIZE).floor())
			if projection.open_sources.has(source_cell):
				_routes.erase(agent_id)
				return goal
			if not projection.checked_corridors.has(source_cell):
				projection.checked_corridors[source_cell] = true
				if _cell_corridor_clear(source_cell, projection.cell, body_radius, _segment_candidates(start, goal, body_radius)):
					projection.open_sources[source_cell] = true
					_routes.erase(agent_id)
					return goal
		if wall_hint >= 0 and walls.rejects_sweep(wall_hint, start, goal, body_radius):
			direct = false
			_wall_hint_hits += 1
		else:
			direct = segment_clear(start, goal, body_radius)
			wall_hint = walls.last_navigation_blocker if not direct else -1
	elif start.is_finite() and bounds.has_point(start):
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
			if not projection.checked_corridors.has(source_cell):
				projection.checked_corridors[source_cell] = true
				if _cell_corridor_clear(source_cell, projection.cell, body_radius, candidates):
					projection.open_sources[source_cell] = true
					_routes.erase(agent_id)
					return goal
			direct = _clear_candidates(start, goal, body_radius, candidates)
	else:
		direct = segment_clear(start, goal, body_radius)
	if direct:
		_routes.erase(agent_id)
		return goal
	if route == null:
		route = NavigationRoute.new()
		_routes[agent_id] = route
	route.wall_hint = wall_hint
	var path: PackedVector2Array = route.path
	var index: int = route.index
	var old_goal: Vector2 = route.goal
	while index < path.size() and start.distance_squared_to(path[index]) <= 64.0:
		index += 1
	var rebuild: bool = index >= path.size()
	if not rebuild:
		rebuild = not segment_clear(start, path[index], body_radius)
	if not rebuild and old_goal.distance_squared_to(goal) > 48.0 * 48.0:
		var next: Vector2 = goal if index == path.size() - 1 else path[index]
		if path.size() >= 2 and segment_clear(start, next, body_radius) and segment_clear(path[path.size() - 2], goal, body_radius):
			path[path.size() - 1] = goal
			old_goal = goal
			_navigation_tail_retargets += 1
		else:
			rebuild = true
	if rebuild:
		if _closed_barrier_separates(start, goal, body_radius):
			path = PackedVector2Array()
			_barrier_route_rejections += 1
		else:
			path = _build_route(start, goal, body_radius)
		index = 1 if path.size() > 1 else 0
		old_goal = goal
	route.path = path
	route.index = index
	route.goal = old_goal
	route.start = start
	route.radius = body_radius
	route.bounds = bounds
	route.unreachable = path.is_empty()
	return path[index] if index < path.size() else start


func _sync_navigation_bounds() -> void:
	if _navigation_bounds == bounds:
		return
	_navigation_bounds = bounds
	_projected_goals.clear()
	_graphs.clear()
	_graph_point_ids.clear()
	_graph_goals.clear()
	_routes.clear()
	_route_queries.clear()
	_closed_barrier_cache.clear()
	_goal_cell_proofs.clear()
	_graph_visibility.clear()


func _cell_corridor_clear(source: Vector2i, target: Vector2i, body_radius: float, candidates: PackedInt32Array) -> bool:
	var cell_size: float = WALL_CORRIDOR_CELL_SIZE if not _wall_rows.is_empty() else INDEX_CELL
	var first := Rect2(Vector2(source) * cell_size, Vector2.ONE * cell_size)
	var last := Rect2(Vector2(target) * cell_size, Vector2.ONE * cell_size)
	if not bounds.encloses(first) or not bounds.encloses(last):
		return false
	var corners := PackedVector2Array()
	for area: Rect2 in [first, last]:
		corners.append(area.position)
		corners.append(Vector2(area.end.x, area.position.y))
		corners.append(area.end)
		corners.append(Vector2(area.position.x, area.end.y))
	var corridor: PackedVector2Array = Geometry2D.convex_hull(corners)
	if not _wall_rows.is_empty():
		var clearance: float = body_radius + SKIN
		for point: Vector2 in corridor:
			if not walls.is_free(point, clearance):
				return false
		for edge: int in corridor.size():
			if not walls.segment_clear(corridor[edge], corridor[(edge + 1) % corridor.size()], clearance):
				return false
		# Clear polygon edges cannot detect a complete wall capsule enclosed by it.
		for wall: Dictionary in _wall_rows:
			if Geometry2D.is_point_in_polygon(_read_point(wall["a"]), corridor) or Geometry2D.is_point_in_polygon(_read_point(wall["b"]), corridor):
				return false
	for index: int in candidates:
		if _active[index] == 0:
			continue
		var center: Vector2 = _centers[index]
		var radius_squared: float = pow(_radii[index] + body_radius + SKIN, 2)
		if Geometry2D.is_point_in_polygon(center, corridor):
			return false
		for edge_index: int in corridor.size():
			var start: Vector2 = corridor[edge_index]
			var edge: Vector2 = corridor[(edge_index + 1) % corridor.size()] - start
			var fraction: float = clampf((center - start).dot(edge) / edge.length_squared(), 0.0, 1.0) if not edge.is_zero_approx() else 0.0
			if center.distance_squared_to(start + edge * fraction) < radius_squared:
				return false
	return true


func _closed_barriers(radius: float) -> Array[ClosedBarrier]:
	if _closed_barrier_cache.has(radius):
		return _closed_barrier_cache[radius] as Array[ClosedBarrier]
	var result: Array[ClosedBarrier] = []
	var groups: Dictionary = {}
	for wall: Dictionary in _wall_rows:
		var parts: PackedStringArray = str(wall["id"]).split(":")
		if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
			continue
		if int(parts[0]) < 0 or int(parts[1]) < 0 or int(parts[2]) < 0:
			continue
		var key: String = parts[0] + ":" + parts[1]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(wall)
	for rows: Array in groups.values():
		if rows.size() < 3:
			continue
		var barrier := ClosedBarrier.new()
		var valid: bool = true
		var magnitude: float = 0.0
		for index: int in rows.size():
			var wall: Dictionary = rows[index]
			if int(str(wall["id"]).get_slice(":", 2)) != index:
				valid = false
				break
			var a: Array = wall["a"]
			var b: Array = wall["b"]
			if index == 0:
				barrier.x.append(float(a[0]))
				barrier.y.append(float(a[1]))
			elif float(a[0]) != barrier.x[-1] or float(a[1]) != barrier.y[-1]:
				valid = false
				break
			barrier.x.append(float(b[0]))
			barrier.y.append(float(b[1]))
		if not valid:
			continue
		for index: int in barrier.x.size():
			var x: float = barrier.x[index]
			var y: float = barrier.y[index]
			magnitude = maxf(magnitude, maxf(absf(x), absf(y)))
			barrier.minimum_x = minf(barrier.minimum_x, x)
			barrier.minimum_y = minf(barrier.minimum_y, y)
			barrier.maximum_x = maxf(barrier.maximum_x, x)
			barrier.maximum_y = maxf(barrier.maximum_y, y)
		# Only bounded source coordinates and substantial body radii get a proof.
		# The omitted closing chord has length <= r, so every point on it lies
		# within r/2 of a real endpoint, well inside its existing capsule end cap.
		var margin: float = maxf(SKIN * 4.0, magnitude * 0.000001)
		var gap_x: float = barrier.x[-1] - barrier.x[0]
		var gap_y: float = barrier.y[-1] - barrier.y[0]
		if magnitude > 1000000.0 or radius < margin * 4.0 or gap_x * gap_x + gap_y * gap_y > radius * radius:
			continue
		result.append(barrier)
	_closed_barrier_cache[radius] = result
	return result


static func _barrier_contains(barrier: ClosedBarrier, point: Vector2) -> bool:
	var x: float = float(point.x)
	var y: float = float(point.y)
	if x < barrier.minimum_x or y < barrier.minimum_y or x > barrier.maximum_x or y > barrier.maximum_y:
		return false
	var inside: bool = false
	var previous: int = barrier.x.size() - 1
	for index: int in barrier.x.size():
		var ax: float = barrier.x[previous]
		var ay: float = barrier.y[previous]
		var bx: float = barrier.x[index]
		var by: float = barrier.y[index]
		if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
			inside = not inside
		previous = index
	return inside


func _closed_barrier_separates(start: Vector2, goal: Vector2, radius: float) -> bool:
	if _wall_rows.is_empty() or not start.is_finite() or not goal.is_finite() or not is_finite(radius) or radius < 1.0 or radius > INDEX_BODY_RADIUS:
		return false
	if maxf(maxf(absf(start.x), absf(start.y)), maxf(absf(goal.x), absf(goal.y))) > 1000000.0:
		return false
	var barriers: Array[ClosedBarrier] = _closed_barriers(radius)
	if barriers.is_empty() or not is_free(start, radius) or not is_free(goal, radius):
		return false
	for barrier: ClosedBarrier in barriers:
		if _barrier_contains(barrier, start) != _barrier_contains(barrier, goal):
			return true
	return false


func _graph(body_radius: float) -> AStar2D:
	if _graphs.has(body_radius):
		return _graphs[body_radius] as AStar2D
	var graph := AStar2D.new()
	for item_index: int in _items.size():
		if _active[item_index] == 0:
			continue
		var item: Dictionary = _items[item_index]
		var center: Vector2 = item["center"]
		var radius: float = (float(item["radius"]) + body_radius + ROUTE_CLEARANCE) / cos(PI / float(ROUTE_SIDES))
		for index: int in ROUTE_SIDES:
			var point: Vector2 = center + Vector2.from_angle(TAU * float(index) / float(ROUTE_SIDES)) * radius
			if is_free(point, body_radius):
				graph.add_point(graph.get_point_count(), point)
	if not _wall_rows.is_empty():
		var endpoints: Dictionary = {}
		var added: Dictionary = {}
		var clearance: float = (body_radius + ROUTE_CLEARANCE) / cos(PI / float(ROUTE_SIDES))
		for row: Dictionary in _wall_rows:
			for key: String in ["a", "b"]:
				var endpoint: Vector2 = _read_point(row[key])
				if endpoints.has(endpoint):
					continue
				endpoints[endpoint] = true
				# These are visibility-graph candidates around actual end caps;
				# physical collision remains the exact unsampled wall capsule.
				for side: int in ROUTE_SIDES:
					var point: Vector2 = endpoint + Vector2.from_angle(TAU * float(side) / float(ROUTE_SIDES)) * clearance
					if not added.has(point) and is_free(point, body_radius):
						graph.add_point(graph.get_point_count(), point)
						added[point] = true
	var ids: PackedInt64Array = graph.get_point_ids()
	_graph_point_ids[body_radius] = ids
	for first: int in ids.size():
		for second: int in range(first + 1, ids.size()):
			_navigation_graph_checks += 1
			if segment_clear(graph.get_point_position(ids[first]), graph.get_point_position(ids[second]), body_radius):
				graph.connect_points(ids[first], ids[second])
	_graphs[body_radius] = graph
	_navigation_graphs_built += 1
	return graph


func _build_route(start: Vector2, goal: Vector2, body_radius: float) -> PackedVector2Array:
	_sync_navigation_bounds()
	var query: Dictionary = _route_queries.get(body_radius, {})
	if query.is_empty() or query.get("goal", Vector2.INF) != goal or query["bounds"] != bounds:
		query = {"goal": goal, "bounds": bounds, "starts": {}}
		_route_queries[body_radius] = query
	var starts: Dictionary = query["starts"]
	if starts.has(start):
		_navigation_query_cache_hits += 1
		return (starts[start] as PackedVector2Array).duplicate()
	var graph: AStar2D = _graph(body_radius)
	var ids: PackedInt64Array = _graph_point_ids[body_radius]
	var goal_id: int = _shared_graph_goal(graph, ids, goal, body_radius)
	var start_id: int = goal_id + 1
	graph.add_point(start_id, start)
	_navigation_route_builds += 1
	var visibility: GraphVisibilityCache = _graph_visibility_for(body_radius)
	var finite_start: bool = start.is_finite()
	var start_links: StartVisibilityLinks = (visibility.starts.get(start) as StartVisibilityLinks) if finite_start else null
	if start_links == null:
		start_links = StartVisibilityLinks.new()
		var candidates: PackedInt64Array = _local_start_candidates(start, graph, ids)
		for id: int in candidates:
			start_links.tested.append(id)
			_navigation_start_checks += 1
			if segment_clear(start, graph.get_point_position(id), body_radius):
				start_links.local_ids.append(id)
				graph.connect_points(start_id, id)
				if start_links.local_ids.size() >= LOCAL_ROUTE_LINKS:
					break
		if finite_start:
			if visibility.starts.size() >= ROUTE_QUERY_CACHE_LIMIT:
				visibility.starts.clear()
			visibility.starts[start] = start_links
	else:
		_start_link_cache_hits += 1
		for id: int in start_links.local_ids:
			graph.connect_points(start_id, id)
	var path: PackedVector2Array = graph.get_point_path(start_id, goal_id)
	if path.is_empty():
		_navigation_fallbacks += 1
		if start_links.has_fallback:
			for id: int in start_links.fallback_ids:
				graph.connect_points(start_id, id)
		else:
			for id: int in ids:
				if start_links.tested.has(id):
					continue
				_navigation_start_checks += 1
				if segment_clear(start, graph.get_point_position(id), body_radius):
					start_links.fallback_ids.append(id)
					graph.connect_points(start_id, id)
			start_links.has_fallback = true
		path = graph.get_point_path(start_id, goal_id)
	graph.remove_point(start_id)
	if starts.size() >= ROUTE_QUERY_CACHE_LIMIT:
		starts.clear()
	starts[start] = path.duplicate()
	return path


func _graph_visibility_for(body_radius: float) -> GraphVisibilityCache:
	if not is_finite(body_radius) or not bounds.position.is_finite() or not bounds.size.is_finite():
		return GraphVisibilityCache.new()
	var cached: GraphVisibilityCache = _graph_visibility.get(body_radius) as GraphVisibilityCache
	if cached == null or cached.area != bounds:
		cached = GraphVisibilityCache.new()
		cached.area = bounds
		_graph_visibility[body_radius] = cached
	return cached


func _shared_graph_goal(graph: AStar2D, ids: PackedInt64Array, goal: Vector2, body_radius: float) -> int:
	var cached: Dictionary = _graph_goals.get(body_radius, {})
	var goal_id: int = ids.size()
	if cached.is_empty():
		graph.add_point(goal_id, goal)
	elif cached["position"] == goal:
		return goal_id
	else:
		for id: int in graph.get_point_connections(goal_id):
			graph.disconnect_points(goal_id, id)
		graph.set_point_position(goal_id, goal)
	var visibility: GraphVisibilityCache = _graph_visibility_for(body_radius)
	var finite_goal: bool = goal.is_finite()
	if finite_goal and visibility.goals.has(goal):
		_visible_goal_cache_hits += 1
		for id: int in visibility.goals[goal]:
			graph.connect_points(goal_id, id)
	else:
		var visible_ids := PackedInt64Array()
		for id: int in ids:
			var vertex: Vector2 = graph.get_point_position(id)
			var visible: bool = not _wall_rows.is_empty() and _fixed_vertex_goal_cell_clear(goal, vertex, body_radius)
			if visible:
				_goal_cell_proof_hits += 1
			else:
				_navigation_goal_checks += 1
				visible = segment_clear(goal, vertex, body_radius)
			if visible:
				visible_ids.append(id)
				graph.connect_points(goal_id, id)
		if finite_goal:
			if visibility.goals.size() >= ROUTE_QUERY_CACHE_LIMIT:
				visibility.goals.clear()
			visibility.goals[goal] = visible_ids
	_graph_goals[body_radius] = {"position": goal, "id": goal_id}
	_navigation_goal_refreshes += 1
	return goal_id


func _fixed_vertex_goal_cell_clear(goal: Vector2, vertex: Vector2, radius: float) -> bool:
	if _wall_rows.is_empty() or not goal.is_finite() or not vertex.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	var x: float = float(goal.x) / WALL_CORRIDOR_CELL_SIZE
	var y: float = float(goal.y) / WALL_CORRIDOR_CELL_SIZE
	if not _safe_curve_cells(x, y, x, y):
		return false
	var cell := Vector2i(floori(x), floori(y))
	var cached: GoalCellProofs = _goal_cell_proofs.get(radius) as GoalCellProofs
	if cached == null or cached.area != bounds:
		cached = GoalCellProofs.new()
		cached.area = bounds
		_goal_cell_proofs[radius] = cached
	if not cached.cells.has(cell):
		if cached.cells.size() >= 128:
			cached.cells.clear()
		cached.cells[cell] = {}
	var proofs: Dictionary = cached.cells[cell]
	if proofs.has(vertex):
		return bool(proofs[vertex])
	var region := Rect2(Vector2(cell) * WALL_CORRIDOR_CELL_SIZE, Vector2.ONE * WALL_CORRIDOR_CELL_SIZE)
	var safe: bool = region.end.is_finite() and region.end.x > region.position.x and region.end.y > region.position.y and bounds.encloses(region) \
		and vertex.x >= bounds.position.x and vertex.y >= bounds.position.y and vertex.x <= bounds.end.x and vertex.y <= bounds.end.y
	if safe:
		var corners := PackedVector2Array([region.position, Vector2(region.end.x, region.position.y), region.end,
			Vector2(region.position.x, region.end.y), vertex])
		var hull: PackedVector2Array = Geometry2D.convex_hull(corners)
		var clearance: float = radius + SKIN
		for index: int in hull.size():
			if not walls.navigation_clear(hull[index], hull[(index + 1) % hull.size()], clearance):
				safe = false
				break
		if safe:
			for wall: Dictionary in _wall_rows:
				if Geometry2D.is_point_in_polygon(_read_point(wall["a"]), hull) or Geometry2D.is_point_in_polygon(_read_point(wall["b"]), hull):
					safe = false
					break
		if safe:
			for index: int in _centers.size():
				if _active[index] == 0:
					continue
				var center: Vector2 = _centers[index]
				var radius_squared: float = pow(_radii[index] + radius + SKIN, 2)
				if Geometry2D.is_point_in_polygon(center, hull):
					safe = false
					break
				for edge_index: int in hull.size():
					var start: Vector2 = hull[edge_index]
					var edge: Vector2 = hull[(edge_index + 1) % hull.size()] - start
					var fraction: float = clampf((center - start).dot(edge) / edge.length_squared(), 0.0, 1.0) if not edge.is_zero_approx() else 0.0
					if center.distance_squared_to(start + edge * fraction) < radius_squared:
						safe = false
						break
				if not safe:
					break
	_goal_cell_proofs_checked += 1
	if proofs.size() >= ROUTE_QUERY_CACHE_LIMIT:
		proofs.clear()
	# False means unknown: the caller still performs the original exact segment.
	proofs[vertex] = safe
	return safe


func _local_start_candidates(start: Vector2, graph: AStar2D, ids: PackedInt64Array) -> PackedInt64Array:
	var nearest: PackedInt64Array = PackedInt64Array()
	var distances: PackedFloat64Array = PackedFloat64Array()
	for id: int in ids:
		var distance: float = start.distance_squared_to(graph.get_point_position(id))
		var index: int = distances.size()
		while index > 0 and distance < distances[index - 1]:
			index -= 1
		if index >= LOCAL_ROUTE_CANDIDATES:
			continue
		nearest.insert(index, id)
		distances.insert(index, distance)
		if nearest.size() > LOCAL_ROUTE_CANDIDATES:
			nearest.resize(LOCAL_ROUTE_CANDIDATES)
			distances.resize(LOCAL_ROUTE_CANDIDATES)
	return nearest


func clear_spawn_segments(segments: Array[Rect2], body_radius: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for segment: Rect2 in segments:
		var length: float = segment.size.length()
		if length <= 0.0001:
			continue
		var direction: Vector2 = segment.size / length
		var intervals: Array[Vector2] = [Vector2(0.0, length)]
		for item_index: int in _items.size():
			if _active[item_index] == 0:
				continue
			var item: Dictionary = _items[item_index]
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
		if not _wall_rows.is_empty():
			intervals = _clear_wall_intervals(segment, direction, intervals, body_radius)
		for interval: Vector2 in intervals:
			if interval.y - interval.x > 0.0001:
				result.append(Rect2(segment.position + direction * interval.x, direction * (interval.y - interval.x)))
	return result


func _safe_cell_movement(start: Vector2, movement: Vector2, body_radius: float, inset: float) -> bool:
	if not start.is_finite() or not movement.is_finite() or not is_finite(body_radius) or body_radius < 0.0 or not is_finite(inset) or inset < 0.0:
		return false
	# The original solver intentionally ignores sub-threshold displacement.
	if movement.length_squared() <= 0.000001:
		return false
	var end: Vector2 = start + movement
	if not end.is_finite():
		return false
	var start_x: float = float(start.x) / CURVE_CELL_SIZE
	var start_y: float = float(start.y) / CURVE_CELL_SIZE
	var end_x: float = float(end.x) / CURVE_CELL_SIZE
	var end_y: float = float(end.y) / CURVE_CELL_SIZE
	if not _safe_curve_cells(start_x, start_y, end_x, end_y):
		return false
	var cell := Vector2i(floori(start_x), floori(start_y))
	if cell != Vector2i(floori(end_x), floori(end_y)):
		return false
	var area: Rect2 = bounds.grow(-inset)
	if end.x <= area.position.x or end.y <= area.position.y or end.x >= area.end.x or end.y >= area.end.y:
		return false
	var inset_caches: Dictionary = _safe_move_cells.get(body_radius, {})
	var cached: SafeMoveCells = inset_caches.get(inset) as SafeMoveCells
	if cached == null or cached.area != area:
		cached = SafeMoveCells.new()
		cached.area = area
		inset_caches[inset] = cached
		_safe_move_cells[body_radius] = inset_caches
	if cached.proofs.has(cell):
		return bool(cached.proofs[cell])
	var region := Rect2(Vector2(cell) * CURVE_CELL_SIZE, Vector2.ONE * CURVE_CELL_SIZE)
	var safe: bool = region.end.is_finite() and region.end.x > region.position.x and region.end.y > region.position.y and area.encloses(region)
	if safe:
		safe = walls.bounds_clear(region, body_radius, SKIN)
	if safe:
		for index: int in _centers.size():
			if _active[index] == 0:
				continue
			var radius: float = _radii[index] + body_radius + SKIN
			var center: Vector2 = _centers[index]
			if float(center.x) + radius >= float(region.position.x) and float(center.x) - radius <= float(region.end.x) \
				and float(center.y) + radius >= float(region.position.y) and float(center.y) - radius <= float(region.end.y):
				safe = false
				break
	if cached.proofs.size() >= ROUTE_QUERY_CACHE_LIMIT:
		cached.proofs.clear()
	# A failed certificate only selects the complete original swept solver.
	cached.proofs[cell] = safe
	_safe_cell_proofs_checked += 1
	return safe


func _proven_wall_movement(start: Vector2, movement: Vector2, body_radius: float, inset: float) -> bool:
	if not start.is_finite() or not movement.is_finite() or not is_finite(body_radius) or body_radius < 0.0 or not is_finite(inset) or inset < 0.0:
		return false
	var end: Vector2 = start + movement
	if not end.is_finite():
		return false
	var area: Rect2 = bounds.grow(-inset)
	if not area.position.is_finite() or not area.size.is_finite() or not area.end.is_finite() or area.size.x <= 0.0 or area.size.y <= 0.0:
		return false
	if start.x < area.position.x or start.y < area.position.y or start.x > area.end.x or start.y > area.end.y:
		return false
	if end.x <= area.position.x or end.y <= area.position.y or end.x >= area.end.x or end.y >= area.end.y:
		return false
	return walls.navigation_clear(start, end, body_radius)


func _move_combined(start: Vector2, movement: Vector2, body_radius: float, inset: float, allow_slide: bool) -> Vector2:
	var position: Vector2 = free_point(start, body_radius, inset)
	if not position.is_finite() or not movement.is_finite():
		return position
	var remaining: Vector2 = movement
	for _iteration: int in TerrainWalls.MAX_SLIDES:
		if remaining.length_squared() <= 0.000001:
			break
		var hit: Dictionary = first_hit(position, remaining, body_radius, inset)
		if hit.is_empty():
			return free_point(position + remaining, body_radius, inset)
		var advance: float = maxf(0.0, float(hit["t"]) - SKIN / maxf(remaining.length(), SKIN))
		position += remaining * advance
		if not allow_slide:
			break
		remaining *= 1.0 - advance
		var normal: Vector2 = hit["normal"]
		var inward: float = remaining.dot(normal)
		if inward < 0.0:
			remaining -= normal * inward
		elif advance == 0.0:
			break
	return free_point(position, body_radius, inset)


func _wall_curves(radius: float) -> Array[Dictionary]:
	if _wall_curve_cache.has(radius):
		return (_wall_curve_cache[radius] as Array[Dictionary]).duplicate()
	var result: Array[Dictionary] = []
	for row: Dictionary in _wall_rows:
		var ax: float = float(row["a"][0])
		var ay: float = float(row["a"][1])
		var bx: float = float(row["b"][0])
		var by: float = float(row["b"][1])
		var vx: float = bx - ax
		var vy: float = by - ay
		var length: float = sqrt(vx * vx + vy * vy)
		if length > 0.0:
			var nx: float = -vy / length * radius
			var ny: float = vx / length * radius
			for side: float in [-1.0, 1.0]:
				result.append({"kind": 0, "ax": ax + nx * side, "ay": ay + ny * side, "bx": bx + nx * side, "by": by + ny * side})
		result.append({"kind": 1, "x": ax, "y": ay, "r": radius})
		if length > 0.0:
			result.append({"kind": 1, "x": bx, "y": by, "r": radius})
	_wall_curve_cache[radius] = result
	return result.duplicate()


static func _bounds_curves(area: Rect2) -> Array[Dictionary]:
	return [{"kind": 0, "ax": float(area.position.x), "ay": float(area.position.y), "bx": float(area.end.x), "by": float(area.position.y)},
		{"kind": 0, "ax": float(area.end.x), "ay": float(area.position.y), "bx": float(area.end.x), "by": float(area.end.y)},
		{"kind": 0, "ax": float(area.end.x), "ay": float(area.end.y), "bx": float(area.position.x), "by": float(area.end.y)},
		{"kind": 0, "ax": float(area.position.x), "ay": float(area.end.y), "bx": float(area.position.x), "by": float(area.position.y)}]


func _combined_curves(radius: float, inset: float, area: Rect2) -> CombinedCurves:
	var inset_caches: Dictionary = _combined_curve_cache.get(radius, {})
	var cached: CombinedCurves = inset_caches.get(inset) as CombinedCurves
	if cached != null and cached.area == area:
		return cached
	var geometry := CombinedCurves.new()
	geometry.area = area
	geometry.curves = _wall_curves(radius + SKIN)
	geometry.curves.append_array(_bounds_curves(area))
	for index: int in _centers.size():
		if _active[index] != 0:
			geometry.curves.append({"kind": 1, "x": float(_centers[index].x), "y": float(_centers[index].y), "r": _radii[index] + radius + SKIN})
	for index: int in geometry.curves.size():
		var curve: Dictionary = geometry.curves[index]
		var low_x: float
		var low_y: float
		var high_x: float
		var high_y: float
		if int(curve["kind"]) == 0:
			low_x = minf(float(curve["ax"]), float(curve["bx"]))
			low_y = minf(float(curve["ay"]), float(curve["by"]))
			high_x = maxf(float(curve["ax"]), float(curve["bx"]))
			high_y = maxf(float(curve["ay"]), float(curve["by"]))
		else:
			low_x = float(curve["x"]) - float(curve["r"])
			low_y = float(curve["y"]) - float(curve["r"])
			high_x = float(curve["x"]) + float(curve["r"])
			high_y = float(curve["y"]) + float(curve["r"])
		geometry.low_x.append(low_x)
		geometry.low_y.append(low_y)
		geometry.high_x.append(high_x)
		geometry.high_y.append(high_y)
		geometry.indices.append(index)
		var pairs: Array[Dictionary] = []
		geometry.intersections.append(pairs)
		var first_x: float = (low_x - SKIN) / CURVE_CELL_SIZE
		var first_y: float = (low_y - SKIN) / CURVE_CELL_SIZE
		var last_x: float = (high_x + SKIN) / CURVE_CELL_SIZE
		var last_y: float = (high_y + SKIN) / CURVE_CELL_SIZE
		if not _safe_curve_cells(first_x, first_y, last_x, last_y):
			geometry.full_order = true
			continue
		var first := Vector2i(floori(first_x), floori(first_y))
		var last := Vector2i(floori(last_x), floori(last_y))
		if float(last.x - first.x + 1) * float(last.y - first.y + 1) <= 4096.0:
			for x: int in range(first.x, last.x + 1):
				for y: int in range(first.y, last.y + 1):
					var cell := Vector2i(x, y)
					var ids: PackedInt32Array = geometry.cells.get(cell, PackedInt32Array())
					ids.append(index)
					geometry.cells[cell] = ids
		else:
			# Unusually large source geometry keeps the complete ordered fallback.
			geometry.full_order = true
	for first: int in geometry.curves.size():
		for second: int in range(first + 1, geometry.curves.size()):
			if geometry.low_x[first] > geometry.high_x[second] + SKIN or geometry.high_x[first] < geometry.low_x[second] - SKIN \
				or geometry.low_y[first] > geometry.high_y[second] + SKIN or geometry.high_y[first] < geometry.low_y[second] - SKIN:
				continue
			_combined_intersections_solved += 1
			var points: PackedFloat64Array = TerrainWalls._intersections(geometry.curves[first], geometry.curves[second])
			var valid := PackedFloat64Array()
			for at: int in range(0, points.size(), 2):
				var candidate := Vector2(points[at], points[at + 1])
				if is_free(candidate, radius, inset):
					valid.append(points[at])
					valid.append(points[at + 1])
			if not valid.is_empty():
				geometry.intersections[first].append({"second": second, "points": valid})
	_combined_curve_builds += 1
	inset_caches[inset] = geometry
	_combined_curve_cache[radius] = inset_caches
	return geometry


static func _safe_curve_cells(first_x: float, first_y: float, last_x: float, last_y: float) -> bool:
	return is_finite(first_x) and is_finite(first_y) and is_finite(last_x) and is_finite(last_y) \
		and maxf(maxf(absf(first_x), absf(first_y)), maxf(absf(last_x), absf(last_y))) <= MAX_CURVE_CELL_COORDINATE


func _curve_query_ids(geometry: CombinedCurves, query: Vector2, radius: float, inset: float) -> PackedInt32Array:
	if geometry.full_order:
		return geometry.indices
	var contact: Dictionary = walls.nearest_point(query)
	if contact.is_empty():
		return geometry.indices
	var normal: Vector2 = contact["normal"]
	var wall_point: Vector2 = contact["wall_point"]
	var upper: float = INF
	for side: float in [1.0, -1.0]:
		var candidate: Vector2 = wall_point + normal * ((radius + SKIN) * side)
		if is_free(candidate, radius, inset):
			upper = minf(upper, candidate.distance_to(query))
	if not is_finite(upper):
		return geometry.indices
	# A feasible point bounds the nearest result, but never enters the candidate
	# stream. Preserve the original projection/pair/point tie order exactly.
	upper += maxf(SKIN, maxf(absf(query.x), absf(query.y)) * 0.000001)
	var first_x: float = (float(query.x) - upper) / CURVE_CELL_SIZE
	var first_y: float = (float(query.y) - upper) / CURVE_CELL_SIZE
	var last_x: float = (float(query.x) + upper) / CURVE_CELL_SIZE
	var last_y: float = (float(query.y) + upper) / CURVE_CELL_SIZE
	if not _safe_curve_cells(first_x, first_y, last_x, last_y):
		return geometry.indices
	var first := Vector2i(floori(first_x), floori(first_y))
	var last := Vector2i(floori(last_x), floori(last_y))
	if float(last.x - first.x + 1) * float(last.y - first.y + 1) > 256.0:
		return geometry.indices
	var key := Vector4i(first.x, first.y, last.x, last.y)
	if geometry.cell_queries.has(key):
		return geometry.cell_queries[key]
	var found: Dictionary = {}
	for x: int in range(first.x, last.x + 1):
		for y: int in range(first.y, last.y + 1):
			for index: int in geometry.cells.get(Vector2i(x, y), PackedInt32Array()):
				found[index] = true
	var ids := PackedInt32Array()
	for index: int in found:
		ids.append(index)
	ids.sort()
	if geometry.cell_queries.size() >= ROUTE_QUERY_CACHE_LIMIT:
		geometry.cell_queries.clear()
	geometry.cell_queries[key] = ids
	return ids


func _remember_known_free(geometry: CombinedCurves, point: Vector2) -> void:
	if geometry.known_free_points.has(point):
		return
	if geometry.known_free_points.size() >= ROUTE_QUERY_CACHE_LIMIT:
		geometry.known_free_points.clear()
	geometry.known_free_points[point] = true
	_known_free_points_recorded += 1


func _free_combined(point: Vector2, body_radius: float, inset: float) -> Vector2:
	var radius: float = maxf(0.0, body_radius) if is_finite(body_radius) else 0.0
	var area: Rect2 = bounds.grow(-maxf(0.0, inset))
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return Vector2.INF
	var query: Vector2 = _clamp(point, inset)
	var existing: CombinedCurves = null
	if _combined_curve_cache.has(radius):
		var inset_caches: Dictionary = _combined_curve_cache[radius]
		existing = inset_caches.get(inset) as CombinedCurves
		if existing != null and existing.area != area:
			existing = null
		if existing != null:
			if existing.known_free_points.has(query):
				_known_free_hits += 1
				return query
			if existing.query_results.has(query):
				_combined_query_hits += 1
				var result: Vector2 = existing.query_results[query]
				if result.is_finite():
					_remember_known_free(existing, result)
				return result
	if is_free(query, radius, inset):
		if existing != null:
			_remember_known_free(existing, query)
		return query
	var geometry: CombinedCurves = _combined_curves(radius, inset, area)
	var ids: PackedInt32Array = _curve_query_ids(geometry, query, radius, inset)
	var best: Vector2 = Vector2.INF
	var best_squared: float = INF
	var x: float = float(query.x)
	var y: float = float(query.y)
	var rounding_margin: float = maxf(SKIN, maxf(absf(x), absf(y)) * 0.000001)
	for index: int in ids:
		var low_dx: float = maxf(0.0, maxf(geometry.low_x[index] - x - rounding_margin, x - geometry.high_x[index] - rounding_margin))
		var low_dy: float = maxf(0.0, maxf(geometry.low_y[index] - y - rounding_margin, y - geometry.high_y[index] - rounding_margin))
		if low_dx * low_dx + low_dy * low_dy > best_squared + 0.00000001:
			continue
		_combined_projection_tests += 1
		var curve: Dictionary = geometry.curves[index]
		var candidate: Vector2
		if int(curve["kind"]) == 0:
			var ax: float = float(curve["ax"])
			var ay: float = float(curve["ay"])
			var vx: float = float(curve["bx"]) - ax
			var vy: float = float(curve["by"]) - ay
			var fraction: float = clampf(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy), 0.0, 1.0)
			candidate = Vector2(ax + vx * fraction, ay + vy * fraction)
		else:
			var cx: float = float(curve["x"])
			var cy: float = float(curve["y"])
			var ox: float = x - cx
			var oy: float = y - cy
			var length: float = sqrt(ox * ox + oy * oy)
			var clearance: float = float(curve["r"])
			if length > 0.000000001:
				candidate = Vector2(cx + ox / length * clearance, cy + oy / length * clearance)
			else:
				for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
					candidate = Vector2(cx, cy) + direction * clearance
					var squared: float = candidate.distance_squared_to(query)
					if squared < best_squared and is_free(candidate, radius, inset):
						best = candidate
						best_squared = squared
				continue
		var squared: float = candidate.distance_squared_to(query)
		if squared < best_squared and is_free(candidate, radius, inset):
			best = candidate
			best_squared = squared
	var distances := PackedFloat64Array()
	distances.resize(geometry.curves.size())
	distances.fill(-1.0)
	for first: int in ids:
		if geometry.intersections[first].is_empty():
			continue
		if distances[first] < 0.0:
			distances[first] = TerrainWalls._curve_distance_squared(geometry.curves[first], x, y)
		if distances[first] > best_squared:
			continue
		for pair: Dictionary in geometry.intersections[first]:
			var second: int = int(pair["second"])
			if distances[second] < 0.0:
				distances[second] = TerrainWalls._curve_distance_squared(geometry.curves[second], x, y)
			if distances[second] > best_squared:
				continue
			var points: PackedFloat64Array = pair["points"]
			for at: int in range(0, points.size(), 2):
				var candidate := Vector2(points[at], points[at + 1])
				var squared: float = candidate.distance_squared_to(query)
				if squared < best_squared:
					best = candidate
					best_squared = squared
	if geometry.query_results.size() >= ROUTE_QUERY_CACHE_LIMIT:
		geometry.query_results.clear()
	geometry.query_results[query] = best
	_combined_queries_solved += 1
	if best.is_finite():
		_remember_known_free(geometry, best)
	return best


func _clear_wall_intervals(segment: Rect2, direction: Vector2, intervals: Array[Vector2], body_radius: float) -> Array[Vector2]:
	var curves: Array[Dictionary] = _wall_curves(body_radius + SKIN)
	curves.append_array(_bounds_curves(bounds))
	var ray: Dictionary = {"kind": 0, "ax": float(segment.position.x), "ay": float(segment.position.y), "bx": float(segment.end.x), "by": float(segment.end.y)}
	var cuts := PackedFloat64Array()
	for curve: Dictionary in curves:
		var points: PackedFloat64Array = TerrainWalls._intersections(ray, curve)
		for at: int in range(0, points.size(), 2):
			cuts.append((points[at] - float(segment.position.x)) * float(direction.x) + (points[at + 1] - float(segment.position.y)) * float(direction.y))
	cuts.sort()
	var result: Array[Vector2] = []
	for interval: Vector2 in intervals:
		var start: float = float(interval.x)
		for cut: float in cuts:
			if cut <= start + 0.0001 or cut >= float(interval.y):
				continue
			var midpoint: Vector2 = segment.position + direction * ((start + cut) * 0.5)
			if is_free(midpoint, body_radius):
				result.append(Vector2(start, cut))
			start = cut
		if float(interval.y) - start > 0.0001 and is_free(segment.position + direction * ((start + float(interval.y)) * 0.5), body_radius):
			result.append(Vector2(start, float(interval.y)))
	return result
