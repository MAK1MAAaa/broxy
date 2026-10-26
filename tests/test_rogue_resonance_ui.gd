extends SceneTree
## Combined core/candle/placement guidance and the shared-edge presentation path.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_ui = GameUI.new()
	root.add_child(_ui)
	await _test_combined_inventory()
	_ui.queue_free()
	await process_frame
	print("RogueResonanceUI: %d assertions, %d failures" % [_checks, _failures])
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
	await _settle()

func _buy(state: RunState, kind: String, id: String) -> int:
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(BackpackInventory.definition(kind, id)), "sold": false}]
	_check(state.buy_offer(0), "The integration fixture buys its real stored item: " + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1

func _label(name: String) -> Label:
	return _ui.find_child(name, true, false) as Label

func _button(name: String) -> Button:
	return _ui.find_child(name, true, false) as Button

func _grid() -> BackpackGrid:
	return _ui.find_child("BackpackGrid", true, false) as BackpackGrid

func _signature(state: RunState) -> String:
	return JSON.stringify({"summary": state.summary(), "rng": str(state.rng.state), "offers": state.offers})

func _test_combined_inventory() -> void:
	var state := RunState.new()
	state.begin(20261027, "bone")
	state.finish_wave()
	_check(state.choose_core("bone_chorus") and state.loadout.size() == 2, "The actual core creates a second independent bone weapon before resonance placement")
	state.gold = 1000
	var first: int = int(state.loadout[0]["uid"])
	var partner: int = int(state.loadout[1]["uid"])
	var candle: int = _buy(state, "relic", "grave_candle")
	_check(state.move_item(candle, Vector2i(0, 3), false), "The candle is legally placed below both vertical bone weapons")
	var armor: int = _buy(state, "relic", "armor")
	_check(state.move_item(armor, Vector2i(2, 2), false), "A second relic supplies only the right-hand weapon's shared edge")
	var rune: int = _buy(state, "rune", "pierce")
	_check(state.equip_rune(state.rune_index_for_uid(rune), state.weapon_index_for_uid(first)), "The linked, resonating weapon also receives a real socket rune")
	state.generate_shop()
	_ui.bind(state)
	_ui.show_shop()
	await _settle()
	_grid().select_item(first)
	await _settle()
	_check(state.linked_weapon_uids() == [first, partner], "Candle targeting remains a separate live relation on both weapons")
	_check(is_equal_approx(float(state.loadout[0]["resonance_bonus"]), 0.03) and is_equal_approx(float(state.loadout[1]["resonance_bonus"]), 0.06), "Shared-edge damage reflects each UID's actual source relics")
	_check(_label("BackpackWeaponStats").text.contains("%.1f伤害" % state.weapon_damage(state.loadout[0])), "Actual effective damage, including resonance, reaches the selected core weapon's UI")
	_check(_label("BackpackResonanceSummary").text == "共鸣+3% · 1件遗物", "The compact resonance summary remains visible beside rogue/candle data")
	_check(_label("BackpackItemEffect").text.contains("引魂烛联动"), "The selected weapon still explains the candle targeting effect")
	var box: Control = _grid().find_child("BackpackItem%d" % first, false, false)
	var material: Control = box.find_child("BoxMaterial", false, false)
	var badge: TextureRect = box.find_child("SocketRuneBadge", false, false)
	var arrow: Label = box.find_child("CandleLink", false, false)
	_check(material != null and material.size == box.size and material.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Metal/leather decoration preserves the original interactive rectangle")
	_check(badge != null and badge.size == Vector2(16, 16) and badge.get_meta("rune_id") == "pierce", "The merged grid keeps the real sixteen-pixel socket badge")
	_check(arrow != null and not arrow.get_rect().intersects(badge.get_rect()), "Candle arrow and socket badge occupy separate rectangles")
	_check(box.get_global_rect().encloses(arrow.get_global_rect()) and box.get_global_rect().encloses(badge.get_global_rect()), "Both live indicators stay inside their weapon box")
	_check(_grid().resonance_contacts().size() == 1 and _grid().resonance_contacts()[0]["relic_uid"] == candle, "Selecting a candle-linked weapon illuminates its actual shared edge")
	var before: String = _signature(state)
	_grid().begin_placement(partner, false, Vector2i.ZERO)
	var candidates: Array[Dictionary] = _grid().placement_targets()
	_check(candidates.size() == 1 and candidates[0]["uid"] == first and candidates[0]["kind"] == "merge", "Merge candidates survive alongside resonance inspection")
	_check(_grid().placement_at(Vector2i.ZERO)["kind"] == "merge" and _grid().resonance_contacts().is_empty(), "An intended merge never advertises a separate hypothetical resonance ghost")
	var source_box: Control = _grid().find_child("BackpackItem%d" % partner, false, false)
	_check(source_box.modulate != Color.WHITE and _grid()._preview.clip_contents, "Held-source dimming and preview clipping remain enabled with the new materials")
	var entry: Button = _button("OpenRogueChoices")
	entry.pressed.emit()
	await _settle()
	_check(_ui._overlay_mode == "rogue_choices" and _grid().held_uid < 0 and source_box.modulate == Color.WHITE, "Opening rogue choices cancels the held ghost and restores the material's brightness")
	_check(not _grid().interaction_enabled and _grid().placement_targets().is_empty(), "The decision modal gates grid interactions and candidate guidance")
	_check(_signature(state) == before and _ui._overlay.is_ancestor_of(root.gui_get_focus_owner()), "Combined presentation remains read-only and gives focus to the active overlay")
	var old_next: Button = _ui._shop_focus_button("next_wave")
	var next_requests: Array[int] = [0]
	_ui.next_wave_requested.connect(func() -> void: next_requests[0] += 1)
	old_next.pressed.emit()
	_check(next_requests[0] == 0, "A retained background callback cannot begin combat through the rogue modal")
	_check(_ui.handle_back(), "Back closes the current decision modal")
	await _settle()
	_check(root.gui_get_focus_owner() == _button("OpenRogueChoices") and _grid().interaction_enabled, "Closing restores the ritual entry focus and grid input")
	_grid().select_item(first)
	_ui._bp_pick_up(first)
	await _settle()
	await _key(KEY_R)
	for step: int in 3:
		await _key(KEY_RIGHT)
	await _key(KEY_DOWN)
	_check(_grid().placement_at(_grid().cursor)["valid"], "The real rotated footprint has a legal remote destination")
	await _key(KEY_ENTER)
	var moved: Dictionary = state.backpack_item(first)
	_check(moved["rotated"] and int(moved["x"]) == 3 and int(moved["y"]) == 1, "Real R/arrows/Enter move the socketed core weapon through the shipped transaction")
	_check(not state.linked_weapon_uids().has(first) and is_zero_approx(float(state.loadout[0]["resonance_bonus"])), "Moving away recomputes both targeting links and local damage instead of retaining old bonuses")
	_check(_label("BackpackWeaponStats").text.contains("%.1f伤害" % state.weapon_damage(state.loadout[0])) and _label("BackpackResonanceSummary").text == "共鸣+0% · 0件遗物", "Post-move detail values come from the new physical layout")
	box = _grid().find_child("BackpackItem%d" % first, false, false)
	_check(box.find_child("SocketRuneBadge", false, false) != null and box.find_child("CandleLink", false, false) == null, "Rotation keeps the installed rune while removing an inactive candle indicator")
	_check(_grid()._preview.clip_contents and _grid()._preview.mouse_filter == Control.MOUSE_FILTER_IGNORE and _grid()._preview.focus_mode == Control.FOCUS_NONE, "The combined overlay keeps clipping and passive pointer/focus semantics after rebuilding")
