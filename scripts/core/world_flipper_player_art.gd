class_name WorldFlipperPlayerArt
extends RefCounted
## Pure pose queries for the source GIF's idle and two four-frame walk cycles.

const ATLAS_PATH: String = "res://assets/worldflipper/sprites/player-atlas.png"
const FRAME_SIZE: int = 96
const ATLAS_COLUMNS: int = 4
const LAST_FRAME: int = 8
const WALK_DURATION: float = 0.38
const FRAME_ENDS: Array[float] = [0.08, 0.18, 0.28, 0.38]


static func frame_index(motion: Vector2, time: float) -> int:
	if not motion.is_finite() or motion.is_zero_approx():
		return 0
	var start: int = 5 if motion.y < 0.0 else 1
	var phase: float = fposmod(maxf(time, 0.0), WALK_DURATION) if is_finite(time) else 0.0
	for offset: int in FRAME_ENDS.size():
		if phase < FRAME_ENDS[offset]:
			return start + offset
	return start + 3


static func flip_for(motion: Vector2) -> bool:
	return motion.is_finite() and not motion.is_zero_approx() and motion.y >= 0.0 and motion.x < 0.0


static func frame_rect(index: int) -> Rect2:
	var frame: int = clampi(index, 0, LAST_FRAME)
	var column: int = frame % ATLAS_COLUMNS
	var row: int = floori(float(frame) / float(ATLAS_COLUMNS))
	return Rect2(Vector2(column * FRAME_SIZE, row * FRAME_SIZE), Vector2.ONE * FRAME_SIZE)
