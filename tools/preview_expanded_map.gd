extends SceneTree
## Native exploration fixture: actual map, camera, minimap and combat without profile IO.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const VIEWS: Array[String] = ["center", "northwest", "northeast", "southeast", "distant", "boss", "small", "reliquary", "mire", "glacier", "ashland", "reliquary_inlay", "mire_inlay", "glacier_inlay", "ashland_inlay"]
var _app: Node

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "center"
	var output: String = "res://reports/expanded-map/center.png"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		else:
			quit(2)
			return
	if DisplayServer.get_name() == "headless" or view not in VIEWS or not output.ends_with(".png"):
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(960, 540) if view == "small" else Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	_app.sound.set_volume(0.0)
	var arena: String = view if view in ArenaCatalog.IDS else "mire"
	if view.ends_with("_inlay"):
		arena = view.trim_suffix("_inlay")
	_app.ui.set_selected_arena(arena)
	_app._begin_run("bone", 20261028)
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var point: Vector2 = CombatSim.ARENA.get_center()
	if view == "northwest":
		point = CombatSim.ARENA.position + Vector2(16, 16)
	elif view == "northeast":
		point = Vector2(CombatSim.ARENA.end.x - 16, CombatSim.ARENA.position.y + 16)
	elif view == "southeast":
		point = CombatSim.ARENA.end - Vector2(16, 16)
	elif view in ["distant", "boss", "small"] or view in ArenaCatalog.IDS:
		point = Vector2(1880, 910)
	elif view.ends_with("_inlay"):
		point = Vector2(1540, 365)
	sim.player_position = point
	sim.player_direction = Vector2.UP
	_app.run.gold = 1000
	for id: String in ["starfall", "arc_slash"]:
		var definition: ContentDef = GameCatalog.skill(id)
		_app.run.offers.assign([{"kind": "skill", "id": id, "price": definition.price, "sold": false}])
		if not _app.run.buy_offer(0):
			push_error("Preview skill purchase failed")
			_app._quit_game(1)
			return
	for index: int in 14:
		var offset := Vector2(cos(index * 2.39996) * (180.0 + index * 19.0), sin(index * 2.39996) * (150.0 + index * 12.0))
		var enemy: CombatSim.Enemy = sim.spawn_enemy(["chaser", "rusher", "tank", "caster"][index % 4], CombatSim.clamp_point(point + offset, 24.0))
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.action_timer = 9999.0
	if view == "boss":
		sim.boss = sim.spawn_enemy("boss", CombatSim.clamp_point(point + Vector2(0, -200)))
		sim.boss.action_timer = 9999.0
	for index: int in 5:
		var drop: Vector2 = point + Vector2(-145.0 + float(index) * 35.0, 95.0 + float(index % 2) * 22.0)
		sim._drop_soul(CombatSim.clamp_point(drop, 24.0), 1 if index % 2 == 0 else 3)
	_app.world._physics_process(STEP)
	_app.ui.update_hud(_app.world.hud_snapshot())
	var focus: Control = root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(output)
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(path)
	var map: MinimapView = _app.ui._hud["minimap"]
	print("EXPANDED_MAP_PREVIEW ", JSON.stringify({"view": view, "arena_id": arena, "result": result,
		"persistent_profile": _app.store.persistent, "fixed_fixture": true, "world_bounds": str(CombatSim.ARENA),
		"player": [sim.player_position.x, sim.player_position.y], "camera_center": [_app.world._camera.position.x, _app.world._camera.position.y],
		"window_size": [root.size.x, root.size.y], "enemy_markers": map.presentation_snapshot()["enemy_count"],
		"terrain_markers": map.presentation_snapshot()["zone_count"], "grounding": _app.world._grounding_painter.get_stats(),
		"minimap_rect": str(map.get_global_rect()), "capture": output}))
	_app._quit_game(0 if result == OK else 1)
