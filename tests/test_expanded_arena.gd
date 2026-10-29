extends SceneTree
## Expanded world coordinates, shared camera geometry and moving encounter pressure.

const STEP: float = 1.0 / 60.0
const OLD_ARENA: Rect2 = Rect2(66, 140, 1148, 450)
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_world_and_camera()
	_test_authored_terrain()
	_test_spawns()
	_test_travel_and_projectiles()
	_test_distant_pool_and_boss()
	print("ExpandedArena: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _sim(arena: String = "reliquary") -> CombatSim:
	var state := RunState.new()
	state.begin(20261028, "bone", arena)
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim

func _points() -> Array[Vector2]:
	var bounds: Rect2 = CombatSim.ARENA
	var center: Vector2 = bounds.get_center()
	return [center, bounds.position, bounds.end, Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end.x, bounds.position.y),
		Vector2(bounds.position.x, center.y), Vector2(bounds.end.x, center.y), Vector2(center.x, bounds.position.y), Vector2(center.x, bounds.end.y),
		Vector2(-680, -180), Vector2(1990, 960)]

func _inclusive_contains(bounds: Rect2, point: Vector2) -> bool:
	return point.is_finite() and point.x >= bounds.position.x and point.x <= bounds.end.x and point.y >= bounds.position.y and point.y <= bounds.end.y

func _test_world_and_camera() -> void:
	_check(CombatSim.ARENA == ArenaCatalog.WORLD_BOUNDS and CombatSim.ARENA.size == Vector2(3444, 1800), "All combat systems share the expanded playable bounds")
	_check(CombatSim.ARENA.get_center() == OLD_ARENA.get_center() and _sim().player_position == Vector2(640, 365), "Expansion preserves the existing central spawn coordinates")
	_check(CombatSim.ARENA.get_area() == OLD_ARENA.get_area() * 12.0, "The authored playable area is twelve times the original arena")
	_check(ArenaCatalog.art_rect() == Rect2(-1146, -679, 3780, 2104), "The shared art rectangle reserves asymmetric world-edge room for the HUD and minimap")
	for point: Vector2 in _points():
		var visible: Rect2 = ArenaCatalog.visible_rect(point)
		_check(visible.size == Vector2(1280, 720) and ArenaCatalog.art_rect().encloses(visible), "The camera exposes one full reference viewport inside the artwork")
		_check(_inclusive_contains(visible, point), "The camera keeps the player visible even at world corners")
		_check(visible.get_center().is_equal_approx(ArenaCatalog.camera_center(point)), "Camera and spawn geometry use the same visible center")
	var playable: Rect2 = CombatSim.ARENA.grow(-16.0)
	for point: Vector2 in [playable.position, playable.end, Vector2(playable.position.x, playable.end.y), Vector2(playable.end.x, playable.position.y)]:
		var screen_position: Vector2 = point - ArenaCatalog.visible_rect(point).position
		_check(screen_position.x >= 80.0 and screen_position.x <= 992.0 and screen_position.y >= 160.0 and screen_position.y <= 544.0, "The actual clamped player remains clear of HUD panels and the minimap at every corner")
	_check(ArenaCatalog.visible_rect(Vector2.INF) == ArenaCatalog.visible_rect(CombatSim.ARENA.get_center()), "Invalid presentation coordinates safely use the central view")
	_check(ArenaCatalog.visible_rect(Vector2.ZERO, Vector2.INF).size == ArenaCatalog.MAX_VIEW_SIZE and ArenaCatalog.visible_rect(Vector2.ZERO, Vector2(4096, 2160)).size == ArenaCatalog.MAX_VIEW_SIZE, "Invalid and oversized logical view sizes remain within the supported camera envelope")
	_check(ArenaCatalog.visible_rect(Vector2.ZERO, Vector2(960, 540)).size == Vector2(960, 540), "Smaller logical views retain valid centered bounds")
	for id: String in ArenaCatalog.IDS:
		_check(ArenaCatalog.texture_path(id) == "res://assets/worldflipper/maps/%s.png" % id, "The expanded source-art texture preserves the selected map identity: " + id)
	_check(ArenaCatalog.texture_path("unknown") == ArenaCatalog.texture_path("reliquary"), "Unknown map art follows the same catalog fallback")

func _test_authored_terrain() -> void:
	for id: String in ArenaCatalog.IDS:
		var definition: Dictionary = ArenaCatalog.definition(id)
		var zones: Array = definition["zones"]
		var legacy_count: int = int(definition["legacy_zone_count"])
		_check(legacy_count == (0 if id == "reliquary" else 4 if id == "ashland" else 3), "Legacy art regions remain explicitly identified: " + id)
		_check(zones.size() == legacy_count + (0 if id == "reliquary" else 8), "Each terrain map adds eight distant authored patches: " + id)
		_check(ArenaCatalog.movement_multiplier(id, CombatSim.ARENA.get_center()) == 1.0, "The unchanged central spawn stays on clear ground: " + id)
		var valid_bounds: bool = true
		var disjoint: bool = true
		for index: int in zones.size():
			var zone: Dictionary = zones[index]
			var center := Vector2(float(zone["center"][0]), float(zone["center"][1]))
			var radius := Vector2(float(zone["radius"][0]), float(zone["radius"][1]))
			var patch := Rect2(center - radius, radius * 2.0)
			valid_bounds = valid_bounds and radius.x > 0.0 and radius.y > 0.0 and CombatSim.ARENA.encloses(patch)
			_check(ArenaCatalog.movement_multiplier(id, center) == float(definition["move_multiplier"]), "Remote and original terrain centers use the same actual slowdown: " + id)
			if index >= legacy_count:
				_check(not OLD_ARENA.has_point(center), "The added terrain actually extends beyond the original room: " + id)
			for previous: int in index:
				var other: Dictionary = zones[previous]
				var other_center := Vector2(float(other["center"][0]), float(other["center"][1]))
				var other_radius := Vector2(float(other["radius"][0]), float(other["radius"][1]))
				disjoint = disjoint and not patch.intersects(Rect2(other_center - other_radius, other_radius * 2.0))
		_check(valid_bounds and disjoint, "Complete terrain patches stay inside the world and preserve clear corridors: " + id)

func _test_spawns() -> void:
	for point: Vector2 in _points():
		var first: CombatSim = _sim()
		var second: CombatSim = _sim()
		first.player_position = point
		second.player_position = point
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.seed = first.rng.seed
		expected_rng.state = first.rng.state
		var view: Rect2 = ArenaCatalog.visible_rect(point)
		var hidden: bool = true
		var safe: bool = true
		var nearby: bool = true
		var deterministic: bool = true
		for sample: int in 180:
			var position: Vector2 = first._edge_position()
			hidden = hidden and not view.grow(24.0).has_point(position)
			safe = safe and _inclusive_contains(CombatSim.ARENA.grow(-CombatSim.SPAWN_INSET), position) and position.distance_squared_to(point) >= 180.0 * 180.0
			nearby = nearby and position.distance_squared_to(point) < 1700.0 * 1700.0
			deterministic = deterministic and position == second._edge_position()
			expected_rng.randf()
			expected_rng.randf()
		_check(hidden and safe, "Center, side and corner encounters always spawn safely outside the actual camera")
		_check(nearby, "Encounter pressure follows the player rather than distant world edges")
		_check(deterministic and first.rng.state == second.rng.state and first.rng.state == expected_rng.state, "Every spawn uses two deterministic random draws without unbounded retries")
		var enemy: CombatSim.Enemy = first.spawn_enemy("tank")
		_check(enemy != null and not view.has_point(enemy.position), "The actual enemy factory consumes the same hidden spawn geometry")

func _test_travel_and_projectiles() -> void:
	for fixture: Dictionary in [{"origin": Vector2(66, 365), "move": Vector2.LEFT}, {"origin": Vector2(1214, 365), "move": Vector2.RIGHT}, {"origin": Vector2(640, 140), "move": Vector2.UP}, {"origin": Vector2(640, 590), "move": Vector2.DOWN}]:
		var sim: CombatSim = _sim()
		sim.player_position = fixture["origin"]
		sim.step(0.25, fixture["move"])
		_check(not OLD_ARENA.has_point(sim.player_position) and CombatSim.ARENA.has_point(sim.player_position), "Normal movement traverses each former arena wall")
	for corner: Vector2 in [CombatSim.ARENA.position, CombatSim.ARENA.end]:
		var sim: CombatSim = _sim()
		sim.player_position = corner
		sim.step(STEP, (corner - CombatSim.ARENA.get_center()).normalized(), true)
		_check(_inclusive_contains(CombatSim.ARENA.grow(-16.0), sim.player_position), "Dash and ordinary movement clamp to the expanded playable edge")
	var sim: CombatSim = _sim()
	sim.player_position = Vector2(-700, 800)
	var target: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + Vector2(90, 0))
	target.definition = target.definition.duplicate() as ContentDef
	target.definition.speed = 0.0
	target.action_timer = 9999.0
	target.health = 1000.0
	sim.fire_weapon("bone", "", target.position - Vector2(40, 0), Vector2.RIGHT)
	for frame: int in 12:
		sim.step(STEP, Vector2.ZERO)
	_check(target.health < 1000.0 and sim.primary_hits == 1, "Real projectiles and collision remain active in negative remote world coordinates")
	_check(CombatSim.clamp_point(Vector2.INF).is_finite(), "World clamping never returns an infinite point")

func _test_distant_pool_and_boss() -> void:
	var sim: CombatSim = _sim()
	sim.player_position = CombatSim.ARENA.end - Vector2(50, 50)
	var point: Vector2 = CombatSim.ARENA.position + Vector2(50, 50)
	var ordinary: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
	var old_uid: int = ordinary.uid
	var hunter: CombatSim.Enemy = sim.spawn_enemy("rusher", point + Vector2(30, 0))
	hunter.hunter = true
	var boss: CombatSim.Enemy = sim.spawn_enemy("boss", point + Vector2(60, 0))
	for enemy: CombatSim.Enemy in [ordinary, hunter, boss]:
		enemy.action_timer = 9999.0
	var before: Array = [sim.run.kills, sim.run.gold, sim.run.xp, sim.soul_count, sim.effects.size(), sim.rng.state]
	var free_slots: int = sim._enemy_free.size()
	sim._update_enemies(STEP)
	_check(not ordinary.active and hunter.active and boss.active and sim.enemy_count == 2, "Remote ordinary enemies recycle while the hunter and boss remain tracked")
	_check(before == [sim.run.kills, sim.run.gold, sim.run.xp, sim.soul_count, sim.effects.size(), sim.rng.state], "Distance recycling grants no kill, currency, XP, drop, effect or random draw")
	_check(sim._enemy_free.size() == free_slots + 1, "Distance recycling returns exactly one slot to the fixed pool")
	sim._update_enemies(STEP)
	_check(sim._enemy_free.size() == free_slots + 1, "A retired enemy cannot be returned to the pool twice")
	var replacement: CombatSim.Enemy = sim.spawn_enemy("chaser", sim.player_position + Vector2(-100, 0))
	_check(replacement == ordinary and replacement.uid > old_uid and replacement.active and sim.enemy_count == 3, "A recycled slot receives a fresh live UID near the player")
	sim = _sim()
	sim.player_position = Vector2(1900, 1000)
	boss = sim.spawn_enemy("boss", Vector2(1600, 1000))
	boss.action_timer = 9999.0
	var origin: Vector2 = boss.position
	sim._update_enemies(1.0)
	_check(boss.position.x > origin.x and boss.position.distance_to(origin) <= boss.definition.speed + 0.001, "Boss patrol follows the remote player's region without changing its movement speed")
