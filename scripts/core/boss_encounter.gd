class_name BossEncounter
extends RefCounted
## Pure boss timing and frozen attack geometry; collision placement belongs to CombatSim.

const MAX_WEAKPOINTS: int = 3
const MAX_EVENTS_PER_CALL: int = 8
const OPENING_SECONDS: float = 1.8
const RECOVERY_SECONDS: float = 1.4
const AFTER_BREAK_RECOVERY_SECONDS: float = 0.85
const BREAK_SECONDS: float = 1.5
const BREAK_DAMAGE_MULTIPLIER: float = 1.35
const WEAKPOINT_RADIUS: float = 13.0
const ATTACK_NAMES: Dictionary = {
	"forest_storm": "翠岚协奏",
	"root_corridor": "荆棘回廊",
	"spirit_chorus": "林灵合唱",
}
const CHARGE_SECONDS: Dictionary = {
	"forest_storm": 2.5,
	"root_corridor": 2.2,
	"spirit_chorus": 2.3,
}
const PHASE_ONE_SEQUENCE: Array[String] = ["forest_storm", "root_corridor", "spirit_chorus"]
const PHASE_TWO_SEQUENCE: Array[String] = ["root_corridor", "forest_storm", "spirit_chorus", "forest_storm"]

var _bounds: Rect2 = ArenaCatalog.WORLD_BOUNDS
var _running: bool = false
var _phase: String = "stopped"
var _phase_left: float = 0.0
var _phase2: bool = false
var _cast_phase2: bool = false
var _sequence_cursor: int = 0
var _cast_id: int = 0
var _next_weakpoint_uid: int = 1
var _attack_id: String = ""
var _charge_total: float = 0.0
var _release_pending: bool = false
var _weakpoints_relocated: bool = false
var _weakpoints_damaged: bool = false
var _boss_position: Vector2 = Vector2.ZERO
var _cast_position: Vector2 = Vector2.ZERO
var _weakpoint_anchor: Vector2 = Vector2.ZERO
var _locked_target: Vector2 = Vector2.ZERO
var _pattern_center: Vector2 = Vector2.ZERO
var _geometry: Array[Dictionary] = []
var _safe_channels: Array[Dictionary] = []
var _weakpoints: Array[Dictionary] = []
var _pending_events: Array[Dictionary] = []


func begin(position: Vector2, health_ratio: float, arena_bounds: Rect2 = ArenaCatalog.WORLD_BOUNDS) -> void:
	stop()
	if not position.is_finite() or not is_finite(health_ratio) or health_ratio <= 0.0:
		return
	if not arena_bounds.position.is_finite() or not arena_bounds.size.is_finite() or not arena_bounds.end.is_finite() or arena_bounds.size.x < 1000.0 or arena_bounds.size.y < 1000.0:
		return
	_bounds = arena_bounds
	_running = true
	_phase = "recovery"
	_phase_left = OPENING_SECONDS
	_phase2 = health_ratio <= 0.5
	_cast_phase2 = _phase2
	_sequence_cursor = 0
	_cast_id = 0
	_next_weakpoint_uid = 1
	_boss_position = position
	_cast_position = position
	_weakpoint_anchor = position
	_locked_target = position
	_pattern_center = position


func stop() -> void:
	_running = false
	_phase = "stopped"
	_phase_left = 0.0
	_phase2 = false
	_cast_phase2 = false
	_sequence_cursor = 0
	_cast_id = 0
	_next_weakpoint_uid = 1
	_attack_id = ""
	_charge_total = 0.0
	_release_pending = false
	_weakpoints_relocated = false
	_weakpoints_damaged = false
	_geometry.clear()
	_safe_channels.clear()
	_weakpoints.clear()
	_pending_events.clear()
	_boss_position = Vector2.ZERO
	_cast_position = Vector2.ZERO
	_weakpoint_anchor = Vector2.ZERO
	_locked_target = Vector2.ZERO
	_pattern_center = Vector2.ZERO


func advance(delta: float, boss_position: Vector2, player_position: Vector2, health_ratio: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not _running or not is_finite(delta) or delta <= 0.0:
		return events
	if not boss_position.is_finite() or not player_position.is_finite() or not is_finite(health_ratio):
		return events
	if health_ratio <= 0.0:
		stop()
		return events
	_boss_position = boss_position
	if health_ratio <= 0.5 and not _phase2:
		_phase2 = true
		_sequence_cursor = 0
	var remaining: float = delta
	# At most break -> recovery -> charge; release always waits for the friendly phase.
	for _transition: int in 3:
		if _phase == "charge":
			_phase_left = _timer_after(_phase_left, remaining)
			_release_pending = _phase_left <= 0.0
			return events
		var consumed: float = minf(remaining, _phase_left)
		_phase_left = _timer_after(_phase_left, consumed)
		remaining = maxf(0.0, remaining - consumed)
		if _phase_left > 0.0:
			return events
		if _phase == "break":
			events.append(_event("break_ended"))
			_phase = "recovery"
			_phase_left = AFTER_BREAK_RECOVERY_SECONDS
		elif _phase == "recovery":
			_start_cast(player_position)
			events.append(_event("telegraph", {
				"duration": _charge_total,
				"geometry": _geometry.duplicate(true),
				"safe_channels": _safe_channels.duplicate(true),
				"locked_target": _locked_target,
			}))
		else:
			return events
		if remaining <= 0.0:
			return events
	return events


func finish_friendly_step() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	events.assign(_pending_events.duplicate(true))
	_pending_events.clear()
	if not _running or _phase != "charge" or not _release_pending:
		return events
	_release_pending = false
	# These records become independent historical zones/minions once dispatched.
	# A future interrupt cannot cancel any previously published record.
	if _attack_id == "spirit_chorus":
		events.append(_event("summon", _summon_pattern()))
	else:
		for shape: Dictionary in _geometry:
			events.append(_event("root_lane" if shape["shape"] == "lane" else "attack", shape))
	events.append(_event("cast_released"))
	_phase = "recovery"
	_phase_left = RECOVERY_SECONDS
	_weakpoints.clear()
	_geometry.clear()
	_safe_channels.clear()
	assert(events.size() <= MAX_EVENTS_PER_CALL)
	return events


func weakpoints_snapshot() -> Array[Dictionary]:
	return _weakpoints.duplicate(true)


func telegraph_snapshot() -> Array[Dictionary]:
	var geometry: Array[Dictionary] = []
	if _phase == "charge":
		geometry.assign(_geometry.duplicate(true))
	return geometry


## Caller resolves obstacles first; every valid position is committed together once.
func relocate_weakpoints(cast_id: int, positions_by_uid: Dictionary) -> bool:
	if not _running or _phase != "charge" or cast_id != _cast_id or _weakpoints_relocated or _weakpoints_damaged or positions_by_uid.size() != _weakpoints.size():
		return false
	var positions: Array[Vector2] = []
	var minimum_spacing: float = 2.0 * WEAKPOINT_RADIUS + 4.0
	for point: Dictionary in _weakpoints:
		var uid: int = int(point["uid"])
		if not positions_by_uid.has(uid) or not positions_by_uid[uid] is Vector2:
			return false
		var position: Vector2 = positions_by_uid[uid]
		var radius: float = float(point["radius"])
		if not position.is_finite() or not _bounds.encloses(Rect2(position - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)):
			return false
		for earlier: Vector2 in positions:
			if earlier.distance_squared_to(position) < minimum_spacing * minimum_spacing:
				return false
		positions.append(position)
	for index: int in _weakpoints.size():
		_weakpoints[index]["position"] = positions[index]
	_weakpoints_relocated = true
	return true


func damage_weakpoint(uid: int, cast_id: int, amount: float) -> Dictionary:
	var rejected: Dictionary = {"hit": false, "broke": false, "interrupted": false, "damage": 0.0}
	# A deadline-pending charge remains hittable until finish_friendly_step.
	if not _running or _phase != "charge" or cast_id != _cast_id or not is_finite(amount) or amount <= 0.0:
		return rejected
	for point: Dictionary in _weakpoints:
		if int(point["uid"]) != uid or not bool(point["active"]) or float(point["health"]) <= 0.0:
			continue
		var actual: float = minf(amount, float(point["health"]))
		_weakpoints_damaged = true
		point["health"] = maxf(0.0, float(point["health"]) - actual)
		var broke: bool = float(point["health"]) <= 0.0
		if broke:
			point["active"] = false
		var interrupted: bool = _remaining_weakpoints() == 0
		if interrupted:
			_interrupt_current_cast()
		return {"hit": true, "broke": broke, "interrupted": interrupted, "damage": actual,
			"uid": uid, "cast_id": _cast_id, "position": point["position"]}
	return rejected


func snapshot() -> Dictionary:
	return {
		"running": _running,
		"phase": _phase,
		"name": str(ATTACK_NAMES.get(_attack_id, "")),
		"attack_id": _attack_id,
		"cast_id": _cast_id,
		"charge_left": _phase_left if _phase == "charge" else 0.0,
		"charge_total": _charge_total,
		"release_pending": _release_pending,
		"weakpoints_remaining": _remaining_weakpoints(),
		"weakpoints": weakpoints_snapshot(),
		"phase2": _phase2,
		"cast_phase2": _cast_phase2,
		"hold_position": _phase == "charge" or _phase == "break",
		"position": _boss_position,
		"cast_position": _cast_position,
		"weakpoint_anchor": _weakpoint_anchor,
		"locked_target": _locked_target,
		"break_left": _phase_left if _phase == "break" else 0.0,
		"damage_multiplier": BREAK_DAMAGE_MULTIPLIER if _phase == "break" else 1.0,
		"safe_channels": _safe_channels.duplicate(true),
	}


func _start_cast(player_position: Vector2) -> void:
	var sequence: Array[String] = []
	sequence.assign(PHASE_TWO_SEQUENCE if _phase2 else PHASE_ONE_SEQUENCE)
	_attack_id = sequence[_sequence_cursor % sequence.size()]
	_sequence_cursor += 1
	_cast_id += 1
	_cast_phase2 = _phase2
	_cast_position = _boss_position
	# A border clamp keeps distinct original point geometry inside the playable world.
	# The points remain at these world coordinates until the cast ends.
	_weakpoint_anchor = _bounded(_boss_position, 164.0)
	_locked_target = _bounded(player_position, 16.0)
	_pattern_center = _bounded(_locked_target, 440.0)
	_charge_total = float(CHARGE_SECONDS[_attack_id])
	_phase_left = _charge_total
	_release_pending = false
	_weakpoints_relocated = false
	_weakpoints_damaged = false
	_phase = "charge"
	_geometry.clear()
	_safe_channels.clear()
	_build_weakpoints()
	if _attack_id == "forest_storm":
		_build_storm()
	elif _attack_id == "root_corridor":
		_build_roots()


func _build_weakpoints() -> void:
	_weakpoints.clear()
	var heading: Vector2 = _locked_target - _cast_position
	heading = heading.normalized() if not heading.is_zero_approx() else Vector2.DOWN
	var side: Vector2 = heading.orthogonal()
	var offsets: Array[Vector2] = []
	match _attack_id:
		"forest_storm":
			if _cast_phase2:
				offsets.assign([heading * 136.0, side * 128.0 - heading * 40.0, -side * 128.0 - heading * 40.0])
			else:
				offsets.assign([Vector2(-108, -64), Vector2(108, -64), Vector2(0, 120)])
		"root_corridor":
			offsets.assign([heading * 92.0 + side * 112.0, heading * 92.0 - side * 112.0] if _cast_phase2 else [side * 108.0, -side * 108.0])
		"spirit_chorus":
			offsets.assign([-heading * 112.0 + side * 96.0, -heading * 112.0 - side * 96.0] if _cast_phase2 else [Vector2(-128, 20), Vector2(128, 20)])
	var health: float = 32.0 if _cast_phase2 else 24.0
	for index: int in offsets.size():
		_weakpoints.append({"uid": _next_weakpoint_uid, "cast_id": _cast_id,
			"position": _weakpoint_anchor + offsets[index], "radius": WEAKPOINT_RADIUS,
			"health": health, "max_health": health, "active": true})
		_next_weakpoint_uid += 1
	assert(_weakpoints.size() <= MAX_WEAKPOINTS)


func _remaining_weakpoints() -> int:
	var count: int = 0
	for point: Dictionary in _weakpoints:
		if float(point["health"]) > 0.0:
			count += 1
	return count


func _interrupt_current_cast() -> void:
	_release_pending = false
	_phase = "break"
	_phase_left = BREAK_SECONDS
	_pending_events.append(_event("interrupted"))
	_pending_events.append(_event("break_started", {"duration": BREAK_SECONDS, "damage_multiplier": BREAK_DAMAGE_MULTIPLIER}))
	assert(_pending_events.size() <= 2)


func _build_storm() -> void:
	var offsets: Array[Vector2] = []
	offsets.assign([Vector2.ZERO, Vector2(-168, 0), Vector2(168, 0), Vector2(0, -168), Vector2(0, 168)] if _cast_phase2 else [Vector2(-112, 0), Vector2(112, 0), Vector2(0, 160)])
	for index: int in offsets.size():
		_geometry.append({"shape": "circle", "position": _bounded(_locked_target + offsets[index], 88.0),
			"radius": 88.0, "damage": 18.0 if _cast_phase2 else 16.0,
			"delay": float(index) * (0.14 if _cast_phase2 else 0.22), "duration": 0.25,
			"order": index})


func _build_roots() -> void:
	# P1: vertical triple lanes, two clear corridors. P2: horizontal four lanes,
	# one central clear corridor. This changes movement decisions, not just timers.
	var direction: Vector2 = Vector2.RIGHT if _cast_phase2 else Vector2.DOWN
	var normal: Vector2 = direction.orthogonal()
	var safe_indices: Array[int] = []
	safe_indices.assign([2] if _cast_phase2 else [1, 3])
	for index: int in 5:
		var midpoint: Vector2 = _pattern_center + normal * float(index - 2) * 160.0
		var lane: Dictionary = {"shape": "lane", "position": midpoint - direction * 420.0,
			"direction": direction, "length": 840.0, "width": 128.0 if safe_indices.has(index) else 112.0,
			"index": index, "cap": "square"}
		if safe_indices.has(index):
			_safe_channels.append(lane)
		else:
			lane["damage"] = 18.0 if _cast_phase2 else 16.0
			lane["delay"] = 0.0
			lane["duration"] = 0.45
			_geometry.append(lane)


func _summon_pattern() -> Dictionary:
	var positions: Array[Vector2] = []
	if _cast_phase2:
		for angle: float in [PI / 6.0, PI * 5.0 / 6.0, PI * 1.5]:
			positions.append(_bounded(_locked_target + Vector2.from_angle(angle) * 180.0, 32.0))
	else:
		positions.assign([_bounded(_cast_position + Vector2(-196, 0), 32.0), _bounded(_cast_position + Vector2(196, 0), 32.0)])
	return {"role": "boss_ghost", "enemy_id": "chaser", "positions": positions,
		"count": positions.size(), "max_alive": 6 if _cast_phase2 else 4,
		"health_factor": 0.6, "damage_factor": 0.75, "expires_on_boss_stop": true}


func _event(type: String, payload: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"type": type, "attack_id": _attack_id, "cast_id": _cast_id,
		"source": "boss_attack:%s:%d" % [_attack_id, _cast_id],
		"phase2": _cast_phase2, "origin": _cast_position}
	result.merge(payload.duplicate(true), true)
	return result


func _bounded(point: Vector2, inset: float) -> Vector2:
	var safe: Rect2 = _bounds.grow(-inset)
	return Vector2(clampf(point.x, safe.position.x, safe.end.x), clampf(point.y, safe.position.y, safe.end.y))


static func _timer_after(remaining: float, delta: float) -> float:
	var result: float = maxf(0.0, remaining - delta)
	return 0.0 if result < 0.0000001 else result
