extends SceneTree
## Actual first-wave pickups along a fixed policy path, then native upgrade/resume captures.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const STEP: float = 1.0 / 60.0

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var case_name: String = "choice"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		else:
			quit(2)
			return
	if case_name not in ["choice", "resumed", "vitality"] or DisplayServer.get_name() == "headless" or not destination.to_lower().ends_with(".png"):
		push_error("Use native rendering with --case=choice|resumed|vitality --capture=<path.png>.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var app = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args = PackedStringArray(["--autoplay"])
	var seed_value: int = 2030 if case_name == "vitality" else 2027
	app._begin_run("bone", seed_value)
	app.world.set_physics_process(false)
	var simulation: CombatSim = app.world.sim
	var steps: int = 0
	while app.run.pending_upgrades == 0 and not simulation.complete and steps < 2701:
		app.world._visual_time += STEP
		app.world._advance_feedback(STEP)
		simulation.step(STEP, BotPolicy.movement(simulation))
		steps += 1
	app.world.set_physics_process(true)
	for frame: int in 4:
		await process_frame
	var paused_elapsed: float = simulation.elapsed
	var paused_health: float = app.run.health
	var paused_maximum: float = app.run.stat("max_health")
	var passed: bool = app.screen == MAIN_SCRIPT.Screen.UPGRADE and paused and not app.paused and app.world.sim == simulation and not simulation.complete
	var chosen: String = ""
	if case_name == "resumed":
		var button: Button = _button(app.ui, "选择强化")
		passed = passed and button != null
		if button != null:
			var ancestor: Node = button.get_parent()
			while ancestor != null and not str(ancestor.name).begins_with("Upgrade_"):
				ancestor = ancestor.get_parent()
			chosen = str(ancestor.name).trim_prefix("Upgrade_") if ancestor != null else ""
			button.pressed.emit()
		for frame: int in 4:
			await process_frame
		await physics_frame
		await physics_frame
		await process_frame
		passed = passed and app.screen == MAIN_SCRIPT.Screen.COMBAT and not paused and app.world.sim == simulation and simulation.elapsed > paused_elapsed and app.run.pending_upgrades == 0
		app.world.set_physics_process(false)
	else:
		for frame: int in 3:
			await process_frame
		passed = passed and simulation.elapsed == paused_elapsed
		if case_name == "vitality":
			passed = passed and app.ui.find_child("Upgrade_vitality", true, false) != null
	var caption := Label.new()
	caption.text = "固定种子首波拾取验证 · 自动策略路径，非真人对局 · 不保存档案"
	caption.position = Vector2(390, 3)
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = Color("89d8d2")
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.ui._root.add_child(caption)
	root.title = "秘术余烬 · 波内升级 / %s（正式首波拾取验证，不写档案）" % case_name
	await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(destination)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var record: Dictionary = {"case": case_name, "seed": seed_value, "steps_to_first_upgrade": steps,
		"fixed_policy_path": true, "sandbox": simulation.sandbox, "extra_gold_or_xp": false,
		"persistent_profile": app.store.persistent, "viewport": [root.size.x, root.size.y],
		"wave": app.run.wave, "level": app.run.level, "pending": app.run.pending_upgrades,
		"paused_combat_elapsed": paused_elapsed, "elapsed": simulation.elapsed,
		"same_simulation": app.world.sim == simulation, "tree_paused": paused,
		"health_at_choice": paused_health, "max_health_at_choice": paused_maximum,
		"health": app.run.health, "max_health": app.run.stat("max_health"),
		"chosen_card": chosen, "capture_result": result, "fixture_passed": passed}
	print("COMBAT_UPGRADE_PREVIEW ", JSON.stringify(record))
	app._quit_game(0 if passed and result == OK else 1)

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child: Node in node.get_children():
		var found: Button = _button(child, text)
		if found != null:
			return found
	return null
