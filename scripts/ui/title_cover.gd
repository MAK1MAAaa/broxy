class_name TitleCover
extends TextureRect
## A fixed 24-frame cosmetic loop shared by the live cover and GIF capture.

const BASE_PATH: String = "res://assets/worldflipper/title/cover.png"
const GIF_PATH: String = "res://assets/worldflipper/title/cover.gif"
const METADATA_PATH: String = "res://assets/worldflipper/title/animation.json"
const DEFAULT_CHARACTER_ID: String = "alk"
const DEFAULT_PORTRAIT_PATH: String = "res://assets/worldflipper/portraits/alk.png"
const PORTRAIT_SLOT := Rect2(660, 16, 600, 688)
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
		Vector2(1210, 640), Vector2(980, 675),
	]
	const LIGHT_POINTS: Array[Vector2] = [
		Vector2(760, 150), Vector2(1195, 210), Vector2(1220, 560),
		Vector2(750, 590), Vector2(1090, 80),
	]
	const BRIGHT_STARS: Array[Vector2] = [Vector2(700, 75), Vector2(1240, 410), Vector2(800, 670)]
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
		_draw_bright_stars(phase)
		_draw_light_points(phase)
		_draw_light_tracks(phase)

	func _draw_motes(phase: float) -> void:
		for index: int in MOTES.size():
			var offset: float = float(index) * 0.73
			var drift := Vector2(sin(phase + offset) * (8.0 + float(index % 3) * 3.0), cos(phase + offset) * 11.0)
			var alpha: float = 0.36 + 0.12 * sin(phase + offset + 0.8)
			var color := Color("f9d585") if index % 3 else Color("8cded2")
			_draw_star(_pixel(MOTES[index] + drift), 2.0, Color(color, alpha))

	func _draw_bright_stars(phase: float) -> void:
		for index: int in BRIGHT_STARS.size():
			var offset: float = phase + float(index) * 1.4
			var point := BRIGHT_STARS[index] + Vector2(sin(offset) * 8.0, cos(offset) * 6.0)
			var alpha: float = 0.48 + 0.10 * cos(offset)
			_draw_star(_pixel(point), 3.0, Color(Color("69bdc3"), alpha))

	func _draw_light_points(phase: float) -> void:
		for index: int in LIGHT_POINTS.size():
			var wave: float = sin(phase + float(index) * 1.1)
			var point: Vector2 = _pixel(LIGHT_POINTS[index] + Vector2(wave * 8.0, cos(phase + float(index) * 1.1) * 9.0))
			draw_rect(Rect2(point - Vector2(3, 3), Vector2(7, 7)), Color(0.45, 0.72, 0.83, 0.09 + wave * 0.025))
			draw_rect(Rect2(point - Vector2.ONE, Vector2(3, 3)), Color(0.94, 0.78, 0.36, 0.35 + wave * 0.06))
			draw_rect(Rect2(point, Vector2.ONE), Color(1.0, 0.97, 0.75, 0.58 + wave * 0.06))

	func _draw_light_tracks(phase: float) -> void:
		for index: int in 8:
			var drift := Vector2(sin(phase + float(index) * 0.4) * 9.0, cos(phase + float(index) * 0.4) * 5.0)
			var begin := Vector2(700.0 + float(index % 4) * 170.0, 250.0 + float(index / 4) * 320.0) + drift
			var end := begin + Vector2(5.0, -6.0)
			var alpha: float = 0.16 + 0.06 * sin(phase + float(index) * 0.4)
			draw_line(_pixel(begin), _pixel(end), Color(0.32, 0.66, 0.73, alpha), 2.0)

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
var _portrait: TextureRect
var _portrait_id: String = DEFAULT_CHARACTER_ID
var _portrait_path: String = DEFAULT_PORTRAIT_PATH
var _portrait_texture: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true
	if texture == null and ResourceLoader.exists(BASE_PATH):
		texture = load(BASE_PATH) as Texture2D
	_portrait = TextureRect.new()
	_portrait.name = "PortraitLayer"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.focus_mode = Control.FOCUS_NONE
	_portrait.set_process(false)
	add_child(_portrait)
	set_character(_portrait_id, _portrait_path)
	resized.connect(_layout_portrait)
	_layout_portrait()
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

func set_character(id: String, portrait_path: String) -> void:
	var candidate: Texture2D
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path, "Texture2D"):
		candidate = load(portrait_path) as Texture2D
	if candidate == null:
		_portrait_id = DEFAULT_CHARACTER_ID
		_portrait_path = DEFAULT_PORTRAIT_PATH
		_portrait_texture = load(DEFAULT_PORTRAIT_PATH) as Texture2D if ResourceLoader.exists(DEFAULT_PORTRAIT_PATH, "Texture2D") else null
	else:
		_portrait_id = id.strip_edges() if not id.strip_edges().is_empty() else DEFAULT_CHARACTER_ID
		_portrait_path = portrait_path
		_portrait_texture = candidate
	if is_instance_valid(_portrait):
		_portrait.texture = _portrait_texture

func _layout_portrait() -> void:
	if not is_instance_valid(_portrait):
		return
	var ratio: Vector2 = size / REFERENCE_SIZE
	_portrait.position = PORTRAIT_SLOT.position * ratio
	_portrait.size = PORTRAIT_SLOT.size * ratio

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
		"portrait_id": _portrait_id, "portrait_path": _portrait_path,
		"portrait_rect": _portrait.get_rect() if is_instance_valid(_portrait) else Rect2(),
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
