extends SceneTree
## Queued input, pooled feedback and scene-tree pause use the shipped CombatWorld.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0
var _native_draw_checks: bool = false

class ProbeSoundBank extends SoundBank:
	var played: Array[String] = []
	func _ready() -> void:
		pass
	func play(name: String, _loudness: float = -10.0) -> void:
		played.append(name)
	func play_cue(name: String, _loudness: float, _cue_id: String) -> void:
		played.append(name)

class ProbeWorld extends CombatWorld:
	var movement: Vector2 = Vector2.RIGHT
	var draw_passes: Array[String] = []
	func _movement() -> Vector2:
		return movement
	func _maintain_stress() -> void:
		pass
	func _draw() -> void:
		draw_passes.clear()
		super._draw()
	func _draw_dash_afterimages() -> void:
		draw_passes.append("afterimages")
		super._draw_dash_afterimages()
	func _player_tint() -> Color:
		draw_passes.append("player")
		return super._player_tint()
	func _draw_feedback() -> void:
		draw_passes.append("incoming")
		super._draw_feedback()
	func _draw_danger() -> void:
		draw_passes.append("danger")
		super._draw_danger()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_request_consumption()
	await _test_input_gates_and_transitions()
	await _test_feedback_pool_and_settings()
	await _test_real_pause()
	await _test_render_order()
	print("DashWorld: %d assertions, %d failures; native draw checks=%s" % [_checks, _failures, _native_draw_checks])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(starter: String = "bone") -> RunState:
	var state := RunState.new()
	state.begin(20261028, starter)
	return state

func _world() -> ProbeWorld:
	var sound := ProbeSoundBank.new()
	root.add_child(sound)
	var world := ProbeWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.set_physics_process(false)
	world.begin(_state())
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	return world

func _dispose(world: ProbeWorld) -> void:
	world.queue_free()
	world.sound.queue_free()
	for frame: int in 3:
		await process_frame

func _trail_lives(world: CombatWorld) -> Array[float]:
	var lives: Array[float] = []
	for afterimage: CombatWorld.DashAfterimage in world._dash_afterimages:
		lives.append(afterimage.life)
	return lives

func _test_request_consumption() -> void:
	var world: ProbeWorld = _world()
	var hud: Array[Dictionary] = []
	world.hud_changed.connect(func(snapshot: Dictionary) -> void: hud.append(snapshot.duplicate(true)))
	var origin: Vector2 = world.sim.player_position
	_check(world.request_dash() and world.sim.dashes_used == 0, "A valid key press queues one action without advancing simulation outside the fixed step")
	_check(not world.request_dash(), "A second request in the same physical tick cannot queue another charge")
	world._physics_process(STEP)
	_check(world.sim.dashes_used == 1 and not world._dash_pending and world.sim.player_position.x > origin.x + 5.0, "The next physics step consumes exactly one queued dash and applies its real movement")
	_check(hud.size() == 1 and bool(hud[0]["dash"]["active"]), "Dash start immediately reports its active state before the ordinary 100ms HUD interval")
	var sound: ProbeSoundBank = world.sound as ProbeSoundBank
	_check(sound.played.count("dash") == 1 and world._shake == 0.0, "Accepted dash has one restrained dedicated sound without introducing camera shake")
	world.movement = Vector2.ZERO
	for frame: int in 24:
		_check(not world.request_dash(), "Requests during burst or cooldown are rejected instead of being cached")
		world._physics_process(STEP)
	for frame: int in 180:
		world._physics_process(STEP)
	_check(world.sim.dashes_used == 1 and world.sim.dash_cooldown_left == 0.0, "Cooldown expiry cannot replay previously rejected input")
	_check(world.request_dash(), "A new deliberate request succeeds once the real cooldown expires")
	world.clear_pending_actions()
	world._physics_process(STEP)
	_check(world.sim.dashes_used == 1, "Explicit action cancellation leaves no latent charge for a later update")
	await _dispose(world)

func _test_input_gates_and_transitions() -> void:
	var empty := CombatWorld.new()
	empty.active = true
	_check(not empty.request_dash(), "Missing simulation cannot accept a skill request")
	empty.free()
	var world: ProbeWorld = _world()
	_check(world.request_dash(), "Pause fixture begins with a valid pending action")
	paused = true
	var elapsed: float = world.sim.elapsed
	_check(not world.request_dash(), "Paused scene trees reject new skill input")
	world._physics_process(STEP)
	_check(world.sim.elapsed == elapsed and not world._dash_pending, "Even an explicit paused update cannot advance or retain queued movement")
	paused = false
	world._physics_process(STEP)
	_check(world.sim.dashes_used == 0, "Resuming cannot consume the canceled pre-pause action")
	world.autopilot = true
	_check(not world.request_dash(), "Autopilot diagnostics reject human dash input")
	world.autopilot = false
	_check(world.request_dash(), "The normal active world still accepts the next request")
	world.autopilot = true
	world._physics_process(STEP)
	_check(world.sim.dashes_used == 0 and not world._dash_pending, "Enabling autopilot between input and physics cancels the queued skill")
	world.autopilot = false
	world.stress_mode = true
	_check(not world.request_dash(), "Pressure diagnostics reject skill input")
	world.stress_mode = false
	_check(world.request_dash(), "Stress transition fixture queues a normal action first")
	world.stress_mode = true
	world._physics_process(STEP)
	_check(world.sim.dashes_used == 0 and not world._dash_pending, "Enabling pressure diagnostics before physics cancels the queued skill")
	world.stress_mode = false
	world.stop()
	_check(not world.request_dash() and not world._dash_pending, "Stopping combat rejects input and clears queued actions")
	world.begin(_state())
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	_check(world.sim.dashes_used == 0 and world.dash_afterimage_count() == 0, "A new battle starts without pending dash or old afterimages")
	_check(world.request_dash(), "New-wave replacement fixture queues a valid action")
	world.begin(_state("ember"))
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	world._physics_process(STEP)
	_check(world.sim.dashes_used == 0 and not world._dash_pending, "Replacing the simulation clears a queued action rather than spending it in the new wave")
	world.sim.run.health = 0.0
	_check(not world.request_dash(), "Dead players cannot queue a skill before deferred settlement")
	world.sim.run.health = 100.0
	_check(world.request_dash(), "Terminal fixture starts a real dash")
	world._physics_process(STEP)
	_check(world.dash_afterimage_count() > 0, "A real dash creates bounded feedback before settlement")
	world.sim._finish(false, "dash world terminal fixture")
	_check(not world.active and not world.request_dash() and not world._dash_pending and world.dash_afterimage_count() == 0, "Terminal settlement rejects input and clears feedback that would otherwise remain frozen forever")
	await _dispose(world)

func _test_feedback_pool_and_settings() -> void:
	var world: ProbeWorld = _world()
	var ids: Array = world._dash_afterimages.map(func(image: CombatWorld.DashAfterimage) -> int: return image.get_instance_id())
	_check(ids.size() == 6 and world.request_dash(), "Afterimage capacity is allocated as six reusable slots")
	world._physics_process(STEP)
	for frame: int in 6:
		world._physics_process(STEP)
		_check(world.dash_afterimage_count() <= 6, "Normal burst feedback stays within its fixed pool")
	for index: int in 40:
		world._add_dash_afterimage(world.sim.player_position, Vector2.RIGHT)
	_check(world.dash_afterimage_count() == 6 and ids == world._dash_afterimages.map(func(image: CombatWorld.DashAfterimage) -> int: return image.get_instance_id()), "Even repeated feedback events reuse the same six objects")
	world.sim.invulnerability = 1.0
	world._visual_time = 3.0 * PI / 70.0
	_check(world.sim.dash_time_left > 0.0 and world._player_tint().a == 1.0, "The dashing player remains opaque at the original hurt-blink minimum")
	world.apply_visual_settings({"shake": false, "flash": false})
	_check(world.dash_afterimage_count() == 0 and world._player_tint() == Color.WHITE, "Disabling flashes clears afterimages immediately and keeps the player fully visible")
	var position_before: Vector2 = world.sim.player_position
	world._physics_process(STEP)
	_check(world.sim.player_position.x > position_before.x and world.dash_afterimage_count() == 0 and world.sim.dashes_used == 1, "The actual skill continues while its optional visual feedback is disabled")
	world.apply_visual_settings({"shake": true, "flash": true})
	_check(world.dash_afterimage_count() == 0, "Re-enabling flashes does not replay old afterimages")
	world.stop()
	_check(world.dash_afterimage_count() == 0 and world._dash_afterimages.size() == 6, "Stop clears life values while retaining the fixed feedback allocation")
	await _dispose(world)

func _test_real_pause() -> void:
	var world: ProbeWorld = _world()
	_check(world.request_dash(), "Pause timing fixture accepts its one charge")
	world._physics_process(STEP)
	var before: Array = [world.sim.elapsed, world.sim.dash_time_left, world.sim.dash_cooldown_left, world._visual_time, _trail_lives(world)]
	paused = true
	world.set_physics_process(true)
	for frame: int in 4:
		await process_frame
	_check(before == [world.sim.elapsed, world.sim.dash_time_left, world.sim.dash_cooldown_left, world._visual_time, _trail_lives(world)], "A real SceneTree pause freezes burst, cooldown, visuals and all six feedback lifetimes")
	paused = false
	await physics_frame
	await physics_frame
	world.set_physics_process(false)
	_check(world.sim.elapsed > float(before[0]) and world.sim.dash_cooldown_left < float(before[2]), "Resume advances the same simulation and cooldown instead of replacing the skill")
	await _dispose(world)

func _test_render_order() -> void:
	var world: ProbeWorld = _world()
	world.request_dash()
	world._physics_process(STEP)
	var state_before: String = JSON.stringify([world.sim.snapshot(), str(world.sim.rng.state), str(world.sim.run.rng.state), _trail_lives(world)])
	for frame: int in 4:
		world.queue_redraw()
		await process_frame
	if DisplayServer.get_name() != "headless":
		_native_draw_checks = true
		var passes: Array[String] = world.draw_passes
		_check(passes.has("afterimages") and passes.find("afterimages") < passes.find("player") and passes.find("player") < passes.find("incoming") and passes.back() == "danger", "Native drawing keeps afterimages behind the current player and all friendly feedback below enemy danger")
	_check(JSON.stringify([world.sim.snapshot(), str(world.sim.rng.state), str(world.sim.run.rng.state), _trail_lives(world)]) == state_before, "Repeated rendering changes neither skill state, feedback lifetimes nor either random stream")
	await _dispose(world)
