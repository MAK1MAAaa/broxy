extends SceneTree
## Actual hostile projectiles confirm evasion without using damage-number storage.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

class ProbeSoundBank extends SoundBank:
	var names: Array[String] = []
	var levels: Array[float] = []
	var cue_ids: Array[String] = []
	func _ready() -> void:
		pass
	func play(name: String, loudness: float = -10.0) -> void:
		names.append(name)
		levels.append(loudness)
		cue_ids.append("")
	func play_cue(name: String, loudness: float, cue_id: String) -> void:
		names.append(name)
		levels.append(loudness)
		cue_ids.append(cue_id)

class ProbeWorld extends CombatWorld:
	var movement: Vector2 = Vector2.RIGHT
	func _movement() -> Vector2:
		return movement

class DrawSpy extends ProbeWorld:
	var passes: Array[String] = []
	var text_anchors: Array[Vector2] = []
	var pulse_centers: Array[Vector2] = []
	func _draw_atmosphere() -> void:
		pass
	func _draw_obstacles() -> void:
		passes.append("obstacles")
	func _draw_ground_contacts() -> void:
		pass
	func _draw_souls() -> void:
		pass
	func _draw_enemies() -> void:
		pass
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
		passes.append("outgoing")
	func _draw_player() -> void:
		passes.append("player")
	func _draw_dash_evasion_feedback() -> void:
		passes.append("evasion")
		super._draw_dash_evasion_feedback()
	func _draw_dash_evasion_text(anchor: Vector2) -> void:
		passes.append("text")
		text_anchors.append(anchor)
	func _draw_dash_evasion_pulse(center: Vector2) -> void:
		passes.append("pulse")
		pulse_centers.append(center)
	func _draw_feedback() -> void:
		passes.append("incoming")
	func _draw_danger() -> void:
		passes.append("danger")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_real_projectile_and_single_slot()
	await _test_tail_damage_priority()
	await _test_flash_and_real_pause()
	await _test_lifecycle()
	_test_draw_order_and_boundaries()
	print("DashEvasionWorld: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _begin(world: CombatWorld) -> void:
	var state := RunState.new()
	state.begin(20261028, "bone", "mire")
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

func _projectile_at_next_dash_step(world: ProbeWorld) -> void:
	world.sim._hostile_shot(world.sim.player_position + Vector2(11, 0), Vector2.ZERO, 8.0, "caster")
	world._physics_process(STEP)

func _trigger(world: ProbeWorld) -> void:
	_check(world.request_dash(), "The fixture queues a real ready dash")
	world._physics_process(STEP)
	_projectile_at_next_dash_step(world)

func _feedback_state(world: CombatWorld) -> String:
	var afterimages: Array = []
	for image: CombatWorld.DashAfterimage in world._dash_afterimages:
		afterimages.append([image.position, image.lean, image.life])
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	return JSON.stringify([world.sim.snapshot(), world.sim.run.summary(), str(world.sim.rng.state), str(world.sim.run.rng.state),
		world.dash_evasion_feedback_snapshot(), world._dash_evasion_dash, world._visual_time, world._shake,
		world._numbers.size(), world._number_free.size(), afterimages, sound.names, sound.levels, sound.cue_ids])

func _test_real_projectile_and_single_slot() -> void:
	var world: ProbeWorld = _world()
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	_check(world.dash_evasion_feedback_snapshot() == {"active": false, "remaining": 0.0, "pulse_remaining": 0.0, "text": ""}, "Idle feedback has one empty, queryable slot")
	var hud: Array[Dictionary] = []
	world.hud_changed.connect(func(value: Dictionary) -> void: hud.append(value.duplicate(true)))
	_check(world.request_dash(), "Real attack fixture accepts its one charge")
	world._physics_process(STEP)
	_check(not world.dash_evasion_feedback_snapshot()["active"] and sound.names == ["dash"], "Starting a dash alone plays only its activation sound and never claims an evasion")
	_check(sound.cue_ids == ["dash"], "Activation uses its own cue without consuming the independent evasion key")
	var ids: Array = world._dash_afterimages.map(func(image: CombatWorld.DashAfterimage) -> int: return image.get_instance_id())
	_projectile_at_next_dash_step(world)
	var feedback: Dictionary = world.dash_evasion_feedback_snapshot()
	_check(world.sim.shot_count == 0 and world.sim.run.health == 100.0 and world.sim.dash_snapshot()["evaded"] and world.sim.dash_snapshot()["evades"] == 1, "An actual overlapping hostile projectile is consumed by dash protection and confirms one evasion")
	_check(feedback["active"] and feedback["text"] == "闪避" and is_equal_approx(feedback["remaining"], 0.32) and is_equal_approx(feedback["pulse_remaining"], 0.32), "Real evasion fills the one 320ms text-and-pulse slot")
	_check(sound.names == ["dash", "evade"] and sound.names.count("hurt") == 0 and sound.levels[-1] == -22.0 and world._shake == 0.0, "Confirmation adds exactly one quiet evasion sound independently of activation and no hurt sound or shake")
	_check(sound.cue_ids[-1] == "dash_evasion" and sound.cue_ids.count("dash_evasion") == 1, "Successful confirmation uses the independent dash_evasion cue through the SoundBank API")
	_check(hud.size() == 2 and hud[-1]["dash"]["evaded"], "The real confirmation immediately publishes the resulting simulation snapshot")
	_check(world._numbers.is_empty() and world._number_free.size() == CombatWorld.NUMBER_LIMIT and world._feedback_serial == 0, "Evasion never occupies or increments pooled damage-number accounting")
	_check(world.sim.invulnerability == 0.0 and world.sim.run.gold == 0 and world.sim.run.kills == 0 and world.sim.run.damage_dealt_by_weapon.is_empty(), "Presentation grants no hit immunity, currency, kills or offensive damage")
	_check(ids == world._dash_afterimages.map(func(image: CombatWorld.DashAfterimage) -> int: return image.get_instance_id()) and ids.size() == 6, "The six original afterimage objects are retained unchanged")
	var before: String = _feedback_state(world)
	for repeat: int in 12:
		world.sim.dash_evaded.emit(world.sim.player_position, world.sim.player_position + Vector2(5, 0), "caster", "projectile")
	_check(_feedback_state(world) == before, "Duplicate events in the same dash cannot extend, stack or replay the confirmation")
	_projectile_at_next_dash_step(world)
	_check(world.sim.dash_snapshot()["evades"] == 1 and sound.names == ["dash", "evade"] and float(world.dash_evasion_feedback_snapshot()["remaining"]) < 0.32, "A second real attack in one dash leaves only the original fading confirmation")
	feedback["remaining"] = 999.0
	_check(float(world.dash_evasion_feedback_snapshot()["remaining"]) < 0.32, "Feedback snapshots are independent query values")
	await _dispose(world)

func _test_tail_damage_priority() -> void:
	var world: ProbeWorld = _world()
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	var confirmations: Array[String] = []
	world.sim.dash_evaded.connect(func(_point: Vector2, _origin: Vector2, _source_id: String, kind: String) -> void: confirmations.append(kind))
	_trigger(world)
	for frame: int in 12:
		if world.sim.dash_invulnerability_left <= 0.0:
			break
		world._physics_process(STEP)
	_check(world.sim.dash_time_left > STEP and world.sim.dash_invulnerability_left == 0.0 and world.dash_evasion_feedback_snapshot()["active"], "The real dash reaches its vulnerable tail while its earlier successful confirmation is still visible")
	var cooldown_before: float = world.sim.dash_cooldown_left
	var burst_before: float = world.sim.dash_time_left
	var latch: int = world._dash_evasion_dash
	_projectile_at_next_dash_step(world)
	_check(world.sim.run.health == 92.0 and world.sim.run.last_hit["kind"] == "projectile" and world.sim.dash_time_left > 0.0, "A second real hostile projectile deals eight damage during the vulnerable movement tail")
	_check(world.dash_evasion_feedback_snapshot() == {"active": false, "remaining": 0.0, "pulse_remaining": 0.0, "text": ""}, "Actual damage immediately clears both confirmation visuals so the new loss has priority")
	_check(world._numbers.size() == 1 and world._numbers[0].player_hit and world._numbers[0].amount == 8.0 and world._damage_flash > 0.0, "The latest actual damage retains its normal incoming floating number and directional feedback")
	_check(world._dash_evasion_dash == latch and world.sim.dash_snapshot()["evaded"] and world.sim.dash_snapshot()["evades"] == 1 and confirmations == ["projectile"], "Damage preserves the original per-dash latch and the single real evasion success")
	_check(is_equal_approx(world.sim.dash_cooldown_left, cooldown_before - STEP) and is_equal_approx(world.sim.dash_time_left, burst_before - STEP) and is_equal_approx(world.sim.invulnerability, 0.7), "Clearing confirmation changes neither the dash clocks nor normal received-hit protection")
	_check(sound.names == ["dash", "evade", "hurt"], "The tail hit plays its ordinary hurt sound without repeating either dash or evasion audio")
	var after_hit: String = _feedback_state(world)
	for repeat: int in 3:
		world.sim.dash_evaded.emit(world.sim.player_position, world.sim.player_position, "caster", "projectile")
	_check(_feedback_state(world) == after_hit and world._numbers.size() == 1, "Repeated same-dash events after a hit cannot resurrect confirmation, replay audio or disturb the incoming loss")
	await _dispose(world)

func _test_flash_and_real_pause() -> void:
	var world: ProbeWorld = _world()
	_trigger(world)
	world.movement = Vector2.ZERO
	var remaining: float = world.dash_evasion_feedback_snapshot()["remaining"]
	paused = true
	world.set_physics_process(true)
	world.apply_visual_settings({"shake": true, "flash": false})
	_check(world.dash_evasion_feedback_snapshot() == {"active": true, "remaining": remaining, "pulse_remaining": 0.0, "text": "闪避"}, "Turning flashes off during pause immediately cancels only the pulse and retains readable static text")
	var frozen: String = _feedback_state(world)
	for frame: int in 4:
		await process_frame
	_check(_feedback_state(world) == frozen, "Real SceneTree pause freezes text, skill clocks, sound counts and all original afterimage lifetimes")
	world.apply_visual_settings({"shake": true, "flash": true})
	_check(world.dash_evasion_feedback_snapshot()["remaining"] == remaining and world.dash_evasion_feedback_snapshot()["pulse_remaining"] == 0.0, "Re-enabling flashes while paused does not replay the canceled pulse")
	paused = false
	await physics_frame
	await physics_frame
	world.set_physics_process(false)
	_check(float(world.dash_evasion_feedback_snapshot()["remaining"]) < remaining and world.dash_evasion_feedback_snapshot()["active"] and world.dash_evasion_feedback_snapshot()["pulse_remaining"] == 0.0, "Resume advances existing text without recreating its optional pulse")
	for frame: int in 30:
		world._physics_process(STEP)
	_check(not world.dash_evasion_feedback_snapshot()["active"] and world.dash_evasion_feedback_snapshot()["text"] == "", "The static confirmation expires normally after resumed simulation time")
	world.apply_visual_settings({"shake": true, "flash": false})
	_begin(world)
	_trigger(world)
	_check(world.dash_evasion_feedback_snapshot()["active"] and world.dash_evasion_feedback_snapshot()["text"] == "闪避" and world.dash_evasion_feedback_snapshot()["pulse_remaining"] == 0.0, "A new real evasion with flashes already off still has accessible text")
	await _dispose(world)

func _test_lifecycle() -> void:
	var world: ProbeWorld = _world()
	_trigger(world)
	# Keep only the cosmetic slot alive long enough to test a later real dash boundary.
	world._dash_evasion_remaining = 3.0
	world.movement = Vector2.ZERO
	for frame: int in 150:
		world._physics_process(STEP)
	_check(world.dash_evasion_feedback_snapshot()["active"] and world.request_dash(), "A deliberately extended cosmetic fixture survives until the next actual ready input")
	world._physics_process(STEP)
	_check(not world.dash_evasion_feedback_snapshot()["active"] and world.sim.dashes_used == 2, "The next real dash clears its predecessor's confirmation before receiving any attack")
	_projectile_at_next_dash_step(world)
	_check(world.dash_evasion_feedback_snapshot()["active"], "The second real dash can independently confirm its first avoided attack")
	world.stop()
	_check(not world.dash_evasion_feedback_snapshot()["active"] and world.dash_evasion_feedback_snapshot()["pulse_remaining"] == 0.0, "Stopping clears the full single slot")
	world.movement = Vector2.RIGHT
	_begin(world)
	_trigger(world)
	_begin(world)
	_check(not world.dash_evasion_feedback_snapshot()["active"] and world.sim.dashes_used == 0, "Beginning a new simulation clears confirmation and its deduplication state")
	_trigger(world)
	world.sim._finish(false, "evasion feedback terminal fixture")
	_check(not world.active and not world.dash_evasion_feedback_snapshot()["active"] and world.dash_evasion_feedback_snapshot()["pulse_remaining"] == 0.0, "Terminal settlement clears feedback that would otherwise remain frozen")
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	var count: int = sound.names.size()
	world.sim.dash_evaded.emit(world.sim.player_position, Vector2.ZERO, "boss", "ritual")
	_check(sound.names.size() == count and not world.dash_evasion_feedback_snapshot()["active"], "Late events from completed combat cannot resurrect confirmation or sound")
	await _dispose(world)

func _test_draw_order_and_boundaries() -> void:
	var sound := ProbeSoundBank.new()
	var world := DrawSpy.new()
	world.sound = sound
	_begin(world)
	_trigger(world)
	var bounds: Rect2 = CombatSim.ARENA.grow(-16.0)
	var center: Vector2 = bounds.get_center()
	var points: Array[Vector2] = [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y), center - Vector2(900, 0), center + Vector2(900, 0), center - Vector2(0, 500), center + Vector2(0, 500)]
	for point: Vector2 in points:
		world.sim.player_position = point
		world.passes.clear()
		world.text_anchors.clear()
		world.pulse_centers.clear()
		var before: String = _feedback_state(world)
		for repeat: int in 3:
			world._draw()
		_check(_feedback_state(world) == before, "Rendering changes neither feedback, combat, random streams nor sound at: " + str(point))
		_check(world.passes.find("player") < world.passes.find("evasion") and world.passes.find("text") < world.passes.find("incoming") and world.passes.back() == "danger", "The executed draw dispatcher keeps confirmation above the player and below incoming damage and hostile danger")
		_check(world.text_anchors.size() == 3 and world.pulse_centers.size() == 3 and world.pulse_centers[-1] == point + Vector2(0, 6), "Text and its small foot arc follow the current player rather than the old evasion location")
		var anchor: Vector2 = world.text_anchors[-1]
		var half_width: float = world._dash_evasion_text_width * 0.5
		var view: Rect2 = world.camera_view()
		var safe: Rect2 = world._feedback_safe_rect()
		var text_rect := Rect2(anchor - Vector2(half_width, 16), Vector2(half_width * 2.0, 16))
		_check(view.grow(0.01).encloses(safe) and safe.grow(0.01).encloses(text_rect), "The confirmation stays inside the current camera's HUD-safe world rectangle")
		var below_player: bool = point.y - 78.0 < safe.position.y
		var clear_of_player: bool = anchor.y - point.y >= 58.0 if below_player else point.y - anchor.y >= 58.0
		_check(clear_of_player, "A player near the camera's top HUD receives a label below the orbit; other labels clear the head and weapons")
	world.apply_visual_settings({"shake": true, "flash": false})
	world.passes.clear()
	world._draw()
	_check(world.passes.has("text") and not world.passes.has("pulse") and world.passes.back() == "danger", "The real draw dispatcher retains static text when optional flashes are off")
	world.stop()
	world.passes.clear()
	world._draw()
	_check(not world.passes.has("text") and not world.passes.has("pulse"), "The idle drawing path immediately skips all single-slot primitives")
	world.free()
	sound.free()
