class_name BossArtPainter
extends RefCounted
## Small state ornaments follow authoritative boss clocks without changing gameplay.

const MAX_DIAMONDS: int = 6
const MAX_LINE_SEGMENTS: int = 8
const MAX_DRAW_COMMANDS: int = 14
const CHARGE_COLOR: Color = Color("a8e5e1")
const CHARGE_INK: Color = Color("244459")
const BREAK_COLOR: Color = Color("f6d37f")
const BREAK_INK: Color = Color("75502e")
const CHARGE_START: Array[Vector2] = [Vector2(-64, -44), Vector2(-64, 12), Vector2(-24, -60), Vector2(24, -60), Vector2(64, 12), Vector2(64, -44)]
const CHARGE_END: Array[Vector2] = [Vector2(-54, -40), Vector2(-54, 10), Vector2(-20, -52), Vector2(20, -52), Vector2(54, 10), Vector2(54, -40)]
const BREAK_FRAGMENTS: Array[Vector2] = [Vector2(-64, -76), Vector2(-66, -6), Vector2(64, -76), Vector2(66, -6)]

static func draw(canvas: CanvasItem, position: Vector2, encounter: Dictionary, visual_time: float, animated: bool) -> void:
	if canvas == null:
		return
	var geometry: Dictionary = geometry_snapshot(position, encounter, visual_time, animated)
	if geometry.is_empty():
		return
	for diamond: Dictionary in geometry["diamonds"]:
		canvas.draw_colored_polygon(diamond["outline"], diamond["outline_color"])
		canvas.draw_colored_polygon(diamond["fill"], diamond["color"])
	var lines: PackedVector2Array = geometry["lines"]
	if not lines.is_empty():
		canvas.draw_multiline(lines, geometry["line_outline_color"], 3.0, false)
		canvas.draw_multiline(lines, geometry["line_color"], 1.0, false)

static func geometry_snapshot(position: Vector2, encounter: Dictionary, visual_time: float, animated: bool) -> Dictionary:
	if not position.is_finite() or not is_finite(visual_time) or encounter.get("active", true) != true or encounter.get("running", true) != true:
		return {}
	var phase: String = str(encounter.get("phase", ""))
	var diamonds: Array[Dictionary] = []
	var lines := PackedVector2Array()
	var progress: float = 0.0
	var fade: float = 1.0
	var ink: Color
	var color: Color
	if phase == "charge":
		var total: float = _number(encounter.get("charge_total"))
		var left: float = _number(encounter.get("charge_left"))
		if total <= 0.0 or left < 0.0:
			return {}
		progress = 1.0 - clampf(left, 0.0, total) / total
		ink = CHARGE_INK
		color = CHARGE_COLOR
		var anchor: Vector2 = position + Vector2(0, -30)
		for index: int in CHARGE_START.size():
			var contraction: float = progress if animated else 0.5
			var center: Vector2 = (anchor + CHARGE_START[index].lerp(CHARGE_END[index], contraction)).round()
			var opacity: float = 0.82
			if animated:
				opacity += sin(fposmod(visual_time, TAU) * 8.0 + float(index) * 1.17) * 0.10
			diamonds.append(_diamond(center, Color(color, opacity), Color(ink, 0.94)))
			if animated and index % 2 == 0:
				var outward: Vector2 = (center - anchor).normalized()
				lines.append((center + outward * 5.0).round())
				lines.append((center + outward * 9.0).round())
	elif phase == "break":
		var left: float = _number(encounter.get("break_left"))
		if left <= 0.0:
			return {}
		fade = clampf(left / BossEncounter.BREAK_SECONDS, 0.0, 1.0)
		progress = 1.0 - fade
		ink = BREAK_INK
		color = BREAK_COLOR
		for offset: Vector2 in BREAK_FRAGMENTS:
			var separation: float = progress * 4.0 if animated else 0.0
			var center: Vector2 = (position + offset + Vector2(signf(offset.x) * separation, 0)).round()
			diamonds.append(_diamond(center, Color(color, fade * 0.9), Color(ink, fade * 0.94)))
		for side: float in [-1.0, 1.0]:
			for bottom: bool in [false, true]:
				var corner: Vector2 = (position + Vector2(side * 58.0, 24.0 if bottom else -94.0)).round()
				lines.append(corner + Vector2(-side * 10.0, 0))
				lines.append(corner)
				lines.append(corner)
				lines.append(corner + Vector2(0, -9.0 if bottom else 9.0))
	else:
		return {}
	var points := PackedVector2Array()
	for diamond: Dictionary in diamonds:
		points.append_array(diamond["outline"])
	points.append_array(lines)
	var bounds: Rect2 = Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	bounds = bounds.grow(2.0)
	return {"state": phase, "diamonds": diamonds, "lines": lines, "bounds": bounds,
		"progress": progress, "fade": fade, "line_color": Color(color, fade * 0.75),
		"line_outline_color": Color(ink, fade * 0.9),
		"draw_commands": diamonds.size() * 2 + (2 if not lines.is_empty() else 0)}

static func _diamond(center: Vector2, color: Color, outline_color: Color) -> Dictionary:
	return {"center": center, "color": color, "outline_color": outline_color,
		"outline": PackedVector2Array([center + Vector2(0, -5), center + Vector2(4, 0), center + Vector2(0, 5), center + Vector2(-4, 0)]),
		"fill": PackedVector2Array([center + Vector2(0, -3), center + Vector2(2, 0), center + Vector2(0, 3), center + Vector2(-2, 0)])}

static func _number(value: Variant) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else -1.0
