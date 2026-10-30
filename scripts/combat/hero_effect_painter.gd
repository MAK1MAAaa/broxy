class_name HeroEffectPainter
extends RefCounted
## Draw real traveling bombs and authoritative blast receipts without a second clock.

const INK := Color("243752")
const FIRE := Color("f1875e")
const CORE := Color("fff1cf")
const LIMIT: int = 20
const MAX_COMMANDS: int = LIMIT * 12

static func draw(canvas: CanvasItem, snapshot: Dictionary, flash: bool) -> void:
	for command: Dictionary in geometry_snapshot(snapshot, flash)["commands"]:
		match str(command["kind"]):
			"line":
				canvas.draw_line(command["from"], command["to"], command["color"], command["width"])
			"rect":
				canvas.draw_rect(command["rect"], command["color"])
			"arc":
				canvas.draw_arc(command["center"], command["radius"], 0, TAU, 32, command["color"], 2.0)

static func geometry_snapshot(snapshot: Dictionary, flash: bool) -> Dictionary:
	var commands: Array[Dictionary] = []
	var bounds: Array[Rect2] = []
	var bombs: Array = snapshot.get("bombs", [])
	for index: int in mini(LIMIT, bombs.size()):
		var bomb: Dictionary = bombs[index]
		var point: Vector2 = bomb["position"]
		var velocity: Vector2 = bomb["velocity"]
		var direction := velocity.normalized()
		bounds.append(Rect2(point - Vector2.ONE * 18, Vector2.ONE * 36))
		commands.append(_line(point - direction * 15.0, point - direction * 6.0, Color(FIRE, 0.5), 3.0))
		for layer: Array in [[6.0, INK], [4.0, FIRE], [2.0, CORE]]:
			var extent: float = layer[0]
			commands.append({"kind": "rect", "rect": Rect2(point - Vector2.ONE * extent, Vector2.ONE * extent * 2), "color": layer[1]})
		commands.append(_line(point + Vector2(3, -6), point + Vector2(6, -9), CORE, 2.0))
	var bursts: Array = snapshot.get("bursts", [])
	for index: int in mini(LIMIT, bursts.size()):
		var burst: Dictionary = bursts[index]
		var point: Vector2 = burst["position"]
		var radius: float = float(burst["radius"])
		var fraction: float = clampf(float(burst["life"]) / maxf(0.001, float(burst["total"])), 0, 1)
		bounds.append(Rect2(point - Vector2.ONE * (radius + 3), Vector2.ONE * (radius + 3) * 2))
		commands.append({"kind": "arc", "center": point, "radius": radius, "color": Color(FIRE, fraction * (0.8 if flash else 0.35))})
		if not flash:
			continue
		for ray: int in 6:
			var direction := Vector2.from_angle(float(ray) * TAU / 6.0)
			var along: float = radius * (1.0 - fraction * 0.55)
			commands.append(_line(point + direction * along * 0.65, point + direction * along, Color(CORE, fraction), 3.0))
	return {"commands": commands, "bounds": bounds, "bomb_count": mini(LIMIT, bombs.size()), "burst_count": mini(LIMIT, bursts.size())}

static func _line(from: Vector2, to: Vector2, color: Color, width: float) -> Dictionary:
	return {"kind": "line", "from": from, "to": to, "color": color, "width": width}
