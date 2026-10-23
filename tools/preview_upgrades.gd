extends SceneTree
## Actual upgrade choices from a fixed state; no Main/GameStore or personal progression.

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "base"
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
			push_error("Use --view=base|boosted|sequence, --capture=path and optional --hold")
			quit(2)
			return
	if view not in ["base", "boosted", "sequence"] or DisplayServer.get_name() == "headless":
		push_error("Upgrade preview requires native rendering and a supported view")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 强化信息验证（固定场景，非实际对局）"
	var state := RunState.new()
	state.begin(7 if view == "boosted" else 2, "bone")
	# The fixed preview budget is used only to obtain relics through formal purchases.
	if view == "boosted":
		state.gold = 1000
		for id: String in ["damage", "haste", "speed", "vitality", "armor", "magnet"]:
			for layer: int in 3:
				var definition: ContentDef = GameCatalog.relic(id)
				state.offers = [{"id": id, "kind": "relic", "price": state.shop_price(definition), "sold": false}]
				assert(state.buy_offer(0))
	state.collect_souls(102)
	assert(state.pending_upgrades == 2)
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_upgrades()
	ui.upgrades_finished.connect(func() -> void:
		state.generate_shop()
		ui.show_shop()
		ui.notify("固定强化验证已完成两次选择，已进入商店。")
		print("UPGRADE_PREVIEW_COMPLETE ", JSON.stringify(state.summary()))
	)
	ui.feedback.connect(func(sound: String) -> void:
		if sound == "level":
			print("UPGRADE_PREVIEW_CHOICE ", JSON.stringify({"pending": state.pending_upgrades, "stats": _stats(state)}))
	)
	var caption := Label.new()
	caption.text = "固定强化验证 · 非实际对局 · " + view
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
		destination = "res://reports/upgrades-" + view + ".png"
	var result: Error = root.get_texture().get_image().save_png(destination)
	print("UPGRADE_PREVIEW view=", view, " result=", result, " persistent=false choices=", JSON.stringify(state.upgrade_choices()))
	if not hold:
		quit(0 if result == OK else 1)

func _stats(state: RunState) -> Dictionary:
	var result: Dictionary = {}
	for key: String in RunState.BASE_STATS:
		result[key] = state.stat(key)
	return result
