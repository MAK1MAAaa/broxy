class_name GameUI
extends CanvasLayer

signal start_requested(starter: String)
signal next_wave_requested
signal resume_requested
signal menu_requested
signal quit_requested
signal setting_changed(key: String, value: Variant)
signal upgrades_finished
signal feedback(sound: String)

const INK := Color("0d111b")
const PANEL := Color("151a27")
const PANEL_LIGHT := Color("242737")
const BONE := Color("f0e5cc")
const MUTED := Color("aaa4b3")
const GOLD := Color("c4a76f")
const PURPLE := Color("bfa2e6")
const CYAN := Color("89d8d2")
const RED := Color("df888d")
const CORAL := Color("ed9a86")

## Painted only on construction/resize. Decorative controls never intercept input.
class RitualFrame:
	extends Control
	var tint: Color = Color("c4a76f")
	var quiet: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 28 or size.y < 20:
			return
		var inset := 4.0
		var length := 8.0 if quiet else 13.0
		var corners: Array[Vector2] = [Vector2(inset, inset), Vector2(size.x - inset, inset), Vector2(inset, size.y - inset), size - Vector2.ONE * inset]
		for corner: Vector2 in corners:
			var x_direction := 1.0 if corner.x < size.x * 0.5 else -1.0
			var y_direction := 1.0 if corner.y < size.y * 0.5 else -1.0
			draw_line(corner, corner + Vector2(length * x_direction, 0), Color(tint, 0.65), 1.0)
			draw_line(corner, corner + Vector2(0, length * y_direction), Color(tint, 0.65), 1.0)
		if not quiet:
			draw_rect(Rect2(Vector2.ONE * 7, size - Vector2.ONE * 14), Color(tint, 0.09), false, 1.0)
			if size.x > 150:
				var center := Vector2(size.x * 0.5, 4)
				draw_colored_polygon(PackedVector2Array([center + Vector2(0, -3), center + Vector2(3, 0), center + Vector2(0, 3), center + Vector2(-3, 0)]), Color(tint, 0.8))


class RitualRule:
	extends Control
	var tint: Color = Color("c4a76f")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y * 0.5)
		draw_line(Vector2(0, center.y), center - Vector2(11, 0), Color(tint, 0.22), 1.0)
		draw_line(center + Vector2(11, 0), Vector2(size.x, center.y), Color(tint, 0.22), 1.0)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -3), center + Vector2(3, 0), center + Vector2(0, 3), center + Vector2(-3, 0)]), Color(tint, 0.8))

var run: RunState
var _root: Control
var _page: Control
var _overlay: Control
var _toast: Label
var _toast_timer: Timer
var _screen := "title"
var _starter := "bone"
var _selected_rune := -1
var _refresh_queued := false
var _settings := {"volume": 0.65, "shake": true, "flash": true}
var _hud: Dictionary = {}
var _hud_loadout_key := ""
var _best: Dictionary = {}
var _requested_shop_focus := ""
var _shop_epoch: int = 0
var _upgrade_epoch: int = 0
var _overlay_mode := ""
var _page_focus: Control
var _page_focus_id := ""


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
	left.custom_minimum_size.x = 530
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	left.add_child(_label("THE LAST ALTAR   /   生存 · 构筑 · 秘术", 13, GOLD))
	var title := _label("EMBERS", 68, BONE)
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Baskerville", "Georgia", "Times New Roman"])
	title.add_theme_font_override("font", title_font)
	left.add_child(title)
	left.add_child(_label("秘 术 余 烬", 27, PURPLE))
	left.add_child(_wrap("守住最后的祭坛。把每一道秘术，改造成你的答案。", 16, MUTED))
	_rule(left)
	var start_card := _panel(left)
	start_card.name = "StarterAltar"
	var start_body := _inside(start_card, 16)
	start_body.add_theme_constant_override("separation", 8)
	_section_heading(start_body, "选择起始法器", GOLD, 18)
	var starters := HBoxContainer.new()
	starters.add_theme_constant_override("separation", 12)
	start_body.add_child(starters)
	for id: String in ["bone", "ember"]:
		var definition: ContentDef = GameCatalog.weapon(id)
		var option := VBoxContainer.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_constant_override("separation", 4)
		starters.add_child(option)
		var card := _button(definition.display_name, _select_starter.bind(id), Vector2(0, 62))
		card.name = "Starter_" + id
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.toggle_mode = true
		card.button_pressed = _starter == id
		card.tooltip_text = definition.description
		card.add_theme_font_size_override("font_size", 20)
		card.add_theme_color_override("font_pressed_color", BONE)
		card.add_theme_stylebox_override("normal", _box(Color("1d2230"), Color(GOLD, 0.3)))
		card.add_theme_stylebox_override("pressed", _box(Color("302b3b"), GOLD))
		_set_button_icon(card, definition)
		option.add_child(card)
		var role := _label(definition.subtitle.get_slice(" · ", 1), 12, GOLD if _starter == id else MUTED)
		role.name = "StarterRole_" + id
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option.add_child(role)
	var chosen: ContentDef = GameCatalog.weapon(_starter)
	var starter_description := _wrap(chosen.description, 14, MUTED)
	starter_description.name = "StarterDescription"
	start_body.add_child(starter_description)
	var start := _button("进入试炼", _start, Vector2(0, 46))
	_accent(start)
	start_body.add_child(start)
	_focus_later(start)
	left.add_child(_label("最佳记录", 14, GOLD))
	left.add_child(_wrap(_best_text(best), 13, MUTED))
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
	var info_card := _panel(right)
	info_card.name = "TrialRules"
	info_card.add_theme_stylebox_override("panel", _box(Color(0.05, 0.07, 0.11, 0.78), Color(GOLD, 0.25)))
	var info := _inside(info_card, 14)
	info.add_theme_constant_override("separation", 7)
	_section_heading(info, "试炼守则", GOLD, 16)
	info.add_child(_wrap("WASD / 方向键  移动   ·   Esc  暂停\n自动攻击，收集魂屑；波末升级 → 商店 → 下一波\n符文可在商店免费拆换；波末祭坛恢复全部生命。", 14, BONE))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	shell.add_child(footer)
	footer.add_child(_button("设置", _show_settings.bind(false), Vector2(120, 40)))
	footer.add_child(_button("退出游戏", _quit, Vector2(140, 40)))
	var note := _label("I — VIII   /   最后的余烬，由你守护", 13, GOLD)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(note)


func show_hud() -> void:
	_set_screen("hud")
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
	top.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
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
	hp.add_theme_stylebox_override("background", _bar_style(Color("2d2630")))
	health_box.add_child(hp)
	_hud["health_bar"] = hp
	for entry: Array in [["wave", "波次  1 / 8"], ["time", "剩余  00:45"], ["gold", "魂屑  0"], ["level", "等级  1"]]:
		var item := _label(str(entry[1]), 17, GOLD if entry[0] == "gold" else BONE)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item)
		_hud[str(entry[0])] = item
	var xp := ProgressBar.new()
	xp.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	xp.offset_left = 26
	xp.offset_right = -26
	xp.offset_top = 91
	xp.offset_bottom = 94
	xp.show_percentage = false
	xp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp.add_theme_stylebox_override("fill", _bar_style(PURPLE))
	xp.add_theme_stylebox_override("background", _bar_style(Color("292334")))
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
	boss_hp.add_theme_stylebox_override("background", _bar_style(Color("2d2630")))
	boss.add_child(boss_hp)
	boss.hide()
	_hud["boss"] = boss
	_hud["boss_bar"] = boss_hp
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
	var help := _label("WASD / 方向键  移动\nEsc  暂停", 15, MUTED)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_row.add_child(help)


func update_hud(snapshot: Dictionary) -> void:
	if _screen != "hud" or _hud.is_empty():
		return
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
	_hud["xp_bar"].max_value = maxf(1, float(snapshot.get("xp_needed", 1)))
	_hud["xp_bar"].value = float(snapshot.get("xp", 0))
	_hud["boss"].visible = boss_alive
	_hud["boss_bar"].max_value = maxf(1, boss_max)
	_hud["boss_bar"].value = boss_health
	var loadout: Array = snapshot.get("loadout", [])
	var key := str(loadout)
	if key != _hud_loadout_key:
		_hud_loadout_key = key
		_update_hud_slots(loadout)


func show_shop() -> void:
	_set_screen("shop")
	_selected_rune = -1
	_requested_shop_focus = "buy:0"
	_build_shop()


func show_upgrades() -> void:
	_set_screen("upgrades")
	_build_upgrades()


func show_pause() -> void:
	var returning_from_settings: bool = _overlay_mode == "settings_pause"
	_begin_overlay("pause")
	var body := _modal("试炼暂停", Vector2(500, 470))
	body.add_child(_label("余烬尚未熄灭。", 17, MUTED))
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
	_clear(_overlay)
	_overlay_mode = ""
	_page.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	if restore_focus:
		_restore_page_focus()
	_page_focus = null
	_page_focus_id = ""


func handle_back() -> bool:
	if _overlay_mode == "relic_details" or _overlay_mode == "relic_comparison":
		hide_pause()
		return true
	if _overlay_mode == "settings_pause":
		show_pause()
		return true
	if _overlay_mode == "settings_title":
		hide_pause()
		return true
	return false


func _begin_overlay(mode: String) -> void:
	if _overlay_mode.is_empty():
		var current: Control = get_viewport().gui_get_focus_owner()
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
	body.add_child(_wrap(_loadout_text(), 15, BONE))
	body.add_child(_wrap("最佳记录：" + _best_text(best), 13, MUTED))
	var damage_card := _panel(columns)
	damage_card.name = "DamageContribution"
	damage_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var damage_body := _inside(damage_card, 22)
	damage_body.add_theme_constant_override("separation", 12)
	_section_heading(damage_body, "法器伤害贡献", GOLD, 18)
	damage_body.add_child(_wrap("本局实际造成的生命损失，包含已出售法器。", 13, MUTED))
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
			bar.add_theme_stylebox_override("background", _bar_style(Color("252638")))
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
	_toast.text = message
	if _screen == "hud":
		# The player's art, orbiting weapons and shake extend above its collision
		# bounds. Use the status panel's spare row, alongside the boss meter.
		_toast.add_theme_font_size_override("font_size", 13)
		var style := _box(PANEL_LIGHT, Color(GOLD, 0.55))
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		_toast.add_theme_stylebox_override("normal", style)
		_toast.clip_text = true
		_toast.max_lines_visible = 1
		_toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_toast.offset_left = 54
		_toast.offset_right = 690
		_toast.offset_top = 62
		_toast.offset_bottom = 82
	else:
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
	if _overlay_mode == "relic_comparison":
		hide_pause()
	_shop_epoch += 1
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
	heading.add_child(_label("波次 %d 完成   /   魂屑 %d" % [run.wave, run.gold], 22, GOLD))
	var guide := _wrap(_rune_guide(), 15, PURPLE if _selected_rune >= 0 else MUTED)
	guide.name = "RuneGuide"
	shell.add_child(guide)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(columns)
	var goods := VBoxContainer.new()
	goods.custom_minimum_size.x = 670
	goods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(goods)
	_section_heading(goods, "本次供奉", GOLD, 18)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	goods.add_child(grid)
	for index in range(run.offers.size()):
		_offer_card(grid, index)
	var build_card := _panel(columns, Vector2(490, 0))
	var build := _inside(build_card, 16)
	build.add_theme_constant_override("separation", 7)
	_section_heading(build, "法器  %d / 4" % run.loadout.size(), GOLD, 18)
	for index in range(4):
		_weapon_row(build, index)
	_section_heading(build, "备用符文  %d / 4" % run.rune_bag.size(), PURPLE, 16)
	var bag := HBoxContainer.new()
	bag.add_theme_constant_override("separation", 5)
	build.add_child(bag)
	for index in range(4):
		_bag_slot(bag, index)
	_build_relic_inventory(build)
	var stats_card := _panel(shell)
	var stats_margin := MarginContainer.new()
	_margin(stats_margin, 14, 10)
	stats_card.add_child(stats_margin)
	stats_margin.add_child(_label(_stats_text(), 15, BONE))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	shell.add_child(footer)
	footer.add_child(_shop_button("刷新  %d 魂屑" % run.reroll_cost(), _reroll, "reroll", Vector2(180, 46)))
	var hint := _label("拆换符文保留原符文；出售不可撤回。", 14, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var next := _shop_button("开始下一波", _next_wave, "next_wave", Vector2(210, 46))
	_accent(next)
	footer.add_child(next)
	_restore_shop_focus.call_deferred(focus_id)


func _offer_card(parent: Control, index: int) -> void:
	var offer: Dictionary = run.offers[index]
	var kind := str(offer.get("kind", "weapon"))
	var definition = _definition(kind, str(offer.get("id", "")))
	var card := _panel(parent, Vector2(320, 190))
	card.name = "Offer%d" % (index + 1)
	var category: Color = {"weapon": GOLD, "rune": PURPLE, "relic": CYAN}.get(kind, GOLD)
	var border := _box(Color("171c29"), Color(category, 0.48))
	border.border_width_left = 3
	card.add_theme_stylebox_override("panel", border)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := _inside(card, 14)
	body.add_theme_constant_override("separation", 6)
	var name_row := HBoxContainer.new()
	body.add_child(name_row)
	_add_icon(name_row, definition, 44)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(names)
	var name_label := _label(definition.display_name, 21, BONE)
	_enable_tooltip(name_label, definition.description)
	names.add_child(name_label)
	var ownership: String = ""
	match kind:
		"weapon": ownership = "法器%d/%d槽" % [run.loadout.size(), RunState.WEAPON_CAP]
		"rune": ownership = "备用%d/%d" % [run.rune_bag.size(), RunState.RUNE_BAG_CAP]
		"relic": ownership = "持有%d/%d层" % [int(run.relic_counts.get(definition.id, 0)), RunState.RELIC_CAP]
	names.add_child(_label({"weapon": "法器", "rune": "符文", "relic": "遗物"}.get(kind, kind) + "  /  " + definition.subtitle.get_slice(" · ", 1) + " · " + ownership, 11, category))
	var summary: String = "首目标仅本体贯穿，不触发符文。第二命中起触发符文；爆破须命中第二目标。" if definition.id == "crescent" else definition.description
	var description := _wrap(summary, 14, MUTED)
	description.name = "OfferDescription"
	_enable_tooltip(description, definition.description)
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(description)
	if kind == "weapon":
		var stats := _wrap(_weapon_stats_text(definition), 14, GOLD)
		stats.name = "WeaponStats"
		_enable_tooltip(stats, _weapon_stats_note())
		body.add_child(stats)
	var sold := bool(offer.get("sold", false))
	var price: int = int(offer.get("price", 0))
	var error: String = run.purchase_error(index)
	var blocked: bool = not sold and not error.is_empty()
	var buy_text: String = "已购买" if sold else "购买  %d 魂屑" % price
	if blocked:
		var reason: String = {
			"魂屑不足。": "魂屑不足",
			"法器槽已满，请先出售一件法器。": "法器槽已满",
			"备用符文已满，请先装备或出售。": "备用符文已满",
			"该遗物已达到3层上限。": "遗物已满3层",
		}.get(error, "暂不可购")
		buy_text = "%s · %d魂屑" % [reason, price]
	var buy := _shop_button(buy_text, _buy.bind(index), "buy:%d" % index, Vector2(0, 35))
	buy.add_theme_font_size_override("font_size", 14 if kind == "relic" else 16)
	buy.add_theme_color_override("font_color", MUTED if blocked else GOLD)
	buy.add_theme_stylebox_override("normal", _box(Color("1a1d29") if blocked else Color("232231"), Color(MUTED, 0.3) if blocked else Color(category, 0.48)))
	buy.tooltip_text = error
	if error == "魂屑不足。":
		buy.tooltip_text += "还差%d魂屑。" % (price - run.gold)
	elif error == "备用符文已满，请先装备或出售。":
		buy.tooltip_text += "\n把备用符文装入无符文法器，或出售备用符文；替换已有符文不会腾位。"
	elif error == "法器槽已满，请先出售一件法器。":
		buy.tooltip_text += "\n出售带符文的法器，需要1个备用符文空位。"
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
	var layers: String = "层数  %d / %d → %d / %d（购后）" % [int(preview["stack_before"]), RunState.RELIC_CAP, int(preview["stack_after"]), RunState.RELIC_CAP] if projected else "层数  %d / %d（保持，不再叠加）" % [int(preview["stack_before"]), RunState.RELIC_CAP]
	var layer_label := _label(layers, 14, BONE)
	layer_label.name = "ComparisonLayers"
	summary.add_child(layer_label)
	var balance: String = "价格 %d 魂屑   ·   余额 %d → %d（购后）" % [int(preview["price"]), int(preview["gold_before"]), int(preview["gold_after"])] if bool(preview["can_buy"]) else "价格 %d 魂屑   ·   当前余额 %d（预览不扣款）" % [int(preview["price"]), int(preview["gold_before"])]
	var balance_label := _label(balance, 14, GOLD)
	balance_label.name = "ComparisonBalance"
	summary.add_child(balance_label)
	var status_text: String = "购前效果预览，尚未购买；关闭后可直接购买。"
	if not bool(preview["can_buy"]):
		status_text = "效果预览，尚缺 %d 魂屑；当前不会扣款或增加层数。" % int(preview["shortfall"]) if projected and int(preview["shortfall"]) > 0 else "无法再次购入：%s 不产生新增效果。" % str(preview["error"])
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
		var unavailable := _wrap("已售出或达到层数上限；保留当前构筑，不展示额外一层的属性与法器变化。", 17, MUTED)
		unavailable.name = "ComparisonNoProjection"
		content.add_child(unavailable)
	var note := _wrap("法器数值是每枚伤害与持续攻击时的标称间隔，未计符文追加命中；这些数值不是 DPS。\n滚轮滚动，或 Tab 选择表格区域后使用 PageUp / PageDown；Esc 返回商品。", 13, MUTED)
	note.name = "ComparisonScope"
	content.add_child(note)
	var close := _button("返回商品", _close_relic_comparison.bind(epoch), Vector2(0, 42))
	close.name = "CloseRelicComparison"
	_accent(close)
	body.add_child(close)
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
	var names: Dictionary = {"max_health": "生命上限", "damage": "伤害倍率", "attack_speed": "攻击速度倍率", "move_speed": "移动速度", "armor": "护甲", "pickup_radius": "拾取范围"}
	for change: Dictionary in preview["stat_changes"]:
		var key: String = str(change["key"])
		var delta: float = float(change["delta"])
		_comparison_cell(grid, str(names.get(key, key)), BONE, 170)
		_comparison_cell(grid, _comparison_stat_value(key, float(change["before"])), MUTED, 150)
		_comparison_cell(grid, _comparison_stat_value(key, float(change["after"])), BONE, 150)
		var variation := _comparison_cell(grid, _comparison_delta(delta, "倍" if key in ["damage", "attack_speed"] else "", 2 if key in ["damage", "attack_speed"] else 0), _comparison_change_color(delta), 260)
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
		var interval_delta: float = float(change["interval_after"]) - float(change["interval_before"])
		var interval := _comparison_cell(grid, "%.3f秒 → %.3f秒\n%s" % [float(change["interval_before"]), float(change["interval_after"]), _comparison_delta(interval_delta, "秒", 3) + ("（更快）" if interval_delta < -0.00001 else "（更慢）" if interval_delta > 0.00001 else "")], _comparison_change_color(-interval_delta), 300)
		interval.name = "ComparisonWeapon%dInterval" % slot


func _comparison_cell(parent: Control, text: String, color: Color, width: float) -> Label:
	var label := _wrap(text, 14, color)
	label.custom_minimum_size.x = width
	parent.add_child(label)
	return label


static func _comparison_stat_value(key: String, value: float) -> String:
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
	if epoch != _shop_epoch or _overlay_mode != "relic_comparison" or not event is InputEventKey:
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


func _weapon_row(parent: Control, index: int) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	if index >= run.loadout.size():
		var empty := _label("%d  ·  空法器槽" % (index + 1), 16, MUTED)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(empty)
		return
	var item: Dictionary = run.loadout[index]
	var definition = GameCatalog.weapon(str(item["id"]))
	row.add_child(_label("%02d" % (index + 1), 12, GOLD))
	_add_icon(row, definition, 31)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 1)
	row.add_child(names)
	var weapon_name := _label(definition.display_name, 16, BONE)
	_enable_tooltip(weapon_name, _equipment_tooltip(item))
	names.add_child(weapon_name)
	var rune: Dictionary = item.get("rune", {})
	var rune_label := _label("无符文" if rune.is_empty() else GameCatalog.rune(str(rune["id"])).display_name, 13, MUTED if rune.is_empty() else PURPLE)
	if not rune.is_empty():
		_enable_tooltip(rune_label, _equipment_tooltip(item))
	names.add_child(rune_label)
	if _selected_rune >= 0:
		var equip := _shop_button("装入", _equip.bind(index), "equip:%d" % index, Vector2(60, 33))
		_accent(equip)
		row.add_child(equip)
	elif not rune.is_empty():
		row.add_child(_shop_button("卸符", _unequip.bind(index), "unequip:%d" % index, Vector2(60, 33)))
	var sell := _shop_button("售", _sell_weapon.bind(index), "sell_weapon:%d" % index, Vector2(37, 33))
	sell.tooltip_text = "出售获得 %d 魂屑；符文退回背包。至少保留一件法器。" % int(floorf(float(item.get("paid", 0)) * 0.5))
	row.add_child(sell)


func _bag_slot(parent: Control, index: int) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	if index >= run.rune_bag.size():
		var empty := _button("空", func() -> void: pass, Vector2(0, 34))
		empty.disabled = true
		box.add_child(empty)
		return
	var item: Dictionary = run.rune_bag[index]
	var definition = GameCatalog.rune(str(item["id"]))
	var uid := int(item["uid"])
	var select := _shop_button(definition.display_name, _select_rune.bind(index), "rune:%d" % uid, Vector2(0, 34))
	select.toggle_mode = true
	select.button_pressed = index == _selected_rune
	select.add_theme_font_size_override("font_size", 13)
	select.tooltip_text = definition.description
	box.add_child(select)
	var sell := _shop_button("出售", _sell_rune.bind(index), "sell_rune:%d" % uid, Vector2(0, 24))
	sell.add_theme_font_size_override("font_size", 12)
	sell.tooltip_text = "出售获得 %d 魂屑。" % int(floorf(float(item.get("paid", 0)) * 0.5))
	box.add_child(sell)


func _build_relic_inventory(parent: Control) -> void:
	var owned: Array[ContentDef] = []
	for definition: ContentDef in GameCatalog.relics():
		if int(run.relic_counts.get(definition.id, 0)) > 0:
			owned.append(definition)
	var title := _label("遗物  %d 类 · 每类最多3层" % owned.size(), 14, CYAN)
	title.name = "RelicInventoryTitle"
	parent.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "RelicInventoryScroll"
	scroll.custom_minimum_size.y = 64
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	parent.add_child(scroll)
	if owned.is_empty():
		scroll.add_child(_label("尚未获得遗物", 13, MUTED))
		return
	var grid := GridContainer.new()
	grid.name = "RelicInventoryGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	for definition: ContentDef in owned:
		var count: int = int(run.relic_counts[definition.id])
		var details: String = "%s × %d\n每层：%s\n效果随层数叠加，已计入下方属性。" % [definition.display_name, count, definition.description]
		var inspect := _shop_button("%s × %d" % [definition.display_name, count], _inspect_relic.bind(definition.id), "relic:" + definition.id, Vector2(0, 28))
		inspect.name = "Relic_" + definition.id
		inspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inspect.alignment = HORIZONTAL_ALIGNMENT_LEFT
		inspect.add_theme_font_size_override("font_size", 12)
		inspect.add_theme_stylebox_override("normal", _box(Color("191f2b"), Color(CYAN, 0.2)))
		inspect.tooltip_text = details + "\n滚轮滚动清单；Tab 选择后回车查看详情。"
		_set_button_icon(inspect, definition)
		inspect.add_theme_constant_override("icon_max_width", 22)
		grid.add_child(inspect)


func _inspect_relic(id: String) -> void:
	var definition: ContentDef = GameCatalog.relic(id)
	if definition == null or run == null or int(run.relic_counts.get(id, 0)) <= 0:
		return
	_begin_overlay("relic_details")
	var body := _modal(definition.display_name, Vector2(560, 330))
	body.name = "RelicDetails"
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	body.add_child(header)
	_add_icon(header, definition, 56)
	var details := _wrap("持有 %d / %d 层\n每层：%s" % [int(run.relic_counts[id]), RunState.RELIC_CAP, definition.description], 17, BONE)
	details.name = "RelicDetailsDescription"
	header.add_child(details)
	body.add_child(_wrap("效果随层数叠加，已计入商店属性。\nEsc 或下方按钮返回清单。", 14, MUTED))
	var close := _button("返回遗物清单", hide_pause, Vector2(0, 42))
	close.name = "CloseRelicDetails"
	_accent(close)
	body.add_child(close)
	_focus_later(close)


func _build_upgrades() -> void:
	_upgrade_epoch += 1
	_clear(_page)
	_background()
	if run == null:
		return
	if run.pending_upgrades <= 0:
		_screen = "transition"
		_finish_upgrades.call_deferred()
		return
	var shell := _shell(60, 88)
	var title := _label("秘术觉醒", 40, BONE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(title)
	var sub := _label("选择一项强化  ·  待选择 %d 次" % run.pending_upgrades, 18, MUTED)
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
	var after: float = before + float(choice.get("amount", 0.0))
	if key == "damage" or key == "attack_speed":
		return "%s  ×%.2f → ×%.2f" % [names[key], before, after]
	return "%s  %.0f → %.0f" % [names[key], before, after]


func _perform_upgrade_action(id: String, epoch: int) -> void:
	# A still-live old button may refer to an ID also offered in the next set.
	if _screen != "upgrades" or _refresh_queued or not _overlay_mode.is_empty() or epoch != _upgrade_epoch:
		return
	_choose_upgrade(id)


func _show_settings(from_pause: bool) -> void:
	_begin_overlay("settings_pause" if from_pause else "settings_title")
	var body := _modal("设置", Vector2(540, 440))
	body.add_child(_label("主音量", 18, BONE))
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.05
	volume.value = float(_settings["volume"])
	volume.custom_minimum_size.y = 34
	volume.value_changed.connect(_change_volume)
	body.add_child(volume)
	var shake := CheckButton.new()
	shake.text = "镜头震动"
	shake.button_pressed = bool(_settings["shake"])
	shake.toggled.connect(_change_toggle.bind("shake"))
	body.add_child(shake)
	var flash := CheckButton.new()
	flash.text = "受击闪光"
	flash.button_pressed = bool(_settings["flash"])
	flash.toggled.connect(_change_toggle.bind("flash"))
	body.add_child(flash)
	body.add_child(_label("设置会立即生效。", 14, MUTED))
	_spacer(body, 8)
	var back := _button("返回", show_pause if from_pause else hide_pause, Vector2(0, 46))
	body.add_child(back)
	_focus_later(back)


func _change_volume(value: float) -> void:
	_settings["volume"] = value
	setting_changed.emit("volume", value)


func _change_toggle(value: bool, key: String) -> void:
	_settings[key] = value
	setting_changed.emit(key, value)


func _select_starter(id: String) -> void:
	if _screen != "title" or not _overlay_mode.is_empty() or id not in ["bone", "ember"]:
		return
	_starter = id
	_refresh_title.call_deferred()


func _refresh_title() -> void:
	if _screen != "title":
		return
	# Update in place so a queued selection never rebuilds away a settings modal
	# or its source control and keyboard focus.
	for id: String in ["bone", "ember"]:
		var button := _page.find_child("Starter_" + id, true, false) as Button
		var role := _page.find_child("StarterRole_" + id, true, false) as Label
		if button != null:
			button.set_pressed_no_signal(_starter == id)
		if role != null:
			role.add_theme_color_override("font_color", GOLD if _starter == id else MUTED)
	var description := _page.find_child("StarterDescription", true, false) as Label
	if description != null:
		description.text = GameCatalog.weapon(_starter).description


func _start() -> void:
	if _screen not in ["title", "result"] or not _overlay_mode.is_empty():
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
	if index < 0 or index >= run.offers.size():
		_handle_action(run.buy_offer(index), "buy")
		return
	var offer: Dictionary = run.offers[index]
	var success := run.buy_offer(index)
	if success and str(offer.get("kind", "")) == "rune":
		_selected_rune = run.rune_bag.size() - 1
		_requested_shop_focus = "equip:0"
		_handle_action(true, "buy", "已获得%s。选择法器「装入」，免费改装。" % GameCatalog.rune(str(offer["id"])).display_name)
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


func _finish_upgrades() -> void:
	if _screen == "transition":
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
	if _overlay_mode == "relic_comparison":
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
	_screen = screen
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
	for index in range(4):
		var card := PanelContainer.new()
		card.name = "EquipmentSlot%d" % (index + 1)
		card.custom_minimum_size.x = 210
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := _box(Color("1c1e2c"), Color(GOLD, 0.22))
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
		if index >= loadout.size():
			box.add_child(_label("空法器槽", 14, MUTED))
			continue
		var item: Dictionary = loadout[index]
		var definition: ContentDef = GameCatalog.weapon(str(item["id"]))
		_enable_tooltip(card, _equipment_tooltip(item))
		_add_icon(box, definition, 30)
		var names := VBoxContainer.new()
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		names.add_theme_constant_override("separation", 1)
		box.add_child(names)
		names.add_child(_label(definition.display_name, 14, BONE))
		var rune: Dictionary = item.get("rune", {})
		names.add_child(_label("未装符文" if rune.is_empty() else GameCatalog.rune(str(rune["id"])).display_name, 12, MUTED if rune.is_empty() else PURPLE))


func _definition(kind: String, id: String) -> ContentDef:
	match kind:
		"rune":
			return GameCatalog.rune(id)
		"relic":
			return GameCatalog.relic(id)
	return GameCatalog.weapon(id)


func _rune_guide() -> String:
	if _selected_rune >= 0 and _selected_rune < run.rune_bag.size():
		var definition: ContentDef = GameCatalog.rune(str(run.rune_bag[_selected_rune]["id"]))
		return "已选%s：%s  选择法器「装入」，原符文会退回备用栏。" % [definition.display_name, definition.description]
	return "购买法器与遗物；选择符文后点「装入」，拆换免费。波末祭坛恢复全部生命。"


func _equipment_tooltip(item: Dictionary) -> String:
	var weapon: ContentDef = GameCatalog.weapon(str(item["id"]))
	var rune: Dictionary = item.get("rune", {})
	var details: String = "%s：%s\n%s\n%s" % [weapon.display_name, weapon.description, _weapon_stats_text(weapon), _weapon_stats_note()]
	if rune.is_empty():
		return details + "\n未装符文。"
	var definition: ContentDef = GameCatalog.rune(str(rune["id"]))
	return "%s\n%s：%s" % [details, definition.display_name, definition.description]


func _weapon_stats_text(definition: ContentDef) -> String:
	var damage_multiplier: float = run.stat("damage") if run != null else 1.0
	var attack_speed: float = run.stat("attack_speed") if run != null else 1.0
	return "每枚 %.1f伤害 · %d枚/次 · 间隔 %.2f秒" % [definition.damage * damage_multiplier, definition.shots, definition.cooldown / attack_speed]


func _weapon_stats_note() -> String:
	return "已计当前伤害与攻速加成，未计符文追加命中。间隔为持续攻击时的标称值。"


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


func _restore_shop_focus(focus_id: String) -> void:
	if _screen != "shop" or _overlay.get_child_count() > 0:
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
		var text: String = GameCatalog.weapon(str(item["id"])).display_name
		var rune: Dictionary = item.get("rune", {})
		if not rune.is_empty():
			text += "·" + GameCatalog.rune(str(rune["id"])).display_name
		parts.append(text)
	return " / ".join(parts)


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
	var path := "res://assets/menu_art.svg"
	if not ResourceLoader.exists(path):
		return
	var art := TextureRect.new()
	art.name = "MenuArtwork"
	art.texture = load(path) as Texture2D
	art.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	art.offset_left = -690
	art.offset_right = 10
	art.offset_top = 0
	art.offset_bottom = 0
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.modulate = Color(1, 1, 1, 0.82)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(art)


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
	shade.color = Color(0.02, 0.03, 0.06, 0.88)
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
	return button


func _focus_later(control: Control) -> void:
	# A screen may be replaced again before its deferred focus request runs.
	var request: Callable = func() -> void:
		if not is_instance_valid(control) or not control.is_inside_tree() or not control.is_visible_in_tree():
			return
		# A delayed underlying-page rebuild must never steal a modal's focus.
		if not _overlay_mode.is_empty() and not _overlay.is_ancestor_of(control):
			return
		control.grab_focus()
	request.call_deferred()


func _accent(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _box(Color("343043"), Color(GOLD, 0.9)))
	button.add_theme_stylebox_override("hover", _box(Color("474058"), GOLD))
	button.add_theme_color_override("font_color", BONE)
	_decorate(button, GOLD, true)


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
	style.border_color = Color(border, border.a * 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


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
	theme.set_color("font_hover_color", "Button", CYAN)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color("676a78"))
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(GOLD, 0.3), 0))
	theme.set_stylebox("normal", "Button", _box(PANEL_LIGHT, Color(GOLD, 0.45)))
	theme.set_stylebox("hover", "Button", _box(Color("353449"), GOLD))
	theme.set_stylebox("pressed", "Button", _box(Color("353047"), PURPLE))
	theme.set_stylebox("disabled", "Button", _box(Color("161b26"), Color("424650")))
	var focus := _box(Color(0, 0, 0, 0), CYAN)
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	return theme


func _icon_texture(definition: ContentDef) -> Texture2D:
	if definition == null or definition.icon.is_empty():
		return null
	var path: String = definition.icon if definition.icon.begins_with("res://") else "res://assets/icons/%s.svg" % definition.icon
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _add_icon(parent: Control, definition: ContentDef, size: int) -> void:
	var texture := _icon_texture(definition)
	if texture == null:
		return
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


func _set_button_icon(button: Button, definition: ContentDef) -> void:
	var texture := _icon_texture(definition)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 36)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
