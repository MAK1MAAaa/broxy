extends SceneTree
## Native art/HUD fixture. No GameStore/Main and no player-profile reads or writes.

const STEP: float = 1.0 / 60.0
const FRAMES: int = 42

class SilentSoundBank:
	extends SoundBank
	func _ready() -> void:
		pass

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "windup"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--output=res://reports/") and argument.ends_with(".png"):
			destination = argument.trim_prefix("--output=")
		else:
			push_error("Use --view=windup|boss and optional --output=res://reports/<name>.png")
			quit(2)
			return
	if view not in ["windup", "boss"] or DisplayServer.get_name() == "headless":
		push_error("Threat preview requires native rendering and a supported view")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 敌方预警验证（固定场景，非实际对局）"
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": false}
	root.add_child(world)
	var state := RunState.new()
	state.begin(20261022, "bone")
	if view == "boss":
		state.wave = 8
	world.begin(state)
	world.set_physics_process(false)
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim.player_position = Vector2(106, 555)
	sim._cooldowns.fill(9999.0)
	var expected: Array[CombatSim.Enemy] = []
	for index: int in 3:
		var progress: float = [0.1, 0.5, 0.9][index]
		var x: float = 240.0 + float(index) * 400.0
		var charge: CombatSim.Enemy = _target(sim, "rusher", Vector2(x, 300))
		charge.action_timer = FRAMES * STEP - CombatSim.RUSHER_WINDUP * progress
		expected.append(charge)
		var cast: CombatSim.Enemy = _target(sim, "caster", Vector2(x, 470))
		cast.action_timer = FRAMES * STEP + CombatSim.CASTER_WINDUP * (1.0 - progress)
		expected.append(cast)
	for frame: int in FRAMES:
		sim.step(STEP, Vector2.ZERO)
		world._visual_time += STEP
	var passed: bool = not sim.complete and sim.primary_hits == 0 and sim.secondary_hits == 0
	for enemy: CombatSim.Enemy in expected:
		passed = passed and enemy.active and enemy.mode == 1 and enemy.action_timer > 0.0
	# Explicitly labelled layer fixture: an actual hostile-round object overlaps a cast ring.
	sim._hostile_shot(Vector2(640, 436), Vector2.ZERO, 8.0, "caster")
	sim.add_effect(Vector2(640, 456), Color("c7a9e1"), 70.0, 0.35)
	if view == "boss":
		sim.elapsed = 81.0
		var ui := GameUI.new()
		root.add_child(ui)
		ui.bind(state)
		ui.show_hud()
		ui.update_hud(sim.snapshot())
		var notice := Label.new()
		notice.text = "固定验证场景 · 非实际对局"
		notice.position = Vector2(925, 106)
		notice.add_theme_font_size_override("font_size", 15)
		notice.add_theme_color_override("font_color", GameUI.GOLD)
		notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui._root.add_child(notice)
	else:
		_overlay()
	world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	world._enemy_telegraphs.rebuild(sim.enemies)
	var stats: Dictionary = world._enemy_telegraphs.get_stats()
	passed = passed and stats["charge_count"] == 3 and stats["cast_count"] == 3
	if destination.is_empty():
		destination = "res://reports/" + ("boss-deadline.png" if view == "boss" else "threat-showcase.png")
	var result: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(destination))
	print("THREAT_PREVIEW view=",view," frames=",FRAMES," fixture_passed=",passed,
		" result=",result," stats=",JSON.stringify(stats)," persistent=false")
	sound.shutdown()
	quit(0 if passed and result == OK else 1)

func _target(sim: CombatSim, id: String, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	return enemy

func _overlay() -> void:
	var ui := GameUI.new()
	root.add_child(ui)
	_panel(ui._root, Rect2(24, 16, 1232, 112))
	_label(ui._root, "冲锋与施法 · 蓄力辨识", Vector2(48, 31), 30, GameUI.BONE)
	_label(ui._root, "固定验证场景，非实际对局", Vector2(793, 39), 20, GameUI.GOLD)
	_label(ui._root, "双轨箭头表示方向；施法环逐渐闭合。危险提示保持在友方法术之上。", Vector2(48, 83), 16, GameUI.MUTED)
	for index: int in 3:
		var x: float = 140.0 + float(index) * 400.0
		_label(ui._root, ["01  开始蓄力", "02  蓄力中段", "03  即将发动"][index], Vector2(x, 187), 23, GameUI.GOLD)
		_label(ui._root, "裂颅犬 · 冲锋方向", Vector2(x, 226), 16, GameUI.CORAL)
		_label(ui._root, "盲眼祭司 · 施法蓄力", Vector2(x, 514), 16, GameUI.CORAL)
	_panel(ui._root, Rect2(24, 616, 1232, 86))
	_label(ui._root, "正式 step 推进42步 · 静止目标 · 三组不同计时 · 停止时序后拍摄", Vector2(48, 631), 16, GameUI.BONE)
	_label(ui._root, "短箭头不表示完整碰撞范围；中央叠加敌弹与友方特效，用于层级检查。无存档读写。", Vector2(48, 665), 14, GameUI.MUTED)

func _panel(parent: Control, rect: Rect2) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111722")
	style.border_color = GameUI.GOLD
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

func _label(parent: Control, text: String, point: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
