extends SceneTree
## Trail styling must preserve combat state, endpoint batches and the instance cap.

const PAINTER_SCRIPT = preload("res://scripts/combat/projectile_painter.gd")
const SOURCES: PackedStringArray = ["bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring"]
const RUNES: PackedStringArray = ["", "pierce", "bounce", "blast"]
const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_styles()
	_test_heterogeneous_family()
	_test_real_combat_purity()
	_test_pressure_budget()
	print("TrailReadability: %d assertions, %d failures; native GPU readback=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _simulation() -> CombatSim:
	var state := RunState.new()
	state.begin(20261024, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(1040, 555)
	for point: Vector2 in [Vector2(615, 320), Vector2(660, 320), Vector2(710, 320)]:
		var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.health = 100000.0
		enemy.max_health = enemy.health
		enemy.action_timer = 9999.0
	for source: String in SOURCES:
		for rune: String in RUNES:
			sim.fire_weapon(source, rune, Vector2(595, 320), Vector2.RIGHT)
	return sim


func _test_styles() -> void:
	var sim: CombatSim = _simulation()
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(sim.shots)
	_check(painter.get_stats()["family_counts"].size() == SOURCES.size() * RUNES.size(), "All catalog weapons and four socket states receive their existing drawing families")
	for source: String in SOURCES:
		var definition: ContentDef = GameCatalog.weapon(source)
		for rune: String in RUNES:
			var key: String = source + ":" + rune
			var trail = painter.trails[key]
			var style = trail.style
			var base_width: float = definition.projectile_radius * (0.25 if source == "return_ring" else 0.55 if source in ["crescent", "comet"] else 1.2)
			_check(is_equal_approx(trail.width, base_width), "Source-radius width remains available without changing geometry: " + key)
			if source == "ember":
				_check(not style.has_halo and is_zero_approx(style.halo_width) and is_zero_approx(style.halo_color.a), "Ember retains one trail command without an added halo: " + key)
				_check(is_equal_approx(style.main_color.a, 0.40) and is_equal_approx(style.main_width, base_width), "Ember keeps its authored opacity and radius width: " + key)
			else:
				_check(style.has_halo and is_equal_approx(style.main_color.a, 0.58) and is_equal_approx(style.halo_color.a, 0.10), "Friendly trail opacity leaves the fully legible heads and sigils in charge: " + key)
				_check(is_equal_approx(style.main_width, base_width * 0.72) and is_equal_approx(style.halo_width, base_width * 1.55), "Main and halo widths narrow relative to the unmodified source width: " + key)
			_check(Color(style.main_color, 1.0).is_equal_approx(Color(trail.color, 1.0)), "Readability styling preserves the weapon/rune RGB identity: " + key)
			if style.has_halo:
				_check(Color(style.halo_color, 1.0).is_equal_approx(Color(trail.color, 1.0)), "The subdued halo retains the same weapon/rune RGB: " + key)
	_check(is_equal_approx(painter.trails["frost:"].style.main_width, 5.184)
		and is_equal_approx(painter.trails["frost:"].style.halo_width, 11.16), "Frost's actual display strokes narrow from 7.2/16.776px to 5.184/11.16px")
	_check(is_equal_approx(painter.trails["comet:"].style.main_width, 4.356)
		and is_equal_approx(painter.trails["comet:"].style.halo_width, 9.3775), "Comet's actual display strokes narrow from 6.05/14.0965px to 4.356/9.3775px")
	_check_authored_tail_geometry(sim, painter)
	_check_global_head_mapping(sim, painter)


func _test_heterogeneous_family() -> void:
	var state := RunState.new()
	state.begin(20261031, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	var large: CombatSim.Shot = sim.fire_weapon("frost", "pierce", Vector2(150, 80), Vector2.RIGHT)
	large.radius = 20.0
	large.color = Color.RED
	var other: CombatSim.Shot = sim.fire_weapon("bone", "", Vector2(150, 150), Vector2.UP)
	var small: CombatSim.Shot = sim.fire_weapon("frost", "pierce", Vector2(150, 80), Vector2.RIGHT)
	small.radius = 0.5
	small.color = Color.GREEN
	var last: CombatSim.Shot = sim.fire_weapon("frost", "pierce", Vector2(260, 80), Vector2.RIGHT)
	last.radius = 0.5
	last.color = Color.BLUE
	var painter = PAINTER_SCRIPT.new()
	var view := Rect2(100, 100, 100, 100)
	var before: String = _signature(sim)
	painter.rebuild(sim.shots, view)
	_check(painter.trails.keys() == ["frost:pierce", "bone:"] and painter.heads.keys() == ["frost:pierce", "bone:"], "Interleaved shots preserve the first-seen family order for trails and heads")
	var direction: Vector2 = large.velocity.normalized()
	var tail: Vector2 = large.position - direction * 25.0
	var expected := PackedVector2Array([tail, large.position])
	var side: Vector2 = direction.orthogonal() * 3.0
	var tip: Vector2 = large.position + direction * 5.0
	var wings := PackedVector2Array([tail + side, tip, tail - side, tip])
	_check(painter.trails["frost:pierce"].points == expected and painter.trails["frost:pierce"].wings == wings, "A large boundary trail uses its own radius for conservative culling even when the last family shot is tiny")
	_check(painter.trails["frost:pierce"].color == Color.BLUE and is_equal_approx(painter.trails["frost:pierce"].width, 0.6), "The final active shot determines family RGB and width even when that shot's own trail is outside the view")
	_check(_signature(sim) == before, "Family metadata preparation cannot mutate custom shot radii, colors, ordering or simulation")
	_check_global_head_mapping(sim, painter)
	last.radius = 20.0
	last.color = Color(0.8, 0.3, 0.6)
	before = _signature(sim)
	painter.rebuild(sim.shots, view)
	_check(painter.trails["frost:pierce"].points == expected and painter.trails["frost:pierce"].wings == wings, "A large final family width cannot make the earlier tiny outside trail falsely visible")
	_check(painter.trails["frost:pierce"].color == last.color and is_equal_approx(painter.trails["frost:pierce"].width, 24.0), "A repeated rebuild refreshes final-shot custom appearance without changing geometric endpoints")
	_check(painter.get_stats()["friendly_count"] == 4 and painter.get_stats()["head_instances"] == 4 and _signature(sim) == before, "Culling and family styling retain every actual head and leave the custom simulation intact")
	_check_global_head_mapping(sim, painter)
	other.active = false
	painter.rebuild(sim.shots, view)
	_check(painter.trails.keys() == ["frost:pierce"] and painter.heads.keys() == ["frost:pierce"], "Disappearing interleaved families are removed without reordering the survivor")
	_check_global_head_mapping(sim, painter, 4)


func _test_real_combat_purity() -> void:
	var painted: CombatSim = _simulation()
	var oracle: CombatSim = _simulation()
	var painter = PAINTER_SCRIPT.new()
	var before: String = _signature(painted)
	painter.rebuild(painted.shots)
	var endpoints: String = _endpoint_signature(painter)
	var heads: String = _head_signature(painter)
	for repeat: int in 3:
		painter.rebuild(painted.shots)
		_check(_endpoint_signature(painter) == endpoints and _head_signature(painter) == heads, "Repeated styling preserves every original trail/wing endpoint and each real head transform")
	_check(_signature(painted) == before and _signature(oracle) == before, "Style preparation preserves both RNGs, projectile budgets, enemies and run state")
	painted.step(STEP, Vector2.ZERO)
	oracle.step(STEP, Vector2.ZERO)
	_check(painted.primary_hits > 0 and painted.secondary_hits > 0, "The oracle comparison includes real direct and blast collisions")
	_check(_signature(painted) == _signature(oracle), "A real collision step remains identical with or without rendering preparation")
	before = _signature(painted)
	painter.rebuild(painted.shots)
	_check(_signature(painted) == before, "Refreshing styles after collisions does not change surviving shots or hit exclusions")
	var empty: Array[CombatSim.Shot] = []
	painter.rebuild(empty)
	_check(painter.trails.is_empty() and painter.heads.is_empty() and painter.rings.is_empty()
		and painter.get_stats()["total_visible_instances"] == 0 and painter.head_multimesh.instance_count == 0
		and painter.head_buffer.is_empty() and painter.get_stats()["head_gpu_batches"] == 0, "An empty rebuild leaves no old styled trail, ring, head or retained physical head allocation")


func _test_pressure_budget() -> void:
	var state := RunState.new()
	state.begin(20261024, "bone")
	var world := CombatWorld.new()
	var sound := SoundBank.new()
	world.sound = sound
	world.begin(state)
	world.sim.populate_stress()
	world.enable_rune_stress(true)
	var before: String = _signature(world.sim)
	var painter = PAINTER_SCRIPT.new()
	painter.rebuild(world.sim.shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["friendly_count"] == 600 and stats["family_counts"].size() == GameCatalog.weapons().size() * GameCatalog.runes().size(), "The formal pressure fixture retains six hundred shots across all catalog weapon/rune families")
	_check(stats["allocated_instances"] <= 4800 and stats["total_visible_instances"] <= 4800, "Trail styling introduces no projectile GPU instances")
	var trail_commands: int = 0
	for trail in painter.trails.values():
		trail_commands += 2 if trail.style.has_halo else 1
		trail_commands += 0 if trail.wings.is_empty() else 1
	_check(trail_commands == 146, "The twenty-one-weapon pressure scene retains all one hundred forty-six tail and wing submissions")
	var visible_heads: int = 0
	for head in painter.heads.values():
		visible_heads += head.cursor
	_check(stats["head_gpu_batches"] == 1 and stats["head_families"] == 63 and painter.heads.size() == 63 and visible_heads == 600
		and painter.head_multimesh.visible_instance_count == visible_heads and painter.head_multimesh.instance_count == visible_heads
		and stats["allocated_head_instances"] == visible_heads and stats["head_instances"] == visible_heads, "Sixty-three logical texture families retain six hundred genuine head instances in one physical GPU batch")
	_check_global_head_mapping(world.sim, painter)
	_check(_signature(world.sim) == before, "Preparing the full pressure scene does not advance or modify its simulation")
	world.free()
	sound.free()


func _check_global_head_mapping(sim: CombatSim, painter, retained_capacity: int = -1) -> void:
	var families: Dictionary = {}
	var count: int = 0
	for shot: CombatSim.Shot in sim.shots:
		if not shot.active or shot.hostile:
			continue
		if count == CombatSim.SHOT_LIMIT:
			break
		var key: String = shot.source + ":" + shot.rune
		if not families.has(key):
			families[key] = []
		families[key].append(shot)
		count += 1
	var cpu: PackedFloat32Array = painter.head_buffer
	var native_readback: bool = DisplayServer.get_name() != "headless"
	var gpu := PackedFloat32Array()
	if native_readback:
		gpu = painter.head_multimesh.buffer
	var capacity: int = retained_capacity if retained_capacity >= 0 else count
	_check(cpu.size() == capacity * PAINTER_SCRIPT.HEAD_INSTANCE_STRIDE
		and painter.head_multimesh.instance_count == capacity and painter.head_multimesh.visible_instance_count == count,
		"The physical head preparation includes every friendly head, including all offscreen and differently sized shots")
	if native_readback:
		_check(gpu.size() == cpu.size(), "The actual native GPU upload contains every prepared head instance")
	var frames: Dictionary = {}
	for index: int in PAINTER_SCRIPT.HEAD_SOURCES.size():
		frames[PAINTER_SCRIPT.HEAD_SOURCES[index]] = index
	for definition: ContentDef in GameCatalog.weapons():
		if not frames.has(definition.id):
			frames[definition.id] = frames.size()
	var start: int = 0
	for key: String in painter.heads:
		var head = painter.heads[key]
		var shots: Array = families.get(key, [])
		var matches: bool = head.start == start and head.cursor == shots.size() and head.capacity >= head.cursor
		var native_matches: bool = gpu.size() == cpu.size()
		matches = matches and head.source == key.get_slice(":", 0) and head.frame == frames.get(head.source, 0) and head.frame >= 0 and head.frame < 32
		for local: int in shots.size():
			var shot: CombatSim.Shot = shots[local]
			var definition: ContentDef = GameCatalog.weapon(shot.source)
			var direction: Vector2 = shot.velocity.normalized()
			if direction.is_zero_approx():
				direction = Vector2.RIGHT
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
		_check(matches, "Global head mapping preserves family order, each shot's authored transform and exact atlas/color channels: " + key)
		if native_readback:
			_check(native_matches, "Actual native GPU readback preserves the family's full transform/color data and exact decoded atlas columns: " + key)
		start += head.cursor
	_check(start == count and painter.heads.size() == families.size(), "Flattened family ranges neither omit nor duplicate any live head")


func _endpoint_signature(painter) -> String:
	var result: Dictionary = {}
	for key: String in painter.trails:
		var trail = painter.trails[key]
		result[key] = [trail.points, trail.wings]
	return JSON.stringify(result)


func _head_signature(painter) -> String:
	var families: Dictionary = {}
	for key: String in painter.heads:
		var head = painter.heads[key]
		families[key] = [head.source, head.frame, head.cursor, head.capacity, head.start, head.base_radius]
	return JSON.stringify({"families": families, "head_buffer": painter.head_buffer,
		"gpu_buffer": painter.head_multimesh.buffer, "capacity": painter.head_multimesh.instance_count,
		"visible": painter.head_multimesh.visible_instance_count})


func _check_authored_tail_geometry(sim: CombatSim, painter) -> void:
	var expected_points: Dictionary = {}
	var expected_wings: Dictionary = {}
	for shot: CombatSim.Shot in sim.shots:
		if not shot.active or shot.hostile:
			continue
		var key: String = shot.source + ":" + shot.rune
		if not expected_points.has(key):
			expected_points[key] = PackedVector2Array()
			expected_wings[key] = PackedVector2Array()
		var direction: Vector2 = shot.velocity.normalized()
		if shot.source == "return_ring" and direction.is_zero_approx():
			direction = Vector2.RIGHT
		var length: float = {"frost": 25.0, "scatter": 9.0, "storm": 13.0, "comet": 29.0}.get(shot.source, 18.0)
		var tail: Vector2 = shot.position - direction * length
		var points: PackedVector2Array = expected_points[key]
		points.append(shot.position - direction * 16.0 if shot.source == "return_ring" else tail - direction * 6.0 if shot.source == "ember" else tail)
		points.append(shot.position - direction * 10.0 if shot.source == "return_ring" else shot.position)
		expected_points[key] = points
		if shot.rune == "pierce" or shot.source == "frost":
			var wings: PackedVector2Array = expected_wings[key]
			var side: Vector2 = direction.orthogonal() * 3.0
			var wing_tail: Vector2 = shot.position - direction * 16.0 if shot.source == "return_ring" else tail
			var wing_head: Vector2 = shot.position - direction * 10.0 if shot.source == "return_ring" else shot.position + direction * 5.0
			wings.append_array(PackedVector2Array([wing_tail + side, wing_head + side if shot.source == "return_ring" else wing_head,
				wing_tail - side, wing_head - side if shot.source == "return_ring" else wing_head]))
			expected_wings[key] = wings
	for key: String in expected_points:
		_check(painter.trails[key].points == expected_points[key] and painter.trails[key].wings == expected_wings[key], "Atlas heads preserve every authored tail and wing endpoint for source/socket family: " + key)


func _signature(sim: CombatSim) -> String:
	var result: Array = [sim.rng.state, sim.run.rng.state, str(sim.interactions._rng.state), sim.run.summary(), sim.snapshot(),
		sim.primary_hits, sim.secondary_hits, sim.damage_by_weapon, sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		result.append([shot.slot, shot.active, shot.hostile, shot.source, shot.attacker_id, shot.position,
			shot.previous, shot.velocity, shot.radius, shot.color, shot.damage, shot.life, shot.rune,
			shot.remaining, shot.innate_remaining, shot.hit_ids.duplicate(), shot.homing, shot.slow])
	for enemy: CombatSim.Enemy in sim.enemies:
		result.append([enemy.slot, enemy.uid, enemy.active, enemy.position, enemy.velocity, enemy.health,
			enemy.max_health, enemy.age, enemy.action_timer, enemy.slow_timer, enemy.slow_factor,
			enemy.hurt_timer, enemy.mode, enemy.charge_direction])
	for effect: CombatSim.Effect in sim.effects:
		result.append([effect.position, effect.radius, effect.color, effect.life, effect.total, effect.kind])
	return JSON.stringify(result)
