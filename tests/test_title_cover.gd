extends SceneTree
## Verify the actual title's presentation, timers and input without player profile IO.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI
var _state: RunState

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var gif: PackedByteArray = FileAccess.get_file_as_bytes(TitleCover.GIF_PATH)
	_check(gif.size() > 13 and gif.slice(0, 6).get_string_from_ascii() == "GIF89a", "The actual delivered looping GIF is included in both source and exported package")
	_check(gif.size() > 10 and int(gif[6]) + (int(gif[7]) << 8) == 1280 and int(gif[8]) + (int(gif[9]) << 8) == 720, "The shipped GIF has the full 1280 by 720 cover canvas")
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	var initial_clocks: int = _count_clocks(root)
	_state = RunState.new()
	_state.begin(20261029, "bone", "mire")
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	var before: String = _state_signature()
	_ui.show_title({"wave": 8, "kills": 123, "wins": 2})
	await _settle()
	var cover := _cover()
	_check(cover != null, "The real title contains the native animated cover")
	if cover != null:
		_test_composition(cover)
		await _test_composite_cover(cover)
		await _test_animation(cover)
		await _test_native_pixels(cover)
		await _test_selection_and_modal(cover)
		await _test_lifecycle(cover, initial_clocks)
	_check(_state_signature() == before, "Title rendering and pending selections never change the live inventory, economy or random stream")
	_ui.queue_free()
	await _settle()
	_check(_count_clocks(root) == initial_clocks, "Freeing the UI releases every owned cover clock")
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile), "The cover fixture leaves the personal profile byte-for-byte unchanged")
	print("TitleCover: %d assertions, %d failures; native pixel checks=%s; fixed UI and software input only" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _wait_until(predicate: Callable, seconds: float = 1.5) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(predicate.call())

func _cover() -> TitleCover:
	return _ui.find_child("MenuArtwork", true, false) as TitleCover

func _button(name: String) -> Button:
	return _ui.find_child(name, true, false) as Button

func _button_with_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _button_with_text(child, text)
		if found != null:
			return found
	return null

func _state_signature() -> String:
	return JSON.stringify([_state.summary(), _state.backpack_snapshot(), _state.offers, _state.loadout,
		_state.rune_bag, str(_state.rng.seed), str(_state.rng.state), _state.health, _state.elapsed])

func _count_clocks(node: Node) -> int:
	var result: int = 1 if node is Timer and node.name == "FrameClock" else 0
	for child: Node in node.get_children():
		result += _count_clocks(child)
	return result

func _decorations_ignore_input(node: Node) -> bool:
	if node is Control and (node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE or node.is_processing()):
		return false
	for child: Node in node.get_children():
		if not _decorations_ignore_input(child):
			return false
	return true

func _visible_text(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label and node.is_visible_in_tree() else ""
	for child: Node in node.get_children():
		result += _visible_text(child)
	return result

func _test_composition(cover: TitleCover) -> void:
	cover.set_frame(0)
	var viewport := Rect2(Vector2.ZERO, Vector2(1280, 720))
	_check(cover.get_global_rect().is_equal_approx(viewport), "The artwork fills the complete logical title without a half-width seam")
	_check(cover.texture != null and cover.texture.resource_path == TitleCover.BASE_PATH and cover.texture.get_size() == Vector2(1280, 720), "The cover loads its actual full-screen imported artwork")
	_check(cover.get_node_or_null("PortraitLayer") == null and not cover.has_method("set_character"), "Alk belongs to the composite artwork without an independent portrait layer or character-selection API")
	_check(cover.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED and cover.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "The panoramic pixel cover keeps its aspect ratio, covers the viewport and preserves crisp sampling")
	_check(str(cover.snapshot().get("base_path", "")) == TitleCover.BASE_PATH and str(cover.snapshot().get("image_generation_path", "")) == TitleCover.IMAGE_GENERATION_PATH, "The title snapshot identifies the actual composite base and its generation provenance")
	_check(_decorations_ignore_input(cover), "The background and animated ornaments neither capture input nor process every frame")
	var actions := _ui.find_child("TitleActions", true, false) as Control
	var breathing := _ui.find_child("IllustrationBreathingSpace", true, false) as Control
	_check(actions != null and viewport.encloses(actions.get_global_rect()) and actions.get_global_rect().end.x <= 612.0, "Title actions occupy the left side without entering the character's visual space")
	_check(breathing != null and breathing.size.x >= 400.0 and breathing.size.y >= 260.0 and breathing.get_global_rect().position.x >= 600.0, "The right-side character keeps a substantial unobstructed area")
	for name: String in ["StarterDescription", "TitleControls"]:
		_check(_ui.find_child(name, true, false) == null, "Removed explanatory cover copy is not retained as a hidden node: " + name)
	for id: String in HeroCatalog.IDS:
		_check(_ui.find_child("StarterRole_" + id, true, false) == null, "Character cards do not append explanatory sublabels: " + id)
		var starter: Button = _button("Character_" + id)
		var identity := _ui.find_child("CharacterName_" + id, true, false) as Label
		_check(starter != null and starter.toggle_mode and viewport.encloses(starter.get_global_rect()) and identity != null and identity.text == HeroCatalog.definition(id).display_name, "The actual character choice retains its necessary name and hit region: " + id)
	for id: String in ArenaCatalog.IDS:
		_check(_ui.find_child("ArenaEffect_" + id, true, false) == null, "Map cards do not append explanatory terrain lines: " + id)
		var option: Button = _button("Arena_" + id)
		var name := _ui.find_child("ArenaName_" + id, true, false) as Label
		_check(option != null and option.toggle_mode and option.focus_mode == Control.FOCUS_ALL and viewport.encloses(option.get_global_rect()), "The actual map remains an accessible selectable control: " + id)
		_check(name != null and name.text.contains(str(ArenaCatalog.definition(id)["name"])), "A map retains its necessary identifying name: " + id)
	var text: String = _visible_text(_ui._page)
	_check(not text.contains("最高波次") and not text.contains("尚无记录") and not text.contains("方向键移动"), "Even a populated profile does not recreate cover statistics or control instructions")
	for action: String in ["进入试炼", "设置", "退出游戏"]:
		var button: Button = _button_with_text(_ui._page, action)
		_check(button != null and button.focus_mode == Control.FOCUS_ALL and not button.disabled and viewport.encloses(button.get_global_rect()), "A necessary title action remains available: " + action)

func _test_composite_cover(cover: TitleCover) -> void:
	var clock := cover.get_node_or_null("FrameClock") as Timer
	if clock == null:
		_check(false, "The composite presentation uses its existing native clock")
		return
	var clocks_before: int = _count_clocks(root)
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(TitleCover.IMAGE_GENERATION_PATH))
	_check(value is Dictionary, "The composite cover ships its actual image-generation record")
	if value is Dictionary:
		var record: Dictionary = value
		var normalized: Dictionary = record.get("normalized_output", {})
		var recorded_size: Array = normalized.get("size", [])
		_check(str(normalized.get("path", "")) == TitleCover.BASE_PATH.trim_prefix("res://") and recorded_size.size() == 2 and int(recorded_size[0]) == 1280 and int(recorded_size[1]) == 720, "The generation record describes the same full-screen base loaded by the native renderer")
		_check(str(record.get("tool", "")) == "image_gen.imagegen built-in" and str(record.get("character_id", "")) == "alk" and bool(record.get("external_game_character_reference", false)), "The record attributes the built-in image editor and the referenced World Flipper protagonist")
		for reference: Dictionary in record.get("references", []):
			var source: String = "res://" + str(reference.get("path", ""))
			_check(ResourceLoader.exists(source, "Texture2D"), "The original cover and Alk portrait remain available as source references: " + source)
		for asset: Dictionary in record.get("preserved_assets", []):
			var legacy: String = "res://" + str(asset.get("path", ""))
			_check(FileAccess.file_exists(legacy) and FileAccess.get_sha256(legacy) == str(asset.get("sha256", "")), "The earlier cover assets remain byte-for-byte available: " + legacy)
	var pending := TitleCover.new()
	pending.set_frame(8)
	root.add_child(pending)
	await _settle()
	_check(pending.texture == cover.texture and pending.get_node_or_null("PortraitLayer") == null, "Another cover reuses the same composite texture without allocating another character layer")
	_check(int(pending.snapshot().get("frame", -1)) == 8 and not bool(pending.snapshot().get("timer_active", true)) and _count_clocks(root) == clocks_before + 1, "A frozen frame chosen before ready survives initialization with exactly one inactive clock")
	pending.queue_free()
	await _settle()
	_check(_count_clocks(root) == clocks_before, "Freeing a preconfigured cover releases its sole owned clock")

func _test_animation(cover: TitleCover) -> void:
	var clock := cover.get_node_or_null("FrameClock") as Timer
	_check(clock != null and not clock.one_shot and is_equal_approx(clock.wait_time, TitleCover.FRAME_SECONDS), "The actual cover owns one repeating frame clock at its declared cadence")
	_check(int(cover.snapshot().get("frame_count", 0)) == 24 and TitleCover.FRAME_COUNT == 24, "The native presentation exposes the complete 24-frame cycle")
	if clock == null:
		return
	cover.set_frame(-1)
	_check(int(cover.snapshot().get("frame", -1)) == 23 and not bool(cover.snapshot().get("playing", true)) and clock.is_stopped(), "Seeking a negative frame wraps to the last frame and freezes playback")
	cover.set_frame(TitleCover.FRAME_COUNT * 2 + 7)
	_check(int(cover.snapshot().get("frame", -1)) == 7, "Seeking beyond the cycle wraps into the same authored frame")
	await create_timer(TitleCover.FRAME_SECONDS * 1.6).timeout
	_check(int(cover.snapshot().get("frame", -1)) == 7, "A frozen cover stays on its requested frame across real elapsed time")
	cover.set_frame(23)
	var observed: Array[int] = []
	var record: Callable = func() -> void: observed.append(int(cover.snapshot().get("frame", -1)))
	clock.timeout.connect(record)
	cover.set_playing(true)
	_check(bool(cover.snapshot().get("playing", false)) and not clock.is_stopped(), "Resume starts the actual timer without rebuilding the cover")
	var advanced: bool = await _wait_until(func() -> bool: return observed.size() >= 2)
	cover.set_playing(false)
	clock.timeout.disconnect(record)
	_check(advanced, "The real timer advances multiple cover frames")
	if observed.size() >= 2:
		_check(observed[0] == 0 and observed[1] == 1, "The last frame loops to zero and continues in order through native timeout signals")
	cover.set_frame(9)
	cover.set_playing(true)
	cover.hide()
	await process_frame
	_check(clock.is_stopped() and bool(cover.snapshot().get("playing", false)), "Hiding a playing cover suspends its timer while retaining the requested playback state")
	await create_timer(TitleCover.FRAME_SECONDS * 1.6).timeout
	_check(int(cover.snapshot().get("frame", -1)) == 9, "An invisible cover consumes no animation frames")
	cover.show()
	var resumed: bool = await _wait_until(func() -> bool: return int(cover.snapshot().get("frame", -1)) != 9)
	_check(resumed and not clock.is_stopped(), "Showing the cover resumes its existing cycle")
	cover.set_frame(0)
	_check(not bool(cover.snapshot().get("playing", true)) and clock.is_stopped(), "A final deterministic seek cancels resumed playback")

func _capture_frame(cover: TitleCover, index: int) -> String:
	cover.set_frame(index)
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and image.get_size() == Vector2i(1280, 720), "A native cover frame renders into the actual complete logical viewport")
	if image == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(image.get_data()) != OK:
		_check(false, "The native pixel capture can be hashed without changing its data")
		return ""
	return context.finish().hex_encode()

func _test_native_pixels(cover: TitleCover) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var first: String = await _capture_frame(cover, 0)
	var later: String = await _capture_frame(cover, 6)
	var end: String = await _capture_frame(cover, 23)
	var repeated: String = await _capture_frame(cover, 24)
	_check(not first.is_empty() and first != later and first != end and later != end, "Different authored phases produce different real rendered pixels")
	_check(first == repeated, "The same logical frame is deterministic after completing the loop")

func _key_enter() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		root.push_input(event, false)
		await process_frame
	await _settle()

func _click(button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	if DisplayServer.get_name() != "headless":
		root.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, false)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, false)
		await process_frame
	await _settle()

func _test_selection_and_modal(cover: TitleCover) -> void:
	cover.set_frame(0)
	var ember: Button = _button("Character_clarisse")
	var bone: Button = _button("Character_alk")
	var glacier: Button = _button("Arena_glacier")
	var settings: Button = _button_with_text(_ui._page, "设置")
	var start: Button = _button_with_text(_ui._page, "进入试炼")
	if ember == null or bone == null or glacier == null or settings == null or start == null:
		_check(false, "The input fixture requires the real title choices and actions")
		return
	ember.grab_focus()
	await _key_enter()
	_check(_ui.selected_hero() == "clarisse" and _ui._starter == "ember" and ember.button_pressed and not bone.button_pressed, "Actual Enter selects the character and its initial weapon with one selected state")
	await _click(glacier)
	_check(_ui.selected_arena() == "glacier" and glacier.button_pressed, "An actual GUI click reaches the map through the full-screen decorative artwork")
	settings.grab_focus()
	await _key_enter()
	var focus: Control = root.gui_get_focus_owner()
	_check(_ui._overlay_mode == "settings_title" and focus != null and _ui._overlay.is_ancestor_of(focus), "Settings receives keyboard focus above the animated cover")
	_check(_cover() == cover and _cover().get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, Vector2(1280, 720))), "Opening settings retains the same full-screen cover instance")
	var back: Button = _button_with_text(_ui._overlay, "返回")
	_check(back != null, "The actual settings back action is still available")
	if back != null:
		back.grab_focus()
		await _key_enter()
	_check(_ui._overlay_mode.is_empty() and _ui._starter == "ember" and _ui.selected_arena() == "glacier", "Returning from settings preserves pending choices without rebuilding explanatory text")
	_check(cover.texture != null and cover.texture.resource_path == TitleCover.BASE_PATH and cover.get_node_or_null("PortraitLayer") == null and int(cover.snapshot().get("frame", -1)) == 0, "Starter and arena choices leave the same composite character artwork and frozen animation state intact")
	var starts: Array[Dictionary] = []
	_ui.start_requested.connect(func(id: String) -> void: starts.append({"starter": id, "arena": _ui.selected_arena()}))
	start.grab_focus()
	await _key_enter()
	_check(starts == [{"starter": "ember", "arena": "glacier"}], "The real start button emits the chosen starter while preserving the separately selected map")
	_check(root.gui_get_focus_owner() != cover, "The animated background never takes action focus")

func _test_lifecycle(cover: TitleCover, initial_clocks: int) -> void:
	var clock := cover.get_node_or_null("FrameClock") as Timer
	if clock == null:
		_check(false, "The lifecycle fixture requires the actual owned frame clock")
		return
	var previous_cover: WeakRef = weakref(cover)
	var previous_clock: WeakRef = weakref(clock)
	var shared_texture: Texture2D = cover.texture
	_ui.show_hud()
	await _settle()
	_check(previous_cover.get_ref() == null and previous_clock.get_ref() == null, "Leaving the title destroys both the previous artwork and its frame timer")
	_check(_count_clocks(root) == initial_clocks, "No title clock remains active on the HUD")
	for visit: int in 3:
		_ui.show_title({})
		await _settle()
		var current: TitleCover = _cover()
		_check(current != null and _count_clocks(root) == initial_clocks + 1, "Reopening the title owns exactly one animation clock: " + str(visit))
		if current == null:
			continue
		_check(current.texture == shared_texture, "Reopened covers reuse the imported base texture rather than duplicating image memory: " + str(visit))
		previous_cover = weakref(current)
		previous_clock = weakref(current.get_node("FrameClock"))
	_ui.show_hud()
	await _settle()
	_check(previous_cover.get_ref() == null and previous_clock.get_ref() == null and _count_clocks(root) == initial_clocks, "Repeated title replacement leaves no detached cover or timer alive")
