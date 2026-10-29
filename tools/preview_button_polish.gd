extends SceneTree
## Real UI fixtures with native draw states; no personal profile or simulated play.

const VIEWS: PackedStringArray = ["title", "settings", "controls", "pause", "shop", "poor", "locked", "sold", "upgrades", "hover", "pressed", "bag_focus", "bag_selected", "bag_valid", "bag_invalid"]

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var view: String = "title"
	var destination: String = "res://reports/buttons/title.png"
	var small: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=")
		elif argument == "--small":
			small = true
		else:
			quit(2)
			return
	if view not in VIEWS or DisplayServer.get_name() == "headless" or not destination.ends_with(".png"):
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(960, 540) if small else Vector2i(1280, 720)
	root.title = "秘术余烬 · 按钮固定验证（不保存档案）"
	var state := RunState.new()
	state.begin(2, "bone")
	state.gold = 1000
	if view.begins_with("bag_"):
		for kind: String in ["skill", "relic"]:
			state.offers.assign([{"kind": kind, "id": "pulse" if kind == "skill" else "damage", "price": 20, "sold": false}])
			assert(state.buy_offer(0))
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	if view in ["shop", "poor", "locked", "sold"] or view.begins_with("bag_"):
		state.offers.clear()
		for definition: ContentDef in GameCatalog.weapons():
			state.offers.append({"id": definition.id, "kind": "weapon", "price": state.shop_price(definition), "sold": false})
			if state.offers.size() == 4:
				break
		if view == "poor":
			state.gold = 0
		elif view == "locked":
			assert(state.set_offer_locked(0, true) and state.set_offer_locked(2, true))
		elif view == "sold":
			assert(state.buy_offer(1))
		ui.show_shop()
	elif view == "upgrades":
		state.collect_souls(102)
		ui.show_upgrades()
	else:
		ui.show_title({})
		if view == "settings":
			ui._show_settings(false)
		elif view == "controls":
			ui._show_controls(false)
		elif view == "pause":
			ui.show_pause()
	var cover := ui.find_child("MenuArtwork", true, false) as TitleCover
	if cover != null:
		cover.set_frame(0)
	await _settle()
	_move_pointer(Vector2(20, 20))
	await _settle()
	var bag_state: Dictionary = {}
	if view.begins_with("bag_"):
		var grid: BackpackGrid = ui._bag_grid
		var uid: int = int(state.loadout[0]["uid"])
		if view == "bag_focus":
			var item := grid.get_node("BackpackItem%d" % uid) as Button
			item.grab_focus()
			assert(item.has_focus())
		elif view == "bag_selected":
			grid.select_item(uid)
			root.gui_release_focus()
		else:
			grid.begin_placement(uid, false, Vector2i(5, 3 if view == "bag_invalid" else 0))
			assert(bool(grid.placement_at(grid.cursor).get("valid", false)) == (view == "bag_valid"))
		await _settle()
		bag_state = {"selected_uid": grid.selected_uid, "held_uid": grid.held_uid,
			"placement": grid.placement_at(grid.cursor) if grid.held_uid >= 0 else {},
			"focus": str(root.gui_get_focus_owner().name) if root.gui_get_focus_owner() != null else ""}
	var draw_mode: int = -1
	if view in ["hover", "pressed"]:
		root.gui_release_focus()
		var target: Button = _button_with_text(ui, "进入试炼")
		assert(target != null)
		var point: Vector2 = target.get_global_rect().get_center()
		_move_pointer(point)
		await _settle()
		if view == "pressed":
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.position = point
			down.global_position = point
			down.pressed = true
			root.push_input(down, false)
			await _settle()
		draw_mode = target.get_draw_mode()
		assert(draw_mode == BaseButton.DRAW_HOVER if view == "hover" else draw_mode in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED])
	var before: String = JSON.stringify([state.summary(), state.backpack_snapshot(), str(state.rng.state)])
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var result: Error = image.save_png(ProjectSettings.globalize_path(destination))
	var unchanged: bool = before == JSON.stringify([state.summary(), state.backpack_snapshot(), str(state.rng.state)])
	print("BUTTON_PREVIEW ", JSON.stringify({"view": view, "capture": destination, "capture_result": result,
		"state_unchanged_while_drawing": unchanged, "personal_profile_io": false, "fixed_fixture": true,
		"window_size": [root.size.x, root.size.y], "viewport_capture_size": [image.get_width(), image.get_height()], "actual_button_draw_mode": draw_mode, "bag_state": bag_state}))
	quit(0 if result == OK and unchanged else 1)

func _move_pointer(point: Vector2) -> void:
	root.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, false)

func _button_with_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _button_with_text(child, text)
		if found != null:
			return found
	return null

func _settle() -> void:
	for frame: int in 5:
		await process_frame
