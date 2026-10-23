class_name ProjectilePainter
extends RefCounted
## Friendly-only drawing data. Rebuild never advances or modifies the simulation.

const LIMIT: int = CombatSim.SHOT_LIMIT
const DISC_SIDES: int = 16
const RING_SIDES: int = 8
const VISUAL_REVISION: String = "arsenal-lines-v3"
const TRAIL_VISUAL_REVISION: String = "subdued-trails-v1"
const TRAIL_MAIN_ALPHA: float = 0.58
const TRAIL_MAIN_WIDTH_SCALE: float = 0.72
const TRAIL_HALO_ALPHA: float = 0.10
const TRAIL_HALO_WIDTH_SCALE: float = 1.55
const EMBER_TRAIL_ALPHA: float = 0.40

class TrailStyle:
	var main_color: Color = Color.WHITE
	var main_width: float = 0.0
	var halo_color: Color = Color.TRANSPARENT
	var halo_width: float = 0.0
	var has_halo: bool = false

class TrailBatch:
	var points: PackedVector2Array = PackedVector2Array()
	var wings: PackedVector2Array = PackedVector2Array()
	var sigils: PackedVector2Array = PackedVector2Array()
	var color: Color = Color.WHITE
	var width: float = 3.0
	var source: String = ""
	var style: TrailStyle = TrailStyle.new()

class RingBatch:
	var radius: float = 0.0
	var multimesh: MultiMesh
	var cursor: int = 0

var bodies: MultiMesh
var cores: MultiMesh
var rings: Dictionary = {}
var trails: Dictionary = {}
var friendly_count: int = 0
var ember_count: int = 0
var bounce_count: int = 0
var family_counts: Dictionary = {}
var _friendly: Array[CombatSim.Shot] = []
var _sigil_shapes: Dictionary = {}

func _init() -> void:
	# Glow and colored body share one mesh instance; a white core and optional ring
	# therefore keep even ember+bounce within three GPU instances per projectile.
	bodies = _multimesh(_disc_mesh(true), LIMIT)
	cores = _multimesh(_disc_mesh(false), LIMIT)
	_sigil_shapes = _make_sigil_shapes()

func rebuild(shots: Array[CombatSim.Shot]) -> void:
	friendly_count = 0
	ember_count = 0
	bounce_count = 0
	family_counts.clear()
	_friendly.clear()
	var ring_counts: Dictionary = {}
	for batch: TrailBatch in trails.values():
		batch.points.clear()
		batch.wings.clear()
		batch.sigils.clear()
	for shot: CombatSim.Shot in shots:
		if not shot.active or shot.hostile:
			continue
		if friendly_count >= LIMIT:
			break
		_friendly.append(shot)
		friendly_count += 1
		if shot.rune == "bounce":
			var radius: float = shot.radius + 3.0
			ring_counts[radius] = int(ring_counts.get(radius, 0)) + 1
			bounce_count += 1
	# Radius-specific rings retain their one-pixel width without scaling it with
	# radius. Their exact current capacities sum to <= LIMIT, including mixed radii.
	for radius: float in rings.keys():
		if not ring_counts.has(radius):
			rings.erase(radius)
		elif rings[radius].multimesh.instance_count > int(ring_counts[radius]):
			# Release spare slots before another radius grows, preserving the global cap.
			rings[radius].multimesh.instance_count = int(ring_counts[radius])
	for radius: float in ring_counts:
		var ring: RingBatch
		if rings.has(radius):
			ring = rings[radius]
		else:
			ring = RingBatch.new()
			ring.radius = radius
			ring.multimesh = _multimesh(_ring_mesh(radius), 0)
			rings[radius] = ring
		var count: int = int(ring_counts[radius])
		if ring.multimesh.instance_count != count:
			ring.multimesh.instance_count = count
		ring.multimesh.visible_instance_count = count
		ring.cursor = 0
	var core_index: int = 0
	for shot: CombatSim.Shot in _friendly:
		var direction: Vector2 = shot.velocity.normalized()
		var trail_length: float = 25.0 if shot.source == "frost" else 18.0
		if shot.source == "scatter":
			trail_length = 9.0
		elif shot.source == "storm":
			trail_length = 13.0
		elif shot.source == "comet":
			trail_length = 29.0
		var tail: Vector2 = shot.position - direction * trail_length
		var color: Color = Color("dab779") if shot.source == "ember" else shot.color
		if shot.rune == "blast":
			color = color.lerp(Color("dca0fa"), 0.35)
		var key: String = shot.source + ":" + shot.rune
		family_counts[key] = int(family_counts.get(key, 0)) + 1
		if not trails.has(key):
			trails[key] = TrailBatch.new()
		var trail: TrailBatch = trails[key]
		trail.source = shot.source
		trail.color = color
		trail.width = shot.radius * 1.2
		if shot.source == "crescent" or shot.source == "comet":
			trail.width = shot.radius * 0.55
		trail.points.append(tail - direction * 6.0 if shot.source == "ember" else tail)
		trail.points.append(shot.position)
		_append_sigil(trail.sigils, shot, direction)
		if shot.rune == "pierce" or shot.source == "frost":
			var wing: Vector2 = direction.orthogonal() * 3.0
			trail.wings.append(tail + wing)
			trail.wings.append(shot.position + direction * 5.0)
			trail.wings.append(tail - wing)
			trail.wings.append(shot.position + direction * 5.0)
		if shot.source == "ember":
			_instance(bodies, ember_count, shot.position, shot.radius, color)
			ember_count += 1
		var core_scale: float = 0.4 if shot.source == "ember" else 0.18 if shot.source == "crescent" else 0.35 if shot.source == "comet" else 0.55
		_instance(cores, core_index, shot.position, shot.radius * core_scale,
			Color("f8efe2") if shot.source == "ember" else Color("f5efe0"))
		core_index += 1
		if shot.rune == "bounce":
			var ring: RingBatch = rings[shot.radius + 3.0]
			_instance(ring.multimesh, ring.cursor, shot.position, 1.0, Color("c7b0f3"))
			ring.cursor += 1
	bodies.visible_instance_count = ember_count
	cores.visible_instance_count = friendly_count
	for key: String in trails.keys():
		if not family_counts.has(key):
			trails.erase(key)
		else:
			_style_trail(trails[key])

static func _style_trail(trail: TrailBatch) -> void:
	var style: TrailStyle = trail.style
	style.has_halo = trail.source != "ember"
	style.main_color = Color(trail.color, TRAIL_MAIN_ALPHA if style.has_halo else EMBER_TRAIL_ALPHA)
	style.main_width = trail.width * TRAIL_MAIN_WIDTH_SCALE if style.has_halo else trail.width
	style.halo_color = Color(trail.color, TRAIL_HALO_ALPHA) if style.has_halo else Color.TRANSPARENT
	style.halo_width = trail.width * TRAIL_HALO_WIDTH_SCALE if style.has_halo else 0.0

func draw(canvas: CanvasItem) -> void:
	# All commands stay in CombatWorld's CanvasItem, before its danger pass.
	if ember_count > 0:
		canvas.draw_multimesh(bodies, null)
	if friendly_count > 0:
		canvas.draw_multimesh(cores, null)
	for ring: RingBatch in rings.values():
		if ring.multimesh.visible_instance_count > 0:
			canvas.draw_multimesh(ring.multimesh, null)
	for trail: TrailBatch in trails.values():
		var style: TrailStyle = trail.style
		if style.has_halo:
			canvas.draw_multiline(trail.points, style.halo_color, style.halo_width, true)
		canvas.draw_multiline(trail.points, style.main_color, style.main_width, true)
		if not trail.wings.is_empty():
			canvas.draw_multiline(trail.wings, Color(trail.color, 0.65), 1.0, true)
		if not trail.sigils.is_empty():
			var sigil_color: Color = Color("e7dba8") if trail.source == "storm" else Color("d5c1e8") if trail.source == "comet" else Color("d3e8de")
			canvas.draw_multiline(trail.sigils, Color(sigil_color, 0.85), 1.3, true)

func get_stats() -> Dictionary:
	var allocated: int = bodies.instance_count + cores.instance_count
	for ring: RingBatch in rings.values():
		allocated += ring.multimesh.instance_count
	return {"friendly_count": friendly_count, "body_instances": ember_count,
		"core_instances": friendly_count, "bounce_instances": bounce_count,
		"total_visible_instances": ember_count + friendly_count + bounce_count,
		"allocated_instances": allocated, "family_counts": family_counts.duplicate(),
		"trail_families": trails.size()}


func _append_sigil(points: PackedVector2Array, shot: CombatSim.Shot, direction: Vector2) -> void:
	if not _sigil_shapes.has(shot.source):
		return
	var scale: float = shot.radius + 3.0 if shot.source == "comet" else 1.0
	# Transform the packed endpoint array in native code. The rotation basis uses
	# the positive turn, while authored crescent/lightning offsets retain their
	# original orthogonal convention inside the cached local geometry.
	var transform := Transform2D(direction * scale, Vector2(-direction.y, direction.x) * scale, shot.position)
	var shape: PackedVector2Array = _sigil_shapes[shot.source]
	points.append_array(transform * shape)


static func _make_sigil_shapes() -> Dictionary:
	var crescent := PackedVector2Array()
	var storm := PackedVector2Array()
	var comet := PackedVector2Array()
	var side: Vector2 = Vector2.RIGHT.orthogonal()
	for index: int in 8:
		var angle_a: float = -PI * 0.5 + float(index) * PI / 8.0
		var angle_b: float = -PI * 0.5 + float(index + 1) * PI / 8.0
		for depth: float in [12.0, 6.0]:
			crescent.append(Vector2(-5, 0) + Vector2.RIGHT * cos(angle_a) * depth + side * sin(angle_a) * 10.0)
			crescent.append(Vector2(-5, 0) + Vector2.RIGHT * cos(angle_b) * depth + side * sin(angle_b) * 10.0)
	for sign_value: float in [-1.0, 1.0]:
		var offsets: Array[Vector2] = [Vector2(-11, sign_value * 3), Vector2(-4, sign_value * 6),
			Vector2(-6, sign_value), Vector2(5, 0)]
		for index: int in 3:
			storm.append(Vector2.RIGHT * offsets[index].x + side * offsets[index].y)
			storm.append(Vector2.RIGHT * offsets[index + 1].x + side * offsets[index + 1].y)
	for index: int in 5:
		var axis: Vector2 = Vector2.RIGHT.rotated(float(index) * TAU / 5.0)
		var next_axis: Vector2 = Vector2.RIGHT.rotated((float(index) + 0.5) * TAU / 5.0)
		var end_axis: Vector2 = Vector2.RIGHT.rotated(float(index + 1) * TAU / 5.0)
		comet.append(axis)
		comet.append(next_axis * 0.43)
		comet.append(next_axis * 0.43)
		comet.append(end_axis)
	return {"crescent": crescent, "storm": storm, "comet": comet}

static func _instance(multimesh: MultiMesh, index: int, point: Vector2, radius: float, color: Color) -> void:
	multimesh.set_instance_transform_2d(index, Transform2D(Vector2(radius, 0), Vector2(0, radius), point))
	multimesh.set_instance_color(index, color)

static func _multimesh(mesh: ArrayMesh, capacity: int) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_2D
	result.use_colors = true
	result.mesh = mesh
	result.instance_count = capacity
	result.visible_instance_count = 0
	return result

static func _disc_mesh(ember: bool) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	if ember:
		_append_disc(vertices, colors, 2.0, Color(1, 1, 1, 0.10))
	_append_disc(vertices, colors, 1.0, Color.WHITE)
	return _mesh(vertices, colors)

static func _append_disc(vertices: PackedVector2Array, colors: PackedColorArray, radius: float, color: Color) -> void:
	for index: int in DISC_SIDES:
		vertices.append(Vector2.ZERO)
		vertices.append(Vector2.from_angle(float(index) * TAU / DISC_SIDES) * radius)
		vertices.append(Vector2.from_angle(float(index + 1) * TAU / DISC_SIDES) * radius)
		for point: int in 3:
			colors.append(color)

static func _ring_mesh(radius: float) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for index: int in RING_SIDES:
		var a: Vector2 = Vector2.from_angle(float(index) * TAU / RING_SIDES)
		var b: Vector2 = Vector2.from_angle(float(index + 1) * TAU / RING_SIDES)
		for point: Vector2 in [a * (radius - 0.5), a * (radius + 0.5), b * (radius + 0.5),
				a * (radius - 0.5), b * (radius + 0.5), b * (radius - 0.5)]:
			vertices.append(point)
			colors.append(Color.WHITE)
	return _mesh(vertices, colors)

static func _mesh(vertices: PackedVector2Array, colors: PackedColorArray) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return result
