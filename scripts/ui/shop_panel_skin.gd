class_name ShopPanelSkin
extends RefCounted
## Local shop surfaces. Decorations never participate in input or layout.

class Finish extends Control:
	var tint: Color
	var backpack: bool = false
	var subdued: bool = false
	var locked: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		set_process(false)
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 36.0 or size.y < 36.0:
			return
		var edge := Color(tint, 0.19 if subdued else 0.42)
		var highlight := Color("fffef2")
		highlight.a = 0.45 if subdued else 0.88
		_draw_paper_edge(highlight)
		draw_line(Vector2(9, 3), Vector2(size.x - 9, 3), highlight, 1.0)
		draw_line(Vector2(9, size.y - 7), Vector2(size.x - 9, size.y - 7), edge, 1.0)
		for corner: Vector2 in [Vector2(6, 6), Vector2(size.x - 6, 6), Vector2(6, size.y - 9), Vector2(size.x - 6, size.y - 9)]:
			var direction := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
			draw_line(corner, corner + Vector2(direction.x * 7, 0), edge, 1.0)
			draw_line(corner, corner + Vector2(0, direction.y * 7), edge, 1.0)
			if not subdued:
				draw_rect(Rect2(corner - Vector2.ONE, Vector2(2, 2)), Color(tint, 0.62))
		if locked:
			_draw_lock_frame(highlight)
		if backpack:
			for x: float in [16.0, size.x - 16.0]:
				draw_rect(Rect2(Vector2(x - 2, 8), Vector2(4, 3)), Color("c5a16a"))
				draw_line(Vector2(x - 1, 8), Vector2(x + 1, 8), highlight, 1.0)

	func _draw_paper_edge(highlight: Color) -> void:
		var shade := Color("bca780")
		shade.a = 0.10 if subdued else 0.14
		draw_rect(Rect2(Vector2(3, 4), Vector2(3, size.y - 10)), shade)
		draw_rect(Rect2(Vector2(size.x - 6, 4), Vector2(3, size.y - 10)), shade)
		draw_rect(Rect2(Vector2(4, size.y - 6), Vector2(size.x - 8, 3)), Color("d7c9a8") if not subdued else Color("d2d2c4"))
		draw_line(Vector2(7, size.y - 4), Vector2(size.x - 7, size.y - 4), Color("fff4d7") if not subdued else Color("e1e0d2"), 1.0)
		var fiber_ink := Color("aa9270")
		fiber_ink.a = 0.12 if subdued else 0.18
		for fiber: int in 7:
			var y: float = floorf(16.0 + float(fiber) * (size.y - 40.0) / 7.0)
			var right_y: float = minf(size.y - 12.0, y + 5.0)
			draw_line(Vector2(3, y), Vector2(5, y + 1), fiber_ink, 1.0)
			draw_line(Vector2(size.x - 5, right_y), Vector2(size.x - 3, right_y - 1), fiber_ink, 1.0)
		for x: float in [6.0, size.x - 6.0]:
			draw_line(Vector2(x, 5), Vector2(x, 10), Color(highlight, highlight.a * 0.7), 1.0)

	func _draw_lock_frame(highlight: Color) -> void:
		var metal := Color("b78c45")
		var metal_shade := Color("7e643c")
		var inset := Rect2(Vector2(2, 2), size - Vector2(4, 7))
		draw_rect(inset, Color(metal, 0.68 if not subdued else 0.26), false, 1.0)
		for corner: Vector2 in [Vector2(4, 4), Vector2(size.x - 4, 4), Vector2(4, size.y - 7), Vector2(size.x - 4, size.y - 7)]:
			var direction := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
			draw_line(corner, corner + Vector2(direction.x * 11, 0), metal_shade, 2.0)
			draw_line(corner, corner + Vector2(0, direction.y * 11), metal, 2.0)
			var rivet: Vector2 = corner + direction * 2.0
			draw_rect(Rect2(rivet - Vector2.ONE, Vector2(3, 3)), metal_shade)
			draw_rect(Rect2(rivet - Vector2.ONE, Vector2(2, 1)), highlight)


static func apply(panel: PanelContainer, tint: Color, backpack: bool = false, locked: bool = false, sold: bool = false) -> void:
	var base := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if base == null:
		return
	base.bg_color = Color("eeecdf") if sold else Color("edf0de") if backpack else Color("fff7e3")
	base.border_color = Color("bc9650") if locked else Color("7d9b8c") if backpack else tint.lerp(Color("c5c3a7"), 0.65)
	base.set_border_width_all(1)
	base.border_width_bottom = 3
	base.set_corner_radius_all(2)
	base.anti_aliasing = false
	base.shadow_color = Color(0.13, 0.24, 0.26, 0.10 if sold else 0.18)
	base.shadow_size = 2
	base.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", base)
	var old_frame := panel.get_node_or_null("RitualFrame")
	if old_frame != null:
		panel.remove_child(old_frame)
		old_frame.queue_free()
	var finish := panel.get_node_or_null("ShopPanelFinish") as Finish
	if finish == null:
		finish = Finish.new()
		finish.name = "ShopPanelFinish"
		finish.mouse_filter = Control.MOUSE_FILTER_IGNORE
		finish.focus_mode = Control.FOCUS_NONE
		panel.add_child(finish)
		finish.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	finish.tint = Color("bc9650") if locked else tint
	finish.backpack = backpack
	finish.subdued = sold
	finish.locked = locked
	finish.queue_redraw()
