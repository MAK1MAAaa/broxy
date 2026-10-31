extends SceneTree
## Frozen native comparison. No Main, GameStore, persistent profile or exported baseline dependency.

const CURRENT_PAINTER = preload("res://scripts/combat/projectile_painter.gd")
const BASELINE_PATH: String = "res://.tools/projectile-before-readability.gd"
const SEED: int = 20261024
const STEP: float = 1.0 / 60.0
const FRAMES: int = 20

class SilentSoundBank:
	extends SoundBank

	func _ready() -> void:
		pass

class ComparisonWorld:
	extends CombatWorld
	var fixture_painter: RefCounted

	func _draw_friendly_shots() -> void:
		fixture_painter.call("rebuild", sim.shots)
		fixture_painter.call("draw", self)


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var variant: String = "after"
	var density: String = "sparse"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=")
		elif argument.begins_with("--density="):
			density = argument.trim_prefix("--density=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		else:
			_invalid_arguments()
			return
	if variant not in ["before", "after"] or density not in ["sparse", "dense"] or (not destination.is_empty() and not destination.to_lower().ends_with(".png")):
		_invalid_arguments()
		return
	if DisplayServer.get_name() == "headless":
		push_error("Trail readability comparison requires native rendering.")
		quit(2)
		return
	var painter_script: Script = CURRENT_PAINTER
	if variant == "before":
		if not ResourceLoader.exists(BASELINE_PATH):
			push_error("The local before snapshot is missing: %s. Save the previous Painter there without class_name, or use --variant=after. The snapshot is intentionally excluded from exports." % BASELINE_PATH)
			quit(2)
			return
		painter_script = load(BASELINE_PATH) as Script
	if painter_script == null or not painter_script.can_instantiate():
		push_error("The requested comparison Painter could not be loaded.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 尾迹对照 / %s / %s（固定场景，不写档案）" % [variant, density]
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world := ComparisonWorld.new()
	world.fixture_painter = painter_script.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": true}
	root.add_child(world)
	var state := RunState.new()
	state.begin(SEED, "bone")
	state.loadout = [
		{"id": "bone", "paid": 0, "rune": {}},
		{"id": "crescent", "paid": 0, "rune": {"id": "blast", "uid": 1}},
		{"id": "storm", "paid": 0, "rune": {"id": "pierce", "uid": 2}},
		{"id": "comet", "paid": 0, "rune": {"id": "bounce", "uid": 3}},
	]
	world.begin(state)
	world.set_physics_process(false)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	world.sim.player_position = Vector2(455, 375)
	if density == "dense":
		world.stress_mode = true
		world.sim.populate_stress()
		world.enable_rune_stress(true)
	else:
		_sparse_setup(world.sim)
	for frame: int in FRAMES:
		world._advance_feedback(STEP)
		world.sim.step(STEP, Vector2.ZERO)
		if density == "dense":
			world._maintain_stress()
	world._visual_time = 7.5
	if density == "sparse":
		_sparse_inflight(world.sim)
	_add_danger_fixture(world.sim)
	world.fixture_painter.call("rebuild", world.sim.shots)
	var stats: Dictionary = world.fixture_painter.call("get_stats")
	var passed: bool = not world.sim.complete and stats["friendly_count"] > 0
	if density == "sparse":
		passed = passed and world.sim.primary_hits > 0 and world.sim.secondary_hits > 0
	else:
		passed = passed and stats["friendly_count"] >= 600 and stats["family_counts"].size() == GameCatalog.weapons().size() * GameCatalog.runes().size()
	_overlay(variant, density, world.sim, stats)
	world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = OK
	if not destination.is_empty():
		var absolute: String = ProjectSettings.globalize_path(destination)
		result = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		if result == OK:
			result = root.get_texture().get_image().save_png(absolute)
	print("TRAIL_READABILITY_PREVIEW ", JSON.stringify({"variant": variant, "density": density,
		"seed": SEED, "frames": FRAMES, "fixed_scene": true, "persistent_profile": false,
		"manual_danger_fixture": true, "fixture_passed": passed, "capture_result": result,
		"capture": destination, "state_hash": _state_hash(world.sim),
		"endpoint_hash": _endpoint_hash(world.fixture_painter),
		"head_layout_hash": _head_layout_hash(world.fixture_painter), "projectiles": stats,
		"primary_hits": world.sim.primary_hits, "secondary_hits": world.sim.secondary_hits}))
	if not passed:
		push_error("The fixed comparison scene did not retain its expected real combat or pressure population.")
	if not destination.is_empty() or not passed:
		quit(0 if passed and result == OK else 1)


func _invalid_arguments() -> void:
	push_error("Use --variant=before|after --density=sparse|dense and optional --capture=<path.png>.")
	quit(2)


func _target(sim: CombatSim, id: String, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = 100000.0
	enemy.max_health = enemy.health
	enemy.action_timer = 9999.0
	return enemy


func _sparse_setup(sim: CombatSim) -> void:
	for entry: Array in [["tank", Vector2(705, 240)], ["tank", Vector2(785, 240)],
		["chaser", Vector2(850, 280)], ["tank", Vector2(790, 355)],
		["tank", Vector2(730, 490)], ["chaser", Vector2(850, 490)]]:
		_target(sim, str(entry[0]), entry[1])
	for entry: Array in [["crescent", "blast", Vector2(655, 240)],
		["storm", "pierce", Vector2(655, 355)], ["comet", "bounce", Vector2(655, 490)]]:
		sim.fire_weapon(str(entry[0]), str(entry[1]), entry[2], Vector2.RIGHT)


func _sparse_inflight(sim: CombatSim) -> void:
	for entry: Array in [["crescent", "blast", Vector2(560, 240)],
		["storm", "pierce", Vector2(565, 355)], ["comet", "bounce", Vector2(580, 490)],
		["bone", "pierce", Vector2(245, 240)], ["frost", "bounce", Vector2(345, 240)],
		["ember", "blast", Vector2(245, 490)], ["scatter", "", Vector2(345, 490)]]:
		sim.fire_weapon(str(entry[0]), str(entry[1]), entry[2], Vector2.RIGHT)


func _add_danger_fixture(sim: CombatSim) -> void:
	# Explicit layer fixtures added after the real steps; not natural boss attacks.
	var charge: CombatSim.Enemy = _target(sim, "rusher", Vector2(950, 545))
	charge.mode = 1
	charge.charge_direction = Vector2(-1, -0.4).normalized()
	charge.action_timer = CombatSim.RUSHER_WINDUP * 0.5
	var caster: CombatSim.Enemy = _target(sim, "caster", Vector2(1130, 535))
	caster.mode = 1
	caster.action_timer = CombatSim.CASTER_WINDUP * 0.5
	var warning := CombatSim.WarningZone.new()
	warning.position = Vector2(1040, 525)
	warning.radius = 45.0
	warning.age = 0.65
	sim.zones.append(warning)
	sim.fire_weapon("frost", "pierce", warning.position - Vector2(6, 0), Vector2.RIGHT)
	sim._hostile_shot(warning.position, Vector2.ZERO, 8.0, "caster")


func _overlay(variant: String, density: String, sim: CombatSim, stats: Dictionary) -> void:
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
	_panel(canvas, Rect2(24, 16, 1232, 112))
	_label(canvas, "友方尾迹对照 · %s / %s" % [variant, density], Vector2(48, 31), 30, GameUI.BONE)
	_label(canvas, "固定种子 %d · 正式推进 %d 步 · 无档案读写" % [SEED, FRAMES], Vector2(48, 82), 16, GameUI.MUTED)
	_label(canvas, "敌人 %d / 友弹 %d / 家族 %d" % [sim.enemy_count, stats["friendly_count"], stats["family_counts"].size()], Vector2(780, 85), 16, GameUI.GOLD)
	_panel(canvas, Rect2(24, 616, 1232, 86))
	_label(canvas, "固定陈列，非自然对局；%d 次直接命中 / %d 次追加命中。" % [sim.primary_hits, sim.secondary_hits], Vector2(48, 632), 16, GameUI.BONE)
	_label(canvas, "右下额外叠加冲锋/施法/范围预警、友方霜矛与真实敌弹对象，用于核对危险层；不是自然Boss攻击。", Vector2(48, 668), 14, GameUI.MUTED)


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


func _label(parent: Control, text: String, point: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


func _state_hash(sim: CombatSim) -> String:
	var result: Array = [sim.rng.state, sim.run.rng.state, sim.run.summary(), sim.snapshot(),
		sim.primary_hits, sim.secondary_hits, sim.damage_by_weapon, sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			result.append([shot.slot, shot.source, shot.hostile, shot.position, shot.previous, shot.velocity,
				shot.damage, shot.radius, shot.life, shot.rune, shot.remaining, shot.innate_remaining, shot.hit_ids])
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			result.append([enemy.uid, enemy.definition.id, enemy.position, enemy.health, enemy.age,
				enemy.action_timer, enemy.mode, enemy.hurt_timer, enemy.slow_timer])
	return JSON.stringify(result).sha256_text()


func _endpoint_hash(painter: RefCounted) -> String:
	var result: Dictionary = {}
	for key: String in painter.get("trails"):
		var trail = painter.get("trails")[key]
		result[key] = [trail.points, trail.wings]
	return JSON.stringify(result).sha256_text()


func _head_layout_hash(painter: RefCounted) -> String:
	var has_heads: bool = false
	var has_global_heads: bool = false
	for property: Dictionary in painter.get_property_list():
		if property["name"] == "heads":
			has_heads = true
		elif property["name"] == "head_multimesh":
			has_global_heads = true
	if not has_heads:
		return ""
	var heads: Dictionary = painter.get("heads")
	var result: Dictionary = {}
	if has_global_heads:
		var multimesh: MultiMesh = painter.get("head_multimesh")
		var buffer: PackedFloat32Array = painter.get("head_buffer")
		result["physical"] = [multimesh.instance_count, multimesh.visible_instance_count,
			multimesh.use_colors, multimesh.use_custom_data, buffer, multimesh.buffer,
			multimesh.mesh.surface_get_arrays(0)]
		for key: String in heads:
			var head = heads[key]
			result[key] = [head.source, head.frame, head.base_radius, head.cursor, head.start, head.capacity,
				buffer.slice(head.start * CURRENT_PAINTER.HEAD_INSTANCE_STRIDE,
					(head.start + head.cursor) * CURRENT_PAINTER.HEAD_INSTANCE_STRIDE)]
		return JSON.stringify(result).sha256_text()
	for key: String in heads:
		var head = heads[key]
		var visible: int = head.multimesh.visible_instance_count
		result[key] = [head.source, head.frame, head.base_radius, visible,
			head.buffer.slice(0, visible * CURRENT_PAINTER.INSTANCE_STRIDE)]
	return JSON.stringify(result).sha256_text()
