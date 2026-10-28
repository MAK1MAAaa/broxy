extends SceneTree
## Fixed Main fixtures use real Q control and compiled-pack compatible resources.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const CASES: PackedStringArray = ["ready", "cast", "flash_off", "immune", "corner", "danger", "resumed", "interactive"]
var _app: Node
var _events: Array[Dictionary] = []

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var case_name: String = "cast"
	var output: String = "res://reports/pulse/cast.png"
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
	if _app.run.backpack.add("skill", "pulse").is_empty():
		_fail("The preview could not place its pulse skill box")
		return
	_app.run._sync_backpack_projection()
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	if case_name == "corner":
		sim.player_position = CombatSim.ARENA.position + Vector2(30, 30)
	var origin: Vector2 = sim.player_position
	sim.pulse_cast.connect(func(point: Vector2, affected: int) -> void:
		_events.append({"origin": [point.x, point.y], "affected": affected})
		print("PULSE_EVENT ", JSON.stringify(_events.back())))
	if case_name == "immune":
		var boss: CombatSim.Enemy = _enemy(sim, "boss", origin + Vector2(100, 0))
		sim.boss = boss
		var hunter: CombatSim.Enemy = _enemy(sim, "rusher", origin + Vector2(-100, 0))
		hunter.hunter = true
	else:
		_enemy(sim, "chaser", origin + Vector2(50, 0))
		_enemy(sim, "tank", origin + Vector2(0, 80))
		var rusher: CombatSim.Enemy = _enemy(sim, "rusher", origin + Vector2(-100, 0))
		if case_name != "interactive":
			rusher.mode = 1
			rusher.action_timer = 0.6
			rusher.charge_direction = Vector2.RIGHT
		_enemy(sim, "caster", origin + Vector2(145, 0))
	var before: Array[Dictionary] = _positions(sim)
	if case_name == "danger":
		var zone := CombatSim.WarningZone.new()
		zone.position = origin + Vector2(100, -70)
		zone.age = 0.7
		zone.delay = 1.5
		sim.zones.append(zone)
		sim._hostile_shot(origin + Vector2(50, -100), Vector2.ZERO, 8.0, "caster")
	if case_name == "flash_off":
		_app.world.apply_visual_settings({"flash": false, "shake": true})
	if case_name not in ["ready", "interactive"]:
		if not _app.world.request_pulse():
			_fail("The fixture's ready Q request was rejected")
			return
		_app.world._physics_process(STEP)
	if case_name == "resumed":
		var frozen: Dictionary = _app.world.pulse_feedback_snapshot()
		_app._pause()
		for frame: int in 4:
			await process_frame
		if frozen != _app.world.pulse_feedback_snapshot():
			_fail("A real pause changed pulse feedback")
			return
		_app._resume()
		_app.world._physics_process(STEP)
	var expected_casts: int = 0 if case_name in ["ready", "interactive"] else 1
	if sim.pulses_used != expected_casts or sim.run.health != 100.0 or (case_name == "immune" and sim.pulse_affected != 0):
		_fail("Actual pulse control did not match the fixture")
		return
	_app.ui.update_hud(_app.world.hud_snapshot())
	var focus: Control = root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	var caption := Label.new()
	caption.text = "秘术脉冲固定验证 · 真实Main与物理步 · 非自然对局 · 不保存档案"
	caption.position = Vector2(340, 104)
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = GameUI.GOLD
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_app.ui._root.add_child(caption)
	root.title = "秘术余烬 · 脉冲验证 / %s（固定场景，不保存档案）" % case_name
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(output)
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(path)
	print("PULSE_PREVIEW ", JSON.stringify({"case": case_name, "fixed_fixture": true, "persistent_profile": _app.store.persistent,
		"capture_result": result, "health": sim.run.health, "pulse": sim.pulse_snapshot(),
		"feedback": _app.world.pulse_feedback_snapshot(), "before": before, "after": _positions(sim), "events": _events,
		"hostiles": sim.shots.filter(func(shot: CombatSim.Shot) -> bool: return shot.active and shot.hostile).size(), "zones": sim.zones.size()}))
	if not hold or result != OK:
		_app._quit_game(0 if result == OK else 1)
		return
	if case_name == "interactive":
		_app.world.set_physics_process(true)

func _enemy(sim: CombatSim, id: String, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, CombatSim.clamp_point(point))
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _positions(sim: CombatSim) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			result.append({"uid": enemy.uid, "id": enemy.definition.id, "hunter": enemy.hunter,
				"position": [enemy.position.x, enemy.position.y], "hinder": enemy.pulse_hinder_timer, "frost": enemy.slow_timer})
	return result

func _fail(message: String) -> void:
	push_error(message)
	_app._quit_game(1)

func _invalid() -> void:
	push_error("Use native --case=ready|cast|flash_off|immune|corner|danger|resumed|interactive [--capture=path.png] [--hold]")
	quit(2)
