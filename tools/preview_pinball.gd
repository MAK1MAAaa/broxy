extends SceneTree
## Frozen Main/World fixtures using real purchases, bumper collisions and projectile hits.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261030
const STEP: float = 1.0 / 60.0

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var arena_id: String = "reliquary"
	var view: String = "field"
	var destination: String = ""
	var small: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arena="):
			arena_id = argument.trim_prefix("--arena=")
		elif argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--small":
			small = true
		else:
			push_error("Unknown pinball preview argument: " + argument)
			quit(2)
			return
	if destination.is_empty():
		destination = "res://reports/world-flipper-pinball/preview-%s-%s.png" % [view, arena_id]
	if arena_id not in ArenaCatalog.IDS or view not in ["field", "ball", "break"] or not destination.ends_with(".png") or DisplayServer.get_name() == "headless":
		push_error("Pinball preview requires an existing arena, field/ball/break view, a PNG path and native rendering")
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(960, 540) if small else Vector2i(1280, 720)
	root.title = "秘术余烬 · 弹射固定预览（不保存档案）"
	var app: Node = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args.append("--autoplay")
	app.sound.set_volume(0.0)
	app.ui.set_selected_arena(arena_id)
	app.ui.set_selected_hero("alk")
	app._begin_run("bone", SEED)
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.apply_visual_settings({"shake": false, "flash": true})
	world._visual_time = 0.12
	var state: RunState = app.run
	state.gold = 1000
	for id: String in ["pulse", "starfall"]:
		var definition: ContentDef = GameCatalog.skill(id)
		state.offers.assign([{"kind": "skill", "id": id, "rank": 1, "price": state.shop_price(definition), "sold": false}])
		if not state.buy_offer(0):
			push_error("The fixed preview could not buy its actual companion: " + id)
			await app._quit_game(1)
			return
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var fixture: Dictionary = {}
	match view:
		"field":
			fixture = _field_fixture(world)
		"ball":
			fixture = _ball_fixture(world)
		"break":
			fixture = _break_fixture(world)
	if not bool(fixture.get("passed", false)):
		push_error("Could not prepare the real pinball preview: " + JSON.stringify(fixture))
		await app._quit_game(1)
		return
	world._update_camera()
	app.ui.update_hud(world.hud_snapshot())
	world.queue_redraw()
	root.warp_mouse(Vector2(20, 20))
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(20, 20)
	pointer.global_position = pointer.position
	root.push_input(pointer, false)
	var before: String = _signature(state, sim)
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(destination)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var pure: bool = _signature(state, sim) == before
	print("PINBALL_PREVIEW ", JSON.stringify({"arena": arena_id, "view": view, "seed": SEED, "size": root.size,
		"fixed_fixture": true, "natural_gameplay": false, "profile_io": false, "persistent_profile": app.store.persistent,
		"fixture": fixture, "state_unchanged_while_drawing": pure, "state_hash": before.sha256_text(), "capture": destination, "result": result}))
	await app._quit_game(0 if result == OK and pure else 1)

func _field_fixture(world: CombatWorld) -> Dictionary:
	var sim: CombatSim = world.sim
	sim.player_position = sim.obstacles.free_point(Vector2(640, 390), 16.0, 16.0)
	sim.player_direction = Vector2.RIGHT
	sim.player_velocity = Vector2(140, 0)
	for entry: Array in [["chaser", Vector2(410, 300)], ["rusher", Vector2(830, 300)], ["tank", Vector2(880, 480)], ["caster", Vector2(430, 510)]]:
		_spawn_frozen_enemy(sim, str(entry[0]), entry[1])
	var crates: Array = sim.interactions.snapshot()["crates"]
	return {"passed": world._arena_obstacles.size() == 12 and crates.size() == 12 and sim.run.active_skills.size() == 2,
		"static_props": world._arena_obstacles.size(), "active_crates": crates.size(), "enemies": sim.enemy_count, "rear_characters": sim.run.active_skills.size()}

func _ball_fixture(world: CombatWorld) -> Dictionary:
	var sim: CombatSim = world.sim
	var bumper: Dictionary = {}
	for obstacle: Dictionary in sim.obstacles.snapshot():
		if str(obstacle["id"]) == "west_bumper":
			bumper = obstacle
			break
	if bumper.is_empty():
		return {"passed": false, "reason": "missing authored west bumper"}
	var center: Vector2 = bumper["center"]
	sim.player_position = center - Vector2(float(bumper["radius"]) + 16.0 + 32.0, 0)
	sim.player_direction = Vector2.RIGHT
	var target: CombatSim.Enemy = _spawn_frozen_enemy(sim, "tank", center - Vector2(144, 0))
	target.health = 2000.0
	target.max_health = 2000.0
	Input.action_press(ControlBindings.PREFIX + "move_right")
	var accepted: bool = world.request_dash()
	var frames: int = 0
	if accepted:
		for index: int in 8:
			world._physics_process(STEP)
			frames = index + 1
			if bool(sim.pinball_snapshot()["active"]) and int(sim.pinball_snapshot()["combo"]) > 0:
				break
	Input.action_release(ControlBindings.PREFIX + "move_right")
	var ball: Dictionary = sim.pinball_snapshot()
	return {"passed": accepted and bool(ball["active"]), "physics_frames": frames, "bounces": ball["bounces"],
		"combo": ball["combo"], "remaining": ball["remaining"], "enemy_health": target.health, "dash_queued": accepted}

func _break_fixture(world: CombatWorld) -> Dictionary:
	var sim: CombatSim = world.sim
	var rounds: int = 0
	var destroyed: int = 0
	var source: Array = sim.interactions.snapshot()["crates"]
	for crate: Dictionary in source:
		var index: int = int(crate["index"])
		var center: Vector2 = crate["position"]
		var separation: float = maxf(float(crate["radius"]) + 80.0, sim.run.stat("pickup_radius") + 64.0)
		sim.player_position = sim.obstacles.free_point(center - Vector2(separation, 0), 16.0, 16.0)
		sim.player_velocity = Vector2.ZERO
		sim.player_direction = (center - sim.player_position).normalized()
		for volley: int in 8:
			var shot: CombatSim.Shot = sim.fire_weapon("bone", "", sim.player_position, sim.player_direction)
			if shot == null:
				return {"passed": false, "reason": "real projectile pool exhausted"}
			rounds += 1
			for frame: int in 90:
				sim._update_shots(STEP)
				if not shot.active:
					break
			if not bool(sim.interactions.snapshot()["crates"][index]["active"]):
				break
		var after: Dictionary = sim.interactions.snapshot()["crates"][index]
		if bool(after["active"]):
			return {"passed": false, "reason": "real bone shots did not destroy the selected crate", "crate": crate["id"]}
		destroyed += 1
		var pickups: Array = sim.interactions.snapshot()["pickups"]
		if not pickups.is_empty():
			var drop: Dictionary = pickups[0]
			sim.interactions.advance(0.08)
			world._advance_interaction_feedback(0.08)
			world._visual_time = 0.12
			_spawn_frozen_enemy(sim, "chaser", center + Vector2(200, 90))
			var retained: bool = not sim.interactions.pickup_candidates(drop["position"], 1.0).is_empty()
			var outside_pickup: bool = sim.player_position.distance_to(drop["position"]) > sim.run.stat("pickup_radius")
			return {"passed": retained and outside_pickup and not bool(after["active"]), "crate": crate["id"], "crates_broken": destroyed,
				"actual_bone_shots": rounds, "drop_uid": drop["uid"], "drop_kind": drop["kind"], "drop_position": drop["position"],
				"drop_retained": retained, "player_outside_pickup_radius": outside_pickup, "break_age": sim.interactions.snapshot()["crates"][index]["break_age"]}
		sim.interactions.advance(0.32)
		world._advance_interaction_feedback(0.32)
	return {"passed": false, "reason": "the fixed seed yielded no drop from any authored crate", "crates_broken": destroyed, "actual_bone_shots": rounds}

func _spawn_frozen_enemy(sim: CombatSim, id: String, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.age = float(enemy.uid) * 0.37
	enemy.action_timer = 9999.0
	return enemy

func _signature(state: RunState, sim: CombatSim) -> String:
	var enemies: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemies.append([enemy.uid, enemy.definition.id, enemy.position, enemy.velocity, enemy.health, enemy.age, enemy.action_timer, enemy.mode])
	var shots: Array = []
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			shots.append([shot.slot, shot.source, shot.position, shot.previous, shot.velocity, shot.damage, shot.life, shot.hit_ids])
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.offers, str(state.rng.state), sim.snapshot(), str(sim.rng.state),
		enemies, shots, sim.obstacles.snapshot(), sim.interactions.snapshot(), str(sim.interactions._rng.state)])
