extends SceneTree
## Selected character, actual companion purchases and real hero cast; no profile I/O.

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "battle"
	var hero_id: String = "alk"
	var destination: String = "res://reports/world-flipper-party/preview-alk.png"
	var small: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--hero="):
			hero_id = argument.trim_prefix("--hero=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--small":
			small = true
		else:
			quit(2)
			return
	if view not in ["title", "shop", "battle"] or hero_id not in HeroCatalog.IDS or DisplayServer.get_name() == "headless" or not destination.ends_with(".png"):
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(960, 540) if small else Vector2i(1280, 720)
	var app: Node = load("res://scenes/main.tscn").instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args.append("--autoplay")
	app.ui.set_selected_hero(hero_id)
	if view == "title":
		app.ui.show_title({})
		(app.ui.find_child("MenuArtwork", true, false) as TitleCover).set_frame(0)
	else:
		app._start_run(HeroCatalog.definition(hero_id).starter_weapon)
		app.world.set_physics_process(false)
		app.sound.set_volume(0.0)
		app.run.gold = 1000
		for skill_id: String in ["pulse", "starfall", "arc_slash"]:
			if HeroCatalog.rear_for_skill(skill_id).id == hero_id or app.run.active_skills.size() >= 2:
				continue
			app.run.offers.assign([{"kind": "skill", "id": skill_id, "price": 24, "sold": false}])
			assert(app.run.buy_offer(0))
		if view == "shop":
			app.world.stop()
			app.run.offers.clear()
			for item: Dictionary in [{"kind": "skill", "id": "arc_slash"}, {"kind": "weapon", "id": "scatter"}, {"kind": "relic", "id": "moon_charm"}, {"kind": "rune", "id": "blast"}]:
				app.run.offers.append({"kind": item.kind, "id": item.id, "price": 24, "sold": false})
			app.ui.show_shop()
		else:
			var sim: CombatSim = app.world.sim
			sim.sandbox = true
			sim._cooldowns.fill(9999.0)
			sim.player_position = Vector2(640, 360)
			sim.player_direction = Vector2.RIGHT
			sim.player_velocity = Vector2(150, 0)
			for index: int in 5:
				var target: CombatSim.Enemy = sim.spawn_enemy("tank" if index == 2 else "chaser", sim.player_position + Vector2(80 + index * 34, (index % 3 - 1) * 45))
				target.health = 1000.0
				target.max_health = 1000.0
			assert(sim.try_hero_skill())
			app.world._active_skill_painter.advance(0.07)
			app.world._visual_time = 0.12
			app.world._update_camera()
			app.ui.update_hud(app.world.hud_snapshot())
			app.world.queue_redraw()
	root.warp_mouse(Vector2(20, 20))
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(20, 20)
	pointer.global_position = pointer.position
	root.push_input(pointer, false)
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination).get_base_dir())
	if error == OK:
		error = root.get_texture().get_image().save_png(destination)
	print("HERO_PARTY_PREVIEW hero=%s view=%s size=%s profile_io=false result=%d" % [hero_id, view, root.size, error])
	app._quit_game(0 if error == OK else 1)
