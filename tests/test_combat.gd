extends SceneTree

const DELTA: float = 1.0 / 60.0

class ExplosionProbeSim extends CombatSim:
	var use_linear: bool = false
	var spawn_after_grid: Vector2 = Vector2.INF
	var deferred_enemy: Enemy
	var freeze_enemy_updates: bool = false
	var nearest_queries: Array[Dictionary] = []
	var nearest_results: Array[int] = []
	var nearest_reference: Array[int] = []
	var nearest_grid_flags: Array[bool] = []
	var nearest_kill_slot: int = -1
	var nearest_rng_unchanged: bool = true

	func _update_enemies(delta: float) -> void:
		if not freeze_enemy_updates:
			super._update_enemies(delta)

	func _update_weapons(delta: float) -> void:
		if spawn_after_grid != Vector2.INF:
			deferred_enemy = spawn_enemy("tank", spawn_after_grid)
			deferred_enemy.health = 10000.0
			deferred_enemy.max_health = 10000.0
			deferred_enemy.slow_timer = 9999.0
			deferred_enemy.slow_factor = 0.0
			deferred_enemy.action_timer = 9999.0
			spawn_after_grid = Vector2.INF
		if nearest_kill_slot >= 0:
			apply_damage(enemies[nearest_kill_slot], enemies[nearest_kill_slot].health, "bone")
			nearest_kill_slot = -1
		var rng_before: int = rng.state
		for query: Dictionary in nearest_queries:
			nearest_grid_flags.append(_explosion_grid_active)
			var actual: Enemy = _nearest(query["position"], float(query["range"]), query.get("excluded", {}))
			var expected: Enemy = _nearest_oracle(query["position"], float(query["range"]), query.get("excluded", {}))
			nearest_results.append(actual.uid if actual != null else -1)
			nearest_reference.append(expected.uid if expected != null else -1)
		nearest_rng_unchanged = nearest_rng_unchanged and rng.state == rng_before
		super._update_weapons(delta)

	func _nearest_oracle(position: Vector2, distance: float, excluded: Dictionary) -> Enemy:
		var result: Enemy
		var best: float = distance * distance
		for enemy: Enemy in enemies:
			if not enemy.active or excluded.has(enemy.uid):
				continue
			var squared: float = enemy.position.distance_squared_to(position)
			if squared < best:
				best = squared
				result = enemy
		return result

	func _explode(position: Vector2, amount: float, source: String, excluded: Dictionary) -> void:
		if not use_linear:
			super._explode(position, amount, source, excluded)
			return
		# Freeze the pre-optimization full-pool ordering as an independent oracle.
		add_effect(position, Color("df9cfa"), 68.0, 0.35, 0)
		for enemy: Enemy in enemies:
			if complete:
				return
			if not enemy.active or excluded.has(enemy.uid):
				continue
			if enemy.position.distance_squared_to(position) < pow(68.0 + enemy.radius, 2):
				apply_damage(enemy, amount, source, true)

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_weapon_rune_matrix()
	_test_pierce()
	_test_bounce()
	_test_blast()
	_test_rune_activation_guards()
	_test_explosion_spatial_equivalence()
	_test_nearest_spatial_equivalence()
	_test_contact_recoil()
	_test_caster_aim()
	_test_ember_homing()
	_test_damage_accounting()
	_test_damage_sources()
	_test_terminal_damage_freeze()
	_test_slow_states()
	_test_swept_collision_order()
	_test_soul_accounting()
	_test_wave_outcomes()
	_test_outcome_ordering()
	_test_seed_reproduction()
	print("Combat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _simulation(seed_value: int = 1234, number: int = 1, starter: String = "bone") -> CombatSim:
	var state: RunState = RunState.new()
	state.begin(seed_value, starter)
	state.wave = number
	var simulation: CombatSim = CombatSim.new()
	simulation.begin(state)
	simulation.sandbox = true
	simulation._cooldowns.fill(9999.0)
	simulation.player_position = Vector2(1050, 590)
	return simulation

func _target(simulation: CombatSim, position: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = simulation.spawn_enemy("chaser", position)
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	enemy.action_timer = 9999.0
	enemy.slow_timer = 9999.0
	enemy.slow_factor = 0.0
	return enemy

func _advance(simulation: CombatSim, frames: int) -> void:
	for index: int in range(frames):
		simulation.step(DELTA, Vector2.ZERO)

func _rune_events(simulation: CombatSim) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var simulation_ref: WeakRef = weakref(simulation)
	if simulation.has_signal("rune_activated"):
		simulation.connect("rune_activated", func(rune_id: String, origin: Vector2, incoming_direction: Vector2, outgoing_direction: Vector2) -> void:
			var current: CombatSim = simulation_ref.get_ref() as CombatSim
			events.append({"rune": rune_id, "origin": origin, "incoming_direction": incoming_direction, "outgoing_direction": outgoing_direction, "primary_hits": current.primary_hits, "secondary_hits": current.secondary_hits, "complete": current.complete})
		)
	return events

func _test_weapon_rune_matrix() -> void:
	for weapon: ContentDef in GameCatalog.weapons():
		for rune: ContentDef in GameCatalog.runes():
			var simulation: CombatSim = _simulation(90, 1, weapon.id)
			var activations: Array[Dictionary] = _rune_events(simulation)
			simulation.player_position = Vector2(200, 300)
			simulation.run.loadout[0]["rune"] = {"id": rune.id, "paid": 0, "uid": 1}
			var first: CombatSim.Enemy = _target(simulation, Vector2(340, 300))
			_target(simulation, Vector2(395, 300))
			_target(simulation, Vector2(450, 300))
			simulation._cooldowns[0] = 0.0
			simulation.step(DELTA, Vector2.ZERO)
			_check(simulation.shot_count == weapon.shots, "Weapon emits its configured shot count: " + weapon.id + "/" + rune.id)
			simulation._cooldowns.fill(9999.0)
			_advance(simulation, 60)
			_check(simulation.primary_hits > 0, "Weapon/rune combination hits an enemy: " + weapon.id + "/" + rune.id)
			_check(float(simulation.damage_by_weapon.get(weapon.id, 0.0)) > 0.0, "Combination accounts damage under its weapon")
			_check(not activations.is_empty(), "All four weapons report an executed rune behavior: " + weapon.id + "/" + rune.id)
			if weapon.id == "frost":
				_check(first.slow_timer > 0.0 and is_equal_approx(first.slow_factor, 0.75), "Frost applies its advertised 25% slow")

func _test_pierce() -> void:
	var simulation: CombatSim = _simulation()
	var activations: Array[Dictionary] = _rune_events(simulation)
	var targets: Array[CombatSim.Enemy] = []
	for index: int in range(4):
		targets.append(_target(simulation, Vector2(300 + index * 40, 300)))
	var shot: CombatSim.Shot = simulation.fire_weapon("bone", "pierce", Vector2(200, 300), Vector2.RIGHT)
	_advance(simulation, 60)
	_check(simulation.primary_hits == 3, "Pierce hits at most three different enemies")
	_check(shot.hit_ids.size() == 3 and not shot.active, "Pierce exhausts its budget without repeat hits")
	for index: int in range(3):
		_check(is_equal_approx(targets[index].health, 9986.0), "Pierce applies one full hit to each traversed target")
	_check(targets[3].health == 10000.0, "Pierce does not hit a fourth enemy")
	_check(activations.size() == 2, "Three pierce hits report only the two actual continuations")
	if activations.size() == 2:
		_check(activations[0]["primary_hits"] == 1 and activations[1]["primary_hits"] == 2, "Pierce feedback follows positive hits and excludes its exhausted third hit")
		_check(activations[0]["rune"] == "pierce" and activations[0]["origin"] == targets[0].position and activations[0]["incoming_direction"] == Vector2.RIGHT and activations[0]["outgoing_direction"] == Vector2.RIGHT, "Pierce feedback reports its impact and unchanged real directions")

func _test_bounce() -> void:
	var simulation: CombatSim = _simulation()
	var activations: Array[Dictionary] = _rune_events(simulation)
	var first: CombatSim.Enemy = _target(simulation, Vector2(330, 300))
	var second: CombatSim.Enemy = _target(simulation, Vector2(390, 340))
	var third: CombatSim.Enemy = _target(simulation, Vector2(450, 300))
	var distant: CombatSim.Enemy = _target(simulation, Vector2(800, 300))
	var shot: CombatSim.Shot = simulation.fire_weapon("bone", "bounce", Vector2(200, 300), Vector2.RIGHT)
	_advance(simulation, 90)
	_check(simulation.primary_hits == 3 and shot.hit_ids.size() == 3, "Bounce reaches three distinct enemies")
	_check(is_equal_approx(10000.0 - first.health, 14.0), "Bounce primary damage is full strength")
	_check(is_equal_approx(10000.0 - second.health, 10.5), "First bounce applies 25% decay")
	_check(is_equal_approx(10000.0 - third.health, 7.875), "Second bounce compounds its decay")
	_check(distant.health == 10000.0 and not shot.active, "Bounce neither exceeds its budget nor returns to a prior target")
	_check(activations.size() == 2, "Three bounce hits report only the two successful redirections")
	if activations.size() == 2:
		_check(activations[0]["origin"] == first.position and activations[1]["origin"] == second.position, "Bounce feedback originates at each real hit")
		_check(activations[0]["rune"] == "bounce" and (activations[0]["outgoing_direction"] as Vector2).is_equal_approx((second.position - first.position).normalized()), "First bounce feedback uses its new direction toward the next target")
		_check((activations[1]["outgoing_direction"] as Vector2).is_equal_approx((third.position - second.position).normalized()), "Second bounce feedback uses the next actual outgoing direction")
		_check(activations[0]["incoming_direction"] == Vector2.RIGHT and (activations[1]["incoming_direction"] as Vector2).is_equal_approx(activations[0]["outgoing_direction"]), "Bounce reports the real incoming direction at each turn")
		_check(activations[0]["primary_hits"] == 1 and activations[1]["primary_hits"] == 2, "Bounce feedback precedes future target damage and excludes the exhausted hit")

func _test_blast() -> void:
	var simulation: CombatSim = _simulation()
	var activations: Array[Dictionary] = _rune_events(simulation)
	var primary: CombatSim.Enemy = _target(simulation, Vector2(330, 300))
	var neighbor: CombatSim.Enemy = _target(simulation, Vector2(385, 300))
	var chain_only: CombatSim.Enemy = _target(simulation, Vector2(440, 300))
	simulation.fire_weapon("bone", "blast", Vector2(200, 300), Vector2.RIGHT)
	_advance(simulation, 60)
	_check(is_equal_approx(10000.0 - primary.health, 14.0), "Blast excludes its primary target from secondary damage")
	_check(is_equal_approx(10000.0 - neighbor.health, 7.7), "Blast deals 55% damage to its neighbor")
	_check(chain_only.health == 10000.0, "Secondary blast damage does not recursively explode")
	_check(simulation.primary_hits == 1 and simulation.secondary_hits == 1, "Primary and secondary hit accounting stays distinct")
	_check(activations.size() == 1, "A blast emits once without secondary recursion")
	if activations.size() == 1:
		_check(activations[0]["origin"] == primary.position and activations[0]["primary_hits"] == 1 and activations[0]["secondary_hits"] == 0, "Blast feedback starts at the real impact after primary damage and before the explosion")
		_check(activations[0]["rune"] == "blast" and (activations[0]["incoming_direction"] as Vector2).is_normalized() and activations[0]["outgoing_direction"] == Vector2.ZERO and not activations[0]["complete"], "Blast feedback retains incoming direction, ends its projectile and never starts after terminal state")

func _test_rune_activation_guards() -> void:
	var plain: CombatSim = _simulation()
	var plain_events: Array[Dictionary] = _rune_events(plain)
	_target(plain, Vector2(330, 300))
	plain.fire_weapon("bone", "", Vector2(200, 300), Vector2.RIGHT)
	_advance(plain, 60)
	_check(plain.has_signal("rune_activated"), "Combat exposes the read-only rune activation signal")
	_check(plain.primary_hits == 1 and plain_events.is_empty(), "Ordinary positive damage never emits rune activation")
	for rune_id: String in ["pierce", "bounce", "blast"]:
		var zero: CombatSim = _simulation()
		var zero_events: Array[Dictionary] = _rune_events(zero)
		_target(zero, Vector2(330, 300))
		_target(zero, Vector2(385, 300))
		_target(zero, Vector2(440, 300))
		var zero_shot: CombatSim.Shot = zero.fire_weapon("bone", rune_id, Vector2(200, 300), Vector2.RIGHT)
		zero_shot.damage = 0.0
		_advance(zero, 90)
		_check(zero.primary_hits == 0 and zero.secondary_hits == 0 and zero_events.is_empty(), "Zero-loss hits never activate " + rune_id + " feedback")
		var terminal: CombatSim = _simulation(8, 8)
		var terminal_events: Array[Dictionary] = _rune_events(terminal)
		terminal.boss.health = 1.0
		terminal.fire_weapon("bone", rune_id, terminal.boss.position, Vector2.RIGHT)
		terminal.step(DELTA, Vector2.ZERO)
		_check(terminal.complete and terminal.victory and terminal_events.is_empty(), "A lethal primary Boss hit does not begin terminal " + rune_id + " behavior")
		terminal.fire_weapon("bone", rune_id, terminal.boss.position, Vector2.RIGHT)
		terminal._update_shots(DELTA)
		_check(terminal_events.is_empty(), "Already-ended shots never emit " + rune_id + " feedback")
	var isolated: CombatSim = _simulation()
	var isolated_events: Array[Dictionary] = _rune_events(isolated)
	_target(isolated, Vector2(330, 300))
	isolated.fire_weapon("bone", "bounce", Vector2(200, 300), Vector2.RIGHT)
	_advance(isolated, 60)
	_check(isolated.primary_hits == 1 and isolated_events.is_empty(), "Bounce without an actual next target emits no redirection")
	for rune_id: String in ["pierce", "bounce"]:
		var exhausted: CombatSim = _simulation()
		var exhausted_events: Array[Dictionary] = _rune_events(exhausted)
		_target(exhausted, Vector2(330, 300))
		_target(exhausted, Vector2(385, 300))
		var shot: CombatSim.Shot = exhausted.fire_weapon("bone", rune_id, Vector2(200, 300), Vector2.RIGHT)
		shot.remaining = 0
		_advance(exhausted, 60)
		_check(exhausted.primary_hits == 1 and not shot.active and exhausted_events.is_empty(), "An exhausted " + rune_id + " does not claim continuation")
	var secondary: CombatSim = _simulation()
	var secondary_events: Array[Dictionary] = _rune_events(secondary)
	_target(secondary, Vector2(330, 300))
	secondary._explode(Vector2(330, 300), 10.0, "bone", {})
	_check(secondary.secondary_hits == 1 and secondary_events.is_empty(), "Secondary-only explosion damage never dispatches rune activation")
	var boss_blast: CombatSim = _simulation(8, 8)
	var boss_blast_events: Array[Dictionary] = _rune_events(boss_blast)
	boss_blast.boss.position = Vector2(385, 300)
	boss_blast.boss.health = 1.0
	boss_blast.boss.action_timer = 9999.0
	boss_blast.boss.slow_timer = 9999.0
	boss_blast.boss.slow_factor = 0.0
	var blast_primary: CombatSim.Enemy = _target(boss_blast, Vector2(330, 300))
	blast_primary.health = 1.0
	var pending_target: CombatSim.Enemy = _target(boss_blast, Vector2(800, 300))
	boss_blast.fire_weapon("bone", "blast", blast_primary.position, Vector2.RIGHT)
	boss_blast.fire_weapon("bone", "pierce", pending_target.position, Vector2.RIGHT)
	boss_blast.step(DELTA, Vector2.ZERO)
	_check(boss_blast.complete and boss_blast.victory and boss_blast.primary_hits == 1 and boss_blast.secondary_hits == 1, "Secondary blast can end the run before a pending rune projectile")
	_check(boss_blast_events.size() == 1 and boss_blast_events[0]["rune"] == "blast" and not boss_blast_events[0]["complete"], "The real explosion emits once before its secondary Boss kill")
	_advance(boss_blast, 3)
	_check(pending_target.health == 10000.0 and boss_blast_events.size() == 1, "Secondary Boss victory prevents all later rune damage and activation")
	for rune_id: String in ["pierce", "bounce", "blast"]:
		var observed: CombatSim = _simulation(717)
		var unobserved: CombatSim = _simulation(717)
		_rune_events(observed)
		for simulation: CombatSim in [observed, unobserved]:
			for index: int in range(3):
				_target(simulation, Vector2(330 + index * 55, 300))
			simulation.fire_weapon("bone", rune_id, Vector2(200, 300), Vector2.RIGHT)
			_advance(simulation, 90)
		_check(observed.snapshot() == unobserved.snapshot() and observed.run.summary() == unobserved.run.summary(), "A read-only rune listener does not change combat or run statistics: " + rune_id)
		_check(observed.run.rng.state == unobserved.run.rng.state, "Rune feedback never consumes random state: " + rune_id)

func _explosion_probe(use_linear: bool, boss_slot: int = -1) -> ExplosionProbeSim:
	var state: RunState = RunState.new()
	state.begin(9031, "bone")
	state.wave = 8 if boss_slot >= 0 else 1
	var sim: ExplosionProbeSim = ExplosionProbeSim.new()
	sim.use_linear = use_linear
	if boss_slot > 0:
		sim._enemy_free.erase(boss_slot)
		sim._enemy_free.append(boss_slot)
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(1050, 550)
	if sim.boss != null:
		sim.boss.position = Vector2(400, 320)
		sim.boss.health = 1.0
		sim.boss.action_timer = 9999.0
		sim.boss.slow_timer = 9999.0
		sim.boss.slow_factor = 0.0
	return sim

func _explosion_events(sim: CombatSim) -> Array:
	var events: Array = []
	sim.damage_dealt.connect(func(point: Vector2, amount: float, source: String, secondary: bool, uid: int) -> void:
		events.append(["damage", point, amount, source, secondary, uid])
	)
	sim.enemy_killed.connect(func(point: Vector2, color: Color) -> void: events.append(["kill", point, color]))
	sim.rune_activated.connect(func(id: String, point: Vector2, incoming: Vector2, outgoing: Vector2) -> void:
		events.append(["rune", id, point, incoming, outgoing])
	)
	sim.ended.connect(func(won: bool, reason: String) -> void: events.append(["ended", won, reason]))
	return events

func _explosion_digest(sim: CombatSim, events: Array) -> Dictionary:
	var health: Array = []
	var drops: Array = []
	var effects: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		health.append([enemy.slot, enemy.uid, enemy.active, enemy.health, enemy.position, enemy.radius])
	for soul: CombatSim.Soul in sim.souls:
		if soul.active:
			drops.append([soul.slot, soul.position, soul.value])
	for effect: CombatSim.Effect in sim.effects:
		effects.append([effect.position, effect.radius, effect.color, effect.life, effect.kind])
	return {"run": sim.run.summary(), "health": health, "drops": drops, "effects": effects, "events": events,
		"enemy_free": sim._enemy_free.duplicate(), "soul_free": sim._soul_free.duplicate(),
		"rng": sim.rng.state, "run_rng": sim.run.rng.state, "primary": sim.primary_hits,
		"secondary": sim.secondary_hits, "damage": sim.damage_by_weapon.duplicate(true),
		"enemy_count": sim.enemy_count, "shot_count": sim.shot_count, "soul_count": sim.soul_count}

func _test_explosion_spatial_equivalence() -> void:
	# Query through the real shot phase, including a radius larger than all resources,
	# a cell boundary, exact tangency, both sides of the strict edge and UID exclusion.
	var outcomes: Array[Dictionary] = []
	for use_linear: bool in [false, true]:
		var sim: ExplosionProbeSim = _explosion_probe(use_linear)
		var events: Array = _explosion_events(sim)
		var primary: CombatSim.Enemy = _target(sim, Vector2(400, 320))
		var large: CombatSim.Enemy = _target(sim, Vector2(550, 320))
		large.radius = 90.0
		var tangent: CombatSim.Enemy = _target(sim, Vector2(485, 320))
		var inside: CombatSim.Enemy = _target(sim, Vector2(484.999, 320))
		var outside: CombatSim.Enemy = _target(sim, Vector2(485.001, 320))
		var across: CombatSim.Enemy = _target(sim, Vector2(315.001, 320))
		for edge: CombatSim.Enemy in [tangent, inside, outside, across]:
			edge.radius = 17.0
		var excluded: CombatSim.Enemy = _target(sim, Vector2(400, 370))
		var shot: CombatSim.Shot = sim.fire_weapon("bone", "blast", primary.position, Vector2.RIGHT)
		shot.hit_ids[excluded.uid] = true
		sim.step(DELTA, Vector2.ZERO)
		_check(large.health < 10000.0 and inside.health < 10000.0 and across.health < 10000.0, "Blast broad phase includes large radii, near edges and neighboring cells")
		_check(tangent.health == 10000.0 and outside.health == 10000.0 and excluded.health == 10000.0, "Blast preserves strict tangency/outside rejection and UID exclusion")
		_check(primary.health == 9986.0 and sim.secondary_hits == 3 and not sim._explosion_grid_active, "Blast excludes its primary and closes the grid query window after the step")
		outcomes.append(_explosion_digest(sim, events))
	_check(outcomes[0] == outcomes[1], "Spatial blast matches linear events, HP, damage, drops, effects and RNG across boundary cases")
	# Direct calls must remain correct without a grid and after external pose/radius edits.
	for grid_state: int in range(3):
		outcomes.clear()
		for use_linear: bool in [false, true]:
			var sim: ExplosionProbeSim = _explosion_probe(use_linear)
			var events: Array = _explosion_events(sim)
			var moved: CombatSim.Enemy = _target(sim, Vector2(1000, 500))
			if grid_state == 1:
				sim._rebuild_grid()
			elif grid_state == 2:
				sim.step(DELTA, Vector2.ZERO)
			moved.position = Vector2(580, 320)
			moved.radius = 120.0
			sim._explode(Vector2(400, 320), 3.0, "ember", {})
			_check(moved.health == 9997.0, "Direct blast respects current position/radius with grid state " + str(grid_state))
			outcomes.append(_explosion_digest(sim, events))
		_check(outcomes[0] == outcomes[1], "Direct stale/empty-grid blast remains equivalent: " + str(grid_state))
	var empty: ExplosionProbeSim = _explosion_probe(false)
	empty._explode(Vector2(400, 320), 3.0, "ember", {})
	_check(empty.secondary_hits == 0 and empty.effects.size() == 1, "An empty direct blast retains its effect without phantom hits")
	# A spawn after grid construction reuses an old slot at a new position and UID.
	outcomes.clear()
	for use_linear: bool in [false, true]:
		var sim: ExplosionProbeSim = _explosion_probe(use_linear)
		var events: Array = _explosion_events(sim)
		var primary: CombatSim.Enemy = _target(sim, Vector2(330, 320))
		var retired: CombatSim.Enemy = _target(sim, Vector2(1000, 500))
		var old_uid: int = retired.uid
		var old_slot: int = retired.slot
		sim.apply_damage(retired, 10000.0, "frost")
		sim.spawn_after_grid = Vector2(370, 320)
		var shot: CombatSim.Shot = sim.fire_weapon("bone", "blast", primary.position, Vector2.RIGHT)
		shot.hit_ids[old_uid] = true
		sim.step(DELTA, Vector2.ZERO)
		_check(sim.deferred_enemy.slot == old_slot and sim.deferred_enemy.uid != old_uid and sim.deferred_enemy.health < 10000.0, "A post-grid recycled slot is hit under its new UID and position")
		outcomes.append(_explosion_digest(sim, events))
	_check(outcomes[0] == outcomes[1], "Post-grid spawning falls back without changing pool, drop or damage ordering")
	# A maximum-radius enemy dying earlier in the same shot phase only leaves a
	# conservative query bound; its stale bucket entry must not be hit again.
	outcomes.clear()
	for use_linear: bool in [false, true]:
		var sim: ExplosionProbeSim = _explosion_probe(use_linear)
		var events: Array = _explosion_events(sim)
		var largest: CombatSim.Enemy = _target(sim, Vector2(550, 320))
		largest.radius = 90.0
		largest.health = 1.0
		var primary: CombatSim.Enemy = _target(sim, Vector2(400, 320))
		var neighbor: CombatSim.Enemy = _target(sim, Vector2(450, 320))
		sim.fire_weapon("bone", "", largest.position, Vector2.UP)
		sim.fire_weapon("bone", "blast", primary.position, Vector2.RIGHT)
		sim.step(DELTA, Vector2.ZERO)
		_check(sim.run.kills == 1 and sim.primary_hits == 2 and sim.secondary_hits == 1 and is_equal_approx(neighbor.health, 9992.3), "A stale largest-radius bucket neither duplicates its kill nor omits a surviving neighbor")
		outcomes.append(_explosion_digest(sim, events))
	_check(outcomes[0] == outcomes[1], "An earlier maximum-radius death preserves linear blast results and ordering")
	# Boss first versus Boss after lower pool slots must preserve the old terminal cut.
	for boss_slot: int in [0, 5]:
		outcomes.clear()
		for use_linear: bool in [false, true]:
			var sim: ExplosionProbeSim = _explosion_probe(use_linear, boss_slot)
			var events: Array = _explosion_events(sim)
			for index: int in 7:
				var neighbor: CombatSim.Enemy = _target(sim, Vector2(330, 320) + Vector2.from_angle(float(index) * TAU / 7.0) * 55.0)
				neighbor.health = 1.0
			var primary: CombatSim.Enemy = _target(sim, Vector2(330, 320))
			primary.health = 1.0
			sim.fire_weapon("bone", "blast", primary.position, Vector2.RIGHT)
			sim.step(DELTA, Vector2.ZERO)
			var expected_kills: int = 2 if boss_slot == 0 else 7
			_check(sim.complete and sim.victory and sim.run.kills == expected_kills and sim.run.gold == expected_kills, "Boss terminal blast retains lower-slot kills/drops only: " + str(boss_slot))
			outcomes.append(_explosion_digest(sim, events))
		_check(outcomes[0] == outcomes[1], "Spatial ordering exactly matches the linear Boss terminal sequence: " + str(boss_slot))

func _test_nearest_spatial_equivalence() -> void:
	# Exercise the actual fresh-grid window, with an independent frozen full scan.
	# Test-only frozen positions also cover negative/out-of-arena grid cells.
	for seed_value: int in range(10):
		var sim: ExplosionProbeSim = _explosion_probe(false)
		sim.freeze_enemy_updates = true
		var samples: RandomNumberGenerator = RandomNumberGenerator.new()
		samples.seed = 7001 + seed_value
		for index: int in 160:
			_target(sim, Vector2(samples.randf_range(-250.0, 1450.0), samples.randf_range(-200.0, 850.0)))
		for index: int in 128:
			var excluded: Dictionary = {}
			for omitted: int in range(index % 7):
				excluded[sim.enemies[samples.randi_range(0, 159)].uid] = true
			var radii: Array[float] = [0.0, 0.001, 79.999, 80.0, 80.001, -230.0, 420.0, 620.0, 1280.0, 2000.0]
			sim.nearest_queries.append({"position": Vector2(samples.randf_range(-400.0, 1600.0), samples.randf_range(-350.0, 1000.0)), "range": radii[index % radii.size()], "excluded": excluded})
		sim.step(DELTA, Vector2.ZERO)
		_check(sim.nearest_results == sim.nearest_reference, "Ring queries equal the frozen oracle for 128 positions/ranges/exclusions: seed " + str(seed_value))
		_check(sim.nearest_grid_flags.count(true) == 128 and sim.nearest_rng_unchanged, "Randomized nearest queries use a fresh grid without RNG calls")
	# The lower-slot tie is in the next ring. A 64-bit pruning square can exceed
	# Vector2's rounded best distance here and incorrectly return the higher slot.
	var rounded: ExplosionProbeSim = _explosion_probe(false)
	rounded.freeze_enemy_updates = true
	var low: CombatSim.Enemy = _target(rounded, Vector2(80, 40))
	var high: CombatSim.Enemy = _target(rounded, Vector2(79.399993896484375, 40))
	var rounded_origin: Vector2 = Vector2(79.7, 40)
	_check(low.position.distance_squared_to(rounded_origin) == high.position.distance_squared_to(rounded_origin), "Float boundary fixture has an exact Vector2 distance tie")
	rounded.nearest_queries = [{"position": rounded_origin, "range": 2.0}]
	rounded.step(DELTA, Vector2.ZERO)
	_check(rounded.nearest_results == [low.uid] and rounded.nearest_results == rounded.nearest_reference, "A rounded next-ring tie still chooses the original lower slot")
	var edges: ExplosionProbeSim = _explosion_probe(false)
	edges.freeze_enemy_updates = true
	var first: CombatSim.Enemy = _target(edges, Vector2(-80, 0))
	_target(edges, Vector2(0, 80))
	_target(edges, Vector2(80, 0))
	_target(edges, Vector2(0, -80))
	edges.nearest_queries = [
		{"position": Vector2.ZERO, "range": 80.0},
		{"position": Vector2.ZERO, "range": -80.0},
		{"position": Vector2.ZERO, "range": 80.001},
		{"position": first.position, "range": 0.0},
		{"position": Vector2.ZERO, "range": -80.001},
		{"position": Vector2.ZERO, "range": 81.0, "excluded": {first.uid: true}},
		{"position": Vector2(80, 80), "range": 100.0},
		{"position": Vector2(5000, 5000), "range": 420.0},
		{"position": Vector2.ZERO, "range": INF},
		{"position": Vector2.ZERO, "range": NAN},
	]
	edges.step(DELTA, Vector2.ZERO)
	_check(edges.nearest_results == edges.nearest_reference, "Exact corners, negative cells, wide/NaN/INF ranges and exclusions preserve linear choices")
	_check(edges.nearest_results[0] == -1 and edges.nearest_results[1] == -1 and edges.nearest_results[3] == -1, "Strict range tangency and zero range never select an enemy")
	_check(edges.nearest_results[2] == first.uid and edges.nearest_results[4] == first.uid, "Positive and negative range use the same strict radius and slot tie")
	# Dead entries remain in buckets but must lose to the next active candidate.
	var dead: ExplosionProbeSim = _explosion_probe(false)
	dead.freeze_enemy_updates = true
	var removed: CombatSim.Enemy = _target(dead, Vector2(400, 320))
	var survivor: CombatSim.Enemy = _target(dead, Vector2(450, 320))
	dead.nearest_kill_slot = removed.slot
	dead.nearest_queries = [{"position": removed.position, "range": 100.0}, {"position": removed.position, "range": 100.0, "excluded": {survivor.uid: true}}]
	dead.step(DELTA, Vector2.ZERO)
	_check(dead.nearest_results == [survivor.uid, -1] and dead.nearest_results == dead.nearest_reference, "Nearest ignores stale inactive entries and excluded surviving UIDs")
	# Recycled post-grid spawns invalidate the window, retaining current UID/position.
	var spawned: ExplosionProbeSim = _explosion_probe(false)
	spawned.freeze_enemy_updates = true
	var retired: CombatSim.Enemy = _target(spawned, Vector2(900, 500))
	var old_uid: int = retired.uid
	spawned.apply_damage(retired, retired.health, "bone")
	spawned.spawn_after_grid = Vector2(-20, -30)
	spawned.nearest_queries = [{"position": Vector2(-20, -30), "range": 10.0, "excluded": {old_uid: true}}]
	spawned.step(DELTA, Vector2.ZERO)
	_check(spawned.nearest_grid_flags == [false] and spawned.nearest_results == [spawned.deferred_enemy.uid] and spawned.nearest_results == spawned.nearest_reference, "Post-grid spawn falls back and does not confuse a new UID with its recycled slot")
	# External calls after a pose edit must never trust a previously built grid.
	for phase: int in range(3):
		var external: ExplosionProbeSim = _explosion_probe(false)
		var moved: CombatSim.Enemy = _target(external, Vector2(900, 500))
		if phase == 1:
			external._rebuild_grid()
		elif phase == 2:
			external.step(DELTA, Vector2.ZERO)
		moved.position = Vector2(-100, -100)
		_check(external._nearest(moved.position, 1.0) == moved and external._nearest(moved.position, 1.0) == external._nearest_oracle(moved.position, 1.0, {}), "Direct nearest uses current positions with stale/empty grid phase " + str(phase))

func _test_soul_accounting() -> void:
	var simulation: CombatSim = _simulation()
	var chaser: CombatSim.Enemy = simulation.spawn_enemy("chaser", Vector2(300, 200))
	var tank: CombatSim.Enemy = simulation.spawn_enemy("tank", Vector2(500, 200))
	simulation.apply_damage(chaser, 1000.0, "bone")
	simulation.apply_damage(tank, 1000.0, "bone")
	_check(simulation.run.kills == 2 and simulation.soul_count == 2, "Kills create one pickup object per enemy")
	_check(simulation.run.gold == 0, "Distant uncollected drops do not credit currency prematurely")
	simulation.collect_remaining_souls()
	_check(simulation.run.gold == 4 and simulation.run.xp == 4, "Wave cleanup credits chaser1 plus tank3 to currency and experience")
	_check(simulation.soul_count == 0, "Wave cleanup releases every pickup")
	simulation.collect_remaining_souls()
	_check(simulation.run.gold == 4, "Repeated cleanup cannot double-credit souls")
	var pressure: CombatSim = _simulation()
	for index: int in range(CombatSim.DROP_LIMIT + 3):
		pressure._drop_soul(Vector2(300, 200), 1)
	_check(pressure.soul_count == CombatSim.DROP_LIMIT and pressure.run.gold == 3, "Full pickup pool credits overflow instead of deleting income")
	pressure.collect_remaining_souls()
	_check(pressure.run.gold == CombatSim.DROP_LIMIT + 3 and pressure.soul_count == 0, "Overflow and existing pickups reconcile exactly")
	var collected: CombatSim = _simulation()
	collected._drop_soul(collected.player_position, 5)
	collected.step(DELTA, Vector2.ZERO)
	_check(collected.run.gold == 5 and collected.soul_count == 0, "Nearby pickups use the normal simulation collection path")

func _test_wave_outcomes() -> void:
	var normal: CombatSim = _simulation()
	normal.sandbox = false
	normal._spawn_timer = 9999.0
	normal.elapsed = normal.duration - 0.001
	normal._drop_soul(Vector2(300, 200), 3)
	normal.step(DELTA, Vector2.ZERO)
	_check(normal.complete and normal.victory, "Surviving a normal wave timer wins the wave")
	_check(normal.run.gold == 3 and normal.soul_count == 0, "Normal wave victory collects remaining souls")
	var before: float = normal.elapsed
	normal.step(1.0, Vector2.RIGHT)
	_check(normal.elapsed == before, "Completed simulation stops advancing")
	var dead: CombatSim = _simulation()
	dead.run.health = 0.0
	dead.step(DELTA, Vector2.ZERO)
	_check(dead.complete and not dead.victory, "Zero player health loses the wave")
	var timeout: CombatSim = _simulation(2, 8)
	_check(timeout.boss != null and timeout.boss.active and timeout.duration == 90.0, "Final wave spawns its boss with a 90-second deadline")
	timeout.sandbox = false
	timeout._spawn_timer = 9999.0
	timeout.elapsed = timeout.duration - 0.001
	timeout.step(DELTA, Vector2.ZERO)
	_check(timeout.complete and not timeout.victory and timeout.boss.active, "Surviving the boss deadline without a kill is a loss")
	var killed: CombatSim = _simulation(2, 8)
	killed.apply_damage(killed.boss, killed.boss.max_health, "bone")
	_check(killed.complete and killed.victory and not killed.boss.active, "Boss death is the final-wave victory condition")
	_check(killed.run.kills == 1 and killed.soul_count == 0 and killed.run.gold == 1, "Boss victory accounts its kill and remaining soul")

func _test_seed_reproduction() -> void:
	var first: CombatSim = _simulation(717)
	var second: CombatSim = _simulation(717)
	first.sandbox = false
	second.sandbox = false
	for index: int in range(180):
		var movement: Vector2 = Vector2.RIGHT.rotated(float(index) * 0.013)
		first.step(DELTA, movement)
		second.step(DELTA, movement)
	_check(first.snapshot() == second.snapshot(), "Same seed and movement reproduce the combat snapshot")
	_check(first.player_position == second.player_position and first.enemy_count == second.enemy_count, "Seed reproduction includes player movement and spawns")
	var positions_match: bool = true
	for index: int in range(CombatSim.ENEMY_LIMIT):
		if first.enemies[index].active != second.enemies[index].active:
			positions_match = false
		if first.enemies[index].active and first.enemies[index].position != second.enemies[index].position:
			positions_match = false
	_check(positions_match, "Enemy trajectories reproduce from the same seed")

func _test_outcome_ordering() -> void:
	# Low boss health here isolates event ordering; campaign runs never alter it.
	var already_dead: CombatSim = _simulation(8, 8)
	already_dead.run.health = 0.0
	already_dead.boss.health = 1.0
	already_dead.fire_weapon("bone", "", already_dead.boss.position, Vector2.RIGHT)
	already_dead.step(DELTA, Vector2.ZERO)
	_check(already_dead.complete and not already_dead.victory, "A dead player cannot shoot the boss and win in the same step")
	_check(already_dead.boss.active, "Death ends the step before processing a pending lethal player shot")
	var contact: CombatSim = _simulation(8, 8)
	contact.player_position = Vector2(1050, 550)
	contact.run.health = 1.0
	contact.boss.health = 1.0
	_target(contact, contact.player_position)
	contact.fire_weapon("bone", "", contact.boss.position, Vector2.RIGHT)
	contact.step(DELTA, Vector2.ZERO)
	_check(contact.complete and not contact.victory and contact.boss.active, "Lethal enemy contact resolves before player weapon damage")
	var hostile_first: CombatSim = _simulation(8, 8)
	hostile_first.player_position = Vector2(1050, 550)
	hostile_first.run.health = 1.0
	hostile_first.boss.health = 1.0
	hostile_first._hostile_shot(hostile_first.player_position, Vector2.ZERO, 10.0)
	hostile_first.fire_weapon("bone", "", hostile_first.boss.position, Vector2.RIGHT)
	hostile_first.step(DELTA, Vector2.ZERO)
	_check(hostile_first.complete and not hostile_first.victory and hostile_first.boss.active, "Lethal hostile projectile cannot be followed by a postmortem boss kill")
	var boss_first: CombatSim = _simulation(8, 8)
	boss_first.player_position = Vector2(1050, 550)
	boss_first.boss.health = 1.0
	boss_first.fire_weapon("bone", "", boss_first.boss.position, Vector2.RIGHT)
	boss_first._hostile_shot(boss_first.player_position, Vector2.ZERO, 1000.0)
	boss_first.step(DELTA, Vector2.ZERO)
	_check(boss_first.complete and boss_first.victory, "A boss kill resolves victory before later enemy projectile updates")
	_check(boss_first.run.health > 0.0, "Later hostile shots cannot damage the player after victory")

func _first_hostile(simulation: CombatSim) -> CombatSim.Shot:
	for shot: CombatSim.Shot in simulation.shots:
		if shot.active and shot.hostile:
			return shot
	return null

func _test_contact_recoil() -> void:
	for behavior: String in ["chaser", "rusher", "rusher_charge", "tank", "caster", "boss"]:
		var sim: CombatSim = _simulation(431, 3)
		sim.player_position = Vector2(640, 365)
		var id: String = "rusher" if behavior == "rusher_charge" else behavior
		var enemy: CombatSim.Enemy = sim.spawn_enemy(id, Vector2(660, 365))
		enemy.action_timer = 9999.0
		if behavior == "rusher_charge":
			enemy.mode = 2
			enemy.charge_direction = Vector2.DOWN
		var hits: Array[Dictionary] = []
		sim.player_damaged.connect(func(amount: float, source: String, kind: String, origin: Vector2) -> void:
			hits.append({"amount": amount, "source": source, "kind": kind, "origin": origin})
		)
		sim.step(DELTA, Vector2.ZERO)
		_check(hits.size() == 1 and sim.run.hits_taken == 1 and is_equal_approx(sim.run.damage_taken, enemy.definition.damage * 1.18), "Contact recoil preserves actual damage and hit count: " + behavior)
		if hits.size() == 1:
			var origin: Vector2 = hits[0]["origin"]
			var recoil: Vector2 = enemy.position - origin
			_check(is_equal_approx(recoil.length(), 18.0) and recoil.normalized().dot((origin - sim.player_position).normalized()) > 0.9999, "Contact recoil moves radially away, independently of pursuit/retreat/charge: " + behavior)
			_check(enemy.position.distance_to(sim.player_position) > origin.distance_to(sim.player_position), "Contact recoil increases separation from the player: " + behavior)
			_check(hits[0]["source"] == id and hits[0]["kind"] == "contact" and is_equal_approx(float(hits[0]["amount"]), enemy.definition.damage * 1.18), "Contact feedback keeps source, origin and scaled damage: " + behavior)
	var edge_cases: Array[Dictionary] = [
		{"player": Vector2(82, 365), "enemy": Vector2(67, 365)},
		{"player": Vector2(1198, 365), "enemy": Vector2(1213, 365)},
		{"player": Vector2(640, 156), "enemy": Vector2(640, 141)},
		{"player": Vector2(640, 574), "enemy": Vector2(640, 589)},
	]
	for fixture: Dictionary in edge_cases:
		var sim: CombatSim = _simulation()
		sim.player_position = fixture["player"]
		var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", fixture["enemy"])
		enemy.action_timer = 9999.0
		sim.step(DELTA, Vector2.ZERO)
		var bounds: Rect2 = CombatSim.ARENA
		_check(enemy.position.x >= bounds.position.x and enemy.position.x <= bounds.end.x and enemy.position.y >= bounds.position.y and enemy.position.y <= bounds.end.y, "Post-contact recoil remains inside every arena edge")
		_check(sim.run.hits_taken == 1 and sim.run.health == 92.0, "Arena clamping does not cancel contact damage")
	var overlap: CombatSim = _simulation()
	overlap.player_position = Vector2(640, 365)
	var coincident: CombatSim.Enemy = overlap.spawn_enemy("chaser", overlap.player_position)
	coincident.action_timer = 9999.0
	overlap.step(DELTA, Vector2.ZERO)
	_check(coincident.position.is_finite() and coincident.position == overlap.player_position and overlap.run.health == 92.0, "Exact overlap keeps a finite zero recoil direction and normal contact damage")
	for distance: float in [100.0, 200.0, 300.0]:
		var sim: CombatSim = _simulation()
		sim.player_position = Vector2(640, 365)
		var start: Vector2 = sim.player_position + Vector2(distance, 0)
		var caster: CombatSim.Enemy = sim.spawn_enemy("caster", start)
		caster.action_timer = 9999.0
		sim.step(DELTA, Vector2.ZERO)
		_check(caster.position.is_equal_approx(CombatSim.clamp_point(start + caster.velocity * DELTA)) and sim.run.hits_taken == 0 and sim.run.health == 100.0, "Non-contact caster motion has no added recoil: distance " + str(distance))
		_check(caster.position.distance_to(sim.player_position) > distance if distance < 160.0 else (caster.velocity == Vector2.ZERO if distance < 250.0 else caster.position.distance_to(sim.player_position) < distance), "Caster retreat/hold/pursuit behavior is unchanged: distance " + str(distance))
	for id: String in ["chaser", "rusher", "tank"]:
		var sim: CombatSim = _simulation()
		sim.player_position = Vector2(640, 365)
		var start: Vector2 = Vector2(840, 365)
		var enemy: CombatSim.Enemy = sim.spawn_enemy(id, start)
		enemy.action_timer = 9999.0
		sim.step(DELTA, Vector2.ZERO)
		_check(enemy.position.is_equal_approx(CombatSim.clamp_point(start + enemy.velocity * DELTA)) and sim.run.hits_taken == 0, "Non-contact pursuit is unchanged: " + id)
	var invulnerable: CombatSim = _simulation()
	invulnerable.player_position = Vector2(640, 365)
	invulnerable.invulnerability = 0.5
	var untouched: CombatSim.Enemy = invulnerable.spawn_enemy("caster", Vector2(660, 365))
	untouched.action_timer = 9999.0
	var start: Vector2 = untouched.position
	invulnerable.step(DELTA, Vector2.ZERO)
	_check(untouched.position.is_equal_approx(start + untouched.velocity * DELTA) and invulnerable.run.hits_taken == 0, "Existing invulnerability suppresses both contact damage and recoil")

func _test_caster_aim() -> void:
	var close: CombatSim = _simulation()
	close.player_position = Vector2(640, 365)
	var retreating: CombatSim.Enemy = close.spawn_enemy("caster", Vector2(640, 465))
	retreating.action_timer = 0.0
	var initial_distance: float = retreating.position.distance_to(close.player_position)
	close.step(DELTA, Vector2.ZERO)
	var close_shot: CombatSim.Shot = _first_hostile(close)
	_check(close_shot != null, "Close-range caster emits its projectile")
	if close_shot == null:
		return
	_check(close_shot.velocity.y < 0.0, "Retreating caster aims toward the player instead of its movement direction")
	_check(is_equal_approx(close_shot.velocity.length(), retreating.definition.projectile_speed), "Close-range projectile uses its resource speed")
	_check(retreating.position.y > 465.0 and retreating.position.distance_to(close.player_position) > initial_distance, "Caster retreats while independently aiming at the player")
	_check(is_equal_approx(retreating.action_timer, retreating.definition.cooldown), "Caster resets its attack timer from resource cooldown")
	var far: CombatSim = _simulation()
	far.player_position = Vector2(640, 365)
	var approaching: CombatSim.Enemy = far.spawn_enemy("caster", Vector2(1000, 365))
	approaching.action_timer = 0.0
	var distant_before: float = approaching.position.distance_to(far.player_position)
	far.step(DELTA, Vector2.ZERO)
	var far_shot: CombatSim.Shot = _first_hostile(far)
	_check(far_shot != null, "Distant caster emits its projectile")
	if far_shot == null:
		return
	_check(far_shot.velocity.x < 0.0, "Distant caster aims toward the player")
	_check(is_equal_approx(far_shot.velocity.length(), approaching.definition.projectile_speed), "Distant projectile uses its resource speed")
	_check(approaching.position.distance_to(far.player_position) < distant_before, "Distant caster approaches the player while firing")
	_check(is_equal_approx(approaching.action_timer, approaching.definition.cooldown), "Distant caster uses resource cooldown")

func _test_ember_homing() -> void:
	var definition: ContentDef = GameCatalog.weapon("ember")
	_check(definition.homing > 0.0, "Ember resource enables homing")
	var simulation: CombatSim = _simulation()
	var origin: Vector2 = Vector2(250, 250)
	var target: CombatSim.Enemy = _target(simulation, Vector2(500, 310))
	var initial_alignment: float = Vector2.RIGHT.dot((target.position - origin).normalized())
	var shot: CombatSim.Shot = simulation.fire_weapon("ember", "", origin, Vector2.RIGHT)
	simulation.step(DELTA, Vector2.ZERO)
	_check(shot.velocity.y > 0.0, "Ember velocity turns toward an off-axis target")
	_check(shot.velocity.normalized().dot((target.position - origin).normalized()) > initial_alignment, "Homing improves alignment with the target")
	_check(is_equal_approx(shot.velocity.length(), definition.projectile_speed), "Homing preserves the configured projectile speed")
	_advance(simulation, 20)
	_check(shot.position.y > origin.y + 1.0, "Ember follows a curved trajectory instead of staying on its initial line")
	var control: CombatSim = _simulation()
	_target(control, Vector2(500, 310))
	var straight: CombatSim.Shot = control.fire_weapon("bone", "", origin, Vector2.RIGHT)
	_advance(control, 21)
	_check(is_zero_approx(straight.velocity.y) and is_equal_approx(straight.position.y, origin.y), "Non-homing weapon retains its straight trajectory")
	var pierced: CombatSim = _simulation()
	var first: CombatSim.Enemy = _target(pierced, Vector2(330, 300))
	_target(pierced, Vector2(470, 400))
	var penetrating: CombatSim.Shot = pierced.fire_weapon("ember", "pierce", Vector2(250, 300), Vector2.RIGHT)
	for frame: int in range(45):
		if penetrating.hit_ids.has(first.uid):
			break
		pierced.step(DELTA, Vector2.ZERO)
	_check(first.active and penetrating.hit_ids.has(first.uid), "Homing exclusion scenario records an actual hit on a surviving enemy")
	_check(penetrating.active, "Piercing ember remains active after its first hit")
	var vertical_before: float = penetrating.velocity.y
	pierced.step(DELTA, Vector2.ZERO)
	_check(penetrating.velocity.y > vertical_before + 0.1, "Piercing ember turns toward an unhit enemy instead of the nearer previously hit enemy")
	_check(is_equal_approx(first.health, 10000.0 - definition.damage), "Previously hit enemy does not receive a repeat hit during homing")

func _test_damage_accounting() -> void:
	var sim: CombatSim = _simulation()
	var records: Array[Dictionary] = []
	var changes: Array[int] = [0]
	var old_hits: Array[int] = [0]
	sim.run.changed.connect(func() -> void: changes[0] += 1)
	sim.enemy_hit.connect(func() -> void: old_hits[0] += 1)
	sim.damage_dealt.connect(func(point: Vector2, amount: float, source: String, secondary: bool, target_uid: int) -> void:
		records.append({"position": point, "amount": amount, "source": source, "secondary": secondary, "target_uid": target_uid})
	)
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", Vector2(400, 300))
	var original_health: float = enemy.health
	sim.apply_damage(enemy, 5.0, "bone")
	sim.apply_damage(enemy, 1000.0, "ember")
	_check(records.size() == 2 and old_hits[0] == 2, "Real damage emits new and compatible legacy hit signals")
	_check(records[0]["amount"] == 5.0 and records[1]["amount"] == original_health - 5.0, "Damage events report actual health loss including lethal overkill")
	_check(sim.run.damage_dealt_by_weapon == {"bone": 5.0, "ember": original_health - 5.0}, "Run damage totals attribute actual damage to each weapon")
	_check(records[0]["position"] == Vector2(400, 300) and records[0]["source"] == "bone" and not records[0]["secondary"], "Damage event contains world position and primary source")
	_check(records[0]["target_uid"] == enemy.uid and records[1]["target_uid"] == enemy.uid, "Primary damage events retain the same real target identity through a lethal hit")
	var survivor: CombatSim.Enemy = sim.spawn_enemy("chaser", Vector2(500, 300))
	sim.apply_damage(survivor, 0.0, "zero")
	sim.apply_damage(survivor, -2.0, "negative")
	_check(records.size() == 2 and not sim.run.damage_dealt_by_weapon.has("zero") and not sim.run.damage_dealt_by_weapon.has("negative"), "Zero-loss attacks create neither damage events nor totals")
	sim._explode(survivor.position, 2.0, "frost", {})
	_check(records.size() == 3 and records[2]["secondary"] and records[2]["source"] == "frost", "Secondary damage retains its weapon and event classification")
	_check(changes[0] == 0, "Outgoing damage accounting does not emit RunState.changed")
	sim.run.next_wave()
	var next: CombatSim = CombatSim.new()
	next.begin(sim.run)
	var next_target: CombatSim.Enemy = next.spawn_enemy("chaser", Vector2(400, 300))
	next.apply_damage(next_target, 3.0, "frost")
	_check(sim.run.damage_dealt_by_weapon["frost"] == 5.0 and next.damage_by_weapon["frost"] == 3.0, "Damage aggregates across waves while local diagnostics remain per-wave")

func _test_damage_sources() -> void:
	var sim: CombatSim = _simulation()
	var events: Array[Dictionary] = []
	var legacy: Array[int] = [0]
	sim.player_hurt.connect(func() -> void: legacy[0] += 1)
	sim.player_damaged.connect(func(amount: float, source_id: String, kind: String, origin: Vector2) -> void:
		events.append({"amount": amount, "source_id": source_id, "kind": kind, "origin": origin})
	)
	sim._hurt_player(12.0, "caster", "projectile", Vector2(400, 300))
	_check(events.size() == 1 and legacy[0] == 1 and events[0] == {"amount": 12.0, "source_id": "caster", "kind": "projectile", "origin": Vector2(400, 300)}, "Damage feedback reports actual loss, source, kind, and origin")
	sim._hurt_player(20.0, "boss", "ritual")
	sim.invulnerability = 0.0
	sim._hurt_player(0.0, "boss", "ritual")
	_check(events.size() == 1 and legacy[0] == 1 and sim.run.hits_taken == 1 and sim.run.damage_taken == 12.0, "Invulnerability and zero-loss attacks emit no damage feedback or counters")
	_check(sim.invulnerability == 0.0, "A zero-loss attack does not start invulnerability")
	for kind: String in ["contact", "projectile", "ritual"]:
		var fatal: CombatSim = _simulation()
		fatal.player_position = Vector2(1000, 550)
		fatal.run.health = 3.0
		var source: String = "rusher" if kind == "contact" else ("caster" if kind == "projectile" else "boss")
		if kind == "contact":
			var touching: CombatSim.Enemy = fatal.spawn_enemy(source, fatal.player_position + Vector2(5, 0))
			touching.action_timer = 9999.0
		elif kind == "projectile":
			fatal._hostile_shot(fatal.player_position, Vector2.ZERO, 100.0, source)
		else:
			var zone: CombatSim.WarningZone = CombatSim.WarningZone.new()
			zone.position = fatal.player_position
			zone.delay = 0.0
			fatal.zones.append(zone)
		fatal.step(DELTA, Vector2.ZERO)
		_check(fatal.complete and not fatal.victory and fatal.run.last_hit["source_id"] == source and fatal.run.last_hit["kind"] == kind, "Fatal " + kind + " retains the real attacker")
		_check(fatal.run.damage_taken == 3.0 and fatal.run.hits_taken == 1 and fatal.run.last_hit["amount"] == 3.0, "Fatal " + kind + " only counts remaining health")
		_check(is_equal_approx(float(fatal.run.last_hit["elapsed"]), DELTA) and fatal.run.last_hit["wave"] == 1, "Fatal " + kind + " records simulation time and wave")
		var attack_label: String = str({"contact": "接触", "projectile": "弹丸", "ritual": "仪式"}[kind])
		_check(fatal.end_reason.contains(GameCatalog.enemy(source).display_name) and fatal.end_reason.contains(attack_label), "Fatal " + kind + " explains the attacker and attack type")
	var pool: CombatSim = _simulation()
	pool._hostile_shot(Vector2(300, 250), Vector2.RIGHT, 5.0, "boss")
	var hostile: CombatSim.Shot = _first_hostile(pool)
	_check(hostile.attacker_id == "boss", "Hostile projectile stores its attacker id")
	var slot: int = hostile.slot
	pool._release_shot(hostile)
	var friendly: CombatSim.Shot = pool.fire_weapon("bone", "", Vector2(300, 250), Vector2.RIGHT)
	_check(friendly.slot == slot and friendly.attacker_id.is_empty(), "Friendly reuse clears the previous hostile attacker")
	pool._release_shot(friendly)
	pool._hostile_shot(Vector2(300, 250), Vector2.RIGHT, 5.0, "caster")
	_check(_first_hostile(pool).attacker_id == "caster", "Hostile reuse replaces the previous attacker")
	pool._release_shot(_first_hostile(pool))
	pool._hostile_shot(Vector2(300, 250), Vector2.RIGHT, 5.0)
	_check(_first_hostile(pool).attacker_id == "enemy", "Default hostile attacker remains backwards compatible")

func _test_terminal_damage_freeze() -> void:
	for rune: String in ["blast", "pierce"]:
		var sim: CombatSim = _simulation(8, 8)
		sim.boss.health = 1.0
		var neighbor: CombatSim.Enemy = sim.spawn_enemy("tank", sim.boss.position + Vector2(55 if rune == "blast" else 25, 0))
		neighbor.health = 1.0
		neighbor.slow_timer = 9999.0
		neighbor.slow_factor = 0.0
		var captured: Array[Dictionary] = []
		var on_end: Callable = func(_won: bool, _reason: String) -> void: captured.append(sim.run.summary())
		sim.ended.connect(on_end)
		sim.fire_weapon("bone", rune, sim.boss.position, Vector2.RIGHT)
		sim.step(DELTA, Vector2.ZERO)
		sim.ended.disconnect(on_end)
		_check(sim.complete and sim.victory and neighbor.active, "Lethal boss " + rune + " does not dispatch further damage")
		_check(captured.size() == 1 and sim.run.summary() == captured[0], "Boss " + rune + " leaves terminal run statistics unchanged after ended")
		_check(sim.run.kills == 1 and sim.run.gold == 1 and sim.soul_count == 0 and sim.run.damage_dealt_by_weapon["bone"] == 1.0, "Boss " + rune + " does not create post-victory drops or damage totals")
		sim.apply_damage(neighbor, 100.0, "ember")
		_check(neighbor.active and sim.run.summary() == captured[0], "Completed combat rejects external damage dispatch")
	var secondary: CombatSim = _simulation(8, 8)
	secondary.boss.health = 1.0
	var primary: CombatSim.Enemy = _target(secondary, secondary.boss.position + Vector2(55, 0))
	var spectator: CombatSim.Enemy = secondary.spawn_enemy("chaser", secondary.boss.position + Vector2(90, 0))
	spectator.health = 1.0
	spectator.slow_timer = 9999.0
	spectator.slow_factor = 0.0
	secondary.fire_weapon("bone", "blast", primary.position, Vector2.RIGHT)
	secondary.step(DELTA, Vector2.ZERO)
	_check(secondary.complete and secondary.victory and spectator.active, "Explosion stops when a secondary hit kills the boss")
	_check(secondary.run.kills == 1 and secondary.run.gold == 1 and secondary.soul_count == 0, "Secondary boss victory cannot leave later explosion kills unsettled")

func _test_slow_states() -> void:
	for id: String in ["chaser", "rusher", "caster", "boss"]:
		var displacements: Array[float] = []
		for chilled: bool in [false, true]:
			var sim: CombatSim = _simulation(2026, 8 if id == "boss" else 1)
			sim.player_position = Vector2(640, 365)
			var enemy: CombatSim.Enemy = sim.boss if id == "boss" else sim.spawn_enemy(id, Vector2(540 if id == "caster" else 400, 365))
			enemy.action_timer = 9999.0
			if id == "rusher":
				enemy.mode = 2
				enemy.charge_direction = Vector2.RIGHT
			if chilled:
				var frost: ContentDef = GameCatalog.weapon("frost")
				sim.apply_damage(enemy, frost.damage, "frost", false, frost.slow)
			var before: Vector2 = enemy.position
			sim.step(DELTA, Vector2.ZERO)
			displacements.append(enemy.position.distance_to(before))
		_check(displacements[0] > 0.0 and absf(displacements[1] / displacements[0] - 0.75) < 0.001, "Frost slows " + id + " movement exactly once, including special movement states")
	var expired: CombatSim = _simulation()
	expired.player_position = Vector2(640, 365)
	var chaser: CombatSim.Enemy = expired.spawn_enemy("chaser", Vector2(400, 365))
	expired.apply_damage(chaser, 1.0, "frost", false, 0.25)
	chaser.slow_timer = DELTA * 0.5
	var initial: Vector2 = chaser.position
	expired.step(DELTA, Vector2.ZERO)
	_check(is_equal_approx(chaser.position.distance_to(initial), chaser.definition.speed * DELTA), "Expired frost restores normal movement speed")

func _test_swept_collision_order() -> void:
	_check(is_equal_approx(CombatSim._swept_circle_entry_t(Vector2.ZERO, Vector2(10, 0), Vector2(5, 0), 2.0), 0.3), "Swept collision returns the circle surface entry time")
	_check(CombatSim._swept_circle_entry_t(Vector2.ZERO, Vector2(10, 0), Vector2(1, 0), 2.0) == 0.0, "Starting inside a circle collides immediately")
	_check(is_equal_approx(CombatSim._swept_circle_entry_t(Vector2.ZERO, Vector2(10, 0), Vector2(5, 2), 2.0), 0.5), "A tangent segment counts as a collision")
	_check(CombatSim._swept_circle_entry_t(Vector2.ZERO, Vector2(10, 0), Vector2(12, 0), 2.0) == 1.0, "A collision exactly at the segment endpoint is included")
	_check(is_inf(CombatSim._swept_circle_entry_t(Vector2.ZERO, Vector2(9.9, 0), Vector2(12, 0), 2.0)), "A circle beyond the segment endpoint is excluded")
	_check(is_inf(CombatSim._swept_circle_entry_t(Vector2.ZERO, Vector2(10, 0), Vector2(-5, 0), 2.0)), "A circle behind the projectile is excluded")
	_check(CombatSim._swept_circle_entry_t(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 2.0) == 0.0, "A stationary projectile inside a circle collides")
	_check(is_inf(CombatSim._swept_circle_entry_t(Vector2.ZERO, Vector2.ZERO, Vector2(5, 0), 2.0)), "A stationary projectile outside a circle does not collide")
	for reversed: bool in [false, true]:
		var sim: CombatSim = _simulation()
		var chaser: CombatSim.Enemy
		var tank: CombatSim.Enemy
		if reversed:
			tank = sim.spawn_enemy("tank", Vector2(337, 300))
			chaser = sim.spawn_enemy("chaser", Vector2(330, 300))
		else:
			chaser = sim.spawn_enemy("chaser", Vector2(330, 300))
			tank = sim.spawn_enemy("tank", Vector2(337, 300))
		for target: CombatSim.Enemy in [chaser, tank]:
			target.slow_timer = 9999.0
			target.slow_factor = 0.0
		sim.fire_weapon("bone", "", Vector2(307, 300), Vector2.RIGHT)
		sim.step(DELTA, Vector2.ZERO)
		_check(is_equal_approx(tank.health, tank.max_health - 14.0) and chaser.health == chaser.max_health, "First physical collision is independent of entity pool order")
