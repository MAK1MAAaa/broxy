extends SceneTree
## Real casts and hostile projectiles exercise the bounded, static result slot.

const STEP: float = 1.0 / 60.0
const SKILL_FIXTURE = preload("res://tests/skill_fixture.gd")
var _checks: int = 0
var _failures: int = 0

class ProbeSoundBank extends SoundBank:
	var names: Array[String] = []
	var levels: Array[float] = []
	var cues: Array[String] = []
	var cancelled: Array[String] = []
	var stops: int = 0
	func _ready() -> void:
		pass
	func play(name: String, loudness: float = -10.0) -> void:
		names.append(name)
		levels.append(loudness)
		cues.append("")
	func play_cue(name: String, loudness: float, cue_id: String) -> void:
		names.append(name)
		levels.append(loudness)
		cues.append(cue_id)
	func cancel_cue(cue_id: String) -> void:
		cancelled.append(cue_id)
	func stop_combat_cues() -> void:
		stops += 1

class ProbeWorld extends CombatWorld:
	var movement: Vector2 = Vector2.ZERO
	func _movement() -> Vector2:
		return movement

class DrawSpy extends ProbeWorld:
	var passes: Array[String] = []
	var anchors: Array[Vector2] = []
	func _draw_atmosphere() -> void:
		pass
	func _draw_ground_contacts() -> void:
		pass
	func _draw_pulse_range(_origin: Vector2, _radius: float) -> void:
		passes.append("range")
	func _draw_pulse_animation(_origin: Vector2, _radius: float, _progress: float) -> void:
		passes.append("animation")
	func _draw_souls() -> void:
		pass
	func _draw_enemies() -> void:
		passes.append("enemies")
	func _draw_friendly_shots() -> void:
		pass
	func _draw_player_ground() -> void:
		pass
	func _draw_effects() -> void:
		pass
	func _draw_impact_feedback() -> void:
		pass
	func _draw_rune_feedback() -> void:
		pass
	func _draw_outgoing_feedback() -> void:
		pass
	func _draw_player() -> void:
		passes.append("player")
	func _draw_skill_feedback_text(anchor: Vector2) -> void:
		passes.append("result")
		anchors.append(anchor)
	func _draw_dash_evasion_feedback() -> void:
		passes.append("evasion")
	func _draw_feedback() -> void:
		passes.append("incoming")
	func _draw_danger() -> void:
		passes.append("danger")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_control_and_frost()
	await _test_no_control()
	await _test_flash_pause_and_expiry()
	await _test_evasion_and_damage_priority()
	await _test_damage_before_cast()
	await _test_lifecycle()
	await _test_draw_and_edges()
	print("SkillFeedback: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _begin(world: CombatWorld) -> void:
	var state := RunState.new()
	state.begin(20261028, "bone", "mire")
	_check(SKILL_FIXTURE.equip_pulse(state), "The feedback fixture owns a physical pulse box")
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	world.sim.player_direction = Vector2.RIGHT
	if world is DrawSpy:
		world.arena_texture = null

func _world(spy: bool = false) -> ProbeWorld:
	var sound := ProbeSoundBank.new()
	root.add_child(sound)
	var world: ProbeWorld = DrawSpy.new() if spy else ProbeWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.set_physics_process(false)
	if spy:
		world.arena_texture = null
	_begin(world)
	return world

func _dispose(world: CombatWorld) -> void:
	world.sound.queue_free()
	world.queue_free()
	for frame: int in 2:
		await process_frame

func _enemy(world: CombatWorld, id: String, offset: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = world.sim.spawn_enemy(id, CombatSim.clamp_point(world.sim.player_position + offset))
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _cast(world: CombatWorld) -> void:
	_check(world.request_pulse(), "A ready World queues the actual pulse")
	world._physics_process(STEP)

func _hash(world: CombatWorld) -> String:
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	return JSON.stringify([world.sim.snapshot(), world.sim.run.summary(), str(world.sim.rng.state), str(world.sim.run.rng.state),
		world.skill_feedback_snapshot(), world.pulse_feedback_snapshot(), world.dash_evasion_feedback_snapshot(),
		world._damage_flash, world._shake, world._numbers.size(), world._feedback_serial,
		sound.names, sound.levels, sound.cues, sound.cancelled, sound.stops])

func _test_control_and_frost() -> void:
	var world: ProbeWorld = _world()
	var frost: CombatSim.Enemy = _enemy(world, "chaser", Vector2(80, 0))
	frost.slow_timer = 0.8
	var tank: CombatSim.Enemy = _enemy(world, "tank", Vector2(0, 90))
	var caster: CombatSim.Enemy = _enemy(world, "caster", Vector2(-100, 0))
	var outside: CombatSim.Enemy = _enemy(world, "chaser", Vector2(150, 0))
	var origin: Vector2 = world.sim.player_position
	var sim_rng: int = world.sim.rng.state
	var run_rng: int = world.sim.run.rng.state
	var image_ids: Array = world._dash_afterimages.map(func(image: CombatWorld.DashAfterimage) -> int: return image.get_instance_id())
	_cast(world)
	var feedback: Dictionary = world.skill_feedback_snapshot()
	_check(bool(feedback["active"]) and feedback["text"] == "受控 ×3" and feedback["affected"] == 3 and is_equal_approx(feedback["remaining"], 0.45), "Three truly controlled ordinary enemies produce one 450ms result")
	var expected_text_width: float = GameTypography.font().get_string_size(str(feedback["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_check(feedback["origin"] == origin and expected_text_width > 0.0 and is_equal_approx(float(feedback["text_width"]), expected_text_width) and feedback["anchor"] == origin + Vector2(0, 54), "The cached pixel text uses its actual font width and stays below the cast origin")
	_check(frost.pulse_hinder_timer > 0.0 and tank.pulse_hinder_timer > 0.0 and caster.pulse_hinder_timer > 0.0 and outside.pulse_hinder_timer == 0.0, "The sign reports actual radial control instead of all living targets")
	_check(frost.slow_timer > 0.0 and world._enemy_tint(frost) == Color("b4e9ed"), "A frozen target retains frost tint while the separate result still confirms control")
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	_check(sound.names == ["pulse_hit"] and sound.cues == ["pulse"] and sound.levels == [-20.0], "A real controlled cast selects its dedicated quiet hit sound")
	_check(world.sim.pulses_used == 1 and world.sim.pulse_affected == 3 and world.sim.last_pulse_affected == 3, "Presentation keeps the simulation's exact cast and affected counts")
	_check(frost.health == frost.max_health and tank.health == tank.max_health and caster.health == caster.max_health and world._numbers.is_empty() and world._feedback_serial == 0, "Control confirmation creates no damage or floating damage-number use")
	_check(world.sim.run.health == 100.0 and world.sim.run.gold == 0 and world.sim.run.kills == 0 and world._shake == 0.0 and world.sim.rng.state == sim_rng and world.sim.run.rng.state == run_rng, "The result creates no reward, health, shake or random-stream changes")
	_check(image_ids.size() == 6 and image_ids == world._dash_afterimages.map(func(image: CombatWorld.DashAfterimage) -> int: return image.get_instance_id()), "The original six afterimage objects remain unchanged")
	var unchanged: String = _hash(world)
	for repeat: int in 8:
		world.sim.pulse_cast.emit(origin, 999)
	_check(_hash(world) == unchanged, "Replayed signals cannot change text, count, lifetime, audio or simulation")
	feedback["affected"] = 999
	_check(world.skill_feedback_snapshot()["affected"] == 3, "The public result snapshot cannot mutate the slot")
	world.movement = Vector2.RIGHT
	world._physics_process(STEP)
	_check(world.sim.player_position != origin and world.skill_feedback_snapshot()["origin"] == origin and world.skill_feedback_snapshot()["anchor"] == origin + Vector2(0, 54), "Moving after a cast leaves the result at its fixed world location")
	await _dispose(world)

func _test_no_control() -> void:
	for scenario: String in ["empty", "immune"]:
		var world: ProbeWorld = _world()
		var immune: Array[CombatSim.Enemy] = []
		if scenario == "immune":
			var boss: CombatSim.Enemy = _enemy(world, "boss", Vector2(100, 0))
			var hunter: CombatSim.Enemy = _enemy(world, "rusher", Vector2(-100, 0))
			hunter.hunter = true
			immune.assign([boss, hunter])
		_cast(world)
		var feedback: Dictionary = world.skill_feedback_snapshot()
		var sound: ProbeSoundBank = world.sound as ProbeSoundBank
		_check(bool(feedback["active"]) and feedback["text"] == "未受控" and feedback["affected"] == 0, "Zero actual control reports a neutral result without guessing immunity: " + scenario)
		_check(sound.names == ["pulse"] and sound.cues == ["pulse"] and sound.levels == [-20.0], "A zero-control cast selects only the empty pulse sound: " + scenario)
		_check(world.sim.pulses_used == 1 and world.sim.pulse_affected == 0 and world.sim.run.health == 100.0 and world._numbers.is_empty(), "A zero-control cast still consumes its real cooldown without causing damage: " + scenario)
		for enemy: CombatSim.Enemy in immune:
			_check(enemy.pulse_hinder_timer == 0.0 and enemy.health == enemy.max_health, "Immune enemies are not marked controlled by feedback")
		await _dispose(world)

func _test_flash_pause_and_expiry() -> void:
	var world: ProbeWorld = _world()
	world.apply_visual_settings({"flash": false, "shake": true})
	_enemy(world, "chaser", Vector2(80, 0))
	_cast(world)
	_check(bool(world.skill_feedback_snapshot()["active"]) and world.skill_feedback_snapshot()["text"] == "受控 ×1" and not bool(world.pulse_feedback_snapshot()["animated"]), "Flash-off retains a static actual result while disabling the optional ring animation")
	paused = true
	world.set_physics_process(true)
	var frozen: String = _hash(world)
	for frame: int in 4:
		await process_frame
	world._physics_process(STEP)
	_check(_hash(world) == frozen, "Real pause freezes result, range, cooldown, audio and simulation")
	world.set_physics_process(false)
	paused = false
	world.apply_visual_settings({"flash": true, "shake": true})
	_check(world.skill_feedback_snapshot()["remaining"] == 0.45 and not bool(world.pulse_feedback_snapshot()["animated"]), "Re-enabling flashes neither restarts the result lifetime nor replays its animation")
	for frame: int in 18:
		world._physics_process(STEP)
	_check(not bool(world.pulse_feedback_snapshot()["active"]) and bool(world.skill_feedback_snapshot()["active"]), "The original 300ms range expires before the independent 450ms result")
	for frame: int in 9:
		world._physics_process(STEP)
	_check(not bool(world.skill_feedback_snapshot()["active"]) and world.skill_feedback_snapshot()["remaining"] == 0.0 and world.skill_feedback_snapshot()["affected"] == 1, "The single result expires at 450ms without clearing its last accepted count")
	_check(float(world.sim.pulse_snapshot()["cooldown_left"]) > 0.0 and world.sim.pulses_used == 1, "Result expiry cannot alter or replay the actual skill cooldown")
	await _dispose(world)

func _test_evasion_and_damage_priority() -> void:
	var world: ProbeWorld = _world()
	world.movement = Vector2.RIGHT
	_enemy(world, "chaser", Vector2(-90, 0))
	_check(world.request_pulse() and world.request_dash(), "Both actual skills can be queued in the same step")
	world.sim._hostile_shot(world.sim.player_position + Vector2(11, 0), Vector2.ZERO, 8.0, "caster")
	world._physics_process(STEP)
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	_check(world.sim.pulses_used == 1 and world.sim.pulse_affected == 1 and world.sim.dash_evades == 1 and world.sim.run.health == 100.0, "A same-step pulse, dash and overlapping hostile projectile use the real protection rules")
	_check(not bool(world.skill_feedback_snapshot()["active"]) and world.skill_feedback_snapshot()["affected"] == 1 and bool(world.dash_evasion_feedback_snapshot()["active"]), "Successful evasion immediately takes visual priority without losing the accepted pulse count")
	_check(sound.names == ["pulse_hit", "dash", "evade"] and sound.cues == ["pulse", "dash", "dash_evasion"] and sound.levels == [-20.0, -20.0, -22.0], "Actual simulation order dispatches the three independent skill cues once")
	var unchanged: String = _hash(world)
	world.sim.pulse_cast.emit(world.skill_feedback_snapshot()["origin"], 1)
	_check(_hash(world) == unchanged, "A replay cannot resurrect the result cleared by a true evasion")
	for frame: int in 12:
		if world.sim.dash_invulnerability_left <= 0.0:
			break
		world._physics_process(STEP)
	world.sim._hostile_shot(world.sim.player_position + Vector2(11, 0), Vector2.ZERO, 8.0, "caster")
	world._physics_process(STEP)
	_check(world.sim.run.health == 92.0 and world.sim.run.hits_taken == 1 and not bool(world.dash_evasion_feedback_snapshot()["active"]) and not bool(world.skill_feedback_snapshot()["active"]), "A real vulnerable-tail projectile clears both success presentations and shows actual incoming loss")
	_check(sound.cancelled == ["dash_evasion"] and sound.names == ["pulse_hit", "dash", "evade", "hurt"], "Actual player damage cancels the success cue before its ordinary hurt sound")
	_check(world.skill_feedback_snapshot()["affected"] == 1 and world.sim.pulse_affected == 1 and world.sim.dash_evades == 1 and world._damage_flash > 0.0, "Damage priority preserves mechanical counts and the existing damage feedback")
	unchanged = _hash(world)
	world.sim.pulse_cast.emit(world.skill_feedback_snapshot()["origin"], 1)
	world.sim.dash_evaded.emit(world.sim.player_position, Vector2.ZERO, "caster", "projectile")
	_check(_hash(world) == unchanged, "Late same-cast and same-dash events cannot revive results or their audio after damage")
	await _dispose(world)
	world = _world()
	_enemy(world, "chaser", Vector2(80, 0))
	world.sim._hostile_shot(world.sim.player_position, Vector2.ZERO, 8.0, "caster")
	_cast(world)
	_check(world.sim.run.health == 92.0 and world.sim.pulse_affected == 1 and not bool(world.skill_feedback_snapshot()["active"]) and bool(world.pulse_feedback_snapshot()["active"]), "A same-frame actual hit clears the earlier pulse result while retaining its true range and count")
	await _dispose(world)

func _test_damage_before_cast() -> void:
	var world: ProbeWorld = _world()
	world.sim._hostile_shot(world.sim.player_position, Vector2.ZERO, 8.0, "caster")
	world._physics_process(STEP)
	_enemy(world, "chaser", Vector2(80, 0))
	_cast(world)
	_check(world.sim.run.health == 92.0 and world.sim.pulse_affected == 1 and world._damage_flash > 0.0 and not bool(world.skill_feedback_snapshot()["active"]), "A fresh valid cast cannot cover an incoming-loss confirmation that is still active")
	_check(world.skill_feedback_snapshot()["affected"] == 1 and bool(world.pulse_feedback_snapshot()["active"]) and (world.sound as ProbeSoundBank).names == ["hurt", "pulse_hit"], "Priority suppresses only the result sign, preserving accepted control, range and sound")
	await _dispose(world)

func _test_lifecycle() -> void:
	var world: ProbeWorld = _world()
	_cast(world)
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	var stop_before: int = sound.stops
	world.stop()
	_check(sound.stops == stop_before + 1 and not bool(world.skill_feedback_snapshot()["active"]) and world.skill_feedback_snapshot()["text"] == "" and world.skill_feedback_snapshot()["affected"] == 0 and world.skill_feedback_snapshot()["origin"] == Vector2.ZERO, "Stop clears the full result slot and stops combat cues")
	_begin(world)
	_cast(world)
	stop_before = sound.stops
	_begin(world)
	_check(sound.stops == stop_before + 1 and not bool(world.skill_feedback_snapshot()["active"]) and world.sim.pulses_used == 0, "Replacing combat resets results, cue playback and deduplication")
	_cast(world)
	stop_before = sound.stops
	world.sim._finish(false, "skill result terminal fixture")
	_check(sound.stops == stop_before + 1 and not world.active and not bool(world.skill_feedback_snapshot()["active"]) and world.skill_feedback_snapshot()["text"] == "", "Terminal combat clears the slot and stops its cues immediately")
	var unchanged: String = _hash(world)
	world.sim.pulse_cast.emit(Vector2(500, 300), 10)
	world.sim.dash_evaded.emit(Vector2(500, 300), Vector2.ZERO, "caster", "projectile")
	_check(_hash(world) == unchanged, "Completed-combat events cannot recreate a result or sound")
	await _dispose(world)

func _test_draw_and_edges() -> void:
	var world: DrawSpy = _world(true) as DrawSpy
	var corners: Array[Vector2] = [CombatSim.ARENA.position, Vector2(CombatSim.ARENA.end.x, CombatSim.ARENA.position.y), CombatSim.ARENA.end, Vector2(CombatSim.ARENA.position.x, CombatSim.ARENA.end.y)]
	for origin: Vector2 in corners:
		_begin(world)
		world.sim.player_position = origin
		_cast(world)
		var feedback: Dictionary = world.skill_feedback_snapshot()
		var anchor: Vector2 = feedback["anchor"]
		var width: float = float(feedback["text_width"])
		var view: Rect2 = world.camera_view()
		var safe: Rect2 = world._feedback_safe_rect()
		var text_rect := Rect2(anchor - Vector2(width * 0.5, CombatWorld.SKILL_FEEDBACK_FONT_SIZE), Vector2(width, CombatWorld.SKILL_FEEDBACK_FONT_SIZE))
		_check(width > 0.0 and view.grow(0.01).encloses(safe) and safe.grow(0.01).encloses(text_rect), "The cached result stays inside the translated camera's HUD-safe rectangle at corner: " + str(origin))
		_check(anchor.y - origin.y >= 54.0 or origin.y - anchor.y >= 62.0, "A bottom-edge result moves above the body instead of covering the player or bottom HUD")
		world.passes.clear()
		world.anchors.clear()
		var before: String = _hash(world)
		for repeat: int in 3:
			world._draw()
		_check(_hash(world) == before and world.anchors.size() == 3 and world.anchors[-1] == anchor, "Repeated drawing never changes feedback, audio, rules or cached placement")
		_check(world.passes.find("range") < world.passes.find("enemies") and world.passes.find("player") < world.passes.find("result") and world.passes.find("result") < world.passes.find("incoming") and world.passes.back() == "danger", "Actual drawing keeps the range below units and result below incoming loss and final hostile danger")
		world.apply_visual_settings({"flash": false, "shake": true})
		world.passes.clear()
		world._draw()
		_check(world.passes.has("result") and world.passes.has("range") and not world.passes.has("animation") and world.passes.back() == "danger", "Flash-off draws static result and range without covering hostile danger")
	world.stop()
	world.passes.clear()
	world._draw()
	_check(not world.passes.has("result") and not world.passes.has("range"), "Stopped combat draws no stale result or range")
	await _dispose(world)
