class_name BotPolicy
extends RefCounted
## Orbit-and-avoid v2 with boss weakpoint targeting. A reproducible movement model, not a claim about human difficulty.

static func movement(sim: CombatSim) -> Vector2:
	var center: Vector2 = CombatSim.ARENA.get_center()
	var angle: float = sim.elapsed * 0.25
	var destination: Vector2 = center + Vector2(cos(angle) * 350.0, sin(angle) * 160.0)
	var weakpoints: Array[Dictionary] = sim.boss_weakpoints()
	var chosen_weakpoint: Dictionary = {}
	var best: float = INF
	for weakpoint: Dictionary in weakpoints:
		var weakpoint_distance: float = sim.player_position.distance_squared_to(weakpoint["position"])
		if weakpoint_distance < best:
			best = weakpoint_distance
			chosen_weakpoint = weakpoint
	if not chosen_weakpoint.is_empty():
		var boss_offset: Vector2 = sim.player_position - (chosen_weakpoint["position"] as Vector2)
		destination = chosen_weakpoint["position"] + (boss_offset.normalized() if not boss_offset.is_zero_approx() else Vector2.DOWN) * 90.0
	var steering: Vector2 = (destination - sim.player_position).normalized()
	for enemy: CombatSim.Enemy in sim.enemies:
		if not enemy.active:
			continue
		var away: Vector2 = sim.player_position - enemy.position
		var distance: float = maxf(1.0, away.length())
		var safe: float = 100.0 + enemy.radius
		if distance < safe:
			steering += away / distance * pow((safe - distance) / safe, 2.0) * 4.5
	for shot: CombatSim.Shot in sim.shots:
		if not shot.active or not shot.hostile:
			continue
		var closest: Vector2 = shot.position + shot.velocity * 0.22
		var away: Vector2 = sim.player_position - closest
		if away.length_squared() < 80.0 * 80.0:
			steering += away.normalized() * 2.0
	for zone: CombatSim.WarningZone in sim.zones:
		if zone.source_cast_id > 0 and zone.age <= zone.delay + zone.duration:
			steering += _avoid_shape({"shape": zone.shape, "position": zone.position, "direction": zone.direction,
				"length": zone.length, "width": zone.width, "radius": zone.radius}, sim.player_position)
		elif not zone.triggered and zone.position.distance_to(sim.player_position) < zone.radius + 38.0:
			steering += (sim.player_position - zone.position).normalized() * 4.0
	if sim.boss != null:
		for shape: Dictionary in sim.boss_encounter.telegraph_snapshot():
			steering += _avoid_shape(shape, sim.player_position)
	var point: Vector2 = sim.player_position
	var safe: Rect2 = CombatSim.ARENA.grow(-45.0)
	steering.x += clampf((safe.position.x - point.x) / 30.0, 0.0, 3.0) - clampf((point.x - safe.end.x) / 30.0, 0.0, 3.0)
	steering.y += clampf((safe.position.y - point.y) / 30.0, 0.0, 3.0) - clampf((point.y - safe.end.y) / 30.0, 0.0, 3.0)
	return steering.limit_length()

static func _avoid_shape(shape: Dictionary, player: Vector2) -> Vector2:
	var origin: Vector2 = shape["position"]
	var away: Vector2 = player - origin
	if shape["shape"] == "lane":
		var direction: Vector2 = (shape["direction"] as Vector2).normalized()
		var across: float = away.dot(direction.orthogonal())
		if away.dot(direction) >= -38.0 and away.dot(direction) <= float(shape["length"]) + 38.0 and absf(across) < float(shape["width"]) * 0.5 + 38.0:
			return direction.orthogonal() * (4.0 if across >= 0.0 else -4.0)
	elif away.length() < float(shape["radius"]) + 38.0:
		return (away.normalized() if not away.is_zero_approx() else Vector2.DOWN) * 4.0
	return Vector2.ZERO
