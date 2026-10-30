extends SceneTree
## Actual purchases and queued original-trait casts form a reproducible, nonpersistent fixture.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const SEED: int = 20261031
const WEAPONS: Array[String] = ["sword_0012", "spear_0005", "sword_0004", "axe_0009", "book_0009", "sword_0007", "axe_0024", "sword_0011"]

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var hero_id: String = "alk"
	var arena_id: String = "town"
	var view: String = "skill"
	var region: String = "center"
	var destination: String = ""
	var small: bool = false
	var flash: bool = true
	var gamepad: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--hero="):
			hero_id = argument.trim_prefix("--hero=")
		elif argument.begins_with("--arena="):
			arena_id = argument.trim_prefix("--arena=")
		elif argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--region="):
			region = argument.trim_prefix("--region=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--small":
			small = true
		elif argument == "--flash-off":
			flash = false
		elif argument == "--gamepad":
			gamepad = true
		else:
			push_error("Unknown expansion preview argument: " + argument)
			quit(2)
			return
	if hero_id not in HeroCatalog.IDS or arena_id not in ArenaCatalog.IDS or view not in ["skill", "bomb-flight", "bomb-burst", "map", "weapons", "shop", "title"] or region not in ["center", "west", "east", "north", "south"] or destination.is_empty() or not destination.ends_with(".png") or DisplayServer.get_name() == "headless":
		push_error("Expansion preview needs existing hero/map/view/region, a PNG destination and native rendering")
		quit(2)
		return
	if view.begins_with("bomb-"):
		hero_id = "hanabi"
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
	app.ui.set_selected_arena(arena_id)
	app.ui.set_selected_hero(hero_id)
	app._begin_run(HeroCatalog.definition(hero_id).starter_weapon, SEED)
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.active = false
	world.autopilot = false
	world.apply_visual_settings({"shake": false, "flash": flash})
	var state: RunState = app.run
	state.gold = 10000
	if not _purchase_loadout(state):
		push_error("The expansion fixture cannot purchase its eight real new weapons: " + state.last_error)
		await app._quit_game(1)
		return
	world.begin(state)
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var position: Vector2 = Vector2(640, 350)
	match region:
		"west": position.x = CombatSim.ARENA.position.x + 220
		"east": position.x = CombatSim.ARENA.end.x - 220
		"north": position.y = CombatSim.ARENA.position.y + 220
		"south": position.y = CombatSim.ARENA.end.y - 220
	sim.player_position = sim.obstacles.free_point(position, 16.0, 16.0)
	sim.player_direction = Vector2.RIGHT
	_stage_enemies(sim, hero_id)
	if view in ["skill", "bomb-flight", "bomb-burst"]:
		if not world.request_hero_skill():
			push_error("The expansion fixture cannot queue the real selected R skill")
			await app._quit_game(1)
			return
		var parameters: Dictionary = sim.run.hero_skill_parameters()
		var delay: float = float(parameters.get("cast_delay", 0.0))
		if parameters.get("timeline") is Array and not parameters["timeline"].is_empty():
			delay = float(parameters["timeline"][0]["delay"])
		var frames: int = ceili(delay / STEP) + (12 if hero_id == "hanabi" else 7)
		for frame: int in frames:
			world._physics_process(STEP)
		if view == "bomb-burst":
			# Capture a real first impact, rather than inventing a blast at a chosen clock.
			for frame: int in 75:
				if not sim.hero_effects_snapshot()["bursts"].is_empty():
					break
				world._physics_process(STEP)
			if sim.hero_effects_snapshot()["bursts"].is_empty():
				push_error("No real bomb blast became visible before the bounded delivery ended")
				await app._quit_game(1)
				return
	elif view == "weapons":
		for index: int in WEAPONS.size():
			var origin: Vector2 = sim.player_position + Vector2(75 + index * 18, -100 + index * 28)
			if sim.fire_weapon(WEAPONS[index], "", origin, Vector2.RIGHT) == null:
				push_error("The actual projectile pool rejected a new weapon preview")
				await app._quit_game(1)
				return
	world._update_camera()
	app.ui.update_hud(world.hud_snapshot())
	if view == "shop":
		world.stop()
		state.offers.clear()
		for index: int in 4:
			var definition: ContentDef = GameCatalog.weapon(WEAPONS[index])
			state.offers.append({"kind": "weapon", "id": definition.id, "price": state.shop_price(definition), "rank": 1, "sold": false})
		app.ui.show_shop()
	elif view == "title":
		world.stop()
		app.ui.show_title({})
		(app.ui._page.find_child("MenuArtwork", true, false) as TitleCover).set_frame(0)
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
	print("WF_EXPANSION_PREVIEW ", JSON.stringify({"hero": hero_id, "arena": arena_id, "view": view, "region": region,
		"small": small, "flash": flash, "gamepad_prompts": gamepad, "physical_gamepad_test": false,
		"fixed_fixture": true, "natural_gameplay": false, "profile_io": false, "persistent_profile": app.store.persistent,
		"fixture_interventions": ["purchase budget and actual largest-first purchases", "sandbox with static high-health enemies", "disabled automatic weapons", "direct projectile presentation only in weapons view"],
		"actual_wave_time": sim.elapsed, "actual_hero_skill": sim.hero_skill_snapshot(), "actual_deliveries": sim.hero_effects_snapshot(),
		"actual_weapon_effects": sim.weapon_effects.snapshot(), "actual_damage": sim.damage_by_skill,
		"inventory": {"weapons": state.loadout.size(), "used_cells": state.backpack_snapshot()["used_cells"]},
		"state_unchanged_while_drawing": pure, "state_hash": before.sha256_text(), "capture": destination, "result": result}))
	await app._quit_game(0 if result == OK and pure else 1)

func _purchase_loadout(state: RunState) -> bool:
	while state.backpack.height < BackpackInventory.MAX_HEIGHT:
		if not state.expand_backpack():
			return false
	var ids: Array[String] = WEAPONS.duplicate()
	for id: String in ids:
		if GameCatalog.weapon(id) == null:
			return false
	ids.sort_custom(func(a: String, b: String) -> bool:
		var first: Vector2i = GameCatalog.weapon(a).inventory_size
		var second: Vector2i = GameCatalog.weapon(b).inventory_size
		return first.x * first.y > second.x * second.y
	)
	var starter_uid: int = int(state.loadout[0]["uid"])
	for index: int in ids.size():
		var definition: ContentDef = GameCatalog.weapon(ids[index])
		if definition == null:
			return false
		state.offers.assign([{"kind": "weapon", "id": definition.id, "rank": 1, "price": state.shop_price(definition), "sold": false}])
		if not state.buy_offer(0):
			return false
		if index == 0 and not state.sell_item(starter_uid):
			return false
	return state.loadout.size() == WEAPONS.size()

func _stage_enemies(sim: CombatSim, hero_id: String) -> void:
	var offsets: Array[Vector2] = [Vector2(90, 0), Vector2(-100, 0), Vector2(160, -45), Vector2(200, 45), Vector2(0, 120)]
	if hero_id == "hanabi":
		offsets.clear()
		for index: int in 5:
			offsets.append(Vector2.from_angle((float(index) / 4.0 - 0.5)) * 280)
	for offset: Vector2 in offsets:
		var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + offset)
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.health = 5000.0
		enemy.max_health = 5000.0
		enemy.action_timer = 9999.0

func _signature(world: CombatWorld) -> String:
	var sim: CombatSim = world.sim
	var enemies: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemies.append([enemy.uid, enemy.position, enemy.health, enemy.age, enemy.action_timer,
				enemy.fire_vulnerability_left, enemy.fire_vulnerability])
	return JSON.stringify([sim.snapshot(), enemies, sim.damage_by_skill, sim.damage_by_weapon, sim.run.summary(),
		sim.run.backpack_snapshot(), sim.run.offers, sim.obstacles.snapshot(), sim.interactions.snapshot(),
		str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)])
