class_name ShopWorkbenchArt
extends RefCounted
## Static, input-transparent surfaces for the altar trading workbench.

const BRASS := Color("bf9b61")
const CREAM := Color("fff1d1")
const INK := Color("142b34")


class PassiveLayer extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		set_process(false)

	func _ready() -> void:
		resized.connect(queue_redraw)


class Backdrop extends PassiveLayer:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), ShopWorkbenchArt.INK)
		if size.x < 64.0 or size.y < 64.0:
			return
		var inside := Rect2(Vector2(10, 10), size - Vector2(20, 20))
		draw_rect(inside, Color("213c43"))
		draw_rect(inside.grow(-2), Color("29464a"), false, 1.0)
		for y: float in [18.0, size.y - 19.0]:
			draw_line(Vector2(30, y), Vector2(size.x - 30, y), Color("6f806b"), 1.0)
		for corner: Vector2 in [Vector2(16, 16), Vector2(size.x - 16, 16), Vector2(16, size.y - 16), size - Vector2(16, 16)]:
			var direction := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
			draw_line(corner, corner + Vector2(direction.x * 18, 0), ShopWorkbenchArt.BRASS, 2.0)
			draw_line(corner, corner + Vector2(0, direction.y * 18), ShopWorkbenchArt.BRASS, 2.0)
			draw_rect(Rect2(corner + direction * 4 - Vector2.ONE, Vector2(2, 2)), ShopWorkbenchArt.CREAM)


class SurfaceFinish extends PassiveLayer:
	var role: String = "bag"

	func _draw() -> void:
		if size.x < 28.0 or size.y < 28.0:
			return
		var pale: bool = role == "inspect"
		var edge := Color("a3916d") if pale else Color("b59a68")
		var shade := Color("d0c4a6") if pale else Color("172c2d")
		var light := Color("fff8e5") if pale else Color("779080")
		draw_line(Vector2(7, 3), Vector2(size.x - 7, 3), light, 1.0)
		draw_line(Vector2(7, size.y - 4), Vector2(size.x - 7, size.y - 4), shade, 2.0)
		if role in ["header", "footer"]:
			_draw_corner_hardware(edge, light, 5.0, 7.0)
			return
		if role == "shelf":
			_draw_corner_hardware(edge, Color("edcf92"), 5.0, 11.0)
			for x: float in [7.0, size.x - 8.0]:
				draw_line(Vector2(x, 24), Vector2(x, size.y - 24), Color("2e302b"), 2.0)
		elif role == "bag":
			_draw_corner_hardware(edge, Color("ead3a3"), 5.0, 12.0)
			for x: float in [10.0, size.x - 11.0]:
				for stitch: int in mini(64, maxi(0, int((size.y - 48.0) / 14.0))):
					var y: float = 24.0 + float(stitch) * 14.0
					draw_line(Vector2(x, y), Vector2(x, y + 4), Color("718775"), 1.0)
		else:
			_draw_corner_hardware(edge, light, 5.0, 6.0)

	func _draw_corner_hardware(edge: Color, light: Color, inset: float, length: float) -> void:
		for corner: Vector2 in [Vector2(inset, inset), Vector2(size.x - inset, inset), Vector2(inset, size.y - inset), size - Vector2.ONE * inset]:
			var direction := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
			draw_line(corner, corner + Vector2(direction.x * length, 0), edge, 2.0)
			draw_line(corner, corner + Vector2(0, direction.y * length), edge, 2.0)
			var rivet: Vector2 = (corner + direction * 3).floor()
			draw_rect(Rect2(rivet - Vector2.ONE, Vector2(3, 3)), Color("746346"))
			draw_rect(Rect2(rivet - Vector2.ONE, Vector2(2, 1)), light)


class Footprint extends PassiveLayer:
	var dimensions := Vector2i.ONE
	var tint := Color("526c65")

	func _draw() -> void:
		var columns: int = clampi(dimensions.x, 1, 4)
		var rows: int = clampi(dimensions.y, 1, 4)
		var cell: float = floorf(minf((size.x - 2.0) / float(columns), (size.y - 2.0) / float(rows)))
		cell = minf(cell, 7.0)
		if cell < 2.0:
			return
		var origin: Vector2 = ((size - Vector2(columns, rows) * cell) * 0.5).floor()
		for y: int in rows:
			for x: int in columns:
				var rect := Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * (cell - 1.0))
				draw_rect(rect, Color(tint, 0.14))
				draw_rect(rect, Color(tint, 0.78), false, 1.0)


static func apply_surface(panel: PanelContainer, role: String) -> void:
	role = role if role in ["shelf", "bag", "inspect", "header", "footer"] else "bag"
	var surface := StyleBoxFlat.new()
	surface.bg_color = {"shelf": Color("4c4235"), "bag": Color("2f4b41"), "inspect": Color("f5edd8"), "header": Color("203b45"), "footer": Color("203b45")}[role]
	surface.border_color = Color("b29c6b") if role in ["shelf", "inspect"] else Color("80947a")
	surface.set_border_width_all(2)
	surface.border_width_bottom = 4
	surface.set_corner_radius_all(2)
	surface.anti_aliasing = false
	surface.shadow_size = 3
	surface.shadow_offset = Vector2(0, 3)
	surface.shadow_color = Color(0.04, 0.09, 0.12, 0.35)
	surface.content_margin_left = 0
	surface.content_margin_right = 0
	surface.content_margin_top = 0
	surface.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", surface)
	for previous_name: String in ["RitualFrame", "ShopPanelFinish"]:
		var previous := panel.get_node_or_null(previous_name)
		if previous != null:
			panel.remove_child(previous)
			previous.queue_free()
	var finish := panel.get_node_or_null("WorkbenchSurfaceFinish") as SurfaceFinish
	if finish == null:
		finish = SurfaceFinish.new()
		finish.name = "WorkbenchSurfaceFinish"
		panel.add_child(finish)
		finish.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	finish.role = role
	finish.queue_redraw()


static func make_backdrop() -> Control:
	var backdrop := Backdrop.new()
	backdrop.name = "ShopWorkbenchBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return backdrop


static func make_footprint(dimensions: Vector2i, tint: Color) -> Control:
	var footprint := Footprint.new()
	footprint.name = "ItemFootprint"
	footprint.dimensions = dimensions
	footprint.tint = tint
	footprint.custom_minimum_size = Vector2(34, 28)
	footprint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return footprint
