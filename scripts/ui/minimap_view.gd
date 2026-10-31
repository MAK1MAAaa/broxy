class_name MinimapView
extends Control
## Event-fed, bounded map projection; no scene polling or gameplay input handlers.

const ENEMY_LIMIT: int = 128
const ENEMY_SCAN_LIMIT: int = 1024
const ZONE_LIMIT: int = 32
const OBSTACLE_LIMIT: int = 64
const PICKUP_LIMIT: int = 24
const PICKUP_SCAN_LIMIT: int = 128
const WALL_LIMIT: int = 512
const INSET: float = 8.0
const PAPER: Color = Color("fff9e8")
const INK: Color = Color("253d54")
const CYAN: Color = Color("14766f")
const GOLD: Color = Color("ba985e")
const RED: Color = Color("b83c50")

var _valid: bool = false
var _bounds: Rect2 = Rect2()
var _player: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.UP
var _view: Rect2 = Rect2()
var _arena_id: String = ""
var _enemies: Array[Dictionary] = []
var _zones: Array[Dictionary] = []
var _obstacles: Array[Dictionary] = []
var _walls: Array[Dictionary] = []
var _pickups: Array[Dictionary] = []
var _pinball_active: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	resized.connect(queue_redraw)
	set_process(false)
	set_physics_process(false)
	visible = _valid

func update_snapshot(value: Variant) -> void:
	_clear()
	if not value is Dictionary:
		_finish_update()
		return
	var bounds: Variant = value.get("bounds")
	var player: Variant = value.get("player")
	if not _valid_rect(bounds) or not player is Vector2 or not player.is_finite():
		_finish_update()
		return
	_bounds = bounds
	_player = _clamp_world(player)
	var facing: Variant = value.get("facing")
	if facing is Vector2 and facing.is_finite() and facing.length_squared() > 0.00001:
		_facing = facing.normalized()
	var view: Variant = value.get("view")
	if _valid_rect(view):
		_view = _bounds.intersection(view)
	_arena_id = str(value.get("arena_id", ""))
	_read_enemies(value.get("enemies", []))
	_read_zones(value.get("zones", []))
	_read_obstacles(value.get("obstacles", []))
	_read_walls(value.get("walls", []))
	_read_pickups(value.get("pickups", []))
	_pinball_active = value.get("pinball_active", false) == true
	_valid = true
	_finish_update()

func _clear() -> void:
	_valid = false
	_bounds = Rect2()
	_player = Vector2.ZERO
	_facing = Vector2.UP
	_view = Rect2()
	_arena_id = ""
	_enemies.clear()
	_zones.clear()
	_obstacles.clear()
	_walls.clear()
	_pickups.clear()
	_pinball_active = false

func _finish_update() -> void:
	visible = _valid
	queue_redraw()

static func _valid_rect(value: Variant) -> bool:
	return value is Rect2 and value.position.is_finite() and value.size.is_finite() and value.end.is_finite() and value.size.x > 0.01 and value.size.y > 0.01 and value.size.x <= 10000000.0 and value.size.y <= 10000000.0

func _clamp_world(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, _bounds.position.x, _bounds.end.x), clampf(point.y, _bounds.position.y, _bounds.end.y))

func _contains(point: Vector2) -> bool:
	return point.x >= _bounds.position.x and point.x <= _bounds.end.x and point.y >= _bounds.position.y and point.y <= _bounds.end.y

func _read_enemies(value: Variant) -> void:
	if not value is Array:
		return
	var priority: Array[Dictionary] = []
	var ordinary: Array[Dictionary] = []
	for index: int in mini(value.size(), ENEMY_SCAN_LIMIT):
		var entry: Variant = value[index]
		if not entry is Dictionary:
			continue
		var point: Variant = entry.get("position")
		if not point is Vector2 or not point.is_finite() or not _contains(point):
			continue
		var boss: bool = entry.get("boss", false) == true
		var hunter: bool = entry.get("hunter", false) == true
		var marker: Dictionary = {"position": point, "boss": boss, "hunter": hunter}
		if boss or hunter:
			if priority.size() < ENEMY_LIMIT:
				priority.append(marker)
		elif ordinary.size() < ENEMY_LIMIT:
			ordinary.append(marker)
	_enemies.assign(priority)
	for index: int in mini(ordinary.size(), ENEMY_LIMIT - _enemies.size()):
		_enemies.append(ordinary[index])

func _read_zones(value: Variant) -> void:
	if not value is Array:
		return
	for index: int in mini(value.size(), ZONE_LIMIT):
		var entry: Variant = value[index]
		if not entry is Dictionary:
			continue
		var center: Variant = entry.get("center")
		var radius: Variant = entry.get("radius")
		if not center is Vector2 or not radius is Vector2 or not center.is_finite() or not radius.is_finite():
			continue
		if radius.x <= 0.0 or radius.y <= 0.0 or radius.x > _bounds.size.x or radius.y > _bounds.size.y:
			continue
		if not _bounds.intersects(Rect2(center - radius, radius * 2.0)):
			continue
		_zones.append({"center": center, "radius": radius})

func _read_obstacles(value: Variant) -> void:
	if not value is Array:
		return
	for index: int in mini(value.size(), OBSTACLE_LIMIT):
		var entry: Variant = value[index]
		if not entry is Dictionary:
			continue
		var center: Variant = entry.get("center")
		var radius: Variant = entry.get("radius")
		if not center is Vector2 or not center.is_finite() or not _contains(center):
			continue
		if not (radius is float or radius is int) or not is_finite(float(radius)):
			continue
		if radius <= 0.0 or radius > minf(_bounds.size.x, _bounds.size.y) * 0.5:
			continue
		if not _bounds.encloses(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)):
			continue
		if entry.get("active", true) != true:
			continue
		var kind: String = "crate" if str(entry.get("kind", "")) == "crate" else "prop"
		_obstacles.append({"center": center, "radius": float(radius), "kind": kind})

func _read_walls(value: Variant) -> void:
	if not value is Array:
		return
	for index: int in mini(value.size(), WALL_LIMIT):
		var entry: Variant = value[index]
		if not entry is Dictionary:
			continue
		var a: Vector2 = ArenaObstacles._read_point(entry.get("a"))
		var b: Vector2 = ArenaObstacles._read_point(entry.get("b"))
		if not a.is_finite() or not b.is_finite():
			continue
		var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), PackedVector2Array([_bounds.position, Vector2(_bounds.end.x, _bounds.position.y), _bounds.end, Vector2(_bounds.position.x, _bounds.end.y)]))
		for line: PackedVector2Array in clipped:
			for point: int in maxi(0, line.size() - 1):
				if _walls.size() >= WALL_LIMIT:
					return
				_walls.append({"a": line[point], "b": line[point + 1]})

func _read_pickups(value: Variant) -> void:
	if not value is Array:
		return
	for index: int in mini(value.size(), PICKUP_SCAN_LIMIT):
		if _pickups.size() >= PICKUP_LIMIT:
			break
		var entry: Variant = value[index]
		if not entry is Dictionary or entry.get("active", true) != true:
			continue
		var point: Variant = entry.get("position")
		var kind: String = str(entry.get("kind", ""))
		if not point is Vector2 or not point.is_finite() or not _contains(point) or kind not in ["gold", "health", "charge"]:
			continue
		_pickups.append({"position": point, "kind": kind})

func map_rect() -> Rect2:
	if not _valid or size.x <= INSET * 2.0 or size.y <= INSET * 2.0:
		return Rect2()
	var available: Vector2 = size - Vector2.ONE * INSET * 2.0
	var factor: float = minf(available.x / _bounds.size.x, available.y / _bounds.size.y)
	var extent: Vector2 = _bounds.size * factor
	return Rect2((size - extent) * 0.5, extent)

func world_to_map(point: Vector2) -> Vector2:
	var area: Rect2 = map_rect()
	if not _valid or not point.is_finite() or not area.has_area():
		return Vector2.ZERO
	return area.position + (_clamp_world(point) - _bounds.position) / _bounds.size * area.size

func presentation_snapshot() -> Dictionary:
	var crates: int = 0
	for obstacle: Dictionary in _obstacles:
		crates += 1 if obstacle["kind"] == "crate" else 0
	return {"valid": _valid, "bounds": _bounds, "player": _player, "facing": _facing, "view": _view,
		"arena_id": _arena_id, "enemies": _enemies.duplicate(true), "zones": _zones.duplicate(true),
		"obstacles": _obstacles.duplicate(true), "obstacle_count": _obstacles.size(),
		"walls": _walls.duplicate(true), "wall_count": _walls.size(),
		"crate_count": crates, "pickups": _pickups.duplicate(true), "pickup_count": _pickups.size(), "pickup_limit": PICKUP_LIMIT, "pinball_active": _pinball_active,
		"enemy_count": _enemies.size(), "zone_count": _zones.size(), "enemy_limit": ENEMY_LIMIT}

func _draw() -> void:
	if not _valid or size.x < 24.0 or size.y < 24.0:
		return
	draw_rect(Rect2(Vector2(1, 3), size - Vector2(1, 3)), Color(INK, 0.20))
	draw_rect(Rect2(Vector2.ZERO, size - Vector2(1, 2)), Color(PAPER, 0.94))
	draw_rect(Rect2(Vector2.ONE, size - Vector2(3, 4)), Color(GOLD, 0.65), false, 1.0)
	var area: Rect2 = map_rect()
	if not area.has_area():
		return
	draw_rect(area, Color("d4e3d7"))
	_draw_zones(area)
	_draw_obstacles(area)
	for wall: Dictionary in _walls:
		draw_line(world_to_map(wall["a"]), world_to_map(wall["b"]), Color(INK, 0.75), 1.0)
	draw_rect(area, Color(CYAN, 0.65), false, 1.0)
	_draw_view(area)
	_draw_pickups(area)
	_draw_enemies(area)
	_draw_player(area)

func _draw_zones(area: Rect2) -> void:
	var color: Color = Color("7da99a")
	if _arena_id == "glacier":
		color = Color("a5bdce")
	elif _arena_id == "ashland":
		color = Color("c4a084")
	for zone: Dictionary in _zones:
		var points := PackedVector2Array()
		for index: int in 20:
			var angle: float = float(index) * TAU / 20.0
			var point: Vector2 = zone["center"] + Vector2(cos(angle), sin(angle)) * zone["radius"]
			var local: Vector2 = world_to_map(point)
			local = Vector2(clampf(local.x, area.position.x, area.end.x), clampf(local.y, area.position.y, area.end.y))
			if points.is_empty() or not points[-1].is_equal_approx(local):
				points.append(local)
		if points.size() > 1 and points[0].is_equal_approx(points[-1]):
			points.remove_at(points.size() - 1)
		var signed_area: float = 0.0
		for index: int in points.size():
			signed_area += points[index].cross(points[(index + 1) % points.size()])
		if points.size() >= 3 and absf(signed_area) > 0.1:
			draw_colored_polygon(points, color)

func _draw_obstacles(area: Rect2) -> void:
	var scale: float = area.size.x / _bounds.size.x
	for obstacle: Dictionary in _obstacles:
		var point: Vector2 = world_to_map(obstacle["center"])
		var radius: float = maxf(1.5, obstacle["radius"] * scale)
		if obstacle["kind"] == "crate":
			draw_rect(Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), GOLD)
			draw_rect(Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), Color(INK, 0.70), false, 1.0)
			continue
		draw_circle(point, radius, Color(INK, 0.66))
		draw_arc(point, radius, 0.0, TAU, 8, Color(PAPER, 0.66), 1.0)

func _draw_pickups(area: Rect2) -> void:
	var inner: Rect2 = area.grow(-3.0)
	for pickup: Dictionary in _pickups:
		var point: Vector2 = world_to_map(pickup["position"])
		point = Vector2(clampf(point.x, inner.position.x, inner.end.x), clampf(point.y, inner.position.y, inner.end.y))
		match str(pickup["kind"]):
			"health":
				draw_line(point - Vector2(2, 0), point + Vector2(2, 0), CYAN, 2.0)
				draw_line(point - Vector2(0, 2), point + Vector2(0, 2), CYAN, 2.0)
			"charge":
				draw_colored_polygon(PackedVector2Array([point + Vector2(0, -3), point + Vector2(2, 0), point + Vector2(0, 3), point - Vector2(2, 0)]), Color("765093"))
			"gold":
				draw_circle(point, 2.0, GOLD)

func _draw_view(area: Rect2) -> void:
	if not _view.has_area():
		return
	var frame := Rect2(world_to_map(_view.position), world_to_map(_view.end) - world_to_map(_view.position))
	frame = area.intersection(frame)
	if frame.has_area():
		draw_rect(frame, Color(PAPER, 0.14))
		draw_rect(frame, Color(PAPER, 0.94), false, 1.0)

func _draw_enemies(area: Rect2) -> void:
	var inner: Rect2 = area.grow(-3.0)
	for entry: Dictionary in _enemies:
		var point: Vector2 = world_to_map(entry["position"])
		point = Vector2(clampf(point.x, inner.position.x, inner.end.x), clampf(point.y, inner.position.y, inner.end.y))
		if entry["boss"]:
			draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), PAPER)
			draw_rect(Rect2(point - Vector2(2, 2), Vector2(4, 4)), RED)
		elif entry["hunter"]:
			draw_colored_polygon(PackedVector2Array([point + Vector2(0, -3), point + Vector2(3, 0), point + Vector2(0, 3), point + Vector2(-3, 0)]), RED)
			draw_rect(Rect2(point - Vector2.ONE, Vector2(2, 2)), GOLD)
		else:
			draw_rect(Rect2(point.floor() - Vector2.ONE, Vector2(2, 2)), RED)

func _draw_player(area: Rect2) -> void:
	var inner: Rect2 = area.grow(-6.0)
	var point: Vector2 = world_to_map(_player)
	point = Vector2(clampf(point.x, inner.position.x, inner.end.x), clampf(point.y, inner.position.y, inner.end.y))
	if _pinball_active:
		draw_arc(point, 6.0, 0.0, TAU, 12, GOLD, 1.0)
	var tangent: Vector2 = _facing.orthogonal()
	var outer := PackedVector2Array([point + _facing * 6.0, point - _facing * 4.0 + tangent * 4.0, point - _facing * 2.0, point - _facing * 4.0 - tangent * 4.0])
	var center := PackedVector2Array([point + _facing * 4.0, point - _facing * 2.5 + tangent * 2.5, point - _facing, point - _facing * 2.5 - tangent * 2.5])
	draw_colored_polygon(outer, INK)
	draw_colored_polygon(center, PAPER)
