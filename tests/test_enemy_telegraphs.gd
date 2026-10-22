extends SceneTree
## Headless state/mesh checks plus native MultiMesh instance-readback verification.

const Painter = preload("res://scripts/combat/enemy_telegraph_painter.gd")
const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0
var _uid: int = 0
var _instance_readback: bool = false
var _renderer_skips: int = 0
var _renderer_checks: int = 0

func _initialize() -> void:
	_instance_readback = _supports_instance_readback()
	if DisplayServer.get_name() != "headless":
		_check(_instance_readback, "A native renderer must expose actual MultiMesh transforms and colors; native checks cannot be skipped")
	_test_filters_and_invalid_values()
	_test_real_windup_states()
	_test_direction_and_local_caster_geometry()
	_test_arena_bounds()
	_test_budget_and_reuse()
	_test_read_only()
	print("EnemyTelegraphs: %d assertions, %d failures" % [_checks, _failures])
	if _renderer_skips > 0:
		print("EnemyTelegraphs: skipped %d renderer checks; MultiMesh instance transform/color readback is unavailable (%s display)" % [_renderer_skips, DisplayServer.get_name()])
	else:
		print("EnemyTelegraphs: executed %d renderer checks using actual MultiMesh instance readback" % _renderer_checks)
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _supports_instance_readback() -> bool:
	# The headless Dummy RenderingServer returns identity/black even after writes.
	# Do not mistake those defaults for real GPU instance data or invent replacements.
	var probe := MultiMesh.new()
	probe.transform_format = MultiMesh.TRANSFORM_2D
	probe.use_colors = true
	probe.instance_count = 1
	var transform := Transform2D(0.0, Vector2(123, 456))
	var color := Color(0.3, 0.4, 0.5, 0.6)
	probe.set_instance_transform_2d(0, transform)
	probe.set_instance_color(0, color)
	# Compatibility rendering stores instance colors at half precision.
	var restored: Color = probe.get_instance_color(0)
	return probe.get_instance_transform_2d(0).is_equal_approx(transform) and _colors_near(restored, color)

func _colors_near(actual: Color, expected: Color) -> bool:
	var tolerance: float = 1.0 / 1024.0
	return absf(actual.r - expected.r) <= tolerance and absf(actual.g - expected.g) <= tolerance and absf(actual.b - expected.b) <= tolerance and absf(actual.a - expected.a) <= tolerance

func _renderer_check(condition: bool, message: String) -> void:
	if _instance_readback:
		_renderer_checks += 1
		_check(condition, message)
	else:
		_renderer_skips += 1

func _enemy(id: String, mode: int = 1, position: Vector2 = Vector2(640, 365)) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = CombatSim.Enemy.new()
	_uid += 1
	enemy.uid = _uid
	enemy.slot = _uid - 1
	enemy.active = true
	enemy.definition = GameCatalog.enemy(id)
	enemy.radius = enemy.definition.radius
	enemy.position = position
	enemy.mode = mode
	enemy.health = enemy.definition.health
	enemy.max_health = enemy.health
	enemy.action_timer = CombatSim.RUSHER_WINDUP * 0.5 if id == "rusher" else CombatSim.CASTER_WINDUP * 0.5
	enemy.charge_direction = Vector2.RIGHT
	return enemy

func _geometry(painter: RefCounted) -> Array:
	var result: Array = []
	for batch: RefCounted in painter.batches:
		result.append({"points": batch.points.duplicate(), "color": batch.color})
	for multimesh: MultiMesh in _caster_multimeshes(painter):
		var instances: Array = []
		if _instance_readback:
			for index: int in multimesh.visible_instance_count:
				instances.append([multimesh.get_instance_transform_2d(index), multimesh.get_instance_color(index)])
		result.append({"mesh": multimesh.mesh, "visible": multimesh.visible_instance_count, "instances": instances})
	return result

func _caster_multimeshes(painter: RefCounted) -> Array[MultiMesh]:
	var result: Array[MultiMesh] = [painter.caster_base, painter.caster_ticks]
	result.append_array(painter.caster_arcs)
	return result

func _mesh_vertices(mesh: Mesh) -> PackedVector2Array:
	var result := PackedVector2Array()
	if mesh == null:
		return result
	for surface: int in mesh.get_surface_count():
		var vertices: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex: Variant in vertices:
			result.append(Vector2(vertex.x, vertex.y))
	return result

func _inside_arena(point: Vector2) -> bool:
	var bounds: Rect2 = CombatSim.ARENA
	return point.is_finite() and point.x >= bounds.position.x - 0.0001 and point.x <= bounds.end.x + 0.0001 and point.y >= bounds.position.y - 0.0001 and point.y <= bounds.end.y + 0.0001

func _all_caster_meshes_local(painter: RefCounted) -> bool:
	for multimesh: MultiMesh in _caster_multimeshes(painter):
		if multimesh.mesh == null:
			continue
		var vertices: PackedVector2Array = _mesh_vertices(multimesh.mesh)
		if vertices.is_empty():
			return false
		for vertex: Vector2 in vertices:
			if not vertex.is_finite() or vertex.length() > 28.251:
				return false
	return true

func _all_points_safe(painter: RefCounted) -> bool:
	for batch: RefCounted in painter.batches:
		if batch.points.size() % 2 != 0:
			return false
		for point: Vector2 in batch.points:
			if not _inside_arena(point):
				return false
	# Caster vertices include both the 2.25 px outline and colored inner triangles.
	# Their real instance transforms must keep the full mesh inside the arena.
	for multimesh: MultiMesh in _caster_multimeshes(painter):
		var vertices: PackedVector2Array = _mesh_vertices(multimesh.mesh)
		for index: int in multimesh.visible_instance_count:
			var transform: Transform2D = multimesh.get_instance_transform_2d(index)
			for vertex: Vector2 in vertices:
				if not _inside_arena(transform * vertex):
					return false
	return true

func _test_filters_and_invalid_values() -> void:
	var painter := Painter.new()
	for id: String in ["rusher", "caster"]:
		for mode: int in [0, 1, 2]:
			var enemy: CombatSim.Enemy = _enemy(id, mode)
			painter.rebuild([enemy])
			var stats: Dictionary = painter.get_stats()
			_check(int(stats["charge_count"]) + int(stats["cast_count"]) == (1 if mode == 1 else 0), "Only windup mode is drawn: %s/%d" % [id, mode])
			enemy.active = false
			painter.rebuild([enemy])
			_check(painter.get_stats()["segments"] == 0, "Dead enemies leave no warning: " + id)
	for id: String in ["chaser", "tank", "boss"]:
		painter.rebuild([_enemy(id)])
		_check(painter.get_stats()["segments"] == 0, "Other enemy families never become windup warnings: " + id)
	var missing: CombatSim.Enemy = _enemy("rusher")
	missing.definition = null
	painter.rebuild([missing])
	_check(painter.get_stats()["segments"] == 0, "An enemy without a definition is ignored")
	for id: String in ["rusher", "caster"]:
		for invalid: float in [INF, -INF, NAN]:
			var enemy: CombatSim.Enemy = _enemy(id)
			enemy.action_timer = invalid
			painter.rebuild([enemy])
			_check(painter.get_stats()["segments"] == 0, "Non-finite timers cannot reach geometry: " + id)
			enemy = _enemy(id)
			enemy.position = Vector2(invalid, 365)
			painter.rebuild([enemy])
			_check(painter.get_stats()["segments"] == 0, "Non-finite positions cannot reach geometry: " + id)
	for direction: Vector2 in [Vector2.ZERO, Vector2(INF, 0), Vector2(NAN, 1)]:
		var enemy: CombatSim.Enemy = _enemy("rusher")
		enemy.charge_direction = direction
		painter.rebuild([enemy])
		var stats: Dictionary = painter.get_stats()
		_check(stats["charge_count"] == 1 and stats["neutral_charge_count"] == 1 and stats["segments"] == 4, "An undefined charge direction uses only the neutral mark")
		_check(_all_points_safe(painter), "Neutral direction marks keep all vertices finite and inside the arena")

func _simulation() -> CombatSim:
	var state: RunState = RunState.new()
	state.begin(9031, "bone")
	var sim: CombatSim = CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(1000, 200)
	return sim

func _test_real_windup_states() -> void:
	var painter := Painter.new()
	_check(CombatSim.RUSHER_WINDUP == 0.65 and CombatSim.CASTER_WINDUP == 0.45, "Named durations retain the existing combat values")
	for duration: float in [CombatSim.RUSHER_WINDUP, CombatSim.CASTER_WINDUP]:
		_check(Painter.windup_progress(duration * 2.0, duration) == 0.0 and Painter.windup_progress(duration, duration) == 0.0, "Windup progress clamps at its real timer start")
		_check(is_equal_approx(Painter.windup_progress(duration * 0.5, duration), 0.5), "Windup progress follows the remaining real timer")
		_check(Painter.windup_progress(0.0, duration) == 1.0 and Painter.windup_progress(-duration, duration) == 1.0, "Windup progress clamps at and beyond expiry")
	var rushing: CombatSim = _simulation()
	var rusher: CombatSim.Enemy = rushing.spawn_enemy("rusher", Vector2(400, 350))
	rusher.action_timer = 0.0
	rushing.step(STEP, Vector2.ZERO)
	painter.rebuild(rushing.enemies)
	_check(rusher.mode == 1 and rusher.action_timer == CombatSim.RUSHER_WINDUP and painter.get_stats()["charge_count"] == 1, "A real rusher enters its named windup and produces a charge warning")
	var timer_before: float = rusher.action_timer
	var geometry_before: Array = _geometry(painter)
	for frame: int in 5:
		painter.rebuild(rushing.enemies)
	_check(rusher.action_timer == timer_before and _geometry(painter) == geometry_before, "Rebuilding while simulation time is stopped never advances a warning timer")
	for frame: int in 20:
		rushing.step(STEP, Vector2.ZERO)
	painter.rebuild(rushing.enemies)
	_check(rusher.mode == 1 and Painter.windup_progress(rusher.action_timer, CombatSim.RUSHER_WINDUP) > 0.5 and _geometry(painter) != geometry_before, "Real rusher windup advances its visual stage")
	for frame: int in 30:
		if rusher.mode != 1:
			break
		rushing.step(STEP, Vector2.ZERO)
	painter.rebuild(rushing.enemies)
	_check(rusher.mode == 2 and painter.get_stats()["charge_count"] == 0, "A real charge clears the prior windup arrow")
	var casting: CombatSim = _simulation()
	var caster: CombatSim.Enemy = casting.spawn_enemy("caster", Vector2(400, 350))
	caster.action_timer = CombatSim.CASTER_WINDUP + STEP * 1.5
	casting.step(STEP, Vector2.ZERO)
	painter.rebuild(casting.enemies)
	_check(caster.mode == 0 and painter.get_stats()["cast_count"] == 0, "Caster has no warning before the actual windup threshold")
	casting.step(STEP, Vector2.ZERO)
	painter.rebuild(casting.enemies)
	_check(caster.mode == 1 and caster.action_timer <= CombatSim.CASTER_WINDUP and painter.get_stats()["cast_count"] == 1, "The real caster threshold starts its casting ring")
	var start_segments: int = int(painter.get_stats()["segments"])
	for frame: int in 12:
		casting.step(STEP, Vector2.ZERO)
	painter.rebuild(casting.enemies)
	_check(caster.mode == 1 and int(painter.get_stats()["segments"]) > start_segments, "The casting ring closes progressively as the real timer expires")
	for frame: int in 30:
		if caster.mode != 1:
			break
		casting.step(STEP, Vector2.ZERO)
	painter.rebuild(casting.enemies)
	_check(caster.mode == 0 and casting.shot_count == 1 and painter.get_stats()["cast_count"] == 0, "Actual projectile emission removes the caster windup ring")
	var dying: CombatSim.Enemy = rushing.spawn_enemy("rusher", Vector2(600, 350))
	dying.mode = 1
	dying.action_timer = CombatSim.RUSHER_WINDUP * 0.5
	painter.rebuild(rushing.enemies)
	_check(painter.get_stats()["charge_count"] == 1, "A living winding-up enemy is visible before death")
	rushing.apply_damage(dying, dying.health, "bone")
	painter.rebuild(rushing.enemies)
	_check(painter.get_stats()["charge_count"] == 0, "Real enemy death clears its warning in the next rebuild")

func _test_direction_and_local_caster_geometry() -> void:
	var painter := Painter.new()
	var sim: CombatSim = _simulation()
	var rusher: CombatSim.Enemy = sim.spawn_enemy("rusher", Vector2(500, 350))
	rusher.mode = 1
	rusher.action_timer = CombatSim.RUSHER_WINDUP * 0.5
	rusher.charge_direction = Vector2.RIGHT
	painter.rebuild(sim.enemies)
	var before: Array = _geometry(painter)
	sim.player_position = Vector2(100, 550)
	painter.rebuild(sim.enemies)
	_check(_geometry(painter) == before, "A charge arrow follows the stored direction rather than a moving player")
	rusher.charge_direction = Vector2.LEFT
	painter.rebuild(sim.enemies)
	_check(_geometry(painter) != before and painter.get_stats()["neutral_charge_count"] == 0, "A defined opposite charge direction reverses the arrow geometry")
	var caster: CombatSim.Enemy = _enemy("caster")
	caster.action_timer = 0.0
	painter.rebuild([caster])
	before = _geometry(painter)
	caster.charge_direction = Vector2(1000, -300)
	painter.rebuild([caster])
	_check(_geometry(painter) == before, "Casting rings do not imply a stored aim direction")
	var center: Vector2 = caster.position + Vector2(0, -14)
	var local_only: bool = true
	for multimesh: MultiMesh in _caster_multimeshes(painter):
		var vertices: PackedVector2Array = _mesh_vertices(multimesh.mesh)
		for index: int in multimesh.visible_instance_count:
			var transform: Transform2D = multimesh.get_instance_transform_2d(index)
			local_only = local_only and transform.origin.is_equal_approx(center)
			for vertex: Vector2 in vertices:
				local_only = local_only and (transform * vertex).distance_to(center) <= 28.251
	_check(_all_caster_meshes_local(painter) and painter.get_stats()["segments"] == 36, "Shared caster meshes stay local and finite, including outline, without an aiming ray")
	_renderer_check(local_only and painter.get_stats()["segments"] == 36, "Caster instances transform only to their local ring center and contain no aiming ray")
	for batch: RefCounted in painter.batches:
		_check(batch.points.is_empty(), "Caster geometry never enters the rusher arrow line batches")

func _test_arena_bounds() -> void:
	var painter := Painter.new()
	var bounds: Rect2 = CombatSim.ARENA
	var positions: Array[Vector2] = [bounds.position, bounds.end, Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.position.x, 365), Vector2(bounds.end.x, 365), Vector2(640, bounds.position.y), Vector2(640, bounds.end.y)]
	for position: Vector2 in positions:
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1, -1).normalized(), Vector2(1, 1).normalized()]:
			var enemy: CombatSim.Enemy = _enemy("rusher", 1, position)
			enemy.charge_direction = direction
			painter.rebuild([enemy])
			_check(_all_points_safe(painter), "Charge vertices stay inside every edge and corner for inward/outward directions")
		var caster: CombatSim.Enemy = _enemy("caster", 1, position)
		caster.action_timer = 0.0
		painter.rebuild([caster])
		_renderer_check(_all_points_safe(painter), "A complete casting ring and its ticks stay inside arena edges")

func _batch_ids(painter: RefCounted) -> Array[int]:
	var result: Array[int] = []
	for batch: RefCounted in painter.batches:
		result.append(batch.get_instance_id())
	for multimesh: MultiMesh in _caster_multimeshes(painter):
		result.append(multimesh.get_instance_id())
		result.append(multimesh.mesh.get_instance_id() if multimesh.mesh != null else -1)
	return result

func _test_budget_and_reuse() -> void:
	var painter := Painter.new()
	var batch_ids: Array[int] = _batch_ids(painter)
	var casters: Array[CombatSim.Enemy] = []
	for index: int in CombatSim.ENEMY_LIMIT + 1:
		var caster: CombatSim.Enemy = _enemy("caster")
		caster.action_timer = 0.0
		casters.append(caster)
	painter.rebuild(casters)
	var stats: Dictionary = painter.get_stats()
	_check(stats["cast_count"] == CombatSim.ENEMY_LIMIT and stats["segments"] == CombatSim.ENEMY_LIMIT * 36, "Even an oversized input caps full caster rings at 340 times 36 segments")
	_check(painter.batches.size() == 3 and painter.caster_arcs.size() == 17 and stats["draw_commands"] <= 24, "Three arrow batches and shared caster meshes remain within the draw-command budget")
	_check(painter.caster_base.instance_count == 340 and painter.caster_ticks.instance_count == 340 and stats["allocated_instances"] == 1020 and stats["visible_instances"] == 1020, "Full caster population uses 340 base, 340 tick and at most 340 arc instances")
	_check(painter.caster_arcs[0].mesh == null and painter.caster_arcs[0].instance_count == 0 and painter.caster_arcs[0].visible_instance_count == 0, "Zero-progress arc is represented by no geometry or instances")
	_check(_all_caster_meshes_local(painter) and _batch_ids(painter) == batch_ids, "Worst-case meshes stay finite and reuse the original batch objects")
	_renderer_check(_all_points_safe(painter), "Every full-population caster mesh instance remains inside the arena")
	painter.clear()
	stats = painter.get_stats()
	_check(stats["allocated_instances"] == 1020 and stats["visible_instances"] == 0 and stats["draw_commands"] == 0 and _batch_ids(painter) == batch_ids, "Clear hides all instances while preserving capacity, meshes and batch objects")
	var mixed: Array[CombatSim.Enemy] = []
	for remaining: float in [CombatSim.RUSHER_WINDUP, CombatSim.RUSHER_WINDUP * 0.5, 0.0]:
		var enemy: CombatSim.Enemy = _enemy("rusher")
		enemy.action_timer = remaining
		mixed.append(enemy)
	for steps: int in 17:
		var caster: CombatSim.Enemy = _enemy("caster")
		var progress: float = 1.0 if steps == 16 else (float(steps) + 0.5) / 16.0
		caster.action_timer = CombatSim.CASTER_WINDUP * (1.0 - progress)
		mixed.append(caster)
	painter.rebuild(mixed)
	stats = painter.get_stats()
	_check(stats["charge_count"] == 3 and stats["cast_count"] == 17 and stats["draw_commands"] == 24, "All progress steps and arrow stages reach the bounded 24-command maximum")
	_check(stats["allocated_instances"] <= 1020 and stats["visible_instances"] == 50, "Mixed progress shares 34 base/tick instances and 16 arc instances")
	var all_arc_steps: bool = true
	for steps: int in range(1, 17):
		all_arc_steps = all_arc_steps and painter.caster_arcs[steps].instance_count == 1 and painter.caster_arcs[steps].visible_instance_count == 1
	_check(all_arc_steps, "Each nonempty floor(progress times 16) arc group uses one shared instance")
	var start_color: Color = painter.caster_ticks.get_instance_color(0)
	var middle_color: Color = painter.caster_ticks.get_instance_color(8)
	var end_color: Color = painter.caster_ticks.get_instance_color(16)
	_renderer_check(start_color.a < middle_color.a and middle_color.a < end_color.a and _colors_near(start_color, Color(Painter.CORAL, 0.50)) and _colors_near(middle_color, Color(Painter.CORAL, 0.74)) and _colors_near(end_color, Color(Painter.CORAL, 0.98)), "Progress brightness uses the configured per-instance colors within half-precision tolerance")
	_renderer_check(_colors_near(painter.caster_arcs[8].get_instance_color(0), middle_color), "Arc and tick instance colors agree within half-precision tolerance")
	var almost_done: CombatSim.Enemy = _enemy("caster")
	almost_done.action_timer = CombatSim.CASTER_WINDUP * 0.001
	painter.rebuild([almost_done])
	_check(painter.get_stats()["segments"] == 35 and painter.caster_arcs[15].visible_instance_count == 1 and painter.caster_arcs[16].visible_instance_count == 0, "A nearly complete real timer never draws a premature full ring")
	var empty: Array[CombatSim.Enemy] = []
	painter.rebuild(empty)
	stats = painter.get_stats()
	_check(stats["segments"] == 0 and stats["active_batches"] == 0 and stats["draw_commands"] == 0 and stats["charge_count"] == 0 and stats["cast_count"] == 0 and stats["neutral_charge_count"] == 0, "An empty frame clears every stale vertex and counter")
	_check(stats["allocated_instances"] == 680 and stats["visible_instances"] == 0 and _batch_ids(painter) == batch_ids, "An empty rebuild shrinks arc capacity while retaining the 680 base/tick slots and all objects")
	for cycle: int in 3:
		painter.rebuild(mixed)
		painter.clear()
	_check(painter.get_stats()["segments"] == 0 and _batch_ids(painter) == batch_ids, "Repeated explicit clears never recreate batches or retain geometry")

func _entity_snapshot(enemies: Array[CombatSim.Enemy]) -> Array:
	var result: Array = []
	for enemy: CombatSim.Enemy in enemies:
		result.append([enemy.active, enemy.slot, enemy.uid, enemy.definition, enemy.position, enemy.velocity, enemy.health, enemy.max_health, enemy.age, enemy.action_timer, enemy.slow_timer, enemy.slow_factor, enemy.hurt_timer, enemy.charge_direction, enemy.mode, enemy.radius])
	return result

func _test_read_only() -> void:
	var sim: CombatSim = _simulation()
	var rusher: CombatSim.Enemy = sim.spawn_enemy("rusher", Vector2(500, 350))
	var caster: CombatSim.Enemy = sim.spawn_enemy("caster", Vector2(700, 350))
	rusher.mode = 1
	rusher.action_timer = CombatSim.RUSHER_WINDUP * 0.5
	caster.mode = 1
	caster.action_timer = CombatSim.CASTER_WINDUP * 0.5
	var painter := Painter.new()
	var before: Array = _entity_snapshot(sim.enemies)
	var summary: Dictionary = sim.run.summary()
	var rng_before: int = sim.rng.state
	var run_rng_before: int = sim.run.rng.state
	var elapsed_before: float = sim.elapsed
	for frame: int in 3:
		painter.rebuild(sim.enemies)
		painter.get_stats()
		painter.clear()
	_check(_entity_snapshot(sim.enemies) == before, "Warning generation never mutates any enemy field or definition reference")
	_check(sim.run.summary() == summary and sim.rng.state == rng_before and sim.run.rng.state == run_rng_before and sim.elapsed == elapsed_before, "Warning rebuilding and clearing leave run state, both RNGs and simulation time unchanged")
