extends SceneTree
## Fixed legal mid-wave build; only the before variant loads the local snapshot.

const FIXTURE = preload("res://tests/test_player_foreground.gd")

class SilentSoundBank extends SoundBank:
	func _ready() -> void:
		pass


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var variant: String = "after"
	var case_name: String = "blast"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=")
		elif argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		else:
			_invalid_arguments()
			return
	if variant not in ["before", "after"] or case_name not in FIXTURE.CASES or (not destination.is_empty() and not destination.to_lower().ends_with(".png")):
		_invalid_arguments()
		return
	if DisplayServer.get_name() == "headless":
		push_error("Player foreground preview requires native rendering.")
		quit(2)
		return
	var script: Script = load("res://scripts/combat/combat_world.gd")
	if variant == "before":
		var baseline: String = "res://.tools/world-before-foreground.gd"
		if not FileAccess.file_exists(baseline):
			push_error("Missing local before snapshot: .tools/world-before-foreground.gd; create the frozen classless World before comparison.")
			quit(2)
			return
		script = load(baseline)
	if script == null or not script.can_instantiate():
		push_error("The selected foreground renderer cannot be instantiated.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 玩家前景 / %s / %s（固定第六波构筑，不写档案）" % [variant, case_name]
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world = script.new()
	world.sound = sound
	root.add_child(world)
	var record: Dictionary = FIXTURE.prepare(world, case_name)
	var before: String = FIXTURE.state_hash(world)
	var feedback: String = FIXTURE.feedback_hash(world)
	_overlay(variant, case_name, record)
	world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var unchanged: bool = before == FIXTURE.state_hash(world) and feedback == FIXTURE.feedback_hash(world)
	var result: Error = OK
	if not destination.is_empty():
		var absolute: String = ProjectSettings.globalize_path(destination)
		result = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		if result == OK:
			result = root.get_texture().get_image().save_png(absolute)
	record.merge({"variant": variant, "case": case_name, "fixed_fixture": true,
		"persistent_profile": false, "visual_revision": "legacy-player-order" if variant == "before" else CombatWorld.PLAYER_FOREGROUND_VISUAL_REVISION,
		"state_hash": before, "feedback_hash": feedback, "draw_read_only": unchanged,
		"sim_rng": str(world.sim.rng.state), "run_rng": str(world.sim.run.rng.state),
		"health": world.sim.run.health, "invulnerability": world.sim.invulnerability,
		"effects": world.sim.effects.size(), "numbers": world._numbers.size(),
		"impact_budget": world._impact_painter.get_stats(), "projectile_budget": world._projectile_painter.get_stats(),
		"capture": destination, "capture_result": result}, true)
	print("PLAYER_FOREGROUND_PREVIEW ", JSON.stringify(record))
	if not bool(record["passed"]) or not unchanged or result != OK:
		push_error("The player foreground fixture did not retain real feedback or read-only drawing.")
		quit(1)
	elif not destination.is_empty():
		quit(0)


func _invalid_arguments() -> void:
	push_error("Use --variant=before|after --case=blast|hurt|flash_off|danger and optional --capture=<path.png>.")
	quit(2)


func _overlay(variant: String, case_name: String, record: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = GameUI.create_ui_font()
	canvas.theme = theme
	layer.add_child(canvas)
	_panel(canvas, Rect2(24, 16, 1232, 110))
	_label(canvas, "玩家前景对照 · %s / %s" % [variant, case_name], Vector2(48, 28), 28, GameUI.BONE)
	_label(canvas, "固定种子 %d · 第6波合法四法器/四符文 · 正式fire/step %d步 · 不写档案" % [FIXTURE.SEED, FIXTURE.FRAMES], Vector2(48, 76), 15, GameUI.MUTED)
	_panel(canvas, Rect2(24, 615, 1232, 88))
	_label(canvas, "固定验证，非自然关卡 · 直接命中%d / 追加命中%d · 测试预算1200魂屑，经正式购买装配" % [record["primary_hits"], record["secondary_hits"]], Vector2(48, 629), 16, GameUI.BONE)
	var note: String = "真实近身爆破与普通第六波敌人数值；不使用300敌人压力维持，不改伤害、半径或寿命。"
	if case_name == "danger":
		note = "角色面前另放真实敌弹对象与范围预警，专查最高层级；手工叠层，不是自然Boss攻击。"
	elif case_name == "flash_off":
		note = "关闭闪光的真实承伤；保留伤害数字，角色保持不透明，关闭方向闪光和普通命中刻痕。"
	elif case_name == "hurt":
		note = "真实接触承伤，冻结于原有无敌闪烁最低透明度0.25；该闪烁规则保持。"
	_label(canvas, note, Vector2(48, 670), 14, GameUI.MUTED)


func _panel(parent: Control, rectangle: Rect2) -> void:
	var panel := Panel.new()
	panel.position = rectangle.position
	panel.size = rectangle.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111722")
	style.border_color = Color("6e654f")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)


func _label(parent: Control, value: String, point: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
