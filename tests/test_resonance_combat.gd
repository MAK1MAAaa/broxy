extends SceneTree
## Stored geometry drives local damage without changing raw-fire fixtures or rune budgets.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_dispatch_and_movement()
	_test_runes_and_pool()
	_test_merge_and_freeze()
	print("ResonanceCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(starter: String = "bone") -> RunState:
	var state := RunState.new()
	state.begin(20261025, starter)
	state.gold = 10000
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	state.offers = [{"kind": kind, "id": id, "price": 20, "sold": false}]
	_check(state.buy_offer(0), "Combat fixture uses a real purchase: " + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1

func _sim(state: RunState) -> CombatSim:
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.player_position = Vector2(220, 320)
	return sim

func _target(sim: CombatSim, offset: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + offset)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = 10000.0
	enemy.max_health = enemy.health
	enemy.action_timer = 9999.0
	return enemy

func _shot(sim: CombatSim, source: String) -> CombatSim.Shot:
	for shot: CombatSim.Shot in sim.shots:
		if shot.active and not shot.hostile and shot.source == source:
			return shot
	return null

func _test_dispatch_and_movement() -> void:
	for definition: ContentDef in GameCatalog.weapons():
		var state: RunState = _state(definition.id)
		var relic: int = _buy(state, "relic", "armor")
		var size: Vector2i = definition.inventory_size
		_check(state.move_item(relic, Vector2i(size.x, 0), false), "A support relic is placed on the weapon's exact edge")
		var sim: CombatSim = _sim(state)
		_target(sim, Vector2(150, 0))
		sim.step(STEP, Vector2.ZERO)
		var shot: CombatSim.Shot = _shot(sim, definition.id)
		_check(shot != null and is_equal_approx(shot.resonance_bonus, 0.03), "Every weapon receives its own cached support bonus: " + definition.id)
		if shot != null:
			_check(is_equal_approx(shot.damage, definition.damage * 1.03) and is_equal_approx(shot.damage, state.weapon_damage(state.loadout[0])), "Real dispatch and the projected per-hit damage agree")
		_check(is_equal_approx(sim._cooldowns[0], definition.cooldown), "Resonance leaves the existing nominal firing interval intact")
		_check(state.move_item(relic, Vector2i(5, 3), false), "Moving the support away commits through the real grid")
		for active: CombatSim.Shot in sim.shots:
			if active.active:
				sim._release_shot(active)
		sim._cooldowns.fill(0.0)
		sim.step(STEP, Vector2.ZERO)
		shot = _shot(sim, definition.id)
		_check(shot != null and shot.resonance_bonus == 0.0 and is_equal_approx(shot.damage, definition.damage), "Later shots use the newly arranged layout rather than a stale bonus")

func _test_runes_and_pool() -> void:
	var state: RunState = _state()
	var sim: CombatSim = _sim(state)
	var first: CombatSim.Enemy = _target(sim, Vector2(65, 0))
	var second: CombatSim.Enemy = _target(sim, Vector2(115, 0))
	sim._cooldowns.fill(9999.0)
	sim._rebuild_grid()
	var shot: CombatSim.Shot = sim.fire_weapon("bone", "bounce", sim.player_position, Vector2.RIGHT, 2, 3, 0.18)
	var damage: float = 14.0 * 2.0 * 1.18
	_check(is_equal_approx(shot.damage, damage) and shot.remaining == 4, "Rank, resonance and rune target budget are independent factors")
	for frame: int in 30:
		if not second.health == 10000.0:
			break
		sim.step(STEP, Vector2.ZERO)
	_check(is_equal_approx(10000.0 - first.health, damage) and is_equal_approx(10000.0 - second.health, damage * 0.75), "Actual bounce hits retain the local damage and the existing per-jump decay")
	for active: CombatSim.Shot in sim.shots:
		if active.active:
			sim._release_shot(active)
	shot = sim.fire_weapon("bone", "", sim.player_position, Vector2.RIGHT)
	_check(shot.resonance_bonus == 0.0 and shot.weapon_rank == 1 and is_equal_approx(shot.damage, 14.0), "A default raw fire call does not inherit the previous pool slot's resonance")
	sim._release_shot(shot)
	shot = sim.fire_weapon("bone", "blast", sim.player_position, Vector2.RIGHT, 1, 1, 8.0)
	var first_health_before: float = first.health
	var second_health_before: float = second.health
	for frame: int in 20:
		if not shot.active:
			break
		sim.step(STEP, Vector2.ZERO)
	_check(is_equal_approx(shot.resonance_bonus, 0.18) and is_equal_approx(first_health_before - first.health, 14.0 * 1.18) and is_equal_approx(second_health_before - second.health, 14.0 * 1.18 * 0.55), "Explicit bonuses obey the ceiling in actual direct damage and secondary blast damage")
	shot = sim.fire_weapon("bone", "", sim.player_position, Vector2.RIGHT, 1, 1, NAN)
	_check(shot.resonance_bonus == 0.0 and is_finite(shot.damage), "Non-finite diagnostic input cannot create invalid combat damage")
	sim._release_shot(shot)
	sim._hostile_shot(sim.player_position + Vector2(160, 0), Vector2.LEFT, 8.0, "caster")
	_check(sim.shots[shot.slot].hostile and sim.shots[shot.slot].resonance_bonus == 0.0 and sim.shots[shot.slot].damage == 8.0, "Hostile pool reuse remains independent of backpack damage bonuses")

func _test_merge_and_freeze() -> void:
	var state: RunState = _state()
	var duplicate: int = _buy(state, "weapon", "bone")
	var relic: int = _buy(state, "relic", "armor")
	_check(state.move_item(relic, Vector2i(1, 3), false), "The merge fixture uses a legal edge-support location")
	var preview: Dictionary = state.merge_preview(duplicate, 1)
	_check(state.merge_items(duplicate, 1), "The supported duplicate merges through the real atomic transaction")
	var sim: CombatSim = _sim(state)
	_target(sim, Vector2(150, 0))
	sim.step(STEP, Vector2.ZERO)
	var shot: CombatSim.Shot = _shot(sim, "bone")
	_check(shot != null and is_equal_approx(shot.damage, float(preview["damage_after"])), "The merged weapon fires its previewed post-layout damage")
	var before: Array = [shot.damage, shot.resonance_bonus, shot.position, sim.elapsed]
	sim._finish(false, "fixture terminal")
	sim.step(1.0, Vector2.RIGHT)
	_check(before == [shot.damage, shot.resonance_bonus, shot.position, sim.elapsed], "Terminal state freezes already fired resonance projectiles")
