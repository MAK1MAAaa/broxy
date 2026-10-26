extends SceneTree
## Snapshot-only placement guidance and actual shop keyboard transactions.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var probe := BackpackGrid.new()
	var available: bool = probe.has_method("placement_targets")
	probe.free()
	_check(available, "BackpackGrid provides read-only placement_targets guidance")
	if not available:
		_finish()
		return
	root.size = Vector2i(1280, 720)
	await _test_snapshot_candidates()
	_ui = GameUI.new()
	root.add_child(_ui)
	await _test_keyboard_move_and_cancel()
	await _test_keyboard_edge_merge()
	await _test_keyboard_rune_swap()
	_ui.queue_free()
	await process_frame
	_finish()


func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261026, "bone")
	state.gold = 10000
	return state


func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	var succeeded: bool = state.buy_offer(0)
	_check(succeeded, "Candidate fixture purchases its real inventory: " + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1 if succeeded else -1


func _ranked(state: RunState, kind: String, id: String, rank: int) -> int:
	if rank == 1:
		return _buy(state, kind, id)
	var target: int = _ranked(state, kind, id, rank - 1)
	var source: int = _ranked(state, kind, id, rank - 1)
	_check(state.merge_items(source, target), "Explicit legal merges create a ranked candidate: " + id)
	return target


func _test_snapshot_candidates() -> void:
	var state: RunState = _state()
	_check(state.expand_backpack() and state.expand_backpack(), "The candidate matrix legally unlocks six backpack rows")
	var source: int = int(state.loadout[0]["uid"])
	var match_one: int = _buy(state, "weapon", "bone")
	var rank_two: int = _ranked(state, "weapon", "bone", 2)
	var match_two: int = _ranked(state, "weapon", "bone", 2)
	var rank_three: int = _ranked(state, "weapon", "bone", 3)
	_ranked(state, "weapon", "bone", 3)
	var frost: int = _buy(state, "weapon", "frost")
	var rune_one: int = _buy(state, "rune", "pierce")
	var rune_match: int = _buy(state, "rune", "pierce")
	var rune_two: int = _ranked(state, "rune", "pierce", 2)
	_buy(state, "rune", "bounce")
	var relic: int = _buy(state, "relic", "damage")
	var relic_match: int = _buy(state, "relic", "damage")
	_ranked(state, "relic", "damage", 2)
	_buy(state, "relic", "armor")
	var old_rune: int = _buy(state, "rune", "blast")
	_check(state.equip_rune(state.rune_index_for_uid(old_rune), state.weapon_index_for_uid(frost)), "One rune candidate weapon already owns a formally purchased rune")
	var external: Dictionary = state.backpack_snapshot()
	var grid := BackpackGrid.new()
	grid.configure(external, 51)
	root.add_child(grid)
	await _settle()
	var changed: Array[int] = [0]
	state.changed.connect(func() -> void: changed[0] += 1)
	var emitted: Array[String] = []
	grid.item_selected.connect(func(_uid: int) -> void: emitted.append("selected"))
	grid.move_requested.connect(func(_uid: int, _cell: Vector2i, _rotated: bool) -> void: emitted.append("move"))
	grid.merge_requested.connect(func(_source: int, _target: int) -> void: emitted.append("merge"))
	grid.rune_requested.connect(func(_source: int, _target: int) -> void: emitted.append("rune"))
	grid.holding_changed.connect(func(_uid: int, _rotated: bool, _cell: Vector2i) -> void: emitted.append("holding"))
	grid.hint_changed.connect(func(_text: String) -> void: emitted.append("hint"))
	_check(_targets(grid).is_empty(), "A grid without a held source has no action candidates")
	grid.begin_placement(source)
	_assert_candidates(grid, {match_one: {"kind": "merge", "result_rank": 2}}, "First-rank weapon excludes itself, other identities, other ranks and other item kinds")
	var before: String = _signature(state)
	var grid_before: String = JSON.stringify(grid.get("_snapshot"))
	var emitted_before: int = emitted.size()
	var focus_before: Control = root.gui_get_focus_owner()
	var expected: Array = _targets(grid)
	for iteration: int in 4:
		var copy: Array = _targets(grid)
		copy[0]["uid"] = -900
		copy[0]["kind"] = "wrong"
		copy[0]["result_rank"] = 99
		copy.append({"uid": 999})
		copy.clear()
	_check(_targets(grid) == expected and JSON.stringify(grid.get("_snapshot")) == grid_before,
		"Repeated query results and their dictionaries are detached from the grid's inventory snapshot")
	_check(_signature(state) == before and changed[0] == 0 and emitted.size() == emitted_before and root.gui_get_focus_owner() == focus_before,
		"Candidate queries preserve currency, UID allocation, RNG, inventory, errors, signals and focus")
	external["items"].clear()
	external["width"] = 1
	var item_copy: Dictionary = grid.snapshot_item(match_one)
	item_copy["rank"] = 3
	_check(_targets(grid) == expected and JSON.stringify(grid.get("_snapshot")) == grid_before,
		"Mutating caller-owned input and item snapshots cannot change candidate guidance")
	await _key(KEY_R)
	_check(grid.held_rotated and _targets(grid) == expected, "Real R rotation changes the ghost orientation without changing compatible targets")
	grid.interaction_enabled = false
	var cursor_before: Vector2i = grid.cursor
	await _key(KEY_RIGHT)
	_check(_targets(grid).is_empty() and grid.cursor == cursor_before, "Disabled interaction exposes no targets and ignores placement input")
	grid.interaction_enabled = true
	_check(_targets(grid) == expected, "Re-enabling the unchanged placement restores its compatible target set")
	grid.begin_placement(rank_two)
	_assert_candidates(grid, {match_two: {"kind": "merge", "result_rank": 3}}, "A second-rank weapon highlights only its same-rank merge partner")
	grid.begin_placement(rank_three)
	_check(_targets(grid).is_empty(), "A third-rank weapon cannot merge even when another identical third-rank box exists")
	grid.begin_placement(relic)
	_assert_candidates(grid, {relic_match: {"kind": "merge", "result_rank": 2}}, "Relics highlight only same-name same-rank relic boxes")
	var rune_expected: Dictionary = {}
	for weapon: Dictionary in state.loadout:
		rune_expected[int(weapon["uid"])] = {"kind": "rune", "result_rank": 1, "replacing": int(weapon["uid"]) == frost}
	rune_expected[rune_match] = {"kind": "merge", "result_rank": 2}
	grid.begin_placement(rune_one)
	_assert_candidates(grid, rune_expected, "A loose rune highlights all weapons and its matching loose rune, including occupied sockets")
	rune_expected.erase(rune_match)
	for uid: int in rune_expected:
		rune_expected[uid]["result_rank"] = 2
	grid.begin_placement(rune_two)
	_assert_candidates(grid, rune_expected, "Rune projections report the incoming rune's rank across first-, second- and third-rank weapons")
	var preview: Dictionary = grid.placement_at(_cell(state.backpack_item(frost)))
	_check(preview.get("kind") == "rune" and preview.get("replacing") == true and preview.get("result_rank") == 2
		and str(preview["error"]).contains("换符") and str(preview["error"]).contains(GameCatalog.rune("blast").display_name),
		"An occupied socket explicitly identifies swapping and the old rune returned to the bag")
	var plain_uid: int = int(state.loadout[0]["uid"])
	preview = grid.placement_at(_cell(state.backpack_item(plain_uid)))
	_check(preview.get("kind") == "rune" and not bool(preview.get("replacing")) and str(preview["error"]).contains("装入"),
		"An empty socket is described as an install rather than a replacement")
	await _settle()
	_check(grid._preview.mouse_filter == Control.MOUSE_FILTER_IGNORE and grid._preview.focus_mode == Control.FOCUS_NONE and grid._preview.clip_contents,
		"The clipped target/ghost layer cannot intercept pointer input or enter the focus chain")
	_check(root.gui_get_focus_owner() == grid, "Drawing candidate highlights leaves keyboard focus on the active grid")
	var bounds := Rect2(Vector2.ZERO, grid.custom_minimum_size)
	var enclosed: bool = true
	for row: Dictionary in _targets(grid):
		var item_rect: Rect2 = grid.call("_item_rect", grid.snapshot_item(int(row["uid"])))
		enclosed = enclosed and bounds.encloses(item_rect)
	_check(enclosed, "All highlighted target item rectangles lie inside the six-row grid")
	grid.cancel_placement()
	_check(_targets(grid).is_empty(), "Cancelling removes all stale action highlights")
	grid.held_uid = 999999
	_check(_targets(grid).is_empty(), "A missing held UID cannot expose stale snapshot candidates")
	grid.queue_free()
	await _settle()


func _test_keyboard_move_and_cancel() -> void:
	var state: RunState = _state()
	var uid: int = int(state.loadout[0]["uid"])
	var partner: int = _buy(state, "weapon", "bone")
	await _show(state)
	_pick_up(uid)
	var grid: BackpackGrid = _grid()
	_assert_candidates(grid, {partner: {"kind": "merge", "result_rank": 2}}, "Picking up a weapon exposes its merge partner before committing any operation")
	var button: Control = grid.find_child("BackpackItem%d" % uid, false, false)
	_check(button != null and button.modulate != Color.WHITE, "The held source remains in place with a dimmed visual treatment")
	var gold: int = state.gold
	var rng_state: int = state.rng.state
	await _key(KEY_R)
	for step: int in 3:
		await _key(KEY_DOWN)
	_check(grid.cursor == Vector2i(0, 3) and grid.held_rotated and root.gui_get_focus_owner() == grid,
		"Real R and arrow input remain available while targets and the ghost are visible")
	await _key(KEY_ENTER)
	await _settle()
	var placed: Dictionary = state.backpack_item(uid)
	_check(_cell(placed) == Vector2i(0, 3) and placed["rotated"] and state.gold == gold and state.rng.state == rng_state,
		"Enter moves the ghost's rotated footprint without spending money or RNG")
	_check(_grid().held_uid < 0 and _targets(_grid()).is_empty(), "Successful placement rebuilds the grid without stale target highlights")
	_pick_up(uid)
	await _key(KEY_R)
	var before: String = _signature(state)
	await _key(KEY_ENTER)
	_check(_signature(state) == before and _grid().held_uid == uid and str(_ui.find_child("BackpackHint", true, false).text).contains("超出"),
		"An out-of-bounds ghost keeps holding and provides its real rejection instead of moving inventory")
	await _key(KEY_ESCAPE)
	_check(_signature(state) == before and _grid().held_uid < 0 and _targets(_grid()).is_empty(), "Real Escape cancels an invalid placement without applying its ghost")
	button = _grid().find_child("BackpackItem%d" % uid, false, false)
	_check(button != null and button.modulate == Color.WHITE, "Cancelling restores the held source's normal modulation")


func _test_keyboard_edge_merge() -> void:
	var state: RunState = _state()
	var target: int = int(state.loadout[0]["uid"])
	_check(state.move_item(target, Vector2i(5, 0), false), "The merge fixture legally places its surviving target at the edge")
	var source: int = _buy(state, "weapon", "bone")
	await _show(state)
	_pick_up(source)
	await _key(KEY_R)
	await _navigate(Vector2i(5, 0))
	var grid: BackpackGrid = _grid()
	var preview: Dictionary = grid.placement_at(grid.cursor)
	_check(preview.get("valid") == true and preview.get("kind") == "merge" and preview.get("target") == target and preview.get("result_rank") == 2,
		"A highlighted edge target is actionable even when the rotated source footprint would extend past the grid")
	_check(str(preview["error"]).contains("合成") and str(preview["error"]).contains(GameCatalog.weapon("bone").display_name),
		"Merge guidance names the actual target weapon and action")
	var gold: int = state.gold
	await _key(KEY_ENTER)
	await _settle()
	var survivor: Dictionary = state.backpack_item(target)
	_check(state.backpack_item(source).is_empty() and int(survivor["rank"]) == 2 and _cell(survivor) == Vector2i(5, 0) and not bool(survivor["rotated"]) and state.gold == gold,
		"Real Enter merges into the advertised target while preserving its position, orientation and currency")
	_check(_targets(_grid()).is_empty(), "Completing a merge removes consumed-source highlights")


func _test_keyboard_rune_swap() -> void:
	var state: RunState = _state()
	var weapon: int = int(state.loadout[0]["uid"])
	var other: int = _buy(state, "weapon", "frost")
	var old_rune: int = _buy(state, "rune", "blast")
	_check(state.equip_rune(state.rune_index_for_uid(old_rune), 0), "The swap fixture installs an actual old rune before showing targets")
	var incoming: int = _ranked(state, "rune", "pierce", 2)
	var original_cell: Vector2i = _cell(state.backpack_item(incoming))
	await _show(state)
	_pick_up(incoming)
	_assert_candidates(_grid(), {weapon: {"kind": "rune", "result_rank": 2, "replacing": true}, other: {"kind": "rune", "result_rank": 2, "replacing": false}},
		"The real swap grid distinguishes occupied and empty weapon sockets")
	await _key(KEY_R)
	await _navigate(_cell(state.backpack_item(weapon)))
	_check(str(_ui.find_child("BackpackHint", true, false).text).contains("换符"), "Keyboard navigation refreshes the displayed swap action hint")
	var gold: int = state.gold
	var next_uid: int = int(state.backpack_snapshot()["next_uid"])
	var rng_state: int = state.rng.state
	await _key(KEY_ENTER)
	await _settle()
	var attached: Dictionary = state.backpack_item(weapon)["rune"]
	_check(int(attached["uid"]) == incoming and int(attached["rank"]) == 2 and state.rune_index_for_uid(incoming) < 0,
		"Real Enter attaches the advertised ranked rune rather than losing or duplicating it")
	_check(_cell(state.backpack_item(old_rune)) == original_cell and state.rune_index_for_uid(old_rune) >= 0,
		"The replaced rune returns to the incoming rune's real freed backpack cell")
	_check(state.gold == gold and int(state.backpack_snapshot()["next_uid"]) == next_uid and state.rng.state == rng_state and _targets(_grid()).is_empty(),
		"Free swapping preserves money, UID allocation and RNG and clears the completed preview")


func _assert_candidates(grid: BackpackGrid, expected: Dictionary, context: String) -> void:
	var result: Array = _targets(grid)
	var actual: Dictionary = {}
	for row: Dictionary in result:
		var values: Dictionary = {"kind": row.get("kind"), "result_rank": row.get("result_rank")}
		if row.has("replacing"):
			values["replacing"] = row["replacing"]
		actual[int(row.get("uid", -1))] = values
	_check(actual == expected and actual.size() == result.size(), context)


func _targets(grid: BackpackGrid) -> Array:
	return grid.call("placement_targets")


func _cell(item: Dictionary) -> Vector2i:
	return Vector2i(int(item.get("x", -1)), int(item.get("y", -1)))


func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.offers, state.rng.state, state.last_error, state._next_rune_uid])


func _show(state: RunState) -> void:
	state.generate_shop()
	_ui.bind(state)
	_ui.show_shop()
	await _settle()


func _grid() -> BackpackGrid:
	return _ui.find_child("BackpackGrid", true, false) as BackpackGrid


func _pick_up(uid: int) -> void:
	_ui._bp_select(uid, _ui._shop_epoch)
	_ui._bp_pick_up(uid)


func _navigate(destination: Vector2i) -> void:
	for step: int in 12:
		if _grid().cursor.x == destination.x:
			break
		await _key(KEY_RIGHT if _grid().cursor.x < destination.x else KEY_LEFT)
	for step: int in 12:
		if _grid().cursor.y == destination.y:
			break
		await _key(KEY_DOWN if _grid().cursor.y < destination.y else KEY_UP)
	_check(_grid().cursor == destination, "Real directional input reaches the advertised action target")


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, false)
		await process_frame


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _finish() -> void:
	print("BackpackTargets: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
