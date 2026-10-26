extends SceneTree
## Formal core gifts, grid resonance, ranks and socket behavior share the shipped shot path.

const STEP: float = 1.0 / 60.0
const HEALTH: float = 10000.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_chorus_resonance()
	_test_frostfire_resonance()
	_test_direct_defaults_and_pool()
	_test_supported_hunter_kill()
	print("RogueResonanceCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _core_state(id: String, starter: String) -> RunState:
	var state := RunState.new()
	state.begin(20261028, starter)
	state.gold = 1000
	state.finish_wave()
	_check(state.choose_core(id), "The combination fixture chooses its real once-per-run core")
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"id": id, "kind": kind, "price": state.shop_price(definition), "sold": false}]
	_check(state.buy_offer(0), "Combination inventory is obtained through a real purchase: " + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1

func _rune(state: RunState, id: String, weapon_uid: int) -> void:
	var target: int = _buy(state, "rune", id)
	var source: int = _buy(state, "rune", id)
	_check(state.merge_items(source, target), "Two formally purchased runes merge into rank two")
	_check(state.equip_rune(state.rune_index_for_uid(target), state.weapon_index_for_uid(weapon_uid)), "The ranked rune equips through the real socket transaction")

func _support(state: RunState, armor_cell: Vector2i, candle_cell: Vector2i) -> void:
	var armor: int = _buy(state, "relic", "armor")
	_check(state.move_item(armor, armor_cell, false), "A real armor relic touches the tested weapon edge")
	var candle: int = _buy(state, "relic", "grave_candle")
	_check(state.move_item(candle, candle_cell, false), "A real candle touches the bottom edge and enables its separate targeting link")
	var damage: int = _buy(state, "relic", "damage")
	_check(state.move_item(damage, Vector2i(5, 3), false), "The global damage relic is kept away from the tested weapon's local edges")

func _bone_state(rune_id: String = "") -> RunState:
	var state: RunState = _core_state("bone_chorus", "bone")
	var weapon_uid: int = int(state.loadout[0]["uid"])
	var donated_uid: int = int(state.loadout[1]["uid"])
	_check(state.merge_items(donated_uid, weapon_uid), "The granted core weapon and starter merge into a single rank-two bone")
	_support(state, Vector2i(1, 0), Vector2i(0, 3))
	if not rune_id.is_empty():
		_rune(state, rune_id, weapon_uid)
	state.next_wave()
	return state

func _ember_state(rune_id: String = "") -> RunState:
	var state: RunState = _core_state("frostfire", "ember")
	var weapon_uid: int = int(state.loadout[0]["uid"])
	var frost_uid: int = int(state.loadout[1]["uid"])
	_check(state.move_item(frost_uid, Vector2i(5, 0), false), "The core's frost weapon is legally moved away from the tested ember")
	_support(state, Vector2i(2, 0), Vector2i(0, 2))
	var duplicate: int = _buy(state, "weapon", "ember")
	_check(state.merge_items(duplicate, weapon_uid), "A purchased ember merges with the real starter into rank two")
	if not rune_id.is_empty():
		_rune(state, rune_id, weapon_uid)
	state.next_wave()
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
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = HEALTH
	enemy.max_health = HEALTH
	enemy.action_timer = 9999.0
	return enemy

func _clear(sim: CombatSim) -> void:
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			sim._release_shot(shot)

func _test_chorus_resonance() -> void:
	for rune_id: String in ["pierce", "bounce", "blast"]:
		var state: RunState = _bone_state(rune_id)
		var weapon: Dictionary = state.loadout[0]
		_check(is_equal_approx(float(weapon["resonance_bonus"]), 0.06) and is_equal_approx(state.stat("damage"), 1.15), "Two real edge relics contribute local6% independently of global15%")
		var sim: CombatSim = _sim(state)
		var direct: CombatSim.Enemy = _target(sim, Vector2(430, 300))
		for attack: int in 3:
			_clear(sim)
			sim._cooldowns.fill(0.0)
			sim._update_weapons(0.0)
		var main_damage: float = 14.0 * 2.0 * 1.15 * 1.06
		var side_count: int = 0
		var primary_count: int = 0
		var upper: CombatSim.Enemy
		var lower: CombatSim.Enemy
		for shot: CombatSim.Shot in sim.shots:
			if not shot.active:
				continue
			_check(is_equal_approx(shot.resonance_bonus, 0.06) and shot.weapon_rank == 2 and shot.rune_rank == 2 and shot.rune == rune_id and shot.low_health_priority,
				"The real primary and side projectiles retain rank, rune, local resonance and candle targeting: " + rune_id)
			if absf(shot.velocity.angle()) < 0.01:
				primary_count += 1
				_check(is_equal_approx(shot.damage, main_damage), "Primary damage applies local resonance once, alongside rank and global damage")
			else:
				side_count += 1
				_check(is_equal_approx(shot.damage, main_damage * RogueRules.CHORUS_FACTOR), "A chorus side shot inherits resonance once and applies only its55% side factor")
				# Separate the impact lanes beyond bounce range so a first receipt
				# identifies its own emitted projectile, even with a bounce socket.
				var enemy: CombatSim.Enemy = _target(sim, sim.player_position + shot.velocity.normalized() * 550.0)
				if shot.velocity.y < 0.0:
					upper = enemy
				else:
					lower = enemy
		_check(primary_count == 1 and side_count == 2 and sim.core_activations["bone_chorus"] == 1, "A single supported weapon's third attack produces one primary and two side projectiles")
		var actual_by_uid: Dictionary = {}
		sim.damage_dealt.connect(func(_point: Vector2, amount: float, source: String, secondary: bool, uid: int) -> void:
			if source == "bone" and not secondary and not actual_by_uid.has(uid):
				actual_by_uid[uid] = amount
		)
		for frame: int in 90:
			sim.step(STEP, Vector2.ZERO)
			if actual_by_uid.has(direct.uid) and actual_by_uid.has(upper.uid) and actual_by_uid.has(lower.uid):
				break
		_check(actual_by_uid.has(direct.uid) and actual_by_uid.has(upper.uid) and actual_by_uid.has(lower.uid), "All three supported shots reach real collision targets: " + rune_id)
		if actual_by_uid.has(direct.uid) and actual_by_uid.has(upper.uid) and actual_by_uid.has(lower.uid):
			_check(is_equal_approx(float(actual_by_uid[direct.uid]), main_damage) and is_equal_approx(float(actual_by_uid[upper.uid]), main_damage * RogueRules.CHORUS_FACTOR)
				and is_equal_approx(float(actual_by_uid[lower.uid]), main_damage * RogueRules.CHORUS_FACTOR), "Actual direct damage agrees with the once-scaled primary and side shot values: " + rune_id)

func _test_frostfire_resonance() -> void:
	for rune_id: String in ["pierce", "bounce", "blast"]:
		var state: RunState = _ember_state(rune_id)
		var ember_index: int = state.weapon_index_for_uid(1)
		var equipped: Dictionary = state.loadout[ember_index]
		_check(is_equal_approx(float(equipped["resonance_bonus"]), 0.06) and is_equal_approx(state.stat("damage"), 1.15), "The ember fixture gets the same independent real local and global modifiers")
		var sim: CombatSim = _sim(state)
		var direct: CombatSim.Enemy = _target(sim, Vector2(400, 300))
		var neighbor: CombatSim.Enemy = _target(sim, Vector2(400, 350))
		for enemy: CombatSim.Enemy in [direct, neighbor]:
			var clearance: float = enemy.radius + GameCatalog.weapon("frost").projectile_radius + 1.0
			sim.fire_weapon("frost", "", enemy.position - Vector2(clearance, 0), Vector2.RIGHT)
		sim.step(STEP, Vector2.ZERO)
		_check(direct.slow_timer > 0.0 and neighbor.slow_timer > 0.0, "Actual frost collisions prime both the direct and secondary targets")
		var direct_before: float = direct.health
		var neighbor_before: float = neighbor.health
		sim._cooldowns[ember_index] = 0.0
		sim._update_weapons(0.0)
		var emitted: CombatSim.Shot
		for shot: CombatSim.Shot in sim.shots:
			if shot.active and shot.source == "ember":
				emitted = shot
		var expected: float = 29.0 * 2.0 * 1.15 * 1.06
		_check(emitted != null and is_equal_approx(emitted.damage, expected) and emitted.low_health_priority and is_equal_approx(emitted.resonance_bonus, 0.06), "Automatic frostfire emission consumes real resonance and retains candle-guided homing")
		for frame: int in 90:
			sim.step(STEP, Vector2.ZERO)
			if sim.core_activations["frostfire"] > 0:
				break
		var secondary_factor: float = RogueRules.FROSTFIRE_FACTOR + (RuneRules.blast_factor(2) if rune_id == "blast" else 0.0)
		_check(is_equal_approx(direct_before - direct.health, expected), "The direct target receives exactly one resonance-scaled primary hit: " + rune_id)
		_check(is_equal_approx(neighbor_before - neighbor.health, expected * secondary_factor), "Frostfire and optional blast scale the true local shot damage without applying resonance again: " + rune_id)
		_check(sim.core_activations["frostfire"] == 1 and direct.slow_timer == 0.0 and neighbor.slow_timer > 0.0,
			"Secondary damage to an already-slowed enemy neither consumes its slow nor recursively reactivates the core")

func _test_direct_defaults_and_pool() -> void:
	var state: RunState = _ember_state()
	var sim: CombatSim = _sim(state)
	var before: int = sim.rng.state
	var raw: CombatSim.Shot = sim.fire_weapon("ember", "", sim.player_position, Vector2.RIGHT)
	_check(raw.resonance_bonus == 0.0 and not raw.low_health_priority and is_equal_approx(raw.damage, 29.0 * 1.15),
		"A diagnostic raw fire call keeps defaultzero resonance even while an equipped weapon is supported")
	sim._release_shot(raw)
	var bounded: CombatSim.Shot = sim.fire_weapon("ember", "blast", sim.player_position, Vector2.RIGHT, 2, 2, 99.0)
	bounded.low_health_priority = true
	_check(is_equal_approx(bounded.resonance_bonus, BackpackResonance.MAX_BONUS) and is_equal_approx(bounded.damage, 29.0 * 2.0 * 1.15 * 1.18), "The shared emission API clamps explicit diagnostic resonance before any core scaling")
	sim._release_shot(bounded)
	sim._hostile_shot(sim.player_position + Vector2(120, 0), Vector2.LEFT, 8.0, "caster")
	_check(sim.shots[bounded.slot].hostile and sim.shots[bounded.slot].resonance_bonus == 0.0 and not sim.shots[bounded.slot].low_health_priority and sim.shots[bounded.slot].damage == 8.0,
		"Hostile pool reuse clears both independent local damage and candle-targeting metadata")
	_check(sim.rng.state == before and sim.core_activations["frostfire"] == 0 and sim.core_activations["bone_chorus"] == 0,
		"Direct emission and pool guards do not fabricate core events or consume RNG")

func _test_supported_hunter_kill() -> void:
	var state: RunState = _core_state("bone_chorus", "bone")
	var weapon_uid: int = int(state.loadout[0]["uid"])
	_check(state.merge_items(int(state.loadout[1]["uid"]), weapon_uid), "A core gift legally supplies a ranked weapon for the hunter encounter")
	var armor: int = _buy(state, "relic", "armor")
	_check(state.move_item(armor, Vector2i(1, 0), false), "The hunter encounter's weapon has one actual supporting relic")
	state.next_wave()
	state.finish_wave()
	_check(state.choose_altar(true), "The supported build takes the real second-wave contract")
	state.next_wave()
	var sim: CombatSim = _sim(state)
	var hunter: CombatSim.Enemy = sim.hunter
	_check(hunter != null and hunter.hunter, "The same supported build enters its accepted real hunter encounter")
	if hunter == null:
		return
	hunter.position = Vector2(400, 300)
	hunter.definition = hunter.definition.duplicate() as ContentDef
	hunter.definition.speed = 0.0
	hunter.action_timer = 9999.0
	sim._cooldowns.fill(0.0)
	for frame: int in 300:
		sim.step(STEP, Vector2.ZERO)
		if state.hunter_defeated:
			break
	_check(state.hunter_defeated and state.rune_reward_pending and not hunter.active, "Actual resonance/core projectiles can defeat the contract hunter and arm its one real reward")
