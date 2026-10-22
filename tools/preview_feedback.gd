extends SceneTree
## Native rendering fixtures for feedback and result layouts, never player progression.

const STEP: float = 1.0 / 60.0
const MAIN_SCRIPT = preload("res://scripts/main.gd")

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	root.size = Vector2i(1280, 720)
	var view: String = "combat"
	var destination: String = ""
	var hold: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			hold = true
	if destination.is_empty():
		destination = "res://reports/feedback-%s.png" % view
	var app = load("res://scenes/main.tscn").instantiate()
	app.store.persistent = false
	root.add_child(app)
	await process_frame
	app.args.append("--autoplay")
	app._start_run("bone")
	app.world.set_physics_process(false)
	var run: RunState = app.run
	run.begin(2027, "bone")
	if view == "shop":
		app.world.stop()
		run.wave = 2
		run.gold = 100
		run.offers = [
			{"id": "frost", "kind": "weapon", "price": 27, "sold": false},
			{"id": "pierce", "kind": "rune", "price": 20, "sold": false},
			{"id": "damage", "kind": "relic", "price": 25, "sold": false},
			{"id": "blast", "kind": "rune", "price": 20, "sold": false},
		]
		app.screen = MAIN_SCRIPT.Screen.SHOP
		app.ui.show_shop()
		app.ui._buy(1)
	else:
		run.wave = 5
		run.elapsed = 185.0
		run.loadout = [
			{"id": "bone", "paid": 18, "rune": {"id": "pierce", "uid": 1}},
			{"id": "frost", "paid": 24, "rune": {"id": "bounce", "uid": 2}},
			{"id": "ember", "paid": 24, "rune": {"id": "blast", "uid": 3}},
			{"id": "scatter", "paid": 26, "rune": {}},
		]
		app.world.begin(run)
		app.world.set_physics_process(false)
		var sim: CombatSim = app.world.sim
		sim.sandbox = true
		sim._cooldowns.fill(1000.0)
		sim.player_position = Vector2(430, 380)
		app.world._visual_time = 7.5
		if view == "result":
			for index: int in 4:
				var definition: ContentDef = GameCatalog.weapons()[index]
				for count: int in 3 + index:
					var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", Vector2(900, 300))
					while enemy.active:
						sim.apply_damage(enemy, definition.damage, definition.id)
			for index: int in 13:
				sim.invulnerability = 0.0
				sim._hurt_player(8.0, "caster", "projectile", Vector2(900, 300))
		else:
			sim.elapsed = 19.0
			var left: CombatSim.Enemy = sim.spawn_enemy("tank", Vector2(580, 310))
			var right: CombatSim.Enemy = sim.spawn_enemy("chaser", Vector2(740, 355))
			sim.spawn_enemy("rusher", Vector2(320, 480))
			sim.spawn_enemy("caster", Vector2(1000, 290))
			sim.apply_damage(left, 14.0, "bone")
			sim.apply_damage(left, 7.7, "bone", true)
			sim.apply_damage(right, 17.0, "frost")
			sim._hurt_player(8.0, "caster", "projectile", Vector2(1000, 290))
			sim.fire_weapon("frost", "bounce", Vector2(620, 350), Vector2.RIGHT)
			var warning := CombatSim.WarningZone.new()
			warning.position = Vector2(820, 460)
			warning.age = 0.65
			sim.zones.append(warning)
			for index: int in 8:
				sim.step(STEP, Vector2.ZERO)
				app.world._advance_feedback(STEP)
			app.ui.update_hud(app.world.hud_snapshot())
			app.world.queue_redraw()
	await process_frame
	await process_frame
	await process_frame
	var caption := Label.new()
	caption.text = "界面验证陈列 · 固定测试场景，非实际对局"
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = Color("a7a9b8")
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.position = Vector2(730, 5)
	app.ui._root.add_child(caption)
	root.title = "秘术余烬 · %s验证（非普通关卡）" % view
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(destination)
	print("FEEDBACK_PREVIEW ", view, " ", destination, " result=", result)
	if not hold:
		app._quit_game(0 if result == OK else 1)
