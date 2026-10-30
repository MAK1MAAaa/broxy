extends SceneTree
## Source-bound roster actions use real simulation clocks, offsets and target UIDs.

const STEP: float = 1.0 / 60.0
const HEALTH: float = 1000000.0
const IDS: Array[String] = ["nasir", "mordiga", "falsche"]
var _checks: int = 0
var _failures: int = 0

class QuietSound extends SoundBank:
	func _ready() -> void:
		pass
	func play(_name: String, _loudness: float = -10.0) -> void:
		pass
	func play_cue(_name: String, _loudness: float, _cue_id: String) -> void:
		pass

class RosterWorld extends CombatWorld:
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
	state.begin(20261101, "bone", "reliquary", hero_id)
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

func _enemy(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", point, true)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 99999.0
	enemy.health = HEALTH
	enemy.max_health = HEALTH
	return enemy

func _steps(sim: CombatSim, frames: int, movement: Vector2 = Vector2.ZERO) -> void:
	for frame: int in frames:
		sim.step(STEP, movement)

func _receipts(sim: CombatSim, id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var reference: WeakRef = weakref(sim)
	sim.damage_dealt.connect(func(_point: Vector2, amount: float, source: String, _secondary: bool, uid: int) -> void:
		if source != "skill:hero_" + id:
			return
		var current: CombatSim = reference.get_ref() as CombatSim
		if current != null:
			events.append({"time": current.elapsed, "uid": uid, "amount": amount})
	)
	return events

func _count(events: Array[Dictionary], uid: int) -> int:
	var count: int = 0
	for event: Dictionary in events:
		count += 1 if int(event["uid"]) == uid else 0
	return count

func _signature(sim: CombatSim) -> String:
	var targets: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			targets.append([enemy.uid, enemy.position, enemy.velocity, enemy.health, enemy.age, enemy.action_timer, enemy.fire_vulnerability_left, enemy.positive_conditions])
	return JSON.stringify([sim.snapshot(), sim.run.summary(), targets, sim.damage_by_skill, sim.damage_by_weapon,
		str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)])

func _run() -> void:
	_test_recorder_lifecycle()
	_test_nasir_activation_offset()
	_test_mordiga_fixed_reference()
	_test_falsche_full_lifetime()
	_test_falsche_follow_and_separation()
	_test_falsche_uid_reuse()
	_test_falsche_external_uid_change()
	_test_pool_and_presentation()
	_test_legacy_offsets()
	await _test_world_lifecycle()
	print("RosterSkills: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_recorder_lifecycle() -> void:
	var sim: CombatSim = _sim("nasir")
	var reference: WeakRef = weakref(sim)
	var events: Array[Dictionary] = _receipts(sim, "nasir")
	sim = null
	_check(reference.get_ref() == null and events.is_empty(), "Roster damage receipts do not retain their RefCounted simulation")

func _test_nasir_activation_offset() -> void:
	var sim: CombatSim = _sim("nasir")
	var cast_position: Vector2 = sim.player_position
	var old_target: CombatSim.Enemy = _enemy(sim, cast_position + Vector2(110, 0))
	var events: Array[Dictionary] = _receipts(sim, "nasir")
	_check(sim.try_hero_skill() and int(sim.skill_timeline.snapshot()["occupied"]) == 1, "Nasir reserves its actual source-bound R area")
	for frame: int in 27:
		sim.step(STEP, Vector2.DOWN, frame == 0)
	_check(sim.player_position.distance_to(cast_position) > 105.0 and old_target.health == HEALTH and events.is_empty(), "Real movement during the first27 units leaves Nasir's fire damage pending")
	var incoming: CombatSim.Enemy = _enemy(sim, sim.player_position + Vector2(110, 0))
	sim.step(STEP, Vector2.DOWN)
	var phase: Dictionary = sim.skill_timeline.snapshot()["areas"][0]
	var activation_origin: Vector2 = sim.player_position + Vector2(110, 0)
	_check((phase["origin"] as Vector2).is_equal_approx(activation_origin) and (phase["follow_offset"] as Vector2) == Vector2(110, 0), "Action unit28 captures the current player position while preserving its source-scaled110 forward offset")
	_check(phase["direction"] == Vector2.RIGHT and old_target.health == HEALTH and incoming.health < HEALTH and events.size() == 1, "The cast retains its original aim while hitting the activation position rather than the obsolete cast position")
	_check(is_equal_approx(HEALTH - incoming.health, float(sim.hero_skill_snapshot()["damage"])), "Nasir's actual single hit reaches the locked R damage budget")
	_steps(sim, 4, Vector2.DOWN)
	_check(sim.skill_timeline.snapshot()["areas"][0]["origin"] == activation_origin and events.size() == 1, "Nasir freezes its area after activation and cannot repeatedly hit the same UID")
	var late: CombatSim.Enemy = _enemy(sim, activation_origin + Vector2(0, 70))
	sim.step(STEP, Vector2.DOWN)
	_check(late.health < HEALTH and _count(events, late.uid) == 1 and events.size() == 2, "A later UID can enter Nasir's still-live20-unit region")
	_steps(sim, 16)
	_check(int(sim.skill_timeline.snapshot()["occupied"]) == 0 and events.size() == 2, "Nasir releases the source20-unit area with one contact per UID")

func _test_mordiga_fixed_reference() -> void:
	var sim: CombatSim = _sim("mordiga")
	var origin: Vector2 = sim.player_position + Vector2(60, 0)
	var fixed_target: CombatSim.Enemy = _enemy(sim, origin)
	var events: Array[Dictionary] = _receipts(sim, "mordiga")
	_check(sim.try_hero_skill(), "Mordiga captures its original cast-time reference")
	for frame: int in 37:
		sim.step(STEP, Vector2.DOWN, frame == 0)
	_check(events.is_empty() and fixed_target.health == HEALTH, "Mordiga cannot deal damage before the source Wait38")
	var moved_target: CombatSim.Enemy = _enemy(sim, sim.player_position + Vector2(60, 0))
	sim.step(STEP, Vector2.DOWN)
	var phase: Dictionary = sim.skill_timeline.snapshot()["areas"][0]
	_check(phase["origin"] == origin and phase["anchor"] == "fixed", "The water circle keeps cast-reference plus60 instead of following the moved player")
	_check(fixed_target.health < HEALTH and moved_target.health == HEALTH and events.size() == 1, "The actual water strike damages the captured point and excludes the distant moved point")
	_check(is_equal_approx(HEALTH - fixed_target.health, float(sim.hero_skill_snapshot()["damage"])), "Mordiga's original single-hit phase retains its project damage budget")
	var late: CombatSim.Enemy = _enemy(sim, origin + Vector2(0, -100))
	_steps(sim, 1)
	_check(late.health < HEALTH and _count(events, late.uid) == 1 and _count(events, fixed_target.uid) == 1, "Mordiga's50-unit lifetime admits another UID without repeating old contacts")
	_steps(sim, 50)
	_check(events.size() == 2 and int(sim.skill_timeline.snapshot()["occupied"]) == 0, "The fixed water region expires after source delay38 plus lifetime50")

func _test_falsche_full_lifetime() -> void:
	var sim: CombatSim = _sim("falsche")
	var target: CombatSim.Enemy = _enemy(sim, sim.player_position + Vector2(80, 0))
	var events: Array[Dictionary] = _receipts(sim, "falsche")
	_check(sim.try_hero_skill() and target.health == HEALTH, "Falsche enqueues its source aura without bypassing the real fixed step")
	var damage: float = float(sim.hero_skill_snapshot()["damage"])
	_steps(sim, 599)
	_check(events.size() == 30 and int(sim.skill_timeline.snapshot()["occupied"]) == 1, "The original600-unit aura remains allocated while distributing its30 target contacts")
	_steps(sim, 1)
	_check(events.size() == 30 and sim.skill_hits == 30 and int(sim.skill_timeline.snapshot()["occupied"]) == 0, "Exactly600 sixty-Hz steps complete the original ten-second aura without a31st hit")
	_check(is_equal_approx(HEALTH - target.health, damage) and is_equal_approx(float(sim.damage_by_skill.get("hero_falsche", 0.0)), damage) and sim.damage_by_weapon.is_empty(), "Thirty actual dark contacts share one project R damage budget and only hero statistics")
	if events.size() == 30:
		for index: int in 30:
			var scheduled: float = float(index) / 3.0
			_check(float(events[index]["time"]) + 0.000001 >= scheduled and float(events[index]["time"]) <= scheduled + STEP + 0.000001, "Falsche contacts remain distributed across the whole source lifetime: %d" % index)
	_steps(sim, 30)
	_check(events.size() == 30, "An expired aura cannot keep damaging its last target")

func _test_falsche_follow_and_separation() -> void:
	var sim: CombatSim = _sim("falsche")
	var old: CombatSim.Enemy = _enemy(sim, sim.player_position + Vector2(90, 0))
	var events: Array[Dictionary] = _receipts(sim, "falsche")
	_check(sim.try_hero_skill(), "The moving-aura fixture casts Falsche's real R")
	_steps(sim, 1)
	_check(_count(events, old.uid) == 1, "A target initially inside the aura receives its first real contact")
	_steps(sim, 60, Vector2.LEFT)
	var phase: Dictionary = sim.skill_timeline.snapshot()["areas"][0]
	_check(sim.player_position.x < 430.0 and phase["origin"] == sim.player_position and phase["anchor"] == "caster", "The source aura follows actual simulated player movement on every physics step")
	_check(_count(events, old.uid) == 1, "An enemy left behind cannot receive the aura's intervening scheduled contacts")
	var following: CombatSim.Enemy = _enemy(sim, sim.player_position + Vector2(80, 0))
	_steps(sim, 1)
	_check(_count(events, following.uid) == 1, "The moved aura damages a new target at the current player location")
	old.position = sim.player_position + Vector2(90, 0)
	_steps(sim, 1)
	_check(_count(events, old.uid) == 2, "Returning to the moving aura grants one contact without paying absent tick debt")
	_steps(sim, 2)
	_check(_count(events, old.uid) == 2, "Aura reentry resumes cadence instead of catching up immediately")

func _test_falsche_uid_reuse() -> void:
	var sim: CombatSim = _sim("falsche")
	var position: Vector2 = sim.player_position + Vector2(80, 0)
	var target: CombatSim.Enemy = _enemy(sim, position)
	var uid: int = target.uid
	var slot: int = target.slot
	var events: Array[Dictionary] = _receipts(sim, "falsche")
	_check(sim.try_hero_skill(), "The aura UID fixture starts a real cast")
	_steps(sim, 1)
	sim.apply_damage(target, HEALTH * 2.0, "fixture")
	var replacement: CombatSim.Enemy = _enemy(sim, position)
	_check(replacement.slot == slot and replacement.uid != uid, "The aura fixture actually reuses a dead pool slot with a distinct UID")
	_steps(sim, 1)
	_check(_count(events, uid) == 1 and _count(events, replacement.uid) == 1 and replacement.health < HEALTH, "A replacement receives its independent first contact immediately rather than inheriting the old UID's next-contact clock")
	var contacts: Dictionary = sim.skill_timeline.snapshot()["areas"][0]["hits"]
	_check(int(contacts.get("enemy:%d" % uid, 0)) == 1 and int(contacts.get("enemy:%d" % replacement.uid, 0)) == 1 and contacts.size() == 2, "The reused pool slot retains two independent canonical enemy:UID keys without changing the public contact protocol")
	_steps(sim, 18)
	_check(_count(events, replacement.uid) == 1, "A new UID also owns its own thirty-hit cadence")
	_steps(sim, 1)
	_check(_count(events, replacement.uid) == 2, "The replacement's second contact occurs on its own valid interval")

func _test_falsche_external_uid_change() -> void:
	var sim: CombatSim = _sim("falsche")
	var target: CombatSim.Enemy = _enemy(sim, sim.player_position + Vector2(80, 0))
	var old_uid: int = target.uid
	var events: Array[Dictionary] = _receipts(sim, "falsche")
	_check(sim.try_hero_skill(), "The external UID fixture starts the real continuous aura")
	_steps(sim, 1)
	var first: Dictionary = sim.skill_timeline.snapshot()["areas"][0]["hits"]
	_check(_count(events, old_uid) == 1 and int(first.get("enemy:%d" % old_uid, 0)) == 1, "The first physical step establishes the old UID contact")
	target.uid = old_uid + 1000
	var next_uid: int = target.uid
	var random_states: Array[String] = [str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)]
	_steps(sim, 1)
	var second: Dictionary = sim.skill_timeline.snapshot()["areas"][0]["hits"]
	_check(_count(events, old_uid) == 1 and _count(events, next_uid) == 1 and int(second.get("enemy:%d" % old_uid, 0)) == 1 and int(second.get("enemy:%d" % next_uid, 0)) == 1 and second.size() == 2, "A directly changed real UID cannot keep its cached predecessor's contact key or cadence")
	_check([str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)] == random_states, "Refreshing the derived UID contact key consumes none of the three random streams")

func _test_pool_and_presentation() -> void:
	var expected: Dictionary = {"nasir": Color("f1875e"), "mordiga": Color("67cce5"), "falsche": Color("b49ce2")}
	for id: String in IDS:
		var sim: CombatSim = _sim(id)
		_check(sim.try_hero_skill(), "Presentation fixture casts the actual roster skill: " + id)
		_steps(sim, 1)
		var before: String = _signature(sim)
		var snapshot: Dictionary = sim.skill_timeline.snapshot()
		for flash: bool in [true, false]:
			var geometry: Dictionary = SkillAreaPainter.geometry_snapshot(snapshot, flash)
			_check(not geometry["commands"].is_empty() and geometry["commands"].size() <= SkillAreaPainter.MAX_COMMANDS, "The actual timeline produces bounded presentation in both flash modes: " + id)
			if not geometry["commands"].is_empty():
				var tint: Color = geometry["commands"][0]["color"]
				var color: Color = expected[id]
				_check(is_equal_approx(tint.r, color.r) and is_equal_approx(tint.g, color.g) and is_equal_approx(tint.b, color.b), "The source element uses its distinct fire/water/dark palette: " + id)
				geometry["commands"][0]["color"] = Color.BLACK
		snapshot["areas"][0]["parameters"]["damage"] = -1.0
		snapshot["areas"][0]["origin"] = Vector2.INF
		snapshot["areas"][0]["hits"]["enemy:999"] = 99
		_check(_signature(sim) == before, "Painter snapshots and external presentation edits cannot change source state, clocks, contacts, stats or three random streams: " + id)
		var full: CombatSim = _sim(id)
		for cast: int in SkillTimelineRuntime.LIMIT:
			_check(full.skill_timeline.enqueue(full.run.hero_skill_parameters(), full.player_position, Vector2.RIGHT), "The roster skill uses the existing bounded area pool: " + id)
		var occupied: Dictionary = full.hero_effects_snapshot()
		_check(not full.try_hero_skill() and full.hero_effects_snapshot() == occupied and int(full.hero_skill_snapshot()["uses"]) == 0, "A full pool rejects the actual R transaction without consuming cooldown or altering any reserved area: " + id)
	_check(SkillTimelineRuntime.LIMIT == 24 and SkillTimelineRuntime.MAX_HITS == 32, "Roster support does not enlarge the existing area or hit budgets")

func _test_legacy_offsets() -> void:
	_check(HeroCatalog.LEGACY_IDS == ["alk", "clarisse", "celtie", "hanabi"] and HeroCatalog.REAR_IDS == {"pulse": "clarisse", "starfall": "hanabi", "arc_slash": "celtie"}, "The old four main identities and three rear mappings remain stable")
	for id: String in HeroCatalog.LEGACY_IDS:
		var sim: CombatSim = _sim(id)
		var origin: Vector2 = sim.player_position + (Vector2(160, 0) if id == "clarisse" else Vector2.ZERO)
		_check(sim.try_hero_skill(), "The existing hero still accepts its real R: " + id)
		for phase: Dictionary in sim.skill_timeline.snapshot()["areas"]:
			_check(phase["origin"] == origin and phase["follow_offset"] == Vector2.ZERO, "The new offset adapter does not move or offset an existing hero's area: " + id)

func _test_world_lifecycle() -> void:
	var sound := QuietSound.new()
	root.add_child(sound)
	var world := RosterWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.set_physics_process(false)
	for id: String in IDS:
		world.begin(_state(id))
		_quiet(world.sim)
		_check(world.request_hero_skill(), "The actual World queues a new roster R: " + id)
		world._physics_process(STEP)
		_check(int(world.sim.hero_skill_snapshot()["uses"]) == 1 and int(world.sim.skill_timeline.snapshot()["occupied"]) == 1, "World consumes the request into a real timeline reservation: " + id)
		paused = true
		var frozen: String = _signature(world.sim)
		world._physics_process(1.0)
		for frame: int in 2:
			await process_frame
		_check(_signature(world.sim) == frozen and not world.request_hero_skill(), "Pause freezes the new character's source clock and rejects queued input: " + id)
		paused = false
		world._physics_process(STEP)
		_check(_signature(world.sim) != frozen, "Resume advances the same source reservation: " + id)
		world.stop()
		_check(int(world.sim.skill_timeline.snapshot()["occupied"]) == 0 and not world.request_hero_skill(), "Stopping World clears the new roster's reservations and pending controls: " + id)
	world.begin(_state("falsche"))
	_quiet(world.sim)
	world.request_hero_skill()
	world._physics_process(STEP)
	world.sim._finish(false, "roster lifecycle fixture")
	_check(not world.active and int(world.sim.skill_timeline.snapshot()["occupied"]) == 0 and not world.sim.try_hero_skill(), "Finishing combat clears the ten-second aura and cannot resume it")
	world.begin(_state("nasir"))
	_quiet(world.sim)
	_check(int(world.sim.hero_skill_snapshot()["uses"]) == 0 and int(world.sim.skill_timeline.snapshot()["occupied"]) == 0 and not world._hero_skill_pending, "Replacement begin starts clean without a prior aura, clock or stale input")
	world.stop()
	world.queue_free()
	sound.queue_free()
	for frame: int in 2:
		await process_frame
