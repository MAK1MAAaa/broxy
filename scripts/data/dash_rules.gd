class_name DashRules
extends RefCounted
## One fixed-step movement burst; terrain and permanent move-speed bonuses do not change it.

const DURATION: float = 0.20
const SPEED: float = 660.0
const COOLDOWN: float = 2.4
const MIN_COOLDOWN: float = 1.2
const INVULNERABILITY: float = 0.12

static func clamp_cooldown(value: float) -> float:
	return clampf(value, MIN_COOLDOWN, COOLDOWN) if is_finite(value) else COOLDOWN
