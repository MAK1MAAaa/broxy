extends SceneTree
## Real fixed-step control, independent status clocks and unchanged damage paths.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_constants_and_ordinary_targets()
	_test_radius_and_eligibility()
	_test_coincident_and_boundaries()
	_test_enemy_actions_and_immunity()
	_test_independent_slows()
	_test_frostfire_and_priority()
	_test_dual_skills_and_cooldown()
	_test_hazards_and_invariants()
	_test_legacy_calls()
	_test_invalid_and_lifecycle()
	print("PulseRules: %d assertions, %d failures" % [_checks, _failures])
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

func _enemy(sim: CombatSim, id: String, point: Vector2, speed: float = 0.0) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = speed
	enemy.action_timer = 9999.0
	return enemy

func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.003

func _terrain_center(arena: String) -> Vector2:
	if arena == "reliquary":
		return CombatSim.ARENA.get_center()
	var zone: Dictionary = ArenaCatalog.definition(arena)["zones"][0]
	return Vector2(float(zone["center"][0]), float(zone["center"][1]))

func _events(sim: CombatSim) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	sim.pulse_cast.connect(func(origin: Vector2, affected: int) -> void:
		events.append({"origin": origin, "affected": affected}))
	return events

func _economy_and_damage(sim: CombatSim) -> Array:
	return [sim.run.health, sim.run.gold, sim.run.xp, sim.run.kills,
		sim.run.damage_taken, sim.run.hits_taken, sim.run.last_hit.duplicate(true),
		sim.run.damage_dealt_by_weapon.duplicate(true), sim.damage_by_weapon.duplicate(true),
		sim.primary_hits, sim.secondary_hits, sim.rng.state, sim.run.rng.state,
		sim.invulnerability, sim.dash_invulnerability_left, sim.core_activations.duplicate(true)]

func _test_constants_and_ordinary_targets() -> void:
	_check(PulseRules.RADIUS == 144.0 and PulseRules.PUSH_DISTANCE == 70.0 and PulseRules.HINDER_FACTOR == 0.65 and PulseRules.HINDER_SECONDS == 1.0 and PulseRules.COOLDOWN == 8.0, "Pulse uses its published fixed control parameters")
	for arena: String in ArenaCatalog.IDS:
		for id: String in ["chaser", "tank", "rusher", "caster"]:
			var sim: CombatSim = _sim(arena)
			sim.player_position = _terrain_center(arena)
			var origin: Vector2 = sim.player_position
			var enemy: CombatSim.Enemy = _enemy(sim, id, origin + Vector2(144, 0))
			var events: Array[Dictionary] = _events(sim)
			sim.step(STEP, Vector2.ZERO, false, true)
			_check(_near(enemy.position, origin + Vector2(214, 0)) and is_equal_approx(enemy.pulse_hinder_timer, 1.0 - STEP), "A real step pushes an eligible ordinary target by seventy pixels in " + arena + ": " + id)
			_check(events == [{"origin": origin, "affected": 1}] and sim.pulses_used == 1 and sim.pulse_affected == 1 and sim.last_pulse_affected == 1, "Successful activation reports its real origin and affected count once")
			_check(enemy.slow_timer == 0.0 and enemy.slow_factor == 1.0 and sim.run.health == 100.0 and sim.damage_by_weapon.is_empty(), "Pulse hindrance is separate from frost and does not deal damage")

func _test_radius_and_eligibility() -> void:
	var sim: CombatSim = _sim()
	var origin: Vector2 = sim.player_position
	var inside: CombatSim.Enemy = _enemy(sim, "chaser", origin + Vector2(72, 72))
	var edge: CombatSim.Enemy = _enemy(sim, "tank", origin + Vector2(144, 0))
	var outside: CombatSim.Enemy = _enemy(sim, "tank", origin + Vector2(144.01, 0))
	var inactive: CombatSim.Enemy = _enemy(sim, "chaser", origin + Vector2(90, 0))
	inactive.active = false
	var dead: CombatSim.Enemy = _enemy(sim, "chaser", origin + Vector2(100, 0))
	dead.health = 0.0
	var excluded: Array[Vector2] = [outside.position, inactive.position, dead.position]
	sim._try_cast_pulse()
	_check(sim.last_pulse_affected == 2 and sim.pulse_affected == 2, "The radius includes active living centers at exactly 144 and excludes all other eligibility failures")
	_check(_near(inside.position, origin + Vector2(72, 72) + Vector2(1, 1).normalized() * 70.0) and _near(edge.position, origin + Vector2(214, 0)), "Radial push preserves diagonal direction and the inclusive cardinal edge")
	_check(excluded == [outside.position, inactive.position, dead.position] and outside.pulse_hinder_timer == 0.0 and inactive.pulse_hinder_timer == 0.0 and dead.pulse_hinder_timer == 0.0, "Collision radius, inactive objects and zero-health targets cannot enlarge the pulse query")

func _test_coincident_and_boundaries() -> void:
	for facing: Vector2 in [Vector2.UP, Vector2(-3, 4), Vector2.ZERO, Vector2.INF]:
		var sim: CombatSim = _sim()
		sim.player_direction = facing
		var enemy: CombatSim.Enemy = _enemy(sim, "chaser", sim.player_position)
		var origin: Vector2 = enemy.position
		var heading: Vector2 = facing.normalized() if facing.is_finite() and facing.length_squared() > 0.0 else Vector2.RIGHT
		var rng_before: Array = [sim.rng.state, sim.run.rng.state]
		sim._try_cast_pulse()
		_check(_near(enemy.position, origin + heading * 70.0) and enemy.position.is_finite() and rng_before == [sim.rng.state, sim.run.rng.state], "Coincident centers use normalized facing or the deterministic right fallback without RNG")
	for arena: String in ArenaCatalog.IDS:
		for positive: bool in [false, true]:
			var sim: CombatSim = _sim(arena)
			sim.player_position = Vector2(1194, 570) if positive else Vector2(86, 160)
			var offset: Vector2 = Vector2(10, 10) if positive else Vector2(-10, -10)
			var enemy: CombatSim.Enemy = _enemy(sim, "tank", sim.player_position + offset)
			sim._try_cast_pulse()
			_check(enemy.position == (Vector2(1214, 590) if positive else Vector2(66, 140)) and enemy.pulse_hinder_timer == 1.0 and sim.last_pulse_affected == 1, "Push clamps to the default enemy arena bounds in " + arena)

func _test_enemy_actions_and_immunity() -> void:
	var sim: CombatSim = _sim()
	var rusher: CombatSim.Enemy = _enemy(sim, "rusher", sim.player_position + Vector2(100, 0))
	rusher.mode = 2
	rusher.action_timer = 0.5
	rusher.charge_direction = Vector2.UP
	var origin: Vector2 = rusher.position
	sim.step(STEP, Vector2.ZERO, false, true)
	_check(is_equal_approx(rusher.velocity.length(), 214.5) and _near(rusher.position, origin + Vector2(70, 0) + rusher.velocity * STEP), "Hindrance also slows an already charging rusher without replacing its actual movement")
	_check(rusher.mode == 2 and is_equal_approx(rusher.action_timer, 0.5 - STEP) and rusher.charge_direction == Vector2.UP, "Pulse preserves a rusher's mode, action deadline and locked charge direction")
	sim = _sim()
	rusher = _enemy(sim, "rusher", sim.player_position + Vector2(100, 0))
	rusher.mode = 1
	rusher.action_timer = STEP * 0.5
	rusher.charge_direction = Vector2.LEFT
	sim.step(STEP, Vector2.ZERO, false, true)
	_check(rusher.mode == 2 and rusher.action_timer == 0.6 and rusher.charge_direction == Vector2.LEFT, "A charging windup completes on its original step instead of being interrupted")
	sim = _sim()
	var caster: CombatSim.Enemy = _enemy(sim, "caster", sim.player_position + Vector2(144, 0))
	caster.mode = 1
	caster.action_timer = 0.3
	sim.step(STEP, Vector2.ZERO, false, true)
	_check(caster.mode == 1 and is_equal_approx(caster.action_timer, 0.3 - STEP) and sim.shot_count == 0, "Caster windup remains active at its original deadline after being pushed")
	caster.action_timer = STEP * 0.5
	sim.step(STEP, Vector2.ZERO)
	_check(sim.shot_count == 1 and caster.mode == 0 and caster.action_timer == caster.definition.cooldown, "The real caster still fires while pulse hindrance is active")
	for id: String in ["boss", "rusher"]:
		var control: CombatSim = _sim()
		var affected: CombatSim = _sim()
		var a: CombatSim.Enemy = _enemy(control, id, control.player_position + Vector2(100, 0), 100.0)
		var b: CombatSim.Enemy = _enemy(affected, id, affected.player_position + Vector2(100, 0), 100.0)
		a.hunter = id == "rusher"
		b.hunter = a.hunter
		control.step(STEP, Vector2.ZERO)
		affected.step(STEP, Vector2.ZERO, false, true)
		_check(a.position == b.position and a.velocity == b.velocity and a.mode == b.mode and a.action_timer == b.action_timer and a.charge_direction == b.charge_direction and b.pulse_hinder_timer == 0.0, "Bosses and marked hunters retain exactly their original behavior: " + id)
		_check(affected.pulses_used == 1 and affected.last_pulse_affected == 0 and control.rng.state == affected.rng.state and control.run.rng.state == affected.run.rng.state, "An immune-only pulse still consumes its cooldown without affecting either random stream")

func _test_independent_slows() -> void:
	for frost_factor: float in [0.8, 0.4]:
		var sim: CombatSim = _sim()
		var enemy: CombatSim.Enemy = _enemy(sim, "chaser", sim.player_position + Vector2(100, 0), 100.0)
		sim.apply_damage(enemy, 1.0, "frost", false, 1.0 - frost_factor)
		var original_frost: Array = [enemy.slow_timer, enemy.slow_factor]
		sim._try_cast_pulse()
		_check(original_frost == [enemy.slow_timer, enemy.slow_factor] and enemy.pulse_hinder_timer == 1.0, "Casting pulse neither replaces nor extends real weapon frost status")
		sim._update_enemies(STEP)
		_check(is_equal_approx(enemy.velocity.length(), 100.0 * minf(frost_factor, 0.65)) and is_equal_approx(enemy.slow_timer, 1.5 - STEP), "Overlapping slows select the stronger factor instead of multiplying")
		sim._update_enemies(1.0)
		_check(enemy.pulse_hinder_timer == 0.0 and enemy.slow_timer > 0.0 and is_equal_approx(enemy.slow_factor, frost_factor) and is_equal_approx(enemy.velocity.length(), 100.0 * frost_factor), "Pulse expiry restores the still-active original frost factor")
	var sim: CombatSim = _sim()
	var enemy: CombatSim.Enemy = _enemy(sim, "chaser", sim.player_position + Vector2(100, 0), 100.0)
	enemy.slow_timer = 0.1
	enemy.slow_factor = 0.4
	sim._try_cast_pulse()
	sim._update_enemies(0.15)
	_check(enemy.slow_timer == 0.0 and is_equal_approx(enemy.pulse_hinder_timer, 0.85) and is_equal_approx(enemy.velocity.length(), 65.0), "Frost can expire first while independent pulse hindrance continues")
	sim._update_enemies(0.85)
	_check(enemy.pulse_hinder_timer == 0.0 and is_equal_approx(enemy.velocity.length(), 100.0), "The final partial hindrance interval expires without extending either slow")
	sim = _sim()
	enemy = _enemy(sim, "chaser", sim.player_position + Vector2(100, 0), 100.0)
	sim._try_cast_pulse()
	for frame: int in 59:
		sim._update_enemies(STEP)
	_check(is_equal_approx(enemy.pulse_hinder_timer, STEP) and is_equal_approx(enemy.velocity.length(), 65.0), "The fixed-step hindrance lasts through its penultimate tick")
	sim._update_enemies(STEP)
	_check(enemy.pulse_hinder_timer == 0.0 and is_equal_approx(enemy.velocity.length(), 100.0), "The sixtieth tick leaves no floating-point extra slow frame")

func _test_frostfire_and_priority() -> void:
	var state := RunState.new()
	state.begin(20261028, "ember")
	state.finish_wave()
	_check(state.choose_core("frostfire"), "The core fixture obtains frostfire through its real transaction")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var target: CombatSim.Enemy = _enemy(sim, "chaser", sim.player_position + Vector2(100, 0))
	var neighbor: CombatSim.Enemy = _enemy(sim, "chaser", sim.player_position + Vector2(100, 50))
	target.health = 10000.0
	target.max_health = 10000.0
	neighbor.health = 10000.0
	neighbor.max_health = 10000.0
	sim._try_cast_pulse()
	_check(target.slow_timer == 0.0 and target.slow_factor == 1.0 and target.pulse_hinder_timer == 1.0, "A pulse-only target never acquires the frost classification")
	sim.fire_weapon("ember", "", target.position - Vector2(40, 0), Vector2.RIGHT)
	for frame: int in 6:
		sim.step(STEP, Vector2.ZERO)
	_check(target.health == 10000.0 - GameCatalog.weapon("ember").damage and neighbor.health == 10000.0 and sim.core_activations["frostfire"] == 0, "A real ember hit on a pulse-only target does not activate frostfire or secondary splash")
	sim = _sim()
	target = _enemy(sim, "chaser", sim.player_position + Vector2(50, 0))
	var frosted: CombatSim.Enemy = _enemy(sim, "chaser", sim.player_position + Vector2(130, 0))
	frosted.slow_timer = 1.5
	frosted.slow_factor = 0.75
	sim._try_cast_pulse()
	_check(sim._weapon_target(sim.player_position, 420.0, true, false) == frosted and target.slow_timer == 0.0, "Existing slow-priority targeting selects frost over a nearer pulse-only target")

func _test_dual_skills_and_cooldown() -> void:
	var sim: CombatSim = _sim()
	sim.player_direction = Vector2.UP
	var origin: Vector2 = sim.player_position
	var left: CombatSim.Enemy = _enemy(sim, "chaser", origin - Vector2(144, 0))
	var right: CombatSim.Enemy = _enemy(sim, "chaser", origin + Vector2(150, 0))
	var coincident: CombatSim.Enemy = _enemy(sim, "chaser", origin)
	var order: Array[String] = []
	var events: Array[Dictionary] = _events(sim)
	sim.pulse_cast.connect(func(_point: Vector2, _affected: int) -> void: order.append("pulse"))
	sim.dash_started.connect(func(_point: Vector2, _direction: Vector2) -> void: order.append("dash"))
	sim.step(STEP, Vector2.RIGHT, true, true)
	_check(order == ["pulse", "dash"] and events == [{"origin": origin, "affected": 2}], "Simultaneous skills cast pulse at the step-start position before dash moves")
	_check(_near(left.position, origin - Vector2(214, 0)) and right.position == origin + Vector2(150, 0) and coincident.position == origin + Vector2(0, -70), "The pre-dash radius and facing decide eligible and coincident push directions")
	_check(_near(sim.player_position, origin + Vector2(11, 0)) and sim.dash_direction == Vector2.RIGHT and is_equal_approx(sim.pulse_cooldown_left, 8.0 - STEP) and is_equal_approx(sim.dash_cooldown_left, 2.4 - STEP), "Both independent skills consume their original physical time in the same step")
	sim = _sim()
	events = _events(sim)
	sim.step(STEP, Vector2.ZERO, false, true)
	_check(sim.pulses_used == 1 and sim.pulse_affected == 0 and sim.last_pulse_affected == 0 and events.size() == 1, "An empty cast still emits once and pays its full cooldown")
	for frame: int in range(1, 479):
		sim.step(STEP, Vector2.ZERO, false, true)
	_check(sim.pulses_used == 1 and is_equal_approx(sim.pulse_cooldown_left, STEP), "Repeated cooldown input never recasts, extends or queues the skill")
	sim.step(STEP, Vector2.ZERO, false, true)
	_check(sim.pulses_used == 1 and sim.pulse_snapshot()["ready"] and sim.pulse_cooldown_left == 0.0, "A request in the final cooldown tick is dropped before that tick reaches readiness")
	sim.step(STEP, Vector2.ZERO)
	_check(sim.pulses_used == 1, "Cooldown expiry cannot replay an earlier rejected pulse request")
	sim.step(STEP, Vector2.ZERO, false, true)
	_check(sim.pulses_used == 2 and events.size() == 2 and sim.pulse_affected == 0, "A fresh post-cooldown request can cast another empty pulse")
	var snapshot: Dictionary = sim.pulse_snapshot()
	snapshot["cooldown_left"] = 999.0
	_check(sim.pulse_snapshot()["cooldown_left"] < 8.0 and sim.snapshot()["pulse"] == sim.pulse_snapshot() and sim.pulse_snapshot()["radius"] == 144.0, "Snapshots expose copies of the actual pulse rules and state")

func _test_hazards_and_invariants() -> void:
	var sim: CombatSim = _sim()
	var enemy: CombatSim.Enemy = _enemy(sim, "chaser", sim.player_position + Vector2(80, 0))
	var before: Array = _economy_and_damage(sim)
	var enemy_health: float = enemy.health
	sim._try_cast_pulse()
	_check(before == _economy_and_damage(sim) and enemy.health == enemy_health and sim.effects.is_empty(), "Casting changes neither RNG, health, damage, rewards, protection nor simulation effects")
	sim = _sim()
	sim._hostile_shot(sim.player_position, Vector2.ZERO, 8.0, "caster")
	sim._hostile_shot(sim.player_position + Vector2(0, -100), Vector2.ZERO, 8.0, "caster")
	sim.step(STEP, Vector2.ZERO, false, true)
	_check(sim.run.health == 92.0 and sim.run.hits_taken == 1 and sim.shot_count == 1 and sim.run.last_hit["kind"] == "projectile", "Pulse grants no immunity and does not clear incoming or passing hostile projectiles")
	sim = _sim()
	var zone := CombatSim.WarningZone.new()
	zone.position = sim.player_position
	zone.delay = STEP * 0.5
	sim.zones.append(zone)
	sim.step(STEP, Vector2.ZERO, false, true)
	_check(zone.triggered and sim.run.health == 84.0 and sim.run.last_hit["kind"] == "ritual", "A real ritual still detonates and damages the pulsing player normally")

func _test_legacy_calls() -> void:
	for with_dash: bool in [false, true]:
		var implicit: CombatSim = _sim()
		var explicit: CombatSim = _sim()
		var a: CombatSim.Enemy = _enemy(implicit, "chaser", Vector2(800, 450), 66.0)
		var b: CombatSim.Enemy = _enemy(explicit, "chaser", Vector2(800, 450), 66.0)
		for frame: int in 30:
			var movement := Vector2(cos(float(frame) * 0.2), sin(float(frame) * 0.2))
			if with_dash:
				implicit.step(STEP, movement, frame == 0)
			else:
				implicit.step(STEP, movement)
			explicit.step(STEP, movement, with_dash and frame == 0, false)
		_check(implicit.snapshot() == explicit.snapshot() and implicit.player_position == explicit.player_position and implicit.player_velocity == explicit.player_velocity and a.position == b.position and a.velocity == b.velocity and a.action_timer == b.action_timer and implicit.rng.state == explicit.rng.state and implicit.run.rng.state == explicit.run.rng.state, "Existing two- and three-argument fixed-step calls retain exactly the explicit pulse-disabled behavior")

func _test_invalid_and_lifecycle() -> void:
	for delta: float in [0.0, -0.01, INF, NAN]:
		var sim: CombatSim = _sim()
		var before: Dictionary = sim.pulse_snapshot()
		sim._update_pulse(delta, true)
		_check(sim.pulse_snapshot() == before, "Nonpositive or nonfinite time neither casts nor advances the pulse cooldown")
	var sim: CombatSim = _sim()
	sim.step(0.0, Vector2.ZERO, false, true)
	_check(sim.pulses_used == 0 and sim.pulse_snapshot()["ready"], "The public zero-time step cannot consume a pulse input")
	sim.run.health = 0.0
	sim._try_cast_pulse()
	_check(sim.pulses_used == 0 and not sim.pulse_snapshot()["ready"], "A dead player cannot cast before terminal settlement")
	sim = _sim()
	var enemy: CombatSim.Enemy = _enemy(sim, "chaser", sim.player_position + Vector2(100, 0))
	sim.step(STEP, Vector2.ZERO, false, true)
	sim._finish(false, "terminal pulse fixture")
	var terminal: Array = [sim.pulse_snapshot(), enemy.position, enemy.pulse_hinder_timer, sim.elapsed, sim.rng.state, sim.run.rng.state]
	sim.step(9.0, Vector2.RIGHT, true, true)
	_check(terminal == [sim.pulse_snapshot(), enemy.position, enemy.pulse_hinder_timer, sim.elapsed, sim.rng.state, sim.run.rng.state], "Terminal steps freeze pulse, hindrance, enemies and both random streams")
	sim = _sim()
	enemy = _enemy(sim, "chaser", sim.player_position + Vector2(100, 0))
	sim._try_cast_pulse()
	var slot: int = enemy.slot
	sim.apply_damage(enemy, 1000.0, "bone")
	var replacement: CombatSim.Enemy = sim.spawn_enemy("tank", Vector2(800, 400))
	_check(replacement.slot == slot and replacement.pulse_hinder_timer == 0.0 and replacement.slow_timer == 0.0 and replacement.slow_factor == 1.0, "A real killed-and-respawned pool slot starts without the previous enemy's pulse status")
	replacement.pulse_hinder_timer = 0.5
	var inactive: CombatSim.Enemy = sim.enemies.back()
	inactive.pulse_hinder_timer = 0.25
	var state := RunState.new()
	state.begin(20261029, "ember", "glacier")
	sim.begin(state)
	_check(sim.pulse_cooldown_left == 0.0 and sim.pulses_used == 0 and sim.pulse_affected == 0 and sim.last_pulse_affected == 0 and sim.pulse_snapshot()["ready"] and sim.enemies.all(func(item: CombatSim.Enemy) -> bool: return item.pulse_hinder_timer == 0.0), "Begin resets all pulse counters, cooldown and active or inactive reused enemy status")
