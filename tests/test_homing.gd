extends SceneTree
## Focused fixed-step homing behavior; fixtures never alter the shared definitions.

const DELTA: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_real_volley_retarget()
	_test_antiparallel_weights()
	_test_near_antiparallel_side()
	_test_hit_uid_exclusion()
	_test_unaffected_paths()
	_test_original_curve()
	_test_determinism()
	print("Homing: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _simulation(seed_value: int = 431, state: RunState = null) -> CombatSim:
	if state == null:
		state = RunState.new()
		state.begin(seed_value, "ember")
	var simulation := CombatSim.new()
	simulation.begin(state)
	simulation.sandbox = true
	simulation._cooldowns.fill(9999.0)
	return simulation

func _stationary_caster(simulation: CombatSim, position: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = simulation.spawn_enemy("caster", position)
	enemy.action_timer = 9999.0
	return enemy

func _rng_state(simulation: CombatSim) -> Array[int]:
	return [simulation.rng.state, simulation.run.rng.state]

func _advance(simulation: CombatSim, frames: int) -> void:
	for frame: int in frames:
		simulation.step(DELTA, Vector2.ZERO)

func _test_real_volley_retarget() -> void:
	var state := RunState.new()
	state.begin(431, "ember")
	# Set up a legal four-weapon inventory; this is a fixed combat fixture, not a run.
	state.gold = 54
	for index: int in 3:
		state.offers = [{"id": "bone", "kind": "weapon", "price": state.shop_price(GameCatalog.weapon("bone")), "sold": false}]
		_check(state.buy_offer(0), "Retarget fixture obtains each bone weapon through the normal purchase API")
	var simulation: CombatSim = _simulation(431, state)
	var behind: CombatSim.Enemy = _stationary_caster(simulation, Vector2(440, 365))
	var forward: CombatSim.Enemy = _stationary_caster(simulation, Vector2(820, 365))
	var rng_before: Array[int] = _rng_state(simulation)
	# Synchronize a real automatic volley so the faster bone projectiles finish first.
	simulation._cooldowns.fill(0.0)
	simulation.step(DELTA, Vector2.ZERO)
	simulation._cooldowns.fill(9999.0)
	var ember: CombatSim.Shot = simulation.shots[0]
	_check(ember.active and ember.source == "ember" and simulation.shot_count == 4, "The formal auto-fire path emits one ember and three bone projectiles")
	_check(ember.velocity == Vector2.RIGHT * GameCatalog.weapon("ember").projectile_speed, "The original closer target produces the initial rightward ember heading")
	for frame: int in 40:
		if not forward.active:
			break
		simulation.step(DELTA, Vector2.ZERO)
	_check(not forward.active and simulation.primary_hits == 3 and simulation.damage_by_weapon == {"bone": forward.max_health}, "Three real bone collisions finish the former target before ember arrives")
	_check(ember.active and behind.active and ember.position.distance_to(behind.position) < 420.0, "The unhit reverse target remains inside the actual homing radius after the finisher")
	var heading_before: Vector2 = ember.velocity.normalized()
	simulation.step(DELTA, Vector2.ZERO)
	_check(ember.velocity.normalized().dot(heading_before) < 0.99999, "Ember changes heading when a real finisher leaves the selected target directly behind")
	_check(ember.position.is_finite() and is_equal_approx(ember.velocity.length(), GameCatalog.weapon("ember").projectile_speed), "Reverse retargeting keeps the configured speed and a finite trajectory")
	_check(behind.health == behind.max_health, "Turning toward a reverse target does not claim an instant or guaranteed hit")
	_check(_rng_state(simulation) == rng_before, "Automatic fire, finishing collisions and reverse retargeting consume no extra random draws")

func _test_antiparallel_weights() -> void:
	for weight: float in [0.04, 0.5]:
		var simulation: CombatSim = _simulation()
		var target: CombatSim.Enemy = _stationary_caster(simulation, Vector2(440, 365))
		var ember: CombatSim.Shot = simulation.fire_weapon("ember", "", simulation.player_position, Vector2.RIGHT)
		# Isolate the interpolation boundary without changing fixed-step delta or resources.
		ember.homing = weight / DELTA
		var original_speed: float = ember.velocity.length()
		var rng_before: Array[int] = _rng_state(simulation)
		simulation.step(DELTA, Vector2.ZERO)
		_check(ember.active and ember.velocity.is_finite() and is_equal_approx(ember.velocity.length(), original_speed), "Antiparallel weight %.2f preserves finite nonzero projectile speed" % weight)
		_check(absf(ember.velocity.y) > 0.01 and ember.velocity.x > 0.0, "Antiparallel weight %.2f begins a gradual turn instead of staying straight, stopping or snapping back" % weight)
		_check(target.health == target.max_health and simulation.primary_hits == 0, "An antiparallel steering step alone creates no damage")
		_check(_rng_state(simulation) == rng_before, "Antiparallel steering leaves both RNG streams unchanged")

func _test_near_antiparallel_side() -> void:
	# These offsets are representable at y=365 and retain a tiny genuine cross sign.
	for side: float in [-1.0, 1.0]:
		var simulation: CombatSim = _simulation()
		var target: CombatSim.Enemy = _stationary_caster(simulation, Vector2(440, 365 + side * 0.000244140625))
		var ember: CombatSim.Shot = simulation.fire_weapon("ember", "", simulation.player_position, Vector2.RIGHT)
		var desired: Vector2 = (target.position - ember.position).normalized()
		_check(signf(Vector2.RIGHT.cross(desired)) == side, "The near-opposite fixture retains the real signed target offset")
		simulation.step(DELTA, Vector2.ZERO)
		_check(ember.velocity.y * side > 0.01, "Near-antiparallel steering honors the tiny cross sign instead of selecting an arbitrary opposite side")
		_check(is_equal_approx(ember.velocity.length(), GameCatalog.weapon("ember").projectile_speed), "Near-antiparallel steering preserves speed")

func _test_hit_uid_exclusion() -> void:
	var simulation: CombatSim = _simulation()
	var first: CombatSim.Enemy = simulation.spawn_enemy("chaser", Vector2(720, 365))
	first.health = 1000.0
	first.max_health = first.health
	first.action_timer = 9999.0
	first.slow_timer = 9999.0
	first.slow_factor = 0.0
	var unhit: CombatSim.Enemy = _stationary_caster(simulation, Vector2(440, 465))
	var ember: CombatSim.Shot = simulation.fire_weapon("ember", "pierce", simulation.player_position, Vector2.RIGHT)
	var rng_before: Array[int] = _rng_state(simulation)
	for frame: int in 40:
		if ember.hit_ids.has(first.uid):
			break
		simulation.step(DELTA, Vector2.ZERO)
	_check(first.active and ember.active and ember.hit_ids.has(first.uid), "A real piercing hit records the surviving target UID")
	var first_health: float = first.health
	_check(first_health == first.max_health - GameCatalog.weapon("ember").damage and not ember.hit_ids.has(unhit.uid), "Only the genuinely hit UID is excluded, with one real damage application")
	simulation.step(DELTA, Vector2.ZERO)
	_check(ember.velocity.y > 0.01, "Piercing ember steers toward the unhit off-axis target instead of the nearer excluded UID")
	_advance(simulation, 4)
	_check(first.health == first_health and simulation.primary_hits == 1, "Homing cannot re-damage a previously hit surviving UID")
	_check(_rng_state(simulation) == rng_before, "UID filtering and normal piercing steering draw no random numbers")

func _test_unaffected_paths() -> void:
	var empty: CombatSim = _simulation()
	var direction: Vector2 = Vector2(3, 7).normalized()
	var ember: CombatSim.Shot = empty.fire_weapon("ember", "", empty.player_position, direction)
	var original_velocity: Vector2 = ember.velocity
	var original_position: Vector2 = ember.position
	var rng_before: Array[int] = _rng_state(empty)
	_advance(empty, 10)
	_check(ember.active and ember.velocity == original_velocity and ember.position.is_equal_approx(original_position + original_velocity * DELTA * 10.0), "No-target ember retains its original straight trajectory")
	_check(_rng_state(empty) == rng_before, "No-target homing queries are RNG-read-only")
	var ordinary: CombatSim = _simulation()
	_stationary_caster(ordinary, Vector2(440, 465))
	var bone: CombatSim.Shot = ordinary.fire_weapon("bone", "", ordinary.player_position, Vector2.RIGHT)
	var initial: Vector2 = bone.velocity
	ordinary.step(DELTA, Vector2.ZERO)
	_check(bone.active and bone.velocity == initial and bone.homing == 0.0, "A non-homing weapon does not turn toward an off-axis target")
	for weight: float in [0.0, 0.75, 1.0]:
		var simulation: CombatSim = _simulation()
		_stationary_caster(simulation, Vector2(440, 365))
		var shot: CombatSim.Shot = simulation.fire_weapon("ember", "", simulation.player_position, Vector2.RIGHT)
		shot.homing = weight / DELTA
		var expected: Vector2 = Vector2.RIGHT.lerp(Vector2.LEFT, weight).normalized() * shot.velocity.length()
		simulation.step(DELTA, Vector2.ZERO)
		_check(shot.velocity.is_equal_approx(expected), "Weights outside the positive <=0.5 degenerate interval retain the original behavior: %.2f" % weight)

func _test_original_curve() -> void:
	for offset: float in [0.2, 100.0]:
		var simulation: CombatSim = _simulation()
		var target: CombatSim.Enemy = _stationary_caster(simulation, Vector2(440, 365 + offset))
		var ember: CombatSim.Shot = simulation.fire_weapon("ember", "", simulation.player_position, Vector2.RIGHT)
		var rng_before: Array[int] = _rng_state(simulation)
		var matches: bool = true
		for frame: int in 12:
			var desired: Vector2 = (target.position - ember.position).normalized()
			var expected: Vector2 = ember.velocity.normalized().lerp(desired, minf(1.0, ember.homing * DELTA)).normalized() * ember.velocity.length()
			simulation.step(DELTA, Vector2.ZERO)
			matches = matches and ember.velocity.is_equal_approx(expected)
		_check(matches, "Nondegenerate tracking retains the original normalized-vector lerp curve over successive formal steps: offset %.1f" % offset)
		_check(is_equal_approx(ember.velocity.length(), GameCatalog.weapon("ember").projectile_speed), "The preserved ordinary curve keeps configured projectile speed")
		_check(_rng_state(simulation) == rng_before, "Ordinary homing queries leave both RNG streams unchanged")

func _deterministic_reverse(seed_value: int) -> Dictionary:
	var simulation: CombatSim = _simulation(seed_value)
	var target: CombatSim.Enemy = _stationary_caster(simulation, Vector2(440, 365))
	var ember: CombatSim.Shot = simulation.fire_weapon("ember", "", simulation.player_position, Vector2.RIGHT)
	var rng_before: Array[int] = _rng_state(simulation)
	_advance(simulation, 20)
	return {"position": ember.position, "velocity": ember.velocity, "active": ember.active, "uid": target.uid, "health": target.health, "hit_ids": ember.hit_ids.duplicate(), "rng": _rng_state(simulation), "rng_unchanged": _rng_state(simulation) == rng_before, "summary": simulation.run.summary()}

func _test_determinism() -> void:
	var first: Dictionary = _deterministic_reverse(991)
	var second: Dictionary = _deterministic_reverse(991)
	var other_seed: Dictionary = _deterministic_reverse(992)
	_check(first == second, "The same seed and reverse target reproduce the complete steering result")
	_check(first["velocity"] == other_seed["velocity"] and first["position"] == other_seed["position"], "The exact-opposite turn side is deterministic and independent of random seed")
	_check(first["rng_unchanged"] and second["rng_unchanged"] and other_seed["rng_unchanged"], "Deterministic reverse steering never consumes RNG")
