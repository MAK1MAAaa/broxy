extends SceneTree
## Shipped rendering consumes real ball, breakable and pickup state without owning physics.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

class ProbeSound extends SoundBank:
	var played: Array[String] = []
	func _ready() -> void:
		pass
	func play(id: String, _loudness: float = -10.0) -> void:
		played.append(id)
	func play_cue(id: String, _loudness: float, _cue: String) -> void:
		played.append(id)

class ProbeWorld extends CombatWorld:
	var movement: Vector2 = Vector2.ZERO
	var passes: Array[String] = []
	func _movement() -> Vector2:
		return movement
	func _draw() -> void:
		passes.clear()
		super._draw()
	func _draw_interactions() -> void:
		passes.append("interactions")
		super._draw_interactions()
	func _draw_enemies() -> void:
		passes.append("enemies")
		super._draw_enemies()
	func _draw_ball_player(tint: Color) -> void:
		passes.append("ball")
		super._draw_ball_player(tint)
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
	for frame: int in 4:
		await process_frame

func _world(hero_id: String = "alk", arena_id: String = "reliquary") -> ProbeWorld:
	var sound := ProbeSound.new()
	root.add_child(sound)
	var world := ProbeWorld.new()
	world.sound = sound
	root.add_child(world)
	world.set_physics_process(false)
	var state := RunState.new()
	state.begin(20261030, "", arena_id, hero_id)
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	return world

func _dispose(world: CombatWorld) -> void:
	world.sound.queue_free()
	world.queue_free()
	await _settle()

func _signature(world: CombatWorld) -> String:
	return JSON.stringify([world.sim.snapshot(), world.sim.run.summary(), world.sim.interactions.snapshot(),
		str(world.sim.rng.state), str(world.sim.run.rng.state), str(world.sim.interactions._rng.state)])

func _by_uid(items: Array, uid: int) -> Dictionary:
	for item: Dictionary in items:
		if int(item["uid"]) == uid:
			return item
	return {}

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_test_frame_boundaries()
	for id: String in HeroCatalog.IDS:
		await _test_ball_identity(id)
	for id: String in ArenaCatalog.IDS:
		await _test_dynamic_crates(id)
	await _test_pickups_and_feedback()
	await _test_hud_state()
	print("PinballWorld: %d assertions, %d failures; native=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)

func _test_frame_boundaries() -> void:
	for sample: Array in [[0.0, 0], [0.119, 0], [0.12, 1], [0.18, 2], [0.24, 3], [0.30, 4], [0.36, 5], [0.42, 6], [0.48, 0], [NAN, 0]]:
		_check(CombatWorld.ball_frame_index(float(sample[0])) == int(sample[1]), "The original seven ball frames follow the declared adapted timing: " + str(sample[0]))
	for index: int in 8:
		_check(CombatWorld.crate_break_frame(float(index) * 0.04 + 0.001) == index + 2, "Barrel breaking advances once through each nonempty fragment frame")
	_check(CombatWorld.crate_break_frame(0.32) == -1 and CombatWorld.crate_break_frame(NAN) == -1, "Completed and invalid break animations never loop back into an intact crate")
	var center := Vector2(100, 80)
	var direction: Vector2 = Vector2(3, -4).normalized()
	var streaks: PackedVector2Array = CombatWorld.ball_speed_lines(center, direction * 700.0)
	_check(streaks.size() == 4, "A moving ball uses exactly two short velocity strokes")
	for index: int in range(0, streaks.size(), 2):
		_check((streaks[index] - center).dot(direction) < 0.0 and (streaks[index + 1] - center).dot(direction) < 0.0 and is_equal_approx(streaks[index].distance_to(streaks[index + 1]), 13.0), "Both short strokes trail the authoritative velocity rather than the player's prior facing")
	_check(CombatWorld.ball_speed_lines(center, Vector2.ZERO).is_empty() and CombatWorld.ball_speed_lines(center, Vector2.INF).is_empty(), "Stationary or invalid velocity cannot create misleading speed lines")

func _test_ball_identity(hero_id: String) -> void:
	var world: ProbeWorld = _world(hero_id)
	var hero: HeroDef = HeroCatalog.definition(hero_id)
	_check(world.textures["player"].resource_path == hero.idle_path and world._interaction_textures["ball"].get_size() == Vector2(448, 64), "A real world loads its selected character and complete original energy atlas: " + hero_id)
	world.sim.player_position = Vector2(18, 360)
	world.movement = Vector2.RIGHT
	_check(world.request_dash(), "The selected character can queue a real dash toward an authored bumper")
	for frame: int in 8:
		world._physics_process(STEP)
		if bool(world.sim.pinball_snapshot()["active"]):
			break
	var ball: Dictionary = world.interaction_presentation_snapshot()["pinball"]
	_check(bool(ball.get("active", false)) and ball["hero_id"] == hero_id and ball["identity_texture"] == hero.idle_path, "An actual bumper collision enters ball form without losing the selected identity: " + hero_id)
	_check((ball["rect"] as Rect2).size == Vector2.ONE * 48.0 and (ball["identity_rect"] as Rect2).size == Vector2.ONE * 32.0, "The ball body and original character inset keep independent readable sizes")
	var before: String = _signature(world)
	world.queue_redraw()
	await _settle()
	_check(_signature(world) == before, "Native queued ball rendering does not advance timers, collisions or any random stream")
	if DisplayServer.get_name() != "headless":
		_check(world.passes.has("ball") and world.passes.find("interactions") < world.passes.find("enemies") and world.passes.back() == "danger", "Actual drawing keeps the recognizable ball in the player pass and hostile warnings last")
	world.apply_visual_settings({"shake": false, "flash": false})
	ball = world.interaction_presentation_snapshot()["pinball"]
	_check(bool(ball["active"]) and int(ball["frame"]) == 0 and ball["identity_texture"] == hero.idle_path and _signature(world) == before, "Flash-off retains a static original ball and current character without changing gameplay")
	world.stop()
	_check(not bool(world.interaction_presentation_snapshot()["pinball"]["active"]) and world._bumper_flashes.is_empty() and world._crate_flashes.is_empty(), "Stopping clears ball presentation and its bounded scenery feedback")
	await _dispose(world)

func _test_dynamic_crates(arena_id: String) -> void:
	var world: ProbeWorld = _world("alk", arena_id)
	var map := MinimapView.new()
	map.size = Vector2(192, 126)
	var before: String = _signature(world)
	var state: Dictionary = world.interaction_presentation_snapshot()
	var source: Dictionary = world.sim.interactions.snapshot()
	_check(state["crates"].size() == 12 and world._arena_obstacles.size() == (ArenaCatalog.definition(arena_id)["obstacles"] as Array).size(), "Dynamic crates are separate from the static scenery cache: " + arena_id)
	for crate: Dictionary in source["crates"]:
		var rendered: Dictionary = _by_uid(state["crates"], int(crate["uid"]))
		var texture_id: String = str(rendered["texture"])
		var width: float = float(world._interaction_widths[texture_id])
		var frame_size: float = 96.0 if texture_id == "chest" else 128.0
		var factor: float = (rendered["rect"] as Rect2).size.x / frame_size
		_check(is_equal_approx(width * factor, float(crate["radius"]) * 2.0) and rendered["active"] and rendered["frame"] == 1, "The original opaque crate width matches its real collider and idle frame")
	map.update_snapshot(world.minimap_snapshot())
	var obstacle_count: int = int(map.presentation_snapshot()["obstacle_count"])
	_check(map.presentation_snapshot()["crate_count"] == 12 and _signature(world) == before, "The minimap reads twelve real crate markers without changing the world")
	var first: Dictionary = source["crates"][0]
	world.sim._damage_crate(0, 1.0)
	var hit: Dictionary = _by_uid(world.interaction_presentation_snapshot()["crates"], int(first["uid"]))
	_check(float(hit["pressure"]) > 0.0 and hit["active"], "A real surviving hit briefly compresses the anchored crate")
	world.sim._damage_crate(0, 1000.0)
	var broken: Dictionary = _by_uid(world.interaction_presentation_snapshot()["crates"], int(first["uid"]))
	_check(not bool(broken["active"]) and broken["frame"] == 2 and broken["texture"] == "barrel", "A real break immediately displays the first original fragment frame")
	map.update_snapshot(world.minimap_snapshot())
	_check(map.presentation_snapshot()["crate_count"] == 11 and map.presentation_snapshot()["obstacle_count"] == obstacle_count - 1 and world.sim.obstacles.is_free(first["position"], 1.0), "The same snapshot removes the broken collider and minimap obstruction before animation completes")
	world.sim.interactions.advance(0.32)
	_check(_by_uid(world.interaction_presentation_snapshot()["crates"], int(first["uid"])).is_empty(), "The fragment presentation vanishes permanently at its bounded lifetime")
	before = _signature(world)
	for repeat: int in 4:
		var copy: Dictionary = world.interaction_presentation_snapshot()
		copy["crates"].clear()
		map.update_snapshot(world.minimap_snapshot())
	_check(_signature(world) == before and world.interaction_presentation_snapshot()["crates"].size() == 11, "Render snapshots are detached and repeated map updates cannot revive crates or consume randomness")
	map.free()
	await _dispose(world)

func _test_pickups_and_feedback() -> void:
	var world: ProbeWorld = _world()
	for index: int in 12:
		world.sim._damage_crate(index, 1000.0)
	var drops: Array = world.sim.interactions.snapshot()["pickups"]
	_check(not drops.is_empty(), "The deterministic break fixture produces actual probabilistic world drops")
	var map := MinimapView.new()
	map.size = Vector2(192, 126)
	map.update_snapshot(world.minimap_snapshot())
	_check(map.presentation_snapshot()["crate_count"] == 0 and map.presentation_snapshot()["pickup_count"] == drops.size(), "Broken routes stay open while every actual drop receives a minimap marker")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CombatWorld.INTERACTION_ROOT + "interaction-art.json"))["assets"]
	for kind: String in ["gold", "health", "charge"]:
		var texture: Texture2D = world._interaction_textures[kind]
		var definition: Dictionary = metadata["mana" if kind == "gold" else kind]
		var frame_size: Array = definition["frame_size"]
		var foot: Array = definition["foot_anchor"]
		var opaque_width: int = texture.get_image().get_used_rect().size.x
		_check(texture.resource_path == str(definition["path"]) and texture.get_size() == Vector2(float(frame_size[0]), float(frame_size[1])) and opaque_width > 0 and float(world._interaction_widths[kind]) == float(opaque_width) and world._interaction_feet[kind] == Vector2(float(foot[0]), float(foot[1])), "Each pickup caches the full original PNG, actual alpha width and metadata foot anchor: " + kind)
	for drop: Dictionary in drops:
		var rendered: Dictionary = _by_uid(world.interaction_presentation_snapshot()["pickups"], int(drop["uid"]))
		var kind: String = str(drop["kind"])
		var texture: Texture2D = world._interaction_textures[kind]
		var visible_width: float = 16.0 if kind == "gold" else 18.0
		var factor: float = visible_width / float(texture.get_image().get_used_rect().size.x)
		var bob: float = sin(float(drop["age"]) * 5.0) * 1.5
		_check(not rendered.is_empty() and rendered["kind"] == kind and (rendered["rect"] as Rect2).size.is_equal_approx(texture.get_size() * factor), "Actual drop scaling preserves the complete original canvas and gives its alpha silhouette the exact readable 16/18-pixel width")
		if not rendered.is_empty():
			var projected_foot: Vector2 = (rendered["rect"] as Rect2).position + world._interaction_feet[kind] * factor + Vector2(0, bob)
			_check(projected_foot.is_equal_approx(drop["position"]), "Scaling keeps the original metadata foot on the real pickup position after its bounded cosmetic bob")
	var backpack: Dictionary = world.sim.run.backpack_snapshot()
	world.sim.run.health = 1.0
	world.sim.try_hero_skill()
	for drop: Dictionary in drops:
		world.sim.player_position = drop["position"]
		for repeat: int in 2:
			if bool(world.sim.hero_skill_snapshot()["ready"]):
				world.sim.try_hero_skill()
			world.sim._collect_world_pickups()
	map.update_snapshot(world.minimap_snapshot())
	_check(map.presentation_snapshot()["pickup_count"] == 0 and world.interaction_presentation_snapshot()["pickups"].is_empty() and world.sim.run.backpack_snapshot() == backpack, "Actual collections remove world/map icons without inserting anything into the backpack")
	var receipt: bool = false
	for number: CombatWorld.FloatingNumber in world._numbers:
		if number.source.begins_with("pickup:"):
			receipt = true
			_check(number.text.begins_with("+") or (number.text.begins_with("−") and number.text.ends_with("秒")), "The existing number pool reports actual gained values or reduced cooldown seconds")
	_check(receipt and world._numbers.size() + world._number_free.size() == CombatWorld.NUMBER_LIMIT, "Pickup receipts share the existing bounded number pool")
	for index: int in 64:
		CombatWorld._add_interaction_flash(world._bumper_flashes, Vector2(index, 0), CombatWorld.BUMPER_FLASH_LIFE, CombatWorld.BUMPER_FLASH_LIMIT)
		CombatWorld._add_interaction_flash(world._crate_flashes, Vector2(index, 0), CombatWorld.CRATE_FLASH_LIFE, CombatWorld.CRATE_FLASH_LIMIT)
	_check(world._bumper_flashes.size() == 8 and world._crate_flashes.size() == 16, "Scenery impact pools retain their strict independent limits under a burst")
	var frozen: Dictionary = world.interaction_presentation_snapshot()
	paused = true
	world._physics_process(STEP)
	_check(world.interaction_presentation_snapshot() == frozen, "Scene pause freezes crate and bumper feedback rather than advancing its own animation")
	paused = false
	world._advance_interaction_feedback(1.0)
	_check(world._bumper_flashes.is_empty() and world._crate_flashes.is_empty(), "All bounded scenery pulses expire and release their slots")
	map.free()
	await _dispose(world)

func _test_hud_state() -> void:
	var world: ProbeWorld = _world()
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(world.sim.run)
	ui.show_hud()
	var snapshot: Dictionary = world.hud_snapshot()
	snapshot["pinball"] = {"active": true, "combo": 4}
	snapshot["dash"] = {"active": false, "ready": false, "cooldown_left": 1.2, "cooldown_total": 2.4}
	ui.update_hud(snapshot)
	_check((ui._hud["dash_label"] as Label).text == "弹射×4" and is_equal_approx((ui._hud["dash_bar"] as ProgressBar).value, 0.5), "Ball status replaces the dash label while its meter retains the actual dash cooldown")
	ui._on_input_device_changed("gamepad", 0)
	_check((ui._hud["dash_label"] as Label).text == "弹射×4" and (ui._hud["dash"] as Control).tooltip_text.contains("冲刺撞击弹板触发球化") and (ui._hud["hero_key"] as Label).text == "RB", "Device switching preserves the authoritative ball state and independent main skill")
	ui.queue_free()
	await _dispose(world)
