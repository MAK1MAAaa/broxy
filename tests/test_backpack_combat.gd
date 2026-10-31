extends SceneTree
## Ranked inventory projections drive the real dispatcher, collisions and paused world.

const STEP: float = 1.0 / 60.0

class SilentSoundBank extends SoundBank:
	func _ready() -> void:
		pass

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_ranked_dispatch()
	_test_more_than_four_weapons()
	_test_pierce_and_bounce()
	_test_blast_geometry()
	_test_return_and_pool()
	_test_actual_damage_accounting()
	await _test_ranked_pause()
	print("BackpackCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(starter: String = "bone") -> RunState:
	var state := RunState.new()
	state.begin(20261024, starter)
	state.gold = 10000
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	var bought: bool = state.buy_offer(0)
	_check(bought, "A test item enters through the formal backpack purchase: " + kind + ":" + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1 if bought else -1

func _obtain_rank(state: RunState, kind: String, id: String, rank: int, initial_uid: int = -1) -> int:
	var target_uid: int = _buy(state, kind, id) if initial_uid < 0 else initial_uid
	if target_uid < 0:
		return -1
	for level: int in range(1, rank):
		var source_uid: int = _obtain_rank(state, kind, id, level)
		if source_uid < 0:
			return -1
		var merged: bool = state.merge_items(source_uid, target_uid)
		_check(merged, "Same-rank formal merges produce the requested combat tier: " + id)
		if not merged:
			return -1
	return target_uid

func _with_rune(weapon_id: String, rune_id: String, rune_rank: int, weapon_rank: int = 1) -> RunState:
	var state: RunState = _state(weapon_id)
	var weapon_uid: int = int(state.loadout[0]["uid"])
	_obtain_rank(state, "weapon", weapon_id, weapon_rank, weapon_uid)
	var rune_uid: int = _obtain_rank(state, "rune", rune_id, rune_rank)
	_check(state.equip_rune(state.rune_index_for_uid(rune_uid), state.weapon_index_for_uid(weapon_uid)), "The upgraded rune is equipped through its real inventory identity")
	return state

func _sim(state: RunState) -> CombatSim:
	var simulation := CombatSim.new()
	simulation.begin(state)
	simulation.sandbox = true
	simulation.player_position = Vector2(180, 319)
	return simulation

func _target(simulation: CombatSim, point: Vector2, health: float = 10000.0) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = simulation.spawn_enemy("chaser", point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = health
	enemy.max_health = health
	enemy.action_timer = 9999.0
	return enemy

func _active_shot(simulation: CombatSim) -> CombatSim.Shot:
	for shot: CombatSim.Shot in simulation.shots:
		if shot.active and not shot.hostile:
			return shot
	return null

func _test_ranked_dispatch() -> void:
	for definition: ContentDef in GameCatalog.weapons():
		for rank: int in range(1, 4):
			var state: RunState = _state(definition.id)
			_obtain_rank(state, "weapon", definition.id, rank, int(state.loadout[0]["uid"]))
			var simulation: CombatSim = _sim(state)
			_target(simulation, simulation.player_position + Vector2(100, 0))
			simulation.step(STEP, Vector2.ZERO)
			var shot: CombatSim.Shot = _active_shot(simulation)
			_check(shot != null and simulation.shot_count == definition.shots, "All configured pellets are dispatched from the ranked backpack weapon: %s/%d" % [definition.id, rank])
			if shot != null:
				var personal_attack: float = 1.0 + 1.6 * pow(2.0, rank - 1) if definition.id == "sword_0005" else 1.0
				_check(shot.weapon_rank == rank and is_equal_approx(shot.damage, definition.damage * pow(2.0, rank - 1) * personal_attack), "The real dispatcher applies rank damage and the independently configured Durendal owner attack exactly once: %s/%d" % [definition.id, rank])
				_check(is_equal_approx(shot.velocity.length(), definition.projectile_speed) and is_equal_approx(shot.radius, definition.projectile_radius), "Rank does not silently change speed or collision size: %s/%d" % [definition.id, rank])
			_check(is_equal_approx(simulation._cooldowns[0], definition.cooldown / state.stat("attack_speed")), "Rank preserves the formal cooldown: %s/%d" % [definition.id, rank])

func _test_more_than_four_weapons() -> void:
	var state: RunState = _state()
	_check(state.expand_backpack() and state.expand_backpack(), "The full twelve-weapon fixture pays for both real row expansions")
	for index: int in 11:
		_buy(state, "weapon", "bone")
	_check(state.loadout.size() == 12 and state.backpack_snapshot()["used_cells"] == 36, "Twelve actual three-cell weapons fit the expanded backpack without an old four-slot gate")
	var simulation: CombatSim = _sim(state)
	simulation._cooldowns.fill(0.0)
	var events: Array[int] = [0]
	simulation.shot_fired.connect(func() -> void: events[0] += 1)
	_target(simulation, simulation.player_position + Vector2(150, 0))
	simulation.step(STEP, Vector2.ZERO)
	_check(simulation._cooldowns.size() == 12 and simulation.shot_count == 12 and events[0] == 12, "Every stored weapon fires, including the four beyond the visible eight-orbit display")
	var before: Array[float] = simulation._cooldowns.duplicate()
	var uid_order: Array[int] = []
	for equipped: Dictionary in state.loadout:
		uid_order.append(int(equipped["uid"]))
	var first: Dictionary = state.backpack_item(uid_order[0])
	_check(state.move_item(uid_order[0], Vector2i(first["x"], first["y"]), bool(first["rotated"])), "A valid placement transaction can retain an equipped item's origin")
	var after_order: Array[int] = []
	for equipped: Dictionary in state.loadout:
		after_order.append(int(equipped["uid"]))
	_check(uid_order == after_order and before == simulation._cooldowns, "Inventory synchronization does not reorder equipped identities or reset running cooldowns")

func _test_pierce_and_bounce() -> void:
	for weapon_id: String in ["bone", "return_ring"]:
		for rune_id: String in ["pierce", "bounce"]:
			for rank: int in range(1, 4):
				var state: RunState = _with_rune(weapon_id, rune_id, rank)
				var simulation: CombatSim = _sim(state)
				var targets: Array[CombatSim.Enemy] = []
				for index: int in 8:
					targets.append(_target(simulation, simulation.player_position + Vector2(50 + index * 18, 0)))
				var birth_delta: float = 0.5 if rune_id == "pierce" else 0.1
				simulation.step(birth_delta, Vector2.ZERO)
				simulation._cooldowns.fill(9999.0)
				for frame: int in 80:
					if simulation.shot_count == 0:
						break
					simulation.step(0.05, Vector2.ZERO)
				var innate: int = GameCatalog.weapon(weapon_id).innate_pierce
				var expected_hits: int = 1 + innate + rank + 1
				_check(simulation.primary_hits == expected_hits and simulation.secondary_hits == 0, "Ranked %s exhausts its exact full-flight direct budget: %s/%d" % [rune_id, weapon_id, rank])
				var direct_damage: float = GameCatalog.weapon(weapon_id).damage
				for index: int in expected_hits:
					var scale: float = 1.0 if rune_id == "pierce" or index <= innate else pow(0.75, index - innate)
					_check(is_equal_approx(10000.0 - targets[index].health, direct_damage * scale), "Actual damage preserves native full hits and bounce decay for %s/%s/%d target%d" % [weapon_id, rune_id, rank, index])
				_check(simulation.shot_count == 0, "The ranked flight is consumed rather than obtaining another budget")

func _test_blast_geometry() -> void:
	for rank: int in range(1, 4):
		var state: RunState = _with_rune("bone", "blast", rank)
		var simulation: CombatSim = _sim(state)
		simulation.player_position = Vector2(280, 319)
		var primary: CombatSim.Enemy = _target(simulation, Vector2(400, 319))
		var radius: float = 68.0 + float(rank - 1) * 10.0
		var inside: CombatSim.Enemy = _target(simulation, primary.position + Vector2(0, radius + primary.radius - 1.0))
		var outside: CombatSim.Enemy = _target(simulation, primary.position + Vector2(0, radius + primary.radius + 1.0))
		var activations: Array[int] = [0]
		simulation.rune_activated.connect(func(id: String, _origin: Vector2, _incoming: Vector2, _outgoing: Vector2) -> void: activations[0] += 1 if id == "blast" else 0)
		simulation.step(0.25, Vector2.ZERO)
		var factor: float = 0.55 + float(rank - 1) * 0.10
		_check(simulation.primary_hits == 1 and simulation.secondary_hits == 1 and activations[0] == 1, "Ranked blast has one primary, one legal secondary and no recursive rune trigger")
		_check(is_equal_approx(10000.0 - primary.health, 14.0) and is_equal_approx(10000.0 - inside.health, 14.0 * factor) and outside.health == 10000.0, "The real grid query uses the ranked blast radius and damage, including the next cell row")
		_check(simulation.shot_count == 0 and simulation.effects.size() == 1 and simulation.effects[0].radius == radius, "The visible blast radius matches the real collision query")
	_check(RuneRules.extra_hits(0) == 2 and RuneRules.extra_hits(99) == 4 and RuneRules.blast_radius(0) == 68.0 and RuneRules.blast_radius(99) == 88.0, "Out-of-range diagnostic ranks clamp to the supported three tiers")

func _test_return_and_pool() -> void:
	var state: RunState = _with_rune("return_ring", "pierce", 3, 3)
	var simulation: CombatSim = _sim(state)
	var target: CombatSim.Enemy = _target(simulation, simulation.player_position + Vector2(80, 0))
	simulation.step(STEP, Vector2.ZERO)
	simulation._cooldowns.fill(9999.0)
	var shot: CombatSim.Shot = _active_shot(simulation)
	_check(shot != null and shot.weapon_rank == 3 and shot.rune_rank == 3 and shot.remaining == 4 and shot.life <= 2.4, "A formally merged return ring retains both tiers and the original hard lifetime")
	var health: float = state.health
	var gold: int = state.gold
	for frame: int in 100:
		if simulation.shot_count == 0:
			break
		simulation.step(STEP, Vector2.ZERO)
	_check(simulation.primary_hits == 1 and is_equal_approx(10000.0 - target.health, 64.0), "Ranked returning flight shares its UID set and does not hit the same target twice")
	_check(simulation.shot_count == 0 and state.health == health and state.gold == gold, "Recovering a ranked return ring still grants no health, gold or bonus projectile")
	var reused: CombatSim.Shot = simulation.fire_weapon("bone", "pierce", simulation.player_position, Vector2.RIGHT)
	_check(reused != null and reused.weapon_rank == 1 and reused.rune_rank == 1 and reused.remaining == 2 and not reused.returning and not reused.return_cancelled, "Pool reuse clears rank and returning state for a default old-style fire call")
	simulation._release_shot(reused)
	simulation._hostile_shot(simulation.player_position + Vector2(100, 0), Vector2.LEFT, 8.0, "caster")
	var hostile: CombatSim.Shot = simulation.shots[reused.slot]
	_check(hostile.active and hostile.hostile and hostile.weapon_rank == 1 and hostile.rune_rank == 1, "Hostile rounds cannot inherit a previously upgraded friendly rune")

func _test_actual_damage_accounting() -> void:
	var state: RunState = _state()
	_obtain_rank(state, "weapon", "bone", 3, int(state.loadout[0]["uid"]))
	var simulation: CombatSim = _sim(state)
	var target: CombatSim.Enemy = _target(simulation, simulation.player_position + Vector2(50, 0), 50.0)
	simulation.step(0.1, Vector2.ZERO)
	_check(not target.active and simulation.damage_by_weapon.get("bone", 0.0) == 50.0 and state.damage_dealt_by_weapon.get("bone", 0.0) == 50.0, "Tier-three overkill records actual lost health under its original weapon source")
	var elapsed_before: float = simulation.elapsed
	simulation._finish(false, "fixture terminal")
	var before: Dictionary = state.summary()
	simulation.step(1.0, Vector2.RIGHT)
	_check(simulation.elapsed == elapsed_before and state.summary() == before, "Ranked projectiles preserve terminal freeze")

func _test_ranked_pause() -> void:
	var state: RunState = _with_rune("return_ring", "bounce", 3, 2)
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	var shot: CombatSim.Shot = world.sim.fire_weapon("return_ring", "bounce", world.sim.player_position, Vector2.RIGHT, 2, 3)
	var before: Array = [world.sim.elapsed, shot.position, shot.life, shot.return_after, shot.weapon_rank, shot.rune_rank, world.sim.rng.state, state.rng.state]
	paused = true
	for frame: int in 3:
		await process_frame
	var after: Array = [world.sim.elapsed, shot.position, shot.life, shot.return_after, shot.weapon_rank, shot.rune_rank, world.sim.rng.state, state.rng.state]
	_check(before == after and world.active, "Actual SceneTree pause freezes a ranked return projectile without replacing the active simulation")
	paused = false
	await physics_frame
	await physics_frame
	await process_frame
	world.set_physics_process(false)
	_check(world.sim.elapsed > float(before[0]) and shot.life < float(before[2]) and shot.rune_rank == 3, "Resuming continues the same ranked flight with its tier intact")
	world.queue_free()
	sound.queue_free()
	await process_frame
