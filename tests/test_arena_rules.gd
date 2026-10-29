extends SceneTree
## Authored ground changes movement only; the default arena remains deterministic.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_catalog()
	_test_compiled_terrain()
	_test_state_lifecycle()
	_test_player_ground()
	_test_enemy_ground()
	_test_projectiles_and_timers()
	_test_default_determinism()
	print("ArenaRules: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _state(arena: String = "reliquary") -> RunState:
	var state := RunState.new()
	state.begin(20261026, "bone", arena)
	return state


func _sim(arena: String = "reliquary") -> CombatSim:
	var sim := CombatSim.new()
	sim.begin(_state(arena))
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim


func _center(zone: Dictionary) -> Vector2:
	return Vector2(float(zone["center"][0]), float(zone["center"][1]))


func _radius(zone: Dictionary) -> Vector2:
	return Vector2(float(zone["radius"][0]), float(zone["radius"][1]))


func _test_catalog() -> void:
	_check(ArenaCatalog.IDS.size() == 4 and ArenaCatalog.normalize_id("unknown") == "reliquary", "The catalog exposes exactly four maps with a safe default")
	_check(ArenaCatalog.WORLD_BOUNDS == Rect2(-1082, -535, 3444, 1800) and ArenaCatalog.ART_MARGIN_TOP == 232.0 and ArenaCatalog.art_rect() == Rect2(-1146, -767, 3780, 2192), "The larger top artwork margin preserves the exact playable-world geometry")
	_check(ArenaCatalog.visible_rect(ArenaCatalog.WORLD_BOUNDS.get_center()).position - ArenaCatalog.art_rect().position == Vector2(1146, 772), "The unchanged central camera maps to the exact new artwork preview crop")
	var total_zones: int = 0
	var points: Array[Vector2] = [Vector2.ZERO, CombatSim.ARENA.get_center(), Vector2.INF]
	for point: Vector2 in points:
		_check(ArenaCatalog.movement_multiplier("reliquary", point) == 1.0 and ArenaCatalog.movement_multiplier("unknown", point) == 1.0, "The default/unknown map never applies terrain")
	for id: String in ArenaCatalog.IDS:
		var definition: Dictionary = ArenaCatalog.definition(id)
		_check(definition["id"] == id and not str(definition["name"]).is_empty() and not str(definition["texture"]).is_empty(), "Every map has an identity, label and visual resource: " + id)
		_check(ArenaCatalog.movement_multiplier(id, CombatSim.ARENA.get_center()) == 1.0 and ArenaCatalog.terrain_name(id, CombatSim.ARENA.get_center()).is_empty(), "Each map leaves the actual player spawn on ordinary ground: " + id)
		_check(ArenaCatalog.movement_multiplier(id, Vector2.INF) == 1.0, "Nonfinite coordinates never activate terrain: " + id)
		var zones: Array = definition["zones"]
		total_zones += zones.size()
		_check(zones.is_empty() if id == "reliquary" else zones.size() >= int(definition["legacy_zone_count"]) + 6, "Expanded maps preserve the original patches and add distant terrain: " + id)
		for zone: Dictionary in zones:
			var center: Vector2 = _center(zone)
			var radius: Vector2 = _radius(zone)
			var bounds := Rect2(center - radius, radius * 2.0)
			_check(radius.x > 0.0 and radius.y > 0.0 and CombatSim.ARENA.encloses(bounds), "The complete ground patch stays within the combat boundary: " + id)
			_check(is_equal_approx(ArenaCatalog.movement_multiplier(id, center), float(definition["move_multiplier"])) and ArenaCatalog.terrain_name(id, center) == definition["terrain_name"], "Center coordinates use the authored terrain rule and name: " + id)
			_check(is_equal_approx(ArenaCatalog.movement_multiplier(id, center + Vector2(radius.x, 0)), float(definition["move_multiplier"])), "The rendered ellipse edge belongs to the ground patch: " + id)
			_check(ArenaCatalog.movement_multiplier(id, center + Vector2(radius.x + 0.1, 0)) == 1.0, "Movement immediately recovers beyond the ellipse edge: " + id)
			for other: Dictionary in zones:
				if zone == other:
					continue
				# Their axis-aligned envelopes are disjoint, a stronger condition than
				# non-intersecting ellipses and a guaranteed ordinary-ground corridor.
				_check(not bounds.intersects(Rect2(_center(other) - _radius(other), _radius(other) * 2.0)), "Ground patches leave separate traversable corridors: " + id)
		definition["name"] = "mutated"
		(definition["zones"] as Array).clear()
		_check(ArenaCatalog.definition(id)["name"] != "mutated" and (id == "reliquary" or not (ArenaCatalog.definition(id)["zones"] as Array).is_empty()), "Catalog copies cannot mutate combat data: " + id)
	_check(total_zones == 34, "Expanded artwork preserves all thirty-four authored terrain patches")


func _test_state_lifecycle() -> void:
	var default_state: RunState = _state()
	for id: String in ArenaCatalog.IDS:
		var state: RunState = _state(id)
		_check(state.arena_id == id and state.summary()["arena_id"] == id, "Run state records the chosen map: " + id)
		_check(state.rng.state == default_state.rng.state and state.loadout == default_state.loadout, "Choosing a map consumes no random values or starting equipment: " + id)
		state.finish_wave()
		state.generate_shop()
		state.next_wave()
		_check(state.arena_id == id, "Shop settlement and the next wave retain the chosen map: " + id)
		state.begin(5, "ember")
		_check(state.arena_id == "reliquary" and state.wave == 1 and state.core_id.is_empty(), "A new default run resets map and run-specific progression: " + id)
	var invalid: RunState = _state("not-a-map")
	_check(invalid.arena_id == "reliquary", "Invalid map input safely selects the original arena")
	var unknown: Dictionary = ArenaCatalog.definition("not-a-map")
	_check(unknown["id"] == "reliquary", "Visual and simulation fallbacks agree on the same map")

func _terrain_oracle(arena: Dictionary, point: Vector2) -> bool:
	for zone: Dictionary in arena["zones"]:
		var x: float = (point.x - float(zone["center"][0])) / float(zone["radius"][0])
		var y: float = (point.y - float(zone["center"][1])) / float(zone["radius"][1])
		if x * x + y * y <= 1.0:
			return true
	return false

func _compare_terrain(arena: Dictionary, point: Vector2) -> void:
	var inside: bool = _terrain_oracle(arena, point)
	var expected: float = float(arena["move_multiplier"]) if inside else 1.0
	var name: String = str(arena["terrain_name"]) if inside else ""
	_check(ArenaCatalog.movement_multiplier(str(arena["id"]), point) == expected and ArenaCatalog.terrain_name(str(arena["id"]), point) == name, "Compiled terrain exactly matches original dictionary division at centers, ellipse edges, cell edges and distant points")

func _test_compiled_terrain() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 1283400
	var zones: int = 0
	for id: String in ArenaCatalog.IDS:
		var arena: Dictionary = ArenaCatalog.definition(id)
		var cache: ArenaCatalog.TerrainIndex = ArenaCatalog._terrain_indices[id]
		zones += cache.centers_x.size()
		_check(cache.centers_x.size() == (arena["zones"] as Array).size() and cache.empty_ids.is_empty(), "Terrain compilation preserves every authored ellipse and a separate immutable empty bucket")
		for zone: Dictionary in arena["zones"]:
			var center: Vector2 = _center(zone)
			var radius: Vector2 = _radius(zone)
			_compare_terrain(arena, center)
			for angle_index: int in 24:
				var angle: float = TAU * float(angle_index) / 24.0
				for factor: float in [0.999999, 1.0, 1.000001]:
					_compare_terrain(arena, center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * factor)
			for offset: Vector2 in [Vector2(radius.x, 0), Vector2(-radius.x, 0), Vector2(0, radius.y), Vector2(0, -radius.y)]:
				_compare_terrain(arena, center + offset)
				_compare_terrain(arena, center + offset + offset.normalized() * 0.0001)
		for sample: int in 300:
			_compare_terrain(arena, Vector2(random.randf_range(-1500.0, 2800.0), random.randf_range(-900.0, 1600.0)))
		for point: Vector2 in [Vector2(1.0e30, -1.0e30), Vector2(-1.0e30, 1.0e30)]:
			_compare_terrain(arena, point)
		for x: float in [-1024.0, -512.0, -128.0, 0.0, 128.0, 512.0, 1024.0, 2304.0]:
			for y: float in [-512.0, -128.0, 0.0, 128.0, 512.0, 1024.0]:
				for epsilon: float in [-0.0001, 0.0, 0.0001]:
					_compare_terrain(arena, Vector2(x + epsilon, y + epsilon))
		var unchanged: Dictionary = ArenaCatalog.definition(id)
		arena["move_multiplier"] = 999.0
		(arena["zones"] as Array).clear()
		_compare_terrain(unchanged, Vector2(310, 275))
	_check(zones == 34, "The exact terrain index compiles all thirty-four ellipses without reducing gameplay coverage")
	for point: Vector2 in [Vector2.INF, Vector2(NAN, 1.0)]:
		for id: String in ArenaCatalog.IDS:
			_check(ArenaCatalog.movement_multiplier(id, point) == 1.0 and ArenaCatalog.terrain_name(id, point).is_empty(), "Invalid positions never enter terrain index arithmetic")
	_check(ArenaCatalog.movement_multiplier("unknown", Vector2(310, 275)) == 1.0 and ArenaCatalog.terrain_name("unknown", Vector2(310, 275)).is_empty(), "Unknown maps retain their original neutral terrain fallback")


func _test_player_ground() -> void:
	for id: String in ["mire", "glacier", "ashland"]:
		var definition: Dictionary = ArenaCatalog.definition(id)
		var zone: Dictionary = definition["zones"][0]
		var center: Vector2 = _center(zone)
		var factor: float = float(definition["move_multiplier"])
		var sim: CombatSim = _sim(id)
		sim.player_position = center
		var before_rng: int = sim.rng.state
		sim.step(STEP, Vector2.RIGHT)
		_check(is_equal_approx(sim.player_velocity.length(), sim.run.stat("move_speed") * factor), "Player movement uses the current surface multiplier: " + id)
		_check(is_equal_approx(sim.player_position.distance_to(center), sim.run.stat("move_speed") * factor * STEP), "Actual displacement reflects terrain without changing the movement stat: " + id)
		_check(is_equal_approx(sim.run.stat("move_speed"), 220.0) and sim.run.health == 100.0 and sim.rng.state == before_rng, "Terrain changes no damage, permanent stats or simulation RNG: " + id)
		sim.player_position = CombatSim.ARENA.get_center()
		sim.step(STEP, Vector2(1, 1))
		_check(is_equal_approx(sim.player_velocity.length(), 220.0), "Leaving a patch restores normalized diagonal speed: " + id)
		sim.player_position = center + Vector2(_radius(zone).x - 0.2, 0)
		sim.step(STEP, Vector2.RIGHT)
		sim.step(STEP, Vector2.RIGHT)
		_check(is_equal_approx(sim.player_velocity.length(), 220.0), "Crossing a patch edge recovers normal movement on the next fixed step: " + id)


func _test_enemy_ground() -> void:
	for id: String in ["mire", "glacier", "ashland"]:
		var definition: Dictionary = ArenaCatalog.definition(id)
		var point: Vector2 = _center(definition["zones"][0])
		var factor: float = float(definition["move_multiplier"])
		for enemy_id: String in ["chaser", "tank", "caster", "rusher", "boss"]:
			var sim: CombatSim = _sim(id)
			sim.player_position = Vector2(1180, 570)
			var enemy: CombatSim.Enemy = sim.spawn_enemy(enemy_id, point)
			enemy.action_timer = 999.0
			var old_position: Vector2 = enemy.position
			sim._update_enemies(STEP)
			var expected_speed: float = enemy.definition.speed * factor
			_check(absf(enemy.position.distance_to(old_position) - expected_speed * STEP) < 0.001, "Ground slows actual movement for " + id + "/" + enemy_id)
			if enemy_id == "rusher":
				enemy.position = point
				enemy.mode = 2
				enemy.charge_direction = Vector2.RIGHT
				enemy.slow_timer = 5.0
				enemy.slow_factor = 0.5
				enemy.hunter = true
				sim._update_enemies(STEP)
				_check(is_equal_approx(enemy.velocity.length(), 330.0 * factor * 0.5 * RogueRules.HUNTER_SPEED_FACTOR), "Chargers compose terrain, frost slow and hunter speed once: " + id)
			if enemy_id == "boss":
				enemy.position = point
				enemy.slow_timer = 5.0
				enemy.slow_factor = 0.5
				sim._update_enemies(STEP)
				_check(absf(enemy.position.distance_to(point) - expected_speed * 0.5 * STEP) < 0.001, "Boss movement composes frost and ground once: " + id)


func _test_projectiles_and_timers() -> void:
	for id: String in ArenaCatalog.IDS:
		var sim: CombatSim = _sim(id)
		var point := Vector2(310, 275)
		if id != "reliquary":
			point = _center(ArenaCatalog.definition(id)["zones"][0])
		sim.player_position = Vector2(1180, 570)
		sim.fire_weapon("bone", "", point, Vector2.RIGHT)
		sim._hostile_shot(point, Vector2(145, 0), 10.0, "caster")
		var original: Array[Dictionary] = []
		for shot: CombatSim.Shot in sim.shots:
			if shot.active:
				original.append({"slot": shot.slot, "position": shot.position, "velocity": shot.velocity, "damage": shot.damage})
		sim.step(STEP, Vector2.ZERO)
		for entry: Dictionary in original:
			var shot: CombatSim.Shot = sim.shots[int(entry["slot"])]
			_check(shot.active and shot.velocity == entry["velocity"] and shot.damage == entry["damage"], "Ground leaves friendly/hostile projectile speed and damage intact: " + id)
			_check(shot.position.is_equal_approx((entry["position"] as Vector2) + (entry["velocity"] as Vector2) * STEP), "Projectiles cross ground without movement damping: " + id)
		sim = _sim(id)
		sim.sandbox = false
		sim._spawn_timer = 9999.0
		sim.elapsed = sim.duration - STEP * 0.5
		sim.step(STEP, Vector2.ZERO)
		_check(sim.complete and sim.victory, "Every ordinary map still settles the wave as soon as its timer expires: " + id)
		sim = CombatSim.new()
		var state: RunState = _state(id)
		state.wave = 8
		sim.begin(state)
		sim._cooldowns.fill(9999.0)
		sim._spawn_timer = 9999.0
		sim.elapsed = sim.duration - STEP * 0.5
		sim.step(STEP, Vector2.ZERO)
		_check(sim.complete and not sim.victory and sim.boss.active, "Every map retains Boss timeout failure: " + id)


func _test_default_determinism() -> void:
	var first := CombatSim.new()
	var second := CombatSim.new()
	var a := RunState.new()
	var b := RunState.new()
	a.begin(20261026, "bone")
	b.begin(20261026, "bone", "reliquary")
	first.begin(a)
	second.begin(b)
	for frame: int in 180:
		var movement := Vector2(sin(float(frame) * 0.03), cos(float(frame) * 0.03))
		first.step(STEP, movement)
		second.step(STEP, movement)
	_check(a.summary() == b.summary() and first.player_position == second.player_position, "Legacy two-argument startup and explicit original map produce the same run and motion")
	_check(first.rng.state == second.rng.state and first.enemy_count == second.enemy_count and first.shot_count == second.shot_count, "The default arena keeps simulation RNG, spawns and attacks identical")
