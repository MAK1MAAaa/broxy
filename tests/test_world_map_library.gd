extends SceneTree
## All compiled layers, bounded paging, real selection and combat integration.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_all_layers()
	_test_combat_layers()
	_test_browser_focus_identity()
	await _test_browser()
	print("WorldMapLibrary: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame: int in 5:
		await process_frame


func _test_all_layers() -> void:
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WorldMapCatalog.SOURCE_PATH))
	var layouts: Dictionary = {}
	var seen_shapes: Dictionary = {}
	var seen_images: Dictionary = {}
	var available: int = 0
	_check(ArenaCatalog.IDS.size() == 10 and WorldMapCatalog.ids().size() > 10, "The paged library adds source-bound maps without changing the ten authored arenas")
	for row: Dictionary in library["entries"]:
		layouts[row["canonical_layout_id"]] = true
		var id: String = str(row["id"])
		if not bool(row["playable"]):
			_check(not ArenaCatalog.contains(id) and ArenaCatalog.normalize_id(id) == "reliquary", "An unresolved layer cannot start a substitute arena: " + id)
			continue
		available += 1
		_check(ArenaCatalog.normalize_id(id) == id and ArenaCatalog.is_source_stage(id), "A playable original layer keeps its exact identity: " + id)
		var bounds: Rect2 = ArenaCatalog.play_bounds(id)
		var source: Rect2 = WorldMapCatalog.source_rect(id)
		_check(ArenaCatalog.WORLD_BOUNDS.encloses(bounds) and bounds.get_center().is_equal_approx(ArenaCatalog.WORLD_BOUNDS.get_center()) and bounds.size == source.size * 4.0, "Source pixels use uniform 4x scale within the combat world: " + id)
		var info: Dictionary = ArenaCatalog.stage_info(id)
		_check(info["layout_id"] == row["canonical_layout_id"] and info["field_id"] == row["field_id"] and int(info["layer_index"]) == int(row["stage"]["layer_index"]), "Background, canonical identity and source layer remain bound: " + id)
		var camera: Rect2 = ArenaCatalog.visible_rect_for(id, bounds.get_center())
		_check(camera.size == Vector2(1280, 720) and camera.get_center().is_finite(), "Source-layer camera preserves the reference viewport: " + id)
		if not seen_images.has(row["image_ref"]):
			seen_images[row["image_ref"]] = true
			var preview := WorldMapCatalog.preview_texture(id) as AtlasTexture
			_check(preview != null and preview.atlas != null and preview.region == source and Rect2(Vector2.ZERO, preview.atlas.get_size()).encloses(source), "Every selected native plane imports with its exact source crop: " + id)
		var geometry_id: String = str(row["geometry_ref"])
		if seen_shapes.has(geometry_id):
			continue
		seen_shapes[geometry_id] = true
		var walls: Array[Dictionary] = ArenaCatalog.wall_geometry(id)
		var field := ArenaObstacles.new()
		field.bounds = bounds
		_check(field.configure_walls(walls) and walls.size() == int(info["wall_segment_count"]), "All original open segments configure without inferred closure: " + id)
		var point: Vector2 = field.free_point(bounds.get_center(), 16.0, 16.0)
		_check(point.is_finite() and field.is_free(point, 16.0), "Every enabled layer supplies a valid initial player position: " + id)
	_check(layouts.size() == 1422 and available == WorldMapCatalog.ids().size(), "The index keeps all1422 canonical layouts and exposes only playable layers")
	var grouped: int = 0
	for group: Dictionary in WorldMapCatalog.groups():
		grouped += WorldMapCatalog.group_ids(str(group["id"])).size()
	_check(grouped == available, "Chapter and event groups partition every available layer once")
	_check(not WorldMapCatalog.contains("wf_invalid_l0"), "Unknown source IDs fail closed")


func _test_combat_layers() -> void:
	var sampled: Dictionary = {}
	for id: String in WorldMapCatalog.ids():
		var row: Dictionary = WorldMapCatalog.entry(id)
		var group: String = str(row["group"])
		if sampled.has(group) or sampled.size() >= 14:
			continue
		sampled[group] = true
		var state := RunState.new()
		state.begin(20261031, "bone", id)
		var sim := CombatSim.new()
		sim.begin(state)
		sim.sandbox = true
		sim._cooldowns.fill(9999.0)
		_check(state.arena_id == id and sim.obstacles.bounds == ArenaCatalog.play_bounds(id), "Production run and collision use the selected layer: " + id)
		var initial: Vector2 = sim.player_position
		for frame: int in 60:
			sim.step(1.0 / 60.0, Vector2.RIGHT)
		_check(sim.player_position.is_finite() and sim.obstacles.is_free(sim.player_position, 16.0) and sim.obstacles.bounds.has_point(sim.player_position), "Actual movement stays inside the selected original terrain: " + id)
		_check(initial != Vector2.INF and sim.obstacles.walls.snapshot().size() == ArenaCatalog.wall_geometry(id).size(), "Runtime retains the complete selected open-wall set: " + id)


func _test_browser_focus_identity() -> void:
	var preview: Node = load("res://scripts/diagnostics/wf_actions_preview.gd").new()
	var browser := WorldMapBrowser.new()
	var group := HBoxContainer.new()
	var search := LineEdit.new()
	search.name = "MapSearch"
	browser.add_child(group)
	group.add_child(search)
	var before: Dictionary = preview._browser_focus_signature(browser, search)
	group.name = "DifferentAutomaticParent"
	browser.name = "DifferentBrowserAncestor"
	_check(before == preview._browser_focus_signature(browser, search), "Browser focus identity ignores automatic ancestor names")
	var chapter := OptionButton.new()
	chapter.name = "MapChapter"
	group.add_child(chapter)
	_check(before != preview._browser_focus_signature(browser, chapter), "Browser focus identity distinguishes live controls")
	var outside := Button.new()
	_check(preview._browser_focus_signature(browser, outside)["scope"] == "outside", "Focus outside the browser remains observable")
	_check(preview._browser_focus_signature(browser, null)["scope"] == "none", "Missing focus remains observable")
	outside.free()
	browser.free()
	preview.free()


func _test_browser() -> void:
	var ui := GameUI.new()
	root.add_child(ui)
	ui.show_title({})
	await _settle()
	var opener := ui.find_child("TitleWorldMaps", true, false) as Button
	opener.grab_focus()
	opener.pressed.emit()
	await _settle()
	var browser := ui.find_child("WorldMapBrowser", true, false) as WorldMapBrowser
	_check(browser != null and ui._overlay_mode == "world_maps", "Title opens a dedicated source-map modal")
	if browser == null:
		ui.queue_free()
		return
	_check(browser._grid.get_child_count() <= WorldMapCatalog.PAGE_SIZE and browser._matches.size() > WorldMapCatalog.PAGE_SIZE, "The browser creates at most six cards regardless of total map count")
	var first_card := browser._grid.get_child(0) as Button
	var selected_id: String = browser._matches[0]
	var stale_action: Callable = first_card.pressed.get_connections()[0]["callable"]
	var old_epoch: int = browser._epoch
	browser._change_page(1)
	await _settle()
	stale_action.call()
	_check(browser._epoch > old_epoch and ui._overlay_mode == "world_maps" and ui.selected_arena() == "reliquary", "An old page callback cannot select a later page's map")
	browser._search.grab_focus()
	browser._search.text = "no-such-map-20261031"
	browser._search.text_changed.emit(browser._search.text)
	await _settle()
	_check(browser._matches.is_empty() and browser._grid.get_child_count() == 1 and browser._next.disabled and browser._previous.disabled, "Search has a bounded, navigable empty state")
	var canonical: String = str(WorldMapCatalog.entry(selected_id)["canonical_layout_id"])
	browser._search.text = canonical
	browser._search.text_changed.emit(browser._search.text)
	await _settle()
	_check(not browser._matches.is_empty() and root.gui_get_focus_owner() != null, "A canonical stage number finds a real map without losing focus")
	var chosen: String = browser._matches[0]
	var card := browser._grid.get_child(0) as Button
	card.pressed.emit()
	await _settle()
	_check(ui._overlay_mode.is_empty() and ui.selected_arena() == chosen and root.gui_get_focus_owner() == opener, "Selecting a source map closes the modal and returns focus to its title control")
	var start := ui.find_child("StartTrial", true, false) as Button
	_check(start.get_node(start.focus_neighbor_top) == opener and opener.text == ArenaCatalog.definition(chosen)["name"], "The selected source-map name and start navigation show the current choice")
	opener.pressed.emit()
	await _settle()
	_check(ui.handle_back(), "Keyboard escape and controller back can close the map browser")
	await _settle()
	_check(ui.selected_arena() == chosen and root.gui_get_focus_owner() == opener, "Closing the browser preserves map selection and title focus")
	opener.pressed.emit()
	var previous_browser := ui.find_child("WorldMapBrowser", true, false) as WorldMapBrowser
	var stale_back: Callable = previous_browser._back.pressed.get_connections()[0]["callable"]
	ui.hide_pause()
	opener.pressed.emit()
	var replacement := ui.find_child("WorldMapBrowser", true, false) as WorldMapBrowser
	stale_back.call()
	_check(ui._overlay_mode == "world_maps" and replacement.is_inside_tree(), "A detached browser's return callback cannot close its replacement")
	replacement._search.text = "no-such-map-20261031"
	replacement._search.text_changed.emit(replacement._search.text)
	await _settle()
	_check(root.gui_get_focus_owner() == replacement._search and replacement._matches.is_empty(), "An immediate search cancels stale deferred card focus and focuses the live search control")
	ui.handle_back()
	await _settle()
	ui._select_arena("mire")
	_check(ui.selected_arena() == "mire" and opener.text == "世界地图", "The existing arena cards remain selectable after a source map")
	ui.queue_free()
	await process_frame
