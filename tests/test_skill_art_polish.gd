extends SceneTree
## Real skill definitions constrain every decorative point and the fixed cosmetic budget.

const PAINTER = preload("res://scripts/combat/active_skill_painter.gd")
const FAMILIES: Dictionary = {"alk": "blade", "clarisse": "alchemy", "celtie": "wind",
	"hanabi": "firework", "starfall": "meteor", "arc_slash": "crescent"}
const COLORS: Dictionary = {"alk": Color("ffc86b"), "clarisse": Color("efa54c"), "celtie": Color("87d9ab"),
	"hanabi": Color("f1875e"), "starfall": Color("ffc86b"), "arc_slash": Color("91e0d1")}
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_definition_geometry()
	_test_identity_and_static_mode()
	_test_firework_readability()
	_test_budget_and_invalid_input()
	_test_pure_queries()
	print("SkillArtPolish: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _parameters(id: String) -> Dictionary:
	return HeroCatalog.hero_skill_parameters(id, {}) if HeroCatalog.IDS.has(id) else ActiveSkillRules.parameters(id, 3, {})

func _add(painter: PAINTER, id: String, origin: Vector2, direction: Vector2, animated: bool = true) -> bool:
	var spec: Dictionary = _parameters(id)
	return painter.add_hero_cast(spec, origin, direction, animated) if HeroCatalog.IDS.has(id) else painter.add_cast(id, origin, direction, float(spec["radius"]), animated)

func _test_definition_geometry() -> void:
	var origin := Vector2(-640.25, 880.5)
	for id: String in FAMILIES:
		var spec: Dictionary = _parameters(id)
		var original: String = JSON.stringify(spec)
		for direction: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2(-0.6, 0.8)]:
			for progress: float in [0.0, 0.25, 0.6, 0.95]:
				var painter = PAINTER.new()
				_check(_add(painter, id, origin, direction), "Every actual hero and rear skill accepts presentation: " + id)
				painter.advance(PAINTER.LIFE * progress)
				var records: Array[Dictionary] = painter.geometry_snapshot()
				_check(records.size() == 1, "One cast produces one diagnostic record: " + id)
				if records.size() != 1:
					continue
				var record: Dictionary = records[0]
				var shape: String = str(spec.get("shape", "arc" if id == "arc_slash" else "circle"))
				_check(record["origin"] == origin and (record["direction"] as Vector2).is_equal_approx(direction.normalized()) and record["shape"] == shape and record["radius"] == spec["radius"], "Cosmetic records retain the true cast origin, orientation and range: " + id)
				_check(record["family"] == FAMILIES[id] and record["color"] == COLORS[id], "Each family keeps its intended distinctive palette and silhouette: " + id)
				var polygons: Array = record["polygons"]
				var details: PackedVector2Array = record["details"]
				var contained: bool = true
				var triangulatable: bool = true
				for polygon: PackedVector2Array in polygons:
					triangulatable = triangulatable and polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty()
					for point: Vector2 in polygon:
						contained = contained and point.is_finite() and CombatSim.skill_contains(spec, origin, direction, point)
				for point: Vector2 in details:
					contained = contained and point.is_finite() and CombatSim.skill_contains(spec, origin, direction, point)
				_check(contained, "All internal fragments and trail endpoints stay inside the actual combat hit shape: " + id)
				_check(triangulatable, "All rendered tapered bands and flower polygons are valid simple fills: " + id)
				_check(polygons.size() > 0 and polygons.size() <= PAINTER.MAX_POLYGONS and details.size() <= PAINTER.MAX_DETAIL_POINTS and details.size() % 2 == 0, "Each cast keeps its fixed polygon and line-point budget: " + id)
		_check(JSON.stringify(spec) == original, "Art queries never rewrite catalog parameters: " + id)

func _test_identity_and_static_mode() -> void:
	var signatures: Dictionary = {}
	for id: String in FAMILIES:
		var painter = PAINTER.new()
		_add(painter, id, Vector2(640, 360), Vector2.RIGHT)
		var record: Dictionary = painter.geometry_snapshot()[0]
		var silhouette: String = JSON.stringify([record["family"], record["polygons"], record["details"]])
		_check(not signatures.has(silhouette), "No two skill identities share the same complete internal silhouette: " + id)
		signatures[silhouette] = true
		painter.disable_animation()
		var static_record: Dictionary = painter.geometry_snapshot()[0]
		_check(not static_record["animated"] and static_record["polygons"].is_empty() and static_record["details"].is_empty(), "Flash suppression leaves only the precise static low-light boundary: " + id)
		painter.advance(0.05)
		var later: Dictionary = painter.geometry_snapshot()[0]
		_check(later["origin"] == static_record["origin"] and later["direction"] == static_record["direction"] and later["radius"] == static_record["radius"] and later["width"] == static_record["width"] and later["half_angle_radians"] == static_record["half_angle_radians"] and later["polygons"].is_empty() and later["details"].is_empty(), "Suppressed effects fade without rotating, moving fragments or replaying animation: " + id)
		_check(painter.snapshot()["animated"] == 0, "Reading or advancing a suppressed cast cannot replay it: " + id)
	var zero_direction = PAINTER.new()
	_add(zero_direction, "hanabi", Vector2.ZERO, Vector2.ZERO)
	_check(zero_direction.geometry_snapshot()[0]["direction"] == Vector2.RIGHT, "A zero diagnostic heading retains the existing finite right-facing fallback")

func _test_firework_readability() -> void:
	var origin := Vector2(640, 360)
	var spec: Dictionary = HeroCatalog.hero_skill_parameters("hanabi", {})
	for direction: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2(-0.6, 0.8)]:
		for progress: float in [0.0, 0.5, 0.95]:
			var painter = PAINTER.new()
			_add(painter, "hanabi", origin, direction)
			painter.advance(PAINTER.LIFE * progress)
			var record: Dictionary = painter.geometry_snapshot()[0]
			var polygons: Array = record["polygons"]
			var details: PackedVector2Array = record["details"]
			_check(polygons.size() == 8 and details.size() == 16 and record["detail_width"] == 2.0, "Four enlarged fireworks retain the original pool and exact bounded short-line budget")
			var side: Vector2 = direction.orthogonal()
			var all_points: PackedVector2Array = details.duplicate()
			for index: int in polygons.size():
				var low: float = INF
				var high: float = -INF
				for point: Vector2 in polygons[index]:
					var along: float = (point - origin).dot(direction)
					low = minf(low, along)
					high = maxf(high, along)
					all_points.append(point)
				var span: float = high - low
				_check(span >= (24.0 if index % 2 == 0 else 8.0), "Both the orange burst and warm core stay legible during the sampled fade")
				_check(span <= float(spec["radius"]) * 0.2, "The line skill uses distinct short bursts rather than a continuous wide fill")
			var contained: bool = true
			for point: Vector2 in all_points:
				var offset: Vector2 = point - origin
				contained = contained and offset.dot(direction) >= 1.0 and offset.dot(direction) <= float(spec["radius"]) - 1.0 and absf(offset.dot(side)) <= float(spec["width"]) * 0.5 - 1.0
			_check(contained, "The enlarged flowers, cores and two-pixel trails keep a full stroke margin inside the true rectangle")

func _test_budget_and_invalid_input() -> void:
	var painter = PAINTER.new()
	for index: int in 80:
		_add(painter, HeroCatalog.IDS[index % HeroCatalog.IDS.size()], Vector2(640, 360), Vector2.RIGHT)
	_check(painter.snapshot() == {"active": 8, "animated": 8, "capacity": 8} and painter.geometry_snapshot().size() == 8, "Skill spam reuses the exact original eight-slot pool")
	var before: String = JSON.stringify(painter.geometry_snapshot())
	for delta: float in [0.0, -1.0, NAN, INF]:
		painter.advance(delta)
	_check(JSON.stringify(painter.geometry_snapshot()) == before, "Invalid or zero time cannot advance the cosmetic clock")
	var invalids: Array[Dictionary] = [
		{"shape": "circle", "radius": NAN}, {"shape": "circle", "radius": -1.0},
		{"shape": "line", "radius": 280.0, "width": INF}, {"shape": "line", "radius": 280.0, "width": 0.0},
		{"shape": "arc", "radius": 180.0, "half_angle_radians": 0.0},
		{"shape": "arc", "radius": 180.0, "half_angle_radians": PI + 0.1},
		{"shape": "other", "radius": 180.0}, {"shape": "circle", "radius": "bad"},
	]
	for invalid: Dictionary in invalids:
		_check(not painter.add_hero_cast(invalid, Vector2.ZERO, Vector2.RIGHT, true), "Malformed presentation input cannot replace a live pool slot")
	_check(not painter.add_cast("pulse", Vector2.ZERO, Vector2.RIGHT, 100.0, true) and not painter.add_cast("starfall", Vector2.INF, Vector2.RIGHT, 112.0, true) and not painter.add_hero_cast(HeroCatalog.hero_skill_parameters("alk", {}), Vector2.ZERO, Vector2.INF, true), "The separate pulse renderer and nonfinite origins or headings stay rejected")
	_check(JSON.stringify(painter.geometry_snapshot()) == before, "Rejected geometry leaves all previous visible casts untouched")
	painter.advance(PAINTER.LIFE)
	_check(painter.snapshot()["active"] == 0 and painter.geometry_snapshot().is_empty(), "No fragments or range confirmations outlive the original 0.26-second effect")
	_add(painter, "alk", Vector2.ZERO, Vector2.RIGHT)
	painter.clear()
	_check(painter.snapshot() == {"active": 0, "animated": 0, "capacity": 8}, "Clearing returns the complete fixed pool to its inactive state")

func _test_pure_queries() -> void:
	var run := RunState.new()
	run.begin(20261030, "bone", "mire", "alk")
	var sim := CombatSim.new()
	sim.begin(run)
	var before: String = JSON.stringify([sim.snapshot(), sim.interactions.snapshot(), run.summary(), str(sim.rng.state), str(run.rng.state), str(sim.interactions._rng.state)])
	var painter = PAINTER.new()
	_add(painter, "alk", sim.player_position, Vector2.RIGHT)
	painter.advance(0.08)
	var stable: String = JSON.stringify(painter.geometry_snapshot())
	var remaining: float = painter._pool[0].life
	for index: int in 100:
		painter.geometry_snapshot()
		painter.snapshot()
	_check(painter._pool[0].life == remaining and JSON.stringify(painter.geometry_snapshot()) == stable, "Repeated art queries do not advance age, fragment positions or cast lifetime")
	var mutable: Array[Dictionary] = painter.geometry_snapshot()
	mutable[0]["origin"] = Vector2.INF
	var mutable_polygons: Array = mutable[0]["polygons"]
	var mutable_polygon: PackedVector2Array = mutable_polygons[0]
	mutable_polygon[0] = Vector2.INF
	mutable_polygons[0] = mutable_polygon
	var mutable_details: PackedVector2Array = mutable[0]["details"]
	mutable_details.clear()
	_check(JSON.stringify(painter.geometry_snapshot()) == stable, "Returned geometry has no aliases into retained cast buffers")
	_check(JSON.stringify([sim.snapshot(), sim.interactions.snapshot(), run.summary(), str(sim.rng.state), str(run.rng.state), str(sim.interactions._rng.state)]) == before, "Skill art leaves actual combat, inventory and all three private RNG streams unchanged")
	seed(812073)
	var expected: int = randi()
	seed(812073)
	painter.geometry_snapshot()
	_check(randi() == expected, "Procedural fragments do not consume the global random stream either")
