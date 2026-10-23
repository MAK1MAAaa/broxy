extends SceneTree
## Headless behavior and geometry checks, not native visual/readability evidence.

const HELPER_PATH: String = "res://scripts/combat/impact_painter.gd"
const SOURCES: Array[String] = ["bone", "frost", "ember", "scatter"]

var _checks: int = 0
var _failures: int = 0
var _helper: Script


class DrawProbe:
	extends Node2D
	var painter: RefCounted
	var drew: bool = false

	func _draw() -> void:
		if painter != null:
			painter.call("draw", self)
			drew = true


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	if not FileAccess.file_exists(HELPER_PATH):
		_check(false, "The bounded primary-hit painter exists")
		_finish()
		return
	_helper = load(HELPER_PATH)
	var painter: RefCounted = _helper.new()
	for method: String in ["add_hit", "advance", "clear", "rebuild", "draw", "get_stats", "active_count"]:
		if not painter.has_method(method):
			_check(false, "The impact painter provides its required method: " + method)
			_finish()
			return
	_test_pool_and_validation(painter)
	_test_deduplication(painter)
	await _test_geometry_and_readonly(painter)
	await _test_world()
	await _test_paused_main_settings()
	paused = false
	await process_frame
	_finish()


func _test_pool_and_validation(painter: RefCounted) -> void:
	var initial: Dictionary = painter.call("get_stats")
	_check(initial == {"capacity": 32, "active_marks": 0, "free_marks": 32, "allocated_marks": 32, "draw_commands": 0, "peak_active": 0},
		"Construction allocates exactly 32 reusable marks and no active geometry")
	var original_ids: Array[int] = _pool_ids(painter)
	_check(original_ids.size() == 32 and _unique_free(painter), "Pool and free-list identities start unique and complete")
	var before: Dictionary = _marks_snapshot(painter)
	painter.call("add_hit", Vector2.ZERO, "unknown", 1)
	painter.call("add_hit", Vector2.INF, "bone", 1)
	painter.call("add_hit", Vector2(NAN, 0), "frost", 1)
	_check(_marks_snapshot(painter) == before, "Unknown sources and nonfinite positions do not allocate or change peak usage")
	for index: int in 32:
		painter.call("add_hit", Vector2(200 + index, 300), SOURCES[index % 4], index)
	_check(int(painter.call("active_count")) == 32 and painter.call("get_stats")["free_marks"] == 0 and painter.get("peak_active") == 32,
		"A dense barrage fills the fixed 32-mark pool and reports peak usage")
	before = _marks_snapshot(painter)
	for index: int in 50:
		painter.call("add_hit", Vector2(900, 500), "bone", 1000 + index)
	_check(_marks_snapshot(painter) == before, "A full pool drops extra hits without replacing marks, changing ages or allocating")
	_check(_pool_ids(painter) == original_ids, "Filling and exhausting the pool creates no new mark objects")
	for invalid_delta: float in [0.0, -1.0, INF, NAN]:
		painter.call("advance", invalid_delta)
	_check(_marks_snapshot(painter) == before, "Zero, negative and nonfinite time cannot corrupt impact lifetimes")
	painter.call("advance", 0.119)
	_check(int(painter.call("active_count")) == 32, "Every hit remains active just before its 0.12-second expiry")
	painter.call("advance", 0.0011)
	_check(int(painter.call("active_count")) == 0 and _unique_free(painter), "Crossing 0.12 seconds returns all marks to the pool")
	for cycle: int in 12:
		for index: int in 32:
			painter.call("add_hit", Vector2(300, 300), SOURCES[index % 4], index)
		painter.call("advance", 0.12)
		_check(_pool_ids(painter) == original_ids and _unique_free(painter) and int(painter.call("active_count")) == 0,
			"Repeated full-pool reuse neither leaks nor duplicates objects: " + str(cycle))
	painter.call("clear")
	_check(painter.call("get_stats") == initial, "Explicit clearing resets counts, geometry and peak usage")
	var cleared: bool = true
	for mark: RefCounted in painter.get("_pool"):
		cleared = cleared and mark.get("origin") == Vector2.ZERO and mark.get("target_uid") == -1 and mark.get("age") == 0.0 and mark.get("life") == 0.0
	_check(cleared, "Cleared pool entries retain no target, origin or lifetime from an old hit")


func _test_deduplication(painter: RefCounted) -> void:
	painter.call("clear")
	var point := Vector2(450, 300)
	painter.call("add_hit", point, "bone", 7)
	painter.call("advance", 0.049)
	var before: Dictionary = _marks_snapshot(painter)
	painter.call("add_hit", point + Vector2(100, 0), "bone", 7)
	_check(_marks_snapshot(painter) == before, "The same source and target before 0.05 seconds is ignored without moving or refreshing its mark")
	painter.call("advance", 0.0711)
	_check(int(painter.call("active_count")) == 0, "An ignored repeated hit cannot extend the original 0.12-second lifetime")
	painter.call("add_hit", point, "bone", 7)
	painter.call("advance", 0.05)
	painter.call("add_hit", point, "bone", 7)
	_check(int(painter.call("active_count")) == 2, "At exactly 0.05 seconds a new hit creates a fresh mark")
	painter.call("add_hit", point, "frost", 7)
	painter.call("add_hit", point, "bone", 8)
	_check(int(painter.call("active_count")) == 4, "Different weapon kinds and target UIDs never merge")
	painter.call("add_hit", point, "bone", -1)
	painter.call("add_hit", point, "bone", -1)
	_check(int(painter.call("active_count")) == 6, "Hits with unknown negative target UID remain separate observations")
	painter.call("clear")


func _test_geometry_and_readonly(painter: RefCounted) -> void:
	var point := Vector2(640, 360)
	var shapes: Dictionary = {}
	for source: String in SOURCES:
		painter.call("clear")
		painter.call("add_hit", point, source, 1)
		var marks_before: Dictionary = _marks_snapshot(painter)
		painter.call("rebuild")
		_check(_marks_snapshot(painter) == marks_before, "Rebuilding geometry never advances or changes the observation: " + source)
		var points: PackedVector2Array = PackedVector2Array()
		var safe: bool = true
		for batch: RefCounted in painter.get("_batches"):
			var batch_points: PackedVector2Array = batch.get("points")
			var width: float = float(batch.get("width"))
			var color: Color = batch.get("color")
			safe = safe and batch_points.size() % 2 == 0 and is_finite(width) and width > 0.0
			safe = safe and is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)
			for vertex: Vector2 in batch_points:
				safe = safe and vertex.is_finite() and vertex.distance_to(point) + width * 0.5 <= 10.0
				points.append(vertex - point)
		_check(not points.is_empty() and safe, "Finite paired strokes including their width stay within a 10px impact radius: " + source)
		_check(int(painter.call("get_stats")["draw_commands"]) == 1, "One source and fade stage need one drawing command: " + source)
		shapes[str(points)] = true
	_check(shapes.size() == 4, "The four weapon sources produce four distinguishable local shape families")

	painter.call("clear")
	for cohort: int in 3:
		if cohort > 0:
			painter.call("advance", 0.041)
		for kind: int in 4:
			painter.call("add_hit", point, SOURCES[kind], cohort * 4 + kind)
	var before: Dictionary = _marks_snapshot(painter)
	painter.call("rebuild", true)
	var batches_before: Array = _batch_snapshot(painter)
	_check(int(painter.call("active_count")) == 12 and int(painter.call("get_stats")["draw_commands"]) == 12,
		"All four sources at all three fade stages exercise the complete 12-command budget")
	_check((painter.get("_batches") as Array).size() == 12 and _marks_snapshot(painter) == before,
		"Fade batching is fixed-size and independent from mark lifetime state")
	for kind: int in 4:
		var batches: Array = painter.get("_batches")
		var first: Color = batches[kind * 3].get("color")
		var middle: Color = batches[kind * 3 + 1].get("color")
		var last: Color = batches[kind * 3 + 2].get("color")
		_check(first.a > middle.a and middle.a > last.a and last.a > 0.0, "The three visible fade stages decrease opacity: " + SOURCES[kind])
	painter.call("rebuild", true)
	_check(_batch_snapshot(painter) == batches_before and _marks_snapshot(painter) == before, "Repeated rebuilds are deterministic and read-only for active marks")
	var probe := DrawProbe.new()
	probe.painter = painter
	root.add_child(probe)
	probe.queue_redraw()
	await process_frame
	await process_frame
	_check(probe.drew and _batch_snapshot(painter) == batches_before and _marks_snapshot(painter) == before,
		"A real CanvasItem draw callback reads prepared batches without changing marks or geometry")
	probe.queue_free()
	painter.call("rebuild", false)
	_check(int(painter.call("active_count")) == 0 and _unique_free(painter) and painter.get("peak_active") == 0 and int(painter.call("get_stats")["draw_commands"]) == 0,
		"Disabling flash rendering immediately clears marks, batches and peak usage")
	painter.call("rebuild", true)
	_check(int(painter.call("get_stats")["draw_commands"]) == 0, "Re-enabling flash cannot replay cleared old hits")

	seed(9901)
	var expected_random: int = randi()
	seed(9901)
	painter.call("add_hit", point, "bone", 9)
	painter.call("advance", 0.04)
	painter.call("rebuild", true)
	painter.call("clear")
	_check(randi() == expected_random, "Impact allocation, aging and batching consume no global random numbers")


func _test_world() -> void:
	var sound := SoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	if not _has_property(world, "_impact_painter"):
		_check(false, "CombatWorld integrates the primary-hit painter")
		world.queue_free()
		sound.queue_free()
		return
	var painter: RefCounted = world.get("_impact_painter")
	world._on_damage_dealt(Vector2(400, 300), 4.0, "bone", false, 990)
	_check(int(painter.call("active_count")) == 0, "A delayed damage callback before an active simulation cannot create an impact")
	var kinds: Dictionary = {}
	for source: String in SOURCES:
		_prepare_world(world)
		var target: CombatSim.Enemy = _target(world.sim, Vector2(520, 300))
		var events: Array[Dictionary] = []
		_capture_events(world.sim, events)
		world.sim.fire_weapon(source, "", Vector2(470, 300), Vector2.RIGHT)
		_step_until_hit(world.sim)
		_check(world.sim.primary_hits == 1 and events.size() == 1 and not bool(events[0]["secondary"]) and events[0]["source"] == source
			and events[0]["uid"] == target.uid and is_equal_approx(float(events[0]["amount"]), GameCatalog.weapon(source).damage),
			"A real projectile collision emits the catalog weapon's accepted primary damage: " + source)
		_check(int(painter.call("active_count")) == 1, "Accepted primary damage creates one actual impact mark: " + source)
		if int(painter.call("active_count")) > 0:
			var mark: RefCounted = painter.get("_marks")[0]
			_check(mark.get("origin") == events[0]["position"] and mark.get("target_uid") == target.uid,
				"The impact uses the real event center and target identity: " + source)
			kinds[mark.get("kind")] = true
		var run_before: Dictionary = world.sim.run.summary()
		var sim_rng_before: int = world.sim.rng.state
		var run_rng_before: int = world.sim.run.rng.state
		painter.call("rebuild", true)
		_check(world.sim.run.summary() == run_before and world.sim.rng.state == sim_rng_before and world.sim.run.rng.state == run_rng_before,
			"Preparing impact geometry changes neither progression nor combat RNG: " + source)
	_check(kinds.size() == 4, "All four real weapon collisions reach their distinct impact families")

	_prepare_world(world)
	_target(world.sim, Vector2(520, 300))
	_target(world.sim, Vector2(560, 300))
	var splash_events: Array[Dictionary] = []
	_capture_events(world.sim, splash_events)
	world.sim.fire_weapon("bone", "blast", Vector2(470, 300), Vector2.RIGHT)
	_step_until_hit(world.sim)
	_check(world.sim.primary_hits == 1 and world.sim.secondary_hits >= 1 and splash_events.size() >= 2,
		"The blast fixture produces both real primary collision and real secondary splash damage")
	_check(int(painter.call("active_count")) == 1 and painter.get("_marks")[0].get("target_uid") == splash_events[0]["uid"],
		"Real splash damage never creates extra primary-impact marks")
	world._reset_feedback()
	for event: Array in [[Vector2(400, 300), 0.0, "bone", false], [Vector2(400, 300), -1.0, "bone", false],
		[Vector2(400, 300), 4.0, "unknown", false], [Vector2.INF, 4.0, "bone", false], [Vector2(400, 300), 4.0, "bone", true]]:
		world._on_damage_dealt(event[0], event[1], event[2], event[3], 991)
		_check(int(painter.call("active_count")) == 0, "Zero/invalid/non-primary observations do not create impact marks: " + str(event))
	for amount: float in [INF, NAN]:
		var previous_numbers: int = world._numbers.size()
		world._on_damage_dealt(Vector2(400, 300), amount, "bone", false, 992)
		_check(int(painter.call("active_count")) == 0 and world._numbers.size() == previous_numbers,
			"Nonfinite damage cannot create either impact geometry or an old-style floating number")
	world._reset_feedback()
	_prepare_world(world)
	world.settings["flash"] = false
	_target(world.sim, Vector2(520, 300))
	world.sim.fire_weapon("bone", "", Vector2(470, 300), Vector2.RIGHT)
	_step_until_hit(world.sim)
	_check(world.sim.primary_hits == 1 and int(painter.call("active_count")) == 0, "Disabling flash suppresses marks while real primary damage remains accepted")
	world.settings["flash"] = true
	await _test_lifecycle(world, painter)
	_test_draw_order()
	world.queue_free()
	sound.queue_free()


func _test_lifecycle(world: CombatWorld, painter: RefCounted) -> void:
	_prepare_world(world)
	world._on_damage_dealt(Vector2(400, 300), 4.0, "bone", false, 1)
	painter.call("rebuild", true)
	world.stop()
	_check(not world.active and int(painter.call("active_count")) == 0 and _unique_free(painter) and int(painter.call("get_stats")["draw_commands"]) == 0,
		"Stopping combat immediately recycles impacts and cached drawing geometry")
	world._on_damage_dealt(Vector2(400, 300), 4.0, "bone", false, 991)
	_check(int(painter.call("active_count")) == 0 and int(painter.call("get_stats")["draw_commands"]) == 0,
		"A delayed positive damage callback after stop cannot recreate impact marks")
	_prepare_world(world)
	world._on_damage_dealt(Vector2(400, 300), 4.0, "frost", false, 2)
	_prepare_world(world)
	_check(int(painter.call("active_count")) == 0 and painter.get("peak_active") == 0, "Beginning another wave resets old impacts and peak telemetry")
	world._on_damage_dealt(Vector2(400, 300), 4.0, "ember", false, 3)
	var mark: RefCounted = painter.get("_marks")[0]
	var life_before: float = float(mark.get("life"))
	var elapsed_before: float = world.sim.elapsed
	world.set_physics_process(true)
	paused = true
	await process_frame
	await process_frame
	_check(is_equal_approx(float(mark.get("life")), life_before) and world.sim.elapsed == elapsed_before,
		"Pausing the real scene tree freezes impact lifetime together with combat")
	paused = false
	await physics_frame
	await physics_frame
	world.set_physics_process(false)
	_check(float(mark.get("life")) < life_before, "Resuming real physics ages existing impact marks")
	world._advance_feedback(0.2)
	_check(int(painter.call("active_count")) == 0 and _unique_free(painter), "World feedback advancement expires impacts without leaking pool entries")

	_prepare_world(world, true)
	world.sim.boss.position = Vector2(520, 300)
	world.sim.boss.health = 1.0
	world.sim.fire_weapon("bone", "", Vector2(470, 300), Vector2.RIGHT)
	_step_until_hit(world.sim)
	_check(world.sim.complete and world.sim.victory and not world.active and int(painter.call("active_count")) == 0,
		"A real projectile killing the boss clears the mark created earlier in the same terminal step")
	world._on_damage_dealt(Vector2(400, 300), 4.0, "bone", false, 992)
	_check(int(painter.call("active_count")) == 0 and int(painter.call("get_stats")["draw_commands"]) == 0,
		"A late positive damage callback after a completed simulation cannot resurrect terminal impact geometry")
	_prepare_world(world, true)
	world._on_damage_dealt(Vector2(400, 300), 4.0, "scatter", false, 4)
	painter.call("rebuild", true)
	world.sim.sandbox = false
	world.sim.elapsed = world.sim.duration
	world.sim.step(1.0 / 60.0, Vector2.ZERO)
	_check(world.sim.complete and not world.sim.victory and int(painter.call("active_count")) == 0 and int(painter.call("get_stats")["draw_commands"]) == 0,
		"A real boss timeout clears old marks and cached impact strokes")


func _test_paused_main_settings() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app = scene.instantiate()
	# Set this before _ready so neither loading nor the real setting callbacks
	# read or save a personal profile. No profile inspection is needed here.
	app.store.persistent = false
	root.add_child(app)
	_check(not app.store.persistent, "The real Main settings fixture disables profile access before entering the tree")
	app._start_run("bone")
	var world: CombatWorld = app.world
	app.run.begin(2026, "bone")
	world.begin(app.run)
	world.set_physics_process(false)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(1000.0)
	world.sim.player_position = Vector2(200, 500)
	_target(world.sim, Vector2(520, 300))
	world.sim.fire_weapon("bone", "", Vector2(470, 300), Vector2.RIGHT)
	_step_until_hit(world.sim)
	var painter: RefCounted = world.get("_impact_painter")
	painter.call("rebuild", true)
	_check(world.sim.primary_hits == 1 and int(painter.call("active_count")) == 1 and int(painter.call("get_stats")["draw_commands"]) > 0,
		"The Main fixture starts with a real accepted primary collision and prepared visible impact geometry")
	world.set_physics_process(true)
	app._pause()
	app.ui._show_settings(true)
	for frame: int in 4:
		await process_frame
	_check(paused and app.paused and not world.can_process() and world.is_physics_processing(),
		"The actual tree pause, rather than disabling physics callbacks, freezes the Main combat world")
	var before: Dictionary = _main_combat_snapshot(app)
	var marks_before: Dictionary = _marks_snapshot(painter)
	app.ui.setting_changed.emit("flash", false)
	_check(not bool(app.store.settings["flash"]) and not bool(world.settings["flash"]), "The connected UI setting signal reaches Main and the shared world setting")
	_check(int(painter.call("active_count")) == 0 and _unique_free(painter) and int(painter.call("get_stats")["draw_commands"]) == 0 and painter.get("peak_active") == 0,
		"Turning flash off through Main while paused immediately clears existing marks and cached strokes")
	_check(_main_combat_snapshot(app) == before, "The paused flash callback leaves combat, transform, progression, RNG and application flags untouched")
	for frame: int in 3:
		await process_frame
	_check(int(painter.call("active_count")) == 0 and int(painter.call("get_stats")["draw_commands"]) == 0,
		"Paused redraws cannot leave the old impact visible after flash is disabled")
	app.ui.setting_changed.emit("flash", true)
	_check(bool(app.store.settings["flash"]) and bool(world.settings["flash"]), "The connected Main callback can re-enable flash without resuming combat")
	_check(int(painter.call("active_count")) == 0 and int(painter.call("get_stats")["draw_commands"]) == 0,
		"Turning flash back on while paused cannot replay the previous hit")
	_check(_main_combat_snapshot(app) == before and paused and app.paused,
		"Off/on toggling preserves the paused simulation and its original application flags")
	_check(not marks_before["marks"].is_empty(), "The off/on regression begins with a nonempty impact, rather than vacuously testing an empty pool")
	app._resume()
	world.set_physics_process(false)
	world.stop()
	app.sound.shutdown()
	app.queue_free()
	await process_frame


func _main_combat_snapshot(app: Node) -> Dictionary:
	var world: CombatWorld = app.get("world")
	var run: RunState = app.get("run")
	var ui: GameUI = app.get("ui")
	return {"summary": run.summary(), "run_rng": run.rng.state, "sim_rng": world.sim.rng.state,
		"sim_elapsed": world.sim.elapsed, "sim_complete": world.sim.complete, "sim_sandbox": world.sim.sandbox,
		"player_position": world.sim.player_position, "player_velocity": world.sim.player_velocity,
		"world_transform": world.transform, "visual_time": world._visual_time, "world_active": world.active,
		"world_physics_enabled": world.is_physics_processing(), "shake": world._shake,
		"main_screen": app.get("screen"), "main_paused": app.get("paused"), "tree_paused": paused,
		"autopilot": world.autopilot, "stress": world.stress_mode, "rune_stress": world.rune_stress_mode,
		"benchmark": app.get("_benchmark"), "screenshot_clock": app.get("_screenshot_clock"),
		"page_refresh_queued": ui._refresh_queued, "overlay": ui._overlay_mode}


func _prepare_world(world: CombatWorld, boss_wave: bool = false) -> void:
	var state := RunState.new()
	state.begin(2026, "bone")
	if boss_wave:
		state.wave = 8
	world.begin(state)
	world.set_physics_process(false)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(1000.0)
	world.sim.player_position = Vector2(200, 500)


func _target(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var target: CombatSim.Enemy = sim.spawn_enemy("tank", point)
	target.health = 1000.0
	target.max_health = 1000.0
	return target


func _capture_events(sim: CombatSim, destination: Array[Dictionary]) -> void:
	sim.damage_dealt.connect(func(point: Vector2, amount: float, source: String, secondary: bool, uid: int) -> void:
		destination.append({"position": point, "amount": amount, "source": source, "secondary": secondary, "uid": uid}))


func _step_until_hit(sim: CombatSim) -> void:
	for frame: int in 20:
		sim.step(1.0 / 60.0, Vector2.ZERO)
		if sim.primary_hits > 0 or sim.complete:
			return


func _test_draw_order() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/combat/combat_world.gd")
	var start: int = source.find("func _draw()")
	var end: int = source.find("\nfunc ", start + 1)
	var body: String = source.substr(start, end - start)
	var impact: int = body.find("_draw_impact")
	if impact < 0:
		impact = body.find("_impact_painter.")
	_check(body.find("_draw_effects()") >= 0 and body.find("_draw_effects()") < impact and impact < body.find("_draw_rune_feedback()")
		and body.find("_draw_rune_feedback()") < body.find("_draw_feedback()") and body.find("_draw_feedback()") < body.find("_draw_danger()"),
		"World code submits impacts after effects and before rune marks, damage numbers and highest-priority danger")


func _marks_snapshot(painter: RefCounted) -> Dictionary:
	var marks: Array[Dictionary] = []
	for mark: RefCounted in painter.get("_marks"):
		marks.append({"id": mark.get_instance_id(), "kind": mark.get("kind"), "origin": mark.get("origin"), "uid": mark.get("target_uid"), "age": mark.get("age"), "life": mark.get("life")})
	return {"marks": marks, "pool_ids": _pool_ids(painter), "free_ids": _ids(painter.get("_free")), "peak": painter.get("peak_active")}


func _batch_snapshot(painter: RefCounted) -> Array:
	var result: Array = []
	for batch: RefCounted in painter.get("_batches"):
		result.append({"points": (batch.get("points") as PackedVector2Array).duplicate(), "color": batch.get("color"), "width": batch.get("width")})
	return result


func _pool_ids(painter: RefCounted) -> Array[int]:
	return _ids(painter.get("_pool"))


func _ids(objects: Array) -> Array[int]:
	var result: Array[int] = []
	for object: RefCounted in objects:
		result.append(object.get_instance_id())
	result.sort()
	return result


func _unique_free(painter: RefCounted) -> bool:
	var free: Array[int] = _ids(painter.get("_free"))
	var unique: Dictionary = {}
	for id: int in free:
		unique[id] = true
	return free.size() == 32 and unique.size() == 32 and free == _pool_ids(painter)


func _has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if property["name"] == property_name:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _finish() -> void:
	print("ImpactFeedback: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
