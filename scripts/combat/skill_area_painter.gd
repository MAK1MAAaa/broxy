class_name SkillAreaPainter
extends RefCounted
## Skill tell and impact geometry consume the authoritative area's clock.

const LIMIT: int = SkillTimelineRuntime.LIMIT
const MAX_COMMANDS: int = LIMIT * 10
const FIRE := Color("f1875e")
const WIND := Color("87d9ab")
const AMBER := Color("efa54c")
const CORE := Color("fff1cf")

static func draw(canvas: CanvasItem, snapshot: Dictionary, flash: bool) -> void:
	for command: Dictionary in geometry_snapshot(snapshot, flash)["commands"]:
		match str(command["kind"]):
			"arc": canvas.draw_arc(command["center"], command["radius"], command["start"], command["end"], 28, command["color"], command["width"])
			"line": canvas.draw_line(command["from"], command["to"], command["color"], command["width"])
			"polygon": canvas.draw_colored_polygon(command["points"], command["color"])

static func geometry_snapshot(snapshot: Dictionary, flash: bool) -> Dictionary:
	var commands: Array[Dictionary] = []
	var bounds: Array[Rect2] = []
	var source: Array = snapshot.get("areas", [])
	for index: int in mini(LIMIT, source.size()):
		var area: Dictionary = source[index]
		if area.get("purpose", "damage") != "damage" or bool(area.get("held", false)):
			continue
		var parameters: Dictionary = area["parameters"]
		var origin: Vector2 = area["origin"]
		var direction: Vector2 = area["direction"]
		var warming: bool = not bool(area["active"])
		var time: float = maxf(0.0, float(area["age"]) - float(area["delay"]))
		var fade: float = 1.0 - clampf(time / float(area["duration"]), 0.0, 1.0)
		var color: Color = WIND if parameters.get("element", "") == "wind" else AMBER if parameters.get("visual_family", "") == "alchemy" else FIRE
		var alpha: float = 0.35 if warming else 0.3 + fade * 0.5
		if not flash:
			alpha = 0.25 if warming else 0.35
		if parameters.get("shape", "circle") == "rectangle":
			var along: Vector2 = direction * float(parameters["half_length"])
			var side: Vector2 = direction.orthogonal() * float(parameters["width"]) * 0.5
			var points := PackedVector2Array([origin - along - side, origin + along - side, origin + along + side, origin - along + side])
			var low: Vector2 = points[0]
			var high: Vector2 = points[0]
			for point: Vector2 in points:
				low = low.min(point)
				high = high.max(point)
			bounds.append(Rect2(low, high - low).grow(3.0))
			for edge: int in 4:
				commands.append(_line(points[edge], points[(edge + 1) % 4], Color(color, alpha * 0.65), 1.0))
			if not warming and flash:
				for sign: float in [-1.0, 1.0]:
					var tip: Vector2 = origin + along * sign
					commands.append({"kind": "polygon", "points": PackedVector2Array([origin - side * 0.55, tip, origin + side * 0.55]), "color": Color(color, fade * 0.7)})
					commands.append(_line(origin, tip, Color(CORE, fade * 0.8), 2.0))
		else:
			var radius: float = float(parameters["radius"])
			bounds.append(Rect2(origin - Vector2.ONE * (radius + 3), Vector2.ONE * (radius + 3) * 2))
			commands.append(_arc(origin, radius, 0.0, TAU, Color(color, alpha * 0.5), 1.0))
			if warming and flash:
				var progress: float = clampf(float(area["age"]) / maxf(0.001, float(area["delay"])), 0.0, 1.0)
				for segment: int in 3:
					var start: float = float(segment) * TAU / 3.0
					commands.append(_arc(origin, radius * 0.92, start, start + TAU / 3.0 * progress, Color(color, alpha), 2.0))
			elif flash:
				var pulse: float = fposmod(time, float(area["interval"])) / float(area["interval"])
				commands.append(_arc(origin, radius * (0.76 + pulse * 0.2), 0.0, TAU, Color(color, alpha), 2.0))
				for ray: int in 6:
					var heading := Vector2.from_angle(float(ray) * TAU / 6.0)
					commands.append(_line(origin + heading * radius * (0.15 + pulse * 0.3), origin + heading * radius * (0.25 + pulse * 0.3), Color(CORE, fade * 0.7), 2.0))
	return {"commands": commands, "bounds": bounds}

static func _arc(center: Vector2, radius: float, start: float, end: float, color: Color, width: float) -> Dictionary:
	return {"kind": "arc", "center": center, "radius": radius, "start": start, "end": end, "color": color, "width": width}

static func _line(from: Vector2, to: Vector2, color: Color, width: float) -> Dictionary:
	return {"kind": "line", "from": from, "to": to, "color": color, "width": width}
