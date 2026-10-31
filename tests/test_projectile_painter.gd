extends SceneTree
## Rendering preparation must remain bounded and leave the real simulation untouched.

const PAINTER_SCRIPT = preload("res://scripts/combat/projectile_painter.gd")
const SOURCES: Array[String] = ["bone", "frost", "ember", "scatter"]
const RUNES: Array[String] = ["pierce", "bounce", "blast"]
const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_mixed_600()
	_test_worst_case_capacity()
	_test_filter_and_clear()
	_test_global_head_order()
	_test_trails_and_color()
	_test_reused_shot_families()
	_test_simulation_unchanged()
	print("ProjectilePainter: %d assertions, %d failures; native GPU readback=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _shot(source: String, rune_id: String, index: int = 0) -> CombatSim.Shot:
	var definition: ContentDef = GameCatalog.weapon(source)
	var shot := CombatSim.Shot.new()
	shot.active = true
	shot.source = source
	shot.rune = rune_id
	shot.radius = definition.projectile_radius
	shot.color = definition.color
	shot.position = Vector2(120 + index % 24 * 40, 180 + index / 24 * 9)
	shot.previous = shot.position - Vector2(5, 0)
	shot.velocity = Vector2.RIGHT * definition.projectile_speed
	shot.damage = definition.damage
	shot.remaining = 2
	shot.life = 1.5
	return shot

func _allocated(painter) -> int:
	var total: int = painter.bodies.instance_count + painter.head_multimesh.instance_count
	for ring in painter.rings.values():
		total += ring.multimesh.instance_count
	return total

func _visible_heads(painter) -> int:
	return painter.head_multimesh.visible_instance_count

func _check_head_mapping(painter, shots: Array[CombatSim.Shot], expected_capacity: int = -1) -> void:
	var expected: Dictionary = {}
	var count: int = 0
	for shot: CombatSim.Shot in shots:
		if not shot.active or shot.hostile:
			continue
		if count == CombatSim.SHOT_LIMIT:
			break
		var key: String = shot.source + ":" + shot.rune
		if not expected.has(key):
			expected[key] = []
		expected[key].append(shot)
		count += 1
	var native_readback: bool = DisplayServer.get_name() != "headless"
	var gpu := PackedFloat32Array()
	if native_readback:
		gpu = painter.head_multimesh.buffer
	var cpu: PackedFloat32Array = painter.head_buffer
	var capacity: int = count if expected_capacity < 0 else expected_capacity
	_check(painter.head_multimesh.instance_count == capacity and _visible_heads(painter) == count and cpu.size() == capacity * PAINTER_SCRIPT.HEAD_INSTANCE_STRIDE, "The sole physical head buffer preserves its exact highest nonempty capacity and prepares every visible projectile once")
	if native_readback:
		_check(gpu.size() == cpu.size(), "The actual native GPU buffer contains every prepared head instance")
	_check(painter.head_multimesh.use_custom_data and painter.get_stats()["head_gpu_batches"] == (1 if count > 0 else 0), "Head atlas selection uses one actual custom-data GPU batch, or none when empty")
	var frames: Dictionary = {}
	for index: int in PAINTER_SCRIPT.HEAD_SOURCES.size():
		frames[PAINTER_SCRIPT.HEAD_SOURCES[index]] = index
	for definition: ContentDef in GameCatalog.weapons():
		if not frames.has(definition.id):
			frames[definition.id] = frames.size()
	var start: int = 0
	for key: String in painter.heads:
		var head = painter.heads[key]
		var family: Array = expected.get(key, [])
		_check(head.start == start and head.cursor == family.size() and head.capacity >= head.cursor and head.capacity <= CombatSim.SHOT_LIMIT, "Logical family ranges preserve their surviving insertion order and bounded capacity: " + key)
		var matches: bool = head.source == key.get_slice(":", 0) and head.frame == frames.get(head.source, 0) and head.frame >= 0 and head.frame < 32
		var native_matches: bool = gpu.size() == cpu.size()
		for local: int in family.size():
			var shot: CombatSim.Shot = family[local]
			var direction: Vector2 = shot.velocity.normalized()
			if direction.is_zero_approx():
				direction = Vector2.RIGHT
			var definition: ContentDef = GameCatalog.weapon(shot.source)
			var scale: float = shot.radius / definition.projectile_radius
			var values: Array[float] = [direction.x * scale, -direction.y * scale, 0.0, shot.position.x,
				direction.y * scale, direction.x * scale, 0.0, shot.position.y, 1.0, 1.0, 1.0, 1.0,
				float(head.frame) / 31.0, 0.5, 0.25, 0.0]
			var offset: int = (int(head.start) + local) * PAINTER_SCRIPT.HEAD_INSTANCE_STRIDE
			matches = matches and is_equal_approx(head.base_radius, definition.projectile_radius)
			for channel: int in values.size():
				matches = matches and is_equal_approx(cpu[offset + channel], values[channel])
			if native_readback and gpu.size() == cpu.size():
				for channel: int in 12:
					native_matches = native_matches and is_equal_approx(gpu[offset + channel], values[channel])
				native_matches = native_matches and roundi(gpu[offset + 12] * 31.0) == head.frame and is_equal_approx(gpu[offset + 13], 0.5)
				native_matches = native_matches and is_equal_approx(gpu[offset + 14], 0.25) and is_zero_approx(gpu[offset + 15])
		_check(matches, "Every real shot retains its independent transform, white tint and exact atlas custom data: " + key)
		if native_readback:
			_check(native_matches, "Actual native GPU readback preserves every transform, tint, decoded frame and both head sentinels: " + key)
		start += head.cursor
	_check(start == count and painter.heads.size() == expected.size(), "Logical families cover the complete physical buffer without omitted or duplicated instances")

func _test_mixed_600() -> void:
	var shots: Array[CombatSim.Shot] = []
	for source: String in SOURCES:
		for rune_id: String in RUNES:
			for index: int in 50:
				shots.append(_shot(source, rune_id, shots.size()))
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["friendly_count"] == 600 and stats["core_instances"] == 600 and stats["head_instances"] == 600, "Every one of 600 friendly projectiles receives a real atlas head while preserving the legacy core count")
	_check(stats["body_instances"] == 150, "Exactly the 150 ember projectiles receive colored body/glow instances")
	_check(stats["bounce_instances"] == 200, "All 200 bounce projectiles retain their rings")
	_check(stats["total_visible_instances"] == 950, "Mixed families use the expected body/head/ring instance total")
	_check(_visible_heads(painter) == 600 and painter.bodies.visible_instance_count == 150, "Visible MultiMesh counts match the full mixed population")
	_check(stats["allocated_instances"] == _allocated(painter) and _allocated(painter) <= CombatSim.SHOT_LIMIT * 3, "Actual GPU buffer capacities stay within the global instance budget")
	_check(stats["family_counts"].size() == 12 and stats["trail_families"] == 12 and stats["head_families"] == 12, "Four sources and three runes remain twelve distinct trail and head drawing families")
	_check(stats["head_gpu_batches"] == 1 and stats["allocated_head_instances"] == 600, "Twelve logical families share one600-instance physical head allocation")
	_check_head_mapping(painter, shots)
	for source: String in SOURCES:
		for rune_id: String in RUNES:
			var key: String = source + ":" + rune_id
			_check(stats["family_counts"].get(key, 0) == 50, "Mixed source/rune population is retained: " + key)
			_check(painter.trails.has(key) and painter.trails[key].points.size() == 100, "Every projectile contributes one trail segment: " + key)
			_check(painter.heads.has(key) and painter.heads[key].cursor == 50, "Every legacy source/rune projectile retains a visible textured head: " + key)
			var expected_wing_points: int = 200 if rune_id == "pierce" or source == "frost" else 0
			_check(painter.trails[key].wings.size() == expected_wing_points, "Pierce and frost wing rules are retained: " + key)

func _test_worst_case_capacity() -> void:
	var shots: Array[CombatSim.Shot] = []
	for index: int in CombatSim.SHOT_LIMIT:
		shots.append(_shot("ember", "bounce", index))
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["friendly_count"] == CombatSim.SHOT_LIMIT, "The full 1600-projectile simulation limit remains visible")
	_check(stats["body_instances"] == CombatSim.SHOT_LIMIT and stats["head_instances"] == CombatSim.SHOT_LIMIT and _visible_heads(painter) == CombatSim.SHOT_LIMIT, "The heaviest family retains every colored body and baked white core head")
	_check(stats["bounce_instances"] == CombatSim.SHOT_LIMIT, "All 1600 worst-case bounce rings remain visible")
	_check(stats["total_visible_instances"] == CombatSim.SHOT_LIMIT * 3, "Ember plus bounce uses exactly three instances per projectile")
	_check(_allocated(painter) == CombatSim.SHOT_LIMIT * 3, "The worst case reaches but never exceeds the fixed GPU instance budget")
	_check_head_mapping(painter, shots)
	_check(painter.rings.size() == 1 and painter.rings.has(11.0), "Equal-radius bounce shots share one ring mesh family")
	if painter.rings.has(11.0):
		var ring = painter.rings[11.0]
		_check(ring.multimesh.visible_instance_count == CombatSim.SHOT_LIMIT, "The shared ring MultiMesh exposes every worst-case ring")
		_check(is_equal_approx(ring.radius, 11.0), "Bounce ring centerline stays at projectile radius plus three pixels")
		var arrays: Array = ring.multimesh.mesh.surface_get_arrays(0)
		_check(not arrays.is_empty(), "Shared ring geometry has readable vertex data")
		if not arrays.is_empty():
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var inner_count: int = 0
			var outer_count: int = 0
			for vertex in vertices:
				var distance: float = Vector2(vertex.x, vertex.y).length()
				if is_equal_approx(distance, 10.5):
					inner_count += 1
				elif is_equal_approx(distance, 11.5):
					outer_count += 1
			_check(vertices.size() == 48 and inner_count == 24 and outer_count == 24, "The eight-sided ring remains one pixel thick instead of scaling its width")
	var narrowed: Array[CombatSim.Shot] = [_shot("frost", "bounce")]
	painter.rebuild(narrowed)
	_check(painter.rings.size() == 1 and painter.rings.has(9.0), "Changing ring radius releases obsolete ring families")
	_check(_allocated(painter) == CombatSim.SHOT_LIMIT * 2 + 1 and painter.head_multimesh.instance_count == CombatSim.SHOT_LIMIT and painter.head_multimesh.visible_instance_count == 1
		and painter.heads.size() == 1 and painter.heads.has("frost:bounce"), "Shrinking after the worst case releases obsolete ring families while retaining the single exact1600-slot head allocation until empty")
	_check_head_mapping(painter, narrowed, CombatSim.SHOT_LIMIT)

func _test_filter_and_clear() -> void:
	var inactive: CombatSim.Shot = _shot("ember", "bounce")
	inactive.active = false
	var hostile: CombatSim.Shot = _shot("ember", "bounce")
	hostile.hostile = true
	var friendly: CombatSim.Shot = _shot("bone", "pierce")
	var shots: Array[CombatSim.Shot] = [inactive, hostile, friendly]
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["friendly_count"] == 1 and stats["family_counts"] == {"bone:pierce": 1}, "Inactive and hostile shots never enter friendly drawing families")
	_check(stats["body_instances"] == 0 and stats["bounce_instances"] == 0, "Filtered ember/bounce shots allocate no visible bodies or rings")
	_check(stats["trail_families"] == 1 and painter.trails["bone:pierce"].points.size() == 2, "Filtering also applies to trails")
	friendly.active = false
	painter.rebuild(shots)
	stats = painter.get_stats()
	_check(stats["friendly_count"] == 0 and stats["total_visible_instances"] == 0, "Deactivating the final friendly projectile clears every visible instance")
	_check(painter.bodies.visible_instance_count == 0 and _visible_heads(painter) == 0, "Empty frames hide body and head instances")
	_check(painter.rings.is_empty() and painter.trails.is_empty() and painter.heads.is_empty() and stats["family_counts"].is_empty(), "Empty frames retain no old heads, rings, trails or family counts")
	_check(painter.head_multimesh.instance_count == 0 and painter.head_buffer.is_empty() and stats["head_gpu_batches"] == 0, "An empty frame releases the physical head buffer instead of retaining invisible1600-head capacity")
	var replacement: Array[CombatSim.Shot] = [_shot("ember", "blast")]
	painter.rebuild(replacement)
	_check(painter.get_stats()["family_counts"] == {"ember:blast": 1} and painter.trails.size() == 1, "Rebuilding another family does not resurrect stale geometry")
	var empty: Array[CombatSim.Shot] = []
	painter.rebuild(empty)
	_check(painter.get_stats()["allocated_instances"] == CombatSim.SHOT_LIMIT and painter.rings.is_empty() and painter.heads.is_empty(), "An empty rebuild releases variable head and ring buffers without growing the persistent body pool")
	_check_head_mapping(painter, empty)

func _test_global_head_order() -> void:
	var first: CombatSim.Shot = _shot("bone", "", 1)
	var middle: CombatSim.Shot = _shot("ember", "", 2)
	var last: CombatSim.Shot = _shot("bone", "", 3)
	var shots: Array[CombatSim.Shot] = [first, middle, last]
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(shots)
	_check(painter.heads.keys() == ["bone:", "ember:"] and painter.heads["bone:"].start == 0 and painter.heads["ember:"].start == 2, "Interleaved shots flatten by first surviving family, with original in-family order")
	_check_head_mapping(painter, shots)
	shots.assign([middle, last, first])
	painter.rebuild(shots)
	_check(painter.heads.keys() == ["bone:", "ember:"] and painter.heads["ember:"].start == 2, "Reordered input does not reorder already-surviving draw families")
	_check_head_mapping(painter, shots)
	first.active = false
	last.active = false
	painter.rebuild(shots)
	_check(painter.heads.keys() == ["ember:"] and painter.heads["ember:"].start == 0, "Removing a family compacts the actual physical head range")
	_check_head_mapping(painter, shots, 3)
	first.active = true
	shots.assign([first, middle])
	painter.rebuild(shots)
	_check(painter.heads.keys() == ["ember:", "bone:"] and painter.heads["bone:"].start == 1, "A returning family appends after the survivor even when its shot appears first")
	_check_head_mapping(painter, shots, 3)

func _test_trails_and_color() -> void:
	var shots: Array[CombatSim.Shot] = [_shot("ember", "pierce"), _shot("frost", ""), _shot("bone", ""), _shot("scatter", "blast")]
	for shot: CombatSim.Shot in shots:
		shot.position = Vector2(100, 200)
		shot.velocity = Vector2(10, 0)
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(shots)
	_check(painter.trails["ember:pierce"].points == PackedVector2Array([Vector2(76, 200), Vector2(100, 200)]), "Ember keeps its extra six-pixel trail extension")
	_check(painter.trails["ember:pierce"].wings == PackedVector2Array([Vector2(82, 197), Vector2(105, 200), Vector2(82, 203), Vector2(105, 200)]), "Ember piercing wings preserve the old pair of directional strokes")
	_check(painter.trails["frost:"].points == PackedVector2Array([Vector2(75, 200), Vector2(100, 200)]) and painter.trails["frost:"].wings.size() == 4, "Frost keeps its longer trail and wings without requiring pierce")
	_check(painter.trails["bone:"].points == PackedVector2Array([Vector2(82, 200), Vector2(100, 200)]) and painter.trails["bone:"].wings.is_empty(), "Plain bone retains the original eighteen-pixel trail")
	_check(painter.trails["scatter:blast"].points == PackedVector2Array([Vector2(91, 200), Vector2(100, 200)]), "Scatter retains its shorter nine-pixel trail")
	_check(painter.trails["ember:pierce"].color.is_equal_approx(Color("dab779")), "Friendly ember stays pale gold rather than hostile coral")
	_check(painter.trails["scatter:blast"].color.is_equal_approx(shots[3].color.lerp(Color("dca0fa"), 0.35)), "Blast tint preserves the previous color blend")
	_check(is_equal_approx(painter.trails["ember:pierce"].width, shots[0].radius * 1.2), "Batched ember trails retain their source radius width")

func _exact_expected_heads(painter, shots: Array[CombatSim.Shot]) -> PackedFloat32Array:
	var expected := PackedFloat32Array()
	expected.resize(painter.head_buffer.size())
	var cursors: Dictionary = {}
	for shot: CombatSim.Shot in shots:
		if not shot.active or shot.hostile:
			continue
		var key: String = shot.source + ":" + shot.rune
		var head = painter.heads[key]
		var index: int = int(cursors.get(key, 0))
		cursors[key] = index + 1
		var direction: Vector2 = shot.velocity.normalized()
		if direction.is_zero_approx():
			direction = Vector2.RIGHT
		var scale: float = shot.radius / GameCatalog.weapon(shot.source).projectile_radius
		var x: float = direction.x * scale
		var y: float = direction.y * scale
		var values: Array[float] = [x, -y, 0.0, shot.position.x, y, x, 0.0, shot.position.y,
			1.0, 1.0, 1.0, 1.0, float(head.frame) / float(PAINTER_SCRIPT.HEAD_ATLAS_COLUMNS - 1), 0.5, 0.25, 0.0]
		var offset: int = (int(head.start) + index) * PAINTER_SCRIPT.HEAD_INSTANCE_STRIDE
		for channel: int in values.size():
			expected[offset + channel] = values[channel]
	return expected

func _test_reused_shot_families() -> void:
	var shots: Array[CombatSim.Shot] = []
	for definition: ContentDef in GameCatalog.weapons():
		for rune_id: String in RUNES:
			var shot: CombatSim.Shot = _shot(definition.id, rune_id, shots.size())
			shot.velocity = Vector2.ZERO if shots.size() % 4 == 0 else Vector2(17.0, -11.0)
			shot.radius *= 0.75 if shots.size() % 2 == 0 else 1.25
			shots.append(shot)
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(shots)
	_check(var_to_bytes(painter.head_buffer) == var_to_bytes(_exact_expected_heads(painter, shots)), "All catalog/rune heads preserve every original Float32 transform, tint and atlas value byte for byte")
	var full_heads: PackedByteArray = var_to_bytes(painter.head_buffer)
	painter.rebuild(shots, Rect2(20000, 20000, 10, 10))
	_check(var_to_bytes(painter.head_buffer) == full_heads, "Trail view culling changes neither head geometry, color nor instance order")
	for trail in painter.trails.values():
		_check(trail.points.is_empty() and trail.wings.is_empty(), "An offscreen trail view excludes only the pre-existing trail geometry")
	# Simulation pools reuse the same Shot object for different sources and runes.
	var reused: CombatSim.Shot = shots[0]
	reused.source = "ember"
	reused.rune = "bounce"
	reused.radius = GameCatalog.weapon("ember").projectile_radius
	reused.color = Color(0.2, 0.4, 0.8, 0.7)
	shots.reverse()
	painter.rebuild(shots)
	_check_head_mapping(painter, shots)
	_check(var_to_bytes(painter.head_buffer) == var_to_bytes(_exact_expected_heads(painter, shots)), "Reused and reordered Shot objects bind their new family without stale cached heads or altered Float32 values")
	var trail = painter.trails["ember:bounce"]
	_check(trail.last_shot == reused and trail.color == Color("dab779"), "Family style still comes from the final current shot and preserves ember's original fixed tint")
	for key: String in painter.trails:
		_check(painter.trails[key].head == painter.heads[key], "Each current trail references its matching surviving head family: " + key)
	for ring in painter.rings.values():
		for index: int in ring.cursor:
			var offset: int = index * PAINTER_SCRIPT.INSTANCE_STRIDE + 8
			var expected := PackedFloat32Array([Color("c7b0f3").r, Color("c7b0f3").g, Color("c7b0f3").b, Color("c7b0f3").a])
			_check(var_to_bytes(ring.buffer.slice(offset, offset + 4)) == var_to_bytes(expected), "Cached bounce tint preserves the original four Float32 channels byte for byte")

func _simulation() -> CombatSim:
	var state := RunState.new()
	state.begin(20261022, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(1000, 550)
	for point: Vector2 in [Vector2(330, 300), Vector2(375, 330), Vector2(420, 300)]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.health = 10000.0
		enemy.max_health = 10000.0
		enemy.action_timer = 9999.0
	for source: String in SOURCES:
		for rune_id: String in RUNES:
			sim.fire_weapon(source, rune_id, Vector2(307, 300), Vector2.RIGHT)
	return sim

func _signature(sim: CombatSim) -> String:
	var data: Array = [sim.rng.state, sim.run.rng.state, str(sim.interactions._rng.state), sim.run.summary(), sim.snapshot(),
		sim.primary_hits, sim.secondary_hits, sim.damage_by_weapon, sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		data.append([shot.slot, shot.active, shot.hostile, shot.position, shot.previous, shot.velocity,
			shot.source, shot.attacker_id, shot.rune, shot.damage, shot.radius, shot.life, shot.remaining,
			shot.hit_ids.duplicate(), shot.homing, shot.slow, shot.color])
	for enemy: CombatSim.Enemy in sim.enemies:
		data.append([enemy.slot, enemy.uid, enemy.active, enemy.position, enemy.velocity, enemy.health,
			enemy.age, enemy.action_timer, enemy.slow_timer, enemy.slow_factor, enemy.hurt_timer])
	for effect: CombatSim.Effect in sim.effects:
		data.append([effect.position, effect.radius, effect.color, effect.life, effect.total, effect.kind])
	return JSON.stringify(data)

func _test_simulation_unchanged() -> void:
	var painted: CombatSim = _simulation()
	var oracle: CombatSim = _simulation()
	var painter = PAINTER_SCRIPT.new()
	var before: String = _signature(painted)
	painter.rebuild(painted.shots)
	_check(_signature(painted) == before, "Preparing projectile geometry changes neither shots, simulation nor either RNG")
	for repeat: int in 3:
		painter.rebuild(painted.shots)
	_check(_signature(painted) == before, "Repeated rebuilds remain pure even when reusing all drawing buffers")
	_check(before == _signature(oracle), "The real-combat oracle starts from the same seeded state")
	painted.step(STEP, Vector2.ZERO)
	oracle.step(STEP, Vector2.ZERO)
	_check(painted.primary_hits > 0 and painted.secondary_hits > 0, "The equivalence fixture actually exercises primary and blast collisions")
	_check(_signature(painted) == _signature(oracle), "A real collision step is identical with or without painter rebuilds")
	before = _signature(painted)
	painter.rebuild(painted.shots)
	_check(_signature(painted) == before, "Rebuilding after actual impacts preserves hit budgets, targets, damage and RNG")
