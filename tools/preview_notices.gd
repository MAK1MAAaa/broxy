extends SceneTree
## Frozen real World/UI rendering at the playable top edge; no Main or profile IO.

class SilentSoundBank:
	extends SoundBank
	func _ready() -> void:
		pass

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "edge"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		else:
			push_error("Use --view=edge|boss|long and optional --capture=path")
			quit(2)
			return
	if view not in ["edge", "boss", "long"] or DisplayServer.get_name() == "headless":
		push_error("Notice preview requires native rendering and a supported view")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 简洁HUD验证（固定场景，非实际对局）"
	var state := RunState.new()
	state.begin(20261022, "bone")
	if view == "boss":
		state.wave = 8
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": false}
	root.add_child(world)
	world.begin(state)
	world.set_physics_process(false)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	# The position is a documented layout fixture, not an accelerated completed wave.
	world.sim.player_position = CombatSim.clamp_point(Vector2(640 if view == "boss" else 300, CombatSim.ARENA.position.y), 16.0)
	if world.sim.boss != null:
		world.sim.boss.position = Vector2(1030, 360)
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_hud()
	ui.update_hud(world.hud_snapshot())
	var before: String = JSON.stringify([state.summary(), str(state.rng.state), str(world.sim.rng.state), world.sim.snapshot()])
	ui.notify("移动躲避 · 法器自动攻击 · 收集魂屑，波间改装" if view != "long" else "这是一段很长的战斗提示。".repeat(40) + "\n另一行不应撑大通知或遮挡角色。")
	world.queue_redraw()
	var caption := Label.new()
	caption.text = "固定简洁HUD验证 · 角色位于上边界 · 非实际对局 · " + view
	caption.position = Vector2(24, 0)
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", GameUI.MUTED)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui._root.add_child(caption)
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	if destination.is_empty():
		destination = "res://reports/notice-" + view + ".png"
	var result: Error = root.get_texture().get_image().save_png(destination)
	var boss: Rect2 = ui._hud["boss"].get_global_rect()
	var unchanged: bool = before == JSON.stringify([state.summary(), str(state.rng.state), str(world.sim.rng.state), world.sim.snapshot()])
	var clean_hud: bool = not ui._toast.visible and ui._toast.text.is_empty() and ui._toast_timer.is_stopped() and ui.find_child("HUDMapInfo", true, false) == null and not ui._hud.has("bag_info")
	var boss_correct: bool = (world.sim.boss != null) == bool(ui._hud["boss"].visible)
	print("NOTICE_PREVIEW ", JSON.stringify({"view": view, "result": result, "notice_visible": ui._toast.visible,
		"notice_text_empty": ui._toast.text.is_empty(), "notice_timer_stopped": ui._toast_timer.is_stopped(),
		"right_corner_copy_absent": ui.find_child("HUDMapInfo", true, false) == null and not ui._hud.has("bag_info"),
		"clean_hud": clean_hud, "state_unchanged": unchanged,
		"boss": [boss.position.x, boss.position.y, boss.size.x, boss.size.y], "boss_visible": ui._hud["boss"].visible,
		"boss_correct": boss_correct, "player": [world.sim.player_position.x, world.sim.player_position.y], "persistent": false}))
	sound.shutdown()
	quit(0 if result == OK and clean_hud and unchanged and boss_correct else 1)
