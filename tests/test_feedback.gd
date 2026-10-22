extends SceneTree
## Real combat events drive bounded feedback without creating per-hit scene nodes.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test.call_deferred()

func _test() -> void:
	var sound := SoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	var run := RunState.new()
	run.begin(2026, "bone")
	world.begin(run)
	world.set_physics_process(false)
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(1000.0)
	var target: CombatSim.Enemy = sim.spawn_enemy("tank", Vector2(860, 300))
	target.health = 1000.0
	sim.apply_damage(target, 14.0, "bone")
	_check(world._numbers.size() == 1 and is_equal_approx(world._numbers[0].amount, 14.0), "A real accepted hit emits its actual damage into the world feedback")
	sim.apply_damage(target, 3.5, "bone", true)
	_check(world._numbers.size() == 1 and world._numbers[0].text == "17.5", "Near-simultaneous primary and splash damage coalesce without losing fractional damage")
	sim.apply_damage(target, 5.0, "frost")
	_check(world._numbers.size() == 2, "Different weapon sources remain distinguishable rather than merging together")
	sim.apply_damage(target, 0.0, "bone")
	_check(world._numbers.size() == 2 and world._numbers[0].text == "17.5", "Zero damage does not create or inflate a combat number")
	var neighbor: CombatSim.Enemy = sim.spawn_enemy("tank", Vector2(880, 300))
	sim.apply_damage(neighbor, 14.0, "bone")
	_check(world._numbers.size() == 3 and world._numbers[0].text == "17.5", "Adjacent enemies keep separate damage numbers using target identity rather than proximity")
	_check(world._numbers[0].text_width > 0.0, "Damage text has a cached layout width for centered native rendering")
	var position_before: Vector2 = world._numbers[0].position
	world._advance_feedback(0.1)
	_check(world._numbers[0].position.y < position_before.y, "Combat numbers drift upward as time advances")
	world.set_physics_process(true)
	paused = true
	var life_before: float = world._numbers[0].life
	await process_frame
	await process_frame
	_check(is_equal_approx(world._numbers[0].life, life_before), "Pausing freezes feedback lifetime along with combat")
	paused = false
	await physics_frame
	await physics_frame
	await physics_frame
	world.set_physics_process(false)
	_check(world._numbers[0].life < life_before, "Resuming the real physics loop resumes feedback motion and expiry")
	sim._hurt_player(8.0, "caster", "projectile", Vector2(760, 300))
	var player_count: int = _player_numbers(world)
	_check(player_count == 1 and is_equal_approx(run.health, 92.0), "Actual incoming damage creates one player number and the same health loss")
	sim._hurt_player(8.0, "caster", "projectile", Vector2(760, 300))
	_check(_player_numbers(world) == player_count and is_equal_approx(run.health, 92.0), "Invulnerability produces neither repeated damage nor misleading incoming numbers")
	_check(world._damage_direction.is_finite() and world._damage_direction.x > 0.0, "Incoming feedback points toward the actual source location")
	world._on_damage_dealt(world._numbers.back().position + Vector2(0, 22), 14.0, "scatter", false, 9999)
	_check(world._numbers.back().player_hit, "Later outgoing damage never draws on top of an existing incoming-damage number")
	world._advance_feedback(2.0)
	_check(world._numbers.is_empty() and world._number_free.size() == CombatWorld.NUMBER_LIMIT, "Expired feedback returns every object to the fixed pool")
	_check(is_zero_approx(world._damage_flash), "The transient damage ring expires completely")
	for index: int in 200:
		world._on_damage_dealt(Vector2(float(index) * 40.0, 300), 1.0, "bone", false)
	_check(world._numbers.size() <= CombatWorld.NUMBER_LIMIT - 1, "A barrage remains bounded and preserves capacity for incoming damage")
	sim.invulnerability = 0.0
	sim._hurt_player(3.0, "chaser", "contact", Vector2(550, 350))
	_check(_player_numbers(world) == 1 and world._numbers.size() <= CombatWorld.NUMBER_LIMIT, "Incoming damage remains visible when friendly damage fills its visual budget")
	world.stop()
	_check(world._numbers.is_empty() and world._number_free.size() == CombatWorld.NUMBER_LIMIT, "Stopping combat clears stale numbers before menus or another run")
	world.begin(run)
	world.set_physics_process(false)
	world._on_player_damaged(2.5, "unknown", "unknown", Vector2.INF)
	_check(world._damage_direction == Vector2.ZERO, "An unspecified source never produces an infinite or NaN direction")
	var player_text: String = world._numbers[0].text
	_check(player_text == "−2.5", "Player feedback retains the loss sign and real fractional amount")
	for cycle: int in 10:
		world._on_damage_dealt(Vector2(200, 200), 1.0, "bone", false)
		world._advance_feedback(2.0)
	var distinct: Dictionary = {}
	for number: CombatWorld.FloatingNumber in world._number_free:
		distinct[number.get_instance_id()] = true
	_check(distinct.size() == CombatWorld.NUMBER_LIMIT, "Repeated reuse never duplicates or leaks feedback pool entries")
	print("Feedback: %d assertions, %d failures" % [_checks, _failures])
	world.queue_free()
	sound.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)

func _player_numbers(world: CombatWorld) -> int:
	var count: int = 0
	for number: CombatWorld.FloatingNumber in world._numbers:
		if number.player_hit:
			count += 1
	return count

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
