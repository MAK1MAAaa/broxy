extends SceneTree
## Readable warning marks stay inside exact combat geometry and own no gameplay state.

const PAINTER = preload("res://scripts/combat/danger_painter.gd")
const EPSILON: float = 0.002
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_exact_rectangles()
	_test_lane_marks()
	_test_circle_marks()
	_test_invalid_geometry()
	_test_bounded_composition_and_purity()
	print("DangerPainter: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _lane(origin: Vector2 = Vector2(20, 30), heading: Vector2 = Vector2.RIGHT, length: float = 120.0, width: float = 40.0) -> Dictionary:
	return {"shape": "lane", "position": origin, "direction": heading, "length": length, "width": width}

func _test_exact_rectangles() -> void:
	var horizontal: PackedVector2Array = PAINTER.lane_polygon(_lane(Vector2(20, 30), Vector2(5, 0)))
	_check(horizontal.size() == 4, "A non-unit heading still produces exactly four square-cap rectangle corners")
	for point: Vector2 in [Vector2(20, 10), Vector2(20, 50), Vector2(140, 10), Vector2(140, 50)]:
		_check(horizontal.has(point), "A 120px horizontal lane retains its exact endpoint and half width: " + str(point))
	var vertical: PackedVector2Array = PAINTER.lane_polygon(_lane(Vector2(20, 30), Vector2(0, -3)))
	for point: Vector2 in [Vector2(0, 30), Vector2(40, 30), Vector2(0, -90), Vector2(40, -90)]:
		_check(vertical.has(point), "A negative vertical heading keeps its true 120px extent: " + str(point))
	for index: int in 24:
		var heading: Vector2 = Vector2.from_angle(float(index) * TAU / 24.0) * 3.0
		var origin := Vector2(-700.0 + float(index) * 30.0, 400.0 - float(index) * 13.0)
		var shape: Dictionary = _lane(origin, heading, 840, 112)
		var corners: PackedVector2Array = PAINTER.lane_polygon(shape)
		_check(corners.size() == 4 and is_equal_approx(corners[0].distance_to(corners[1]), 840.0) and is_equal_approx(corners[0].distance_to(corners[3]), 112.0), "Rotated rectangles preserve independent length and width")
		var unit: Vector2 = heading.normalized()
		var correct: bool = true
		for corner: Vector2 in corners:
			var offset: Vector2 = corner - origin
			var along: float = offset.dot(unit)
			correct = correct and (absf(along) <= EPSILON or absf(along - 840.0) <= EPSILON)
			correct = correct and absf(absf(offset.cross(unit)) - 56.0) <= EPSILON
		_check(correct, "Every rotated corner lies on the original finite collision rectangle")

func _test_lane_marks() -> void:
	for heading: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2(-3, 4), Vector2(4, 3)]:
		var shape: Dictionary = _lane(Vector2(-123, 231), heading, 840, 112)
		for safe: bool in [false, true]:
			for progress: float in [-2.0, 0.0, 0.37, 1.0, 2.0]:
				var value: Dictionary = PAINTER.presentation(shape, progress, safe)
				_check(not value.is_empty() and value["kind"] == "lane" and value["safe"] == safe, "Both styles share the same valid rectangle")
				var corners: PackedVector2Array = PAINTER.lane_polygon(shape)
				var boundary: PackedVector2Array = value["boundary"]
				_check(boundary.size() == 5 and boundary[0] == boundary[4] and boundary.slice(0, 4) == corners, "The visible boundary closes the original four corners without an offset")
				var inside: bool = true
				for point: Vector2 in value["marks"]:
					inside = inside and _inside_lane(shape, point)
				_check(inside and (value["marks"] as PackedVector2Array).size() <= 80 and (value["marks"] as PackedVector2Array).size() % 2 == 0, "All corner marks and teeth remain inside the true lane, with at most forty segments")
				var advance: PackedVector2Array = value["advance"]
				var fraction: float = clampf(progress, 0.0, 1.0)
				if safe:
					_check(advance.is_empty(), "Safe corridors remain static and never acquire a dangerous moving crossbar")
				else:
					var exact_front: Vector2 = (shape["position"] as Vector2) + heading.normalized() * 840.0 * fraction
					_check(advance.size() == 2 and ((advance[0] + advance[1]) * 0.5).distance_to(exact_front) <= EPSILON and is_equal_approx(advance[0].distance_to(advance[1]), 112.0), "Danger progress spans the exact width at the authoritative front")
				_check(value["progress"] == fraction and int(value["draw_commands"]) <= PAINTER.MAX_DRAW_COMMANDS, "Out-of-range progress clamps without increasing the fixed draw budget")
		var danger: Dictionary = PAINTER.presentation(shape, 0.5)
		var safe_value: Dictionary = PAINTER.presentation(shape, 0.5, true)
		_check((danger["marks"] as PackedVector2Array).size() > (safe_value["marks"] as PackedVector2Array).size(), "Inward danger teeth differ from safe short ticks without depending on color alone")
		_check((danger["fill_color"] as Color).a <= 0.04 and (safe_value["fill_color"] as Color).a <= 0.025, "The underlying original map is not washed out by broad opaque fills")

func _test_circle_marks() -> void:
	for center: Vector2 in [Vector2.ZERO, Vector2(-310, 180), Vector2(1500, -700)]:
		for radius: float in [13.0, 88.0, 120.0]:
			var shape: Dictionary = {"shape": "circle", "position": center, "radius": radius}
			for safe: bool in [false, true]:
				for progress: float in [0.0, 0.5, 1.0]:
					var value: Dictionary = PAINTER.presentation(shape, progress, safe)
					_check(not value.is_empty() and value["center"] == center and value["radius"] == radius, "Circle styles never move the target or alter the attack radius")
					var boundary: PackedVector2Array = value["boundary"]
					var exact_radius: bool = boundary.size() == PAINTER.CIRCLE_SEGMENTS + 1
					for point: Vector2 in boundary:
						exact_radius = exact_radius and absf(point.distance_to(center) - radius) <= EPSILON
					_check(exact_radius, "Every circular boundary vertex stays on the original radius")
					var marks: PackedVector2Array = value["marks"]
					var inside: bool = marks.size() == PAINTER.CIRCLE_TICKS * 2
					for point: Vector2 in marks:
						inside = inside and point.distance_to(center) <= radius + EPSILON
					_check(inside, "Twelve circle ticks point inward rather than inventing an outer hit area")
					var advance: PackedVector2Array = value["advance"]
					if safe or progress <= 0.0:
						_check(advance.is_empty(), "Safe circles and zero charge have no partial attack arc")
					else:
						var end: Vector2 = center + Vector2.from_angle(-PI * 0.5 + TAU * progress) * radius
						var valid_arc: bool = advance.size() <= PAINTER.CIRCLE_SEGMENTS + 1 and advance[0].distance_to(center + Vector2(0, -radius)) <= EPSILON and advance[advance.size() - 1].distance_to(end) <= EPSILON
						for point: Vector2 in advance:
							valid_arc = valid_arc and absf(point.distance_to(center) - radius) <= EPSILON
						_check(valid_arc, "Charge advances along the exact original ring from its fixed top origin")
					var expected := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
					_check((value["bounds"] as Rect2).is_equal_approx(expected) and (value["draw_bounds"] as Rect2).is_equal_approx(expected.grow(PAINTER.INK_WIDTH * 0.5)), "Circle geometry and conservative stroke bounds are explicit and exact")

func _test_invalid_geometry() -> void:
	var invalid: Array[Dictionary] = [{}, {"position": Vector2.ZERO, "radius": 0.0},
		{"position": Vector2.ZERO, "radius": -3.0}, {"position": Vector2.INF, "radius": 88.0},
		{"position": Vector2.ZERO, "radius": NAN}, {"position": Vector2.ZERO, "radius": INF},
		{"position": Vector2.ZERO, "radius": "88"}, {"position": Vector2i.ZERO, "radius": 88.0},
		{"position": Vector2.ZERO, "radius": 88.0, "shape": "capsule"},
		_lane(Vector2.ZERO, Vector2.ZERO), _lane(Vector2.INF), _lane(Vector2.ZERO, Vector2.INF),
		_lane(Vector2.ZERO, Vector2.RIGHT, 0.0), _lane(Vector2.ZERO, Vector2.RIGHT, -1.0),
		_lane(Vector2.ZERO, Vector2.RIGHT, INF), _lane(Vector2.ZERO, Vector2.RIGHT, 120, 0),
		_lane(Vector2.ZERO, Vector2.RIGHT, 120, -2), _lane(Vector2.ZERO, Vector2.RIGHT, 120, NAN),
		_lane(Vector2(1.0e38, 1.0e38), Vector2.RIGHT, 1.0e38, 1.0e38),
		{"position": Vector2(1.0e38, 1.0e38), "radius": 1.0e38}]
	for shape: Dictionary in invalid:
		_check(PAINTER.presentation(shape, 0.5).is_empty() and PAINTER.presentation(shape, 0.5, true).is_empty(), "Invalid, nonfinite or degenerate shapes cannot publish any draw geometry")
	for progress: float in [NAN, INF, -INF]:
		_check(PAINTER.presentation(_lane(), progress).is_empty(), "Nonfinite timing cannot generate unstable warning marks")
	PAINTER.draw(null, _lane(), 0.5)

func _test_bounded_composition_and_purity() -> void:
	var shape: Dictionary = _lane(Vector2(-123, 47), Vector2(3, 4), 840, 112)
	shape["unrelated"] = {"cast_id": 913, "nested": [1, 2, 3]}
	var before: PackedByteArray = var_to_bytes(shape)
	var original: Dictionary = PAINTER.presentation(shape, 0.5)
	var damaged: Dictionary = PAINTER.presentation(shape, 0.5)
	var points: PackedVector2Array = damaged["marks"]
	points[0] = Vector2.INF
	damaged["progress"] = 0.0
	_check(PAINTER.presentation(shape, 0.5) == original and var_to_bytes(shape) == before, "Returned geometry is independent and cannot mutate the source or future calls")
	seed(871319)
	var expected: float = randf()
	seed(871319)
	var bounded: bool = true
	for iteration: int in 128:
		var length: float = 12.0 + float(iteration) * 1234.0
		var value: Dictionary = PAINTER.presentation(_lane(Vector2.ZERO, Vector2.RIGHT, length, 112), float(iteration % 11) / 10.0)
		bounded = bounded and (value["marks"] as PackedVector2Array).size() <= 80 and (value["boundary"] as PackedVector2Array).size() == 5 and int(value["draw_commands"]) <= 7
	_check(bounded, "Long lanes and repeated frames never grow beyond eight marker stations or seven commands")
	_check(randf() == expected and var_to_bytes(shape) == before, "Repeated presentation uses neither simulation data mutation nor the global random stream")
	var storm: Array[Dictionary] = []
	var roots: Array[Dictionary] = []
	for index: int in 5:
		storm.append(PAINTER.presentation({"position": Vector2(index * 168, 0), "radius": 88.0}, 0.75))
	for index: int in 4:
		roots.append(PAINTER.presentation(_lane(Vector2(0, index * 160), Vector2.RIGHT, 840, 112), 0.75))
	var commands: int = 0
	for value: Dictionary in storm + roots:
		commands += int(value["draw_commands"])
	_check(commands <= 9 * PAINTER.MAX_DRAW_COMMANDS, "The largest five-circle and four-lane combination has a bounded presentation budget")

func _inside_lane(shape: Dictionary, point: Vector2) -> bool:
	var heading: Vector2 = (shape["direction"] as Vector2).normalized()
	var offset: Vector2 = point - (shape["position"] as Vector2)
	var along: float = offset.dot(heading)
	return along >= -EPSILON and along <= float(shape["length"]) + EPSILON and absf(offset.cross(heading)) <= float(shape["width"]) * 0.5 + EPSILON
