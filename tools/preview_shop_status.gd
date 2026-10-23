extends SceneTree
## Fixed inventory and budget; no Main, GameStore or player profile.


func _initialize() -> void:
	_preview.call_deferred()


func _preview() -> void:
	var view: String = "full"
	var stage: String = "after"
	var hold: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--stage="):
			stage = argument.trim_prefix("--stage=")
		elif argument == "--hold":
			hold = true
		else:
			quit(2)
			return
	if view not in ["full", "poor"] or stage not in ["before", "after"] or DisplayServer.get_name() == "headless":
		push_error("Use native rendering, --view=full|poor, --stage=before|after and optional --hold")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 购买条件验证（固定场景，非实际对局）"
	var state := RunState.new()
	state.begin(4, "bone")
	state.gold = 2000
	for id: String in ["frost", "ember", "scatter"]:
		_purchase(state, "weapon", id)
	for index: int in 3:
		_purchase(state, "rune", ["pierce", "bounce", "blast"][index])
		assert(state.equip_rune(0, index))
	for id: String in ["pierce", "bounce", "blast", "pierce"]:
		_purchase(state, "rune", id)
	for id: String in ["damage", "haste", "speed", "vitality", "armor", "magnet"]:
		for layer: int in (3 if id == "damage" else 2):
			_purchase(state, "relic", id)
	state.gold = 5 if view == "poor" else 100
	state.offers = [
		{"id": "scatter", "kind": "weapon", "price": 28, "sold": false},
		{"id": "blast", "kind": "rune", "price": 18, "sold": false},
		{"id": "damage", "kind": "relic", "price": 20, "sold": false},
		{"id": "vitality", "kind": "relic", "price": 22, "sold": false},
	]
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_shop()
	var caption := Label.new()
	caption.text = "固定购买条件验证 · 非实际对局 · " + view
	caption.position = Vector2(810, 5)
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", GameUI.MUTED)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui._root.add_child(caption)
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var destination: String = "res://reports/shop-status-" + stage + "-" + view + ".png"
	var result: Error = root.get_texture().get_image().save_png(destination)
	print("SHOP_STATUS_PREVIEW view=", view, " stage=", stage, " result=", result, " persistent=false gold=", state.gold)
	if not hold:
		quit(0 if result == OK else 1)


func _purchase(state: RunState, kind: String, id: String) -> void:
	var definition: ContentDef = GameCatalog.weapon(id) if kind == "weapon" else (GameCatalog.rune(id) if kind == "rune" else GameCatalog.relic(id))
	state.offers = [{"id": id, "kind": kind, "price": state.shop_price(definition), "sold": false}]
	assert(state.buy_offer(0))
