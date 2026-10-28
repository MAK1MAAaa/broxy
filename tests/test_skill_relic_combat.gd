extends SceneTree
## Purchased, merged and sold relics drive real skills without rewriting an active cast.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

class ProbeWorld extends CombatWorld:
	var sell_before_feedback: int = -1
	var sale_succeeded: bool = false
	func _movement() -> Vector2:
		return Vector2.ZERO
	func _on_pulse_cast(origin: Vector2, affected: int) -> void:
		if sell_before_feedback >= 0:
			sale_succeeded = sim.run.sell_item(sell_before_feedback)
			sell_before_feedback = -1
		super._on_pulse_cast(origin, affected)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_rule_limits()
	_test_ranked_casts()
	_test_capped_casts()
	_test_cast_locking()
	_test_wave_reset()
	await _test_world_range_and_pause()
	print("SkillRelicCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _state(arena: String = "reliquary") -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone", arena)
	state.gold = 10000
	_check(state.expand_backpack() and state.expand_backpack(), "The purchase fixture expands through the real paid inventory transaction")
	return state

func _buy(state: RunState, id: String) -> int:
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	var definition: ContentDef = GameCatalog.relic(id)
	if definition == null:
		_check(false, "The skill relic must be present in the real catalog: " + id)
		return -1
	state.offers = [{"kind": "relic", "id": id, "price": definition.price, "sold": false}]
	_check(state.buy_offer(0), "The skill relic is bought through the real shop and assigned an inventory UID: " + id)
	return uid

func _ranked_relic(state: RunState, id: String, rank: int) -> int:
	var first: int = _buy(state, id)
	if rank >= 2:
		var second: int = _buy(state, id)
		_check(state.merge_items(second, first), "Two paid first-rank relics merge into the real second-rank item: " + id)
	if rank >= 3:
		var third: int = _buy(state, id)
		var fourth: int = _buy(state, id)
		_check(state.merge_items(fourth, third) and state.merge_items(third, first), "Two real second-rank relics merge into the real third-rank item: " + id)
	return first

func _sim(state: RunState) -> CombatSim:
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim

func _enemy(sim: CombatSim, id: String, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _advance_until_ready(sim: CombatSim) -> void:
	for frame: int in 1000:
		if sim.dash_cooldown_left == 0.0 and sim.pulse_cooldown_left == 0.0:
			return
		sim.step(STEP, Vector2.ZERO)
	_check(false, "Both bounded cooldowns must finish in fewer than one thousand fixed steps")

func _test_rule_limits() -> void:
	_check(DashRules.MIN_COOLDOWN == 1.2 and PulseRules.MAX_RADIUS == 216.0 and PulseRules.MAX_COOLDOWN == 16.0, "Skill-growth bounds match their published limits")
	for invalid: float in [NAN, INF, -INF]:
		_check(DashRules.clamp_cooldown(invalid) == 2.4 and PulseRules.clamp_radius(invalid) == 144.0 and PulseRules.clamp_cooldown(invalid) == 8.0, "Nonfinite rule input falls back to the original finite skill values")
	_check(DashRules.clamp_cooldown(-100.0) == 1.2 and DashRules.clamp_cooldown(100.0) == 2.4 and DashRules.clamp_cooldown(1.8) == 1.8, "Dash cooldown cannot go below its floor or above its baseline")
	_check(PulseRules.clamp_radius(-100.0) == 144.0 and PulseRules.clamp_radius(1000.0) == 216.0 and PulseRules.clamp_radius(180.0) == 180.0, "Pulse radius retains its baseline and finite maximum")
	_check(PulseRules.clamp_cooldown(-100.0) == 8.0 and PulseRules.clamp_cooldown(1000.0) == 16.0 and PulseRules.clamp_cooldown(9.6) == 9.6, "The larger pulse always retains its cooldown tradeoff within finite limits")

func _test_ranked_casts() -> void:
	for rank: int in [1, 2, 3]:
		var state: RunState = _state()
		_ranked_relic(state, "fold_clasp", rank)
		_ranked_relic(state, "echo_stone", rank)
		var weight: float = BackpackInventory.rank_multiplier(rank)
		var dash_cooldown: float = 2.4 - 0.3 * weight
		var pulse_radius: float = 144.0 + 18.0 * weight
		var pulse_cooldown: float = 8.0 + 0.8 * weight
		var sim: CombatSim = _sim(state)
		_check(_near(float(sim.dash_snapshot()["cooldown_total"]), dash_cooldown) and _near(float(sim.pulse_snapshot()["cooldown_total"]), pulse_cooldown) and sim.pulse_snapshot()["radius"] == pulse_radius, "Wave initialization publishes the real merged build before either skill is used")
		var origin: Vector2 = sim.player_position
		var edge: CombatSim.Enemy = _enemy(sim, "chaser", origin + Vector2(pulse_radius, 0))
		var outside: CombatSim.Enemy = _enemy(sim, "tank", origin + Vector2(pulse_radius + 0.01, 0))
		var boss: CombatSim.Enemy = _enemy(sim, "boss", origin + Vector2(80, 0))
		var hunter: CombatSim.Enemy = _enemy(sim, "rusher", origin + Vector2(90, 0))
		hunter.hunter = true
		var untouched: Array = [outside.position, boss.position, hunter.position]
		var rng_before: Array = [sim.rng.state, state.rng.state]
		sim.step(STEP, Vector2.RIGHT, true, true)
		_check(sim.dashes_used == 1 and sim.pulses_used == 1 and sim.last_pulse_affected == 1 and sim.pulse_affected == 1, "A real dual-skill step consumes both upgraded skills and only one eligible target")
		_check(edge.position.is_equal_approx(origin + Vector2(pulse_radius + 70.0, 0)) and _near(edge.pulse_hinder_timer, 1.0 - STEP), "The expanded inclusive radius uses the original seventy-pixel control and one-second timer")
		_check(untouched == [outside.position, boss.position, hunter.position] and outside.pulse_hinder_timer == 0.0 and boss.pulse_hinder_timer == 0.0 and hunter.pulse_hinder_timer == 0.0, "Targets outside the real radius and immune bosses or hunters remain unmarked and unmoved")
		_check(sim.player_position.is_equal_approx(origin + Vector2(11, 0)) and _near(sim.dash_time_left, 0.2 - STEP) and _near(sim.dash_invulnerability_left, 0.12 - STEP), "Relic movement penalties never alter dash speed, duration, distance or its short shield")
		_check(_near(sim.dash_cooldown_left, dash_cooldown - STEP) and _near(sim.pulse_cooldown_left, pulse_cooldown - STEP) and _near(float(sim.dash_snapshot()["cooldown_total"]), dash_cooldown) and _near(float(sim.pulse_snapshot()["cooldown_total"]), pulse_cooldown), "Both actual cooldown clocks consume the current physical step from their cast-locked totals")
		_check(sim.pulse_snapshot()["last_cast_radius"] == pulse_radius and state.health == 100.0 and state.damage_taken == 0.0 and sim.damage_by_weapon.is_empty() and rng_before == [sim.rng.state, state.rng.state], "Skill relics introduce no damage, economy, health or random-stream side effects during control")
		for frame: int in 11:
			sim.step(STEP, Vector2.ZERO)
		_check(sim.player_position.is_equal_approx(origin + Vector2(132, 0)) and sim.dash_time_left == 0.0 and sim.dash_invulnerability_left == 0.0, "Every merged tier keeps the complete dash distance and vulnerable tail")

func _test_capped_casts() -> void:
	for arena: String in ArenaCatalog.IDS:
		var state: RunState = _state(arena)
		_ranked_relic(state, "fold_clasp", 3)
		_ranked_relic(state, "fold_clasp", 3)
		for index: int in 3:
			_ranked_relic(state, "echo_stone", 3)
		var sim: CombatSim = _sim(state)
		var origin: Vector2 = sim.player_position
		var edge: CombatSim.Enemy = _enemy(sim, "tank", origin + Vector2(216, 0))
		var outside: CombatSim.Enemy = _enemy(sim, "tank", origin + Vector2(216.01, 0))
		sim.step(STEP, Vector2.ZERO, true, true)
		_check(_near(sim.dash_cooldown_left, 1.2 - STEP) and _near(sim.pulse_cooldown_left, 16.0 - STEP) and sim.last_pulse_radius == 216.0, "Multiple actual third-rank boxes reach the finite skill caps in " + arena)
		_check(edge.pulse_hinder_timer > 0.0 and outside.pulse_hinder_timer == 0.0 and sim.last_pulse_affected == 1, "The maximum radius remains an inclusive real geometric boundary in " + arena)
		_check(sim.player_velocity.length() == 660.0, "The capped cooldown still cannot inherit a terrain or permanent movement penalty in " + arena)

func _test_cast_locking() -> void:
	var state: RunState = _state()
	var sim: CombatSim = _sim(state)
	sim.step(STEP, Vector2.RIGHT, true, true)
	var original_left: Array = [sim.dash_cooldown_left, sim.pulse_cooldown_left]
	var clasp: int = _buy(state, "fold_clasp")
	var stone: int = _buy(state, "echo_stone")
	var dash: Dictionary = sim.dash_snapshot()
	var pulse: Dictionary = sim.pulse_snapshot()
	_check(original_left == [sim.dash_cooldown_left, sim.pulse_cooldown_left] and dash["cooldown_total"] == 2.4 and pulse["cooldown_total"] == 8.0, "Purchasing during an existing cast never refunds, extends or rescales either clock")
	_check(_near(float(dash["next_cooldown_total"]), 2.1) and _near(float(pulse["next_cooldown_total"]), 8.8) and pulse["radius"] == 162.0 and pulse["last_cast_radius"] == 144.0, "Snapshots separate the current build from the parameters of the last real cast")
	var rng_before: Array = [sim.rng.state, state.rng.state]
	for query: int in 5:
		dash = sim.dash_snapshot()
		pulse = sim.pulse_snapshot()
	_check(original_left == [sim.dash_cooldown_left, sim.pulse_cooldown_left] and rng_before == [sim.rng.state, state.rng.state], "Repeated snapshot queries never progress cooldowns or consume randomness")
	_advance_until_ready(sim)
	_check(_near(float(sim.dash_snapshot()["cooldown_total"]), 2.1) and _near(float(sim.pulse_snapshot()["cooldown_total"]), 8.8), "Readiness exposes the next cast's current-build total instead of the expired cast's total")
	sim.step(STEP, Vector2.ZERO, true, true)
	_check(_near(sim.dash_cooldown_total, 2.1) and _near(sim.pulse_cooldown_total, 8.8) and sim.last_pulse_radius == 162.0 and sim.dashes_used == 2 and sim.pulses_used == 2, "A fresh input locks the purchased values on the next actual cast")
	original_left = [sim.dash_cooldown_left, sim.pulse_cooldown_left]
	_check(state.sell_item(clasp) and state.sell_item(stone), "Both paid skill relics can be sold through the real inventory transaction")
	dash = sim.dash_snapshot()
	pulse = sim.pulse_snapshot()
	_check(original_left == [sim.dash_cooldown_left, sim.pulse_cooldown_left] and _near(float(dash["cooldown_total"]), 2.1) and _near(float(pulse["cooldown_total"]), 8.8) and pulse["last_cast_radius"] == 162.0, "Selling never rewrites the parameters already paid by either current cast")
	_check(dash["next_cooldown_total"] == 2.4 and pulse["next_cooldown_total"] == 8.0 and pulse["radius"] == 144.0, "Selling restores baseline values for the next cast without erasing its predecessor")
	_advance_until_ready(sim)
	sim.step(STEP, Vector2.ZERO, true, true)
	_check(sim.dash_cooldown_total == 2.4 and sim.pulse_cooldown_total == 8.0 and sim.last_pulse_radius == 144.0 and sim.dashes_used == 3 and sim.pulses_used == 3, "Subsequent ordinary casts use the original baseline after both relics leave the backpack")

func _test_wave_reset() -> void:
	var state: RunState = _state()
	var clasp: int = _ranked_relic(state, "fold_clasp", 2)
	var stone: int = _ranked_relic(state, "echo_stone", 2)
	var sim: CombatSim = _sim(state)
	sim.step(STEP, Vector2.ZERO, true, true)
	_check(state.sell_item(clasp) and state.sell_item(stone), "Reset fixture sells both upgraded relics through real inventory actions")
	sim.begin(state)
	_check(sim.dash_cooldown_left == 0.0 and sim.pulse_cooldown_left == 0.0 and sim.dash_cooldown_total == 2.4 and sim.pulse_cooldown_total == 8.0 and sim.last_pulse_radius == 144.0, "Beginning another wave resets all locked totals and radius to its current build")
	_check(sim.dashes_used == 0 and sim.pulses_used == 0 and sim.last_pulse_affected == 0 and sim.dash_snapshot()["ready"] and sim.pulse_snapshot()["ready"], "No skill count, use, cooldown or stale request survives wave initialization")

func _test_world_range_and_pause() -> void:
	var state: RunState = _state()
	_ranked_relic(state, "fold_clasp", 1)
	var stone: int = _ranked_relic(state, "echo_stone", 2)
	var world := ProbeWorld.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.set_physics_process(false)
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	world.sell_before_feedback = stone
	var target: CombatSim.Enemy = _enemy(world.sim, "tank", world.sim.player_position + Vector2(180, 0))
	_check(world.request_dash() and world.request_pulse(), "Real World input accepts both upgraded ready skills")
	world._physics_process(STEP)
	var feedback: Dictionary = world.pulse_feedback_snapshot()
	_check(world.sale_succeeded and world.sim.pulse_snapshot()["radius"] == 144.0 and world.sim.pulse_snapshot()["last_cast_radius"] == 180.0, "A same-signal inventory change exposes a new build without replacing the completed cast's radius")
	_check(feedback["active"] and feedback["radius"] == 180.0 and feedback["affected"] == 1 and target.pulse_hinder_timer > 0.0, "World feedback uses the exact locked radius that actually controlled the edge target")
	_check(_near(float(world.sim.pulse_snapshot()["cooldown_total"]), 9.6) and float(world.sim.pulse_snapshot()["next_cooldown_total"]) == 8.0, "World HUD snapshots retain the old real cooldown while advertising the new next-cast value")
	paused = true
	world.set_physics_process(true)
	var before: Array = [world.sim.dash_snapshot(), world.sim.pulse_snapshot(), world.pulse_feedback_snapshot(), world.sim.elapsed]
	for frame: int in 4:
		await process_frame
	_check(before == [world.sim.dash_snapshot(), world.sim.pulse_snapshot(), world.pulse_feedback_snapshot(), world.sim.elapsed], "Real scene-tree pause freezes upgraded timers and the cast-locked visual slot")
	world.apply_visual_settings({"shake": true, "flash": false})
	feedback = world.pulse_feedback_snapshot()
	_check(feedback["active"] and feedback["radius"] == 180.0 and not feedback["animated"], "Flash-off keeps the accurate expanded static range while canceling optional animation")
	world.apply_visual_settings({"shake": true, "flash": true})
	_check(not world.pulse_feedback_snapshot()["animated"] and world.pulse_feedback_snapshot()["radius"] == 180.0, "Re-enabling flash cannot replay or resize the older cast")
	paused = false
	await physics_frame
	await physics_frame
	world.set_physics_process(false)
	_check(world.sim.elapsed > float(before[3]) and _near(float(world.sim.pulse_snapshot()["cooldown_total"]), 9.6), "Resume advances the same real locked cooldown")
	world.stop()
	_check(not world.pulse_feedback_snapshot()["active"] and world.pulse_feedback_snapshot()["radius"] == 0.0, "World stop clears the old cast's visual radius")
	world.queue_free()
	for frame: int in 3:
		await process_frame
