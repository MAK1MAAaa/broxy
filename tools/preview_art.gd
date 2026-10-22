extends SceneTree
## A frozen art fixture. It never reads/writes the player's profile or evaluates balance.

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var destination: String = "res://reports/art-showcase.png"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output=res://reports/") and argument.ends_with(".png"):
			destination = argument.trim_prefix("--output=")
	root.size = Vector2i(1280, 720)
	var app = load("res://scenes/main.tscn").instantiate()
	app.store.persistent = false
	root.add_child(app)
	await process_frame
	# Reuse the automated-validation focus exemption; the frozen fixture has no bot.
	app.args.append("--autoplay")
	app._start_run("bone")
	var run: RunState = app.run
	run.wave = 8
	run.loadout = [
		{"id": "bone", "paid": 0, "rune": {"id": "pierce", "uid": 1}},
		{"id": "frost", "paid": 0, "rune": {"id": "bounce", "uid": 2}},
		{"id": "ember", "paid": 0, "rune": {"id": "blast", "uid": 3}},
		{"id": "scatter", "paid": 0, "rune": {}},
	]
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.begin(run)
	world.set_physics_process(false)
	world._visual_time = 7.5
	var sim: CombatSim = world.sim
	sim.elapsed = 18.0
	sim.player_position = Vector2(430, 380)
	sim.player_velocity = Vector2(100, 0)
	sim.boss.position = Vector2(960, 310)
	for entry: Array in [
		["chaser", Vector2(180, 250)], ["chaser", Vector2(750, 330)],
		["chaser", Vector2(360, 215)], ["chaser", Vector2(660, 490)],
		["rusher", Vector2(740, 225)], ["rusher", Vector2(260, 475)],
		["tank", Vector2(840, 465)], ["caster", Vector2(1110, 470)],
	]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy(str(entry[0]), entry[1])
		enemy.age = float(enemy.uid) * 0.37
	for entry: Array in [
		["bone", "pierce", Vector2(550, 350), Vector2(1, -0.2)],
		["frost", "bounce", Vector2(605, 285), Vector2(0.8, -0.4)],
		["ember", "blast", Vector2(560, 440), Vector2(0.9, 0.3)],
		["scatter", "", Vector2(540, 470), Vector2(0.7, 0.5)],
		["scatter", "", Vector2(515, 490), Vector2(0.4, 0.7)],
	]:
		sim.fire_weapon(str(entry[0]), str(entry[1]), entry[2], entry[3])
	for index: int in 15:
		sim._drop_soul(Vector2(190 + index * 56, 540 + sin(float(index)) * 12), 1)
	var warning := CombatSim.WarningZone.new()
	warning.position = Vector2(630, 390)
	warning.age = 0.65
	sim.zones.append(warning)
	sim.add_effect(Vector2(810, 365), Color("d2a4ed"), 48.0, 0.35, 0)
	sim.effects.back().life = 0.2
	app.ui.update_hud(world.hud_snapshot())
	app.ui.notify("美术陈列 · 固定场景，展示角色、法器与危险预警")
	root.title = "秘术余烬 · 美术陈列（非普通关卡）"
	world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(destination)
	print("ART_PREVIEW_CAPTURE result=", result, " output=", destination, " persistent=false")
	app._quit_game(0 if result == OK else 1)
