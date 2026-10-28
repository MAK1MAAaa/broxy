extends SceneTree
## Source and exported-game fixtures use the real Main without personal profile persistence.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const CASES: PackedStringArray = ["ready", "dash", "cooldown", "danger", "interactive"]
var _app: Node
var _last_state: String = ""

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var case_name: String = "dash"
	var arena: String = "mire"
	var output: String = "res://reports/dash/dash.png"
	var hold: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--arena="):
			arena = argument.trim_prefix("--arena=")
		elif argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			hold = true
		else:
			_invalid()
			return
	if DisplayServer.get_name() == "headless" or case_name not in CASES or arena not in ArenaCatalog.IDS or not output.to_lower().ends_with(".png"):
		_invalid()
		return
	root.size = Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	_app.sound.set_volume(0.0)
	_app.ui.set_selected_arena(arena)
	_app._begin_run("bone", 20261028)
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_direction = Vector2.RIGHT
	var map: Dictionary = ArenaCatalog.definition(arena)
	if not (map["zones"] as Array).is_empty():
		var center: Array = map["zones"][0]["center"]
		var radius: Array = map["zones"][0]["radius"]
		sim.player_position = Vector2(float(center[0]) + float(radius[0]) * 0.6, float(center[1]))
	if case_name == "danger":
		var zone := CombatSim.WarningZone.new()
		zone.position = sim.player_position + Vector2(170, 0)
		zone.age = 0.6
		zone.delay = 1.5
		sim.zones.append(zone)
		var rusher: CombatSim.Enemy = sim.spawn_enemy("rusher", sim.player_position + Vector2(230, 30))
		rusher.mode = 1
		rusher.action_timer = 0.6
		rusher.charge_direction = Vector2.LEFT
	if case_name in ["dash", "cooldown", "danger"]:
		if not _app.world.request_dash():
			push_error("The real world rejected the fixture's ready skill")
			_app._quit_game(1)
			return
		for frame: int in (22 if case_name == "cooldown" else 6):
			_app.world._physics_process(STEP)
	_app.ui.update_hud(_app.world.hud_snapshot())
	var focus: Control = root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	var caption := Label.new()
	caption.text = "冲刺固定验证 · 真实Main与物理步 · 非自然对局 · 不保存档案"
	caption.position = Vector2(365, 104)
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = GameUI.GOLD
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app.ui._root.add_child(caption)
	root.title = "秘术余烬 · 冲刺验证 / %s（固定场景，不保存档案）" % case_name
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(output)
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(path)
	_print_state(_app.world.hud_snapshot())
	print("DASH_PREVIEW ", JSON.stringify({"case": case_name, "arena": arena, "fixed_fixture": true,
		"persistent_profile": _app.store.persistent, "capture_result": result, "capture": output,
		"dash": sim.dash_snapshot(), "position": [sim.player_position.x, sim.player_position.y]}))
	if not hold or result != OK:
		_app._quit_game(0 if result == OK else 1)
		return
	_app.world.hud_changed.connect(_print_state)
	if case_name == "interactive":
		_app.world.set_physics_process(true)

func _print_state(snapshot: Dictionary) -> void:
	var dash: Dictionary = snapshot.get("dash", {})
	var signature: String = JSON.stringify([dash.get("ready", false), dash.get("active", false), dash.get("uses", 0)])
	if signature == _last_state:
		return
	_last_state = signature
	print("DASH_STATE ", JSON.stringify({"dash": dash, "position": [_app.world.sim.player_position.x, _app.world.sim.player_position.y], "health": _app.run.health}))

func _invalid() -> void:
	push_error("Use native --case=ready|dash|cooldown|danger|interactive --arena=reliquary|mire|glacier|ashland [--capture=path.png] [--hold]")
	quit(2)
