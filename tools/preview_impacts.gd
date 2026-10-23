extends SceneTree
## Native fixed-step collision fixture. No Main, GameStore, direct damage or FX injection.

const STEP: float = 1.0 / 60.0
const FRAMES: int = 7
const TARGET_HEALTH: float = 10000.0
const SOURCES: Array[String] = ["bone", "frost", "ember", "scatter"]
const COLUMNS: Array[float] = [260.0, 500.0, 740.0, 980.0]
const ROWS: Array[float] = [260.0, 380.0, 500.0]

class SilentSoundBank:
	extends SoundBank

	func _ready() -> void:
		pass


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var destination: String = "res://reports/impact-showcase.png"
	var age_shift: float = 0.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output=res://reports/") and argument.ends_with(".png"):
			destination = argument.trim_prefix("--output=")
		elif argument.begins_with("--age-shift="):
			var value: String = argument.trim_prefix("--age-shift=")
			if value not in ["0", ".05", "0.05", ".12", "0.12"]:
				_invalid_arguments()
				return
			age_shift = value.to_float()
		else:
			_invalid_arguments()
			return
	if DisplayServer.get_name() == "headless":
		push_error("Impact preview requires native rendering.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 普通命中验证（固定场景，非普通对局）"
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": true}
	root.add_child(world)
	var state := RunState.new()
	state.begin(20261022, "bone")
	world.begin(state)
	world.set_physics_process(false)
	world._visual_time = 6.0
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(1180, 568)
	var targets: Array[CombatSim.Enemy] = []
	for row: int in ROWS.size():
		for column: int in COLUMNS.size():
			targets.append(_target(sim, Vector2(COLUMNS[column], ROWS[row])))
	var primary_receipts: Dictionary = {}
	var source_hits: Dictionary = {}
	sim.damage_dealt.connect(func(_point: Vector2, amount: float, source: String, secondary: bool, target_uid: int) -> void:
		if amount > 0.0 and not secondary:
			primary_receipts[target_uid] = int(primary_receipts.get(target_uid, 0)) + 1
			source_hits[source] = int(source_hits.get(source, 0)) + 1
	)
	# Advance feedback before stepping, exactly as CombatWorld's live physics loop does.
	# Oldest row fires at 0, middle at 3 and newest at 6; all collide in their launch step.
	for frame: int in FRAMES:
		world._advance_feedback(STEP)
		if frame in [0, 3, 6]:
			var row: int = 2 - int(frame / 3)
			for column: int in SOURCES.size():
				_launch(sim, targets[row * COLUMNS.size() + column], SOURCES[column])
		sim.step(STEP, Vector2.ZERO)
		world._visual_time += STEP
	# This optional phase advances existing feedback only: no extra step or fabricated hit.
	if age_shift > 0.0:
		world._advance_feedback(age_shift)
	var expected_primary: int = 0
	for source: String in SOURCES:
		expected_primary += GameCatalog.weapon(source).shots * ROWS.size()
	var passed: bool = not sim.complete and sim.primary_hits == expected_primary and sim.secondary_hits == 0
	var target_results: Array[Dictionary] = []
	for index: int in targets.size():
		var enemy: CombatSim.Enemy = targets[index]
		var actual_hits: int = int(primary_receipts.get(enemy.uid, 0))
		passed = passed and enemy.active and enemy.health < TARGET_HEALTH and actual_hits > 0
		target_results.append({"uid": enemy.uid, "source": SOURCES[index % SOURCES.size()],
			"row": int(index / SOURCES.size()), "primary_hits": actual_hits, "health_lost": TARGET_HEALTH - enemy.health})
	if not passed:
		push_error("Impact fixture did not damage all twelve targets through real primary collisions.")
	# Labelled layer fixture, deliberately added after stepping; not a natural boss attack.
	var warning := CombatSim.WarningZone.new()
	warning.position = Vector2(COLUMNS[3], ROWS[2])
	warning.radius = 36.0
	warning.age = 0.65
	sim.zones.append(warning)
	sim._hostile_shot(warning.position + Vector2(3, 0), Vector2.ZERO, 8.0, "caster")
	_overlay(sim.primary_hits, sim.secondary_hits, age_shift)
	world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(destination)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var impact_stats: Dictionary = _impact_stats(world)
	print("IMPACT_PREVIEW output=", absolute, " result=", result, " fixture_passed=", passed,
		" frames=", FRAMES, " age_shift=", age_shift, " primary_hits=", sim.primary_hits,
		" secondary_hits=", sim.secondary_hits, " source_hits=", JSON.stringify(source_hits),
		" targets=", JSON.stringify(target_results), " impact=", JSON.stringify(impact_stats),
		" rng_state=", sim.rng.state, " persistent=false layer_fixture=true")
	sound.shutdown()
	quit(0 if passed and result == OK else 1)


func _invalid_arguments() -> void:
	push_error("Use optional --output=res://reports/<name>.png and --age-shift=0|.05|.12")
	quit(2)


func _target(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = TARGET_HEALTH
	enemy.max_health = TARGET_HEALTH
	enemy.action_timer = 9999.0
	return enemy


func _launch(sim: CombatSim, target: CombatSim.Enemy, source: String) -> void:
	var definition: ContentDef = GameCatalog.weapon(source)
	# Begin one pixel outside the formal sum of collision radii. Actual weapon speed
	# and spread bring every projectile into its own target on the following step.
	var clearance: float = target.radius + definition.projectile_radius + 1.0
	var point: Vector2 = target.position - Vector2(clearance, 0)
	for pellet: int in definition.shots:
		var angle: float = (float(pellet) - float(definition.shots - 1) * 0.5) * definition.spread
		sim.fire_weapon(source, "", point, Vector2.from_angle(angle))


func _impact_stats(world: CombatWorld) -> Dictionary:
	# The identical fixture is valid against the old world, before the helper exists.
	for property: Dictionary in world.get_property_list():
		if str(property.get("name", "")) != "_impact_painter":
			continue
		var painter: Variant = world.get("_impact_painter")
		if painter is Object and painter.has_method("get_stats"):
			var stats: Dictionary = painter.call("get_stats")
			stats["available"] = true
			return stats
	return {"available": false}


func _overlay(primary_hits: int, secondary_hits: int, age_shift: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	var canvas := Control.new()
	canvas.size = Vector2(1280, 720)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = GameUI.create_ui_font()
	canvas.theme = theme
	layer.add_child(canvas)
	_panel(canvas, Rect2(24, 16, 1232, 112))
	_label(canvas, "普通法器 · 真实命中刻痕", Vector2(48, 31), 700, 29, Color("f0e5cc"))
	_label(canvas, "固定场景，非普通对局", Vector2(864, 40), 360, 19, Color("c4a76f"))
	_label(canvas, "正式 fire_weapon + step 碰撞 · 高生命静止目标 · 不改伤害/发射参数", Vector2(49, 84), 1160, 15, Color("aaa4b3"))
	for column: int in SOURCES.size():
		var definition: ContentDef = GameCatalog.weapon(SOURCES[column])
		_label(canvas, definition.display_name, Vector2(COLUMNS[column] - 65, 167), 170, 23, definition.color)
	for row: int in ROWS.size():
		var age: float = float(row) * 3.0 * STEP + age_shift
		_label(canvas, "刚命中" if is_zero_approx(age) else "%.2f 秒" % age, Vector2(76, ROWS[row] - 10), 110, 16, Color("c4a76f"))
	_panel(canvas, Rect2(24, 616, 1232, 86))
	_label(canvas, "固定7步 · 主命中%d / 次级命中%d · 散魂按正式三发扇面命中同一UID" % [primary_hits, secondary_hits], Vector2(48, 630), 1160, 15, Color("f0e5cc"))
	_label(canvas, "右下叠加预警与真实敌弹对象核对层级，非自然Boss攻击；年龄偏移仅推进既有反馈，无存档读写。", Vector2(48, 665), 1180, 14, Color("aaa4b3"))


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


func _label(parent: Control, text: String, point: Vector2, width: float, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.size = Vector2(width, 42)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
