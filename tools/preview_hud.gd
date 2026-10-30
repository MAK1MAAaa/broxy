extends SceneTree
## Frozen Main fixtures use real inventory transactions, queued casts and boss damage.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const SEED: int = 20261031
const VIEWS: PackedStringArray = ["full", "cooldown", "boss-intro", "boss-settled", "boss-phase2", "empty"]

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "full"
	var destination: String = ""
	var small: bool = false
	var gamepad: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--small":
			small = true
		elif argument == "--gamepad":
			gamepad = true
		else:
			push_error("Unknown HUD preview argument: " + argument)
			quit(2)
			return
	if view not in VIEWS or destination.is_empty() or not destination.ends_with(".png") or DisplayServer.get_name() == "headless":
		push_error("HUD preview needs an existing view, a PNG path and native rendering")
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(960, 540) if small else Vector2i(1280, 720)
	root.title = "秘术余烬 · HUD 固定预览（不保存档案）"
	var app: Node = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args.append("--autoplay")
	app.sound.set_volume(0.0)
	app.ui.set_selected_arena("mire")
	app.ui.set_selected_hero("alk")
	app._begin_run("bone", SEED)
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.active = false
	world.autopilot = false
	world.apply_visual_settings({"flash": true, "shake": false})
	var state: RunState = app.run
	state.gold = 3000
	state.collect_souls(141)
	while state.pending_upgrades > 0:
		var choices: Array[Dictionary] = state.upgrade_choices()
		if choices.is_empty() or not state.choose_upgrade(str(choices[0]["id"])):
			push_error("HUD fixture could not consume an actual level upgrade")
			await app._quit_game(1)
			return
	if view != "empty" and not _purchase_loadout(state):
		push_error("HUD fixture could not buy its actual inventory: " + state.last_error)
		await app._quit_game(1)
		return
	if view.begins_with("boss-"):
		state.wave = 8
	world.begin(state)
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = sim.obstacles.free_point(Vector2(640, 470), 16.0, 16.0)
	sim.player_velocity = Vector2.ZERO
	sim.player_direction = Vector2.UP
	if sim.boss != null:
		sim.boss.definition = sim.boss.definition.duplicate() as ContentDef
		sim.boss.definition.speed = 0.0
		sim.boss.position = sim.obstacles.free_point(Vector2(640, 340), sim.boss.radius, sim.boss.radius)
		sim.boss.velocity = Vector2.ZERO
		if view == "boss-phase2":
			sim.apply_damage(sim.boss, sim.boss.max_health * 0.55, "bone")
		if view != "boss-intro":
			for frame: int in 168:
				state.health = state.stat("max_health")
				world._physics_process(STEP)
	else:
		_spawn_stage_enemies(sim)
	if view == "cooldown":
		var queued: bool = world.request_dash()
		queued = world.request_skill(0) and queued
		queued = world.request_skill(1) and queued
		queued = world.request_hero_skill() and queued
		if not queued:
			push_error("HUD fixture could not queue all four actual actions")
			await app._quit_game(1)
			return
		for frame: int in 36:
			world._physics_process(STEP)
	state.take_damage(state.health - state.stat("max_health") * 0.6, "fixture", "fixture")
	world._visual_time = 0.12
	world._update_camera()
	app.ui.update_hud(world.hud_snapshot())
	world.queue_redraw()
	root.warp_mouse(Vector2(20, 20))
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(20, 20)
	pointer.global_position = pointer.position
	root.push_input(pointer, false)
	app.ui._on_input_device_changed("gamepad" if gamepad else "keyboard", 0 if gamepad else -1)
	var before: String = _signature(world)
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(destination)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var pure: bool = before == _signature(world)
	var snapshot: Dictionary = world.hud_snapshot()
	print("HUD_PREVIEW ", JSON.stringify({"view": view, "small": small, "gamepad_prompts": gamepad,
		"physical_gamepad_test": false, "fixed_fixture": true, "natural_gameplay": false,
		"profile_io": false, "persistent_profile": app.store.persistent,
		"fixture_interventions": ["seeded inventory purchase budget", "sandbox with static enemies", "disabled automatic weapons", "boss warmup health refill"],
		"inventory": {"weapons": state.loadout.size(), "rear_characters": state.active_skills.size(), "used_cells": state.backpack.snapshot()["used_cells"]},
		"actual_values": {"health": snapshot["health"], "max_health": snapshot["max_health"], "level": snapshot["level"],
			"xp": snapshot["xp"], "xp_needed": snapshot["xp_needed"], "gold": snapshot["gold"], "time_left": snapshot["time_left"],
			"dash": snapshot["dash"], "skills": snapshot["skills"], "hero_skill": snapshot["hero_skill"],
			"boss": snapshot["boss_encounter"], "boss_intro_left": snapshot.get("boss_intro_left", 0.0)},
		"visible_weapon_widgets": app.ui._hud["slots"].get_child_count(),
		"state_unchanged_while_drawing": pure, "state_hash": before.sha256_text(), "capture": destination, "result": result}))
	await app._quit_game(0 if result == OK and pure else 1)

func _purchase_loadout(state: RunState) -> bool:
	while state.backpack.height < BackpackInventory.MAX_HEIGHT:
		if not state.expand_backpack():
			return false
	# Six 1×3 weapons, two 2×2 weapons and two companions fit the real 6×6 grid.
	for id: String in ["frost", "bone", "frost", "bone", "frost", "ember", "scatter"]:
		if not _buy(state, "weapon", id):
			return false
	for id: String in ["pulse", "starfall"]:
		if not _buy(state, "skill", id):
			return false
	return state.loadout.size() == 8 and state.active_skills.size() == 2

func _buy(state: RunState, kind: String, id: String) -> bool:
	var definition: ContentDef = GameCatalog.weapon(id) if kind == "weapon" else GameCatalog.skill(id)
	state.offers.assign([{"kind": kind, "id": id, "rank": 1, "price": state.shop_price(definition), "sold": false}])
	return state.buy_offer(0)

func _spawn_stage_enemies(sim: CombatSim) -> void:
	var ids: PackedStringArray = ["chaser", "rusher", "tank", "caster"]
	var positions: Array[Vector2] = [Vector2(400, 320), Vector2(890, 440), Vector2(780, 260), Vector2(410, 620)]
	for index: int in ids.size():
		var enemy: CombatSim.Enemy = sim.spawn_enemy(ids[index], positions[index])
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.action_timer = 9999.0

func _signature(world: CombatWorld) -> String:
	var sim: CombatSim = world.sim
	var enemies: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemies.append([enemy.uid, enemy.definition.id, enemy.position, enemy.health, enemy.age, enemy.action_timer])
	return JSON.stringify([world.hud_snapshot(), enemies, sim.damage_by_skill, sim.damage_by_weapon,
		sim.run.summary(), sim.run.offers, sim.obstacles.snapshot(), sim.interactions.snapshot(),
		str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)])
