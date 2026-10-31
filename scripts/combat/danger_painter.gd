class_name DangerPainter
extends RefCounted
## Exact attack geometry with bounded pixel marks; presentation owns no clock or RNG.

const INK: Color = Color("263b4c")
const DANGER: Color = Color("e77c69")
const SAFE: Color = Color("77d8c4")
const DANGER_MARK: Color = Color("f5b58a")
const SAFE_MARK: Color = Color("b5f0d7")
const PROGRESS: Color = Color("fff0c9")
const INK_WIDTH: float = 4.0
const EDGE_WIDTH: float = 2.0
const CIRCLE_SEGMENTS: int = 48
const CIRCLE_TICKS: int = 12
const MAX_LANE_STATIONS: int = 8
const LANE_STATION_SPACING: float = 120.0
const MAX_DRAW_COMMANDS: int = 7

static func lane_polygon(shape: Dictionary) -> PackedVector2Array:
	var point: Variant = shape.get("position")
	var heading: Variant = shape.get("direction")
	var length: float = _number(shape.get("length"))
	var width: float = _number(shape.get("width"))
	if not point is Vector2 or not heading is Vector2 or not point.is_finite() or not heading.is_finite():
		return PackedVector2Array()
	if heading.is_zero_approx() or not is_finite(length) or not is_finite(width) or length <= 0.0 or width <= 0.0:
		return PackedVector2Array()
	var direction: Vector2 = heading.normalized()
	var side: Vector2 = direction.orthogonal() * width * 0.5
	var end: Vector2 = point + direction * length
	var corners := PackedVector2Array([point + side, end + side, end - side, point - side])
	return corners if _finite_points(corners) else PackedVector2Array()

static func presentation(shape: Dictionary, progress: float, safe: bool = false) -> Dictionary:
	if not is_finite(progress):
		return {}
	var kind: String = str(shape.get("shape", "circle"))
	var center: Variant = shape.get("position")
	if not center is Vector2 or not center.is_finite() or kind not in ["lane", "circle"]:
		return {}
	var fraction: float = clampf(progress, 0.0, 1.0)
	var boundary := PackedVector2Array()
	var marks := PackedVector2Array()
	var advance := PackedVector2Array()
	var radius: float = 0.0
	if kind == "lane":
		boundary = lane_polygon(shape)
		if boundary.is_empty() or not _has_area(boundary):
			return {}
		marks = _lane_marks(boundary, safe)
		if not safe:
			var first: Vector2 = boundary[0].lerp(boundary[1], fraction)
			var last: Vector2 = boundary[3].lerp(boundary[2], fraction)
			advance.append(first)
			advance.append(last)
		boundary.append(boundary[0])
	else:
		radius = _number(shape.get("radius"))
		if not is_finite(radius) or radius <= 0.0:
			return {}
		boundary = _circle_points(center, radius, 1.0)
		if not _finite_points(boundary) or not _has_area(boundary):
			return {}
		var depth: float = minf(5.0 if safe else 8.0, radius * 0.2)
		for index: int in CIRCLE_TICKS:
			var direction: Vector2 = Vector2.from_angle(float(index) * TAU / float(CIRCLE_TICKS))
			marks.append(center + direction * (radius - depth))
			marks.append(center + direction * radius)
		if not safe and fraction > 0.0:
			advance = _circle_points(center, radius, fraction)
	var bounds: Rect2 = _bounds(boundary)
	var draw_bounds: Rect2 = bounds.grow(INK_WIDTH * 0.5)
	if not _valid_bounds(bounds) or not _valid_bounds(draw_bounds) or not _finite_points(marks) or not _finite_points(advance):
		return {}
	return {"kind": kind, "center": center, "radius": radius, "boundary": boundary,
		"marks": marks, "advance": advance, "progress": fraction, "safe": safe,
		"bounds": bounds, "draw_bounds": draw_bounds,
		"fill_color": Color(SAFE if safe else DANGER, 0.02 if safe else 0.035),
		"edge_color": Color(SAFE if safe else DANGER, 0.88 if safe else 0.98),
		"mark_color": Color(SAFE_MARK if safe else DANGER_MARK, 0.95),
		"draw_commands": 5 + (2 if not advance.is_empty() else 0)}

static func draw(canvas: CanvasItem, shape: Dictionary, progress: float, safe: bool = false) -> void:
	if canvas == null:
		return
	var value: Dictionary = presentation(shape, progress, safe)
	if value.is_empty():
		return
	var boundary: PackedVector2Array = value["boundary"]
	if value["kind"] == "lane":
		canvas.draw_colored_polygon(lane_polygon(shape), value["fill_color"])
	else:
		canvas.draw_circle(value["center"], float(value["radius"]), value["fill_color"])
	canvas.draw_polyline(boundary, Color(INK, 0.72), INK_WIDTH, false)
	canvas.draw_polyline(boundary, value["edge_color"], EDGE_WIDTH, false)
	canvas.draw_multiline(value["marks"], Color(INK, 0.72), INK_WIDTH, false)
	canvas.draw_multiline(value["marks"], value["mark_color"], EDGE_WIDTH, false)
	var advance: PackedVector2Array = value["advance"]
	if not advance.is_empty():
		canvas.draw_polyline(advance, Color(INK, 0.8), INK_WIDTH, false)
		canvas.draw_polyline(advance, PROGRESS, EDGE_WIDTH, false)

static func _lane_marks(corners: PackedVector2Array, safe: bool) -> PackedVector2Array:
	var marks := PackedVector2Array()
	for index: int in 4:
		var corner: Vector2 = corners[index]
		for neighbor: int in [(index + 1) % 4, (index + 3) % 4]:
			var edge: Vector2 = corners[neighbor] - corner
			marks.append(corner)
			marks.append(corner + edge.normalized() * minf(12.0, edge.length() * 0.2))
	var length: float = corners[0].distance_to(corners[1])
	var width: float = corners[0].distance_to(corners[3])
	var direction: Vector2 = (corners[1] - corners[0]).normalized()
	var across: Vector2 = (corners[3] - corners[0]).normalized()
	var stations: int = MAX_LANE_STATIONS if length >= LANE_STATION_SPACING * float(MAX_LANE_STATIONS) else maxi(1, floori(length / LANE_STATION_SPACING))
	var depth: float = minf(5.0 if safe else 8.0, width * 0.2)
	var shoulder: float = minf(3.0, length * 0.1)
	for station: int in stations:
		var fraction: float = float(station + 1) / float(stations + 1)
		for side: int in 2:
			var edge: Vector2 = corners[0].lerp(corners[1], fraction) if side == 0 else corners[3].lerp(corners[2], fraction)
			var inward: Vector2 = across if side == 0 else -across
			if safe:
				marks.append(edge)
				marks.append(edge + inward * depth)
			else:
				var tip: Vector2 = edge + inward * depth
				marks.append(edge - direction * shoulder)
				marks.append(tip)
				marks.append(tip)
				marks.append(edge + direction * shoulder)
	return marks

static func _circle_points(center: Vector2, radius: float, fraction: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments: int = maxi(1, ceili(float(CIRCLE_SEGMENTS) * fraction))
	for index: int in segments + 1:
		var angle: float = -PI * 0.5 + TAU * fraction * float(index) / float(segments)
		points.append(center + Vector2.from_angle(angle) * radius)
	return points

static func _number(value: Variant) -> float:
	return float(value) if value is float or value is int else NAN

static func _finite_points(points: PackedVector2Array) -> bool:
	for point: Vector2 in points:
		if not point.is_finite():
			return false
	return true

static func _has_area(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	var doubled: float = 0.0
	var origin: Vector2 = points[0]
	for index: int in range(1, points.size() - 1):
		doubled += (points[index] - origin).cross(points[index + 1] - origin)
	return is_finite(doubled) and absf(doubled) > 0.0

static func _bounds(points: PackedVector2Array) -> Rect2:
	var low: Vector2 = points[0]
	var high: Vector2 = low
	for point: Vector2 in points:
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)

static func _valid_bounds(bounds: Rect2) -> bool:
	return bounds.position.is_finite() and bounds.size.is_finite() and bounds.end.is_finite() and bounds.size.x > 0.0 and bounds.size.y > 0.0
