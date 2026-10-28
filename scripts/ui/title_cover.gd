class_name TitleCover
extends TextureRect
## A fixed 24-frame cosmetic loop shared by the live cover and GIF capture.

const BASE_PATH: String = "res://assets/title/cover.png"
const FRAME_COUNT: int = 24
const FRAME_SECONDS: float = 0.12
const REFERENCE_SIZE := Vector2(1280, 720)
const DRAW_COMMANDS_BUDGET: int = 83

class MotionLayer:
	extends Control
	const MOTES: Array[Vector2] = [
		Vector2(720, 190), Vector2(760, 400), Vector2(790, 285),
		Vector2(820, 470), Vector2(850, 610), Vector2(1080, 375),
		Vector2(1140, 445), Vector2(1180, 545), Vector2(1220, 340),
		Vector2(1210, 640), Vector2(980, 675), Vector2(1150, 90),
	]
	const FLAMES: Array[Vector2] = [
		Vector2(790, 482), Vector2(812, 486), Vector2(828, 474),
		Vector2(1265, 367), Vector2(1170, 653),
	]
	const RING_ANGLES: Array[float] = [-2.3, -0.5, 1.2]
	var frame_number: int = 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		set_process(false)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var cover := get_parent() as TextureRect
		if cover == null or cover.texture == null or size.x <= 0.0 or size.y <= 0.0:
			return
		var texture_extent: Vector2 = cover.texture.get_size()
		if texture_extent.x <= 0.0 or texture_extent.y <= 0.0:
			return
		var fit: float = maxf(size.x / texture_extent.x, size.y / texture_extent.y)
		var drawn_extent: Vector2 = texture_extent * fit
		draw_set_transform((size - drawn_extent) * 0.5, 0.0, drawn_extent / TitleCover.REFERENCE_SIZE)
		var phase: float = float(frame_number) * TAU / float(TitleCover.FRAME_COUNT)
		_draw_motes(phase)
		_draw_ring_lights(phase)
		_draw_flames(phase)
		_draw_ground_breath(phase)

	func _draw_motes(phase: float) -> void:
		for index: int in MOTES.size():
			var offset: float = float(index) * 0.73
			var drift := Vector2(sin(phase + offset) * (8.0 + float(index % 3) * 3.0), cos(phase + offset) * 11.0)
			var alpha: float = 0.36 + 0.12 * sin(phase + offset + 0.8)
			var color := Color("f9d585") if index % 3 else Color("8cded2")
			_draw_star(_pixel(MOTES[index] + drift), 2.0, Color(color, alpha))

	func _draw_ring_lights(phase: float) -> void:
		var center := Vector2(1103, 168)
		for index: int in 3:
			var resting_angle: float = RING_ANGLES[index]
			var angle: float = resting_angle + sin(phase + float(index) * 1.4) * 0.16
			var point := center + Vector2(cos(angle) * 145.0, sin(angle) * 141.0)
			var alpha: float = 0.48 + 0.10 * cos(phase + float(index) * 1.4)
			_draw_star(_pixel(point), 3.0, Color(Color("fff1b8"), alpha))

	func _draw_flames(phase: float) -> void:
		for index: int in FLAMES.size():
			var wave: float = sin(phase + float(index) * 1.1)
			var point: Vector2 = FLAMES[index] + Vector2(roundf(wave), roundf(cos(phase + float(index) * 1.1)))
			draw_rect(Rect2(point - Vector2(3, 5), Vector2(7, 9)), Color(1.0, 0.75, 0.33, 0.09 + wave * 0.025))
			draw_rect(Rect2(point - Vector2(1, 4), Vector2(3, 6)), Color(1.0, 0.78, 0.34, 0.35 + wave * 0.06))
			draw_rect(Rect2(point - Vector2(0, 2), Vector2(1, 3)), Color(1.0, 0.97, 0.75, 0.58 + wave * 0.06))

	func _draw_ground_breath(phase: float) -> void:
		var center := Vector2(995, 590)
		for index: int in 8:
			var angle: float = float(index) * TAU / 8.0
			var begin := center + Vector2(cos(angle) * 118.0, sin(angle) * 26.0)
			var end := center + Vector2(cos(angle + 0.13) * 118.0, sin(angle + 0.13) * 26.0)
			var alpha: float = 0.16 + 0.06 * sin(phase + float(index) * 0.4)
			draw_line(_pixel(begin), _pixel(end), Color(0.83, 0.98, 0.79, alpha), 2.0)

	func _draw_star(center: Vector2, radius: float, color: Color) -> void:
		draw_rect(Rect2(center - Vector2.ONE * (radius + 2.0), Vector2.ONE * (radius * 2.0 + 5.0)), Color(color, color.a * 0.12))
		draw_rect(Rect2(center - Vector2(radius, 0), Vector2(radius * 2.0 + 1.0, 1)), color)
		draw_rect(Rect2(center - Vector2(0, radius), Vector2(1, radius * 2.0 + 1.0)), color)
		draw_rect(Rect2(center, Vector2.ONE), Color(Color("fff7d8"), minf(0.8, color.a + 0.15)))

	func _pixel(point: Vector2) -> Vector2:
		return Vector2(roundf(point.x), roundf(point.y))

var _frame: int = 0
var _playing: bool = true
var _clock: Timer
var _motion: MotionLayer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	if texture == null and ResourceLoader.exists(BASE_PATH):
		texture = load(BASE_PATH) as Texture2D
	_motion = MotionLayer.new()
	_motion.name = "MotionLayer"
	_motion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion.focus_mode = Control.FOCUS_NONE
	add_child(_motion)
	_motion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_motion.frame_number = _frame
	_clock = Timer.new()
	_clock.name = "FrameClock"
	_clock.wait_time = FRAME_SECONDS
	_clock.one_shot = false
	_clock.timeout.connect(_advance_frame)
	add_child(_clock)
	visibility_changed.connect(_sync_playback)
	resized.connect(_redraw_motion)
	draw.connect(_redraw_motion)
	_sync_playback()

func set_frame(index: int) -> void:
	set_playing(false)
	_frame = posmod(index, FRAME_COUNT)
	_redraw_motion()

func set_playing(enabled: bool) -> void:
	_playing = enabled
	_sync_playback()

func snapshot() -> Dictionary:
	return {
		"frame": _frame, "frame_count": FRAME_COUNT, "frame_seconds": FRAME_SECONDS,
		"playing": _playing, "timer_active": is_instance_valid(_clock) and not _clock.is_stopped(),
		"visible": is_visible_in_tree(), "texture_size": texture.get_size() if texture != null else Vector2.ZERO,
		"rect": get_rect(), "overlay_rect": _motion.get_rect() if is_instance_valid(_motion) else Rect2(),
		"draw_commands_budget": DRAW_COMMANDS_BUDGET,
	}

func _advance_frame() -> void:
	_frame = (_frame + 1) % FRAME_COUNT
	_redraw_motion()

func _redraw_motion() -> void:
	if is_instance_valid(_motion):
		_motion.frame_number = _frame
		_motion.queue_redraw()

func _sync_playback() -> void:
	if not is_instance_valid(_clock):
		return
	if _playing and is_visible_in_tree():
		_clock.start()
	else:
		_clock.stop()

func _exit_tree() -> void:
	if is_instance_valid(_clock):
		_clock.stop()
