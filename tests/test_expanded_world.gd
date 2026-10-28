extends SceneTree
## Real camera, HUD and combat retain one world coordinate system in distant regions.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
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

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	var app: Node = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args = PackedStringArray(["--autoplay"])
	app.sound.set_volume(0.0)
	for id: String in ArenaCatalog.IDS:
		app.ui.set_selected_arena(id)
		app._begin_run("bone", 20261028)
		app.world.set_physics_process(false)
		app.world.sim.sandbox = true
		app.world.sim._cooldowns.fill(9999.0)
		await _settle()
		_check(app.world.arena_texture.resource_path == ArenaCatalog.texture_path(id) and app.world.arena_texture.get_size() == ArenaCatalog.art_rect().size, "The real selected map uses its full-size continuous background: " + id)
		_check(app.world._camera.is_current() and app.world._camera.top_level and app.world._camera.zoom == Vector2.ONE, "A separate unscaled camera follows the world without scaling the actors")
		var map: MinimapView = app.ui._hud["minimap"]
		var hud_rect: Rect2 = map.get_global_rect()
		var bounds: Rect2 = CombatSim.ARENA
		var points: Array[Vector2] = [Vector2(-850, -300), Vector2(2100, -300), Vector2(-850, 1030), Vector2(2100, 1030),
			bounds.position + Vector2(16, 16), Vector2(bounds.end.x - 16, bounds.position.y + 16), bounds.end - Vector2(16, 16), Vector2(bounds.position.x + 16, bounds.end.y - 16)]
		for point: Vector2 in points:
			app.world.sim.player_position = point
			app.world._physics_process(STEP)
			var sim: CombatSim = app.world.sim
			var rng_before: int = sim.rng.state
			var run_rng_before: int = sim.run.rng.state
			var hud: Dictionary = app.world.hud_snapshot()
			app.ui.update_hud(hud)
			_check(app.world._camera.position.is_equal_approx(ArenaCatalog.camera_center(point)) and app.world.camera_view().has_point(point), "The camera reaches the distant region and retains the player: " + str(point))
			_check(hud["minimap"]["view"] == app.world.camera_view() and hud["minimap"]["player"] == point, "HUD and camera project the same distant world coordinates")
			_check(map.get_global_rect().is_equal_approx(hud_rect) and map.presentation_snapshot()["player"] == point, "Panning moves world markers while the minimap stays anchored to the HUD")
			var screen_player: Vector2 = point - app.world.camera_view().position
			var body := Rect2(screen_player - Vector2(61, 61), Vector2(122, 122))
			_check(not body.intersects(hud_rect) and not body.intersects(Rect2(24, 16, 1232, 70)) and not body.intersects(Rect2(24, 617, 1232, 96)), "The camera keeps the player and orbit clear of the minimap and top/bottom HUD even at the world corners")
			hud["minimap"]["enemies"].append({"position": Vector2.ZERO})
			hud["minimap"]["zones"].clear()
			_check(sim.rng.state == rng_before and sim.run.rng.state == run_rng_before and app.world.minimap_snapshot()["enemies"].is_empty(), "Minimap queries are detached projections and consume no gameplay randomness")
		var point: Vector2 = Vector2(-700, 900)
		app.world.sim.player_position = point
		app.world._physics_process(STEP)
		var enemy: CombatSim.Enemy = app.world.sim.spawn_enemy("tank", point + Vector2(50, 0))
		enemy.health = 500.0
		enemy.max_health = 500.0
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.action_timer = 9999.0
		var before: float = enemy.health
		app.world.sim.fire_weapon("bone", "", enemy.position - Vector2(8, 0), Vector2.RIGHT)
		app.world._physics_process(STEP)
		_check(enemy.health < before and app.world.sim.primary_hits > 0, "Real projectile collisions work outside the original arena, including negative coordinates")
		var mini: Dictionary = app.world.minimap_snapshot()
		_check(mini["enemies"].size() == 1 and mini["enemies"][0]["position"] == enemy.position and mini["zones"].size() == ArenaCatalog.definition(id)["zones"].size(), "The minimap receives live enemies and every authored terrain patch")
		app.world._shake = 4.0
		app.world._physics_process(STEP)
		_check(app.world._camera.position.is_equal_approx(ArenaCatalog.camera_center(app.world.sim.player_position)) and app.world.position.length() > 0.0, "World shake cannot drag the independent camera or HUD")
		var camera_position: Vector2 = app.world._camera.position
		paused = true
		app.world._physics_process(STEP)
		_check(app.world._camera.position == camera_position, "Real scene pause freezes the exploration camera")
		paused = false
		app.world.stop()
		_check(not app.world._camera.enabled and root.canvas_transform.is_equal_approx(Transform2D.IDENTITY), "Stopping restores the neutral canvas before another screen or run")
		app._title()
		await _settle()
	app.sound.shutdown()
	app.queue_free()
	await _settle()
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile), "Exploration and minimap integration preserve the personal profile")
	print("ExpandedWorld: %d assertions, %d failures; native=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)
