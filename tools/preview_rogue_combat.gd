extends SceneTree
## Native fixed-step showcase: formal core/contract grants, real fire/step, no FX injection.

const STEP: float = 1.0 / 60.0
const SEED: int = 20261027
const TARGET_HEALTH: float = 10000.0

class SilentSoundBank:
	extends SoundBank
	func _ready() -> void:
		pass

var _case: String = "frostfire"
var _capture: String = ""
var _transactions: Array[Dictionary] = []
var _setup_ok: bool = true
var _frames: int = 0
var _source_hits: Dictionary = {}

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			_case = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			_capture = argument.trim_prefix("--capture=")
		else:
			_invalid()
			return
	if _case not in ["frostfire", "bone_chorus", "hunter"] or DisplayServer.get_name() == "headless":
		_invalid()
		return
	if _capture.is_empty():
		_capture = "res://reports/rogue-combat-%s.png" % _case
	if not _capture.ends_with(".png"):
		_invalid()
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 肉鸽战斗陈列 / %s（固定场景，不写档案）" % _case
	var state := RunState.new()
	state.begin(SEED, "bone")
	state.finish_wave()
	_transactions.append({"operation": "finish_wave", "wave": state.wave})
	if _case != "hunter":
		var chosen: bool = state.choose_core(_case)
		_setup_ok = chosen
		_transactions.append({"operation": "choose_core", "id": _case, "success": chosen})
	state.next_wave()
	_transactions.append({"operation": "next_wave", "wave": state.wave})
	if _case == "hunter":
		state.finish_wave()
		_transactions.append({"operation": "finish_wave", "wave": state.wave})
		var accepted: bool = state.choose_altar(true)
		_setup_ok = accepted
		_transactions.append({"operation": "choose_altar", "accepted": accepted})
		state.next_wave()
		_transactions.append({"operation": "next_wave", "wave": state.wave})
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.settings = {"shake": false, "flash": true}
	root.add_child(world)
	world.set_physics_process(false)
	world.begin(state)
	world.set_physics_process(false)
	world._visual_time = 6.0
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.damage_dealt.connect(func(_point: Vector2, amount: float, source: String, secondary: bool, _uid: int) -> void:
		if amount > 0.0:
			var key: String = source + (":secondary" if secondary else ":primary")
			_source_hits[key] = int(_source_hits.get(key, 0)) + 1
	)
	var passed: bool = _setup_ok
	match _case:
		"frostfire":
			sim.player_position = Vector2(430, 425)
			var direct: CombatSim.Enemy = _target(sim, Vector2(650, 345))
			var neighbor: CombatSim.Enemy = _target(sim, Vector2(687, 375))
			var second_neighbor: CombatSim.Enemy = _target(sim, Vector2(642, 395))
			# The slow is produced by an actual frost collision, not assigned to the target.
			_launch_at(sim, direct, "frost")
			_tick(world, 4)
			var chilled: bool = direct.slow_timer > 0.0
			_launch_at(sim, direct, "ember")
			_tick(world, 5)
			passed = passed and chilled and direct.slow_timer == 0.0 and sim.core_activations["frostfire"] == 1
			passed = passed and neighbor.health < TARGET_HEALTH and second_neighbor.health < TARGET_HEALTH
		"bone_chorus":
			sim.player_position = Vector2(440, 380)
			_target(sim, Vector2(790, 380))
			_target(sim, Vector2(870, 295))
			_target(sim, Vector2(870, 465))
			# Preserve the real per-weapon initial staggering and cooldown progression.
			for index: int in state.loadout.size():
				sim._cooldowns[index] = float(index) * 0.14
			_tick(world, 68)
			passed = passed and sim.core_activations["bone_chorus"] == 2 and sim.primary_hits > 0 and sim.shot_count >= 6
		"hunter":
			sim.player_position = Vector2(440, 440)
			var hunter: CombatSim.Enemy = sim.hunter
			passed = passed and hunter != null
			if hunter != null:
				hunter.position = Vector2(700, 330)
				# Advance the actual rusher AI into its windup; only the initial clock/position is controlled.
				hunter.action_timer = 0.001
				_launch_at(sim, hunter, "bone")
			_tick(world, 5)
			var ordinary: CombatSim.Enemy = sim.spawn_enemy("rusher", Vector2(890, 435))
			ordinary.definition = ordinary.definition.duplicate() as ContentDef
			ordinary.definition.speed = 0.0
			ordinary.action_timer = 9999.0
			passed = passed and hunter != null and hunter.active and hunter.hunter and hunter.mode == 1
			passed = passed and hunter.health < hunter.max_health and not state.hunter_defeated
	_overlay(sim)
	world.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(_capture)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var targets: Array[Dictionary] = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			targets.append({"uid": enemy.uid, "source_id": enemy.definition.id, "position": [enemy.position.x, enemy.position.y],
				"health": enemy.health, "max_health": enemy.max_health, "slow_timer": enemy.slow_timer, "hunter": enemy.hunter, "mode": enemy.mode})
	print("ROGUE_COMBAT_PREVIEW ", JSON.stringify({"case": _case, "fixed_fixture": true, "natural_run": false,
		"persistent_profile": false, "profile_access": false, "seed": SEED, "viewport": [1280, 720],
		"transactions": _transactions, "fixture_passed": passed, "capture": absolute, "capture_result": result,
		"fixed_steps": _frames, "core_activations": sim.core_activations, "primary_hits": sim.primary_hits,
		"secondary_hits": sim.secondary_hits, "source_hits": _source_hits, "targets": targets,
		"state": state.summary(), "hud_rogue": world.hud_snapshot()["rogue"], "simulation_rng_state": str(sim.rng.state),
		"controls": "High-health stationary chasers, controlled player/enemy positions and manual launch origins; frost slow and all core effects from real fire/step. Chorus preserves real cooldowns; hunter initial action clock controlled then real AI windup. Physics/render age frozen at capture."}))
	sound.shutdown()
	quit(0 if passed and result == OK else 1)

func _tick(world: CombatWorld, count: int) -> void:
	for frame: int in count:
		world._advance_feedback(STEP)
		world.sim.step(STEP, Vector2.ZERO)
		world._visual_time += STEP
		_frames += 1

func _target(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = TARGET_HEALTH
	enemy.max_health = TARGET_HEALTH
	enemy.action_timer = 9999.0
	return enemy

func _launch_at(sim: CombatSim, target: CombatSim.Enemy, source: String) -> void:
	var definition: ContentDef = GameCatalog.weapon(source)
	var clearance: float = target.radius + definition.projectile_radius + 1.0
	sim.fire_weapon(source, "", target.position - Vector2(clearance, 0), Vector2.RIGHT)

func _overlay(sim: CombatSim) -> void:
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
	var titles: Dictionary = {"frostfire": "霜火共鸣 · 消耗减速，化作寒焰", "bone_chorus": "白骨齐鸣 · 第三次攻击的双翼", "hunter": "追猎契约 · 额外精英的代价"}
	_panel(canvas, Rect2(24, 16, 1232, 112))
	_label(canvas, str(titles[_case]), Vector2(48, 32), 820, 28, Color("f0e5cc"))
	_label(canvas, "固定战斗陈列 · 非自然通关", Vector2(882, 42), 350, 17, Color("c4a76f"))
	_label(canvas, "正式波间选择 → 正式战斗模拟 · 同一画面尺寸 · 不写个人档案", Vector2(49, 85), 1160, 15, Color("aaa4b3"))
	match _case:
		"frostfire":
			_label(canvas, "霜矛先命中减速 → 幽焰直接命中消耗", Vector2(485, 205), 650, 19, Color("9de1e6"))
			_label(canvas, "蓝金双环：48px / 本次伤害50%的次级爆发", Vector2(740, 430), 450, 16, Color("d1cbb9"))
			_label(canvas, "次级伤害不再次触发符文或核心", Vector2(740, 463), 450, 15, Color("aaa4b3"))
		"bone_chorus":
			_label(canvas, "两件骨针独立计数 · 保留真实0.46秒冷却与初始错峰", Vector2(330, 200), 850, 19, Color("e6d8b4"))
			_label(canvas, "侧弹各55%伤害，继承法器阶级与所装符文", Vector2(500, 530), 700, 16, Color("d1cbb9"))
		"hunter":
			_label(canvas, "追猎者：古金冠标 / 珊瑚圈 / 独立生命条", Vector2(490, 205), 700, 19, Color("e0ba7b"))
			_label(canvas, "真实冲锋蓄力方向，仍在危险信息最高层", Vector2(490, 505), 700, 16, Color("d1cbb9"))
			_label(canvas, "普通冲锋者", Vector2(840, 474), 250, 15, Color("aaa4b3"))
	_panel(canvas, Rect2(24, 616, 1232, 86))
	_label(canvas, "固定%d步 · 主命中%d / 次级命中%d · 霜火触发%d / 齐鸣触发%d" % [_frames, sim.primary_hits, sim.secondary_hits, int(sim.core_activations["frostfire"]), int(sim.core_activations["bone_chorus"])], Vector2(48, 630), 1170, 16, Color("f0e5cc"))
	_label(canvas, "敌人位置、耐久与取景受控；核心效果由真实发射和碰撞产生。该陈列不作为自然对局、难度或性能证明。", Vector2(48, 665), 1180, 14, Color("aaa4b3"))

func _panel(parent: Control, rect: Rect2) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111722")
	style.border_color = Color("6e654f")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

func _label(parent: Control, text: String, point: Vector2, width: float, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.size = Vector2(width, 42)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _invalid() -> void:
	push_error("Use --case=frostfire|bone_chorus|hunter and optional --capture=<png>; native rendering required.")
	quit(2)
