class_name ProjectilePainter
extends RefCounted
## Friendly-only drawing data. Rebuild never advances or modifies the simulation.

const LIMIT: int = CombatSim.SHOT_LIMIT
const DISC_SIDES: int = 16
const RING_SIDES: int = 8

class TrailBatch:
	var points: PackedVector2Array = PackedVector2Array()
	var wings: PackedVector2Array = PackedVector2Array()
	var color: Color = Color.WHITE
	var width: float = 3.0
	var source: String = ""

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

func _init() -> void:
	# Glow and colored body share one mesh instance; a white core and optional ring
	# therefore keep even ember+bounce within three GPU instances per projectile.
	bodies = _multimesh(_disc_mesh(true), LIMIT)
	cores = _multimesh(_disc_mesh(false), LIMIT)

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
		trail.points.append(tail - direction * 6.0 if shot.source == "ember" else tail)
		trail.points.append(shot.position)
		if shot.rune == "pierce" or shot.source == "frost":
			var wing: Vector2 = direction.orthogonal() * 3.0
			trail.wings.append(tail + wing)
			trail.wings.append(shot.position + direction * 5.0)
			trail.wings.append(tail - wing)
			trail.wings.append(shot.position + direction * 5.0)
		if shot.source == "ember":
			_instance(bodies, ember_count, shot.position, shot.radius, color)
			ember_count += 1
		_instance(cores, core_index, shot.position, shot.radius * (0.4 if shot.source == "ember" else 0.55),
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
		if trail.source == "ember":
			canvas.draw_multiline(trail.points, Color(trail.color, 0.4), trail.width, true)
		else:
			canvas.draw_multiline(trail.points, Color(trail.color, 0.20), trail.width * 2.33, true)
			canvas.draw_multiline(trail.points, trail.color, trail.width, true)
		if not trail.wings.is_empty():
			canvas.draw_multiline(trail.wings, Color(trail.color, 0.65), 1.0, true)

func get_stats() -> Dictionary:
	var allocated: int = bodies.instance_count + cores.instance_count
	for ring: RingBatch in rings.values():
		allocated += ring.multimesh.instance_count
	return {"friendly_count": friendly_count, "body_instances": ember_count,
		"core_instances": friendly_count, "bounce_instances": bounce_count,
		"total_visible_instances": ember_count + friendly_count + bounce_count,
		"allocated_instances": allocated, "family_counts": family_counts.duplicate(),
		"trail_families": trails.size()}

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
