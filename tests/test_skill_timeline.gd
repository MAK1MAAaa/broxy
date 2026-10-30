extends SceneTree
## Real delayed R contacts, temporary conditions, reserved bombs and lifecycle boundaries.

const STEP: float = 1.0 / 60.0
const HEALTH: float = 1000000.0
var _checks: int = 0
var _failures: int = 0

class QuietSound extends SoundBank:
	func _ready() -> void:
		pass
	func play(_name: String, _loudness: float = -10.0) -> void:
		pass
	func play_cue(_name: String, _loudness: float, _cue_id: String) -> void:
		pass

class TimelineWorld extends CombatWorld:
	func _ready() -> void:
		pass
	func _draw() -> void:
		pass
	func _movement() -> Vector2:
		return Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(hero_id: String) -> RunState:
	var state := RunState.new()
	state.begin(20261031, "", "reliquary", hero_id)
	return state

func _quiet(sim: CombatSim) -> void:
	sim.sandbox = true
	sim.invulnerability = 99999.0
	sim._cooldowns.fill(99999.0)
	sim.obstacles.configure([])
	sim.interactions = ArenaInteractions.new()
	sim.player_position = Vector2(640, 360)
	sim.player_direction = Vector2.RIGHT

func _sim(hero_id: String) -> CombatSim:
	var sim := CombatSim.new()
	sim.begin(_state(hero_id))
	_quiet(sim)
	return sim

func _target(sim: CombatSim, offset: Vector2, id: String = "tank") -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, sim.player_position + offset, true)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = HEALTH
	enemy.max_health = HEALTH
	enemy.action_timer = 99999.0
	return enemy

func _step(sim: CombatSim, frames: int) -> void:
	for frame: int in frames:
		sim.step(STEP, Vector2.ZERO)

func _record(sim: CombatSim, target_uid: int, source_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var weak_sim: WeakRef = weakref(sim)
	sim.damage_dealt.connect(func(_position: Vector2, amount: float, source: String, _secondary: bool, uid: int) -> void:
		if uid != target_uid or source != source_id:
			return
		var current: CombatSim = weak_sim.get_ref() as CombatSim
		if current == null:
			return
		var weakness: float = 0.0
		for enemy: CombatSim.Enemy in current.enemies:
			if enemy.active and enemy.uid == uid:
				weakness = enemy.fire_vulnerability if enemy.fire_vulnerability_left > 0.0 else 0.0
				break
		events.append({"time": current.elapsed, "amount": amount, "weakness_before": weakness})
	)
	return events

func _run() -> void:
	_test_recorder_releases_sim()
	_test_alk_delay_and_uid()
	_test_clarisse_timing_and_weakness()
	_test_fire_skill_buff_scope()
	_test_clarisse_late_dispel()
	_test_dispel_preserves_intrinsic_boss_state()
	_test_contact_separation()
	_test_compiled_contact_geometry()
	_test_contact_geometry_callback_refresh()
	_test_reentrant_enemy_slot_reuse()
	_test_reentrant_kill_without_replacement()
	_test_celtie_rectangle_and_combo()
	_test_hanabi_reservations_and_sweep()
	_test_hanabi_held_impacts()
	_test_validation_and_atomic_capacity()
	_test_snapshot_and_large_delta()
	_test_vulnerability_expiry_across_steps()
	await _test_world_pause_and_cleanup()
	print("SkillTimeline: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_recorder_releases_sim() -> void:
	var sim: CombatSim = _sim("clarisse")
	var reference: WeakRef = weakref(sim)
	var events: Array[Dictionary] = _record(sim, -1, "skill:hero_clarisse")
	sim = null
	_check(reference.get_ref() == null and events.is_empty(), "A connected damage recorder does not retain its RefCounted simulation or pooled resources")

func _test_alk_delay_and_uid() -> void:
	var sim: CombatSim = _sim("alk")
	var enemy: CombatSim.Enemy = _target(sim, Vector2(80, 0))
	var uid: int = enemy.uid
	var slot: int = enemy.slot
	_check(sim.try_hero_skill(), "Alk reserves its real delayed shockwave")
	var damage: float = float(sim.hero_skill_snapshot()["damage"])
	_check(sim.hero_effects.attack_left > 0.0 and is_equal_approx(sim.hero_effects.attack_multiplier(), 1.2), "Alk attack power starts at the cast, before its delayed shockwave")
	var shot: CombatSim.Shot = sim.fire_weapon("bone", "", sim.player_position, Vector2.RIGHT)
	_check(shot != null and is_equal_approx(shot.damage, GameCatalog.weapon("bone").damage * sim.run.stat("damage") * 1.2), "The opening buff already affects a real weapon shot")
	if shot != null:
		sim._release_shot(shot)
	_step(sim, 43)
	_check(enemy.health == HEALTH and sim.skill_hits == 0 and int(sim.skill_timeline.snapshot()["occupied"]) == 1, "The first 43 adapted action units cannot deal Alk damage")
	_step(sim, 1)
	_check(is_equal_approx(HEALTH - enemy.health, damage) and sim.skill_hits == 1, "Action unit 44 opens the real damage area")
	_step(sim, 7)
	_check(is_equal_approx(HEALTH - enemy.health, damage) and sim.skill_hits == 1, "A UID is hit once throughout the original 20-unit lifetime")
	sim.apply_damage(enemy, HEALTH * 2.0, "fixture")
	var replacement: CombatSim.Enemy = _target(sim, Vector2(80, 0))
	_check(replacement.slot == slot and replacement.uid != uid, "The contact fixture really reuses a dead enemy pool slot with a new UID")
	_step(sim, 1)
	_check(is_equal_approx(HEALTH - replacement.health, damage) and sim.skill_hits == 2, "A new UID can enter the still-live area despite sharing the old pool slot")
	_step(sim, 13)
	_check(int(sim.skill_timeline.snapshot()["occupied"]) == 0 and sim.skill_hits == 2, "Alk releases its area after delay 44 plus lifetime 20 without re-hitting either UID")
	var late: CombatSim.Enemy = _target(sim, Vector2(-80, 0))
	_step(sim, 1)
	_check(late.health == HEALTH, "An expired shockwave cannot hit a later arrival")

func _test_clarisse_timing_and_weakness() -> void:
	var sim: CombatSim = _sim("clarisse")
	var enemy: CombatSim.Enemy = _target(sim, Vector2(160, 0))
	var events: Array[Dictionary] = _record(sim, enemy.uid, "skill:hero_clarisse")
	_check(sim.try_hero_skill(), "Clarisse reserves two damage phases and its independent dispel area")
	var damage: float = float(sim.hero_skill_snapshot()["damage"])
	_check(int(sim.skill_timeline.snapshot()["occupied"]) == 3 and enemy.health == HEALTH, "All three real areas wait without an instant cast hit")
	_step(sim, 41)
	_check(events.is_empty() and enemy.fire_vulnerability_left == 0.0, "Clarisse cannot damage or weaken targets before action unit 42")
	_step(sim, 1)
	_check(events.size() == 1 and enemy.fire_vulnerability_left > 0.0, "The first real contact deals damage then applies fire weakness")
	_step(sim, 16)
	_check(events.size() == 4, "The first 16-unit window produces four real contacts")
	_step(sim, 20)
	_check(events.size() == 4, "The gap before action unit 79 has no invented damage ticks")
	_step(sim, 1)
	_check(events.size() == 5, "Action unit 79 begins the distinct eleven-hit phase")
	_step(sim, 69)
	_check(events.size() == 15 and sim.skill_hits == 15, "The final JP phases deliver exactly four plus eleven actual hits")
	if events.size() != 15:
		return
	for index: int in events.size():
		var scheduled: float = (42.0 + float(index) * 4.0) * STEP if index < 4 else (79.0 + float(index - 4) * 67.0 / 11.0) * STEP
		var actual: float = float(events[index]["time"])
		_check(actual + 0.000001 >= scheduled and actual <= scheduled + STEP + 0.000001, "The actual contact is distributed across its phase, not collapsed at cast time: %d" % index)
		var part: float = damage * (0.15 / 4.0 if index < 4 else 0.85 / 11.0)
		var weakness: float = 0.0 if index == 0 else 0.25
		_check(is_equal_approx(float(events[index]["weakness_before"]), weakness) and is_equal_approx(float(events[index]["amount"]), part * (1.0 + weakness)), "Damage observes the prior weakness; this contact applies the next weakness afterwards: %d" % index)
	_check(sim.damage_by_weapon.is_empty() and int(sim.skill_timeline.snapshot()["occupied"]) == 0, "All distributed damage stays in hero statistics and every phase is released")

func _test_fire_skill_buff_scope() -> void:
	var sim: CombatSim = _sim("clarisse")
	_check(not sim.run.backpack.add("skill", "starfall").is_empty() and not sim.run.backpack.add("skill", "arc_slash").is_empty(), "Elemental scope uses real owned fire and wind rear skills")
	sim.run._sync_backpack_projection()
	var fire_base: float = float(sim.run.active_skill_parameters(sim.run.active_skills[0])["damage"])
	var wind_base: float = float(sim.run.active_skill_parameters(sim.run.active_skills[1])["damage"])
	_check(sim.try_hero_skill() and sim.hero_effects.skill_left > 0.0, "The fire skill buff starts immediately with Clarisse's cast")
	_check(sim.try_active_skill(0) and is_equal_approx(float(sim.active_skill_snapshot(0)["damage"]), fire_base * 1.25), "The fire rear skill receives the actual fire-only skill modifier once")
	_check(sim.try_active_skill(1) and is_equal_approx(float(sim.active_skill_snapshot(1)["damage"]), wind_base), "The wind rear skill does not receive the fire-only modifier")
	var weapon: CombatSim.Shot = sim.fire_weapon("ember", "", sim.player_position, Vector2.RIGHT)
	_check(weapon != null and is_equal_approx(weapon.damage, GameCatalog.weapon("ember").damage * sim.run.stat("damage")), "A normal fire weapon does not inherit the skill-only damage modifier")
	if weapon != null:
		sim._release_shot(weapon)

func _test_clarisse_late_dispel() -> void:
	var sim: CombatSim = _sim("clarisse")
	var enemy: CombatSim.Enemy = _target(sim, Vector2(500, 0))
	_check(sim.try_hero_skill(), "Late dispel fixture starts the real three-phase cast")
	_step(sim, 63)
	_check(enemy.health == HEALTH, "The late entrant missed the entire first damage phase")
	_check(sim.grant_enemy_condition(enemy, "attack", 0.4, 10.0) and sim.grant_enemy_condition(enemy, "speed", 0.3, 10.0), "The target owns two independent temporary positive conditions")
	enemy.position = sim.player_position + Vector2(160, 0)
	_step(sim, 1)
	_check(enemy.health == HEALTH and enemy.positive_conditions.size() == 1 and enemy.positive_speed > 0.0, "The independently persistent dispel clears one condition after the first damage window has ended")
	_check(sim.grant_enemy_condition(enemy, "attack", 0.2, 10.0), "A dispelled target can receive a later real temporary condition")
	_step(sim, 7)
	_check(enemy.positive_conditions.size() == 2, "The same dispel area cannot remove a second condition from an already-contacted UID")
	enemy.position = sim.player_position + Vector2(500, 0)
	_step(sim, 76)
	var after: CombatSim.Enemy = _target(sim, Vector2(160, 0))
	sim.grant_enemy_condition(after, "attack", 0.2, 10.0)
	sim.grant_enemy_condition(after, "defense", 0.2, 10.0)
	_step(sim, 1)
	_check(after.positive_conditions.size() == 2 and after.health == HEALTH and int(sim.skill_timeline.snapshot()["occupied"]) == 0, "The 104-unit dispel lifetime cannot clear conditions after its actual expiry")

func _test_dispel_preserves_intrinsic_boss_state() -> void:
	var sim: CombatSim = _sim("clarisse")
	var enemy: CombatSim.Enemy = _target(sim, Vector2(160, 0), "boss")
	sim.boss = enemy
	sim.boss_encounter.begin(enemy.position, 0.4)
	sim.boss_encounter.advance(BossEncounter.OPENING_SECONDS, enemy.position, sim.player_position, 0.4)
	var cast_id: int = int(sim.boss_encounter.snapshot()["cast_id"])
	for point: Dictionary in sim.boss_encounter.weakpoints_snapshot():
		sim.boss_encounter.damage_weakpoint(int(point["uid"]), cast_id, 1000.0)
	var intrinsic: Dictionary = sim.boss_encounter.snapshot()
	_check(intrinsic["phase"] == "break" and bool(intrinsic["phase2"]) and float(intrinsic["damage_multiplier"]) > 1.0, "The fixture has a real intrinsic second-phase boss break, not a fake positive condition")
	sim.grant_enemy_condition(enemy, "attack", 0.4, 10.0)
	sim.grant_enemy_condition(enemy, "speed", 0.3, 10.0)
	_check(sim.try_hero_skill(), "The real hero cast also accepts the intrinsic boss target")
	sim._advance_skill_timeline(42.0 * STEP)
	_check(enemy.positive_conditions.size() == 1 and enemy.fire_vulnerability_left > 0.0, "The real dispel removes one positive condition without removing a negative fire weakness")
	_check(sim.boss_encounter.snapshot() == intrinsic and enemy.definition.id == "boss", "A dispel cannot erase the boss's intrinsic break, phase, cast identity or damage multiplier")

func _test_contact_separation() -> void:
	var sim: CombatSim = _sim("clarisse")
	var enemy: CombatSim.Enemy = _target(sim, Vector2(160, 0))
	var events: Array[Dictionary] = _record(sim, enemy.uid, "skill:hero_clarisse")
	_check(sim.try_hero_skill(), "Separation fixture casts the real persistent area")
	_step(sim, 42)
	_check(events.size() == 1, "The target first contacts the opened area")
	enemy.position = sim.player_position + Vector2(500, 0)
	sim.step(8.0 * STEP, Vector2.ZERO)
	_check(events.size() == 1, "Leaving the area misses the intervening scheduled contact opportunities")
	enemy.position = sim.player_position + Vector2(160, 0)
	_step(sim, 1)
	_check(events.size() == 2, "Reentry grants one new contact without catching up the absent ticks")
	_step(sim, 2)
	_check(events.size() == 2, "Reentry resumes contact cadence rather than immediately paying old tick debt")

func _test_compiled_contact_geometry() -> void:
	var configurations: Array[Dictionary] = [
		{"shape": "circle", "radius": 1.0},
		{"shape": "circle", "radius": 100.0},
		{"shape": "rectangle", "half_length": 300.0, "width": 50.0},
	]
	var headings: Array[Vector2] = [Vector2.RIGHT, Vector2(3.1, 4.7).normalized(), Vector2(2.0, -3.0), Vector2.ZERO, Vector2.INF]
	var centers: Array[Vector2] = [Vector2.ZERO, Vector2(640, 360), Vector2.INF]
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(1.0048, 0), Vector2(1.0052, 0), Vector2(100, 0), Vector2(100.001, 0), Vector2(300, 25), Vector2(-300, -25), Vector2(300.001, 0), Vector2(0, 25.001), Vector2.INF, Vector2(NAN, 0)]
	for parameters: Dictionary in configurations:
		for heading: Vector2 in headings:
			for center: Vector2 in centers:
				var geometry := SkillTimelineRuntime.ContactGeometry.new()
				geometry.configure(parameters, center, heading)
				var matches: bool = true
				for offset: Vector2 in offsets:
					var point: Vector2 = center + offset
					matches = matches and geometry.contains(point) == CombatSim.skill_contains(parameters, center, heading, point)
				_check(matches, "Compiled timeline geometry exactly matches the original query for boundary/invalid points, including its second normalization: %s/%s/%s" % [parameters["shape"], heading, center])
	var tolerance := SkillTimelineRuntime.ContactGeometry.new()
	tolerance.configure(configurations[0], Vector2.ZERO, Vector2.RIGHT)
	_check(tolerance.contains(Vector2(1.0048, 0)) and not tolerance.contains(Vector2(1.0052, 0)), "A circle retains the original squared-distance plus0.01 boundary tolerance")
	for parameters: Dictionary in configurations:
		var sim: CombatSim = _sim("alk")
		var heading: Vector2 = Vector2(3.1, 4.7).normalized()
		var phase: Dictionary = parameters.duplicate(true)
		phase.merge({"delay": 0.0, "duration": 1.0, "hits": 1, "damage_weight": 1.0})
		var cast: Dictionary = {"id": "geometry_probe", "damage": 12.0, "timeline": [phase]}
		var targets: Array[CombatSim.Enemy] = []
		var expected: Array[bool] = []
		for offset: Vector2 in offsets:
			if not offset.is_finite():
				continue
			var target: CombatSim.Enemy = _target(sim, Vector2.ZERO)
			target.position = sim.player_position + offset
			targets.append(target)
			expected.append(CombatSim.skill_contains(parameters, sim.player_position, heading.normalized(), target.position))
		_check(sim.skill_timeline.enqueue(cast, sim.player_position, heading), "The real timeline accepts the geometry equivalence fixture")
		var before: String = JSON.stringify(sim.skill_timeline.snapshot())
		sim.skill_timeline.areas[0].contact_geometry.configure(parameters, sim.player_position, heading)
		_check(JSON.stringify(sim.skill_timeline.snapshot()) == before, "Derived geometry never changes the public timeline snapshot bytes")
		sim._advance_skill_timeline(STEP)
		for index: int in targets.size():
			_check((targets[index].health < HEALTH) == expected[index], "The production enemy scan preserves the original circle/rectangle hit result: %s/%d" % [parameters["shape"], index])

func _test_contact_geometry_callback_refresh() -> void:
	for shape: String in ["circle", "rectangle"]:
		var sim: CombatSim = _sim("alk")
		var first: CombatSim.Enemy = _target(sim, Vector2.ZERO)
		var excluded: CombatSim.Enemy = _target(sim, Vector2(200, 0))
		var included: CombatSim.Enemy = _target(sim, Vector2(160, 0) if shape == "circle" else Vector2(0, 200))
		var phase: Dictionary = {"delay": 0.0, "duration": 1.0, "hits": 1, "damage_weight": 1.0, "shape": shape, "radius": 40.0, "half_length": 300.0, "width": 50.0}
		var reference: WeakRef = weakref(sim)
		var changed: Array[bool] = [false]
		sim.damage_dealt.connect(func(_point: Vector2, _amount: float, source: String, _secondary: bool, _uid: int) -> void:
			if source != "skill:geometry_callback" or changed[0]:
				return
			changed[0] = true
			var current: CombatSim = reference.get_ref() as CombatSim
			if current == null:
				return
			var area: SkillTimelineRuntime.Area = current.skill_timeline.areas[0]
			if shape == "circle":
				area.origin += Vector2(160, 0)
				area.parameters["radius"] = 10.0
			else:
				area.direction = Vector2(0, 3)
				area.parameters["width"] = 20.0
		)
		_check(sim.skill_timeline.enqueue({"id": "geometry_callback", "damage": 12.0, "timeline": [phase]}, sim.player_position, Vector2.RIGHT), "The synchronous geometry fixture reserves its actual area: " + shape)
		sim._advance_skill_timeline(STEP)
		_check(changed[0] and first.health < HEALTH and excluded.health == HEALTH and included.health < HEALTH and sim.skill_hits == 2, "A synchronous first-hit callback changes origin/shape dimensions/heading before later pool slots are tested: " + shape)

func _test_celtie_rectangle_and_combo() -> void:
	var sim: CombatSim = _sim("celtie")
	var front: CombatSim.Enemy = _target(sim, Vector2(300, 0))
	var rear: CombatSim.Enemy = _target(sim, Vector2(-300, 0))
	var side: CombatSim.Enemy = _target(sim, Vector2(0, 30))
	sim._pinball_combo = 40
	var base: float = float(sim.run.hero_skill_parameters()["damage"])
	_check(sim.try_hero_skill(), "Celtie reserves its actual long rectangle with the current combo")
	sim._pinball_combo = 0
	_step(sim, 24)
	_check(front.health == HEALTH and rear.health == HEALTH and side.health == HEALTH, "Celtie's original Wait 25 is respected")
	_step(sim, 1)
	_check(is_equal_approx(HEALTH - front.health, base * 1.2) and is_equal_approx(HEALTH - rear.health, base * 1.2), "The real centered rectangle reaches both directions at distance 300")
	_check(side.health == HEALTH, "The real rectangle excludes a perpendicular distance of 30")
	_check(int(sim.hero_skill_snapshot()["combo"]) == 40 and is_equal_approx(float(sim.hero_skill_snapshot()["combo_bonus"]), 0.2), "The cast's combo remains locked even when live combo changes during the delay")
	_step(sim, 32)
	_check(sim.skill_hits == 2 and int(sim.skill_timeline.snapshot()["occupied"]) == 0, "Celtie's original lifetime 31 does not create duplicate hits")

func _test_reentrant_enemy_slot_reuse() -> void:
	var sim: CombatSim = _sim("clarisse")
	var enemy: CombatSim.Enemy = _target(sim, Vector2(160, 0))
	var original_uid: int = enemy.uid
	var original_slot: int = enemy.slot
	var original_position: Vector2 = enemy.position
	var reference: WeakRef = weakref(sim)
	var receipts: Array[Dictionary] = []
	var replacements: Array[Dictionary] = []
	sim.damage_dealt.connect(func(_point: Vector2, amount: float, source: String, _secondary: bool, uid: int) -> void:
		if source != "skill:hero_clarisse":
			return
		receipts.append({"uid": uid, "amount": amount})
		if uid != original_uid or not replacements.is_empty():
			return
		var current: CombatSim = reference.get_ref() as CombatSim
		if current == null:
			return
		var victim: CombatSim.Enemy = current.enemies[original_slot]
		if not victim.active or victim.uid != original_uid:
			return
		current.apply_damage(victim, HEALTH * 2.0, "fixture")
		var replacement: CombatSim.Enemy = current.spawn_enemy("tank", original_position, true)
		if replacement == null:
			return
		replacement.definition = replacement.definition.duplicate() as ContentDef
		replacement.definition.speed = 0.0
		replacement.action_timer = 99999.0
		replacement.health = HEALTH
		replacement.max_health = HEALTH
		replacements.append({"uid": replacement.uid, "slot": replacement.slot})
	)
	_check(sim.try_hero_skill(), "Reentrant UID fixture starts the actual four-plus-eleven cast")
	var part: float = float(sim.hero_skill_snapshot()["damage"]) * 0.15 / 4.0
	sim.step(1.0, Vector2.ZERO)
	_check(replacements.size() == 1 and int(replacements[0]["slot"]) == original_slot and int(replacements[0]["uid"]) != original_uid, "The first real damage callback synchronously kills, frees and reuses the same enemy slot with a new UID")
	if replacements.size() != 1:
		return
	var replacement: CombatSim.Enemy = sim.enemies[original_slot]
	_check(receipts.size() == 1 and int(receipts[0]["uid"]) == original_uid and is_equal_approx(float(receipts[0]["amount"]), part), "Already-claimed first-phase hits cannot continue onto the synchronously replaced UID")
	_check(replacement.health == HEALTH and replacement.fire_vulnerability_left == 0.0 and sim.skill_hits == 1, "A replacement inherits neither same-step damage nor the old contact's post-hit fire weakness")
	_check(sim.run.kills == 1 and is_equal_approx(float(sim.damage_by_skill.get("hero_clarisse", 0.0)), part), "Actual kill accounting is retained while skipped stale hits do not enter hero damage totals")
	_step(sim, 20)
	_check(receipts.size() == 2 and int(receipts[1]["uid"]) == replacement.uid and replacement.health < HEALTH and sim.skill_hits == 2, "The new UID can still receive its own later second-phase contact, independent of the old UID's claimed budget")

func _test_reentrant_kill_without_replacement() -> void:
	for callback_signal: String in ["damage_dealt", "enemy_hit"]:
		var sim: CombatSim = _sim("clarisse")
		var enemy: CombatSim.Enemy = _target(sim, Vector2(160, 0))
		var original_uid: int = enemy.uid
		var original_slot: int = enemy.slot
		var reference: WeakRef = weakref(sim)
		var invoked: Array[bool] = [false]
		var receipts: Array[Dictionary] = _record(sim, original_uid, "skill:hero_clarisse")
		var kill_once: Callable = func() -> void:
			if invoked[0]:
				return
			invoked[0] = true
			var current: CombatSim = reference.get_ref() as CombatSim
			if current == null:
				return
			var victim: CombatSim.Enemy = current.enemies[original_slot]
			if victim.active and victim.uid == original_uid:
				current.apply_damage(victim, HEALTH * 2.0, "fixture")
		if callback_signal == "damage_dealt":
			sim.damage_dealt.connect(func(_point: Vector2, _amount: float, source: String, _secondary: bool, uid: int) -> void:
				if source == "skill:hero_clarisse" and uid == original_uid:
					kill_once.call()
			)
		else:
			sim.enemy_hit.connect(kill_once)
		_check(sim.try_hero_skill(), "The no-replacement reentrant fixture starts the real delayed cast: " + callback_signal)
		var part: float = float(sim.hero_skill_snapshot()["damage"]) * 0.15 / 4.0
		sim.step(1.0, Vector2.ZERO)
		_check(invoked[0] and not enemy.active and sim.run.kills == 1 and sim.enemy_count == 0, "A synchronous lethal callback releases its enemy exactly once: " + callback_signal)
		var free_copies: int = 0
		for slot: int in sim._enemy_free:
			if slot == original_slot:
				free_copies += 1
		_check(free_copies == 1 and sim._enemy_free.size() == CombatSim.ENEMY_LIMIT, "Reentrant kill cannot duplicate a free slot or underflow active enemy count: " + callback_signal)
		_check(receipts.size() == 1 and sim.skill_hits == 1 and is_equal_approx(float(sim.damage_by_skill.get("hero_clarisse", 0.0)), part), "The canceled remainder cannot invent further hero damage after the callback kill: " + callback_signal)
		sim._kill_enemy(enemy)
		_check(sim.run.kills == 1 and sim.enemy_count == 0 and sim._enemy_free.size() == CombatSim.ENEMY_LIMIT, "Repeated release of an inactive enemy is idempotent: " + callback_signal)
		var first: CombatSim.Enemy = _target(sim, Vector2(160, 0))
		var second: CombatSim.Enemy = _target(sim, Vector2(200, 0))
		_check(first.slot == original_slot and first.uid != original_uid and first.slot != second.slot and sim.enemy_count == 2, "Subsequent spawns own distinct live pool slots after a reentrant kill: " + callback_signal)

func _test_hanabi_reservations_and_sweep() -> void:
	var sim: CombatSim = _sim("hanabi")
	var enemy: CombatSim.Enemy = _target(sim, Vector2(140, 0))
	_check(sim.try_hero_skill(), "Hanabi atomically reserves five bomb slots at the actual cast")
	var preparing: Dictionary = sim.hero_effects_snapshot()
	_check(int(preparing["reserved_bombs"]) == 5 and int(preparing["active_bombs"]) == 0 and sim.hero_effects.active_count() == 5, "Preparing bombs consume real pool capacity without becoming physical projectiles")
	_check(sim.hero_effects.can_spawn(15) and not sim.hero_effects.can_spawn(16), "Five delayed reservations cannot be spent again by another cast")
	_step(sim, 54)
	_check(enemy.health == HEALTH and sim.skill_hits == 0 and int(sim.hero_effects_snapshot()["reserved_bombs"]) == 5 and int(sim.hero_effects_snapshot()["active_bombs"]) == 0, "No projectile or damage exists during the first 54 adapted action units")
	_step(sim, 1)
	var launched: Dictionary = sim.hero_effects_snapshot()
	_check(int(launched["reserved_bombs"]) == 0 and int(launched["active_bombs"]) == 5 and enemy.health == HEALTH, "Action unit 55 launches the reserved bombs without pre-impact damage")
	_step(sim, 1)
	var moving: Dictionary = sim.hero_effects_snapshot()
	if launched["bombs"].size() == 5 and moving["bombs"].size() == 5:
		for index: int in 5:
			_check((moving["bombs"][index]["position"] as Vector2).distance_to(launched["bombs"][index]["position"]) > 0.0, "A launched bomb really moves through the simulation: %d" % index)
	else:
		_check(false, "The movement fixture retains all five bombs before the distant contact")
	_step(sim, 80)
	_check(enemy.health < HEALTH and int(sim.hero_effects_snapshot()["explosions"]) == 5 and sim.hero_effects.active_count() == 0, "Every real bomb detonates once and releases its reservation after contact or lifetime")
	_check(float(sim.damage_by_skill.get("hero_hanabi", 0.0)) <= float(sim.hero_skill_snapshot()["damage"]) + 0.000001, "Five bomb explosions cannot exceed their shared one-target damage budget")
	var sweep: CombatSim = _sim("hanabi")
	var swept: CombatSim.Enemy = _target(sweep, Vector2(140, 0))
	_check(sweep.try_hero_skill(), "The large-step swept collision starts a real delayed cast")
	sweep.step(55.0 * STEP + 0.7, Vector2.ZERO)
	_check(swept.health < HEALTH, "A step spanning both preparation and flight cannot tunnel bombs through a target")
	var full: CombatSim = _sim("hanabi")
	var eighteen: Dictionary = full.run.hero_skill_parameters().duplicate(true)
	eighteen["projectiles"] = 18
	_check(full.hero_effects.spawn_bombs(eighteen, full.player_position, Vector2.RIGHT), "Capacity fixture owns eighteen real preparing bombs")
	var before: Dictionary = full.hero_effects_snapshot()
	_check(not full.try_hero_skill() and full.hero_effects_snapshot() == before and int(full.hero_skill_snapshot()["uses"]) == 0, "Insufficient reservation capacity rejects all five bombs without consuming R or overwriting live deliveries")

func _test_hanabi_held_impacts() -> void:
	var sim: CombatSim = _sim("hanabi")
	var primary: CombatSim.Enemy = _target(sim, Vector2(140, 0))
	var late: CombatSim.Enemy = _target(sim, Vector2(500, 0))
	_check(sim.try_hero_skill(), "The real Hanabi cast reserves an impact area for each physical bomb")
	var reserved: Dictionary = sim.skill_timeline.snapshot()
	_check(int(reserved["occupied"]) == 5 and reserved["areas"].size() == 5, "Five delayed bombs also consume five of the shared twenty-four area slots")
	for area: Dictionary in reserved["areas"]:
		_check(bool(area["held"]) and not bool(area["active"]) and float(area["age"]) == 0.0 and is_equal_approx(float(area["duration"]), 30.0 * STEP), "A reserved explosion has its original thirty-unit lifetime but no running clock or contacts")
	_step(sim, 55)
	var flight: Dictionary = sim.skill_timeline.snapshot()
	for area: Dictionary in flight["areas"]:
		_check(bool(area["held"]) and float(area["age"]) == 0.0 and (area["hits"] as Dictionary).is_empty(), "Preparation and launch do not age or activate the held explosion")
	var impact: SkillTimelineRuntime.Area
	for frame: int in 90:
		sim.step(STEP, Vector2.ZERO)
		for candidate: SkillTimelineRuntime.Area in sim.skill_timeline.areas:
			if candidate.occupied and not candidate.held and candidate.opened:
				impact = candidate
				break
		if impact != null:
			break
	_check(impact != null and int(sim.hero_effects_snapshot()["explosions"]) > 0, "A physical bomb impact activates its previously held area")
	if impact == null:
		return
	_check(impact.age >= 0.0 and impact.age <= STEP + 0.000001 and is_equal_approx(impact.duration, 30.0 * STEP), "The explosion clock starts at the physical impact rather than at cast or launch")
	_check(int(impact.contacts.get("enemy:%d" % primary.uid, 0)) == 1 and late.health == HEALTH, "The activated area hits the actual contact target once and leaves the distant UID untouched")
	late.position = impact.origin
	sim.step(STEP, Vector2.ZERO)
	var late_key: String = "enemy:%d" % late.uid
	_check(late.health < HEALTH and int(impact.contacts.get(late_key, 0)) == 1, "A later UID enters the existing post-impact circle and receives its real damage")
	_step(sim, 5)
	_check(impact.occupied and int(impact.contacts.get(late_key, 0)) == 1, "The persistent thirty-unit blast does not re-hit an already-contacted UID")
	_step(sim, 25)
	_check(not impact.occupied and not sim.skill_timeline.can_contact(impact), "The impact area releases only after its own thirty-unit lifetime")
	var full: CombatSim = _sim("hanabi")
	for index: int in 22:
		_check(full.skill_timeline.enqueue(_parameters(), full.player_position, Vector2.RIGHT), "The shared-capacity fixture owns a real pending area")
	var before: Dictionary = full.hero_effects_snapshot()
	_check(not full.try_hero_skill() and full.hero_effects_snapshot() == before and full.hero_effects.active_count() == 0 and int(full.hero_skill_snapshot()["uses"]) == 0, "Insufficient shared impact slots reject Hanabi atomically before reserving bombs or consuming R")

func _parameters(count: int = 1) -> Dictionary:
	var phases: Array[Dictionary] = []
	for index: int in count:
		phases.append({"delay": 0.1, "duration": 0.5, "hits": 3, "damage_weight": 1.0 / float(count), "shape": "circle", "radius": 80.0})
	return {"id": "hero_fixture", "damage": 90.0, "timeline": phases}

func _test_validation_and_atomic_capacity() -> void:
	var runtime := SkillTimelineRuntime.new()
	var valid: Dictionary = _parameters()
	var invalid: Array[Dictionary] = []
	for value: Variant in [NAN, INF, -1.0, "90", true]:
		var parameters: Dictionary = valid.duplicate(true)
		parameters["damage"] = value
		invalid.append(parameters)
	for pair: Array in [["delay", NAN], ["delay", -0.1], ["delay", 31.0], ["duration", INF], ["duration", 0.0], ["duration", 11.0], ["hits", 2.5], ["hits", 0], ["hits", 33], ["hits", "3"], ["damage_weight", 0.5], ["damage_weight", -1.0], ["damage_weight", NAN], ["radius", INF], ["radius", 0.0], ["shape", "unknown"], ["purpose", "unknown"], ["anchor", "unknown"], ["purpose", "dispel"]]:
		var parameters: Dictionary = valid.duplicate(true)
		parameters["timeline"][0][pair[0]] = pair[1]
		invalid.append(parameters)
	invalid.append({"id": "hero_fixture", "damage": 1.0, "timeline": []})
	invalid.append({"id": "hero_fixture", "damage": 1.0, "timeline": {}})
	invalid.append({"id": "hero_fixture", "damage": 1.0, "timeline": ["invalid"]})
	invalid.append({"damage": 1.0, "timeline": valid["timeline"]})
	invalid.append(_parameters(9))
	for parameters: Dictionary in invalid:
		var before: Dictionary = runtime.snapshot()
		_check(not runtime.enqueue(parameters, Vector2.ZERO, Vector2.RIGHT) and runtime.snapshot() == before, "Invalid values, fractional hits and incorrect phase weights leave the pool untouched")
	for vectors: Array in [[Vector2.INF, Vector2.RIGHT], [Vector2.ZERO, Vector2.INF], [Vector2.ZERO, Vector2.ZERO]]:
		_check(not runtime.enqueue(valid, vectors[0], vectors[1]) and int(runtime.snapshot()["occupied"]) == 0, "Invalid origins and directions cannot allocate skill areas")
	for cast: int in 8:
		_check(runtime.enqueue(_parameters(3), Vector2.ZERO, Vector2.RIGHT), "The fixed pool admits eight whole three-phase casts")
	var full: Dictionary = runtime.snapshot()
	_check(int(full["occupied"]) == 24 and not runtime.enqueue(valid, Vector2.ZERO, Vector2.RIGHT) and runtime.snapshot() == full, "The 24-area limit rejects overflow without mutating any reserved phase")
	runtime.clear()
	_check(int(runtime.snapshot()["occupied"]) == 0 and runtime.areas.size() == 24 and int(runtime.snapshot()["peak"]) == 0, "Clear retains fixed storage while resetting ownership and telemetry")
	var sim: CombatSim = _sim("clarisse")
	for cast: int in 8:
		_check(sim.skill_timeline.enqueue(sim.run.hero_skill_parameters(), sim.player_position, Vector2.RIGHT), "Combat capacity fixture reserves actual three-phase hero casts")
	var before: Dictionary = sim.hero_effects_snapshot()
	_check(not sim.try_hero_skill() and sim.hero_effects_snapshot() == before and int(sim.hero_skill_snapshot()["uses"]) == 0, "A full real timeline rejects R before granting a buff or consuming its cooldown")

func _test_snapshot_and_large_delta() -> void:
	var runtime := SkillTimelineRuntime.new()
	var parameters: Dictionary = _parameters()
	parameters["timeline"][0]["hits"] = 32
	_check(runtime.enqueue(parameters, Vector2(20, 30), Vector2.RIGHT), "Snapshot fixture reserves a real phase")
	parameters["timeline"][0]["radius"] = 9999.0
	parameters["damage"] = 99999.0
	var original: Dictionary = runtime.snapshot()
	_check(float(original["areas"][0]["parameters"]["radius"]) == 80.0, "Enqueue owns its phase parameters independently from caller dictionaries")
	var changed: Dictionary = runtime.snapshot()
	changed["areas"][0]["parameters"]["damage"] = 0.0
	changed["areas"][0]["hits"]["enemy:1"] = 999
	changed["areas"][0]["origin"] = Vector2.INF
	_check(runtime.snapshot() == original, "A renderer cannot alter source parameters, UID contacts or geometry through a snapshot")
	for delta: float in [0.0, -1.0, NAN, INF]:
		runtime.advance(delta, Vector2.ZERO)
	_check(runtime.snapshot() == original, "Invalid time cannot advance phases or change reservations")
	_check(runtime.claim_hits(runtime.areas[0], "") == 0 and runtime.claim_hits(runtime.areas[0], "enemy:1") == 0, "Empty targets and contacts before activation cannot consume hit budgets")
	runtime.advance(1000.0, Vector2.ZERO)
	_check(runtime.claim_hits(runtime.areas[0], "enemy:1") == 32 and runtime.claim_hits(runtime.areas[0], "enemy:1") == 0, "A huge valid delta is bounded by the per-UID maximum rather than an unbounded tick loop")
	_check(runtime.claim_hits(runtime.areas[0], "enemy:2") == 32, "The bounded budget remains independent for another target UID")
	runtime.finish_step()
	_check(int(runtime.snapshot()["occupied"]) == 0 and runtime.claim_hits(runtime.areas[0], "enemy:3") == 0, "Finishing a crossed lifetime releases the phase and all pending target contacts")
	var sim: CombatSim = _sim("clarisse")
	var enemy: CombatSim.Enemy = _target(sim, Vector2(160, 0))
	var events: Array[Dictionary] = _record(sim, enemy.uid, "skill:hero_clarisse")
	_check(sim.try_hero_skill(), "Large-delta integration uses the real hero cast")
	sim.step(50.0, Vector2.ZERO)
	_check(events.size() == 15 and int(sim.skill_timeline.snapshot()["occupied"]) == 0, "A real simulation step crossing every phase still produces at most the original four plus eleven contacts")
	_check(enemy.fire_vulnerability_left == 0.0 and enemy.fire_vulnerability == 0.0, "A step past the last contact's expiry cannot leave a fresh four-second fire weakness")

func _test_vulnerability_expiry_across_steps() -> void:
	var total: float = 2.907
	var large: CombatSim = _sim("clarisse")
	var large_target: CombatSim.Enemy = _target(large, Vector2(160, 0))
	_check(large.try_hero_skill(), "Nonintegral large-step fixture uses the real Clarisse cast")
	large.step(total, Vector2.ZERO)
	var chunked: CombatSim = _sim("clarisse")
	var chunked_target: CombatSim.Enemy = _target(chunked, Vector2(160, 0))
	_check(chunked.try_hero_skill(), "Nonintegral chunked fixture uses the real Clarisse cast")
	for delta: float in [0.173, 0.541, 0.619, 0.927, 0.647]:
		chunked.step(delta, Vector2.ZERO)
	var regular: CombatSim = _sim("clarisse")
	var regular_target: CombatSim.Enemy = _target(regular, Vector2(160, 0))
	_check(regular.try_hero_skill(), "Reference fixture uses real sixty-Hz steps")
	_step(regular, floori(total / STEP))
	regular.step(total - regular.elapsed, Vector2.ZERO)
	var expected: float = (79.0 + 10.0 * 67.0 / 11.0) * STEP + 4.0 - total
	_check(large.skill_hits == 15 and chunked.skill_hits == 15 and regular.skill_hits == 15 and is_equal_approx(large_target.health, regular_target.health) and is_equal_approx(chunked_target.health, regular_target.health), "Clock correction preserves all four-plus-eleven hits and their actual weakness-amplified damage")
	_check(is_equal_approx(large_target.fire_vulnerability_left, expected) and is_equal_approx(chunked_target.fire_vulnerability_left, expected) and is_equal_approx(regular_target.fire_vulnerability_left, expected), "Weakness remaining time uses the last real contact rather than the end of an arbitrary large step")
	_check(is_equal_approx(large_target.fire_vulnerability_left, regular_target.fire_vulnerability_left) and is_equal_approx(chunked_target.fire_vulnerability_left, regular_target.fire_vulnerability_left), "A nonintegral large step, irregular chunks and sixty-Hz processing agree on the final weakness clock")

func _test_world_pause_and_cleanup() -> void:
	var sound := QuietSound.new()
	root.add_child(sound)
	var world := TimelineWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.set_physics_process(false)
	world.begin(_state("alk"))
	_quiet(world.sim)
	_check(world.request_hero_skill(), "The real World queues delayed R")
	world._physics_process(STEP)
	_check(int(world.sim.skill_timeline.snapshot()["occupied"]) == 1 and world.sim.hero_effects.attack_left > 0.0, "World's fixed step owns the real pending area and opening buff")
	paused = true
	var frozen: Dictionary = world.sim.hero_effects_snapshot()
	var cooldown: Dictionary = world.sim.hero_skill_snapshot()
	_check(not world.request_hero_skill(), "A paused World rejects a new R request")
	world._physics_process(1.0)
	for frame: int in 3:
		await process_frame
	_check(world.sim.hero_effects_snapshot() == frozen and world.sim.hero_skill_snapshot() == cooldown, "Pause freezes phase ages, UID contacts, temporary buffs and cooldowns")
	paused = false
	world._physics_process(STEP)
	_check(world.sim.hero_effects_snapshot() != frozen, "Resume advances the existing delayed phase")
	world.stop()
	_check(not world.active and int(world.sim.skill_timeline.snapshot()["occupied"]) == 0 and world.sim.hero_effects.attack_left == 0.0, "World stop clears the pending area and temporary attack buff")
	world.begin(_state("hanabi"))
	_quiet(world.sim)
	_check(world.request_hero_skill(), "A new World simulation accepts Hanabi")
	world._physics_process(STEP)
	_check(int(world.sim.hero_effects_snapshot()["reserved_bombs"]) == 5, "The World owns five real unlaunched reservations")
	world.stop()
	_check(world.sim.hero_effects.active_count() == 0 and int(world.sim.hero_effects_snapshot()["reserved_bombs"]) == 0, "Stopping cannot leak delayed bomb reservations")
	world.begin(_state("clarisse"))
	_quiet(world.sim)
	_check(world.request_hero_skill(), "Begin starts a fresh independent hero clock")
	world._physics_process(STEP)
	var old: CombatSim = world.sim
	old._finish(false, "timeline lifecycle fixture")
	_check(not world.active and int(old.skill_timeline.snapshot()["occupied"]) == 0 and old.hero_effects.skill_left == 0.0 and old.hero_effects.active_count() == 0, "Finish clears all phases, skill buffs and physical deliveries before terminal observers")
	var finished: Dictionary = old.hero_effects_snapshot()
	old.step(1.0, Vector2.ZERO)
	_check(old.hero_effects_snapshot() == finished and not old.try_hero_skill(), "A finished simulation cannot restart or advance any stale skill work")
	old.begin(_state("alk"))
	_check(int(old.skill_timeline.snapshot()["occupied"]) == 0 and old.hero_effects.active_count() == 0 and int(old.hero_skill_snapshot()["uses"]) == 0, "CombatSim begin also clears the previous wave's reservations and independent R clock")
	world.begin(_state("alk"))
	_quiet(world.sim)
	_check(int(world.sim.skill_timeline.snapshot()["occupied"]) == 0 and int(world.sim.hero_skill_snapshot()["uses"]) == 0 and not world._hero_skill_pending, "Replacement World begin cannot inherit prior phases or queued R input")
	world.stop()
	world.queue_free()
	sound.queue_free()
	for frame: int in 2:
		await process_frame
