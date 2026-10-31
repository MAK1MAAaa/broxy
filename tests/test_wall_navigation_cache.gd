extends SceneTree
## Exact repeated queries reuse work; moving endpoints and geometry still recompute.

class ProjectionReference extends ArenaObstacles:
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
		var candidates: PackedInt64Array = _local_start_candidates(start, graph, ids)
		var links: int = 0
		var tested: PackedInt64Array = PackedInt64Array()
		for id: int in candidates:
			tested.append(id)
			_navigation_start_checks += 1
			if segment_clear(start, graph.get_point_position(id), body_radius):
				graph.connect_points(start_id, id)
				links += 1
				if links >= LOCAL_ROUTE_LINKS:
					break
		var path: PackedVector2Array = graph.get_point_path(start_id, goal_id)
		if path.is_empty():
			_navigation_fallbacks += 1
			for id: int in ids:
				if tested.has(id):
					continue
				_navigation_start_checks += 1
				if segment_clear(start, graph.get_point_position(id), body_radius):
					graph.connect_points(start_id, id)
			path = graph.get_point_path(start_id, goal_id)
		graph.remove_point(start_id)
		if starts.size() >= ROUTE_QUERY_CACHE_LIMIT:
			starts.clear()
		starts[start] = path.duplicate()
		return path

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
		for id: int in ids:
			_navigation_goal_checks += 1
			if segment_clear(goal, graph.get_point_position(id), body_radius):
				graph.connect_points(goal_id, id)
		_graph_goals[body_radius] = {"position": goal, "id": goal_id}
		_navigation_goal_refreshes += 1
		return goal_id


	func move_body(start: Vector2, movement: Vector2, body_radius: float, inset: float = 0.0, slide: bool = true) -> Vector2:
		if not _wall_rows.is_empty():
			return _move_combined(start, movement, body_radius, inset, slide)
		return super.move_body(start, movement, body_radius, inset, slide)

	func _free_combined(point: Vector2, body_radius: float, inset: float) -> Vector2:
		var radius: float = maxf(0.0, body_radius) if is_finite(body_radius) else 0.0
		var area: Rect2 = bounds.grow(-maxf(0.0, inset))
		if area.size.x <= 0.0 or area.size.y <= 0.0:
			return Vector2.INF
		var query: Vector2 = _clamp(point, inset)
		if is_free(query, radius, inset):
			return query
		# Exact boundary candidates for a bounded union: wall offset lines/end caps,
		# circle colliders, and the four actual bounds edges. No iterative pushing
		# between a wall and a boundary, and no sampled replacement collision.
		var curves: Array[Dictionary] = _wall_curves(radius + SKIN)
		curves.append_array(_bounds_curves(area))
		for index: int in _centers.size():
			if _active[index] != 0:
				curves.append({"kind": 1, "x": float(_centers[index].x), "y": float(_centers[index].y), "r": _radii[index] + radius + SKIN})
		var candidates: Array[Vector2] = []
		var x: float = float(query.x)
		var y: float = float(query.y)
		for curve: Dictionary in curves:
			if int(curve["kind"]) == 0:
				var ax: float = float(curve["ax"])
				var ay: float = float(curve["ay"])
				var vx: float = float(curve["bx"]) - ax
				var vy: float = float(curve["by"]) - ay
				var fraction: float = clampf(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy), 0.0, 1.0)
				candidates.append(Vector2(ax + vx * fraction, ay + vy * fraction))
			else:
				var cx: float = float(curve["x"])
				var cy: float = float(curve["y"])
				var ox: float = x - cx
				var oy: float = y - cy
				var length: float = sqrt(ox * ox + oy * oy)
				var clearance: float = float(curve["r"])
				if length > 0.000000001:
					candidates.append(Vector2(cx + ox / length * clearance, cy + oy / length * clearance))
				else:
					for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
						candidates.append(Vector2(cx, cy) + direction * clearance)
		var best: Vector2 = Vector2.INF
		var best_squared: float = INF
		for candidate: Vector2 in candidates:
			var squared: float = candidate.distance_squared_to(query)
			if squared < best_squared and is_free(candidate, radius, inset):
				best = candidate
				best_squared = squared
		for first: int in curves.size():
			if TerrainWalls._curve_distance_squared(curves[first], x, y) > best_squared:
				continue
			for second: int in range(first + 1, curves.size()):
				if TerrainWalls._curve_distance_squared(curves[second], x, y) > best_squared:
					continue
				var intersections: PackedFloat64Array = TerrainWalls._intersections(curves[first], curves[second])
				for at: int in range(0, intersections.size(), 2):
					var candidate := Vector2(intersections[at], intersections[at + 1])
					var squared: float = candidate.distance_squared_to(query)
					if squared < best_squared and is_free(candidate, radius, inset):
						best = candidate
						best_squared = squared
		return best


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
				projection.checked_corridors.clear()
		var goal: Vector2 = projection.position
		var direct: bool = false
		if not _wall_rows.is_empty():
			direct = segment_clear(start, goal, body_radius)
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
		var route: Dictionary = _routes.get(agent_id, {})
		var path: PackedVector2Array = route.get("path", PackedVector2Array())
		var index: int = int(route.get("index", 0))
		var old_goal: Vector2 = route.get("goal", Vector2.INF)
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
			path = _build_route(start, goal, body_radius)
			index = 1 if path.size() > 1 else 0
			old_goal = goal
		_routes[agent_id] = {"path": path, "index": index, "goal": old_goal}
		return path[index] if index < path.size() else start


class CorridorProbe extends ArenaObstacles:
	var corridor_calls: int = 0

	func _cell_corridor_clear(source: Vector2i, target: Vector2i, body_radius: float, candidates: PackedInt32Array) -> bool:
		corridor_calls += 1
		return super._cell_corridor_clear(source, target, body_radius, candidates)


class KnownFreeProbe extends ArenaObstacles:
	var free_checks: int = 0

	func is_free(point: Vector2, body_radius: float = 0.0, inset: float = 0.0) -> bool:
		free_checks += 1
		return super.is_free(point, body_radius, inset)


var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_unreachable_queries()
	_test_shared_positive_queries()
	_test_geometry_invalidation()
	_test_curve_cache()
	_test_bounded_query_cache()
	_test_projection_oracle()
	_test_wall_cell_corridors()
	_test_exact_projection_queries()
	_test_known_free_points()
	_test_safe_cell_movement()
	_test_safe_cell_boundary_endpoints()
	_test_proven_wall_movement()
	_test_closed_barrier_certificates()
	_test_goal_cell_vertex_proofs()
	_test_navigation_route_reuse()
	_test_exact_visibility_links()
	_test_visibility_link_invalidation()
	_test_visibility_link_limits()
	print("WallNavigationCache: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _field(closed: bool = true) -> ArenaObstacles:
	var field := ArenaObstacles.new()
	field.bounds = Rect2(0, 0, 400, 400)
	field.configure([{"id": "switch", "center": Vector2(50, 50), "radius": 18.0}])
	var low: float = 0.0 if closed else 100.0
	var high: float = 400.0 if closed else 300.0
	_check(field.configure_walls([{"id": "divider", "object_id": 77, "a": [200.0, low], "b": [200.0, high]}]), "The real open segment configures")
	return field


func _test_unreachable_queries() -> void:
	var field: ArenaObstacles = _field()
	var start := Vector2(100, 200)
	var goal := Vector2(300, 200)
	_check(not field.segment_clear(start, goal, 13.0), "The bounds-spanning wall actually separates the fixture")
	for tick: int in 300:
		_check(field.next_target(start, goal, 13.0, 7) == start, "An unchanged disconnected agent remains stationary without an unsafe shortcut")
	var stats: Dictionary = field.navigation_stats()
	_check(int(stats["route_builds"]) == 1 and int(stats["unreachable_cache_hits"]) == 299, "Three hundred identical failed queries perform one real A-star build")
	for agent: int in range(8, 308):
		_check(field.next_target(start, goal, 13.0, agent) == start, "Different agents with the same exact query retain the same empty route")
	stats = field.navigation_stats()
	_check(int(stats["route_builds"]) == 1 and int(stats["query_cache_hits"]) == 300, "Coincident enemy projections share the actual empty result")
	field.next_target(start + Vector2(0.125, 0), goal, 13.0, 7)
	_check(int(field.navigation_stats()["route_builds"]) == 2, "A subpixel start change cannot reuse an unreachable-agent proof")
	field.next_target(start, goal + Vector2(0, 0.125), 13.0, 7)
	_check(int(field.navigation_stats()["route_builds"]) == 3 and int(field.navigation_stats()["goal_refreshes"]) == 2, "A subpixel exact goal change recomputes both route and goal visibility")
	field.next_target(start, goal, 22.0, 7)
	_check(int(field.navigation_stats()["graphs_built"]) == 2 and int(field.navigation_stats()["route_builds"]) == 4, "Different enemy radii never share clearance results")
	field.clear_routes()
	field.next_target(start, goal, 13.0, 7)
	_check(int(field.navigation_stats()["route_builds"]) == 5, "Explicit route invalidation also discards shared negative results")
	field.forget_agent(7)
	_check(not field._routes.has(7), "Recycled agent identity loses its per-agent route state")


func _test_shared_positive_queries() -> void:
	var field: ArenaObstacles = _field(false)
	var start := Vector2(100, 200)
	var goal := Vector2(300, 200)
	var expected: PackedVector2Array = field._build_route(start, goal, 13.0)
	_check(expected.size() > 2 and expected[0] == start and expected[-1] == goal, "The finite original wall requires a genuine route around an endpoint")
	for index: int in range(1, expected.size()):
		_check(field.segment_clear(expected[index - 1], expected[index], 13.0), "Every shared path edge has full body clearance against the exact wall")
	for agent: int in 300:
		var waypoint: Vector2 = field.next_target(start, goal, 13.0, agent)
		_check(waypoint == expected[1] and field._routes[agent].path == expected, "Every coincident agent receives the complete original route and first waypoint")
	_check(int(field.navigation_stats()["route_builds"]) == 1 and int(field.navigation_stats()["query_cache_hits"]) == 300, "A positive exact query also shares one actual A-star result")
	var detached: PackedVector2Array = field._build_route(start, goal, 13.0)
	detached[-1] = Vector2.INF
	_check(field._build_route(start, goal, 13.0) == expected, "Caller mutation of a packed path cannot corrupt cached geometry")
	var moved_goal := Vector2(300, 260)
	var waypoint: Vector2 = field.next_target(start, moved_goal, 13.0, 0)
	var path: PackedVector2Array = field._routes[0].path
	_check(field.segment_clear(start, waypoint, 13.0) and path[-1] == moved_goal, "A moving reachable goal still uses the original safe tail-retarget rule")
	_check(field._build_route(start, goal, 13.0) == expected, "One agent's tail retarget cannot corrupt the original exact start-goal answer")


func _test_geometry_invalidation() -> void:
	var field: ArenaObstacles = _field()
	var start := Vector2(100, 200)
	var goal := Vector2(300, 200)
	field.next_target(start, goal, 13.0, 1)
	_check(field.set_active("switch", false) and field._route_queries.is_empty() and field._routes.is_empty(), "Circle activation invalidates all shared and per-agent route answers")
	field.next_target(start, goal, 13.0, 1)
	_check(int(field.navigation_stats()["route_builds"]) == 2, "An actual geometry revision cannot reuse the prior failed query")
	_check(field.configure_walls([]) and field._wall_curve_cache.is_empty(), "Removing walls discards the derived offset curves")
	_check(field.next_target(start, goal, 13.0, 1) == goal, "Opening the physical divider makes the destination reachable immediately")
	_check(field.configure_walls([{"id": "new-divider", "a": [200, 0], "b": [200, 400]}]), "Restoring a distinct source wall succeeds")
	_check(field.next_target(start, goal, 13.0, 1) == start, "Restored geometry cannot reuse the former open route")
	field.configure([])
	_check(field._wall_curve_cache.is_empty() and field._route_queries.is_empty() and field.next_target(start, goal, 13.0, 1) == goal, "Full arena reconfiguration removes every derived result")


func _test_curve_cache() -> void:
	var field: ArenaObstacles = _field(false)
	var curves: Array[Dictionary] = field._wall_curves(13.05)
	var count: int = curves.size()
	curves.append({"kind": 0, "ax": -999.0, "ay": -999.0, "bx": -998.0, "by": -998.0})
	_check(field._wall_curves(13.05).size() == count, "Bounds appended by a query cannot accumulate inside the static wall-curve cache")
	var source := Vector2(200, 200)
	var expected: Vector2 = field.free_point(source, 13.0, 8.0)
	for repeat: int in 30:
		_check(field.free_point(source, 13.0, 8.0) == expected and field.is_free(expected, 13.0, 8.0), "Repeated exact combined projection preserves its free point and candidate ordering")
	_check(field._wall_curves(13.05).size() == count, "Combined queries keep an independent array for bounds and circles")
	field.configure_walls([{"id": "replacement", "a": [300, 100], "b": [300, 300]}])
	_check(field._wall_curve_cache.is_empty() and field.free_point(source, 13.0, 8.0) == source, "A changed source wall discards the earlier curves and frees the original point")


func _test_bounded_query_cache() -> void:
	var field: ArenaObstacles = _field()
	var goal := Vector2(300, 200)
	for index: int in range(ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT + 2):
		var start := Vector2(100, 180.0 + float(index) / 100.0)
		_check(field.next_target(start, goal, 13.0, 1) == start, "Distinct disconnected starts preserve their actual failed paths")
	var cached: Dictionary = field._route_queries[13.0]["starts"]
	_check(cached.size() <= ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT, "Exact moving queries cannot grow the shared cache without bound")


func _test_projection_oracle() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 2026103109
	var circles: Array = [{"id": "toggle", "center": Vector2(550, 440), "radius": 39.0},
		{"id": "corner", "center": Vector2(910, 780), "radius": 27.0}]
	var stage_id: String = "wf_main_4_4_4_l0"
	var source_walls: Array[Dictionary] = ArenaCatalog.wall_geometry(stage_id)
	_check(source_walls.size() == 87, "The projection oracle exercises all87 real source wall segments")
	var actual := ArenaObstacles.new()
	var reference := ProjectionReference.new()
	actual.bounds = ArenaCatalog.play_bounds(stage_id)
	reference.bounds = actual.bounds
	actual.configure(circles)
	reference.configure(circles)
	actual.configure_walls(source_walls)
	reference.configure_walls(source_walls)
	for radius: float in [13.0, 14.0, 18.0, 22.0]:
		for sample: int in 320:
			var point := Vector2(random.randf_range(-400, 1600), random.randf_range(-900, 1700))
			if sample < source_walls.size():
				var row: Dictionary = source_walls[sample]
				point = Vector2(float(row["a"][0]), float(row["a"][1]))
			elif sample % 3 == 0:
				var row: Dictionary = source_walls[sample % source_walls.size()]
				var start := Vector2(float(row["a"][0]), float(row["a"][1]))
				var end := Vector2(float(row["b"][0]), float(row["b"][1]))
				point = start.lerp(end, 0.43) + Vector2(0.9, 0)
			var inset: float = 0.0 if sample % 2 == 0 else 16.0
			_check(actual.free_point(point, radius, inset) == reference.free_point(point, radius, inset), "The exact original87-wall projection matches the frozen candidate/pair oracle")
	var before: int = int(actual.navigation_stats()["combined_curve_builds"])
	actual.free_point(Vector2(550, 440), 13.0, 0.0)
	actual.set_active("toggle", false)
	reference.set_active("toggle", false)
	_check(not actual.is_free(Vector2(910, 780), 13.0), "The remaining active corner circle supplies a genuinely blocked post-toggle query")
	for point: Vector2 in [Vector2(550, 440), Vector2(550, 405), Vector2(-5000, 5000), Vector2(640, 365), Vector2(910, 780)]:
		_check(actual.free_point(point, 13.0, 0.0) == reference.free_point(point, 13.0, 0.0), "Circle activation invalidates prefiltered intersections without stale projected points")
	_check(int(actual.navigation_stats()["combined_curve_builds"]) > before, "Changing circle state builds a fresh exact curve certificate")
	actual.bounds = actual.bounds.grow(-12.0)
	reference.bounds = actual.bounds
	for sample: int in 80:
		var point := Vector2(random.randf_range(200, 1100), random.randf_range(-300, 1050))
		_check(actual.free_point(point, 14.0, 8.0) == reference.free_point(point, 14.0, 8.0), "Changed bounds and inset cannot reuse a previous domain's intersection validity")
	actual.configure_walls([{"id": "line", "a": [400, -200], "b": [920, 700]},
		{"id": "cross", "a": [300, 650], "b": [970, 20]}, {"id": "point", "a": [500, 300], "b": [500, 300]}])
	reference.configure_walls(actual.walls.snapshot())
	for sample: int in 320:
		var point := Vector2(random.randf_range(250, 1050), random.randf_range(-300, 1100))
		_check(actual.free_point(point, 18.0, 16.0) == reference.free_point(point, 18.0, 16.0), "Crossing lines, zero-length wall caps, circles and bounded outliers preserve the exact original projection")


func _test_wall_cell_corridors() -> void:
	var actual := CorridorProbe.new()
	var reference := ProjectionReference.new()
	actual.bounds = Rect2(0, 0, 768, 512)
	reference.bounds = actual.bounds
	actual.configure([])
	reference.configure([])
	var distant: Array = [{"id": "below", "a": [300, 400], "b": [500, 400]}]
	actual.configure_walls(distant)
	reference.configure_walls(distant)
	var start := Vector2(160, 160)
	var goal := Vector2(600, 160)
	_check(actual.next_target(start, goal, 13.0, 1) == reference.next_target(start, goal, 13.0, 1)
		and actual.corridor_calls == 1 and actual._projected_goals[13.0].open_sources.has(Vector2i(2, 2)), "A full clear hull proves the real original direct result once")
	for from: Vector2 in [Vector2(128, 128), Vector2(191.99, 191.99), Vector2(150, 180), Vector2(180, 140)]:
		for target: Vector2 in [Vector2(576, 128), Vector2(639.99, 191.99), Vector2(580, 185), Vector2(630, 140)]:
			_check(actual.segment_clear(from, target, 13.0)
				and actual.next_target(from, target, 13.0, 2) == reference.next_target(from, target, 13.0, 2), "Every endpoint pair inside a proved wall-cell hull matches the frozen original navigation")
	_check(actual.corridor_calls == 1, "Exact goal movement within the same proved cell preserves the full-hull certificate")
	goal = Vector2(650, 160)
	_check(actual.next_target(start, goal, 13.0, 3) == reference.next_target(start, goal, 13.0, 3) and actual.corridor_calls == 2, "A changed goal cell must establish a distinct wall-hull proof")
	actual.bounds = Rect2(0, 0, 630, 512)
	actual.next_target(start, Vector2(600, 160), 13.0, 4)
	_check(not actual._projected_goals[13.0].open_sources.has(Vector2i(2, 2)), "Writing new bounds invalidates an otherwise cached hull that no longer fits")
	actual.bounds = Rect2(0, 0, 768, 512)
	var fixtures: Array = [
		[{"id": "enclosed", "a": [320, 150], "b": [320, 170]}],
		[{"id": "crossing", "a": [350, 80], "b": [350, 300]}],
		[{"id": "grazing", "a": [200, 115], "b": [400, 115]}],
	]
	for walls: Array in fixtures:
		actual.configure_walls(walls)
		reference.configure_walls(walls)
		_check(not actual._cell_corridor_clear(Vector2i(2, 2), Vector2i(9, 2), 13.0, PackedInt32Array()), "An enclosed capsule, a crossing segment or a near-tangent boundary cannot receive a false full-hull certificate")
		for target: Vector2 in [Vector2(600, 160), Vector2(600, 200), Vector2(620, 240)]:
			_check(actual.next_target(start, target, 13.0, 5) == reference.next_target(start, target, 13.0, 5), "Unproved wall corridors retain the exact original route and waypoint")
	actual.configure([])
	reference.configure([])
	actual.configure_walls(distant)
	reference.configure_walls(distant)
	_check(actual.next_target(start, Vector2(600, 160), 22.0, 6) == reference.next_target(start, Vector2(600, 160), 22.0, 6)
		and actual._projected_goals[22.0].open_sources.has(Vector2i(2, 2)), "Geometry reconfiguration and a distinct collision radius create an independent valid proof")


func _test_exact_projection_queries() -> void:
	var actual: ArenaObstacles = _field(false)
	var reference := ProjectionReference.new()
	reference.bounds = actual.bounds
	reference.configure(actual.snapshot())
	reference.configure_walls(actual.walls.snapshot())
	var query := Vector2(200, 200)
	var expected: Vector2 = reference.free_point(query, 13.0, 0.0)
	_check(not actual.is_free(query, 13.0), "Exact-result reuse starts with a genuinely blocked wall query")
	for repeat: int in 300:
		_check(actual.free_point(query, 13.0, 0.0) == expected, "Repeated blocked coordinates preserve the frozen original exact result")
	var stats: Dictionary = actual.navigation_stats()
	_check(int(stats["combined_queries_solved"]) == 1 and int(stats["combined_query_hits"]) == 299, "Three hundred equal blocked queries run the analytic projection once")
	var changed: Vector2 = query + Vector2(0.125, 0)
	_check(actual.free_point(changed, 13.0, 0.0) == reference.free_point(changed, 13.0, 0.0)
		and int(actual.navigation_stats()["combined_queries_solved"]) == 2, "A0.125-pixel change is a distinct exact query")
	actual.free_point(query, 13.0, 8.0)
	_check(int(actual.navigation_stats()["combined_queries_solved"]) == 3, "A changed inset uses an independent exact result certificate")
	actual.free_point(query, 14.0, 0.0)
	_check(int(actual.navigation_stats()["combined_queries_solved"]) == 4, "A changed body radius recomputes analytic projection")
	actual.bounds = actual.bounds.grow(-4.0)
	reference.bounds = actual.bounds
	_check(actual.free_point(query, 13.0, 0.0) == reference.free_point(query, 13.0, 0.0)
		and int(actual.navigation_stats()["combined_queries_solved"]) == 5, "Changing bounds cannot reuse a prior domain's exact result")
	actual.set_active("switch", false)
	reference.set_active("switch", false)
	_check(not actual.is_free(query, 13.0) and actual.free_point(query, 13.0, 0.0) == reference.free_point(query, 13.0, 0.0)
		and int(actual.navigation_stats()["combined_queries_solved"]) == 6, "Circle activation invalidates the result even when this wall query remains blocked")
	var returned: Vector2 = actual.free_point(query, 13.0, 0.0)
	returned.x = -9999.0
	_check(actual.free_point(query, 13.0, 0.0) == expected, "A caller's Vector2 edit cannot mutate the cached exact result")
	for index: int in range(ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT + 2):
		actual.free_point(Vector2(200, 150.0 + float(index) / 100.0), 13.0, 0.0)
	_check(actual._combined_curve_cache[13.0][0.0].query_results.size() <= ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT, "Moving exact projection queries cannot grow the result cache beyond1024 entries")
	actual.configure_walls([])
	_check(actual.free_point(query, 13.0, 0.0) == query and actual._combined_curve_cache.is_empty(), "Removing the wall discards all formerly blocked exact results")
	var sealed := ArenaObstacles.new()
	sealed.bounds = Rect2(0, 0, 20, 20)
	sealed.configure([])
	sealed.configure_walls([{"id": "sealed", "a": [0, 10], "b": [20, 10]}])
	var sealed_reference := ProjectionReference.new()
	sealed_reference.bounds = sealed.bounds
	sealed_reference.configure([])
	sealed_reference.configure_walls(sealed.walls.snapshot())
	var impossible: Vector2 = sealed_reference.free_point(Vector2(10, 10), 50.0, 0.0)
	_check(impossible == Vector2.INF, "The bounded capsule fixture truly has no free point")
	for repeat: int in 300:
		_check(sealed.free_point(Vector2(10, 10), 50.0, 0.0) == impossible, "Cached infinity retains the exact original no-solution result")
	_check(int(sealed.navigation_stats()["combined_queries_solved"]) == 1 and int(sealed.navigation_stats()["combined_query_hits"]) == 299, "A no-solution result also uses one exact analytic query")


func _test_known_free_points() -> void:
	var actual := KnownFreeProbe.new()
	var reference := ProjectionReference.new()
	actual.bounds = Rect2(0, 0, 400, 400)
	reference.bounds = actual.bounds
	var circles: Array = [{"id": "switch", "center": Vector2(50, 50), "radius": 18.0}]
	var walls: Array = [{"id": "divider", "a": [200, 100], "b": [200, 300]}]
	actual.configure(circles)
	reference.configure(circles)
	actual.configure_walls(walls)
	reference.configure_walls(walls)
	var free := Vector2(100, 140)
	_check(actual.free_point(free, 13.0, 0.0) == free and actual._combined_curve_cache.is_empty(), "An ordinary free query does not force construction of a combined geometry certificate")
	var query := Vector2(200, 200)
	var projected: Vector2 = actual.free_point(query, 13.0, 0.0)
	_check(projected == reference.free_point(query, 13.0, 0.0), "The original analytic projection supplies the known-free output")
	var before_checks: int = actual.free_checks
	for repeat: int in 300:
		_check(actual.free_point(projected, 13.0, 0.0) == projected, "An exactly repeated validated point stays unchanged")
	_check(actual.free_checks == before_checks and int(actual.navigation_stats()["known_free_hits"]) == 300, "The projected output reuses its certificate without another physical free check")
	actual.free_point(free, 13.0, 0.0)
	var after_first: int = actual.free_checks
	_check(actual.free_point(free, 13.0, 0.0) == free and actual.free_checks == after_first, "A free query verified inside an existing certificate is remembered independently")
	actual.free_point(free + Vector2(0.125, 0), 13.0, 0.0)
	_check(actual.free_checks == after_first + 1, "Known-free results never quantize a0.125-pixel coordinate change")
	actual.free_point(free, 14.0, 0.0)
	actual.free_point(free, 13.0, 8.0)
	_check(actual.free_checks == after_first + 3, "Different exact body radii and insets revalidate free positions")
	var before_pool: int = actual._combined_curve_cache[13.0][0.0].query_results.size()
	for index: int in range(ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT + 2):
		actual.free_point(Vector2(20, 120.0 + float(index) / 100.0), 13.0, 0.0)
	_check(actual._combined_curve_cache[13.0][0.0].known_free_points.size() <= ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT
		and actual._combined_curve_cache[13.0][0.0].query_results.size() == before_pool, "The independent1024-entry free pool cannot evict hot blocked-query results")
	actual.free_point(free, 13.0, 0.0)
	_check(actual._combined_curve_cache[13.0][0.0].known_free_points.has(free), "The bounds invalidation fixture holds an actual known-free cache entry")
	actual.bounds = actual.bounds.grow(-4.0)
	reference.bounds = actual.bounds
	before_checks = actual.free_checks
	_check(actual.free_point(free, 13.0, 0.0) == reference.free_point(free, 13.0, 0.0) and actual.free_checks > before_checks, "A bounds change cannot reuse old known-free evidence")
	actual.set_active("switch", false)
	reference.set_active("switch", false)
	actual.free_point(query, 13.0, 0.0)
	_check(actual.free_point(Vector2(50, 50), 13.0, 0.0) == Vector2(50, 50), "A disabled circle exposes a genuinely free point for the new certificate")
	actual.set_active("switch", true)
	reference.set_active("switch", true)
	_check(actual.free_point(Vector2(50, 50), 13.0, 0.0) == reference.free_point(Vector2(50, 50), 13.0, 0.0)
		and actual.free_point(Vector2(50, 50), 13.0, 0.0) != Vector2(50, 50), "Reactivating a circle invalidates a previously known free point")
	actual.free_point(free, 13.0, 0.0)
	_check(actual._combined_curve_cache[13.0][0.0].known_free_points.has(free), "The source-wall invalidation fixture holds an actual known-free cache entry")
	actual.configure_walls([{"id": "replacement", "a": [100, 100], "b": [100, 300]}])
	reference.configure_walls(actual.walls.snapshot())
	_check(actual.free_point(free, 13.0, 0.0) == reference.free_point(free, 13.0, 0.0) and actual.free_point(free, 13.0, 0.0) != free, "A replaced source wall cannot reuse a formerly free coordinate")
	var random := RandomNumberGenerator.new()
	random.seed = 2026103111
	for radius: float in [13.0, 14.0, 18.0, 22.0]:
		for sample: int in 100:
			var start := Vector2(random.randf_range(-100, 500), random.randf_range(-100, 500))
			var movement := Vector2(random.randf_range(-180, 180), random.randf_range(-180, 180))
			var slide: bool = sample % 2 == 0
			_check(actual.move_body(start, movement, radius, 8.0, slide) == reference.move_body(start, movement, radius, 8.0, slide), "Independent known-free caching preserves complete frozen movement outputs for changed starts, directions, radii and slide states")
	actual.configure([])
	_check(actual._combined_curve_cache.is_empty() and actual.free_point(free, 13.0, 0.0) == free, "Full geometry configuration releases all known-free certificates")


func _test_safe_cell_movement() -> void:
	var actual := ArenaObstacles.new()
	var reference := ProjectionReference.new()
	actual.bounds = Rect2(0, 0, 400, 400)
	reference.bounds = actual.bounds
	var circles: Array = [{"id": "switch", "center": Vector2(50, 50), "radius": 18.0}]
	var walls: Array = [{"id": "far", "a": [300, 100], "b": [300, 300]}]
	actual.configure(circles)
	reference.configure(circles)
	actual.configure_walls(walls)
	reference.configure_walls(walls)
	var random := RandomNumberGenerator.new()
	random.seed = 2026103113
	for radius: float in [13.0, 14.0, 18.0, 22.0]:
		for sample: int in 120:
			var start := Vector2(random.randf_range(140, 180), random.randf_range(140, 180))
			var movement := Vector2(random.randf_range(-2, 2), random.randf_range(-2, 2))
			if movement.length_squared() <= 0.000001:
				movement = Vector2(1, 0)
			var slide: bool = sample % 2 == 0
			_check(actual.move_body(start, movement, radius, 8.0, slide) == reference.move_body(start, movement, radius, 8.0, slide), "A certified empty convex cell preserves the complete frozen movement result for ordinary and locked-charge motion")
	_check(int(actual.navigation_stats()["safe_cell_move_hits"]) == 480, "All480 truly empty-cell moves use the proven fast path without dropping movement")
	var hits: int = int(actual.navigation_stats()["safe_cell_move_hits"])
	var start := Vector2(160, 160)
	var tiny := Vector2(0.0001, 0)
	_check(actual.move_body(start, tiny, 13.0, 8.0) == reference.move_body(start, tiny, 13.0, 8.0)
		and actual.move_body(start, tiny, 13.0, 8.0) == start, "The fast path preserves the original sub-threshold no-motion rule")
	_check(actual.move_body(Vector2(191.5, 160), Vector2(1, 0), 13.0) == reference.move_body(Vector2(191.5, 160), Vector2(1, 0), 13.0)
		and int(actual.navigation_stats()["safe_cell_move_hits"]) == hits, "Crossing a grid boundary falls back without treating an uncertified cell as blocked")
	actual.bounds = Rect2(140, 140, 260, 260)
	reference.bounds = actual.bounds
	_check(actual.move_body(start, Vector2(1, 0), 13.0, 8.0) == reference.move_body(start, Vector2(1, 0), 13.0, 8.0)
		and int(actual.navigation_stats()["safe_cell_move_hits"]) == hits, "A changed domain invalidates a cached cell that is no longer wholly enclosed")
	actual.bounds = Rect2(0, 0, 400, 400)
	reference.bounds = actual.bounds
	_check(actual.move_body(Vector2(170, 170), Vector2(1, 0), 13.0, 160.0) == reference.move_body(Vector2(170, 170), Vector2(1, 0), 13.0, 160.0)
		and int(actual.navigation_stats()["safe_cell_move_hits"]) == hits, "A changed inset keeps its own whole-domain proof")
	actual.move_body(Vector2(220, 160), Vector2(1, 0), 13.0)
	hits = int(actual.navigation_stats()["safe_cell_move_hits"])
	_check(actual.move_body(Vector2(220, 160), Vector2(1, 0), 50.0) == reference.move_body(Vector2(220, 160), Vector2(1, 0), 50.0)
		and int(actual.navigation_stats()["safe_cell_move_hits"]) == hits, "A larger radius cannot reuse a smaller body's safe-cell proof")
	actual.configure_walls([{"id": "near-tangent", "a": [205, 100], "b": [205, 300]}])
	reference.configure_walls(actual.walls.snapshot())
	_check(actual.move_body(start, Vector2(1, 0), 13.0) == reference.move_body(start, Vector2(1, 0), 13.0)
		and int(actual.navigation_stats()["safe_cell_move_hits"]) == hits, "A capsule touching the cell's expanded boundary rejects only the fast-path proof")
	for slide: bool in [false, true]:
		_check(actual.move_body(Vector2(180, 160), Vector2(80, 30), 13.0, 0.0, slide) == reference.move_body(Vector2(180, 160), Vector2(80, 30), 13.0, 0.0, slide), "A real wall hit retains exact contact and slide or locked-charge stopping")
		_check(actual.move_body(Vector2(390, 160), Vector2(30, 10), 13.0, 0.0, slide) == reference.move_body(Vector2(390, 160), Vector2(30, 10), 13.0, 0.0, slide), "A bounds crossing retains the complete original boundary sweep")
	actual.configure([{"id": "center", "center": start, "radius": 12.0}])
	reference.configure(actual.snapshot())
	actual.configure_walls(walls)
	reference.configure_walls(walls)
	actual.set_active("center", false)
	reference.set_active("center", false)
	_check(actual.move_body(start, Vector2(1, 0), 13.0) == reference.move_body(start, Vector2(1, 0), 13.0), "A disabled center obstacle allows a newly certified empty cell")
	hits = int(actual.navigation_stats()["safe_cell_move_hits"])
	actual.set_active("center", true)
	reference.set_active("center", true)
	_check(actual.move_body(start, Vector2(1, 0), 13.0) == reference.move_body(start, Vector2(1, 0), 13.0)
		and int(actual.navigation_stats()["safe_cell_move_hits"]) == hits, "Activating a circle invalidates the safe cell before resolving an initially overlapping body")
	for invalid_start: Vector2 in [Vector2.INF, Vector2(1e30, 1e30)]:
		_check(actual.move_body(invalid_start, Vector2(1, 0), 13.0) == reference.move_body(invalid_start, Vector2(1, 0), 13.0), "Nonfinite and oversized coordinates never enter the grid fast path")
	actual.configure([])
	_check(actual._safe_move_cells.is_empty(), "Full geometry reconfiguration releases every safe-cell certificate")


func _test_safe_cell_boundary_endpoints() -> void:
	var actual := ArenaObstacles.new()
	var reference := ProjectionReference.new()
	var far_wall: Array = [{"id": "far", "a": [200, 200], "b": [220, 200]}]
	for inset: float in [0.0, 8.0, 16.0]:
		actual.bounds = Rect2(-inset, -inset, 256.0 + inset * 2.0, 256.0 + inset * 2.0)
		reference.bounds = actual.bounds
		actual.configure([])
		reference.configure([])
		actual.configure_walls(far_wall)
		reference.configure_walls(far_wall)
		var starts: Array[Vector2] = [Vector2(10, 32), Vector2(32, 10), Vector2(246, 32), Vector2(32, 246)]
		var motions: Array[Vector2] = [Vector2(-10, 0), Vector2(0, -10), Vector2(10, 0), Vector2(0, 10)]
		for slide: bool in [false, true]:
			for index: int in starts.size():
				var expected: Vector2 = reference.move_body(starts[index], motions[index], 2.0, inset, slide)
				var before_hits: int = int(actual.navigation_stats()["safe_cell_move_hits"])
				_check(actual.move_body(starts[index], motions[index], 2.0, inset, slide) == expected,
					"All four exact boundary endpoints preserve the frozen t==1 sweep and SKIN retreat for each inset and slide state")
				_check(expected != starts[index] + motions[index] and int(actual.navigation_stats()["safe_cell_move_hits"]) == before_hits,
					"A boundary endpoint cannot skip the original sweep even when its entire source cell is otherwise free")
		_check(actual.move_body(Vector2(10, 32), Vector2(-9, 0), 2.0, inset) == Vector2(1, 32)
			and int(actual.navigation_stats()["safe_cell_move_hits"]) > 0, "A strictly interior near-boundary move still uses the proven empty-cell fast path")


func _test_proven_wall_movement() -> void:
	var actual := ArenaObstacles.new()
	var reference := ProjectionReference.new()
	actual.bounds = Rect2(0, 0, 400, 400)
	reference.bounds = actual.bounds
	actual.configure([])
	reference.configure([])
	var divider: Array = [{"id": "divider", "a": [200, 0], "b": [200, 400]}]
	actual.configure_walls(divider)
	reference.configure_walls(divider)
	for slide: bool in [true, false]:
		for index: int in 20:
			var start := Vector2(180, 140 + index)
			var movement := Vector2(0, 2)
			_check(actual.move_body(start, movement, 13.0, 8.0, slide) == reference.move_body(start, movement, 13.0, 8.0, slide), "A real near-wall sweep preserves the frozen result even when the whole cell cannot be certified")
	_check(int(actual.navigation_stats()["safe_cell_move_hits"]) == 0 and int(actual.navigation_stats()["proven_sweep_move_hits"]) == 40, "All forty exact near-wall clear moves use the fused proof rather than inventing a safe cell")
	var start := Vector2(180, 180)
	for tiny: Vector2 in [Vector2.ZERO, Vector2(0.0001, 0), Vector2(0, -0.0001)]:
		_check(actual.move_body(start, tiny, 13.0) == reference.move_body(start, tiny, 13.0)
			and actual.move_body(start, tiny, 13.0) == start, "A proved tiny clear sweep still retains the original no-displacement threshold")
	var before_hits: int = int(actual.navigation_stats()["proven_sweep_move_hits"])
	_check(actual.move_body(Vector2(200, 180), Vector2.ZERO, 13.0) == reference.move_body(Vector2(200, 180), Vector2.ZERO, 13.0)
		and actual.move_body(Vector2(200, 180), Vector2.ZERO, 13.0) != Vector2(200, 180)
		and int(actual.navigation_stats()["proven_sweep_move_hits"]) == before_hits, "An overlapping start is projected by the original solver even with zero requested movement")
	for slide: bool in [false, true]:
		for pair: Array in [[Vector2(10, 32), Vector2(-10, 0)], [Vector2(32, 10), Vector2(0, -10)],
			[Vector2(390, 32), Vector2(10, 0)], [Vector2(32, 390), Vector2(0, 10)]]:
			_check(actual.move_body(pair[0], pair[1], 2.0, 0.0, slide) == reference.move_body(pair[0], pair[1], 2.0, 0.0, slide), "The fused sweep cannot bypass the original exact-boundary SKIN retreat")
	_check(int(actual.navigation_stats()["proven_sweep_move_hits"]) == before_hits, "All boundary endpoints are excluded from the positive fused movement proof")
	actual.configure([{"id": "disabled", "center": Vector2(50, 50), "radius": 18.0}])
	reference.configure(actual.snapshot())
	actual.configure_walls(divider)
	reference.configure_walls(divider)
	actual.set_active("disabled", false)
	reference.set_active("disabled", false)
	_check(actual.move_body(start, Vector2(0, 2), 13.0) == reference.move_body(start, Vector2(0, 2), 13.0)
		and int(actual.navigation_stats()["proven_sweep_move_hits"]) == 0, "Even an inactive circle keeps mixed-geometry movement on the original threshold semantics")
	var stage_id: String = "wf_main_4_4_4_l0"
	actual.bounds = ArenaCatalog.play_bounds(stage_id)
	reference.bounds = actual.bounds
	actual.configure([])
	reference.configure([])
	var source: Array[Dictionary] = ArenaCatalog.wall_geometry(stage_id)
	actual.configure_walls(source)
	reference.configure_walls(source)
	var random := RandomNumberGenerator.new()
	random.seed = 2026103117
	for radius: float in [13.0, 14.0, 18.0, 22.0]:
		for sample: int in 120:
			var point := Vector2(random.randf_range(150, 1100), random.randf_range(-400, 1100))
			if sample < source.size():
				point = Vector2(float(source[sample]["a"][0]), float(source[sample]["a"][1]))
			var movement := Vector2(random.randf_range(-24, 24), random.randf_range(-24, 24))
			var inset: float = 0.0 if sample % 2 == 0 else 16.0
			var slide: bool = sample % 3 != 0
			_check(actual.move_body(point, movement, radius, inset, slide) == reference.move_body(point, movement, radius, inset, slide), "Four hundred eighty real87-wall movements preserve the complete frozen contact, projection and charge result")
	for pair: Array in [[Vector2.INF, Vector2(1, 0)], [Vector2(640, 365), Vector2.INF], [Vector2(1e30, -1e30), Vector2(-1, 1)]]:
		_check(actual.move_body(pair[0], pair[1], 13.0) == reference.move_body(pair[0], pair[1], 13.0), "Nonfinite and oversized movement inputs remain on the complete original solver")


func _test_closed_barrier_certificates() -> void:
	var actual := ArenaObstacles.new()
	var reference := ProjectionReference.new()
	var stage_id: String = "wf_main_4_4_4_l0"
	actual.bounds = ArenaCatalog.play_bounds(stage_id)
	reference.bounds = actual.bounds
	actual.configure([])
	reference.configure([])
	var source: Array[Dictionary] = ArenaCatalog.wall_geometry(stage_id)
	actual.configure_walls(source)
	reference.configure_walls(source)
	var before: Array[Dictionary] = actual.walls.snapshot()
	var goal := Vector2(640, 365)
	for radius: float in [13.0, 14.0, 18.0, 22.0]:
		_check(actual._closed_barriers(radius).size() == 9, "Only nine real continuous chains have their omitted closing chord covered by existing endpoint caps")
		for start: Vector2 in [Vector2(511, 329), Vector2(497, 262)]:
			_check(actual.is_free(start, radius) and actual.is_free(goal, radius), "The real rock-interior and exterior query points are both valid free body centers")
			_check(reference._build_route(start, goal, radius).is_empty(), "The frozen complete visibility graph confirms the original inside-outside route is empty")
			var hits: int = int(actual.navigation_stats()["barrier_route_rejections"])
			_check(actual.next_target(start, goal, radius, 100 + int(radius)) == reference.next_target(start, goal, radius, 100 + int(radius))
				and int(actual.navigation_stats()["barrier_route_rejections"]) == hits + 1, "A proved closed original capsule chain skips only the same empty route at the original rebuild point")
	_check(actual.walls.snapshot() == before and actual._wall_rows == before and before.size() == 87, "Barrier certificates never append closing collision segments or change the original source-wall snapshot")
	actual.bounds = Rect2(0, 0, 400, 400)
	reference.bounds = actual.bounds
	actual.configure([])
	reference.configure([])
	var ring: Array = [
		{"id": "0:42:0", "a": [70, 70], "b": [130, 70]},
		{"id": "0:42:1", "a": [130, 70], "b": [130, 130]},
		{"id": "0:42:2", "a": [130, 130], "b": [70, 130]},
		{"id": "0:42:3", "a": [70, 130], "b": [70, 74]},
		{"id": "0:43:0", "a": [165, 115], "b": [165, 165]},
	]
	actual.configure_walls(ring)
	reference.configure_walls(ring)
	var start := Vector2(190, 190)
	var old_goal := Vector2(150, 100)
	var first: Vector2 = actual.next_target(start, old_goal, 13.0, 7)
	_check(first == reference.next_target(start, old_goal, 13.0, 7) and not (actual._routes[7].path as PackedVector2Array).is_empty(), "The stale-path fixture first builds a genuine reachable detour outside the original closed capsule ring")
	var moved_goal := Vector2(110, 100)
	_check(actual._closed_barrier_separates(start, moved_goal, 13.0) and old_goal.distance_to(moved_goal) < 48.0, "The new projected goal crosses into another component within the original tail-retarget threshold")
	var before_rejections: int = int(actual.navigation_stats()["barrier_route_rejections"])
	_check(actual.next_target(start, moved_goal, 13.0, 7) == reference.next_target(start, moved_goal, 13.0, 7)
		and not (actual._routes[7].path as PackedVector2Array).is_empty()
		and int(actual.navigation_stats()["barrier_route_rejections"]) == before_rejections,
		"The certificate cannot interrupt an old positive path that the frozen original navigation still follows")
	var open_ring: Array = ring.duplicate(true)
	open_ring[3]["b"] = [70, 110]
	actual.configure_walls(open_ring)
	_check(not actual._closed_barrier_separates(Vector2(100, 100), Vector2(180, 100), 13.0), "An endpoint gap larger than the conservative radius leaves reachability unknown")
	var broken: Array = ring.duplicate(true)
	broken[2]["a"] = [129, 130]
	actual.configure_walls(broken)
	_check(not actual._closed_barrier_separates(Vector2(100, 100), Vector2(180, 100), 13.0), "A discontinuous original source chain cannot receive a closure certificate")
	actual.configure([{"id": "far-circle", "center": Vector2(330, 330), "radius": 18.0}])
	actual.configure_walls(ring)
	_check(actual._closed_barrier_separates(Vector2(100, 100), Vector2(180, 100), 13.0), "A valid capsule ring remains a sufficient obstruction when unrelated circle geometry is present")
	actual.set_active("far-circle", false)
	_check(actual._closed_barrier_cache.is_empty(), "Circle state changes invalidate cached closure certificates")
	actual._closed_barrier_separates(Vector2(100, 100), Vector2(180, 100), 13.0)
	actual.bounds = Rect2(10, 10, 380, 380)
	actual._sync_navigation_bounds()
	_check(actual._closed_barrier_cache.is_empty(), "Changing actual navigation bounds invalidates closure certificates before projected goals are reused")
	_check(not actual._closed_barrier_separates(Vector2(100, 100), Vector2(180, 100), 0.5)
		and not actual._closed_barrier_separates(Vector2(100, 100), Vector2(180, 100), 128.0)
		and not actual._closed_barrier_separates(Vector2(100, 100), Vector2.INF, 13.0), "Unsupported radii and nonfinite points remain unknown rather than receiving a false no-path result")
	actual.configure([])
	_check(actual._closed_barrier_cache.is_empty(), "A new arena releases every cached topology certificate")


func _vertex_graph(points: Array[Vector2]) -> AStar2D:
	var graph := AStar2D.new()
	for index: int in points.size():
		graph.add_point(index, points[index])
	return graph


func _test_goal_cell_vertex_proofs() -> void:
	var actual := ArenaObstacles.new()
	var reference := ProjectionReference.new()
	actual.bounds = Rect2(0, 0, 768, 512)
	reference.bounds = actual.bounds
	actual.configure([])
	reference.configure([])
	var divider: Array = [{"id": "divider", "a": [400, 0], "b": [400, 512]}]
	actual.configure_walls(divider)
	reference.configure_walls(divider)
	var points: Array[Vector2] = [Vector2(240, 160), Vector2(320, 180), Vector2(500, 160)]
	var ids := PackedInt64Array([0, 1, 2])
	var graph: AStar2D = _vertex_graph(points)
	var old_graph: AStar2D = _vertex_graph(points)
	var goal := Vector2(160, 160)
	var goal_id: int = actual._shared_graph_goal(graph, ids, goal, 13.0)
	reference._shared_graph_goal(old_graph, ids, goal, 13.0)
	_check(graph.get_point_connections(goal_id) == old_graph.get_point_connections(goal_id)
		and graph.are_points_connected(goal_id, 0) and graph.are_points_connected(goal_id, 1)
		and not graph.are_points_connected(goal_id, 2), "The initial fixed-vertex proofs preserve every original goal edge and insertion order")
	var proofs: int = int(actual.navigation_stats()["goal_cell_proofs_checked"])
	var hits: int = int(actual.navigation_stats()["goal_cell_proof_hits"])
	for moved: Vector2 in [Vector2(180, 180), Vector2(128, 128), Vector2(191.99, 191.99)]:
		actual._shared_graph_goal(graph, ids, moved, 13.0)
		reference._shared_graph_goal(old_graph, ids, moved, 13.0)
		_check(graph.get_point_connections(goal_id) == old_graph.get_point_connections(goal_id)
			and int(actual.navigation_stats()["goal_cell_proofs_checked"]) == proofs, "An exact goal moving inside the same proved64-cell keeps the frozen goal-adjacency order")
	_check(int(actual.navigation_stats()["goal_cell_proof_hits"]) >= hits + 6, "Repeated exact goals reuse successful fixed-vertex proofs")
	goal = Vector2(384, 160)
	actual._shared_graph_goal(graph, ids, goal, 13.0)
	reference._shared_graph_goal(old_graph, ids, goal, 13.0)
	_check(graph.get_point_connections(goal_id) == old_graph.get_point_connections(goal_id)
		and graph.are_points_connected(goal_id, 0), "A hull crossing the wall stays unknown and retains a visible edge through the original exact segment query")
	actual.configure([{"id": "toggle", "center": Vector2(250, 160), "radius": 20.0}])
	actual.configure_walls(divider)
	actual._fixed_vertex_goal_cell_clear(Vector2(160, 160), points[0], 13.0)
	_check(not actual._goal_cell_proofs.is_empty() and actual.set_active("toggle", false) and actual._goal_cell_proofs.is_empty(), "Circle activation invalidates both positive and unknown fixed-vertex proof records")
	actual._fixed_vertex_goal_cell_clear(Vector2(160, 160), points[0], 13.0)
	actual.bounds = Rect2(140, 0, 628, 512)
	actual._sync_navigation_bounds()
	_check(actual._goal_cell_proofs.is_empty() and not actual._fixed_vertex_goal_cell_clear(Vector2(160, 160), points[0], 13.0), "A changed bounds rectangle cannot reuse a whole-cell certificate that is no longer enclosed")
	var stage_id: String = "wf_main_4_4_4_l0"
	actual.bounds = ArenaCatalog.play_bounds(stage_id)
	reference.bounds = actual.bounds
	actual.configure([])
	reference.configure([])
	var source: Array[Dictionary] = ArenaCatalog.wall_geometry(stage_id)
	actual.configure_walls(source)
	reference.configure_walls(source)
	for radius: float in [13.0, 22.0]:
		for target: Vector2 in [Vector2(640, 365), Vector2(650, 370), Vector2(660, 375), Vector2(640, 365)]:
			_check(actual._build_route(Vector2(720, 500), target, radius) == reference._build_route(Vector2(720, 500), target, radius), "Fixed-vertex proof reuse preserves the complete original87-wall A-star path and tie outcome")
	actual.configure_walls([])
	_check(actual._goal_cell_proofs.is_empty(), "Replacing source walls clears all cached fixed-vertex proofs")


func _test_navigation_route_reuse() -> void:
	var defaults := ArenaObstacles.NavigationRoute.new()
	_check(defaults.path.is_empty() and defaults.index == 0 and defaults.goal == Vector2.INF and defaults.start == Vector2.INF
		and defaults.radius == -1.0 and defaults.bounds == Rect2() and not defaults.unreachable,
		"Typed route defaults retain every former missing-dictionary-field value")
	var actual: ArenaObstacles = _field(false)
	var reference := ProjectionReference.new()
	reference.bounds = actual.bounds
	reference.configure(actual.snapshot())
	reference.configure_walls(actual.walls.snapshot())
	var start := Vector2(100, 200)
	var goal := Vector2(300, 200)
	_check(actual.next_target(start, goal, 13.0, 90) == reference.next_target(start, goal, 13.0, 90), "The first typed record produces the frozen original detour")
	var record: ArenaObstacles.NavigationRoute = actual._routes[90]
	var instance: int = record.get_instance_id()
	for tick: int in 300:
		_check(actual.next_target(start, goal, 13.0, 90) == reference.next_target(start, goal, 13.0, 90)
			and (actual._routes[90] as ArenaObstacles.NavigationRoute).get_instance_id() == instance,
			"Repeated non-direct navigation reuses one typed record without changing any waypoint")
	_check(int(actual.navigation_stats()["wall_hint_hits"]) >= 299, "Repeated blocked direct queries recheck their exact source wall instead of traversing every unrelated wall")
	goal = Vector2(300, 260)
	_check(actual.next_target(start, goal, 13.0, 90) == reference.next_target(start, goal, 13.0, 90)
		and actual._routes[90] == record and record.goal == goal, "A moving goal updates the same record while retaining the original tail-retarget result")
	actual.forget_agent(90)
	reference.forget_agent(90)
	_check(not actual._routes.has(90), "Recycling an agent erases its typed route record")
	actual.next_target(start, goal, 13.0, 90)
	_check((actual._routes[90] as ArenaObstacles.NavigationRoute).get_instance_id() != instance, "A reused agent identity obtains independent route storage")
	actual.configure_walls([])
	_check(actual.next_target(start, goal, 13.0, 90) == goal and actual._routes.is_empty(), "Opening a direct route neither retains nor allocates a route record")


func _reference_for(actual: ArenaObstacles) -> ProjectionReference:
	var reference := ProjectionReference.new()
	reference.bounds = actual.bounds
	reference.configure(actual.snapshot())
	reference.configure_walls(actual.walls.snapshot())
	return reference


func _assert_visibility_connections(actual: ArenaObstacles, reference: ProjectionReference, start: Vector2, goal: Vector2, radius: float) -> void:
	var graph: AStar2D = actual._graphs[radius]
	var old_graph: AStar2D = reference._graphs[radius]
	var ids: PackedInt64Array = actual._graph_point_ids[radius]
	_check(ids == reference._graph_point_ids[radius], "Visibility reuse preserves the complete static point order")
	_check(graph.get_point_ids() == old_graph.get_point_ids() and not graph.has_point(ids.size() + 1), "Both route searches remove the same temporary start point")
	_check(graph.get_point_connections(ids.size()) == old_graph.get_point_connections(ids.size()), "Changing or restoring an exact goal preserves every adjacency in original insertion order")
	var cache: ArenaObstacles.GraphVisibilityCache = actual._graph_visibility[radius]
	var expected_goal_ids := PackedInt64Array()
	for id: int in ids:
		if actual.segment_clear(goal, graph.get_point_position(id), radius):
			expected_goal_ids.append(id)
	_check((cache.goals[goal] as PackedInt64Array) == expected_goal_ids, "Goal memoization records original ids order rather than a sorted or shared path")
	var links: ArenaObstacles.StartVisibilityLinks = cache.starts[start]
	var tested := PackedInt64Array()
	var local_ids := PackedInt64Array()
	for id: int in actual._local_start_candidates(start, graph, ids):
		tested.append(id)
		if actual.segment_clear(start, graph.get_point_position(id), radius):
			local_ids.append(id)
			if local_ids.size() >= ArenaObstacles.LOCAL_ROUTE_LINKS:
				break
	_check(links.tested == tested and links.local_ids == local_ids, "Cached start visibility keeps exactly the original tested candidates and first six connected ids")
	if links.has_fallback:
		var fallback_ids := PackedInt64Array()
		for id: int in ids:
			if not tested.has(id) and actual.segment_clear(start, graph.get_point_position(id), radius):
				fallback_ids.append(id)
		_check(links.fallback_ids == fallback_ids, "Cached fallback edges preserve ids order and exclude all originally tested local candidates")
	else:
		_check(links.fallback_ids.is_empty(), "A successful local path does not speculate or prepopulate fallback edges")


func _test_exact_visibility_links() -> void:
	var actual: ArenaObstacles = _field()
	var reference: ProjectionReference = _reference_for(actual)
	var start := Vector2(100, 200)
	var near_goal := Vector2(100, 300)
	var far_goal := Vector2(300, 200)
	var first: PackedVector2Array = actual._build_route(start, near_goal, 13.0)
	_check(not first.is_empty() and first == reference._build_route(start, near_goal, 13.0), "The mixed-circle-and-wall fixture first obtains the frozen successful local path")
	var cache: ArenaObstacles.GraphVisibilityCache = actual._graph_visibility[13.0]
	var links: ArenaObstacles.StartVisibilityLinks = cache.starts[start]
	_check(not links.has_fallback and links.fallback_ids.is_empty(), "A first locally reachable goal leaves fallback visibility genuinely unknown")
	_assert_visibility_connections(actual, reference, start, near_goal, 13.0)
	var checks: int = int(actual.navigation_stats()["start_visibility_checks"])
	var blocked: PackedVector2Array = actual._build_route(start, far_goal, 13.0)
	_check(blocked.is_empty() and blocked == reference._build_route(start, far_goal, 13.0), "The next goal in the disconnected component still invokes and returns the original empty full-graph search")
	_check(cache.starts[start] == links and links.has_fallback and int(actual.navigation_stats()["start_visibility_checks"]) > checks, "The same start reuses local links and lazily computes missing fallback visibility exactly when a later goal requires it")
	_assert_visibility_connections(actual, reference, start, far_goal, 13.0)
	checks = int(actual.navigation_stats()["start_visibility_checks"])
	var goal_checks: int = int(actual.navigation_stats()["goal_visibility_checks"])
	for target: Vector2 in [near_goal, far_goal, near_goal, far_goal]:
		var path: PackedVector2Array = actual._build_route(start, target, 13.0)
		_check(path == reference._build_route(start, target, 13.0), "A/B/A target changes retain every original A-star waypoint, including unreachable answers")
		_assert_visibility_connections(actual, reference, start, target, 13.0)
		if not path.is_empty():
			path[path.size() - 1] += Vector2(7, 11)
			_check(actual._build_route(start, target, 13.0) == reference._build_route(start, target, 13.0), "A caller cannot change a cached route or its cached visibility by editing its returned PackedVector2Array")
	_check(int(actual.navigation_stats()["start_visibility_checks"]) == checks and int(actual.navigation_stats()["goal_visibility_checks"]) == goal_checks, "Exact revisited starts and goals perform no further LOS work across target changes")
	_check(int(actual.navigation_stats()["visible_goal_cache_hits"]) == 4 and int(actual.navigation_stats()["start_link_cache_hits"]) == 5, "Only replayed exact-goal visibility and rebuilt exact-start links increment the new cache counters")
	var before: PackedInt64Array = links.local_ids.duplicate()
	var candidates: PackedInt64Array = actual._local_start_candidates(start, actual._graphs[13.0], actual._graph_point_ids[13.0])
	if not candidates.is_empty():
		candidates[0] = -99
	_check(links.local_ids == before and not links.tested.has(-99), "Transient candidate arrays do not alias the retained tested or connected edge arrays")
	actual.reset_navigation_stats()
	_check(int(actual.navigation_stats()["visible_goal_cache_hits"]) == 0 and int(actual.navigation_stats()["start_link_cache_hits"]) == 0, "Visibility counters reset without changing the cached geometry or connectivity")


func _test_visibility_link_invalidation() -> void:
	var actual: ArenaObstacles = _field()
	var reference: ProjectionReference = _reference_for(actual)
	var start := Vector2(100, 200)
	var goal := Vector2(300, 200)
	for radius: float in [13.0, 14.0, 22.0]:
		_check(actual._build_route(start, goal, radius) == reference._build_route(start, goal, radius), "Distinct exact body radii keep independent frozen visibility results")
	_check(actual._graph_visibility.size() == 3 and actual._graph_visibility[13.0] != actual._graph_visibility[14.0], "Visibility records cannot cross radius keys")
	var original: ArenaObstacles.GraphVisibilityCache = actual._graph_visibility[13.0]
	_check(not actual.configure_walls([{"a": [0, 0], "b": [INF, 1]}]) and actual._graph_visibility[13.0] == original, "Rejected wall configuration atomically preserves the existing valid visibility certificate")
	_check(actual.set_active("switch", true) and actual._graph_visibility[13.0] == original, "Setting an unchanged circle state keeps its valid exact links")
	_check(actual.set_active("switch", false) and actual._graph_visibility.is_empty(), "An actual circle-state change releases every goal and start visibility record")
	reference.set_active("switch", false)
	_check(actual._build_route(start, goal, 13.0) == reference._build_route(start, goal, 13.0), "Circle-state invalidation recomputes the same complete original route")
	actual.bounds = Rect2(0, 0, 400, 399)
	reference.bounds = actual.bounds
	actual._sync_navigation_bounds()
	_check(actual._graph_visibility.is_empty(), "A directly written navigation bound invalidates cached goal and start edges")
	_check(actual._build_route(start, goal, 13.0) == reference._build_route(start, goal, 13.0), "Changed bounds rebuild frozen graph connectivity before any visibility is reused")
	_check(actual.configure_walls([]) and actual._graph_visibility.is_empty(), "Replacing source walls clears the exact visibility caches")
	reference.configure_walls([])
	_check(actual._build_route(start, goal, 13.0) == reference._build_route(start, goal, 13.0), "The empty-wall fast path retains its original A-star result after wall removal")
	actual.configure([{"id": "replacement", "center": Vector2(200, 200), "radius": 25.0}])
	_check(actual._graph_visibility.is_empty(), "A new arena circle configuration releases all exact connectivity records")
	reference.configure(actual.snapshot())
	for target: Vector2 in [goal, Vector2(300, 300), goal]:
		_check(actual._build_route(start, target, 13.0) == reference._build_route(start, target, 13.0), "The original pure-circle graph and all ties remain unchanged when cached across goals")


func _test_visibility_link_limits() -> void:
	var actual := ArenaObstacles.new()
	var graph: AStar2D = actual._graph(13.0)
	var ids: PackedInt64Array = actual._graph_point_ids[13.0]
	for index: int in ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT + 3:
		actual._shared_graph_goal(graph, ids, Vector2(float(index) * 0.125, 300), 13.0)
	var cache: ArenaObstacles.GraphVisibilityCache = actual._graph_visibility[13.0]
	_check(cache.goals.size() <= ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT, "Exact moving-goal visibility is bounded per radius even for empty adjacency lists")
	for index: int in ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT + 3:
		actual._build_route(Vector2(float(index) * 0.125, 100), Vector2(300, 300), 13.0)
	_check(cache.starts.size() <= ArenaObstacles.ROUTE_QUERY_CACHE_LIMIT, "Exact moving-start local and fallback records are bounded per radius")
	for links: ArenaObstacles.StartVisibilityLinks in cache.starts.values():
		_check(links.tested.is_empty() and links.local_ids.is_empty() and links.fallback_ids.is_empty() and links.has_fallback, "An empty static graph caches a genuinely exhausted local and fallback scan without adding fictitious edges")
