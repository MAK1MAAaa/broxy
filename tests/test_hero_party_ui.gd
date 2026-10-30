extends SceneTree
## Real character selection, companion transactions and authoritative Q/E/R HUD state.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await _settle()

func _text(node: Node, value: String) -> bool:
	if node == null:
		return false
	if node is Label and node.text.contains(value):
		return true
	for child: Node in node.get_children():
		if _text(child, value):
			return true
	return false

func _icon(node: Node, kind: String, id: String) -> TextureRect:
	if node == null:
		return null
	if node is TextureRect and str(node.get_meta("content_kind", "")) == kind and str(node.get_meta("content_id", "")) == id:
		return node
	for child: Node in node.get_children():
		var found: TextureRect = _icon(child, kind, id)
		if found != null:
			return found
	return null

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, str(state.rng.state)])

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_ui = GameUI.new()
	root.add_child(_ui)
	await _test_selection()
	await _test_companion_transactions()
	await _test_hud()
	_ui.queue_free()
	await _settle()
	print("HeroPartyUI: %d assertions, %d failures; native=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)

func _test_selection() -> void:
	_ui.set_progress(["bone", "ember"])
	_ui.show_title({})
	await _settle()
	var choices := _ui.find_child("CharacterChoices", true, false) as GridContainer
	var cover: Node = _ui.find_child("MenuArtwork", true, false)
	_check(choices != null and choices.columns == 2 and choices.get_child_count() == 4, "The title provides exactly four real character choices in two columns")
	_check(_ui.find_child("Starter_bone", true, false) == null and _ui.find_child("StarterChoices", true, false) == null, "The previous weapon selector is replaced without hidden compatibility controls")
	var starts: Array[Dictionary] = []
	var record: Callable = func(starter: String) -> void: starts.append({"hero": _ui.selected_hero(), "starter": starter})
	_ui.start_requested.connect(record)
	for id: String in HeroCatalog.IDS:
		var hero: HeroDef = HeroCatalog.definition(id)
		var card := _ui.find_child("Character_" + id, true, false) as Button
		_check(card != null and not card.disabled and card.focus_mode == Control.FOCUS_ALL, "Legacy weapon progression does not lock character selection: " + id)
		if card == null:
			continue
		var art: TextureRect = _icon(card, "hero", id)
		var weapon: TextureRect = _icon(card, "weapon", hero.starter_weapon)
		_check(art != null and art.texture != null and art.texture.resource_path == hero.idle_path and art.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Each character card uses its own original pixel identity: " + id)
		_check(weapon != null and _text(card, hero.display_name) and _text(card, GameCatalog.weapon(hero.starter_weapon).display_name), "Each character card shows the full real initial weapon name and image: " + id)
		card.grab_focus()
		await _key(KEY_ENTER)
		_check(_ui.selected_hero() == id and _ui._starter == hero.starter_weapon and card.button_pressed, "Actual menu confirmation selects the character and its bound weapon: " + id)
		var start := _ui.find_child("StartTrial", true, false) as Button
		start.grab_focus()
		await _key(KEY_ENTER)
		_check(starts.back() == {"hero": id, "starter": hero.starter_weapon} and starts.size() == HeroCatalog.IDS.find(id) + 1, "The start action emits exactly once with the selected character's weapon: " + id)
	_ui.start_requested.disconnect(record)
	var last := _ui.find_child("Character_hanabi", true, false) as Button
	_check(last != null and last.get_node(last.focus_neighbor_bottom).name == "Arena_mire", "The final character row navigates directly into the same map column")
	_ui._show_settings(false)
	var selected: String = _ui.selected_hero()
	_ui.set_selected_hero("alk")
	await _settle()
	_check(_ui.selected_hero() == selected and _ui._overlay_mode == "settings_title", "A retained background selection cannot change the title under a settings modal")
	_ui.hide_pause()
	await _settle()
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		await _settle()
		var viewport: Rect2 = root.get_visible_rect()
		for id: String in HeroCatalog.IDS:
			var card := _ui.find_child("Character_" + id, true, false) as Control
			_check(card != null and viewport.encloses(card.get_global_rect()), "All character cards remain in the scaled title viewport: " + str(physical_size) + "/" + id)
		for id: String in ArenaCatalog.IDS:
			var map := _ui.find_child("Arena_" + id, true, false) as Control
			_check(map != null and viewport.encloses(map.get_global_rect()), "Character selection preserves all four visible maps: " + id)
		var start := _ui.find_child("StartTrial", true, false) as Control
		_check(start != null and viewport.encloses(start.get_global_rect()) and cover != null and _ui.find_child("MenuArtwork", true, false) == cover, "The start action remains visible and the composite cover remains unchanged")
	root.size = Vector2i(1280, 720)

func _test_companion_transactions() -> void:
	var state := RunState.new()
	state.begin(20261030, "bone", "reliquary", "alk")
	state.gold = 1000
	state.offers.assign([
		{"kind": "skill", "id": "pulse", "rank": 1, "price": 20},
		{"kind": "skill", "id": "pulse", "rank": 1, "price": 20},
		{"kind": "skill", "id": "starfall", "rank": 1, "price": 20},
		{"kind": "skill", "id": "arc_slash", "rank": 1, "price": 20},
	])
	_ui.bind(state)
	_ui.show_shop()
	await _settle()
	var before: String = _signature(state)
	for index: int in state.offers.size():
		var id: String = str(state.offers[index]["id"])
		var card: Node = _ui.find_child("Offer%d" % (index + 1), true, false)
		var art: TextureRect = _icon(card, "skill", id)
		_check(card != null and art != null and art.texture.resource_path == HeroCatalog.rear_for_skill(id).idle_path, "Actual rear offers use the corresponding original character image: " + id)
		_check(_text(card, HeroCatalog.rear_for_skill(id).display_name) and _text(card, GameUI._rear_skill_name(id)) and _text(card, GameUI._rear_bonuses_text(id, 1)), "A real offer directly exposes character, skill and actual attribute bonus: " + id)
		var purchase: Button = _ui._shop_focus_button("buy:%d" % index)
		_check(purchase != null and root.get_visible_rect().encloses(purchase.get_global_rect()), "Four rear offers retain visible purchase actions")
	_check(_signature(state) == before, "Constructing all companion cards is read-only")
	_ui._shop_focus_button("buy:0").pressed.emit()
	await _settle()
	var target: int = int(state.active_skills[0]["uid"])
	_ui._shop_focus_button("buy:1").pressed.emit()
	await _settle()
	var source: int = int(state.active_skills[1]["uid"])
	_ui._bag_grid.select_item(source)
	await _settle()
	var merge: Button = _ui._shop_focus_button("bag_merge:%d" % target)
	_check(merge != null and _text(_ui._bag_details, GameUI._rear_bonuses_text("pulse", 1)), "The actual selected UID displays its companion's pre-merge attributes")
	if merge != null:
		merge.pressed.emit()
		await _settle()
	_check(state.active_skills.size() == 1 and int(state.active_skills[0]["uid"]) == target and int(state.active_skills[0]["rank"]) == 2, "The real merge action preserves the target companion identity and upgrades its tier")
	_check(_text(_ui._bag_details, GameUI._rear_bonuses_text("pulse", 2)), "The merged companion details show the real upgraded attribute bonus")
	_ui._shop_focus_button("buy:2").pressed.emit()
	await _settle()
	var capacity := _ui.find_child("BackpackCapacity", true, false) as Label
	_check(capacity != null and capacity.text.contains("后排 2/2"), "The backpack reports actual companion capacity after real transactions")
	var blocked: Button = _ui._shop_focus_button("buy:3")
	_check(blocked != null and blocked.text == "后排已满 2/2" and not blocked.disabled, "A full rear party has a concrete visible purchase state and remains focusable")
	_ui.show_result(false, "试炼结束", {})
	await _settle()
	for item: Dictionary in state.active_skills:
		var row: Node = _ui.find_child("ResultItem_%d" % int(item["uid"]), true, false)
		_check(row != null and _icon(row, "skill", str(item["id"])) != null and _text(row, GameUI._rear_skill_name(str(item["id"]))) and _text(row, GameUI._rear_bonuses_text(str(item["id"]), int(item["rank"]))), "Settlement follows the actual companion UID, tier, skill and attributes")

func _test_hud() -> void:
	var state := RunState.new()
	state.begin(20261030, "bone", "reliquary", "alk")
	state.offers.assign([{"kind": "skill", "id": "pulse", "rank": 1, "price": 0}, {"kind": "skill", "id": "arc_slash", "rank": 1, "price": 0}])
	_check(state.buy_offer(0) and state.buy_offer(1), "The HUD fixture uses two genuinely purchased rear characters")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	_ui.bind(state)
	_ui.show_hud()
	_ui.update_hud(sim.snapshot())
	await _settle()
	_check((_ui._hud["hero"] as Control).visible and (_ui._hud["hero_key"] as Label).text == "R" and (_ui._hud["hero_label"] as Label).text == str(state.hero_skill_parameters()["name"]), "The main character owns a visible independent R skill")
	_check((_ui._hud["pulse_label"] as Label).text == HeroCatalog.rear_for_skill("pulse").display_name and (_ui._hud["secondary_label"] as Label).text == HeroCatalog.rear_for_skill("arc_slash").display_name, "Q and E identify the actual rear characters")
	var before: Dictionary = sim.snapshot()
	_check(sim.try_hero_skill(), "The real main-character cast starts its authoritative cooldown")
	_ui.update_hud(sim.snapshot())
	var progress: Array = [(_ui._hud["hero_bar"] as ProgressBar).value, (_ui._hud["hero_time"] as Label).text]
	await _settle()
	_check(progress == [(_ui._hud["hero_bar"] as ProgressBar).value, (_ui._hud["hero_time"] as Label).text] and _skill_clocks(sim.active_skill_snapshots()) == _skill_clocks(before["skills"]), "HUD never advances cooldowns itself and an attack buff cannot change rear cooldowns or identities")
	var bindings: Dictionary = ControlBindings.defaults()
	bindings["hero_skill"] = KEY_NUMLOCK
	_ui.set_controls(bindings)
	_check((_ui._hud["hero_key"] as Label).text == ControlBindings.key_label(KEY_NUMLOCK), "Rebinding the main skill refreshes the visible R slot without a simulation tick")
	_ui._on_input_device_changed("gamepad", 0)
	_check((_ui._hud["hero_key"] as Label).text == "RB" and (_ui._hud["pulse_key"] as Label).text == "X" and (_ui._hud["secondary_key"] as Label).text == "Y", "Input switching presents distinct fixed gamepad buttons for all three slots")
	_ui._on_input_device_changed("keyboard", -1)
	var value: Dictionary = sim.snapshot()
	var weapons: Array = []
	for index: int in 8:
		weapons.append(state.loadout[0].duplicate(true))
	value["loadout"] = weapons
	_ui.update_hud(value)
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		await _settle()
		var panel := _ui.find_child("RitualEquipment", true, false) as Control
		var abilities := _ui.find_child("RitualAbilities", true, false) as Control
		var slots: Control = _ui._hud["slots"]
		_check(slots.get_child_count() == 8 and panel.get_global_rect().grow(0.1).encloses(slots.get_global_rect()), "Eight icon-and-rank weapon slots remain visible beside the party")
		for key: String in ["pulse", "secondary", "hero"]:
			var card: Control = _ui._hud[key]
			_check(abilities.get_global_rect().grow(0.1).encloses(card.get_global_rect()) and root.get_visible_rect().encloses(card.get_global_rect()) and not card.get_global_rect().intersects(slots.get_global_rect()), "Right-hand Q/E/R cards fit without overlapping eight left-hand weapons: " + str(physical_size) + "/" + key)
	_ui.set_controls(ControlBindings.defaults())
	root.size = Vector2i(1280, 720)

func _skill_clocks(skills: Array) -> Array:
	var result: Array = []
	for skill: Dictionary in skills:
		result.append([skill.get("id"), skill.get("uid"), skill.get("ready"), skill.get("cooldown_remaining"), skill.get("cooldown_duration"), skill.get("uses")])
	return result
