extends SceneTree
## Finite movement surviving the input deadzone must aim movement and dash consistently.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_light_movement_and_dash()
	_test_release_retains_facing()
	_test_zero_and_invalid_requests()
	print("AnalogDash: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _sim() -> CombatSim:
	var state := RunState.new()
	state.begin(20261028, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim

func _test_light_movement_and_dash() -> void:
	for heading: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(-1, -1).normalized(), Vector2(1, 1).normalized()]:
		for strength: float in [0.05, 0.0001]:
			var sim: CombatSim = _sim()
			var movement: Vector2 = heading * strength
			var origin: Vector2 = sim.player_position
			sim.step(STEP, movement)
			_check(sim.player_velocity.is_equal_approx(movement * 220.0) and sim.player_position.distance_to(origin + movement * 220.0 * STEP) < 0.003, "A light finite movement retains its exact analog strength and ordinary speed")
			_check(sim.player_direction.is_equal_approx(heading), "Every finite nonzero light movement updates facing, including strength below the old threshold")
			var dash_origin: Vector2 = sim.player_position
			sim.step(STEP, movement, true)
			_check(sim.dash_direction.is_equal_approx(heading) and sim.player_position.distance_to(dash_origin + heading * 11.0) < 0.003, "A real light-direction dash follows the current movement rather than stale facing")
			_check(absf(sim.player_velocity.length() - 660.0) < 0.001 and _near(sim.dash_time_left, 0.2 - STEP) and _near(sim.dash_invulnerability_left, 0.12 - STEP) and _near(sim.dash_cooldown_left, 2.4 - STEP), "Analog aiming changes neither dash speed, duration, shield nor cooldown")
			for frame: int in 11:
				sim.step(STEP, Vector2.ZERO)
			_check(sim.player_position.distance_to(dash_origin + heading * 132.0) < 0.003 and sim.dash_time_left == 0.0 and sim.dash_invulnerability_left == 0.0 and sim.dashes_used == 1, "The complete light-direction burst retains its original distance and vulnerable tail")

func _test_release_retains_facing() -> void:
	var sim: CombatSim = _sim()
	for frame: int in 4:
		sim.step(STEP, Vector2.UP * 0.05)
	sim.step(STEP, Vector2.ZERO)
	_check(sim.player_velocity == Vector2.ZERO and sim.player_direction == Vector2.UP, "Releasing light movement stops the player and retains that last real facing")
	sim.step(STEP, Vector2.ZERO, true)
	_check(sim.dash_direction == Vector2.UP and sim.dashes_used == 1, "A later stationary dash uses the facing established by light analog movement")

func _test_zero_and_invalid_requests() -> void:
	for facing: Vector2 in [Vector2.UP, Vector2(-3, 4), Vector2.ZERO, Vector2.INF, Vector2(NAN, 0.0)]:
		var sim: CombatSim = _sim()
		sim.player_direction = facing
		var expected: Vector2 = facing.normalized() if facing.is_finite() and facing.length_squared() > 0.01 else Vector2.RIGHT
		sim.step(STEP, Vector2.ZERO, true)
		_check(sim.dash_direction.is_equal_approx(expected) and sim.player_position.is_finite() and sim.player_velocity.is_finite(), "True zero movement retains the existing facing or finite rightward fallback")
	for movement: Vector2 in [Vector2.INF, Vector2(-INF, 0.0), Vector2(NAN, 0.0), Vector2(0.0, NAN)]:
		var sim: CombatSim = _sim()
		var before: Array = [sim.player_position, sim.player_direction, sim.dash_snapshot(), sim.dash_invulnerability_left]
		sim._try_start_dash(movement)
		_check(before == [sim.player_position, sim.player_direction, sim.dash_snapshot(), sim.dash_invulnerability_left] and sim.player_position.is_finite(), "Nonfinite dash requests retain their original rejection and cannot poison direction or consume a skill")
