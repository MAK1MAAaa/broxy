extends SceneTree
## Only fully invisible cosmetic geometry may be omitted; live combat and instances stay intact.

const VIEW: Rect2 = Rect2(200, 200, 100, 100)
const RUNES: Array[String] = ["pierce", "bounce", "blast"]
const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

class DrawSpy extends CombatWorld:
	var view: Rect2 = Rect2(200, 200, 100, 100)
	var drawn_effects: Array[CombatSim.Effect] = []
	var drawn_souls: Array[CombatSim.Soul] = []
	var drawn_numbers: Array[CombatWorld.FloatingNumber] = []

	func camera_view() -> Rect2:
		return view

	func _draw_effect(effect: CombatSim.Effect) -> void:
		drawn_effects.append(effect)

	func _draw_soul(soul: CombatSim.Soul) -> void:
		drawn_souls.append(soul)

	func _draw_number(number: CombatWorld.FloatingNumber) -> void:
		drawn_numbers.append(number)

func _initialize() -> void:
	_test_cosmetic_edges()
	_test_trail_edges()
	_test_600_instances_and_purity()
	_test_enemy_buckets_and_purity()
	print("CosmeticCulling: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _simulation() -> CombatSim:
	var state := RunState.new()
	state.begin(20261030, "bone", "mire", "alk")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim

func _number(point: Vector2, width: float, hit: bool = false) -> CombatWorld.FloatingNumber:
	var number := CombatWorld.FloatingNumber.new()
	number.position = point
	number.velocity = Vector2(18, -38)
	number.text = "1234"
	number.text_width = width
	number.font_size = 24
	number.life = 0.4
	number.player_hit = hit
	return number

func _signature(world: CombatWorld) -> String:
	var sim: CombatSim = world.sim
	var data: Array = [sim.snapshot(), sim.run.summary(), sim.elapsed,
		str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state),
		sim.interactions.snapshot(), sim.soul_count, sim.shot_count,
		sim.primary_hits, sim.secondary_hits, sim.damage_by_weapon,
		sim._shot_free.duplicate(), sim._soul_free.duplicate()]
	for effect: CombatSim.Effect in sim.effects:
		data.append([effect.position, effect.radius, effect.color, effect.life, effect.total, effect.kind])
	for soul: CombatSim.Soul in sim.souls:
		data.append([soul.slot, soul.active, soul.position, soul.age, soul.value])
	for shot: CombatSim.Shot in sim.shots:
		data.append([shot.slot, shot.active, shot.position, shot.previous, shot.velocity,
			shot.source, shot.rune, shot.radius, shot.damage, shot.life, shot.hit_ids.duplicate(), shot.remaining])
	for number: CombatWorld.FloatingNumber in world._numbers:
		data.append([number.position, number.velocity, number.text, number.text_width,
			number.amount, number.life, number.total, number.font_size, number.player_hit])
	for enemy: CombatSim.Enemy in sim.enemies:
		data.append([enemy.slot, enemy.active, enemy.uid, enemy.definition.id if enemy.definition != null else "",
			enemy.position, enemy.velocity, enemy.health, enemy.max_health, enemy.age, enemy.action_timer,
			enemy.hurt_timer, enemy.slow_timer, enemy.slow_factor, enemy.pulse_hinder_timer, enemy.radius,
			enemy.hunter, enemy.mode, enemy.positive_conditions.duplicate(true), enemy.fire_vulnerability_left])
	return JSON.stringify(data)

func _test_cosmetic_edges() -> void:
	var world := DrawSpy.new()
	world.sim = _simulation()
	for kind: int in 4:
		world.sim.add_effect(Vector2(250, 250), Color.WHITE, 20.0, 0.4, kind)
		world.sim.add_effect(Vector2(316, 250), Color.WHITE, 20.0, 0.4, kind)
		world.sim.add_effect(Vector2(500, 250), Color.WHITE, 20.0, 0.4, kind)
	world._draw_effects()
	_check(world.drawn_effects.size() == 8, "All four effect types keep onscreen and edge-crossing geometry while fully distant effects are skipped")
	for index: int in 4:
		_check(world.drawn_effects.has(world.sim.effects[index * 3 + 1]), "An effect center outside the camera does not hide its expanding arc: " + str(index))
	var expanding: CombatSim.Effect = world.sim.effects[4]
	_check(CombatWorld.effect_draw_bounds(expanding).has_point(expanding.position - Vector2(28, 0)), "The full 1.4-radius expanding arc remains inside its conservative draw bounds")
	for spec: Array in [[Vector2(250, 250), 1], [Vector2(305, 250), 1], [Vector2(250, 309), 2], [Vector2(500, 500), 1]]:
		world.sim._drop_soul(Vector2(500, 500), int(spec[1]))
		var soul: CombatSim.Soul = world.sim.souls[world.sim.soul_count - 1]
		soul.position = spec[0]
		soul.age = 0.5
	world._draw_souls()
	_check(world.drawn_souls.size() == 3, "Both soul sizes preserve edge-crossing sprites and the full two-pixel vertical bob")
	var large_soul: CombatSim.Soul = world.sim.souls[2]
	_check(CombatWorld.soul_draw_bounds(large_soul).has_point(large_soul.position + Vector2(0, -10.0)), "Large-soul bounds include its canvas extent and negative bob")
	world._numbers.append(_number(Vector2(250, 250), 48))
	world._numbers.append(_number(Vector2(321, 250), 48))
	world._numbers.append(_number(Vector2(250, 324), 48, true))
	world._numbers.append(_number(Vector2(500, 500), 48))
	world._draw_numbers(false)
	_check(world.drawn_numbers.size() == 2 and world.drawn_numbers.has(world._numbers[1]), "Outgoing numbers preserve partial glyphs and outlines even when the anchor is outside")
	world.drawn_numbers.clear()
	world._draw_numbers(true)
	_check(world.drawn_numbers.size() == 1 and world.drawn_numbers[0] == world._numbers[2], "Incoming numbers retain their own layer and full glyph height across the bottom edge")
	var drifting: CombatWorld.FloatingNumber = world._numbers[1]
	var text_bounds: Rect2 = CombatWorld.number_draw_bounds(drifting)
	_check(text_bounds.has_point(drifting.position + Vector2(-24, -24)), "Number bounds cover glyph width, ascent and outline rather than only the anchor")
	_check(text_bounds.has_point(drifting.position + drifting.velocity / 30.0), "Number bounds retain the next presentation interval of drift")
	world.sim.effects.clear()
	world.sim.add_effect(Vector2(345, 250), Color.WHITE, 20, 0.4)
	world.drawn_effects.clear()
	world._draw_effects()
	_check(world.drawn_effects.is_empty(), "A complete effect beyond every unshaken stroke is omitted")
	world.position = Vector2(-12, 0)
	world._draw_effects()
	_check(world.drawn_effects.size() == 1, "Screen-shake translation keeps geometry that can enter the visible screen")
	var before: String = _signature(world)
	for repeat: int in 4:
		world._draw_effects()
		world._draw_souls()
		world._draw_numbers(false)
		world._draw_numbers(true)
	_check(_signature(world) == before, "Cosmetic culling leaves all effects, souls, floating lifetimes, counters and three RNG states untouched")
	world.view = Rect2(450, 450, 100, 100)
	world.drawn_souls.clear()
	world._draw_souls()
	_check(world.drawn_souls.size() == 1 and world.drawn_souls[0] == world.sim.souls[3], "A camera move immediately restores previously invisible live souls")
	world.free()

func _test_trail_edges() -> void:
	var sim: CombatSim = _simulation()
	var edge_tail: CombatSim.Shot = sim.fire_weapon("bone", "pierce", Vector2(310, 250), Vector2.RIGHT)
	var edge_wing: CombatSim.Shot = sim.fire_weapon("bone", "pierce", Vector2(196, 270), Vector2.RIGHT)
	var remote: CombatSim.Shot = sim.fire_weapon("bone", "pierce", Vector2(600, 600), Vector2.RIGHT)
	var baseline := ProjectilePainter.new()
	var culled := ProjectilePainter.new()
	baseline.rebuild(sim.shots)
	culled.rebuild(sim.shots, VIEW)
	var expected_points: PackedVector2Array = baseline.trails["bone:pierce"].points.slice(0, 4)
	var expected_wings: PackedVector2Array = baseline.trails["bone:pierce"].wings.slice(0, 8)
	_check(culled.trails["bone:pierce"].points == expected_points, "A center outside the screen keeps its crossing tail, and a fully remote segment is omitted")
	_check(culled.trails["bone:pierce"].wings == expected_wings, "Directional wings and their antialias margin survive near the left screen edge")
	_check(edge_tail.position.x > VIEW.end.x and edge_wing.position.x < VIEW.position.x and remote.active, "The edge fixture genuinely crosses both screen edges while the skipped projectile stays active")
	_check(culled.get_stats() == baseline.get_stats(), "Trail culling does not replace live projectile or head/ring instance statistics with visible-tail counts")
	culled.rebuild(sim.shots)
	_check(culled.trails["bone:pierce"].points == baseline.trails["bone:pierce"].points and culled.trails["bone:pierce"].wings == baseline.trails["bone:pierce"].wings, "Omitting the optional camera rectangle preserves the complete legacy painter behavior")

func _pressure_simulation() -> CombatSim:
	var sim: CombatSim = _simulation()
	for source: String in ProjectilePainter.HEAD_SOURCES:
		for rune: String in RUNES:
			for index: int in 25:
				var point := Vector2(240 + index, 240) if index < 12 else Vector2(940 + index, 640)
				sim.fire_weapon(source, rune, point, Vector2.RIGHT)
	return sim

func _check_instances(baseline: ProjectilePainter, culled: ProjectilePainter) -> void:
	_check(culled.get_stats() == baseline.get_stats(), "The camera preserves every global, family, visible-instance and allocation count")
	_check(culled._body_buffer == baseline._body_buffer and culled.bodies.buffer == baseline.bodies.buffer, "All ember body transforms and GPU instances remain unchanged")
	_check(culled.head_multimesh.instance_count == baseline.head_multimesh.instance_count and culled.head_multimesh.visible_instance_count == baseline.head_multimesh.visible_instance_count
		and culled.head_buffer == baseline.head_buffer and culled.head_multimesh.buffer == baseline.head_multimesh.buffer, "The single physical head batch keeps all onscreen and offscreen CPU/GPU instances unchanged")
	var start: int = 0
	for key: String in baseline.heads:
		var before: ProjectilePainter.HeadBatch = baseline.heads[key]
		var after: ProjectilePainter.HeadBatch = culled.heads[key]
		_check(after.cursor == before.cursor and after.capacity == before.capacity and after.start == before.start and after.start == start
			and after.source == before.source and after.frame == before.frame and is_equal_approx(after.base_radius, before.base_radius), "Every logical textured-head range retains count, order, source and independent geometry: " + key)
		var first: int = start * ProjectilePainter.HEAD_INSTANCE_STRIDE
		var end: int = (start + before.cursor) * ProjectilePainter.HEAD_INSTANCE_STRIDE
		_check(culled.head_buffer.slice(first, end) == baseline.head_buffer.slice(first, end), "Every family still occupies its exact real physical instance slice: " + key)
		start += before.cursor
	_check(start == baseline.head_multimesh.visible_instance_count and start == baseline.get_stats()["head_instances"], "Logical families cover every physical head instance exactly once despite cosmetic culling")
	for radius: float in baseline.rings:
		var before: ProjectilePainter.RingBatch = baseline.rings[radius]
		var after: ProjectilePainter.RingBatch = culled.rings[radius]
		_check(after.cursor == before.cursor and after.multimesh.visible_instance_count == before.multimesh.visible_instance_count and after.buffer == before.buffer and after.multimesh.buffer == before.multimesh.buffer, "Every bounce ring is retained with the same actual CPU/GPU data: " + str(radius))

func _test_600_instances_and_purity() -> void:
	var world := DrawSpy.new()
	world.sim = _pressure_simulation()
	var oracle := DrawSpy.new()
	oracle.sim = _pressure_simulation()
	var baseline := ProjectilePainter.new()
	var culled := ProjectilePainter.new()
	var before: String = _signature(world)
	_check(world.sim.shot_count == 600, "The pressure fixture contains 600 real active projectiles across all eight weapons and three runes")
	baseline.rebuild(world.sim.shots)
	culled.rebuild(world.sim.shots, VIEW)
	_check(baseline.get_stats()["family_counts"].size() == 24, "The pressure fixture exercises all 24 source/rune families")
	_check(baseline.get_stats()["head_gpu_batches"] == 1 and baseline.head_multimesh.visible_instance_count == 600 and baseline.head_multimesh.instance_count == 600, "All24 logical families retain600 real heads in one physical draw batch")
	_check_instances(baseline, culled)
	for key: String in baseline.trails:
		var full: ProjectilePainter.TrailBatch = baseline.trails[key]
		var clipped: ProjectilePainter.TrailBatch = culled.trails[key]
		_check(clipped.points == full.points.slice(0, 24), "Every fully visible trail endpoint remains exact: " + key)
		_check(clipped.wings == full.wings.slice(0, 48) if not full.wings.is_empty() else clipped.wings.is_empty(), "Every fully visible directional wing remains exact: " + key)
	culled.rebuild(world.sim.shots, Rect2(900, 600, 100, 100))
	for key: String in baseline.trails:
		_check(culled.trails[key].points == baseline.trails[key].points.slice(24), "Moving the camera restores the other thirteen live tails without stale geometry: " + key)
	_check(_signature(world) == before and before == _signature(oracle), "Repeated camera-dependent preparation leaves all real projectiles, resources, environment and RNG identical to the seeded oracle")
	world.sim.step(STEP, Vector2.ZERO)
	oracle.sim.step(STEP, Vector2.ZERO)
	_check(_signature(world) == _signature(oracle), "The next fixed simulation step is identical whether or not offscreen geometry was prepared")
	world.free()
	oracle.free()

func _legacy_enemy_order(enemies: Array[CombatSim.Enemy]) -> Array[int]:
	var result: Array[int] = []
	for id: String in ["chaser", "rusher", "tank", "caster", "boss"]:
		for enemy: CombatSim.Enemy in enemies:
			if enemy.active and enemy.definition.id == id:
				result.append(enemy.uid)
	return result

func _prepared_enemy_order(world: CombatWorld) -> Array[int]:
	var result: Array[int] = []
	for id: String in CombatWorld.ENEMY_DRAW_IDS:
		var bucket: CombatWorld.EnemyDrawBucket = world._enemy_draw_buckets[id]
		for enemy: CombatSim.Enemy in bucket.enemies:
			result.append(enemy.uid)
	return result

func _test_enemy_buckets_and_purity() -> void:
	var world := DrawSpy.new()
	world.sim = _simulation()
	var unknown := ContentDef.new()
	unknown.id = "unknown_visual_family"
	var fixtures: Array[CombatSim.Enemy] = []
	var ids: Array[String] = ["caster", "chaser", "rusher", "tank", "chaser", "boss", "caster", "rusher", unknown.id, "tank"]
	for index: int in ids.size():
		var enemy := CombatSim.Enemy.new()
		enemy.slot = index
		enemy.uid = 101 + index
		enemy.definition = unknown if ids[index] == unknown.id else GameCatalog.enemy(ids[index])
		enemy.active = index not in [2, 9]
		enemy.health = 0.0 if index == 3 else 37.0
		enemy.max_health = 90.0
		enemy.position = Vector2(250, 250) if index % 2 == 0 else Vector2(9000 + index, -8000)
		enemy.radius = 12.0 + float(index)
		enemy.age = float(index) * 0.13
		enemy.hurt_timer = 0.08
		enemy.hunter = index == 4
		fixtures.append(enemy)
	world.sim.enemies.assign(fixtures)
	var buckets: Dictionary = world._enemy_draw_buckets.duplicate()
	var before: String = _signature(world)
	for repeat: int in 4:
		world._rebuild_enemy_draw_buckets()
		_check(_prepared_enemy_order(world) == [102, 105, 108, 104, 101, 107, 106], "Mixed families preserve original texture order and pool order on every rebuild")
		_check(_prepared_enemy_order(world) == _legacy_enemy_order(world.sim.enemies), "The prepared draw list equals an independent original five-pass traversal")
		for id: String in CombatWorld.ENEMY_DRAW_IDS:
			_check(world._enemy_draw_buckets[id] == buckets[id], "Rebuilding reuses the existing family bucket without replacing or accumulating it: " + id)
	_check(_prepared_enemy_order(world).has(102) and fixtures[1].position.x > VIEW.end.x and _prepared_enemy_order(world).has(104) and fixtures[3].health == 0.0, "Grouping retains offscreen active enemies and does not add a health-based draw filter")
	_check(not _prepared_enemy_order(world).has(103) and not _prepared_enemy_order(world).has(109), "Only inactive entities and unknown visual families retain the original skip behavior")
	_check(_signature(world) == before and CombatWorld.NUMBER_LIMIT == 48, "Repeated enemy presentation preparation preserves all enemy state, feedback, inventory, hit counters and RNG")
	fixtures[2].active = true
	fixtures[1].active = false
	fixtures[8].definition = GameCatalog.enemy("boss")
	fixtures[6].definition = GameCatalog.enemy("tank")
	world.sim.enemies.reverse()
	before = _signature(world)
	for repeat: int in 3:
		world._rebuild_enemy_draw_buckets()
		_check(_prepared_enemy_order(world) == [105, 108, 103, 107, 104, 101, 109, 106] and _prepared_enemy_order(world) == _legacy_enemy_order(world.sim.enemies), "Active flips, family replacement and reversed pool order immediately replace the actual draw sequence")
	_check(_signature(world) == before, "Rebuilding after real entity changes remains pure and does not retain old entity membership")
	for enemy: CombatSim.Enemy in fixtures:
		enemy.active = false
	world._rebuild_enemy_draw_buckets()
	_check(_prepared_enemy_order(world).is_empty(), "Deactivating all entities clears every previously populated family")
	fixtures[8].active = true
	fixtures[8].definition = unknown
	world._rebuild_enemy_draw_buckets()
	_check(_prepared_enemy_order(world).is_empty(), "An unknown-only active pool cannot revive stale known-family entries")
	fixtures[0].active = true
	world._rebuild_enemy_draw_buckets()
	_check(_prepared_enemy_order(world) == [101], "A reused bucket immediately recovers one newly active entity after an empty frame")
	world.free()
