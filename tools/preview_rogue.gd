extends SceneTree
## Fixed shop/UI fixtures use formal inventory/decision transactions, never player profiles.

var _state: RunState
var _ui: GameUI
var _case: String = "core"
var _capture: String = ""
var _hold: bool = false
var _transactions: Array[Dictionary] = []
var _setup_ok: bool = true
var _hunter_fixture: bool = false
var _window_size := Vector2i(1280, 720)

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			_case = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			_capture = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			_hold = true
		elif argument.begins_with("--size="):
			var requested: String = argument.trim_prefix("--size=")
			if requested not in ["1280x720", "960x540"]:
				_invalid()
				return
			_window_size = Vector2i(960, 540) if requested == "960x540" else Vector2i(1280, 720)
		else:
			_invalid()
			return
	if _case not in ["core", "altar", "reward", "route", "lamp", "title", "unlocked"] or DisplayServer.get_name() == "headless":
		_invalid()
		return
	if _capture.is_empty():
		_capture = "res://reports/rogue-%s.png" % _case
	if not _capture.to_lower().ends_with(".png"):
		_invalid()
		return
	root.size = _window_size
	root.title = "秘术余烬 · 秘术抉择固定验证 / %s（不保存档案）" % _case
	_state = RunState.new()
	_state.begin(20261026, "bone")
	_state.finish_wave()
	_transactions.append({"operation": "finish_wave", "wave": 1})
	if _case not in ["core", "title", "unlocked"]:
		var selected: bool = _state.choose_core("frostfire")
		_setup_ok = selected and _setup_ok
		_transactions.append({"operation": "choose_core", "id": "frostfire", "success": selected})
		_state.next_wave()
		_state.finish_wave()
		_transactions.append({"operation": "finish_wave", "wave": 2})
	if _case == "reward":
		var accepted: bool = _state.choose_altar(true)
		_setup_ok = accepted and _setup_ok
		_transactions.append({"operation": "choose_altar", "accepted": true, "success": accepted})
		_state.next_wave()
		# A fixed lethal hit uses the real hunter/kill path. This is a controlled
		# outcome, not a natural battle or a proof of challenge difficulty.
		var sim := CombatSim.new()
		sim.begin(_state)
		for enemy: CombatSim.Enemy in sim.enemies:
			if enemy.active and enemy.hunter:
				sim.apply_damage(enemy, enemy.health, "bone")
				_hunter_fixture = true
				break
		_setup_ok = _state.hunter_defeated and _state.rune_reward_pending and _setup_ok
		_state.finish_wave()
		_transactions.append({"operation": "controlled_hunter_kill", "success": _hunter_fixture})
	if _case in ["route", "lamp"]:
		while _state.wave < 4:
			_state.next_wave()
			_state.finish_wave()
		var routed: bool = _state.choose_route("bulwark")
		_setup_ok = routed and _setup_ok
		_transactions.append({"operation": "choose_route", "id": "bulwark", "success": routed})
	_state.gold = 600
	if _case == "lamp":
		_state.offers = [{"kind": "relic", "id": "grave_candle", "price": _state.shop_price(GameCatalog.relic("grave_candle")), "sold": false}]
		var bought: bool = _state.buy_offer(0)
		var uid: int = int(_state.backpack_snapshot()["next_uid"]) - 1
		var moved: bool = bought and _state.move_item(uid, Vector2i(0, 3), false)
		_setup_ok = moved and _setup_ok
		_transactions.append({"operation": "buy_and_place_candle", "uid": uid, "success": moved})
	_state.generate_shop()
	var before: String = _signature()
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	if _case in ["title", "unlocked"]:
		if _case == "unlocked":
			_ui.set_progress(["bone", "ember", "frost", "scatter"])
		_ui.show_title({})
	else:
		_ui.show_shop()
	for frame: int in 5:
		await process_frame
	if _case == "lamp":
		for item: Dictionary in _state.backpack_snapshot()["items"]:
			if item["kind"] == "relic" and item["id"] == "grave_candle":
				_ui._bp_select(int(item["uid"]), _ui._shop_epoch)
	elif _case not in ["title", "unlocked"]:
		var entry: Button = _ui.find_child("OpenRogueChoices", true, false)
		entry.pressed.emit()
	var caption := Label.new()
	caption.text = "固定验证 · 正式事务 / 受控波末与击杀 · 非自然对局 · 不保存档案 · " + _case
	caption.position = Vector2(360, 3)
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = Color("89d8d2")
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui._root.add_child(caption)
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var after: String = _signature()
	var path: String = ProjectSettings.globalize_path(_capture)
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(path)
	var passed: bool = _setup_ok and before == after and (_case in ["lamp", "title", "unlocked"] or _ui._overlay_mode == "rogue_choices")
	print("ROGUE_PREVIEW ", JSON.stringify({"case": _case, "fixed_fixture": true, "formal_transactions": true,
		"controlled_wave_settlement": true, "controlled_hunter_kill": _hunter_fixture, "test_budget": 600,
		"persistent_profile": false, "viewport": [root.size.x, root.size.y], "state": _state.summary(),
		"state_sha256_before": before.sha256_text(), "state_sha256_after": after.sha256_text(),
		"transactions": _transactions, "capture": _capture, "capture_result": result,
		"fixture_passed": passed, "hold": _hold}))
	if not _hold or not passed or result != OK:
		quit(0 if passed and result == OK else 1)

func _signature() -> String:
	return JSON.stringify({"summary": _state.summary(), "rng": str(_state.rng.state), "offers": _state.offers})

func _invalid() -> void:
	push_error("Usage: native --script res://tools/preview_rogue.gd -- --case=core|altar|reward|route|lamp|title|unlocked [--size=1280x720|960x540] [--capture=<png>] [--hold]")
	quit(2)
