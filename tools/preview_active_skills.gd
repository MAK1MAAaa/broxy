extends SceneTree
## Native, nonpersistent fixtures use real purchases and fixed-step skill requests.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const VIEWS: Array[String] = ["empty", "starfall", "slash", "dual", "flash_off", "shop", "small"]
var _app: Node

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "dual"
	var output: String = "res://reports/active-skills/dual.png"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		else:
			quit(2)
			return
	if DisplayServer.get_name() == "headless" or view not in VIEWS or not output.to_lower().ends_with(".png"):
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
	_app.ui.set_selected_arena("mire")
	_app._begin_run("bone", 20261028)
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(580, 350)
	sim.player_direction = Vector2.RIGHT
	_app.run.gold = 1000
	if view != "empty":
		for id: String in ["starfall", "arc_slash"]:
			var definition: ContentDef = GameCatalog.skill(id)
			_app.run.offers.assign([{"kind": "skill", "id": id, "price": definition.price, "sold": false}])
			if not _app.run.buy_offer(0):
				_fail("Real skill purchase failed")
				return
	if view == "shop":
		_app.world.stop()
		_app.run.offers.assign([
			{"kind": "skill", "id": "pulse", "rank": 2, "price": 40, "sold": false},
			{"kind": "weapon", "id": "crescent", "price": 24, "sold": false},
			{"kind": "relic", "id": "echo_stone", "price": 22, "sold": false},
			{"kind": "skill", "id": "arc_slash", "price": 24, "sold": false}])
		_app.ui.show_shop()
		_app.ui._bp_select(int(_app.run.active_skills[0]["uid"]), _app.ui._shop_epoch)
	else:
		for point: Vector2 in [Vector2(675, 350), Vector2(660, 295), Vector2(720, 390), Vector2(450, 310)]:
			var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", point)
			enemy.definition = enemy.definition.duplicate() as ContentDef
			enemy.definition.speed = 0.0
			enemy.health = 300.0
			enemy.max_health = 300.0
			enemy.action_timer = 9999.0
		var zone := CombatSim.WarningZone.new()
		zone.position = Vector2(680, 440)
		zone.age = 0.6
		zone.delay = 1.5
		sim.zones.append(zone)
		sim._hostile_shot(Vector2(610, 410), Vector2.ZERO, 8.0, "caster")
		if view == "flash_off":
			_app.world.apply_visual_settings({"flash": false, "shake": false})
		if view in ["starfall", "dual", "flash_off", "small"] and not _app.world.request_skill(0):
			_fail("First skill did not queue")
			return
		if view in ["slash", "dual", "flash_off", "small"] and not _app.world.request_skill(1):
			_fail("Second skill did not queue")
			return
		_app.world._physics_process(STEP)
		_app.world._active_skill_painter.advance(0.045)
		_app.world.queue_redraw()
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
	print("ACTIVE_SKILL_PREVIEW ", JSON.stringify({"view": view, "fixed_fixture": true, "persistent_profile": _app.store.persistent,
		"window_size": [root.size.x, root.size.y], "skills": sim.active_skill_snapshots(),
		"effects": _app.world._active_skill_painter.snapshot(), "capture": output, "result": result}))
	_app._quit_game(0 if result == OK else 1)

func _fail(message: String) -> void:
	push_error(message)
	_app._quit_game(1)
