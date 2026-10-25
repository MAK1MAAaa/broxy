extends SceneTree
## Native content fixtures. Purchases and combat use production rules; no profile is loaded or saved.

const VIEWS: PackedStringArray = ["arsenal", "relics", "shop", "combat"]
const NEW_WEAPONS: PackedStringArray = ["crescent", "storm", "comet"]
const NEW_RELICS: PackedStringArray = ["moon_charm", "pilgrim", "bulwark", "hourglass"]
const PAIRINGS: Dictionary = {
	"crescent": "搭配贯穿：最多4个直接目标；月蚀吊坠强化伤害与咒速。",
	"storm": "搭配爆破：双发分别触发；裂砂漏提高攻速、降低每枚伤害。",
	"comet": "搭配弹射：重击转向后继目标；巡礼靴便于保持距离。",
}

var _app: Node
var _view: String = "arsenal"
var _destination: String = ""
var _inspect: String = ""
var _fixture_failed: bool = false
var _page: Control


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			_view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			_destination = argument.trim_prefix("--capture=")
		elif argument.begins_with("--inspect="):
			_inspect = argument.trim_prefix("--inspect=")
	if _view not in VIEWS or (not _destination.is_empty() and not _destination.to_lower().ends_with(".png")):
		push_error("Use --view=arsenal|relics|shop|combat and optional --capture=<path.png>")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	_app = load("res://scenes/main.tscn").instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	await process_frame
	# The fixture controls capture itself, and frozen combat must not auto-pause
	# when the screenshot runner or another editor takes focus.
	_app.args.append("--autoplay")
	_app._screenshot_clock = -1.0
	_app._start_run("bone")
	_app.world.set_physics_process(false)
	_app.world.stop()
	_app.sound.set_volume(0.0)
	root.title = "秘术余烬 · 内容陈列 / %s（固定场景，不写档案）" % _view
	match _view:
		"arsenal", "relics":
			_app.ui.hide()
			_build_catalog()
		"shop":
			_build_shop()
		"combat":
			_build_combat()
	if _fixture_failed:
		_app._quit_game(1)
		return
	await process_frame
	await process_frame
	await process_frame
	if _view == "shop" and not _inspect.is_empty():
		var inspect_button: Button = _owned_relic_button(_inspect)
		if inspect_button == null:
			push_error("Unknown owned relic to inspect: " + _inspect)
			_app._quit_game(2)
			return
		inspect_button.grab_focus()
		await process_frame
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = true
		root.push_input(key, false)
		await process_frame
		key = InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = false
		root.push_input(key, false)
		await process_frame
		await process_frame
	if _destination.is_empty():
		print("CONTENT_PREVIEW view=", _view, " persistent=false capture=interactive")
		return
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path(_destination).get_base_dir()
	var result: Error = DirAccess.make_dir_recursive_absolute(directory)
	if result == OK:
		result = root.get_texture().get_image().save_png(_destination)
	print("CONTENT_PREVIEW view=", _view, " result=", result, " output=", _destination,
		" persistent=false primary_hits=", _app.world.sim.primary_hits,
		" secondary_hits=", _app.world.sim.secondary_hits)
	_app._quit_game(0 if result == OK else 1)


func _build_catalog() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	_app.add_child(layer)
	_page = Control.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.theme = _app.ui._make_theme()
	layer.add_child(_page)
	var background := ColorRect.new()
	background.color = GameUI.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_app.ui._margin(margin, 30, 22)
	_page.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	margin.add_child(scroll)
	scroll.add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var title: Label = _app.ui._label("法器图鉴 · %d种秘术" % GameCatalog.weapons().size() if _view == "arsenal" else "遗物图鉴 · %d种刻印" % GameCatalog.relics().size(), 28, GameUI.BONE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_app.ui._label("固定陈列 · 基础数值 · 不写档案", 14, GameUI.GOLD))
	if _view == "arsenal":
		_app.ui._section_heading(body, "新增法器 / 各有独立弹体与轮廓", GameUI.CYAN, 16)
		var additions := HBoxContainer.new()
		additions.custom_minimum_size.y = 340
		additions.add_theme_constant_override("separation", 12)
		additions.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(additions)
		for id: String in NEW_WEAPONS:
			_catalog_card(additions, GameCatalog.weapon(id), true)
		_app.ui._section_heading(body, "原有法器 / 骨针与余烬仍为起始选择", GameUI.GOLD, 16)
		var originals := HBoxContainer.new()
		originals.add_theme_constant_override("separation", 12)
		body.add_child(originals)
		for definition: ContentDef in GameCatalog.weapons():
			if definition.id not in NEW_WEAPONS:
				_catalog_card(originals, definition, false)
	else:
		_app.ui._section_heading(body, "新增遗物 / 放入背包占格生效，同名同阶手动合成至Ⅲ阶", GameUI.CYAN, 16)
		var additions := HBoxContainer.new()
		additions.custom_minimum_size.y = 280
		additions.add_theme_constant_override("separation", 12)
		additions.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(additions)
		for id: String in NEW_RELICS:
			_catalog_card(additions, GameCatalog.relic(id), true)
		_app.ui._section_heading(body, "其他遗物 / 属性与取舍", GameUI.GOLD, 16)
		var originals := GridContainer.new()
		originals.columns = 3
		originals.add_theme_constant_override("h_separation", 12)
		originals.add_theme_constant_override("v_separation", 10)
		body.add_child(originals)
		for definition: ContentDef in GameCatalog.relics():
			if definition.id not in NEW_RELICS:
				_catalog_card(originals, definition, false)
	body.add_child(_app.ui._label("此页读取正式内容定义；商店页使用真实购买，战斗页使用真实发射与碰撞。", 13, GameUI.MUTED))


func _catalog_card(parent: Control, definition: ContentDef, featured: bool) -> void:
	var panel: PanelContainer = _app.ui._panel(parent)
	panel.name = "Catalog_" + definition.id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body: VBoxContainer = _app.ui._inside(panel, 14 if featured else 10)
	body.add_theme_constant_override("separation", 7 if featured else 4)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	body.add_child(header)
	_app.ui._add_icon(header, definition, (60 if definition.kind == "relic" else 76) if featured else 38)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(names)
	names.add_child(_app.ui._label(definition.display_name, (22 if definition.kind == "relic" else 24) if featured else 18, GameUI.BONE))
	names.add_child(_app.ui._label("%d 魂屑" % definition.price, 14, GameUI.GOLD))
	names.add_child(_app.ui._label("Ⅰ阶 · 占格 %d×%d" % [definition.inventory_size.x, definition.inventory_size.y], 12, GameUI.MUTED))
	if featured:
		body.add_child(_app.ui._wrap(definition.subtitle, 14, GameUI.CYAN))
	if definition.kind == "weapon":
		body.add_child(_app.ui._wrap("%.0f伤害 × %d枚 / %.2f秒\n弹速 %.0f · 索敌范围 %.0f" % [definition.damage, definition.shots, definition.cooldown, definition.projectile_speed, definition.range], 14 if featured else 12, GameUI.GOLD))
		if featured:
			var description: Label = _app.ui._wrap(definition.description, 14, GameUI.MUTED)
			description.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(description)
			body.add_child(_app.ui._wrap(str(PAIRINGS.get(definition.id, "")), 13, GameUI.PURPLE))
	else:
		body.add_child(_app.ui._wrap(definition.description, 15 if featured else 13, GameUI.CYAN if featured else GameUI.MUTED))
		if featured:
			var role: String = {"moon_charm": "适合持续输出：月镰、雷灯均可受益。", "pilgrim": "适合远程走位：拉开距离，收拢魂屑。", "bulwark": "适合近身容错：购买时同步补充新增生命。", "hourglass": "以单次伤害换咒速：按武器节奏选择。"}.get(definition.id, "")
			body.add_child(_app.ui._wrap(role, 14, GameUI.PURPLE))


func _purchase(kind: String, id: String) -> bool:
	if _fixture_failed:
		return false
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	var state: RunState = _app.run
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	if not state.buy_offer(0):
		_fixture_failed = true
		push_error("Content fixture purchase failed: " + state.last_error)
		return false
	return true


func _owned_relic_button(id: String) -> Button:
	for item: Dictionary in _app.run.backpack_snapshot()["items"]:
		if item["kind"] == "relic" and item["id"] == id:
			return _app.ui._shop_focus_button("bag:%d" % int(item["uid"]))
	return null


func _purchased_build(all_relics: bool) -> void:
	_app.run.begin(20261023, "bone")
	_app.run.wave = 4
	_app.run.collect_souls(1800)
	if not _app.run.expand_backpack() or not _app.run.expand_backpack():
		_fixture_failed = true
		push_error("Content fixture expansion failed: " + _app.run.last_error)
		return
	var weapons: PackedStringArray = PackedStringArray(["frost", "ember", "scatter"]) if all_relics else NEW_WEAPONS
	for id: String in weapons:
		if not _purchase("weapon", id):
			return
	for pair: Array in [["blast", 1], ["pierce", 2], ["bounce", 3]]:
		if not _purchase("rune", str(pair[0])):
			return
		if not _app.run.equip_rune(0, int(pair[1])):
			_fixture_failed = true
			push_error("Content fixture equip failed: " + _app.run.last_error)
			return
	for definition: ContentDef in GameCatalog.relics():
		if all_relics or definition.id in NEW_RELICS:
			if not _purchase("relic", definition.id):
				return
	var expected_cells: int = 32 if all_relics else 29
	if int(_app.run.backpack_snapshot()["used_cells"]) != expected_cells:
		_fixture_failed = true
		push_error("Content fixture does not match its declared physical backpack occupancy")
	_app.run.pending_upgrades = 0


func _build_shop() -> void:
	_purchased_build(true)
	if _fixture_failed:
		return
	for id: String in ["pierce", "bounce", "blast", "pierce"]:
		if not _purchase("rune", id):
			return
	if int(_app.run.backpack_snapshot()["used_cells"]) != 36:
		_fixture_failed = true
		push_error("Content shop fixture must fill exactly thirty-six cells")
		return
	_app.run.offers.clear()
	for entry: Array in [["weapon", "crescent"], ["weapon", "storm"], ["relic", "moon_charm"], ["relic", "hourglass"]]:
		var kind: String = str(entry[0])
		var id: String = str(entry[1])
		var definition: ContentDef = GameCatalog.weapon(id) if kind == "weapon" else GameCatalog.relic(id)
		_app.run.offers.append({"kind": kind, "id": id, "price": definition.price, "sold": false})
	_app.screen = 3
	_app.ui.show_shop()
	_add_fixture_note("商店固定陈列 · 36格满背包 / %d法器 / %d松散符文 / %d类遗物 · 真实购买，不写档案" % [_app.run.loadout.size(), _app.run.rune_bag.size(), _app.run.relic_counts.size()])


func _build_combat() -> void:
	_purchased_build(false)
	if _fixture_failed:
		return
	var world: CombatWorld = _app.world
	world.begin(_app.run)
	world.set_physics_process(false)
	world._visual_time = 7.5
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(10000.0)
	sim.player_position = Vector2(455, 375)
	for entry: Array in [["tank", Vector2(705, 240)], ["tank", Vector2(785, 240)], ["chaser", Vector2(850, 280)],
		["tank", Vector2(790, 355)], ["tank", Vector2(730, 490)], ["chaser", Vector2(850, 490)]]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy(str(entry[0]), entry[1])
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.health = 5000.0
		enemy.max_health = 5000.0
		enemy.action_timer = 10000.0
	for entry: Array in [["crescent", "blast", Vector2(655, 240)], ["storm", "pierce", Vector2(655, 355)], ["comet", "bounce", Vector2(655, 490)]]:
		sim.fire_weapon(str(entry[0]), str(entry[1]), entry[2], Vector2.RIGHT)
	for step_index: int in 20:
		sim.step(1.0 / 60.0, Vector2.ZERO)
		world._advance_feedback(1.0 / 60.0)
	for entry: Array in [["crescent", "blast", Vector2(560, 240)], ["storm", "pierce", Vector2(565, 355)], ["comet", "bounce", Vector2(580, 490)]]:
		sim.fire_weapon(str(entry[0]), str(entry[1]), entry[2], Vector2.RIGHT)
	var warning := CombatSim.WarningZone.new()
	warning.position = Vector2(1080, 520)
	warning.age = 0.65
	sim.zones.append(warning)
	_app.ui.show_hud()
	_app.ui.update_hud(world.hud_snapshot())
	world.queue_redraw()
	_add_fixture_note("战斗固定陈列 · 真实购买/发射/碰撞 · %d次直接命中 / %d次追加命中 · 不写档案" % [sim.primary_hits, sim.secondary_hits])
	var labels := CanvasLayer.new()
	labels.layer = 12
	_app.add_child(labels)
	for entry: Array in [["月镰 + 爆破\n先贯穿首目标，第二命中引爆", Vector2(48, 222)], ["雷灯 + 贯穿\n窄角双发，冷青轨迹/淡金电芯", Vector2(48, 337)], ["星陨 + 弹射\n低速重击，金紫多面星核", Vector2(48, 472)]]:
		var label: Label = _app.ui._label(str(entry[0]), 15, GameUI.BONE)
		label.position = entry[1]
		label.theme = _app.ui._make_theme()
		labels.add_child(label)


func _add_fixture_note(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	_app.add_child(layer)
	var note: Label = _app.ui._label(text, 12, GameUI.CYAN)
	note.theme = _app.ui._make_theme()
	note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.offset_top = 1
	note.offset_bottom = 19
	layer.add_child(note)
