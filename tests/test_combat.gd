extends SceneTree

const DELTA: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_weapon_rune_matrix()
	_test_pierce()
	_test_bounce()
	_test_blast()
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

func _test_weapon_rune_matrix() -> void:
	for weapon: ContentDef in GameCatalog.weapons():
		for rune: ContentDef in GameCatalog.runes():
			var simulation: CombatSim = _simulation(90, 1, weapon.id)
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
			if weapon.id == "frost":
				_check(first.slow_timer > 0.0 and is_equal_approx(first.slow_factor, 0.75), "Frost applies its advertised 25% slow")

func _test_pierce() -> void:
	var simulation: CombatSim = _simulation()
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

func _test_bounce() -> void:
	var simulation: CombatSim = _simulation()
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

func _test_blast() -> void:
	var simulation: CombatSim = _simulation()
	var primary: CombatSim.Enemy = _target(simulation, Vector2(330, 300))
	var neighbor: CombatSim.Enemy = _target(simulation, Vector2(385, 300))
	var chain_only: CombatSim.Enemy = _target(simulation, Vector2(440, 300))
	simulation.fire_weapon("bone", "blast", Vector2(200, 300), Vector2.RIGHT)
	_advance(simulation, 60)
	_check(is_equal_approx(10000.0 - primary.health, 14.0), "Blast excludes its primary target from secondary damage")
	_check(is_equal_approx(10000.0 - neighbor.health, 7.7), "Blast deals 55% damage to its neighbor")
	_check(chain_only.health == 10000.0, "Secondary blast damage does not recursively explode")
	_check(simulation.primary_hits == 1 and simulation.secondary_hits == 1, "Primary and secondary hit accounting stays distinct")

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
