class_name RuneRules
extends RefCounted
## Shared numeric behavior for the real projectile dispatcher and equipment forecasts.

const EXTRA_HITS: int = 2
const BOUNCE_RANGE: float = 230.0
const BOUNCE_DAMAGE_FACTOR: float = 0.75
const BLAST_RADIUS: float = 68.0
const BLAST_DAMAGE_FACTOR: float = 0.55

static func extra_hits(rank: int = 1) -> int:
	return EXTRA_HITS + clampi(rank, 1, 3) - 1

static func blast_radius(rank: int = 1) -> float:
	return BLAST_RADIUS + float(clampi(rank, 1, 3) - 1) * 10.0

static func blast_factor(rank: int = 1) -> float:
	return BLAST_DAMAGE_FACTOR + float(clampi(rank, 1, 3) - 1) * 0.10
