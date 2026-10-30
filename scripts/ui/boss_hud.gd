class_name BossHUD
extends Control
## The world owns the arrival clock; this module only presents event-fed values.

const PHASE_ONE: Color = Color("e05a7b")
const PHASE_TWO: Color = Color("ffbd60")
const TRACK: Color = Color("1c2937e8")
const PAPER: Color = Color("fff9e8")
var health_bar: ProgressBar
var _name_label: Label
var _state: Dictionary = {}
var _phase_one_fill: StyleBoxFlat
var _phase_two_fill: StyleBoxFlat

func _init() -> void:
	name = "BossStatus"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -280
	offset_right = 280
	offset_top = 70
	offset_bottom = 126
	_phase_one_fill = _bar_fill(PHASE_ONE)
	_phase_two_fill = _bar_fill(PHASE_TWO)
	health_bar = ProgressBar.new()
	health_bar.name = "BossHealth"
	health_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	health_bar.offset_bottom = 14
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.focus_mode = Control.FOCUS_NONE
	health_bar.show_percentage = false
	health_bar.step = 0.0
	var track := _bar_fill(TRACK)
	track.border_color = Color("fff1cd75")
	track.set_border_width_all(1)
	track.shadow_color = Color(0.04, 0.07, 0.12, 0.55)
	track.shadow_size = 2
	track.shadow_offset = Vector2(0, 2)
	health_bar.add_theme_stylebox_override("background", track)
	health_bar.add_theme_stylebox_override("fill", _phase_one_fill)
	add_child(health_bar)
	_name_label = Label.new()
	_name_label.name = "BossArrivalName"
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_name_label.offset_top = 20
	_name_label.offset_bottom = 56
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.focus_mode = Control.FOCUS_NONE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_override("font", GameTypography.font())
	_name_label.add_theme_font_size_override("font_size", 24)
	_name_label.add_theme_color_override("font_color", PAPER)
	_name_label.add_theme_color_override("font_outline_color", Color("1c2937"))
	_name_label.add_theme_constant_override("outline_size", 4)
	add_child(_name_label)
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
	var phase_two: bool = raw.get("phase2", false) == true
	var intro_left: float = maxf(0.0, _finite_number(value.get("boss_intro_left"), 0.0))
	var boss_name: String = str(raw.get("display_name", "")) if intro_left > 0.0 else ""
	health_bar.max_value = maximum
	health_bar.value = clampf(hp, 0.0, maximum)
	health_bar.add_theme_stylebox_override("fill", _phase_two_fill if phase_two else _phase_one_fill)
	_name_label.text = boss_name
	_name_label.visible = not boss_name.is_empty()
	_state = {"active": true, "health": hp, "max_health": maximum,
		"phase2": phase_two, "intro_left": intro_left, "display_name": boss_name}
	show()

func clear() -> void:
	_state.clear()
	hide()
	if health_bar == null:
		return
	_name_label.text = ""
	_name_label.hide()
	health_bar.value = 0.0
	health_bar.max_value = 1.0

func snapshot() -> Dictionary:
	return _state.duplicate(true)

static func _finite_number(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback

static func _bar_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style
