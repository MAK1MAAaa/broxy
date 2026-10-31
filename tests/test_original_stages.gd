extends SceneTree
## Original layer-0 geometry, exact pixels, composite collision and real routes.

var _checks: int = 0
var _failures: int = 0

class SilentSound extends SoundBank:
	func _ready() -> void:
		pass
	func play(_name: String, _loudness: float = -10.0) -> void:
		pass
	func play_cue(_name: String, _loudness: float, _cue_id: String) -> void:
		pass

class WorldProbe extends CombatWorld:
	func _movement() -> Vector2:
		return Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_test_catalog_and_source_transform()
	_test_source_art()
	_test_composite_collision()
	_test_bounded_projection()
	_test_navigation()
	_test_actual_stage_routes()
	_test_spawn_and_boss_integration()
	_test_original_wall_dash()
	_test_enemy_route_integration()
	_test_legacy_camera_values()
	_test_minimap_wall_clipping()
	await _test_world_hud_integration()
	print("OriginalStages: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _field(id: String) -> ArenaObstacles:
	var result := ArenaObstacles.new()
	result.bounds = ArenaCatalog.play_bounds(id)
	result.configure(ArenaCatalog.definition(id)["obstacles"])
	_check(result.configure_walls(ArenaCatalog.wall_geometry(id)), "The source wall geometry configures without substitutes: " + id)
	return result


func _test_catalog_and_source_transform() -> void:
	_check(ArenaCatalog.IDS.size() == 10 and ArenaCatalog.ORIGINAL_STAGE_IDS.size() == 3 and ArenaCatalog.LEGACY_IDS.size() == 7, "Three original stages append to the seven preserved arenas")
	for id: String in ArenaCatalog.LEGACY_IDS:
		_check(ArenaCatalog.play_bounds(id) == ArenaCatalog.WORLD_BOUNDS and ArenaCatalog.wall_geometry(id).is_empty() and ArenaCatalog.stage_info(id).is_empty(), "Legacy arenas keep their exact bounds and empty-wall fast path: " + id)
	_check(ArenaCatalog.play_bounds("unknown") == ArenaCatalog.WORLD_BOUNDS and ArenaCatalog.wall_geometry("unknown").is_empty(), "Unknown arena geometry uses the unchanged safe fallback")
	var normalized: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ArenaCatalog.LAYOUT_PATH))
	var sources: Dictionary = {}
	for layout: Dictionary in normalized["layouts"]:
		sources[layout["id"]] = layout
	var expected: Dictionary = {"jp_sand_2_9_5": ["main_2_9_5", "sand_ruins", 3, Vector2(96, -275)],
		"jp_shrine_6_6_2": ["main_6_6_2", "japan_shrine", 6, Vector2(96, -275)],
		"jp_ship_3_6_2": ["main_3_6_2", "sea_ship_boss", 8, Vector2(96, -811)]}
	for id: String in ArenaCatalog.ORIGINAL_STAGE_IDS:
		var info: Dictionary = ArenaCatalog.stage_info(id)
		var definition: Dictionary = ArenaCatalog.definition(id)
		var bounds: Rect2 = ArenaCatalog.play_bounds(id)
		var walls: Array[Dictionary] = ArenaCatalog.wall_geometry(id)
		_check(bounds == Rect2(280, -275, 720, 1280) and bounds.get_center() == ArenaCatalog.WORLD_BOUNDS.get_center(), "The original 180x320 viewport uses uniform 4x pixels at the unchanged world center: " + id)
		_check(info["layout_id"] == expected[id][0] and info["field_id"] == expected[id][1] and int(info["layer_index"]) == 0, "Playable stage names the exact matching final-JP reference and original layer: " + id)
		_check(absf(float(info["logic_scale"]) - 2.0 / 3.0) < 0.000000001 and _point(info["logic_offset"]) == expected[id][3], "Geometry uses one exact scale and the field-specific translation: " + id)
		_check(walls.size() == int(expected[id][2]), "Every original adjacent wall segment is retained without an inferred closing edge: " + id)
		_check(definition["zones"].is_empty() and definition["crates"].is_empty() and definition["obstacles"].is_empty(), "Unknown original prop definitions do not become invented crates or generic colliders: " + id)
		var original: Array = sources[info["layout_id"]]["layers"][0]["walls"]
		for index: int in original.size():
			for end: String in ["a", "b"]:
				for axis: int in 2:
					var expected_coordinate: float = float(original[index][end][axis]) * (2.0 / 3.0) + float(info["logic_offset"][axis])
					_check(absf(float(walls[index][end][axis]) - expected_coordinate) < 0.000000001, "Actual imported endpoints share the background's uniform transform")
		var field: ArenaObstacles = _field(id)
		_check(field.is_free(bounds.get_center(), 16, 16), "The unchanged hero spawn is genuinely clear in the original layout: " + id)
		walls[0]["a"][0] = -99999
		info["logic_offset"][0] = 99999
		_check(float(ArenaCatalog.wall_geometry(id)[0]["a"][0]) > -99999 and float(ArenaCatalog.stage_info(id)["logic_offset"][0]) == 96, "Callers cannot corrupt cached source transforms")


func _test_source_art() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/worldflipper/stages/manifest.json"))
	_check(manifest.get("revision") == "world-flipper-original-stages-01" and manifest["assets"].size() == 6 and manifest["stages"].size() == 3, "Original-stage art has an independent six-PNG provenance manifest")
	var assets: Dictionary = {}
	for asset: Dictionary in manifest["assets"]:
		assets[asset["id"]] = asset
	for id: String in ArenaCatalog.ORIGINAL_STAGE_IDS:
		var texture := load(ArenaCatalog.texture_path(id)) as Texture2D
		var preview := load(ArenaCatalog.preview_path(id)) as Texture2D
		_check(texture != null and preview != null, "Both source stage textures are engine-importable: " + id)
		if texture == null or preview == null:
			continue
		_check(texture.get_size() == Vector2(3780, 2192) and preview.get_size() == Vector2(1280, 720), "Original stages use the same full canvas and exact camera preview dimensions")
		_check(FileAccess.get_sha256(ArenaCatalog.texture_path(id)) == assets[id]["sha256"] and FileAccess.get_sha256(ArenaCatalog.preview_path(id)) == assets[id + "_preview"]["sha256"], "The independent manifest describes the actual shipped stage bytes")
		var image: Image = texture.get_image()
		_check(image.get_region(Rect2i(1146, 772, 1280, 720)).get_data() == preview.get_image().get_data(), "The stage preview is the untouched start-camera crop")
		var original_crop: Image = image.get_region(Rect2i(1426, 492, 720, 1280))
		var integer_pixels: bool = true
		for y: int in range(0, original_crop.get_height(), 4):
			for x: int in range(0, original_crop.get_width(), 4):
				var color: Color = original_crop.get_pixel(x, y)
				for dy: int in 4:
					for dx: int in 4:
						integer_pixels = integer_pixels and color == original_crop.get_pixel(x + dx, y + dy)
		_check(integer_pixels, "Every original stage pixel remains an exact 4x4 block without interpolation or anisotropic stretching: " + id)


func _test_composite_collision() -> void:
	var field := ArenaObstacles.new()
	field.bounds = Rect2(0, 0, 400, 400)
	field.configure([{"id": "circle", "center": [150, 200], "radius": 25}])
	_check(field.configure_walls([{"id": "source", "a": [250, 80], "b": [250, 320]}]), "Circle and actual segment geometry compose in the same field")
	var from_left: Dictionary = field.first_hit(Vector2(50, 200), Vector2(300, 0), 10)
	_check(from_left.get("id") == "circle" and absf(float(from_left.get("t", 0)) - 65.0 / 300.0) < 0.00001, "The nearer circle wins before a later wall")
	var from_right: Dictionary = field.first_hit(Vector2(350, 200), Vector2(-300, 0), 10)
	_check(from_right.get("art_id") == "wall" and absf(float(from_right.get("t", 0)) - 0.3) < 0.00001, "The nearer exact wall wins before a later circle")
	_check(from_right.get("index") == -1 and from_right.get("source_id") == "source", "Wall hits retain original segment identity without impersonating a crate index")
	_check(not field.segment_clear(Vector2(50, 200), Vector2(350, 200), 10), "Visibility cannot pass through either collider family")
	var moved: Vector2 = field.move_body(Vector2(50, 200), Vector2(300, 0), 10)
	_check(moved.x <= 115.001 and field.is_free(moved, 10), "Composite movement stops before its earliest continuous collision")
	field.set_active("circle", false)
	var without_circle: Dictionary = field.first_hit(Vector2(50, 200), Vector2(300, 0), 10)
	_check(without_circle.get("art_id") == "wall" and absf(float(without_circle.get("t", 0)) - 190.0 / 300.0) < 0.00001, "Removing a destructible circle preserves the independent wall geometry")
	var clipped: Vector2 = field.move_body(Vector2(350, 200), Vector2(600, 0), 10, 10)
	_check(clipped.x <= 390.001 and clipped.x > 389.9 and field.is_free(clipped, 10, 10), "New-stage movement also respects the per-map physical bounds")
	var before: Array[Dictionary] = field.walls.snapshot()
	_check(not field.configure_walls([{"a": [NAN, 0], "b": [1, 1]}]) and field.walls.snapshot() == before, "Malformed wall replacement cannot erase valid collision or navigation geometry")
	field.configure([])
	_check(field.walls.snapshot().is_empty() and field.segment_clear(Vector2(50, 200), Vector2(350, 200), 10), "A full scene rebuild clears walls before the next map is configured")


func _test_bounded_projection() -> void:
	var field := ArenaObstacles.new()
	field.bounds = Rect2(0, 0, 400, 400)
	field.configure_walls([{"a": [0, 0], "b": [0, 400]}])
	var point: Vector2 = field.free_point(Vector2(0, 200), 16)
	_check(field.is_free(point, 16) and point.distance_to(Vector2(16, 200)) < 0.1, "A wall on the bounds projects inward locally rather than oscillating or teleporting outside")
	field.configure([{"center": [200, 112], "radius": 6}])
	field.configure_walls([{"a": [0, 100], "b": [400, 100]}])
	point = field.free_point(Vector2(200, 106), 6)
	_check(field.is_free(point, 6) and point.distance_to(Vector2(200, 106)) < 10.6, "Nearest feasible composite projection uses the real line-circle intersection")
	var intervals: Array[Rect2] = field.clear_spawn_segments([Rect2(Vector2(0, 100), Vector2(400, 0))], 6)
	_check(intervals.is_empty(), "A spawn interval lying along an entire wall is removed exactly")
	intervals = field.clear_spawn_segments([Rect2(Vector2(200, 0), Vector2(0, 400))], 6)
	var has_above: bool = false
	var has_below: bool = false
	var clear: bool = true
	for segment: Rect2 in intervals:
		clear = clear and field.segment_clear(segment.position, segment.end, 6)
		has_above = has_above or segment.position.y < 90
		has_below = has_below or segment.end.y > 130
	_check(clear and has_above and has_below, "Analytic spawn clipping retains both genuinely clear sides of a wall/circle crossing")


func _safe_path(field: ArenaObstacles, path: PackedVector2Array, radius: float) -> bool:
	if path.size() < 2:
		return false
	for index: int in range(1, path.size()):
		if not field.is_free(path[index], radius) or not field.segment_clear(path[index - 1], path[index], radius):
			return false
	return true


func _test_navigation() -> void:
	var field := ArenaObstacles.new()
	field.bounds = Rect2(0, 0, 400, 400)
	field.configure([{"id": "circle", "center": [200, 340], "radius": 16}])
	field.configure_walls([{"id": "wall", "a": [200, 100], "b": [200, 300]}])
	var start := Vector2(50, 200)
	var goal := Vector2(350, 200)
	var path: PackedVector2Array = field._build_route(start, goal, 10)
	_check(path.size() > 2 and _safe_path(field, path, 10), "The visibility graph finds a genuine route around a wall end while respecting nearby circles and bounds")
	var position: Vector2 = start
	for _step: int in 160:
		var target: Vector2 = field.next_target(position, goal, 10, 101)
		if target == position:
			break
		var movement: Vector2 = (target - position).limit_length(8)
		position = field.move_body(position, movement, 10)
	_check(position.distance_to(goal) < 8.1 and field.is_free(position, 10), "An actual moving body follows legal cached wall-end waypoints to its goal")
	_check(int(field.navigation_stats()["graphs_built"]) == 1, "Wall navigation shares one static graph for a body radius")
	field.configure_walls([])
	_check(field.segment_clear(start, goal, 10) and field.next_target(start, goal, 10, 102) == goal, "Removing a wall invalidates blocked routes and their projected-goal cache")


func _test_actual_stage_routes() -> void:
	for id: String in ArenaCatalog.ORIGINAL_STAGE_IDS:
		var field: ArenaObstacles = _field(id)
		var rows: Array[Dictionary] = ArenaCatalog.wall_geometry(id)
		var longest: Dictionary = rows[0]
		for row: Dictionary in rows:
			if _point(row["a"]).distance_squared_to(_point(row["b"])) > _point(longest["a"]).distance_squared_to(_point(longest["b"])):
				longest = row
		var a: Vector2 = _point(longest["a"])
		var b: Vector2 = _point(longest["b"])
		var middle: Vector2 = (a + b) * 0.5
		var tangent: Vector2 = (b - a).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var start: Vector2 = middle + normal * 12
		var end: Vector2 = middle - normal * 12
		var hit: Dictionary = field.first_hit(start, end - start, 4)
		_check(hit.get("art_id") == "wall" and absf(float(hit.get("t", 0)) - 1.0 / 3.0) < 0.00001, "The composed field continuously collides against actual scaled original source coordinates: " + id)
		_check(field.is_free(field.move_body(start, end - start, 4), 4), "Swept source-stage movement cannot cross the real wall: " + id)
	var field: ArenaObstacles = _field("jp_sand_2_9_5")
	var start := Vector2(640, 365)
	var goal := Vector2(295, 365)
	var path: PackedVector2Array = field._build_route(start, goal, 10)
	_check(path.size() > 2 and _safe_path(field, path, 10), "The original ruins' lower opening remains navigable around its real unclosed wall")
	var bottom := Vector2(640, 980)
	_check(field.segment_clear(start, bottom, 16), "The original ruins bottom exit stays genuinely open inside its play envelope")


func _sim_stage(id: String, seed_value: int = 20261031, wave: int = 1) -> CombatSim:
	var state := RunState.new()
	state.begin(seed_value, "bone", id)
	state.wave = wave
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.invulnerability = 1000.0
	sim._cooldowns.fill(9999.0)
	return sim


func _inside(area: Rect2, point: Vector2) -> bool:
	return point.is_finite() and point.x >= area.position.x and point.x <= area.end.x and point.y >= area.position.y and point.y <= area.end.y


func _test_spawn_and_boss_integration() -> void:
	for id: String in ArenaCatalog.ORIGINAL_STAGE_IDS:
		var bounds: Rect2 = ArenaCatalog.play_bounds(id)
		for seed_value: int in [7, 19, 73, 101]:
			for y: float in [bounds.position.y + 16, bounds.get_center().y, bounds.end.y - 16]:
				var sim: CombatSim = _sim_stage(id, seed_value)
				var mirror: CombatSim = _sim_stage(id, seed_value)
				var point: Vector2 = sim.obstacles.free_point(Vector2(bounds.get_center().x, y), 16, 16)
				sim.player_position = point
				mirror.player_position = point
				var view: Rect2 = ArenaCatalog.visible_rect_for(id, point)
				_check(sim.obstacles.bounds == bounds and sim.obstacles.is_free(point, 16, 16), "The production simulation uses each real stage's bounds and a genuinely free player position")
				var safe: bool = true
				var hidden: bool = true
				var deterministic: bool = true
				for enemy_id: String in ["chaser", "tank", "caster", "rusher", "chaser", "tank", "caster", "rusher"]:
					var enemy: CombatSim.Enemy = sim.spawn_enemy(enemy_id)
					var same: CombatSim.Enemy = mirror.spawn_enemy(enemy_id)
					_check(enemy != null and same != null, "Real stage spawn factories return active enemies")
					if enemy == null or same == null:
						continue
					safe = safe and _inside(bounds.grow(-CombatSim.SPAWN_INSET), enemy.position) and sim.obstacles.is_free(enemy.position, enemy.radius)
					hidden = hidden and not view.grow(24).has_point(enemy.position)
					deterministic = deterministic and enemy.position == same.position
					enemy.action_timer = 9999.0
				_check(safe and hidden, "Multi-seed center/top/bottom spawns stay free inside the actual bounds and outside the current camera: %s seed=%d y=%.0f" % [id, seed_value, y])
				_check(deterministic and sim.rng.state == mirror.rng.state, "Wall clipping preserves deterministic production spawn positions and RNG")
				sim.step(1.0 / 60.0, Vector2.ZERO)
				for enemy: CombatSim.Enemy in sim.enemies:
					if enemy.active:
						_check(_inside(bounds, enemy.position) and sim.obstacles.is_free(enemy.position, enemy.radius), "Actual enemy updates retain legal source-stage positions")
		var boss_sim: CombatSim = _sim_stage(id, 20261101, 8)
		_check(boss_sim.boss != null and boss_sim.boss.active and _inside(bounds, boss_sim.boss.position) and boss_sim.obstacles.is_free(boss_sim.boss.position, boss_sim.boss.radius), "An actual boss wave begins with its boss inside the source stage and clear of the real walls: " + id)
		if boss_sim.boss != null:
			boss_sim.boss.action_timer = 9999.0
			boss_sim.step(0.2, Vector2.ZERO)
			_check(_inside(bounds, boss_sim.boss.position) and boss_sim.obstacles.is_free(boss_sim.boss.position, boss_sim.boss.radius), "The real boss update respects the source-stage geometry: " + id)


func _test_original_wall_dash() -> void:
	for id: String in ArenaCatalog.ORIGINAL_STAGE_IDS:
		var sim: CombatSim = _sim_stage(id)
		var rows: Array[Dictionary] = ArenaCatalog.wall_geometry(id)
		var longest: Dictionary = rows[0]
		for row: Dictionary in rows:
			if _point(row["a"]).distance_squared_to(_point(row["b"])) > _point(longest["a"]).distance_squared_to(_point(longest["b"])):
				longest = row
		var a: Vector2 = _point(longest["a"])
		var b: Vector2 = _point(longest["b"])
		var middle: Vector2 = (a + b) * 0.5
		var tangent: Vector2 = (b - a).normalized()
		var inward := Vector2(-tangent.y, tangent.x)
		if inward.dot(sim.obstacles.bounds.get_center() - middle) < 0.0:
			inward = -inward
		sim.player_position = middle + inward * 64.0
		sim.player_direction = -inward
		var echoes: Array[Dictionary] = []
		sim.pinball_bounced.connect(func(point: Vector2, normal: Vector2, _boosted: bool, _combo: int) -> void: echoes.append({"point": point, "normal": normal}))
		_check(sim.obstacles.is_free(sim.player_position, 16, 16) and sim.obstacles.snapshot().is_empty(), "The dash fixture starts clear and contains real source walls without fake bumpers")
		var combat_rng: int = sim.rng.state
		var run_rng: int = sim.run.rng.state
		sim.step(0.12, Vector2.ZERO, true)
		var ball: Dictionary = sim.pinball_snapshot()
		_check(ball["active"] and int(ball["bounces"]) == 1 and sim.dashes_used == 1 and echoes.size() == 1, "A real Sim.step dash against an original wall enters one ball state and emits one bounce: " + id)
		_check(sim.player_velocity.dot(inward) > 0.0 and (sim.player_position - middle).dot(inward) >= 16.0 and sim.obstacles.is_free(sim.player_position, 16, 16), "Original-wall ball reflection remains on the original side with a real outward velocity: " + id)
		_check(sim.rng.state == combat_rng and sim.run.rng.state == run_rng, "Original-wall dash and reflection consume no combat or inventory RNG")
		sim.step(1.0 / 60.0, Vector2.ZERO)
		_check(sim.pinball_snapshot()["active"] and sim.obstacles.is_free(sim.player_position, 16, 16), "The reflected ball continues safely on subsequent production ticks")


func _test_enemy_route_integration() -> void:
	var sim: CombatSim = _sim_stage("jp_sand_2_9_5")
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", Vector2(295, 365))
	_check(enemy != null and sim.obstacles.is_free(enemy.position, enemy.radius) and not sim.obstacles.segment_clear(enemy.position, sim.player_position, enemy.radius), "A real chaser begins outside the original ruins wall with no illegal direct shortcut")
	if enemy == null:
		return
	enemy.action_timer = 9999.0
	var legal: bool = true
	var maximum_y: float = enemy.position.y
	var closest: float = INF
	for _frame: int in 900:
		sim.step(1.0 / 30.0, Vector2.ZERO)
		legal = legal and enemy.active and sim.obstacles.is_free(enemy.position, enemy.radius) and _inside(sim.obstacles.bounds, enemy.position)
		maximum_y = maxf(maximum_y, enemy.position.y)
		closest = minf(closest, enemy.position.distance_to(sim.player_position))
		if closest < 30.0:
			break
	_check(legal and maximum_y > 780.0 and closest < 30.0, "Production enemy AI follows the real lower wall opening, never crosses its capsule, and reaches the player")


func _test_legacy_camera_values() -> void:
	var bounds: Rect2 = ArenaCatalog.WORLD_BOUNDS
	var points: Array[Vector2] = [bounds.get_center(), bounds.position, bounds.end, Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end.x, bounds.position.y), Vector2.INF]
	for id: String in ArenaCatalog.LEGACY_IDS:
		for point: Vector2 in points:
			for view_size: Vector2 in [Vector2(1280, 720), Vector2(960, 540), Vector2.INF]:
				_check(ArenaCatalog.camera_center_for(id, point, view_size) == ArenaCatalog.camera_center(point, view_size) and ArenaCatalog.visible_rect_for(id, point, view_size) == ArenaCatalog.visible_rect(point, view_size), "All seven legacy cameras keep exact old center/corner/fallback arithmetic at every supported view size")


func _test_minimap_wall_clipping() -> void:
	var map := MinimapView.new()
	map.size = Vector2(192, 126)
	var bounds: Rect2 = ArenaCatalog.play_bounds("jp_sand_2_9_5")
	var center: Vector2 = bounds.get_center()
	map.update_snapshot({"bounds": bounds, "player": center, "view": ArenaCatalog.visible_rect_for("jp_sand_2_9_5", center),
		"walls": [{"a": [bounds.position.x - 100, center.y], "b": [bounds.end.x + 100, center.y]},
			{"a": [center.x, bounds.position.y - 100], "b": [center.x, bounds.end.y + 100]},
			{"a": [bounds.position.x, bounds.position.y - 100], "b": [bounds.end.x, bounds.position.y - 100]},
			{"a": [NAN, 0], "b": [0, 0]}]})
	var snapshot: Dictionary = map.presentation_snapshot()
	_check(int(snapshot["wall_count"]) == 2, "Minimap clipping retains crossing walls and rejects entirely external/nonfinite segments")
	var horizontal: bool = false
	var vertical: bool = false
	for wall: Dictionary in snapshot["walls"]:
		var a: Vector2 = wall["a"]
		var b: Vector2 = wall["b"]
		_check(_inside(bounds, a) and _inside(bounds, b), "All minimap wall endpoints lie inside the exact playable portrait envelope")
		horizontal = horizontal or (is_equal_approx(a.y, center.y) and is_equal_approx(b.y, center.y) and absf(a.x - b.x) == bounds.size.x)
		vertical = vertical or (is_equal_approx(a.x, center.x) and is_equal_approx(b.x, center.x) and absf(a.y - b.y) == bounds.size.y)
	_check(horizontal and vertical, "Clipping intersects actual wall lines with the boundary instead of clamping unrelated endpoints")
	var area: Rect2 = map.map_rect()
	_check(absf(area.size.x / area.size.y - 9.0 / 16.0) < 0.00001 and map.world_to_map(bounds.position).is_equal_approx(area.position) and map.world_to_map(bounds.end).is_equal_approx(area.end), "Portrait minimaps preserve the true 720x1280 aspect ratio and both corners")
	map.free()


func _settle() -> void:
	for _frame: int in 4:
		await process_frame


func _test_world_hud_integration() -> void:
	var sound := SilentSound.new()
	root.add_child(sound)
	for id: String in ArenaCatalog.ORIGINAL_STAGE_IDS:
		var state := RunState.new()
		state.begin(20261031, "bone", id)
		var world := WorldProbe.new()
		world.sound = sound
		root.add_child(world)
		world.set_physics_process(false)
		world.begin(state)
		world.sim.sandbox = true
		world.sim.invulnerability = 1000.0
		world.sim._cooldowns.fill(9999.0)
		var ui := GameUI.new()
		root.add_child(ui)
		ui.bind(state)
		ui.show_hud()
		ui.update_hud(world.hud_snapshot())
		await _settle()
		var bounds: Rect2 = ArenaCatalog.play_bounds(id)
		var wall_count: int = ArenaCatalog.wall_geometry(id).size()
		_check(world.sim.obstacles.bounds == bounds and world.arena_texture != null and world.arena_texture.resource_path == ArenaCatalog.texture_path(id), "A real CombatWorld.begin loads the selected original stage and its live collision bounds")
		_check(world.sim.interactions.snapshot()["crates"].is_empty() and world.interaction_presentation_snapshot()["crates"].is_empty() and world._arena_obstacles.is_empty(), "Source-stage runtime and rendering contain no invented crates or legacy prop cache")
		world._grounding_painter.rebuild(world.sim, world.camera_view())
		var grounding: Dictionary = world._grounding_painter.get_stats()
		var shadow: Array[Dictionary] = world._grounding_painter.geometry_snapshot()
		_check(int(grounding["player_count"]) == 1 and int(grounding["enemy_count"]) == 0 and int(grounding["pickup_count"]) == 0 and int(grounding["active_count"]) == 1 and shadow.size() == 1 and shadow[0]["position"] == world.sim.player_position + Vector2(0, 12), "A source-stage world grounds the actual hero foot without creating fake scenery shadows")
		var map: MinimapView = ui._hud["minimap"] as MinimapView
		var map_rect: Rect2 = map.get_global_rect()
		for y: float in [bounds.position.y + 16, bounds.get_center().y, bounds.end.y - 16]:
			world.sim.player_position = world.sim.obstacles.free_point(Vector2(bounds.get_center().x, y), 16, 16)
			world._physics_process(1.0 / 60.0)
			var snapshot: Dictionary = world.minimap_snapshot()
			var combat_rng: int = world.sim.rng.state
			var run_rng: int = state.rng.state
			ui.update_hud(world.hud_snapshot())
			await _settle()
			var projected: Dictionary = map.presentation_snapshot()
			_check(snapshot["bounds"] == bounds and snapshot["walls"].size() == wall_count and projected["bounds"] == bounds and int(projected["wall_count"]) == wall_count, "The real world/HUD/minimap chain retains every original wall segment and the exact stage bounds")
			_check(world.camera_view() == ArenaCatalog.visible_rect_for(id, world.sim.player_position) and world._camera.position == ArenaCatalog.camera_center_for(id, world.sim.player_position), "The production camera and snapshot use the same stage-aware view")
			var screen: Vector2 = world.sim.player_position - world.camera_view().position
			var body := Rect2(screen - Vector2(61, 61), Vector2(122, 122))
			var status := ui.find_child("RitualStatus", true, false) as Control
			var equipment := ui.find_child("RitualEquipment", true, false) as Control
			var abilities := ui.find_child("RitualAbilities", true, false) as Control
			var vitals := ui.find_child("PlayerVitals", true, false) as Control
			_check(screen.y >= 248.0 and screen.y <= 544.0 and not body.intersects(map_rect) and not body.intersects(status.get_global_rect()) and not body.intersects(equipment.get_global_rect()) and not body.intersects(abilities.get_global_rect()) and not body.intersects(vitals.get_global_rect()), "At the real top/bottom edges the player body and orbit remain clear of the actual HUD panels")
			_check(map.get_global_rect() == map_rect and absf(map.map_rect().size.x / map.map_rect().size.y - 9.0 / 16.0) < 0.00001, "Camera travel leaves the actual HUD minimap fixed while preserving portrait map proportions")
			_check(map.get_child_count() == 0 and map.mouse_filter == Control.MOUSE_FILTER_IGNORE and map.focus_mode == Control.FOCUS_NONE, "The real minimap remains geometric, without explanatory labels, legend children, or focus targets")
			snapshot["walls"].clear()
			projected["walls"].clear()
			_check(world.sim.obstacles.walls.snapshot().size() == wall_count and int(map.presentation_snapshot()["wall_count"]) == wall_count and world.sim.rng.state == combat_rng and state.rng.state == run_rng, "Returned wall projections cannot mutate live geometry or consume gameplay randomness")
		ui.queue_free()
		world.stop()
		world.queue_free()
		await process_frame
	sound.queue_free()
	await process_frame
