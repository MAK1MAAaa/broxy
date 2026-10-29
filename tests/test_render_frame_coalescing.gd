extends SceneTree
## Real engine catch-up ticks at 10 presentation FPS; no manually repeated physics calls.

const FIXED_HZ: int = 60
var _checks: int = 0
var _failures: int = 0

class SilentSound extends SoundBank:
	func _ready() -> void:
		pass

class CountedWorld extends CombatWorld:
	var physics_calls: int = 0
	var process_calls: int = 0
	var draw_calls: int = 0
	var fixed_delta_sum: float = 0.0
	var max_delta_error: float = 0.0
	var physics_by_process_frame: Dictionary = {}
	var draws_by_process_frame: Dictionary = {}
	var flash_on_last_draw: bool = true

	func _movement() -> Vector2:
		return Vector2.ZERO

	func _physics_process(delta: float) -> void:
		physics_calls += 1
		fixed_delta_sum += delta
		max_delta_error = maxf(max_delta_error, absf(delta - 1.0 / 60.0))
		var frame: int = Engine.get_process_frames()
		physics_by_process_frame[frame] = int(physics_by_process_frame.get(frame, 0)) + 1
		super._physics_process(delta)

	func _process(delta: float) -> void:
		process_calls += 1
		super._process(delta)

	func _draw() -> void:
		draw_calls += 1
		var frame: int = Engine.get_process_frames()
		draws_by_process_frame[frame] = int(draws_by_process_frame.get(frame, 0)) + 1
		flash_on_last_draw = bool(settings.get("flash", true))
		super._draw()

	func reset_counts() -> void:
		physics_calls = 0
		process_calls = 0
		draw_calls = 0
		fixed_delta_sum = 0.0
		max_delta_error = 0.0
		physics_by_process_frame.clear()
		draws_by_process_frame.clear()

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for index: int in count:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _run() -> void:
	var old_fps: int = Engine.max_fps
	var old_physics_hz: int = Engine.physics_ticks_per_second
	var old_paused: bool = paused
	Engine.max_fps = 10
	Engine.physics_ticks_per_second = FIXED_HZ
	paused = false
	root.size = Vector2i(1280, 720)
	var sound := SilentSound.new()
	root.add_child(sound)
	var world := CountedWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.set_physics_process(false)
	var state := RunState.new()
	state.begin(20261030, "bone", "reliquary", "alk")
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	await _frames(3)
	world.reset_counts()
	var initial_elapsed: float = world.sim.elapsed
	var started: int = Time.get_ticks_msec()
	world.set_physics_process(true)
	while Time.get_ticks_msec() - started < 800:
		await process_frame
	world.set_physics_process(false)
	await _frames(2)
	var elapsed: float = world.sim.elapsed - initial_elapsed
	var physics_calls: int = world.physics_calls
	var process_calls: int = world.process_calls
	var draw_calls: int = world.draw_calls
	var maximum_ticks: int = 0
	for count: int in world.physics_by_process_frame.values():
		maximum_ticks = maxi(maximum_ticks, count)
	_check(physics_calls > 0 and process_calls > 0 and not world.sim.complete, "The real engine advances a live sandbox through its normal physics and process callbacks")
	_check(world.max_delta_error < 0.000001 and absf(elapsed - world.fixed_delta_sum) < 0.000001 and absf(elapsed - float(physics_calls) / float(FIXED_HZ)) < 0.000001, "Every actual 60-Hz physics callback advances the complete simulation tick without losing elapsed time to presentation throttling")
	if DisplayServer.get_name() != "headless":
		_check(maximum_ticks >= 2 and physics_calls >= process_calls * 2, "The native low-FPS fixture actually executes multiple physics ticks per presentation frame")
		_check(draw_calls > 0 and draw_calls <= process_calls + 1, "Native redraw preparation is coalesced to presentation callbacks despite real engine message flushes between physics ticks")
		var maximum_draws: int = 0
		for count: int in world.draws_by_process_frame.values():
			maximum_draws = maxi(maximum_draws, count)
		_check(maximum_draws <= 1, "A single Engine process frame never prepares the combat canvas repeatedly")
	var frozen_elapsed: float = world.sim.elapsed
	var frozen_visual_time: float = world._visual_time
	var frozen_physics_calls: int = world.physics_calls
	var frozen_process_calls: int = world.process_calls
	var draws_before_pause: int = world.draw_calls
	world.set_physics_process(true)
	paused = true
	world.apply_visual_settings({"shake": false, "flash": false})
	await _frames(3)
	_check(world.sim.elapsed == frozen_elapsed and world._visual_time == frozen_visual_time and world.physics_calls == frozen_physics_calls and world.process_calls == frozen_process_calls, "A real SceneTree pause freezes simulation and process timers while a visual setting is changed")
	if DisplayServer.get_name() != "headless":
		_check(world.draw_calls > draws_before_pause and not world.flash_on_last_draw, "Flash-off while paused immediately reaches an actual native redraw without requiring a gameplay or process tick")
	paused = false
	await _frames(2)
	_check(world.sim.elapsed > frozen_elapsed and world.physics_calls > frozen_physics_calls, "Resuming continues the same simulation through normal fixed engine ticks")
	world.set_physics_process(false)
	world.stop()
	world.queue_free()
	sound.queue_free()
	await process_frame
	Engine.max_fps = old_fps
	Engine.physics_ticks_per_second = old_physics_hz
	paused = old_paused
	_check(Engine.max_fps == old_fps and Engine.physics_ticks_per_second == old_physics_hz, "The regression restores the host's presentation limit and physics frequency")
	print("RenderFrameCoalescing: %d assertions, %d failures; native=%s physics=%d process=%d draws=%d max_ticks_per_process=%d elapsed=%s" % [_checks, _failures, DisplayServer.get_name() != "headless", physics_calls, process_calls, draw_calls, maximum_ticks, elapsed])
	quit(0 if _failures == 0 else 1)
