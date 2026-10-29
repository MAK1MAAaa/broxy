class_name BossHUD
extends PanelContainer
## Event-fed boss state; clocks and combat decisions remain in BossEncounter.

const PAPER: Color = Color("fff9e8")
const INK: Color = Color("253d54")
const RED: Color = Color("b83c50")
const GOLD: Color = Color("8a5b20")
var health_bar: ProgressBar
var charge_bar: ProgressBar
var _name_label: Label
var _health_label: Label
var _phase_label: Label
var _state_label: Label
var _skill_label: Label
var _state: Dictionary = {}
var _normal_panel: StyleBoxFlat
var _broken_panel: StyleBoxFlat
var _normal_fill: StyleBoxFlat
var _broken_fill: StyleBoxFlat

func _init() -> void:
	name = "BossStatus"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -400
	offset_right = 400
	offset_top = 104
	offset_bottom = 154
	_normal_panel = _panel(RED)
	_broken_panel = _panel(GOLD)
	_normal_fill = _bar_fill(RED)
	_broken_fill = _bar_fill(GOLD)
	add_theme_stylebox_override("panel", _normal_panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 2)
	margin.add_child(rows)
	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_constant_override("separation", 12)
	rows.add_child(title)
	_name_label = _label("BossName", 24)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_child(_name_label)
	_health_label = _label("BossHealthValue", 12)
	_health_label.custom_minimum_size.x = 112
	title.add_child(_health_label)
	_phase_label = _label("BossPhase", 12)
	_phase_label.custom_minimum_size.x = 60
	title.add_child(_phase_label)
	_state_label = _label("BossBreak", 12)
	_state_label.custom_minimum_size.x = 76
	title.add_child(_state_label)
	var bars := HBoxContainer.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", 12)
	rows.add_child(bars)
	health_bar = _bar("BossHealth", RED, 10)
	health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_child(health_bar)
	_skill_label = _label("BossSkillName", 12)
	_skill_label.custom_minimum_size.x = 156
	_skill_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bars.add_child(_skill_label)
	charge_bar = _bar("BossCharge", GOLD, 8)
	charge_bar.custom_minimum_size.x = 128
	charge_bar.max_value = 1
	bars.add_child(charge_bar)
	set_process(false)
	set_physics_process(false)
	clear()

func update_snapshot(value: Variant) -> void:
	clear()
	if not value is Dictionary:
		return
	var raw: Variant = value.get("boss_encounter")
	if not raw is Dictionary or raw.get("active", false) != true:
		return
	var hp: float = _finite_number(raw.get("health"), -1.0)
	var maximum: float = _finite_number(raw.get("max_health"), -1.0)
	if hp <= 0 or maximum <= 0:
		return
	var phase: String = str(raw.get("phase", "stopped"))
	var break_left: float = maxf(0, _finite_number(raw.get("break_left"), 0))
	var broken: bool = phase == "break" and break_left > 0
	var charge_total: float = _finite_number(raw.get("charge_total"), 0)
	var charge_left: float = maxf(0, _finite_number(raw.get("charge_left"), 0))
	var charging: bool = phase == "charge" and charge_total > 0
	var boss_name: String = str(raw.get("display_name", ""))
	var skill_name: String = str(raw.get("name", ""))
	_name_label.text = boss_name
	_name_label.tooltip_text = boss_name
	_health_label.text = "%d / %d" % [ceili(hp), ceili(maximum)]
	_phase_label.text = "阶段 %d" % [2 if raw.get("phase2", false) == true else 1]
	_state_label.visible = broken
	_state_label.text = "破防 %.1f" % break_left if broken else ""
	_state_label.add_theme_color_override("font_color", GOLD)
	health_bar.max_value = maximum
	health_bar.value = clampf(hp, 0, maximum)
	health_bar.add_theme_stylebox_override("fill", _broken_fill if broken else _normal_fill)
	_skill_label.visible = charging and not skill_name.is_empty()
	_skill_label.text = skill_name if charging else ""
	_skill_label.tooltip_text = skill_name if charging else ""
	charge_bar.visible = charging
	charge_bar.value = clampf(1 - charge_left / charge_total, 0, 1) if charging else 0
	add_theme_stylebox_override("panel", _broken_panel if broken else _normal_panel)
	_state = {"active": true, "display_name": boss_name, "health": hp, "max_health": maximum,
		"phase": phase, "phase2": raw.get("phase2", false) == true,
		"name": skill_name if charging else "", "charge_progress": charge_bar.value,
		"break_left": break_left if broken else 0.0}
	show()

func clear() -> void:
	_state.clear()
	hide()
	if health_bar == null:
		return
	_name_label.text = ""
	_name_label.tooltip_text = ""
	_health_label.text = ""
	_phase_label.text = ""
	_state_label.text = ""
	_state_label.hide()
	_skill_label.text = ""
	_skill_label.tooltip_text = ""
	_skill_label.hide()
	charge_bar.value = 0
	charge_bar.hide()
	health_bar.value = 0
	health_bar.max_value = 1

func snapshot() -> Dictionary:
	return _state.duplicate(true)

static func _finite_number(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback

static func _label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", GameTypography.font())
	label.add_theme_font_size_override("font_size", GameTypography.size_for(font_size))
	label.add_theme_color_override("font_color", INK)
	return label

static func _bar(node_name: String, color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.focus_mode = Control.FOCUS_NONE
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", _bar_fill(color))
	bar.add_theme_stylebox_override("background", _bar_fill(Color("dbd3c3")))
	return bar

static func _bar_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style

static func _panel(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = color
	style.set_border_width_all(1)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style
