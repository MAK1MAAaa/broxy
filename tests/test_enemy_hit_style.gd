extends SceneTree
## Actual collisions drive the timer; rendering preserves state, cold hue and budgets.

const STEP: float = 1.0 / 60.0
const IDS: PackedStringArray = ["chaser", "rusher", "tank", "caster", "boss"]

class SilentSoundBank:
	extends SoundBank

	func _ready() -> void:
		pass

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_real_hit_and_decay()
	_test_repeat_and_disabled()
	_test_boundaries()
	_test_dense_purity_and_budget()
	print("EnemyHitStyle: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _world() -> CombatWorld:
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": true}
	root.add_child(world)
	var state := RunState.new()
	state.begin(20261025, "bone")
	world.begin(state)
	world.set_physics_process(false)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	world.sim.player_position = Vector2(1180, 570)
	return world


func _target(sim: CombatSim, id: String) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, Vector2(500, 340))
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = 100000.0
	enemy.max_health = enemy.health
	enemy.action_timer = 9999.0
	return enemy


func _step(world: CombatWorld) -> void:
	world._advance_feedback(STEP)
	world.sim.step(STEP, Vector2.ZERO)


func _hit(world: CombatWorld, enemy: CombatSim.Enemy, chilled: bool) -> void:
	world.sim.fire_weapon("frost" if chilled else "bone", "", enemy.position - Vector2(20, 0), Vector2.RIGHT)
	_step(world)


func _dispose(world: CombatWorld) -> void:
	var sound: SoundBank = world.sound
	world.free()
	sound.free()


func _test_real_hit_and_decay() -> void:
	for chilled: bool in [false, true]:
		for id: String in IDS:
			var world: CombatWorld = _world()
			var enemy: CombatSim.Enemy = _target(world.sim, id)
			var base: Color = Color("b4e9ed") if chilled else Color.WHITE
			var label: String = id + (" chilled" if chilled else " normal")
			_hit(world, enemy, chilled)
			_check(world.sim.primary_hits == 1 and enemy.health < enemy.max_health, "A real projectile damages the target: " + label)
			_check(is_equal_approx(enemy.hurt_timer, 0.10), "The production collision retains the original 100ms timer: " + label)
			_check((enemy.slow_timer > 0.0) == chilled, "Only the actual frost collision establishes the cold state: " + label)
			var tint: Color = world._enemy_tint(enemy)
			_check(tint.is_equal_approx(Color(base.r * 1.22, base.g * 1.22, base.b * 1.22, 1.0)), "The real-hit peak is bounded and based on the current state color: " + label)
			_check(world._impact_painter.active_count() == 1 and not world._numbers.is_empty(), "The primary hit retains its existing mark and actual-damage number: " + label)
			var original: String = _signature(world.sim)
			var visual: Dictionary = _visual_budget(world)
			for repeat: int in 3:
				world._enemy_tint(enemy)
			_check(_signature(world.sim) == original and _visual_budget(world) == visual, "Repeated tint reads change neither simulation nor existing rendering resources: " + label)
			var previous_gain: float = tint.r / base.r
			for frame: int in 7:
				_step(world)
				tint = world._enemy_tint(enemy)
				var gain: float = tint.r / base.r
				_check(gain <= previous_gain + 0.00001 and gain >= 1.0 and gain <= 1.22001 and tint.a == 1.0, "A real step only decays the bounded opaque pulse: " + label)
				if chilled:
					_check(is_equal_approx(tint.r / base.r, tint.g / base.g)
						and is_equal_approx(tint.g / base.g, tint.b / base.b)
						and tint.b > tint.g and tint.g > tint.r, "Brightness preserves the cold RGB ratios rather than replacing them: " + label)
				if frame == 3:
					_check(enemy.hurt_timer > 0.0 and tint.is_equal_approx(base), "The tint returns to its material color before the simulation's receipt expires: " + label)
				previous_gain = gain
			_check(is_zero_approx(enemy.hurt_timer) and tint.is_equal_approx(base), "Expiry leaves no residual body brightening: " + label)
			_dispose(world)


func _test_repeat_and_disabled() -> void:
	var world: CombatWorld = _world()
	var enemy: CombatSim.Enemy = _target(world.sim, "chaser")
	_hit(world, enemy, false)
	for frame: int in 3:
		_step(world)
	_check(world._enemy_tint(enemy).r < 1.01, "A prior hit fades almost completely after fifty milliseconds")
	_hit(world, enemy, false)
	_check(world.sim.primary_hits == 2 and is_equal_approx(enemy.hurt_timer, 0.10)
		and is_equal_approx(world._enemy_tint(enemy).r, 1.22), "A second real hit restarts one bounded pulse instead of accumulating brightness")
	var marks: int = world._impact_painter.active_count()
	world.sim.apply_damage(enemy, 5.0, "bone", true)
	_check(world.sim.secondary_hits == 1 and is_equal_approx(world._enemy_tint(enemy).r, 1.22)
		and world._impact_painter.active_count() == marks, "Real secondary damage stays within the same tint cap and adds no primary-only impact mark")
	world.apply_visual_settings({"shake": false, "flash": false})
	_check(world._enemy_tint(enemy).is_equal_approx(Color.WHITE) and world._impact_painter.active_count() == 0, "Disabling flash immediately restores the base material and clears the existing marks")
	var health: float = enemy.health
	_hit(world, enemy, true)
	_check(enemy.health < health and world.sim.primary_hits == 3 and enemy.slow_timer > 0.0,
		"Flash suppression leaves actual damage and frost application intact")
	_check(world._enemy_tint(enemy).is_equal_approx(Color("b4e9ed")) and world._impact_painter.active_count() == 0,
		"A new hit with flash disabled retains the cold material without adding marks")
	_dispose(world)


func _test_boundaries() -> void:
	var world: CombatWorld = _world()
	var enemy := CombatSim.Enemy.new()
	for chilled: bool in [false, true]:
		enemy.slow_timer = 1.0 if chilled else 0.0
		var base: Color = Color("b4e9ed") if chilled else Color.WHITE
		for remaining: float in [-1.0, 0.0, 0.04, -INF, INF, NAN]:
			enemy.hurt_timer = remaining
			_check(world._enemy_tint(enemy).is_equal_approx(base), "Expired and non-finite timers return the unmodified state color")
		enemy.hurt_timer = 1000.0
		_check(is_equal_approx(world._enemy_tint(enemy).r / base.r, 1.22), "An oversized finite timer cannot exceed the visual peak")
		enemy.hurt_timer = 0.10 - 1.0 / 60.0
		_check(is_equal_approx(world._enemy_tint(enemy).r / base.r, 1.1147530864), "One-sixtieth of a second after impact has the defined short decay")
		enemy.hurt_timer = 0.10 - 2.0 / 60.0
		_check(is_equal_approx(world._enemy_tint(enemy).r / base.r, 1.0434567901), "The second frame has the defined lower gain")
	_dispose(world)


func _test_dense_purity_and_budget() -> void:
	var world: CombatWorld = _world()
	world.sim.player_position = Vector2(455, 375)
	world.stress_mode = true
	world.sim.populate_stress()
	world.enable_rune_stress(true)
	for frame: int in 20:
		_step(world)
		world._maintain_stress()
	world._projectile_painter.rebuild(world.sim.shots)
	world._enemy_telegraphs.rebuild(world.sim.enemies)
	world._impact_painter.rebuild()
	var before: String = _signature(world.sim)
	var budget: Dictionary = _visual_budget(world)
	var count: int = 0
	for enemy: CombatSim.Enemy in world.sim.enemies:
		if enemy.active:
			var tint: Color = world._enemy_tint(enemy)
			_check(tint.a == 1.0 and maxf(tint.r, maxf(tint.g, tint.b)) <= 1.22001, "Every active dense-scene enemy keeps its opaque bounded tint")
			count += 1
	_check(count == 300 and world.sim.primary_hits > 0 and world.sim.secondary_hits > 0, "The full production pressure scene actually exercises direct and secondary damage")
	_check(_signature(world.sim) == before and _visual_budget(world) == budget, "Dense tint preparation changes neither RNG/state nor projectile, telegraph and impact allocations")
	var stats: Dictionary = world._projectile_painter.get_stats()
	_check(stats["friendly_count"] == 600 and stats["family_counts"].size() == 21
		and stats["allocated_instances"] <= 4800, "The existing twenty-one projectile families retain the original instance budget")
	_check(world._impact_painter.get_stats()["draw_commands"] <= 12, "Primary-hit marks retain their twelve-command budget")
	_dispose(world)


func _visual_budget(world: CombatWorld) -> Dictionary:
	return {"projectiles": world._projectile_painter.get_stats(), "telegraphs": world._enemy_telegraphs.get_stats(),
		"impacts": world._impact_painter.get_stats(), "numbers": world._numbers.size(), "runes": world._rune_flashes.size()}


func _signature(sim: CombatSim) -> String:
	var result: Array = [sim.rng.state, sim.run.rng.state, sim.run.summary(), sim.snapshot(),
		sim.primary_hits, sim.secondary_hits, sim.damage_by_weapon, sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		result.append([shot.slot, shot.active, shot.hostile, shot.source, shot.position, shot.previous,
			shot.velocity, shot.damage, shot.radius, shot.life, shot.rune, shot.remaining, shot.innate_remaining, shot.hit_ids])
	for enemy: CombatSim.Enemy in sim.enemies:
		result.append([enemy.slot, enemy.uid, enemy.active, enemy.position, enemy.velocity, enemy.health,
			enemy.max_health, enemy.age, enemy.action_timer, enemy.hurt_timer, enemy.slow_timer,
			enemy.slow_factor, enemy.mode, enemy.charge_direction])
	for effect: CombatSim.Effect in sim.effects:
		result.append([effect.position, effect.radius, effect.color, effect.life, effect.total, effect.kind])
	return JSON.stringify(result)
