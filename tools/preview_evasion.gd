extends SceneTree
## Real blocked contact in Main, with fixed physical steps and no personal profile IO.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const CASES: PackedStringArray = ["hit", "flash_off", "resumed", "miss", "danger", "hurt", "interactive"]
var _app: Node
var _events: Array[Dictionary] = []

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var case_name: String = "hit"
	var output: String = "res://reports/evasion/hit.png"
	var hold: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			hold = true
		else:
			_invalid()
			return
	if DisplayServer.get_name() == "headless" or case_name not in CASES or not output.to_lower().ends_with(".png"):
		_invalid()
		return
	root.size = Vector2i(1280, 720)
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
	sim.player_position = Vector2(560, 365)
	sim.player_direction = Vector2.RIGHT
	sim.dash_evaded.connect(_on_evaded)
	if case_name == "flash_off":
		_app.world.apply_visual_settings({"flash": false, "shake": true})
	if case_name == "interactive":
		_stationary_enemy(sim, sim.player_position + Vector2(56, 0))
	else:
		if not _app.world.request_dash():
			_fail("A ready dash was rejected")
			return
		_app.world._physics_process(STEP)
		if case_name != "miss":
			_stationary_enemy(sim, sim.player_position + Vector2(19, 0))
		_app.world._physics_process(STEP)
		if case_name == "hurt":
			for frame: int in 7:
				_app.world._physics_process(STEP)
			sim._hostile_shot(sim.player_position + Vector2(11, 0), Vector2.ZERO, 8.0, "caster")
			_app.world._physics_process(STEP)
		if case_name == "danger":
			var zone := CombatSim.WarningZone.new()
			zone.position = sim.player_position + Vector2(110, 0)
			zone.age = 0.6
			zone.delay = 1.5
			sim.zones.append(zone)
		if case_name == "resumed":
			var frozen: Dictionary = _app.world.dash_evasion_feedback_snapshot()
			_app._pause()
			for frame: int in 5:
				await process_frame
			if frozen != _app.world.dash_evasion_feedback_snapshot():
				_fail("Pausing changed evasion feedback")
				return
			_app._resume()
			_app.world._physics_process(STEP)
	var expected: int = 0 if case_name in ["miss", "interactive"] else 1
	var feedback: Dictionary = _app.world.dash_evasion_feedback_snapshot()
	var expected_health: float = 92.0 if case_name == "hurt" else 100.0
	if sim.dash_evades != expected or bool(feedback["active"]) != (expected == 1 and case_name != "hurt") or sim.run.health != expected_health:
		_fail("The fixture did not use the expected actual contact protection")
		return
	var focused: Control = root.gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	var caption := Label.new()
	caption.text = "成功闪避固定验证 · 真实接触与物理步 · 非自然对局 · 不保存档案"
	caption.position = Vector2(340, 104)
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = GameUI.GOLD
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app.ui._root.add_child(caption)
	root.title = "秘术余烬 · 成功闪避验证 / %s（固定场景，不保存档案）" % case_name
	_app.ui.update_hud(_app.world.hud_snapshot())
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(output)
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(path)
	print("EVASION_PREVIEW ", JSON.stringify({"case": case_name, "fixed_fixture": true,
		"persistent_profile": _app.store.persistent, "capture_result": result, "capture": output,
		"health": sim.run.health, "hits_taken": sim.run.hits_taken, "last_hit": sim.run.last_hit,
		"dash": sim.dash_snapshot(), "feedback": feedback, "events": _events}))
	if not hold or result != OK:
		_app._quit_game(0 if result == OK else 1)
		return
	if case_name == "interactive":
		_app.world.set_physics_process(true)

func _stationary_enemy(sim: CombatSim, point: Vector2) -> void:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0

func _on_evaded(point: Vector2, origin: Vector2, source_id: String, kind: String) -> void:
	var event: Dictionary = {"position": [point.x, point.y], "origin": [origin.x, origin.y], "source_id": source_id, "kind": kind}
	_events.append(event)
	print("EVASION_EVENT ", JSON.stringify(event))

func _fail(message: String) -> void:
	push_error(message)
	_app._quit_game(1)

func _invalid() -> void:
	push_error("Use native --case=hit|flash_off|resumed|miss|danger|hurt|interactive [--capture=path.png] [--hold]")
	quit(2)
