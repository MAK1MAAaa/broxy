extends SceneTree
## An isolated, interactive backpack shop fixture; never loads or saves a player profile.

var _state: RunState
var _ui: GameUI
var _case: String = "filled"
var _hold: bool = false
var _capture: String = ""
var _selected: int = -1

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
		else:
			_invalid()
			return
	if _case not in ["empty", "filled", "merge", "full"] or DisplayServer.get_name() == "headless":
		_invalid()
		return
	if _capture.is_empty():
		_capture = "res://reports/backpack/%s.png" % _case
	if not _capture.to_lower().ends_with(".png"):
		_invalid()
		return
	root.size = Vector2i(1280, 720)
	_state = RunState.new()
	_state.begin(20261024, "bone")
	_state.wave = 1 if _case == "empty" else 4
	_state.gold = 80 if _case == "empty" else 1200
	var test_budget: int = _state.gold
	if _case in ["filled", "full"]:
		_make_filled()
	elif _case == "merge":
		_selected = _purchase("weapon", "bone")
		_purchase("relic", "damage")
		_purchase("relic", "damage")
		_purchase("rune", "pierce")
		_purchase("rune", "pierce")
	if _case == "full":
		assert(_state.expand_backpack(), "The full fixture must pay for the sixth row")
		for count: int in 40:
			_state.offers = [_offer("relic", "armor")]
			if not _state.purchase_error(0).is_empty():
				break
			assert(_state.buy_offer(0), "The full fixture must use real free-cell purchases")
		_selected = int((_state.backpack_snapshot()["items"] as Array).back()["uid"])
	_state.offers = [_offer("weapon", "return_ring"), _offer("weapon", "bone"), _offer("relic", "grave_candle"), _offer("rune", "blast")]
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	_ui.show_shop()
	for frame: int in 5:
		await process_frame
	if _selected >= 0:
		_ui._bag_grid.select_item(_selected)
	var caption := Label.new()
	caption.text = "背包整理固定验证 · 正式购买与合成 · 非自然对局 · 不保存档案"
	caption.position = Vector2(420, 3)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 12)
	caption.modulate = Color("89d8d2")
	_ui._root.add_child(caption)
	root.title = "秘术余烬 · 背包交互验证 / %s（固定构筑，不保存档案）" % _case
	_state.changed.connect(_print_state.bind("changed"))
	_print_state("initial")
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(_capture)
	var result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(path)
	var snapshot: Dictionary = _state.backpack_snapshot()
	var passed: bool = snapshot["items"].size() > 0 and _ui.find_child("BackpackGrid", true, false) != null
	if _case == "full":
		passed = passed and snapshot["used_cells"] == snapshot["total_cells"] and snapshot["height"] == 6
	print("BACKPACK_PREVIEW ", JSON.stringify({"case": _case, "fixed_fixture": true,
		"formal_transactions": true, "test_budget": test_budget, "persistent_profile": false,
		"viewport": [root.size.x, root.size.y], "selected_uid": _selected,
		"backpack": snapshot, "loadout": _state.loadout, "rune_bag": _state.rune_bag,
		"capture": _capture, "capture_result": result, "fixture_passed": passed, "hold": _hold}))
	if not _hold or not passed or result != OK:
		quit(0 if passed and result == OK else 1)

func _offer(kind: String, id: String) -> Dictionary:
	return {"kind": kind, "id": id, "price": _state.shop_price(BackpackInventory.definition(kind, id)), "sold": false}

func _purchase(kind: String, id: String) -> int:
	_state.offers = [_offer(kind, id)]
	assert(_state.buy_offer(0), "The fixture must buy and auto-place " + id)
	return int((_state.backpack_snapshot()["items"] as Array).back()["uid"])

func _make_filled() -> void:
	assert(_state.expand_backpack(), "The filled fixture must pay for its fifth row")
	var partner: int = _purchase("weapon", "bone")
	assert(_state.merge_items(partner, int(_state.loadout[0]["uid"])), "The fixture must manually merge its two bone boxes")
	for id: String in ["ember", "return_ring", "frost", "scatter"]:
		_purchase("weapon", id)
	_purchase("relic", "damage")
	_purchase("relic", "haste")
	_purchase("relic", "grave_candle")
	var rune: int = _purchase("rune", "pierce")
	assert(_state.equip_rune(_state.rune_index_for_uid(rune), 0), "The fixture must install its purchased rune")
	_selected = _purchase("rune", "bounce")

func _print_state(reason: String) -> void:
	print("BACKPACK_STATE ", JSON.stringify({"reason": reason, "ticks_ms": Time.get_ticks_msec(),
		"gold": _state.gold, "last_error": _state.last_error, "backpack": _state.backpack_snapshot(),
		"loadout": _state.loadout, "rune_bag": _state.rune_bag}))

func _invalid() -> void:
	push_error("Use native rendering with --case=empty|filled|merge|full, --capture=<path.png> and optional --hold.")
	quit(2)
