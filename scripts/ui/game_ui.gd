class_name GameUI
extends CanvasLayer

signal start_requested(starter: String)
signal next_wave_requested
signal resume_requested
signal menu_requested
signal quit_requested
signal setting_changed(key: String, value: Variant)
signal controls_changed(bindings: Dictionary)
signal upgrades_finished
signal feedback(sound: String)

const INK := Color("dceef0")
const PANEL := Color("fff9e8")
const PANEL_LIGHT := Color("f0ead8")
const BONE := Color("253d54")
const MUTED := Color("526575")
const GOLD := Color("8a5b20")
const PURPLE := Color("765093")
const CYAN := Color("14766f")
const RED := Color("b83c50")
const CORAL := Color("ed9a86")
const BACKPACK_GRID = preload("res://scripts/ui/backpack_grid.gd")
const MINIMAP_VIEW = preload("res://scripts/ui/minimap_view.gd")
const SHOP_PANEL_SKIN = preload("res://scripts/ui/shop_panel_skin.gd")

## Paper-and-brass ornaments draw only on construction/resize and never intercept input.
class RitualFrame:
	extends Control
	var tint: Color = Color("8a5b20")
	var quiet: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 28 or size.y < 20:
			return
		var inset := 5.0
		var length := 7.0 if quiet else 12.0
		var corners: Array[Vector2] = [Vector2(inset, inset), Vector2(size.x - inset, inset), Vector2(inset, size.y - inset), size - Vector2.ONE * inset]
		for corner: Vector2 in corners:
			var horizontal := 1.0 if corner.x < size.x * 0.5 else -1.0
			var vertical := 1.0 if corner.y < size.y * 0.5 else -1.0
			draw_line(corner, corner + Vector2(length * horizontal, 0), Color(tint, 0.48), 2.0)
			draw_line(corner, corner + Vector2(0, length * vertical), Color(tint, 0.48), 2.0)
			draw_rect(Rect2(corner + Vector2(3 * horizontal - 1, 3 * vertical - 1), Vector2(2, 2)), Color(tint, 0.65))
		if not quiet and size.x > 150:
			var center := Vector2(floorf(size.x * 0.5), 5)
			draw_rect(Rect2(center - Vector2(1, 4), Vector2(2, 8)), Color(tint, 0.8))
			draw_rect(Rect2(center - Vector2(4, 1), Vector2(8, 2)), Color(tint, 0.8))
			draw_rect(Rect2(center - Vector2(2, 2), Vector2(4, 4)), Color(tint, 0.8))


class RitualRule:
	extends Control
	var tint: Color = Color("8a5b20")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var center := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5))
		draw_line(Vector2(0, center.y), center - Vector2(11, 0), Color(tint, 0.28), 1.0)
		draw_line(center + Vector2(11, 0), Vector2(size.x, center.y), Color(tint, 0.28), 1.0)
		draw_rect(Rect2(center - Vector2(1, 3), Vector2(2, 6)), Color(tint, 0.8))
		draw_rect(Rect2(center - Vector2(3, 1), Vector2(6, 2)), Color(tint, 0.8))


class TitleChoiceMark:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		set_process(false)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var button := get_parent() as Button
		if button == null or (not button.disabled and not button.button_pressed):
			return
		var point := Vector2(size.x - 16, 8)
		draw_rect(Rect2(point - Vector2.ONE, Vector2(13, 13)), Color(GameUI.PANEL, 0.96))
		if button.disabled:
			draw_rect(Rect2(point + Vector2(2, 5), Vector2(7, 6)), GameUI.MUTED)
			draw_polyline(PackedVector2Array([point + Vector2(3, 5), point + Vector2(3, 2), point + Vector2(8, 2), point + Vector2(8, 5)]), GameUI.MUTED, 2.0)
		else:
			draw_polyline(PackedVector2Array([point + Vector2(1, 6), point + Vector2(4, 9), point + Vector2(10, 2)]), GameUI.CYAN, 2.0, true)


var run: RunState
var _root: Control
var _page: Control
var _overlay: Control
var _toast: Label
var _toast_timer: Timer
var _screen := "title"
var _starter := "bone"
var _arena_id := "reliquary"
var _selected_rune := -1
var _refresh_queued := false
var _settings := {"volume": 0.65, "shake": true, "flash": true}
var _controls: Dictionary = ControlBindings.defaults()
var _control_buttons: Dictionary = {}
var _controls_notice: Label
var _capture_label: Label
var _capture_action: String = ""
var _controls_epoch: int = 0
var _hud_skill_snapshot: Dictionary = {}
var _input_device_tracker: InputDeviceTracker
var _input_kind: String = "keyboard"
var _hud: Dictionary = {}
var _hud_loadout_key := ""
var _best: Dictionary = {}
var _requested_shop_focus := ""
var _shop_epoch: int = 0
var _upgrade_epoch: int = 0
var _upgrades_during_combat: bool = false
var _overlay_mode := ""
var _page_focus: Control
var _page_focus_id := ""
var _bag_selected_uid: int = -1
var _bag_held_uid: int = -1
var _bag_held_rotated: bool = false
var _bag_cursor: Vector2i = Vector2i.ZERO
var _bag_grid: Control
var _bag_details: VBoxContainer
var _bag_status: Label
var _bag_hint_is_default: bool = true
var _unlocked_starters: Array[String] = ["bone", "ember"]
var _rogue_epoch: int = 0
var _rogue_notice: String = ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Interface"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.theme = _make_theme()
	_page = Control.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_page)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)
	_toast = _label("", 16, BONE)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -430
	_toast.offset_right = 430
	_toast.offset_top = -218
	_toast.offset_bottom = -178
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_stylebox_override("normal", _box(PANEL_LIGHT, GOLD))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.hide()
	_root.add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(_toast.hide)
	add_child(_toast_timer)
	_input_device_tracker = InputDeviceTracker.new()
	_input_device_tracker.name = "InputDeviceTracker"
	_input_device_tracker.device_changed.connect(_on_input_device_changed)
	add_child(_input_device_tracker)


func bind(state: RunState) -> void:
	if run != null and run.changed.is_connected(_on_state_changed):
		run.changed.disconnect(_on_state_changed)
	run = state
	if run != null:
		run.changed.connect(_on_state_changed)


func set_settings(values: Dictionary) -> void:
	for key: String in _settings:
		if values.has(key):
			_settings[key] = values[key]


func set_controls(bindings: Dictionary) -> void:
	_controls = ControlBindings.normalize(bindings)
	_refresh_control_buttons()
	_refresh_input_prompts()


func input_device_snapshot() -> Dictionary:
	return _input_device_tracker.snapshot() if is_instance_valid(_input_device_tracker) else {"kind": "keyboard", "gamepad_id": -1}


func _on_input_device_changed(kind: String, _device: int) -> void:
	_input_kind = "gamepad" if kind == "gamepad" else "keyboard"
	_refresh_input_prompts()


func _refresh_input_prompts() -> void:
	if _screen == "hud" and not _hud.is_empty() and not _hud_skill_snapshot.is_empty():
		_update_dash_hud(_hud_skill_snapshot)
		_update_pulse_hud(_hud_skill_snapshot)
	if is_instance_valid(_bag_grid):
		_bag_grid.set_skill_bindings(_controls)
		_bag_grid.set_input_device(_input_kind)
	if is_instance_valid(_bag_status) and _bag_hint_is_default:
		_bag_status.text = _backpack_default_hint()
	if _page != null:
		var move := _page.find_child("MoveBackpackItem", true, false) as Button
		if move != null:
			move.tooltip_text = _backpack_move_tooltip()
		var rotate := _page.find_child("RotateBackpackItem", true, false) as Button
		if rotate != null:
			rotate.text = _backpack_rotate_text()
			rotate.tooltip_text = _backpack_rotate_tooltip()
		var skill_slot := _page.find_child("BackpackSkillSlot", true, false) as Label
		if skill_slot != null and run != null:
			var slot_index: int = _active_skill_index(_bag_selected_uid)
			if slot_index >= 0:
				var action: String = "pulse" if slot_index == 0 else "skill_secondary"
				var input_key: String = ("X" if slot_index == 0 else "Y") if _input_kind == "gamepad" else ControlBindings.key_label(int(_controls[action]))
				skill_slot.text = "技能%d · %s" % [slot_index + 1, input_key]
	_refresh_reading_guides()


func _refresh_reading_guides() -> void:
	for surface: Control in [_page, _overlay]:
		if surface == null:
			continue
		var guide := surface.find_child("ReadingGuide", true, false) as Label
		if guide != null:
			guide.text = str(guide.get_meta("gamepad_text" if _input_kind == "gamepad" else "keyboard_text"))
			if surface == _page and _screen == "shop" and _input_kind == "gamepad" and _bag_held_uid >= 0:
				guide.text = "整理完成后可用 LB / RB 查看详情"


func _add_reading_guide(parent: Control, keyboard_text: String, gamepad_text: String) -> void:
	var guide := _label(gamepad_text if _input_kind == "gamepad" else keyboard_text, 13, MUTED)
	guide.name = "ReadingGuide"
	guide.set_meta("keyboard_text", keyboard_text)
	guide.set_meta("gamepad_text", gamepad_text)
	guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(guide)


func _reading_footer(parent: Control, close: Button) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	parent.add_child(footer)
	_add_reading_guide(footer, "Tab 选择内容 · PageUp / PageDown 翻页 · Esc 返回", "LB / RB 翻页 · B 返回")
	close.custom_minimum_size.x = 200
	footer.add_child(close)


func _gamepad_reading_target() -> ScrollContainer:
	var surface: Control = _overlay if not _overlay_mode.is_empty() else _page
	var target_name: String = ""
	if not _overlay_mode.is_empty():
		target_name = str({"relic_comparison": "ComparisonScroll", "rune_equip_comparison": "RuneEquipScroll", "rogue_choices": "RogueChoicesScroll"}.get(_overlay_mode, ""))
	elif _screen == "shop" and not _refresh_queued and _bag_held_uid < 0:
		if is_instance_valid(_bag_grid) and _bag_grid.held_uid < 0 and _bag_grid.interaction_enabled:
			target_name = "BackpackDetailsScroll"
	elif _screen == "result":
		target_name = "ResultBuildScroll"
	if target_name.is_empty() or get_viewport().gui_is_dragging():
		return null
	var target := surface.find_child(target_name, true, false) as ScrollContainer
	return target if target != null and target.is_visible_in_tree() else null


func _page_gamepad_reading(event: InputEvent) -> bool:
	if not event is InputEventJoypadButton or not event.pressed or event.device < 0:
		return false
	if event.button_index not in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		return false
	var target: ScrollContainer = _gamepad_reading_target()
	if target == null:
		return false
	var direction: int = -1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
	var page: int = maxi(1, int(target.size.y * 0.8))
	var bar: VScrollBar = target.get_v_scroll_bar()
	var limit: int = maxi(0, ceili(bar.max_value - bar.page))
	target.scroll_vertical = clampi(target.scroll_vertical + direction * page, 0, limit)
	get_viewport().set_input_as_handled()
	return true


func _input(event: InputEvent) -> void:
	if not _capture_action.is_empty():
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
			if not event.pressed or event.echo:
				return
			var key: int = int(event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
			if key == KEY_ESCAPE:
				_cancel_control_capture()
				return
			if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed:
				_set_controls_notice("请使用单个按键，不使用修饰键组合。", RED)
				return
			var error: String = ControlBindings.binding_error(_controls, _capture_action, key)
			if not error.is_empty():
				_set_controls_notice(error, RED)
				return
			var action: String = _capture_action
			var next_bindings: Dictionary = _controls.duplicate(true)
			next_bindings[action] = key
			_capture_action = ""
			set_controls(next_bindings)
			_set_controls_notice("%s已绑定为%s。" % [ControlBindings.action_label(action), ControlBindings.key_label(key)], CYAN)
			var source := _control_buttons.get(action) as Button
			if source != null:
				_focus_later(source)
			controls_changed.emit(_controls.duplicate(true))
			return
		if event is InputEventMouse or event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			if event is InputEventJoypadButton:
				if event.pressed and event.button_index == JOY_BUTTON_B:
					_cancel_control_capture()
				elif event.pressed:
					_set_controls_notice("请按键盘按键；Esc / 手柄B取消。", RED)
			elif event is InputEventMouseButton and event.pressed:
				_set_controls_notice("请按键盘按键；Esc / 手柄B取消。", RED)
		return
	if _page_gamepad_reading(event):
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B and handle_back():
		get_viewport().set_input_as_handled()


func set_progress(starters: Array[String]) -> void:
	_unlocked_starters = ["bone", "ember"]
	for id: String in ["frost", "scatter"]:
		if starters.has(id):
			_unlocked_starters.append(id)
	if not _unlocked_starters.has(_starter):
		_starter = "bone"


func show_title(best: Dictionary) -> void:
	_best = best.duplicate()
	_set_screen("title")
	_background()
	_menu_art()
	var shell := _shell(52, 30)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 46)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(columns)
	var left := VBoxContainer.new()
	left.name = "TitleActions"
	left.custom_minimum_size.x = 520
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	var title := _label("EMBERS", 60, BONE)
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Trebuchet MS", "Avenir Next", "Verdana", "Arial"])
	title_font.font_weight = 800
	title.add_theme_font_override("font", title_font)
	left.add_child(title)
	left.add_child(_label("秘 术 余 烬", 24, PURPLE))
	var start_card := _panel(left)
	start_card.name = "StarterAltar"
	var start_body := _inside(start_card, 12)
	start_body.add_theme_constant_override("separation", 6)
	var starters := HBoxContainer.new()
	starters.add_theme_constant_override("separation", 12)
	start_body.add_child(starters)
	for id: String in ["bone", "ember", "frost", "scatter"]:
		var definition: ContentDef = GameCatalog.weapon(id)
		var option := VBoxContainer.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_constant_override("separation", 4)
		starters.add_child(option)
		var card := _button(definition.display_name, _select_starter.bind(id), Vector2(0, 58))
		card.name = "Starter_" + id
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.toggle_mode = true
		card.disabled = not _unlocked_starters.has(id)
		card.focus_mode = Control.FOCUS_NONE if card.disabled else Control.FOCUS_ALL
		card.button_pressed = _starter == id
		card.add_theme_font_size_override("font_size", 17)
		ButtonSkin.apply(card, "choice")
		_set_button_icon(card, definition)
		option.add_child(card)
		_add_title_choice_mark(card)
	_build_arena_selection(left)
	var start := _button("进入试炼", _start, Vector2(0, 50))
	_accent(start)
	left.add_child(start)
	_focus_later(start)
	var right := VBoxContainer.new()
	right.name = "TitleIllustrationSpace"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	var space := Control.new()
	space.name = "IllustrationBreathingSpace"
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(space)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	shell.add_child(footer)
	footer.add_child(_button("设置", _show_settings.bind(false), Vector2(120, 40)))
	footer.add_child(_button("退出游戏", _quit, Vector2(140, 40)))


func selected_arena() -> String:
	return _arena_id


func set_selected_arena(id: String) -> void:
	if not _overlay_mode.is_empty():
		return
	_arena_id = ArenaCatalog.normalize_id(id)
	if _screen == "title" and _page != null:
		_refresh_arena_selection()


func _build_arena_selection(parent: Control) -> void:
	var card := _panel(parent)
	card.name = "ArenaSelection"
	card.add_theme_stylebox_override("panel", _box(Color(PANEL, 0.96), Color(GOLD, 0.25)))
	var body := _inside(card, 12)
	body.add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	for id: String in ArenaCatalog.IDS:
		var definition: Dictionary = ArenaCatalog.definition(id)
		var option := _button("", _select_arena.bind(id), Vector2(0, 84))
		option.name = "Arena_" + id
		option.toggle_mode = true
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.clip_contents = true
		ButtonSkin.apply(option, "choice")
		grid.add_child(option)
		var inset := MarginContainer.new()
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_margin(inset, 9, 8)
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		option.add_child(inset)
		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 2)
		inset.add_child(content)
		var image := TextureRect.new()
		image.name = "ArenaPreview_" + id
		image.custom_minimum_size.y = 32
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.texture = load(AdventureArt.path(str(definition["texture"]))) as Texture2D
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(image)
		var name_label := _label(str(definition["name"]), 16, BONE)
		name_label.name = "ArenaName_" + id
		content.add_child(name_label)
		_add_title_choice_mark(option)
	_refresh_arena_selection()


func _add_title_choice_mark(button: Button) -> void:
	var mark := TitleChoiceMark.new()
	mark.name = "SelectionMark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.focus_mode = Control.FOCUS_NONE
	button.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _select_arena(id: String) -> void:
	if _screen != "title" or not _overlay_mode.is_empty() or not ArenaCatalog.IDS.has(id):
		return
	_arena_id = id
	_refresh_arena_selection()


func _refresh_arena_selection() -> void:
	for id: String in ArenaCatalog.IDS:
		var option := _page.find_child("Arena_" + id, true, false) as Button
		if option != null:
			option.set_pressed_no_signal(_arena_id == id)
			var mark := option.get_node_or_null("SelectionMark") as Control
			if mark != null:
				mark.queue_redraw()
		var name_label := _page.find_child("ArenaName_" + id, true, false) as Label
		if name_label != null:
			name_label.text = str(ArenaCatalog.definition(id)["name"])
			name_label.add_theme_color_override("font_color", GOLD if _arena_id == id else BONE)


func show_hud() -> void:
	_set_screen("hud")
	_toast.text = ""
	_toast_timer.stop()
	_hud.clear()
	_hud_loadout_key = ""
	var top := PanelContainer.new()
	top.name = "RitualStatus"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_top = 16
	top.offset_right = -24
	top.offset_bottom = 86
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(top)
	_decorate(top, GOLD, true)
	var margin := MarginContainer.new()
	_margin(margin, 18, 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var health_box := VBoxContainer.new()
	health_box.custom_minimum_size.x = 260
	health_box.add_theme_constant_override("separation", 4)
	row.add_child(health_box)
	_hud["health"] = _label("生命  100 / 100", 16, BONE)
	health_box.add_child(_hud["health"])
	var hp := ProgressBar.new()
	hp.custom_minimum_size.y = 9
	hp.show_percentage = false
	hp.add_theme_stylebox_override("fill", _bar_style(RED))
	hp.add_theme_stylebox_override("background", _bar_style(Color("dbd3c3")))
	health_box.add_child(hp)
	_hud["health_bar"] = hp
	for entry: Array in [["wave", "波次  1 / 8"], ["time", "剩余  00:45"], ["gold", "魂屑  0"], ["level", "等级  1"]]:
		var item := _label(str(entry[1]), 17, GOLD if entry[0] == "gold" else BONE)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item)
		_hud[str(entry[0])] = item
	_add_hud_skill(row, "dash", "Dash", "空格：向当前移动方向冲刺；静止时沿面向。\n短冲距离约132，冷却2.4秒；起始短暂闪避，可冲离减速地形。")
	var xp := ProgressBar.new()
	xp.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	xp.offset_left = 26
	xp.offset_right = -26
	xp.offset_top = 91
	xp.offset_bottom = 94
	xp.show_percentage = false
	xp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp.add_theme_stylebox_override("fill", _bar_style(PURPLE))
	xp.add_theme_stylebox_override("background", _bar_style(Color("d9e4df")))
	_page.add_child(xp)
	_hud["xp_bar"] = xp
	var boss := HBoxContainer.new()
	boss.name = "BossStatus"
	boss.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	boss.offset_left = -560
	boss.offset_right = -54
	boss.offset_top = 62
	boss.offset_bottom = 82
	boss.add_theme_constant_override("separation", 12)
	boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(boss)
	var boss_name := _label(GameCatalog.enemy("boss").display_name, 16, RED)
	boss_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boss.add_child(boss_name)
	var boss_hp := ProgressBar.new()
	boss_hp.custom_minimum_size = Vector2(200, 8)
	boss_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	boss_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_hp.show_percentage = false
	boss_hp.add_theme_stylebox_override("fill", _bar_style(RED))
	boss_hp.add_theme_stylebox_override("background", _bar_style(Color("dbd3c3")))
	boss.add_child(boss_hp)
	boss.hide()
	_hud["boss"] = boss
	_hud["boss_bar"] = boss_hp
	var minimap := MINIMAP_VIEW.new()
	minimap.name = "ArenaMinimap"
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -216
	minimap.offset_right = -24
	minimap.offset_top = 104
	minimap.offset_bottom = 230
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.focus_mode = Control.FOCUS_NONE
	_page.add_child(minimap)
	_hud["minimap"] = minimap
	var bottom := PanelContainer.new()
	bottom.name = "RitualEquipment"
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -104
	bottom.offset_bottom = -18
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(bottom)
	_decorate(bottom, GOLD, true)
	var bottom_margin := MarginContainer.new()
	_margin(bottom_margin, 16, 10)
	bottom.add_child(bottom_margin)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 16)
	bottom_margin.add_child(bottom_row)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 12)
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(slots)
	_hud["slots"] = slots
	var active_slots := HBoxContainer.new()
	active_slots.name = "ActiveSkillSlots"
	active_slots.add_theme_constant_override("separation", 10)
	active_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_row.add_child(active_slots)
	_add_active_skill_slot(active_slots, "pulse", "Pulse")
	_add_active_skill_slot(active_slots, "secondary", "Secondary")



func update_hud(snapshot: Dictionary) -> void:
	if _screen != "hud" or _hud.is_empty():
		return
	_hud_skill_snapshot = {"health": snapshot.get("health", 0.0), "benchmark": snapshot.get("benchmark", false)}
	for key: String in ["dash", "skills"]:
		var skill: Variant = snapshot.get(key, {})
		_hud_skill_snapshot[key] = skill.duplicate(true) if skill is Dictionary or skill is Array else skill
	var hp := float(snapshot.get("health", 0.0))
	var maximum := maxf(1.0, float(snapshot.get("max_health", 1.0)))
	_hud["health"].text = "生命  %d / %d" % [ceili(hp), ceili(maximum)]
	_hud["health_bar"].max_value = maximum
	_hud["health_bar"].value = hp
	var boss_health := float(snapshot.get("boss_health", 0))
	var boss_max := float(snapshot.get("boss_max_health", 0))
	var boss_alive: bool = boss_max > 0.0 and boss_health > 0.0
	_hud["wave"].text = "波次  %d / %d" % [int(snapshot.get("wave", 1)), GameCatalog.WAVE_DEFS.size()]
	var time_left := maxf(0.0, float(snapshot.get("time_left", 0)))
	var seconds := ceili(time_left)
	var timer: Label = _hud["time"]
	timer.text = "剩余  %02d:%02d" % [seconds / 60, seconds % 60]
	timer.add_theme_color_override("font_color", BONE)
	timer.add_theme_constant_override("outline_size", 0)
	_hud["gold"].text = "魂屑  %d" % int(snapshot.get("gold", 0))
	_hud["level"].text = "等级  %d" % int(snapshot.get("level", 1))
	if bool(snapshot.get("benchmark", false)):
		_hud["wave"].text = "性能测试"
		timer.text = "采样  %02d:%02d" % [seconds / 60, seconds % 60]
		_hud["gold"].text = "敌人  %d" % int(snapshot.get("enemies", 0))
		_hud["level"].text = "投射物  %d" % int(snapshot.get("projectiles", 0))
	elif boss_alive:
		_hud["wave"].text = "击败首领"
		timer.text = "限时  %02d:%02d" % [seconds / 60, seconds % 60]
		if time_left <= 10.0:
			timer.add_theme_color_override("font_color", CORAL)
			timer.add_theme_color_override("font_outline_color", BONE)
			timer.add_theme_constant_override("outline_size", 2)
	_hud["xp_bar"].max_value = maxf(1, float(snapshot.get("xp_needed", 1)))
	_hud["xp_bar"].value = float(snapshot.get("xp", 0))
	_hud["boss"].visible = boss_alive
	_hud["boss_bar"].max_value = maxf(1, boss_max)
	_hud["boss_bar"].value = boss_health
	(_hud["minimap"] as MinimapView).update_snapshot(snapshot.get("minimap"))
	_update_dash_hud(snapshot)
	_update_pulse_hud(snapshot)
	var loadout: Array = snapshot.get("loadout", [])
	var key := str(loadout)
	if key != _hud_loadout_key:
		_hud_loadout_key = key
		_update_hud_slots(loadout)


func _add_hud_skill(row: HBoxContainer, key: String, prefix: String, tooltip: String) -> void:
	var indicator := VBoxContainer.new()
	indicator.name = prefix + "Skill"
	indicator.custom_minimum_size.x = 106
	indicator.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	indicator.add_theme_constant_override("separation", 3)
	indicator.mouse_filter = Control.MOUSE_FILTER_PASS
	indicator.focus_mode = Control.FOCUS_NONE
	indicator.tooltip_text = tooltip
	row.add_child(indicator)
	var label := _label("", 14, CYAN)
	label.name = prefix + "Status"
	label.focus_mode = Control.FOCUS_NONE
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	indicator.add_child(label)
	var meter := ProgressBar.new()
	meter.name = prefix + "Cooldown"
	meter.custom_minimum_size.y = 5
	meter.max_value = 1.0
	meter.step = 0.0
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.focus_mode = Control.FOCUS_NONE
	meter.add_theme_stylebox_override("fill", _bar_style(CYAN))
	meter.add_theme_stylebox_override("background", _bar_style(Color("d9e4df")))
	indicator.add_child(meter)
	indicator.hide()
	_hud[key] = indicator
	_hud[key + "_label"] = label
	_hud[key + "_bar"] = meter


func _clear_hud_skill(key: String) -> void:
	_hud[key].hide()
	_hud[key + "_label"].text = ""
	_hud[key + "_bar"].value = 0.0


func _update_dash_hud(snapshot: Dictionary) -> void:
	var indicator: Control = _hud["dash"]
	var label: Label = _hud["dash_label"]
	var meter: ProgressBar = _hud["dash_bar"]
	var value: Variant = snapshot.get("dash", {})
	if bool(snapshot.get("benchmark", false)) or not value is Dictionary or value.is_empty() or float(snapshot.get("health", 0.0)) <= 0.0:
		_clear_hud_skill("dash")
		return
	var dash: Dictionary = value
	var remaining: float = float(dash.get("cooldown_left", 0.0))
	var total: float = float(dash.get("cooldown_total", 0.0))
	remaining = maxf(0.0, remaining) if is_finite(remaining) else 0.0
	total = maxf(0.0, total) if is_finite(total) else 0.0
	var active: bool = bool(dash.get("active", false))
	var ready: bool = bool(dash.get("ready", false))
	var next_total: float = _skill_tooltip_value(dash.get("next_cooldown_total", total), DashRules.COOLDOWN)
	var key: String = "A" if _input_kind == "gamepad" else ControlBindings.key_label(int(_controls["dash"]))
	indicator.tooltip_text = "%s：向当前移动方向冲刺；静止时沿面向。\n短冲距离约132，冷却%s秒；起始短暂闪避，可冲离减速地形。" % [key, _skill_number(next_total)]
	if remaining > 0.0 and total > 0.0 and not is_equal_approx(total, next_total):
		indicator.tooltip_text += "\n本次冷却总长%s秒；改装仅影响下次施放。" % _skill_number(total)
	indicator.show()
	if active:
		label.text = "冲刺中"
		label.add_theme_color_override("font_color", GOLD)
		meter.value = 0.0
	elif ready:
		label.text = "冲刺 · " + key
		label.add_theme_color_override("font_color", CYAN)
		meter.value = 1.0
	else:
		label.text = "冲刺 %.1f秒" % (ceilf(remaining * 10.0) / 10.0) if remaining > 0.0 else "冲刺"
		label.add_theme_color_override("font_color", MUTED)
		meter.value = clampf(1.0 - remaining / total, 0.0, 1.0) if remaining > 0.0 and total > 0.0 else 0.0


func _add_active_skill_slot(parent: HBoxContainer, key: String, prefix: String) -> void:
	var card := PanelContainer.new()
	card.name = prefix + "Skill"
	card.custom_minimum_size = Vector2(104, 64)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.focus_mode = Control.FOCUS_NONE
	var style := _box(Color("e5efe9"), Color(CYAN, 0.45))
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var badge := _label("", 14, CYAN)
	badge.name = prefix + "Key"
	badge.custom_minimum_size.x = 18
	badge.clip_text = true
	badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(badge)
	var icon := TextureRect.new()
	icon.name = prefix + "Icon"
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var clock := _label("", 12, CYAN)
	clock.name = prefix + "Time"
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(clock)
	var label := _label("空槽", 12, MUTED)
	label.name = prefix + "Status"
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(label)
	var meter := ProgressBar.new()
	meter.name = prefix + "Cooldown"
	meter.custom_minimum_size.y = 5
	meter.max_value = 1.0
	meter.step = 0.0
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_theme_stylebox_override("fill", _bar_style(CYAN))
	meter.add_theme_stylebox_override("background", _bar_style(Color("c9d9d2")))
	box.add_child(meter)
	_hud[key] = card
	_hud[key + "_label"] = label
	_hud[key + "_bar"] = meter
	_hud[key + "_key"] = badge
	_hud[key + "_icon"] = icon
	_hud[key + "_time"] = clock
	card.hide()


func _update_pulse_hud(snapshot: Dictionary) -> void:
	var values: Variant = snapshot.get("skills", [])
	for index: int in 2:
		var key: String = "pulse" if index == 0 else "secondary"
		var indicator: Control = _hud[key]
		var label: Label = _hud[key + "_label"]
		var meter: ProgressBar = _hud[key + "_bar"]
		var badge: Label = _hud[key + "_key"]
		var icon: TextureRect = _hud[key + "_icon"]
		var clock: Label = _hud[key + "_time"]
		if bool(snapshot.get("benchmark", false)) or float(snapshot.get("health", 0.0)) <= 0.0:
			_clear_hud_skill(key)
			badge.text = ""
			clock.text = ""
			icon.texture = null
			continue
		var skill: Dictionary = {}
		if values is Array and index < values.size() and values[index] is Dictionary:
			skill = values[index]
		var action: String = "pulse" if index == 0 else "skill_secondary"
		var input_key: String = ("X" if index == 0 else "Y") if _input_kind == "gamepad" else ControlBindings.key_label(int(_controls[action]))
		badge.text = input_key
		indicator.show()
		var id: String = str(skill.get("id", ""))
		var available: bool = bool(skill.get("available", false)) and int(skill.get("uid", -1)) >= 0 and not id.is_empty()
		var definition: ContentDef = GameCatalog.skill(id) if available else null
		if definition == null:
			label.text = "空槽"
			label.add_theme_color_override("font_color", MUTED)
			clock.text = "—"
			clock.add_theme_color_override("font_color", MUTED)
			icon.texture = null
			meter.value = 0.0
			indicator.tooltip_text = input_key + " · 空槽"
			indicator.set_meta("skill_uid", -1)
			continue
		var remaining: float = float(skill.get("cooldown_remaining", 0.0))
		var total: float = float(skill.get("cooldown_duration", 0.0))
		remaining = maxf(0.0, remaining) if is_finite(remaining) else 0.0
		total = maxf(0.0, total) if is_finite(total) else 0.0
		var ready: bool = bool(skill.get("ready", false)) and remaining <= 0.0
		label.text = definition.display_name
		label.add_theme_color_override("font_color", CYAN if ready else MUTED)
		clock.text = "就绪" if ready else "%.1f" % (ceilf(remaining * 10.0) / 10.0) if remaining > 0.0 else "—"
		clock.add_theme_color_override("font_color", CYAN if ready else MUTED)
		var icon_id: String = definition.icon
		if str(icon.get_meta("skill_icon", "")) != icon_id or icon.texture == null:
			icon.texture = load(AdventureArt.path("res://assets/icons/%s.svg" % icon_id))
			icon.set_meta("skill_icon", icon_id)
		icon.modulate = Color.WHITE if ready else Color(0.65, 0.72, 0.70)
		meter.value = 1.0 if ready else clampf(1.0 - remaining / total, 0.0, 1.0) if remaining > 0.0 and total > 0.0 else 0.0
		indicator.tooltip_text = "%s · %s阶\n%s · 伤害%s · 范围%s · 冷却%s秒" % [definition.display_name, _rank_name(int(skill.get("rank", 1))), input_key, _skill_number(float(skill.get("damage", 0.0))), _skill_number(float(skill.get("radius", 0.0))), _skill_number(total)]
		if id == "pulse":
			indicator.tooltip_text = "%s · %s阶\n%s · 击退%s · 减速%s%%\n范围%s · 冷却%s秒" % [definition.display_name, _rank_name(int(skill.get("rank", 1))), input_key, _skill_number(PulseRules.PUSH_DISTANCE), _skill_number((1.0 - PulseRules.HINDER_FACTOR) * 100.0), _skill_number(float(skill.get("radius", 0.0))), _skill_number(total)]
		indicator.set_meta("skill_uid", int(skill["uid"]))


static func _skill_tooltip_value(value: Variant, fallback: float) -> float:
	var number: float = float(value) if value is float or value is int else fallback
	return number if is_finite(number) and number > 0.0 else fallback


static func _skill_number(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")


func show_shop() -> void:
	_set_screen("shop")
	_selected_rune = -1
	_requested_shop_focus = "buy:0"
	_build_shop()


func show_upgrades(during_combat: bool = false) -> void:
	_set_screen("upgrades")
	_upgrades_during_combat = during_combat
	_build_upgrades()


func show_pause() -> void:
	var returning_from_settings: bool = _overlay_mode == "settings_pause"
	_begin_overlay("pause")
	var body := _modal("试炼暂停", Vector2(500, 430))
	_spacer(body, 12)
	var resume := _button("继续试炼", _resume, Vector2(0, 48))
	_accent(resume)
	body.add_child(resume)
	var settings := _button("设置", _show_settings.bind(true), Vector2(0, 46))
	body.add_child(settings)
	body.add_child(_button("返回主菜单", _menu, Vector2(0, 46)))
	body.add_child(_button("退出游戏", _quit, Vector2(0, 46)))
	_focus_later(settings if returning_from_settings else resume)


func hide_pause() -> void:
	var restore_focus: bool = not _overlay_mode.is_empty()
	_clear_controls_modal_state()
	_clear(_overlay)
	_overlay_mode = ""
	_page.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	if restore_focus:
		_restore_page_focus()
	_page_focus = null
	_page_focus_id = ""
	if is_instance_valid(_bag_grid) and _screen == "shop":
		_bag_grid.interaction_enabled = true


func handle_back() -> bool:
	if not _capture_action.is_empty():
		_cancel_control_capture()
		return true
	if _overlay_mode in ["controls_title", "controls_pause"]:
		_show_settings(_overlay_mode == "controls_pause")
		return true
	if _overlay_mode in ["relic_details", "relic_comparison", "rune_equip_comparison", "rogue_choices"]:
		hide_pause()
		return true
	if _overlay_mode == "settings_pause":
		show_pause()
		return true
	if _overlay_mode == "settings_title":
		hide_pause()
		return true
	if _screen == "shop" and is_instance_valid(_bag_grid) and _bag_grid.cancel_placement(true):
		return true
	return false


func _begin_overlay(mode: String) -> void:
	_clear_controls_modal_state()
	var holding_source: Button
	if is_instance_valid(_bag_grid):
		if _bag_grid.held_uid >= 0 and not get_viewport().gui_is_dragging():
			holding_source = _shop_focus_button("bag_move:%d" % int(_bag_grid.held_uid))
		_bag_grid.cancel_placement()
		_bag_grid.interaction_enabled = false
	if _overlay_mode.is_empty():
		var current: Control = holding_source if holding_source != null else get_viewport().gui_get_focus_owner()
		_page_focus = current if current != null and _page.is_ancestor_of(current) else null
		_page_focus_id = str(current.get_meta("shop_focus_id", "")) if _page_focus != null else ""
	_overlay_mode = mode
	_page.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_clear(_overlay)


func _restore_page_focus() -> void:
	if is_instance_valid(_page_focus) and _page_focus.is_inside_tree() and _page.is_ancestor_of(_page_focus):
		_focus_later(_page_focus)
	elif _screen == "shop":
		_restore_shop_focus(_page_focus_id)
	else:
		var candidate: Button = _first_page_button(_page)
		if candidate != null:
			_focus_later(candidate)


func _first_page_button(node: Node) -> Button:
	if node is Button and not node.disabled and node.is_visible_in_tree():
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _first_page_button(child)
		if found != null:
			return found
	return null


func show_result(victory: bool, reason: String, best: Dictionary) -> void:
	_best = best.duplicate()
	_set_screen("result")
	_background()
	var shell := _shell(64, 34)
	var title := _label("余烬未灭" if victory else "试炼终止", 40, GOLD if victory else BONE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(title)
	var description := _wrap(reason, 17, MUTED)
	description.name = "ResultReason"
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(description)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(columns)
	var summary_card := _panel(columns)
	summary_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _inside(summary_card, 22)
	body.add_theme_constant_override("separation", 12)
	_section_heading(body, "本局记录", GOLD, 18)
	body.add_child(_wrap("抵达波次  %d / %d   ·   击杀  %d   ·   等级  %d\n存活时间  %02d:%02d   ·   剩余魂屑  %d" % [run.wave, GameCatalog.WAVE_DEFS.size(), run.kills, run.level, int(run.elapsed) / 60, int(run.elapsed) % 60, run.gold], 18, BONE))
	var received := _wrap("实际承伤  %.1f   ·   受击  %d 次" % [run.damage_taken, run.hits_taken], 18, RED)
	received.name = "DamageReceived"
	body.add_child(received)
	var last_hit_text := _last_hit_text()
	if not last_hit_text.is_empty():
		var last_hit := _wrap(last_hit_text, 14, MUTED)
		last_hit.name = "LastHit"
		body.add_child(last_hit)
	_rule(body)
	_section_heading(body, "最终构筑", PURPLE, 16)
	var build_scroll := ScrollContainer.new()
	build_scroll.name = "ResultBuildScroll"
	build_scroll.custom_minimum_size.y = 84
	build_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	build_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	build_scroll.focus_mode = Control.FOCUS_ALL
	body.add_child(build_scroll)
	build_scroll.add_child(_wrap(_loadout_text(), 15, BONE))
	_add_reading_guide(body, "滚轮查看最终构筑", "LB / RB 查看最终构筑")
	body.add_child(_wrap("最佳记录：" + _best_text(best), 13, MUTED))
	var damage_card := _panel(columns)
	damage_card.name = "DamageContribution"
	damage_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var damage_body := _inside(damage_card, 22)
	damage_body.add_theme_constant_override("separation", 12)
	_section_heading(damage_body, "法器伤害贡献", GOLD, 18)
	_enable_tooltip(damage_card, "累计实际伤害，包含已出售法器。")
	var contributions := _damage_contributions()
	var total := 0.0
	for contribution: Dictionary in contributions:
		total += float(contribution["amount"])
	if contributions.is_empty():
		var empty := _wrap("尚无实际伤害记录", 18, MUTED)
		empty.name = "DamageEmpty"
		damage_body.add_child(empty)
	else:
		for contribution: Dictionary in contributions:
			var definition: ContentDef = contribution["definition"]
			var amount := float(contribution["amount"])
			var row := VBoxContainer.new()
			row.name = "Damage_" + definition.id
			row.add_theme_constant_override("separation", 5)
			damage_body.add_child(row)
			var heading := HBoxContainer.new()
			row.add_child(heading)
			var name_label := _label(definition.display_name, 16, BONE)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			heading.add_child(name_label)
			heading.add_child(_label("%.1f   ·   %.1f%%" % [amount, amount / total * 100.0], 16, GOLD))
			var bar := ProgressBar.new()
			bar.custom_minimum_size.y = 5
			bar.max_value = total
			bar.value = amount
			bar.show_percentage = false
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.add_theme_stylebox_override("fill", _bar_style(Color(definition.color, 0.85)))
			bar.add_theme_stylebox_override("background", _bar_style(Color("e0e5dc")))
			row.add_child(bar)
		damage_body.add_child(_label("实际总伤害  %.1f" % total, 14, MUTED))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	shell.add_child(actions)
	var restart := _button("再次试炼", _start, Vector2(200, 48))
	_accent(restart)
	actions.add_child(restart)
	actions.add_child(_button("返回主菜单", _menu, Vector2(200, 48)))
	_focus_later(restart)


func _last_hit_text() -> String:
	var hit: Dictionary = run.last_hit
	var amount := float(hit.get("amount", 0.0))
	if hit.is_empty() or amount <= 0.0:
		return ""
	var definition: ContentDef = GameCatalog.enemy(str(hit.get("source_id", "")))
	var source := "未知来源" if definition == null else definition.display_name
	var attack := str({"contact": "接触攻击", "projectile": "弹丸", "ritual": "仪式"}.get(str(hit.get("kind", "")), "未知攻击"))
	var wave := int(hit.get("wave", 0))
	var wave_text := " · 第%d波" % wave if wave > 0 else ""
	return "最后承伤：%s / %s · 生命损失 %.1f%s" % [source, attack, amount, wave_text]


func _damage_contributions() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for definition: ContentDef in GameCatalog.weapons():
		var amount := maxf(0.0, float(run.damage_dealt_by_weapon.get(definition.id, 0.0)))
		if amount > 0.0:
			rows.append({"definition": definition, "amount": amount})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["amount"]) > float(b["amount"]))
	return rows


func notify(message: String) -> void:
	if _toast == null:
		return
	if _screen == "hud":
		_toast.hide()
		_toast.text = ""
		_toast_timer.stop()
		return
	_toast.text = message
	_toast.add_theme_font_size_override("font_size", 16)
	_toast.add_theme_stylebox_override("normal", _box(PANEL_LIGHT, GOLD))
	_toast.clip_text = false
	_toast.max_lines_visible = -1
	_toast.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -430
	_toast.offset_right = 430
	_toast.offset_top = -218
	_toast.offset_bottom = -178
	_toast.show()
	_toast_timer.start(2.8)


func _build_shop() -> void:
	if _overlay_mode in ["relic_comparison", "rune_equip_comparison", "rogue_choices"]:
		hide_pause()
	_shop_epoch += 1
	if is_instance_valid(_bag_grid):
		_bag_grid.interaction_enabled = false
	_bag_grid = null
	_bag_details = null
	_bag_status = null
	var focus_id := _requested_shop_focus
	_requested_shop_focus = ""
	if focus_id.is_empty():
		var previous := get_viewport().gui_get_focus_owner()
		if previous != null:
			focus_id = str(previous.get_meta("shop_focus_id", ""))
	_clear(_page)
	_background()
	if run == null:
		return
	if _selected_rune >= run.rune_bag.size():
		_selected_rune = -1
	var shell := _shell(32, 24)
	shell.add_theme_constant_override("separation", 10)
	var heading := HBoxContainer.new()
	shell.add_child(heading)
	var title := _label("祭坛商店", 31, BONE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var rogue_state: Dictionary = run.rogue_choices()
	var rogue_text: String = "秘术抉择 · 核心待选" if str(rogue_state.get("core_id", "")).is_empty() else "秘术抉择 · 当前构筑"
	if bool(rogue_state.get("reward_pending", false)):
		rogue_text = "秘术抉择 · 符文待领"
	var ritual := _shop_button(rogue_text, _show_rogue_choices, "rogue", Vector2(240, 38))
	ritual.name = "OpenRogueChoices"
	ritual.add_theme_font_size_override("font_size", 15)
	ritual.tooltip_text = "选择本局流派、可跳过的追猎契约与下一波敌群；可稍后决定。"
	heading.add_child(ritual)
	heading.add_child(_label("波次 %d 完成   /   魂屑 %d" % [run.wave, run.gold], 22, GOLD))
	var guide := _wrap(_rune_guide(), 15, PURPLE if _selected_rune >= 0 else MUTED)
	guide.name = "RuneGuide"
	guide.visible = _selected_rune >= 0
	shell.add_child(guide)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(columns)
	var goods := VBoxContainer.new()
	goods.custom_minimum_size.x = 520
	goods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(goods)
	var stock_heading := HBoxContainer.new()
	stock_heading.add_theme_constant_override("separation", 14)
	goods.add_child(stock_heading)
	var lock_count := _label("本次供奉 · 已锁 %d / %d" % [run.locked_offer_count(), RunState.SHOP_LOCK_CAP], 18, GOLD)
	lock_count.name = "ShopLockCount"
	stock_heading.add_child(lock_count)
	var stock_rule := RitualRule.new()
	stock_rule.custom_minimum_size.x = 28
	stock_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_heading.add_child(stock_rule)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	goods.add_child(grid)
	for index in range(run.offers.size()):
		_offer_card(grid, index)
	_build_backpack(columns)
	var stats_card := _panel(shell)
	var stats_margin := MarginContainer.new()
	_margin(stats_margin, 14, 10)
	stats_card.add_child(stats_margin)
	stats_margin.add_child(_label(_stats_text(), 15, BONE))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	shell.add_child(footer)
	var reroll := _shop_button(("刷新未锁  %d 魂屑" if run.locked_offer_count() > 0 else "刷新  %d 魂屑") % run.reroll_cost(), _reroll, "reroll", Vector2(180, 46))
	reroll.add_theme_font_size_override("font_size", 16)
	reroll.tooltip_text = "刷新仅替换未锁定商品；锁定商品跨波保留，价格随波次调整。"
	footer.add_child(reroll)
	var hint := _label("购买自动找空位 · 法器全部生效", 14, MUTED)
	hint.name = "ShopLockGuide"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var next := _shop_button("开始下一波", _next_wave, "next_wave", Vector2(210, 46))
	_accent(next)
	footer.add_child(next)
	_restore_shop_focus.call_deferred(focus_id, _shop_epoch)


func _show_rogue_choices(keep_notice: bool = false) -> void:
	if _screen != "shop" or _refresh_queued or not _overlay_mode.is_empty() or run == null:
		return
	if not keep_notice:
		_rogue_notice = ""
	var source: Button = _shop_focus_button("rogue")
	if source != null:
		source.grab_focus()
	_begin_overlay("rogue_choices")
	_rogue_epoch += 1
	var epoch: int = _rogue_epoch
	var choices: Dictionary = run.rogue_choices()
	var body := _modal("秘术抉择", Vector2(1030, 650))
	body.name = "RogueChoices"
	body.add_theme_constant_override("separation", 8)
	var note := _wrap(_rogue_notice if not _rogue_notice.is_empty() else "核心每局限选一个 · 路线仅影响下一波", 14, CYAN if not _rogue_notice.is_empty() else MUTED)
	note.name = "RogueNotice"
	body.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.name = "RogueChoicesScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	scroll.gui_input.connect(_rogue_scroll_input.bind(scroll, epoch))
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	_section_heading(content, "I · 本局核心", GOLD, 18)
	var current: String = str(choices.get("core_id", ""))
	if current.is_empty():
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 14)
		content.add_child(cards)
		for option: Dictionary in choices.get("core_options", []):
			var card := _panel(cards)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var inside := _inside(card, 12)
			inside.add_child(_label(str(option["name"]), 20, BONE))
			inside.add_child(_wrap(_core_description(option), 14, MUTED))
			var choose := _button("选择 · " + str(option["name"]), _rogue_action.bind("core", str(option["id"]), epoch), Vector2(0, 36))
			choose.name = "RogueCore_" + str(option["id"])
			choose.disabled = not bool(choices.get("can_choose_core", false))
			inside.add_child(choose)
		if not bool(choices.get("can_choose_core", false)):
			content.add_child(_wrap("完成首波后即可选择；免费法器需要真实空位，可先返回整理。", 13, GOLD))
	else:
		for option: Dictionary in choices.get("core_options", []):
			if str(option["id"]) == current:
				content.add_child(_wrap("已选 · %s\n%s" % [option["name"], _core_description(option)], 14, CYAN))
	_section_heading(content, "II · 追猎契约", CORAL, 18)
	if bool(choices.get("altar_available", false)):
		content.add_child(_wrap("第3波追加冲锋追猎者（生命×%.1f、移速×%.2f）。击败后自选Ⅰ阶符文；仅存活到波末不算完成。" % [RogueRules.HUNTER_HEALTH_FACTOR, RogueRules.HUNTER_SPEED_FACTOR], 14, MUTED))
		var actions := HBoxContainer.new()
		content.add_child(actions)
		var accept := _button("接受追猎 · 自选符文", _rogue_action.bind("altar", "accept", epoch), Vector2(0, 36))
		accept.name = "RogueAltarAccept"
		accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(accept)
		var decline := _button("跳过契约", _rogue_action.bind("altar", "decline", epoch), Vector2(0, 36))
		decline.name = "RogueAltarDecline"
		decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(decline)
	else:
		var altar_text: String = "第2波结束后开放 · 可跳过"
		if str(choices.get("altar_choice", "")) == "declined":
			altar_text = "本局已跳过追猎契约。"
		elif str(choices.get("altar_choice", "")) == "accepted":
			if bool(choices.get("hunter_defeated", false)):
				altar_text = "已击败追猎者。" if bool(choices.get("reward_pending", false)) else "已击败追猎者，符文奖励已领取。"
			else:
				altar_text = "第3波已结束，追猎契约未完成。" if run.wave >= int(choices.get("altar_wave", 3)) else "已接受：第3波击败追猎者后，波间领取符文。"
		elif run.wave > 2:
			altar_text = "本局已错过追猎祭坛；下一局第2波结束后可选择。"
		content.add_child(_wrap(altar_text, 14, MUTED))
	if bool(choices.get("reward_pending", false)):
		content.add_child(_wrap("契约奖励待领：任选一枚Ⅰ阶符文。空间不足时奖励保留，可返回整理后领取。", 14, CYAN))
		var rewards := HBoxContainer.new()
		content.add_child(rewards)
		for rune: ContentDef in GameCatalog.runes():
			var claim := _button("领取 · " + rune.display_name, _rogue_action.bind("reward", rune.id, epoch), Vector2(0, 36))
			claim.name = "RogueReward_" + rune.id
			claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			claim.disabled = not bool(choices.get("can_claim_reward", false))
			rewards.add_child(claim)
	_section_heading(content, "III · 下一波路线", PURPLE, 18)
	if bool(choices.get("can_choose_route", false)):
		var routes := HBoxContainer.new()
		routes.add_theme_constant_override("separation", 12)
		content.add_child(routes)
		for option: Dictionary in choices.get("route_options", []):
			var card := _panel(routes)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var inside := _inside(card, 10)
			inside.add_child(_wrap(str(option["description"]), 13, MUTED))
			var selected: bool = str(option["id"]) == str(choices.get("route", "balanced"))
			var select := _button(("已选 · " if selected else "选择 · ") + str(option["name"]), _rogue_action.bind("route", str(option["id"]), epoch), Vector2(0, 36))
			select.name = "RogueRoute_" + str(option["id"])
			select.add_theme_font_size_override("font_size", 14)
			if selected:
				_accent(select)
			inside.add_child(select)
	else:
		content.add_child(_wrap("首领战使用固定敌群；普通波结束后可选择下一波路线。", 14, MUTED))
	var close := _button("返回商店", _close_rogue_choices.bind(epoch), Vector2(0, 40))
	close.name = "CloseRogueChoices"
	_accent(close)
	_reading_footer(body, close)
	_focus_later(_first_page_button(content) if _first_page_button(content) != null else close)


func _core_description(option: Dictionary) -> String:
	return str(option["description"]).replace("；每局只选一个核心。", "。")


func _rogue_action(kind: String, id: String, epoch: int) -> void:
	if _screen != "shop" or _overlay_mode != "rogue_choices" or _refresh_queued or epoch != _rogue_epoch:
		return
	_rogue_epoch += 1
	var reopen_token: int = _rogue_epoch
	var state: RunState = run
	hide_pause()
	var success: bool = false
	match kind:
		"core": success = run.choose_core(id)
		"altar": success = run.choose_altar(id == "accept")
		"route": success = run.choose_route(id)
		"reward": success = run.claim_altar_rune(id)
	_rogue_notice = _rogue_success_text(kind, id) if success else run.last_error
	feedback.emit("buy" if success else "hurt")
	_queue_refresh()
	_reopen_rogue_choices.call_deferred(state, reopen_token)


func _rogue_success_text(kind: String, id: String) -> String:
	match kind:
		"core": return "已选择%s，所需法器已补齐。可返回背包装符与整理。" % str(RogueRules.core(id).get("name", ""))
		"altar": return "已接受追猎：第3波击败追猎者后，波间任选符文。" if id == "accept" else "已跳过本局追猎契约。"
		"route":
			var option: Dictionary = RogueRules.route(id)
			return "下一波路线：%s。%s" % [option.get("name", ""), option.get("description", "")]
		"reward": return "%s已放入背包；本次契约奖励已领取。" % GameCatalog.rune(id).display_name
	return "抉择已生效。"


func _reopen_rogue_choices(state: RunState, token: int) -> void:
	if run == state and _rogue_epoch == token and _screen == "shop" and _overlay_mode.is_empty() and not _refresh_queued:
		_show_rogue_choices(true)


func _close_rogue_choices(epoch: int) -> void:
	if _screen == "shop" and _overlay_mode == "rogue_choices" and epoch == _rogue_epoch:
		hide_pause()


func _rogue_scroll_input(event: InputEvent, scroll: ScrollContainer, epoch: int) -> void:
	if _overlay_mode != "rogue_choices" or epoch != _rogue_epoch or not event is InputEventKey or not event.pressed:
		return
	var page: int = maxi(1, int(scroll.size.y * 0.8))
	match event.keycode:
		KEY_PAGEDOWN: scroll.scroll_vertical += page
		KEY_PAGEUP: scroll.scroll_vertical -= page
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return
	scroll.accept_event()


func _backpack_default_hint() -> String:
	return "在「拿起」按A；持物用左杆 / 十字移动，A放置、X旋转、B取消" if _input_kind == "gamepad" else "拖拽整理 · R旋转 · Esc取消"


func _backpack_move_tooltip() -> String:
	return "A拿起后，用左杆 / 十字键移动、A放置、X旋转、B取消。" if _input_kind == "gamepad" else "拿起后用方向键移动、Enter放置、R旋转、Esc取消；也可直接拖拽。"


func _backpack_rotate_text() -> String:
	return "旋转 X" if _input_kind == "gamepad" else "旋转 R"


func _backpack_rotate_tooltip() -> String:
	return "A确定旋转按钮；持物时X旋转、A放置、B取消。" if _input_kind == "gamepad" else "旋转选中物品；整理时也可按R，Enter放置、Esc取消。"


func _build_backpack(parent: Control) -> void:
	var snapshot: Dictionary = run.backpack_snapshot()
	var items: Array = snapshot["items"]
	if run.backpack_item(_bag_selected_uid).is_empty():
		_bag_selected_uid = int(items[0]["uid"]) if not items.is_empty() else -1
	if run.backpack_item(_bag_held_uid).is_empty():
		_bag_held_uid = -1
	_selected_rune = run.rune_index_for_uid(_bag_selected_uid)
	var card := _panel(parent, Vector2(650, 0))
	card.name = "BackpackPanel"
	SHOP_PANEL_SKIN.apply(card, CYAN, true)
	var body := _inside(card, 14)
	body.add_theme_constant_override("separation", 6)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var title := _label("秘术行囊", 20, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var capacity := _label("占格 %d / %d · 法器 %d · 技能 %d/2" % [int(snapshot["used_cells"]), int(snapshot["total_cells"]), run.loadout.size(), run.active_skills.size()], 14, CYAN)
	capacity.name = "BackpackCapacity"
	heading.add_child(capacity)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	_bag_grid = BACKPACK_GRID.new()
	_bag_grid.name = "BackpackGrid"
	_bag_grid.set_skill_bindings(_controls)
	_bag_grid.configure(snapshot, _shop_epoch, _bag_selected_uid)
	_bag_grid.set_input_device(_input_kind)
	_bag_grid.item_selected.connect(_bp_select.bind(_shop_epoch))
	_bag_grid.move_requested.connect(_bp_move.bind(_shop_epoch))
	_bag_grid.merge_requested.connect(_bp_merge.bind(_shop_epoch))
	_bag_grid.rune_requested.connect(_bp_equip.bind(_shop_epoch))
	_bag_grid.holding_changed.connect(_bp_holding.bind(_shop_epoch))
	_bag_grid.hint_changed.connect(_bp_hint.bind(_shop_epoch))
	_bag_grid.placement_cancelled.connect(_bp_cancelled.bind(_shop_epoch))
	columns.add_child(_bag_grid)
	var scroll := ScrollContainer.new()
	scroll.name = "BackpackDetailsScroll"
	scroll.custom_minimum_size.x = 244
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	columns.add_child(scroll)
	_bag_details = VBoxContainer.new()
	_bag_details.name = "BackpackDetails"
	_bag_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_details.add_theme_constant_override("separation", 6)
	scroll.add_child(_bag_details)
	_build_backpack_details()
	_add_reading_guide(body, "滚轮查看物品详情", "LB / RB 查看物品详情")
	_bag_status = _wrap(_backpack_default_hint(), 13, MUTED)
	_bag_hint_is_default = true
	_bag_status.name = "BackpackHint"
	_bag_status.custom_minimum_size.y = 32
	body.add_child(_bag_status)
	var expansion := HBoxContainer.new()
	expansion.add_theme_constant_override("separation", 10)
	body.add_child(expansion)
	var cost: int = int(snapshot.get("expansion_cost", 0))
	var expand_text: String = "背包已扩满" if int(snapshot["height"]) >= int(snapshot["max_height"]) else "扩容一排 · %d魂屑" % cost
	var expand := _shop_button(expand_text, _bp_expand, "bag_expand", Vector2(180, 34))
	expand.name = "ExpandBackpack"
	expand.add_theme_font_size_override("font_size", 14)
	expand.disabled = int(snapshot["height"]) >= int(snapshot["max_height"])
	expand.tooltip_text = str(snapshot.get("expansion_error", "")) if not bool(snapshot.get("can_expand", true)) else "解锁下一排6个格子；不移动现有物品。"
	expansion.add_child(expand)
	if _bag_held_uid >= 0:
		_bag_grid.begin_placement(_bag_held_uid, _bag_held_rotated, _bag_cursor)


func _build_backpack_details() -> void:
	if not is_instance_valid(_bag_details):
		return
	_clear(_bag_details)
	var item: Dictionary = run.backpack_item(_bag_selected_uid)
	if item.is_empty():
		_bag_details.add_child(_wrap("选择物品查看效果", 15, MUTED))
		return
	var uid: int = int(item["uid"])
	var rank: int = int(item.get("rank", 1))
	var definition: ContentDef = _definition(str(item["kind"]), str(item["id"]))
	var heading := HBoxContainer.new()
	_bag_details.add_child(heading)
	_add_icon(heading, definition, 40)
	var title := _wrap("%s · %s阶" % [definition.display_name, _rank_name(rank)], 18, BONE)
	title.name = "BackpackItemTitle"
	title.tooltip_text = _backpack_effect_text(item)
	heading.add_child(title)
	var dimensions: Vector2i = BACKPACK_GRID._item_size(item, bool(item.get("rotated", false)))
	var footprint := _label("占格 %d×%d" % [dimensions.x, dimensions.y], 13, MUTED)
	footprint.name = "BackpackFootprint"
	_bag_details.add_child(footprint)
	if str(item["kind"]) == "weapon":
		var stats := _wrap(_weapon_stats_text(definition, rank, _item_resonance_bonus(item)), 12, CYAN)
		stats.name = "BackpackWeaponStats"
		_bag_details.add_child(stats)
		var weapon_index: int = run.weapon_index_for_uid(uid)
		var source_count: int = (run.loadout[weapon_index].get("resonance_sources", []) as Array).size() if weapon_index >= 0 else 0
		var resonance_summary := _label("共鸣+%s · %d件遗物" % [_rune_percent(_item_resonance_bonus(item)), source_count], 12, CYAN)
		resonance_summary.name = "BackpackResonanceSummary"
		_enable_tooltip(resonance_summary, _resonance_details(item))
		_bag_details.add_child(resonance_summary)
	elif str(item["kind"]) == "skill":
		var skill_stats := _wrap(_active_skill_stats_text(run.active_skill_parameters(item)), 14, CYAN)
		skill_stats.name = "BackpackSkillStats"
		_bag_details.add_child(skill_stats)
		var slot_index: int = _active_skill_index(uid)
		if slot_index >= 0:
			var action: String = "pulse" if slot_index == 0 else "skill_secondary"
			var input_key: String = ("X" if slot_index == 0 else "Y") if _input_kind == "gamepad" else ControlBindings.key_label(int(_controls[action]))
			var slot_status := _label("技能%d · %s" % [slot_index + 1, input_key], 14, CYAN)
			slot_status.name = "BackpackSkillSlot"
			_bag_details.add_child(slot_status)
	var partners: Array[Dictionary] = []
	for other: Dictionary in run.backpack_snapshot()["items"]:
		var preview: Dictionary = run.merge_preview(uid, int(other["uid"]))
		if bool(preview.get("can_merge", false)):
			partners.append({"item": other, "preview": preview})
	if not partners.is_empty():
		_section_heading(_bag_details, "同名同阶合成", GOLD, 14)
		var sample: Dictionary = partners[0]["preview"]
		var explanation: String = "释放%d格；全局属性保持两件合计。\n共鸣按新邻接重算。" % int(sample.get("cells_freed", dimensions.x * dimensions.y))
		if str(item["kind"]) == "weapon":
			explanation = "目标伤害 %.1f → %.1f，释放%d格。" % [float(sample.get("damage_before", definition.damage)), float(sample.get("damage_after", definition.damage * 2.0)), int(sample.get("cells_freed", dimensions.x * dimensions.y))]
			explanation += "\n合成后按目标位置重算共鸣。"
		elif str(item["kind"]) == "rune":
			explanation = _rune_rank_text(str(item["id"]), rank + 1)
		elif str(item["kind"]) == "skill":
			explanation = "伤害 %s → %s\n范围 %s → %s · 冷却 %s → %s秒" % [_skill_number(float(sample.get("damage_before", 0.0))), _skill_number(float(sample.get("damage_after", 0.0))), _skill_number(float(sample.get("radius_before", 0.0))), _skill_number(float(sample.get("radius_after", 0.0))), _skill_number(float(sample.get("cooldown_before", 0.0))), _skill_number(float(sample.get("cooldown_after", 0.0)))]
			if str(item["id"]) == "pulse":
				explanation = "范围 %s → %s\n冷却 %s → %s秒" % [_skill_number(float(sample.get("radius_before", 0.0))), _skill_number(float(sample.get("radius_after", 0.0))), _skill_number(float(sample.get("cooldown_before", 0.0))), _skill_number(float(sample.get("cooldown_after", 0.0)))]
		elif str(item["kind"]) == "relic" and str(item["id"]) in ["fold_clasp", "echo_stone"]:
			var effects: PackedStringArray = []
			for change: Dictionary in sample.get("stat_changes", []):
				var key: String = str(change["key"])
				effects.append("%s %s → %s" % [_relic_stat_name(key), _relic_amount_text(key, float(change["before"])), _relic_amount_text(key, float(change["after"]))])
			explanation += "\n目标单件：" + "；".join(effects)
		var merge_preview := _wrap(explanation, 12, GOLD)
		merge_preview.name = "BackpackMergePreview"
		_bag_details.add_child(merge_preview)
		_add_backpack_merge_target(uid, partners[0])
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_bag_details.add_child(actions)
	var move := _shop_button("拿起 / 移动", _bp_pick_up.bind(uid), "bag_move:%d" % uid, Vector2(110, 32))
	move.name = "MoveBackpackItem"
	move.add_theme_font_size_override("font_size", 13)
	move.tooltip_text = _backpack_move_tooltip()
	actions.add_child(move)
	var rotate := _shop_button(_backpack_rotate_text(), _bp_rotate.bind(uid), "bag_rotate:%d" % uid, Vector2(76, 32))
	rotate.name = "RotateBackpackItem"
	rotate.add_theme_font_size_override("font_size", 13)
	rotate.tooltip_text = _backpack_rotate_tooltip()
	actions.add_child(rotate)
	var sale := _shop_button("出售 · %d魂屑" % int(floorf(float(item.get("paid", 0)) * 0.5)), _bp_sell.bind(uid), "bag_sell:%d" % uid, Vector2(0, 32))
	sale.name = "SellBackpackItem"
	sale.add_theme_font_size_override("font_size", 13)
	sale.tooltip_text = "出售不可撤回。" if str(item["kind"]) == "skill" else "出售不可撤回；必须保留至少一件法器。法器上的符文退回背包空格。"
	_bag_details.add_child(sale)
	var rune: Dictionary = item.get("rune", {})
	if str(item["kind"]) == "weapon" and not rune.is_empty():
		var detach := _shop_button("拆下 %s · %s阶" % [GameCatalog.rune(str(rune["id"])).display_name, _rank_name(int(rune.get("rank", 1)))], _bp_unequip.bind(uid), "bag_unequip:%d" % uid, Vector2(0, 32))
		detach.name = "UnequipBackpackRune"
		detach.add_theme_font_size_override("font_size", 12)
		detach.tooltip_text = "免费拆下；背包需要一个真实空格。"
		_bag_details.add_child(detach)
	if str(item["kind"]) == "rune":
		_section_heading(_bag_details, "装入法器", PURPLE, 14)
		for weapon: Dictionary in run.loadout:
			var weapon_uid: int = int(weapon["uid"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			_bag_details.add_child(row)
			var equip := _shop_button("装入 %s %s" % [GameCatalog.weapon(str(weapon["id"])).display_name, _rank_name(int(weapon.get("rank", 1)))], _bp_equip.bind(uid, weapon_uid, _shop_epoch), "bag_equip:%d" % weapon_uid, Vector2(0, 30))
			equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			equip.add_theme_font_size_override("font_size", 12)
			row.add_child(equip)
			var index: int = run.weapon_index_for_uid(weapon_uid)
			var preview := _shop_button("预览", _preview_rune_equip.bind(index, _shop_epoch, run.rune_bag[_selected_rune].duplicate(true), weapon.duplicate(true)), "rune_preview:%d" % index, Vector2(48, 30))
			preview.add_theme_font_size_override("font_size", 12)
			row.add_child(preview)
	if str(item["kind"]) in ["weapon", "relic"]:
		var resonance := _wrap(_resonance_details(item), 12, CYAN)
		resonance.name = "BackpackResonance"
		_bag_details.add_child(resonance)
	if partners.size() > 1:
		_section_heading(_bag_details, "其他合成目标", GOLD, 14)
		for index: int in range(1, partners.size()):
			_add_backpack_merge_target(uid, partners[index])
	if str(item["kind"]) != "skill":
		var description := _wrap(_backpack_effect_text(item), 13, CYAN)
		description.name = "BackpackItemEffect"
		_bag_details.add_child(description)


func _add_backpack_merge_target(source: int, partner: Dictionary) -> void:
	var other: Dictionary = partner["item"]
	var preview: Dictionary = partner["preview"]
	var merge := _shop_button("与 #%d 合成 → %s阶" % [int(other["uid"]), _rank_name(int(preview["rank_after"]))], _bp_merge.bind(source, int(other["uid"]), _shop_epoch), "bag_merge:%d" % int(other["uid"]), Vector2(0, 32))
	merge.name = "MergeBackpackItem%d" % int(other["uid"])
	merge.add_theme_font_size_override("font_size", 13)
	var returned: Dictionary = preview.get("returned_rune", {})
	merge.tooltip_text = "保留目标物品的位置和朝向；该操作不可撤回。" + ("另一份符文退回背包。" if not returned.is_empty() else "")
	if str(other["kind"]) == "weapon":
		merge.tooltip_text += "\n当前两件单枚伤害合计 %.1f；合成后 %.1f，共鸣 %s → %s。" % [float(preview.get("combined_damage_before", 0.0)), float(preview.get("damage_after", 0.0)), _rune_percent(float(preview.get("resonance_before", 0.0))), _rune_percent(float(preview.get("resonance_after", 0.0)))]
	elif str(other["kind"]) == "relic":
		merge.tooltip_text += "\n遗物总属性保留，周边法器按目标位置重新计算共鸣。"
	elif str(other["kind"]) == "skill":
		merge.tooltip_text += "\n" + _active_skill_stats_text(preview.get("skill_after", {}))
	_bag_details.add_child(merge)


func _bp_select(uid: int, epoch: int) -> void:
	if not _bp_allowed(epoch) or run.backpack_item(uid).is_empty():
		return
	_bag_selected_uid = uid
	_selected_rune = run.rune_index_for_uid(uid)
	_build_backpack_details()
	var guide: Label = _page.find_child("RuneGuide", true, false) as Label
	if guide != null:
		guide.text = _rune_guide()
		guide.visible = _selected_rune >= 0


func _bp_allowed(epoch: int) -> bool:
	return _screen == "shop" and not _refresh_queued and _overlay_mode.is_empty() and epoch == _shop_epoch and run != null and is_instance_valid(_bag_grid) and _bag_grid.is_inside_tree()


func _bp_guard(uid: int, epoch: int) -> bool:
	return _bp_allowed(epoch) and not run.backpack_item(uid).is_empty() and run.backpack_item(uid) == _bag_grid.snapshot_item(uid)


func _bp_holding(uid: int, rotated: bool, cell: Vector2i, epoch: int) -> void:
	if epoch == _shop_epoch and _screen == "shop":
		_bag_held_uid = uid
		_bag_held_rotated = rotated
		_bag_cursor = cell
		_refresh_reading_guides()


func _bp_hint(text: String, epoch: int) -> void:
	if epoch == _shop_epoch and is_instance_valid(_bag_status):
		_bag_hint_is_default = false
		_bag_status.text = text


func _bp_cancelled(uid: int, epoch: int) -> void:
	if not _bp_guard(uid, epoch) or uid != _bag_selected_uid or _bag_grid.held_uid >= 0 or not _bag_grid.interaction_enabled or get_viewport().gui_is_dragging():
		return
	var target: Button = _shop_focus_button("bag_move:%d" % uid)
	if target == null:
		target = _shop_focus_button("bag:%d" % uid)
	if target != null:
		target.grab_focus()


func _bp_pick_up(uid: int) -> void:
	if _bp_guard(uid, _shop_epoch) and uid == _bag_selected_uid:
		_bag_grid.begin_placement(uid)


func _bp_rotate(uid: int) -> void:
	if not _bp_guard(uid, _shop_epoch) or uid != _bag_selected_uid:
		return
	if int(_bag_grid.held_uid) != uid:
		_bag_grid.begin_placement(uid)
	_bag_grid.rotate_held()


func _bp_move(uid: int, cell: Vector2i, rotated: bool, epoch: int) -> void:
	if not _bp_guard(uid, epoch):
		return
	_bp_complete(run.move_item(uid, cell, rotated), "物品已放置。", uid)


func _bp_merge(source: int, target: int, epoch: int) -> void:
	if source != _bag_selected_uid or not _bp_guard(source, epoch) or not _bp_guard(target, epoch):
		return
	var success: bool = run.merge_items(source, target)
	_bp_complete(success, "合成完成；目标物品升阶，位置保持。", target)


func _bp_equip(source: int, target: int, epoch: int) -> void:
	if source != _bag_selected_uid or not _bp_guard(source, epoch) or not _bp_guard(target, epoch):
		return
	_bp_complete(run.equip_rune(run.rune_index_for_uid(source), run.weapon_index_for_uid(target)), "符文已装入；原符文退回背包。", target)


func _bp_unequip(uid: int) -> void:
	if _bp_guard(uid, _shop_epoch) and uid == _bag_selected_uid:
		_bp_complete(run.unequip_rune(run.weapon_index_for_uid(uid)), "符文已拆下，放入背包空格。", uid)


func _bp_sell(uid: int) -> void:
	if _bp_guard(uid, _shop_epoch) and uid == _bag_selected_uid:
		var items: Array = run.backpack_snapshot()["items"]
		var index: int = 0
		for item: Dictionary in items:
			if int(item["uid"]) == uid:
				break
			index += 1
		var success: bool = run.sell_item(uid)
		var remaining: Array = run.backpack_snapshot()["items"]
		var next_uid: int = int(remaining[mini(index, remaining.size() - 1)]["uid"]) if success and not remaining.is_empty() else uid
		_bp_complete(success, "物品已出售。", next_uid)


func _bp_expand() -> void:
	if not _bp_allowed(_shop_epoch):
		return
	_requested_shop_focus = "bag_expand"
	_handle_action(run.expand_backpack(), "buy", "背包已解锁一排格子。")


func _bp_complete(success: bool, message: String, result_uid: int) -> void:
	if success and is_instance_valid(_bag_grid):
		var native_drag: bool = get_viewport().gui_is_dragging() or bool(_bag_grid._native_dragging)
		_bag_selected_uid = result_uid
		_selected_rune = run.rune_index_for_uid(result_uid)
		_requested_shop_focus = ("bag:%d" if native_drag else "bag_move:%d") % result_uid
		_bag_grid.cancel_placement()
	_handle_action(success, "buy", message if success else "")


func _backpack_effect_text(item: Dictionary) -> String:
	var rank: int = int(item.get("rank", 1))
	var definition: ContentDef = _definition(str(item["kind"]), str(item["id"]))
	match str(item["kind"]):
		"skill": return definition.description
		"weapon":
			var text: String = definition.description
			var rune: Dictionary = item.get("rune", {})
			if not rune.is_empty():
				text += "\n" + _rune_rank_text(str(rune["id"]), int(rune.get("rank", 1)))
			if run.linked_weapon_uids().has(int(item["uid"])):
				text += "\n引魂烛联动：优先攻击射程内生命比例最低的敌人。"
			return text
		"rune": return _rune_rank_text(definition.id, rank) + "\n拖到法器上装入，或选择下方目标。"
		"relic":
			var result: PackedStringArray = []
			for pair: Array in [[definition.stat, definition.amount], [definition.bonus_stat, definition.bonus_amount]]:
				if str(pair[0]).is_empty():
					continue
				var amount: float = float(pair[1]) * BackpackInventory.rank_multiplier(rank)
				result.append("%s %s" % [_relic_stat_name(str(pair[0])), _relic_amount_text(str(pair[0]), amount)])
			var text: String = "\n".join(result)
			if definition.id == "grave_candle":
				text += "\n正上方边缘相接的法器优先攻击残血目标；不叠加。\n当前连接：" + _candle_link_names(item)
			elif definition.id == "fold_clasp":
				text += "\n当前构筑：冲刺冷却%s秒，最低%s秒。" % [_skill_number(run.stat("dash_cooldown")), _skill_number(DashRules.MIN_COOLDOWN)]
			elif definition.id == "echo_stone":
				text += "\n当前构筑：脉冲半径%s，冷却%s秒。\n半径上限%s，冷却上限%s秒。" % [_skill_number(run.stat("pulse_radius")), _skill_number(run.stat("pulse_cooldown")), _skill_number(PulseRules.MAX_RADIUS), _skill_number(PulseRules.MAX_COOLDOWN)]
			return text
	return definition.description


func _active_skill_index(uid: int) -> int:
	for index: int in run.active_skills.size():
		if int(run.active_skills[index]["uid"]) == uid:
			return index
	return -1


static func _active_skill_stats_text(parameters: Dictionary) -> String:
	if str(parameters.get("id", "")) == "pulse":
		return "范围 %s · 冷却 %s秒\n击退 %s · 减速 %s%%" % [_skill_number(float(parameters.get("radius", 0.0))), _skill_number(float(parameters.get("cooldown", 0.0))), _skill_number(float(parameters.get("push_distance", PulseRules.PUSH_DISTANCE))), _skill_number((1.0 - float(parameters.get("hinder_factor", PulseRules.HINDER_FACTOR))) * 100.0)]
	return "伤害 %s · 范围 %s\n冷却 %s秒" % [_skill_number(float(parameters.get("damage", 0.0))), _skill_number(float(parameters.get("radius", 0.0))), _skill_number(float(parameters.get("cooldown", 0.0)))]


static func _relic_stat_name(key: String) -> String:
	var names: Dictionary = {"damage": "伤害", "attack_speed": "攻速", "move_speed": "移速", "max_health": "生命上限", "armor": "护甲", "pickup_radius": "拾取范围", "dash_cooldown": "冲刺冷却", "pulse_radius": "脉冲半径", "pulse_cooldown": "脉冲冷却"}
	return str(names.get(key, key))


static func _relic_amount_text(key: String, value: float) -> String:
	if key in ["damage", "attack_speed"]:
		return "%+.0f%%" % (value * 100.0)
	return "%+.1f秒" % value if key in ["dash_cooldown", "pulse_cooldown"] else "%+.0f" % value


static func _rank_name(rank: int) -> String:
	return ["Ⅰ", "Ⅱ", "Ⅲ"][clampi(rank, 1, 3) - 1]


static func _rune_rank_text(id: String, rank: int) -> String:
	match id:
		"pierce": return "贯穿额外命中%d个目标；同一弹体不重击同一目标。" % RuneRules.extra_hits(rank)
		"bounce": return "最多追加%d跳；范围%.0f，每跳保留75%%伤害。" % [RuneRules.extra_hits(rank), RuneRules.BOUNCE_RANGE]
		"blast": return "爆破半径%.0f，溅射为本体伤害%.0f%%；不递归触发。" % [RuneRules.blast_radius(rank), RuneRules.blast_factor(rank) * 100.0]
	return ""


func _offer_card(parent: Control, index: int) -> void:
	var offer: Dictionary = run.offers[index]
	var kind := str(offer.get("kind", "weapon"))
	var definition = _definition(kind, str(offer.get("id", "")))
	var card := _panel(parent, Vector2(252, 180))
	card.name = "Offer%d" % (index + 1)
	var category: Color = {"weapon": GOLD, "rune": PURPLE, "relic": CYAN, "skill": Color("287eb5")}.get(kind, GOLD)
	var locked: bool = run.is_offer_locked(index)
	var sold: bool = bool(offer.get("sold", false))
	SHOP_PANEL_SKIN.apply(card, category, false, locked, sold)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := _inside(card, 12)
	body.add_theme_constant_override("separation", 5)
	var name_row := HBoxContainer.new()
	body.add_child(name_row)
	var icon_well := PanelContainer.new()
	icon_well.name = "OfferIconWell"
	icon_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_well.custom_minimum_size = Vector2(42, 42)
	var icon_surface := _box(category.lerp(PANEL, 0.92), category.lerp(PANEL_LIGHT, 0.70), 3)
	icon_surface.content_margin_left = 4
	icon_surface.content_margin_right = 4
	icon_surface.content_margin_top = 4
	icon_surface.content_margin_bottom = 4
	icon_surface.border_width_bottom = 2
	icon_well.add_theme_stylebox_override("panel", icon_surface)
	name_row.add_child(icon_well)
	_add_icon(icon_well, definition, 34)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(names)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	names.add_child(title_row)
	var name_label := _label(definition.display_name, 18, BONE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_enable_tooltip(name_label, definition.description)
	title_row.add_child(name_label)
	var lock_marker := _label("已锁" if locked else "", 11, GOLD)
	lock_marker.name = "OfferLockMarker%d" % index
	lock_marker.custom_minimum_size.x = 22
	title_row.add_child(lock_marker)
	var lock_button := _shop_button("已售" if sold else "解锁" if locked else "锁定", _toggle_offer_lock.bind(index, _shop_epoch, offer.duplicate(true), locked), "lock:%d" % index, Vector2(56, 24))
	lock_button.name = "OfferLock%d" % index
	lock_button.add_theme_font_size_override("font_size", 12)
	lock_button.disabled = sold
	lock_button.focus_mode = Control.FOCUS_NONE if sold else Control.FOCUS_ALL
	lock_button.tooltip_text = "已售商品不能锁定。" if sold else "解锁后，下次刷新会替换此商品。" if locked else "锁定此商品，刷新和跨波保留；价格随波次调整，最多锁定%d件。" % RunState.SHOP_LOCK_CAP
	if not sold and not locked:
		var lock_error: String = run.shop_lock_error(index)
		if not lock_error.is_empty():
			lock_button.tooltip_text += "\n" + lock_error
	ButtonSkin.apply(lock_button, "primary" if locked else "quiet", true)
	title_row.add_child(lock_button)
	var dimensions: Vector2i = definition.inventory_size
	var offer_rank: int = int(offer.get("rank", 1)) if kind == "skill" else 1
	names.add_child(_label("%s阶 · %s · 占格%d×%d" % [_rank_name(offer_rank), {"weapon": "法器", "rune": "符文", "relic": "遗物", "skill": "技能"}.get(kind, kind), dimensions.x, dimensions.y], 11, category))
	var summary: String = _shop_description(definition) if kind != "skill" else ""
	var description := _wrap(summary, 13, MUTED)
	description.name = "OfferDescription"
	description.max_lines_visible = 2
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_enable_tooltip(description, definition.description)
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(description)
	description.visible = kind != "skill"
	if kind == "weapon":
		var projection: Dictionary = run.weapon_purchase_preview(index)
		var has_placement: bool = bool(projection.get("has_projection", false))
		var predicted_bonus: float = float(projection.get("resonance_bonus", 0.0))
		var predicted: String = _weapon_stats_text(definition, 1, predicted_bonus) if has_placement else "已售出，不再预测落点。" if sold else "无完整空位，整理后更新共鸣预估。"
		var stats := _wrap(predicted, 12, GOLD)
		stats.name = "WeaponStats"
		_enable_tooltip(stats, ("按购买时自动落点预计，共鸣 +%s。\n" % _rune_percent(predicted_bonus) if has_placement else "当前没有可用于购买预估的实际落点。\n") + _weapon_stats_note())
		body.add_child(stats)
	elif kind == "skill":
		var projection: Dictionary = run.skill_purchase_preview(index)
		var stats := _wrap(_active_skill_stats_text(projection.get("parameters", projection)), 13, category)
		stats.name = "SkillStats"
		body.add_child(stats)
	var price: int = int(offer.get("price", 0))
	var error: String = run.purchase_error(index)
	var blocked: bool = not sold and not error.is_empty()
	var buy_text: String = "已购买" if sold else "购买  %d 魂屑" % price
	if blocked:
		var reason: String = {
			"魂屑不足。": "魂屑不足",
			"背包空间不足。": "背包无空位",
			"主动技能已达上限（2）。": "技能已满 2/2",
		}.get(error, "暂不可购")
		buy_text = "%s · %d魂屑" % [reason, price]
	var buy := _shop_button(buy_text, _buy.bind(index), "buy:%d" % index, Vector2(0, 35))
	buy.add_theme_font_size_override("font_size", 14)
	ButtonSkin.apply(buy, "blocked" if blocked else "primary", true)
	buy.tooltip_text = error
	if error == "魂屑不足。":
		buy.tooltip_text += "还差%d魂屑。" % (price - run.gold)
	elif error == "背包空间不足。":
		buy.tooltip_text += "\n移动、旋转、合成或扩容后再购买；不会自动合成。"
	# Blocked unsold offers stay focusable so keyboard users can read the reason.
	buy.disabled = sold
	buy.focus_mode = Control.FOCUS_NONE if sold else Control.FOCUS_ALL
	if kind == "relic":
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		body.add_child(actions)
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(buy)
		var compare := _shop_button("对照", _compare_relic.bind(index, _shop_epoch, offer.duplicate(true)), "compare:%d" % index, Vector2(54, 35))
		compare.name = "CompareRelic%d" % index
		compare.add_theme_font_size_override("font_size", 13)
		compare.tooltip_text = "查看当前与购入后的属性、生命和法器变化；不会购买。"
		actions.add_child(compare)
	else:
		body.add_child(buy)


func _toggle_offer_lock(index: int, epoch: int, expected_offer: Dictionary, was_locked: bool) -> void:
	if _screen != "shop" or _refresh_queued or not _overlay_mode.is_empty() or epoch != _shop_epoch:
		return
	if run == null or index < 0 or index >= run.offers.size() or run.offers[index] != expected_offer or run.is_offer_locked(index) != was_locked:
		return
	_requested_shop_focus = "lock:%d" % index
	var success: bool = run.set_offer_locked(index, not was_locked)
	var definition: ContentDef = _definition(str(expected_offer["kind"]), str(expected_offer["id"]))
	var message: String = "%s已解锁，下次刷新可替换。" % definition.display_name if was_locked else "%s已锁定（%d / %d）；跨波保留，价格随波次调整。" % [definition.display_name, run.locked_offer_count(), RunState.SHOP_LOCK_CAP]
	_handle_action(success, "", message)


func _compare_relic(index: int, epoch: int, expected_offer: Dictionary) -> void:
	if _screen != "shop" or _refresh_queued or not _overlay_mode.is_empty() or epoch != _shop_epoch:
		return
	if run == null or index < 0 or index >= run.offers.size() or run.offers[index] != expected_offer:
		return
	var preview: Dictionary = run.relic_purchase_preview(index)
	if preview.is_empty():
		return
	var definition: ContentDef = GameCatalog.relic(str(preview["id"]))
	var source: Button = _shop_focus_button("compare:%d" % index)
	if source != null:
		source.grab_focus()
	_begin_overlay("relic_comparison")
	var body := _modal("购前对照 · " + definition.display_name, Vector2(1000, 660))
	body.name = "RelicComparison"
	body.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	body.add_child(header)
	_add_icon(header, definition, 72)
	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 3)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(summary)
	summary.add_child(_wrap(definition.description, 16, CYAN))
	var projected: bool = bool(preview["has_projection"])
	var layers: String = "属性权重  %d → %d（购后）" % [int(preview["stack_before"]), int(preview["stack_after"])] if projected else "属性权重  %d（保持）" % int(preview["stack_before"])
	var layer_label := _label(layers, 14, BONE)
	layer_label.name = "ComparisonLayers"
	summary.add_child(layer_label)
	var balance: String = "价格 %d 魂屑   ·   余额 %d → %d（购后）" % [int(preview["price"]), int(preview["gold_before"]), int(preview["gold_after"])] if bool(preview["can_buy"]) else "价格 %d 魂屑   ·   当前余额 %d（预览不扣款）" % [int(preview["price"]), int(preview["gold_before"])]
	var balance_label := _label(balance, 14, GOLD)
	balance_label.name = "ComparisonBalance"
	summary.add_child(balance_label)
	var status_text: String = "购前效果预览，尚未购买；关闭后可直接购买。"
	if not bool(preview["can_buy"]):
		status_text = "效果预览，尚缺 %d 魂屑；当前不会扣款或放入物品。" % int(preview["shortfall"]) if projected and int(preview["shortfall"]) > 0 else "当前无法购入：%s" % str(preview["error"])
	if projected and not bool(preview.get("placement_available", false)):
		status_text += "\n背包无可用落点；下表仅假设全局属性变化，不新增邻接共鸣。"
	var status := _wrap(status_text, 14, CYAN if bool(preview["can_buy"]) else GOLD)
	status.name = "ComparisonStatus"
	body.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.name = "ComparisonScroll"
	scroll.custom_minimum_size.y = 260
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CYAN))
	scroll.gui_input.connect(_comparison_scroll_input.bind(scroll, epoch))
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	if projected:
		_build_relic_stat_comparison(content, preview)
		_build_relic_weapon_comparison(content, preview)
	else:
		var unavailable := _wrap("商品已售出；保留当前构筑，不展示新增物品的变化。", 17, MUTED)
		unavailable.name = "ComparisonNoProjection"
		content.add_child(unavailable)
	var note := _wrap("法器数值是每枚伤害与持续攻击时的标称间隔，未计符文追加命中；这些数值不是 DPS。\n滚轮滚动，或 Tab 选择表格区域后使用 PageUp / PageDown；Esc 返回商品。", 13, MUTED)
	note.name = "ComparisonScope"
	content.add_child(note)
	var close := _button("返回商品", _close_relic_comparison.bind(epoch), Vector2(0, 42))
	close.name = "CloseRelicComparison"
	_accent(close)
	_reading_footer(body, close)
	_focus_later(close)


func _build_relic_stat_comparison(parent: Control, preview: Dictionary) -> void:
	_section_heading(parent, "属性与实际生命补充", GOLD, 16)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for heading: Array in [["属性", 170], ["当前", 150], ["购后", 150], ["变化", 260]]:
		_comparison_cell(grid, str(heading[0]), GOLD, float(heading[1]))
	var names: Dictionary = {"max_health": "生命上限", "damage": "伤害倍率", "attack_speed": "攻击速度倍率", "move_speed": "移动速度", "armor": "护甲", "pickup_radius": "拾取范围", "dash_cooldown": "冲刺冷却", "pulse_radius": "脉冲半径", "pulse_cooldown": "脉冲冷却"}
	for change: Dictionary in preview["stat_changes"]:
		var key: String = str(change["key"])
		var delta: float = float(change["delta"])
		_comparison_cell(grid, str(names.get(key, key)), BONE, 170)
		_comparison_cell(grid, _comparison_stat_value(key, float(change["before"])), MUTED, 150)
		_comparison_cell(grid, _comparison_stat_value(key, float(change["after"])), BONE, 150)
		var cooldown: bool = key in ["dash_cooldown", "pulse_cooldown"]
		var variation := _comparison_cell(grid, _comparison_delta(delta, "秒" if cooldown else "倍" if key in ["damage", "attack_speed"] else "", 1 if cooldown else 2 if key in ["damage", "attack_speed"] else 0), _comparison_change_color(-delta if cooldown else delta), 260)
		variation.name = "ComparisonStat_" + key
	var health_gain: float = float(preview["health_after"]) - float(preview["health_before"])
	_comparison_cell(grid, "当前生命", BONE, 170)
	_comparison_cell(grid, "%.1f" % float(preview["health_before"]), MUTED, 150)
	_comparison_cell(grid, "%.1f" % float(preview["health_after"]), BONE, 150)
	var healing := _comparison_cell(grid, "实际补充 %.1f 生命" % health_gain if health_gain > 0.0 else "不补充生命", _comparison_change_color(health_gain), 260)
	healing.name = "ComparisonHealthGain"


func _build_relic_weapon_comparison(parent: Control, preview: Dictionary) -> void:
	_section_heading(parent, "现有法器 · 当前 → 购后", PURPLE, 16)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for heading: Array in [["法器 / 每次枚数", 220], ["每枚伤害", 270], ["标称间隔", 300]]:
		_comparison_cell(grid, str(heading[0]), GOLD, float(heading[1]))
	for change: Dictionary in preview["weapon_changes"]:
		var slot: int = int(change["slot"])
		var definition: ContentDef = GameCatalog.weapon(str(change["id"]))
		var name_label := _comparison_cell(grid, "%02d  %s / %d枚" % [slot + 1, definition.display_name, int(change["shots"])], BONE, 220)
		_enable_tooltip(name_label, _equipment_tooltip(run.loadout[slot]))
		var damage_delta: float = float(change["damage_after"]) - float(change["damage_before"])
		var damage := _comparison_cell(grid, "%.1f → %.1f\n%s" % [float(change["damage_before"]), float(change["damage_after"]), _comparison_delta(damage_delta, "伤害", 1)], _comparison_change_color(damage_delta), 270)
		damage.name = "ComparisonWeapon%dDamage" % slot
		damage.text += "\n共鸣 %s → %s" % [_rune_percent(float(change.get("resonance_before", 0.0))), _rune_percent(float(change.get("resonance_after", 0.0)))]
		var interval_delta: float = float(change["interval_after"]) - float(change["interval_before"])
		var interval := _comparison_cell(grid, "%.3f秒 → %.3f秒\n%s" % [float(change["interval_before"]), float(change["interval_after"]), _comparison_delta(interval_delta, "秒", 3) + ("（更快）" if interval_delta < -0.00001 else "（更慢）" if interval_delta > 0.00001 else "")], _comparison_change_color(-interval_delta), 300)
		interval.name = "ComparisonWeapon%dInterval" % slot


func _comparison_cell(parent: Control, text: String, color: Color, width: float) -> Label:
	var label := _wrap(text, 14, color)
	label.custom_minimum_size.x = width
	parent.add_child(label)
	return label


static func _comparison_stat_value(key: String, value: float) -> String:
	if key in ["dash_cooldown", "pulse_cooldown"]:
		return "%.1f秒" % value
	return "×%.2f" % value if key in ["damage", "attack_speed"] else "%.0f" % value


static func _comparison_delta(delta: float, unit: String, decimals: int) -> String:
	if absf(delta) < 0.00001:
		return "保持不变"
	var amount: String = ("%.3f" % absf(delta)) if decimals == 3 else ("%.2f" % absf(delta)) if decimals == 2 else ("%.1f" % absf(delta)) if decimals == 1 else ("%.0f" % absf(delta))
	var direction: String = "增加" if delta > 0.0 else "减少"
	return direction + ("约 " if decimals > 0 else " ") + amount + (" " + unit if not unit.is_empty() else "")


static func _comparison_change_color(delta: float) -> Color:
	return CYAN if delta > 0.00001 else RED if delta < -0.00001 else MUTED


func _close_relic_comparison(epoch: int) -> void:
	if _overlay_mode == "relic_comparison" and epoch == _shop_epoch:
		hide_pause()


func _comparison_scroll_input(event: InputEvent, scroll: ScrollContainer, epoch: int) -> void:
	if epoch != _shop_epoch or _overlay_mode not in ["relic_comparison", "rune_equip_comparison"] or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	match key_event.keycode:
		KEY_PAGEDOWN:
			scroll.scroll_vertical += int(scroll.size.y * 0.8)
		KEY_PAGEUP:
			scroll.scroll_vertical -= int(scroll.size.y * 0.8)
		KEY_HOME:
			scroll.scroll_vertical = 0
		KEY_END:
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_:
			return
	scroll.accept_event()


func _preview_rune_equip(index: int, epoch: int, incoming_snapshot: Dictionary, weapon_snapshot: Dictionary) -> void:
	if _screen != "shop" or _refresh_queued or not _overlay_mode.is_empty() or epoch != _shop_epoch:
		return
	if run == null or _selected_rune < 0 or _selected_rune >= run.rune_bag.size() or index < 0 or index >= run.loadout.size():
		return
	if run.rune_bag[_selected_rune] != incoming_snapshot or run.loadout[index] != weapon_snapshot:
		return
	var preview: Dictionary = run.rune_equip_preview(_selected_rune, index)
	if preview.is_empty():
		return
	var weapon: ContentDef = GameCatalog.weapon(str(preview["weapon_id"]))
	var incoming: ContentDef = GameCatalog.rune(str(preview["rune_id"]))
	var returned: Dictionary = preview["returned_rune"]
	var source: Button = _shop_focus_button("rune_preview:%d" % index)
	if source != null:
		source.grab_focus()
	_begin_overlay("rune_equip_comparison")
	var body := _modal("符文装入预览 · " + weapon.display_name, Vector2(1000, 660))
	body.name = "RuneEquipComparison"
	body.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	body.add_child(header)
	_add_icon(header, weapon, 64)
	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 5)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(summary)
	var current_name: String = "无符文" if returned.is_empty() else "%s %s阶" % [GameCatalog.rune(str(returned["id"])).display_name, _rank_name(int(returned.get("rank", 1)))]
	var socket := _wrap("当前 %s → 所选 %s %s阶" % [current_name, incoming.display_name, _rank_name(int(incoming_snapshot.get("rank", 1)))], 21, BONE)
	socket.name = "RuneEquipSocket"
	summary.add_child(socket)
	var capacity := _label("松散符文  %d → %d件 · 装入后不额外占格" % [int(preview["bag_before"]), int(preview["bag_after"])], 15, CYAN)
	capacity.name = "RuneEquipBag"
	summary.add_child(capacity)
	_add_icon(header, incoming, 64)
	var return_text: String = "原法器没有符文，装入后释放所选符文的1格空间。" if returned.is_empty() else "%s退回所选符文腾出的格子，保留阶级与原购买价值。" % current_name
	var returns := _wrap(return_text, 15, GOLD)
	returns.name = "RuneEquipReturn"
	body.add_child(returns)
	var scroll := ScrollContainer.new()
	scroll.name = "RuneEquipScroll"
	scroll.custom_minimum_size.y = 260
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CYAN))
	scroll.gui_input.connect(_comparison_scroll_input.bind(scroll, epoch))
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var weapon_stats := _wrap(_weapon_stats_text(weapon, int(preview.get("weapon_rank", 1)), float(preview.get("resonance_bonus", 0.0))) + "\n当前共鸣 +%s；装符不改变共边关系。" % _rune_percent(float(preview.get("resonance_bonus", 0.0))), 15, CYAN)
	weapon_stats.name = "RuneEquipWeaponStats"
	content.add_child(weapon_stats)
	_section_heading(content, "逐弹触发与理论上限", PURPLE, 17)
	var trigger_hit: int = int(preview["trigger_hit"])
	var trigger_text: String = "从第%d次直接命中触发符文。" % trigger_hit
	var innate: int = int(preview["innate_pierce"])
	if innate > 0:
		trigger_text += "第1次直接命中仅执行本体贯穿，不触发符文。" if innate == 1 else "前%d次直接命中仅执行本体贯穿，不触发符文。" % innate
	var trigger := _wrap(trigger_text, 17, PURPLE)
	trigger.name = "RuneEquipTrigger"
	content.add_child(trigger)
	var targets := _wrap("每枚弹体理论最多 %d 个直接目标；每次发射 %d 枚，各枚独立计算。" % [int(preview["max_direct_targets"]), int(preview["shots"])], 16, BONE)
	targets.name = "RuneEquipTargets"
	content.add_child(targets)
	if bool(preview.get("returns_to_player", false)):
		var flight := _wrap("预算未耗尽时，发射后 %.2f秒开始追踪当前玩家返航；基础返航速度 %.0f，发射起总寿命 %.1f秒。接触玩家回收。\n往返共用命中记录与预算，同一目标不重复直击；预算耗尽后消失。" % [float(preview["return_delay"]), float(preview["return_speed"]), float(preview["return_lifetime"])], 15, CYAN)
		flight.name = "RuneEquipReturnFlight"
		content.add_child(flight)
		var cadence := _wrap("冷却独立计时，不等待回收；返航不额外生成新弹体，也不重置符文命中预算。", 15, MUTED)
		cadence.name = "RuneEquipReturnCooldown"
		content.add_child(cadence)
	match str(preview["rune_id"]):
		"pierce":
			var extra: int = int(preview["max_direct_targets"]) - trigger_hit
			content.add_child(_wrap("第%d次直接命中后，继续贯穿最多 %d 个未命中过的目标；直接命中的每个目标均按该枚本体伤害计算。" % [trigger_hit, extra], 16, CYAN))
		"bounce":
			var scales: Array = preview["bounce_scales"]
			var sequence: PackedStringArray = []
			for scale: float in scales:
				sequence.append(_rune_percent(scale))
			var bounce := _wrap("各次直接命中的本体伤害比例：\n" + " → ".join(sequence), 18, GOLD)
			bounce.name = "RuneEquipBounceScales"
			content.add_child(bounce)
			var reach := _wrap("第%d次直接命中后，寻找 %.0f 范围内最近的未命中目标，最多再转向 %d 次。" % [trigger_hit, float(preview["bounce_range"]), scales.size() - trigger_hit], 16, CYAN)
			reach.name = "RuneEquipBounceRange"
			content.add_child(reach)
			if bool(preview.get("return_cancelled_by_bounce", false)):
				var takeover := _wrap("成功弹射后永久取消返航，保留转向当时的速度，随后只按弹射规则飞行；不会再追踪玩家回收。", 16, CORAL)
				takeover.name = "RuneEquipBounceTakeover"
				content.add_child(takeover)
		"blast":
			var blast := _wrap("在第%d次直接命中处引爆：半径 %.0f，溅射伤害为该枚本体伤害的 %s。" % [trigger_hit, float(preview["blast_radius"]), _rune_percent(float(preview["blast_multiplier"]))], 17, GOLD)
			blast.name = "RuneEquipBlast"
			content.add_child(blast)
			if trigger_hit > 1:
				var delayed := _wrap("只命中1个目标不会爆破；必须命中第2个直接目标才引爆。" if trigger_hit == 2 else "未达到第%d次直接命中不会爆破；必须达到该次命中才引爆。" % trigger_hit, 17, CORAL)
				delayed.name = "RuneEquipDelayedBlast"
				content.add_child(delayed)
			var exclusions := _wrap("该枚已经直接命中的目标（含引爆目标）不再承受它的溅射。溅射不会再次触发符文；范围内额外目标数量另计。", 16, MUTED)
			exclusions.name = "RuneEquipBlastExclusions"
			content.add_child(exclusions)
			if bool(preview.get("return_consumed_on_blast", false)):
				var consumed := _wrap("引爆会消耗这枚归航弹体，爆破后直接消失，不再返航。", 15, CORAL)
				consumed.name = "RuneEquipBlastConsumesReturn"
				content.add_child(consumed)
	var independent := _wrap("同一枚弹体不会重复直击已命中过的目标。不同弹体分别记录与排重，可以各自命中同一敌人；多发的符文效果也按每枚独立触发。", 15, CYAN)
	independent.name = "RuneEquipIndependent"
	content.add_child(independent)
	var scope := _wrap("理论上限需要足够实际目标，并受射程、弹体存活时间和目标位置影响；不保证每次命中，不代表实战DPS。\n此面板只预览；返回背包后可装入，拆换免费。\n滚轮滚动；Tab选择内容区域后可用PageUp/PageDown；Esc返回背包。", 14, MUTED)
	scope.name = "RuneEquipScope"
	content.add_child(scope)
	var close := _button("返回背包", _close_rune_equip_comparison.bind(epoch), Vector2(0, 42))
	close.name = "CloseRuneEquipComparison"
	_accent(close)
	_reading_footer(body, close)
	_focus_later(close)


static func _rune_percent(scale: float) -> String:
	var number: String = "%.2f" % (scale * 100.0)
	while number.ends_with("0"):
		number = number.substr(0, number.length() - 1)
	return number.trim_suffix(".") + "%"


func _close_rune_equip_comparison(epoch: int) -> void:
	if _overlay_mode == "rune_equip_comparison" and epoch == _shop_epoch:
		hide_pause()


func _build_upgrades() -> void:
	_upgrade_epoch += 1
	_clear(_page)
	_background()
	if run == null:
		return
	if run.pending_upgrades <= 0:
		_screen = "transition"
		_finish_upgrades.call_deferred(_upgrade_epoch)
		return
	var shell := _shell(60, 88)
	var title := _label("秘术觉醒", 40, BONE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(title)
	var context: String = "战斗已暂停，选完强化继续当前波次。  " if _upgrades_during_combat else ""
	var sub := _label(context + "选择一项强化  ·  待选择 %d 次" % run.pending_upgrades, 18, MUTED)
	sub.name = "UpgradeContext"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(sub)
	_spacer(shell, 34)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(row)
	var choices: Array[Dictionary] = run.upgrade_choices()
	for index in range(choices.size()):
		var choice: Dictionary = choices[index]
		var card := _panel(row)
		card.name = "Upgrade_" + str(choice["id"])
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var body := _inside(card, 26)
		var card_heading := HBoxContainer.new()
		body.add_child(card_heading)
		var ordinal := _label("%02d  /  强化" % (index + 1), 15, GOLD)
		ordinal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_heading.add_child(ordinal)
		var definition: ContentDef = GameCatalog.relic(str(choice.get("id", "")))
		if definition != null:
			_add_icon(card_heading, definition, 36)
		_spacer(body, 8)
		body.add_child(_label(str(choice.get("name", "秘术强化")), 26, BONE))
		var description := _wrap(str(choice.get("description", "")), 19, BONE)
		description.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(description)
		var preview := VBoxContainer.new()
		preview.add_theme_constant_override("separation", 4)
		body.add_child(preview)
		preview.add_child(_label("当前 → 强化后", 12, MUTED))
		var values := _label(_upgrade_stat_preview(choice), 20, CYAN)
		values.name = "UpgradePreview"
		preview.add_child(values)
		if str(choice.get("stat", "")) == "max_health":
			var after_health: float = minf(run.projected_upgrade_stat("max_health", float(choice.get("amount", 0.0))), run.health + float(choice.get("amount", 0.0)))
			var health := _label("生命  %.0f → %.0f（回复 %.0f）" % [run.health, after_health, after_health - run.health], 16, CYAN)
			health.name = "UpgradeHealthPreview"
			preview.add_child(health)
		var button := _button("选择强化", _perform_upgrade_action.bind(str(choice["id"]), _upgrade_epoch), Vector2(0, 46))
		_accent(button)
		body.add_child(button)
		if index == 0:
			_focus_later(button)


func _upgrade_stat_preview(choice: Dictionary) -> String:
	var key: String = str(choice.get("stat", ""))
	var names: Dictionary = {"damage": "伤害", "attack_speed": "攻速", "move_speed": "移速", "max_health": "生命上限", "armor": "护甲", "pickup_radius": "拾取范围"}
	if run == null or not names.has(key):
		return ""
	# RunState stacks upgrade and relic bonuses additively for all six current stats.
	var before: float = run.stat(key)
	var after: float = run.projected_upgrade_stat(key, float(choice.get("amount", 0.0)))
	if key == "damage" or key == "attack_speed":
		return "%s  ×%.2f → ×%.2f" % [names[key], before, after]
	return "%s  %.0f → %.0f" % [names[key], before, after]


func _perform_upgrade_action(id: String, epoch: int) -> void:
	# A still-live old button may refer to an ID also offered in the next set.
	if _screen != "upgrades" or _refresh_queued or not _overlay_mode.is_empty() or epoch != _upgrade_epoch:
		return
	_choose_upgrade(id)


func _show_settings(from_pause: bool) -> void:
	var returning_from_controls: bool = _overlay_mode in ["controls_title", "controls_pause"]
	_begin_overlay("settings_pause" if from_pause else "settings_title")
	var body := _modal("设置", Vector2(540, 500))
	body.add_child(_label("主音量", 18, BONE))
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.05
	volume.value = float(_settings["volume"])
	volume.custom_minimum_size.y = 34
	volume.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	volume.value_changed.connect(_change_volume)
	body.add_child(volume)
	var shake := CheckButton.new()
	shake.text = "镜头震动"
	ButtonSkin.apply(shake)
	shake.button_pressed = bool(_settings["shake"])
	shake.toggled.connect(_change_toggle.bind("shake"))
	body.add_child(shake)
	var flash := CheckButton.new()
	flash.text = "受击闪光"
	ButtonSkin.apply(flash)
	flash.button_pressed = bool(_settings["flash"])
	flash.toggled.connect(_change_toggle.bind("flash"))
	body.add_child(flash)
	var controls := _button("操作设置", _show_controls.bind(from_pause), Vector2(0, 42))
	controls.name = "ControlsSettings"
	body.add_child(controls)
	_spacer(body, 8)
	var back := _button("返回", show_pause if from_pause else hide_pause, Vector2(0, 46))
	body.add_child(back)
	_focus_later(controls if returning_from_controls else back)


func _show_controls(from_pause: bool) -> void:
	_begin_overlay("controls_pause" if from_pause else "controls_title")
	var epoch: int = _controls_epoch
	var body := _modal("操作设置", Vector2(700, 646))
	(body.get_parent().get_parent() as Control).name = "ControlsPanel"
	body.add_theme_constant_override("separation", 8)
	body.add_child(_wrap("选择动作后按新键；Esc / 手柄B取消本次重绑。", 14, MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for action: String in ControlBindings.ACTIONS:
		var label := _label(ControlBindings.action_label(action), 16, BONE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(label)
		var binding := _button("", _begin_control_capture.bind(action, epoch), Vector2(210, 34))
		binding.name = "Bind_" + action
		binding.add_theme_font_size_override("font_size", 16)
		binding.tooltip_text = "修改%s的键盘主键；方向键始终可用于移动。" % ControlBindings.action_label(action)
		grid.add_child(binding)
		_control_buttons[action] = binding
	_capture_label = _label("", 14, GOLD)
	_capture_label.name = "BindingCapture"
	body.add_child(_capture_label)
	_controls_notice = _wrap("主键不可重复；界面保留键不可重绑。", 14, MUTED)
	_controls_notice.name = "BindingStatus"
	_controls_notice.custom_minimum_size.y = 34
	body.add_child(_controls_notice)
	var guide := _wrap("键盘：方向键始终可用；Esc、Enter、Tab、F11及修饰键保留。\n手柄：左杆 / 十字移动，A冲刺，X / Y技能，Start暂停。\n菜单A确定、B返回；背包持物时X旋转。", 13, MUTED)
	guide.name = "ControllerGuide"
	body.add_child(guide)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	var restore := _button("恢复默认", _restore_controls.bind(epoch), Vector2(0, 42))
	restore.name = "RestoreControls"
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(restore)
	var back := _button("返回设置", _close_controls.bind(from_pause, epoch), Vector2(0, 42))
	back.name = "CloseControls"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(back)
	_refresh_control_buttons()
	_focus_later(_control_buttons["move_up"] as Button)


func _controls_page_current(epoch: int) -> bool:
	return epoch == _controls_epoch and _overlay_mode in ["controls_title", "controls_pause"]


func _begin_control_capture(action: String, epoch: int) -> void:
	if not _controls_page_current(epoch) or not _controls.has(action):
		return
	_capture_action = action
	_refresh_control_buttons()
	_set_controls_notice("按下新的键盘主键；Esc / 手柄B取消。", MUTED)


func _cancel_control_capture() -> void:
	var source := _control_buttons.get(_capture_action) as Button
	_capture_action = ""
	_refresh_control_buttons()
	_set_controls_notice("已取消，原按键保持。", MUTED)
	if is_instance_valid(source):
		_focus_later(source)


func _refresh_control_buttons() -> void:
	for action: String in _control_buttons:
		var button := _control_buttons[action] as Button
		if not is_instance_valid(button):
			continue
		button.text = "请按新键…" if _capture_action == action else ControlBindings.key_label(int(_controls[action]))
		button.add_theme_color_override("font_color", CYAN if _capture_action == action else BONE)
	if is_instance_valid(_capture_label):
		_capture_label.text = "正在重绑：" + ControlBindings.action_label(_capture_action) if not _capture_action.is_empty() else "选择一个动作开始重绑。"


func _set_controls_notice(message: String, color: Color) -> void:
	if is_instance_valid(_controls_notice):
		_controls_notice.text = message
		_controls_notice.add_theme_color_override("font_color", color)


func _restore_controls(epoch: int) -> void:
	if not _controls_page_current(epoch):
		return
	_capture_action = ""
	set_controls(ControlBindings.defaults())
	_set_controls_notice("已恢复默认键位。", CYAN)
	controls_changed.emit(_controls.duplicate(true))


func _close_controls(from_pause: bool, epoch: int) -> void:
	if _controls_page_current(epoch):
		_show_settings(from_pause)


func _clear_controls_modal_state() -> void:
	_controls_epoch += 1
	_capture_action = ""
	_control_buttons.clear()
	_controls_notice = null
	_capture_label = null


func _change_volume(value: float) -> void:
	_settings["volume"] = value
	setting_changed.emit("volume", value)


func _change_toggle(value: bool, key: String) -> void:
	_settings[key] = value
	setting_changed.emit(key, value)


func _candle_link_names(candle: Dictionary) -> String:
	var names: PackedStringArray = []
	var candle_size: Vector2i = BACKPACK_GRID._item_size(candle, bool(candle.get("rotated", false)))
	var candle_rect := Rect2i(Vector2i(int(candle["x"]), int(candle["y"])), candle_size)
	for weapon: Dictionary in run.loadout:
		var item: Dictionary = run.backpack_item(int(weapon["uid"]))
		var item_size: Vector2i = BACKPACK_GRID._item_size(item, bool(item.get("rotated", false)))
		var rect := Rect2i(Vector2i(int(item["x"]), int(item["y"])), item_size)
		if rect.end.y == candle_rect.position.y and rect.position.x < candle_rect.end.x and rect.end.x > candle_rect.position.x:
			names.append("%s #%d" % [GameCatalog.weapon(str(item["id"])).display_name, int(item["uid"])])
	return "、".join(names) if not names.is_empty() else "无；请把烛台放在法器正下方。"


func _select_starter(id: String) -> void:
	if _screen != "title" or not _overlay_mode.is_empty() or not _unlocked_starters.has(id):
		return
	_starter = id
	_refresh_title.call_deferred()


func _refresh_title() -> void:
	if _screen != "title":
		return
	# Update in place so a queued selection never rebuilds away a settings modal
	# or its source control and keyboard focus.
	for id: String in ["bone", "ember", "frost", "scatter"]:
		var button := _page.find_child("Starter_" + id, true, false) as Button
		if button != null:
			button.set_pressed_no_signal(_starter == id)
			var mark := button.get_node_or_null("SelectionMark") as Control
			if mark != null:
				mark.queue_redraw()


func _start() -> void:
	if _screen not in ["title", "result"] or not _overlay_mode.is_empty():
		return
	if not _unlocked_starters.has(_starter):
		return
	start_requested.emit(_starter)


func _next_wave() -> void:
	next_wave_requested.emit()


func _resume() -> void:
	resume_requested.emit()


func _menu() -> void:
	menu_requested.emit()


func _quit() -> void:
	quit_requested.emit()


func _buy(index: int) -> void:
	_requested_shop_focus = "buy:%d" % index
	if is_instance_valid(_bag_grid):
		_bag_grid.cancel_placement()
	if index < 0 or index >= run.offers.size():
		_handle_action(run.buy_offer(index), "buy")
		return
	var offer: Dictionary = run.offers[index]
	var success := run.buy_offer(index)
	if success:
		var items: Array = run.backpack_snapshot()["items"]
		_bag_selected_uid = int(items.back()["uid"])
		_selected_rune = run.rune_index_for_uid(_bag_selected_uid)
		_requested_shop_focus = "bag:%d" % _bag_selected_uid
	if success and str(offer.get("kind", "")) == "rune":
		_requested_shop_focus = "bag_equip:%d" % int(run.loadout[0]["uid"])
		_handle_action(true, "buy", "符文已放入空格；拖到法器上或选择「装入」，免费改装。")
	else:
		_handle_action(success, "buy")


func _reroll() -> void:
	_requested_shop_focus = "reroll"
	_handle_action(run.reroll_shop(), "buy")


func _sell_weapon(index: int) -> void:
	_requested_shop_focus = "sell_weapon:%d" % index
	_handle_action(run.sell_weapon(index), "buy")


func _sell_rune(index: int) -> void:
	if index < 0 or index >= run.rune_bag.size():
		_handle_action(run.sell_rune(index), "buy")
		return
	_requested_shop_focus = "sell_rune:%d" % int(run.rune_bag[index]["uid"])
	_selected_rune = -1
	_handle_action(run.sell_rune(index), "buy")


func _select_rune(index: int) -> void:
	if index < 0 or index >= run.rune_bag.size():
		return
	_selected_rune = -1 if _selected_rune == index else index
	_requested_shop_focus = "equip:0" if _selected_rune >= 0 else "rune:%d" % int(run.rune_bag[index]["uid"])
	_queue_refresh()


func _equip(index: int) -> void:
	if _selected_rune < 0 or _selected_rune >= run.rune_bag.size() or index < 0 or index >= run.loadout.size():
		_handle_action(run.equip_rune(_selected_rune, index), "rune")
		return
	var rune: Dictionary = run.rune_bag[_selected_rune]
	var weapon: Dictionary = run.loadout[index]
	var weapon_name: String = GameCatalog.weapon(str(weapon["id"])).display_name
	var rune_name: String = GameCatalog.rune(str(rune["id"])).display_name
	_requested_shop_focus = "equip:%d" % index
	var success := run.equip_rune(_selected_rune, index)
	if success:
		_selected_rune = -1
	_handle_action(success, "rune", "%s已装入%s。悬停法器名称可查看详情。" % [rune_name, weapon_name])


func _unequip(index: int) -> void:
	if index < 0 or index >= run.loadout.size():
		_handle_action(run.unequip_rune(index), "rune")
		return
	var weapon: Dictionary = run.loadout[index]
	var rune: Dictionary = weapon.get("rune", {})
	_requested_shop_focus = "unequip:%d" % index
	var success := run.unequip_rune(index)
	if success:
		_requested_shop_focus = "rune:%d" % int(rune.get("uid", -1))
	_handle_action(success, "rune", "%s的符文已卸下，退回备用栏。" % GameCatalog.weapon(str(weapon["id"])).display_name)


func _choose_upgrade(id: String) -> void:
	_handle_action(run.choose_upgrade(id), "level")


func _finish_upgrades(epoch: int) -> void:
	if _screen == "transition" and epoch == _upgrade_epoch:
		upgrades_finished.emit()


func _handle_action(success: bool, sound: String = "", message: String = "") -> void:
	if success:
		if not sound.is_empty():
			feedback.emit(sound)
		if not message.is_empty():
			notify(message)
	else:
		notify(run.last_error if not run.last_error.is_empty() else "当前无法完成此操作。")
	_queue_refresh()


func _on_state_changed() -> void:
	if _overlay_mode in ["relic_comparison", "rune_equip_comparison", "rogue_choices"]:
		hide_pause()
	if _screen == "shop" or _screen == "upgrades":
		_queue_refresh()


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	if _screen == "shop":
		_build_shop()
	elif _screen == "upgrades":
		_build_upgrades()


func _set_screen(screen: String) -> void:
	_clear_controls_modal_state()
	_hud_skill_snapshot.clear()
	_rogue_epoch += 1
	_rogue_notice = ""
	_screen = screen
	_bag_held_uid = -1
	_bag_selected_uid = -1
	if is_instance_valid(_bag_grid):
		_bag_grid.cancel_placement()
		_bag_grid.interaction_enabled = false
	_bag_grid = null
	_bag_details = null
	_bag_status = null
	if screen != "upgrades":
		_upgrades_during_combat = false
	_requested_shop_focus = ""
	_overlay_mode = ""
	_page_focus = null
	_page_focus_id = ""
	_page.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	_clear(_page)
	_clear(_overlay)
	if _toast != null:
		_toast.hide()


func _update_hud_slots(loadout: Array) -> void:
	var slots: HBoxContainer = _hud["slots"]
	_clear(slots)
	for index in range(mini(8, loadout.size())):
		var card := PanelContainer.new()
		card.name = "EquipmentSlot%d" % (index + 1)
		card.custom_minimum_size.x = 94
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := _box(Color("f4edd8"), Color(GOLD, 0.22))
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		card.add_theme_stylebox_override("panel", style)
		slots.add_child(card)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(box)
		box.add_child(_label("%02d" % (index + 1), 12, GOLD))
		var item: Dictionary = loadout[index]
		var definition: ContentDef = GameCatalog.weapon(str(item["id"]))
		_enable_tooltip(card, _equipment_tooltip(item))
		_add_icon(box, definition, 26)
		var names := VBoxContainer.new()
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		names.add_theme_constant_override("separation", 1)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(names)
		var title := _label(definition.display_name + " " + _rank_name(int(item.get("rank", 1))), 12, BONE)
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names.add_child(title)
		var rune: Dictionary = item.get("rune", {})
		var socket := _label("无附魔" if rune.is_empty() else "%s %s" % [GameCatalog.rune(str(rune["id"])).display_name, _rank_name(int(rune.get("rank", 1)))], 10, MUTED if rune.is_empty() else PURPLE)
		socket.clip_text = true
		socket.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names.add_child(socket)
	if loadout.size() > 8:
		var more := _label("另%d件\n同样攻击" % (loadout.size() - 8), 12, GOLD)
		more.name = "AdditionalWeapons"
		_enable_tooltip(more, _loadout_text())
		slots.add_child(more)


func _definition(kind: String, id: String) -> ContentDef:
	match kind:
		"rune":
			return GameCatalog.rune(id)
		"relic":
			return GameCatalog.relic(id)
		"skill":
			return GameCatalog.skill(id)
	return GameCatalog.weapon(id)


func _rune_guide() -> String:
	if _selected_rune >= 0 and _selected_rune < run.rune_bag.size():
		var definition: ContentDef = GameCatalog.rune(str(run.rune_bag[_selected_rune]["id"]))
		return "已选%s %s阶：%s" % [definition.display_name, _rank_name(int(run.rune_bag[_selected_rune].get("rank", 1))), _rune_rank_text(definition.id, int(run.rune_bag[_selected_rune].get("rank", 1)))]
	return ""


func _shop_description(definition: ContentDef) -> String:
	if not definition.shop_summary.is_empty():
		return definition.shop_summary
	if definition.kind == "weapon" and definition.innate_pierce > 0:
		if definition.innate_pierce == 1:
			return "首目标仅本体贯穿，不触发符文。第二命中起触发符文；爆破须命中第二目标。"
		return "本体先贯穿额外%d个目标；符文从第%d次直接命中触发，爆破须达到该次命中。" % [definition.innate_pierce, definition.innate_pierce + 1]
	return definition.description


func _item_resonance_bonus(item: Dictionary) -> float:
	if item.has("resonance_bonus"):
		return float(item["resonance_bonus"])
	if run == null:
		return 0.0
	var index: int = run.weapon_index_for_uid(int(item.get("uid", -1)))
	return float(run.loadout[index].get("resonance_bonus", 0.0)) if index >= 0 else 0.0


func _resonance_details(item: Dictionary) -> String:
	if run == null:
		return ""
	var uid: int = int(item.get("uid", -1))
	var names: PackedStringArray = []
	if str(item.get("kind", "weapon")) == "weapon":
		var index: int = run.weapon_index_for_uid(uid)
		var sources: Array = run.loadout[index].get("resonance_sources", []) if index >= 0 else item.get("resonance_sources", [])
		for source_uid: int in sources:
			var source: Dictionary = run.backpack_item(source_uid)
			if not source.is_empty():
				names.append("%s%s #%d" % [GameCatalog.relic(str(source["id"])).display_name, _rank_name(int(source.get("rank", 1))), source_uid])
		return "邻接共鸣 +%s伤害（上限18%%）\n%s\n遗物共边Ⅰ/Ⅱ/Ⅲ阶 +3/6/12%%，对角不计。" % [_rune_percent(_item_resonance_bonus(item)), "来源：" + "、".join(names) if not names.is_empty() else "尚无共边遗物。"]
	for weapon: Dictionary in run.loadout:
		if uid in weapon.get("resonance_sources", []):
			names.append("%s #%d" % [GameCatalog.weapon(str(weapon["id"])).display_name, int(weapon.get("uid", -1))])
	return "共边供能 +%s → %s\n每把法器共鸣最高18%%；旋转、合成或出售后按新邻接重算。" % [_rune_percent(0.03 * BackpackInventory.rank_multiplier(int(item.get("rank", 1)))), "、".join(names) if not names.is_empty() else "暂无共边法器"]


func _equipment_tooltip(item: Dictionary) -> String:
	var weapon: ContentDef = GameCatalog.weapon(str(item["id"]))
	var rune: Dictionary = item.get("rune", {})
	var details: String = "%s %s阶：%s\n%s\n%s\n邻接共鸣 +%s伤害（上限18%%）。" % [weapon.display_name, _rank_name(int(item.get("rank", 1))), weapon.description, _weapon_stats_text(weapon, int(item.get("rank", 1)), _item_resonance_bonus(item)), _weapon_stats_note(), _rune_percent(_item_resonance_bonus(item))]
	if weapon.return_delay > 0.0:
		details += "\n" + _return_flight_tooltip(weapon)
	if rune.is_empty():
		return details + "\n未装符文。"
	var definition: ContentDef = GameCatalog.rune(str(rune["id"]))
	var rune_rank: int = int(rune.get("rank", 1))
	var effect: String = _rune_rank_text(definition.id, rune_rank)
	var trigger: int = weapon.innate_pierce + 1
	effect = "从第%d次直接命中触发。" % trigger + effect
	if weapon.return_delay > 0.0 and definition.id == "bounce":
		effect += "成功弹射后永久取消返航，保留当时速度继续弹射，不再回收。"
	elif weapon.return_delay > 0.0 and definition.id == "blast":
		effect += "爆破后弹体消失，不再返航。"
	return "%s\n%s %s阶：%s" % [details, definition.display_name, _rank_name(rune_rank), effect]


static func _return_flight_tooltip(weapon: ContentDef) -> String:
	var speed: float = weapon.return_speed if weapon.return_speed > 0.0 else weapon.projectile_speed
	return "预算未耗尽时，发射后%.2f秒以基础速度%.0f追踪当前玩家返航，接触玩家回收；全航程同一目标不重复直击。冷却独立计时，不等待回收。" % [weapon.return_delay, speed]


func _weapon_stats_text(definition: ContentDef, rank: int = 1, resonance_bonus: float = 0.0) -> String:
	var attack_speed: float = run.stat("attack_speed") if run != null else 1.0
	var damage: float = run.weapon_damage({"id": definition.id, "rank": rank, "resonance_bonus": resonance_bonus}) if run != null else definition.damage * BackpackInventory.rank_multiplier(rank) * (1.0 + resonance_bonus)
	return "每枚 %.1f伤害 · %d枚/次 · 间隔 %.2f秒" % [damage, definition.shots, definition.cooldown / attack_speed]


func _weapon_stats_note() -> String:
	return "已计当前伤害、攻速与该法器的邻接共鸣，未计符文追加命中。间隔为持续攻击时的标称值。"


func _enable_tooltip(control: Control, text: String) -> void:
	control.tooltip_text = text
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.focus_mode = Control.FOCUS_NONE


func _shop_button(text: String, action: Callable, focus_id: String, minimum: Vector2 = Vector2(0, 40)) -> Button:
	var button := _button(text, _perform_shop_action.bind(action, _shop_epoch), minimum)
	button.set_meta("shop_focus_id", focus_id)
	return button


func _perform_shop_action(action: Callable, epoch: int) -> void:
	# Deferred rebuilding leaves old controls alive briefly. Their indices must not
	# act on newer stock or inventory, even if another input arrives in this frame.
	if _screen != "shop" or _refresh_queued or not _overlay_mode.is_empty() or epoch != _shop_epoch:
		return
	action.call()


func _restore_shop_focus(focus_id: String, epoch: int = -1) -> void:
	if _screen != "shop" or _refresh_queued or _overlay.get_child_count() > 0 or get_viewport().gui_is_dragging() or (epoch >= 0 and epoch != _shop_epoch):
		return
	if is_instance_valid(_bag_grid) and _bag_held_uid >= 0 and int(_bag_grid.held_uid) == _bag_held_uid:
		_bag_grid.grab_focus()
		return
	var target := _shop_focus_button(focus_id)
	var operation := focus_id.get_slice(":", 0)
	if target == null and operation == "buy":
		var previous_index := int(focus_id.get_slice(":", 1))
		for offset: int in [1, 2, 3, -1, -2, -3]:
			target = _shop_focus_button("buy:%d" % (previous_index + offset))
			if target != null:
				break
	elif target == null and operation == "equip":
		target = _shop_focus_button("unequip:" + focus_id.get_slice(":", 1))
	elif target == null and operation == "sell_weapon":
		target = _shop_focus_button("sell_weapon:%d" % maxi(0, run.loadout.size() - 1))
	elif target == null and operation == "sell_rune":
		for rune: Dictionary in run.rune_bag:
			target = _shop_focus_button("sell_rune:%d" % int(rune["uid"]))
			if target != null:
				break
	elif target == null and operation.begins_with("bag"):
		target = _shop_focus_button("bag_move:%d" % _bag_selected_uid)
		if target == null:
			target = _shop_focus_button("bag:%d" % _bag_selected_uid)
	if target == null:
		for index: int in range(run.offers.size()):
			target = _shop_focus_button("buy:%d" % index)
			if target != null:
				break
	if target == null:
		target = _shop_focus_button("reroll")
	if target != null:
		target.grab_focus()


func _shop_focus_button(focus_id: String, node: Node = null) -> Button:
	var current: Node = _page if node == null else node
	if current is Button and str(current.get_meta("shop_focus_id", "")) == focus_id and not current.disabled and current.is_visible_in_tree():
		return current as Button
	for child: Node in current.get_children():
		var found := _shop_focus_button(focus_id, child)
		if found != null:
			return found
	return null


func _stats_text() -> String:
	return "生命 %d   伤害 ×%.2f   攻速 ×%.2f   移速 %.0f   护甲 %.0f   拾取 %.0f" % [int(run.stat("max_health")), run.stat("damage"), run.stat("attack_speed"), run.stat("move_speed"), run.stat("armor"), run.stat("pickup_radius")]


func _relic_text() -> String:
	var parts: PackedStringArray = []
	for id: String in run.relic_counts:
		var count := int(run.relic_counts[id])
		if count > 0:
			parts.append("%s×%d" % [GameCatalog.relic(id).display_name, count])
	return "遗物：" + ("尚未获得" if parts.is_empty() else "  ".join(parts))


func _loadout_text() -> String:
	var parts: PackedStringArray = []
	for item: Dictionary in run.loadout:
		var text: String = GameCatalog.weapon(str(item["id"])).display_name + " " + _rank_name(int(item.get("rank", 1))) + "阶"
		var rune: Dictionary = item.get("rune", {})
		if not rune.is_empty():
			text += "·" + GameCatalog.rune(str(rune["id"])).display_name + _rank_name(int(rune.get("rank", 1)))
		var bonus: float = _item_resonance_bonus(item)
		if bonus > 0.0:
			text += " · 共鸣+" + _rune_percent(bonus)
		parts.append(text)
	return "\n".join(parts)


func _best_text(best: Dictionary) -> String:
	var wave := int(best.get("wave", best.get("best_wave", 0)))
	var kills := int(best.get("kills", best.get("best_kills", 0)))
	var wins := int(best.get("wins", 0))
	if wave <= 0 and kills <= 0:
		return "尚无记录，第一道余烬等待点燃。"
	return "最高波次 %d  ·  最多击杀 %d  ·  通关 %d 次" % [wave, kills, wins]


func _background() -> void:
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(background)
	var frame := RitualFrame.new()
	frame.name = "PageOrnament"
	frame.tint = Color(GOLD, 0.4)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 14
	frame.offset_top = 14
	frame.offset_right = -14
	frame.offset_bottom = -14
	_page.add_child(frame)


func _menu_art() -> void:
	var art := TitleCover.new()
	art.name = "MenuArtwork"
	art.texture = load(TitleCover.BASE_PATH) as Texture2D
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color.WHITE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(art)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(PANEL, 0.94), Color(PANEL, 0.88), Color(PANEL, 0.30), Color(PANEL, 0.0)])
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var veil_texture := GradientTexture2D.new()
	veil_texture.gradient = gradient
	veil_texture.width = 256
	veil_texture.height = 2
	veil_texture.fill_from = Vector2.ZERO
	veil_texture.fill_to = Vector2(0.64, 0)
	var veil := TextureRect.new()
	veil.name = "TitleReadabilityVeil"
	veil.texture = veil_texture
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.focus_mode = Control.FOCUS_NONE
	veil.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_page.add_child(veil)


func _shell(horizontal: int, vertical: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin(margin, horizontal, vertical)
	_page.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	return body


func _modal(title: String, dimensions: Vector2) -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(0.10, 0.20, 0.27, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -dimensions.x * 0.5
	card.offset_right = dimensions.x * 0.5
	card.offset_top = -dimensions.y * 0.5
	card.offset_bottom = dimensions.y * 0.5
	_overlay.add_child(card)
	_decorate(card, GOLD)
	var body := _inside(card, 30)
	body.add_child(_label(title, 30, GOLD))
	_rule(body)
	return body


func _inside(panel: Control, padding: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	_margin(margin, padding, padding)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	return body


func _panel(parent: Control, minimum: Vector2 = Vector2.ZERO) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	parent.add_child(panel)
	_decorate(panel, GOLD)
	return panel


func _decorate(panel: Control, color: Color, quiet: bool = false) -> void:
	var frame := RitualFrame.new()
	frame.name = "RitualFrame"
	frame.tint = color
	frame.quiet = quiet
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(frame)


func _rule(parent: Control) -> void:
	var rule := RitualRule.new()
	rule.custom_minimum_size.y = 10
	parent.add_child(rule)


func _section_heading(parent: Control, text: String, color: Color = GOLD, font_size: int = 18) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	row.add_child(_label(text, font_size, color))
	var rule := RitualRule.new()
	rule.tint = color
	rule.custom_minimum_size.x = 28
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rule)


func _label(text: String, font_size: int = 18, color: Color = BONE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _wrap(text: String, font_size: int = 18, color: Color = BONE) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(text: String, action: Callable, minimum: Vector2 = Vector2(0, 40)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	ButtonSkin.apply(button, "secondary", minimum.y > 0.0 and minimum.y <= 35.0)
	return button


func _focus_later(control: Control) -> void:
	# A screen may be replaced again before its deferred focus request runs.
	var request: Callable = func() -> void:
		if not is_instance_valid(control) or not control.is_inside_tree() or not control.is_visible_in_tree():
			return
		if get_viewport().gui_is_dragging() and not _overlay.is_ancestor_of(control):
			return
		# A delayed underlying-page rebuild must never steal a modal's focus.
		if not _overlay_mode.is_empty() and not _overlay.is_ancestor_of(control):
			return
		control.grab_focus()
	request.call_deferred()


func _accent(button: Button) -> void:
	ButtonSkin.apply(button, "primary")


func _spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)


func _margin(margin: MarginContainer, horizontal: int, vertical: int) -> void:
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)


func _box(fill: Color, border: Color, radius: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(border, border.a * 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = false
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


func _slider_track(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.anti_aliasing = false
	return style


func _slider_grabber(fill: Color) -> ImageTexture:
	var image := Image.create(14, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(2, 0, 10, 18), BONE)
	image.fill_rect(Rect2i(0, 2, 14, 14), BONE)
	image.fill_rect(Rect2i(2, 2, 10, 14), fill)
	image.fill_rect(Rect2i(3, 3, 8, 2), fill.lightened(0.35))
	for x: int in [5, 8]:
		image.fill_rect(Rect2i(x, 6, 1, 7), BONE)
	return ImageTexture.create_from_image(image)


static func create_ui_font() -> SystemFont:
	var font := SystemFont.new()
	# Some macOS installations resolve PingFang SC to HK without simplified glyphs.
	font.font_names = PackedStringArray([
		"Hiragino Sans GB", "PingFang SC", "Heiti SC",
		"Microsoft YaHei UI", "Microsoft YaHei", "DengXian", "SimHei", "SimSun",
		"Noto Sans CJK SC", "Noto Sans SC", "Arial",
	])
	return font


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = create_ui_font()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", BONE)
	theme.set_color("font_color", "Button", BONE)
	theme.set_color("font_hover_color", "Button", BONE)
	theme.set_color("font_pressed_color", "Button", BONE)
	theme.set_color("font_focus_color", "Button", BONE)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(GOLD, 0.3), 0))
	theme.set_stylebox("normal", "Button", _box(PANEL_LIGHT, Color(GOLD, 0.45)))
	theme.set_stylebox("hover", "Button", _box(Color("d5eee1"), GOLD))
	theme.set_stylebox("pressed", "Button", _box(Color("bfdfd4"), PURPLE))
	theme.set_stylebox("disabled", "Button", _box(Color("e1e4db"), Color("aeb9ac")))
	var focus := _box(Color(0, 0, 0, 0), CYAN)
	focus.set_border_width_all(3)
	theme.set_stylebox("focus", "Button", focus)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, "CheckButton", BONE)
	theme.set_stylebox("panel", "TooltipPanel", _box(PANEL, GOLD))
	theme.set_color("font_color", "TooltipLabel", BONE)
	theme.set_stylebox("slider", "HSlider", _slider_track(Color("dce8dd"), Color("8fafa6")))
	theme.set_stylebox("grabber_area", "HSlider", _slider_track(CYAN, CYAN.darkened(0.2)))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _slider_track(CYAN, CYAN.darkened(0.2)))
	theme.set_icon("grabber", "HSlider", _slider_grabber(Color("8bdbc0")))
	theme.set_icon("grabber_highlight", "HSlider", _slider_grabber(Color("f1c96b")))
	theme.set_icon("grabber_disabled", "HSlider", _slider_grabber(Color("b8c6bd")))
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	return theme


func _icon_texture(definition: ContentDef) -> Texture2D:
	if definition == null or definition.icon.is_empty():
		return null
	var source: String = definition.icon if definition.icon.begins_with("res://") else "res://assets/icons/%s.svg" % definition.icon
	var path: String = AdventureArt.path(source)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _add_icon(parent: Control, definition: ContentDef, size: int) -> void:
	var texture := _icon_texture(definition)
	if texture == null:
		return
	var rect := TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


func _set_button_icon(button: Button, definition: ContentDef) -> void:
	var texture := _icon_texture(definition)
	if texture != null:
		button.icon = texture
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 36)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
