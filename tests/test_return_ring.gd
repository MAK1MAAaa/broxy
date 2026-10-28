extends SceneTree
## Returning flight, ordinary rune dispatch and existing projectile behavior share one sim.

const STEP: float = 1.0 / 60.0
const OLD_WEAPONS: Array[String] = ["bone", "frost", "ember", "scatter", "crescent", "storm", "comet"]

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_definition()
	_test_return_and_tracking()
	_test_distinct_targets()
	_test_runes()
	_test_swept_recovery()
	_test_edges_and_lifetime()
	_test_pool_and_terminal()
	_test_independent_cooldown()
	_test_relic_transactions()
	_test_legacy_prefixes()
	print("ReturnRing: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _sim(starter: String = "return_ring", legacy: bool = false, seed_value: int = 1234) -> CombatSim:
	var state: RunState = RunState.new()
	state.begin(seed_value, starter)
	var sim: CombatSim = LegacyShotSim.new() if legacy else CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.player_position = Vector2(300, 300)
	sim._cooldowns.fill(9999.0)
	return sim

func _target(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	enemy.action_timer = 9999.0
	enemy.slow_timer = 9999.0
	enemy.slow_factor = 0.0
	return enemy

func _advance(sim: CombatSim, frames: int) -> void:
	for frame: int in frames:
		sim.step(STEP, Vector2.ZERO)

func _until_return(sim: CombatSim, shot: CombatSim.Shot) -> void:
	for frame: int in 40:
		if shot.returning or not shot.active:
			return
		sim.step(STEP, Vector2.ZERO)

func _test_definition() -> void:
	var definition: ContentDef = GameCatalog.weapon("return_ring")
	_check(GameCatalog.weapons().size() == 8 and GameCatalog.relics().size() == 14, "The formal catalog includes the returning weapon and active-skill tradeoff relics")
	_check(definition.price == 28 and definition.damage == 16.0 and definition.cooldown == 0.95 and definition.projectile_speed == 360.0 and definition.range == 230.0 and definition.innate_pierce == 1, "The return ring uses the agreed affordable base values")
	_check(definition.return_delay == 0.6 and definition.return_speed == 460.0 and definition.return_lifetime == 2.4, "The ring explicitly defines total flight lifetime and return timing")
	for id: String in OLD_WEAPONS:
		_check(GameCatalog.weapon(id).return_delay == 0.0, "Old weapon resources do not enable returning flight: " + id)

func _test_return_and_tracking() -> void:
	var sim: CombatSim = _sim()
	sim.run.health = 40.0
	var rng_before: int = sim.rng.state
	var run_rng: int = sim.run.rng.state
	var shot: CombatSim.Shot = sim.fire_weapon("return_ring", "", sim.player_position, Vector2.RIGHT)
	_advance(sim, 30)
	_check(shot.active and not shot.returning and shot.position.x > 470.0 and shot.velocity == Vector2(360, 0), "The ring first travels outward along its launch direction")
	_until_return(sim, shot)
	_check(shot.active and shot.returning and shot.velocity.x < 0.0 and is_equal_approx(shot.velocity.length(), 460.0), "The unspent ring turns toward the player after its finite delay")
	sim.player_position = Vector2(300, 430)
	var before: Vector2 = shot.position
	sim.step(STEP, Vector2.ZERO)
	_check(shot.velocity.normalized().is_equal_approx((sim.player_position - before).normalized()) and shot.velocity.y > 0.0, "Return steering follows the current player position rather than the launch origin")
	_advance(sim, 120)
	_check(not shot.active and sim.shot_count == 0 and sim.run.health == 40.0 and sim.run.gold == 0 and sim.run.xp == 0, "Recovery releases the projectile without currency, experience or healing")
	_check(sim.rng.state == rng_before and sim.run.rng.state == run_rng, "Returning flight and recovery consume neither RNG")

func _test_distinct_targets() -> void:
	var same: CombatSim = _sim()
	var original: CombatSim.Enemy = _target(same, Vector2(400, 300))
	var ring: CombatSim.Shot = same.fire_weapon("return_ring", "", same.player_position, Vector2.RIGHT)
	_advance(same, 120)
	_check(same.primary_hits == 1 and original.health == 9984.0 and ring.hit_ids.size() == 1 and not ring.active, "Outbound and inbound crossings never damage the same UID twice")
	var moving: CombatSim = _sim()
	var first: CombatSim.Enemy = _target(moving, Vector2(400, 300))
	var shot: CombatSim.Shot = moving.fire_weapon("return_ring", "", moving.player_position, Vector2.RIGHT)
	_until_return(moving, shot)
	moving.player_position = Vector2(300, 440)
	var second: CombatSim.Enemy = _target(moving, (shot.position + moving.player_position) * 0.5)
	_advance(moving, 100)
	_check(first.health == 9984.0 and second.health == 9984.0 and moving.primary_hits == 2 and not shot.active, "Player movement bends the return path into a different target while preserving the two-hit budget")

func _test_runes() -> void:
	var pierced: CombatSim = _sim()
	var targets: Array[CombatSim.Enemy] = []
	for point: Vector2 in [Vector2(355, 300), Vector2(405, 300)]:
		targets.append(_target(pierced, point))
	var ring: CombatSim.Shot = pierced.fire_weapon("return_ring", "pierce", pierced.player_position, Vector2.RIGHT)
	_until_return(pierced, ring)
	pierced.player_position = Vector2(300, 450)
	var axis: Vector2 = (pierced.player_position - ring.position).normalized()
	targets.append(_target(pierced, ring.position + axis * 60.0))
	targets.append(_target(pierced, ring.position + axis * 120.0))
	_advance(pierced, 90)
	_check(pierced.primary_hits == 4 and ring.hit_ids.size() == 4 and not ring.active, "Pierce preserves four total distinct targets across both flight phases")
	for target: CombatSim.Enemy in targets:
		_check(target.health == 9984.0, "Every permitted pierced UID receives exactly one full-strength hit")
	var blast: CombatSim = _sim()
	_target(blast, Vector2(400, 300))
	var bomb: CombatSim.Shot = blast.fire_weapon("return_ring", "blast", blast.player_position, Vector2.RIGHT)
	_until_return(blast, bomb)
	blast.player_position = Vector2(300, 440)
	var second_point: Vector2 = (bomb.position + blast.player_position) * 0.5
	var second: CombatSim.Enemy = _target(blast, second_point)
	var splash: CombatSim.Enemy = _target(blast, second_point + Vector2(0, 50))
	var events: Array[int] = [0]
	blast.rune_activated.connect(func(id: String, _point: Vector2, _incoming: Vector2, _outgoing: Vector2) -> void:
		if id == "blast":
			events[0] += 1
	)
	_advance(blast, 90)
	_check(not bomb.active and blast.primary_hits == 2 and second.health == 9984.0 and is_equal_approx(10000.0 - splash.health, 8.8) and events[0] == 1, "The second distinct inbound hit triggers one normal blast and ends the flight")
	var lone: CombatSim = _sim()
	_target(lone, Vector2(400, 300))
	lone.fire_weapon("return_ring", "blast", lone.player_position, Vector2.RIGHT)
	_advance(lone, 150)
	_check(lone.primary_hits == 1 and lone.secondary_hits == 0 and lone.shot_count == 0, "A one-target ring does not explode on its excluded return crossing")
	var bounce: CombatSim = _sim()
	var bounce_targets: Array[CombatSim.Enemy] = []
	for point: Vector2 in [Vector2(355, 300), Vector2(410, 300), Vector2(630, 350), Vector2(800, 350)]:
		bounce_targets.append(_target(bounce, point))
	var hunter: CombatSim.Shot = bounce.fire_weapon("return_ring", "bounce", bounce.player_position, Vector2.RIGHT)
	_advance(bounce, 40)
	_check(hunter.active and hunter.return_cancelled and not hunter.returning and hunter.return_after == 0.0 and hunter.velocity.x > 0.0, "A real successful outbound bounce permanently takes over beyond the original return deadline")
	_advance(bounce, 140)
	_check(bounce.primary_hits == 4 and bounce.shot_count == 0, "A cancelled return still exhausts its normal four-target bounce route")
	for index: int in 4:
		_check(is_equal_approx(10000.0 - bounce_targets[index].health, [16.0, 16.0, 12.0, 9.0][index]), "Native penetration keeps full damage and each actual bounce applies the standard decay")
	var no_neighbor: CombatSim = _sim()
	_target(no_neighbor, Vector2(355, 300))
	_target(no_neighbor, Vector2(410, 300))
	var failed_bounce: CombatSim.Shot = no_neighbor.fire_weapon("return_ring", "bounce", no_neighbor.player_position, Vector2.RIGHT)
	_advance(no_neighbor, 90)
	_check(not failed_bounce.active and not failed_bounce.return_cancelled and no_neighbor.primary_hits == 2, "A bounce with no unhit neighbor ends normally without claiming a successful return cancellation")
	var pending: CombatSim = _sim()
	var turn: CombatSim.Shot = pending.fire_weapon("return_ring", "bounce", Vector2(500, 300), Vector2.RIGHT)
	turn.return_after = 0.0
	turn.returning = true
	turn.innate_remaining = 0
	_target(pending, Vector2(400, 300))
	_target(pending, Vector2(400, 380))
	pending._rebuild_grid()
	pending._update_shots(0.5)
	_check(turn.active and turn.return_cancelled and not turn.returning and turn.velocity.y > 0.0, "An inbound bounce before a pending recovery invalidates that old recovery endpoint")
	pending._update_shots(STEP)
	_check(turn.active and not turn.returning and turn.velocity.y > 0.0, "The next frame preserves the actual bounce direction instead of snapping back to the player")
	turn.life = STEP * 0.5
	pending._update_shots(STEP)
	_check(not turn.active, "Bounce takeover retains the ring's remaining total lifetime")
	var late: CombatSim = _sim()
	var fading: CombatSim.Shot = late.fire_weapon("return_ring", "bounce", Vector2(500, 300), Vector2.LEFT)
	fading.return_after = 0.0
	fading.returning = true
	fading.innate_remaining = 0
	fading.life = 0.02
	_target(late, Vector2(488, 300))
	_target(late, Vector2(488, 380))
	late._rebuild_grid()
	late._update_shots(STEP)
	_check(fading.active and fading.return_cancelled and fading.life < STEP, "A late successful bounce never grants the ordinary projectile's extra 0.7-second lifetime")
	late._update_shots(STEP)
	_check(not fading.active, "The late bouncing ring expires at the original total-lifetime boundary")

func _test_swept_recovery() -> void:
	var sim: CombatSim = _sim()
	var behind: CombatSim.Enemy = _target(sim, Vector2(250, 300))
	var shot: CombatSim.Shot = sim.fire_weapon("return_ring", "pierce", Vector2(500, 300), Vector2.LEFT)
	shot.return_after = 0.0
	shot.returning = true
	sim._rebuild_grid()
	sim._update_shots(0.6)
	_check(not shot.active and shot.position.x >= 319.9 and behind.health == 10000.0 and sim.primary_hits == 0, "Swept recovery catches a projectile that crosses the player and clips enemies beyond the recovery point")
	_check(sim._shot_free.count(shot.slot) == 1, "Recovery returns the slot exactly once")

func _test_edges_and_lifetime() -> void:
	var bounds: Rect2 = CombatSim.ARENA
	var cleanup_bounds: Rect2 = bounds.grow(100.0)
	var left_launch := Vector2(bounds.position.x + 16.0, bounds.get_center().y)
	var edge: CombatSim = _sim()
	edge.player_position = left_launch
	var ring: CombatSim.Shot = edge.fire_weapon("return_ring", "", edge.player_position, Vector2.LEFT)
	_advance(edge, 30)
	_check(ring.active and ring.position.x < cleanup_bounds.position.x, "Outward edge launches are not deleted before their return deadline")
	_advance(edge, 120)
	_check(not ring.active and edge.shot_count == 0, "An out-of-bounds ring can reenter and recover normally")
	var old: CombatSim = _sim("bone")
	var needle: CombatSim.Shot = old.fire_weapon("bone", "", Vector2(cleanup_bounds.position.x - 6.0, bounds.get_center().y), Vector2.LEFT)
	old._update_shots(STEP)
	_check(not needle.active, "Ordinary projectiles retain cleanup beyond the actual arena's one-hundred-pixel envelope")
	var timeout: CombatSim = _sim()
	var lost: CombatSim.Shot = timeout.fire_weapon("return_ring", "", left_launch, Vector2.LEFT)
	timeout.player_position = Vector2(bounds.end.x - 24.0, bounds.get_center().y)
	_advance(timeout, 150)
	_check(not lost.active and lost.life <= 0.0 and timeout.shot_count == 0, "A distant or faster-moving player cannot create an immortal returning projectile")

func _test_pool_and_terminal() -> void:
	var sim: CombatSim = _sim()
	var ring: CombatSim.Shot = sim.fire_weapon("return_ring", "bounce", Vector2(400, 300), Vector2.RIGHT)
	var slot: int = ring.slot
	ring.return_cancelled = true
	ring.returning = true
	sim._release_shot(ring)
	sim._hostile_shot(Vector2(400, 300), Vector2.RIGHT, 5.0)
	var hostile: CombatSim.Shot = sim.shots[slot]
	_check(hostile.active and hostile.hostile and hostile.return_after == 0.0 and hostile.return_speed == 0.0 and not hostile.returning and not hostile.return_cancelled, "Hostile pool reuse clears every returning-flight field")
	sim._release_shot(hostile)
	var ordinary: CombatSim.Shot = sim.fire_weapon("bone", "", Vector2(400, 300), Vector2.RIGHT)
	_check(ordinary.slot == slot and ordinary.return_after == 0.0 and ordinary.return_speed == 0.0 and not ordinary.returning and not ordinary.return_cancelled, "Ordinary friendly reuse does not inherit return phase or cancellation")
	sim._release_shot(ordinary)
	var restored: CombatSim.Shot = sim.fire_weapon("return_ring", "", Vector2(400, 300), Vector2.RIGHT)
	_check(restored.slot == slot and restored.return_after == 0.6 and restored.return_speed == 460.0 and restored.life == 2.4 and not restored.returning and not restored.return_cancelled, "A reused ring starts with fresh outgoing timing and total lifetime")
	var terminal: CombatSim = CombatSim.new()
	var state: RunState = RunState.new()
	state.begin(8, "return_ring")
	state.wave = 8
	terminal.begin(state)
	terminal.sandbox = true
	terminal._cooldowns.fill(9999.0)
	terminal.boss.health = 1.0
	terminal.fire_weapon("return_ring", "blast", terminal.boss.position, Vector2.RIGHT)
	terminal.step(STEP, Vector2.ZERO)
	var before: Dictionary = terminal.run.summary()
	terminal._update_shots(STEP)
	_check(terminal.complete and terminal.victory and terminal.run.summary() == before and terminal.primary_hits == 1 and terminal.secondary_hits == 0, "A lethal Boss impact freezes returning dispatch before native/rune/recovery side effects")

func _test_independent_cooldown() -> void:
	var sim: CombatSim = _sim()
	_target(sim, Vector2(520, 300))
	sim._cooldowns[0] = 0.0
	var emissions: Array[int] = [0]
	var launched_during_return: Array[bool] = [false]
	var sim_ref: WeakRef = weakref(sim)
	sim.shot_fired.connect(func() -> void:
		emissions[0] += 1
		var current: CombatSim = sim_ref.get_ref() as CombatSim
		if current.shot_count >= 2:
			for shot: CombatSim.Shot in current.shots:
				if shot.active and shot.returning:
					launched_during_return[0] = true
	)
	_advance(sim, 60)
	_check(emissions[0] == 2 and launched_during_return[0], "The next cooldown launches a second ring while the earlier ring is still returning, even if that earlier ring recovers before the final sample")

func _test_relic_transactions() -> void:
	for id: String in ["blood_pact", "grave_candle"]:
		var state: RunState = RunState.new()
		state.begin(123, "return_ring")
		state.gold = 1000
		var definition: ContentDef = GameCatalog.relic(id)
		var item_uids: Array[int] = []
		for layer: int in range(1, 5):
			state.offers = [{"kind": "relic", "id": id, "price": definition.price, "sold": false}]
			var before: Dictionary = state.summary()
			var preview: Dictionary = state.relic_purchase_preview(0)
			_check(state.summary() == before and preview["has_projection"] and preview["can_buy"], "New tradeoff relic purchase previews remain pure and legal")
			_check(state.buy_offer(0) and is_equal_approx(state.stat(definition.stat), float(RunState.BASE_STATS[definition.stat]) + layer * definition.amount) and is_equal_approx(state.stat(definition.bonus_stat), float(RunState.BASE_STATS[definition.bonus_stat]) + layer * definition.bonus_amount), "Both tradeoff attributes scale through real purchases: " + id)
			item_uids.append(int(state.backpack_snapshot()["next_uid"]) - 1)
			for change: Dictionary in preview["stat_changes"]:
				_check(float(change["after"]) == state.stat(str(change["key"])), "The real tradeoff purchase exactly matches its stat projection")
			_check(state.health == 100.0 and state.stat("attack_speed") > 0.0 and state.stat("move_speed") > 0.0, "Tradeoffs do not subtract health or produce invalid movement/attack divisors")
		var stats_before: Array[float] = [state.stat(definition.stat), state.stat(definition.bonus_stat)]
		_check(state.merge_items(item_uids[1], item_uids[0]) and state.merge_items(item_uids[3], item_uids[2]) and state.merge_items(item_uids[2], item_uids[0]), "Four tradeoff relic boxes explicitly merge through the second and third ranks")
		_check(state.backpack_item(item_uids[0])["rank"] == 3 and state.relic_counts[id] == 4 and state.stat(definition.stat) == stats_before[0] and state.stat(definition.bonus_stat) == stats_before[1] and state.health == 100.0, "The third-rank tradeoff preserves all four contributions without another purchase or heal")
		_check(state.gold == 1000 - definition.price * 4, "Only the four successful tradeoff purchases spend gold; manual merges are free")

func _flight_signature(sim: CombatSim) -> String:
	var data: Array = [sim.run.summary(), sim.rng.state, sim.run.rng.state, sim.primary_hits, sim.secondary_hits, sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			data.append([shot.slot, shot.position, shot.previous, shot.velocity, shot.damage, shot.radius, shot.life, shot.source, shot.rune, shot.remaining, shot.innate_remaining, shot.hit_ids.duplicate(), shot.hostile])
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			data.append([enemy.uid, enemy.position, enemy.health, enemy.slow_timer, enemy.slow_factor])
	return JSON.stringify(data)

func _test_legacy_prefixes() -> void:
	for weapon: String in OLD_WEAPONS:
		for rune: String in ["", "pierce", "bounce", "blast"]:
			var current: CombatSim = _sim(weapon)
			var legacy: CombatSim = _sim(weapon, true)
			for sim: CombatSim in [current, legacy]:
				for index: int in 5:
					_target(sim, Vector2(360 + index * 50, 300 + (index % 2) * 20))
				sim.fire_weapon(weapon, rune, Vector2(300, 300), Vector2.RIGHT)
			var equivalent: bool = true
			for frame: int in 120:
				current.step(STEP, Vector2.ZERO)
				legacy.step(STEP, Vector2.ZERO)
				equivalent = equivalent and _flight_signature(current) == _flight_signature(legacy)
			_check(equivalent, "Original weapon/rune fixed-step prefix matches the frozen old dispatcher exactly: " + weapon + "/" + rune)

class LegacyShotSim extends CombatSim:
	func _update_shots(delta: float) -> void:
		for shot: Shot in shots:
			if complete:
				return
			if not shot.active:
				continue
			shot.life -= delta
			if shot.life <= 0.0 or not ARENA.grow(100.0).has_point(shot.position):
				_release_shot(shot)
				continue
			if shot.homing > 0.0 and not shot.hostile:
				var target: Enemy = _nearest(shot.position, 420.0, shot.hit_ids)
				if target != null:
					var speed: float = shot.velocity.length()
					var desired: Vector2 = (target.position - shot.position).normalized()
					var heading: Vector2 = shot.velocity.normalized()
					var weight: float = minf(1.0, shot.homing * delta)
					var turn_cross: float = heading.cross(desired)
					# Opposite vectors keep their heading below half weight, or cancel at half.
					# Only escape that narrow case; exact opposition takes a fixed, RNG-free side.
					if weight > 0.0 and weight <= 0.5 and heading.dot(desired) < 0.0 and absf(turn_cross) <= 0.0001:
						var turn_sign: float = -1.0 if turn_cross < 0.0 else 1.0
						shot.velocity = heading.rotated(turn_sign * weight) * speed
					else:
						shot.velocity = heading.lerp(desired, weight).normalized() * speed
			shot.previous = shot.position
			shot.position += shot.velocity * delta
			if shot.hostile:
				if _segment_distance_squared(player_position, shot.previous, shot.position) < pow(shot.radius + 12.0, 2):
					var hit_damage: float = shot.damage
					var attacker_id: String = shot.attacker_id
					var hit_origin: Vector2 = shot.position
					_release_shot(shot)
					_hurt_player(hit_damage, attacker_id, "projectile", hit_origin)
				continue
			var impact: Enemy = _first_collision(shot)
			var hit_count: int = 0
			var hit_limit: int = 4 if shot.innate_remaining > 0 else 3
			while impact != null and shot.active and hit_count < hit_limit:
				hit_count += 1
				shot.hit_ids[impact.uid] = true
				var impact_position: Vector2 = impact.position
				var health_before: float = impact.health
				var incoming_direction: Vector2 = shot.velocity.normalized()
				apply_damage(impact, shot.damage, shot.source, false, shot.slow)
				var positive_hit: bool = impact.health < health_before
				if complete:
					_release_shot(shot)
					return
				# Native penetration precedes the socketed rune and shares its hit exclusions.
				if shot.innate_remaining > 0:
					shot.innate_remaining -= 1
					impact = _first_collision(shot)
					continue
				if shot.rune == "blast":
					_release_shot(shot)
					if positive_hit:
						rune_activated.emit("blast", impact_position, incoming_direction, Vector2.ZERO)
					_explode(impact_position, shot.damage * RuneRules.BLAST_DAMAGE_FACTOR, shot.source, shot.hit_ids)
				elif shot.rune == "pierce" and shot.remaining > 0:
					shot.remaining -= 1
					if positive_hit:
						rune_activated.emit("pierce", impact_position, incoming_direction, incoming_direction)
					impact = _first_collision(shot)
					continue
				elif shot.rune == "bounce" and shot.remaining > 0:
					var target: Enemy = _nearest(impact_position, RuneRules.BOUNCE_RANGE, shot.hit_ids)
					if target != null:
						shot.position = impact_position
						shot.velocity = (target.position - impact_position).normalized() * shot.velocity.length()
						shot.damage *= RuneRules.BOUNCE_DAMAGE_FACTOR
						shot.remaining -= 1
						shot.life = maxf(shot.life, 0.7)
						add_effect(impact_position, Color("dcc5ff"), 12.0, 0.18, 1)
						if positive_hit:
							rune_activated.emit("bounce", impact_position, incoming_direction, shot.velocity.normalized())
					else:
						_release_shot(shot)
				else:
					_release_shot(shot)
				break
