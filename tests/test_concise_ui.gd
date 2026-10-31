extends SceneTree
## Map selection stays on the title page; concise guidance preserves actionable state.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_ui = GameUI.new()
	root.add_child(_ui)
	await _test_map_selection()
	await _test_contextual_guidance()
	_ui.queue_free()
	await process_frame
	await _test_live_hud_bounds()
	print("ConciseUI: %d assertions, %d failures" % [_checks, _failures])
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

func _button(name: String) -> Button:
	return _ui.find_child(name, true, false) as Button

func _label(name: String) -> Label:
	return _ui.find_child(name, true, false) as Label

func _visible_labels(node: Node) -> String:
	var text: String = ""
	if node is Label and node.is_visible_in_tree():
		text = node.text + "\n"
	for child: Node in node.get_children():
		text += _visible_labels(child)
	return text

func _test_map_selection() -> void:
	var state := RunState.new()
	state.begin(20261027, "bone")
	_ui.bind(state)
	_ui.set_selected_arena("unknown")
	_ui.show_title({})
	await _settle()
	_check(_ui.selected_arena() == "reliquary", "Unknown map choices normalize to the unchanged original arena")
	var before: String = JSON.stringify({"summary": state.summary(), "rng": str(state.rng.state)})
	var starts: Array[String] = []
	_ui.start_requested.connect(func(id: String) -> void: starts.append(id))
	for id: String in ArenaCatalog.IDS:
		var option: Button = _button("Arena_" + id)
		_check(option != null and option.focus_mode == Control.FOCUS_ALL and option.toggle_mode, "Each map exposes a focusable, explicitly selected card: " + id)
		var preview := _ui.find_child("ArenaPreview_" + id, true, false) as TextureRect
		_check(preview != null and preview.texture != null and preview.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Each selectable map uses the actual arena texture without blocking its button: " + id)
		option.grab_focus()
		await _key(KEY_ENTER)
		_check(_ui.selected_arena() == id and option.button_pressed, "Actual Enter selects the intended map without starting combat: " + id)
		var mark := option.find_child("SelectionMark", false, false) as Control
		_check(_label("ArenaName_" + id).text == str(ArenaCatalog.definition(id)["name"]) and mark != null and mark.mouse_filter == Control.MOUSE_FILTER_IGNORE and mark.focus_mode == Control.FOCUS_NONE and not mark.is_processing(), "Selection keeps the actual map name and a non-interactive check mark rather than descriptive copy: " + id)
		var selected: int = 0
		for other: String in ArenaCatalog.IDS:
			selected += 1 if _button("Arena_" + other).button_pressed else 0
		_check(selected == 1, "Selecting a map clears the other selected states: " + id)
	_check(starts.is_empty() and JSON.stringify({"summary": state.summary(), "rng": str(state.rng.state)}) == before, "Browsing maps changes neither a live run nor its random stream, and never starts combat")
	_ui._start()
	_check(starts == ["bone"] and _ui.selected_arena() == ArenaCatalog.IDS.back(), "Starting preserves the existing one-argument signal and makes the map separately available to Main")
	_ui.show_title({})
	await _settle()
	_check(_ui.selected_arena() == ArenaCatalog.IDS.back() and _button("Arena_" + ArenaCatalog.IDS.back()).button_pressed, "The chosen map survives returning to the title page")
	_ui._show_settings(false)
	await _settle()
	var focus: Control = root.gui_get_focus_owner()
	_button("Arena_mire").pressed.emit()
	_ui.set_selected_arena("glacier")
	_check(_ui.selected_arena() == ArenaCatalog.IDS.back() and root.gui_get_focus_owner() == focus, "A settings modal prevents map callbacks or setters from changing the background choice or focus")
	_ui.hide_pause()

	await _settle()
	_ui.set_selected_arena("mire")
	_check(_ui.selected_arena() == "mire" and _button("Arena_mire").button_pressed, "The explicit setter updates an existing title selector in place")
	var viewport := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var panel: Control = _ui.find_child("ArenaSelection", true, false)
	_check(viewport.encloses(panel.get_global_rect()), "The complete map selector fits the reference viewport")
	for id: String in ArenaCatalog.IDS:
		var option: Button = _button("Arena_" + id)
		option.grab_focus()
		await _settle()
		_check(panel.get_global_rect().encloses(option.get_global_rect()) and option.size.y >= 76, "The compact map card stays inside the left action panel at a readable size: " + id)
		var name: Label = _label("ArenaName_" + id)
		var effect: Label = _label("ArenaEffect_" + id)
		_check(option.get_global_rect().encloses(name.get_global_rect()) and effect == null and option.tooltip_text.is_empty(), "Map cards contain their name without terrain descriptions or explanatory tooltip: " + id)
	var no_small_copy: bool = _label("TitleControls") == null and _label("StarterDescription") == null
	for id: String in ["bone", "ember", "frost", "scatter"]:
		no_small_copy = no_small_copy and _label("StarterRole_" + id) == null
	var visible: String = _visible_labels(_ui)
	_check(no_small_copy and not visible.contains("THE LAST ALTAR") and not visible.contains("试炼守则") and not visible.contains("最佳记录") and not visible.contains("尚无记录"), "The title exposes choices and actions without descriptive small copy or empty records")

func _test_contextual_guidance() -> void:
	var state := RunState.new()
	state.begin(20261027, "bone", "mire")
	state.finish_wave()
	state.gold = 500
	state.offers = [{"kind": "rune", "id": "pierce", "price": state.shop_price(GameCatalog.rune("pierce")), "sold": false}]
	_check(state.buy_offer(0), "The rune guide fixture obtains a rune through the actual purchase transaction")
	var uid: int = int(state.rune_bag[0]["uid"])
	state.generate_shop()
	_ui.bind(state)
	_ui.show_shop()
	await _settle()
	_check(not _label("RuneGuide").visible and _label("RuneGuide").text.is_empty(), "The default shop no longer repeats general inventory rules above its cards")
	_check(_label("BackpackFootprint").text.begins_with("占格") and not _label("BackpackFootprint").text.contains("编号"), "Selected items show their footprint without an internal UID")
	_check(_button("MoveBackpackItem").tooltip_text.contains("方向键") and _button("MoveBackpackItem").tooltip_text.contains("Enter"), "Keyboard placement instructions remain available on the actual move action")
	_ui._bp_select(uid, _ui._shop_epoch)
	_check(_label("RuneGuide").visible and _label("RuneGuide").text.contains(GameCatalog.rune("pierce").display_name), "Selecting a rune reveals its contextual behavior rather than a generic instruction")
	_ui._bp_select(int(state.loadout[0]["uid"]), _ui._shop_epoch)
	_check(not _label("RuneGuide").visible, "Leaving rune selection removes the contextual line and its extra height")
	_ui.show_hud()
	_ui.update_hud({"health": 100, "max_health": 100, "loadout": state.loadout, "arena_name": "沉沼遗庭", "terrain_name": "", "terrain_multiplier": 1.0})
	_check(not _ui._hud.has("bag_info") and _ui.find_child("HUDMapInfo", true, false) == null, "The battle HUD has no lower-right text column")
	_ui.update_hud({"health": 100, "max_health": 100, "loadout": state.loadout, "arena_name": "沉沼遗庭", "terrain_name": "泥潭", "terrain_multiplier": 0.72})
	_check(not _visible_labels(_ui._page).contains("泥潭") and not _visible_labels(_ui._page).contains("Esc暂停"), "Entering terrain never recreates the removed lower-right description")
	_ui.show_pause()
	_check(not _visible_labels(_ui).contains("余烬尚未熄灭"), "Pause focuses on actions without an extra slogan")
	_ui.hide_pause()

func _test_live_hud_bounds() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var app = main_scene.instantiate()
	app.store.persistent = false
	root.add_child(app)
	await _settle()
	# Exercise Main's real begin/world/HUD signal path. The controlled budget only
	# supplies legal inventory sizes; this is a layout test, not an economy run.
	app.args = PackedStringArray(["--smoke"])
	app.set_process(false)
	for arena_id: String in ArenaCatalog.IDS:
		for count: int in [1, 8, 10]:
			app.ui.set_selected_arena(arena_id)
			app._begin_run("bone", 20261027)
			app.world.set_physics_process(false)
			var state: RunState = app.run
			state.gold = 10000
			if count > 8:
				_check(app.run.expand_backpack(), "Large HUD inventory legally expands before buying extra weapons")
			for index: int in range(1, count):
				state.offers = [{"kind": "weapon", "id": "bone", "price": state.shop_price(GameCatalog.weapon("bone")), "sold": false}]
				_check(app.run.buy_offer(0), "HUD inventory uses actual weapon purchases")
			if count > 1:
				app.world.begin(app.run)
			app.world.sim._spawn_timer = 9999.0
			app.world.sim._cooldowns.fill(9999.0)
			var definition: Dictionary = ArenaCatalog.definition(arena_id)
			var terrain_point: Vector2 = CombatSim.ARENA.get_center()
			if not (definition["zones"] as Array).is_empty():
				var point: Array = definition["zones"][0]["center"]
				terrain_point = Vector2(float(point[0]), float(point[1]))
			for phase: int in 3:
				app.world.sim.player_position = terrain_point if phase == 1 else CombatSim.ARENA.get_center()
				var no_small_copy: bool = true
				var notice_suppressed: bool = true
				var slots_contained: bool = true
				var active_counts_match: bool = true
				for frame: int in 20:
					app.world._physics_process(1.0 / 60.0)
					await process_frame
					if frame < 5:
						continue
					var panel: Control = app.ui.find_child("RitualEquipment", true, false)
					app.ui.notify("试炼开始 · 地图与地形说明")
					var slots: Control = app.ui._hud["slots"]
					no_small_copy = no_small_copy and not app.ui._hud.has("bag_info") and app.ui.find_child("HUDMapInfo", true, false) == null
					notice_suppressed = notice_suppressed and not app.ui._toast.visible and app.ui._toast.text.is_empty() and app.ui._toast_timer.is_stopped()
					active_counts_match = active_counts_match and state.loadout.size() == count
					for child: Node in slots.get_children():
						if child is Control:
							slots_contained = slots_contained and panel.get_global_rect().grow(-6).encloses(child.get_global_rect())
				var context: String = "%s / %d weapons / phase %d" % [arena_id, count, phase]
				_check(no_small_copy, "Repeated live Main HUD updates never recreate lower-right descriptions: " + context)
				_check(notice_suppressed, "Wave messages stay hidden beneath the health bar during live updates: " + context)
				_check(slots_contained, "Every visible equipment card and extra-weapons indicator stays in the panel: " + context)
				_check(active_counts_match, "Removing HUD descriptions preserves the actual active weapon count: " + context)
			app._title()
			await _settle()
	app.sound.shutdown()
	app.queue_free()
	await _settle()
