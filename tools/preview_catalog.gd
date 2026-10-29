extends SceneTree
## Real inventory fixtures, with explicit synthetic damage history and no profile I/O.

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "result"
	var destination: String = "res://reports/world-flipper-catalog/preview-result.png"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		else:
			quit(2)
			return
	if view not in ["result", "shop"] or DisplayServer.get_name() == "headless" or not destination.ends_with(".png"):
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	var state := RunState.new()
	state.begin(20261030, "bone")
	state.gold = 1000
	for item: Dictionary in [{"kind": "relic", "id": "haste"}, {"kind": "skill", "id": "pulse"}, {"kind": "rune", "id": "pierce"}]:
		state.offers.assign([{"kind": item.kind, "id": item.id, "price": 20, "sold": false}])
		assert(state.buy_offer(0))
	assert(state.equip_rune(0, 0))
	state.offers.assign([{"kind": "rune", "id": "bounce", "price": 20, "sold": false}])
	assert(state.buy_offer(0))
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	if view == "result":
		for index: int in GameCatalog.weapons().size():
			state.damage_dealt_by_weapon[GameCatalog.weapons()[index].id] = 100.0 + 20.0 * index
		ui.show_result(true, "击败首领", {})
	else:
		state.offers.clear()
		for item: Dictionary in [{"kind": "weapon", "id": "scatter"}, {"kind": "relic", "id": "moon_charm"}, {"kind": "rune", "id": "blast"}, {"kind": "skill", "id": "arc_slash"}]:
			state.offers.append({"kind": item.kind, "id": item.id, "price": 20, "sold": false})
		ui.show_shop()
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination).get_base_dir())
	if error == OK:
		error = root.get_texture().get_image().save_png(destination)
	print("CATALOG_PREVIEW view=%s result=%d profile_io=false synthetic_damage_history=%s" % [view, error, view == "result"])
	quit(0 if error == OK else 1)
