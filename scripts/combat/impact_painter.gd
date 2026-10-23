extends RefCounted
## Small neutral marks at enemy centers; they do not imply a contact direction.

const CAPACITY: int = 32
const LIFE: float = 0.12
const MERGE_WINDOW: float = 0.05
const STAGES: int = 3
const KINDS: Dictionary = {"bone": 0, "frost": 1, "ember": 2, "scatter": 3,
	"crescent": 0, "storm": 1, "comet": 3}
const COLORS: Array[Color] = [Color("decfad"), Color("9ec5dc"), Color("dec08b"), Color("bca4cf")]
const ALPHAS: Array[float] = [0.80, 0.52, 0.26]

class ImpactMark:
	var origin: Vector2 = Vector2.ZERO
	var kind: int = 0
	var source: String = ""
	var target_uid: int = -1
	var age: float = 0.0
	var life: float = 0.0

class LineBatch:
	var points: PackedVector2Array = PackedVector2Array()
	var color: Color = Color.WHITE
	var width: float = 1.5

var peak_active: int = 0
var _pool: Array[ImpactMark] = []
var _free: Array[ImpactMark] = []
var _marks: Array[ImpactMark] = []
var _batches: Array[LineBatch] = []
var _shapes: Array[PackedVector2Array] = []


func _init() -> void:
	# Author the tiny, direction-neutral segments once, independent of simulation RNG.
	_shapes = [
		PackedVector2Array([Vector2(-5, -4), Vector2(-2, 4), Vector2(2, -4), Vector2(5, 4)]),
		PackedVector2Array([Vector2(-6, -4), Vector2(-2, -4), Vector2(-4, -6), Vector2(-4, -2),
			Vector2(2, 4), Vector2(6, 4), Vector2(4, 2), Vector2(4, 6)]),
		PackedVector2Array([Vector2(-6, 3), Vector2(-3, -2), Vector2(-1, -5), Vector2(1, -2),
			Vector2(3, 1), Vector2(6, 4)]),
		PackedVector2Array([Vector2(0, -7), Vector2(6, 0), Vector2(6, 0), Vector2(0, 7),
			Vector2(0, 7), Vector2(-6, 0), Vector2(-6, 0), Vector2(0, -7)]),
	]
	for index: int in CAPACITY:
		_pool.append(ImpactMark.new())
	for kind: int in COLORS.size():
		for stage: int in STAGES:
			var batch := LineBatch.new()
			batch.color = Color(COLORS[kind], ALPHAS[stage])
			_batches.append(batch)
	clear()


func add_hit(point: Vector2, source: String, target_uid: int) -> void:
	if not point.is_finite() or not KINDS.has(source):
		return
	var kind: int = int(KINDS[source])
	if target_uid >= 0:
		for mark: ImpactMark in _marks:
			# Age is measured directly so a hit at exactly 0.05s starts a new mark;
			# an ignored hit never restarts the existing mark's lifetime.
			if mark.source == source and mark.target_uid == target_uid and mark.age < MERGE_WINDOW:
				return
	if _free.is_empty():
		return
	var mark: ImpactMark = _free.pop_back()
	mark.origin = point
	mark.kind = kind
	mark.source = source
	mark.target_uid = target_uid
	mark.age = 0.0
	mark.life = LIFE
	_marks.append(mark)
	peak_active = maxi(peak_active, _marks.size())


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for index: int in range(_marks.size() - 1, -1, -1):
		var mark: ImpactMark = _marks[index]
		mark.age += delta
		mark.life = maxf(0.0, LIFE - mark.age)
		if mark.life > 0.0:
			continue
		_marks.remove_at(index)
		_reset_mark(mark)
		_free.append(mark)


func clear() -> void:
	_marks.clear()
	_free.clear()
	for mark: ImpactMark in _pool:
		_reset_mark(mark)
		_free.append(mark)
	for batch: LineBatch in _batches:
		batch.points.clear()
	peak_active = 0


func rebuild(enabled: bool = true) -> void:
	if not enabled:
		clear()
		return
	for batch: LineBatch in _batches:
		batch.points.clear()
	for mark: ImpactMark in _marks:
		var stage: int = mini(STAGES - 1, int(mark.age / LIFE * STAGES))
		var batch: LineBatch = _batches[mark.kind * STAGES + stage]
		for offset: Vector2 in _shapes[mark.kind]:
			batch.points.append(mark.origin + offset)


func draw(canvas: CanvasItem) -> void:
	# At most one draw per weapon/fade stage; all geometry was prepared by rebuild.
	for batch: LineBatch in _batches:
		if not batch.points.is_empty():
			canvas.draw_multiline(batch.points, batch.color, batch.width, true)


func active_count() -> int:
	return _marks.size()


func get_stats() -> Dictionary:
	var commands: int = 0
	for batch: LineBatch in _batches:
		if not batch.points.is_empty():
			commands += 1
	return {"capacity": CAPACITY, "active_marks": _marks.size(), "free_marks": _free.size(),
		"allocated_marks": _pool.size(), "draw_commands": commands, "peak_active": peak_active}


static func _reset_mark(mark: ImpactMark) -> void:
	mark.origin = Vector2.ZERO
	mark.kind = 0
	mark.source = ""
	mark.target_uid = -1
	mark.age = 0.0
	mark.life = 0.0
