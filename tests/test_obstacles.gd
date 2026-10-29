extends SceneTree
## Real ground movement, deterministic navigation and flying attacks share authored cover.

const STEP: float = 1.0 / 60.0
const ROCK: Vector2 = Vector2(640, 365)
const SKILL_FIXTURE = preload("res://tests/skill_fixture.gd")
var _checks: int = 0
var _failures: int = 0

class ProjectionProbe extends ArenaObstacles:
	var projection_calls: int = 0
	func free_point(point: Vector2, body_radius: float = 0.0, inset: float = 0.0) -> Vector2:
		projection_calls += 1
		return super.free_point(point, body_radius, inset)


func _initialize() -> void:
	_test_authored_layouts()
	_test_geometry_and_projection()
	_test_index_boundaries()
	_test_shared_projection()
	_test_player_and_dash()
	_test_push_and_recoil()
	_test_enemy_routes()
	_test_locked_charge()
	_test_spawns_and_randomness()
	_test_boss_summons_and_drops()
	_test_flying_shots()
	print("Obstacles: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)


func _sim(arena: String = "reliquary", isolated: bool = true) -> CombatSim:
	var state := RunState.new()
	state.begin(20261029, "bone", arena)
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	if isolated:
		sim.obstacles.configure([{"id": "fixture", "center": ROCK, "radius": 40.0, "art_id": "monument"}])
		sim.player_position = ROCK + Vector2(-160, 0)
	return sim


func _test_authored_layouts() -> void:
	var names: Array[String] = ["沙漠遗迹", "和风神社", "魔界高塔", "海盗船"]
	var terrain: Array[String] = ["石板", "湿苔", "秘纹", "碎木"]
	var multipliers: Array[float] = [1.0, 0.72, 0.84, 0.88]
	for index: int in ArenaCatalog.IDS.size():
		var id: String = ArenaCatalog.IDS[index]
		var data: Dictionary = ArenaCatalog.definition(id)
		var sim: CombatSim = _sim(id, false)
		var items: Array[Dictionary] = sim.obstacles.snapshot()
		_check(data["name"] == names[index] and data["terrain_name"] == terrain[index] and is_equal_approx(float(data["move_multiplier"]), multipliers[index]), "Each existing map keeps its movement rule with the new original-art theme: " + id)
		_check(items.size() >= 8 and items.size() <= 10, "Each map has a bounded authored cover layout: " + id)
		_check(sim.player_position == ROCK and sim.obstacles.is_free(ROCK, 16.0), "The original central spawn stays unchanged and clear: " + id)
		for first: int in items.size():
			var item: Dictionary = items[first]
			var center: Vector2 = item["center"]
			var radius: float = float(item["radius"])
			_check(["monument", "planter", "bumper"].has(item["art_id"]) and radius >= 28.0 and radius <= 52.0, "Cover references one low original prop and a small ground footprint: " + id)
			_check(center.distance_to(ROCK) - radius >= 240.0 and center.distance_to(Vector2(640, 208)) - radius >= 160.0, "Player and boss openings keep their full safe areas: " + id)
			_check(CombatSim.ARENA.grow(-180.0).encloses(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)), "Cover leaves wide world-edge and spawn corridors: " + id)
			for second: int in range(first + 1, items.size()):
				_check(center.distance_to(items[second]["center"]) - radius - float(items[second]["radius"]) >= 180.0, "Separated cover cannot create a closed wall or a boss-sized dead end: " + id)
		items[0]["center"] = Vector2.INF
		_check((sim.obstacles.snapshot()[0]["center"] as Vector2).is_finite(), "Presentation copies cannot mutate collision geometry: " + id)


func _test_geometry_and_projection() -> void:
	var sim: CombatSim = _sim()
	var field: ArenaObstacles = sim.obstacles
	var safe: Vector2 = field.free_point(ROCK, 22.0)
	_check(field.is_free(safe, 22.0) and safe.x > ROCK.x and safe.y == ROCK.y, "Coincident positions escape to one deterministic safe side")
	_check(field.free_point(Vector2.INF, 16.0).is_finite() and not field.is_free(Vector2.INF), "Invalid source coordinates never reach collision arithmetic")
	var start: Vector2 = ROCK + Vector2(-100, 0)
	var result: Vector2 = field.move_body(start, Vector2(1000, 0), 16.0)
	_check(result.x < ROCK.x - 55.9 and field.is_free(result, 16.0), "A swept move cannot tunnel through a circle even when both endpoints are clear")
	start = ROCK + Vector2(-100, -35)
	result = field.move_body(start, Vector2(200, 0), 16.0)
	_check(field.is_free(result, 16.0) and result.x > ROCK.x - 40.0 and result.y < start.y, "Glancing movement slides around the ground footprint")
	_check(field.move_body(result, Vector2(-20, -20), 16.0).distance_to(result) > 20.0, "A body can immediately leave a touching surface without sticky contact")
	var before: Array = [sim.rng.state, sim.run.rng.state]
	for repeat: int in 3:
		field.next_target(ROCK + Vector2(-180, 0), ROCK + Vector2(180, 0), 22.0, repeat)
	_check(before == [sim.rng.state, sim.run.rng.state], "Geometry, graph construction and route queries consume neither gameplay RNG")
	var follows_target: bool = true
	for frame: int in 160:
		var target: Vector2 = ROCK + Vector2(180, -float(frame) * 0.5)
		field.next_target(ROCK + Vector2(-180, 0), target, 22.0, 100)
		var route: Dictionary = field._routes[100]
		var path: PackedVector2Array = route["path"]
		follows_target = follows_target and not path.is_empty() and path[-1] == route["goal"] and (route["goal"] as Vector2).distance_to(target) <= 48.0
	_check(follows_target, "Many small target moves accumulate against the actual route endpoint and trigger a fresh route")
	var boundary_field := ArenaObstacles.new([{"center": Vector2(0, -435), "radius": 100.0}])
	var boundary_result: Vector2 = boundary_field.move_body(Vector2(-400, -485), Vector2(900, 0), 16.0, 16.0)
	_check(boundary_field.is_free(boundary_result, 16.0, 16.0), "A long glancing slide near the world edge re-sweeps the clamped remainder and leaves the complete body legal")


func _test_player_and_dash() -> void:
	var sim: CombatSim = _sim()
	sim.player_position = ROCK + Vector2(-100, 0)
	sim.step(0.5, Vector2.RIGHT)
	_check(sim.player_position.x < ROCK.x - 55.9 and sim.obstacles.is_free(sim.player_position, 16.0), "Ordinary gameplay movement stops at solid cover")
	for sign_value: float in [-1.0, 1.0]:
		sim = _sim()
		sim.player_position = ROCK + Vector2(sign_value * 100.0, 0)
		var before: Array = [sim.rng.state, sim.run.rng.state]
		sim.step(0.3, Vector2(-sign_value, 0), true)
		_check((sim.player_position.x - ROCK.x) * sign_value > 55.9 and sim.obstacles.is_free(sim.player_position, 16.0), "A complete large-step dash cannot emerge on the far side of cover")
		_check(sim.dashes_used == 1 and sim.dash_time_left == 0.0 and is_equal_approx(sim.dash_cooldown_left, 2.1) and before == [sim.rng.state, sim.run.rng.state], "Blocked movement preserves dash uses, real time and RNG independence")


func _test_index_boundaries() -> void:
	for center: Vector2 in [Vector2(128, 128), Vector2(-128, -128), Vector2(127.9, -128.1)]:
		var field := ArenaObstacles.new([{"center": center, "radius": 40.0}])
		for body_radius: float in [0.0, 16.0, 42.0, 64.0, 65.0, 100.0]:
			var clearance: float = 40.0 + body_radius
			for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized()]:
				var outside: Vector2 = center + direction * (clearance + 0.1)
				var inside: Vector2 = center + direction * (clearance - 0.1)
				_check(field.is_free(outside, body_radius) and not field.is_free(inside, body_radius), "Spatial candidates keep exact circle membership at signed cell boundaries and all body sizes")
				var projected: Vector2 = field.free_point(inside, body_radius)
				_check(field.is_free(projected, body_radius) and field.free_point(projected, body_radius) == projected, "A projected point stays legal and stable without repeated floating-point reprojection")
			var start: Vector2 = center + Vector2(-clearance - 100.0, 0)
			var end: Vector2 = center + Vector2(clearance + 100.0, 0)
			var stopped: Vector2 = field.move_body(start, end - start, body_radius)
			_check(not field.segment_clear(start, end, body_radius) and stopped.x < center.x - clearance + 0.01 and field.is_free(stopped, body_radius), "Cross-cell sweeps and bodies above the index radius use the full collision fallback")
	var small := ArenaObstacles.new([{"center": Vector2(120, 120), "radius": 4.0}])
	var stopped: Vector2 = small.move_body(Vector2(112, 120), Vector2(14, 0), 0.0)
	_check(stopped.x < 116.01 and not small.segment_clear(Vector2(112, 120), Vector2(126, 120)), "Same-cell broadphase still detects a small obstacle between two clear endpoints")
	_check(small.segment_clear(Vector2(124, 120), Vector2(126, 120)), "A tangent source can leave cover immediately through the indexed path")
	_check(small.segment_clear(Vector2(90, 90), Vector2(150, 90)) and not small.segment_clear(Vector2(90, 120), Vector2(150, 120)), "A cached cell pair remains conservative when the exact source and destination move within those cells")
	var empty := ArenaObstacles.new()
	_check(empty.move_body(Vector2(0, 0), Vector2(17, 23), 16.0) == Vector2(17, 23), "An empty broadphase preserves exact open-ground movement")
	var authored: Array = ArenaCatalog.definition("reliquary")["obstacles"]
	var reused := ArenaObstacles.new()
	for count: int in [10, 1, 0, 2, 1, 0, 10]:
		reused.configure(authored.slice(0, count))
		var consistent: bool = reused._empty_ids.is_empty() and reused._point_candidates(Vector2(-900, -400), 16.0).is_empty()
		consistent = consistent and reused.segment_clear(Vector2(100, 560), Vector2(300, 560), 16.0) == (count == 0)
		for bucket: PackedInt32Array in reused._cells.values():
			consistent = consistent and bucket.size() <= count
			for index: int in bucket:
				consistent = consistent and index >= 0 and index < count
		for point: Vector2 in [Vector2(-900, -400), ROCK, Vector2(200, 560), Vector2(1120, 560)]:
			var legal: Vector2 = reused.free_point(point, 16.0)
			consistent = consistent and reused.is_free(legal, 16.0) and reused.segment_clear(legal, legal, 16.0)
		_check(consistent and reused.snapshot().size() == count, "Repeated configuration keeps independent empty spatial buckets and never retains stale circle indices")


func _test_shared_projection() -> void:
	var field := ProjectionProbe.new()
	field.configure([{"center": Vector2(1500, 1000), "radius": 40.0}])
	var target: Vector2 = ROCK + Vector2(100, 0)
	for uid: int in 300:
		field.next_target(ROCK, target, 13.0, uid)
	_check(field.projection_calls == 1, "Three hundred same-body enemies share one exact target projection")
	var retreat: Vector2 = ROCK + Vector2(-100, 0)
	_check(field.next_target(ROCK, retreat, 13.0, 0) == retreat and field.projection_calls == 2, "A distinct caster retreat point cannot reuse another target's projection")
	_check(field.next_target(ROCK, target, 22.0, 1) == target and field.projection_calls == 3, "Different collision radii keep separate projected targets")
	field.configure([])
	_check(field.next_target(ROCK, target, 22.0, 1) == target and field.projection_calls == 4, "Reconfiguring an arena invalidates shared target projections")
	var invalid: Vector2 = field.next_target(Vector2.ZERO, Vector2.INF, 16.0, 2)
	_check(invalid.is_finite(), "The first cached nonfinite target still receives the normal safe projection")
	var moved: Vector2 = target + Vector2(4, 4)
	_check(field.next_target(ROCK + Vector2(8, 8), moved, 22.0, 1) == moved, "An obstacle-free corridor remains valid while exact endpoints move inside their cached cells")
	field.configure([{"center": Vector2(1500, 1000), "radius": 40.0}])
	field.next_target(ROCK, target, 22.0, 1)
	var obstacle_target: Vector2 = Vector2(1500, 1000)
	var detour: Vector2 = field.next_target(ROCK, obstacle_target, 22.0, 1)
	_check(detour != obstacle_target and not field._projected_goals[22.0].open_sources.has(Vector2i((ROCK / ArenaObstacles.INDEX_CELL).floor())), "Moving the target into another cell invalidates open-corridor shortcuts before a blocking obstacle")


func _test_push_and_recoil() -> void:
	var sim: CombatSim = _sim()
	_check(SKILL_FIXTURE.equip_pulse(sim.run), "The push fixture owns a real backpack skill")
	sim.player_position = ROCK + Vector2(-120, 0)
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", ROCK + Vector2(-70, 0))
	var before: Array = [sim.rng.state, sim.run.rng.state]
	_check(sim.try_pulse() and sim.last_pulse_affected == 1, "The real active skill accepts an eligible target beside cover")
	_check(enemy.position.x < ROCK.x - 52.9 and sim.obstacles.is_free(enemy.position, enemy.radius) and enemy.pulse_hinder_timer == 1.0, "Pulse push stops at cover and retains its independent hindrance")
	_check(before == [sim.rng.state, sim.run.rng.state] and sim.run.kills == 0 and sim.damage_by_weapon.is_empty(), "Collision resolution adds no random draw, offensive hit or reward")
	sim = _sim()
	sim.player_position = ROCK + Vector2(-80, 0)
	enemy = sim.spawn_enemy("chaser", ROCK + Vector2(-65, 0))
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	sim._update_enemies(STEP)
	_check(sim.run.health < 100.0 and enemy.position.x < ROCK.x - 52.9 and sim.obstacles.is_free(enemy.position, enemy.radius), "Contact damage keeps its radial recoil without pushing an enemy into a pillar")


func _route_fixture(id: String) -> CombatSim:
	var sim: CombatSim = _sim()
	sim.player_position = ROCK + Vector2(280, 0)
	sim.invulnerability = 9999.0
	var enemy: CombatSim.Enemy = sim.spawn_enemy(id, ROCK + Vector2(-240, 0))
	enemy.action_timer = 9999.0
	return sim


func _test_enemy_routes() -> void:
	for id: String in ["chaser", "rusher", "tank", "caster", "boss"]:
		var first: CombatSim = _route_fixture(id)
		var second: CombatSim = _route_fixture(id)
		var enemy: CombatSim.Enemy = first.enemies[0]
		var safe: bool = true
		var detour: float = 0.0
		var before: Array = [first.rng.state, first.run.rng.state]
		for frame: int in 1800:
			first._update_enemies(STEP)
			second._update_enemies(STEP)
			safe = safe and first.obstacles.is_free(enemy.position, enemy.radius)
			detour = maxf(detour, absf(enemy.position.y - ROCK.y))
		_check(safe and detour > 40.0 and enemy.position.x > ROCK.x + 20.0, "The real enemy moves around a head-on obstacle and continues its role: " + id)
		_check(enemy.position == second.enemies[0].position and before == [first.rng.state, first.run.rng.state] and first.rng.state == second.rng.state, "Identical ground routes remain deterministic without random retries: " + id)


func _test_locked_charge() -> void:
	var sim: CombatSim = _sim()
	sim.player_position = ROCK + Vector2(280, 0)
	var enemy: CombatSim.Enemy = sim.spawn_enemy("rusher", ROCK + Vector2(-80, 0))
	enemy.mode = 2
	enemy.charge_direction = Vector2.RIGHT
	enemy.action_timer = 0.6
	sim._update_enemies(0.21)
	_check(enemy.position.x < ROCK.x - 50.9 and enemy.position.y == ROCK.y and enemy.charge_direction == Vector2.RIGHT and enemy.mode == 2, "A locked charge hits cover in a straight line instead of steering through it")
	sim._update_enemies(0.4)
	_check(enemy.mode == 0 and enemy.action_timer == 2.5 and sim.obstacles.is_free(enemy.position, enemy.radius), "The original charge deadline recovers normally after hitting cover")
	var before: Vector2 = enemy.position
	for frame: int in 30:
		sim._update_enemies(STEP)
	_check(enemy.position.distance_to(before) > 10.0 and sim.obstacles.is_free(enemy.position, enemy.radius), "A recovered rusher resumes a traversable route instead of staying pinned")


func _test_spawns_and_randomness() -> void:
	for id: String in ArenaCatalog.IDS:
		var sim: CombatSim = _sim(id, false)
		var expected := RandomNumberGenerator.new()
		expected.seed = sim.rng.seed
		expected.state = sim.rng.state
		var safe: bool = true
		for point: Vector2 in [CombatSim.ARENA.get_center(), CombatSim.ARENA.position, CombatSim.ARENA.end, Vector2(-700, 800), Vector2(1900, -250)]:
			sim.player_position = point
			var view: Rect2 = ArenaCatalog.visible_rect(point)
			for sample: int in 40:
				var position: Vector2 = sim._edge_position(42.0)
				expected.randf()
				expected.randf()
				safe = safe and sim.obstacles.is_free(position, 42.0) and not view.grow(24.0).has_point(position)
		_check(safe and sim.rng.state == expected.state, "Camera-edge spawning excludes cover with exactly the original two random draws: " + id)
		for item: Dictionary in sim.obstacles.snapshot():
			for enemy_id: String in ["chaser", "rusher", "tank", "caster", "boss"]:
				expected.state = sim.rng.state
				expected.randf_range(1.0, 2.5)
				var enemy: CombatSim.Enemy = sim.spawn_enemy(enemy_id, item["center"])
				_check(enemy != null and sim.obstacles.is_free(enemy.position, enemy.radius) and sim.rng.state == expected.state, "Explicit spawning projects each actual body size without extra RNG: " + id + "/" + enemy_id)


func _test_boss_summons_and_drops() -> void:
	var sim: CombatSim = _sim()
	sim.player_position = ROCK + Vector2(280, 0)
	var boss: CombatSim.Enemy = sim.spawn_enemy("boss", ROCK + Vector2(-100, 0))
	boss.action_timer = 0.0
	sim._boss_cycle = 1
	sim._update_boss(boss, Vector2.RIGHT, 0.0)
	var safe: bool = sim.enemy_count == 3
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			safe = safe and sim.obstacles.is_free(enemy.position, enemy.radius)
	_check(safe, "Real boss summons project even a requested spawn at the pillar center")
	var before: Array = [sim.rng.state, sim.run.rng.state]
	sim._drop_soul(ROCK, 3)
	_check(sim.soul_count == 1 and sim.obstacles.is_free(sim.souls[0].position, 6.0) and before == [sim.rng.state, sim.run.rng.state], "Earned drops leave cover safely without advancing either RNG")
	for frame: int in 30:
		sim._update_souls(STEP)
	_check(sim.souls[0].active and sim.obstacles.is_free(sim.souls[0].position, 6.0), "An unmagnetized drop remains safely outside the ground footprint")
	sim.collect_remaining_souls()
	_check(sim.soul_count == 0 and sim.run.gold == 3, "Cover cannot delete earned currency when the wave collects remaining drops")
	for side: float in [-1.0, 1.0]:
		sim = _sim("reliquary", false)
		sim.player_position = Vector2(200.0 + side * 50.0, 560)
		sim.run._upgrade_bonuses["pickup_radius"] = 80.0
		sim._drop_soul(Vector2(200.0 - side * 40.0, 560), 3)
		before = [sim.rng.state, sim.run.rng.state]
		for frame: int in 180:
			sim._update_souls(STEP)
		_check(sim.soul_count == 0 and sim.run.gold == 3 and before == [sim.rng.state, sim.run.rng.state], "Flying magnetic drops reach a stationary player on either side of low cover without RNG")
	sim = _sim("reliquary", false)
	sim.populate_stress()
	safe = sim.enemy_count == 300 and sim.shot_count == 600 and sim.soul_count == 200
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			safe = safe and sim.obstacles.is_free(enemy.position, enemy.radius)
	for soul: CombatSim.Soul in sim.souls:
		if soul.active:
			safe = safe and sim.obstacles.is_free(soul.position, 6.0)
	_check(safe, "The original full stress pools also start outside authored ground cover")


func _test_flying_shots() -> void:
	var sim: CombatSim = _sim()
	sim.player_position = ROCK + Vector2(200, 200)
	var start: Vector2 = ROCK + Vector2(-100, 0)
	var friendly: CombatSim.Shot = sim.fire_weapon("bone", "", start, Vector2.RIGHT)
	friendly.velocity = Vector2(400, 0)
	sim._hostile_shot(start, Vector2(400, 0), 8.0, "caster")
	sim._rebuild_grid()
	sim._update_shots(0.4)
	_check(friendly.active and friendly.position.is_equal_approx(start + Vector2(160, 0)), "Flying player weapons keep their original path across low ground cover")
	var hostile: CombatSim.Shot = sim.shots[1]
	_check(hostile.active and hostile.hostile and hostile.position.is_equal_approx(friendly.position), "Hostile flying shots follow the same unobstructed low-cover rule")
