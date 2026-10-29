extends SceneTree
## Actual collider topology, deterministic loot and continuous hit queries.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_authored_layouts()
	_test_first_hit()
	_test_indexed_crate_sweeps()
	_test_nearby_damage_candidates()
	_test_disabled_topology()
	_test_crate_damage()
	_test_drop_streams()
	_test_queries_and_collection()
	_test_configuration_limits()
	print("ArenaInteractions: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _arena(count: int = 1) -> Dictionary:
	var crates: Array[Dictionary] = []
	for index: int in count:
		crates.append({"id": "box_%d" % index, "center": Vector2(300 + index * 100, 300),
			"radius": 18.0, "art_id": "barrel", "max_health": 24.0})
	return {"id": "fixture", "obstacles": [], "crates": crates}

func _fixture(seed_value: int = 20261030, count: int = 1, wave: int = 1, arena_id: String = "fixture") -> ArenaInteractions:
	var arena: Dictionary = _arena(count)
	arena["id"] = arena_id
	var result := ArenaInteractions.new()
	result.configure(arena, seed_value, wave, ArenaObstacles.new())
	return result

func _test_authored_layouts() -> void:
	var legacy_ids: Array[String] = ["southwest", "southeast", "northwest", "north", "northeast", "east_north", "east", "east_south", "south", "west_south"]
	var zone_count: int = 0
	for id: String in ArenaCatalog.IDS:
		var arena: Dictionary = ArenaCatalog.definition(id)
		zone_count += (arena["zones"] as Array).size()
		var field := ArenaObstacles.new()
		var interactions := ArenaInteractions.new()
		interactions.configure(arena, 42, 1, field)
		var crates: Array = interactions.snapshot()["crates"]
		var colliders: Array[Dictionary] = field.snapshot()
		_check(crates.size() == 12 and colliders.size() == 24 and colliders.size() <= ArenaObstacles.MAX_OBSTACLES, "Every map has twelve crates and bounded static-plus-breakable collision: " + id)
		var actual_ids: Array[String] = []
		for obstacle: Dictionary in arena["obstacles"]:
			actual_ids.append(str(obstacle["id"]))
		for legacy_id: String in legacy_ids:
			_check(actual_ids.has(legacy_id), "Existing authored obstacle identity survives: " + id + "/" + legacy_id)
		_check(actual_ids.has("west_bumper") and actual_ids.has("east_bumper"), "The opening view contains two new discoverable bumper landmarks: " + id)
		var central: int = 0
		for crate: Dictionary in crates:
			var center: Vector2 = crate["position"]
			var radius: float = float(crate["radius"])
			if Rect2(0, 0, 1280, 720).has_point(center):
				central += 1
			_check(crate["active"] and radius == 18.0 and crate["health"] == crate["max_health"] and float(crate["max_health"]) == (40.0 if crate["art_id"] == "chest" else 24.0), "Crates use their authored art and real health: " + id)
			_check(center.distance_to(Vector2(640, 360)) - radius >= 180.0 and center.distance_to(Vector2(640, 208)) - radius >= 120.0, "Crates preserve the main-character and boss openings: " + id)
			_check(ArenaCatalog.WORLD_BOUNDS.encloses(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)), "The complete crate collider stays inside the world: " + id)
			for other: Dictionary in colliders:
				if str(other["id"]) == "crate:" + str(crate["id"]):
					continue
				_check(center.distance_to(other["center"]) > radius + float(other["radius"]) + 32.0, "Crates and landmarks retain open traversable gaps: " + id)
		_check(central == 4 and field.is_free(ArenaCatalog.WORLD_BOUNDS.get_center(), 16.0, 16.0), "Four opening crates leave eight distant finds and a clear actual spawn: " + id)
	_check(zone_count == 34 and ArenaCatalog.WORLD_BOUNDS == Rect2(-1082, -535, 3444, 1800), "New scenery preserves all thirty-four terrain patches and the established world")
	_check(ArenaCatalog.art_rect() == Rect2(-1146, -767, 3780, 2192), "Art has the requested top extension for the separate boss HUD")

func _field(rows: Array) -> ArenaObstacles:
	var field := ArenaObstacles.new()
	field.bounds = Rect2(0, 0, 1000, 600)
	field.configure(rows)
	return field

func _test_first_hit() -> void:
	var field: ArenaObstacles = _field([
		{"id": "far", "center": Vector2(500, 300), "radius": 40.0, "art_id": "bumper"},
		{"id": "near", "center": Vector2(300, 300), "radius": 20.0, "art_id": "barrel"},
	])
	var hit: Dictionary = field.first_hit(Vector2(100, 300), Vector2(2000, 0), 10.0, 10.0)
	_check(hit["id"] == "near" and hit["index"] == 1 and is_equal_approx(float(hit["t"]), 170.0 / 2000.0) and hit["normal"] == Vector2.LEFT, "Continuous collision finds the earliest expanded circle independently of registry order or large step")
	_check((hit["normal"] as Vector2).is_finite() and is_equal_approx((hit["normal"] as Vector2).length(), 1.0), "A returned contact normal is finite and normalized")
	hit = field.first_hit(Vector2(100, 300), Vector2(-2000, 0), 10.0, 10.0)
	_check(hit["id"] == "boundary" and hit["art_id"] == "wall" and hit["index"] == -1 and is_equal_approx(float(hit["t"]), 90.0 / 2000.0) and hit["normal"] == Vector2.RIGHT, "World bounds participate in the same earliest time-of-impact query")
	hit = field.first_hit(Vector2(100, 100), Vector2(-200, -200), 10.0, 10.0)
	_check(is_equal_approx(float(hit["t"]), 0.45) and (hit["normal"] as Vector2).is_equal_approx(Vector2.ONE.normalized()), "Simultaneous corner contact combines both inward boundary normals")
	_check(field.first_hit(Vector2(280, 300), Vector2(-10, 0), 10.0).is_empty(), "Starting overlapped and leaving a circle does not create sticky contact")
	hit = field.first_hit(Vector2(280, 300), Vector2(10, 0), 10.0)
	_check(hit["id"] == "near" and hit["t"] == 0.0 and hit["normal"] == Vector2.LEFT, "Starting overlapped and moving deeper reports an immediate surface")
	_check(field.first_hit(Vector2(100, 100), Vector2.ZERO, 16.0).is_empty() and field.first_hit(Vector2.INF, Vector2.RIGHT, 16.0).is_empty() and field.first_hit(Vector2.ZERO, Vector2.INF, 16.0).is_empty() and field.first_hit(Vector2.ZERO, Vector2.ONE, NAN).is_empty(), "Invalid or stationary sweeps cannot produce a contact")
	_check(field.set_active("near", false) and field.first_hit(Vector2(100, 300), Vector2(800, 0), 10.0)["id"] == "far", "Disabling the first collider reveals the next actual contact")
	_check(field.first_hit(Vector2(100, 300), Vector2(2000, 0), 10.0, 10.0, "crate:", false).is_empty(), "Filtered flying sweeps skip unrelated scenery and world bounds")

func _test_disabled_topology() -> void:
	var field: ArenaObstacles = _field([{"id": "crate:gate", "center": Vector2(500, 300), "radius": 40.0, "art_id": "chest"}])
	var start := Vector2(100, 300)
	var goal := Vector2(900, 300)
	var blocked: Vector2 = field.move_body(start, goal - start, 16.0)
	_check(blocked.x < 444.1 and not field.segment_clear(start, goal, 16.0) and field.is_free(blocked, 16.0), "An intact gate prevents large-step tunneling with ordinary sliding movement")
	_check(field.next_target(start, goal, 16.0, 7) != goal and not field._graphs.is_empty() and not field._routes.is_empty(), "The fixture builds an actual detour and cached visibility graph")
	field.next_target(Vector2(100, 40), Vector2(900, 40), 12.0, 8)
	var projection: ArenaObstacles.ProjectedGoal = field._projected_goals[12.0]
	_check(not projection.open_sources.is_empty(), "The fixture also caches a genuinely open source cell")
	var segments: Array[Rect2] = [Rect2(start, goal - start)]
	_check(field.clear_spawn_segments(segments, 16.0).size() == 2, "An intact gate cuts its actual spawn segment")
	_check(field.set_active("crate:gate", false) and field._graphs.is_empty() and field._graph_point_ids.is_empty() and field._graph_goals.is_empty() and field._routes.is_empty() and field._projected_goals.is_empty() and projection.open_sources.is_empty(), "Topology changes discard graph, shared endpoints, route, projected-goal and held open-source caches")
	_check(field.snapshot().is_empty() and field.is_free(Vector2(500, 300), 16.0) and field.free_point(Vector2(500, 300), 16.0) == Vector2(500, 300), "Inactive slots disappear from snapshots and position projections")
	_check(field.first_hit(start, goal - start, 16.0).is_empty() and field.segment_clear(start, goal, 16.0) and field.move_body(start, goal - start, 16.0) == goal and field.next_target(start, goal, 16.0, 7) == goal, "Destroying the gate opens real movement, segment and navigation queries immediately")
	_check(field.clear_spawn_segments(segments, 16.0) == segments, "Inactive slots no longer cut spawn segments despite conservative cached candidates")
	_check(field.set_active("crate:gate", true) and field.first_hit(start, goal - start, 16.0)["index"] == 0 and not field.segment_clear(start, goal, 16.0), "Reactivation retains the original fixed collider index and blocks the route again")
	_check(not field.set_active("missing", false), "Unknown collider IDs cannot alter topology")

func _oracle_crate_hit(crates: Array, start: Vector2, end: Vector2, padding: float) -> Dictionary:
	if not start.is_finite() or not end.is_finite() or not is_finite(padding) or padding < 0.0:
		return {}
	var delta: Vector2 = end - start
	var squared: float = delta.length_squared()
	if not delta.is_finite() or squared <= 0.000001:
		return {}
	var first: Dictionary = {}
	var earliest: float = INF
	for crate: Dictionary in crates:
		if not bool(crate["active"]):
			continue
		var offset: Vector2 = start - (crate["position"] as Vector2)
		var radius: float = float(crate["radius"]) + padding
		var outside: float = offset.length_squared() - radius * radius
		var projection: float = offset.dot(delta)
		var time: float = INF
		if outside <= 0.0001:
			if projection < -0.0001:
				time = 0.0
		elif projection < 0.0:
			var discriminant: float = projection * projection - squared * outside
			if discriminant >= 0.0:
				var entering: float = (-projection - sqrt(discriminant)) / squared
				if entering >= 0.0 and entering <= 1.0:
					time = entering
		if time < earliest:
			earliest = time
			first = {"index": crate["index"], "t": time, "position": start + delta * time}
	return first

func _same_sweep(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.is_empty() or expected.is_empty():
		return actual.is_empty() and expected.is_empty()
	return actual["index"] == expected["index"] and is_equal_approx(float(actual["t"]), float(expected["t"])) and (actual["position"] as Vector2).distance_to(expected["position"]) <= 0.01

func _indexed_fixture() -> ArenaInteractions:
	var points: Array[Vector2] = [Vector2(-128, -128), Vector2(128, 128), Vector2(127.9, -128.1),
		Vector2(-600, 850), Vector2(420, 300), Vector2(820, 300), Vector2(1600, 1000),
		Vector2(2100, -300), Vector2(360, 160), Vector2(950, 160), Vector2(440, 620), Vector2(840, 620)]
	var arena: Dictionary = {"id": "signed-cell-fixture", "obstacles": [{"id": "unrelated", "center": Vector2(300, 300), "radius": 50.0}], "crates": []}
	for index: int in points.size():
		(arena["crates"] as Array).append({"id": "cell_%d" % index, "center": points[index], "radius": 18.0, "max_health": 24.0, "art_id": "barrel"})
	var interactions := ArenaInteractions.new()
	interactions.configure(arena, 20261030, 1, ArenaObstacles.new())
	return interactions

func _test_indexed_crate_sweeps() -> void:
	var interactions: ArenaInteractions = _indexed_fixture()
	var before: Dictionary = interactions.snapshot()
	var crates: Array = before["crates"]
	var source_state: int = interactions._rng.state
	var random := RandomNumberGenerator.new()
	random.seed = 600128
	for padding: float in [0.0, 4.0, 16.0, 64.0, 64.01, 120.0]:
		for sample: int in 160:
			var start := Vector2(random.randf_range(-1200.0, 2500.0), random.randf_range(-650.0, 1400.0))
			var end: Vector2 = start + Vector2(random.randf_range(-10.0, 10.0), random.randf_range(-10.0, 10.0)) if sample % 2 == 0 else Vector2(random.randf_range(-1200.0, 2500.0), random.randf_range(-650.0, 1400.0))
			_check(_same_sweep(interactions.first_crate_hit(start, end, padding), _oracle_crate_hit(crates, start, end, padding)), "Indexed same-cell, cross-cell and large-padding sweeps equal an independent full-scan quadratic oracle")
		for crate: Dictionary in crates:
			var center: Vector2 = crate["position"]
			for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized()]:
				var start: Vector2 = center + direction * (18.0 + padding + 20.0)
				var end: Vector2 = center - direction * (18.0 + padding + 20.0)
				_check(_same_sweep(interactions.first_crate_hit(start, end, padding), _oracle_crate_hit(crates, start, end, padding)), "Signed cell boundaries retain exact radial contact and deterministic earliest identity")
	var center: Vector2 = crates[0]["position"]
	_check(interactions.first_crate_hit(center + Vector2(5, 0), center + Vector2(10, 0)).is_empty(), "An initially overlapping shot can leave a crate without a false collision")
	_check(interactions.first_crate_hit(center + Vector2(5, 0), center)["t"] == 0.0 and interactions.first_crate_hit(center, center + Vector2(10, 0)).is_empty(), "Entering an overlap hits immediately while exact-center departure retains its established semantics")
	for invalid: Dictionary in [{"start": Vector2.INF, "end": Vector2.ZERO, "padding": 0.0}, {"start": Vector2.ZERO, "end": Vector2.INF, "padding": 0.0}, {"start": Vector2.ZERO, "end": Vector2.ONE, "padding": NAN}, {"start": Vector2.ZERO, "end": Vector2.ONE, "padding": -1.0}, {"start": center, "end": center, "padding": 4.0}]:
		_check(interactions.first_crate_hit(invalid["start"], invalid["end"], invalid["padding"]).is_empty(), "Invalid and stationary crate sweeps preserve the no-hit contract")
	_check(interactions._region_candidates(Vector2i(-8, -4), Vector2i(-8, -4)).is_empty(), "A same-cell empty bucket has no static-prop or crate candidates")
	_check(interactions.snapshot() == before and interactions._rng.state == source_state, "Index population and all collision queries preserve gameplay state and the complete loot stream")
	interactions.damage_crate(0, 100.0)
	crates = interactions.snapshot()["crates"]
	for padding: float in [0.0, 64.0, 120.0]:
		var start: Vector2 = center + Vector2(-300, 0)
		var end: Vector2 = center + Vector2(300, 0)
		_check(_same_sweep(interactions.first_crate_hit(start, end, padding), _oracle_crate_hit(crates, start, end, padding)), "A disabled fixed slot is skipped by cached and full-scan candidates alike")
	for index: int in range(1, crates.size()):
		interactions.damage_crate(index, 100.0)
	_check(not interactions.has_active_crates() and interactions.first_crate_hit(Vector2(-1000, -400), Vector2(2300, 1200), 120.0).is_empty(), "Breaking the last crate enables a safe immediate empty fast path")
	interactions.configure(_arena(), 1, 2, interactions._obstacles)
	_check(interactions.has_active_crates() and interactions.first_crate_hit(Vector2(200, 300), Vector2(400, 300), 4.0)["index"] == 0 and interactions._crate_centers.size() == 1, "Reconfiguration rebuilds packed positions and active masks without stale indices")

func _test_nearby_damage_candidates() -> void:
	var interactions: ArenaInteractions = _indexed_fixture()
	var before: Dictionary = interactions.snapshot()
	var source_state: int = interactions._rng.state
	for origin: Vector2 in [Vector2.ZERO, Vector2(-128, -128), Vector2(640, 365), Vector2(950, 160), Vector2(2100, 1000)]:
		for reach: float in [0.0, 32.0, 112.0, 216.0, 900.0, 6000.0]:
			var candidates: Array[Dictionary] = interactions.damage_candidates(origin, reach)
			var actual: Array[int] = []
			for candidate: Dictionary in candidates:
				actual.append(int(candidate["index"]))
				_check(candidate.size() == 2 and candidate.has("position") and candidate["position"] == before["crates"][int(candidate["index"])]["position"], "Nearby damage queries expose only independent index and position records")
			var expected: Array[int] = []
			for crate: Dictionary in before["crates"]:
				var radius: float = reach + float(crate["radius"])
				if origin.distance_squared_to(crate["position"]) <= radius * radius + 0.01:
					expected.append(int(crate["index"]))
			_check(actual == expected, "Nearby active candidates match a full geometric bound without excluding any final shape target")
	var copy: Array[Dictionary] = interactions.damage_candidates(Vector2(950, 160), 0.0)
	copy[0]["position"] = Vector2.INF
	_check(interactions.snapshot() == before and interactions._rng.state == source_state and interactions.damage_candidates(Vector2.INF, 100.0).is_empty() and interactions.damage_candidates(Vector2.ZERO, NAN).is_empty() and interactions.damage_candidates(Vector2.ZERO, -1.0).is_empty(), "Damage candidates are pure copied queries with safe invalid-input handling")
	interactions.damage_crate(9, 100.0)
	_check(interactions.damage_candidates(Vector2(950, 160), 0.0).is_empty() and interactions.has_active_crates(), "Nearby damage candidates immediately omit a broken slot while preserving other live crates")
	for index: int in 1200:
		interactions.first_crate_hit(Vector2(-900, -400), Vector2(float(index + 10) * 128.0, -500), 4.0)
	_check(interactions._region_cache.size() <= ArenaInteractions.REGION_CACHE_LIMIT and interactions._empty_ids.is_empty(), "Cross-cell candidate caching stays bounded and never mutates its shared empty bucket")
	interactions.configure({"id": "empty", "obstacles": [], "crates": []}, 1, 1, interactions._obstacles)
	_check(not interactions.has_active_crates() and interactions.damage_candidates(Vector2.ZERO, 6000.0).is_empty() and interactions._crate_cells.is_empty() and interactions._region_cache.is_empty(), "An empty wave clears every crate-only spatial cache and active count")

func _test_crate_damage() -> void:
	var interactions: ArenaInteractions = _fixture()
	var before: Dictionary = interactions.snapshot()
	var random_state: int = interactions._rng.state
	for amount: float in [0.0, -1.0, INF, NAN]:
		_check(not interactions.damage_crate(0, amount)["hit"], "Nonpositive or nonfinite damage cannot hit a crate")
	_check(not interactions.damage_crate(-1, 24.0)["hit"] and not interactions.damage_crate(1, 24.0)["hit"] and interactions.snapshot() == before and interactions._rng.state == random_state, "Invalid damage preserves health, identity, topology, version and loot RNG")
	var hit: Dictionary = interactions.first_crate_hit(Vector2(200, 300), Vector2(400, 300), 4.0)
	_check(hit["index"] == 0 and is_equal_approx(float(hit["t"]), 78.0 / 200.0) and (hit["position"] as Vector2).is_equal_approx(Vector2(278, 300)), "Projectile sweep includes its own padding and exposes the actual impact position")
	var mixed: Dictionary = _arena()
	mixed["obstacles"] = [{"id": "low_cover", "center": Vector2(240, 300), "radius": 12.0, "art_id": "planter"}]
	var filtered := ArenaInteractions.new()
	filtered.configure(mixed, 1, 1, ArenaObstacles.new())
	_check(filtered.first_crate_hit(Vector2(200, 300), Vector2(400, 300), 4.0)["index"] == 0, "Flying crate queries reuse spatial candidates while preserving low-cover pass-through")
	var partial: Dictionary = interactions.damage_crate(0, 10.0)
	_check(partial["hit"] and not partial["broke"] and partial["drop"].is_empty() and interactions.snapshot()["crates"][0]["health"] == 14.0 and interactions._rng.state == random_state, "A nonlethal real hit changes health without consuming a drop roll")
	var broken: Dictionary = interactions.damage_crate(0, 100.0)
	var crate: Dictionary = interactions.snapshot()["crates"][0]
	_check(broken["hit"] and broken["broke"] and broken["position"] == Vector2(300, 300) and not crate["active"] and crate["health"] == 0.0 and crate["index"] == 0 and crate["uid"] == 1, "Lethal damage preserves the fixed crate slot and returns the authored center")
	_check(interactions._obstacles.is_free(Vector2(300, 300), 16.0) and interactions.first_crate_hit(Vector2(200, 300), Vector2(400, 300), 4.0).is_empty(), "The first break removes both ground and flying collision immediately")
	before = interactions.snapshot()
	random_state = interactions._rng.state
	for repeat: int in 8:
		_check(not interactions.damage_crate(0, 100.0)["hit"], "Repeated hits on a broken fixed slot cannot award a second drop")
	_check(interactions.snapshot() == before and interactions._rng.state == random_state, "Repeated breaking consumes neither loot RNG nor reward identity")
	interactions.advance(0.4)
	_check(interactions.snapshot()["crates"].size() == 1 and is_equal_approx(float(interactions.snapshot()["crates"][0]["break_age"]), 0.4), "Broken crates retain their slot and advance their full fragment-animation age")

func _break_signature(interactions: ArenaInteractions) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in (interactions.snapshot()["crates"] as Array).size():
		result.append((interactions.damage_crate(index, 100.0)["drop"] as Dictionary).duplicate(true))
	return result

func _test_drop_streams() -> void:
	var state := RunState.new()
	state.begin(20261030, "bone")
	var combat_rng := RandomNumberGenerator.new()
	combat_rng.seed = 33001
	var shop_state: int = state.rng.state
	var combat_state: int = combat_rng.state
	var first: ArenaInteractions = _fixture(77, 12)
	var second: ArenaInteractions = _fixture(77, 12)
	var drops: Array[Dictionary] = _break_signature(first)
	_check(drops == _break_signature(second) and first.snapshot() == second.snapshot(), "Identical environment seed, arena and wave produce identical one-time drops")
	_check(drops != _break_signature(_fixture(77, 12, 2)) and drops != _break_signature(_fixture(77, 12, 1, "other")), "Wave and arena identity each select an independent deterministic loot sequence")
	_check(state.rng.state == shop_state and combat_rng.state == combat_state, "Environment configuration and breaking do not advance shop or combat random streams")
	var seen: Dictionary = {}
	var dropped: int = 0
	for seed_value: int in range(1, 25):
		var sample: ArenaInteractions = _fixture(seed_value, 12)
		for drop: Dictionary in _break_signature(sample):
			if drop.is_empty():
				seen["empty"] = true
				continue
			dropped += 1
			seen[str(drop["kind"])] = true
			var kind: String = str(drop["kind"])
			_check(float(drop["value"]) in [1.0, 2.0, 3.0] if kind == "gold" else float(drop["value"]) == (8.0 if kind == "health" else 1.5), "Actual drops retain gold/health/charge reward amounts")
		_check((sample.snapshot()["pickups"] as Array).size() <= 12 and (sample.snapshot()["crates"] as Array).size() == 12, "A wave never exceeds its fixed reward or scenery pools")
	_check(ArenaInteractions.DROP_CHANCE == 0.60 and dropped > 100 and dropped < 250 and seen.has_all(["empty", "gold", "health", "charge"]), "Fixed seeded trials include misses and all three reward types under the sixty-percent rule")

func _reward_fixture() -> ArenaInteractions:
	for seed_value: int in range(1, 65):
		var interactions: ArenaInteractions = _fixture(seed_value)
		if not (interactions.damage_crate(0, 24.0)["drop"] as Dictionary).is_empty():
			return interactions
	return _fixture()

func _test_queries_and_collection() -> void:
	var interactions: ArenaInteractions = _reward_fixture()
	var before: Dictionary = interactions.snapshot()
	var random_state: int = interactions._rng.state
	var rewards: Array[Dictionary] = interactions.pickup_candidates(Vector2(300, 300), 0.0)
	_check(rewards.size() == 1 and interactions.pickup_candidates(Vector2(400, 300), 99.0).is_empty(), "Collection queries use the inclusive real pickup radius")
	var copy: Dictionary = interactions.snapshot()
	copy["crates"][0]["health"] = 999.0
	copy["pickups"][0]["value"] = -1.0
	rewards[0]["value"] = -2.0
	_check(interactions.snapshot() == before and interactions.pickup_candidates(Vector2(300, 300), 0.0)[0]["value"] > 0.0 and interactions._rng.state == random_state, "Snapshots and candidate lists are detached pure queries that do not consume a pickup")
	for delta: float in [0.0, -1.0, INF, NAN]:
		interactions.advance(delta)
	_check(interactions.snapshot() == before and interactions._rng.state == random_state, "Invalid time cannot age scenery or consume RNG")
	interactions.advance(1.0)
	_check(interactions.snapshot()["crates"][0]["break_age"] == 1.0 and interactions.snapshot()["pickups"][0]["age"] == 1.0 and interactions._rng.state == random_state, "A valid step ages retained fragments and uncollected rewards without randomness")
	var uid: int = int(interactions.snapshot()["pickups"][0]["uid"])
	_check(interactions.consume_pickup(uid) and not interactions.consume_pickup(uid) and not interactions.consume_pickup(-1) and interactions.pickup_candidates(Vector2(300, 300), 1000.0).is_empty(), "Explicit accepted collection consumes one reward exactly once")
	interactions.configure(_arena(), 44, 2, interactions._obstacles)
	_check(interactions.snapshot()["crates"][0]["active"] and interactions.snapshot()["crates"][0]["health"] == 24.0 and interactions.snapshot()["pickups"].is_empty() and not interactions._obstacles.is_free(Vector2(300, 300), 16.0), "The next wave resets health, fragment age, reward pool and real collision together")

func _test_configuration_limits() -> void:
	var arena: Dictionary = _arena(20)
	var interactions := ArenaInteractions.new()
	var field := ArenaObstacles.new()
	interactions.configure(arena, 1, 1, field)
	_check(interactions.snapshot()["crates"].size() == ArenaInteractions.MAX_CRATES and field.snapshot().size() == ArenaInteractions.MAX_CRATES, "Oversized input cannot exceed twelve fixed crate colliders")
	arena = _arena()
	(arena["crates"] as Array).append((arena["crates"][0] as Dictionary).duplicate(true))
	(arena["crates"] as Array).append({"id": "invalid", "center": Vector2.INF})
	interactions.configure(arena, 1, 1, field)
	_check(interactions.snapshot()["crates"].size() == 1 and field.snapshot().size() == 1, "Duplicate identity and invalid geometry cannot create visual-only crate slots")
