extends SceneTree
## Real backpack ownership, cast identity and accepted damage drive both active slots.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_ownership_and_clocks()
	_test_fixed_step_requests()
	_test_pulse_locking()
	_test_starfall_targeting()
	_test_arc_geometry_and_damage()
	_test_ranks_and_boss()
	print("ActiveSkillCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _sim(ids: Array[String] = [], rank: int = 1, wave: int = 1) -> CombatSim:
	var state := RunState.new()
	state.begin(20261028, "bone")
	for id: String in ids:
		_check(not state.backpack.add("skill", id, 0, rank).is_empty(), "The fixture owns a real skill box: " + id)
	state._sync_backpack_projection()
	state.wave = wave
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim

func _enemy(sim: CombatSim, point: Vector2, health: float = 1000.0) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", point)
	enemy.health = health
	enemy.max_health = health
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _events(sim: CombatSim) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	sim.active_skill_cast.connect(func(id: String, uid: int, origin: Vector2, direction: Vector2, affected: int, rank: int) -> void:
		result.append({"id": id, "uid": uid, "origin": origin, "direction": direction, "affected": affected, "rank": rank}))
	return result

func _test_ownership_and_clocks() -> void:
	var sim: CombatSim = _sim()
	var events: Array[Dictionary] = _events(sim)
	_check(not sim.try_pulse() and not sim.try_active_skill(0) and not sim.try_active_skill(1), "No active ability exists before a real box enters the backpack")
	sim._try_cast_pulse()
	sim.step(STEP, Vector2.RIGHT, true, true)
	_check(events.is_empty() and sim.pulses_used == 0 and not sim.pulse_snapshot()["available"] and not sim.pulse_snapshot()["ready"] and sim.dashes_used == 1,
		"Legacy pulse input cannot bypass ownership while the innate dash remains usable")
	_check(sim.active_skill_snapshots().size() == 2 and sim.snapshot()["skills"] == sim.active_skill_snapshots() and not sim.active_skill_snapshot(-1)["available"] and not sim.active_skill_snapshot(2)["available"],
		"HUD projections expose exactly two safe slots and reject invalid indices")
	sim = _sim(["pulse", "arc_slash"])
	var first: int = int(sim.active_skill_snapshot(0)["uid"])
	var second: int = int(sim.active_skill_snapshot(1)["uid"])
	_check(sim.try_active_skill(1, second) and not sim.try_active_skill(1, second), "A real UID can consume its ready slot once")
	_check(sim.run.sell_item(first), "Selling the other real box shifts the second skill to the first slot")
	var moved: Dictionary = sim.active_skill_snapshot(0)
	_check(moved["uid"] == second and moved["cooldown_remaining"] == 6.0 and moved["uses"] == 1 and not moved["ready"], "Cooldown and uses follow UID through slot changes")
	sim.step(1.0, Vector2.ZERO, false, false, [{"slot": 0, "uid": first}])
	_check(sim.active_skill_snapshot(0)["cooldown_remaining"] == 5.0 and sim.active_skill_snapshot(0)["uses"] == 1, "A stale queued UID is dropped without redirecting the cast to the new occupant")
	var snapshot: Dictionary = sim.active_skill_snapshot(0)
	var rng_before: Array = [sim.rng.state, sim.run.rng.state]
	snapshot["radius"] = 99999.0
	_check(sim.active_skill_snapshot(0)["radius"] == 148.0 and rng_before == [sim.rng.state, sim.run.rng.state], "Skill snapshots are detached, read-only projections without RNG consumption")
	sim.run.backpack.remove(second)
	_check(not sim.try_active_skill(0, second) and not sim.active_skill_snapshot(0)["available"], "Even a stale state projection cannot cast a UID removed from the actual backpack")

func _test_fixed_step_requests() -> void:
	for delta: float in [0.0, -1.0, INF, NAN]:
		var invalid: CombatSim = _sim(["arc_slash"])
		var uid: int = int(invalid.active_skill_snapshot(0)["uid"])
		var before: Dictionary = invalid.snapshot()
		invalid.step(delta, Vector2.RIGHT, true, false, [{"slot": 0, "uid": uid}])
		_check(invalid.snapshot() == before and invalid.elapsed == 0.0, "Invalid fixed-step time consumes neither the skill request nor simulation time")
	var sim: CombatSim = _sim(["arc_slash", "pulse"])
	var origin: Vector2 = sim.player_position
	sim.player_direction = Vector2.LEFT
	var upper: CombatSim.Enemy = _enemy(sim, origin + Vector2(0, -100))
	var left: CombatSim.Enemy = _enemy(sim, origin + Vector2(-100, 0))
	var events: Array[Dictionary] = _events(sim)
	var first: int = int(sim.active_skill_snapshot(0)["uid"])
	var second: int = int(sim.active_skill_snapshot(1)["uid"])
	sim.step(STEP, Vector2.UP * 0.01, true, false, [{"slot": 0, "uid": first}, {"slot": 1, "uid": second}])
	_check(events.size() == 2 and events[0]["origin"] == origin and events[1]["origin"] == origin and events[0]["direction"].is_equal_approx(Vector2.UP), "Both skills cast at the pre-dash origin using the current light-stick direction")
	_check(upper.health == 976.0 and left.health == 1000.0 and sim.dashes_used == 1 and sim.player_position.y < origin.y, "The current-frame cone lands before the innate dash moves the player")
	_check(is_equal_approx(float(sim.active_skill_snapshot(0)["cooldown_remaining"]), 6.0 - STEP) and is_equal_approx(float(sim.active_skill_snapshot(1)["cooldown_remaining"]), 8.0 - STEP), "Both UID cooldown clocks consume the physical casting frame once")
	sim = _sim(["pulse"])
	var pulse_events: Array[int] = [0]
	sim.pulse_cast.connect(func(_origin: Vector2, _affected: int) -> void: pulse_events[0] += 1)
	first = int(sim.active_skill_snapshot(0)["uid"])
	sim.step(STEP, Vector2.ZERO, false, true, [{"slot": 0, "uid": first}, {"slot": 0, "uid": first}])
	_check(pulse_events[0] == 1 and sim.pulses_used == 1, "Legacy and generic requests cannot duplicate a pulse or its compatibility signal")
	sim.run.health = 0.0
	sim.step(10.0, Vector2.RIGHT, true, true, [{"slot": 0, "uid": first}])
	_check(sim.pulses_used == 1 and not sim.active_skill_snapshot(0)["ready"], "Death rejects queued skills before cooldown expiry or movement can revive their readiness")

func _test_pulse_locking() -> void:
	var sim: CombatSim = _sim(["pulse"])
	var uid: int = int(sim.active_skill_snapshot(0)["uid"])
	var origin: Vector2 = sim.player_position
	var ordinary: CombatSim.Enemy = _enemy(sim, origin + Vector2(144, 0))
	var boss_target: CombatSim.Enemy = sim.spawn_enemy("boss", origin + Vector2(80, 0))
	var hunter: CombatSim.Enemy = _enemy(sim, origin + Vector2(-80, 0))
	hunter.hunter = true
	_check(sim.try_pulse() and ordinary.position == origin + Vector2(214, 0) and ordinary.pulse_hinder_timer == 1.0 and boss_target.position == origin + Vector2(80, 0) and hunter.position == origin + Vector2(-80, 0), "The owned pulse retains radial push, independent hindrance and boss/hunter immunity")
	var source: Dictionary = sim.run.backpack.add("skill", "pulse")
	_check(sim.run.merge_items(int(source["uid"]), uid), "The real backpack upgrades the casting pulse UID")
	_check(not sim.run.backpack.add("relic", "echo_stone").is_empty(), "Echo stone enters the same real inventory")
	sim.run._sync_backpack_projection()
	var locked: Dictionary = sim.active_skill_snapshot(0)
	_check(locked["rank"] == 1 and locked["radius"] == 144.0 and locked["cooldown_duration"] == 8.0 and locked["cooldown_remaining"] == 8.0, "Rank and relic changes cannot rewrite an existing cast or refund its cooldown")
	_check(sim.pulse_snapshot()["last_cast_radius"] == 144.0 and sim.pulse_snapshot()["radius"] == 174.0 and sim.damage_by_skill.is_empty(), "Legacy pulse statistics retain the last cast while forecasting the next upgraded radius without damage")
	sim._update_pulse(8.0, false)
	_check(sim.try_active_skill(0, uid) and sim.last_pulse_radius == 174.0 and is_equal_approx(float(sim.active_skill_snapshot(0)["cooldown_duration"]), 8.8), "The next actual pulse locks the merged rank and current echo-stone values")

func _test_starfall_targeting() -> void:
	var sim: CombatSim = _sim(["starfall"])
	var origin: Vector2 = sim.player_position
	var nearest: CombatSim.Enemy = _enemy(sim, origin + Vector2(180, 0))
	var edge: CombatSim.Enemy = _enemy(sim, nearest.position + Vector2(0, 112))
	var outside: CombatSim.Enemy = _enemy(sim, nearest.position + Vector2(0, 112.01))
	var events: Array[Dictionary] = _events(sim)
	_check(sim.try_active_skill(0) and events[0]["origin"] == nearest.position and events[0]["affected"] == 2, "Starfall centers its real hit on the closest live enemy within 320 pixels")
	_check(nearest.health == 968.0 and edge.health == 968.0 and outside.health == 1000.0, "The starfall center query includes exactly its 112-pixel edge without inflating by enemy collision radius")
	for distance: float in [320.0, 320.01]:
		sim = _sim(["starfall"])
		origin = sim.player_position
		_enemy(sim, origin + Vector2(distance, 0))
		events = _events(sim)
		sim.try_active_skill(0)
		var expected: Vector2 = origin + Vector2(distance if distance == 320.0 else 140.0, 0)
		_check(events[0]["origin"] == expected, "Starfall includes the target-search boundary and otherwise uses its deterministic forward fallback")
	sim = _sim(["starfall"])
	sim.player_position = CombatSim.ARENA.end - Vector2(10, 10)
	sim.player_direction = Vector2(1, 1)
	events = _events(sim)
	var rng_before: Array = [sim.rng.state, sim.run.rng.state]
	sim.try_active_skill(0)
	_check(events[0]["origin"] == CombatSim.ARENA.end and events[0]["affected"] == 0 and rng_before == [sim.rng.state, sim.run.rng.state], "An empty cast clamps its fallback to the arena without RNG or invented hits")

func _test_arc_geometry_and_damage() -> void:
	var sim: CombatSim = _sim(["arc_slash"])
	var origin: Vector2 = sim.player_position
	var center: CombatSim.Enemy = _enemy(sim, origin)
	var front: CombatSim.Enemy = _enemy(sim, origin + Vector2(100, 0), 10.0)
	var edge: CombatSim.Enemy = _enemy(sim, origin + Vector2.from_angle(deg_to_rad(50.0)) * 148.0)
	var wide: CombatSim.Enemy = _enemy(sim, origin + Vector2.from_angle(deg_to_rad(50.01)) * 100.0)
	var far: CombatSim.Enemy = _enemy(sim, origin + Vector2(148.01, 0))
	var behind: CombatSim.Enemy = _enemy(sim, origin + Vector2(-40, 0))
	var rune: Dictionary = sim.run.backpack.add("rune", "blast")
	_check(sim.run.backpack.equip(int(rune["uid"]), int(sim.run.loadout[0]["uid"])), "The no-chain fixture equips an actual explosion rune on the weapon")
	sim.run._sync_backpack_projection()
	var events: Array[Dictionary] = _events(sim)
	var damage_events: Array[Dictionary] = []
	var rune_events: Array[int] = [0]
	sim.rune_activated.connect(func(_id: String, _point: Vector2, _incoming: Vector2, _outgoing: Vector2) -> void: rune_events[0] += 1)
	sim.damage_dealt.connect(func(point: Vector2, amount: float, source: String, secondary: bool, uid: int) -> void:
		damage_events.append({"point": point, "amount": amount, "source": source, "secondary": secondary, "uid": uid}))
	sim.try_active_skill(0)
	_check(center.health == 976.0 and not front.active and edge.health == 976.0 and wide.health == 1000.0 and far.health == 1000.0 and behind.health == 1000.0 and events[0]["affected"] == 3,
		"The one-hundred-degree slash includes coincident centers, the angular edge and radial edge once")
	_check(damage_events.size() == 3 and damage_events.all(func(event: Dictionary) -> bool: return event["source"] == "skill:arc_slash" and not event["secondary"]), "Skill damage emits accepted target UIDs and the dedicated source through the real damage pipeline")
	_check(sim.damage_by_skill == {"arc_slash": 58.0} and sim.skill_hits == 3 and sim.damage_by_weapon.is_empty() and sim.run.damage_dealt_by_weapon.is_empty() and sim.primary_hits == 0 and sim.secondary_hits == 0,
		"Actual damage is clamped to remaining health and belongs exclusively to skill statistics")
	_check(sim.run.kills == 1 and sim.soul_count == 1 and rune_events[0] == 0 and sim.shot_count == 0, "A slash kill produces its real drop without triggering weapon runes, extra shots or secondary chains")

func _test_ranks_and_boss() -> void:
	for id: String in ["starfall", "arc_slash"]:
		for rank: int in range(1, 4):
			var sim: CombatSim = _sim([id], rank)
			_check(not sim.run.backpack.add("relic", "echo_stone").is_empty(), "Damage-skill fixture owns an echo stone")
			sim.run._sync_backpack_projection()
			var target: CombatSim.Enemy = _enemy(sim, sim.player_position + Vector2(100, 0))
			var parameters: Dictionary = ActiveSkillRules.parameters(id, rank, {"damage": sim.run.stat("damage")})
			sim.try_active_skill(0)
			var current: Dictionary = sim.active_skill_snapshot(0)
			_check(target.health == 1000.0 - float(parameters["damage"]) and current["radius"] == parameters["radius"] and current["cooldown_duration"] == parameters["cooldown"] and current["rank"] == rank,
				"Each damage-skill rank uses global damage and its own radius/cooldown without echo-stone pulse modifiers: " + id + str(rank))
	var sim: CombatSim = _sim(["pulse", "arc_slash"], 1, 8)
	sim.player_position = sim.boss.position - Vector2(100, 0)
	var boss_origin: Vector2 = sim.boss.position
	sim.boss.health = 10.0
	sim.try_active_skill(0)
	_check(sim.boss.position == boss_origin and sim.boss.health == 10.0 and sim.last_pulse_affected == 0, "A real wave boss remains immune to the owned pulse")
	_check(sim.try_active_skill(1) and sim.complete and sim.victory and sim.run.kills == 1 and sim.damage_by_skill == {"arc_slash": 10.0}, "An output skill can kill the real boss and complete the wave through normal settlement")
	var final: Dictionary = sim.snapshot()
	_check(not sim.try_active_skill(1) and not sim.try_pulse(), "Terminal state rejects both owned active skill APIs")
	sim.step(10.0, Vector2.LEFT, true, true, [{"slot": 1, "uid": int(sim.run.active_skills[1]["uid"])}])
	_check(sim.snapshot() == final, "Terminal queued input cannot advance active clocks or replay the finishing cast")
