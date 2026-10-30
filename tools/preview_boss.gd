extends SceneTree
## Frozen real Main encounters; casts, half-health transition and breaks use actual simulation paths.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261030
const STEP: float = 1.0 / 60.0

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var arena_id: String = "mire"
	var view: String = "charge"
	var destination: String = ""
	var small: bool = false
	var flash: bool = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arena="):
			arena_id = argument.trim_prefix("--arena=")
		elif argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--flash-off":
			flash = false
		elif argument == "--small":
			small = true
		else:
			push_error("Unknown boss preview argument: " + argument)
			quit(2)
			return
	if destination.is_empty():
		destination = "res://reports/world-flipper-boss/preview-%s-%s.png" % [view, arena_id]
	if arena_id not in ArenaCatalog.IDS or view not in ["charge", "storm", "root", "phase2", "break"] or not destination.ends_with(".png") or DisplayServer.get_name() == "headless":
		push_error("Boss preview requires an existing arena, charge/storm/root/phase2/break view, a PNG path and native rendering")
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(960, 540) if small else Vector2i(1280, 720)
	root.title = "秘术余烬 · 首领固定预览（不保存档案）"
	var app: Node = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args.append("--autoplay")
	app.sound.set_volume(0.0)
	app.ui.set_selected_arena(arena_id)
	app.ui.set_selected_hero("alk")
	app._begin_run("bone", SEED)
	var state: RunState = app.run
	state.gold = 1000
	for id: String in ["pulse", "starfall"]:
		var definition: ContentDef = GameCatalog.skill(id)
		state.offers.assign([{"kind": "skill", "id": id, "rank": 1, "price": state.shop_price(definition), "sold": false}])
		if not state.buy_offer(0):
			push_error("The boss preview could not buy its actual rear character: " + id)
			await app._quit_game(1)
			return
	state.wave = 8
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.autopilot = false
	world.begin(state)
	world.apply_visual_settings({"shake": false, "flash": flash})
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.boss.definition = sim.boss.definition.duplicate() as ContentDef
	sim.boss.definition.speed = 0.0
	sim.boss.position = sim.obstacles.free_point(Vector2(640, 400), sim.boss.radius, sim.boss.radius)
	sim.boss.velocity = Vector2.ZERO
	sim.player_position = sim.obstacles.free_point(Vector2(640, 470), 16.0, 16.0)
	sim.player_velocity = Vector2.ZERO
	sim.player_direction = Vector2.UP
	var fixture: Dictionary = _fixture(world, view)
	if not bool(fixture.get("passed", false)):
		push_error("Could not prepare the actual boss preview: " + JSON.stringify(fixture))
		await app._quit_game(1)
		return
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
	var pure: bool = _signature(world) == before
	print("BOSS_PREVIEW ", JSON.stringify({"arena": arena_id, "view": view, "seed": SEED, "size": root.size,
		"fixed_fixture": true, "natural_gameplay": false, "profile_io": false, "flash": flash, "persistent_profile": app.store.persistent,
		"fixture": fixture, "state_unchanged_while_drawing": pure, "state_hash": before.sha256_text(), "capture": destination, "result": result}))
	await app._quit_game(0 if result == OK and pure else 1)

func _step(world: CombatWorld) -> void:
	world.sim.run.health = world.sim.run.stat("max_health")
	world._physics_process(STEP)

func _wait_cast(world: CombatWorld, id: String) -> bool:
	for frame: int in 1200:
		var encounter: Dictionary = world.sim.boss_encounter_snapshot()
		if encounter["phase"] == "charge" and encounter["attack_id"] == id:
			return true
		_step(world)
	return false

func _fixture(world: CombatWorld, view: String) -> Dictionary:
	var sim: CombatSim = world.sim
	if view == "phase2":
		sim.apply_damage(sim.boss, sim.boss.max_health * 0.55, "bone")
	var attack_id: String = "root_corridor" if view in ["root", "phase2"] else "forest_storm"
	if not _wait_cast(world, attack_id):
		return {"passed": false, "reason": "the real boss did not enter its expected cast", "attack": attack_id}
	var encounter: Dictionary = sim.boss_encounter_snapshot()
	var desired_fraction: float = 0.72 if view == "phase2" else 0.45
	for frame: int in 180:
		encounter = sim.boss_encounter_snapshot()
		var fraction: float = 1.0 - float(encounter["charge_left"]) / float(encounter["charge_total"])
		if fraction >= desired_fraction:
			break
		_step(world)
	var actual_shots: int = 0
	if view == "storm":
		for frame: int in 180:
			if sim.boss_encounter_snapshot()["phase"] != "charge":
				break
			_step(world)
	elif view == "break":
		for volley: int in 12:
			var points: Array[Dictionary] = sim.boss_weakpoints()
			if points.is_empty():
				break
			var target: Dictionary = points[points.size() - 1]
			var shot: CombatSim.Shot = sim.fire_weapon("bone", "", target["position"] - Vector2(10, 0), Vector2.RIGHT)
			if shot == null:
				return {"passed": false, "reason": "the actual projectile pool was exhausted"}
			actual_shots += 1
			_step(world)
		for frame: int in 3:
			_step(world)
	encounter = sim.boss_encounter_snapshot()
	var expected: bool = encounter["active"] and sim.run.active_skills.size() == 2
	if view == "storm":
		expected = expected and encounter["phase"] == "recovery" and sim.zones.size() == 3 and world.boss_danger_snapshot().is_empty()
	elif view == "break":
		expected = expected and encounter["phase"] == "break" and sim.boss_interrupts == 1 and world.boss_weakpoint_presentation_snapshot().size() == 3
	else:
		expected = expected and encounter["phase"] == "charge" and encounter["attack_id"] == attack_id and not sim.boss_weakpoints().is_empty()
	if view == "phase2":
		expected = expected and encounter["phase2"] and encounter["cast_phase2"]
	return {"passed": expected, "phase": encounter["phase"], "attack_id": encounter["attack_id"], "cast_id": encounter["cast_id"],
		"phase2": encounter["phase2"], "cast_phase2": encounter["cast_phase2"], "charge_left": encounter["charge_left"],
		"weakpoints_remaining": encounter["weakpoints_remaining"], "actual_bone_shots": actual_shots,
		"broken": sim.weakpoints_broken, "interrupts": sim.boss_interrupts, "published_zones": sim.zones.size(),
		"rear_characters": sim.run.active_skills.size()}

func _signature(world: CombatWorld) -> String:
	var sim: CombatSim = world.sim
	var enemies: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemies.append([enemy.uid, enemy.definition.id, enemy.position, enemy.velocity, enemy.health, enemy.age, enemy.action_timer, enemy.mode])
	var shots: Array = []
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			shots.append([shot.slot, shot.source, shot.position, shot.previous, shot.velocity, shot.damage, shot.life, shot.hit_ids])
	var zones: Array = []
	for zone: CombatSim.WarningZone in sim.zones:
		zones.append([zone.shape, zone.position, zone.radius, zone.direction, zone.length, zone.width, zone.age, zone.delay, zone.triggered, zone.source_cast_id])
	return JSON.stringify([sim.run.summary(), sim.run.backpack_snapshot(), sim.run.offers, str(sim.run.rng.state),
		sim.snapshot(), str(sim.rng.state), sim.boss_weakpoints(), enemies, shots, zones,
		sim.obstacles.snapshot(), sim.interactions.snapshot(), str(sim.interactions._rng.state)])
