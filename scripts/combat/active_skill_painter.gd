extends RefCounted
## Fixed cosmetic pool; cast geometry follows the simulation's recorded origin.

const LIMIT: int = 8
const LIFE: float = 0.26
const INK: Color = Color("243752")
const GOLD: Color = Color("ffc86b")
const CORE: Color = Color("fff1cf")
const CYAN: Color = Color("91e0d1")

class Cast:
	var id: String = ""
	var origin: Vector2 = Vector2.ZERO
	var direction: Vector2 = Vector2.RIGHT
	var radius: float = 0.0
	var life: float = 0.0
	var animated: bool = false
	var shape: String = "circle"
	var half_angle: float = deg_to_rad(50.0)
	var width: float = 70.0
	var color: Color = GOLD

var _pool: Array[Cast] = []
var _next: int = 0

func _init() -> void:
	for index: int in LIMIT:
		_pool.append(Cast.new())

func add_cast(id: String, origin: Vector2, direction: Vector2, radius: float, animated: bool) -> bool:
	if id not in ["starfall", "arc_slash"] or not origin.is_finite() or not direction.is_finite() or not is_finite(radius) or radius <= 0.0:
		return false
	var cast: Cast = _pool[_next]
	_next = (_next + 1) % LIMIT
	cast.id = id
	cast.origin = origin
	cast.direction = direction.normalized() if direction.length_squared() > 0.0 else Vector2.RIGHT
	cast.radius = radius
	cast.life = LIFE
	cast.animated = animated
	cast.shape = "arc" if id == "arc_slash" else "circle"
	cast.half_angle = deg_to_rad(50.0)
	cast.color = CYAN if id == "arc_slash" else GOLD
	return true

func add_hero_cast(parameters: Dictionary, origin: Vector2, direction: Vector2, animated: bool) -> bool:
	var radius: float = float(parameters.get("radius", 0.0))
	var shape: String = str(parameters.get("shape", ""))
	if shape not in ["arc", "circle", "line"] or not origin.is_finite() or not direction.is_finite() or not is_finite(radius) or radius <= 0.0:
		return false
	var cast: Cast = _pool[_next]
	_next = (_next + 1) % LIMIT
	cast.id = str(parameters.get("id", ""))
	cast.origin = origin
	cast.direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	cast.radius = radius
	cast.life = LIFE
	cast.animated = animated
	cast.shape = shape
	cast.half_angle = float(parameters.get("half_angle_radians", deg_to_rad(50.0)))
	cast.width = float(parameters.get("width", 70.0))
	cast.color = Color("f69268") if cast.id == "hero_hanabi" else Color("87d9ab") if cast.id == "hero_celtie" else GOLD
	return true

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
	for cast: Cast in _pool:
		if cast.life <= 0.0:
			continue
		var progress: float = clampf(1.0 - cast.life / LIFE, 0.0, 1.0)
		var alpha: float = (1.0 - progress) * (0.85 if cast.animated else 0.26)
		if cast.shape == "arc":
			_draw_slash(canvas, cast, progress, alpha)
		elif cast.shape == "line":
			_draw_line_skill(canvas, cast, progress, alpha)
		else:
			_draw_starfall(canvas, cast, progress, alpha)

func _draw_slash(canvas: CanvasItem, cast: Cast, progress: float, alpha: float) -> void:
	var angle: float = cast.direction.angle()
	var sweep: float = cast.half_angle
	var radius: float = cast.radius * (0.88 + progress * 0.12) if cast.animated else cast.radius
	canvas.draw_arc(cast.origin, radius, angle - sweep, angle + sweep, 24, Color(INK, alpha), 8.0, false)
	canvas.draw_arc(cast.origin, radius, angle - sweep, angle + sweep, 24, Color(cast.color, alpha), 4.0, false)
	if cast.animated:
		canvas.draw_arc(cast.origin, radius - 3.0, angle - sweep * 0.65, angle + sweep * 0.65, 18, Color(CORE, alpha), 2.0, false)
		for edge: float in [-sweep, sweep]:
			var direction: Vector2 = Vector2.from_angle(angle + edge)
			canvas.draw_line(cast.origin + direction * radius * 0.65, cast.origin + direction * radius, Color(cast.color, alpha * 0.6), 2.0)

func _draw_starfall(canvas: CanvasItem, cast: Cast, progress: float, alpha: float) -> void:
	canvas.draw_arc(cast.origin, cast.radius, 0.0, TAU, 40, Color(cast.color, alpha * 0.55), 2.0, false)
	if not cast.animated:
		return
	var radius: float = 10.0 + cast.radius * progress * 0.85
	canvas.draw_arc(cast.origin, radius, 0.0, TAU, 32, Color(INK, alpha), 7.0, false)
	canvas.draw_arc(cast.origin, radius, 0.0, TAU, 32, Color(cast.color, alpha), 3.0, false)
	var core: float = 22.0 * (1.0 - progress)
	canvas.draw_line(cast.origin - Vector2(core, 0), cast.origin + Vector2(core, 0), Color(CORE, alpha), 4.0)
	canvas.draw_line(cast.origin - Vector2(0, core * 1.4), cast.origin + Vector2(0, core * 1.4), Color(CORE, alpha), 4.0)
	for index: int in 8:
		var direction: Vector2 = Vector2.from_angle(float(index) * TAU / 8.0)
		canvas.draw_line(cast.origin + direction * (radius + 4.0), cast.origin + direction * (radius + 12.0), Color(cast.color, alpha), 2.0)

func _draw_line_skill(canvas: CanvasItem, cast: Cast, progress: float, alpha: float) -> void:
	var normal: Vector2 = cast.direction.orthogonal() * cast.width * 0.5
	var endpoint: Vector2 = cast.origin + cast.direction * cast.radius
	var outline := PackedVector2Array([cast.origin - normal, endpoint - normal, endpoint + normal, cast.origin + normal, cast.origin - normal])
	canvas.draw_polyline(outline, Color(cast.color, alpha * 0.5), 2.0, false)
	if not cast.animated:
		return
	canvas.draw_line(cast.origin, endpoint, Color(INK, alpha), cast.width * (1.0 - progress) + 3.0)
	canvas.draw_line(cast.origin, endpoint, Color(cast.color, alpha), cast.width * (1.0 - progress))
	canvas.draw_line(cast.origin, endpoint, Color(CORE, alpha), maxf(1.0, 8.0 * (1.0 - progress)))
	for index: int in 5:
		var center: Vector2 = cast.origin.lerp(endpoint, float(index + 1) / 5.0)
		var size: float = (8.0 + progress * 14.0) * (1.0 - progress)
		canvas.draw_line(center - normal.normalized() * size, center + normal.normalized() * size, Color(CORE, alpha), 2.0)
