extends RefCounted
## Bounded cosmetic casts; precise range edges surround distinct pixel-cut interiors.

const LIMIT: int = 8
const LIFE: float = 0.26
const MAX_POLYGONS: int = 8
const MAX_DETAIL_POINTS: int = 16
const BAND_SEGMENTS: int = 16
const INK: Color = Color("243752")
const GOLD: Color = Color("ffc86b")
const CORE: Color = Color("fff1cf")
const CYAN: Color = Color("91e0d1")
const WIND: Color = Color("87d9ab")
const AMBER: Color = Color("efa54c")
const FIRE: Color = Color("f1875e")
const VISUAL_REVISION: String = "pixel-cast-families-v1"

class Cast:
	var id: String = ""
	var family: String = "meteor"
	var origin: Vector2 = Vector2.ZERO
	var direction: Vector2 = Vector2.RIGHT
	var radius: float = 0.0
	var life: float = 0.0
	var animated: bool = false
	var shape: String = "circle"
	var half_angle: float = deg_to_rad(50.0)
	var width: float = 70.0
	var color: Color = GOLD
	var polygons: Array[PackedVector2Array] = []
	var borders: Array[PackedVector2Array] = []
	var tones: PackedByteArray = PackedByteArray()
	var outlined: PackedByteArray = PackedByteArray()
	var details: PackedVector2Array = PackedVector2Array()
	var polygon_count: int = 0

	func _init() -> void:
		for index: int in MAX_POLYGONS:
			polygons.append(PackedVector2Array())
			borders.append(PackedVector2Array())
		tones.resize(MAX_POLYGONS)
		outlined.resize(MAX_POLYGONS)

var _pool: Array[Cast] = []
var _next: int = 0

func _init() -> void:
	for index: int in LIMIT:
		_pool.append(Cast.new())

func add_cast(id: String, origin: Vector2, direction: Vector2, radius: float, animated: bool) -> bool:
	if id not in ["starfall", "arc_slash"] or not _valid_origin(origin, direction, radius):
		return false
	var cast: Cast = _take_cast(id, origin, direction, radius, animated)
	cast.shape = "arc" if id == "arc_slash" else "circle"
	cast.half_angle = deg_to_rad(50.0)
	cast.width = 70.0
	cast.family = "crescent" if id == "arc_slash" else "meteor"
	cast.color = CYAN if id == "arc_slash" else GOLD
	return true

func add_hero_cast(parameters: Dictionary, origin: Vector2, direction: Vector2, animated: bool) -> bool:
	var radius: float = _number(parameters.get("radius"), 0.0)
	var shape: String = str(parameters.get("shape", ""))
	var angle: float = _number(parameters.get("half_angle_radians"), deg_to_rad(50.0))
	var width: float = _number(parameters.get("width"), 70.0)
	if shape not in ["arc", "circle", "line"] or not _valid_origin(origin, direction, radius):
		return false
	if not is_finite(angle) or not is_finite(width) or width <= 0.0 or (shape == "arc" and (angle <= 0.0 or angle > PI)):
		return false
	var cast: Cast = _take_cast(str(parameters.get("id", "")), origin, direction, radius, animated)
	cast.shape = shape
	cast.half_angle = angle
	cast.width = width
	match cast.id:
		"hero_alk":
			cast.family = "blade"
			cast.color = GOLD
		"hero_celtie":
			cast.family = "wind"
			cast.color = WIND
		"hero_clarisse":
			cast.family = "alchemy"
			cast.color = AMBER
		"hero_hanabi":
			cast.family = "firework"
			cast.color = FIRE
		_:
			cast.family = "blade" if shape == "arc" else "firework" if shape == "line" else "meteor"
			cast.color = GOLD
	return true

func _take_cast(id: String, origin: Vector2, direction: Vector2, radius: float, animated: bool) -> Cast:
	var cast: Cast = _pool[_next]
	_next = (_next + 1) % LIMIT
	cast.id = id
	cast.origin = origin
	cast.direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	cast.radius = radius
	cast.life = LIFE
	cast.animated = animated
	cast.polygon_count = 0
	cast.details.clear()
	return cast

static func _valid_origin(origin: Vector2, direction: Vector2, radius: float) -> bool:
	return origin.is_finite() and direction.is_finite() and is_finite(radius) and radius > 0.0

static func _number(value: Variant, fallback: float) -> float:
	return float(value) if value is int or value is float else fallback

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for cast: Cast in _pool:
		cast.life = maxf(0.0, cast.life - delta)

func clear() -> void:
	for cast: Cast in _pool:
		cast.life = 0.0
	_next = 0

func disable_animation() -> void:
	for cast: Cast in _pool:
		cast.animated = false

func snapshot() -> Dictionary:
	var active: int = 0
	var animated: int = 0
	for cast: Cast in _pool:
		if cast.life > 0.0:
			active += 1
			animated += int(cast.animated)
	return {"active": active, "animated": animated, "capacity": _pool.size()}

func draw(canvas: CanvasItem) -> void:
	if canvas == null:
		return
	var transformed: bool = false
	for cast: Cast in _pool:
		if cast.life <= 0.0:
			continue
		var progress: float = clampf(1.0 - cast.life / LIFE, 0.0, 1.0)
		var alpha: float = (1.0 - progress) * 0.85 if cast.animated else 0.32
		canvas.draw_set_transform(cast.origin, cast.direction.angle())
		transformed = true
		_draw_range(canvas, cast, alpha)
		if cast.animated:
			_prepare_geometry(cast, progress)
			_draw_interior(canvas, cast, alpha)
	if transformed:
		canvas.draw_set_transform(Vector2.ZERO)

func _draw_range(canvas: CanvasItem, cast: Cast, alpha: float) -> void:
	var color := Color(cast.color, alpha * (0.18 if cast.animated else 0.8))
	var line_width: float = 1.0 if cast.animated else 2.0
	if cast.shape == "arc":
		canvas.draw_arc(Vector2.ZERO, cast.radius, -cast.half_angle, cast.half_angle, 24, color, line_width, false)
	elif cast.shape == "line":
		var side := Vector2(0, cast.width * 0.5)
		var end := Vector2(cast.radius, 0)
		canvas.draw_polyline(PackedVector2Array([-side, end - side, end + side, side, -side]), color, line_width, false)
	else:
		canvas.draw_arc(Vector2.ZERO, cast.radius, 0, TAU, 40, color, line_width, false)

func _draw_interior(canvas: CanvasItem, cast: Cast, alpha: float) -> void:
	for index: int in cast.polygon_count:
		var polygon: PackedVector2Array = cast.polygons[index]
		var tone: int = int(cast.tones[index])
		var color: Color = CORE if tone == 1 else cast.color
		canvas.draw_colored_polygon(polygon, Color(color, alpha * (0.10 if tone == 2 else 0.9)))
		if cast.outlined[index] != 0:
			canvas.draw_polyline(cast.borders[index], Color(INK, alpha * 0.8), 2.0, false)
			if tone == 2:
				canvas.draw_polyline(cast.borders[index], Color(cast.color, alpha), 1.0, false)
	if not cast.details.is_empty():
		canvas.draw_multiline(cast.details, Color(CORE, alpha * 0.75), 2.0 if cast.family == "firework" else 1.0, false)

func _prepare_geometry(cast: Cast, progress: float) -> void:
	cast.polygon_count = 0
	cast.details.clear()
	if cast.shape == "arc":
		_prepare_slash(cast, progress)
	elif cast.shape == "line":
		_prepare_firework(cast, progress)
	elif cast.family == "wind":
		_prepare_wind(cast, progress)
	elif cast.family == "alchemy":
		_prepare_alchemy(cast, progress)
	else:
		_prepare_meteor(cast, progress)

func _prepare_slash(cast: Cast, progress: float) -> void:
	var radius: float = cast.radius * (0.76 + progress * 0.20)
	var sweep: float = minf(cast.half_angle * 0.94, PI * 0.94)
	var thickness: float = minf(cast.radius * 0.18, (17.0 - progress * 10.0) * (0.65 if cast.family == "crescent" else 1.0))
	_band(cast, radius, 0.0, sweep, thickness, 0, true)
	_band(cast, radius - thickness * 0.32, -sweep * 0.10, sweep * 0.65, thickness * 0.19, 1, false)
	for sign_value: float in [-1.0, 1.0]:
		var heading: Vector2 = Vector2.from_angle(sweep * sign_value * 0.56)
		_diamond(cast, heading * radius * 0.84, heading, minf(5.0, cast.radius * 0.035) * (1.0 - progress * 0.5), 0, false)
	for offset: float in [-0.64, -0.2, 0.2, 0.64]:
		var heading: Vector2 = Vector2.from_angle(sweep * offset)
		cast.details.append(heading * radius * 0.58)
		cast.details.append(heading * radius * 0.75)

func _prepare_wind(cast: Cast, progress: float) -> void:
	var radius: float = cast.radius * (0.42 + progress * 0.46)
	var thickness: float = minf(cast.radius * 0.10, 10.0 * (1.0 - progress * 0.55))
	for index: int in 3:
		var angle: float = float(index) * TAU / 3.0 + progress * 0.45
		_band(cast, radius, angle, 0.64, thickness, 0, true)
		_band(cast, radius - thickness * 0.28, angle - 0.08, 0.42, thickness * 0.18, 1, false)
		var heading: Vector2 = Vector2.from_angle(angle)
		cast.details.append(heading * radius * 0.57)
		cast.details.append(heading * radius * 0.78)

func _prepare_alchemy(cast: Cast, progress: float) -> void:
	_diamond(cast, Vector2.ZERO, Vector2.RIGHT, cast.radius * (0.22 + progress * 0.12), 2, true)
	_diamond(cast, Vector2.ZERO, Vector2.RIGHT, cast.radius * 0.085 * (1.0 - progress * 0.5), 1, false)
	var distance: float = cast.radius * (0.28 + progress * 0.43)
	for index: int in 6:
		var heading: Vector2 = Vector2.from_angle(PI / 6.0 + float(index) * TAU / 6.0)
		_diamond(cast, heading * distance, heading, minf(6.0, cast.radius * 0.035) * (1.0 - progress * 0.45), 0, false)
	var length: float = cast.radius * 0.10
	cast.details.append_array(PackedVector2Array([Vector2(-length, 0), Vector2(length, 0), Vector2(0, -length), Vector2(0, length)]))

func _prepare_meteor(cast: Cast, progress: float) -> void:
	var slot: int = cast.polygon_count
	var polygon: PackedVector2Array = cast.polygons[slot]
	polygon.resize(8)
	var long_ray: float = minf(26.0, cast.radius * 0.20) * (1.0 - progress * 0.65)
	var short_ray: float = long_ray * 0.20
	for index: int in 8:
		var heading: Vector2 = Vector2.from_angle(float(index) * PI / 4.0)
		var scale: float = (1.25 if index == 2 or index == 6 else 0.85) if index % 2 == 0 else 1.0
		polygon[index] = heading * (long_ray * scale if index % 2 == 0 else short_ray)
	_store_polygon(cast, slot, polygon, 1, false)
	var distance: float = cast.radius * (0.20 + progress * 0.53)
	for index: int in 6:
		var heading: Vector2 = Vector2.from_angle(float(index) * TAU / 6.0)
		_diamond(cast, heading * distance, heading, minf(6.0, cast.radius * 0.04) * (1.0 - progress * 0.45), 0, false)
		cast.details.append(heading * distance * 0.76)
		cast.details.append(heading * distance * 0.90)

func _prepare_firework(cast: Cast, progress: float) -> void:
	for index: int in 4:
		var along: float = cast.radius * (0.14 + float(index) * 0.24 + progress * 0.035)
		var center := Vector2(along, 0)
		var size: float = minf(cast.width * 0.38, cast.radius * 0.08) * (1.0 - progress * 0.45)
		var slot: int = cast.polygon_count
		var flower: PackedVector2Array = cast.polygons[slot]
		flower.resize(8)
		for ray: int in 8:
			var heading: Vector2 = Vector2.from_angle(float(ray) * PI / 4.0)
			var distance: float = size * (1.0 if ray % 2 == 0 else 0.28)
			flower[ray] = center + Vector2(heading.x, heading.y * 0.72) * distance
		_store_polygon(cast, slot, flower, 0, true)
		_diamond(cast, center, Vector2.RIGHT, size * 0.35, 1, false)
		cast.details.append(Vector2(along - cast.radius * 0.10, 0))
		cast.details.append(Vector2(along - cast.radius * 0.025, 0))
		var side: float = -1.0 if index % 2 == 0 else 1.0
		cast.details.append(center + Vector2(-size * 0.5, side * size * 0.5))
		cast.details.append(center + Vector2(size * 0.1, side * size * 0.85))

static func _band(cast: Cast, radius: float, center_angle: float, half_angle: float, thickness: float, tone: int, outline: bool) -> void:
	var slot: int = cast.polygon_count
	var polygon: PackedVector2Array = cast.polygons[slot]
	var count: int = BAND_SEGMENTS + 1
	polygon.resize(count * 2)
	for index: int in count:
		var fraction: float = float(index) / float(BAND_SEGMENTS)
		var heading: Vector2 = Vector2.from_angle(center_angle - half_angle + half_angle * 2.0 * fraction)
		var width: float = thickness * (0.10 + sin(fraction * PI) * 0.90)
		polygon[index] = heading * radius
		polygon[count * 2 - 1 - index] = heading * maxf(0.0, radius - width)
	_store_polygon(cast, slot, polygon, tone, outline)

static func _diamond(cast: Cast, center: Vector2, direction: Vector2, size: float, tone: int, outline: bool) -> void:
	var slot: int = cast.polygon_count
	var polygon: PackedVector2Array = cast.polygons[slot]
	polygon.resize(4)
	var side: Vector2 = direction.orthogonal()
	polygon[0] = center + direction * size
	polygon[1] = center + side * size * 0.65
	polygon[2] = center - direction * size
	polygon[3] = center - side * size * 0.65
	_store_polygon(cast, slot, polygon, tone, outline)

static func _store_polygon(cast: Cast, slot: int, polygon: PackedVector2Array, tone: int, outline: bool) -> void:
	cast.polygons[slot] = polygon
	cast.tones[slot] = tone
	cast.outlined[slot] = int(outline)
	if outline:
		var border: PackedVector2Array = cast.borders[slot]
		border.resize(polygon.size() + 1)
		for index: int in polygon.size():
			border[index] = polygon[index]
		border[polygon.size()] = polygon[0]
		cast.borders[slot] = border
	cast.polygon_count += 1

func geometry_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cast: Cast in _pool:
		if cast.life <= 0.0:
			continue
		var progress: float = clampf(1.0 - cast.life / LIFE, 0.0, 1.0)
		var polygons: Array[PackedVector2Array] = []
		var details := PackedVector2Array()
		if cast.animated:
			_prepare_geometry(cast, progress)
			for index: int in cast.polygon_count:
				polygons.append(_world_points(cast, cast.polygons[index]))
			details = _world_points(cast, cast.details)
		result.append({"id": cast.id, "family": cast.family, "color": cast.color,
			"shape": cast.shape, "origin": cast.origin, "direction": cast.direction,
			"radius": cast.radius, "width": cast.width, "half_angle_radians": cast.half_angle,
			"animated": cast.animated, "progress": progress,
			"polygons": polygons, "details": details, "detail_width": 2.0 if cast.family == "firework" else 1.0, "revision": VISUAL_REVISION})
	return result

static func _world_points(cast: Cast, points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	var side: Vector2 = cast.direction.orthogonal()
	for index: int in points.size():
		result[index] = cast.origin + cast.direction * points[index].x + side * points[index].y
	return result
