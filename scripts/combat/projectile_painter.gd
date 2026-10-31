class_name ProjectilePainter
extends RefCounted
## Friendly-only drawing data. Rebuild never advances or modifies the simulation.

const LIMIT: int = CombatSim.SHOT_LIMIT
const DISC_SIDES: int = 16
const RING_SIDES: int = 8
const INSTANCE_STRIDE: int = 12
const HEAD_INSTANCE_STRIDE: int = 16
const HEAD_ATLAS_COLUMNS: int = 32
const HEAD_SHADER: Shader = preload("res://shaders/projectile_heads.gdshader")
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
	var point_cursor: int = 0
	var wing_cursor: int = 0
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

class HeadBatch:
	var cursor: int = 0
	var capacity: int = 0
	var start: int = 0
	var source: String = ""
	var frame: int = 0
	var base_radius: float = 1.0
	var texture: Texture2D

var bodies: MultiMesh
var heads: Dictionary = {}
var rings: Dictionary = {}
var trails: Dictionary = {}
var atlas_texture: Texture2D
var head_atlas_texture: Texture2D
var head_multimesh: MultiMesh
var head_buffer: PackedFloat32Array = PackedFloat32Array()
var head_mesh: ArrayMesh
var head_material: ShaderMaterial
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
var _head_frames: Dictionary = {}

func _init() -> void:
	bodies = _multimesh(_disc_mesh(true), LIMIT)
	_body_buffer.resize(LIMIT * INSTANCE_STRIDE)
	atlas_texture = load(AdventureArt.path("res://assets/fx/projectile_heads.svg"))
	for frame: int in HEAD_SOURCES.size():
		var source: String = HEAD_SOURCES[frame]
		_head_base_radii[source] = GameCatalog.weapon(source).projectile_radius
		_head_meshes[source] = _head_mesh(frame)
		_head_textures[source] = atlas_texture
		_head_frames[source] = frame
	_build_head_atlas()
	head_mesh = _head_mesh(0, 1)
	head_multimesh = _multimesh(head_mesh, 0, true)
	head_material = ShaderMaterial.new()
	head_material.shader = HEAD_SHADER

func _build_head_atlas() -> void:
	var image: Image = Image.create(HEAD_ATLAS_COLUMNS * HEAD_FRAME_SIZE, HEAD_FRAME_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var source_image: Image = atlas_texture.get_image()
	source_image.convert(Image.FORMAT_RGBA8)
	image.blit_rect(source_image, Rect2i(0, 0, HEAD_SOURCES.size() * HEAD_FRAME_SIZE, HEAD_FRAME_SIZE), Vector2i.ZERO)
	var frame: int = HEAD_SOURCES.size()
	for definition: ContentDef in GameCatalog.weapons():
		if _head_frames.has(definition.id):
			continue
		if frame >= HEAD_ATLAS_COLUMNS:
			push_error("Projectile head atlas exceeds its thirty-two source columns")
			break
		var texture := load(AdventureArt.path("res://assets/icons/%s.svg" % definition.icon)) as Texture2D
		if texture == null:
			push_error("Missing projectile head texture: " + definition.id)
			continue
		var icon: Image = texture.get_image()
		if icon == null or icon.get_size() != Vector2i(HEAD_FRAME_SIZE, HEAD_FRAME_SIZE):
			push_error("Projectile head texture is not an authored sixty-four-pixel cell: " + definition.id)
			continue
		icon.convert(Image.FORMAT_RGBA8)
		image.blit_rect(icon, Rect2i(0, 0, HEAD_FRAME_SIZE, HEAD_FRAME_SIZE), Vector2i(frame * HEAD_FRAME_SIZE, 0))
		_head_base_radii[definition.id] = definition.projectile_radius
		_head_meshes[definition.id] = _head_mesh(0, 1)
		_head_textures[definition.id] = texture
		_head_frames[definition.id] = frame
		frame += 1
	head_atlas_texture = ImageTexture.create_from_image(image)

func attach_material(canvas: CanvasItem) -> void:
	if canvas.material != head_material:
		canvas.material = head_material

func rebuild(shots: Array[CombatSim.Shot], view: Rect2 = Rect2()) -> void:
	friendly_count = 0
	ember_count = 0
	bounce_count = 0
	family_counts.clear()
	_friendly.clear()
	_friendly_keys.clear()
	var ring_counts: Dictionary = {}
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
			trail.points[trail.point_cursor] = start
			trail.points[trail.point_cursor + 1] = end
			trail.point_cursor += 2
			if shot.rune == "pierce" or shot.source == "frost":
				var wing: Vector2 = direction.orthogonal() * 3.0
				var wing_tail: Vector2 = shot.position - direction * 16.0 if shot.source == "return_ring" else tail
				var wing_head: Vector2 = shot.position - direction * 10.0 if shot.source == "return_ring" else shot.position + direction * 5.0
				trail.wings[trail.wing_cursor] = wing_tail + wing
				trail.wings[trail.wing_cursor + 1] = wing_head + wing if shot.source == "return_ring" else wing_head
				trail.wings[trail.wing_cursor + 2] = wing_tail - wing
				trail.wings[trail.wing_cursor + 3] = wing_head - wing if shot.source == "return_ring" else wing_head
				trail.wing_cursor += 4
		if shot.source == "ember":
			_write_instance(_body_buffer, ember_count, shot.position, shot.radius, trail.color)
			ember_count += 1
		var head: HeadBatch = heads[key]
		var head_direction: Vector2 = Vector2.RIGHT if direction.is_zero_approx() else direction
		var head_index: int = head.start + head.cursor
		_write_head_instance(head_buffer, head_index, shot.position, head_direction, shot.radius / head.base_radius, HEAD_INSTANCE_STRIDE)
		head_buffer[head_index * HEAD_INSTANCE_STRIDE + 12] = float(head.frame) / float(HEAD_ATLAS_COLUMNS - 1)
		head.cursor += 1
		if shot.rune == "bounce":
			var ring: RingBatch = rings[shot.radius + 3.0]
			_write_instance(ring.buffer, ring.cursor, shot.position, 1.0, Color("c7b0f3"))
			ring.cursor += 1
	if ember_count > 0:
		bodies.buffer = _body_buffer
	if friendly_count > 0:
		head_multimesh.buffer = head_buffer
	for ring: RingBatch in rings.values():
		ring.multimesh.buffer = ring.buffer
	bodies.visible_instance_count = ember_count
	for key: String in trails.keys():
		var trail: TrailBatch = trails[key]
		trail.points.resize(trail.point_cursor if family_counts.has(key) else 0)
		trail.wings.resize(trail.wing_cursor if family_counts.has(key) else 0)
		if not family_counts.has(key):
			trail.point_cursor = 0
			trail.wing_cursor = 0
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

func _reclaim_head_capacity() -> void:
	var allocated: int = 0
	for key: String in heads.keys():
		if not family_counts.has(key):
			heads.erase(key)
		else:
			allocated += heads[key].capacity
	var growth: int = 0
	for key: String in family_counts:
		var capacity: int = heads[key].capacity if heads.has(key) else 0
		growth += maxi(0, int(family_counts[key]) - capacity)
	var release: int = maxi(0, allocated + growth - LIMIT)
	for key: String in heads:
		if release == 0:
			break
		var head: HeadBatch = heads[key]
		var freed: int = mini(release, maxi(0, head.capacity - int(family_counts[key])))
		head.capacity -= freed
		release -= freed

func _prepare_heads() -> void:
	_reclaim_head_capacity()
	for key: String in family_counts:
		var head: HeadBatch
		if heads.has(key):
			head = heads[key]
		else:
			head = HeadBatch.new()
			head.source = key.get_slice(":", 0)
			var source: String = head.source if _head_frames.has(head.source) else "bone"
			head.frame = _head_frames[source]
			head.base_radius = _head_base_radii[source]
			head.texture = _head_textures[source]
			heads[key] = head
		var count: int = int(family_counts[key])
		head.capacity = maxi(head.capacity, count)
		head.cursor = 0
		var trail: TrailBatch = trails[key]
		_prepare_trail(trail)
		trail.points.resize(count * 2)
		trail.wings.resize(count * 4 if trail.last_shot.rune == "pierce" or trail.source == "frost" else 0)
		trail.point_cursor = 0
		trail.wing_cursor = 0
	var offset: int = 0
	for key: String in heads:
		var head: HeadBatch = heads[key]
		head.start = offset
		offset += int(family_counts[key])
	if friendly_count == 0:
		head_multimesh.instance_count = 0
		head_buffer.resize(0)
	elif head_multimesh.instance_count < friendly_count:
		var previous_capacity: int = head_multimesh.instance_count
		head_multimesh.instance_count = friendly_count
		head_buffer.resize(friendly_count * HEAD_INSTANCE_STRIDE)
		for index: int in range(previous_capacity, friendly_count):
			var base: int = index * HEAD_INSTANCE_STRIDE
			for channel: int in range(8, 12):
				head_buffer[base + channel] = 1.0
			head_buffer[base + 13] = 0.5
			head_buffer[base + 14] = 0.25
	head_multimesh.visible_instance_count = friendly_count

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
	# The single head submission follows every friendly trail and precedes danger.
	attach_material(canvas)
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
	if friendly_count > 0:
		canvas.draw_multimesh(head_multimesh, head_atlas_texture)

func get_stats() -> Dictionary:
	var logical_head_capacity: int = 0
	for head: HeadBatch in heads.values():
		logical_head_capacity += head.capacity
	var head_capacity: int = head_multimesh.instance_count
	var allocated: int = bodies.instance_count + head_capacity
	for ring: RingBatch in rings.values():
		allocated += ring.multimesh.instance_count
	return {"friendly_count": friendly_count, "body_instances": ember_count,
		"core_instances": friendly_count, "head_instances": friendly_count,
		"head_families": heads.size(), "head_gpu_batches": 1 if friendly_count > 0 else 0,
		"logical_head_capacity": logical_head_capacity, "allocated_head_instances": head_capacity,
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

static func _write_head_instance(buffer: PackedFloat32Array, index: int, point: Vector2, direction: Vector2, scale: float, stride: int = INSTANCE_STRIDE) -> void:
	var offset: int = index * stride
	var x: float = direction.x * scale
	var y: float = direction.y * scale
	buffer[offset] = x
	buffer[offset + 1] = -y
	buffer[offset + 3] = point.x
	buffer[offset + 4] = y
	buffer[offset + 5] = x
	buffer[offset + 7] = point.y

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

static func _multimesh(mesh: ArrayMesh, capacity: int, custom_data: bool = false) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_2D
	result.use_colors = true
	result.use_custom_data = custom_data
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
