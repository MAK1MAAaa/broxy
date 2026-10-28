extends SceneTree
## Real World requests, control, optional animation and inherited draw ordering.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

class ProbeSoundBank extends SoundBank:
	var names: Array[String] = []
	var levels: Array[float] = []
	var cues: Array[String] = []
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

class ProbeWorld extends CombatWorld:
	var movement: Vector2 = Vector2.ZERO
	func _movement() -> Vector2:
		return movement
	func _maintain_stress() -> void:
		pass

class DrawSpy extends ProbeWorld:
	var passes: Array[String] = []
	var range_origins: Array[Vector2] = []
	var range_radii: Array[float] = []
	var animation_radii: Array[float] = []
	func _draw_atmosphere() -> void:
		passes.append("atmosphere")
	func _draw_pulse_range(origin: Vector2, radius: float) -> void:
		passes.append("range")
		range_origins.append(origin)
		range_radii.append(radius)
	func _draw_pulse_animation(_origin: Vector2, radius: float, _progress: float) -> void:
		passes.append("animation")
		animation_radii.append(radius)
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
	func _draw_feedback() -> void:
		passes.append("incoming")
	func _draw_danger() -> void:
		passes.append("danger")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_queue_and_cooldown()
	await _test_dual_skill_control()
	await _test_gates_and_lifecycle()
	await _test_pause_and_flash()
	_test_state_tint_and_draw()
	print("PulseWorld: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _begin(world: CombatWorld) -> void:
	var state := RunState.new()
	state.begin(20261028, "bone")
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)

func _world() -> ProbeWorld:
	var sound := ProbeSoundBank.new()
	root.add_child(sound)
	var world := ProbeWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.set_physics_process(false)
	_begin(world)
	return world

func _dispose(world: ProbeWorld) -> void:
	world.sound.queue_free()
	world.queue_free()
	for frame: int in 3:
		await process_frame

func _pulse(world: CombatWorld) -> Dictionary:
	return world.sim.snapshot()["pulse"]

func _state_hash(world: CombatWorld) -> String:
	var entities: Array = []
	for enemy: CombatSim.Enemy in world.sim.enemies:
		if enemy.active:
			entities.append([enemy.position, enemy.velocity, enemy.health, enemy.action_timer, enemy.hurt_timer, enemy.slow_timer, enemy.pulse_hinder_timer])
	for image: CombatWorld.DashAfterimage in world._dash_afterimages:
		entities.append([image.get_instance_id(), image.position, image.lean, image.life])
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	return JSON.stringify([world.sim.snapshot(), world.sim.run.summary(), str(world.sim.rng.state), str(world.sim.run.rng.state),
		world.pulse_feedback_snapshot(), world.dash_evasion_feedback_snapshot(), world._visual_time, world._numbers.size(), world._number_free.size(),
		entities, sound.names, sound.levels, sound.cues])

func _test_queue_and_cooldown() -> void:
	var world: ProbeWorld = _world()
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	var hud: Array[Dictionary] = []
	world.hud_changed.connect(func(value: Dictionary) -> void: hud.append(value.duplicate(true)))
	var origin: Vector2 = world.sim.player_position
	_check(not world.pulse_feedback_snapshot()["active"] and world.request_pulse() and int(_pulse(world)["uses"]) == 0, "A real ready pulse queues without changing simulation or creating feedback")
	_check(not world.request_pulse(), "Repeated input in one tick cannot queue another pulse")
	world._physics_process(STEP)
	var feedback: Dictionary = world.pulse_feedback_snapshot()
	_check(int(_pulse(world)["uses"]) == 1 and not world._pulse_pending, "The next real fixed step consumes exactly one pulse request")
	_check(feedback["active"] and is_equal_approx(feedback["remaining"], 0.30) and feedback["origin"] == origin and feedback["radius"] == 144.0 and feedback["affected"] == 0 and feedback["animated"], "One bounded 300ms slot reports the real origin, radius and zero-target cast")
	_check(hud.size() == 1 and int(hud[0]["pulse"]["uses"]) == 1, "Cast feedback immediately publishes the actual cooldown snapshot")
	_check(sound.names == ["rune"] and sound.levels == [-20.0] and sound.cues == ["pulse"], "Pulse uses the real independent cue API at its intended level")
	_check(world._numbers.is_empty() and world._number_free.size() == CombatWorld.NUMBER_LIMIT and world._shake == 0.0 and world.sim.run.health == 100.0 and world.sim.run.gold == 0, "A pulse adds no damage numbers, camera shake, health cost or reward")
	for frame: int in 18:
		world._physics_process(STEP)
	_check(not world.pulse_feedback_snapshot()["active"] and world.pulse_feedback_snapshot()["remaining"] == 0.0 and float(_pulse(world)["cooldown_left"]) > 0.0, "The single visual slot expires after 300ms while the real cooldown continues")
	var cooldown_requests_rejected: bool = true
	for frame: int in ceili(float(_pulse(world)["cooldown_total"]) / STEP) + 2:
		if bool(_pulse(world)["ready"]):
			break
		cooldown_requests_rejected = not world.request_pulse() and cooldown_requests_rejected
		world._physics_process(STEP)
	_check(cooldown_requests_rejected and bool(_pulse(world)["ready"]) and int(_pulse(world)["uses"]) == 1, "Cooldown input is rejected and never replayed on readiness")
	_check(world.request_pulse(), "Readiness accepts a fresh deliberate request")
	world.clear_pending_actions()
	world._physics_process(STEP)
	_check(int(_pulse(world)["uses"]) == 1 and not world._pulse_pending, "Clearing pending actions cancels a queued pulse")
	feedback["radius"] = 999.0
	_check(world.pulse_feedback_snapshot()["radius"] == 144.0, "Feedback queries return independent values")
	await _dispose(world)

func _test_dual_skill_control() -> void:
	var world: ProbeWorld = _world()
	world.movement = Vector2.RIGHT
	var origin: Vector2 = world.sim.player_position
	var behind: CombatSim.Enemy = world.sim.spawn_enemy("chaser", origin + Vector2(-140, 0))
	var outside: CombatSim.Enemy = world.sim.spawn_enemy("chaser", origin + Vector2(180, 0))
	behind.action_timer = 999.0
	outside.action_timer = 999.0
	var ids: Array = world._dash_afterimages.map(func(image: CombatWorld.DashAfterimage) -> int: return image.get_instance_id())
	_check(world.request_dash() and world.request_pulse(), "Both independently ready skills can queue in the same tick")
	world._physics_process(STEP)
	_check(world.sim.dashes_used == 1 and int(_pulse(world)["uses"]) == 1 and not world._dash_pending and not world._pulse_pending, "A dual-skill step consumes each input exactly once")
	_check(world.sim.player_position.x > origin.x and world.pulse_feedback_snapshot()["origin"] == origin and world.pulse_feedback_snapshot()["affected"] == 1, "Pulse applies at the starting point before the same-tick dash displacement")
	_check(behind.pulse_hinder_timer > 0.0 and behind.velocity.length() < behind.definition.speed and outside.pulse_hinder_timer == 0.0, "The real pulse slows the ordinary enemy inside its original radius and leaves the distant enemy unmarked")
	_check(behind.health == behind.max_health and behind.hurt_timer == 0.0 and world._numbers.is_empty(), "Control changes no enemy health or damage-number accounting")
	_check(ids == world._dash_afterimages.map(func(image: CombatWorld.DashAfterimage) -> int: return image.get_instance_id()) and ids.size() == 6 and world.dash_afterimage_count() > 0, "Dual casting retains all six original dash afterimage slots")
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	_check(sound.cues == ["pulse", ""] and sound.names == ["rune", "rune"], "The original dash sound and independent pulse cue follow their actual simulation order")
	world._physics_process(STEP)
	_check(int(_pulse(world)["uses"]) == 1 and world.sim.dashes_used == 1 and world.pulse_feedback_snapshot()["origin"] == origin, "Later ticks cannot replay either queued skill or move the stored pulse origin")
	await _dispose(world)

func _test_gates_and_lifecycle() -> void:
	var empty := CombatWorld.new()
	empty.active = true
	_check(not empty.request_pulse(), "Missing simulation rejects pulse input")
	empty.free()
	var world: ProbeWorld = _world()
	_check(world.request_dash() and world.request_pulse(), "Pause fixture queues both real actions")
	paused = true
	var elapsed: float = world.sim.elapsed
	_check(not world.request_pulse(), "Paused trees reject a new pulse request")
	world._physics_process(STEP)
	_check(world.sim.elapsed == elapsed and not world._pulse_pending and not world._dash_pending, "A paused update cancels both pending skills without advancing simulation")
	paused = false
	for mode: String in ["autopilot", "stress_mode"]:
		_check(world.request_dash() and world.request_pulse(), "Diagnostic transition queues both ready skills first")
		world.set(mode, true)
		world._physics_process(STEP)
		_check(not world.request_pulse() and int(_pulse(world)["uses"]) == 0 and world.sim.dashes_used == 0 and not world._pulse_pending and not world._dash_pending, "Changing to a diagnostic cancels both queued skills: " + mode)
		world.set(mode, false)
	_check(world.request_dash() and world.request_pulse(), "Stop fixture queues both actions")
	world.stop()
	_check(not world.request_pulse() and not world._dash_pending and not world._pulse_pending and not world.pulse_feedback_snapshot()["active"], "Stopping rejects pulse input and clears both queues and its visual slot")
	_begin(world)
	_check(world.request_dash() and world.request_pulse(), "Replacement fixture queues both actions")
	_begin(world)
	world._physics_process(STEP)
	_check(int(_pulse(world)["uses"]) == 0 and world.sim.dashes_used == 0 and not world._pulse_pending and not world._dash_pending, "A replacement simulation consumes neither old pending action")
	world.sim.run.health = 0.0
	_check(not world.request_pulse(), "A dead player cannot queue control")
	world.sim.run.health = 100.0
	world.request_pulse()
	world._physics_process(STEP)
	world.sim._finish(false, "pulse world terminal fixture")
	_check(not world.active and not world.request_pulse() and not world.pulse_feedback_snapshot()["active"] and world.pulse_feedback_snapshot()["origin"] == Vector2.ZERO, "Terminal combat clears the origin and slot and rejects future input")
	await _dispose(world)

func _test_pause_and_flash() -> void:
	var world: ProbeWorld = _world()
	world.request_pulse()
	world._physics_process(STEP)
	var origin: Vector2 = world.pulse_feedback_snapshot()["origin"]
	world.movement = Vector2.RIGHT
	world._physics_process(STEP)
	_check(world.sim.player_position != origin and world.pulse_feedback_snapshot()["origin"] == origin, "Moving after a cast cannot drag its real range outline with the player")
	paused = true
	world.set_physics_process(true)
	var remaining: float = world.pulse_feedback_snapshot()["remaining"]
	world.apply_visual_settings({"shake": true, "flash": false})
	_check(world.pulse_feedback_snapshot()["active"] and not world.pulse_feedback_snapshot()["animated"] and world.pulse_feedback_snapshot()["remaining"] == remaining, "Flash-off cancels animation immediately while preserving the static range and its original lifetime")
	var frozen: String = _state_hash(world)
	for frame: int in 4:
		await process_frame
	_check(_state_hash(world) == frozen, "Real pause freezes pulse feedback, cooldown and the entire combat fixture")
	world.apply_visual_settings({"shake": true, "flash": true})
	_check(not world.pulse_feedback_snapshot()["animated"] and world.pulse_feedback_snapshot()["remaining"] == remaining, "Flash-on does not replay the canceled range animation")
	paused = false
	await physics_frame
	await physics_frame
	world.set_physics_process(false)
	_check(float(world.pulse_feedback_snapshot()["remaining"]) < remaining, "Resume continues the existing slot countdown")
	for frame: int in 20:
		world._physics_process(STEP)
	_check(not world.pulse_feedback_snapshot()["active"], "The static range expires at the original lifetime")
	world.apply_visual_settings({"shake": true, "flash": false})
	_begin(world)
	world.request_pulse()
	world._physics_process(STEP)
	_check(world.pulse_feedback_snapshot()["active"] and not world.pulse_feedback_snapshot()["animated"], "A flash-off cast still creates its static true-range indicator")
	world.stop()
	_begin(world)
	_check(not world.pulse_feedback_snapshot()["active"] and world.pulse_feedback_snapshot()["radius"] == 0.0, "Stop and begin remove all previous single-slot state")
	await _dispose(world)

func _test_state_tint_and_draw() -> void:
	var sound := ProbeSoundBank.new()
	var world := DrawSpy.new()
	world.sound = sound
	_begin(world)
	var enemy: CombatSim.Enemy = world.sim.spawn_enemy("chaser", world.sim.player_position + Vector2(80, 0))
	world.request_pulse()
	world._physics_process(STEP)
	_check(enemy.pulse_hinder_timer > 0.0 and world._enemy_tint(enemy) == CombatWorld.PULSE_HINDER_TINT, "Real ordinary control has a restrained distinct status color")
	world.apply_visual_settings({"shake": true, "flash": false})
	_check(world._enemy_tint(enemy) == CombatWorld.PULSE_HINDER_TINT, "Control information remains visible with flashes disabled")
	enemy.slow_timer = 1.0
	_check(world._enemy_tint(enemy) == Color("b4e9ed"), "The established frost status takes priority over pulse color")
	enemy.hurt_timer = 0.1
	world.apply_visual_settings({"shake": true, "flash": true})
	var frost: Color = Color("b4e9ed")
	var tint: Color = world._enemy_tint(enemy)
	_check(is_equal_approx(tint.r, frost.r * 1.22) and is_equal_approx(tint.g, frost.g * 1.22) and tint.a == 1.0, "The original hit peak applies unchanged to the prioritized frost base")
	enemy.hurt_timer = CombatWorld.ENEMY_HIT_TIMER_CUTOFF
	_check(world._enemy_tint(enemy) == frost, "The existing hit cutoff restores status color without an extra fade tail")
	enemy.slow_timer = 0.0
	enemy.hunter = true
	_check(world._enemy_tint(enemy) == Color.WHITE, "Immune hunters are never falsely shown with pulse status color")
	enemy.hunter = false
	var boss: CombatSim.Enemy = world.sim.spawn_enemy("boss", Vector2(1000, 300))
	boss.pulse_hinder_timer = 1.0
	_check(world._enemy_tint(boss) == Color.WHITE, "Immune bosses retain their normal status base")
	_begin(world)
	world.request_pulse()
	world._physics_process(STEP)
	var origin: Vector2 = world.pulse_feedback_snapshot()["origin"]
	world.sim.player_position += Vector2(90, 30)
	for stage: int in 4:
		var before: String = _state_hash(world)
		world.passes.clear()
		world._draw()
		_check(_state_hash(world) == before, "Repeated draw dispatch cannot mutate simulation, random streams, audio, timers or six afterimages")
		_check(world.passes.find("range") < world.passes.find("enemies") and world.passes.find("range") < world.passes.find("player") and world.passes.find("player") < world.passes.find("incoming") and world.passes.back() == "danger", "The real draw dispatcher preserves units, player, incoming loss and final enemy-danger priority above pulse")
		_check(world.range_origins[-1] == origin and world.range_radii[-1] == 144.0 and world.animation_radii[-1] < 144.0, "Static and expanding rings stay at the cast origin and inside the actual control range")
		world._advance_pulse_feedback(0.05)
	world.apply_visual_settings({"shake": true, "flash": false})
	world.passes.clear()
	world._draw()
	_check(world.passes.has("range") and not world.passes.has("animation") and world.passes.back() == "danger", "Flash-off drawing retains only the static true-range line below danger")
	world.stop()
	world.passes.clear()
	world._draw()
	_check(not world.passes.has("range") and not world.passes.has("animation"), "Inactive pulse drawing skips both primitives immediately")
	world.free()
	sound.free()
