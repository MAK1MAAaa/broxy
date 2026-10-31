extends SceneTree
## Optimized boolean queries retain the frozen exhaustive capsule-query contract.

class ProbeWalls extends TerrainWalls:
	var entry_calls: int = 0
	var first_hit_calls: int = 0
	var contact_calls: int = 0
	var fraction_calls: int = 0
	var point_calls: int = 0
	var segment_calls: int = 0
	var free_xy_calls: int = 0

	func _free_xy(x: float, y: float, radius: float) -> bool:
		free_xy_calls += 1
		return super._free_xy(x, y, radius)

	func _fraction(index: int, x: float, y: float) -> float:
		fraction_calls += 1
		return super._fraction(index, x, y)

	func is_free(point: Vector2, radius: float = 0.0, padding: float = 0.0) -> bool:
		point_calls += 1
		return super.is_free(point, radius, padding)

	func segment_clear(start: Vector2, end: Vector2, radius: float = 0.0, padding: float = 0.0) -> bool:
		segment_calls += 1
		return super.segment_clear(start, end, radius, padding)

	func _entry_time(index: int, sx: float, sy: float, dx: float, dy: float, radius: float) -> float:
		entry_calls += 1
		return super._entry_time(index, sx, sy, dx, dy, radius)

	func first_hit(start: Vector2, end: Vector2, radius: float = 0.0, padding: float = 0.0) -> Dictionary:
		first_hit_calls += 1
		return super.first_hit(start, end, radius, padding)

	func _contact(index: int, x: float, y: float, dx: float, dy: float, fraction: float, time: float) -> Dictionary:
		contact_calls += 1
		return super._contact(index, x, y, dx, dy, fraction, time)

class ScriptedEntryWalls extends TerrainWalls:
	var entry_times: PackedFloat64Array = PackedFloat64Array()

	func _entry_time(index: int, _sx: float, _sy: float, _dx: float, _dy: float, _radius: float) -> float:
		return entry_times[index]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_early_boolean_hit()
	_test_analytic_boundaries()
	_test_spatial_order_ties()
	_test_entry_comparison_contract()
	_test_nearest_boundaries()
	_test_navigation_combined()
	_test_point_cache()
	_test_navigation_point_cache()
	_test_point_cache_lifecycle_and_capacity()
	_test_bounds_clear_proofs()
	_test_rejection_hints()
	_test_deterministic_scene()
	_test_reconfiguration_and_extremes()
	print("TerrainWallQueries: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _line(id: String, a: Vector2, b: Vector2) -> Dictionary:
	return {"id": id, "a": a, "b": b}


func _reference_first_hit(walls: TerrainWalls, start: Vector2, end: Vector2, radius: float, padding: float) -> Dictionary:
	if not TerrainWalls._valid_query(start, radius, padding) or not end.is_finite():
		return {}
	var sx: float = float(start.x)
	var sy: float = float(start.y)
	var dx: float = float(end.x) - sx
	var dy: float = float(end.y) - sy
	var clearance: float = radius + padding
	var best: float = INF
	var winner: int = -1
	for index: int in walls._items.size():
		if maxf(sx, sx + dx) < minf(walls._ax[index], walls._bx[index]) - clearance or minf(sx, sx + dx) > maxf(walls._ax[index], walls._bx[index]) + clearance or maxf(sy, sy + dy) < minf(walls._ay[index], walls._by[index]) - clearance or minf(sy, sy + dy) > maxf(walls._ay[index], walls._by[index]) + clearance:
			continue
		var hit: float = walls._entry_time(index, sx, sy, dx, dy, clearance)
		if hit < best:
			best = hit
			winner = index
	if winner < 0:
		return {}
	var x: float = sx + dx * best
	var y: float = sy + dy * best
	return walls._contact(winner, x, y, dx, dy, walls._fraction(winner, x, y), best)


func _reference_free(walls: TerrainWalls, point: Vector2, radius: float, padding: float) -> bool:
	if not TerrainWalls._valid_query(point, radius, padding):
		return false
	var x: float = float(point.x)
	var y: float = float(point.y)
	var clearance: float = radius + padding
	var r2: float = clearance * clearance
	for index: int in walls._items.size():
		if x < minf(walls._ax[index], walls._bx[index]) - clearance or x > maxf(walls._ax[index], walls._bx[index]) + clearance or y < minf(walls._ay[index], walls._by[index]) - clearance or y > maxf(walls._ay[index], walls._by[index]) + clearance:
			continue
		var fraction: float = walls._fraction(index, x, y)
		var dx: float = x - (walls._ax[index] + walls._vx[index] * fraction)
		var dy: float = y - (walls._ay[index] + walls._vy[index] * fraction)
		var distance_squared: float = dx * dx + dy * dy
		if distance_squared < r2 - TerrainWalls.EPSILON or (clearance == 0.0 and distance_squared <= TerrainWalls.EPSILON * TerrainWalls.EPSILON):
			return false
	return true


func _reference_nearest(walls: TerrainWalls, point: Vector2) -> Dictionary:
	if not point.is_finite() or walls._items.is_empty():
		return {}
	var best_index: int = -1
	var best_squared: float = INF
	var best_fraction: float = 0.0
	for index: int in walls._items.size():
		var fraction: float = walls._fraction(index, float(point.x), float(point.y))
		var dx: float = float(point.x) - (walls._ax[index] + walls._vx[index] * fraction)
		var dy: float = float(point.y) - (walls._ay[index] + walls._vy[index] * fraction)
		var distance_squared: float = dx * dx + dy * dy
		if distance_squared < best_squared:
			best_index = index
			best_squared = distance_squared
			best_fraction = fraction
	return walls._contact(best_index, float(point.x), float(point.y), 0.0, 0.0, best_fraction, 0.0)


func _reference_navigation(walls: TerrainWalls, start: Vector2, end: Vector2, radius: float, padding: float) -> bool:
	return _reference_free(walls, start, radius, padding) \
		and _reference_free(walls, end, radius, padding) \
		and _reference_first_hit(walls, start, end, radius, padding).is_empty()


func _compare(walls: TerrainWalls, start: Vector2, end: Vector2, radius: float, padding: float, label: String) -> void:
	var expected: Dictionary = _reference_first_hit(walls, start, end, radius, padding)
	_check(walls.first_hit(start, end, radius, padding) == expected, label + ": first contact preserves exact time, normal, fraction, source identity and input-order ties")
	var valid: bool = TerrainWalls._valid_query(start, radius, padding) and end.is_finite()
	_check(walls.segment_clear(start, end, radius, padding) == (valid and expected.is_empty()), label + ": early boolean query equals the exhaustive contact query")
	_check(walls.is_free(start, radius, padding) == _reference_free(walls, start, radius, padding), label + ": indexed point clearance equals the exhaustive capsule union")
	_check(walls.navigation_clear(start, end, radius, padding) == _reference_navigation(walls, start, end, radius, padding), label + ": one navigation traversal equals both exhaustive endpoint queries and the exact sweep")
	_check(walls.nearest_point(start) == _reference_nearest(walls, start), label + ": indexed nearest preserves every original start-contact field")
	_check(walls.nearest_point(end) == _reference_nearest(walls, end), label + ": indexed nearest preserves every original end-contact field")


func _test_early_boolean_hit() -> void:
	var walls := ProbeWalls.new()
	var rows: Array = []
	for index: int in 87:
		rows.append(_line("coincident_%d" % index, Vector2(100, 0), Vector2(100, 200)))
	_check(walls.configure(rows), "The exact87-wall pressure fixture configures")
	_check(not walls.segment_clear(Vector2(0, 100), Vector2(200, 100), 10), "Boolean visibility detects an actual capsule crossing")
	_check(walls.entry_calls == 1 and walls.first_hit_calls == 0 and walls.contact_calls == 0, "A blocked boolean query performs one exact entry calculation and constructs no full-contact dictionary")
	_check(walls._tree_wall.size() == 173 and walls._tree_escape[0] == 173, "The immutable balanced index includes every source segment once with bounded escape links")
	var hit: Dictionary = walls.first_hit(Vector2(0, 100), Vector2(200, 100), 10)
	_check(hit.get("id") == "coincident_0" and hit.get("segment_index") == 0, "The full query still resolves exact equal-time hits by original input order")
	walls.entry_calls = 0
	_check(walls.segment_clear(Vector2(-3000, -3000), Vector2(-2800, -2700), 30) and walls.entry_calls == 0, "A query outside the complete wall envelope skips all exact contact calculations")


func _test_analytic_boundaries() -> void:
	var walls := TerrainWalls.new()
	_check(walls.configure([_line("vertical", Vector2(100, 0), Vector2(100, 200)), _line("point", Vector2(220, 70), Vector2(220, 70))]), "Endpoint and finite-segment boundary fixture configures")
	var cases: Array[Array] = [
		[Vector2(0, 100), Vector2(300, 100), 10.0, 0.0],
		[Vector2(300, 100), Vector2(0, 100), 10.0, 5.0],
		[Vector2(70, -10), Vector2(130, -10), 10.0, 0.0],
		[Vector2(70, -6), Vector2(130, -6), 10.0, 0.0],
		[Vector2(90, 100), Vector2(80, 100), 10.0, 0.0],
		[Vector2(90, 100), Vector2(90, 120), 10.0, 0.0],
		[Vector2(90, 100), Vector2(110, 100), 10.0, 0.0],
		[Vector2(95, 100), Vector2(80, 100), 10.0, 0.0],
		[Vector2(95, 100), Vector2(110, 100), 10.0, 0.0],
		[Vector2(100, 100), Vector2(100, 100), 0.0, 0.0],
		[Vector2(0, 100), Vector2(300, 100), 0.0, 0.0],
		[Vector2(190, 70), Vector2(250, 70), 10.0, 0.0],
		[Vector2.INF, Vector2.ZERO, 1.0, 0.0],
		[Vector2.ZERO, Vector2.INF, 1.0, 0.0],
		[Vector2.ZERO, Vector2.ONE, -1.0, 0.0],
		[Vector2.ZERO, Vector2.ONE, 1.0, -1.0],
		[Vector2.ZERO, Vector2.ONE, NAN, 0.0],
		[Vector2.ZERO, Vector2.ONE, INF, 0.0],
		[Vector2(NAN, 0), Vector2.ZERO, 1.0, 0.0],
		[Vector2.ZERO, Vector2(0, NAN), 1.0, 0.0],
		[Vector2.ZERO, Vector2.ONE, 1.0, INF],
		[Vector2.ZERO, Vector2.ONE, 1e200, 0.0],
	]
	for index: int in cases.size():
		var row: Array = cases[index]
		_compare(walls, row[0], row[1], row[2], row[3], "boundary/%d" % index)
	_check(walls.segment_clear(Vector2(70, -10), Vector2(130, -10), 10), "A pure tangent remains passable rather than becoming an AABB collision")
	_check(walls.segment_clear(Vector2(95, 100), Vector2(80, 100), 10), "Outward motion from initial overlap stays passable")


func _test_deterministic_scene() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	var rows: Array = []
	for index: int in 87:
		var a := Vector2(rng.randf_range(-1200, 2400), rng.randf_range(-1000, 1800))
		var b: Vector2 = a if index % 9 == 0 else a + Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(15, 420)
		rows.append(_line("source_%d" % index, a, b))
	var walls := TerrainWalls.new()
	_check(walls.configure(rows), "A deterministic mix of87 open, diagonal and degenerate walls configures")
	var before: Array[Dictionary] = walls.snapshot()
	for index: int in 640:
		var start := Vector2(rng.randf_range(-1800, 3000), rng.randf_range(-1500, 2300))
		var end: Vector2 = start if index % 13 == 0 else start + Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(0.01, 5000)
		var radius: float = [0.0, 0.000001, 2.5, 10.0, 30.0][index % 5]
		var padding: float = [0.0, 1.25, 8.0][index % 3]
		_compare(walls, start, end, radius, padding, "mixed87/%d" % index)
	for index: int in 120:
		var start := Vector2(rng.randf_range(-1800, 3000), rng.randf_range(-1500, 2300))
		var end: Vector2 = start + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		_compare(walls, start, end, float(index % 31), 0.125, "local-movement/%d" % index)
	for index: int in rows.size():
		var a: Vector2 = rows[index]["a"]
		var b: Vector2 = rows[index]["b"]
		var direction: Vector2 = (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x) if not direction.is_zero_approx() else Vector2.RIGHT
		var middle: Vector2 = (a + b) * 0.5
		_compare(walls, middle + normal * 24, middle - normal * 24, 8, 0, "every-wall-surface/%d" % index)
	_check(walls.snapshot() == before, "All indexed point and segment queries leave exact source coordinates and ordering unchanged")
	rows.reverse()
	_check(walls.configure(rows), "Reversed source order rebuilds the independent spatial hierarchy")
	for index: int in 40:
		_compare(walls, Vector2(index * 40 - 500, 10), Vector2(1500 - index * 13, 1400), float(index % 17), 0.0, "reversed/%d" % index)


func _test_spatial_order_ties() -> void:
	var walls := TerrainWalls.new()
	_check(walls.configure([_line("input_first", Vector2(100, -20), Vector2(100, 420)), _line("spatial_first", Vector2(100, -20), Vector2(100, 20))]), "Different source centers can share exactly the same swept contact time")
	_check(walls._tree_wall[1] == 1, "This fixture really visits original index1 before index0 in the spatial hierarchy")
	_compare(walls, Vector2.ZERO, Vector2(200, 0), 10, 0, "nonzero-spatial-tie")
	var hit: Dictionary = walls.first_hit(Vector2.ZERO, Vector2(200, 0), 10)
	_check(hit.get("id") == "input_first" and hit.get("segment_index") == 0 and hit.get("t") == 0.45, "A later visited lower input index wins an exact positive-time tie")
	_check(walls.configure([_line("input_first", Vector2(15, 0), Vector2(15, 0)), _line("spatial_first", Vector2(10, 0), Vector2(10, 0))]), "Overlapping point capsules configure in reverse spatial order")
	_check(walls._tree_wall[1] == 1, "The zero-time fixture also forces reversed spatial visitation")
	_compare(walls, Vector2.ZERO, Vector2(100, 0), 20, 0, "zero-spatial-tie")
	hit = walls.first_hit(Vector2.ZERO, Vector2(100, 0), 20)
	_check(hit.get("id") == "input_first" and hit.get("t") == 0.0 and hit.get("wall_point") == Vector2(15, 0), "A zero-time hit cannot terminate the tree before the original first wall has been considered")


func _test_entry_comparison_contract() -> void:
	var walls := ScriptedEntryWalls.new()
	_check(walls.configure([_line("input_first", Vector2(15, 0), Vector2(15, 0)), _line("spatial_first", Vector2(10, 0), Vector2(10, 0))]), "Comparison fixtures use the same reversed spatial traversal")
	var times: Array[PackedFloat64Array] = [
		PackedFloat64Array([NAN, INF]), PackedFloat64Array([INF, NAN]),
		PackedFloat64Array([NAN, 0.5]), PackedFloat64Array([0.5, NAN]),
		PackedFloat64Array([INF, 0.5]), PackedFloat64Array([0.5, INF]),
		PackedFloat64Array([0.5, 0.5]), PackedFloat64Array([0.0, -0.0]),
		PackedFloat64Array([-INF, 0.5]), PackedFloat64Array([0.5, -INF]),
		PackedFloat64Array([-INF, -INF]),
	]
	var expected_indices: Array[int] = [-1, -1, 1, 0, 1, 0, 0, 0, 0, 1, 0]
	for index: int in times.size():
		walls.entry_times = times[index]
		var expected: Dictionary = _reference_first_hit(walls, Vector2.ZERO, Vector2(100, 0), 20, 0)
		var actual: Dictionary = walls.first_hit(Vector2.ZERO, Vector2(100, 0), 20)
		var winner: int = expected_indices[index]
		_check(int(actual.get("segment_index", -1)) == winner and actual.is_empty() == expected.is_empty(), "NaN/positive infinity never replace the current best, and equal times retain original index order")
		if winner >= 0:
			_check(actual["id"] == expected["id"] and PackedFloat64Array([actual["t"]]).to_byte_array() == PackedFloat64Array([expected["t"]]).to_byte_array(), "First-hit comparison preserves signed zero and negative-infinity selection byte-for-byte")
		_check(walls.segment_clear(Vector2.ZERO, Vector2(100, 0), 20) == expected.is_empty(), "Boolean and first-contact paths preserve the same finite/NaN/infinity comparison contract")


func _test_nearest_boundaries() -> void:
	var walls := ProbeWalls.new()
	var rows: Array = []
	for index: int in 87:
		rows.append(_line("separated_%d" % index, Vector2(100 + index * 100, 100), Vector2(100 + index * 100, 200)))
	_check(walls.configure(rows), "Nearest-query pruning has87 spatially separated exact segments")
	var hit: Dictionary = walls.nearest_point(Vector2(100, 100))
	_check(hit.get("segment_index") == 0 and walls.fraction_calls == 1 and walls.contact_calls == 1, "An exact nearest endpoint prunes the other86 projections and constructs only the selected full contact")
	_check(hit == _reference_nearest(walls, Vector2(100, 100)), "Pruned nearest returns the frozen exhaustive result exactly")
	_check(walls.configure([_line("input_first", Vector2(15, 0), Vector2(15, 0)), _line("spatial_first", Vector2(-15, 0), Vector2(-15, 0))]), "Equidistant nearest walls configure in reversed spatial visitation order")
	_check(walls._tree_wall[1] == 1, "The nearest tie really visits original index1 first")
	hit = walls.nearest_point(Vector2.ZERO)
	_check(hit == _reference_nearest(walls, Vector2.ZERO) and hit.get("segment_index") == 0 and hit.get("wall_point") == Vector2(15, 0), "Equal positive nearest distances retain the lower original source index and its own normal")
	_check(walls.configure([
		{"id": "rounded_endpoint", "a": [1.0, 0.0], "b": [5e-17, 0.0]},
		_line("spatial_first", Vector2.ZERO, Vector2.ZERO),
	]), "The endpoint-cancellation fixture retains exact double source coordinates")
	_check(walls._tree_wall[1] == 1 and walls._tree_min_x[2] > 0.0 and walls._nearest_min_x[2] == 0.0, "Nearest bounds enclose a+(b-a) while swept-contact bounds retain the exact source endpoint")
	hit = walls.nearest_point(Vector2.ZERO)
	_check(hit == _reference_nearest(walls, Vector2.ZERO) and hit.get("segment_index") == 0 and hit.get("distance") == 0.0 and hit.get("fraction") == 1.0, "A5e-17 endpoint cancellation cannot falsely prune the original zero-distance winner")
	_check(walls.configure([{"id": "overflow_distance", "a": [1e300, 1e300], "b": [1e300, 1e300]}]), "Finite huge degenerate walls preserve the original distance-overflow path")
	_check(walls.nearest_point(Vector2.ZERO) == _reference_nearest(walls, Vector2.ZERO), "When every squared distance is infinite the original full-contact fallback is unchanged")
	_check(walls.nearest_point(Vector2.INF).is_empty() and walls.nearest_point(Vector2(NAN, 0)).is_empty(), "Nonfinite nearest inputs remain rejected")


func _test_navigation_combined() -> void:
	var walls := ProbeWalls.new()
	_check(walls.configure([_line("vertical", Vector2(100, 0), Vector2(100, 200))]), "The combined navigation fixture configures")
	_check(not walls.navigation_clear(Vector2(0, 100), Vector2(200, 100), 10), "Navigation rejects an exact sweep between two free endpoints")
	_check(walls.entry_calls == 1 and walls.contact_calls == 0 and walls.first_hit_calls == 0 and walls.point_calls == 0 and walls.segment_calls == 0, "Navigation performs its own single traversal without three public queries or contact allocation")
	walls.entry_calls = 0
	_check(not walls.navigation_clear(Vector2(95, 100), Vector2(80, 100), 10) and walls.entry_calls == 0, "An overlapping start is rejected before the outward sweep can report clear")
	_check(walls.segment_clear(Vector2(95, 100), Vector2(80, 100), 10), "The same outward sweep alone is actually clear, proving the start check remains necessary")
	_check(walls.navigation_clear(Vector2(70, -10), Vector2(130, -10), 10), "A purely tangential navigation remains clear")
	_check(walls.navigation_clear(Vector2.ZERO, Vector2.ZERO, 0) and not walls.navigation_clear(Vector2(100, 100), Vector2(100, 100), 0), "Stationary navigation retains the exact free-point and zero-radius collision rules")
	_check(not walls.navigation_clear(Vector2(90, 100), Vector2(80, 100), 10, 0.5), "Padding participates in endpoint overlap rather than only expanding the sweep")
	var endpoint := Vector2(1e-16, 0)
	_check(walls.configure([_line("real_endpoint", endpoint, endpoint)]), "A navigation endpoint can differ from start+(end-start) after double rounding")
	_check(walls.segment_clear(Vector2(1, 0), endpoint) and not walls.is_free(endpoint), "The original segment bbox misses this real endpoint while its independent point check blocks it")
	_check(not walls.navigation_clear(Vector2(1, 0), endpoint), "The combined hierarchy bounds include the real endpoint, not only the reconstructed sweep endpoint")
	_compare(walls, Vector2(1, 0), endpoint, 0, 0, "rounded-navigation-endpoint")


func _test_point_cache() -> void:
	var walls := ProbeWalls.new()
	_check(walls.configure([_line("vertical", Vector2(100, 0), Vector2(100, 200))]), "Exact point-cache fixture configures")
	var before: Array[Dictionary] = walls.snapshot()
	var free_point := Vector2(90, 100)
	var blocked_point := Vector2(95, 100)
	var expected_free: bool = _reference_free(walls, free_point, 10, 0)
	var expected_blocked: bool = _reference_free(walls, blocked_point, 10, 0)
	walls.fraction_calls = 0
	for index: int in 300:
		_check(walls.is_free(free_point, 10) == expected_free and walls.is_free(blocked_point, 10) == expected_blocked, "Repeated exact point queries preserve both frozen boolean results/%d" % index)
	_check(expected_free and not expected_blocked and walls.free_xy_calls == 2 and walls.fraction_calls == 2, "300 repeated free and blocked queries perform only their two original narrow-phase projections")
	_check(walls.is_free(free_point, 8, 2) == expected_free and walls.free_xy_calls == 2, "Equivalent exact radius-plus-padding reuses the same double-clearance bucket")
	_check(walls._point_query_caches.size() == 1 and walls._point_query_caches[10.0].size() == 2 and walls.snapshot() == before, "Point memoization changes neither the source snapshot nor query identities")
	_check(walls.configure([_line("point", Vector2.ZERO, Vector2.ZERO)]), "Sub-float32 clearance fixture configures")
	var smaller: float = 1.00000000025
	var larger: float = 1.000000001
	var point := Vector2(1, 0)
	var smaller_expected: bool = _reference_free(walls, point, smaller, 0)
	var larger_expected: bool = _reference_free(walls, point, larger, 0)
	_check(smaller_expected and not larger_expected, "Two clearances that both round to float32 one have different exact EPS collision results")
	for index: int in 12:
		_check(walls.is_free(point, smaller) == smaller_expected and walls.is_free(point, larger) == larger_expected, "Clearance keys retain double precision rather than quantizing into Vector coordinates/%d" % index)
	_check(walls._point_query_caches.size() == 2, "Different exact float64 clearances remain independent cache buckets")
	var cached_before: Dictionary = walls._point_query_caches.duplicate(true)
	_check(not walls.is_free(Vector2(NAN, 0), smaller) and not walls.is_free(Vector2.INF, smaller), "Nonfinite point inputs are rejected before cache insertion")
	_check(not walls.is_free(point, NAN) and not walls.is_free(point, INF) and not walls.is_free(point, 1, -1) and not walls.is_free(point, 1e200), "Nonfinite, negative or squared-overflow clearances never become keys")
	_check(not walls.navigation_clear(Vector2(NAN, 0), point, smaller) and not walls.navigation_clear(point, Vector2.INF, smaller) and not walls.navigation_clear(point, point, NAN), "Invalid navigation inputs cannot seed endpoint cache entries")
	_check(walls._point_query_caches == cached_before, "Rejected NaN and infinity queries leave all valid exact cache entries unchanged")


func _test_navigation_point_cache() -> void:
	var walls := ProbeWalls.new()
	var rows: Array = [_line("vertical", Vector2(100, 0), Vector2(100, 200))]
	_check(walls.configure(rows), "Endpoint-cache navigation fixture configures")
	var start := Vector2(95, -10)
	var end := Vector2(105, -10)
	var expected: bool = _reference_navigation(walls, start, end, 10, 0)
	_check(expected and walls.is_free(start, 10) and walls.is_free(end, 10), "The exact tangential route starts with two independently proved free endpoints")
	walls.entry_calls = 0
	walls.fraction_calls = 0
	walls.free_xy_calls = 0
	for index: int in 300:
		_check(walls.navigation_clear(start, end, 10) == expected, "Cached endpoints retain the frozen tangential navigation result/%d" % index)
	_check(walls.entry_calls == 300 and walls.fraction_calls == 300 and walls.free_xy_calls == 0, "300 cached-endpoint navigations retain all300 original sweeps while skipping600 redundant endpoint projections")
	_check(not walls.is_free(Vector2(95, 100), 10), "A real point collision can populate a cached false endpoint")
	walls.entry_calls = 0
	walls.fraction_calls = 0
	_check(not walls.navigation_clear(Vector2(95, 100), Vector2(80, 100), 10) and walls.entry_calls == 0 and walls.fraction_calls == 0, "A cached false start rejects outward navigation without declaring the overlapping point free")
	_check(walls.configure(rows), "Cold navigation cache is rebuilt independently")
	walls.fraction_calls = 0
	walls.free_xy_calls = 0
	_check(walls.navigation_clear(start, end, 10) and walls.fraction_calls == 3, "A successful cold navigation performs both original point projections and its exact sweep")
	_check(walls.is_free(start, 10) and walls.is_free(end, 10) and walls.free_xy_calls == 0 and walls.fraction_calls == 3, "Only after full navigation success are both proved endpoint results reusable by point queries")
	_check(walls.configure([
		_line("first_crossing", Vector2(0, -20), Vector2(0, 20)),
		_line("later_blocked_endpoint", Vector2(150, 0), Vector2(150, 0)),
	]), "An early crossing can precede another wall's blocked endpoint in tree order")
	_check(not walls.navigation_clear(Vector2(-10, 0), Vector2(150, 0), 1), "The original crossing still rejects the route before the later endpoint wall is visited")
	var cache: Dictionary = walls._point_query_caches[1.0]
	_check(not cache.has(Vector2(-10, 0)) and not cache.has(Vector2(150, 0)), "A rejected sweep cannot publish unproved true endpoint results")
	_check(not walls.is_free(Vector2(150, 0), 1), "The unvisited endpoint remains correctly blocked after the failed navigation")


func _test_point_cache_lifecycle_and_capacity() -> void:
	var walls := ProbeWalls.new()
	_check(walls.configure([]), "Empty valid geometry supports bounded exact memoization")
	for index: int in TerrainWalls.POINT_CACHE_LIMIT:
		_check(walls.is_free(Vector2(index, 0), 1), "Distinct finite empty-scene query remains free/%d" % index)
	_check(walls._point_query_caches[1.0].size() == TerrainWalls.POINT_CACHE_LIMIT and walls.free_xy_calls == TerrainWalls.POINT_CACHE_LIMIT, "A clearance bucket stores exactly1024 distinct computed results")
	_check(walls.is_free(Vector2(-1, 0), 2), "Another exact clearance has an independent cache")
	var before_calls: int = walls.free_xy_calls
	_check(walls.is_free(Vector2(TerrainWalls.POINT_CACHE_LIMIT, 0), 1), "A query beyond cache capacity retains its original result")
	_check(walls._point_query_caches[1.0].size() == 1 and walls._point_query_caches[2.0].size() == 1 and walls.free_xy_calls == before_calls + 1, "Overflow clears only the full clearance bucket and inserts the one newly computed result")
	_check(walls.is_free(Vector2.ZERO, 1) and walls.free_xy_calls == before_calls + 2 and walls._point_query_caches[1.0].size() == 2, "An evicted exact point is recomputed without stale results")
	_check(walls.configure([]), "Navigation capacity fixture starts without retained query entries")
	for index: int in TerrainWalls.POINT_CACHE_LIMIT - 1:
		walls.is_free(Vector2(index, 0), 1)
	_check(walls.navigation_clear(Vector2(10000, 0), Vector2(10000, 0), 1) and walls._point_query_caches[1.0].size() == TerrainWalls.POINT_CACHE_LIMIT, "A stationary successful route inserts its identical endpoints only once at exact capacity")
	_check(walls.navigation_clear(Vector2(10001, 0), Vector2(10002, 0), 1) and walls._point_query_caches[1.0].size() == 2, "Successful navigation inserts two proved endpoints atomically within the same1024-entry bound")
	_check(walls.configure([_line("old", Vector2(100, 0), Vector2(100, 200))]) and walls._point_query_caches.is_empty(), "Successful configuration clears every previous clearance bucket")
	_check(walls.is_free(Vector2(90, 100), 10), "The old wall's exact boundary point is free before reconfiguration")
	var cached_before: Dictionary = walls._point_query_caches.duplicate(true)
	_check(not walls.configure([{"id": "invalid", "a": [NAN, 0], "b": [1, 2]}]) and walls._point_query_caches == cached_before, "Invalid configuration preserves the unchanged geometry's valid query results")
	_check(walls.configure([_line("new", Vector2(90, 0), Vector2(90, 200))]) and walls._point_query_caches.is_empty(), "A different successful wall configuration invalidates old true and false results")
	_check(not walls.is_free(Vector2(90, 100), 10), "The formerly free point is recalculated against the new blocking wall")
	walls.clear()
	_check(walls._point_query_caches.is_empty() and walls.is_free(Vector2(90, 100), 10), "Clear removes cached collisions along with the geometry")


func _verify_bounds_proof(walls: TerrainWalls, region: Rect2, radius: float, padding: float, rng: RandomNumberGenerator, label: String) -> void:
	var end: Vector2 = region.end
	var points: Array[Vector2] = [region.position, Vector2(end.x, region.position.y), end, Vector2(region.position.x, end.y), region.get_center()]
	for _index: int in 8:
		points.append(Vector2(lerpf(region.position.x, end.x, rng.randf()), lerpf(region.position.y, end.y, rng.randf())))
	for index: int in points.size():
		var start: Vector2 = points[index]
		var target: Vector2 = points[(index + 3) % points.size()]
		_check(_reference_free(walls, start, radius, padding), label + ": every corner, center and random point satisfies the frozen exact point query")
		_check(_reference_first_hit(walls, start, target, radius, padding).is_empty(), label + ": arbitrary internal segments have no frozen exact first contact")
		_check(_reference_navigation(walls, start, target, radius, padding), label + ": positive bounds proof implies the complete original navigation conjunction")


func _test_rejection_hints() -> void:
	var walls := TerrainWalls.new()
	_check(walls.configure([_line("first", Vector2(100, 0), Vector2(100, 200)), _line("far", Vector2(500, 0), Vector2(500, 200))]), "Rejection-hint fixture configures")
	var start := Vector2(50, 100)
	var end := Vector2(150, 100)
	_check(not walls.navigation_clear(start, end, 5) and walls.last_navigation_blocker == 0, "A full rejected query records an actual blocking leaf")
	_check(walls.rejects_sweep(0, start, end, 5), "Rechecking the same exact capsule proves the route blocked")
	_check(not walls.rejects_sweep(1, start, end, 5) and not walls.rejects_sweep(0, start, Vector2(60, 100), 5), "A stale or irrelevant hint is inconclusive and cannot reject an open sweep")
	_check(not walls.rejects_sweep(-1, start, end, 5) and not walls.rejects_sweep(2, start, end, 5), "Missing and out-of-range hint indices remain inconclusive")
	_check(not walls.rejects_sweep(0, Vector2(NAN, 0), end, 5) and not walls.rejects_sweep(0, start, Vector2.INF, 5)
		and not walls.rejects_sweep(0, start, end, -1) and not walls.rejects_sweep(0, start, end, INF), "Invalid coordinates or clearances do not create rejection proofs")
	_check(walls.navigation_clear(start, Vector2(60, 100), 5) and walls.last_navigation_blocker == -1, "A successful query clears the previous blocker receipt")
	var rows: Array[Dictionary] = ArenaCatalog.wall_geometry("wf_main_4_4_4_l0")
	_check(walls.configure(rows) and walls.last_navigation_blocker == -1, "Replacing geometry invalidates the previous blocker receipt")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	var proofs: int = 0
	for index: int in 512:
		start = Vector2(rng.randf_range(280, 1000), rng.randf_range(-275, 1005))
		end = Vector2(rng.randf_range(280, 1000), rng.randf_range(-275, 1005))
		var radius: float = [0.0, 5.0, 13.0, 18.0][index % 4]
		walls.navigation_clear(start, end, radius)
		var hint: int = walls.last_navigation_blocker if walls.last_navigation_blocker >= 0 else index % rows.size()
		if walls.rejects_sweep(hint, start, end, radius):
			proofs += 1
			_check(not _reference_navigation(walls, start, end, radius, 0), "A single-wall hint implies the exhaustive original navigation is rejected/%d" % index)
	_check(proofs > 200, "Real-map hint coverage includes substantial exact rejected queries")
	walls.clear()
	_check(walls.last_navigation_blocker == -1 and not walls.rejects_sweep(0, start, end, 13), "Cleared geometry cannot reuse any previous wall index")


func _test_bounds_clear_proofs() -> void:
	var walls := ProbeWalls.new()
	_check(walls.configure([_line("vertical", Vector2(100, 0), Vector2(100, 200)), _line("point", Vector2(220, 70), Vector2(220, 70))]), "Conservative region-proof fixture configures")
	var free_region := Rect2(0, 10, 64, 64)
	_check(walls.bounds_clear(free_region, 10), "A complete region outside all expanded source-wall bounds is proved free")
	_check(not walls.bounds_clear(Rect2(26, 10, 64, 64), 10), "Touching an expanded wall bound cannot produce a positive proof")
	_check(not walls.bounds_clear(Rect2(90, -30, 20, 20), 10), "A capsule-end bounding-box tangent remains conservatively unproved")
	_check(not walls.bounds_clear(free_region, 10, 30), "Padding expands source wall bounds for the complete region proof")
	_check(not walls.bounds_clear(Rect2(100, 0, 20, 20), 0), "Zero-radius wall contact on a closed region boundary remains unproved")
	var corner_region := Rect2(229, 79, 2, 2)
	_check(not walls.bounds_clear(corner_region, 10) and _reference_free(walls, corner_region.position, 10, 0), "An overlapping AABB returns only an inconclusive false rather than inventing a capsule collision")
	_check(walls.entry_calls == 0 and walls.contact_calls == 0 and walls.free_xy_calls == 0 and walls.point_calls == 0 and walls.segment_calls == 0, "Region proofs use only the spatial hierarchy without full point, sweep or contact queries")
	var source_before: Array[Dictionary] = walls.snapshot()
	var cache_before: Dictionary = walls._point_query_caches.duplicate(true)
	var invalid_regions: Array[Rect2] = [
		Rect2(0, 0, 0, 64), Rect2(0, 0, 64, 0), Rect2(0, 0, -1, 64), Rect2(0, 0, 64, -1),
		Rect2(Vector2(NAN, 0), Vector2(64, 64)), Rect2(Vector2.INF, Vector2(64, 64)),
		Rect2(Vector2.ZERO, Vector2(NAN, 64)), Rect2(Vector2.ZERO, Vector2(64, INF)),
		Rect2(Vector2(3e38, 0), Vector2(3e38, 64)), Rect2(Vector2(1e30, 0), Vector2(1, 64)),
	]
	for index: int in invalid_regions.size():
		_check(not walls.bounds_clear(invalid_regions[index], 10), "Nonfinite, nonpositive or rounded-empty region is never proved free/%d" % index)
	_check(not walls.bounds_clear(free_region, NAN) and not walls.bounds_clear(free_region, INF) and not walls.bounds_clear(free_region, -1) and not walls.bounds_clear(free_region, 1e200), "Invalid or squared-overflow radii cannot produce free-region proofs")
	_check(not walls.bounds_clear(free_region, 1, NAN) and not walls.bounds_clear(free_region, 1, INF) and not walls.bounds_clear(free_region, 1, -1), "Padding validation matches the original finite nonnegative query contract")
	_check(walls.snapshot() == source_before and walls._point_query_caches == cache_before, "Region proofs and rejected inputs mutate neither source geometry nor memoized point results")
	_check(walls.configure([{"id": "rounding_gap", "a": [2e-17, 0.0], "b": [2e-17, 0.0]}]), "A source point can lie just outside a tiny nonzero region boundary")
	var cancellation_region := Rect2(Vector2(5e-17, 0), Vector2(1, 1))
	_check(not _reference_first_hit(walls, Vector2(1, 0), cancellation_region.position, 0, 0).is_empty(), "The frozen sweep can reconstruct its tiny endpoint outside the nominal region after cancellation")
	_check(not walls.bounds_clear(cancellation_region, 0), "The region proof conservatively encloses double-rounding drift instead of accepting the nominal AABB gap")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026103102
	var rows: Array = []
	for index: int in 87:
		var a := Vector2(rng.randf_range(-1200, 2400), rng.randf_range(-1000, 1800))
		var b: Vector2 = a if index % 9 == 0 else a + Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(15, 420)
		rows.append(_line("proof_wall_%d" % index, a, b))
	_check(walls.configure(rows), "Deterministic87-wall positive-proof regression fixture configures")
	var positive_regions: int = 0
	for index: int in 160:
		var region := Rect2(Vector2(rng.randf_range(-1600, 2800), rng.randf_range(-1400, 2200)), Vector2([32, 64, 96][index % 3], [32, 64, 96][(index + 1) % 3]))
		var radius: float = [0.0, 2.5, 10.0, 30.0][index % 4]
		var padding: float = [0.0, 0.125, 8.0][index % 3]
		if walls.bounds_clear(region, radius, padding):
			positive_regions += 1
			_verify_bounds_proof(walls, region, radius, padding, rng, "positive-region/%d" % index)
	_check(positive_regions >= 16, "The mixed real-wall regression checks numerous positive regions rather than vacuously rejecting all cells")
	walls.clear()
	_check(walls.bounds_clear(free_region, 10), "Clearing geometry removes every old obstacle from region proofs")
	_check(walls.configure([_line("replacement", Vector2(32, 0), Vector2(32, 200))]) and not walls.bounds_clear(free_region, 10), "Successful replacement rebuilds region proofs against the new source walls")
	_check(not walls.configure([{"id": "invalid", "a": [NAN, 0], "b": [1, 2]}]) and not walls.bounds_clear(free_region, 10), "Invalid replacement preserves the previous region-proof geometry")


func _test_reconfiguration_and_extremes() -> void:
	var walls := TerrainWalls.new()
	_check(walls.configure([_line("old", Vector2(100, -100), Vector2(100, 100))]), "Reconfiguration fixture begins with a real wall")
	var before: Array[Dictionary] = walls.snapshot()
	var old_tree: PackedFloat64Array = walls._tree_min_x.duplicate()
	var old_nearest: PackedFloat64Array = walls._nearest_min_x.duplicate()
	_check(not walls.configure([{"id": "invalid", "a": [NAN, 0], "b": [1, 2]}]) and walls.snapshot() == before and walls._tree_min_x == old_tree and walls._nearest_min_x == old_nearest, "Invalid configuration preserves both the old geometry and its exact query indexes atomically")
	_check(not walls.segment_clear(Vector2.ZERO, Vector2(200, 0), 5), "Failed reconfiguration does not discard the previous blocking wall")
	_check(walls.configure([_line("new", Vector2(-10, 1000), Vector2(10, 1000))], 2.0, Vector2(50, -100)), "A new finite source transform replaces the previous hierarchy")
	_compare(walls, Vector2.ZERO, Vector2(200, 0), 5, 0, "replacement")
	_check(walls.segment_clear(Vector2.ZERO, Vector2(200, 0), 5), "A replaced wall cannot survive as a stale visibility blocker")
	walls.clear()
	_check(walls._tree_wall.is_empty() and walls._tree_escape.is_empty() and walls._bounds_min_x.is_empty() and walls._nearest_min_x.is_empty() and walls._nearest_min_y.is_empty() and walls._nearest_max_x.is_empty() and walls._nearest_max_y.is_empty(), "Clear releases every derived hierarchy and cached wall bound")
	_compare(walls, Vector2.ZERO, Vector2(100000, -100000), 200, 50, "empty")
	_check(walls.configure([{"id": "huge", "a": [1e150, -1e150], "b": [1e150, -1e150]}]), "Finite huge source coordinates need no integer grid conversion")
	_compare(walls, Vector2(-10000, 20000), Vector2(10000, -20000), 0, 0, "huge-source")
	_compare(walls, Vector2.ZERO, Vector2.ZERO, 1e151, 0, "huge-radius")
	_check(walls.configure([{"id": "precise", "a": [123.123456789, -45.987654321], "b": [223.123456789, 54.012345679]}]), "Double-precision source endpoints build the same precise bounds")
	_compare(walls, Vector2(0, 3), Vector2(500, 3), 0.125, 0.03125, "double-source")
