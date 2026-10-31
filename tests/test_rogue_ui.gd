extends SceneTree
## Shipped shop decisions, modal input isolation and horizontal starter access.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_ui = GameUI.new()
	root.add_child(_ui)
	await _test_starters()
	await _test_core_route_and_modal()
	await _test_altar_and_rewards()
	await _test_full_reward_and_candle()
	_ui.queue_free()
	await process_frame
	print("RogueUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	root.push_input(event)
	await process_frame

func _button(name: String) -> Button:
	return _ui.find_child(name, true, false) as Button

func _state(number: int) -> RunState:
	var state := RunState.new()
	state.begin(20261026, "bone")
	while state.wave < number:
		state.finish_wave()
		state.next_wave()
	state.finish_wave()
	return state

func _show(state: RunState) -> void:
	state.generate_shop()
	_ui.bind(state)
	_ui.show_shop()
	await _settle()

func _open() -> void:
	var button: Button = _button("OpenRogueChoices")
	button.grab_focus()
	await _key(KEY_ENTER)
	await _settle()
	_check(_ui._overlay_mode == "rogue_choices", "Enter opens the ritual decisions from the real shop entry")

func _signature(state: RunState) -> String:
	return JSON.stringify({"summary": state.summary(), "rng": str(state.rng.state), "offers": state.offers})

func _test_starters() -> void:
	var starts: Array[String] = []
	_ui.start_requested.connect(func(id: String) -> void: starts.append(id))
	_ui.show_title({})
	await _settle()
	for id: String in HeroCatalog.IDS:
		var card: Button = _button("Character_" + id)
		_check(card != null and not card.disabled and card.focus_mode == Control.FOCUS_ALL, "All four characters are directly selectable on a fresh profile: " + id)
		_check(card != null and card.tooltip_text.is_empty() and card.get_node_or_null("SelectionMark") != null, "Character selection uses a visible mark without explanatory hover copy: " + id)
	_ui.set_selected_hero("celtie")
	_ui._start()
	_check(starts == [HeroCatalog.definition("celtie").starter_weapon], "Character selection binds its actual initial weapon independently of legacy weapon unlocks")
	_ui.set_progress(["bone", "ember", "frost", "scatter"])
	_ui.show_title({})
	await _settle()
	var previous: Button = _button("Character_hanabi")
	previous.pressed.emit()
	await _settle()
	_check(_ui.selected_hero() == "hanabi" and _ui._starter == HeroCatalog.definition("hanabi").starter_weapon, "The actual character card selects its identity and initial weapon")
	_ui._start()
	_check(starts == [HeroCatalog.definition("celtie").starter_weapon, HeroCatalog.definition("hanabi").starter_weapon], "Start requests carry each selected character's weapon")
	_ui.set_progress(["bone", "ember"])
	previous.pressed.emit()
	_check(_ui.selected_hero() == "hanabi", "Legacy weapon progress changes do not remove access to the selected character")
	_ui.show_title({})
	await _settle()
	var breathing: Control = _ui.find_child("IllustrationBreathingSpace", true, false)
	_check(breathing.size.x >= 400 and breathing.size.y >= 260, "Compact selectors preserve the complete right-hand illustration space")

func _test_core_route_and_modal() -> void:
	var state: RunState = _state(1)
	await _show(state)
	var before: String = _signature(state)
	await _open()
	_check(_signature(state) == before, "Constructing and opening the choices is read-only, including RNG")
	_check(_ui._page.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED and not _ui._bag_grid.interaction_enabled, "The modal disables background focus and backpack input")
	var next: Button = _ui._shop_focus_button("next_wave")
	var requests: Array[int] = [0]
	_ui.next_wave_requested.connect(func() -> void: requests[0] += 1)
	next.pressed.emit()
	_check(requests[0] == 0, "A retained background next-wave callback cannot bypass the decisions modal")
	for step: int in 12:
		await _key(KEY_TAB)
		_check(_ui._overlay.is_ancestor_of(root.gui_get_focus_owner()), "Real Tab traversal stays in the ritual overlay")
	var old_other: Button = _button("RogueCore_frostfire")
	var old_route: Button = _button("RogueRoute_bulwark")
	var core: Button = _button("RogueCore_bone_chorus")
	core.pressed.emit()
	old_other.pressed.emit()
	old_route.pressed.emit()
	_check(state.core_id == "bone_chorus" and state.next_route == "balanced", "Only one core transaction runs before the old overlay callbacks expire")
	await _settle()
	_check(_ui._overlay_mode == "rogue_choices" and _button("RogueCore_frostfire") == null, "Core selection reopens the current decision summary without stale core controls")
	_check(str((_ui.find_child("RogueNotice", true, false) as Label).text).contains("白骨齐鸣"), "The rebuilt modal reports successful application in its own notice area")
	var opposite: Button = _button("RogueRoute_bulwark")
	_button("RogueRoute_swarm").pressed.emit()
	opposite.pressed.emit()
	_check(state.next_route == "swarm", "A second route callback from the same old frame cannot overwrite the chosen route")
	await _settle()
	_check(_button("RogueRoute_swarm").text.begins_with("已选"), "The next-wave route is explicitly marked after rebuilding")
	var viewport := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var body: Control = _ui.find_child("RogueChoices", true, false)
	_check(viewport.encloses(body.get_global_rect()) and viewport.encloses(_button("CloseRogueChoices").get_global_rect()), "Modal content and persistent return action fit the reference viewport")
	var scroll: ScrollContainer = _ui.find_child("RogueChoicesScroll", true, false)
	var long_note := Label.new()
	long_note.text = "Temporary overflow for real key scrolling\n".repeat(32)
	scroll.get_child(0).add_child(long_note)
	await _settle()
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "The scroll fixture explicitly establishes a real overflow range")
	scroll.grab_focus()
	await _key(KEY_END)
	_check(scroll.scroll_vertical > 0, "Long decisions can be scrolled with actual End input")
	await _key(KEY_HOME)
	_check(scroll.scroll_vertical == 0, "Actual Home restores the start of the decision list")
	long_note.get_parent().remove_child(long_note)
	long_note.queue_free()
	await _settle()
	_check(_ui.handle_back(), "The shared back handler closes ritual decisions")
	await _settle()
	_check(_ui._overlay_mode.is_empty() and _ui._bag_grid.interaction_enabled and root.gui_get_focus_owner() == _button("OpenRogueChoices"), "Back restores the shop entry focus and backpack interaction")
	_check(viewport.encloses(_ui._bag_grid.get_global_rect()) and _ui._bag_grid.size.x >= 300 and _ui._bag_grid.size.y >= 300, "The added shop entry preserves the complete six-by-six backpack")
	await _open()
	var stale: Button = _button("RogueRoute_bulwark")
	state.gold += 1
	state.changed.emit()
	stale.pressed.emit()
	_check(state.next_route == "swarm" and _ui._overlay_mode.is_empty(), "External shop changes close the projection and invalidate its old actions")
	await _settle()

func _test_altar_and_rewards() -> void:
	var declined: RunState = _state(2)
	await _show(declined)
	await _open()
	var accept_old: Button = _button("RogueAltarAccept")
	_button("RogueAltarDecline").pressed.emit()
	accept_old.pressed.emit()
	_check(declined.altar_choice == "declined" and declined.altar_wave == -1, "Skipping the contract is a final legitimate choice, protected against repeated old callbacks")
	await _settle()
	_check(_button("RogueAltarAccept") == null, "A skipped contract cannot be silently accepted later in the same run")
	var state: RunState = _state(2)
	await _show(state)
	await _open()
	_button("RogueAltarAccept").pressed.emit()
	await _settle()
	_check(state.altar_choice == "accepted" and state.altar_wave == 3, "The real altar control schedules the next-wave hunter")
	state.next_wave()
	state.record_hunter_defeat()
	state.finish_wave()
	await _show(state)
	await _open()
	_check(_button("RogueReward_blast") != null and state.rune_reward_pending, "A completed contract exposes three selectable rune rewards at the shop")
	var other: Button = _button("RogueReward_pierce")
	var gold: int = state.gold
	var claim: Button = _button("RogueReward_blast")
	claim.pressed.emit()
	other.pressed.emit()
	_check(not state.rune_reward_pending and state.rune_bag.size() == 1 and state.rune_bag[0]["id"] == "blast", "Only one selected reward rune is granted through the real transaction")
	_check(state.gold == gold and state.rune_bag[0]["paid"] == 0 and state.rune_bag[0]["rank"] == 1, "Contract rewards preserve currency and grant the advertised first-rank unsellable value")
	await _settle()
	_check(_button("RogueReward_pierce") == null, "Claiming removes obsolete reward controls")
	state.begin(20261027, "bone")
	await _show(state)
	await _open()
	_check(state.core_id.is_empty() and state.altar_choice.is_empty() and not state.rune_reward_pending, "A fresh run cannot inherit core, contract or pending rewards")
	_check(_button("RogueCore_frostfire").disabled, "Unfinished first-wave fixtures cannot choose a core through the UI")

func _buy(state: RunState, kind: String, id: String) -> int:
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(BackpackInventory.definition(kind, id)), "sold": false}]
	if not state.buy_offer(0):
		return -1
	return int(state.backpack_snapshot()["next_uid"]) - 1

func _test_full_reward_and_candle() -> void:
	var state: RunState = _state(2)
	_check(state.choose_altar(true), "The full-bag fixture accepts the real contract")
	state.next_wave()
	state.record_hunter_defeat()
	state.finish_wave()
	state.gold = 10000
	var last: int = -1
	while state.backpack.can_add("relic", "armor"):
		last = _buy(state, "relic", "armor")
	await _show(state)
	await _open()
	var before: String = JSON.stringify(state.backpack_snapshot())
	_button("RogueReward_bounce").pressed.emit()
	await _settle()
	_check(state.rune_reward_pending and JSON.stringify(state.backpack_snapshot()) == before, "A full bag preserves both the pending reward and all existing items")
	_check((_ui.find_child("RogueNotice", true, false) as Label).text.contains("空间不足"), "A failed claim explains the recoverable capacity problem inside the modal")
	_check(state.sell_item(last), "A formal sale frees a reward cell")
	await _settle()
	await _open()
	_button("RogueReward_bounce").pressed.emit()
	await _settle()
	_check(not state.rune_reward_pending and state.rune_bag.size() == 1, "The same reserved reward can be claimed after organizing inventory")
	var lamp: RunState = _state(1)
	lamp.gold = 1000
	var candle: int = _buy(lamp, "relic", "grave_candle")
	_check(candle > 0 and lamp.move_item(candle, Vector2i(0, 3), false), "The lamp fixture purchases and places its candle through actual inventory transactions")
	await _show(lamp)
	var weapon: int = int(lamp.loadout[0]["uid"])
	_ui._bp_select(weapon, _ui._shop_epoch)
	var linked_effect := _ui.find_child("BackpackItemEffect", true, false) as Label
	_check(linked_effect.text.contains("烛引") and linked_effect.tooltip_text.contains("引魂烛联动"), "A linked weapon shows its targeting status and preserves the full behavior in its details")
	_ui._bp_select(candle, _ui._shop_epoch)
	var effect: String = (_ui.find_child("BackpackItemEffect", true, false) as Label).tooltip_text
	_check(effect.contains("正上方") and effect.contains(GameCatalog.weapon("bone").display_name + " #") and effect.contains("不叠加"), "The candle names its actual linked weapon and states direction and non-stacking behavior")
