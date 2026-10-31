extends SceneTree
## Real queued casts and purchases produce a frozen, nonpersistent native art fixture.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var hero_id: String = "alk"
	var mode: String = "hero"
	var destination: String = ""
	var small: bool = false
	var flash: bool = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--hero="):
			hero_id = argument.trim_prefix("--hero=")
		elif argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--small":
			small = true
		elif argument == "--flash-off":
			flash = false
		else:
			push_error("Unknown art preview argument: " + argument)
			quit(2)
			return
	if hero_id not in HeroCatalog.IDS or mode not in ["hero", "rear"] or (mode == "rear" and hero_id != "alk") or destination.is_empty() or not destination.ends_with(".png") or DisplayServer.get_name() == "headless":
		push_error("Art preview needs an existing hero, hero/rear mode, PNG capture and native renderer")
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(960, 540) if small else Vector2i(1280, 720)
	var app: Node = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args.append("--autoplay")
	app.sound.set_volume(0.0)
	app.ui.set_selected_arena("mire")
	app.ui.set_selected_hero(hero_id)
	app._begin_run(HeroCatalog.definition(hero_id).starter_weapon, 20261030)
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.autopilot = false
	world.apply_visual_settings({"flash": flash, "shake": false})
	app.run.gold = 1000
	var wanted: Array[String] = []
	wanted.assign(["starfall", "arc_slash"] if mode == "rear" else ["pulse", "starfall", "arc_slash"])
	for id: String in wanted:
		if app.run.active_skills.size() >= 2 or HeroCatalog.rear_for_skill(id).id == hero_id:
			continue
		var definition: ContentDef = GameCatalog.skill(id)
		app.run.offers.assign([{"kind": "skill", "id": id, "rank": 1, "price": app.run.shop_price(definition), "sold": false}])
		if not app.run.buy_offer(0):
			push_error("Art fixture could not purchase its actual companion")
			await app._quit_game(1)
			return
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = sim.obstacles.free_point(Vector2(580, 350), 16.0, 16.0)
	sim.player_direction = Vector2.RIGHT
	for offset: Vector2 in [Vector2(80, 0), Vector2(120, -40), Vector2(150, 35), Vector2(190, 0), Vector2(0, -105)]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + offset)
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.health = 5000.0
		enemy.max_health = 5000.0
		enemy.action_timer = 9999.0
	var zone := CombatSim.WarningZone.new()
	zone.position = sim.player_position + Vector2(110, 115)
	zone.radius = 66.0
	zone.age = 0.7
	zone.delay = 1.5
	sim.zones.append(zone)
	var queued: bool = world.request_hero_skill()
	if mode == "rear":
		world.clear_pending_actions()
		queued = world.request_skill(0) and world.request_skill(1)
	if not queued:
		push_error("Art fixture could not queue its actual cast")
		await app._quit_game(1)
		return
	world._physics_process(STEP)
	world._active_skill_painter.advance(0.055)
	world._visual_time = 0.12
	world._update_camera()
	app.ui.update_hud(world.hud_snapshot())
	world.queue_redraw()
	root.warp_mouse(Vector2(20, 20))
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(20, 20)
	pointer.global_position = pointer.position
	root.push_input(pointer, false)
	var before: String = _signature(world)
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(destination)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var pure: bool = before == _signature(world)
	print("ART_MOTION_PREVIEW ", JSON.stringify({"hero": hero_id, "mode": mode, "flash": flash, "small": small,
		"fixed_fixture": true, "natural_gameplay": false, "profile_io": false, "persistent_profile": app.store.persistent,
		"actual_hero_uses": sim.hero_skill_snapshot()["uses"], "actual_rear_uses": sim.active_skill_snapshots(),
		"cosmetic_pool": world._active_skill_painter.snapshot(), "state_hash": before.sha256_text(),
		"state_unchanged_while_drawing": pure, "capture": destination, "result": result}))
	await app._quit_game(0 if result == OK and pure else 1)

func _signature(world: CombatWorld) -> String:
	var sim: CombatSim = world.sim
	var enemies: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemies.append([enemy.uid, enemy.position, enemy.health, enemy.age, enemy.action_timer])
	return JSON.stringify([sim.snapshot(), enemies, sim.damage_by_skill, sim.damage_by_weapon,
		sim.run.summary(), sim.run.offers, sim.obstacles.snapshot(), sim.interactions.snapshot(),
		str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)])
