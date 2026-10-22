extends SceneTree
## Frozen native-rendering fixture; no Main/GameStore, profile access or direct FX emission.

const STEP: float = 1.0 / 60.0
const FRAMES: int = 52
const TARGET_HEALTH: float = 10000.0

class SilentSoundBank:
	extends SoundBank

	func _ready() -> void:
		pass


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var destination: String = "res://reports/rune-showcase.png"
	var hold: bool = false
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var argument_index: int = 0
	while argument_index < arguments.size():
		var argument: String = arguments[argument_index]
		if argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--capture":
			if argument_index + 1 < arguments.size() and not arguments[argument_index + 1].begins_with("--"):
				argument_index += 1
				destination = arguments[argument_index]
		elif argument == "--hold":
			hold = true
		else:
			push_error("Unknown rune-preview argument: " + argument)
			quit(2)
			return
		argument_index += 1
	if destination.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Rune capture needs a native rendering window and a nonempty capture path.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 符文命中验证（固定场景，非实际通关）"
	var sound: SoundBank = SilentSoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": true}
	root.add_child(world)
	world.set_physics_process(false)
	var state := RunState.new()
	state.begin(20261022, "bone")
	state.loadout = [
		{"id": "bone", "paid": 0, "rune": {"id": "pierce", "uid": 1}},
		{"id": "frost", "paid": 0, "rune": {"id": "bounce", "uid": 2}},
		{"id": "ember", "paid": 0, "rune": {"id": "blast", "uid": 3}},
	]
	world.begin(state)
	world.set_physics_process(false)
	world._visual_time = 6.0
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(640, 545)
	var pierce_targets: Array[CombatSim.Enemy] = []
	for point: Vector2 in [Vector2(200, 340), Vector2(260, 340), Vector2(320, 340)]:
		pierce_targets.append(_target(sim, point))
	var bounce_first: CombatSim.Enemy = _target(sim, Vector2(670, 340))
	_target(sim, Vector2(580, 410))
	var blast_targets: Array[CombatSim.Enemy] = []
	for point: Vector2 in [Vector2(1030, 350), Vector2(1070, 325), Vector2(1065, 380)]:
		blast_targets.append(_target(sim, point))
	var rune_events: Dictionary = {"pierce": 0, "bounce": 0, "blast": 0}
	sim.rune_activated.connect(func(rune_id: String, _origin: Vector2, _incoming: Vector2, _outgoing: Vector2) -> void:
		rune_events[rune_id] = int(rune_events.get(rune_id, 0)) + 1
	)
	var bounce_shot: CombatSim.Shot
	# Stagger launches so the capture shows the last pierce, real bounce corner and blast together.
	# The frost shot is photographed during its return flight, before the second target is hit.
	for frame: int in FRAMES:
		world._advance_feedback(STEP)
		if frame == 24:
			sim.fire_weapon("bone", "pierce", Vector2(110, 340), Vector2.RIGHT)
			bounce_shot = sim.fire_weapon("frost", "bounce", Vector2(500, 340), Vector2.RIGHT)
		elif frame == 28:
			sim.fire_weapon("ember", "blast", Vector2(900, 350), Vector2.RIGHT)
		sim.step(STEP, Vector2.ZERO)
		world._visual_time += STEP
	var passed: bool = true
	for enemy: CombatSim.Enemy in pierce_targets:
		passed = passed and enemy.health < TARGET_HEALTH
	for enemy: CombatSim.Enemy in blast_targets:
		passed = passed and enemy.health < TARGET_HEALTH
	passed = passed and bounce_first.health < TARGET_HEALTH
	passed = passed and bounce_shot != null and bounce_shot.active and bounce_shot.velocity.x < 0.0
	for rune_id: String in rune_events:
		passed = passed and int(rune_events[rune_id]) > 0
	if not passed:
		push_error("Rune fixture did not reach its expected real collision/turn states.")
	# This warning is a labelled layer fixture; no hostile damage is injected into the frozen sample.
	var warning := CombatSim.WarningZone.new()
	warning.position = Vector2(1060, 375)
	warning.age = 0.65
	sim.zones.append(warning)
	_overlay(sim.primary_hits, sim.secondary_hits)
	world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(destination)
	if not absolute.is_absolute_path():
		absolute = ProjectSettings.globalize_path("res://" + destination)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	print("RUNE_PREVIEW ", absolute, " result=", result, " fixture_passed=", passed,
		" primary_hits=", sim.primary_hits, " secondary_hits=", sim.secondary_hits,
		" rune_events=", JSON.stringify(rune_events))
	if not hold:
		sound.shutdown()
		quit(0 if passed and result == OK else 1)


func _target(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
	# Duplicate the resource so frozen targets never modify the shared shipped enemy definition.
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = TARGET_HEALTH
	enemy.max_health = TARGET_HEALTH
	enemy.action_timer = 9999.0
	return enemy


func _overlay(primary_hits: int, secondary_hits: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	var canvas := Control.new()
	canvas.size = Vector2(1280, 720)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Arial"])
	theme.default_font = font
	canvas.theme = theme
	layer.add_child(canvas)
	_panel(canvas, Rect2(24, 16, 1232, 112))
	_label(canvas, "符文命中表现", Vector2(48, 30), 550, 28, Color("e7dcc0"))
	_label(canvas, "固定验证场景，非实际通关", Vector2(765, 38), 460, 20, Color("c5ad7d"))
	_label(canvas, "正式 fire_weapon / step 驱动 · 三组独立目标 · 冻结同一采样帧", Vector2(49, 82), 1120, 15, Color("a9abb7"))
	var colors: Array[Color] = [Color("b8d6b2"), Color("9ec5dc"), Color("dfbc87")]
	var titles: Array[String] = ["01  骨针 × 贯穿", "02  霜矛 × 弹射", "03  幽焰 × 爆破"]
	var details: Array[String] = ["横线三敌 · 每敌仅命中一次", "两敌折返 · 正在飞向第二目标", "聚堆范围 · 次级伤害不递归"]
	for index: int in 3:
		var left: float = 88.0 + float(index) * 383.0
		_label(canvas, titles[index], Vector2(left, 179), 330, 23, colors[index])
		_label(canvas, details[index], Vector2(left, 459), 330, 15, colors[index])
	for x: float in [437.0, 823.0]:
		var divider := ColorRect.new()
		divider.position = Vector2(x, 172)
		divider.size = Vector2(1, 326)
		divider.color = Color(0.68, 0.62, 0.49, 0.22)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(divider)
	_panel(canvas, Rect2(24, 616, 1232, 86))
	_label(canvas, "固定 %d 步 · 实际主命中 %d / 范围命中 %d · 禁自动发射、刷怪 · 高生命静止目标" % [FRAMES, primary_hits, secondary_hits], Vector2(48, 629), 1180, 15, Color("d2c7ad"))
	_label(canvas, "珊瑚危险预警覆盖友方符文特效，用于核对层级；本工具无个人存档读写。", Vector2(48, 662), 1180, 14, Color("a9abb7"))


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
	label.size = Vector2(width, 45)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
