extends SceneTree
## Analytic fixtures exercise continuous capsules and imported open terrain walls.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_configuration()
	_test_continuous_hits()
	_test_open_walls_and_slide()
	_test_free_points()
	_test_generated_sweeps()
	_test_original_geometry()
	print("TerrainWalls: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _scene(rows: Array) -> TerrainWalls:
	var result := TerrainWalls.new()
	_check(result.configure(rows), "The analytic wall fixture configures")
	return result


func _line(a: Vector2, b: Vector2, id: String = "wall") -> Dictionary:
	return {"id": id, "a": a, "b": b}


func _test_configuration() -> void:
	var walls := _scene([{"id": "precise", "a": [123.123456789, -45.987654321], "b": [223.123456789, 54.012345679]}])
	var rows: Array[Dictionary] = walls.snapshot()
	_check(absf(float(rows[0]["a"][0]) - 123.123456789) < 0.0000000001, "JSON scalar endpoints keep double precision before Vector2 output")
	rows[0]["a"][0] = -999.0
	rows.clear()
	_check(absf(float(walls.snapshot()[0]["a"][0]) - 123.123456789) < 0.0000000001, "Snapshot mutations cannot modify wall geometry")
	var before: Array[Dictionary] = walls.snapshot()
	var invalid: Array = [null, {"a": [0, NAN], "b": [1, 1]}, {"a": [true, 0], "b": [1, 1]}, {"a": [0], "b": [1, 1]}]
	for row: Variant in invalid:
		_check(not walls.configure([row]) and not walls.last_error.is_empty(), "Malformed wall input returns an explicit error")
		_check(walls.snapshot() == before, "A malformed rebuild preserves the previous valid scene")
	_check(not walls.configure([_line(Vector2.ZERO, Vector2.ONE), _line(Vector2.ZERO, Vector2.UP)]), "Duplicate wall IDs are rejected atomically")
	_check(not walls.configure([], -1.0) and walls.snapshot() == before, "Negative uniform scale cannot invert source geometry")
	_check(not walls.configure([], 1.0, Vector2.INF), "Nonfinite wall offsets are rejected")
	_check(walls.configure([_line(Vector2(2, 3), Vector2(4, 7))], 6.0, Vector2(-12, 20)), "Uniform scale and translation are accepted")
	_check(walls.snapshot()[0]["a"] == [0.0, 38.0] and walls.snapshot()[0]["b"] == [12.0, 62.0], "Uniform transform maps both endpoints without axis stretching")
	_check(not walls.is_free(Vector2.INF, 3) and not walls.is_free(Vector2.ZERO, -1), "Invalid point/radius queries fail closed")
	_check(not walls.segment_clear(Vector2.ZERO, Vector2.INF) and not walls.segment_clear(Vector2.ZERO, Vector2.ONE, 1, -2), "Invalid sweep parameters fail closed")
	_check(walls.free_point(Vector2.INF) == Vector2.INF and walls.slide(Vector2.ZERO, Vector2.INF) == Vector2.INF, "Invalid movement returns an explicit nonfinite sentinel")
	walls.clear()
	_check(walls.snapshot().is_empty() and walls.nearest_point(Vector2.ZERO).is_empty(), "Clearing removes all segments and nearest-wall metadata")
	_check(walls.is_free(Vector2(999, -999), 200) and walls.segment_clear(Vector2.ZERO, Vector2.ONE, 200), "An empty wall scene imposes no fabricated world bounds")


func _test_continuous_hits() -> void:
	var walls := _scene([_line(Vector2(100, 0), Vector2(100, 200))])
	var hit: Dictionary = walls.first_hit(Vector2(0, 100), Vector2(200, 100), 10)
	_check(not hit.is_empty(), "A complete one-step crossing hits the finite wall")
	if hit.is_empty():
		return
	_check(absf(float(hit["t"]) - 0.45) < 0.00000001 and hit["position"].distance_to(Vector2(90, 100)) < 0.001, "Wall-side hit time is the exact swept-circle solution")
	_check(hit["normal"].distance_to(Vector2.LEFT) < 0.00001 and hit["wall_point"] == Vector2(100, 100), "Contact reports an outward normal and centerline witness")
	_check(hit["id"] == "wall" and int(hit["segment_index"]) == 0, "Contact retains source segment identity")
	var reverse: Dictionary = walls.first_hit(Vector2(200, 100), Vector2(0, 100), 10)
	_check(absf(float(reverse["t"]) - 0.45) < 0.00000001 and reverse["normal"] == Vector2.RIGHT, "An open segment blocks both sides symmetrically")
	var cap: Dictionary = walls.first_hit(Vector2(70, -6), Vector2(130, -6), 10)
	_check(not cap.is_empty() and absf(float(cap.get("t", 0.0)) - 22.0 / 60.0) < 0.00000001, "An endpoint uses the real circular cap, not an axis-aligned box")
	_check(cap.get("wall_point") == Vector2(100, 0) and absf(float(cap.get("distance", 0.0)) - 10.0) < 0.00001, "The endpoint contact's distance equals body radius")
	_check(walls.segment_clear(Vector2(70, -11), Vector2(130, -11), 10), "A sweep outside the end cap remains clear")
	_check(walls.segment_clear(Vector2(70, -10), Vector2(130, -10), 10), "Pure tangent motion does not create a blocking impact")
	_check(not walls.first_hit(Vector2(0, 100), Vector2(200, 100), 0).is_empty(), "Zero-radius projectiles still cross the exact centerline")
	_check(walls.first_hit(Vector2(90, 100), Vector2(80, 100), 10).is_empty(), "A body touching the side can move outward")
	_check(walls.first_hit(Vector2(90, 100), Vector2(90, 120), 10).is_empty(), "A body can move tangentially along a wall")
	_check(float(walls.first_hit(Vector2(90, 100), Vector2(110, 100), 10).get("t", -1)) == 0.0, "Inward motion from exact contact blocks immediately")
	_check(walls.first_hit(Vector2(95, 100), Vector2(80, 100), 10).is_empty(), "Existing overlap can escape along the outward half-space")
	_check(float(walls.first_hit(Vector2(95, 100), Vector2(110, 100), 10).get("t", -1)) == 0.0, "Motion deeper into an existing overlap reports immediate contact")
	_check(walls.first_hit(Vector2(0, 100), Vector2(0, 100), 10).is_empty(), "A stationary free point has no collision")
	var nearest: Dictionary = walls.nearest_point(Vector2(112, -5))
	_check(nearest["wall_point"] == Vector2(100, 0) and absf(float(nearest["distance"]) - 13.0) < 0.00001, "Nearest-point queries clamp to finite endpoints")
	var padded: Dictionary = walls.first_hit(Vector2(0, 100), Vector2(200, 100), 10, 5)
	_check(absf(float(padded["t"]) - 0.425) < 0.00000001, "Extra clearance is composed once with the querying radius")
	var degenerate := _scene([_line(Vector2(100, 100), Vector2(100, 100), "point")])
	_check(absf(float(degenerate.first_hit(Vector2(0, 100), Vector2(200, 100), 10).get("t", 0)) - 0.45) < 0.00000001, "A zero-length source wall remains an exact point capsule")
	var tied := _scene([_line(Vector2(100, 0), Vector2(100, 200), "first"), _line(Vector2(100, 0), Vector2(100, 200), "second")])
	_check(tied.first_hit(Vector2(0, 100), Vector2(200, 100), 10).get("id") == "first", "Coincident hit times preserve deterministic input order")


func _test_open_walls_and_slide() -> void:
	var walls := _scene([_line(Vector2(0, 100), Vector2(0, 0), "left"), _line(Vector2(0, 0), Vector2(100, 0), "top"), _line(Vector2(100, 0), Vector2(100, 100), "right")])
	_check(walls.segment_clear(Vector2(50, 50), Vector2(50, 250), 5), "A three-sided source polyline keeps its bottom genuinely open")
	_check(walls.move(Vector2(50, 50), Vector2(0, 200), 5).distance_to(Vector2(50, 250)) < 0.001, "Movement leaves through the open side without an inferred closing wall")
	var slide: Vector2 = walls.slide(Vector2(50, 50), Vector2(100, -30), 5)
	_check(walls.is_free(slide, 5) and slide.x <= 95.001 and absf(slide.y - 20.0) < 0.01, "Continuous movement stops at the wall and preserves tangential travel")
	var corner: Vector2 = walls.slide(Vector2(50, 50), Vector2(100, -100), 5)
	_check(walls.is_free(corner, 5) and corner.x <= 95.001 and corner.y >= 4.999, "Two sequential contacts stop a diagonal sweep at the interior corner")
	_check(corner.distance_to(Vector2(95, 5)) < 0.02, "Corner resolution neither tunnels nor jumps to a distant point")
	var restored: Vector2 = walls.slide(Vector2(1, 50), Vector2(0, 20), 5)
	_check(walls.is_free(restored, 5) and restored.distance_to(Vector2(5, 70)) < 0.02, "An overlapping spawn is projected locally before movement")
	var diagonal := _scene([_line(Vector2(100, 0), Vector2(200, 100))])
	var hit: Dictionary = diagonal.first_hit(Vector2(0, 50), Vector2(300, 50), 10)
	var expected_x: float = 150.0 - sqrt(200.0)
	_check(absf(float(hit.get("t", 0)) - expected_x / 300.0) < 0.00000001, "A diagonal wall uses perpendicular radius, preserving its actual angle")
	var moved: Vector2 = diagonal.slide(Vector2(110, 90), Vector2(120, 0), 10)
	_check(diagonal.is_free(moved, 10) and moved.y > 90, "Sliding follows the actual diagonal rather than a bounding-box edge")


func _test_free_points() -> void:
	var single := _scene([_line(Vector2(-100, 0), Vector2(100, 0))])
	_check(single.free_point(Vector2(0, 20), 10) == Vector2(0, 20), "Already-free points remain byte-stable")
	var projected: Vector2 = single.free_point(Vector2(0, 3), 10)
	_check(single.is_free(projected, 10) and projected.distance_to(Vector2(0, 10)) < 0.01, "An embedded point projects to the nearest capsule side")
	var endpoint: Vector2 = single.free_point(Vector2(104, 3), 10)
	_check(single.is_free(endpoint, 10) and endpoint.distance_to(Vector2(108, 6)) < 0.01, "Projection beyond a segment end follows the exact endpoint arc")
	var cross := _scene([_line(Vector2(-100, 0), Vector2(100, 0), "horizontal"), _line(Vector2(0, -100), Vector2(0, 100), "vertical")])
	var cross_free: Vector2 = cross.free_point(Vector2.ZERO, 10)
	_check(cross.is_free(cross_free, 10) and absf(absf(cross_free.x) - 10) < 0.01 and absf(absf(cross_free.y) - 10) < 0.01, "The nearest point outside intersecting capsules uses the offset-line intersection")
	var parallel := _scene([_line(Vector2(-100, 0), Vector2(100, 0), "lower"), _line(Vector2(-100, 12), Vector2(100, 12), "upper")])
	var parallel_free: Vector2 = parallel.free_point(Vector2(0, 6), 8)
	_check(parallel.is_free(parallel_free, 8) and parallel_free.distance_to(Vector2(0, 6)) < 14.01, "An impossible narrow corridor exits the capsule union without oscillating between walls")
	var circles := _scene([_line(Vector2(-5, 0), Vector2(-5, 0), "a"), _line(Vector2(5, 0), Vector2(5, 0), "b")])
	var circle_free: Vector2 = circles.free_point(Vector2.ZERO, 10)
	_check(circles.is_free(circle_free, 10) and absf(circle_free.x) < 0.001 and absf(absf(circle_free.y) - sqrt(75.0)) < 0.01, "Overlapping endpoint capsules use their real circle-circle boundary intersection")
	var mixed := _scene([_line(Vector2(-20, 0), Vector2(20, 0), "line"), _line(Vector2(0, 8), Vector2(0, 8), "cap")])
	var mixed_free: Vector2 = mixed.free_point(Vector2(0, 4), 6)
	_check(mixed.is_free(mixed_free, 6) and mixed_free.distance_to(Vector2(0, 4)) < 6.02, "A line-circle overlap uses the analytic intersection instead of a remote fallback")
	var zero: Vector2 = single.free_point(Vector2.ZERO)
	_check(single.is_free(zero) and zero.length() <= TerrainWalls.SKIN * 1.1, "Zero-radius points on a wall receive only the numeric safety offset")


func _test_generated_sweeps() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	for sample: int in 80:
		var center := Vector2(rng.randf_range(-1200, 2400), rng.randf_range(-600, 1300))
		var tangent: Vector2 = Vector2.from_angle(rng.randf_range(-PI, PI))
		var normal := Vector2(-tangent.y, tangent.x)
		var half_length: float = rng.randf_range(80, 300)
		var radius: float = rng.randf_range(0.5, 30)
		var a: Vector2 = center - tangent * half_length
		var b: Vector2 = center + tangent * half_length
		var walls := _scene([_line(a, b)])
		var start: Vector2 = center + normal * 2000.0
		var finish: Vector2 = center - normal * 2000.0
		var hit: Dictionary = walls.first_hit(start, finish, radius)
		_check(not hit.is_empty(), "Long randomized sweeps cannot tunnel: %d" % sample)
		if hit.is_empty():
			continue
		var time: float = float(hit["t"])
		_check(absf(time - (2000.0 - radius) / 4000.0) < 0.000001, "Long-sweep contact time matches an independently known perpendicular distance: %d" % sample)
		var witness: Vector2 = Geometry2D.get_closest_point_to_segment(hit["position"], a, b)
		_check(absf(hit["position"].distance_to(witness) - radius) < 0.002, "Returned contact lies on the continuous capsule surface: %d" % sample)
		var moved: Vector2 = walls.slide(start, finish - start, radius)
		_check(walls.is_free(moved, radius) and (moved - center).dot(normal) >= radius - 0.002, "Movement remains on its original side after the long sweep: %d" % sample)


func _test_original_geometry() -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/worldflipper/layouts.json"))
	_check(value is Dictionary and value.get("schema_version") == 1, "The standalone collision tests use the actual normalized source geometry")
	if not value is Dictionary:
		return
	var expected: Dictionary = {"main_2_9_5": 3, "main_3_6_2": 8, "main_6_6_2": 6}
	var tested: int = 0
	for layout: Dictionary in value["layouts"]:
		if not expected.has(layout["id"]):
			continue
		var layer: Dictionary = layout["layers"][0]
		_check(layer["walls"].size() == int(expected[layout["id"]]), "The verified JP-reference layout retains its exact open segment count")
		var walls := _scene(layer["walls"])
		var longest: Dictionary = {}
		var longest_squared: float = -1.0
		for wall: Dictionary in layer["walls"]:
			var a := Vector2(float(wall["a"][0]), float(wall["a"][1]))
			var b := Vector2(float(wall["b"][0]), float(wall["b"][1]))
			if a.distance_squared_to(b) > longest_squared:
				longest_squared = a.distance_squared_to(b)
				longest = wall
		var a := Vector2(float(longest["a"][0]), float(longest["a"][1]))
		var b := Vector2(float(longest["b"][0]), float(longest["b"][1]))
		var midpoint: Vector2 = (a + b) * 0.5
		var direction: Vector2 = (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var hit: Dictionary = walls.first_hit(midpoint + normal * 30, midpoint - normal * 30, 8)
		_check(not hit.is_empty() and hit.get("id") == longest["id"], "Imported source walls participate directly in the capsule query")
		_check(absf(float(hit.get("t", 0)) - 22.0 / 60.0) < 0.00001, "Imported x6 coordinates preserve the source wall's real continuous geometry")
		tested += 1
	_check(tested == 3, "All three exact final-JP reference matches are exercised")
