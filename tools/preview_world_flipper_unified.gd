extends SceneTree
## Frozen real purchases and enemy spawns; no personal profile or balance claim.

const MAIN: PackedScene = preload("res://scenes/main.tscn")

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var arena: String = "reliquary"
	var output: String = "res://reports/world-flipper-unified/enemies.png"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arena="):
			arena = argument.trim_prefix("--arena=")
		elif argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		else:
			quit(2)
			return
	if arena not in ArenaCatalog.IDS or not output.ends_with(".png") or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 原作敌人固定预览（不保存档案）"
	var app: Node = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.args.append("--autoplay")
	app.set_process(false)
	app.sound.set_volume(0.0)
	app.ui.set_selected_arena(arena)
	app._begin_run("bone", 20261029)
	var state: RunState = app.run
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.stop()
	state.gold = 1000
	if not state.expand_backpack() or not state.expand_backpack():
		push_error("The fixed enemy fixture must purchase its inventory expansions")
		app._quit_game(1)
		return
	for id: String in ["frost", "ember", "crescent", "storm"]:
		var definition: ContentDef = GameCatalog.weapon(id)
		state.offers.assign([{"kind": "weapon", "id": id, "price": state.shop_price(definition), "sold": false}])
		if not state.buy_offer(0):
			push_error("The fixed enemy fixture could not purchase " + id)
			app._quit_game(1)
			return
	state.wave = 8
	world.begin(state)
	world.set_physics_process(false)
	world._visual_time = 7.5
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(600, 430)
	sim.player_velocity = Vector2.RIGHT * 100.0
	sim.boss.position = Vector2(930, 320)
	for entry: Array in [
		["chaser", Vector2(400, 300)], ["chaser", Vector2(450, 490)],
		["rusher", Vector2(610, 260)], ["rusher", Vector2(790, 510)],
		["tank", Vector2(800, 330)], ["caster", Vector2(1000, 490)],
	]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy(str(entry[0]), entry[1])
		enemy.age = float(enemy.uid) * 0.37
		enemy.action_timer = 9999.0
	var danger := CombatSim.WarningZone.new()
	danger.position = Vector2(870, 440)
	danger.age = 0.65
	danger.delay = 1.5
	sim.zones.append(danger)
	world._update_camera()
	app.ui.update_hud(world.hud_snapshot())
	var before: String = _signature(state, sim)
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(output)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var unchanged: bool = _signature(state, sim) == before
	print("UNIFIED_ART_PREVIEW ", JSON.stringify({"arena": arena, "result": result,
		"fixed_fixture": true, "persistent_profile": app.store.persistent,
		"state_unchanged_while_drawing": unchanged, "capture": output,
		"enemy_roles": ["chaser", "rusher", "tank", "caster", "boss"]}))
	app._quit_game(0 if result == OK and unchanged else 1)

func _signature(state: RunState, sim: CombatSim) -> String:
	var enemies: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemies.append([enemy.uid, enemy.definition.id, enemy.position, enemy.health, enemy.age])
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.offers, str(state.rng.state), sim.snapshot(), str(sim.rng.state), enemies])
