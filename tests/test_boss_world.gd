extends SceneTree
## Actual boss steps and projectile impacts drive every weakpoint and hazard presentation.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

class SilentSound extends SoundBank:
	var cues: Array[String] = []
	func _ready() -> void:
		pass
	func play(_id: String, _loudness: float = -10.0) -> void:
		pass
	func play_cue(_id: String, _loudness: float, cue: String) -> void:
		cues.append(cue)

class ProbeWorld extends CombatWorld:
	var passes: Array[String] = []
	func _movement() -> Vector2:
		return Vector2.ZERO
	func _draw() -> void:
		passes.clear()
		super._draw()
	func _draw_boss_weakpoints() -> void:
		passes.append("weakpoints")
		super._draw_boss_weakpoints()
	func _draw_player() -> void:
		passes.append("player")
		super._draw_player()
	func _draw_danger() -> void:
		passes.append("danger")
		super._draw_danger()

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for index: int in 3:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _world() -> ProbeWorld:
	var sound := SilentSound.new()
	root.add_child(sound)
	var world := ProbeWorld.new()
	world.sound = sound
	root.add_child(world)
	world.set_physics_process(false)
	world.apply_visual_settings({"shake": false, "flash": true})
	var state := RunState.new()
	state.begin(20261030, "bone", "reliquary", "alk")
	state.wave = 8
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	world.sim.boss.definition = world.sim.boss.definition.duplicate() as ContentDef
	world.sim.boss.definition.speed = 0.0
	world.sim.player_position = world.sim.obstacles.free_point(Vector2(640, 460), 16.0, 16.0)
	return world

func _step(world: CombatWorld, count: int = 1) -> void:
	for index: int in count:
		world.sim.run.health = world.sim.run.stat("max_health")
		world._physics_process(STEP)

func _wait_cast(world: CombatWorld, attack_id: String) -> bool:
	for index: int in 1200:
		var value: Dictionary = world.sim.boss_encounter_snapshot()
		if value["phase"] == "charge" and value["attack_id"] == attack_id:
			return true
		_step(world)
	return false

func _signature(world: CombatWorld) -> String:
	var sim: CombatSim = world.sim
	var zones: Array = []
	for zone: CombatSim.WarningZone in sim.zones:
		zones.append([zone.shape, zone.position, zone.radius, zone.direction, zone.length, zone.width,
			zone.age, zone.delay, zone.duration, zone.triggered, zone.source_cast_id])
	return JSON.stringify([sim.snapshot(), sim.boss_weakpoints(), sim.boss_encounter_snapshot(), zones,
		sim.run.summary(), str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state),
		sim.weakpoint_damage, sim.weakpoints_broken, sim.boss_interrupts])

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_test_lane_geometry()
	await _test_weakpoint_lifecycle()
	await _test_charge_and_history()
	print("BossWorld: %d assertions, %d failures; native=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)

func _test_lane_geometry() -> void:
	for heading: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2(3, 4).normalized()]:
		var shape: Dictionary = {"shape": "lane", "position": Vector2(100, 200), "direction": heading, "length": 840.0, "width": 112.0}
		var corners: PackedVector2Array = CombatWorld.lane_polygon(shape)
		_check(corners.size() == 4, "A root lane is an actual four-corner rectangle, including diagonal orientation")
		var zone := CombatSim.WarningZone.new()
		zone.shape = "lane"
		zone.position = shape["position"]
		zone.direction = heading
		zone.length = 840
		zone.width = 112
		for corner: Vector2 in corners:
			var offset: Vector2 = corner - zone.position
			_check(absf(absf(offset.dot(heading.orthogonal())) - 56.0) < 0.001, "Rendered lane corners retain the exact collision half width")
			_check(is_zero_approx(offset.dot(heading)) or is_equal_approx(offset.dot(heading), 840.0), "Square end caps remain at the true finite start or end")
		_check(not CombatSim.zone_contains(zone, zone.position - heading, 0.0) and not CombatSim.zone_contains(zone, zone.position + heading * 841.0, 0.0), "The corresponding collision has no capsule extension beyond either square cap")
	_check(CombatWorld.lane_polygon({"position": Vector2.ZERO, "direction": Vector2.ZERO, "length": 840, "width": 112}).is_empty(), "Invalid heading produces no invented hazard geometry")

func _test_weakpoint_lifecycle() -> void:
	var world: ProbeWorld = _world()
	_check(_wait_cast(world, "forest_storm"), "Actual boss steps enter the first named charging cast")
	var points: Array[Dictionary] = world.sim.boss_weakpoints()
	var shown: Array[Dictionary] = world.boss_weakpoint_presentation_snapshot()
	_check(points.size() == 3 and shown.size() == 3 and world._boss_receipts.size() == 3, "The real three-point cast uses a bounded three-receipt pool")
	_check(world._weakpoint_texture != null and world._weakpoint_texture.get_size() == Vector2(288, 96), "Weakpoints use the shipped original three-cell atlas")
	for index: int in points.size():
		_check(shown[index]["position"] == points[index]["position"] and shown[index]["rect"] == Rect2(points[index]["position"] - Vector2(16, 16), Vector2(32, 32)), "Every complete 96px source cell is scaled to a centered 32px canvas so its visible target matches the actual radius-13 collider")
		_check(shown[index]["frame"] == 0 and CombatWorld.weakpoint_source_rect(0) == Rect2(0, 0, 96, 96), "A newly charging point displays the complete white source cell")
	var first: Dictionary = points[0]
	world.sim.fire_weapon("bone", "", first["position"] - Vector2(10, 0), Vector2.RIGHT)
	_step(world)
	shown = world.boss_weakpoint_presentation_snapshot()
	_check(world.sim.weakpoint_damage > 0.0 and shown[0]["tint"] != Color.WHITE, "A real projectile hit changes the target's bounded hit color")
	world.apply_visual_settings({"shake": false, "flash": false})
	_check(world.boss_weakpoint_presentation_snapshot()[0]["tint"] == Color.WHITE, "Disabling flash retains the same active weakpoint while removing its transient hit color")
	world.apply_visual_settings({"shake": false, "flash": true})
	for volley: int in 12:
		if world.sim.boss_weakpoints().is_empty():
			break
		var target: Dictionary = world.sim.boss_weakpoints()[0]
		world.sim.fire_weapon("bone", "", target["position"] - Vector2(10, 0), Vector2.RIGHT)
		_step(world)
	_check(world.sim.boss_encounter_snapshot()["phase"] == "break" and world.sim.boss_interrupts == 1, "Destroying all real points interrupts the actual cast")
	shown = world.boss_weakpoint_presentation_snapshot()
	_check(shown.size() == 3 and world.sim.boss_weakpoints().is_empty(), "Broken artwork may finish briefly after all actual target colliders are gone")
	for point: Dictionary in shown:
		_check(point["frame"] == 2 and point["broken"] and CombatWorld.weakpoint_source_rect(2) == Rect2(192, 0, 96, 96), "Real break receipts use only the original third cell")
	var before: String = _signature(world)
	var receipts_before: Array[Dictionary] = world.boss_weakpoint_presentation_snapshot()
	for repeat: int in 4:
		world.boss_weakpoint_presentation_snapshot()
		world.boss_danger_snapshot()
		world.hud_snapshot()
	_check(_signature(world) == before and world.boss_weakpoint_presentation_snapshot() == receipts_before, "Reading HUD and draw snapshots changes no simulation, timers or RNG")
	paused = true
	world.apply_visual_settings({"shake": false, "flash": false})
	await _settle()
	world._physics_process(STEP)
	_check(_signature(world) == before and world.boss_weakpoint_presentation_snapshot() == receipts_before, "Paused visual changes preserve all three broken targets and freeze their real physics clocks")
	paused = false
	_step(world, 14)
	_check(world.boss_weakpoint_presentation_snapshot().is_empty(), "The 0.22-second break receipt window expires without reviving targets")
	world.stop()
	_check(world.boss_weakpoint_presentation_snapshot().is_empty() and world.boss_danger_snapshot().is_empty(), "Stopping the world clears the finished encounter's target and danger presentation")
	world.sound.queue_free()
	world.queue_free()
	await _settle()

func _test_charge_and_history() -> void:
	var world: ProbeWorld = _world()
	_check(_wait_cast(world, "forest_storm"), "The danger fixture enters a real forest-storm charge")
	var current: Dictionary = world.boss_danger_snapshot()
	_check(current["geometry"] == world.sim.boss_encounter.telegraph_snapshot() and current["geometry"].size() == 3, "Charge draws the actual three frozen circle geometries exactly once")
	var total: float = world.sim.boss_encounter_snapshot()["charge_total"]
	for tick: int in 180:
		if float(world.sim.boss_encounter_snapshot()["charge_left"]) <= total * 0.25:
			break
		_step(world)
	for point: Dictionary in world.boss_weakpoint_presentation_snapshot():
		_check(point["frame"] == 1, "An imminent real cast changes live original targets from white to red")
	world.sim.apply_damage(world.sim.boss, world.sim.boss.max_health * 0.55, "bone")
	_step(world)
	var phase: Dictionary = world.sim.boss_encounter_snapshot()
	_check(phase["phase2"] and not phase["cast_phase2"] and world.boss_danger_snapshot()["geometry"].size() == 3, "Half health changes the stage indicator without changing the already locked cast geometry")
	for tick: int in 180:
		if world.sim.boss_encounter_snapshot()["phase"] != "charge":
			break
		_step(world)
	_check(world.boss_danger_snapshot().is_empty() and not world.sim.zones.is_empty(), "Released historical zones replace the current charge geometry without duplicate layers")
	_check(_wait_cast(world, "root_corridor"), "Real recovery leads into the next phase-two root cast")
	current = world.boss_danger_snapshot()
	_check(current["geometry"].size() == 4 and current["safe_channels"].size() == 1, "Phase two draws four actual horizontal lanes and one real safe corridor")
	for lane: Dictionary in current["geometry"]:
		_check(lane["shape"] == "lane" and lane["direction"] == Vector2.RIGHT and CombatWorld.lane_polygon(lane).size() == 4, "The rendered phase-two lane retains the actual rectangular geometry and direction")
	var hud: Dictionary = world.hud_snapshot()
	_check(hud["boss_encounter"] == world.sim.boss_encounter_snapshot(), "World forwards the actual encounter snapshot to the independent HUD")
	var view: Rect2 = world.camera_view()
	var safe: Rect2 = world._feedback_safe_rect()
	_check(is_equal_approx(safe.position.y, view.position.y + 150.0), "Feedback clears the compact top HUD and minimap by 150px")
	await _settle()
	if DisplayServer.get_name() != "headless":
		_check(world.passes.find("weakpoints") >= 0 and world.passes.find("weakpoints") < world.passes.find("player") and world.passes.back() == "danger", "Real canvas submission keeps targets before the player and every hostile warning above them")
	var before: String = _signature(world)
	var copied: Dictionary = world.boss_danger_snapshot()
	copied["geometry"][0]["width"] = 1
	copied["safe_channels"].clear()
	_check(_signature(world) == before and world.boss_danger_snapshot() == current, "Mutating a presentation copy cannot alter attack rectangles or safe channels")
	world.sim.boss.health = 0.0
	_check(is_equal_approx(world._feedback_safe_rect().position.y, view.position.y + 150.0) and world.boss_danger_snapshot().is_empty(), "Boss defeat preserves the compact HUD clearance without stale hazards")
	world.sound.queue_free()
	world.queue_free()
	await _settle()
