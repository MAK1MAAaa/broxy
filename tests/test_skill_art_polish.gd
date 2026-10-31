extends SceneTree
## Real skill definitions constrain every decorative point and the fixed cosmetic budget.

const PAINTER = preload("res://scripts/combat/active_skill_painter.gd")
const FAMILIES: Dictionary = {"starfall": "meteor", "arc_slash": "crescent"}
const COLORS: Dictionary = {"starfall": Color("ffc86b"), "arc_slash": Color("91e0d1")}
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_definition_geometry()
	_test_timeline_geometry()
	_test_identity_and_static_mode()
	_test_bomb_delivery_separation()
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
				_check(_add(painter, id, origin, direction), "Every instant rear skill accepts its own bounded presentation: " + id)
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
	_add(zero_direction, "starfall", Vector2.ZERO, Vector2.ZERO)
	_check(zero_direction.geometry_snapshot()[0]["direction"] == Vector2.RIGHT, "A zero diagnostic heading retains the existing finite right-facing fallback")

func _test_bomb_delivery_separation() -> void:
	var spec: Dictionary = HeroCatalog.hero_skill_parameters("hanabi", {})
	var painter = PAINTER.new()
	_add(painter, "starfall", Vector2(640, 360), Vector2.RIGHT)
	var before: String = JSON.stringify(painter.geometry_snapshot())
	for heading: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2(-0.6, 0.8)]:
		_check(not painter.add_hero_cast(spec, Vector2(640, 360), heading, true), "Hanabi's actual bombs never produce an instant cosmetic hit rectangle")
	_check(JSON.stringify(painter.geometry_snapshot()) == before, "Rejecting bomb delivery leaves existing instant-cast geometry untouched")
	_check(spec["delivery"] == "bombs" and spec["projectiles"] == 5, "The Hanabi spec explicitly hands five deliveries to the physical runtime")


func _test_budget_and_invalid_input() -> void:
	var painter = PAINTER.new()
	for index: int in 80:
		_add(painter, "starfall" if index % 2 == 0 else "arc_slash", Vector2(640, 360), Vector2.RIGHT)
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
	_add(painter, "starfall", Vector2.ZERO, Vector2.RIGHT)
	painter.clear()
	_check(painter.snapshot() == {"active": 0, "animated": 0, "capacity": 8}, "Clearing returns the complete fixed pool to its inactive state")

func _test_pure_queries() -> void:
	var run := RunState.new()
	run.begin(20261030, "bone", "mire", "alk")
	var sim := CombatSim.new()
	sim.begin(run)
	var before: String = JSON.stringify([sim.snapshot(), sim.interactions.snapshot(), run.summary(), str(sim.rng.state), str(run.rng.state), str(sim.interactions._rng.state)])
	var painter = PAINTER.new()
	_add(painter, "starfall", sim.player_position, Vector2.RIGHT)
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

func _test_timeline_geometry() -> void:
	for id: String in ["alk", "clarisse", "celtie"]:
		var spec: Dictionary = HeroCatalog.hero_skill_parameters(id, {})
		for direction: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2(-0.6, 0.8)]:
			for age: float in [0.0, 0.5, 0.75, 1.4, 2.3]:
				var runtime := SkillTimelineRuntime.new()
				_check(runtime.enqueue(spec, Vector2(640, 360), direction), "Actual delayed areas enter their authoritative pool: " + id)
				runtime.advance(age, Vector2(640, 360))
				runtime.finish_step()
				var value: Dictionary = runtime.snapshot()
				var stable: String = JSON.stringify(value)
				var has_damage: bool = false
				for area: Dictionary in value["areas"]:
					has_damage = has_damage or area["purpose"] == "damage"
				for flash: bool in [true, false]:
					var geometry: Dictionary = SkillAreaPainter.geometry_snapshot(value, flash)
					_check(geometry["commands"].is_empty() == (not has_damage) and geometry["commands"].size() <= SkillAreaPainter.MAX_COMMANDS, "Real area phases retain bounded geometry in both flash settings: " + id)
					for command: Dictionary in geometry["commands"]:
						var points := PackedVector2Array()
						var padding: float = 0.0
						match str(command["kind"]):
							"line":
								points.append_array(PackedVector2Array([command["from"], command["to"]]))
								padding = float(command["width"]) * 0.5
							"polygon":
								points = command["points"]
								_check(not Geometry2D.triangulate_polygon(points).is_empty(), "Active wind ribbons remain valid simple polygons")
							"arc":
								var center: Vector2 = command["center"]
								var extent := Vector2.ONE * float(command["radius"])
								points.append_array(PackedVector2Array([center - extent, center + extent]))
								padding = float(command["width"]) * 0.5
						var contained: bool = false
						for bound: Rect2 in geometry["bounds"]:
							var fits: bool = true
							for point: Vector2 in points:
								fits = fits and point.is_finite() and bound.grow(0.002 - padding).has_point(point)
							contained = contained or fits
						_check(contained, "The exact native area command including stroke width stays inside an authoritative range bound: " + id)
					_check(JSON.stringify(value) == stable and runtime.snapshot() == value, "Area art is a pure read of simulation clocks, positions and contact counters")
				var old = PAINTER.new()
				_check(not old.add_hero_cast(spec, Vector2(640, 360), direction, true) and old.geometry_snapshot().is_empty(), "Delayed areas cannot also emit a phantom instant cast: " + id)
	var full := SkillTimelineRuntime.new()
	for index: int in SkillTimelineRuntime.LIMIT:
		_check(full.enqueue(HeroCatalog.hero_skill_parameters("alk", {}), Vector2(640, 360), Vector2.RIGHT), "All declared area slots remain usable by real phase definitions")
	full.advance(0.8, Vector2(640, 360))
	var crowded: Dictionary = SkillAreaPainter.geometry_snapshot(full.snapshot(), true)
	_check(crowded["bounds"].size() == SkillTimelineRuntime.LIMIT and crowded["commands"].size() <= SkillAreaPainter.MAX_COMMANDS, "Twenty-four real areas keep their complete native geometry within the fixed command budget")
	full.clear()
	_check(SkillAreaPainter.geometry_snapshot(full.snapshot(), true)["commands"].is_empty(), "A cleared timeline cannot leave stale windups or impact art")
