extends SceneTree
## Fixed-step movement and real attack paths verify the active dash independently of rendering.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_ordinary_movement()
	_test_distance_and_direction()
	_test_cooldown()
	_test_terrain_and_partial_step()
	_test_boundaries()
	_test_contact_and_existing_protection()
	_test_projectile_and_ritual()
	_test_invalid_and_lifecycle()
	print("DashRules: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
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

func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.003

func _zone_center(arena: String) -> Vector2:
	if (ArenaCatalog.definition(arena)["zones"] as Array).is_empty():
		return ArenaCatalog.play_bounds(arena).get_center()
	var zone: Dictionary = ArenaCatalog.definition(arena)["zones"][0]
	return Vector2(float(zone["center"][0]), float(zone["center"][1]))

func _still_enemy(sim: CombatSim) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", sim.player_position + Vector2(8, 0))
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _hostile(sim: CombatSim, offset: float, speed: float) -> CombatSim.Shot:
	sim._hostile_shot(sim.player_position + Vector2(offset, 0), Vector2(speed, 0), 8.0, "caster")
	for shot: CombatSim.Shot in sim.shots:
		if shot.active and shot.hostile:
			return shot
	return null

func _ritual(sim: CombatSim) -> CombatSim.WarningZone:
	var zone := CombatSim.WarningZone.new()
	zone.position = sim.player_position
	zone.radius = 24.0
	zone.delay = STEP * 0.5
	zone.damage = 16.0
	sim.zones.append(zone)
	return zone

func _test_ordinary_movement() -> void:
	for arena: String in ArenaCatalog.IDS:
		var sim: CombatSim = _sim(arena)
		sim.player_position = _zone_center(arena)
		var point: Vector2 = sim.player_position
		var velocity: Vector2 = Vector2(1, 1).limit_length() * sim.run.stat("move_speed") * ArenaCatalog.movement_multiplier(arena, point)
		sim.step(STEP, Vector2(1, 1))
		_check(_near(sim.player_position, CombatSim.clamp_point(point + velocity * STEP, 16.0)) and _near(sim.player_velocity, velocity), "Two-argument calls retain ordinary ground movement: " + arena)
		_check(sim.dashes_used == 0 and sim.dash_time_left == 0.0 and sim.dash_cooldown_left == 0.0 and sim.dash_invulnerability_left == 0.0, "Ordinary movement never starts or charges the skill")
		var implicit: CombatSim = _sim(arena)
		var explicit: CombatSim = _sim(arena)
		for frame: int in 30:
			var direction := Vector2(cos(float(frame) * 0.2), sin(float(frame) * 0.2))
			implicit.step(STEP, direction)
			explicit.step(STEP, direction, false)
		_check(implicit.player_position == explicit.player_position and implicit.player_velocity == explicit.player_velocity and implicit.rng.state == explicit.rng.state and implicit.run.rng.state == explicit.run.rng.state, "The optional input preserves exact old-call compatibility: " + arena)

func _test_distance_and_direction() -> void:
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2(-1, -1)]:
		var sim: CombatSim = _sim()
		var origin: Vector2 = sim.player_position
		var rng_before: int = sim.rng.state
		var activations: Array[Vector2] = []
		sim.dash_started.connect(func(point: Vector2, heading: Vector2) -> void:
			activations.append(point)
			activations.append(heading))
		sim.step(STEP, direction, true)
		_check(sim.dashes_used == 1 and activations.size() == 2 and activations[0] == origin and activations[1].is_equal_approx(direction.normalized()), "A successful activation emits exactly its origin and normalized heading")
		_check(_near(sim.player_velocity, direction.normalized() * 660.0) and is_equal_approx(sim.dash_time_left, 0.2 - STEP) and is_equal_approx(sim.dash_cooldown_left, 2.4 - STEP), "The first physical step consumes movement and cooldown time immediately")
		for frame: int in 11:
			sim.step(STEP, direction.rotated(PI * 0.5))
		_check(_near(sim.player_position, origin + direction.normalized() * 132.0), "Horizontal and diagonal bursts travel the same independent distance")
		_check(sim.dash_time_left == 0.0 and sim.dash_direction.is_equal_approx(direction.normalized()) and not sim.dash_snapshot()["active"], "Direction stays locked through all twelve steps without a floating-point extra frame")
		_check(sim.rng.state == rng_before and sim.run.health == 100.0 and sim.damage_by_weapon.is_empty(), "Dash alone consumes no RNG, health, rewards or offensive damage")
	var facing: CombatSim = _sim()
	facing.player_direction = Vector2.UP
	var origin: Vector2 = facing.player_position
	facing.step(STEP, Vector2.ZERO, true)
	_check(facing.dash_direction == Vector2.UP and _near(facing.player_position, origin + Vector2(0, -11)), "No movement input uses the existing facing direction")
	for heading: Vector2 in [Vector2.ZERO, Vector2.INF]:
		facing = _sim()
		facing.player_direction = heading
		facing.step(STEP, Vector2.ZERO, true)
		_check(facing.dash_direction == Vector2.RIGHT and facing.player_position.is_finite(), "A missing or invalid facing falls back to a finite rightward burst")
	facing = _sim()
	facing.player_direction = Vector2.LEFT
	facing.step(STEP, Vector2.DOWN, true)
	_check(facing.dash_direction == Vector2.DOWN, "Current movement takes priority over a different old facing")

func _test_cooldown() -> void:
	var sim: CombatSim = _sim()
	sim.step(STEP, Vector2.RIGHT, true)
	for frame: int in range(1, 143):
		sim.step(STEP, Vector2.ZERO, true)
	_check(sim.dashes_used == 1 and is_equal_approx(sim.dash_cooldown_left, STEP), "Repeated cooldown inputs never restart or extend a burst")
	sim.step(STEP, Vector2.ZERO, true)
	_check(sim.dashes_used == 1 and sim.dash_snapshot()["ready"] and sim.dash_cooldown_left == 0.0, "A press made before the last cooldown step is discarded even when that step reaches readiness")
	sim.step(STEP, Vector2.ZERO)
	_check(sim.dashes_used == 1 and sim.dash_time_left == 0.0, "Readiness does not replay a discarded input")
	sim.step(STEP, Vector2.LEFT, true)
	_check(sim.dashes_used == 2 and sim.dash_time_left > 0.0 and sim.dash_direction == Vector2.LEFT, "A fresh post-cooldown press can activate in a new direction")
	var snapshot: Dictionary = sim.dash_snapshot()
	snapshot["cooldown_left"] = 999.0
	_check(sim.dash_snapshot()["cooldown_left"] < 2.4 and sim.snapshot()["dash"] == sim.dash_snapshot(), "Snapshot queries expose copies of actual skill state")

func _test_terrain_and_partial_step() -> void:
	for arena: String in ArenaCatalog.IDS:
		var sim: CombatSim = _sim(arena)
		sim.player_position = _zone_center(arena)
		var origin: Vector2 = sim.player_position
		sim.run.gold = 1000
		sim.run.offers = [{"kind": "relic", "id": "speed", "price": 20, "sold": false}]
		_check(sim.run.buy_offer(0) and sim.run.stat("move_speed") > 220.0, "The speed-independence fixture uses a real relic purchase")
		sim.step(STEP, Vector2.RIGHT, true)
		_check(_near(sim.player_velocity, Vector2(660, 0)) and _near(sim.player_position, origin + Vector2(11, 0)), "Burst speed ignores movement relics and the selected ground: " + arena)
		sim = _sim(arena)
		origin = _zone_center(arena)
		sim.player_position = origin
		var after_dash: Vector2 = CombatSim.clamp_point(origin + Vector2(132, 0), 16.0)
		var normal_speed: float = 220.0 * ArenaCatalog.movement_multiplier(arena, after_dash)
		var expected: Vector2 = CombatSim.clamp_point(after_dash + Vector2(normal_speed * 0.1, 0), 16.0)
		sim.step(0.3, Vector2.RIGHT, true)
		_check(_near(sim.player_position, expected) and is_equal_approx(sim.player_velocity.length(), normal_speed), "An oversized step uses exact burst time, then current-position ground for its normal remainder: " + arena)
		_check(sim.dash_time_left == 0.0 and sim.dash_invulnerability_left == 0.0 and is_equal_approx(sim.dash_cooldown_left, 2.1), "All skill clocks use the same elapsed physical time")
	for leaves_patch: bool in [false, true]:
		var sim: CombatSim = _sim("mire")
		sim.player_position = Vector2(370, 275) if leaves_patch else Vector2(140, 275)
		var after_dash: Vector2 = sim.player_position + Vector2(132, 0)
		var speed: float = 220.0 * ArenaCatalog.movement_multiplier("mire", after_dash)
		sim.step(0.3, Vector2.RIGHT, true)
		_check(_near(sim.player_position, after_dash + Vector2(speed * 0.1, 0)) and is_equal_approx(sim.player_velocity.length(), 220.0 if leaves_patch else 158.4), "A partial final step samples the landing surface when entering or leaving mud")

func _test_boundaries() -> void:
	var bounds: Rect2 = CombatSim.ARENA.grow(-16.0)
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1, 1)]:
		var sim: CombatSim = _sim()
		sim.player_position = Vector2(bounds.end.x - 1, bounds.end.y - 1) if direction.x >= 0.0 and direction.y >= 0.0 else bounds.position + Vector2.ONE
		var expected: Vector2 = CombatSim.clamp_point(sim.player_position + direction.normalized() * 132.0, 16.0)
		sim.step(0.2, direction, true)
		_check(_near(sim.player_position, expected) and sim.player_position == CombatSim.clamp_point(sim.player_position, 16.0), "Dash respects the same player-center arena inset in every direction")
		_check(sim.dashes_used == 1 and sim.dash_time_left == 0.0, "A boundary truncates displacement without extending the active timer")

func _test_contact_and_existing_protection() -> void:
	var sim: CombatSim = _sim()
	sim.step(STEP, Vector2.RIGHT, true)
	var enemy: CombatSim.Enemy = _still_enemy(sim)
	var position_before: Vector2 = enemy.position
	sim._update_enemies(STEP)
	_check(sim.run.health == 100.0 and enemy.position == position_before and sim.invulnerability == 0.0, "Dash immunity blocks both contact damage and contact recoil without granting hit immunity")
	for frame: int in 7:
		sim.step(STEP, Vector2.ZERO)
	_check(sim.dash_time_left > 0.0 and sim.dash_invulnerability_left == 0.0, "The short shield expires before the movement burst finishes")
	enemy.position = sim.player_position + Vector2(8, 0)
	position_before = enemy.position
	sim._update_enemies(STEP)
	_check(sim.run.health < 100.0 and enemy.position != position_before and is_equal_approx(sim.invulnerability, 0.7), "The vulnerable tail of a dash can receive ordinary contact damage and recoil")
	sim = _sim()
	sim.invulnerability = 0.5
	sim.step(STEP, Vector2.RIGHT, true)
	_check(is_equal_approx(sim.invulnerability, 0.5 - STEP) and is_equal_approx(sim.dash_invulnerability_left, 0.12 - STEP), "Activation keeps existing hit protection and dash protection on independent clocks")
	sim.step(0.2, Vector2.ZERO)
	sim._hurt_player(10.0, "tank", "contact")
	_check(sim.run.health == 100.0 and sim.invulnerability > 0.0 and sim.dash_invulnerability_left == 0.0, "Dash expiry never shortens the original received-hit protection")

func _test_projectile_and_ritual() -> void:
	var sim: CombatSim = _sim()
	sim.step(STEP, Vector2.RIGHT, true)
	var shot: CombatSim.Shot = _hostile(sim, -50.0, 1200.0)
	for frame: int in 6:
		if not shot.active:
			break
		sim.step(STEP, Vector2.ZERO)
	_check(not shot.active and sim.run.health == 100.0 and sim.invulnerability == 0.0, "A real hostile projectile crossing the short shield causes no damage")
	sim.step(0.2, Vector2.ZERO)
	shot = _hostile(sim, -25.0, 1500.0)
	sim.step(STEP, Vector2.ZERO)
	_check(not shot.active and sim.run.health == 92.0 and sim.run.last_hit["kind"] == "projectile", "Actual projectile damage returns after the shield expires")
	sim = _sim()
	sim.step(STEP, Vector2.RIGHT, true)
	var zone: CombatSim.WarningZone = _ritual(sim)
	sim.step(STEP, Vector2.ZERO)
	_check(zone.triggered and sim.run.health == 100.0 and sim.invulnerability == 0.0, "An actual ritual detonation respects the same short shield")
	sim.step(0.2, Vector2.ZERO)
	zone = _ritual(sim)
	sim.step(STEP, Vector2.ZERO)
	_check(zone.triggered and sim.run.health == 84.0 and sim.run.last_hit["kind"] == "ritual", "Ritual damage resumes once the independent shield has elapsed")

func _test_invalid_and_lifecycle() -> void:
	for delta: float in [0.0, -0.01, INF, NAN]:
		var sim: CombatSim = _sim()
		sim._move_player(delta, Vector2.RIGHT, true)
		_check(sim.dashes_used == 0 and sim.dash_time_left == 0.0 and sim.dash_cooldown_left == 0.0 and sim.dash_invulnerability_left == 0.0, "Invalid or nonpositive time cannot activate the skill")
	var sim: CombatSim = _sim()
	sim.step(0.0, Vector2.RIGHT, true)
	_check(sim.dashes_used == 0, "A zero-time production step does not consume the input as an activation")
	sim = _sim()
	var unchanged_dash: Dictionary = sim.dash_snapshot()
	sim._try_start_dash(Vector2.INF)
	_check(sim.dash_snapshot() == unchanged_dash and sim.dash_invulnerability_left == 0.0, "Nonfinite directional input leaves skill state unchanged")
	sim = _sim()
	sim.run.health = 0.0
	sim.step(STEP, Vector2.RIGHT, true)
	_check(sim.dashes_used == 0 and not sim.dash_snapshot()["ready"], "A dead player cannot activate")
	sim = _sim()
	sim.step(STEP, Vector2.RIGHT, true)
	sim._finish(false, "fixture terminal")
	var before: Array = [sim.dash_snapshot(), sim.dash_invulnerability_left, sim.player_position, sim.elapsed, sim.rng.state, sim.run.rng.state]
	sim.step(0.5, Vector2.LEFT, true)
	_check(before == [sim.dash_snapshot(), sim.dash_invulnerability_left, sim.player_position, sim.elapsed, sim.rng.state, sim.run.rng.state], "Terminal steps neither activate nor advance skill clocks or movement")
	sim = _sim()
	sim.step(STEP, Vector2.LEFT, true)
	var state := RunState.new()
	state.begin(20261029, "ember", "glacier")
	sim.begin(state)
	_check(sim.dash_time_left == 0.0 and sim.dash_cooldown_left == 0.0 and sim.dash_invulnerability_left == 0.0 and sim.dashes_used == 0 and sim.dash_direction == Vector2.RIGHT and sim.dash_snapshot()["ready"], "Beginning a wave resets all transient skill state")
