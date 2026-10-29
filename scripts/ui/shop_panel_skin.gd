class_name ShopPanelSkin
extends RefCounted
## Local shop surfaces. Decorations never participate in input or layout.

class Finish extends Control:
	var tint: Color
	var backpack: bool = false
	var subdued: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		set_process(false)
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 36.0 or size.y < 36.0:
			return
		var edge := Color(tint, 0.20 if subdued else 0.38)
		var highlight := Color("fffef2")
		highlight.a = 0.45 if subdued else 0.88
		draw_line(Vector2(8, 3), Vector2(size.x - 8, 3), highlight, 1.0)
		draw_line(Vector2(8, size.y - 7), Vector2(size.x - 8, size.y - 7), edge, 1.0)
		for corner: Vector2 in [Vector2(6, 6), Vector2(size.x - 6, 6), Vector2(6, size.y - 9), Vector2(size.x - 6, size.y - 9)]:
			var direction := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
			draw_line(corner, corner + Vector2(direction.x * 8, 0), edge, 1.0)
			draw_line(corner, corner + Vector2(0, direction.y * 8), edge, 1.0)
		if backpack:
			for x: float in [16.0, size.x - 16.0]:
				draw_rect(Rect2(Vector2(x - 2, 8), Vector2(4, 3)), Color("c5a16a"))
				draw_line(Vector2(x - 1, 8), Vector2(x + 1, 8), highlight, 1.0)


static func apply(panel: PanelContainer, tint: Color, backpack: bool = false, locked: bool = false, sold: bool = false) -> void:
	var base := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if base == null:
		return
	base.bg_color = Color("f0eee2") if sold else Color("edf0de") if backpack else Color("fff9e9")
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
	finish.queue_redraw()
