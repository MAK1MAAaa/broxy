extends SceneTree
## Bounded contact geometry, conservative culling and exact simulation-state purity.

const PAINTER = preload("res://scripts/combat/grounding_painter.gd")
var _checks: int = 0
var _failures: int = 0

class DrawProbe extends Node2D:
	var painter: GroundingPainter
	var drew: bool = false
	func _draw() -> void:
		painter.draw(self)
		drew = true

func _initialize() -> void:
	_test.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _sim() -> CombatSim:
	var state := RunState.new()
	state.begin(20261029, "bone", "mire")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	return sim

func _test() -> void:
	_test_empty_and_mesh()
	_test_contacts_and_culling()
	_test_capacity_and_reuse()
	await _test_purity_and_draw()
	print("GroundingPainter: %d assertions, %d failures; native=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)

func _test_empty_and_mesh() -> void:
	var painter: GroundingPainter = PAINTER.new()
	_check(painter.get_stats() == {"active_count": 0, "player_count": 0, "enemy_count": 0, "pickup_count": 0, "capacity": CombatSim.ENEMY_LIMIT + CombatSim.DROP_LIMIT + 1, "draw_commands": 0}, "Construction allocates the combined actor/drop capacity without visible contacts")
	_check(painter is RefCounted and painter.shadows.instance_count == PAINTER.CAPACITY and painter.shadows.mesh.get_surface_count() == 1, "A shared node-less mesh and one fixed instance buffer own every shadow")
	var arrays: Array = painter.shadows.mesh.surface_get_arrays(0)
	var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check(vertices.size() == 18 and colors.size() == vertices.size() and arrays[Mesh.ARRAY_TEX_UV] == null, "Three baked horizontal bands use eighteen vertices without texture dependencies")
	var envelope: bool = true
	var edge_vertices: int = 0
	var center_vertices: int = 0
	for index: int in vertices.size():
		envelope = envelope and vertices[index].is_finite() and absf(vertices[index].x) <= 1.0 and absf(vertices[index].y) <= 1.0
		envelope = envelope and colors[index].r == 1.0 and colors[index].g == 1.0 and colors[index].b == 1.0
		if absf(colors[index].a - 0.08) <= 1.0 / 255.0:
			edge_vertices += 1
		elif absf(colors[index].a - 0.16) <= 1.0 / 255.0:
			center_vertices += 1
	_check(envelope and edge_vertices == 12 and center_vertices == 6, "Stepped contact edges remain faint around one darker middle band")
	painter.rebuild(null, Rect2(0, 0, 1280, 720))
	_check(painter.geometry_snapshot().is_empty() and painter.shadows.visible_instance_count == 0, "An absent simulation leaves no stale geometry")
	var sim: CombatSim = _sim()
	for view: Rect2 in [Rect2(), Rect2(0, 0, -1, 720), Rect2(Vector2.INF, Vector2.ONE), Rect2(0, 0, NAN, 720)]:
		painter.rebuild(sim, view)
		_check(painter.get_stats()["active_count"] == 0 and painter.get_stats()["draw_commands"] == 0, "Invalid view geometry clears prepared instances")

func _test_contacts_and_culling() -> void:
	var sim: CombatSim = _sim()
	var painter: GroundingPainter = PAINTER.new()
	sim.player_position = Vector2(-400, -100)
	var tank: CombatSim.Enemy = sim.spawn_enemy("tank", Vector2(-330, -90))
	var boss: CombatSim.Enemy = sim.spawn_enemy("boss", Vector2(-250, -70))
	sim._drop_soul(Vector2(-360, -110), 1)
	sim._drop_soul(Vector2(-350, -80), 5)
	var view := Rect2(-600, -300, 1280, 720)
	painter.rebuild(sim, view)
	_check(painter.get_stats()["player_count"] == 1 and painter.get_stats()["enemy_count"] == 2 and painter.get_stats()["pickup_count"] == 2 and painter.get_stats()["draw_commands"] == 1, "One shared command carries the real player, two enemy types and both pickup values")
	var geometry: Array[Dictionary] = painter.geometry_snapshot()
	_check(geometry[0]["kind"] == PAINTER.PLAYER and geometry[0]["position"] == sim.player_position + Vector2(0, 12) and geometry[0]["radius"] == Vector2(18, 4), "The player receives its fixed foot contact in world coordinates")
	var tank_contact: Dictionary = _entry(geometry, PAINTER.ENEMY, tank.uid)
	var boss_contact: Dictionary = _entry(geometry, PAINTER.ENEMY, boss.uid)
	_check(tank_contact["position"].is_equal_approx(tank.position + Vector2(0, (tank.radius * 3.0 + 15.0) * 0.25)) and is_equal_approx(tank_contact["radius"].x, clampf(tank.radius * 0.95, 10.0, 36.0)), "An enemy footprint follows its authored ground anchor and bounded width")
	_check(boss_contact["radius"].x <= 36.0 and boss_contact["radius"].y < tank_contact["radius"].y, "The large boss has a wide, restrained ground contact rather than a large filled collision ring")
	var drops: Array[Dictionary] = []
	for entry: Dictionary in geometry:
		if entry["kind"] == PAINTER.PICKUP:
			drops.append(entry)
	_check(drops.size() == 2 and drops[0]["radius"].x < drops[1]["radius"].x and drops[0]["color"].a < drops[1]["color"].a, "Higher-value pickups receive a distinct but still subdued fixed base")
	var before: Array[Dictionary] = painter.geometry_snapshot()
	tank.age += 10.0
	tank.hurt_timer = 0.1
	tank.slow_timer = 4.0
	for soul: CombatSim.Soul in sim.souls:
		if soul.active:
			soul.age += 10.0
	painter.rebuild(sim, view)
	_check(painter.geometry_snapshot() == before, "Bobbing age, hit compression and status tint do not move or flash ground contacts")
	geometry[0]["position"] = Vector2.ZERO
	_check(painter.geometry_snapshot()[0]["position"] != Vector2.ZERO, "Fixture snapshots are detached from the prepared rendering data")
	tank.position = Vector2.INF
	boss.radius = NAN
	for soul: CombatSim.Soul in sim.souls:
		if soul.active:
			soul.position = Vector2(NAN, 0)
	sim.player_position = Vector2.INF
	painter.rebuild(sim, view)
	_check(painter.get_stats()["active_count"] == 0, "Nonfinite actor/drop positions and radii never reach the shared GPU buffer")
	sim = _sim()
	sim.player_position = Vector2(2000, 1000)
	var edge: CombatSim.Enemy = sim.spawn_enemy("tank", Vector2(-1050, -500))
	var nearby := Rect2(-1000, -550, 200, 200)
	painter.rebuild(sim, nearby)
	_check(painter.get_stats()["enemy_count"] == 1 and painter.get_stats()["player_count"] == 0, "The presentation margin retains nearby contacts beyond the visible rectangle, including negative coordinates")
	edge.position.x = nearby.position.x - PAINTER.CULL_MARGIN - 1.0
	painter.rebuild(sim, nearby)
	_check(painter.get_stats()["active_count"] == 0, "Beyond the ninety-six-pixel padding no off-screen contact is prepared")

func _entry(geometry: Array[Dictionary], kind: int, id: int) -> Dictionary:
	for entry: Dictionary in geometry:
		if entry["kind"] == kind and entry["id"] == id:
			return entry
	return {}

func _test_capacity_and_reuse() -> void:
	var sim: CombatSim = _sim()
	for index: int in CombatSim.ENEMY_LIMIT:
		sim.spawn_enemy("chaser", Vector2(300 + index % 20, 300 + index / 20))
	for index: int in CombatSim.DROP_LIMIT:
		sim._drop_soul(Vector2(450 + index % 20, 350 + index / 20), 1 if index % 2 == 0 else 3)
	var painter: GroundingPainter = PAINTER.new()
	var multimesh_id: int = painter.shadows.get_instance_id()
	var mesh_id: int = painter.shadows.mesh.get_instance_id()
	for repeat: int in 5:
		painter.rebuild(sim, Rect2(0, 0, 1280, 720))
		var stats: Dictionary = painter.get_stats()
		_check(stats["active_count"] == PAINTER.CAPACITY and stats["enemy_count"] == CombatSim.ENEMY_LIMIT and stats["pickup_count"] == CombatSim.DROP_LIMIT and painter.shadows.visible_instance_count == PAINTER.CAPACITY, "A full population fits its fixed actor and drop budget")
		_check(stats["draw_commands"] == 1 and painter.shadows.get_instance_id() == multimesh_id and painter.shadows.mesh.get_instance_id() == mesh_id and painter.shadows.instance_count == PAINTER.CAPACITY, "Dense rebuilds reuse their exact mesh/buffer and stay at one rendering command")
	for enemy: CombatSim.Enemy in sim.enemies:
		enemy.active = false
	for soul: CombatSim.Soul in sim.souls:
		soul.active = false
	sim.player_position = Vector2.INF
	painter.rebuild(sim, Rect2(0, 0, 1280, 720))
	_check(painter.get_stats()["active_count"] == 0 and painter.shadows.visible_instance_count == 0, "Rebuilding an empty population hides every previously occupied instance")
	painter.clear()
	_check(painter.get_stats()["draw_commands"] == 0 and painter.geometry_snapshot().is_empty() and painter.shadows.instance_count == PAINTER.CAPACITY, "Clearing retains allocation while removing all visible and fixture geometry")

func _state(sim: CombatSim) -> String:
	var enemies: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		enemies.append([enemy.active, enemy.uid, enemy.position, enemy.velocity, enemy.health, enemy.age, enemy.hurt_timer, enemy.slow_timer, enemy.action_timer])
	var souls: Array = []
	for soul: CombatSim.Soul in sim.souls:
		souls.append([soul.active, soul.position, soul.value, soul.age])
	return JSON.stringify([sim.snapshot(), sim.run.summary(), sim.player_position, sim.player_velocity, sim.player_direction,
		str(sim.rng.state), str(sim.run.rng.state), sim.enemy_count, sim.soul_count, enemies, souls])

func _test_purity_and_draw() -> void:
	var sim: CombatSim = _sim()
	sim.spawn_enemy("caster", Vector2(700, 400))
	sim._drop_soul(Vector2(600, 400), 5)
	var painter: GroundingPainter = PAINTER.new()
	var before: String = _state(sim)
	for repeat: int in 5:
		painter.rebuild(sim, ArenaCatalog.visible_rect(sim.player_position))
	_check(_state(sim) == before, "Repeated grounding projections preserve all combat/economy state and both random streams")
	var probe := DrawProbe.new()
	probe.painter = painter
	root.add_child(probe)
	probe.queue_redraw()
	for frame: int in 4:
		await process_frame
	_check(probe.drew and _state(sim) == before and painter.get_stats()["draw_commands"] == 1, "An actual CanvasItem draw executes the one shadow command without advancing the simulation")
	probe.queue_free()
	for frame: int in 3:
		await process_frame
