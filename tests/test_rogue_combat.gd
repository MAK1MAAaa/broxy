extends SceneTree
## Real fixed-step shots, inventory-linked targeting and route/contract encounters.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_frostfire()
	_test_frostfire_runes()
	_test_priority()
	_test_chorus()
	_test_chorus_ranks_and_pool()
	_test_routes()
	_test_hunter()
	print("RogueCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _state(core: String = "", starter: String = "bone") -> RunState:
	var state := RunState.new()
	state.begin(20261027, starter)
	state.gold = 1000
	if not core.is_empty():
		state.finish_wave()
		_check(state.choose_core(core), "The combat fixture obtains its core through the real once-per-run transaction")
	return state

func _sim(state: RunState) -> CombatSim:
	var sim := CombatSim.new()
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

func _clear_shots(sim: CombatSim) -> void:
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			sim._release_shot(shot)

func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"id": id, "kind": kind, "price": state.shop_price(definition), "sold": false}]
	_check(state.buy_offer(0), "Formal inventory purchase for combat: " + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1

func _test_frostfire() -> void:
	var sim: CombatSim = _sim(_state("frostfire", "ember"))
	var direct: CombatSim.Enemy = _target(sim, Vector2(400, 300))
	var nearby: CombatSim.Enemy = _target(sim, Vector2(400, 350))
	var outside: CombatSim.Enemy = _target(sim, Vector2(400, 390))
	var activations: Array[String] = []
	sim.core_activated.connect(func(id: String, _point: Vector2) -> void: activations.append(id))
	var source_damage: float = GameCatalog.weapon("ember").damage
	sim.fire_weapon("ember", "", sim.player_position, Vector2.RIGHT)
	_advance(sim, 45)
	_check(is_equal_approx(direct.health, 10000.0 - source_damage), "Frostfire excludes its direct target from secondary damage")
	_check(is_equal_approx(nearby.health, 10000.0 - source_damage * RogueRules.FROSTFIRE_FACTOR), "A real slowed-target ember hit bursts for the shared secondary damage factor")
	_check(outside.health == 10000.0, "Frostfire respects its radius including enemy collision size")
	_check(direct.slow_timer == 0.0 and direct.slow_factor == 1.0 and nearby.slow_timer > 0.0, "The burst consumes only the directly hit target's slow")
	_check(sim.primary_hits == 1 and sim.secondary_hits == 1 and activations == ["frostfire"], "Secondary splash does not recursively activate the core")
	_check(is_equal_approx(float(sim.run.damage_dealt_by_weapon["ember"]), source_damage * (1.0 + RogueRules.FROSTFIRE_FACTOR)), "Core splash keeps the original weapon's actual damage attribution")
	var ordinary: CombatSim = _sim(_state("", "ember"))
	var plain: CombatSim.Enemy = _target(ordinary, Vector2(400, 300))
	var plain_neighbor: CombatSim.Enemy = _target(ordinary, Vector2(400, 350))
	ordinary.fire_weapon("ember", "", ordinary.player_position, Vector2.RIGHT)
	_advance(ordinary, 45)
	_check(plain.health < 10000.0 and plain_neighbor.health == 10000.0 and plain.slow_timer > 0.0, "An unchosen core leaves original ember and slow behavior unchanged")
	var indirect: CombatSim = _sim(_state("frostfire", "ember"))
	var secondary: CombatSim.Enemy = _target(indirect, Vector2(400, 300))
	indirect.apply_damage(secondary, 10.0, "ember", true)
	_check(secondary.slow_timer > 0.0 and indirect.core_activations["frostfire"] == 0, "Secondary damage attributed to ember cannot trigger frostfire")

func _test_frostfire_runes() -> void:
	for rune: String in ["pierce", "bounce", "blast"]:
		var sim: CombatSim = _sim(_state("frostfire", "ember"))
		_target(sim, Vector2(400, 300))
		var nearby: CombatSim.Enemy = _target(sim, Vector2(400, 350))
		var events: Array[String] = []
		sim.rune_activated.connect(func(id: String, _point: Vector2, _incoming: Vector2, _outgoing: Vector2) -> void: events.append(id))
		sim.fire_weapon("ember", rune, sim.player_position, Vector2.RIGHT)
		_advance(sim, 80)
		_check(sim.core_activations["frostfire"] >= 1 and nearby.health < 10000.0, "Frostfire coexists with the real socket behavior: " + rune)
		_check(events.size() <= 2 and sim.core_activations["frostfire"] <= 2, "Core/rune secondary effects remain bounded without a recursive dispatch: " + rune)
		if rune == "blast":
			_check(events == ["blast"] and sim.core_activations["frostfire"] == 1 and sim.secondary_hits == 2,
				"Blast and frostfire each dispatch once, without retriggering each other")

func _test_priority() -> void:
	var state: RunState = _state("frostfire", "ember")
	var sim: CombatSim = _sim(state)
	var nearest: CombatSim.Enemy = _target(sim, Vector2(350, 300))
	nearest.slow_timer = 0.0
	var slowed: CombatSim.Enemy = _target(sim, Vector2(300, 440))
	var rng_before: int = sim.rng.state
	_check(sim._weapon_target(sim.player_position, 500, true, false) == slowed, "Ember chooses a slowed target before a nearer ordinary enemy")
	_check(sim._weapon_target(sim.player_position, 90, true, false) == nearest, "Frostfire falls back to the normal in-range target when the slowed enemy is out of range")
	var round: CombatSim.Shot = sim.fire_weapon("ember", "", sim.player_position, Vector2.RIGHT)
	_advance(sim, 1)
	_check(round.velocity.y > 0.0 and round.velocity.x > 0.0, "Real ember homing turns toward the slowed target rather than the nearest ordinary enemy")
	_check(sim.rng.state == rng_before, "Priority targeting and homing do not consume simulation RNG")
	var lamp_state: RunState = _state()
	var candle: int = _buy(lamp_state, "relic", "grave_candle")
	_check(lamp_state.move_item(candle, Vector2i(0, 3), false), "The lamp fixture legally places its candle directly below the three-cell bone")
	var lamp: CombatSim = _sim(lamp_state)
	var close: CombatSim.Enemy = _target(lamp, Vector2(300, 340))
	var weak: CombatSim.Enemy = _target(lamp, Vector2(440, 300))
	weak.health = 1000.0
	var weapon_uid: int = int(lamp_state.loadout[0]["uid"])
	_check(lamp._linked_weapons.has(weapon_uid), "The real candle adjacency is cached for this wave")
	lamp._cooldowns.fill(0.0)
	lamp._update_weapons(0.0)
	_check(lamp.shot_count == 1 and lamp.shots[0].velocity.is_equal_approx(Vector2.RIGHT * GameCatalog.weapon("bone").projectile_speed), "An actually linked weapon fires toward the lowest-health-ratio in-range target")
	_check(lamp._weapon_target(lamp.player_position, 100, false, true) == close, "An out-of-range wounded target cannot distract the lamp weapon")
	weak.health = 10000.0
	_check(lamp._weapon_target(lamp.player_position, 500, false, true) == close, "Equal health ratios retain distance priority")
	weak.position = Vector2(300, 260)
	_check(lamp._weapon_target(lamp.player_position, 500, false, true) == close, "Equal health and distance ties retain pool-slot order")
	_check(lamp_state.move_item(candle, Vector2i(1, 3), false), "Moving the candle out of the vertical contact is a legal shop operation")
	var detached: CombatSim = _sim(lamp_state)
	_check(not detached._linked_weapons.has(weapon_uid), "The next wave drops stale lamp links after backpack rearrangement")
	var ember_state: RunState = _state("", "ember")
	var ember_candle: int = _buy(ember_state, "relic", "grave_candle")
	_check(ember_state.move_item(ember_candle, Vector2i(0, 2), false), "A real candle can touch the bottom edge of a square ember weapon")
	var guided: CombatSim = _sim(ember_state)
	_target(guided, Vector2(350, 300))
	var wounded: CombatSim.Enemy = _target(guided, Vector2(300, 440))
	wounded.health = 1000.0
	guided._cooldowns.fill(0.0)
	guided._update_weapons(0.0)
	var guided_shot: CombatSim.Shot = guided.shots[0]
	_check(guided_shot.low_health_priority and guided_shot.velocity.normalized().is_equal_approx(Vector2.DOWN), "A linked ember projectile captures the candle's wounded-target priority at launch")
	_advance(guided, 1)
	_check(guided_shot.velocity.normalized().is_equal_approx(Vector2.DOWN), "Real homing continues toward the wounded target rather than immediately switching to the nearer healthy one")
	guided._release_shot(guided_shot)
	var reused: CombatSim.Shot = guided.fire_weapon("ember", "", guided.player_position, Vector2.RIGHT)
	_check(reused.slot == guided_shot.slot and not reused.low_health_priority, "Projectile pool reuse does not leak a previous candle's targeting priority")

func _test_chorus() -> void:
	var state: RunState = _state("bone_chorus")
	var second: int = int(state.loadout[1]["uid"])
	var sim: CombatSim = _sim(state)
	_target(sim, Vector2(450, 300))
	for attack: int in 3:
		_clear_shots(sim)
		sim._cooldowns.fill(0.0)
		sim._update_weapons(0.0)
		_check(sim.shot_count == (6 if attack == 2 else 2), "Each separate bone UID adds two real side shots on its third actual attack")
	_check(sim.core_activations["bone_chorus"] == 2 and sim._chorus_counts.has(second), "Two bones keep independent attack counters rather than sharing one cadence")
	var side_shots: int = 0
	for shot: CombatSim.Shot in sim.shots:
		if shot.active and not is_equal_approx(shot.velocity.angle(), 0.0):
			side_shots += 1
			_check(is_equal_approx(shot.damage, GameCatalog.weapon("bone").damage * RogueRules.CHORUS_FACTOR), "Chorus side shots carry their own reduced real damage")
			_check(is_equal_approx(absf(shot.velocity.angle()), RogueRules.CHORUS_ANGLE), "The side-shot fan angle comes from the shared rules")
	_check(side_shots == 4, "The third dual-bone attack contains exactly four side shots")
	var next: CombatSim = _sim(state)
	_target(next, Vector2(450, 300))
	next._cooldowns.fill(0.0)
	next._update_weapons(0.0)
	_check(next.shot_count == 2, "Every wave starts fresh cadence for each bone")
	var direct: CombatSim = _sim(state)
	direct.fire_weapon("bone", "", Vector2(300, 300), Vector2.RIGHT)
	_check(direct.shot_count == 1 and direct._chorus_counts.is_empty(), "The diagnostic projectile constructor never counts as a weapon attack")

func _test_chorus_ranks_and_pool() -> void:
	for rune_id: String in ["pierce", "bounce", "blast"]:
		var state: RunState = _state("bone_chorus")
		var weapon: int = int(state.loadout[0]["uid"])
		var copy: int = int(state.loadout[1]["uid"])
		_check(state.merge_items(copy, weapon), "A formal merge supplies a ranked bone for chorus")
		var rune: int = _buy(state, "rune", rune_id)
		var rune_copy: int = _buy(state, "rune", rune_id)
		_check(state.merge_items(rune_copy, rune), "A formal merge supplies a ranked rune for chorus")
		_check(state.equip_rune(state.rune_index_for_uid(rune), state.weapon_index_for_uid(weapon)), "The ranked rune attaches through the real socket transaction")
		var sim: CombatSim = _sim(state)
		_target(sim, Vector2(450, 300))
		for attack: int in 3:
			_clear_shots(sim)
			sim._cooldowns.fill(0.0)
			sim._update_weapons(0.0)
		var extras: int = 0
		for shot: CombatSim.Shot in sim.shots:
			if shot.active and absf(shot.velocity.angle()) > 0.01:
				extras += 1
				_check(shot.weapon_rank == 2 and shot.rune_rank == 2 and shot.rune == rune_id,
					"Chorus preserves weapon and socket rank in its actual extra projectiles: " + rune_id)
				_check(is_equal_approx(shot.damage, GameCatalog.weapon("bone").damage * 2.0 * RogueRules.CHORUS_FACTOR), "Rank scales chorus damage once")
		_check(extras == 2, "Ranked chorus still adds exactly two shots: " + rune_id)
	var full: CombatSim = _sim(_state("bone_chorus"))
	_target(full, Vector2(450, 300))
	for index: int in CombatSim.SHOT_LIMIT:
		full.fire_weapon("bone", "", full.player_position, Vector2.RIGHT)
	full._cooldowns.fill(0.0)
	full._update_weapons(0.0)
	_check(full._chorus_counts.is_empty() and full.core_activations["bone_chorus"] == 0, "An exhausted pool with no emitted primary shot does not advance the core cadence")

func _route_sim(route: String, wave: int = 2) -> CombatSim:
	var state: RunState = _state()
	state.finish_wave()
	_check(state.choose_route(route), "The route fixture makes a real shop route choice")
	state.next_wave()
	state.wave = wave
	if wave == 8:
		state.active_route = route
	var sim := CombatSim.new()
	sim.begin(state)
	sim._cooldowns.fill(9999.0)
	return sim

func _test_routes() -> void:
	for id: String in ["balanced", "swarm", "bulwark"]:
		var sim: CombatSim = _route_sim(id)
		var route: Dictionary = RogueRules.route(id)
		sim.step(0.6, Vector2.ZERO)
		var expected: int = 3 if id == "balanced" else maxi(1, ceili(3.0 * float(route["count_factor"])))
		_check(sim.enemy_count == expected and sim.duration == GameCatalog.wave(2).duration, "The chosen route changes batch size without changing wave duration: " + id)
		_check(is_equal_approx(sim._spawn_timer, GameCatalog.wave(2).spawn_interval * float(route["interval_factor"])), "The chosen route uses its declared spawn interval: " + id)
		for group: int in 10:
			sim._spawn_wave_group()
		var allowed: Dictionary = GameCatalog.wave(2).spawn_weights if id == "balanced" else route["weights"]
		var legal: bool = true
		for enemy: CombatSim.Enemy in sim.enemies:
			if enemy.active:
				legal = legal and allowed.has(enemy.definition.id)
		_check(legal and sim.enemy_count <= GameCatalog.wave(2).cap, "Route composition stays inside its declared enemy set and original cap: " + id)
		var paired: CombatSim = _route_sim(id)
		paired.step(0.6, Vector2.ZERO)
		for group: int in 10:
			paired._spawn_wave_group()
		_check(_enemy_signature(sim) == _enemy_signature(paired) and sim.rng.state == paired.rng.state, "Identical route decisions and seed reproduce the full enemy batch: " + id)
	var boss: CombatSim = _route_sim("bulwark", 8)
	var baseline: CombatSim = _route_sim("balanced", 8)
	boss._spawn_wave_group()
	baseline._spawn_wave_group()
	_check(_enemy_signature(boss) == _enemy_signature(baseline) and boss.rng.state == baseline.rng.state,
		"Boss waves ignore route mutations and preserve the original enemy sequence")

func _enemy_signature(sim: CombatSim) -> Array:
	var result: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			result.append([enemy.uid, enemy.definition.id, enemy.position, enemy.health, enemy.action_timer])
	return result

func _test_hunter() -> void:
	var state: RunState = _state()
	state.wave = 2
	state.finish_wave()
	_check(state.choose_altar(true), "The contract fixture accepts the real second-wave altar")
	state.next_wave()
	var sim: CombatSim = _sim(state)
	_check(sim.hunter != null and sim.hunter.active and sim.hunter.hunter and sim.hunter.definition.id == "rusher", "The accepted contract introduces one identifiable rusher hunter")
	var hunter: CombatSim.Enemy = sim.hunter
	_check(is_equal_approx(hunter.max_health, GameCatalog.enemy("rusher").health * (1.0 + 0.17 * 2.0) * RogueRules.HUNTER_HEALTH_FACTOR), "Hunter health uses only the declared per-instance factor")
	var normal: CombatSim.Enemy = sim.spawn_enemy("rusher", Vector2(700, 300))
	hunter.position = normal.position
	hunter.action_timer = 9999.0
	normal.action_timer = 9999.0
	sim._update_enemies(0.1)
	_check(is_equal_approx(hunter.velocity.length(), normal.velocity.length() * RogueRules.HUNTER_SPEED_FACTOR), "The hunter moves faster without modifying the shared rusher definition")
	_check(not state.rune_reward_pending, "Accepting or merely encountering the hunter does not pay the reward")
	sim.apply_damage(hunter, hunter.health, "bone")
	_check(state.hunter_defeated and state.rune_reward_pending, "Actual hunter death arms exactly one deferred rune reward")
	var replacement: CombatSim.Enemy = sim.spawn_enemy("rusher", Vector2(800, 300))
	_check(replacement.slot == hunter.slot and not replacement.hunter, "Pool reuse clears the hunter flag from the next ordinary enemy")
	var world := CombatWorld.new()
	world.sim = sim
	_check(not bool(world.hud_snapshot()["rogue"]["hunter_alive"]), "The HUD does not mistake a reused ordinary slot for a live hunter")
	world.free()
	var missed_state: RunState = _state()
	missed_state.wave = 2
	missed_state.finish_wave()
	_check(missed_state.choose_altar(true), "The timeout fixture takes the same optional contract")
	missed_state.next_wave()
	var missed: CombatSim = _sim(missed_state)
	missed.sandbox = false
	missed.elapsed = missed.duration
	missed.step(STEP, Vector2.ZERO)
	_check(missed.complete and missed.victory and not missed_state.hunter_defeated and not missed_state.rune_reward_pending,
		"A surviving hunter cleared by the ordinary wave timer grants no kill reward")
	var next_state: RunState = _state()
	next_state.wave = 4
	next_state.altar_choice = "accepted"
	next_state.altar_wave = 3
	var late: CombatSim = _sim(next_state)
	_check(late.hunter == null, "A missed past-wave hunter never respawns in later waves")
