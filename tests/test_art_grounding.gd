extends SceneTree
## Real scene redraws keep cosmetic grounding out of combat state and cleanup paths.

class SilentSound extends SoundBank:
	func _ready() -> void:
		pass

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _signature(world: CombatWorld) -> String:
	var entities: Array = []
	for enemy: CombatSim.Enemy in world.sim.enemies:
		if enemy.active:
			entities.append([enemy.uid, enemy.position, enemy.radius, enemy.health, enemy.age, enemy.hurt_timer, enemy.mode, enemy.action_timer])
	for soul: CombatSim.Soul in world.sim.souls:
		if soul.active:
			entities.append([soul.slot, soul.position, soul.value, soul.age])
	return JSON.stringify([world.sim.snapshot(), world.sim.run.summary(), world.sim.rng.state, world.sim.run.rng.state, entities])

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var sound := SilentSound.new()
	root.add_child(sound)
	for id: String in ArenaCatalog.IDS:
		var state := RunState.new()
		state.begin(20261029, "bone", id)
		var world := CombatWorld.new()
		world.sound = sound
		root.add_child(world)
		world.begin(state)
		world.set_physics_process(false)
		world.sim.sandbox = true
		world.sim._cooldowns.fill(9999.0)
		var original_stage: bool = ArenaCatalog.ORIGINAL_STAGE_IDS.has(id)
		world.sim.player_position = world.sim.obstacles.free_point(ArenaCatalog.play_bounds(id).get_center(), 16, 16) if original_stage else Vector2(-500, 900)
		world._update_camera()
		for index: int in 5:
			var enemy: CombatSim.Enemy = world.sim.spawn_enemy(["chaser", "rusher", "tank", "caster", "boss"][index], world.sim.player_position + Vector2(-220 + index * 90, -90))
			enemy.action_timer = 9999.0
		for index: int in 2:
			var point: Vector2 = world.sim.player_position + Vector2(100 + index * 25, 65)
			if original_stage:
				point = world.sim.obstacles.free_point(point)
			world.sim._drop_soul(point, 1 if index == 0 else 3)
		if original_stage:
			var visible: Rect2 = world.camera_view()
			var legal: bool = world.sim.obstacles.is_free(world.sim.player_position, 16, 16)
			for enemy: CombatSim.Enemy in world.sim.enemies:
				if enemy.active:
					legal = legal and world.sim.obstacles.is_free(enemy.position, enemy.radius) and visible.has_point(enemy.position)
			for soul: CombatSim.Soul in world.sim.souls:
				if soul.active:
					legal = legal and world.sim.obstacles.is_free(soul.position) and visible.has_point(soul.position)
			_check(legal, "Every source-stage grounding fixture uses actual legal, visible actor and soul positions: " + id)
		var before: String = _signature(world)
		for repeat: int in 3:
			world._grounding_painter.rebuild(world.sim, world.camera_view())
			world.queue_redraw()
			await _settle()
		var stats: Dictionary = world._grounding_painter.get_stats()
		_check(stats["player_count"] == 1 and stats["enemy_count"] == 5 and stats["pickup_count"] == 2 and stats["active_count"] == 8, "The real world projects each visible actor and pickup into one grounding batch: " + id)
		_check(stats["draw_commands"] <= 3 and _signature(world) == before, "Repeated real redraws preserve positions, health, inventory, timers and RNG: " + id)
		world.apply_visual_settings({"flash": false, "shake": false})
		world._grounding_painter.rebuild(world.sim, world.camera_view())
		_check(world._grounding_painter.get_stats()["active_count"] == 8 and _signature(world) == before, "Steady grounding survives flash-off without adding a gameplay effect")
		paused = true
		var frozen: Dictionary = world._grounding_painter.get_stats().duplicate(true)
		world._physics_process(1.0 / 60.0)
		await _settle()
		_check(world._grounding_painter.get_stats() == frozen and _signature(world) == before, "A real pause leaves grounding and combat frozen")
		paused = false
		world.stop()
		await _settle()
		_check(world._grounding_painter.get_stats()["active_count"] == 0, "Stopping combat clears the grounding batch across queued redraws")
		world.queue_free()
		await _settle()
	sound.queue_free()
	await _settle()
	print("ArtGrounding: %d assertions, %d failures; native=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)
