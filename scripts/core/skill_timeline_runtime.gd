class_name SkillTimelineRuntime
extends RefCounted
## Fixed-step skill areas retain their own lifetime and per-target contact cadence.

const LIMIT: int = 24
const MAX_PHASES: int = 8
const MAX_HITS: int = 32
const EPSILON: float = 0.0000001

class ContactGeometry:
	var kind: int = 0
	var valid: bool = false
	var origin: Vector2 = Vector2.ZERO
	var direction: Vector2 = Vector2.RIGHT
	var radius_squared: float = 0.0
	var half_length: float = 0.0
	var half_width: float = 0.0

	func configure(parameters: Dictionary, center: Vector2, heading: Vector2) -> void:
		origin = center
		valid = center.is_finite() and heading.is_finite() and not heading.is_zero_approx()
		direction = heading.normalized() if valid else Vector2.ZERO
		match str(parameters.get("shape", "arc" if parameters.get("id", "") == "arc_slash" else "circle")):
			"circle":
				kind = 1
				var radius: float = float(parameters.get("radius", 0.0))
				radius_squared = radius * radius + 0.01
			"rectangle":
				kind = 2
				half_length = float(parameters.get("half_length", 0.0))
				half_width = float(parameters.get("width", 0.0)) * 0.5
			_: kind = 0

	func contains(point: Vector2) -> bool:
		if not valid or not point.is_finite():
			return false
		var offset: Vector2 = point - origin
		if kind == 1:
			return not (offset.length_squared() > radius_squared)
		return kind == 2 and absf(direction.dot(offset)) <= half_length and absf(direction.cross(offset)) <= half_width

class Area:
	var occupied: bool = false
	var serial: int = 0
	var age: float = 0.0
	var previous_age: float = 0.0
	var delay: float = 0.0
	var duration: float = 0.0
	var max_hits: int = 1
	var interval: float = 0.0
	var purpose: String = "damage"
	var origin: Vector2 = Vector2.ZERO
	var direction: Vector2 = Vector2.RIGHT
	var follow_offset: Vector2 = Vector2.ZERO
	var anchor: String = "fixed"
	var parameters: Dictionary = {}
	var contacts: Dictionary = {}
	var next_contacts: Dictionary = {}
	var opened: bool = false
	var held: bool = false
	var contact_geometry: ContactGeometry = ContactGeometry.new()

var areas: Array[Area] = []
var _serial: int = 0
var _occupied: int = 0
var _step_serial_limit: int = 0
var peak: int = 0

func _init() -> void:
	for index: int in LIMIT:
		areas.append(Area.new())

func clear() -> void:
	for area: Area in areas:
		area.occupied = false
		area.parameters.clear()
		area.contacts.clear()
		area.next_contacts.clear()
	_occupied = 0
	_serial = 0
	_step_serial_limit = 0
	peak = 0

func enqueue(parameters: Dictionary, origin: Vector2, direction: Vector2) -> bool:
	var phases: Variant = parameters.get("timeline", [])
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not phases is Array:
		return false
	if phases.is_empty() or phases.size() > MAX_PHASES or _occupied + phases.size() > LIMIT:
		return false
	var damage: float = _number(parameters.get("damage"), -1.0)
	if damage < 0.0 or str(parameters.get("id", "")).is_empty():
		return false
	var weight: float = 0.0
	for phase: Variant in phases:
		if not phase is Dictionary or not _valid_phase(phase):
			return false
		weight += _number(phase.get("damage_weight"), 0.0)
	if not is_finite(weight) or absf(weight - 1.0) > EPSILON:
		return false
	var slot: int = 0
	for phase: Dictionary in phases:
		while areas[slot].occupied:
			slot += 1
		var area: Area = areas[slot]
		_serial += 1
		area.occupied = true
		area.serial = _serial
		area.age = 0.0
		area.previous_age = 0.0
		area.delay = float(phase["delay"])
		area.duration = float(phase["duration"])
		area.max_hits = int(phase.get("hits", 1))
		area.interval = area.duration / float(area.max_hits)
		area.purpose = str(phase.get("purpose", "damage"))
		area.direction = direction.normalized()
		area.follow_offset = area.direction * float(phase.get("forward_offset", 0.0)) + area.direction.orthogonal() * float(phase.get("lateral_offset", 0.0))
		area.origin = origin + area.follow_offset
		area.anchor = str(phase.get("anchor", "fixed"))
		area.parameters = parameters.duplicate(true)
		area.parameters.erase("timeline")
		area.parameters.merge(phase, true)
		area.parameters["damage"] = damage * float(phase.get("damage_weight", 0.0)) / float(area.max_hits)
		area.contacts.clear()
		area.next_contacts.clear()
		area.opened = false
		area.held = phase.get("trigger", "clock") == "impact"
		_occupied += 1
		slot += 1
	peak = maxi(peak, _occupied)
	return true

func reserve_impacts(parameters: Dictionary, origin: Vector2, direction: Vector2, count: int) -> Array[Area]:
	var selected: Array[Area] = []
	if count < 1 or count > MAX_PHASES:
		return selected
	var copy: Dictionary = parameters.duplicate(true)
	var phases: Array[Dictionary] = []
	for index: int in count:
		phases.append({"delay": 0.0, "duration": parameters.get("explosion_duration", 0.5),
			"shape": "circle", "radius": parameters.get("radius", 0.0), "hits": 1,
			"damage_weight": 1.0 / float(count), "trigger": "impact"})
	copy["timeline"] = phases
	var previous: int = _serial
	if not enqueue(copy, origin, direction):
		return selected
	for area: Area in areas:
		if area.occupied and area.serial > previous:
			selected.append(area)
	return selected

func cancel(held_areas: Array[Area]) -> void:
	for area: Area in held_areas:
		if areas.has(area) and area.occupied and area.held:
			area.occupied = false
			area.parameters.clear()
			area.contacts.clear()
			area.next_contacts.clear()
			_occupied -= 1

func activate_impact(area: Area, origin: Vector2, offset: float) -> bool:
	if area == null or not areas.has(area) or not area.occupied or not area.held or not origin.is_finite() or not is_finite(offset) or offset < 0.0:
		return false
	area.held = false
	area.opened = true
	area.origin = origin
	area.age = -offset
	area.previous_age = -offset
	return true

func advance(delta: float, caster: Vector2) -> void:
	if _occupied == 0 or not is_finite(delta) or delta <= 0.0:
		return
	_step_serial_limit = _serial
	for area: Area in areas:
		if not area.occupied or area.held:
			continue
		area.previous_age = area.age
		area.age += delta
		if (area.anchor == "caster" or (not area.opened and area.anchor == "caster_at_activation")) and caster.is_finite():
			area.origin = caster + area.follow_offset
		if not area.opened and area.age + EPSILON >= area.delay:
			area.opened = true

func can_contact(area: Area) -> bool:
	return area.occupied and area.serial <= _step_serial_limit and not area.held and area.age + EPSILON >= area.delay and area.previous_age < area.delay + area.duration - EPSILON

func claim_hits(area: Area, target_key: String) -> int:
	if target_key.is_empty() or not can_contact(area):
		return 0
	var used: int = int(area.contacts.get(target_key, 0))
	if used >= area.max_hits:
		return 0
	var start: float = maxf(area.previous_age, area.delay)
	var next: float = float(area.next_contacts.get(target_key, start))
	var end: float = minf(area.age, area.delay + area.duration - EPSILON)
	if next > end + EPSILON:
		return 0
	var count: int = mini(area.max_hits - used, 1 + maxi(0, floori((end - next + EPSILON) / area.interval)))
	area.contacts[target_key] = used + count
	area.next_contacts[target_key] = next + float(count) * area.interval
	return count

func separate(area: Area, target_key: String) -> void:
	area.next_contacts.erase(target_key)

func finish_step() -> void:
	if _occupied == 0:
		return
	for area: Area in areas:
		if area.occupied and not area.held and area.age + EPSILON >= area.delay + area.duration:
			area.occupied = false
			area.parameters.clear()
			area.contacts.clear()
			area.next_contacts.clear()
			_occupied -= 1

func snapshot() -> Dictionary:
	var visible: Array[Dictionary] = []
	for area: Area in areas:
		if not area.occupied:
			continue
		visible.append({"serial": area.serial, "age": area.age, "delay": area.delay,
			"duration": area.duration, "active": area.opened, "held": area.held, "purpose": area.purpose, "anchor": area.anchor,
			"origin": area.origin, "direction": area.direction, "follow_offset": area.follow_offset,
			"parameters": area.parameters.duplicate(true), "hits": area.contacts.duplicate(),
			"max_hits": area.max_hits, "interval": area.interval})
	return {"areas": visible, "occupied": _occupied, "capacity": LIMIT, "peak": peak}

static func _valid_phase(phase: Dictionary) -> bool:
	for key: String in ["forward_offset", "lateral_offset"]:
		var offset: float = _number(phase.get(key, 0.0), INF)
		if not is_finite(offset) or absf(offset) > 10240.0:
			return false
	var delay: float = _number(phase.get("delay"), -1.0)
	var duration: float = _number(phase.get("duration"), -1.0)
	var raw_hits: float = _number(phase.get("hits", 1), -1.0)
	var hits: int = int(raw_hits)
	var weight: float = _number(phase.get("damage_weight", 0.0), -1.0)
	if delay < 0.0 or delay > 30.0 or duration <= 0.0 or duration > 10.0 or hits < 1 or hits > MAX_HITS or float(hits) != raw_hits or weight < 0.0:
		return false
	if phase.get("purpose", "damage") not in ["damage", "dispel"] or phase.get("anchor", "fixed") not in ["fixed", "caster_at_activation", "caster"]:
		return false
	if phase.get("trigger", "clock") not in ["clock", "impact"]:
		return false
	if (phase.get("purpose", "damage") == "dispel" and weight != 0.0) or (phase.get("purpose", "damage") == "damage" and weight <= 0.0):
		return false
	match str(phase.get("shape", "")):
		"circle": return _number(phase.get("radius"), 0.0) > 0.0
		"rectangle": return _number(phase.get("half_length"), 0.0) > 0.0 and _number(phase.get("width"), 0.0) > 0.0
	return false

static func _number(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback
