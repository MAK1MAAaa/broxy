extends SceneTree
## Native full-build reservation fixtures; never read or write personal profiles.

const BUILD_FIXTURE = preload("res://tools/preview_rune_equip.gd")
const CASES: PackedStringArray = ["full", "repriced", "bought"]


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var case_name: String = "full"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
	if case_name not in CASES or (not destination.is_empty() and not destination.to_lower().ends_with(".png")):
		push_error("Use --case=full|repriced|bought and optional --capture=<path.png>")
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
	var state: RunState = BUILD_FIXTURE.make_state("full-swap")
	if state == null:
		app._quit_game(1)
		return
	for offer: Dictionary in state.offers:
		var definition: ContentDef = GameCatalog.weapon(str(offer["id"])) if offer["kind"] == "weapon" else GameCatalog.rune(str(offer["id"])) if offer["kind"] == "rune" else GameCatalog.relic(str(offer["id"]))
		offer["price"] = state.shop_price(definition)
	app.run = state
	app.ui.bind(state)
	app.screen = 3
	app.ui.show_shop()
	root.title = "秘术余烬 · 商店保留 / %s（固定场景，不写档案）" % case_name
	var layer := CanvasLayer.new()
	layer.layer = 12
	app.add_child(layer)
	var note: Label = app.ui._label("商店保留固定陈列 · 正式购买/装配 · 真实 Enter 操作 · 不写档案", 12, GameUI.CYAN)
	note.theme = app.ui._make_theme()
	note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.offset_top = 2
	note.offset_bottom = 20
	layer.add_child(note)
	await _settle()
	var passed: bool = await _activate(app.ui, "rune:%d" % int(state.rune_bag[0]["uid"]))
	passed = await _activate(app.ui, "lock:0") and passed
	passed = await _activate(app.ui, "lock:2") and passed
	var before: Array[Dictionary] = state.offers.duplicate(true)
	var wallet: int = state.gold
	var random_state: int = state.rng.state
	passed = passed and state.locked_offer_count() == 2 and state.loadout.size() == 4 and state.rune_bag.size() == 4 and state.relic_counts.size() == GameCatalog.relics().size()
	if case_name in ["repriced", "bought"]:
		state.next_wave()
		state.generate_shop()
		app.ui.show_shop()
		await _settle()
		passed = passed and state.gold == wallet and state.rng.state != random_state
		for slot: int in [0, 2]:
			passed = passed and state.is_offer_locked(slot) and state.offers[slot]["id"] == before[slot]["id"] and int(state.offers[slot]["price"]) > int(before[slot]["price"])
	if case_name == "bought":
		var price: int = int(state.offers[2]["price"])
		passed = await _activate(app.ui, "buy:2") and passed
		passed = passed and state.offers[2]["sold"] and not state.is_offer_locked(2) and state.is_offer_locked(0) and state.gold == wallet - price and int(state.relic_counts["hourglass"]) == 2
	var record: Dictionary = {"case": case_name, "fixture_passed": passed, "wave": state.wave, "gold": state.gold, "locked": state.locked_offer_count(), "offers": state.offers, "locked_slots": [], "persistent": app.store.persistent, "viewport": [root.size.x, root.size.y]}
	for slot: int in state.offers.size():
		if state.is_offer_locked(slot):
			record["locked_slots"].append(slot)
	if not passed:
		push_error("The shop reservation fixture failed")
	if destination.is_empty():
		print("SHOP_LOCK_PREVIEW ", JSON.stringify(record))
		return
	await create_timer(3.1).timeout
	await RenderingServer.frame_post_draw
	var result: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination).get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(destination)
	record["capture_result"] = result
	print("SHOP_LOCK_PREVIEW ", JSON.stringify(record))
	app._quit_game(0 if result == OK and passed else 1)


func _activate(ui: GameUI, id: String) -> bool:
	var source: Button = ui._shop_focus_button(id)
	if source == null or source.disabled:
		push_error("Missing fixture action: " + id)
		return false
	source.grab_focus()
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		root.push_input(event, false)
	await _settle()
	return true


func _settle() -> void:
	for frame: int in 4:
		await process_frame
