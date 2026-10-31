extends Node
## Native source/PCK/release fixtures share real Main, inventory, actors and draw purity.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const SEED: int = 20261102
const VIEWS: Array[String] = ["shop-own", "shop-fire", "shop-dark", "merge", "sell", "staff-zero", "staff-four", "combat"]
const EQUIPMENT: Array[String] = ["sword_0005", "bow_0006", "book_0002", "fist_0006", "staff_0001"]
var _checks: Dictionary = {}
var _receipts: Array[Dictionary] = []
var _manual_steps: int = 0
var _selected_uid: int = -1
var _manual_shots: Array[String] = []

func _ready() -> void:
	_preview.call_deferred()

func _options() -> Dictionary:
	var options: Dictionary = {"view": "shop-own", "small": false, "gamepad": false, "capture": ""}
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--wf-equipment-preview":
			continue
		if argument.begins_with("--view="):
			options["view"] = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			options["capture"] = argument.trim_prefix("--capture=").replace("\\", "/")
		elif argument == "--small":
			options["small"] = true
		elif argument == "--gamepad":
			options["gamepad"] = true
		else:
			return {"error": "Unknown equipment preview argument: " + argument}
	var path: String = str(options["capture"])
	if options["view"] not in VIEWS:
		return {"error": "An existing equipment preview view is required"}
	if path.is_empty() or not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://") or path.get_extension().to_lower() != "png":
		return {"error": "--capture requires an absolute filesystem PNG path"}
	if DisplayServer.get_name() == "headless":
		return {"error": "Equipment previews require the native renderer"}
	return options

func _record(check_name: String, passed: bool) -> bool:
	_checks[check_name] = passed
	return passed

func _all_checks() -> bool:
	for value: Variant in _checks.values():
		if value != true:
			return false
	return not _checks.is_empty()

func _settle() -> void:
	for frame: int in 5:
		await get_tree().process_frame

func _preview() -> void:
	var options: Dictionary = _options()
	if options.has("error"):
		print("WF_EQUIPMENT_PREVIEW ", JSON.stringify({"error": options["error"], "profile_io": false, "debug_build": OS.is_debug_build()}))
		get_tree().quit(2)
		return
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_tree().root.size = Vector2i(960, 540) if bool(options["small"]) else Vector2i(1280, 720)
	var app: Node = MAIN.instantiate()
	app.set_meta("wf_equipment_preview_child", true)
	app.store.persistent = false
	get_tree().root.add_child(app)
	app.set_process(false)
	app._screenshot_clock = -1.0
	app.args.append("--autoplay")
	app.sound.set_volume(0.0)
	var view: String = str(options["view"])
	var hero_id: String = "falsche" if view in ["shop-dark", "staff-zero", "staff-four"] else "mordiga"
	app.ui.set_selected_hero(hero_id)
	app.ui.set_selected_arena("throne")
	app._begin_run("bone", SEED)
	var world: CombatWorld = app.world
	world.set_physics_process(false)
	world.autopilot = false
	world.apply_visual_settings({"shake": false, "flash": true})
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(99999.0)
	sim.player_direction = Vector2.RIGHT
	ControlBindings.ensure_installed()
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(ControlBindings.PREFIX + action)
	var records: Array[Dictionary] = _receipts
	sim.damage_dealt.connect(func(_point: Vector2, amount: float, source: String, _secondary: bool, uid: int) -> void:
		records.append({"source": source, "amount": amount, "uid": uid})
	)
	app.run.gold = 10000
	while app.run.backpack.height < 6:
		if not app.run.expand_backpack():
			await _fail(app, options, "Production backpack expansion failed")
			return
	var fixture_ready: bool = await _prepare(app, view)
	if not fixture_ready or not _all_checks():
		await _fail(app, options, "The real equipment fixture did not satisfy its ownership/scope checks")
		return
	app.ui._on_input_device_changed("gamepad" if bool(options["gamepad"]) else "keyboard", 0 if bool(options["gamepad"]) else -1)
	world._update_camera()
	get_tree().root.warp_mouse(Vector2(20, 20))
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(20, 20)
	pointer.global_position = pointer.position
	get_tree().root.push_input(pointer, false)
	await _settle()
	var before: String = _signature(sim)
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
	var native_frames: int = Engine.get_frames_drawn() - native_before
	var after: String = _signature(sim)
	var pure: bool = warmup_pure and before == after
	var destination: String = str(options["capture"])
	var result: Error = DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if result == OK:
		result = get_tree().root.get_texture().get_image().save_png(destination)
	var passed: bool = _all_checks() and result == OK and pure and native_frames >= 2 and draws[0] >= 2 and not app.store.persistent
	print("WF_EQUIPMENT_PREVIEW ", JSON.stringify({"view": view, "hero_id": hero_id, "small": options["small"], "gamepad_prompts": options["gamepad"],
		"debug_build": OS.is_debug_build(), "engine_version": Engine.get_version_info()["string"], "profile_io": false, "persistent_profile": app.store.persistent,
		"seed": SEED, "manual_step_seconds": STEP, "manual_steps": _manual_steps, "elapsed": sim.elapsed, "inventory": app.run.backpack_snapshot(),
		"selected_uid": _selected_uid, "R": sim.hero_skill_snapshot(), "weapon_effects": sim.weapon_effects.snapshot(), "damage_records": _receipts,
		"manual_projectile_sources": _manual_shots, "checks": _checks, "state_hash": before.sha256_text(), "state_hash_after": after.sha256_text(),
		"pure_drawing": pure, "state_unchanged_after_warmup": warmup_pure, "native_frames_drawn": native_frames, "world_draws_observed": draws[0],
		"fixed_fixture": true, "natural_gameplay": false, "physical_gamepad_test": false, "capture": destination, "result": result, "passed": passed,
		"fixture_interventions": ["fixed starting currency for genuine purchases/expansion", "production inventory and actor identities", "disabled automatic weapons and fixed manual World steps", "static high-health targets and production fire_weapon samples in combat view", "production map collision/camera"]}))
	world.stop()
	await app._quit_game(0 if passed else 1)

func _offer(state: RunState, id: String, kind: String = "weapon") -> void:
	state.offers.assign([{"kind": kind, "id": id, "price": state.shop_price(BackpackInventory.definition(kind, id)), "sold": false}])

func _buy(state: RunState, id: String, kind: String = "weapon") -> int:
	_offer(state, id, kind)
	if not state.buy_offer(0):
		return -1
	var items: Array = state.backpack_snapshot()["items"]
	return int(items.back()["uid"])

func _step(world: CombatWorld) -> void:
	world._physics_process(STEP)
	_manual_steps += 1

func _prepare(app: Node, view: String) -> bool:
	var state: RunState = app.run
	if view == "combat":
		for id: String in EQUIPMENT:
			if _buy(state, id) < 0:
				return false
		var starter_uid: int = int(state.loadout[0]["uid"])
		if not state.sell_item(starter_uid):
			return false
	if _buy(state, "starfall", "skill") < 0 or _buy(state, "arc_slash", "skill") < 0:
		return false
	if not _record("real_two_rear_actors", state.active_skills.size() == 2):
		return false
	if view in ["staff-zero", "staff-four", "combat"]:
		if view != "combat":
			_selected_uid = _buy(state, "staff_0001")
			if _selected_uid < 0:
				return false
		return _prepare_combat(app, view)
	var id: String = "fist_0006" if view == "shop-fire" else "book_0002" if view == "shop-dark" else "bow_0006"
	if view in ["merge", "sell"]:
		_selected_uid = _buy(state, id)
		if _selected_uid < 0:
			return false
		if view == "merge" and _buy(state, id) < 0:
			return false
	else:
		_offer(state, id)
	app.ui.show_shop()
	await _settle()
	var expected: Dictionary = {state.hero_id: "+47.5%", "hanabi": "0%", "celtie": "0%"}
	var node_name: String = "EquipmentPurchaseActors"
	if view == "shop-fire":
		expected = {"mordiga": "0%", "hanabi": "+22.5%", "celtie": "0%"}
	elif view == "shop-dark":
		expected = {"falsche": "+22.5%", "hanabi": "0%", "celtie": "0%"}
	if view in ["merge", "sell"]:
		app.ui._bp_select(_selected_uid, app.ui._shop_epoch)
		expected[state.hero_id] = "0%" if view == "merge" else "-32.2%"
		node_name = "EquipmentMergeActors" if view == "merge" else "EquipmentSaleActors"
	else:
		app.ui._show_offer_record(0, app.ui._shop_epoch, state.offers[0].duplicate(true))
	await _settle()
	return _validate_actor_ui(app.ui, state.hero_id, node_name, expected)

func _validate_actor_ui(ui: GameUI, hero_id: String, node_name: String, expected: Dictionary) -> bool:
	var owner: Node = ui.find_child("EquipmentOwner", true, false)
	var portrait := owner.find_child("EquipmentOwnerPortrait", true, false) as TextureRect if owner != null else null
	var name_label := owner.find_child("EquipmentOwnerName", true, false) as Label if owner != null else null
	_record("owner_is_actual_main", owner != null and owner.get_meta("owner_ref", {}) == {"kind": "main"} and name_label != null and name_label.text == HeroCatalog.definition(hero_id).display_name)
	_record("owner_original_portrait", portrait != null and portrait.texture != null and portrait.texture.resource_path == HeroCatalog.definition(hero_id).idle_path)
	var panel: Node = ui.find_child(node_name, true, false)
	var grid: Node = panel.find_child("EquipmentActors", true, false) if panel != null else null
	_record("three_actor_comparison", grid != null and grid.get_child_count() == expected.size())
	if grid == null:
		return false
	for cell: Node in grid.get_children():
		var id: String = str(cell.get_meta("hero_id", ""))
		var label := cell.find_child("EquipmentActorDelta", true, false) as Label
		_record("relative_scope_" + id, expected.has(id) and label != null and label.text == str(expected.get(id, "")))
	return _all_checks()

func _prepare_combat(app: Node, view: String) -> bool:
	var world: CombatWorld = app.world
	var sim: CombatSim = world.sim
	sim._cooldowns.resize(app.run.loadout.size())
	sim._cooldowns.fill(99999.0)
	var point: Vector2 = sim.obstacles.free_point(sim.player_position, 16.0, 16.0)
	if not sim.obstacles.is_free(point, 16.0, 16.0):
		return false
	sim.player_position = point
	for offset: Vector2 in [Vector2(90, 0), Vector2(-90, 0)]:
		var target: Vector2 = sim.obstacles.free_point(point + offset, 22.0)
		var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", target, true)
		if enemy == null:
			return false
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.health = 1000000.0
		enemy.max_health = enemy.health
		enemy.action_timer = 99999.0
	_step(world)
	if view == "staff-four":
		for cast: int in 4:
			for frame: int in 1800:
				if bool(sim.hero_skill_snapshot()["ready"]):
					break
				_step(world)
			if not world.request_hero_skill():
				return false
			_step(world)
	elif view == "combat":
		if not world.request_hero_skill():
			return false
		for frame: int in 43:
			_step(world)
		if not world.request_skill(0) or not world.request_skill(1):
			return false
		for index: int in EQUIPMENT.size():
			var id: String = EQUIPMENT[index]
			if sim.fire_weapon(id, "", sim.player_position, Vector2.RIGHT.rotated((float(index) - 2.0) * 0.4)) == null:
				return false
			_manual_shots.append(id)
		for frame: int in 6:
			_step(world)
		_record("five_real_equipped_items", app.run.loadout.size() == 5 and _manual_shots.size() == 5)
		var legal: bool = true
		for item: Dictionary in app.run.loadout:
			legal = legal and EQUIPMENT.has(str(item["id"])) and item.get("owner_ref", {}) == {"kind": "main"}
		_record("equipment_owned_and_legally_stored", legal and _legal_backpack(app.run.backpack))
		_record("real_main_and_rear_skills", int(sim.hero_skill_snapshot()["uses"]) == 1 and int(sim.active_skill_snapshot(0).get("uses", 0)) == 1 and int(sim.active_skill_snapshot(1).get("uses", 0)) == 1)
		_record("live_original_timeline_area", int(sim.skill_timeline.snapshot()["occupied"]) > 0)
	else:
		_record("zero_cast_is_not_synthetic_windup", int(sim.hero_skill_snapshot()["uses"]) == 0)
	app.ui.show_hud()
	app.ui.update_hud(world.hud_snapshot())
	if view.begins_with("staff-"):
		var expected_stacks: int = 4 if view == "staff-four" else 0
		var row: Node = app.ui.find_child("EquipmentCastPips_%d" % _selected_uid, true, false)
		var count := row.find_child("EquipmentCastCount", true, false) as Label if row != null else null
		_record("staff_hud_uid_stacks", count != null and count.text == "%d/4" % expected_stacks)
		var actual: int = -1
		for record: Dictionary in sim.weapon_effects.snapshot().get("items", []):
			if int(record.get("uid", -2)) == _selected_uid:
				actual = int(record.get("party_cast_stacks", 0))
		_record("staff_runtime_committed_stacks", actual == expected_stacks and int(sim.hero_skill_snapshot()["uses"]) == expected_stacks)
	return _all_checks()

func _legal_backpack(backpack: BackpackInventory) -> bool:
	var state: Dictionary = backpack.snapshot()
	var occupied: Dictionary = {}
	var uids: Dictionary = {}
	for item: Dictionary in state["items"]:
		var uid: int = int(item["uid"])
		if uids.has(uid) or backpack.item(uid) != item:
			return false
		uids[uid] = true
		var size: Vector2i = BackpackInventory.size_for(str(item["kind"]), str(item["id"]), bool(item["rotated"]))
		var cell := Vector2i(int(item["x"]), int(item["y"]))
		if size.x <= 0 or size.y <= 0 or cell.x < 0 or cell.y < 0 or cell.x + size.x > int(state["width"]) or cell.y + size.y > int(state["height"]):
			return false
		for y: int in size.y:
			for x: int in size.x:
				var position: Vector2i = cell + Vector2i(x, y)
				if occupied.has(position):
					return false
				occupied[position] = uid
	return occupied.size() == int(state["used_cells"])

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
		"equipment_effects": sim.weapon_effects.snapshot(),
		"obstacles": sim.obstacles.snapshot(), "walls": sim.obstacles.walls.snapshot(), "interactions": sim.interactions.snapshot(),
		"rng": [str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)]})

func _fail(app: Node, options: Dictionary, message: String) -> void:
	push_error(message)
	print("WF_EQUIPMENT_PREVIEW ", JSON.stringify({"error": message, "view": options["view"], "checks": _checks, "profile_io": false, "persistent_profile": app.store.persistent, "debug_build": OS.is_debug_build()}))
	app.world.stop()
	await app._quit_game(1)
