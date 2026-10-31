extends SceneTree
## Controlled input ordering and stale signals, not claims of natural human OS timing.

const MAIN: PackedScene = preload("res://scenes/main.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.size = Vector2i(1280, 720)
	await _test_same_frame_upgrade_returns()
	await _test_reopened_upgrade_page()
	await _test_upgrade_after_screen_change()
	await _test_upgrade_under_overlay()
	await _test_old_controls_after_restart()
	await _test_starter_refresh_preserves_settings()
	await _test_saved_character_is_visible_without_focus_theft()
	paused = false
	print("ChoiceActions: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _state(seed_value: int = 2) -> RunState:
	var state := RunState.new()
	state.begin(seed_value, "bone")
	state.collect_souls(102)
	return state


func _new_upgrade_ui(state: RunState) -> GameUI:
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_upgrades()
	await _settle()
	_check(state.pending_upgrades == 2, "The fixture earns exactly two pending upgrades through the real XP API")
	return ui


func _test_same_frame_upgrade_returns() -> void:
	var state: RunState = _state()
	var ui: GameUI = await _new_upgrade_ui(state)
	var completions: Array[int] = [0]
	ui.upgrades_finished.connect(func() -> void: completions[0] += 1)
	var choices: Array[Dictionary] = state.upgrade_choices()
	var old_id: String = str(choices[0]["id"])
	var oracle: RunState = _state()
	oracle.upgrade_choices()
	_check(oracle.choose_upgrade(old_id), "The first displayed choice is legal in the independent state fixture")
	var next_choices: Array[Dictionary] = oracle.upgrade_choices()
	var repeats: bool = false
	for choice: Dictionary in next_choices:
		repeats = repeats or str(choice["id"]) == old_id
	_check(old_id == "armor" and repeats, "Seed two repeats the old armor ID in the next unseen set, so core ID validation alone cannot prevent the bug")
	var first: Button = _find_button(ui._page, "选择强化")
	_check(first != null and root.gui_get_focus_owner() == first, "The displayed first choice owns real keyboard focus")
	if first == null:
		await _dispose(ui)
		return
	_key(KEY_ENTER)
	_check(state.pending_upgrades == 1, "The first real Return consumes exactly one displayed upgrade")
	var after_first: Dictionary = _snapshot(state, ui)
	_key(KEY_ENTER)
	_check(state.pending_upgrades == 1, "A second Return before rebuilding cannot consume an unseen upgrade")
	_check(_snapshot(state, ui) == after_first, "Rejected duplicate input leaves bonuses, options, RNG, errors and queued state untouched")
	await _settle()
	_check(state.upgrade_choices() == next_choices and state.rng.state == oracle.rng.state, "The next visible choices and RNG match one ordinary selection")
	var current: Button = _find_button(ui._page, "选择强化")
	_check(current != null, "The rebuilt page still presents the remaining choice")
	if current != null:
		current.grab_focus()
		_key(KEY_ENTER)
	_check(state.pending_upgrades == 0, "The newly displayed page accepts its own real Return normally")
	var after_last: Dictionary = _snapshot(state, ui)
	_key(KEY_ENTER)
	_check(_snapshot(state, ui) == after_last, "Repeated input after the last choice cannot add a spurious no-upgrades error")
	await _settle()
	_check(completions[0] == 1, "Completing two displayed choices emits one transition")
	await _dispose(ui)


func _test_reopened_upgrade_page() -> void:
	var state: RunState = _state()
	var ui: GameUI = await _new_upgrade_ui(state)
	var old: Button = _find_button(ui._page, "选择强化")
	ui.show_upgrades()
	_check(is_instance_valid(old) and not old.is_inside_tree(), "The reopened-page fixture retains an old detached button before deferred deletion")
	var before: Dictionary = _snapshot(state, ui)
	_emit(old)
	_check(_snapshot(state, ui) == before, "A prior page's live old signal cannot apply its still-valid choice ID")
	await _settle()
	var current: Button = _find_button(ui._page, "选择强化")
	_check(current != null, "Reopening leaves a usable current upgrade button")
	if current != null:
		current.grab_focus()
		_key(KEY_ENTER)
		_check(state.pending_upgrades == 1, "The new page remains actionable after rejecting its old generation")
	await _dispose(ui)


func _test_upgrade_after_screen_change() -> void:
	var state: RunState = _state()
	var ui: GameUI = await _new_upgrade_ui(state)
	var old: Button = _find_button(ui._page, "选择强化")
	ui.show_title({})
	var before: Dictionary = _snapshot(state, ui)
	_emit(old)
	_check(_snapshot(state, ui) == before, "An old upgrade cannot mutate a run after returning to the title")
	await _settle()
	_check(ui._screen == "title" and _find_button(ui._page, "进入试炼") != null, "Rejecting a cross-screen signal preserves the title and its start action")
	await _dispose(ui)


func _test_upgrade_under_overlay() -> void:
	for mode: String in ["pause", "settings"]:
		var state: RunState = _state()
		var ui: GameUI = await _new_upgrade_ui(state)
		var old: Button = _find_button(ui._page, "选择强化")
		ui.show_pause()
		paused = true
		if mode == "settings":
			ui._show_settings(true)
		var before: Dictionary = _snapshot(state, ui)
		_emit(old)
		_check(_snapshot(state, ui) == before, "A controlled old upgrade signal cannot consume choices beneath " + mode)
		await _settle()
		_check(state.pending_upgrades == 2 and _overlay_owns_focus(ui), "The modal keeps its input focus and both unconsumed choices: " + mode)
		ui.hide_pause()
		paused = false
		await _settle()
		var current: Button = _find_button(ui._page, "选择强化")
		_check(current != null, "Closing the modal restores an available upgrade choice: " + mode)
		if current != null:
			current.grab_focus()
			_key(KEY_ENTER)
			_check(state.pending_upgrades == 1, "Closing the modal does not permanently disable normal upgrade input: " + mode)
		await _dispose(ui)


func _test_old_controls_after_restart() -> void:
	var state: RunState = _state()
	var ui: GameUI = await _new_upgrade_ui(state)
	var old_upgrade: Button = _find_button(ui._page, "选择强化")
	var starts: Array[int] = [0]
	ui.start_requested.connect(func(starter: String) -> void:
		starts[0] += 1
		state.begin(991, starter)
		ui.show_hud())
	ui.show_title({})
	var old_start: Button = _find_button(ui._page, "进入试炼")
	_check(old_start != null, "The restart fixture has a current title start action")
	if old_start == null:
		await _dispose(ui)
		return
	old_start.grab_focus()
	_key(KEY_ENTER)
	_check(starts[0] == 1 and ui._screen == "hud" and state.pending_upgrades == 0, "The fresh title accepts Return and starts one clean run")
	var after_start: Dictionary = _snapshot(state, ui)
	_emit(old_upgrade)
	_check(_snapshot(state, ui) == after_start, "An abandoned upgrade callback cannot inject an error or bonus into the new run")
	_emit(old_start)
	_check(starts[0] == 1 and _snapshot(state, ui) == after_start, "An old start callback cannot restart the newly active run a second time")
	await _settle()
	_check(ui._screen == "hud" and not ui._toast.visible, "Rejected old controls do not display stale upgrade feedback over the new HUD")
	await _dispose(ui)


func _test_starter_refresh_preserves_settings() -> void:
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(_state())
	ui.show_title({})
	await _settle()
	var ember := ui._page.find_child("Character_clarisse", true, false) as Button
	_check(ember != null, "The title offers the actual Clarisse character choice")
	if ember == null:
		await _dispose(ui)
		return
	ember.grab_focus()
	_key(KEY_ENTER)
	var source: Button = _find_button(ui._page, "设置")
	# Do not yield: the selected-character refresh must remain queued until Return.
	var visited: Array[Control] = []
	while source != null and root.gui_get_focus_owner() != source:
		var current: Control = root.gui_get_focus_owner()
		if current == null or current in visited:
			break
		visited.append(current)
		_key(KEY_TAB)
	_check(source != null and root.gui_get_focus_owner() == source, "Real Tab navigation reaches settings before the queued starter refresh")
	_check(visited.all(func(control: Control) -> bool: return control is Button and ui._page.is_ancestor_of(control)), "Title Tab traversal visits actionable choices rather than scroll containers or scrollbar-only stops")
	_key(KEY_ENTER)
	_check(ui._overlay_mode == "settings_title", "Real Return opens settings before the queued title refresh executes")
	await _settle()
	_check(ui._overlay_mode == "settings_title" and ui._overlay.get_child_count() > 0, "A queued starter update cannot silently close newly opened settings")
	_check(_overlay_owns_focus(ui) and ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED, "Settings retain modal keyboard focus through the delayed starter update")
	_check(ui.handle_back(), "The preserved settings layer still consumes Back normally")
	await _settle()
	ember = ui._page.find_child("Character_clarisse", true, false) as Button
	var bone := ui._page.find_child("Character_alk", true, false) as Button
	_check(ui._overlay_mode.is_empty() and ui.selected_hero() == "clarisse" and ui._starter == "ember" and ember != null and ember.button_pressed and bone != null and not bone.button_pressed, "Closing settings reveals the selected character and weapon with coherent toggle states")
	var owner: Control = root.gui_get_focus_owner()
	_check(owner is Button and owner.text == "设置", "Closing settings after a starter update restores its settings source focus")
	await _dispose(ui)


func _test_saved_character_is_visible_without_focus_theft() -> void:
	var temporary: DirAccess = DirAccess.create_temp("broxy-title-character", true)
	_check(temporary != null, "The saved-character title fixture uses an isolated temporary profile")
	if temporary == null:
		return
	var directory: String = temporary.get_current_dir()
	temporary = null
	var path: String = directory.path_join("profile.cfg")
	var saved := ConfigFile.new()
	saved.set_value("progress", "hero", "falsche")
	_check(saved.save(path) == OK, "The isolated startup fixture genuinely saves the last-row character")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var app = MAIN.instantiate()
	app.store = GameStore.new(path)
	root.add_child(app)
	app.set_process(false)
	app.world.set_physics_process(false)
	await _settle()
	var ui: GameUI = app.ui
	var scroll := ui.find_child("CharacterScroll", true, false) as ScrollContainer
	var selected := ui.find_child("Character_falsche", true, false) as Button
	var start := ui.find_child("StartTrial", true, false) as Button
	_check(app.store.selected_hero == "falsche" and ui.selected_hero() == "falsche" and selected != null and selected.button_pressed, "The actual Main startup loads the persisted canonical character")
	_check(scroll != null and selected != null and scroll.get_global_rect().grow(0.1).encloses(selected.get_global_rect()) and scroll.scroll_vertical > 0, "A persisted last-row selection is automatically scrolled fully into view")
	_check(start != null and root.gui_get_focus_owner() == start, "Revealing a persisted character preserves the real initial Start focus")
	if scroll != null:
		_check(scroll.focus_mode == Control.FOCUS_NONE and scroll.get_v_scroll_bar().focus_mode == Control.FOCUS_NONE, "The character viewport contributes no inert Tab stop")
	ui.show_hud()
	app._title()
	await _settle()
	scroll = ui.find_child("CharacterScroll", true, false) as ScrollContainer
	selected = ui.find_child("Character_falsche", true, false) as Button
	start = ui.find_child("StartTrial", true, false) as Button
	_check(scroll != null and selected != null and scroll.get_global_rect().grow(0.1).encloses(selected.get_global_rect()) and root.gui_get_focus_owner() == start, "Returning to the actual Main title reveals the retained character without taking Start focus")
	ui.set_selected_hero("alk")
	await _settle()
	scroll.scroll_vertical = 0
	var settings: Button = _find_button(ui._page, "设置")
	settings.grab_focus()
	ui.set_selected_hero("falsche")
	_key(KEY_ENTER)
	_check(ui._overlay_mode == "settings_title", "A queued last-row reveal allows the real settings action to open first")
	await _settle()
	_check(ui._overlay_mode == "settings_title" and _overlay_owns_focus(ui), "The deferred character reveal preserves an already-open modal and its focus")
	_check(ui.handle_back(), "The modal still handles Back after deferred selected-character scrolling")
	await _settle()
	_check(root.gui_get_focus_owner() == settings and selected.button_pressed and scroll.get_global_rect().grow(0.1).encloses(selected.get_global_rect()), "Back restores settings focus with the retained last-row character fully visible")
	_check(FileAccess.get_file_as_bytes(path) == original, "Startup, title scrolling and settings focus leave the isolated saved profile unchanged")
	app.queue_free()
	await _settle()
	_check(DirAccess.remove_absolute(path) == OK and DirAccess.remove_absolute(directory) == OK, "The saved-character title fixture removes its temporary profile and directory")


func _snapshot(state: RunState, ui: GameUI) -> Dictionary:
	return {"summary": state.summary(), "rng": state.rng.state,
		"bonuses": state.get("_upgrade_bonuses").duplicate(true),
		"options": state.get("_upgrade_options").duplicate(true), "error": state.last_error,
		"screen": ui._screen, "overlay": ui._overlay_mode, "starter": ui._starter,
		"refresh_queued": ui._refresh_queued}


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.is_visible_in_tree() and node.text == text:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null


func _overlay_owns_focus(ui: GameUI) -> bool:
	var owner: Control = root.gui_get_focus_owner()
	return owner != null and ui._overlay.is_ancestor_of(owner)


func _emit(button: Button) -> void:
	if is_instance_valid(button):
		button.pressed.emit()


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, false)


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _dispose(ui: GameUI) -> void:
	ui.queue_free()
	await _settle()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
