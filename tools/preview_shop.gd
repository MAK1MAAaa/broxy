extends SceneTree
## Fixed shop fixtures; never instantiate Main or read/write player progression.

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "boosted"
	var destination: String = ""
	var hold: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			hold = true
		else:
			push_error("Use --view=base|boosted|fullbag|transactions, optional --capture=path and --hold")
			quit(2)
			return
	if view not in ["base", "boosted", "fullbag", "transactions"] or DisplayServer.get_name() == "headless":
		push_error("Shop preview requires native rendering and a supported view")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 商店信息验证（固定场景，非实际对局）"
	var state := RunState.new()
	state.begin(4, "bone")
	# A fixture budget supplies inventory through the public transaction API.
	state.gold = 1000
	if view in ["boosted", "fullbag"]:
		for id: String in ["damage", "haste"]:
			for layer: int in 3:
				_purchase(state, "relic", id)
	if view == "fullbag":
		for id: String in ["speed", "vitality", "armor", "magnet"]:
			for layer: int in 3:
				_purchase(state, "relic", id)
		for id: String in ["frost", "ember", "scatter"]:
			_purchase(state, "weapon", id)
		for index: int in 4:
			_purchase(state, "rune", ["pierce", "bounce", "blast", "pierce"][index])
			assert(state.equip_rune(0, index))
		for id: String in ["pierce", "bounce", "blast", "pierce"]:
			_purchase(state, "rune", id)
	state.offers.clear()
	for definition: ContentDef in GameCatalog.weapons():
		state.offers.append({"id": definition.id, "kind": "weapon", "price": state.shop_price(definition), "sold": false})
	if view == "transactions":
		state.offers = [
			{"id": "frost", "kind": "weapon", "price": 24, "sold": false},
			{"id": "pierce", "kind": "rune", "price": 18, "sold": false},
			{"id": "damage", "kind": "relic", "price": 20, "sold": false},
			{"id": "haste", "kind": "relic", "price": 20, "sold": false},
		]
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_shop()
	if view == "fullbag":
		ui._select_rune(1)
	var caption := Label.new()
	caption.text = "固定商店验证 · 非实际对局 · " + view
	caption.position = Vector2(810, 5)
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", GameUI.MUTED)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui._root.add_child(caption)
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if destination.is_empty():
		destination = "res://reports/shop-" + view + ".png"
	var result: Error = root.get_texture().get_image().save_png(destination)
	print("SHOP_PREVIEW view=", view, " result=", result, " persistent=false damage=", state.stat("damage"), " attack_speed=", state.stat("attack_speed"))
	if not hold:
		quit(0 if result == OK else 1)

func _purchase(state: RunState, kind: String, id: String) -> void:
	var definition: ContentDef = GameCatalog.weapon(id) if kind == "weapon" else (GameCatalog.rune(id) if kind == "rune" else GameCatalog.relic(id))
	state.offers = [{"id": id, "kind": kind, "price": state.shop_price(definition), "sold": false}]
	assert(state.buy_offer(0))
