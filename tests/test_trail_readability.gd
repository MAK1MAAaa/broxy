extends SceneTree
## Trail styling must preserve combat state, endpoint batches and the instance cap.

const PAINTER_SCRIPT = preload("res://scripts/combat/projectile_painter.gd")
const SOURCES: PackedStringArray = ["bone", "frost", "ember", "scatter", "crescent", "storm", "comet"]
const RUNES: PackedStringArray = ["", "pierce", "bounce", "blast"]
const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_styles()
	_test_real_combat_purity()
	_test_pressure_budget()
	print("TrailReadability: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _simulation() -> CombatSim:
	var state := RunState.new()
	state.begin(20261024, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(1040, 555)
	for point: Vector2 in [Vector2(615, 320), Vector2(660, 320), Vector2(710, 320)]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.health = 100000.0
		enemy.max_health = enemy.health
		enemy.action_timer = 9999.0
	for source: String in SOURCES:
		for rune: String in RUNES:
			sim.fire_weapon(source, rune, Vector2(595, 320), Vector2.RIGHT)
	return sim


func _test_styles() -> void:
	var sim: CombatSim = _simulation()
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(sim.shots)
	_check(painter.get_stats()["family_counts"].size() == 28, "All seven weapons and four socket states receive their existing drawing families")
	for source: String in SOURCES:
		var definition: ContentDef = GameCatalog.weapon(source)
		for rune: String in RUNES:
			var key: String = source + ":" + rune
			var trail = painter.trails[key]
			var style = trail.style
			var base_width: float = definition.projectile_radius * (0.55 if source in ["crescent", "comet"] else 1.2)
			_check(is_equal_approx(trail.width, base_width), "Source-radius width remains available without changing geometry: " + key)
			if source == "ember":
				_check(not style.has_halo and is_zero_approx(style.halo_width) and is_zero_approx(style.halo_color.a), "Ember retains one trail command without an added halo: " + key)
				_check(is_equal_approx(style.main_color.a, 0.40) and is_equal_approx(style.main_width, base_width), "Ember keeps its authored opacity and radius width: " + key)
			else:
				_check(style.has_halo and is_equal_approx(style.main_color.a, 0.58) and is_equal_approx(style.halo_color.a, 0.10), "Friendly trail opacity leaves the fully legible heads and sigils in charge: " + key)
				_check(is_equal_approx(style.main_width, base_width * 0.72) and is_equal_approx(style.halo_width, base_width * 1.55), "Main and halo widths narrow relative to the unmodified source width: " + key)
			_check(Color(style.main_color, 1.0).is_equal_approx(Color(trail.color, 1.0)), "Readability styling preserves the weapon/rune RGB identity: " + key)
			if style.has_halo:
				_check(Color(style.halo_color, 1.0).is_equal_approx(Color(trail.color, 1.0)), "The subdued halo retains the same weapon/rune RGB: " + key)
	_check(is_equal_approx(painter.trails["frost:"].style.main_width, 5.184)
		and is_equal_approx(painter.trails["frost:"].style.halo_width, 11.16), "Frost's actual display strokes narrow from 7.2/16.776px to 5.184/11.16px")
	_check(is_equal_approx(painter.trails["comet:"].style.main_width, 4.356)
		and is_equal_approx(painter.trails["comet:"].style.halo_width, 9.3775), "Comet's actual display strokes narrow from 6.05/14.0965px to 4.356/9.3775px")


func _test_real_combat_purity() -> void:
	var painted: CombatSim = _simulation()
	var oracle: CombatSim = _simulation()
	var painter = PAINTER_SCRIPT.new()
	var before: String = _signature(painted)
	painter.rebuild(painted.shots)
	var endpoints: String = _endpoint_signature(painter)
	for repeat: int in 3:
		painter.rebuild(painted.shots)
		_check(_endpoint_signature(painter) == endpoints, "Repeated styling preserves every trail, wing and sigil endpoint")
	_check(_signature(painted) == before and _signature(oracle) == before, "Style preparation preserves both RNGs, projectile budgets, enemies and run state")
	painted.step(STEP, Vector2.ZERO)
	oracle.step(STEP, Vector2.ZERO)
	_check(painted.primary_hits > 0 and painted.secondary_hits > 0, "The oracle comparison includes real direct and blast collisions")
	_check(_signature(painted) == _signature(oracle), "A real collision step remains identical with or without rendering preparation")
	before = _signature(painted)
	painter.rebuild(painted.shots)
	_check(_signature(painted) == before, "Refreshing styles after collisions does not change surviving shots or hit exclusions")
	var empty: Array[CombatSim.Shot] = []
	painter.rebuild(empty)
	_check(painter.trails.is_empty() and painter.rings.is_empty()
		and painter.get_stats()["total_visible_instances"] == 0, "An empty rebuild leaves no old styled trail, ring or core visible")


func _test_pressure_budget() -> void:
	var state := RunState.new()
	state.begin(20261024, "bone")
	var world := CombatWorld.new()
	var sound := SoundBank.new()
	world.sound = sound
	world.begin(state)
	world.sim.populate_stress()
	world.enable_rune_stress(true)
	var before: String = _signature(world.sim)
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(world.sim.shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["friendly_count"] == 600 and stats["family_counts"].size() == 21, "The formal pressure fixture retains six hundred shots across twenty-one families")
	_check(stats["allocated_instances"] <= 4800 and stats["total_visible_instances"] <= 4800, "Trail styling introduces no projectile GPU instances")
	var trail_commands: int = 0
	for trail in painter.trails.values():
		trail_commands += 2 if trail.style.has_halo else 1
		trail_commands += 0 if trail.wings.is_empty() else 1
		trail_commands += 0 if trail.sigils.is_empty() else 1
	_check(trail_commands == 57, "The same twenty-one families retain their original fifty-seven trail, wing and sigil submissions")
	_check(_signature(world.sim) == before, "Preparing the full pressure scene does not advance or modify its simulation")
	world.free()
	sound.free()


func _endpoint_signature(painter) -> String:
	var result: Dictionary = {}
	for key: String in painter.trails:
		var trail = painter.trails[key]
		result[key] = [trail.points, trail.wings, trail.sigils]
	return JSON.stringify(result)


func _signature(sim: CombatSim) -> String:
	var result: Array = [sim.rng.state, sim.run.rng.state, sim.run.summary(), sim.snapshot(),
		sim.primary_hits, sim.secondary_hits, sim.damage_by_weapon, sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		result.append([shot.slot, shot.active, shot.hostile, shot.source, shot.attacker_id, shot.position,
			shot.previous, shot.velocity, shot.radius, shot.color, shot.damage, shot.life, shot.rune,
			shot.remaining, shot.innate_remaining, shot.hit_ids.duplicate(), shot.homing, shot.slow])
	for enemy: CombatSim.Enemy in sim.enemies:
		result.append([enemy.slot, enemy.uid, enemy.active, enemy.position, enemy.velocity, enemy.health,
			enemy.max_health, enemy.age, enemy.action_timer, enemy.slow_timer, enemy.slow_factor,
			enemy.hurt_timer, enemy.mode, enemy.charge_direction])
	for effect: CombatSim.Effect in sim.effects:
		result.append([effect.position, effect.radius, effect.color, effect.life, effect.total, effect.kind])
	return JSON.stringify(result)
