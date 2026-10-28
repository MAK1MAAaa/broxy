class_name PulseRules
extends RefCounted
## A radial control skill with no damage, frost status or resource reward.

const RADIUS: float = 144.0
const PUSH_DISTANCE: float = 70.0
const HINDER_FACTOR: float = 0.65
const HINDER_SECONDS: float = 1.0
const COOLDOWN: float = 8.0
const MAX_RADIUS: float = 216.0
const MAX_COOLDOWN: float = 16.0

static func clamp_radius(value: float) -> float:
	return clampf(value, RADIUS, MAX_RADIUS) if is_finite(value) else RADIUS

static func clamp_cooldown(value: float) -> float:
	return clampf(value, COOLDOWN, MAX_COOLDOWN) if is_finite(value) else COOLDOWN
