extends SceneTree
## Native placement fixture: formal transactions, controlled UI position, no player profile.

const TEST_BUDGET: int = 1200
const SEED: int = 20261026

var _state: RunState
var _ui: GameUI
var _case: String = "merge"
var _capture: String = ""
var _hold: bool = false
var _setup_ok: bool = true
var _transactions: Array[Dictionary] = []


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
	if _case not in ["merge", "rune", "move", "blocked"] or DisplayServer.get_name() == "headless":
		_invalid()
		return
	if _capture.is_empty():
		_capture = "res://reports/backpack/targets-%s.png" % _case
	if not _capture.to_lower().ends_with(".png"):
		_invalid()
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 背包目标验证 / %s（固定场景，不保存档案）" % _case
	_state = RunState.new()
	_state.begin(SEED, "bone")
	_state.wave = 4
	_state.gold = TEST_BUDGET
	for row: int in 2:
		var paid: int = _state.backpack.expansion_cost()
		var expanded: bool = _state.expand_backpack()
		_setup_ok = expanded and _setup_ok
		_transactions.append({"operation": "expand", "paid": paid, "success": expanded})
	var first_bone: int = int(_state.loadout[0]["uid"])
	var held_bone: int = _purchase("weapon", "bone")
	_purchase("weapon", "bone")
	var socket_weapon: int = _purchase("weapon", "frost")
	var square_weapon: int = _purchase("weapon", "ember")
	_purchase("relic", "damage")
	_purchase("relic", "damage")
	var attached_rune: int = _purchase("rune", "pierce")
	var equipped: bool = _state.equip_rune(_state.rune_index_for_uid(attached_rune), _state.weapon_index_for_uid(socket_weapon))
	_setup_ok = equipped and _setup_ok
	_transactions.append({"operation": "equip", "source": attached_rune, "target": socket_weapon, "success": equipped})
	var held_rune: int = _purchase("rune", "bounce")
	_purchase("rune", "bounce")
	_purchase("rune", "pierce")
	_purchase("rune", "blast")
	_state.offers = [_offer("weapon", "bone"), _offer("relic", "damage"), _offer("rune", "bounce"), _offer("rune", "blast")]
	var inventory: Dictionary = _state.backpack_snapshot()
	_setup_ok = _setup_ok and _inventory_is_legal(inventory)
	if not _setup_ok:
		push_error("The backpack-target fixture could not construct its legal 6 by 6 inventory through formal transactions.")
		quit(1)
		return
	var state_before: Dictionary = _state_snapshot()
	var changed_count: Array[int] = [0]
	_state.changed.connect(func() -> void: changed_count[0] += 1)
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	_ui.show_shop()
	for frame: int in 4:
		await process_frame
	var grid: Control = _ui.find_child("BackpackGrid", true, false) as Control
	if grid == null or not grid.has_method("begin_placement") or not grid.has_method("placement_at") or not grid.has_method("select_item"):
		push_error("The native shop did not expose its established placement API.")
		quit(1)
		return
	var source: int = held_bone
	var cursor := Vector2i(4, 3)
	var expected_kind: String = "move"
	var expected_target: int = -1
	match _case:
		"merge":
			expected_target = first_bone
			cursor = _cell_of(first_bone)
			expected_kind = "merge"
		"rune":
			source = held_rune
			expected_target = socket_weapon
			cursor = _cell_of(socket_weapon)
			expected_kind = "rune"
		"blocked":
			source = square_weapon
			cursor = Vector2i(5, 5)
			expected_kind = ""
	var source_item: Dictionary = _state.backpack_item(source)
	var rotated: bool = bool(source_item.get("rotated", false))
	# Selection/pickup use the real UI. Only the destination cell is a controlled
	# presentation condition; no move, merge or equip is committed by the fixture.
	grid.call("select_item", source)
	grid.call("begin_placement", source, rotated, cursor)
	_caption()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var actual_cursor: Vector2i = grid.get("cursor")
	var placement: Dictionary = grid.call("placement_at", actual_cursor)
	var targets: Dictionary = {"available": false, "items": []}
	if grid.has_method("placement_targets"):
		var candidates: Array = grid.call("placement_targets")
		targets = {"available": true, "items": candidates.duplicate(true)}
	var state_after: Dictionary = _state_snapshot()
	var passed: bool = state_before == state_after and changed_count[0] == 0 and actual_cursor == cursor and int(grid.get("held_uid")) == source
	if _case == "blocked":
		passed = passed and not bool(placement.get("valid", true))
	else:
		passed = passed and bool(placement.get("valid", false)) and str(placement.get("kind", "")) == expected_kind
		if expected_target >= 0:
			passed = passed and int(placement.get("target", -1)) == expected_target
	var absolute: String = ProjectSettings.globalize_path(_capture)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	print("BACKPACK_TARGET_PREVIEW ", JSON.stringify({"case": _case, "fixed_fixture": true,
		"formal_transactions": true, "controlled_placement": true, "persistent_profile": false,
		"test_budget": TEST_BUDGET, "seed": SEED, "viewport": [root.size.x, root.size.y],
		"transactions": _transactions, "inventory": inventory, "state": state_after,
		"state_fingerprint_before": _fingerprint(state_before), "state_fingerprint_after": _fingerprint(state_after),
		"inventory_fingerprint": _fingerprint(inventory), "changed_during_ui": changed_count[0],
		"held_uid": int(grid.get("held_uid")), "held_rotated": bool(grid.get("held_rotated")),
		"selected_uid": int(grid.get("selected_uid")), "cursor": [actual_cursor.x, actual_cursor.y],
		"placement_at": placement, "targets": targets, "capture": _capture, "capture_result": result,
		"fixture_passed": passed, "hold": _hold}))
	if not passed:
		push_error("Backpack-target preview changed run state or failed to retain its intended placement class.")
	if not _hold or not passed or result != OK:
		quit(0 if passed and result == OK else 1)


func _offer(kind: String, id: String) -> Dictionary:
	return {"kind": kind, "id": id, "price": _state.shop_price(BackpackInventory.definition(kind, id)), "sold": false}


func _purchase(kind: String, id: String) -> int:
	var offer: Dictionary = _offer(kind, id)
	_state.offers = [offer]
	var bought: bool = _state.buy_offer(0)
	_setup_ok = bought and _setup_ok
	var uid: int = -1
	if bought:
		uid = int((_state.backpack_snapshot()["items"] as Array).back()["uid"])
	_transactions.append({"operation": "buy", "kind": kind, "id": id, "paid": int(offer["price"]), "uid": uid, "success": bought})
	return uid


func _cell_of(uid: int) -> Vector2i:
	var entry: Dictionary = _state.backpack_item(uid)
	return Vector2i(int(entry.get("x", -1)), int(entry.get("y", -1)))


func _inventory_is_legal(snapshot: Dictionary) -> bool:
	if int(snapshot.get("width", 0)) != 6 or int(snapshot.get("height", 0)) != 6:
		return false
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(6, 6))
	var occupied: Dictionary = {}
	var uids: Dictionary = {}
	for entry: Dictionary in snapshot.get("items", []):
		var uid: int = int(entry["uid"])
		if uids.has(uid):
			return false
		uids[uid] = true
		var dimensions: Vector2i = BackpackInventory.size_for(str(entry["kind"]), str(entry["id"]), bool(entry["rotated"]))
		var area := Rect2i(Vector2i(int(entry["x"]), int(entry["y"])), dimensions)
		if dimensions.x <= 0 or dimensions.y <= 0 or not bounds.encloses(area):
			return false
		for y: int in range(area.position.y, area.end.y):
			for x: int in range(area.position.x, area.end.x):
				var cell := Vector2i(x, y)
				if occupied.has(cell):
					return false
				occupied[cell] = uid
	return occupied.size() == int(snapshot.get("used_cells", -1))


func _state_snapshot() -> Dictionary:
	return {"summary": _state.summary(), "offers": _state.offers.duplicate(true), "last_error": _state.last_error,
		"rng_seed": str(_state.rng.seed), "rng_state": str(_state.rng.state),
		"backpack_last_error": _state.backpack.last_error, "next_rune_uid": _state.get("_next_rune_uid")}


func _fingerprint(value: Dictionary) -> String:
	return JSON.stringify(value).sha256_text()


func _caption() -> void:
	var caption := Label.new()
	caption.text = "固定预算1200魂屑 · 正式购买库存 · 拿起/光标为受控陈列 · 非自然对局 · 不写档案 · " + _case
	caption.position = Vector2(330, 3)
	caption.size = Vector2(910, 17)
	caption.clip_text = true
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", GameUI.CYAN)
	_ui._root.add_child(caption)


func _invalid() -> void:
	push_error("Use native rendering with --case=merge|rune|move|blocked, optional --capture=<path.png> and --hold.")
	quit(2)
