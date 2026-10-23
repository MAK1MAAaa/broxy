extends SceneTree
## Read real upgrade cards; independent, legally purchased states supply post-choice stats.

const STAT_NAMES: Dictionary = {
	"damage": "伤害", "haste": "攻速", "speed": "移速",
	"vitality": "生命上限", "armor": "护甲", "magnet": "拾取范围",
}

var _checks: int = 0
var _failures: int = 0
var _fixture_valid: bool = true


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.size = Vector2i(1280, 720)
	var covered: Dictionary = {}
	for seed_value: int in range(1, 61):
		if covered.size() == STAT_NAMES.size():
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
		var ui := GameUI.new()
		root.add_child(ui)
		ui.bind(state)
		var before: Dictionary = _snapshot(state)
		ui.show_upgrades()
		await _settle()
		_check(_snapshot(state) == before, "Rendering generated choices preserves stats, currency, RNG and options: seed %d" % seed_value)
		_check(state.pending_upgrades == 2, "The ordinary XP API earns exactly two upgrade selections: seed %d" % seed_value)
		_assert_page(ui, seed_value, [], choices)
		ui.show_upgrades()
		await _settle()
		_check(_snapshot(state) == before, "Reopening the same preview page does not roll choices or apply bonuses: seed %d" % seed_value)
		var id: String = str(selected["id"])
		var stat_key: String = str(selected["stat"])
		var oracle: RunState = _state(seed_value)
		_check(oracle.upgrade_choices() == choices and oracle.choose_upgrade(id), "The independent fixture accepts the naturally offered first upgrade: " + id)
		var selected_index: int = choices.find(selected)
		var button: Button = _choice_button(ui, id, selected_index)
		_check(button != null, "Each current card has an actionable real choice button: " + id)
		if button != null:
			button.grab_focus()
			_key(KEY_ENTER)
		_check(state.pending_upgrades == 1 and is_equal_approx(state.stat(stat_key), oracle.stat(stat_key)), "Real Return applies exactly the stat promised by the independent choice: " + id)
		_check(state.rng.state == oracle.rng.state, "Choosing a displayed preview does not consume extra random numbers: " + id)
		await _settle()
		var following: Array[Dictionary] = oracle.upgrade_choices()
		_check(state.upgrade_choices() == following and state.rng.state == oracle.rng.state, "The second visible page uses the ordinary subsequent choices: " + id)
		var second_before: Dictionary = _snapshot(state)
		_assert_page(ui, seed_value, [id], following)
		_check(_snapshot(state) == second_before, "Inspecting second-page previews preserves the remaining upgrade and its bonuses: " + id)
		covered[id] = true
		ui.queue_free()
		await _settle()
	_check(_fixture_valid, "All catalog relics are purchased at formal shop prices up to their real three-stack caps")
	_check(covered.size() == STAT_NAMES.size(), "Naturally generated choices across seeds 1 through 60 allow actual selections of all six upgrade types")
	await _test_repeated_stat()
	print("UpgradePreviews: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_repeated_stat() -> void:
	# Seed two offers armor in both pending sets; this exposes stale before/after numbers.
	var state: RunState = _state(2)
	var first: Array[Dictionary] = state.upgrade_choices()
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_upgrades()
	await _settle()
	var old_preview: String = _preview(ui, "armor").text if _preview(ui, "armor") != null else ""
	var first_index: int = _choice_index(first, "armor")
	var button: Button = _choice_button(ui, "armor", first_index)
	_check(first_index >= 0 and button != null, "Seed two exposes an actual armor choice on the first page")
	if button != null:
		button.grab_focus()
		_key(KEY_ENTER)
	await _settle()
	var following: Array[Dictionary] = state.upgrade_choices()
	_check(_choice_index(following, "armor") >= 0 and state.pending_upgrades == 1, "The same armor type is naturally offered again after one actual selection")
	var oracle: RunState = _state(2, ["armor"])
	var before: float = oracle.stat("armor")
	oracle.upgrade_choices()
	_check(oracle.choose_upgrade("armor"), "The independent second armor choice succeeds through RunState")
	var preview: Label = _preview(ui, "armor")
	var expected: String = _format_preview("armor", before, oracle.stat("armor"))
	_check(preview != null and preview.text == expected and preview.text != old_preview, "A repeated stat preview starts at the newly gained armor and shows the actual next choice result")
	button = _choice_button(ui, "armor", _choice_index(following, "armor"))
	if button != null:
		button.grab_focus()
		_key(KEY_ENTER)
	_check(state.pending_upgrades == 0 and is_equal_approx(state.stat("armor"), oracle.stat("armor")), "The second real Return agrees with the updated armor preview")
	await _settle()
	_check(ui._screen == "transition", "Completing both selections leaves the preview page normally")
	ui.queue_free()
	await _settle()


func _assert_page(ui: GameUI, seed_value: int, prior: Array[String], choices: Array[Dictionary]) -> void:
	_check(choices.size() == 3 and _buttons(ui._page).size() == 3, "Every preview page keeps three distinct actionable choice cards")
	var cards: Array[Control] = []
	for choice: Dictionary in choices:
		var id: String = str(choice["id"])
		var key: String = str(choice["stat"])
		var oracle: RunState = _state(seed_value, prior)
		_check(oracle.upgrade_choices() == choices, "The independent oracle regenerates the same natural offer set: " + id)
		var current: float = oracle.stat(key)
		_check(oracle.choose_upgrade(id), "The oracle applies the actual offered RunState upgrade: " + id)
		var expected: String = _format_preview(id, current, oracle.stat(key))
		var card: Control = ui._page.find_child("Upgrade_" + id, true, false) as Control
		var preview: Label = _preview(ui, id)
		_check(card != null and card.is_visible_in_tree(), "A visible card is identified by its actual upgrade ID: " + id)
		_check(preview != null and preview.is_visible_in_tree(), "The upgrade exposes a visible numeric preview label: " + id)
		_check(preview != null and preview.text == expected, "The visible before/after text agrees with real relic-stacked RunState selection: " + id + " -> " + expected)
		_check(preview != null and preview.get_theme_font_size("font_size") >= 16, "Upgrade preview numbers retain a readable font size: " + id)
		_check(card != null and preview != null and card.get_global_rect().grow(1.0).encloses(preview.get_global_rect()), "The numeric preview fits inside its own choice card: " + id)
		if card != null:
			cards.append(card)
	_check(_controls_fit(ui._page), "Upgrade cards, buttons and all labels remain unclipped within 1280 by 720")
	var separated: bool = cards.size() == 3
	for first: int in cards.size():
		for second: int in range(first + 1, cards.size()):
			separated = separated and not cards[first].get_global_rect().intersects(cards[second].get_global_rect())
	_check(separated, "All three named choice cards occupy separate visible areas")


func _state(seed_value: int, prior: Array[String] = []) -> RunState:
	var state := RunState.new()
	state.begin(seed_value, "bone")
	# Currency is a controlled fixture; ownership is acquired only through real purchases.
	state.gold = 1000
	for definition: ContentDef in GameCatalog.relics():
		for stack: int in 3:
			state.offers = [{"kind": "relic", "id": definition.id, "price": state.shop_price(definition), "sold": false}]
			_fixture_valid = state.buy_offer(0) and _fixture_valid
		_fixture_valid = int(state.relic_counts.get(definition.id, 0)) == RunState.RELIC_CAP and _fixture_valid
	state.collect_souls(102)
	for id: String in prior:
		state.upgrade_choices()
		_fixture_valid = state.choose_upgrade(id) and _fixture_valid
	return state


func _format_preview(id: String, before: float, after: float) -> String:
	if id == "damage" or id == "haste":
		return "%s  ×%.2f → ×%.2f" % [STAT_NAMES[id], before, after]
	return "%s  %.0f → %.0f" % [STAT_NAMES[id], before, after]


func _snapshot(state: RunState) -> Dictionary:
	var stats: Dictionary = {}
	for key: String in RunState.BASE_STATS:
		stats[key] = state.stat(key)
	return {"summary": state.summary(), "stats": stats, "rng": state.rng.state,
		"options": state._upgrade_options.duplicate(true), "bonuses": state._upgrade_bonuses.duplicate(true),
		"offers": state.offers.duplicate(true), "rerolls": state.rerolls, "error": state.last_error}


func _preview(ui: GameUI, id: String) -> Label:
	var card: Node = ui._page.find_child("Upgrade_" + id, true, false)
	return null if card == null else card.find_child("UpgradePreview", true, false) as Label


func _choice_button(ui: GameUI, id: String, fallback_index: int) -> Button:
	var card: Node = ui._page.find_child("Upgrade_" + id, true, false)
	var candidates: Array[Button] = _buttons(card if card != null else ui._page)
	if card != null:
		return candidates[0] if candidates.size() == 1 else null
	return candidates[fallback_index] if fallback_index >= 0 and fallback_index < candidates.size() else null


func _choice_index(choices: Array[Dictionary], id: String) -> int:
	for index: int in choices.size():
		if str(choices[index]["id"]) == id:
			return index
	return -1


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button and node.is_visible_in_tree() and node.text == "选择强化":
		result.append(node as Button)
	for child: Node in node.get_children():
		result.append_array(_buttons(child))
	return result


func _controls_fit(node: Node) -> bool:
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button or node is PanelContainer):
		var control: Control = node
		var rect: Rect2 = control.get_global_rect()
		if not Rect2(-1, -1, 1282, 722).encloses(rect) or control.size.y + 1.0 < control.get_minimum_size().y or control.size.x + 1.0 < control.get_minimum_size().x:
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
