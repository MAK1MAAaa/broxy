extends SceneTree
## Source-game heads and bounded batches must stay independent of combat state.

const IMPACT = preload("res://scripts/combat/impact_painter.gd")
const HEAD_GPU_STRIDE: int = 16

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_hollow_atlas()
	_test_heads()
	_test_capacity()
	print("ReturnRingPresentation: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _sim() -> CombatSim:
	var state := RunState.new()
	state.begin(20261027, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim


func _test_heads() -> void:
	var sim: CombatSim = _sim()
	for index: int in 4:
		var rune: String = ["", "pierce", "bounce", "blast"][index]
		var shot: CombatSim.Shot = sim.fire_weapon("return_ring", rune, Vector2(150 + index * 170, 320), Vector2.RIGHT)
		if index == 3:
			shot.velocity = Vector2.ZERO
	var painter := ProjectilePainter.new()
	var before: String = _signature(sim)
	painter.rebuild(sim.shots)
	_check(_signature(sim) == before, "Drawing all ring socket states, including zero speed, does not change simulation or RNG")
	_check(painter.family_counts.size() == 4 and painter.get_stats()["friendly_count"] == 4, "The ring retains all four socket identities without a separate rendering pool")
	var original_mesh: Array = painter._head_meshes["return_ring"].surface_get_arrays(0)
	_check(painter.head_multimesh.visible_instance_count == 4 and painter.head_multimesh.mesh == painter.head_mesh and painter.head_multimesh.use_custom_data, "All four ring socket families share one real physical head pool")
	for index: int in 4:
		var rune: String = ["", "pierce", "bounce", "blast"][index]
		var shot: CombatSim.Shot = sim.shots[index]
		var trail: ProjectilePainter.TrailBatch = painter.trails["return_ring:" + rune]
		var head = painter.heads["return_ring:" + rune]
		_check(head.frame == 7 and head.source == "return_ring" and head.cursor == 1 and head.capacity >= 1 and head.start >= 0 and head.start < painter.head_multimesh.visible_instance_count, "Each socket state renders one real physical head from the hollow ring frame: " + rune)
		_check(head.texture == painter.atlas_texture and painter._head_meshes[head.source].surface_get_arrays(0) == original_mesh, "Socket states preserve the same original ring texture and authored UV evidence: " + rune)
		var transform: Transform2D = _head_transform(painter.head_buffer, head.start)
		_check(transform.is_equal_approx(Transform2D(0.0, shot.position)), "The real hollow head remains full-size at its shot position, including zero velocity: " + rune)
		var offset: int = head.start * HEAD_GPU_STRIDE
		var custom := Color(painter.head_buffer[offset + 12], painter.head_buffer[offset + 13], painter.head_buffer[offset + 14], painter.head_buffer[offset + 15])
		_check(custom.is_equal_approx(Color(7.0 / 31.0, 0.5, 0.25, 0.0)) and int(round(custom.r * 31.0)) == 7, "Every physical ring head selects original atlas column seven and the head-shader sentinels: " + rune)
		var tails_clear: bool = true
		for endpoint: int in range(0, trail.points.size(), 2):
			tails_clear = tails_clear and CombatSim._segment_distance_squared(shot.position, trail.points[endpoint], trail.points[endpoint + 1]) >= 99.9
		for endpoint: int in range(0, trail.wings.size(), 2):
			tails_clear = tails_clear and CombatSim._segment_distance_squared(shot.position, trail.wings[endpoint], trail.wings[endpoint + 1]) >= 99.9
		_check(tails_clear, "Short tail and pierce rails stay behind the hollow head: " + rune)
		if DisplayServer.get_name() != "headless":
			_check(painter.head_multimesh.get_instance_transform_2d(head.start).is_equal_approx(transform), "Native GPU readback confirms a visible full-scale ring, rather than a hidden zero-scale core: " + rune)
			var gpu_custom: Color = painter.head_multimesh.get_instance_custom_data(head.start)
			_check(int(round(gpu_custom.r * 31.0)) == 7 and gpu_custom.g == 0.5 and gpu_custom.b == 0.25 and gpu_custom.a == 0.0, "The real GPU ring instance retains its decoded original frame and exact binary shader sentinels: " + rune)
	for repeat: int in 3:
		painter.rebuild(sim.shots)
	_check(_signature(sim) == before and painter._head_meshes["return_ring"].surface_get_arrays(0) == original_mesh, "Repeated atlas transforms preserve shots, flight phases and shared UV geometry")
	var impact = IMPACT.new()
	impact.add_hit(Vector2(450, 300), "return_ring", 71)
	impact.add_hit(Vector2(450, 300), "return_ring", 71)
	impact.rebuild()
	_check(impact.active_count() == 1 and impact.get_stats()["draw_commands"] == 2, "The new weapon reuses one outlined ordinary impact mark without duplicate feedback")


func _test_hollow_atlas() -> void:
	var painter := ProjectilePainter.new()
	_check(painter.atlas_texture != null and painter.atlas_texture.resource_path == AdventureArt.path("res://assets/fx/projectile_heads.svg"), "The displayed texture uses the tested authored pixel head atlas")
	var native_image: Image = painter.atlas_texture.get_image()
	var amulet := load(AdventureArt.FAN_ROOT + "icons/return_ring.png") as Texture2D
	_check(native_image != null and native_image.get_size() == Vector2i(512, 64), "The imported source-game PNG retains the declared eight-frame atlas")
	if native_image != null:
		_check(native_image.get_region(Rect2i(448, 0, 64, 64)).get_data() == amulet.get_image().get_data(), "The actual return-flight head preserves the complete original amulet image")
	var runtime_image: Image = painter.head_atlas_texture.get_image()
	_check(runtime_image != null and runtime_image.get_size() == Vector2i(2048, 64) and native_image != null and runtime_image.get_region(Rect2i(448, 0, 64, 64)).get_data() == native_image.get_region(Rect2i(448, 0, 64, 64)).get_data(), "The one physical head atlas copies the complete original amulet column without regenerating or resizing pixels")
	# Keep checking the preserved historical art independently of the runtime reskin.
	var image := Image.new()
	var error: Error = image.load_svg_from_string(FileAccess.get_file_as_string(AdventureArt.ROOT + "fx/projectile_heads.svg"))
	_check(error == OK and image.get_size() == Vector2i(512, 64), "The actual SVG can be rasterized at its declared eight-frame resolution")
	if error != OK or image.get_size() != Vector2i(512, 64):
		return
	var opaque_pixels: int = 0
	var hollow: bool = true
	var bounded: bool = true
	for y: int in 64:
		for x: int in range(448, 512):
			if image.get_pixel(x, y).a <= 0.02:
				continue
			opaque_pixels += 1
			var distance: float = (Vector2(x, y) + Vector2.ONE * 0.5).distance_to(Vector2(480, 32))
			hollow = hollow and distance > 6.0
			bounded = bounded and distance <= 22.5
	_check(hollow and opaque_pixels > 60, "The real return-ring frame has visible blades and a transparent central three-world-pixel disc")
	_check(bounded, "The three-blade texture remains inside the authored twenty-pixel envelope plus antialiasing")
	if DisplayServer.get_name() != "headless":
		_check(native_image != null and not native_image.is_empty() and native_image.get_region(Rect2i(448, 0, 64, 64)).get_used_rect().has_area(), "The imported GPU texture exposes a visible original amulet head")


static func _head_transform(buffer: PackedFloat32Array, index: int) -> Transform2D:
	var offset: int = index * HEAD_GPU_STRIDE
	return Transform2D(Vector2(buffer[offset], buffer[offset + 4]), Vector2(buffer[offset + 1], buffer[offset + 5]), Vector2(buffer[offset + 3], buffer[offset + 7]))


func _test_capacity() -> void:
	var sim: CombatSim = _sim()
	var allocated: int = 0
	for index: int in CombatSim.SHOT_LIMIT:
		var shot: CombatSim.Shot = sim.fire_weapon("return_ring", "bounce", Vector2(300 + index % 50, 300 + index / 50), Vector2.RIGHT)
		allocated += 1 if shot != null else 0
	_check(allocated == CombatSim.SHOT_LIMIT, "The ordinary shot pool can be filled entirely with the new weapon")
	var painter := ProjectilePainter.new()
	var before: String = _signature(sim)
	painter.rebuild(sim.shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["friendly_count"] == CombatSim.SHOT_LIMIT and stats["allocated_instances"] <= 4800 and stats["total_visible_instances"] <= 4800, "A full pool of bounce rings stays inside the existing 4800-instance budget")
	_check(painter.trails.size() == 1 and painter.heads.size() == 1 and painter.heads["return_ring:bounce"].cursor == CombatSim.SHOT_LIMIT and painter.heads["return_ring:bounce"].start == 0 and painter.head_multimesh.visible_instance_count == CombatSim.SHOT_LIMIT and stats["head_instances"] == CombatSim.SHOT_LIMIT, "A full pool shares one UV family with all 1600 real hollow heads visible")
	_check(_signature(sim) == before, "Pressure render preparation leaves all return timers and hit budgets untouched")
	var empty: Array[CombatSim.Shot] = []
	painter.rebuild(empty)
	_check(painter.trails.is_empty() and painter.heads.is_empty() and painter.rings.is_empty() and painter.head_multimesh.visible_instance_count == 0 and painter.get_stats()["total_visible_instances"] == 0, "Empty rebuilding releases the head family, tails, bounce rings and all visible instances")


func _signature(sim: CombatSim) -> String:
	var result: Array = [sim.rng.state, sim.run.rng.state, sim.run.summary(), sim._shot_free, sim.snapshot()]
	for shot: CombatSim.Shot in sim.shots:
		result.append([shot.active, shot.source, shot.rune, shot.position, shot.previous, shot.velocity,
			shot.damage, shot.life, shot.remaining, shot.innate_remaining, shot.hit_ids, shot.return_after,
			shot.returning, shot.return_cancelled, shot.return_speed])
	return JSON.stringify(result)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
