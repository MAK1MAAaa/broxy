extends SceneTree
## Fixed purchase fixtures for the native comparison dialog; never accesses a profile.
## The legacy capped argument now means a physically full backpack, not a relic ownership limit.

const CASES: PackedStringArray = ["tradeoff", "bulwark", "capped", "poor"]


func _initialize() -> void:
	_preview.call_deferred()


static func make_state(case_name: String) -> RunState:
	if case_name not in CASES:
		return null
	var state := RunState.new()
	state.begin(20261024, "bone")
	var purchases: Array[Dictionary] = []
	for id: String in ["frost", "ember", "scatter"]:
		purchases.append({"kind": "weapon", "definition": GameCatalog.weapon(id)})
	for id: String in ["blast", "pierce", "bounce"]:
		purchases.append({"kind": "rune", "definition": GameCatalog.rune(id)})
	for definition: ContentDef in GameCatalog.relics():
		purchases.append({"kind": "relic", "definition": definition})
	var fillers: int = 4 if case_name == "capped" else 0
	var budget: int = (7 if case_name == "poor" else 120) + 80 + fillers * GameCatalog.rune("pierce").price
	for purchase: Dictionary in purchases:
		var definition: ContentDef = purchase["definition"]
		budget += definition.price
	state.collect_souls(budget)
	if not state.expand_backpack() or not state.expand_backpack():
		push_error("Comparison fixture expansion failed: " + state.last_error)
		return null
	var rune_slot: int = 1
	for purchase: Dictionary in purchases:
		var definition: ContentDef = purchase["definition"]
		state.offers = [{"kind": purchase["kind"], "id": definition.id, "price": definition.price, "sold": false}]
		if not state.buy_offer(0):
			push_error("Comparison fixture purchase failed: " + state.last_error)
			return null
		if str(purchase["kind"]) == "rune":
			if not state.equip_rune(0, rune_slot):
				push_error("Comparison fixture equip failed: " + state.last_error)
				return null
			rune_slot += 1
	for filler: int in fillers:
		var definition: ContentDef = GameCatalog.rune("pierce")
		state.offers = [{"kind": "rune", "id": definition.id, "price": definition.price, "sold": false}]
		if not state.buy_offer(0):
			push_error("Comparison full-backpack fixture purchase failed: " + state.last_error)
			return null
	if case_name == "capped":
		var snapshot: Dictionary = state.backpack_snapshot()
		if snapshot["used_cells"] != snapshot["total_cells"]:
			push_error("The capped comparison fixture must occupy every real backpack cell")
			return null
	state.wave = 4
	state.pending_upgrades = 0
	if case_name == "bulwark":
		state.take_damage(37.0, "chaser", "contact")
	var target: String = "bulwark" if case_name == "bulwark" else "hourglass"
	state.offers.clear()
	for entry: Array in [["relic", target], ["weapon", "crescent"], ["relic", "moon_charm"], ["relic", "bulwark"]]:
		var kind: String = str(entry[0])
		var definition: ContentDef = GameCatalog.weapon(str(entry[1])) if kind == "weapon" else GameCatalog.relic(str(entry[1]))
		state.offers.append({"kind": kind, "id": definition.id, "price": definition.price, "sold": false})
	return state


func _preview() -> void:
	var case_name: String = "tradeoff"
	var destination: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
	if case_name not in CASES or (not destination.is_empty() and not destination.to_lower().ends_with(".png")):
		push_error("Use --case=tradeoff|bulwark|capped|poor and optional --capture=<path.png>; capped means a full backpack")
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
	var case_label: String = "capped：背包空间已满" if case_name == "capped" else case_name
	root.title = "秘术余烬 · 遗物对照 / %s（固定场景，不写档案）" % case_label
	var layer := CanvasLayer.new()
	layer.layer = 12
	app.add_child(layer)
	var note: Label = app.ui._label("遗物对照固定陈列 · 正式购买构筑 · " + case_label + " · 不写档案", 12, GameUI.CYAN)
	note.theme = app.ui._make_theme()
	note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.offset_top = 2
	note.offset_bottom = 20
	layer.add_child(note)
	for frame: int in 4:
		await process_frame
	var source: Button = app.ui._shop_focus_button("compare:0")
	if source == null:
		push_error("The fixture has no comparison source")
		app._quit_game(1)
		return
	var before: String = JSON.stringify([state.summary(), state.offers, state.rng.state, state.last_error])
	source.grab_focus()
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		root.push_input(event, false)
	for frame: int in 4:
		await process_frame
	if app.ui._overlay_mode != "relic_comparison" or JSON.stringify([state.summary(), state.offers, state.rng.state, state.last_error]) != before:
		push_error("The comparison fixture did not open read-only")
		app._quit_game(1)
		return
	if destination.is_empty():
		print("RELIC_COMPARISON_PREVIEW case=", case_name, " persistent=false capture=interactive")
		return
	await RenderingServer.frame_post_draw
	var result: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination).get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(destination)
	print("RELIC_COMPARISON_PREVIEW case=", case_name, " result=", result, " output=", destination, " persistent=false")
	app._quit_game(0 if result == OK else 1)
