class_name ButtonSkin
extends RefCounted
## Event-driven presentation for actions; no input, focus or business state changes.

const INK := Color("253d54")
const CREAM := Color("fff5dc")
const GOLD := Color("edbc65")
const ROLES: Array[String] = ["primary", "secondary", "choice", "quiet", "blocked"]
const STATES: Array[String] = ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]


class ButtonFinish:
	extends Control
	var button: Button
	var role: String = "secondary"
	var compact: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		set_process(false)
		resized.connect(queue_redraw)

	func watch(owner_button: Button) -> void:
		button = owner_button
		button.mouse_entered.connect(queue_redraw)
		button.mouse_exited.connect(queue_redraw)
		button.button_down.connect(queue_redraw)
		button.button_up.connect(queue_redraw)
		button.focus_entered.connect(queue_redraw)
		button.focus_exited.connect(queue_redraw)
		button.toggled.connect(_on_toggled)
		# Includes native redraws caused by disabled/theme changes, without polling.
		button.draw.connect(queue_redraw)

	func _on_toggled(_pressed: bool) -> void:
		queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(button) or size.x < 22.0 or size.y < 16.0:
			return
		var mode: int = button.get_draw_mode()
		var down: bool = mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
		var highlighted: bool = mode == BaseButton.DRAW_HOVER or mode == BaseButton.DRAW_HOVER_PRESSED
		var inset: float = 8.0 if compact else 13.0
		var top: float = (4.0 if compact else 5.0) + (2.0 if down else 0.0)
		var gloss := Color(1.0, 0.98, 0.88, 0.32 if role == "primary" else 0.7)
		if highlighted:
			gloss.a = minf(0.85, gloss.a + 0.1)
		if button.disabled:
			gloss.a = 0.18
		draw_line(Vector2(inset, top), Vector2(size.x - inset, top), gloss, 1.0, true)
		if not down and not button.disabled:
			var bottom := Color(0.09, 0.25, 0.28, 0.14 if role == "primary" else 0.1)
			draw_line(Vector2(inset, size.y - 5.0), Vector2(size.x - inset, size.y - 5.0), bottom, 1.0)
		if button.has_focus() and not button.disabled:
			var focus_inset: float = 3.0 if compact else 5.0
			_draw_focus_mark(Vector2(focus_inset, size.y * 0.5))
			_draw_focus_mark(Vector2(size.x - focus_inset, size.y * 0.5))

	func _draw_focus_mark(center: Vector2) -> void:
		var height: float = 2.0 if compact else 3.0
		var width: float = 1.0 if compact else 2.0
		var outline := PackedVector2Array([center + Vector2(0, -height - 1), center + Vector2(width + 1, 0), center + Vector2(0, height + 1), center + Vector2(-width - 1, 0)])
		var core := PackedVector2Array([center + Vector2(0, -height), center + Vector2(width, 0), center + Vector2(0, height), center + Vector2(-width, 0)])
		draw_colored_polygon(outline, ButtonSkin.INK)
		draw_colored_polygon(core, ButtonSkin.GOLD)


static func apply(button: Button, role: String = "secondary", compact: bool = false) -> void:
	role = role if role in ROLES else "secondary"
	for state: String in STATES:
		button.add_theme_stylebox_override(state, style(state, role, compact))
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var key: String = "font_color" if state == "normal" else "font_%s_color" % state
		button.add_theme_color_override(key, _palette(state, role)[2])
	var finish := button.get_node_or_null("ButtonFinish") as ButtonFinish
	if finish == null:
		finish = ButtonFinish.new()
		finish.name = "ButtonFinish"
		finish.mouse_filter = Control.MOUSE_FILTER_IGNORE
		finish.focus_mode = Control.FOCUS_NONE
		button.add_child(finish)
		finish.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		finish.watch(button)
	finish.role = role
	finish.compact = compact
	finish.queue_redraw()


static func style(state: String, role: String = "secondary", compact: bool = false) -> StyleBoxFlat:
	role = role if role in ROLES else "secondary"
	state = state if state in STATES else "normal"
	var colors: Array[Color] = _palette(state, role)
	var result := StyleBoxFlat.new()
	result.bg_color = colors[0]
	result.border_color = colors[1]
	result.set_border_width_all(1)
	result.border_width_bottom = 2 if compact else 3
	result.set_corner_radius_all(6 if compact else 10 if role == "primary" else 8)
	result.corner_detail = 6
	result.anti_aliasing = true
	result.anti_aliasing_size = 0.8
	result.shadow_color = Color(Color("1d454d"), 0.18 if role == "primary" else 0.12)
	result.shadow_size = 1 if compact else 2
	result.shadow_offset = Vector2(0, 1 if compact else 2)
	var down: bool = state == "pressed" or state == "hover_pressed"
	if down:
		result.border_width_bottom = 1
		result.shadow_size = 0
		result.shadow_offset = Vector2.ZERO
	elif state == "disabled":
		result.shadow_size = 0
		result.border_width_bottom = 1
	if state == "focus":
		result.bg_color = Color.TRANSPARENT
		result.draw_center = false
		result.border_color = GOLD if role == "primary" else INK
		result.set_border_width_all(2)
		result.shadow_color = Color(GOLD, 0.24)
		result.shadow_size = 1
		result.shadow_offset = Vector2.ZERO
	# Shift the face's content down without changing the combined minimum size.
	result.content_margin_left = 6 if compact else 12
	result.content_margin_right = 6 if compact else 12
	result.content_margin_top = (2 if compact else 7) + (2 if down else 0)
	result.content_margin_bottom = (2 if compact else 7) - (2 if down else 0)
	return result


static func _palette(state: String, role: String) -> Array[Color]:
	if state == "disabled":
		return [Color("dde4da"), Color("b4c0b5"), Color("586b61")]
	var down: bool = state == "pressed" or state == "hover_pressed"
	var hover: bool = state == "hover" or state == "hover_pressed"
	match role:
		"primary":
			return [Color("155962") if down else Color("23777b") if hover else Color("1b6d71"), Color("173f50"), CREAM]
		"choice":
			return [Color("d6ebdf") if down else Color("edf4e3") if hover else Color("fff8e5"), Color("3c827c") if down else Color("72a395") if hover else Color("b0c3b3"), INK]
		"quiet":
			return [Color("d6e6db") if down else Color("e5f0e2") if hover else Color("f2eddb"), Color("7e9e90") if down or hover else Color("b6c2ad"), Color("355a60")]
		"blocked":
			return [Color("d5dfd5") if down else Color("edf0e7") if hover else Color("e4e8de"), Color("82998c") if down or hover else Color("b3c0b3"), Color("53695f")]
	return [Color("cde7dd") if down else Color("e5f3e9") if hover else Color("f8efd9"), Color("658f86") if down or hover else Color("9eb5a4"), INK]
