extends SceneTree
## Combat-context upgrade pages use the same legal choices and modal input guards.

class EscapeRouter:
	extends Node
	var ui: GameUI

	func _unhandled_key_input(event: InputEvent) -> void:
		if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
			return
		if not ui.handle_back():
			if ui._overlay_mode == "pause":
				ui.hide_pause()
			elif ui._overlay_mode.is_empty():
				ui.show_pause()
		get_viewport().set_input_as_handled()

var _checks: int = 0
var _failures: int = 0
var _fixture_valid: bool = true


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.size = Vector2i(1280, 720)
	await _test_legal_previews_and_selections()
	await _test_pending_pages_and_pause_settings()
	await _test_context_replacement_and_stale_controls()
	await _test_deferred_completion_generation()
	paused = false
	_check(_fixture_valid, "Existing relic bonuses come from formal purchases and health loss uses the damage API")
	print("CombatUpgradeUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _state(seed_value: int = 2) -> RunState:
	var state := RunState.new()
	state.begin(seed_value, "bone")
	state.gold = 2000
	for id: String in ["damage", "haste", "vitality", "blood_pact", "hourglass", "grave_candle"]:
		var definition: ContentDef = GameCatalog.relic(id)
		state.offers = [{"kind": "relic", "id": id, "price": state.shop_price(definition), "sold": false}]
		_fixture_valid = state.buy_offer(0) and _fixture_valid
	_fixture_valid = state.take_damage(17.0) > 0.0 and _fixture_valid
	state.collect_souls(102)
	_fixture_valid = state.pending_upgrades == 2 and _fixture_valid
	return state


func _new_ui(state: RunState, during_combat: bool) -> GameUI:
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_upgrades(during_combat)
	await _settle()
	return ui


func _test_legal_previews_and_selections() -> void:
	var covered: Dictionary = {}
	for seed_value: int in range(1, 61):
		if covered.size() == RunState.UPGRADE_POOL.size():
			break
		var state: RunState = _state(seed_value)
		var choices: Array[Dictionary] = state.upgrade_choices()
		var selected: Dictionary = {}
		for choice: Dictionary in choices:
			if not covered.has(str(choice["id"])):
				selected = choice
				break
		if selected.is_empty():
			continue
		var before: Dictionary = _snapshot(state)
		paused = true
		var ui: GameUI = await _new_ui(state, true)
		_check(_snapshot(state) == before and paused, "Rendering a combat upgrade page preserves stats, choices, currency, RNG and the externally paused tree")
		_check(_context(ui).contains("战斗已暂停，选完强化继续当前波次") and ui._upgrades_during_combat, "Combat upgrades explain that choices resume the current wave")
		_check(_choice_buttons(ui._page).size() == 3, "Combat context retains exactly three choices with no skip or extra reward action")
		for choice: Dictionary in choices:
			var oracle: RunState = _state(seed_value)
			_check(oracle.upgrade_choices() == choices, "The independent legal state reproduces the displayed natural choices")
			var key: String = str(choice["stat"])
			var current: float = oracle.stat(key)
			var health_before: float = oracle.health
			_check(oracle.choose_upgrade(str(choice["id"])), "The preview oracle applies the actual offered upgrade")
			var card: Control = ui._page.find_child("Upgrade_" + str(choice["id"]), true, false)
			var preview: Label = card.find_child("UpgradePreview", true, false) if card != null else null
			_check(preview != null and preview.text == _stat_preview(key, current, oracle.stat(key)), "Combat stat previews match real relic-stacked choices without a DPS claim: " + str(choice["id"]))
			var health: Label = card.find_child("UpgradeHealthPreview", true, false) if card != null else null
			if key == "max_health":
				var expected: String = "生命  %.0f → %.0f（回复 %.0f）" % [health_before, oracle.health, oracle.health - health_before]
				_check(health != null and health.text == expected and oracle.health > health_before, "Vitality displays the actual current-health refill as well as the new maximum")
			else:
				_check(health == null and is_equal_approx(oracle.health, health_before), "Other upgrade types neither promise nor apply an unrelated health refill")
		_check(_controls_fit(ui._page), "All combat-context descriptions, real stat previews and choice buttons fit within 1280 by 720")
		var id: String = str(selected["id"])
		var selected_oracle: RunState = _state(seed_value)
		selected_oracle.upgrade_choices()
		selected_oracle.choose_upgrade(id)
		var button: Button = _choice_button(ui, id)
		_check(button != null and button.focus_mode == Control.FOCUS_ALL, "The offered combat upgrade is keyboard actionable")
		if button != null:
			button.grab_focus()
			_key(KEY_ENTER)
		_check(_snapshot(state) == _snapshot(selected_oracle) and state.pending_upgrades == 1, "Real Enter applies only the displayed upgrade and its real health/stat change")
		var after: Dictionary = _snapshot(state)
		_key(KEY_ENTER)
		_check(_snapshot(state) == after, "Repeated Enter before rebuilding cannot consume an unseen combat upgrade")
		await _settle()
		_check(ui._upgrades_during_combat and _context(ui).contains("继续当前波次") and paused, "The next pending choice preserves combat context and leaves pause ownership with Main")
		covered[id] = true
		ui.queue_free()
		paused = false
		await _settle()
	_check(covered.size() == RunState.UPGRADE_POOL.size(), "Natural seeded choices exercise all six real upgrade types during combat")


func _test_pending_pages_and_pause_settings() -> void:
	var state: RunState = _state()
	paused = true
	var ui: GameUI = await _new_ui(state, true)
	var router := EscapeRouter.new()
	router.process_mode = Node.PROCESS_MODE_ALWAYS
	router.ui = ui
	root.add_child(router)
	ui.resume_requested.connect(ui.hide_pause)
	var completions: Array[int] = [0]
	ui.upgrades_finished.connect(func() -> void: completions[0] += 1)
	var first: Button = _choice_buttons(ui._page)[0]
	_check(root.gui_get_focus_owner() == first, "A combat upgrade receives initial keyboard focus even while the tree is paused")
	_key(KEY_TAB)
	await process_frame
	var second: Button = _choice_buttons(ui._page)[1]
	_check(root.gui_get_focus_owner() == second, "Real Tab reaches the next combat upgrade card")
	_key(KEY_ENTER)
	_check(state.pending_upgrades == 1, "The focused card accepts one real keyboard selection")
	_key(KEY_ESCAPE)
	await _settle()
	_check(ui._overlay_mode == "pause" and _overlay_owns_focus(ui) and paused, "Esc opens the ordinary pause overlay while a pending upgrade rebuild remains frozen")
	_check(ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED and ui._upgrades_during_combat, "The rebuilt underlying upgrade page stays modal-gated with its combat context")
	var before: Dictionary = _snapshot(state)
	var underlying: Button = _choice_buttons(ui._page)[0]
	underlying.pressed.emit()
	_check(_snapshot(state) == before, "A still-live underlying choice callback cannot act through the pause overlay")
	for count: int in 8:
		_key(KEY_TAB)
		await process_frame
		_check(_overlay_owns_focus(ui), "Tab navigation remains inside the pause overlay")
	var settings: Button = _find_button(ui._overlay, "设置")
	_check(settings != null, "The pause overlay retains its ordinary settings action")
	if settings != null:
		settings.grab_focus()
		_key(KEY_ENTER)
	await _settle()
	_check(ui._overlay_mode == "settings_pause" and _overlay_owns_focus(ui), "Real Enter opens settings over the combat upgrade page")
	_key(KEY_ESCAPE)
	await _settle()
	settings = _find_button(ui._overlay, "设置")
	_check(ui._overlay_mode == "pause" and root.gui_get_focus_owner() == settings and paused, "Esc from settings returns to pause with settings focus and leaves combat frozen")
	_key(KEY_ESCAPE)
	await _settle()
	_check(ui._overlay_mode.is_empty() and ui._screen == "upgrades" and ui._upgrades_during_combat and paused, "Esc from pause reveals the remaining upgrade rather than the live combat HUD")
	var owner: Control = root.gui_get_focus_owner()
	_check(owner is Button and owner.text == "选择强化" and ui._page.is_ancestor_of(owner), "Closing pause restores a usable current upgrade button after the original card was rebuilt")
	_check(_snapshot(state) == before and completions[0] == 0, "Pause/settings navigation consumes no choice and emits no completion")
	_key(KEY_ENTER)
	_key(KEY_ENTER)
	await _settle()
	_check(state.pending_upgrades == 0 and completions[0] == 1 and ui._screen == "transition", "Only the final displayed choice emits one completion signal")
	_check(paused, "UI completion never resumes the SceneTree itself")
	router.queue_free()
	ui.queue_free()
	paused = false
	await _settle()


func _test_context_replacement_and_stale_controls() -> void:
	var state: RunState = _state()
	var ui: GameUI = await _new_ui(state, true)
	var old: Button = _choice_buttons(ui._page)[0]
	ui.show_upgrades(true)
	var before: Dictionary = _snapshot(state)
	if is_instance_valid(old):
		old.pressed.emit()
	_check(_snapshot(state) == before, "Reopening combat upgrades invalidates the old page's still-live choice callback")
	await _settle()
	_check(ui._upgrades_during_combat and _context(ui).contains("继续当前波次"), "Explicitly reopening the combat page preserves its context")
	old = _choice_buttons(ui._page)[0]
	ui.show_upgrades()
	if is_instance_valid(old):
		old.pressed.emit()
	_check(_snapshot(state) == before and not ui._upgrades_during_combat, "Default show_upgrades restores wave-end context and rejects the prior combat page")
	await _settle()
	_check(_context(ui) == "选择一项强化  ·  待选择 2 次", "Wave-end upgrades retain their existing explanation")
	old = _choice_buttons(ui._page)[0]
	ui.show_title({})
	if is_instance_valid(old):
		old.pressed.emit()
	_check(_snapshot(state) == before and not ui._upgrades_during_combat, "Leaving upgrades clears their context and blocks abandoned choice callbacks")
	ui.queue_free()
	await _settle()


func _test_deferred_completion_generation() -> void:
	var state := RunState.new()
	state.begin(33, "bone")
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	var completions: Array[int] = [0]
	ui.upgrades_finished.connect(func() -> void: completions[0] += 1)
	ui.show_upgrades(true)
	var old_epoch: int = ui._upgrade_epoch
	ui.show_upgrades()
	_check(ui._screen == "transition" and ui._upgrade_epoch != old_epoch, "The generation fixture replaces one deferred completion with a new transition")
	var before: Dictionary = _snapshot(state)
	ui._finish_upgrades(old_epoch)
	_check(completions[0] == 0 and _snapshot(state) == before, "An old completion cannot finish a newer transition with the same screen name")
	await _settle()
	_check(completions[0] == 1 and _snapshot(state) == before, "Only the current deferred generation completes, without adding a reward or consuming RNG")
	ui.queue_free()
	await _settle()


func _stat_preview(key: String, before: float, after: float) -> String:
	var names: Dictionary = {"damage": "伤害", "attack_speed": "攻速", "move_speed": "移速", "max_health": "生命上限", "armor": "护甲", "pickup_radius": "拾取范围"}
	return "%s  ×%.2f → ×%.2f" % [names[key], before, after] if key in ["damage", "attack_speed"] else "%s  %.0f → %.0f" % [names[key], before, after]


func _snapshot(state: RunState) -> Dictionary:
	var stats: Dictionary = {}
	for key: String in RunState.BASE_STATS:
		stats[key] = state.stat(key)
	return {"summary": state.summary(), "stats": stats, "health": state.health,
		"rng": state.rng.state, "options": state._upgrade_options.duplicate(true),
		"bonuses": state._upgrade_bonuses.duplicate(true), "offers": state.offers.duplicate(true), "error": state.last_error}


func _context(ui: GameUI) -> String:
	var label: Label = ui._page.find_child("UpgradeContext", true, false)
	return label.text if label != null else ""


func _choice_button(ui: GameUI, id: String) -> Button:
	var card: Node = ui._page.find_child("Upgrade_" + id, true, false)
	var buttons: Array[Button] = _choice_buttons(card) if card != null else []
	return buttons[0] if buttons.size() == 1 else null


func _choice_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button and node.text == "选择强化" and node.is_visible_in_tree():
		buttons.append(node)
	for child: Node in node.get_children():
		buttons.append_array(_choice_buttons(child))
	return buttons


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null


func _overlay_owns_focus(ui: GameUI) -> bool:
	var owner: Control = root.gui_get_focus_owner()
	return owner != null and ui._overlay.is_ancestor_of(owner)


func _controls_fit(node: Node) -> bool:
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button or node is PanelContainer):
		if not root.get_visible_rect().grow(1).encloses(node.get_global_rect()) or node.size.x + 1 < node.get_minimum_size().x or node.size.y + 1 < node.get_minimum_size().y:
			return false
	for child: Node in node.get_children():
		if not _controls_fit(child):
			return false
	return true


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


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
