class_name TerrainWalls
extends RefCounted
## Exact open segments, expanded to capsules by the querying body's radius.
## No bounds closure, sampled circles, or prop collision is inferred here.

const SKIN: float = 0.002
const EPSILON: float = 0.000000001
const MAX_SLIDES: int = 8
const POINT_CACHE_LIMIT: int = 1024
const ROUND_TRIP_RELATIVE_MARGIN: float = 8.881784197001252e-16

var last_error: String = ""
var last_navigation_blocker: int = -1
var _items: Array[Dictionary] = []
var _ax: PackedFloat64Array = PackedFloat64Array()
var _ay: PackedFloat64Array = PackedFloat64Array()
var _bx: PackedFloat64Array = PackedFloat64Array()
var _by: PackedFloat64Array = PackedFloat64Array()
var _vx: PackedFloat64Array = PackedFloat64Array()
var _vy: PackedFloat64Array = PackedFloat64Array()
var _length_squared: PackedFloat64Array = PackedFloat64Array()
var _bounds_min_x: PackedFloat64Array = PackedFloat64Array()
var _bounds_min_y: PackedFloat64Array = PackedFloat64Array()
var _bounds_max_x: PackedFloat64Array = PackedFloat64Array()
var _bounds_max_y: PackedFloat64Array = PackedFloat64Array()
var _tree_min_x: PackedFloat64Array = PackedFloat64Array()
var _tree_min_y: PackedFloat64Array = PackedFloat64Array()
var _tree_max_x: PackedFloat64Array = PackedFloat64Array()
var _tree_max_y: PackedFloat64Array = PackedFloat64Array()
var _nearest_min_x: PackedFloat64Array = PackedFloat64Array()
var _nearest_min_y: PackedFloat64Array = PackedFloat64Array()
var _nearest_max_x: PackedFloat64Array = PackedFloat64Array()
var _nearest_max_y: PackedFloat64Array = PackedFloat64Array()
var _tree_wall: PackedInt32Array = PackedInt32Array()
var _tree_escape: PackedInt32Array = PackedInt32Array()
var _point_query_caches: Dictionary = {}


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
		_bounds_min_x.append(minf(_ax[-1], _bx[-1]))
		_bounds_min_y.append(minf(_ay[-1], _by[-1]))
		_bounds_max_x.append(maxf(_ax[-1], _bx[-1]))
		_bounds_max_y.append(maxf(_ay[-1], _by[-1]))
	if not _items.is_empty():
		var indices: Array[int] = []
		for index: int in _items.size():
			indices.append(index)
		_append_spatial_node(indices)
	return true


func clear() -> void:
	last_navigation_blocker = -1
	_items.clear()
	_ax.clear()
	_ay.clear()
	_bx.clear()
	_by.clear()
	_vx.clear()
	_vy.clear()
	_length_squared.clear()
	_bounds_min_x.clear()
	_bounds_min_y.clear()
	_bounds_max_x.clear()
	_bounds_max_y.clear()
	_tree_min_x.clear()
	_tree_min_y.clear()
	_tree_max_x.clear()
	_tree_max_y.clear()
	_nearest_min_x.clear()
	_nearest_min_y.clear()
	_nearest_max_x.clear()
	_nearest_max_y.clear()
	_tree_wall.clear()
	_tree_escape.clear()
	_point_query_caches.clear()
	last_error = ""


func _append_spatial_node(indices: Array[int]) -> void:
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	var nearest_min_x: float = INF
	var nearest_min_y: float = INF
	var nearest_max_x: float = -INF
	var nearest_max_y: float = -INF
	for index: int in indices:
		min_x = minf(min_x, _bounds_min_x[index])
		min_y = minf(min_y, _bounds_min_y[index])
		max_x = maxf(max_x, _bounds_max_x[index])
		max_y = maxf(max_y, _bounds_max_y[index])
		# The original projection reconstructs b as a + (b - a), including rounding.
		var end_x: float = _ax[index] + _vx[index]
		var end_y: float = _ay[index] + _vy[index]
		nearest_min_x = minf(nearest_min_x, minf(_ax[index], end_x))
		nearest_min_y = minf(nearest_min_y, minf(_ay[index], end_y))
		nearest_max_x = maxf(nearest_max_x, maxf(_ax[index], end_x))
		nearest_max_y = maxf(nearest_max_y, maxf(_ay[index], end_y))
	var node: int = _tree_wall.size()
	_tree_min_x.append(min_x)
	_tree_min_y.append(min_y)
	_tree_max_x.append(max_x)
	_tree_max_y.append(max_y)
	_nearest_min_x.append(nearest_min_x)
	_nearest_min_y.append(nearest_min_y)
	_nearest_max_x.append(nearest_max_x)
	_nearest_max_y.append(nearest_max_y)
	_tree_wall.append(indices[0] if indices.size() == 1 else -1)
	_tree_escape.append(0)
	if indices.size() > 1:
		var split_x: bool = max_x - min_x >= max_y - min_y
		indices.sort_custom(func(first: int, second: int) -> bool:
			var first_center: float = _bounds_min_x[first] + (_bounds_max_x[first] - _bounds_min_x[first]) * 0.5 if split_x else _bounds_min_y[first] + (_bounds_max_y[first] - _bounds_min_y[first]) * 0.5
			var second_center: float = _bounds_min_x[second] + (_bounds_max_x[second] - _bounds_min_x[second]) * 0.5 if split_x else _bounds_min_y[second] + (_bounds_max_y[second] - _bounds_min_y[second]) * 0.5
			return first_center < second_center or (first_center == second_center and first < second)
		)
		var middle: int = indices.size() / 2
		_append_spatial_node(indices.slice(0, middle))
		_append_spatial_node(indices.slice(middle))
	_tree_escape[node] = _tree_wall.size()


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
	var node: int = 0
	while node < _tree_wall.size():
		if x < _tree_min_x[node] - radius or x > _tree_max_x[node] + radius or y < _tree_min_y[node] - radius or y > _tree_max_y[node] + radius:
			node = _tree_escape[node]
			continue
		var index: int = _tree_wall[node]
		node += 1
		if index < 0:
			continue
		var fraction: float = _fraction(index, x, y)
		var dx: float = x - (_ax[index] + _vx[index] * fraction)
		var dy: float = y - (_ay[index] + _vy[index] * fraction)
		var distance_squared: float = dx * dx + dy * dy
		if distance_squared < r2 - EPSILON or (radius == 0.0 and distance_squared <= EPSILON * EPSILON):
			return false
	return true


func is_free(point: Vector2, radius: float = 0.0, padding: float = 0.0) -> bool:
	if not _valid_query(point, radius, padding):
		return false
	var clearance: float = radius + padding
	var cache: Dictionary = _point_cache_for(clearance)
	var cached: Variant = cache.get(point)
	if cached is bool:
		return cached
	var result: bool = _free_xy(float(point.x), float(point.y), clearance)
	if cache.size() >= POINT_CACHE_LIMIT:
		cache.clear()
	cache[point] = result
	return result


func _point_cache_for(clearance: float) -> Dictionary:
	var existing: Variant = _point_query_caches.get(clearance)
	if existing is Dictionary:
		return existing
	var cache: Dictionary = {}
	_point_query_caches[clearance] = cache
	return cache


func nearest_point(point: Vector2) -> Dictionary:
	if not point.is_finite() or _items.is_empty():
		return {}
	var x: float = float(point.x)
	var y: float = float(point.y)
	var best_index: int = -1
	var best_squared: float = INF
	var best_fraction: float = 0.0
	var node: int = 0
	while node < _tree_wall.size():
		var low_dx: float = maxf(0.0, maxf(_nearest_min_x[node] - x, x - _nearest_max_x[node]))
		var low_dy: float = maxf(0.0, maxf(_nearest_min_y[node] - y, y - _nearest_max_y[node]))
		if low_dx * low_dx + low_dy * low_dy > best_squared:
			node = _tree_escape[node]
			continue
		var index: int = _tree_wall[node]
		node += 1
		if index < 0:
			continue
		var fraction: float = _fraction(index, x, y)
		var dx: float = x - (_ax[index] + _vx[index] * fraction)
		var dy: float = y - (_ay[index] + _vy[index] * fraction)
		var distance_squared: float = dx * dx + dy * dy
		if distance_squared < best_squared or (distance_squared == best_squared and index < best_index):
			best_index = index
			best_squared = distance_squared
			best_fraction = fraction
	return _contact(best_index, x, y, 0.0, 0.0, best_fraction, 0.0)


func first_hit(start: Vector2, end: Vector2, radius: float = 0.0, padding: float = 0.0) -> Dictionary:
	if not _valid_query(start, radius, padding) or not end.is_finite():
		return {}
	var sx: float = float(start.x)
	var sy: float = float(start.y)
	var dx: float = float(end.x) - sx
	var dy: float = float(end.y) - sy
	var clearance: float = radius + padding
	var low_x: float = minf(sx, sx + dx)
	var high_x: float = maxf(sx, sx + dx)
	var low_y: float = minf(sy, sy + dy)
	var high_y: float = maxf(sy, sy + dy)
	var best: float = INF
	var winner: int = -1
	var node: int = 0
	while node < _tree_wall.size():
		if high_x < _tree_min_x[node] - clearance or low_x > _tree_max_x[node] + clearance or high_y < _tree_min_y[node] - clearance or low_y > _tree_max_y[node] + clearance:
			node = _tree_escape[node]
			continue
		var index: int = _tree_wall[node]
		node += 1
		if index < 0:
			continue
		var hit: float = _entry_time(index, sx, sy, dx, dy, clearance)
		if hit < best or (hit == best and index < winner):
			best = hit
			winner = index
	if winner < 0:
		return {}
	var x: float = sx + dx * best
	var y: float = sy + dy * best
	return _contact(winner, x, y, dx, dy, _fraction(winner, x, y), best)


func segment_clear(start: Vector2, end: Vector2, radius: float = 0.0, padding: float = 0.0) -> bool:
	if not _valid_query(start, radius, padding) or not end.is_finite():
		return false
	var sx: float = float(start.x)
	var sy: float = float(start.y)
	var dx: float = float(end.x) - sx
	var dy: float = float(end.y) - sy
	var clearance: float = radius + padding
	var low_x: float = minf(sx, sx + dx)
	var high_x: float = maxf(sx, sx + dx)
	var low_y: float = minf(sy, sy + dy)
	var high_y: float = maxf(sy, sy + dy)
	var node: int = 0
	while node < _tree_wall.size():
		if high_x < _tree_min_x[node] - clearance or low_x > _tree_max_x[node] + clearance or high_y < _tree_min_y[node] - clearance or low_y > _tree_max_y[node] + clearance:
			node = _tree_escape[node]
			continue
		var index: int = _tree_wall[node]
		node += 1
		if index >= 0 and _entry_time(index, sx, sy, dx, dy, clearance) < INF:
			return false
	return true


func navigation_clear(start: Vector2, end: Vector2, radius: float = 0.0, padding: float = 0.0) -> bool:
	last_navigation_blocker = -1
	if not _valid_query(start, radius, padding) or not end.is_finite():
		return false
	var clearance: float = radius + padding
	var cache: Dictionary = _point_cache_for(clearance)
	var start_cached: Variant = cache.get(start)
	var end_cached: Variant = cache.get(end)
	if (start_cached is bool and not start_cached) or (end_cached is bool and not end_cached):
		return false
	var check_start: bool = not (start_cached is bool)
	var check_end: bool = not (end_cached is bool)
	var sx: float = float(start.x)
	var sy: float = float(start.y)
	var ex: float = float(end.x)
	var ey: float = float(end.y)
	var dx: float = ex - sx
	var dy: float = ey - sy
	var r2: float = clearance * clearance
	var segment_low_x: float = minf(sx, sx + dx)
	var segment_high_x: float = maxf(sx, sx + dx)
	var segment_low_y: float = minf(sy, sy + dy)
	var segment_high_y: float = maxf(sy, sy + dy)
	# The real endpoint may differ from the segment's reconstructed endpoint.
	var low_x: float = minf(segment_low_x, ex)
	var high_x: float = maxf(segment_high_x, ex)
	var low_y: float = minf(segment_low_y, ey)
	var high_y: float = maxf(segment_high_y, ey)
	var node: int = 0
	while node < _tree_wall.size():
		var min_x: float = _tree_min_x[node] - clearance
		var max_x: float = _tree_max_x[node] + clearance
		var min_y: float = _tree_min_y[node] - clearance
		var max_y: float = _tree_max_y[node] + clearance
		if high_x < min_x or low_x > max_x or high_y < min_y or low_y > max_y:
			node = _tree_escape[node]
			continue
		var index: int = _tree_wall[node]
		node += 1
		if index < 0:
			continue
		if check_start and not (sx < min_x or sx > max_x or sy < min_y or sy > max_y):
			var fraction: float = _fraction(index, sx, sy)
			var ox: float = sx - (_ax[index] + _vx[index] * fraction)
			var oy: float = sy - (_ay[index] + _vy[index] * fraction)
			var distance_squared: float = ox * ox + oy * oy
			if distance_squared < r2 - EPSILON or (clearance == 0.0 and distance_squared <= EPSILON * EPSILON):
				last_navigation_blocker = index
				return false
		if check_end and not (ex < min_x or ex > max_x or ey < min_y or ey > max_y):
			var fraction: float = _fraction(index, ex, ey)
			var ox: float = ex - (_ax[index] + _vx[index] * fraction)
			var oy: float = ey - (_ay[index] + _vy[index] * fraction)
			var distance_squared: float = ox * ox + oy * oy
			if distance_squared < r2 - EPSILON or (clearance == 0.0 and distance_squared <= EPSILON * EPSILON):
				last_navigation_blocker = index
				return false
		if not (segment_high_x < min_x or segment_low_x > max_x or segment_high_y < min_y or segment_low_y > max_y):
			if _entry_time(index, sx, sy, dx, dy, clearance) < INF:
				last_navigation_blocker = index
				return false
	if check_start or check_end:
		var additions: int = int(check_start) + int(check_end and end != start)
		if cache.size() + additions > POINT_CACHE_LIMIT:
			cache.clear()
		cache[start] = true
		cache[end] = true
	return true


func rejects_sweep(index: int, start: Vector2, end: Vector2, radius: float = 0.0, padding: float = 0.0) -> bool:
	if index < 0 or index >= _items.size() or not _valid_query(start, radius, padding) or not end.is_finite():
		return false
	var sx: float = float(start.x)
	var sy: float = float(start.y)
	var dx: float = float(end.x) - sx
	var dy: float = float(end.y) - sy
	var clearance: float = radius + padding
	if maxf(sx, sx + dx) < _bounds_min_x[index] - clearance or minf(sx, sx + dx) > _bounds_max_x[index] + clearance \
		or maxf(sy, sy + dy) < _bounds_min_y[index] - clearance or minf(sy, sy + dy) > _bounds_max_y[index] + clearance:
		return false
	return _entry_time(index, sx, sy, dx, dy, clearance) < INF


func bounds_clear(region: Rect2, radius: float, padding: float = 0.0) -> bool:
	if not _valid_query(region.position, radius, padding) or not region.size.is_finite() or region.size.x <= 0.0 or region.size.y <= 0.0:
		return false
	var end: Vector2 = region.end
	if not end.is_finite() or end.x <= region.position.x or end.y <= region.position.y:
		return false
	var clearance: float = radius + padding
	var low_x: float = float(region.position.x)
	var high_x: float = float(end.x)
	var low_y: float = float(region.position.y)
	var high_y: float = float(end.y)
	# Bound both float64 operations in start + (end - start), including cancellation.
	var margin_x: float = maxf(absf(low_x), absf(high_x)) * ROUND_TRIP_RELATIVE_MARGIN
	var margin_y: float = maxf(absf(low_y), absf(high_y)) * ROUND_TRIP_RELATIVE_MARGIN
	low_x -= margin_x
	high_x += margin_x
	low_y -= margin_y
	high_y += margin_y
	var node: int = 0
	while node < _tree_wall.size():
		if high_x < _tree_min_x[node] - clearance or low_x > _tree_max_x[node] + clearance or high_y < _tree_min_y[node] - clearance or low_y > _tree_max_y[node] + clearance:
			node = _tree_escape[node]
			continue
		if _tree_wall[node] >= 0:
			return false
		node += 1
	return true


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
