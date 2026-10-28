class_name GroundingPainter
extends RefCounted
## Shared pixel contact shadows; projections never advance or mutate combat state.

const CAPACITY: int = CombatSim.ENEMY_LIMIT + CombatSim.DROP_LIMIT + 1
const INSTANCE_STRIDE: int = 12
const CULL_MARGIN: float = 96.0
const INK: Color = Color("243752")
const PLAYER: int = 0
const ENEMY: int = 1
const PICKUP: int = 2

var shadows: MultiMesh
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _kinds: PackedByteArray = PackedByteArray()
var _ids: PackedInt64Array = PackedInt64Array()
var _active_count: int = 0
var _player_count: int = 0
var _enemy_count: int = 0
var _pickup_count: int = 0

func _init() -> void:
	shadows = MultiMesh.new()
	shadows.transform_format = MultiMesh.TRANSFORM_2D
	shadows.use_colors = true
	shadows.mesh = _shadow_mesh()
	shadows.instance_count = CAPACITY
	shadows.visible_instance_count = 0
	_buffer.resize(CAPACITY * INSTANCE_STRIDE)
	_kinds.resize(CAPACITY)
	_ids.resize(CAPACITY)

func clear() -> void:
	_active_count = 0
	_player_count = 0
	_enemy_count = 0
	_pickup_count = 0
	shadows.visible_instance_count = 0

func rebuild(sim: CombatSim, view: Rect2) -> void:
	clear()
	if sim == null or not _valid_view(view):
		return
	var visible: Rect2 = view.grow(CULL_MARGIN)
	if sim.run != null and _add(PLAYER, -1, sim.player_position + Vector2(0, 12), Vector2(18, 4), 1.0, visible):
		_player_count += 1
	for index: int in mini(sim.enemies.size(), CombatSim.ENEMY_LIMIT):
		var enemy: CombatSim.Enemy = sim.enemies[index]
		if enemy == null or not enemy.active or enemy.definition == null or not is_finite(enemy.radius) or enemy.radius <= 0.0:
			continue
		var size: float = enemy.radius * 3.0 + 15.0
		var width: float = clampf(enemy.radius * 0.95, 10.0, 36.0)
		var height: float = clampf(enemy.radius * 0.22, 3.0, 5.0)
		if enemy.definition.id == "boss":
			width = minf(36.0, width * 1.12)
			height = 3.8
		if _add(ENEMY, enemy.uid, enemy.position + Vector2(0, size * 0.25), Vector2(width, height), 1.0, visible):
			_enemy_count += 1
	for index: int in mini(sim.souls.size(), CombatSim.DROP_LIMIT):
		var soul: CombatSim.Soul = sim.souls[index]
		if soul == null or not soul.active or soul.value <= 0:
			continue
		var large: bool = soul.value > 1
		if _add(PICKUP, soul.slot, soul.position + Vector2(0, 4), Vector2(6, 2) if large else Vector2(4, 1.5), 0.70 if large else 0.55, visible):
			_pickup_count += 1
	shadows.buffer = _buffer
	shadows.visible_instance_count = _active_count

func draw(canvas: CanvasItem) -> void:
	if canvas != null and _active_count > 0:
		canvas.draw_multimesh(shadows, null)

func get_stats() -> Dictionary:
	return {"active_count": _active_count, "player_count": _player_count,
		"enemy_count": _enemy_count, "pickup_count": _pickup_count,
		"capacity": CAPACITY, "draw_commands": 1 if _active_count > 0 else 0}

func geometry_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in _active_count:
		var offset: int = index * INSTANCE_STRIDE
		result.append({"kind": _kinds[index], "id": _ids[index],
			"position": Vector2(_buffer[offset + 3], _buffer[offset + 7]),
			"radius": Vector2(_buffer[offset], _buffer[offset + 5]),
			"color": Color(_buffer[offset + 8], _buffer[offset + 9], _buffer[offset + 10], _buffer[offset + 11])})
	return result

static func _valid_view(view: Rect2) -> bool:
	return view.position.is_finite() and view.size.is_finite() and view.end.is_finite() and view.size.x > 0.0 and view.size.y > 0.0 and view.grow(CULL_MARGIN).end.is_finite()

func _add(kind: int, id: int, point: Vector2, radius: Vector2, opacity: float, visible: Rect2) -> bool:
	if _active_count >= CAPACITY or not point.is_finite() or not radius.is_finite() or not visible.has_point(point):
		return false
	var index: int = _active_count
	var offset: int = index * INSTANCE_STRIDE
	_buffer[offset] = radius.x
	_buffer[offset + 1] = 0.0
	_buffer[offset + 2] = 0.0
	_buffer[offset + 3] = point.x
	_buffer[offset + 4] = 0.0
	_buffer[offset + 5] = radius.y
	_buffer[offset + 6] = 0.0
	_buffer[offset + 7] = point.y
	_buffer[offset + 8] = INK.r
	_buffer[offset + 9] = INK.g
	_buffer[offset + 10] = INK.b
	_buffer[offset + 11] = opacity
	_kinds[index] = kind
	_ids[index] = id
	_active_count += 1
	return true

static func _shadow_mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	_append_band(vertices, colors, Rect2(-0.66, -1.0, 1.32, 0.5), 0.08)
	_append_band(vertices, colors, Rect2(-1.0, -0.5, 2.0, 1.0), 0.16)
	_append_band(vertices, colors, Rect2(-0.66, 0.5, 1.32, 0.5), 0.08)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh

static func _append_band(vertices: PackedVector2Array, colors: PackedColorArray, band: Rect2, alpha: float) -> void:
	var left: Vector2 = band.position
	var right: Vector2 = band.end
	for point: Vector2 in [left, Vector2(right.x, left.y), right, left, right, Vector2(left.x, right.y)]:
		vertices.append(point)
		colors.append(Color(1.0, 1.0, 1.0, alpha))
