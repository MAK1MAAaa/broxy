extends SceneTree
## Retained bounce buffers must preserve visible data, ordering and the global cap.

const LIMIT: int = CombatSim.SHOT_LIMIT
const BOUNCE_COLOR: Color = Color("c7b0f3")

var _checks: int = 0
var _failures: int = 0
var _native_readback: bool = false


func _initialize() -> void:
	_native_readback = DisplayServer.get_name() != "headless"
	_test_reuse()
	_test_bulk_buffers()
	_test_trail_buffer_reuse()
	_test_head_buffer_capacity_reuse()
	_test_capacity_reclamation()
	_test_head_capacity_reclamation()
	_test_limit_and_empty()
	_test_simulation_unchanged()
	print("ProjectileCapacity: %d assertions, %d failures; native GPU readback=%s" % [_checks, _failures, _native_readback])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _shots(counts: Dictionary, source: String = "bone") -> Array[CombatSim.Shot]:
	var shots: Array[CombatSim.Shot] = []
	for radius: float in counts:
		for index: int in int(counts[radius]):
			var shot := CombatSim.Shot.new()
			shot.slot = shots.size()
			shot.active = true
			shot.source = source
			shot.rune = "bounce"
			shot.radius = radius - 3.0
			shot.color = GameCatalog.weapon(source).color
			shot.position = Vector2(100 + shots.size() % 50 * 18, 190 + shots.size() / 50 * 8)
			shot.previous = shot.position - Vector2(4, 0)
			shot.velocity = Vector2(240, 0)
			shot.damage = 16.0
			shot.life = 2.0
			shot.remaining = 3
			shots.append(shot)
	return shots


func _ring_capacity(painter: ProjectilePainter) -> int:
	var total: int = 0
	for ring: ProjectilePainter.RingBatch in painter.rings.values():
		total += ring.multimesh.instance_count
	return total


func _colors_near(actual: Color, expected: Color) -> bool:
	var tolerance: float = 1.0 / 1024.0
	return absf(actual.r - expected.r) <= tolerance and absf(actual.g - expected.g) <= tolerance and absf(actual.b - expected.b) <= tolerance and absf(actual.a - expected.a) <= tolerance


func _buffer_instance_matches(buffer: PackedFloat32Array, index: int, point: Vector2, radius: float, color: Color) -> bool:
	var offset: int = index * 12
	if buffer.size() < offset + 12:
		return false
	return is_equal_approx(buffer[offset], radius) and is_equal_approx(buffer[offset + 5], radius) \
		and is_zero_approx(buffer[offset + 1]) and is_zero_approx(buffer[offset + 2]) \
		and is_zero_approx(buffer[offset + 4]) and is_zero_approx(buffer[offset + 6]) \
		and Vector2(buffer[offset + 3], buffer[offset + 7]).is_equal_approx(point) \
		and _colors_near(Color(buffer[offset + 8], buffer[offset + 9], buffer[offset + 10], buffer[offset + 11]), color)


func _native_instance_matches(multimesh: MultiMesh, index: int, point: Vector2, radius: float, color: Color) -> bool:
	var transform: Transform2D = multimesh.get_instance_transform_2d(index)
	return transform.origin.is_equal_approx(point) and transform.x.is_equal_approx(Vector2(radius, 0)) \
		and transform.y.is_equal_approx(Vector2(0, radius)) and _colors_near(multimesh.get_instance_color(index), color)


func _head_buffer_matches(buffer: PackedFloat32Array, index: int, point: Vector2, direction: Vector2, scale: float) -> bool:
	var offset: int = index * ProjectilePainter.HEAD_INSTANCE_STRIDE
	if buffer.size() < offset + ProjectilePainter.HEAD_INSTANCE_STRIDE:
		return false
	return is_equal_approx(buffer[offset], direction.x * scale) and is_equal_approx(buffer[offset + 1], -direction.y * scale) \
		and is_equal_approx(buffer[offset + 4], direction.y * scale) and is_equal_approx(buffer[offset + 5], direction.x * scale) \
		and is_zero_approx(buffer[offset + 2]) and is_zero_approx(buffer[offset + 6]) \
		and Vector2(buffer[offset + 3], buffer[offset + 7]).is_equal_approx(point) \
		and _colors_near(Color(buffer[offset + 8], buffer[offset + 9], buffer[offset + 10], buffer[offset + 11]), Color.WHITE)


func _check_visible(painter: ProjectilePainter, shots: Array[CombatSim.Shot], label: String, expected_head_capacity: int = -1) -> void:
	var ring_counts: Dictionary = {}
	var head_counts: Dictionary = {}
	var visible: int = 0
	var bodies: int = 0
	var packed_data_matches: bool = true
	var native_data_matches: bool = true
	for shot: CombatSim.Shot in shots:
		if not shot.active or shot.hostile or visible >= LIMIT:
			continue
		var key: String = shot.source + ":" + shot.rune
		var head_index: int = int(head_counts.get(key, 0))
		head_counts[key] = head_index + 1
		var head: ProjectilePainter.HeadBatch = painter.heads[key]
		var global_head_index: int = head.start + head_index
		var direction: Vector2 = shot.velocity.normalized()
		if direction.is_zero_approx():
			direction = Vector2.RIGHT
		var scale: float = shot.radius / head.base_radius
		packed_data_matches = packed_data_matches and _head_buffer_matches(painter.head_buffer, global_head_index, shot.position, direction, scale)
		var custom_offset: int = global_head_index * ProjectilePainter.HEAD_INSTANCE_STRIDE + 12
		var custom := Color(float(head.frame) / float(ProjectilePainter.HEAD_ATLAS_COLUMNS - 1), 0.5, 0.25, 0.0)
		packed_data_matches = packed_data_matches and _colors_near(Color(painter.head_buffer[custom_offset], painter.head_buffer[custom_offset + 1], painter.head_buffer[custom_offset + 2], painter.head_buffer[custom_offset + 3]), custom)
		if _native_readback:
			var transform: Transform2D = painter.head_multimesh.get_instance_transform_2d(global_head_index)
			var expected := Transform2D(direction * scale, Vector2(-direction.y, direction.x) * scale, shot.position)
			native_data_matches = native_data_matches and transform.is_equal_approx(expected)
			native_data_matches = native_data_matches and _colors_near(painter.head_multimesh.get_instance_color(global_head_index), Color.WHITE)
			native_data_matches = native_data_matches and _colors_near(painter.head_multimesh.get_instance_custom_data(global_head_index), custom)
		if shot.source == "ember":
			var body_color := Color("dab779")
			if shot.rune == "blast":
				body_color = body_color.lerp(Color("dca0fa"), 0.35)
			packed_data_matches = packed_data_matches and _buffer_instance_matches(painter._body_buffer, bodies, shot.position, shot.radius, body_color)
			if _native_readback:
				native_data_matches = native_data_matches and _native_instance_matches(painter.bodies, bodies, shot.position, shot.radius, body_color)
			bodies += 1
		visible += 1
		if shot.rune != "bounce":
			continue
		var radius: float = shot.radius + 3.0
		var index: int = int(ring_counts.get(radius, 0))
		ring_counts[radius] = index + 1
		var ring: ProjectilePainter.RingBatch = painter.rings[radius]
		packed_data_matches = packed_data_matches and _buffer_instance_matches(ring.buffer, index, shot.position, 1.0, BOUNCE_COLOR)
		if _native_readback:
			native_data_matches = native_data_matches and _native_instance_matches(ring.multimesh, index, shot.position, 1.0, BOUNCE_COLOR)
	var visible_counts_match: bool = painter.rings.size() == ring_counts.size() and painter.heads.size() == head_counts.size() and painter.bodies.visible_instance_count == bodies
	var buffer_sizes_match: bool = painter._body_buffer.size() == painter.bodies.instance_count * 12
	buffer_sizes_match = buffer_sizes_match and painter.head_buffer.size() == painter.head_multimesh.instance_count * ProjectilePainter.HEAD_INSTANCE_STRIDE
	var physical_head_capacity: int = visible if expected_head_capacity < 0 else expected_head_capacity
	visible_counts_match = visible_counts_match and painter.head_multimesh.visible_instance_count == visible and painter.head_multimesh.instance_count == physical_head_capacity
	var logical_head_capacity: int = 0
	var global_head_cursor: int = 0
	for key: String in painter.heads:
		var head: ProjectilePainter.HeadBatch = painter.heads[key]
		logical_head_capacity += head.capacity
		visible_counts_match = visible_counts_match and head.cursor == int(head_counts.get(key, 0)) and head.start == global_head_cursor
		visible_counts_match = visible_counts_match and head.capacity >= head.cursor
		global_head_cursor += head.cursor
	visible_counts_match = visible_counts_match and global_head_cursor == visible
	var geometry_matches: bool = true
	for radius: float in painter.rings:
		var ring: ProjectilePainter.RingBatch = painter.rings[radius]
		visible_counts_match = visible_counts_match and ring.cursor == int(ring_counts.get(radius, 0))
		visible_counts_match = visible_counts_match and ring.multimesh.visible_instance_count == ring.cursor
		visible_counts_match = visible_counts_match and ring.multimesh.instance_count >= ring.multimesh.visible_instance_count
		buffer_sizes_match = buffer_sizes_match and ring.buffer.size() == ring.multimesh.instance_count * 12
		var vertices: Variant = ring.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		geometry_matches = geometry_matches and vertices.size() == ProjectilePainter.RING_SIDES * 6
		for vertex: Variant in vertices:
			var distance: float = Vector2(vertex.x, vertex.y).length()
			geometry_matches = geometry_matches and (is_equal_approx(distance, radius - 0.5) or is_equal_approx(distance, radius + 0.5))
	_check(visible_counts_match, label + ": every head occupies its family-ordered global GPU range and every ring cursor matches its population")
	_check(buffer_sizes_match and packed_data_matches, label + ": reusable buffers preserve transform/color bytes and sixteen-float head frame/sentinel data")
	_check(geometry_matches, label + ": bounce rings retain their original one-pixel geometry")
	_check(logical_head_capacity <= LIMIT and painter.head_multimesh.instance_count <= LIMIT and _ring_capacity(painter) <= LIMIT and painter.get_stats()["allocated_instances"] <= LIMIT * 3, label + ": logical head ranges, both real GPU pools and their actual total remain within their limits")
	_check(painter.head_multimesh.use_custom_data and painter.get_stats()["head_gpu_batches"] == (1 if visible > 0 else 0) and painter.get_stats()["allocated_head_instances"] == painter.head_multimesh.instance_count, label + ": honest rendering statistics expose one physical custom-data head batch rather than one GPU allocation per family")
	if _native_readback:
		_check(native_data_matches, label + ": native GPU readback preserves every body, rotated head and ring instance in family order")


func _test_reuse() -> void:
	var painter := ProjectilePainter.new()
	var original: Array[CombatSim.Shot] = _shots({11.0: 64})
	painter.rebuild(original)
	var ring: ProjectilePainter.RingBatch = painter.rings[11.0]
	var mesh_rid: RID = ring.multimesh.mesh.get_rid()
	for count: int in [20, 45, 64, 12, 63]:
		var shots: Array[CombatSim.Shot] = _shots({11.0: count})
		painter.rebuild(shots)
		_check(painter.rings[11.0] == ring and ring.multimesh.mesh.get_rid() == mesh_rid, "Population changes retain the same batch and authored radius mesh")
		_check(ring.multimesh.instance_count == 64 and ring.multimesh.visible_instance_count == count, "Falling and regrowing populations reuse sixty-four allocated slots without repeated resizing")
		_check_visible(painter, shots, "reuse/%d" % count, 64)
		if _native_readback and count < 64:
			var hidden: Transform2D = ring.multimesh.get_instance_transform_2d(63)
			_check(hidden.origin.is_equal_approx(original[63].position), "Hidden slot data survives a visible-count reduction without a buffer reset")
	var grown: Array[CombatSim.Shot] = _shots({11.0: 65})
	painter.rebuild(grown)
	_check(ring.multimesh.instance_count == 65, "Demand beyond retained capacity grows only the required buffer")
	painter.rebuild(_shots({11.0: 32}))
	_check(ring.multimesh.instance_count == 65 and ring.multimesh.visible_instance_count == 32, "Newly grown capacity also survives a later population reduction")


func _test_bulk_buffers() -> void:
	var painter := ProjectilePainter.new()
	var shots: Array[CombatSim.Shot] = []
	for definition: ContentDef in GameCatalog.weapons():
		for rune: String in ["", "pierce", "bounce", "blast"]:
			var shot := CombatSim.Shot.new()
			shot.active = true
			shot.source = definition.id
			shot.rune = rune
			shot.radius = definition.projectile_radius
			shot.color = definition.color
			shot.position = Vector2(123.25 + shots.size() * 5.5, 456.75 - shots.size() * 0.75)
			shot.velocity = Vector2.from_angle(float(shots.size()) * 0.2) * definition.projectile_speed
			if rune.is_empty():
				shot.velocity = Vector2.ZERO
			shots.append(shot)
	painter.rebuild(shots)
	_check_visible(painter, shots, "bulk/all-weapon-sockets")
	shots.reverse()
	for shot: CombatSim.Shot in shots:
		shot.position += Vector2(-13.125, 7.875)
	painter.rebuild(shots)
	_check_visible(painter, shots, "bulk/reordered-sockets")
	var buffer := PackedFloat32Array()
	buffer.resize(24)
	var first_point := Vector2(123.25, -456.75)
	var second_point := Vector2(-731.5, 18.125)
	var first_color := Color(0.123, 0.456, 0.789, 0.625)
	var second_color := Color(0.913, 0.117, 0.537, 0.375)
	ProjectilePainter._write_instance(buffer, 0, first_point, 2.5, first_color)
	ProjectilePainter._write_instance(buffer, 1, second_point, 0.0, second_color)
	_check(_buffer_instance_matches(buffer, 0, first_point, 2.5, first_color) and _buffer_instance_matches(buffer, 1, second_point, 0.0, second_color), "The public buffer layout retains fractional signed origins, independent RGBA components and a zero-scale hollow head")
	if _native_readback:
		var probe := MultiMesh.new()
		probe.transform_format = MultiMesh.TRANSFORM_2D
		probe.use_colors = true
		probe.mesh = painter._head_meshes["bone"]
		probe.instance_count = 2
		probe.buffer = buffer
		_check(_native_instance_matches(probe, 0, first_point, 2.5, first_color) and _native_instance_matches(probe, 1, second_point, 0.0, second_color), "Native bulk upload decodes the twelve-float transform/color layout with no transposition, alpha loss or extra filled head")


func _test_trail_buffer_reuse() -> void:
	var painter := ProjectilePainter.new()
	var shapes: Dictionary = {
		"frost:": [PackedVector2Array([Vector2(75, 190), Vector2(100, 190)]),
			PackedVector2Array([Vector2(75, 187), Vector2(105, 190), Vector2(75, 193), Vector2(105, 190)])],
		"return_ring:pierce": [PackedVector2Array([Vector2(84, 190), Vector2(90, 190)]),
			PackedVector2Array([Vector2(84, 187), Vector2(90, 187), Vector2(84, 193), Vector2(90, 193)])],
		"ember:blast": [PackedVector2Array([Vector2(76, 190), Vector2(100, 190)]), PackedVector2Array()],
		"bone:bounce": [PackedVector2Array([Vector2(82, 190), Vector2(100, 190)]), PackedVector2Array()],
	}
	var frames: Array[Dictionary] = [
		{"count": 3, "reverse": false, "cull": false, "offscreen": false},
		{"count": 1, "reverse": true, "cull": false, "offscreen": false},
		{"count": 3, "reverse": true, "cull": true, "offscreen": false},
		{"count": 2, "reverse": false, "cull": false, "offscreen": true},
		{"count": 3, "reverse": false, "cull": false, "offscreen": false},
		{"count": 0, "reverse": false, "cull": false, "offscreen": false},
		{"count": 3, "reverse": true, "cull": true, "offscreen": false},
		{"count": 3, "reverse": false, "cull": false, "offscreen": false},
	]
	var retained: Dictionary = {}
	for frame_index: int in frames.size():
		var frame: Dictionary = frames[frame_index]
		var count: int = int(frame["count"])
		var counts: Dictionary = {}
		if count > 0:
			for key: String in shapes:
				counts[key] = count
		var shots: Array[CombatSim.Shot] = _head_populations(counts)
		if frame["cull"]:
			for index: int in range(count - 1, shots.size(), count):
				shots[index].position = Vector2(10000, 190)
		if frame["reverse"]:
			shots.reverse()
		var view := Rect2(40, 150, 150, 80) if frame["cull"] else Rect2()
		if frame["offscreen"]:
			view = Rect2(-5000, -5000, 50, 50)
		painter.rebuild(shots, view)
		_check_visible(painter, shots, "trail-reuse/%d" % frame_index, 0 if count == 0 else 12)
		if count == 0:
			_check(painter.trails.is_empty(), "An empty frame removes every retained trail family")
			for trail: ProjectilePainter.TrailBatch in retained.values():
				_check(trail.points.is_empty() and trail.wings.is_empty(), "Removed trail objects expose no geometry left from an earlier frame")
			retained.clear()
			continue
		var visible_count: int = 0 if frame["offscreen"] else count - 1 if frame["cull"] else count
		for key: String in shapes:
			var trail: ProjectilePainter.TrailBatch = painter.trails[key]
			var expected_points := PackedVector2Array()
			var expected_wings := PackedVector2Array()
			var shape: Array = shapes[key]
			for ordinal: int in visible_count:
				var index: int = visible_count - ordinal - 1 if frame["reverse"] else ordinal
				var offset := Vector2(index * 18, 0)
				for point: Vector2 in shape[0]:
					expected_points.append(point + offset)
				for point: Vector2 in shape[1]:
					expected_wings.append(point + offset)
			_check(trail.points.to_byte_array() == expected_points.to_byte_array() and trail.wings.to_byte_array() == expected_wings.to_byte_array(), "Trail reuse preserves exact authored segment bytes, input ordering and viewport clipping: %d/%s" % [frame_index, key])
			_check(trail.point_cursor == expected_points.size() and trail.wing_cursor == expected_wings.size(), "Trail cursors end at the visible array lengths after population and viewport changes")
			_check(trail.style.has_halo == (key != "ember:blast"), "Ember remains unhaloed while frost, return-ring and bone keep their halo pass")
			if retained.has(key):
				_check(retained[key] == trail, "Surviving families reuse the same trail object through full, clipped and empty-view frames")
			else:
				retained[key] = trail


func _test_head_buffer_capacity_reuse() -> void:
	var painter := ProjectilePainter.new()
	var populations: Array[int] = [6, 2, 11, 1, 0, 2]
	var capacities: Array[int] = [6, 6, 11, 11, 0, 2]
	var previous_buffer := PackedFloat32Array()
	for index: int in populations.size():
		var count: int = populations[index]
		var shots: Array[CombatSim.Shot] = []
		if count > 0:
			shots = _shots({11.0: count})
		painter.rebuild(shots)
		_check(painter.head_multimesh.instance_count == capacities[index] and painter.head_multimesh.visible_instance_count == count
			and painter.head_buffer.size() == capacities[index] * ProjectilePainter.HEAD_INSTANCE_STRIDE,
			"A single global head allocation follows the exact grow, retain, grow, retain, empty, restart capacity sequence")
		_check_visible(painter, shots, "global-capacity/%d" % index, capacities[index])
		if index == 1 or index == 3:
			var first_hidden: int = count * ProjectilePainter.HEAD_INSTANCE_STRIDE
			_check(painter.head_buffer.slice(first_hidden) == previous_buffer.slice(first_hidden), "Shrinking visibility preserves every hidden transform, white channel and frame sentinel in the retained allocation")
			if _native_readback:
				var hidden: int = capacities[index] - 1
				_check(painter.head_multimesh.get_instance_transform_2d(hidden).origin.is_equal_approx(Vector2(100 + hidden * 18, 190)), "The actual native GPU retains hidden head transforms instead of rebuilding the pool on a count reduction")
		previous_buffer = painter.head_buffer.duplicate()


func _test_capacity_reclamation() -> void:
	var painter := ProjectilePainter.new()
	painter.rebuild(_shots({11.0: 900, 7.0: 700}))
	var first: ProjectilePainter.RingBatch = painter.rings[11.0]
	var second: ProjectilePainter.RingBatch = painter.rings[7.0]
	var shots: Array[CombatSim.Shot] = _shots({7.0: 900, 11.0: 100})
	painter.rebuild(shots)
	_check(painter.rings.keys() == [11.0, 7.0], "Reordered input never changes surviving radius-group drawing order")
	_check(painter.rings[11.0] == first and painter.rings[7.0] == second, "Capacity transfer retains both existing MultiMesh groups")
	_check(first.multimesh.instance_count == 700 and second.multimesh.instance_count == 900, "A growing group reclaims exactly two hundred spare slots before exceeding the global cap")
	_check_visible(painter, shots, "reclaim/two-radii", LIMIT)
	shots = _shots({15.0: 300, 7.0: 1100, 11.0: 200})
	painter.rebuild(shots)
	_check(painter.rings.keys() == [11.0, 7.0, 15.0], "A new radius appends after surviving groups even when its shots appear first")
	_check(first.multimesh.instance_count == 200 and second.multimesh.instance_count == 1100 and painter.rings[15.0].multimesh.instance_count == 300, "Combined growth is funded before either an existing or a new radius allocates")
	_check_visible(painter, shots, "reclaim/new-radius")
	shots = _shots({15.0: 1000, 11.0: 300, 7.0: 300})
	painter.rebuild(shots)
	_check(first.multimesh.instance_count == 300 and second.multimesh.instance_count == 300 and painter.rings[15.0].multimesh.instance_count == 1000, "Later pressure can reclaim another group's retained capacity without losing its live instances")
	_check_visible(painter, shots, "reclaim/reversed-growth")
	shots = _shots({15.0: 2, 11.0: 3})
	painter.rebuild(shots)
	_check(not painter.rings.has(7.0) and painter.rings.keys() == [11.0, 15.0], "A radius with no live instances is released immediately without reordering survivors")
	_check(first.multimesh.instance_count == 300 and painter.rings[15.0].multimesh.instance_count == 1000, "Removing an empty group does not gratuitously shrink other active buffers")
	_check_visible(painter, shots, "reclaim/released-radius", LIMIT)


func _head_populations(counts: Dictionary) -> Array[CombatSim.Shot]:
	var result: Array[CombatSim.Shot] = []
	for key: String in counts:
		var source: String = key.get_slice(":", 0)
		var group: Array[CombatSim.Shot] = _shots({GameCatalog.weapon(source).projectile_radius + 3.0: counts[key]}, source)
		for shot: CombatSim.Shot in group:
			shot.rune = key.get_slice(":", 1)
			result.append(shot)
	return result


func _test_head_capacity_reclamation() -> void:
	var painter := ProjectilePainter.new()
	painter.rebuild(_head_populations({"bone:pierce": 900, "ember:blast": 700}))
	var first: ProjectilePainter.HeadBatch = painter.heads["bone:pierce"]
	var second: ProjectilePainter.HeadBatch = painter.heads["ember:blast"]
	var shots: Array[CombatSim.Shot] = _head_populations({"ember:blast": 900, "bone:pierce": 100})
	painter.rebuild(shots)
	_check(painter.heads.keys() == ["bone:pierce", "ember:blast"] and painter.heads["bone:pierce"] == first and painter.heads["ember:blast"] == second, "Head-family population changes retain surviving batches and their order")
	_check(first.capacity == 700 and second.capacity == 900, "Logical head family capacities reclaim only the range required by a growing family")
	_check_visible(painter, shots, "heads/two-families", LIMIT)
	shots = _head_populations({"return_ring:bounce": 300, "ember:blast": 1100, "bone:pierce": 200})
	painter.rebuild(shots)
	_check(painter.heads.keys() == ["bone:pierce", "ember:blast", "return_ring:bounce"], "A new textured family appends after existing family groups")
	_check(first.capacity == 200 and second.capacity == 1100 and painter.heads["return_ring:bounce"].capacity == 300, "Logical head-family growth preserves its separate sixteen-hundred-slot metadata cap without allocating family GPU pools")
	_check_visible(painter, shots, "heads/new-family")
	shots = _head_populations({"return_ring:bounce": 1000, "bone:pierce": 300, "ember:blast": 300})
	painter.rebuild(shots)
	_check(first.capacity == 300 and second.capacity == 300 and painter.heads["return_ring:bounce"].capacity == 1000, "Logical head ranges can move in the opposite direction without dropping any global visible instance")
	_check_visible(painter, shots, "heads/reversed-growth")
	painter.rebuild(_head_populations({"return_ring:bounce": 1}))
	_check(painter.heads.size() == 1 and painter.heads["return_ring:bounce"].capacity == 1000 and painter.head_multimesh.instance_count == LIMIT
		and painter.head_multimesh.visible_instance_count == 1 and painter.head_buffer.size() == LIMIT * ProjectilePainter.HEAD_INSTANCE_STRIDE,
		"Empty logical families release immediately while the one physical pool retains its exact highest nonempty demand")


func _test_limit_and_empty() -> void:
	var painter := ProjectilePainter.new()
	var shots: Array[CombatSim.Shot] = _shots({11.0: LIMIT}, "ember")
	painter.rebuild(shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["allocated_instances"] == LIMIT * 3 and stats["total_visible_instances"] == LIMIT * 3, "Sixteen hundred ember bounce shots retain all forty-eight hundred visible and allocated instances")
	_check_visible(painter, shots, "limit/single-radius")
	shots = _shots({7.0: 534, 11.0: 533, 15.0: 533}, "ember")
	painter.rebuild(shots)
	stats = painter.get_stats()
	_check(_ring_capacity(painter) == LIMIT and stats["total_visible_instances"] == LIMIT * 3, "Sixteen hundred shots across three radii retain the full visible population within the original budget")
	_check_visible(painter, shots, "limit/mixed-radii")
	var extra: Array[CombatSim.Shot] = _shots({19.0: 1})
	shots.append(extra[0])
	painter.rebuild(shots)
	_check(painter.friendly_count == LIMIT and not painter.rings.has(19.0), "An over-limit input cannot allocate a seventeenth-hundredth instance or an extra radius")
	var empty: Array[CombatSim.Shot] = []
	painter.rebuild(empty)
	stats = painter.get_stats()
	_check(painter.rings.is_empty() and painter.heads.is_empty() and painter.trails.is_empty() and stats["total_visible_instances"] == 0, "An empty rebuild releases every radius group and hides all previous geometry")
	_check(stats["allocated_instances"] == LIMIT, "An empty rebuild leaves only the original fixed body buffer")
	painter.rebuild(_shots({7.0: 1}))
	_check(painter.rings.size() == 1 and painter.rings[7.0].multimesh.instance_count == 1, "Reactivation allocates only the new radius demand, without resurrecting released capacity")


func _simulation() -> CombatSim:
	var state := RunState.new()
	state.begin(20261028, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(1000, 550)
	for point: Vector2 in [Vector2(330, 300), Vector2(375, 300), Vector2(420, 300)]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.health = 10000.0
		enemy.max_health = 10000.0
		enemy.action_timer = 9999.0
	for source: String in ["bone", "frost", "return_ring"]:
		sim.fire_weapon(source, "bounce", Vector2(307, 300), Vector2.RIGHT)
	return sim


func _signature(sim: CombatSim) -> String:
	var data: Array = [sim.rng.state, sim.run.rng.state, sim.snapshot(), sim.run.summary(),
		sim.primary_hits, sim.secondary_hits, sim.damage_by_weapon, sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		data.append([shot.slot, shot.active, shot.hostile, shot.source, shot.rune, shot.position,
			shot.previous, shot.velocity, shot.color, shot.radius, shot.damage, shot.life, shot.remaining,
			shot.innate_remaining, shot.hit_ids.duplicate(), shot.return_after, shot.return_speed,
			shot.returning, shot.return_cancelled, shot.homing, shot.slow])
	for enemy: CombatSim.Enemy in sim.enemies:
		data.append([enemy.slot, enemy.uid, enemy.active, enemy.position, enemy.velocity, enemy.health,
			enemy.age, enemy.action_timer, enemy.slow_timer, enemy.slow_factor, enemy.hurt_timer])
	return JSON.stringify(data)


func _test_simulation_unchanged() -> void:
	var painted: CombatSim = _simulation()
	var oracle: CombatSim = _simulation()
	var painter := ProjectilePainter.new()
	var initial_head_capacity: int = painted.shot_count
	_check(_signature(painted) == _signature(oracle), "The real-fire fixtures begin with identical simulation and RNG state")
	for step: int in 12:
		var before: String = _signature(painted)
		painter.rebuild(painted.shots)
		painter.rebuild(painted.shots)
		_check(_signature(painted) == before, "Repeated capacity preparation never changes either RNG, hit budgets or flight state")
		_check_visible(painter, painted.shots, "real-fire/%d" % step, initial_head_capacity if painted.shot_count > 0 else 0)
		painted.step(1.0 / 60.0, Vector2.ZERO)
		oracle.step(1.0 / 60.0, Vector2.ZERO)
		_check(_signature(painted) == _signature(oracle), "A formal collision step is identical with or without retained ring-buffer preparation")
	_check(painted.primary_hits > 0, "The read-only comparison exercises actual direct collisions")
