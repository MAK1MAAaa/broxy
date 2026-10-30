class_name ProjectilePainter
extends RefCounted
## Friendly-only drawing data. Rebuild never advances or modifies the simulation.

const LIMIT: int = CombatSim.SHOT_LIMIT
const DISC_SIDES: int = 16
const RING_SIDES: int = 8
const INSTANCE_STRIDE: int = 12
const HEAD_FRAME_SIZE: int = 64
const HEAD_WORLD_SIZE: float = 32.0
const HEAD_SOURCES: PackedStringArray = ["bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring"]
const VISUAL_REVISION: String = "world-flipper-armaments-v1"
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
	var color: Color = Color.WHITE
	var width: float = 3.0
	var source: String = ""
	var width_scale: float = 1.2
	var last_shot: CombatSim.Shot
	var style: TrailStyle = TrailStyle.new()

class InstanceBatch:
	var multimesh: MultiMesh
	var buffer: PackedFloat32Array = PackedFloat32Array()
	var cursor: int = 0

class RingBatch extends InstanceBatch:
	var radius: float = 0.0

class HeadBatch extends InstanceBatch:
	var source: String = ""
	var frame: int = 0
	var base_radius: float = 1.0
	var texture: Texture2D

var bodies: MultiMesh
var heads: Dictionary = {}
var rings: Dictionary = {}
var trails: Dictionary = {}
var atlas_texture: Texture2D
var friendly_count: int = 0
var ember_count: int = 0
var bounce_count: int = 0
var family_counts: Dictionary = {}
var _friendly: Array[CombatSim.Shot] = []
var _friendly_keys: Array[String] = []
var _body_buffer: PackedFloat32Array = PackedFloat32Array()
var _head_base_radii: Dictionary = {}
var _head_meshes: Dictionary = {}
var _head_textures: Dictionary = {}

func _init() -> void:
	bodies = _multimesh(_disc_mesh(true), LIMIT)
	_body_buffer.resize(LIMIT * INSTANCE_STRIDE)
	atlas_texture = load(AdventureArt.path("res://assets/fx/projectile_heads.svg"))
	for frame: int in HEAD_SOURCES.size():
		var source: String = HEAD_SOURCES[frame]
		_head_base_radii[source] = GameCatalog.weapon(source).projectile_radius
		_head_meshes[source] = _head_mesh(frame)
		_head_textures[source] = atlas_texture

func rebuild(shots: Array[CombatSim.Shot], view: Rect2 = Rect2()) -> void:
	friendly_count = 0
	ember_count = 0
	bounce_count = 0
	family_counts.clear()
	_friendly.clear()
	_friendly_keys.clear()
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
		var key: String = shot.source + ":" + shot.rune
		_friendly_keys.append(key)
		family_counts[key] = int(family_counts.get(key, 0)) + 1
		if not trails.has(key):
			trails[key] = TrailBatch.new()
		var trail: TrailBatch = trails[key]
		trail.last_shot = shot
		friendly_count += 1
		if shot.rune == "bounce":
			var radius: float = shot.radius + 3.0
			ring_counts[radius] = int(ring_counts.get(radius, 0)) + 1
			bounce_count += 1
	_prepare_heads()
	_prepare_rings(ring_counts)
	for index: int in _friendly.size():
		var shot: CombatSim.Shot = _friendly[index]
		var direction: Vector2 = shot.velocity.normalized()
		if shot.source == "return_ring" and direction.is_zero_approx():
			direction = Vector2.RIGHT
		var trail_length: float = 25.0 if shot.source == "frost" else 18.0
		if shot.source == "scatter":
			trail_length = 9.0
		elif shot.source == "storm":
			trail_length = 13.0
		elif shot.source == "comet":
			trail_length = 29.0
		var tail: Vector2 = shot.position - direction * trail_length
		var key: String = _friendly_keys[index]
		var trail: TrailBatch = trails[key]
		var width: float = shot.radius * trail.width_scale
		var start: Vector2 = shot.position - direction * 16.0 if shot.source == "return_ring" else tail - direction * 6.0 if shot.source == "ember" else tail
		var end: Vector2 = shot.position - direction * 10.0 if shot.source == "return_ring" else shot.position
		if not view.has_area() or trail_draw_bounds(start, end, width).intersects(view):
			trail.points.append(start)
			trail.points.append(end)
			if shot.rune == "pierce" or shot.source == "frost":
				var wing: Vector2 = direction.orthogonal() * 3.0
				var wing_tail: Vector2 = shot.position - direction * 16.0 if shot.source == "return_ring" else tail
				var wing_head: Vector2 = shot.position - direction * 10.0 if shot.source == "return_ring" else shot.position + direction * 5.0
				trail.wings.append(wing_tail + wing)
				trail.wings.append(wing_head + wing if shot.source == "return_ring" else wing_head)
				trail.wings.append(wing_tail - wing)
				trail.wings.append(wing_head - wing if shot.source == "return_ring" else wing_head)
		if shot.source == "ember":
			_write_instance(_body_buffer, ember_count, shot.position, shot.radius, trail.color)
			ember_count += 1
		var head: HeadBatch = heads[key]
		var head_direction: Vector2 = Vector2.RIGHT if direction.is_zero_approx() else direction
		_write_head_instance(head.buffer, head.cursor, shot.position, head_direction, shot.radius / head.base_radius)
		head.cursor += 1
		if shot.rune == "bounce":
			var ring: RingBatch = rings[shot.radius + 3.0]
			_write_instance(ring.buffer, ring.cursor, shot.position, 1.0, Color("c7b0f3"))
			ring.cursor += 1
	if ember_count > 0:
		bodies.buffer = _body_buffer
	for head: HeadBatch in heads.values():
		head.multimesh.buffer = head.buffer
	for ring: RingBatch in rings.values():
		ring.multimesh.buffer = ring.buffer
	bodies.visible_instance_count = ember_count
	for key: String in trails.keys():
		if not family_counts.has(key):
			trails.erase(key)

func _reclaim_capacity(batches: Dictionary, counts: Dictionary) -> void:
	var allocated: int = 0
	for key: Variant in batches.keys():
		if not counts.has(key):
			batches.erase(key)
		else:
			allocated += batches[key].multimesh.instance_count
	var growth: int = 0
	for key: Variant in counts:
		var capacity: int = batches[key].multimesh.instance_count if batches.has(key) else 0
		growth += maxi(0, int(counts[key]) - capacity)
	var release: int = maxi(0, allocated + growth - LIMIT)
	if release > 0:
		for key: Variant in batches:
			var batch: InstanceBatch = batches[key]
			var count: int = int(counts[key])
			var freed: int = mini(release, maxi(0, batch.multimesh.instance_count - count))
			if freed > 0:
				batch.multimesh.visible_instance_count = count
				batch.multimesh.instance_count -= freed
				release -= freed
			if release == 0:
				break

func _resize_batch(batch: InstanceBatch, count: int) -> void:
	if batch.multimesh.instance_count < count:
		batch.multimesh.instance_count = count
	var buffer_size: int = batch.multimesh.instance_count * INSTANCE_STRIDE
	if batch.buffer.size() != buffer_size:
		batch.buffer.resize(buffer_size)
	batch.multimesh.visible_instance_count = count
	batch.cursor = 0

func _prepare_heads() -> void:
	_reclaim_capacity(heads, family_counts)
	for key: String in family_counts:
		var head: HeadBatch
		if heads.has(key):
			head = heads[key]
		else:
			head = HeadBatch.new()
			head.source = key.get_slice(":", 0)
			var definition: ContentDef = GameCatalog.weapon(head.source)
			if not _head_meshes.has(head.source) and definition != null:
				_head_base_radii[head.source] = definition.projectile_radius
				_head_meshes[head.source] = _head_mesh(0, 1)
				_head_textures[head.source] = load(AdventureArt.path("res://assets/icons/%s.svg" % definition.icon)) as Texture2D
			var source: String = head.source if _head_meshes.has(head.source) else "bone"
			head.frame = HEAD_SOURCES.find(source)
			head.base_radius = _head_base_radii[source]
			head.texture = _head_textures[source]
			head.multimesh = _multimesh(_head_meshes[source], 0)
			heads[key] = head
		_resize_batch(head, int(family_counts[key]))
		_prepare_trail(trails[key])

static func _prepare_trail(trail: TrailBatch) -> void:
	var shot: CombatSim.Shot = trail.last_shot
	trail.source = shot.source
	trail.color = Color("dab779") if shot.source == "ember" else shot.color
	if shot.rune == "blast":
		trail.color = trail.color.lerp(Color("dca0fa"), 0.35)
	trail.width_scale = 0.25 if shot.source == "return_ring" else 0.55 if shot.source in ["crescent", "comet"] else 1.2
	trail.width = shot.radius * trail.width_scale
	_style_trail(trail)

func _prepare_rings(ring_counts: Dictionary) -> void:
	_reclaim_capacity(rings, ring_counts)
	for radius: float in ring_counts:
		var ring: RingBatch
		if rings.has(radius):
			ring = rings[radius]
		else:
			ring = RingBatch.new()
			ring.radius = radius
			ring.multimesh = _multimesh(_ring_mesh(radius), 0)
			rings[radius] = ring
		_resize_batch(ring, int(ring_counts[radius]))

static func _style_trail(trail: TrailBatch) -> void:
	var style: TrailStyle = trail.style
	style.has_halo = trail.source != "ember"
	style.main_color = Color(trail.color, TRAIL_MAIN_ALPHA if style.has_halo else EMBER_TRAIL_ALPHA)
	style.main_width = trail.width * TRAIL_MAIN_WIDTH_SCALE if style.has_halo else trail.width
	style.halo_color = Color(trail.color, TRAIL_HALO_ALPHA) if style.has_halo else Color.TRANSPARENT
	style.halo_width = trail.width * TRAIL_HALO_WIDTH_SCALE if style.has_halo else 0.0

static func trail_draw_bounds(start: Vector2, end: Vector2, width: float) -> Rect2:
	var minimum := Vector2(minf(start.x, end.x), minf(start.y, end.y))
	var maximum := Vector2(maxf(start.x, end.x), maxf(start.y, end.y))
	# Wing tips extend five pixels ahead and three sideways; include halo and AA.
	return Rect2(minimum, maximum - minimum).grow(absf(width) * TRAIL_HALO_WIDTH_SCALE * 0.5 + 8.0)

func draw(canvas: CanvasItem) -> void:
	# Each family head follows its trails; all commands precede the danger pass.
	if ember_count > 0:
		canvas.draw_multimesh(bodies, null)
	for ring: RingBatch in rings.values():
		if ring.multimesh.visible_instance_count > 0:
			canvas.draw_multimesh(ring.multimesh, null)
	for key: String in trails:
		var trail: TrailBatch = trails[key]
		var style: TrailStyle = trail.style
		if not trail.points.is_empty():
			if style.has_halo:
				canvas.draw_multiline(trail.points, style.halo_color, style.halo_width, true)
			canvas.draw_multiline(trail.points, style.main_color, style.main_width, true)
		if not trail.wings.is_empty():
			canvas.draw_multiline(trail.wings, Color(trail.color, 0.65), 1.0, true)
		var head: HeadBatch = heads[key]
		canvas.draw_multimesh(head.multimesh, head.texture)

func get_stats() -> Dictionary:
	var head_capacity: int = 0
	for head: HeadBatch in heads.values():
		head_capacity += head.multimesh.instance_count
	var allocated: int = bodies.instance_count + head_capacity
	for ring: RingBatch in rings.values():
		allocated += ring.multimesh.instance_count
	return {"friendly_count": friendly_count, "body_instances": ember_count,
		"core_instances": friendly_count, "head_instances": friendly_count,
		"head_families": heads.size(), "allocated_head_instances": head_capacity,
		"bounce_instances": bounce_count,
		"total_visible_instances": ember_count + friendly_count + bounce_count,
		"allocated_instances": allocated, "family_counts": family_counts.duplicate(),
		"trail_families": trails.size()}

static func _write_instance(buffer: PackedFloat32Array, index: int, point: Vector2, radius: float, color: Color) -> void:
	var offset: int = index * INSTANCE_STRIDE
	buffer[offset] = radius
	buffer[offset + 3] = point.x
	buffer[offset + 5] = radius
	buffer[offset + 7] = point.y
	buffer[offset + 8] = color.r
	buffer[offset + 9] = color.g
	buffer[offset + 10] = color.b
	buffer[offset + 11] = color.a

static func _write_head_instance(buffer: PackedFloat32Array, index: int, point: Vector2, direction: Vector2, scale: float) -> void:
	var offset: int = index * INSTANCE_STRIDE
	var x: float = direction.x * scale
	var y: float = direction.y * scale
	buffer[offset] = x
	buffer[offset + 1] = -y
	buffer[offset + 3] = point.x
	buffer[offset + 4] = y
	buffer[offset + 5] = x
	buffer[offset + 7] = point.y
	buffer[offset + 8] = 1.0
	buffer[offset + 9] = 1.0
	buffer[offset + 10] = 1.0
	buffer[offset + 11] = 1.0

static func _head_mesh(frame: int, frame_count: int = HEAD_SOURCES.size()) -> ArrayMesh:
	var half_size: float = HEAD_WORLD_SIZE * 0.5
	var vertices := PackedVector2Array([
		Vector2(-half_size, -half_size), Vector2(half_size, -half_size), Vector2(half_size, half_size),
		Vector2(-half_size, -half_size), Vector2(half_size, half_size), Vector2(-half_size, half_size)])
	var left: float = float(frame) / float(frame_count)
	var right: float = float(frame + 1) / float(frame_count)
	var uvs := PackedVector2Array([Vector2(left, 0), Vector2(right, 0), Vector2(right, 1),
		Vector2(left, 0), Vector2(right, 1), Vector2(left, 1)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return result

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
