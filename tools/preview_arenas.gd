extends SceneTree
## Fixed native terrain/readability fixture; uses production rendering without profiles.

class SilentSound extends SoundBank:
	func _ready() -> void:
		pass

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var id: String = "reliquary"
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arena="):
			id = argument.trim_prefix("--arena=")
		elif argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		else:
			quit(2)
			return
	if not ArenaCatalog.IDS.has(id) or DisplayServer.get_name() == "headless":
		push_error("Use native --arena=reliquary|mire|glacier|ashland [--capture=<png>]")
		quit(2)
		return
	if output.is_empty():
		output = "res://reports/arena-%s.png" % id
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 地形固定验证（不保存档案）"
	var state := RunState.new()
	state.begin(20261026, "bone", id)
	var sound := SilentSound.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": true}
	root.add_child(world)
	world.begin(state)
	world.set_physics_process(false)
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var definition: Dictionary = ArenaCatalog.definition(id)
	if not (definition["zones"] as Array).is_empty():
		var center: Array = definition["zones"][0]["center"]
		sim.player_position = Vector2(float(center[0]), float(center[1]))
	for index: int in 4:
		var enemy: CombatSim.Enemy = sim.spawn_enemy(["chaser", "tank", "rusher", "caster"][index], Vector2(515 + index * 145, 395))
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.action_timer = 99.0
		if index >= 2:
			enemy.mode = 1
			enemy.action_timer = 0.25
			enemy.charge_direction = Vector2(-1, -0.3).normalized()
	var danger := CombatSim.WarningZone.new()
	danger.position = Vector2(1010, 235)
	danger.radius = 48
	danger.age = 0.7
	sim.zones.append(danger)
	sim._hostile_shot(Vector2(1050, 265), Vector2.ZERO, 8.0, "caster")
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_hud()
	ui.update_hud(world.hud_snapshot())
	var caption := Label.new()
	caption.text = "固定地形与危险层级验证 · 非自然对局 · 不保存档案"
	caption.position = Vector2(390, 103)
	caption.add_theme_font_size_override("font_size", 13)
	caption.modulate = GameUI.GOLD
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui._root.add_child(caption)
	var signature: String = JSON.stringify([state.summary(), str(state.rng.state), str(sim.rng.state), sim.snapshot()])
	world.queue_redraw()
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var unchanged: bool = signature == JSON.stringify([state.summary(), str(state.rng.state), str(sim.rng.state), sim.snapshot()])
	var result: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("ARENA_PREVIEW ", JSON.stringify({"arena_id": id, "fixed_fixture": true, "persistent_profile": false,
		"state_unchanged": unchanged, "viewport": [1280, 720], "hud": world.hud_snapshot(), "capture": output, "capture_result": result}))
	sound.shutdown()
	quit(0 if unchanged and result == OK else 1)
