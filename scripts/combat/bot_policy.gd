class_name BotPolicy
extends RefCounted
## Orbit-and-avoid v1. A reproducible movement model, not a claim about human difficulty.

static func movement(sim: CombatSim) -> Vector2:
	var center: Vector2 = CombatSim.ARENA.get_center()
	var angle: float = sim.elapsed * 0.25
	var destination: Vector2 = center + Vector2(cos(angle) * 350.0, sin(angle) * 160.0)
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
		if not zone.triggered and zone.position.distance_to(sim.player_position) < zone.radius + 38.0:
			steering += (sim.player_position - zone.position).normalized() * 4.0
	var point: Vector2 = sim.player_position
	var safe: Rect2 = CombatSim.ARENA.grow(-45.0)
	steering.x += clampf((safe.position.x - point.x) / 30.0, 0.0, 3.0) - clampf((point.x - safe.end.x) / 30.0, 0.0, 3.0)
	steering.y += clampf((safe.position.y - point.y) / 30.0, 0.0, 3.0) - clampf((point.y - safe.end.y) / 30.0, 0.0, 3.0)
	return steering.limit_length()
