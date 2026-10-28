extends SceneTree
## Parsed device input updates hints before GUI handling and leaves real actions authoritative.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0
var _app: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _key_event(code: Key, down: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	return event

func _joy_event(button: JoyButton, down: bool = true, device: int = 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = down
	return event

func _axis_event(value: float, device: int = 0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	return event

func _key(code: Key) -> void:
	_send(_key_event(code))
	await process_frame
	_send(_key_event(code, false))
	await _settle()

func _joy(button: JoyButton, device: int = 0) -> void:
	_send(_joy_event(button, true, device))
	await process_frame
	_send(_joy_event(button, false, device))
	await _settle()

func _start() -> CombatSim:
	_app._begin_run("bone", 20261028)
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var focused: Control = root.gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	return sim

func _tick() -> void:
	_app.world._physics_process(STEP)

func _grid() -> BackpackGrid:
	return _app.ui.find_child("BackpackGrid", true, false) as BackpackGrid

func _hint() -> String:
	var label := _app.ui.find_child("BackpackHint", true, false) as Label
	return label.text if label != null else ""

func _node_ids(node: Node) -> Array[int]:
	var result: Array[int] = [node.get_instance_id()]
	for child: Node in node.get_children():
		result.append_array(_node_ids(child))
	return result

func _grid_state(grid: BackpackGrid) -> Array:
	var focused: Control = root.gui_get_focus_owner()
	return [_app.run.backpack_snapshot(), _app.run.loadout.duplicate(true), _app.run.gold, _app.run.rng.state,
		grid.held_uid, grid.held_rotated, grid.cursor, grid._grab_offset, grid._drop_target_cell,
		grid._native_dragging, grid.resonance_contacts(), _node_ids(grid), focused.get_instance_id() if focused != null else 0]

func _shop() -> void:
	var sim: CombatSim = _start()
	sim.sandbox = false
	sim.elapsed = sim.duration - STEP * 0.5
	_tick()
	await _settle()
	_app.run.gold = 1000
	_check(_app.screen == MAIN_SCRIPT.Screen.SHOP and not _app.world.active and _grid() != null, "A real wave completion reaches the actual shop for input-prompt checks")

func _buy(kind: String, id: String) -> int:
	var uid: int = int(_app.run.backpack_snapshot()["next_uid"])
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	_app.run.offers.assign([{"kind": kind, "id": id, "price": _app.run.shop_price(definition), "sold": false}])
	_check(_app.run.buy_offer(0), "The prompt fixture buys through the real inventory transaction: " + id)
	await _settle()
	return uid

func _pick_up(uid: int) -> void:
	_app.ui._bp_select(uid, _app.ui._shop_epoch)
	var move := _app.ui.find_child("MoveBackpackItem", true, false) as Button
	_check(move != null, "The selected real item exposes its existing pickup button")
	if move == null:
		return
	move.grab_focus()
	await _joy(JOY_BUTTON_A)
	_check(_grid().held_uid == uid and _app.ui.input_device_snapshot()["kind"] == "gamepad", "A is observed before the real pickup button consumes it and still picks the item up once")

func _move_to(target: Vector2i) -> void:
	if _grid() == null:
		_check(false, "Inventory navigation requires the real shop grid")
		return
	for step: int in 16:
		var current: Vector2i = _grid().cursor
		if current == target:
			return
		await _joy((JOY_BUTTON_DPAD_RIGHT if current.x < target.x else JOY_BUTTON_DPAD_LEFT) if current.x != target.x else (JOY_BUTTON_DPAD_DOWN if current.y < target.y else JOY_BUTTON_DPAD_UP))
	_check(false, "Real directional input reaches the requested inventory target")

func _gamepad_hint(text: String) -> bool:
	return text.contains("A") and text.contains("X") and text.contains("B") and not text.contains("Enter") and not text.contains("Esc") and not text.contains("R旋转")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	var controls: Dictionary = ControlBindings.defaults()
	controls["dash"] = KEY_E
	controls["pulse"] = KEY_R
	_app.ui.controls_changed.emit(controls)
	await _settle()
	_check(_app.ui.get_child(-1).name == "InputDeviceTracker", "The observer remains the UI's final child so it sees events before GUI and B handlers")
	await _test_skill_order_and_axes()
	await _test_pause_modal_and_disconnect()
	await _test_grid_switch_and_mouse_transaction()
	await _test_transaction_prompts()
	await _test_grid_purity_links_and_native_mode()
	await _test_signal_argument_snapshots()
	_send(_axis_event(0.0))
	_app._title()
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile), "Device-prompt integration never changes the personal profile")
	print("InputPromptsFlow: %d assertions, %d failures" % [_checks, _failures])
	_app._quit_game(0 if _failures == 0 else 1)

func _test_skill_order_and_axes() -> void:
	var sim: CombatSim = _start()
	_app.ui._input_device_tracker.reset()
	_send(_joy_event(JOY_BUTTON_A))
	_check(_app.ui.input_device_snapshot() == {"kind": "gamepad", "gamepad_id": 0} and _app.ui._hud["dash_label"].text == "冲刺 · A" and _app.ui._hud["pulse_label"].text == "脉冲 · X", "A updates both ready labels synchronously before the pending skill is consumed")
	_check(_app.world._dash_pending and sim.dashes_used == 0, "The hint observer neither consumes A nor executes the dash outside its physics step")
	_send(_joy_event(JOY_BUTTON_A, false))
	_send(_joy_event(JOY_BUTTON_X))
	_send(_joy_event(JOY_BUTTON_X, false))
	_tick()
	_check(sim.dashes_used == 1 and sim.pulses_used == 1, "The same observed A and X events activate each real skill exactly once")
	_check(_app.ui._hud["dash"].tooltip_text.begins_with("A：") and _app.ui._hud["pulse"].tooltip_text.begins_with("X："), "Gamepad labels and full tooltips share the active device")
	sim = _start()
	_send(_key_event(KEY_E))
	_check(_app.ui.input_device_snapshot()["kind"] == "keyboard" and _app.ui._hud["dash_label"].text == "冲刺 · E" and _app.ui._hud["pulse_label"].text == "脉冲 · R", "A real rebound E press restores the actual E and R labels in the same event")
	_send(_key_event(KEY_E, false))
	_send(_key_event(KEY_R))
	_send(_key_event(KEY_R, false))
	_tick()
	_check(sim.dashes_used == 1 and sim.pulses_used == 1, "Prompt switching preserves the actual rebound keyboard actions without double execution")
	_send(_axis_event(0.1))
	_check(_app.ui.input_device_snapshot()["kind"] == "keyboard", "Sub-deadzone controller drift cannot steal keyboard hints")
	_send(_axis_event(0.8))
	_check(_app.ui.input_device_snapshot()["kind"] == "gamepad", "A deliberate left-stick threshold edge switches the prompts")
	_send(_key_event(KEY_F6))
	_send(_key_event(KEY_F6, false))
	_send(_axis_event(0.9))
	_check(_app.ui.input_device_snapshot()["kind"] == "keyboard", "A continuously held stick cannot take hints back after fresh keyboard input")
	_send(_axis_event(0.0))
	_send(_axis_event(0.8))
	_check(_app.ui.input_device_snapshot()["kind"] == "gamepad", "Returning the stick to neutral allows a fresh deliberate device switch")
	_send(_axis_event(0.0))

func _test_pause_modal_and_disconnect() -> void:
	var sim: CombatSim = _start()
	await _joy(JOY_BUTTON_Y)
	await _joy(JOY_BUTTON_START)
	_check(paused and _app.paused and _app.ui.input_device_snapshot()["kind"] == "gamepad", "The real Start pause action is observed before its menu transition")
	var frozen: Array = [sim.dash_snapshot(), sim.pulse_snapshot(), sim.elapsed]
	_app.ui._show_settings(true)
	_app.ui._show_controls(true)
	await _settle()
	await _key(KEY_F6)
	_check(_app.ui.input_device_snapshot()["kind"] == "keyboard" and frozen == [sim.dash_snapshot(), sim.pulse_snapshot(), sim.elapsed], "Device hints can change in a paused controls modal without moving either skill clock")
	await _joy(JOY_BUTTON_B)
	_check(_app.ui.input_device_snapshot()["kind"] == "gamepad" and _app.ui._overlay_mode == "settings_pause" and paused, "B is observed even when the UI consumes it while returning one modal level")
	var focused: Control = root.gui_get_focus_owner()
	_check(focused != null and _app.ui._overlay.is_ancestor_of(focused), "Changing hints preserves focus inside the active modal")
	await _joy(JOY_BUTTON_B)
	await _joy(JOY_BUTTON_B)
	_check(not paused and not _app.paused and frozen == [sim.dash_snapshot(), sim.pulse_snapshot(), sim.elapsed], "Returning through pause resumes with the original ready skills and untouched clocks")
	await _joy(JOY_BUTTON_Y, 7)
	var ready: Array = [sim.dash_snapshot(), sim.pulse_snapshot()]
	Input.joy_connection_changed.emit(6, false)
	_check(paused and _app.ui.input_device_snapshot() == {"kind": "gamepad", "gamepad_id": 7}, "The existing any-device safety pause does not discard the still-selected other controller's hints")
	_app._resume()
	Input.joy_connection_changed.emit(7, false)
	_check(paused and _app.ui.input_device_snapshot() == {"kind": "keyboard", "gamepad_id": -1} and ready == [sim.dash_snapshot(), sim.pulse_snapshot()], "Disconnecting the selected pad falls back to keyboard hints without clearing available skills or resetting cooldowns")
	_check(_app.ui._hud["dash_label"].text == "冲刺 · E" and _app.ui._hud["pulse_label"].text == "脉冲 · R", "Disconnect fallback keeps the player's actual rebound keys while the game stays safely paused")
	_app._resume()
	await _joy(JOY_BUTTON_Y)
	_app.args = PackedStringArray()
	_app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(paused and _app.ui.input_device_snapshot()["kind"] == "gamepad" and ready == [sim.dash_snapshot(), sim.pulse_snapshot()], "Focus-loss pause preserves the last intentional device and all authoritative skill state")
	_app.args = PackedStringArray(["--autoplay"])
	_app._resume()

func _test_grid_switch_and_mouse_transaction() -> void:
	await _shop()
	if _grid() == null:
		return
	_app.ui._input_device_tracker.reset()
	var uid: int = int(_app.run.loadout[0]["uid"])
	await _pick_up(uid)
	_check(_gamepad_hint(_hint()), "The newly picked-up item immediately advertises A placement, X rotation and B cancellation")
	var grid: BackpackGrid = _grid()
	var holding: Array = []
	var hints: Array[String] = []
	grid.holding_changed.connect(func(item: int, rotated: bool, cell: Vector2i) -> void: holding.append([item, rotated, cell]))
	grid.hint_changed.connect(func(text: String) -> void: hints.append(text))
	var before: Array = _grid_state(grid)
	await _key(KEY_F6)
	_check(_grid_state(grid) == before and holding.is_empty() and hints.size() == 1, "A keyboard-only device switch updates one hint without rebuilding the grid, moving focus, changing holding state or touching inventory or RNG")
	_check(_hint().contains("Enter") and _hint().contains("R旋转") and _hint().contains("Esc取消"), "Keyboard placement retains its original instructions")
	await _joy(JOY_BUTTON_Y)
	_check(_grid_state(grid) == before and holding.is_empty() and _gamepad_hint(_hint()), "A harmless gamepad button changes only text and preserves the exact inventory and held geometry")
	var old_cursor: Vector2i = grid.cursor
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	_check(grid.cursor == old_cursor + Vector2i.RIGHT and holding.size() == 1 and _app.run.backpack_snapshot() == before[0], "The same observed directional press still moves a held preview exactly one cell without committing inventory")
	var moves: Array = []
	grid.move_requested.connect(func(item: int, cell: Vector2i, rotated: bool) -> void: moves.append([item, cell, rotated]))
	var gold: int = _app.run.gold
	var point: Vector2 = grid.global_position + Vector2(2.5, 0.5) * BackpackGrid.CELL
	var mouse := InputEventMouseButton.new()
	mouse.position = point
	mouse.global_position = point
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	_send(mouse)
	await process_frame
	mouse = InputEventMouseButton.new()
	mouse.position = point
	mouse.global_position = point
	mouse.button_index = MOUSE_BUTTON_LEFT
	_send(mouse)
	await _settle()
	var placed: Dictionary = _app.run.backpack_item(uid)
	var expected: Array = [[uid, Vector2i(2, 0), false]]
	_check(_app.ui.input_device_snapshot()["kind"] == "keyboard" and moves == expected, "A real mouse click switches the prompt first and still emits exactly one original placement transaction (device=%s, moves=%s, expected=%s, item=%s)" % [JSON.stringify(_app.ui.input_device_snapshot()), str(moves), str(expected), JSON.stringify(placed)])
	_check(int(placed["x"]) == 2 and int(placed["y"]) == 0 and _app.run.gold == gold and _grid().held_uid < 0, "Mouse placement preserves the paid economy and stable UID while changing only the requested cell")

func _test_transaction_prompts() -> void:
	await _shop()
	if _grid() == null:
		return
	var source: int = await _buy("weapon", "bone")
	var pierce: int = await _buy("rune", "pierce")
	var bounce: int = await _buy("rune", "bounce")
	var target: int = int(_app.run.loadout[0]["uid"])
	var target_item: Dictionary = _app.run.backpack_item(target)
	var cell := Vector2i(int(target_item["x"]), int(target_item["y"]))
	await _pick_up(source)
	await _move_to(cell)
	var inventory: Dictionary = _app.run.backpack_snapshot()
	_check(_hint().contains("A合成") and _gamepad_hint(_hint()), "A compatible real target advertises the existing merge transaction using the current pad controls")
	await _key(KEY_F6)
	_check(_hint().contains("松手或Enter合成") and _app.run.backpack_snapshot() == inventory, "Changing merge instructions preserves the target, UID and full transaction state")
	var merge_events: Array = []
	_grid().merge_requested.connect(func(source_uid: int, target_uid: int) -> void: merge_events.append([source_uid, target_uid]))
	await _joy(JOY_BUTTON_A)
	_check(_app.run.backpack_item(source).is_empty() and int(_app.run.backpack_item(target)["rank"]) == 2, "The observed A confirmation still performs one real weapon merge")
	_check(merge_events == [[source, target]], "A later merge listener receives the original source and target UIDs after the UI has canceled its held preview")
	await _pick_up(pierce)
	await _move_to(cell)
	_check(_hint().contains("A装入") and _gamepad_hint(_hint()), "A loose paid rune uses the correct current-device install wording")
	var rune_events: Array = []
	_grid().rune_requested.connect(func(source_uid: int, target_uid: int) -> void: rune_events.append([source_uid, target_uid]))
	await _joy(JOY_BUTTON_A)
	_check(_app.run.backpack_item(pierce).is_empty() and str(_app.run.backpack_item(target)["rune"].get("id", "")) == "pierce", "Device hints do not replace or duplicate the actual rune installation")
	_check(rune_events == [[pierce, target]], "A later install listener receives stable original UIDs after the real UI transaction cancels holding")
	await _pick_up(bounce)
	await _move_to(cell)
	_check(_hint().contains("A换符") and _hint().contains("退回") and _gamepad_hint(_hint()), "Replacing a real installed rune retains the return-to-backpack consequence in gamepad wording")
	var swap_events: Array = []
	_grid().rune_requested.connect(func(source_uid: int, target_uid: int) -> void: swap_events.append([source_uid, target_uid]))
	await _joy(JOY_BUTTON_A)
	_check(str(_app.run.backpack_item(target)["rune"].get("id", "")) == "bounce" and _app.run.rune_bag.size() == 1 and _app.run.rune_bag[0]["id"] == "pierce", "One observed A swap commits the chosen rune and returns the prior rune exactly once")
	_check(swap_events == [[bounce, target]], "A later swap listener retains the purchased source and target UIDs after synchronous cancellation")
	await _pick_up(target)
	await _move_to(Vector2i(0, 3))
	inventory = _app.run.backpack_snapshot()
	_check(_hint().contains("超出") and _hint().contains("X可旋转") and _hint().contains("B取消") and not _hint().contains("R可旋转"), "An invalid expanded footprint advertises pad rotation and cancellation instead of a false valid placement")
	await _joy(JOY_BUTTON_A)
	_check(_app.run.backpack_snapshot() == inventory and _grid().held_uid == target, "An observed A cannot turn invalid geometry into a successful transaction")
	await _key(KEY_F6)
	_check(_hint().contains("R可旋转") and _app.run.backpack_snapshot() == inventory, "Keyboard fallback preserves the original out-of-bounds reason and geometry")
	await _joy(JOY_BUTTON_B)
	_check(_grid().held_uid < 0 and _app.run.backpack_snapshot() == inventory, "B changes prompts before UI return handling but only cancels the held preview")

func _test_grid_purity_links_and_native_mode() -> void:
	var candle: int = await _buy("relic", "grave_candle")
	_check(_app.run.move_item(candle, Vector2i(0, 3), false), "The prompt fixture creates a real candle link through inventory placement")
	await _settle()
	var uid: int = int(_app.run.loadout[0]["uid"])
	var grid: BackpackGrid = _grid()
	if grid == null:
		_check(false, "The candle tooltip fixture requires the real shop grid")
		return
	var item := grid.find_child("BackpackItem%d" % uid, false, false) as Button
	if item == null:
		_check(false, "The linked inventory weapon must have its real item button before tooltip checks")
		return
	var badge: Node = item.find_child("CandleLink", false, false)
	_check(item != null and badge != null and item.tooltip_text.contains("烛引生效"), "The real linked weapon exposes its original candle badge and tactical tooltip")
	grid.begin_placement(uid)
	var before: Array = _grid_state(grid)
	var holding: Array = []
	grid.holding_changed.connect(func(item_uid: int, rotated: bool, at: Vector2i) -> void: holding.append([item_uid, rotated, at]))
	grid.set_input_device("keyboard")
	var keyboard: String = item.tooltip_text
	grid.set_input_device("gamepad")
	_check(item.tooltip_text.contains("A拿起") and item.tooltip_text.contains("X旋转") and item.tooltip_text.count("烛引生效") == 1 and item.find_child("CandleLink", false, false) == badge, "Gamepad tooltip updates retain the exact tactical candle addon and original badge instance")
	grid.set_input_device("invalid-device")
	_check(item.tooltip_text == keyboard and _grid_state(grid) == before and holding.is_empty(), "Invalid device kinds restore the exact keyboard tooltip without touching focus, holding, geometry, node identity, inventory or RNG")
	grid.cancel_placement()
	var hints: Array[String] = []
	grid.hint_changed.connect(func(text: String) -> void: hints.append(text))
	grid.set_input_device("gamepad")
	_check(hints.is_empty(), "A device switch with no held item emits no fabricated placement result")
	grid.begin_placement(uid)
	grid._native_dragging = true
	grid._drop_target_cell = grid.cursor
	var preview := Label.new()
	preview.text = grid._native_preview_text(grid.snapshot_item(uid))
	grid.add_child(preview)
	grid._native_preview_label = preview
	grid.set_input_device("keyboard")
	before = _grid_state(grid)
	grid.set_input_device("gamepad")
	var native_hint: String = str(grid.placement_at(grid.cursor)["error"])
	_check(native_hint.contains("松手") and not native_hint.contains("A放置") and not native_hint.contains("X旋转") and preview.text.contains("松手确认"), "The native-drag mode fixture keeps mouse-release instructions when pad hints become active")
	_check(_grid_state(grid) == before and grid._native_dragging, "Updating native-drag text preserves the exact mouse anchor, preview mode, focus and inventory")
	grid.set_input_device("keyboard")
	_check(preview.text.ends_with("R旋转") and str(grid.placement_at(grid.cursor)["error"]).contains("Enter"), "Returning to keyboard restores the original native-drag text")
	grid._native_dragging = false
	grid.cancel_placement()
	preview.queue_free()
	_app.ui._input_device_tracker.reset()
	await _settle()

func _test_signal_argument_snapshots() -> void:
	for mode: String in ["move", "merge", "rune"]:
		var state := RunState.new()
		state.begin(20261028, "bone")
		state.gold = 1000
		var target: int = int(state.loadout[0]["uid"])
		var source: int = target
		if mode != "move":
			var kind: String = "rune" if mode == "rune" else "weapon"
			var id: String = "pierce" if mode == "rune" else "bone"
			source = int(state.backpack_snapshot()["next_uid"])
			state.offers.assign([{"kind": kind, "id": id, "price": state.shop_price(BackpackInventory.definition(kind, id)), "sold": false}])
			_check(state.buy_offer(0), "The argument-stability fixture purchases its actual transaction source: " + mode)
		var grid := BackpackGrid.new()
		grid.configure(state.backpack_snapshot(), 1)
		root.add_child(grid)
		var first: Array = []
		var later: Array = []
		var gold: int = state.gold
		if mode == "move":
			grid.move_requested.connect(func(uid: int, cell: Vector2i, rotated: bool) -> void:
				first.append([uid, cell, rotated])
				_check(state.move_item(uid, cell, rotated), "The first movement listener performs the real inventory transaction")
				grid.cancel_placement()
				grid.cursor = Vector2i.ZERO
				grid.held_rotated = false)
			grid.move_requested.connect(func(uid: int, cell: Vector2i, rotated: bool) -> void: later.append([uid, cell, rotated]))
			grid.begin_placement(source, true, Vector2i(2, 3))
			grid.commit_placement()
			var expected: Array = [[source, Vector2i(2, 3), true]]
			_check(first == expected and later == expected, "Movement arguments remain identical for later listeners even when the first cancels and changes held cursor and rotation")
			var item: Dictionary = state.backpack_item(source)
			_check(int(item["x"]) == 2 and int(item["y"]) == 3 and bool(item["rotated"]), "The stable movement signal preserves the actual requested inventory footprint")
		elif mode == "merge":
			grid.merge_requested.connect(func(source_uid: int, target_uid: int) -> void:
				first.append([source_uid, target_uid])
				_check(state.merge_items(source_uid, target_uid), "The first merge listener performs the real inventory transaction")
				grid.cancel_placement()
				grid.cursor = Vector2i(5, 3)
				grid.held_rotated = true)
			grid.merge_requested.connect(func(source_uid: int, target_uid: int) -> void: later.append([source_uid, target_uid]))
			grid.begin_placement(source, false, Vector2i.ZERO)
			grid.commit_placement()
			_check(first == [[source, target]] and later == first, "Both merge UIDs stay identical across a first listener that cancels holding")
			_check(state.backpack_item(source).is_empty() and int(state.backpack_item(target)["rank"]) == 2, "The original merge still promotes exactly its intended target")
		else:
			grid.rune_requested.connect(func(source_uid: int, target_uid: int) -> void:
				first.append([source_uid, target_uid])
				_check(state.equip_rune(state.rune_index_for_uid(source_uid), state.weapon_index_for_uid(target_uid)), "The first rune listener performs the real inventory transaction")
				grid.cancel_placement()
				grid.cursor = Vector2i(5, 3)
				grid.held_rotated = true)
			grid.rune_requested.connect(func(source_uid: int, target_uid: int) -> void: later.append([source_uid, target_uid]))
			grid.begin_placement(source, false, Vector2i.ZERO)
			grid.commit_placement()
			_check(first == [[source, target]] and later == first, "Both rune UIDs remain stable after the first listener cancels and changes held geometry")
			_check(state.backpack_item(source).is_empty() and str(state.backpack_item(target)["rune"].get("id", "")) == "pierce", "The stable rune signal installs exactly its original purchased source")
		_check(state.gold == gold and grid.held_uid < 0, "Signal snapshots neither duplicate transactions nor change currency: " + mode)
		grid.queue_free()
		await _settle()
