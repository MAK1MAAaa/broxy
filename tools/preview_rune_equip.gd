extends SceneTree
## Production purchase/equip fixtures for the read-only rune socket preview.

const CASES: PackedStringArray = ["crescent-blast", "crescent-bounce", "full-swap", "volley", "shop"]


func _initialize() -> void:
	_preview.call_deferred()


static func weapon_index(case_name: String) -> int:
	return 2 if case_name == "volley" else 1


static func make_state(case_name: String) -> RunState:
	if case_name not in CASES:
		return null
	var state := RunState.new()
	state.begin(20261025, "bone")
	var purchases: Array[Dictionary] = []
	for id: String in ["crescent", "storm", "scatter"]:
		purchases.append({"kind": "weapon", "definition": GameCatalog.weapon(id), "equip": -1})
	for slot: int in 4:
		if slot == 1 and case_name in ["crescent-blast", "crescent-bounce"]:
			continue
		var rune: String = "blast" if slot == 1 else "bounce" if slot == 3 else "pierce"
		purchases.append({"kind": "rune", "definition": GameCatalog.rune(rune), "equip": slot})
	var incoming: String = "blast" if case_name in ["crescent-blast", "volley"] else "bounce"
	for id: String in [incoming, "pierce", "blast", "bounce"]:
		purchases.append({"kind": "rune", "definition": GameCatalog.rune(id), "equip": -1})
	for definition: ContentDef in GameCatalog.relics():
		purchases.append({"kind": "relic", "definition": definition, "equip": -1})
	var budget: int = 120
	for purchase: Dictionary in purchases:
		var definition: ContentDef = purchase["definition"]
		budget += definition.price
	state.collect_souls(budget)
	for purchase: Dictionary in purchases:
		var definition: ContentDef = purchase["definition"]
		state.offers = [{"kind": purchase["kind"], "id": definition.id, "price": definition.price, "sold": false}]
		if not state.buy_offer(0):
			push_error("Rune fixture purchase failed: " + state.last_error)
			return null
		if int(purchase["equip"]) >= 0 and not state.equip_rune(0, int(purchase["equip"])):
			push_error("Rune fixture equip failed: " + state.last_error)
			return null
	state.wave = 4
	state.pending_upgrades = 0
	state.offers.clear()
	for entry: Array in [["weapon", "crescent"], ["rune", "blast"], ["relic", "hourglass"], ["relic", "moon_charm"]]:
		var kind: String = str(entry[0])
		var definition: ContentDef = GameCatalog.weapon(str(entry[1])) if kind == "weapon" else GameCatalog.rune(str(entry[1])) if kind == "rune" else GameCatalog.relic(str(entry[1]))
		state.offers.append({"kind": kind, "id": definition.id, "price": definition.price, "sold": false})
	return state


func _preview() -> void:
	var case_name: String = "crescent-blast"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
	if case_name not in CASES or (not destination.is_empty() and not destination.to_lower().ends_with(".png")):
		push_error("Use --case=crescent-blast|crescent-bounce|full-swap|volley|shop and optional --capture=<path.png>")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var app: Node = load("res://scenes/main.tscn").instantiate()
	app.store.persistent = false
	root.add_child(app)
	await process_frame
	app.args.append("--autoplay")
	app._screenshot_clock = -1.0
	app.world.stop()
	app.sound.set_volume(0.0)
	var state: RunState = make_state(case_name)
	if state == null:
		app._quit_game(1)
		return
	app.run = state
	app.ui.bind(state)
	app.screen = 3
	app.ui.show_shop()
	root.title = "秘术余烬 · 符文预览 / %s（固定场景，不写档案）" % case_name
	var layer := CanvasLayer.new()
	layer.layer = 12
	app.add_child(layer)
	var note: Label = app.ui._label("符文装入固定陈列 · 正式购买/装配 · 真实 Enter 打开 · 不写档案", 12, GameUI.CYAN)
	note.theme = app.ui._make_theme()
	note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.offset_top = 2
	note.offset_bottom = 20
	layer.add_child(note)
	for frame: int in 4:
		await process_frame
	var original: String = JSON.stringify([state.summary(), state.offers, state.rng.state, state.last_error])
	var bag_button: Button = app.ui._shop_focus_button("rune:%d" % int(state.rune_bag[0]["uid"]))
	if bag_button == null:
		push_error("Rune fixture has no incoming rune action")
		app._quit_game(1)
		return
	bag_button.grab_focus()
	_key(KEY_ENTER)
	for frame: int in 4:
		await process_frame
	if case_name != "shop":
		var source: Button = app.ui._shop_focus_button("rune_preview:%d" % weapon_index(case_name))
		if source == null:
			push_error("Rune fixture has no preview action")
			app._quit_game(1)
			return
		source.grab_focus()
		_key(KEY_ENTER)
		for frame: int in 4:
			await process_frame
		if app.ui._overlay_mode != "rune_equip_comparison":
			push_error("Rune fixture did not open its preview")
			app._quit_game(1)
			return
	if JSON.stringify([state.summary(), state.offers, state.rng.state, state.last_error]) != original:
		push_error("Rune preview changed production state")
		app._quit_game(1)
		return
	if destination.is_empty():
		print("RUNE_EQUIP_PREVIEW case=", case_name, " persistent=false capture=interactive")
		return
	await RenderingServer.frame_post_draw
	var result: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination).get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(destination)
	print("RUNE_EQUIP_PREVIEW case=", case_name, " result=", result, " output=", destination, " persistent=false")
	app._quit_game(0 if result == OK else 1)


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, false)
