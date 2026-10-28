extends SceneTree
## Paid, merged inventory fixtures using the real Main and fixed combat step.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const CASES: PackedStringArray = ["shop", "comparison", "merge", "cast", "flash_off", "corner", "interactive"]
const STEP: float = 1.0 / 60.0
var _app: Node
var _case: String = "cast"
var _output: String = "res://reports/skill-relics/cast.png"
var _hold: bool = false
var _events: Array[Dictionary] = []

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			_case = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			_output = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			_hold = true
		else:
			_invalid()
			return
	if DisplayServer.get_name() == "headless" or _case not in CASES or not _output.to_lower().ends_with(".png"):
		_invalid()
		return
	root.size = Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	_app.sound.set_volume(0.0)
	_app.ui.set_selected_arena("mire")
	_app._begin_run("bone", 20261028)
	if _app.run.backpack.add("skill", "pulse").is_empty():
		_fail("The preview could not place its pulse skill box")
		return
	_app.run._sync_backpack_projection()
	_app.world.set_physics_process(false)
	_app.run.gold = 500
	var shop_case: bool = _case in ["shop", "comparison", "merge"]
	var selected_uid: int = -1
	for id: String in ["fold_clasp", "echo_stone"]:
		var uids: Array[int] = []
		for copy: int in (2 if shop_case else 4):
			var uid: int = _buy(id)
			if uid < 0:
				_fail("A real skill-relic purchase failed")
				return
			uids.append(uid)
		if not shop_case:
			if not _app.run.merge_items(uids[1], uids[0]) or not _app.run.merge_items(uids[3], uids[2]) or not _app.run.merge_items(uids[2], uids[0]):
				_fail("Real rank-III skill-relic merges failed")
				return
		if id == "fold_clasp":
			selected_uid = uids[0]
	if shop_case:
		_app.world.hide()
		_app.run.offers.clear()
		for entry: Array in [["relic", "fold_clasp"], ["relic", "echo_stone"], ["weapon", "return_ring"], ["rune", "blast"]]:
			var definition: ContentDef = BackpackInventory.definition(str(entry[0]), str(entry[1]))
			_app.run.offers.append({"kind": entry[0], "id": entry[1], "price": definition.price, "sold": false})
		_app.ui.show_shop()
		_app.ui._bp_select(selected_uid, _app.ui._shop_epoch)
		if _case == "comparison":
			_app.ui._compare_relic(1, _app.ui._shop_epoch, _app.run.offers[1].duplicate(true))
		elif _case == "merge":
			for other: Dictionary in _app.run.backpack_snapshot()["items"]:
				if bool(_app.run.merge_preview(selected_uid, int(other["uid"])).get("can_merge", false)):
					_app.ui._bp_merge(selected_uid, int(other["uid"]), _app.ui._shop_epoch)
					break
	else:
		_app.world.begin(_app.run)
		_app.world.set_physics_process(false)
		var sim: CombatSim = _app.world.sim
		sim.sandbox = true
		sim._cooldowns.fill(9999.0)
		if _case == "corner":
			sim.player_position = CombatSim.ARENA.position + Vector2(30, 30)
		var origin: Vector2 = sim.player_position
		for offset: Vector2 in [Vector2(160, 0), Vector2(-180, 0), Vector2(0, 200), Vector2(217, 0)]:
			var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", CombatSim.clamp_point(origin + offset))
			enemy.definition = enemy.definition.duplicate() as ContentDef
			enemy.definition.speed = 0.0
			enemy.action_timer = 9999.0
		sim.pulse_cast.connect(func(point: Vector2, affected: int) -> void:
			_events.append({"origin": [point.x, point.y], "affected": affected, "radius": sim.pulse_snapshot()["last_cast_radius"], "cooldown": sim.pulse_snapshot()["cooldown_total"]})
			print("SKILL_RELIC_EVENT ", JSON.stringify(_events.back())))
		if _case == "flash_off":
			_app.world.apply_visual_settings({"flash": false, "shake": true})
		if _case != "interactive":
			if not _app.world.request_pulse() or not _app.world.request_dash():
				_fail("Real active skill requests were rejected")
				return
			_app.world._physics_process(STEP)
		_app.ui.update_hud(_app.world.hud_snapshot())
	var caption := Label.new()
	caption.position = Vector2(340, 104)
	caption.text = "技能遗物固定验证 · 实际购买与合成 · 非自然对局 · 不保存档案"
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = GameUI.GOLD
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.visible = not shop_case
	_app.ui._root.add_child(caption)
	root.title = "秘术余烬 · 技能遗物验证 / %s（固定场景，不保存档案）" % _case
	for frame: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(_output)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	print("SKILL_RELIC_PREVIEW ", JSON.stringify({"case": _case, "capture_result": result, "persistent_profile": _app.store.persistent,
		"fixture_gold_before": 500, "gold_after": _app.run.gold, "backpack": _app.run.backpack_snapshot(),
		"dash_cooldown": _app.run.stat("dash_cooldown"), "pulse_radius": _app.run.stat("pulse_radius"), "pulse_cooldown": _app.run.stat("pulse_cooldown"),
		"dash": _app.world.sim.dash_snapshot(), "pulse": _app.world.sim.pulse_snapshot(), "feedback": _app.world.pulse_feedback_snapshot(), "events": _events}))
	if not _hold or result != OK:
		_app._quit_game(0 if result == OK else 1)
		return
	if _case == "interactive":
		_app.world.set_physics_process(true)

func _buy(id: String) -> int:
	_app.run.offers.assign([{"kind": "relic", "id": id, "price": GameCatalog.relic(id).price, "sold": false}])
	if not _app.run.buy_offer(0):
		return -1
	var items: Array = _app.run.backpack_snapshot()["items"]
	return int(items.back()["uid"])

func _fail(message: String) -> void:
	push_error(message)
	_app._quit_game(1)

func _invalid() -> void:
	push_error("Use native --case=shop|comparison|merge|cast|flash_off|corner|interactive [--capture=path.png] [--hold]")
	quit(2)
