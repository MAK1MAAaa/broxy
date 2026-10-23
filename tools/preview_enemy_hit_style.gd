extends SceneTree
## Native fixed-step hit-color comparison; no Main, GameStore or profile I/O.

const SEED: int = 20261025
const STEP: float = 1.0 / 60.0
const IDS: PackedStringArray = ["chaser", "rusher", "tank", "caster", "boss"]
const COLUMNS: PackedFloat32Array = [120.0, 365.0, 610.0, 855.0, 1100.0]
const ROWS: PackedFloat32Array = [235.0, 385.0, 535.0]
const FIRE_FRAMES: PackedInt32Array = [7, 5, 0]

class SilentSoundBank:
	extends SoundBank

	func _ready() -> void:
		pass

class LegacyTintWorld:
	extends CombatWorld

	func _enemy_tint(enemy: CombatSim.Enemy) -> Color:
		var tint: Color = Color("b4e9ed") if enemy.slow_timer > 0.0 else Color.WHITE
		if enemy.hurt_timer > 0.0 and bool(settings.get("flash", true)):
			tint = Color(1.7, 1.5, 1.5, 1.0)
		return tint


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var variant: String = "after"
	var view: String = "normal"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=")
		elif argument.begins_with("--case="):
			view = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		else:
			_invalid_arguments()
			return
	if variant not in ["before", "after"] or view not in ["normal", "chilled", "dense", "disabled"] or (not destination.is_empty() and not destination.to_lower().ends_with(".png")):
		_invalid_arguments()
		return
	if DisplayServer.get_name() == "headless":
		push_error("Enemy hit style comparison requires native rendering.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 受击材质对照 / %s / %s（固定场景，不写档案）" % [variant, view]
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world: CombatWorld = LegacyTintWorld.new() if variant == "before" else CombatWorld.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": view != "disabled"}
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
	world.sim.player_position = Vector2(1180, 580)
	var targets: Array[CombatSim.Enemy] = []
	var frames: int = 8
	if view == "dense":
		frames = 20
		_dense_setup(world, frames)
	else:
		targets = _matrix_setup(world, view != "normal", frames)
	world._visual_time = 7.5
	world._projectile_painter.rebuild(world.sim.shots)
	world._enemy_telegraphs.rebuild(world.sim.enemies)
	world._impact_painter.rebuild(view != "disabled")
	var stats: Dictionary = _budgets(world)
	var passed: bool = not world.sim.complete
	if view == "dense":
		passed = passed and world.sim.primary_hits > 0 and world.sim.secondary_hits > 0
		passed = passed and stats["projectiles"]["friendly_count"] >= 600 and stats["projectiles"]["family_counts"].size() == 21
	else:
		passed = passed and world.sim.primary_hits == 15 and world.sim.secondary_hits == 0
		for index: int in targets.size():
			var enemy: CombatSim.Enemy = targets[index]
			var row: int = index / IDS.size()
			var expected: float = [0.10, 0.10 - 2.0 * STEP, 0.0][row]
			passed = passed and enemy.active and enemy.health < enemy.max_health
			passed = passed and is_equal_approx(enemy.hurt_timer, expected)
			passed = passed and ((enemy.slow_timer > 0.0) == (view != "normal"))
	_overlay(variant, view, frames, world.sim)
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
	print("ENEMY_HIT_STYLE_PREVIEW ", JSON.stringify({"variant": variant, "case": view,
		"seed": SEED, "frames": frames, "fixed_scene": true, "persistent_profile": false,
		"manual_danger_fixture": view == "dense", "visual_revision": "legacy-flat-hit" if variant == "before" else CombatWorld.ENEMY_HIT_VISUAL_REVISION,
		"fixture_passed": passed, "capture_result": result, "capture": destination,
		"state_hash": _state_hash(world.sim), "endpoint_hash": _endpoint_hash(world._projectile_painter),
		"primary_hits": world.sim.primary_hits, "secondary_hits": world.sim.secondary_hits,
		"timers": _timer_report(world, view == "dense"), "budgets": stats}))
	if not passed:
		push_error("The hit-style fixture did not retain the expected real hits, timers or pressure population.")
	if not destination.is_empty() or not passed:
		quit(0 if passed and result == OK else 1)


func _invalid_arguments() -> void:
	push_error("Use --variant=before|after --case=normal|chilled|dense|disabled and optional --capture=<path.png>.")
	quit(2)


func _target(sim: CombatSim, id: String, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = 100000000.0
	enemy.max_health = enemy.health
	enemy.action_timer = 9999.0
	return enemy


func _matrix_setup(world: CombatWorld, chilled: bool, frames: int) -> Array[CombatSim.Enemy]:
	var targets: Array[CombatSim.Enemy] = []
	for row: int in ROWS.size():
		for column: int in IDS.size():
			targets.append(_target(world.sim, IDS[column], Vector2(COLUMNS[column], ROWS[row])))
	for frame: int in frames:
		world._advance_feedback(STEP)
		for row: int in FIRE_FRAMES.size():
			if frame != FIRE_FRAMES[row]:
				continue
			for column: int in IDS.size():
				var enemy: CombatSim.Enemy = targets[row * IDS.size() + column]
				world.sim.fire_weapon("frost" if chilled else "bone", "", enemy.position - Vector2(20, 0), Vector2.RIGHT)
		world.sim.step(STEP, Vector2.ZERO)
	return targets


func _dense_setup(world: CombatWorld, frames: int) -> void:
	world.sim.player_position = Vector2(455, 375)
	world.stress_mode = true
	world.sim.populate_stress()
	world.enable_rune_stress(true)
	for frame: int in frames:
		world._advance_feedback(STEP)
		world.sim.step(STEP, Vector2.ZERO)
		world._maintain_stress()
	# Explicit unchanged layer fixtures, not a natural boss attack or charge event.
	var charge: CombatSim.Enemy = _target(world.sim, "rusher", Vector2(950, 545))
	charge.mode = 1
	charge.charge_direction = Vector2(-1, -0.4).normalized()
	charge.action_timer = CombatSim.RUSHER_WINDUP * 0.5
	var caster: CombatSim.Enemy = _target(world.sim, "caster", Vector2(1130, 535))
	caster.mode = 1
	caster.action_timer = CombatSim.CASTER_WINDUP * 0.5
	var warning := CombatSim.WarningZone.new()
	warning.position = Vector2(1040, 525)
	warning.radius = 45.0
	warning.age = 0.65
	world.sim.zones.append(warning)
	world.sim.fire_weapon("frost", "pierce", warning.position - Vector2(6, 0), Vector2.RIGHT)
	world.sim._hostile_shot(warning.position, Vector2.ZERO, 8.0, "caster")


func _overlay(variant: String, view: String, frames: int, sim: CombatSim) -> void:
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
	_label(canvas, "受击材质对照 · %s / %s" % [variant, view], Vector2(48, 27), 28, GameUI.BONE)
	_label(canvas, "固定种子 %d · 正式 fire/step 推进 %d 步 · 不写档案" % [SEED, frames], Vector2(48, 68), 15, GameUI.MUTED)
	if view != "dense":
		for column: int in IDS.size():
			_label(canvas, GameCatalog.enemy(IDS[column]).display_name, Vector2(COLUMNS[column] - 40, 101), 15, GameUI.GOLD)
		for row: int in ROWS.size():
			_label(canvas, ["0 ms", "33 ms", ">100 ms"][row], Vector2(22, ROWS[row] - 14), 14, GameUI.MUTED)
	_panel(canvas, Rect2(24, 616, 1232, 86))
	_label(canvas, "固定静帧，非自然对局 · %d 次直接命中 / %d 次追加命中 · 关闭闪光不影响实际伤害。" % [sim.primary_hits, sim.secondary_hits], Vector2(48, 630), 16, GameUI.BONE)
	var note: String = "五列为实际敌人尺寸；三行年龄来自分帧发射，未直接改计时、伤害或受击特效。"
	if view == "dense":
		note = "正式七法器压力推进；右下另加危险层夹具与真实敌弹对象，非自然Boss攻击。"
	elif view == "disabled":
		note = "此页为关闭闪光后的真实寒霜命中；应保留冷色材质，三行均不出现整身受击增亮。"
	_label(canvas, note, Vector2(48, 668), 14, GameUI.MUTED)


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


func _timer_report(world: CombatWorld, dense: bool) -> Dictionary:
	var samples: Array = []
	var hurt: int = 0
	var pulse: int = 0
	var cold: int = 0
	for enemy: CombatSim.Enemy in world.sim.enemies:
		if not enemy.active:
			continue
		hurt += 1 if enemy.hurt_timer > 0.0 else 0
		pulse += 1 if enemy.hurt_timer > 0.04 else 0
		cold += 1 if enemy.slow_timer > 0.0 else 0
		if dense and samples.size() >= 24:
			continue
		var tint: Color = world._enemy_tint(enemy)
		samples.append({"uid": enemy.uid, "id": enemy.definition.id, "position": [enemy.position.x, enemy.position.y],
			"hurt_timer": enemy.hurt_timer, "slow_timer": enemy.slow_timer, "health_lost": enemy.max_health - enemy.health,
			"tint": [tint.r, tint.g, tint.b, tint.a]})
	return {"hurt_count": hurt, "within_60ms_count": pulse, "cold_count": cold, "samples": samples,
		"sample_scope": "first 24 active enemies" if dense else "all fifteen matrix enemies"}


func _budgets(world: CombatWorld) -> Dictionary:
	return {"projectiles": world._projectile_painter.get_stats(), "telegraphs": world._enemy_telegraphs.get_stats(),
		"impacts": world._impact_painter.get_stats(), "numbers": world._numbers.size(), "runes": world._rune_flashes.size()}


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
		result[key] = [trail.points, trail.wings, trail.sigils]
	return JSON.stringify(result).sha256_text()
