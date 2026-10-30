class_name TerrainWalls
extends RefCounted
## Exact open segments, expanded to capsules by the querying body's radius.
## No bounds closure, sampled circles, or prop collision is inferred here.

const SKIN: float = 0.002
const EPSILON: float = 0.000000001
const MAX_SLIDES: int = 8

var last_error: String = ""
var _items: Array[Dictionary] = []
var _ax: PackedFloat64Array = PackedFloat64Array()
var _ay: PackedFloat64Array = PackedFloat64Array()
var _bx: PackedFloat64Array = PackedFloat64Array()
var _by: PackedFloat64Array = PackedFloat64Array()
var _vx: PackedFloat64Array = PackedFloat64Array()
var _vy: PackedFloat64Array = PackedFloat64Array()
var _length_squared: PackedFloat64Array = PackedFloat64Array()


func configure(segments: Array, scale: float = 1.0, offset: Vector2 = Vector2.ZERO) -> bool:
	# Invalid input leaves the previous valid scene intact.
	if not is_finite(scale) or scale <= 0.0 or not offset.is_finite():
		last_error = "Wall transform must be finite with positive uniform scale"
		return false
	var next: Array[Dictionary] = []
	var ids: Dictionary = {}
	for value: Variant in segments:
		if not value is Dictionary:
			last_error = "Wall entry must be a dictionary"
			return false
		var a: PackedFloat64Array = _point(value.get("a"))
		var b: PackedFloat64Array = _point(value.get("b"))
		var id: String = str(value.get("id", next.size()))
		if a.size() != 2 or b.size() != 2 or id.is_empty() or ids.has(id):
			last_error = "Walls require finite endpoints and unique nonempty IDs"
			return false
		a[0] = a[0] * scale + float(offset.x)
		a[1] = a[1] * scale + float(offset.y)
		b[0] = b[0] * scale + float(offset.x)
		b[1] = b[1] * scale + float(offset.y)
		var vx: float = b[0] - a[0]
		var vy: float = b[1] - a[1]
		if not is_finite(a[0]) or not is_finite(a[1]) or not is_finite(b[0]) or not is_finite(b[1]) or not is_finite(vx * vx + vy * vy):
			last_error = "Transformed wall coordinates overflow"
			return false
		ids[id] = true
		next.append({"id": id, "a": [a[0], a[1]], "b": [b[0], b[1]]})
	clear()
	_items = next
	for item: Dictionary in _items:
		var a: Array = item["a"]
		var b: Array = item["b"]
		_ax.append(float(a[0]))
		_ay.append(float(a[1]))
		_bx.append(float(b[0]))
		_by.append(float(b[1]))
		_vx.append(float(b[0]) - float(a[0]))
		_vy.append(float(b[1]) - float(a[1]))
		_length_squared.append(_vx[-1] * _vx[-1] + _vy[-1] * _vy[-1])
	return true


func clear() -> void:
	_items.clear()
	_ax.clear()
	_ay.clear()
	_bx.clear()
	_by.clear()
	_vx.clear()
	_vy.clear()
	_length_squared.clear()
	last_error = ""


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _items:
		result.append(item.duplicate(true))
	return result


static func _point(value: Variant) -> PackedFloat64Array:
	if value is Vector2:
		return PackedFloat64Array([float(value.x), float(value.y)]) if value.is_finite() else PackedFloat64Array()
	if (value is Array or value is PackedFloat64Array or value is PackedFloat32Array) and value.size() == 2:
		if (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
			var x: float = float(value[0])
			var y: float = float(value[1])
			if is_finite(x) and is_finite(y):
				return PackedFloat64Array([x, y])
	return PackedFloat64Array()


static func _valid_query(point: Vector2, radius: float, padding: float) -> bool:
	return point.is_finite() and is_finite(radius) and radius >= 0.0 and is_finite(padding) and padding >= 0.0 and is_finite((radius + padding) * (radius + padding))


func _fraction(index: int, x: float, y: float) -> float:
	if _length_squared[index] == 0.0:
		return 0.0
	return clampf(((x - _ax[index]) * _vx[index] + (y - _ay[index]) * _vy[index]) / _length_squared[index], 0.0, 1.0)


func _free_xy(x: float, y: float, radius: float) -> bool:
	var r2: float = radius * radius
	for index: int in _items.size():
		if x < minf(_ax[index], _bx[index]) - radius or x > maxf(_ax[index], _bx[index]) + radius or y < minf(_ay[index], _by[index]) - radius or y > maxf(_ay[index], _by[index]) + radius:
			continue
		var fraction: float = _fraction(index, x, y)
		var dx: float = x - (_ax[index] + _vx[index] * fraction)
		var dy: float = y - (_ay[index] + _vy[index] * fraction)
		var distance_squared: float = dx * dx + dy * dy
		if distance_squared < r2 - EPSILON or (radius == 0.0 and distance_squared <= EPSILON * EPSILON):
			return false
	return true


func is_free(point: Vector2, radius: float = 0.0, padding: float = 0.0) -> bool:
	return _valid_query(point, radius, padding) and _free_xy(float(point.x), float(point.y), radius + padding)


func nearest_point(point: Vector2) -> Dictionary:
	if not point.is_finite() or _items.is_empty():
		return {}
	var best_index: int = -1
	var best_squared: float = INF
	var best_fraction: float = 0.0
	for index: int in _items.size():
		var fraction: float = _fraction(index, float(point.x), float(point.y))
		var dx: float = float(point.x) - (_ax[index] + _vx[index] * fraction)
		var dy: float = float(point.y) - (_ay[index] + _vy[index] * fraction)
		var distance_squared: float = dx * dx + dy * dy
		if distance_squared < best_squared:
			best_index = index
			best_squared = distance_squared
			best_fraction = fraction
	return _contact(best_index, float(point.x), float(point.y), 0.0, 0.0, best_fraction, 0.0)


func first_hit(start: Vector2, end: Vector2, radius: float = 0.0, padding: float = 0.0) -> Dictionary:
	if not _valid_query(start, radius, padding) or not end.is_finite():
		return {}
	var sx: float = float(start.x)
	var sy: float = float(start.y)
	var dx: float = float(end.x) - sx
	var dy: float = float(end.y) - sy
	var clearance: float = radius + padding
	var best: float = INF
	var winner: int = -1
	for index: int in _items.size():
		if maxf(sx, sx + dx) < minf(_ax[index], _bx[index]) - clearance or minf(sx, sx + dx) > maxf(_ax[index], _bx[index]) + clearance or maxf(sy, sy + dy) < minf(_ay[index], _by[index]) - clearance or minf(sy, sy + dy) > maxf(_ay[index], _by[index]) + clearance:
			continue
		var hit: float = _entry_time(index, sx, sy, dx, dy, clearance)
		if hit < best:
			best = hit
			winner = index
	if winner < 0:
		return {}
	var x: float = sx + dx * best
	var y: float = sy + dy * best
	return _contact(winner, x, y, dx, dy, _fraction(winner, x, y), best)


func segment_clear(start: Vector2, end: Vector2, radius: float = 0.0, padding: float = 0.0) -> bool:
	return _valid_query(start, radius, padding) and end.is_finite() and first_hit(start, end, radius, padding).is_empty()


func _entry_time(index: int, sx: float, sy: float, dx: float, dy: float, radius: float) -> float:
	var fraction: float = _fraction(index, sx, sy)
	var ox: float = sx - (_ax[index] + _vx[index] * fraction)
	var oy: float = sy - (_ay[index] + _vy[index] * fraction)
	var initial_squared: float = ox * ox + oy * oy
	var radius_squared: float = radius * radius
	if initial_squared <= radius_squared + EPSILON:
		# A convex capsule cannot be re-entered by a straight outward ray.
		if ox * dx + oy * dy > EPSILON or (initial_squared >= radius_squared - EPSILON and initial_squared > EPSILON and ox * dx + oy * dy >= -EPSILON):
			return INF
		return 0.0
	if dx * dx + dy * dy == 0.0:
		return INF
	var best: float = minf(_circle_entry(sx, sy, dx, dy, _ax[index], _ay[index], radius), _circle_entry(sx, sy, dx, dy, _bx[index], _by[index], radius))
	if _length_squared[index] == 0.0:
		return best
	var length: float = sqrt(_length_squared[index])
	var nx: float = -_vy[index] / length
	var ny: float = _vx[index] / length
	var distance: float = (sx - _ax[index]) * nx + (sy - _ay[index]) * ny
	var speed: float = dx * nx + dy * ny
	if absf(speed) <= EPSILON:
		return best
	for side: float in [-1.0, 1.0]:
		if radius > 0.0 and side * speed >= 0.0:
			continue
		var time: float = (side * radius - distance) / speed
		if time < 0.0 or time > 1.0 or time >= best:
			continue
		var projection: float = ((sx + dx * time - _ax[index]) * _vx[index] + (sy + dy * time - _ay[index]) * _vy[index]) / _length_squared[index]
		if projection >= 0.0 and projection <= 1.0:
			best = time
	return best


static func _circle_entry(sx: float, sy: float, dx: float, dy: float, cx: float, cy: float, radius: float) -> float:
	var ox: float = sx - cx
	var oy: float = sy - cy
	var a: float = dx * dx + dy * dy
	if a == 0.0:
		return INF
	var b: float = ox * dx + oy * dy
	var c: float = ox * ox + oy * oy - radius * radius
	var discriminant: float = b * b - a * c
	if discriminant < 0.0:
		return INF
	var root: float = sqrt(discriminant)
	# q avoids cancellation when the entry is close to a long sweep's start.
	var q: float = -b - (root if b >= 0.0 else -root)
	var first: float = q / a if q != 0.0 else -b / a
	var second: float = c / q if q != 0.0 else first
	var time: float = minf(first, second)
	if time < 0.0 or time > 1.0 or (radius > 0.0 and a * time + b >= -EPSILON):
		return INF
	return time


func _contact(index: int, x: float, y: float, dx: float, dy: float, fraction: float, time: float) -> Dictionary:
	var wall_x: float = _ax[index] + _vx[index] * fraction
	var wall_y: float = _ay[index] + _vy[index] * fraction
	var nx: float = x - wall_x
	var ny: float = y - wall_y
	var distance: float = sqrt(nx * nx + ny * ny)
	if distance > EPSILON:
		nx /= distance
		ny /= distance
	elif _length_squared[index] > 0.0:
		var length: float = sqrt(_length_squared[index])
		nx = -_vy[index] / length
		ny = _vx[index] / length
		if nx * dx + ny * dy > 0.0:
			nx = -nx
			ny = -ny
	else:
		var motion_length: float = sqrt(dx * dx + dy * dy)
		nx = -dx / motion_length if motion_length > EPSILON else 1.0
		ny = -dy / motion_length if motion_length > EPSILON else 0.0
	return {"id": _items[index]["id"], "segment_index": index, "t": time,
		"position": Vector2(x, y), "wall_point": Vector2(wall_x, wall_y),
		"normal": Vector2(nx, ny), "distance": distance, "fraction": fraction}


func move(start: Vector2, displacement: Vector2, radius: float = 0.0, padding: float = 0.0) -> Vector2:
	return slide(start, displacement, radius, padding)


func slide(start: Vector2, displacement: Vector2, radius: float = 0.0, padding: float = 0.0) -> Vector2:
	if not _valid_query(start, radius, padding) or not displacement.is_finite():
		return Vector2.INF
	var position: Vector2 = free_point(start, radius, padding)
	var remaining: Vector2 = displacement
	for _iteration: int in MAX_SLIDES:
		if remaining.length_squared() <= EPSILON * EPSILON:
			break
		var hit: Dictionary = first_hit(position, position + remaining, radius, padding)
		if hit.is_empty():
			position += remaining
			break
		var time: float = float(hit["t"])
		var advance: float = maxf(0.0, time - SKIN / maxf(remaining.length(), SKIN))
		position += remaining * advance
		remaining *= 1.0 - advance
		var normal: Vector2 = hit["normal"]
		var inward: float = float(remaining.x) * float(normal.x) + float(remaining.y) * float(normal.y)
		if inward < 0.0:
			remaining -= normal * inward
		elif advance == 0.0:
			break
	return free_point(position, radius, padding)


func free_point(point: Vector2, radius: float = 0.0, padding: float = 0.0) -> Vector2:
	if not _valid_query(point, radius, padding):
		return Vector2.INF
	var clearance: float = radius + padding
	if _free_xy(float(point.x), float(point.y), clearance):
		return point
	# The nearest boundary of a finite capsule union is a projection onto one
	# analytic boundary curve or an intersection of two such curves.
	var safe_radius: float = clearance + SKIN
	var curves: Array[Dictionary] = []
	var candidates: Array[PackedFloat64Array] = []
	var px: float = float(point.x)
	var py: float = float(point.y)
	var low_x: float = INF
	var low_y: float = INF
	var high_x: float = -INF
	var high_y: float = -INF
	for index: int in _items.size():
		low_x = minf(low_x, minf(_ax[index], _bx[index]))
		low_y = minf(low_y, minf(_ay[index], _by[index]))
		high_x = maxf(high_x, maxf(_ax[index], _bx[index]))
		high_y = maxf(high_y, maxf(_ay[index], _by[index]))
		if _length_squared[index] > 0.0:
			var length: float = sqrt(_length_squared[index])
			var nx: float = -_vy[index] / length * safe_radius
			var ny: float = _vx[index] / length * safe_radius
			for side: float in [-1.0, 1.0]:
				var line: Dictionary = {"kind": 0, "ax": _ax[index] + nx * side, "ay": _ay[index] + ny * side,
					"bx": _bx[index] + nx * side, "by": _by[index] + ny * side}
				curves.append(line)
				var fraction: float = clampf(((px - float(line["ax"])) * _vx[index] + (py - float(line["ay"])) * _vy[index]) / _length_squared[index], 0.0, 1.0)
				candidates.append(PackedFloat64Array([float(line["ax"]) + _vx[index] * fraction, float(line["ay"]) + _vy[index] * fraction]))
		for endpoint: int in range(1 if _length_squared[index] == 0.0 else 2):
			var cx: float = _ax[index] if endpoint == 0 else _bx[index]
			var cy: float = _ay[index] if endpoint == 0 else _by[index]
			curves.append({"kind": 1, "x": cx, "y": cy, "r": safe_radius})
			var ox: float = px - cx
			var oy: float = py - cy
			var length: float = sqrt(ox * ox + oy * oy)
			if length > EPSILON:
				candidates.append(PackedFloat64Array([cx + ox / length * safe_radius, cy + oy / length * safe_radius]))
			else:
				candidates.append(PackedFloat64Array([cx + safe_radius, cy]))
				candidates.append(PackedFloat64Array([cx - safe_radius, cy]))
				candidates.append(PackedFloat64Array([cx, cy + safe_radius]))
				candidates.append(PackedFloat64Array([cx, cy - safe_radius]))
	# Guaranteed finite fallbacks outside the complete wall envelope.
	candidates.append(PackedFloat64Array([low_x - safe_radius, py]))
	candidates.append(PackedFloat64Array([high_x + safe_radius, py]))
	candidates.append(PackedFloat64Array([px, low_y - safe_radius]))
	candidates.append(PackedFloat64Array([px, high_y + safe_radius]))
	var best: PackedFloat64Array = PackedFloat64Array([INF, INF, INF])
	for candidate: PackedFloat64Array in candidates:
		best = _closer_free(candidate, px, py, clearance, best)
	for first: int in curves.size():
		if _curve_distance_squared(curves[first], px, py) > best[2]:
			continue
		for second: int in range(first + 1, curves.size()):
			if _curve_distance_squared(curves[second], px, py) > best[2]:
				continue
			var intersections: PackedFloat64Array = _intersections(curves[first], curves[second])
			for at: int in range(0, intersections.size(), 2):
				best = _closer_free(PackedFloat64Array([intersections[at], intersections[at + 1]]), px, py, clearance, best)
	return Vector2(best[0], best[1])


func _closer_free(candidate: PackedFloat64Array, px: float, py: float, radius: float, best: PackedFloat64Array) -> PackedFloat64Array:
	var dx: float = candidate[0] - px
	var dy: float = candidate[1] - py
	var distance_squared: float = dx * dx + dy * dy
	if distance_squared >= best[2] or not _free_xy(candidate[0], candidate[1], radius):
		return best
	# Check the actual Vector2 returned to callers, after float32 quantization.
	var rounded := Vector2(candidate[0], candidate[1])
	if not rounded.is_finite() or not _free_xy(float(rounded.x), float(rounded.y), radius):
		return best
	return PackedFloat64Array([candidate[0], candidate[1], distance_squared])


static func _curve_distance_squared(curve: Dictionary, x: float, y: float) -> float:
	if int(curve["kind"]) == 1:
		var dx: float = x - float(curve["x"])
		var dy: float = y - float(curve["y"])
		var distance: float = sqrt(dx * dx + dy * dy) - float(curve["r"])
		return distance * distance
	var vx: float = float(curve["bx"]) - float(curve["ax"])
	var vy: float = float(curve["by"]) - float(curve["ay"])
	var fraction: float = clampf(((x - float(curve["ax"])) * vx + (y - float(curve["ay"])) * vy) / (vx * vx + vy * vy), 0.0, 1.0)
	var dx: float = x - (float(curve["ax"]) + vx * fraction)
	var dy: float = y - (float(curve["ay"]) + vy * fraction)
	return dx * dx + dy * dy


static func _intersections(first: Dictionary, second: Dictionary) -> PackedFloat64Array:
	if int(first["kind"]) == 1 and int(second["kind"]) == 1:
		return _circle_circle(first, second)
	if int(first["kind"]) == 1:
		return _line_circle(second, first)
	if int(second["kind"]) == 1:
		return _line_circle(first, second)
	var ax: float = float(first["ax"])
	var ay: float = float(first["ay"])
	var vx: float = float(first["bx"]) - ax
	var vy: float = float(first["by"]) - ay
	var wx: float = float(second["bx"]) - float(second["ax"])
	var wy: float = float(second["by"]) - float(second["ay"])
	var cross: float = vx * wy - vy * wx
	if absf(cross) <= EPSILON:
		return PackedFloat64Array()
	var ox: float = float(second["ax"]) - ax
	var oy: float = float(second["ay"]) - ay
	var t: float = (ox * wy - oy * wx) / cross
	var u: float = (ox * vy - oy * vx) / cross
	return PackedFloat64Array([ax + vx * t, ay + vy * t]) if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0 else PackedFloat64Array()


static func _line_circle(line: Dictionary, circle: Dictionary) -> PackedFloat64Array:
	var ax: float = float(line["ax"])
	var ay: float = float(line["ay"])
	var vx: float = float(line["bx"]) - ax
	var vy: float = float(line["by"]) - ay
	var ox: float = ax - float(circle["x"])
	var oy: float = ay - float(circle["y"])
	var radius: float = float(circle["r"])
	var a: float = vx * vx + vy * vy
	var b: float = ox * vx + oy * vy
	var c: float = ox * ox + oy * oy - radius * radius
	var discriminant: float = b * b - a * c
	if discriminant < 0.0:
		return PackedFloat64Array()
	var root: float = sqrt(discriminant)
	var result := PackedFloat64Array()
	for time: float in [(-b - root) / a, (-b + root) / a]:
		if time >= 0.0 and time <= 1.0:
			result.append(ax + vx * time)
			result.append(ay + vy * time)
	return result


static func _circle_circle(first: Dictionary, second: Dictionary) -> PackedFloat64Array:
	var ax: float = float(first["x"])
	var ay: float = float(first["y"])
	var vx: float = float(second["x"]) - ax
	var vy: float = float(second["y"]) - ay
	var length: float = sqrt(vx * vx + vy * vy)
	var r: float = float(first["r"])
	var s: float = float(second["r"])
	if length <= EPSILON or length > r + s or length < absf(r - s):
		return PackedFloat64Array()
	var along: float = (r * r - s * s + length * length) / (2.0 * length)
	var height: float = sqrt(maxf(0.0, r * r - along * along))
	var cx: float = ax + vx / length * along
	var cy: float = ay + vy / length * along
	var nx: float = -vy / length * height
	var ny: float = vx / length * height
	return PackedFloat64Array([cx + nx, cy + ny, cx - nx, cy - ny])
