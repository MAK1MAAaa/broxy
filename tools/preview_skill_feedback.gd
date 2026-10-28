extends SceneTree
## Fixed Main scenes expose real cast results without accessing a personal profile.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const CASES: PackedStringArray = ["hit", "empty", "flash_off", "danger", "hurt", "corner"]
var _app: Node
var _events: Array[Dictionary] = []

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var case_name: String = "hit"
	var output: String = "res://reports/skill-feedback/hit.png"
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
	sim.player_position = Vector2(580, 350)
	sim.player_direction = Vector2.RIGHT
	if case_name == "corner":
		sim.player_position = CombatSim.ARENA.end - Vector2(18, 18)
	var origin: Vector2 = sim.player_position
	sim.pulse_cast.connect(func(point: Vector2, affected: int) -> void:
		_events.append({"origin": [point.x, point.y], "affected": affected})
		print("SKILL_FEEDBACK_EVENT ", JSON.stringify(_events.back())))
	if case_name != "empty":
		var facing: float = -1.0 if case_name == "corner" else 1.0
		_enemy(sim, "chaser", origin + Vector2(75 * facing, 0))
		_enemy(sim, "tank", origin + Vector2(0, -95))
		var frost: CombatSim.Enemy = _enemy(sim, "chaser", origin + Vector2(100 * facing, -70))
		frost.slow_timer = 0.8
		_enemy(sim, "caster", origin + Vector2(170 * facing, -20))
	if case_name == "danger":
		var zone := CombatSim.WarningZone.new()
		zone.position = origin + Vector2(75, 50)
		zone.age = 0.7
		zone.delay = 1.5
		sim.zones.append(zone)
		sim._hostile_shot(origin + Vector2(7, 47), Vector2.ZERO, 8.0, "caster")
	if case_name == "flash_off":
		_app.world.apply_visual_settings({"flash": false, "shake": true})
	var before: Array[Dictionary] = _positions(sim)
	if not _app.world.request_pulse():
		_fail("The fixture's ready pulse request was rejected")
		return
	_app.world._physics_process(STEP)
	if case_name == "hurt":
		sim._hostile_shot(sim.player_position, Vector2.ZERO, 8.0, "caster")
		_app.world._physics_process(STEP)
	var feedback: Dictionary = _app.world.skill_feedback_snapshot()
	var expected_affected: int = 0 if case_name == "empty" else 3
	var expected_health: float = 92.0 if case_name == "hurt" else 100.0
	if sim.pulses_used != 1 or sim.pulse_affected != expected_affected or sim.run.health != expected_health or bool(feedback["active"]) != (case_name != "hurt"):
		_fail("Actual pulse result or incoming-loss priority did not match the fixture")
		return
	var focus: Control = root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	var caption := Label.new()
	caption.text = "技能反馈固定验证 · 真实受控与承伤 · 非自然对局 · 不保存档案"
	caption.position = Vector2(340, 104)
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = GameUI.GOLD
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app.ui._root.add_child(caption)
	root.title = "秘术余烬 · 技能反馈验证 / %s（固定场景，不保存档案）" % case_name
	_app.ui.update_hud(_app.world.hud_snapshot())
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(output)
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(path)
	print("SKILL_FEEDBACK_PREVIEW ", JSON.stringify({"case": case_name, "fixed_fixture": true,
		"persistent_profile": _app.store.persistent, "capture_result": result, "capture": output,
		"health": sim.run.health, "hits_taken": sim.run.hits_taken, "last_hit": sim.run.last_hit,
		"pulse": sim.pulse_snapshot(), "feedback": feedback, "range": _app.world.pulse_feedback_snapshot(),
		"before": before, "after": _positions(sim), "events": _events,
		"hostiles": sim.shots.filter(func(shot: CombatSim.Shot) -> bool: return shot.active and shot.hostile).size(),
		"zones": sim.zones.size(), "flash": bool(_app.world.settings.get("flash", true))}))
	if not hold or result != OK:
		_app._quit_game(0 if result == OK else 1)

func _enemy(sim: CombatSim, id: String, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, CombatSim.clamp_point(point))
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _positions(sim: CombatSim) -> Array[Dictionary]:
	var positions: Array[Dictionary] = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			positions.append({"uid": enemy.uid, "id": enemy.definition.id, "position": [enemy.position.x, enemy.position.y],
				"hinder": enemy.pulse_hinder_timer, "frost": enemy.slow_timer, "health": enemy.health})
	return positions

func _fail(message: String) -> void:
	push_error(message)
	_app._quit_game(1)

func _invalid() -> void:
	push_error("Use native --case=hit|empty|flash_off|danger|hurt|corner [--capture=path.png] [--hold]")
	quit(2)
