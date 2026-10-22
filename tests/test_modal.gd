extends SceneTree
## Real keyboard events exercise modal isolation without Main, persistence or combat.

var _checks: int = 0
var _failures: int = 0
var _starts: int = 0
var _next_waves: int = 0

func _initialize() -> void:
	_test.call_deferred()

func _test() -> void:
	root.size = Vector2i(1280, 720)
	var state := RunState.new()
	state.begin(20261022, "bone")
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.start_requested.connect(func(_starter: String) -> void: _starts += 1)
	ui.next_wave_requested.connect(func() -> void: _next_waves += 1)
	await _test_title_settings(ui)
	await _test_shop_pause(ui, state)
	await _test_upgrade_race(ui, state)
	await _test_screen_replacement(ui)
	paused = false
	ui.queue_free()
	await process_frame
	print("Modal: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _test_title_settings(ui: GameUI) -> void:
	ui.show_title({})
	await _settle()
	var source: Button = _find_button(ui._page, "设置")
	_check(source != null, "Title exposes a settings source button")
	if source == null:
		return
	source.grab_focus()
	_key(KEY_ENTER)
	await _settle()
	_check(ui._overlay_mode == "settings_title", "Real Return opens settings from the title source")
	_check(ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED, "Title descendants cannot acquire focus behind settings")
	_check(_overlay_owns_focus(ui), "The settings modal receives initial keyboard focus")
	var count: int = _button_count(ui._page) + _button_count(ui._overlay) + 2
	_check(await _tabs_stay_in_overlay(ui, count, false), "Forward Tab wraps inside title settings instead of entering the page")
	_check(await _tabs_stay_in_overlay(ui, count, true), "Shift+Tab also wraps inside title settings")
	var back: Button = _find_button(ui._overlay, "返回")
	if back != null:
		back.grab_focus()
		_key(KEY_ENTER)
	await _settle()
	_check(ui._overlay_mode.is_empty() and ui._overlay.get_child_count() == 0, "Real Return closes title settings")
	_check(root.gui_get_focus_owner() == source, "Closing title settings restores the exact settings source button")
	_check(ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_INHERITED and _starts == 0, "Closing settings restores page navigation without starting a run")

func _test_shop_pause(ui: GameUI, state: RunState) -> void:
	state.begin(20261022, "bone")
	state.gold = 1000
	state.offers = [
		{"id": "frost", "kind": "weapon", "price": 24, "sold": false},
		{"id": "pierce", "kind": "rune", "price": 18, "sold": false},
		{"id": "damage", "kind": "relic", "price": 25, "sold": false},
		{"id": "blast", "kind": "rune", "price": 22, "sold": false},
	]
	ui.show_shop()
	await _settle()
	var source: Button = _find_shop_button(ui._page, "buy:2")
	_check(source != null and not source.disabled, "The shop fixture has an actionable buy:2 source")
	if source == null:
		return
	source.grab_focus()
	_check(_focus_id() == "buy:2", "The nondefault shop source owns focus before pausing")
	var before: Dictionary = state.summary()
	var offers_before: Array = state.offers.duplicate(true)
	ui.show_pause()
	paused = true
	await _settle()
	_check(paused and ui._overlay_mode == "pause" and _overlay_owns_focus(ui), "The real paused tree leaves keyboard focus inside the pause modal")
	_check(ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED, "Shop buttons cannot focus beneath the pause modal")
	var count: int = _button_count(ui._page) + _button_count(ui._overlay) + 2
	_check(await _tabs_stay_in_overlay(ui, count, false), "Forward Tab stays modal beyond the complete underlying button count")
	_check(await _tabs_stay_in_overlay(ui, count, true), "Reverse Tab stays modal beyond the complete underlying button count")
	_check(state.summary() == before and state.offers == offers_before and _next_waves == 0, "Pause navigation neither buys hidden offers nor starts the next wave")
	var settings: Button = _find_button(ui._overlay, "设置")
	if settings != null:
		settings.grab_focus()
		_key(KEY_ENTER)
	await _settle()
	_check(ui._overlay_mode == "settings_pause" and _overlay_owns_focus(ui), "Real Return opens settings within the paused modal stack")
	_check(ui.handle_back(), "Back is consumed by pause settings")
	await _settle()
	_check(paused and ui._overlay_mode == "pause", "Leaving pause settings preserves the paused tree")
	settings = _find_button(ui._overlay, "设置")
	_check(settings != null and root.gui_get_focus_owner() == settings, "Settings back restores focus to the new pause settings button")
	_check(not ui.handle_back(), "Plain pause leaves Back handling to the application")
	_check(paused and ui._overlay_mode == "pause", "Plain pause Back does not silently resume the tree")
	ui.hide_pause()
	paused = false
	await _settle()
	_check(ui._overlay_mode.is_empty() and ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_INHERITED, "Hiding pause releases recursive page focus gating")
	_check(_focus_id() == "buy:2", "Resuming returns to the original nondefault shop action")
	_check(state.summary() == before and state.offers == offers_before and _next_waves == 0, "Entering and leaving pause settings performs no hidden shop action")

func _test_upgrade_race(ui: GameUI, state: RunState) -> void:
	state.begin(20261022, "bone")
	state.pending_upgrades = 2
	ui.show_upgrades()
	await _settle()
	var source: Control = root.gui_get_focus_owner()
	_check(source is Button and source.text == "选择强化", "An upgrade choice receives initial keyboard focus")
	if not source is Button:
		return
	var source_id: int = source.get_instance_id()
	_key(KEY_ENTER)
	_check(state.pending_upgrades == 1, "Real Return accepts exactly one upgrade before deferred refresh")
	# Reproduce the original ordering: queued page rebuild, then modal focus, then
	# the rebuilt page's delayed focus request, all within the same input frame.
	ui.show_pause()
	paused = true
	await _settle()
	_check(ui._screen == "upgrades" and ui._overlay_mode == "pause" and state.pending_upgrades == 1, "Upgrade refresh does not dismiss the active pause modal")
	var owner: Control = root.gui_get_focus_owner()
	_check(_overlay_owns_focus(ui) and owner is Button and owner.text == "继续试炼", "A rebuilt upgrade page cannot steal the pause resume focus")
	_check(ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED, "The rebuilt upgrade controls remain recursively gated")
	ui.hide_pause()
	paused = false
	await _settle()
	owner = root.gui_get_focus_owner()
	_check(owner is Button and owner.text == "选择强化" and ui._page.is_ancestor_of(owner), "Resuming chooses a usable replacement upgrade button")
	_check(owner != null and owner.get_instance_id() != source_id, "Upgrade focus restoration does not target the removed button")
	_check(state.pending_upgrades == 1, "Pausing and restoring focus do not consume the second upgrade")

func _test_screen_replacement(ui: GameUI) -> void:
	var outgoing: Control = root.gui_get_focus_owner()
	if outgoing != null:
		ui._focus_later(outgoing)
	ui.show_pause()
	ui.show_title({})
	await _settle()
	_check(ui._screen == "title" and ui._overlay_mode.is_empty() and ui._overlay.get_child_count() == 0, "Replacing the screen clears the modal stack")
	_check(ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_INHERITED, "A new screen never inherits disabled page focus")
	var owner: Control = root.gui_get_focus_owner()
	_check(owner is Button and owner.text == "进入试炼" and ui._page.is_ancestor_of(owner), "Stale page and modal focus requests cannot override the new screen's entry focus")
	_key(KEY_ENTER)
	await _settle()
	_check(_starts == 1 and _next_waves == 0, "The restored title receives real Return instead of a stale underlying action")

func _key(keycode: Key, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.shift_pressed = shift
		event.pressed = pressed
		root.push_input(event, false)

func _tabs_stay_in_overlay(ui: GameUI, count: int, backwards: bool) -> bool:
	var contained: bool = true
	for step: int in count:
		_key(KEY_TAB, backwards)
		await process_frame
		contained = contained and _overlay_owns_focus(ui)
	return contained

func _overlay_owns_focus(ui: GameUI) -> bool:
	var owner: Control = root.gui_get_focus_owner()
	return owner != null and ui._overlay.is_ancestor_of(owner) and not ui._page.is_ancestor_of(owner)

func _focus_id() -> String:
	var owner: Control = root.gui_get_focus_owner()
	return "" if owner == null else str(owner.get_meta("shop_focus_id", ""))

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null

func _find_shop_button(node: Node, focus_id: String) -> Button:
	if node is Button and str(node.get_meta("shop_focus_id", "")) == focus_id:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_shop_button(child, focus_id)
		if found != null:
			return found
	return null

func _button_count(node: Node) -> int:
	var count: int = 1 if node is BaseButton else 0
	for child: Node in node.get_children():
		count += _button_count(child)
	return count

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
