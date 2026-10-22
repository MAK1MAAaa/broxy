class_name EnemyTelegraphPainter
extends RefCounted
## Direction and windup marks, not collision ranges or locked caster aim.

const RING_STEPS: int = 16
const ARROW_LENGTH: float = 130.0
const MAX_SEGMENTS_PER_ENEMY: int = 36
const BATCH_COUNT: int = 3
const CORAL: Color = Color("ff9272")

class LineBatch:
	var points: PackedVector2Array = PackedVector2Array()
	var color: Color = Color.WHITE

var batches: Array[LineBatch] = []
var charge_count: int = 0
var cast_count: int = 0
var neutral_charge_count: int = 0
var _ring_directions: PackedVector2Array = PackedVector2Array()
var caster_base: MultiMesh
var caster_ticks: MultiMesh
var caster_arcs: Array[MultiMesh] = []
var _casters: Array[CombatSim.Enemy] = []
var _arc_steps: Array[int] = []
var _caster_segments: int = 0

func _init() -> void:
	for index: int in range(RING_STEPS + 1):
		_ring_directions.append(Vector2.from_angle(-PI * 0.5 + TAU * float(index) / RING_STEPS))
	for stage: int in BATCH_COUNT:
		var batch := LineBatch.new()
		batch.color = Color(CORAL, [0.50, 0.74, 0.98][stage])
		batches.append(batch)
	caster_base = _multimesh(_outlined_mesh(_arc_points(RING_STEPS)), CombatSim.ENEMY_LIMIT)
	var tick_points := PackedVector2Array()
	for index: int in 4:
		var direction: Vector2 = _ring_directions[index * 4]
		tick_points.append(direction * 22.0)
		tick_points.append(direction * 26.0)
	caster_ticks = _multimesh(_outlined_mesh(tick_points), CombatSim.ENEMY_LIMIT)
	# Index zero represents an empty arc. Meshes are shared; no per-frame tessellation.
	for steps: int in RING_STEPS + 1:
		caster_arcs.append(_multimesh(_outlined_mesh(_arc_points(steps)) if steps > 0 else null, 0))

func clear() -> void:
	charge_count = 0
	cast_count = 0
	neutral_charge_count = 0
	_caster_segments = 0
	_casters.clear()
	_arc_steps.clear()
	for batch: LineBatch in batches:
		batch.points.clear()
	caster_base.visible_instance_count = 0
	caster_ticks.visible_instance_count = 0
	for arc: MultiMesh in caster_arcs:
		arc.visible_instance_count = 0

func rebuild(enemies: Array[CombatSim.Enemy]) -> void:
	clear()
	var considered: int = 0
	for enemy: CombatSim.Enemy in enemies:
		if considered >= CombatSim.ENEMY_LIMIT:
			break
		considered += 1
		if not enemy.active or enemy.definition == null or enemy.mode != 1:
			continue
		if not enemy.position.is_finite() or not is_finite(enemy.action_timer):
			continue
		if enemy.definition.id == "rusher":
			charge_count += 1
			_charge(enemy)
		elif enemy.definition.id == "caster":
			cast_count += 1
			_casters.append(enemy)
	_rebuild_casters()

func draw(canvas: CanvasItem) -> void:
	# Reused color batches bound native draw commands even with hundreds of warnings.
	for batch: LineBatch in batches:
		if batch.points.is_empty():
			continue
		canvas.draw_multiline(batch.points, Color(0.03, 0.035, 0.055, batch.color.a * 0.9), 4.5, true)
		canvas.draw_multiline(batch.points, batch.color, 1.8, true)
	if cast_count > 0:
		canvas.draw_multimesh(caster_base, null)
		canvas.draw_multimesh(caster_ticks, null)
	for arc: MultiMesh in caster_arcs:
		if arc.visible_instance_count > 0:
			canvas.draw_multimesh(arc, null)

func get_stats() -> Dictionary:
	var segments: int = _caster_segments
	var active_batches: int = 0
	for batch: LineBatch in batches:
		segments += batch.points.size() / 2
		if not batch.points.is_empty():
			active_batches += 1
	var commands: int = active_batches * 2
	var allocated: int = caster_base.instance_count + caster_ticks.instance_count
	var visible: int = caster_base.visible_instance_count + caster_ticks.visible_instance_count
	if cast_count > 0:
		commands += 2
		active_batches += 2
	for arc: MultiMesh in caster_arcs:
		allocated += arc.instance_count
		visible += arc.visible_instance_count
		if arc.visible_instance_count > 0:
			active_batches += 1
			commands += 1
	return {"charge_count": charge_count, "cast_count": cast_count,
		"neutral_charge_count": neutral_charge_count, "segments": segments,
		"active_batches": active_batches, "draw_commands": commands,
		"allocated_instances": allocated, "visible_instances": visible}

static func windup_progress(remaining: float, duration: float) -> float:
	return clampf(1.0 - remaining / duration, 0.0, 1.0)

func _charge(enemy: CombatSim.Enemy) -> void:
	var progress: float = windup_progress(enemy.action_timer, CombatSim.RUSHER_WINDUP)
	var batch: LineBatch = batches[mini(2, int(progress * 3.0))]
	var center: Vector2 = _safe_center(enemy.position, 10.0)
	_diamond(batch, center, 6.0)
	if not enemy.charge_direction.is_finite() or enemy.charge_direction.length_squared() < 0.0001:
		neutral_charge_count += 1
		return
	var axis: Vector2 = enemy.charge_direction.normalized()
	var side: Vector2 = axis.orthogonal()
	var length: float = _marker_length(center, axis)
	if length < 30.0:
		neutral_charge_count += 1
		return
	var tail: Vector2 = center + axis * minf(enemy.radius + 6.0, length * 0.3)
	var tip: Vector2 = center + axis * length
	var neck: Vector2 = tip - axis * 11.0
	_segment(batch, tail + side * 3.5, neck + side * 3.5)
	_segment(batch, tail - side * 3.5, neck - side * 3.5)
	_segment(batch, neck + side * 7.0, tip)
	_segment(batch, neck - side * 7.0, tip)
	_segment(batch, tail - side * 5.0, tail + side * 5.0)

func _rebuild_casters() -> void:
	var counts: Array[int] = []
	counts.resize(RING_STEPS + 1)
	counts.fill(0)
	for enemy: CombatSim.Enemy in _casters:
		var progress: float = windup_progress(enemy.action_timer, CombatSim.CASTER_WINDUP)
		# Never draw a completed ring before the simulation reaches its deadline.
		var steps: int = mini(RING_STEPS, int(progress * RING_STEPS))
		_arc_steps.append(steps)
		if steps > 0:
			counts[steps] += 1
		_caster_segments += RING_STEPS + 4 + steps
	# Release spare arc slots before growing another group: the total remains <= 340.
	for steps: int in range(1, RING_STEPS + 1):
		if caster_arcs[steps].instance_count > counts[steps]:
			caster_arcs[steps].instance_count = counts[steps]
	for steps: int in range(1, RING_STEPS + 1):
		if caster_arcs[steps].instance_count != counts[steps]:
			caster_arcs[steps].instance_count = counts[steps]
		caster_arcs[steps].visible_instance_count = counts[steps]
	counts.fill(0)
	for index: int in _casters.size():
		var enemy: CombatSim.Enemy = _casters[index]
		var center: Vector2 = _safe_center(enemy.position + Vector2(0, -14), 29.0)
		var progress: float = windup_progress(enemy.action_timer, CombatSim.CASTER_WINDUP)
		var color := Color(CORAL, [0.50, 0.74, 0.98][mini(2, int(progress * 3.0))])
		_instance(caster_base, index, center, Color("b65b50", 0.50))
		_instance(caster_ticks, index, center, color)
		var steps: int = _arc_steps[index]
		if steps > 0:
			_instance(caster_arcs[steps], counts[steps], center, color)
			counts[steps] += 1
	caster_base.visible_instance_count = cast_count
	caster_ticks.visible_instance_count = cast_count

static func _safe_center(point: Vector2, inset: float) -> Vector2:
	var bounds: Rect2 = CombatSim.ARENA.grow(-inset)
	return Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.y, bounds.position.y, bounds.end.y))

static func _marker_length(center: Vector2, axis: Vector2) -> float:
	# Clip a short direction symbol to the arena, rather than inventing a dash endpoint.
	var bounds: Rect2 = CombatSim.ARENA.grow(-10.0)
	var length: float = ARROW_LENGTH
	if axis.x > 0.0001:
		length = minf(length, (bounds.end.x - center.x) / axis.x)
	elif axis.x < -0.0001:
		length = minf(length, (bounds.position.x - center.x) / axis.x)
	if axis.y > 0.0001:
		length = minf(length, (bounds.end.y - center.y) / axis.y)
	elif axis.y < -0.0001:
		length = minf(length, (bounds.position.y - center.y) / axis.y)
	return maxf(0.0, length)

static func _segment(batch: LineBatch, start: Vector2, end: Vector2) -> void:
	batch.points.append(start)
	batch.points.append(end)

static func _diamond(batch: LineBatch, center: Vector2, radius: float) -> void:
	var corners: PackedVector2Array = PackedVector2Array([center + Vector2.UP * radius,
		center + Vector2.RIGHT * radius, center + Vector2.DOWN * radius, center + Vector2.LEFT * radius])
	for index: int in 4:
		_segment(batch, corners[index], corners[(index + 1) % 4])

func _arc_points(steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in steps:
		points.append(_ring_directions[index] * 20.0)
		points.append(_ring_directions[index + 1] * 20.0)
	return points

static func _instance(multimesh: MultiMesh, index: int, point: Vector2, color: Color) -> void:
	multimesh.set_instance_transform_2d(index, Transform2D(0.0, point))
	multimesh.set_instance_color(index, color)

static func _multimesh(mesh: ArrayMesh, capacity: int) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_2D
	result.use_colors = true
	result.mesh = mesh
	result.instance_count = capacity
	result.visible_instance_count = 0
	return result

static func _outlined_mesh(points: PackedVector2Array) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for layer: int in 2:
		var half_width: float = 2.25 if layer == 0 else 0.9
		var color := Color(0.03, 0.035, 0.055, 0.9) if layer == 0 else Color.WHITE
		for index: int in range(0, points.size(), 2):
			var start: Vector2 = points[index]
			var end: Vector2 = points[index + 1]
			var side: Vector2 = (end - start).normalized().orthogonal() * half_width
			for point: Vector2 in [start - side, start + side, end + side,
					start - side, end + side, end - side]:
				vertices.append(point)
				colors.append(color)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh
