extends SceneTree
## Parsed joypad events manipulate real paid inventory through the shop UI.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

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

func _button(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	Input.parse_input_event(event)
	await _settle()

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await process_frame

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone")
	state.gold = 10000
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	_check(state.buy_offer(0), "The gamepad fixture pays the real inventory purchase price for " + id)
	return uid

func _show(state: RunState) -> void:
	state.generate_shop()
	_ui.bind(state)
	_ui.show_shop()
	await _settle()

func _grid() -> BackpackGrid:
	return _ui.find_child("BackpackGrid", true, false) as BackpackGrid

func _pick_up(uid: int) -> void:
	_ui._bp_select(uid, _ui._shop_epoch)
	var move := _ui.find_child("MoveBackpackItem", true, false) as Button
	_check(move != null, "The actual selected inventory item exposes its move button")
	if move == null:
		return
	move.grab_focus()
	await _button(JOY_BUTTON_A)
	_check(_grid().held_uid == uid and root.gui_get_focus_owner() == _grid(), "Gamepad A activates the real focused move button and transfers focus to the held-item grid")

func _move_to(target: Vector2i) -> void:
	for step: int in 16:
		var current: Vector2i = _grid().cursor
		if current == target:
			return
		if current.x != target.x:
			await _button(JOY_BUTTON_DPAD_RIGHT if current.x < target.x else JOY_BUTTON_DPAD_LEFT)
		elif current.y != target.y:
			await _button(JOY_BUTTON_DPAD_DOWN if current.y < target.y else JOY_BUTTON_DPAD_UP)
	_check(false, "The real pad must be able to reach the requested in-bounds inventory cell")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	ControlBindings.ensure_installed()
	_ui = GameUI.new()
	root.add_child(_ui)
	await _test_placement_and_cancel()
	await _test_axis_edges()
	await _test_modal_and_disabled_grid()
	await _test_merge_and_rune()
	await _axis(JOY_AXIS_LEFT_X, 0.0)
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	print("GamepadBackpack: %d assertions, %d failures" % [_checks, _failures])
	_ui.queue_free()
	for frame: int in 3:
		await process_frame
	quit(0 if _failures == 0 else 1)

func _test_placement_and_cancel() -> void:
	var state: RunState = _state()
	_buy(state, "weapon", "frost")
	await _show(state)
	var uid: int = int(state.loadout[0]["uid"])
	var gold: int = state.gold
	await _pick_up(uid)
	await _button(JOY_BUTTON_X)
	_check(_grid().held_rotated, "Gamepad X rotates the held three-cell weapon without activating a combat skill")
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _button(JOY_BUTTON_DPAD_DOWN)
	_check(_grid().cursor == Vector2i(0, 3), "Each directional-pad press advances the held item exactly one cell")
	await _button(JOY_BUTTON_A)
	var placed: Dictionary = state.backpack_item(uid)
	_check(int(placed["x"]) == 0 and int(placed["y"]) == 3 and bool(placed["rotated"]) and _grid().held_uid < 0, "A commits the rotated weapon through the actual inventory transaction")
	_check(state.gold == gold and int(state.loadout[0]["uid"]) == uid, "Manual gamepad placement preserves currency and the combat projection's stable weapon identity")
	await _pick_up(uid)
	var inventory: Dictionary = state.backpack_snapshot()
	await _button(JOY_BUTTON_X)
	await _button(JOY_BUTTON_A)
	_check(state.backpack_snapshot() == inventory and _grid().held_uid == uid, "An out-of-bounds rotated placement stays held and cannot mutate inventory")
	var hint := _ui.find_child("BackpackHint", true, false) as Label
	_check(hint != null and hint.text.contains("超出"), "Invalid gamepad placement exposes the existing transaction error")
	await _button(JOY_BUTTON_B)
	_check(_grid().held_uid < 0 and state.backpack_snapshot() == inventory, "B cancels the held placement while keeping the original item and paid inventory unchanged")

func _test_axis_edges() -> void:
	var state: RunState = _ui.run
	var uid: int = int(state.loadout[0]["uid"])
	await _pick_up(uid)
	var inventory: Dictionary = state.backpack_snapshot()
	await _axis(JOY_AXIS_LEFT_Y, -0.1)
	_check(_grid().cursor == Vector2i(0, 3), "Small held-item stick drift cannot move the placement cursor")
	await _axis(JOY_AXIS_LEFT_Y, -0.9)
	_check(_grid().cursor == Vector2i(0, 2), "Crossing the stick threshold advances the held item one cell")
	await _axis(JOY_AXIS_LEFT_Y, -1.0)
	await _axis(JOY_AXIS_LEFT_Y, -0.4)
	_check(_grid().cursor == Vector2i(0, 2), "Same-direction stick motion and threshold jitter cannot repeat movement")
	await _axis(JOY_AXIS_LEFT_Y, -0.1)
	await _axis(JOY_AXIS_LEFT_Y, -0.6)
	_check(_grid().cursor == Vector2i(0, 1), "Returning to neutral permits a fresh deliberate same-direction stick step")
	await _axis(JOY_AXIS_LEFT_X, 0.9)
	await _axis(JOY_AXIS_LEFT_X, 0.8)
	_check(_grid().cursor == Vector2i(1, 1), "The horizontal stick has an independent one-step edge latch")
	await _axis(JOY_AXIS_LEFT_X, -0.9)
	_check(_grid().cursor == Vector2i(0, 1), "A deliberate opposite stick direction produces one corresponding cell step")
	await _button(JOY_BUTTON_DPAD_LEFT)
	_check(_grid().cursor.x == 0, "Pad cursor movement remains clamped at the real unlocked grid boundary")
	await _button(JOY_BUTTON_B)
	_check(_grid().held_uid < 0 and state.backpack_snapshot() == inventory, "Analog preview movement and cancellation never mutate the inventory model")
	await _axis(JOY_AXIS_LEFT_X, 0.0)
	await _axis(JOY_AXIS_LEFT_Y, 0.0)

func _test_modal_and_disabled_grid() -> void:
	var state: RunState = _ui.run
	var uid: int = int(state.loadout[0]["uid"])
	await _pick_up(uid)
	var inventory: Dictionary = state.backpack_snapshot()
	_ui._show_settings(false)
	await _settle()
	var grid: BackpackGrid = _grid()
	var cursor: Vector2i = grid.cursor
	_check(grid.held_uid < 0 and not grid.interaction_enabled, "Opening an actual settings modal cancels held placement and disables the underlying grid")
	await _button(JOY_BUTTON_X)
	await _button(JOY_BUTTON_DPAD_RIGHT)
	await _axis(JOY_AXIS_LEFT_X, 0.9)
	_check(grid.cursor == cursor and state.backpack_snapshot() == inventory and grid.held_uid < 0, "Modal gamepad input cannot rotate, move or commit an underlying inventory item")
	var focused: Control = root.gui_get_focus_owner()
	_check(focused == null or _ui._overlay.is_ancestor_of(focused), "Settings retain keyboard and gamepad focus inside the real modal")
	_check(_ui.handle_back(), "The real overlay stack can return from settings")
	await _axis(JOY_AXIS_LEFT_X, 0.0)
	await _settle()
	await _pick_up(uid)
	grid = _grid()
	cursor = grid.cursor
	var rotated: bool = grid.held_rotated
	grid.interaction_enabled = false
	for button: JoyButton in [JOY_BUTTON_X, JOY_BUTTON_A, JOY_BUTTON_DPAD_UP]:
		await _button(button)
	_check(grid.cursor == cursor and grid.held_rotated == rotated and grid.held_uid == uid and state.backpack_snapshot() == inventory, "Disabled held-item movement, rotation and placement respect the existing interaction-enabled transaction gate")
	await _button(JOY_BUTTON_B)
	_check(grid.held_uid < 0 and state.backpack_snapshot() == inventory, "The global B return action may cancel a disabled preview without mutating its original inventory")
	grid.interaction_enabled = true
	grid.cancel_placement()

func _test_merge_and_rune() -> void:
	var state: RunState = _state()
	var source: int = _buy(state, "weapon", "bone")
	var rune: int = _buy(state, "rune", "pierce")
	await _show(state)
	var target: int = int(state.loadout[0]["uid"])
	var target_item: Dictionary = state.backpack_item(target)
	var target_cell := Vector2i(int(target_item["x"]), int(target_item["y"]))
	var gold: int = state.gold
	await _pick_up(source)
	await _move_to(target_cell)
	await _button(JOY_BUTTON_A)
	_check(state.backpack_item(source).is_empty() and int(state.backpack_item(target)["rank"]) == 2 and state.loadout.size() == 1, "A over a compatible real weapon performs the existing paid-item merge transaction")
	_check(state.gold == gold, "Gamepad merging adds no currency charge or reward")
	await _pick_up(rune)
	await _move_to(target_cell)
	await _button(JOY_BUTTON_A)
	_check(state.backpack_item(rune).is_empty() and str(state.backpack_item(target)["rune"].get("id", "")) == "pierce", "A over the real weapon installs the held purchased rune through the existing transaction")
	_check(state.gold == gold and str(state.loadout[0]["rune"].get("id", "")) == "pierce" and _grid().held_uid < 0, "Gamepad rune installation updates the combat projection and leaves no stale held item")
