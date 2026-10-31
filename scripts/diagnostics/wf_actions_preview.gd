extends Node
## Native, nonpersistent previews advance production R actions through real fixed steps.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const SEED: int = 20261031
const HEALTH: float = 1000000.0
const VIEWS: Array[String] = ["windup", "first", "second", "bomb-flight", "bomb-impact", "bomb-late", "dispel", "map", "follow", "aura-late", "aura-end", "world-maps", "world-maps-empty"]
const AURA_VIEWS: Array[String] = ["follow", "aura-late", "aura-end"]
const REGIONS: Array[String] = ["center", "north", "south"]
var _receipts: Array[Dictionary] = []
var _late_uid: int = -1
var _view_checks: Dictionary = {}

func _ready() -> void:
	_preview.call_deferred()

func _options() -> Dictionary:
	var result: Dictionary = {"hero": "alk", "arena": "throne", "view": "first", "region": "center", "capture": "", "small": false, "gamepad": false, "flash": true}
	var explicit_hero: bool = false
	var explicit_region: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--wf-actions-preview":
			continue
		if argument.begins_with("--hero="):
			result["hero"] = argument.trim_prefix("--hero=")
			explicit_hero = true
		elif argument.begins_with("--arena="):
			result["arena"] = argument.trim_prefix("--arena=")
		elif argument.begins_with("--view="):
			result["view"] = argument.trim_prefix("--view=")
		elif argument.begins_with("--region="):
			result["region"] = argument.trim_prefix("--region=")
			explicit_region = true
		elif argument.begins_with("--capture="):
			result["capture"] = argument.trim_prefix("--capture=").replace("\\", "/")
		elif argument == "--small":
			result["small"] = true
		elif argument == "--gamepad":
			result["gamepad"] = true
		elif argument == "--flash-off":
			result["flash"] = false
		else:
			return _option_error("Unknown preview argument: " + argument, result)
	if not explicit_hero:
		if str(result["view"]).begins_with("bomb-"):
			result["hero"] = "hanabi"
		elif result["view"] in ["second", "dispel"]:
			result["hero"] = "clarisse"
		elif result["view"] in AURA_VIEWS:
			result["hero"] = "falsche"
	var destination: String = str(result["capture"])
	if result["region"] not in REGIONS:
		return _option_error("Region must be center, north or south", result)
	if explicit_region and result["view"] != "map":
		return _option_error("--region is only supported with --view=map", result)
	if result["hero"] not in HeroCatalog.IDS or not ArenaCatalog.contains(str(result["arena"])) or result["view"] not in VIEWS:
		return _option_error("Hero, arena and view must be existing production IDs", result)
	if (str(result["view"]).begins_with("bomb-") and result["hero"] != "hanabi") or (result["view"] in ["second", "dispel"] and result["hero"] != "clarisse"):
		return _option_error("Bomb views require Hanabi; second/dispel require Clarisse", result)
	if result["view"] in AURA_VIEWS and result["hero"] != "falsche":
		return _option_error("Follow/aura-late/aura-end require Falsche", result)
	if result["view"] == "windup" and result["hero"] == "falsche":
		return _option_error("Falsche has no windup; use first, follow, aura-late or aura-end", result)
	if destination.is_empty() or not destination.is_absolute_path() or destination.begins_with("res://") or destination.begins_with("user://") or destination.get_extension().to_lower() != "png":
		return _option_error("--capture requires an absolute filesystem PNG path", result)
	if DisplayServer.get_name() == "headless":
		return _option_error("This preview requires native rendering", result)
	return result

func _option_error(message: String, options: Dictionary) -> Dictionary:
	return {"error": message, "region": options.get("region", "center")}

func _preview() -> void:
	var options: Dictionary = _options()
	if options.has("error"):
		push_error(str(options["error"]))
		print("WF_ACTION_PREVIEW ", JSON.stringify(options))
		get_tree().quit(2)
		return
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_tree().root.size = Vector2i(960, 540) if bool(options["small"]) else Vector2i(1280, 720)
	var app: Node = MAIN.instantiate()
	app.set_meta("wf_actions_preview_child", true)
	app.store.persistent = false
	get_tree().root.add_child(app)
	app.set_process(false)
	app._screenshot_clock = -1.0
	app.args.append("--autoplay")
	app.sound.set_volume(0.0)
	app.ui.set_selected_arena(str(options["arena"]))
	app.ui.set_selected_hero(str(options["hero"]))
	if options["view"] in ["world-maps", "world-maps-empty"]:
		await _browser_preview(app, options)
		return
	app._begin_run("bone", SEED)
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.autopilot = false
	world.apply_visual_settings({"shake": false, "flash": bool(options["flash"])})
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(99999.0)
	sim.player_direction = Vector2.RIGHT
	var offsets: Array[Vector2] = _target_offsets(str(options["hero"]))
	var point: Vector2 = _map_staging_point(sim, str(options["region"])) if options["view"] == "map" else _staging_point(sim, offsets, str(options["hero"]), str(options["view"]))
	if not point.is_finite():
		await _fail(app, options, "No legal deterministic staging point exists for this arena and target geometry")
		return
	sim.player_position = point
	var targets: Array[CombatSim.Enemy] = []
	if options["view"] != "map":
		for offset: Vector2 in offsets:
			var enemy: CombatSim.Enemy = _spawn_target(sim, point + offset)
			if enemy == null:
				await _fail(app, options, "The production enemy pool rejected a static target")
				return
			targets.append(enemy)
	_attach_receipts(sim)
	_release_movement()
	var conditions_before: Array[Dictionary] = []
	if options["view"] == "dispel":
		if targets.is_empty() or not sim.grant_enemy_condition(targets[0], "defense", 0.5, 10.0):
			await _fail(app, options, "The real temporary defense condition could not be granted")
			return
		conditions_before = sim.enemy_conditions_snapshot()
	if options["view"] != "map":
		if not world.request_hero_skill():
			await _fail(app, options, "The production World rejected the real R request")
			return
		if not _advance_view(world, str(options["view"]), targets):
			await _fail(app, options, "The requested real timeline phase did not satisfy its bounded runtime checks")
			return
	world._update_camera()
	app.ui.update_hud(world.hud_snapshot())
	get_tree().root.warp_mouse(Vector2(20, 20))
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(20, 20)
	pointer.global_position = pointer.position
	get_tree().root.push_input(pointer, false)
	app.ui._on_input_device_changed("gamepad" if bool(options["gamepad"]) else "keyboard", 0 if bool(options["gamepad"]) else -1)
	var before: String = _signature(sim)
	# Initialize the native renderer before measuring its completed-frame counter.
	# Physics remains disabled; the same purity signature covers this warm-up.
	world.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var warmup_pure: bool = before == _signature(sim)
	var draws: Array[int] = [0]
	world.draw.connect(func() -> void: draws[0] += 1)
	var native_before: int = Engine.get_frames_drawn()
	for frame: int in 2:
		world.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var native_after: int = Engine.get_frames_drawn()
	var after: String = _signature(sim)
	var pure: bool = warmup_pure and before == after
	var absolute: String = str(options["capture"])
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var capture_size := Vector2i.ZERO
	if result == OK:
		var capture_image: Image = get_tree().root.get_texture().get_image()
		capture_size = capture_image.get_size()
		result = capture_image.save_png(absolute)
	var late_counts: Array[Dictionary] = _late_counts(sim)
	var late_hits: int = 0
	var bounded_late: bool = _late_counts_bounded(sim)
	for contact: Dictionary in late_counts:
		late_hits += int(contact["hits"])
	var payload: Dictionary = {
		"debug_build": OS.is_debug_build(), "engine_version": Engine.get_version_info()["string"],
		"hero": options["hero"], "arena": options["arena"], "view": options["view"], "region": options["region"],
		"player": sim.player_position, "play_bounds": sim.obstacles.bounds, "camera_view": world.camera_view(), "wall_segments": sim.obstacles.walls.snapshot().size(),
		"small": options["small"], "gamepad_prompts": options["gamepad"], "physical_gamepad_test": false, "flash": options["flash"],
		"presentation": _window_state(), "render_size": [capture_size.x, capture_size.y],
		"actual_elapsed": sim.elapsed, "R": sim.hero_skill_snapshot(), "effects": sim.hero_effects_snapshot(),
		"targets": _target_states(targets), "conditions_before": conditions_before, "conditions_after": sim.enemy_conditions_snapshot(),
		"damage_records": _receipts, "damage_by_skill": sim.damage_by_skill, "late_uid": _late_uid, "late_hits": late_hits, "late_area_hits": late_counts, "view_checks": _view_checks,
		"native_frames_before": native_before, "native_frames_after": native_after, "native_frames_drawn": native_after - native_before,
		"native_warmup_frames": 1, "state_unchanged_after_warmup": warmup_pure,
		"world_draws_observed": draws[0], "state_unchanged_while_drawing": pure,
		"state_hash": before.sha256_text(), "state_hash_after": after.sha256_text(),
		"profile_io": false, "persistent_profile": app.store.persistent, "pure_drawing": pure,
		"fixed_fixture": true, "natural_gameplay": false, "manual_step_seconds": STEP, "capture": absolute, "result": result,
		"fixture_interventions": _fixture_interventions(str(options["view"]))}
	print("WF_ACTION_PREVIEW ", JSON.stringify(payload))
	world.stop()
	await app._quit_game(0 if result == OK and pure and bounded_late and bool(_view_checks.get("passed", true)) and draws[0] >= 2 and native_after - native_before >= 2 and not app.store.persistent else 1)


func _settle() -> void:
	for frame: int in 5:
		await get_tree().process_frame


func _browser_preview(app: Node, options: Dictionary) -> void:
	app.run.begin(SEED, "bone", str(options["arena"]), str(options["hero"]))
	var art := app.ui.find_child("MenuArtwork", true, false) as TitleCover
	if art != null:
		art.set_frame(0)
	app.ui._show_world_maps()
	var browser := app.ui.find_child("WorldMapBrowser", true, false) as WorldMapBrowser
	if browser == null:
		await _fail(app, options, "The production world-map browser did not open")
		return
	if options["view"] == "world-maps-empty":
		browser._search.text = "no-such-map-20261031"
		browser._search.text_changed.emit(browser._search.text)
	app.ui._on_input_device_changed("gamepad" if bool(options["gamepad"]) else "keyboard", 0 if bool(options["gamepad"]) else -1)
	get_tree().root.warp_mouse(Vector2(20, 20))
	await _settle()
	var cards: Array[Dictionary] = []
	var visible: bool = true
	var viewport := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for card: Node in browser._grid.get_children():
		if card is Button:
			cards.append({"id": str(card.name).trim_prefix("WorldMap_"), "rect": card.get_global_rect()})
			visible = visible and viewport.encloses(card.get_global_rect())
	var before: String = _browser_signature(app, browser)
	var native_before: int = Engine.get_frames_drawn()
	for frame: int in 2:
		browser.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var after: String = _browser_signature(app, browser)
	var pure: bool = before == after
	var capture: String = str(options["capture"])
	var result: Error = DirAccess.make_dir_recursive_absolute(capture.get_base_dir())
	var capture_size := Vector2i.ZERO
	if result == OK:
		var capture_image: Image = get_tree().root.get_texture().get_image()
		capture_size = capture_image.get_size()
		result = capture_image.save_png(capture)
	var native_frames: int = Engine.get_frames_drawn() - native_before
	var passed: bool = result == OK and pure and visible and native_frames >= 2 and cards.size() <= WorldMapCatalog.PAGE_SIZE and not app.store.persistent
	if options["view"] == "world-maps-empty":
		passed = passed and cards.is_empty() and browser._matches.is_empty()
	else:
		passed = passed and not cards.is_empty()
	print("WF_ACTION_PREVIEW ", JSON.stringify({"debug_build": OS.is_debug_build(), "view": options["view"], "arena": options["arena"],
		"cards": cards, "page": browser._page, "matches": browser._matches.size(), "small": options["small"],
		"presentation": _window_state(), "render_size": [capture_size.x, capture_size.y],
		"gamepad_prompts": options["gamepad"], "physical_gamepad_test": false, "cards_inside_viewport": visible,
		"native_frames_drawn": native_frames, "profile_io": false, "persistent_profile": app.store.persistent,
		"state_hash": before.sha256_text(), "state_hash_after": after.sha256_text(), "pure_drawing": pure, "fixed_fixture": true, "natural_gameplay": false,
		"capture": capture, "result": result, "passed": passed}))
	await app._quit_game(0 if passed else 1)


func _browser_signature(app: Node, browser: WorldMapBrowser) -> String:
	var cards: Array[Dictionary] = []
	for card: Node in browser._grid.get_children():
		cards.append({"id": str(card.name), "rect": (card as Control).get_global_rect()})
	var focus: Control = get_tree().root.gui_get_focus_owner()
	return JSON.stringify([_window_state(), app.run.summary(), str(app.run.rng.state), app.ui.selected_arena(), app.ui._overlay_mode,
		browser._page, browser._epoch, browser._search.text, browser._group.selected, browser._matches, cards,
		_browser_focus_signature(browser, focus)])


func _browser_focus_signature(browser: WorldMapBrowser, focus: Control) -> Dictionary:
	if not is_instance_valid(focus):
		return {"scope": "none"}
	var state: Dictionary = {"scope": "outside", "control": str(focus.name), "class": focus.get_class()}
	if not browser.is_ancestor_of(focus):
		return state
	var indices: Array[int] = []
	var current: Node = focus
	while current != browser:
		indices.push_front(current.get_index())
		current = current.get_parent()
	state["scope"] = "browser"
	state["child_indices"] = indices
	return state


func _window_state() -> Dictionary:
	var window: Window = get_tree().root
	var client: Vector2i = DisplayServer.window_get_size(window.get_window_id()) if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	return {"window_size": [window.size.x, window.size.y], "client_size": [client.x, client.y],
		"content_scale_size": [window.content_scale_size.x, window.content_scale_size.y],
		"content_scale_mode": window.content_scale_mode, "content_scale_aspect": window.content_scale_aspect}

func _fixture_interventions(view: String) -> Array[String]:
	if view == "map":
		return ["legal map-region placement", "disabled automatic weapons", "production map collision and camera"]
	var result: Array[String] = ["static high-health targets", "disabled automatic weapons", "real queued R and manual fixed steps", "production map collision and camera"]
	if view == "follow":
		result.append("real movement Input action for six World fixed steps")
	elif view == "aura-late":
		result.append("new production enemy UID staged outside then moved into an already active aura")
	return result

func _release_movement() -> void:
	ControlBindings.ensure_installed()
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(ControlBindings.PREFIX + action)

func _target_offsets(hero_id: String) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	match hero_id:
		"clarisse": offsets.assign([Vector2(160, 0), Vector2(-160, 0)])
		"celtie": offsets.assign([Vector2(270, 0), Vector2(-270, 0), Vector2(0, 60)])
		"hanabi":
			for index: int in 5:
				offsets.append(Vector2.from_angle(float(index) / 4.0 - 0.5) * 110.0)
		_: offsets.assign([Vector2(90, 0), Vector2(-90, 0)])
	return offsets

func _map_staging_point(sim: CombatSim, region: String) -> Vector2:
	var area: Rect2 = sim.obstacles.bounds.grow(-16.0)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return Vector2.INF
	var requested: Vector2 = area.get_center()
	if region == "north":
		requested.y = area.position.y
	elif region == "south":
		requested.y = area.end.y
	var point: Vector2 = sim.obstacles.free_point(requested, 16.0, 16.0)
	return point if sim.obstacles.is_free(point, 16.0, 16.0) else Vector2.INF

func _staging_point(sim: CombatSim, offsets: Array[Vector2], hero_id: String, view: String) -> Vector2:
	var preferred: Array[Vector2] = [sim.player_position, CombatSim.ARENA.get_center()]
	for row: int in 9:
		for column: int in 15:
			preferred.append(CombatSim.ARENA.position + Vector2((float(column) + 0.5) / 15.0, (float(row) + 0.5) / 9.0) * CombatSim.ARENA.size)
	for requested: Vector2 in preferred:
		var point: Vector2 = sim.obstacles.free_point(requested, 16.0, 16.0)
		if not sim.obstacles.is_free(point, 16.0, 16.0):
			continue
		if view == "map":
			return point
		var legal: bool = true
		for offset: Vector2 in offsets:
			if not sim.obstacles.is_free(point + offset, 22.0):
				legal = false
				break
			if hero_id == "hanabi":
				var heading: Vector2 = offset.normalized()
				if not sim.obstacles.first_hit(point + heading * 18.0, heading * 56.0, 9.0).is_empty():
					legal = false
					break
		if legal:
			return point
	return Vector2.INF

func _spawn_target(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", point, true)
	if enemy == null:
		return null
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = HEALTH
	enemy.max_health = HEALTH
	enemy.action_timer = 99999.0
	return enemy

func _attach_receipts(sim: CombatSim) -> void:
	var reference: WeakRef = weakref(sim)
	var records: Array[Dictionary] = _receipts
	sim.damage_dealt.connect(func(_position: Vector2, amount: float, source: String, _secondary: bool, uid: int) -> void:
		var current: CombatSim = reference.get_ref() as CombatSim
		if current != null:
			records.append({"time": current.elapsed, "source": source, "uid": uid, "amount": amount})
	)

func _advance_view(world: CombatWorld, view: String, targets: Array[CombatSim.Enemy]) -> bool:
	var sim: CombatSim = world.sim
	if view in AURA_VIEWS:
		return _advance_aura_view(world, view, targets)
	var parameters: Dictionary = sim.run.hero_skill_parameters()
	var delay: float = float(parameters.get("cast_delay", 0.0))
	if parameters.get("timeline") is Array and not parameters["timeline"].is_empty():
		delay = float(parameters["timeline"][0]["delay"])
	if view in ["bomb-impact", "bomb-late"]:
		for frame: int in ceili((delay + float(parameters.get("projectile_life", 1.2))) / STEP) + 2:
			world._physics_process(STEP)
			if int(sim.hero_effects_snapshot()["explosions"]) > 0:
				break
		if int(sim.hero_effects_snapshot()["explosions"]) == 0:
			return false
		return _stage_late_target(world, targets) if view == "bomb-late" else _active_impact(sim) != null
	var frames: int = ceili(delay / STEP) + 5
	match view:
		"windup": frames = maxi(1, floori(delay / STEP * 0.5))
		"second": frames = 79 + 7
		"bomb-flight": frames = 55 + 12
	for frame: int in frames:
		world._physics_process(STEP)
	if int(sim.hero_skill_snapshot()["uses"]) != 1 or sim.shot_count != 0:
		return false
	if view == "windup":
		return sim.skill_hits == 0 and sim.damage_by_skill.is_empty() and _receipts.is_empty()
	if view == "bomb-flight":
		var effect: Dictionary = sim.hero_effects_snapshot()
		return int(effect["active_bombs"]) == 5 and int(effect["reserved_bombs"]) == 0 and int(effect["explosions"]) == 0 and sim.skill_hits == 0
	if view == "dispel":
		return not targets.is_empty() and targets[0].health < HEALTH and not targets[0].positive_conditions.has("defense")
	if view == "second":
		for area: SkillTimelineRuntime.Area in sim.skill_timeline.areas:
			if area.occupied and area.opened and area.max_hits == 11:
				return sim.skill_hits > 4
		return false
	if view == "first" and sim.run.hero_id in ["nasir", "mordiga", "falsche"]:
		return _new_hero_first(sim, targets)
	return not _receipts.is_empty() if sim.run.hero_id != "hanabi" else int(sim.hero_effects_snapshot()["active_bombs"]) == 5

func _new_hero_first(sim: CombatSim, targets: Array[CombatSim.Enemy]) -> bool:
	var area: SkillTimelineRuntime.Area = _active_hero_area(sim, "hero_" + sim.run.hero_id)
	if area == null or targets.size() != 2:
		return false
	var expected: Array[int] = []
	var actual: Array[int] = []
	var passed: bool = true
	for enemy: CombatSim.Enemy in targets:
		var inside: bool = CombatSim.skill_contains(area.parameters, area.origin, area.direction, enemy.position)
		var hits: int = int(area.contacts.get("enemy:%d" % enemy.uid, 0))
		expected.append(1 if inside else 0)
		actual.append(hits)
		passed = passed and hits == (1 if inside else 0)
	_view_checks = {"passed": passed and actual[0] == 1, "phase": "first", "area_origin": area.origin,
		"forward_offset": area.follow_offset, "expected_target_hits": expected, "actual_target_hits": actual,
		"locked_damage": sim.hero_skill_snapshot()["damage"]}
	return bool(_view_checks["passed"])

func _active_hero_area(sim: CombatSim, source_id: String) -> SkillTimelineRuntime.Area:
	for area: SkillTimelineRuntime.Area in sim.skill_timeline.areas:
		if area.occupied and area.opened and not area.held and area.parameters.get("id", "") == source_id:
			return area
	return null

func _advance_aura_view(world: CombatWorld, view: String, targets: Array[CombatSim.Enemy]) -> bool:
	var sim: CombatSim = world.sim
	world._physics_process(STEP)
	var area: SkillTimelineRuntime.Area = _active_hero_area(sim, "hero_falsche")
	if sim.run.hero_id != "falsche" or targets.size() != 2 or area == null:
		return false
	if int(sim.hero_skill_snapshot()["uses"]) != 1 or sim.shot_count != 0 or area.anchor != "caster" or area.max_hits != 30:
		return false
	if not is_zero_approx(area.delay) or not is_equal_approx(area.duration, 10.0) or not area.follow_offset.is_zero_approx():
		return false
	for target: CombatSim.Enemy in targets:
		if int(area.contacts.get("enemy:%d" % target.uid, 0)) != 1:
			return false
	var locked_damage: float = float(sim.hero_skill_snapshot()["damage"])
	match view:
		"follow": return _follow_aura(world, area)
		"aura-late": return _late_aura(world, area, targets)
		"aura-end": return _finish_aura(world, area, targets, locked_damage)
	return false

func _follow_aura(world: CombatWorld, area: SkillTimelineRuntime.Area) -> bool:
	var sim: CombatSim = world.sim
	var start: Vector2 = sim.player_position
	var action: String = ""
	var choices: Dictionary = {"move_down": Vector2.DOWN, "move_up": Vector2.UP, "move_right": Vector2.RIGHT, "move_left": Vector2.LEFT}
	var distance: float = sim.run.stat("move_speed") * STEP * 6.0
	for candidate: String in choices:
		var displacement: Vector2 = choices[candidate] * distance
		if sim.obstacles.first_hit(start, displacement, 16.0, 16.0).is_empty() and sim.obstacles.is_free(start + displacement, 16.0, 16.0):
			action = candidate
			break
	if action.is_empty():
		return false
	Input.action_press(ControlBindings.PREFIX + action)
	var follows: bool = true
	for frame: int in 6:
		world._physics_process(STEP)
		follows = follows and area.occupied and area.origin.is_equal_approx(sim.player_position)
	Input.action_release(ControlBindings.PREFIX + action)
	var moved: bool = start.distance_to(sim.player_position) > 0.1
	_view_checks = {"passed": follows and moved, "phase": "follow", "movement_action": ControlBindings.PREFIX + action,
		"movement_steps": 6, "player_before": start, "player_after": sim.player_position,
		"movement_distance": start.distance_to(sim.player_position), "area_origin": area.origin,
		"follows_every_step": follows, "actual_movement": moved}
	return bool(_view_checks["passed"])

func _late_aura(world: CombatWorld, area: SkillTimelineRuntime.Area, targets: Array[CombatSim.Enemy]) -> bool:
	var sim: CombatSim = world.sim
	for frame: int in 59:
		world._physics_process(STEP)
	if not area.occupied or area.age >= area.duration:
		return false
	var initial_hits: Array[int] = []
	for enemy: CombatSim.Enemy in targets:
		initial_hits.append(int(area.contacts.get("enemy:%d" % enemy.uid, 0)))
	var outside: Vector2 = _aura_target_point(sim, area, false)
	var inside: Vector2 = _aura_target_point(sim, area, true)
	if not outside.is_finite() or not inside.is_finite():
		return false
	var late: CombatSim.Enemy = _spawn_target(sim, outside)
	if late == null:
		return false
	for original: CombatSim.Enemy in targets:
		if original.uid == late.uid:
			return false
	_late_uid = late.uid
	targets.append(late)
	var key: String = "enemy:%d" % late.uid
	world._physics_process(STEP)
	var outside_hits: int = int(area.contacts.get(key, 0))
	if outside_hits != 0 or late.health != HEALTH:
		return false
	late.position = inside
	world._physics_process(STEP)
	var entry_hits: int = int(area.contacts.get(key, 0))
	if entry_hits != 1 or late.health >= HEALTH:
		return false
	for frame: int in 20:
		world._physics_process(STEP)
	var late_hits: int = int(area.contacts.get(key, 0))
	var independent: bool = initial_hits[0] > entry_hits and initial_hits[1] > entry_hits
	var late_receipts: int = 0
	for receipt: Dictionary in _receipts:
		if receipt["source"] == "skill:hero_falsche" and int(receipt["uid"]) == late.uid:
			late_receipts += 1
	var bounded: bool = area.occupied and area.max_hits == 30 and _late_counts_bounded(sim)
	for enemy: CombatSim.Enemy in targets:
		var hits: int = int(area.contacts.get("enemy:%d" % enemy.uid, 0))
		bounded = bounded and hits > 0 and hits <= 30
	_view_checks = {"passed": independent and bounded and late_hits == 2 and late_receipts == late_hits, "phase": "aura-late",
		"original_target_hits_before_entry": initial_hits, "late_uid": late.uid, "outside": outside, "entry": inside,
		"outside_hits": outside_hits, "entry_hits": entry_hits, "late_hits_after_interval": late_hits, "late_damage_receipts": late_receipts,
		"per_uid_max_hits": area.max_hits, "independent_contact_budget": independent,
		"no_retroactive_hits": entry_hits == 1, "area_still_active": area.occupied, "area_age": area.age}
	return bool(_view_checks["passed"])

func _aura_target_point(sim: CombatSim, area: SkillTimelineRuntime.Area, inside: bool) -> Vector2:
	var reach: float = float(area.parameters.get("radius", 0.0))
	var distance: float = reach * 0.6 if inside else reach + 44.0
	for heading: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT]:
		var point: Vector2 = sim.obstacles.free_point(area.origin + heading * distance, 22.0)
		if not sim.obstacles.is_free(point, 22.0) or point.distance_to(sim.player_position) < 50.0:
			continue
		if CombatSim.skill_contains(area.parameters, area.origin, area.direction, point) == inside:
			return point
	return Vector2.INF

func _finish_aura(world: CombatWorld, area: SkillTimelineRuntime.Area, targets: Array[CombatSim.Enemy], locked_damage: float) -> bool:
	var sim: CombatSim = world.sim
	for frame: int in 599:
		world._physics_process(STEP)
	var records: Array[Dictionary] = []
	var total: float = 0.0
	var complete_damage: bool = true
	for enemy: CombatSim.Enemy in targets:
		var hits: int = 0
		var damage: float = 0.0
		for receipt: Dictionary in _receipts:
			if receipt["source"] == "skill:hero_falsche" and int(receipt["uid"]) == enemy.uid:
				hits += 1
				damage += float(receipt["amount"])
		records.append({"uid": enemy.uid, "hits": hits, "damage": damage, "health_lost": HEALTH - enemy.health})
		total += damage
		complete_damage = complete_damage and hits == 30 and is_equal_approx(damage, locked_damage) and is_equal_approx(HEALTH - enemy.health, locked_damage)
	var cleared: bool = not area.occupied and area.parameters.is_empty() and area.contacts.is_empty() and area.next_contacts.is_empty()
	cleared = cleared and int(sim.skill_timeline.snapshot()["occupied"]) == 0 and _active_hero_area(sim, "hero_falsche") == null
	var expected_total: float = locked_damage * float(targets.size())
	var passed: bool = complete_damage and cleared and is_equal_approx(sim.elapsed, 600.0 * STEP)
	passed = passed and sim.skill_hits == 30 * targets.size() and int(sim.hero_skill_snapshot()["uses"]) == 1
	passed = passed and is_equal_approx(total, expected_total) and is_equal_approx(float(sim.damage_by_skill.get("hero_falsche", 0.0)), expected_total)
	_view_checks = {"passed": passed, "phase": "aura-end", "fixed_steps": 600, "locked_damage_per_uid": locked_damage,
		"expected_total_damage": expected_total, "actual_total_damage": total, "per_uid": records,
		"full_lifetime": sim.elapsed, "complete_damage": complete_damage, "area_cleared": cleared}
	return passed

func _active_impact(sim: CombatSim) -> SkillTimelineRuntime.Area:
	for area: SkillTimelineRuntime.Area in sim.skill_timeline.areas:
		if area.occupied and area.opened and not area.held and area.parameters.get("id", "") == "hero_hanabi":
			return area
	return null

func _stage_late_target(world: CombatWorld, targets: Array[CombatSim.Enemy]) -> bool:
	var sim: CombatSim = world.sim
	var area: SkillTimelineRuntime.Area = _active_impact(sim)
	if area == null:
		return false
	var point: Vector2 = Vector2.INF
	for offset: Vector2 in [Vector2.ZERO, Vector2(12, 0), Vector2(-12, 0), Vector2(0, 12), Vector2(0, -12)]:
		var candidate: Vector2 = sim.obstacles.free_point(area.origin + offset, 22.0)
		if sim.obstacles.is_free(candidate, 22.0) and CombatSim.skill_contains(area.parameters, area.origin, area.direction, candidate):
			point = candidate
			break
	if not point.is_finite():
		return false
	var late: CombatSim.Enemy = _spawn_target(sim, point)
	if late == null:
		return false
	_late_uid = late.uid
	targets.append(late)
	var key: String = "enemy:%d" % late.uid
	for frame: int in ceili(area.duration / STEP) + 2:
		world._physics_process(STEP)
		if late.health < HEALTH:
			return int(area.contacts.get(key, 0)) == 1 and _late_counts_bounded(sim)
	return false

func _late_counts(sim: CombatSim) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _late_uid < 0:
		return result
	var key: String = "enemy:%d" % _late_uid
	for area: SkillTimelineRuntime.Area in sim.skill_timeline.areas:
		if area.occupied and area.parameters.get("id", "") in ["hero_hanabi", "hero_falsche"] and area.contacts.has(key):
			result.append({"serial": area.serial, "hits": int(area.contacts[key]), "max_hits": area.max_hits})
	return result

func _late_counts_bounded(sim: CombatSim) -> bool:
	var maximum: int = 30 if sim.run.hero_id == "falsche" else 1
	for contact: Dictionary in _late_counts(sim):
		if int(contact["hits"]) < 1 or int(contact["hits"]) > maximum or int(contact["max_hits"]) != maximum:
			return false
	return true

func _target_states(targets: Array[CombatSim.Enemy]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy: CombatSim.Enemy in targets:
		result.append({"uid": enemy.uid, "active": enemy.active, "position": enemy.position, "health": enemy.health, "initial_health": HEALTH,
			"positive_conditions": enemy.positive_conditions.duplicate(true), "fire_vulnerability": enemy.fire_vulnerability, "fire_vulnerability_left": enemy.fire_vulnerability_left})
	return result

func _signature(sim: CombatSim) -> String:
	var timeline: Array = []
	for area: SkillTimelineRuntime.Area in sim.skill_timeline.areas:
		timeline.append([area.occupied, area.serial, area.age, area.previous_age, area.delay, area.duration,
			area.max_hits, area.interval, area.purpose, area.origin, area.direction, area.follow_offset, area.anchor,
			area.parameters, area.contacts, area.next_contacts, area.opened, area.held])
	var bombs: Array = []
	for bomb: HeroSkillRuntime.Bomb in sim.hero_effects.bombs:
		bombs.append([bomb.active, bomb.uid, bomb.position, bomb.previous, bomb.velocity, bomb.collision_radius,
			bomb.blast_radius, bomb.damage, bomb.life, bomb.total, bomb.source, bomb.element, bomb.delay, bomb.delay_total,
			bomb.impact_area.serial if bomb.impact_area != null else -1])
	var enemies: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemies.append([enemy.slot, enemy.uid, enemy.definition.id, enemy.position, enemy.velocity, enemy.health, enemy.max_health,
				enemy.age, enemy.action_timer, enemy.mode, enemy.radius, enemy.slow_timer, enemy.slow_factor, enemy.pulse_hinder_timer,
				enemy.hurt_timer, enemy.charge_direction, enemy.hunter, enemy.boss_ghost, enemy.boss_cast_id, enemy.damage_scale,
				enemy.fire_vulnerability_left, enemy.fire_vulnerability, enemy.positive_conditions, enemy.positive_attack, enemy.positive_speed, enemy.positive_defense])
	var shots: Array = []
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			shots.append([shot.slot, shot.position, shot.previous, shot.velocity, shot.damage, shot.life, shot.source, shot.rune, shot.hit_ids, shot.weakpoint_hit_ids, shot.hostile])
	var souls: Array = []
	for soul: CombatSim.Soul in sim.souls:
		if soul.active:
			souls.append([soul.slot, soul.position, soul.value, soul.age])
	var zones: Array = []
	for zone: CombatSim.WarningZone in sim.zones:
		zones.append([zone.shape, zone.position, zone.direction, zone.radius, zone.length, zone.width, zone.age, zone.delay, zone.duration, zone.damage, zone.triggered, zone.source_cast_id, zone.source_id])
	var effects: Array = []
	for effect: CombatSim.Effect in sim.effects:
		effects.append([effect.position, effect.radius, effect.color, effect.life, effect.total, effect.kind])
	return JSON.stringify({"snapshot": sim.snapshot(), "run": sim.run.summary(), "offers": sim.run.offers,
		"run_runtime": [sim.run.healing_events, sim.run.inventory_revision, sim.run.last_error],
		"player": [sim.player_position, sim.player_velocity, sim.player_direction, sim.invulnerability],
		"simulation": [sim.elapsed, sim.duration, sim.complete, sim.victory, sim.end_reason, sim.enemy_count, sim.shot_count, sim.soul_count, sim.skill_hits, sim.primary_hits, sim.secondary_hits],
		"clocks": [sim._hero_skill_clock, sim._active_skill_clocks, sim._cooldowns], "free_slots": [sim._enemy_free, sim._shot_free, sim._soul_free],
		"timeline": timeline, "timeline_pool": [sim.skill_timeline._serial, sim.skill_timeline._occupied, sim.skill_timeline._step_serial_limit, sim.skill_timeline.peak],
		"bombs": bombs, "delivery_pool": [sim.hero_effects._serial, sim.hero_effects._next_burst],
		"enemies": enemies, "shots": shots, "souls": souls, "zones": zones, "effects": effects,
		"skill_damage": sim.damage_by_skill, "weapon_damage": sim.damage_by_weapon, "damage_records": _receipts,
		"obstacles": sim.obstacles.snapshot(), "walls": sim.obstacles.walls.snapshot(), "interactions": sim.interactions.snapshot(),
		"rng": [str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)]})

func _fail(app: Node, options: Dictionary, message: String) -> void:
	push_error(message)
	print("WF_ACTION_PREVIEW ", JSON.stringify({"hero": options["hero"], "arena": options["arena"], "view": options["view"], "region": options["region"], "error": message, "view_checks": _view_checks, "profile_io": false, "persistent_profile": app.store.persistent}))
	app.world.stop()
	await app._quit_game(1)
