extends SceneTree
## Native source-art, collision and shop fixtures; profile persistence stays disabled.

const FIXTURE = preload("res://tests/test_return_ring_ui.gd")
const CASES: PackedStringArray = ["art", "outbound", "returning", "shop", "rune", "blood_pact", "grave_candle", "result"]
const STEP: float = 1.0 / 60.0

class HeadCanvas:
	extends Node2D
	var painter: ProjectilePainter
	func _draw() -> void:
		painter.draw(self)

var _app: Node
var _record: Dictionary = {}


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var case_name: String = "art"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
	if case_name not in CASES or (not destination.is_empty() and not destination.to_lower().ends_with(".png")):
		push_error("Use --case=art|outbound|returning|shop|rune|blood_pact|grave_candle|result and optional --capture=<path.png>")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	_app = load("res://scenes/main.tscn").instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	await process_frame
	_app.args.append("--autoplay")
	_app._screenshot_clock = -1.0
	_app.sound.set_volume(0.0)
	_app.world.stop()
	_app.world.set_physics_process(false)
	root.title = "秘术余烬 · 归魂环陈列 / %s（固定场景，不写档案）" % case_name
	_record = {"case": case_name, "persistent": false, "viewport": [1280, 720], "fixture_passed": true}
	match case_name:
		"art":
			_art()
		"outbound", "returning":
			_combat(case_name)
		"result":
			_result()
		_:
			var state: RunState = FIXTURE.make_fixture()
			if state == null:
				_app._quit_game(1)
				return
			_app.run = state
			_app.ui.bind(state)
			_app.screen = 3
			_app.ui.show_shop()
			await _settle()
			if case_name == "shop":
				await _activate("lock:0")
				await _activate("lock:1")
				await _activate("bag:%d" % int(state.rune_bag[0]["uid"]))
			elif case_name == "rune":
				await _activate("bag:%d" % int(state.rune_bag[0]["uid"]))
				await _activate("rune_preview:1")
			else:
				await _activate("compare:1" if case_name == "blood_pact" else "compare:2")
			_record["summary"] = state.summary()
			_record["overlay"] = _app.ui._overlay_mode
			_record["fixture_passed"] = bool(_record["fixture_passed"]) and state.loadout.size() == 3 and state.rune_bag.size() == 3 and state.relic_counts.size() == GameCatalog.relics().size() and state.backpack_snapshot()["used_cells"] == 34
	_note("归魂环固定陈列 · 正式规则与资源 · 非自然对局 · 不写档案")
	await _settle()
	if destination.is_empty():
		print("RETURN_RING_PREVIEW ", JSON.stringify(_record))
		return
	await create_timer(3.1).timeout
	await RenderingServer.frame_post_draw
	var result: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination).get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(destination)
	_record["capture_result"] = result
	print("RETURN_RING_PREVIEW ", JSON.stringify(_record))
	_app._quit_game(0 if result == OK and bool(_record["fixture_passed"]) else 1)


func _art() -> void:
	_app.ui.hide()
	var layer := CanvasLayer.new()
	layer.layer = 20
	_app.add_child(layer)
	var page := Control.new()
	page.theme = _app.ui._make_theme()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(page)
	var background := ColorRect.new()
	background.color = GameUI.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_app.ui._margin(margin, 30, 28)
	page.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	body.add_child(_app.ui._label("归魂军械 · 一件回旋法器与两件取舍遗物", 28, GameUI.BONE))
	body.add_child(_app.ui._label("engraved-06 · 冷白断骨 / 旧金封蜡 / 冷青魂焰 · 8法器 / 12遗物", 15, GameUI.CYAN))
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 400
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	for id: String in ["return_ring", "blood_pact", "grave_candle"]:
		var definition: ContentDef = GameCatalog.weapon(id) if id == "return_ring" else GameCatalog.relic(id)
		var card: PanelContainer = _app.ui._panel(row, Vector2(390, 400))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inside: VBoxContainer = _app.ui._inside(card, 20)
		inside.add_theme_constant_override("separation", 10)
		var title := HBoxContainer.new()
		inside.add_child(title)
		_app.ui._add_icon(title, definition, 76)
		var names := VBoxContainer.new()
		title.add_child(names)
		names.add_child(_app.ui._label(definition.display_name, 24, GameUI.BONE))
		names.add_child(_app.ui._label("基础价格 %d 魂屑" % definition.price, 15, GameUI.GOLD))
		inside.add_child(_app.ui._wrap(definition.subtitle, 15, GameUI.CYAN))
		inside.add_child(_app.ui._wrap(definition.description, 15, GameUI.MUTED))
		if definition.kind == "weapon":
			inside.add_child(_app.ui._wrap("基础16伤害 / 0.95秒\n索敌230，去程约216；冷却独立。", 15, GameUI.GOLD))
	body.add_child(_app.ui._label("实际批量弹体 · 原尺寸约20px · 空心头部与三种符文 / 月镰、星陨对照", 16, GameUI.PURPLE))
	var sim := CombatSim.new()
	var state := RunState.new()
	state.begin(20261027, "bone")
	sim.begin(state)
	var examples: Array[Array] = [["return_ring", ""], ["return_ring", "pierce"], ["return_ring", "bounce"], ["return_ring", "blast"], ["crescent", ""], ["comet", ""], ["return_ring", "zero"]]
	var centers: Array[Vector2] = []
	for index: int in examples.size():
		var center := Vector2(90 + index * 180, 600)
		centers.append(center)
		var example: Array = examples[index]
		var shot: CombatSim.Shot = sim.fire_weapon(str(example[0]), "" if example[1] == "zero" else str(example[1]), center, Vector2.RIGHT)
		if example[1] == "zero":
			shot.velocity = Vector2.ZERO
		var label: Label = _app.ui._label(["归魂环", "贯穿", "弹射", "爆破", "月镰", "星陨", "零速朝向"][index], 14, GameUI.MUTED)
		label.position = center + Vector2(-35, 24)
		page.add_child(label)
	var canvas := HeadCanvas.new()
	canvas.painter = ProjectilePainter.new()
	canvas.painter.rebuild(sim.shots)
	page.add_child(canvas)
	_record["head_centers"] = centers
	_record["batches"] = canvas.painter.get_stats()


func _combat(case_name: String) -> void:
	var state := RunState.new()
	state.begin(20261027, "return_ring")
	var rune: ContentDef = GameCatalog.rune("pierce")
	state.collect_souls(rune.price)
	state.offers = [{"kind": "rune", "id": rune.id, "price": rune.price, "sold": false}]
	if not state.buy_offer(0) or not state.equip_rune(0, 0):
		_record["fixture_passed"] = false
		push_error("Combat fixture could not purchase and equip pierce")
		return
	_app.run = state
	_app.ui.bind(state)
	_app.ui.show_hud()
	_app.world.begin(state)
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(640, 365)
	for position: Vector2 in [Vector2(760, 365), Vector2(795, 420), Vector2(720, 490)]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", position)
		enemy.health = 10000.0
		enemy.max_health = enemy.health
		enemy.slow_timer = 9999.0
		enemy.slow_factor = 0.0
	var shot: CombatSim.Shot = sim.fire_weapon("return_ring", "pierce", sim.player_position, Vector2.RIGHT)
	var frames: int = 18 if case_name == "outbound" else 48
	for frame: int in frames:
		sim.step(STEP, Vector2.DOWN if frame >= 18 else Vector2.ZERO)
	_app.world._visual_time = 2.0
	_app.world.queue_redraw()
	_app.ui.update_hud(_app.world.hud_snapshot())
	_record.merge({"frames": frames, "rune": rune.id, "primary_hits": sim.primary_hits, "hit_ids": shot.hit_ids, "returning": shot.returning, "active": shot.active, "position": shot.position, "player": sim.player_position, "life": shot.life, "fixture_passed": shot.active and shot.returning == (case_name == "returning")})


func _result() -> void:
	var state := RunState.new()
	state.begin(20261027, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	for index: int in GameCatalog.weapons().size():
		var position := Vector2(200 + index % 4 * 260, 230 + index / 4 * 220)
		var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", position)
		enemy.health = 10000.0
		enemy.max_health = enemy.health
		enemy.slow_timer = 9999.0
		enemy.slow_factor = 0.0
		sim.fire_weapon(GameCatalog.weapons()[index].id, "", position - Vector2(12, 0), Vector2.RIGHT)
	sim.step(STEP, Vector2.ZERO)
	_app.run = state
	_app.ui.bind(state)
	_app.ui.show_result(false, "固定单弹命中陈列，非自然对局结算。", _app.store.best)
	_record["damage_by_weapon"] = sim.damage_by_weapon
	_record["fixture_passed"] = sim.damage_by_weapon.size() == 8


func _note(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	_app.add_child(layer)
	var note: Label = _app.ui._label(text, 12, GameUI.CYAN)
	note.theme = _app.ui._make_theme()
	note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.offset_top = 2
	note.offset_bottom = 20
	layer.add_child(note)


func _activate(id: String) -> void:
	var button: Button = _app.ui._shop_focus_button(id)
	if button == null:
		push_error("Missing fixture action: " + id)
		_record["fixture_passed"] = false
		return
	button.grab_focus()
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		root.push_input(event, false)
	await _settle()


func _settle() -> void:
	for frame: int in 4:
		await process_frame
