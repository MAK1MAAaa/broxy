extends SceneTree
## Exercise the shipped font through real screens and inventory transactions.

const LOGICAL_SIZE := Vector2i(1280, 720)
const FONT_PATH := "res://assets/fonts/fusion-pixel-12px-proportional-zh-hans.otf"
const LICENSE_PATHS: PackedStringArray = [
	"res://assets/fonts/licenses/fusion-pixel/OFL.txt",
	"res://assets/fonts/licenses/fusion-pixel/LICENSES/ark-pixel/OFL.txt",
	"res://assets/fonts/licenses/fusion-pixel/LICENSES/cubic-11/OFL.txt",
	"res://assets/fonts/licenses/fusion-pixel/LICENSES/galmuri/LICENSE.txt",
]

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI
var _state: RunState
var _font: Font
var _bottom_skill_uid: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = LOGICAL_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = LOGICAL_SIZE
	_font = GameTypography.font()
	_test_font_resource()
	_test_combat_typography()
	_state = RunState.new()
	_state.begin(20261029, "bone")
	_state.gold = 10000
	_check(_state.expand_backpack() and _state.expand_backpack(), "The font fixture unlocks six rows through real purchases")
	_buy("weapon", "frost")
	_bottom_skill_uid = _buy("skill", "pulse")
	_buy("skill", "starfall")
	_buy("relic", "echo_stone")
	_check(_bottom_skill_uid >= 0 and _state.move_item(_bottom_skill_uid, Vector2i(4, 5), false), "A real skill occupies the last row of the six-by-six backpack")
	_state.offers.assign([_offer("weapon", "bone"), _offer("skill", "pulse"), _offer("relic", "grave_candle"), _offer("rune", "blast")])
	var before: String = _state_signature()
	_test_catalog_glyphs()
	_check(_state_signature() == before, "Font and catalog queries preserve inventory, stock, economy and random state")
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	_check(_ui._root.theme.default_font == _font, "The production UI theme uses the same shared local font")
	_ui.show_title({})
	await _settle()
	_test_screen_fonts("title", 8)
	_check(_has_visible_text("EMBERS"), "The production title participates in the font check")
	_ui.show_hud()
	_ui.update_hud(_hud_snapshot())
	await _settle()
	_test_screen_fonts("HUD", 10)
	_check(_has_visible_text(GameCatalog.skill("pulse").display_name) and _has_visible_text(GameCatalog.skill("starfall").display_name), "HUD font checks include both genuinely owned skills")
	_ui.show_shop()
	await _settle()
	_test_screen_fonts("shop", 20)
	_test_backpack_bounds()
	await _test_long_key_badges()
	await _test_records()
	_check(_state_signature() == before, "Rendering screens, changing key labels and reading records preserve complete run state")
	_ui.queue_free()
	await process_frame
	print("PixelTypography: %d assertions, %d failures; shared local font, live screens and six-by-six inventory" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame: int in 5:
		await process_frame


func _test_font_resource() -> void:
	_check(ResourceLoader.exists(FONT_PATH, "FontFile"), "The complete local font is an importable export resource")
	_check(_font is FontFile and not _font is SystemFont, "Runtime typography uses a bundled FontFile rather than a system font")
	_check(GameTypography.font() == _font and GameUI.create_ui_font() == _font, "Font accessors reuse one runtime resource")
	var file := _font as FontFile
	if file != null:
		_check(file.resource_path == FONT_PATH, "The shared runtime font retains the imported local resource path")
		_check(not file.data.is_empty(), "The runtime font contains embedded source bytes")
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(file.data)
		_check(digest.finish().hex_encode() == "2972782f05d7dd5f8414bc0215f69c181561172286b1f9823b5c279d9e5e6674", "The runtime font bytes match the complete official selected release")
		var source := load(FONT_PATH) as FontFile
		_check(source != null and file.data == source.data, "Runtime text uses the complete selected font bytes rather than a substitute or subset")
		_check(not file.allow_system_fallback and file.fallbacks.is_empty(), "Missing glyphs cannot silently resolve to machine-specific fonts")
		_check(file.antialiasing == TextServer.FONT_ANTIALIASING_NONE and file.hinting == TextServer.HINTING_NONE and not file.force_autohinter, "Pixel glyphs disable antialiasing and hinting")
		_check(is_equal_approx(file.oversampling, 1.0) and file.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED, "Pixel glyphs use explicit unit oversampling and integer positioning")
		_check(not file.multichannel_signed_distance_field and not file.generate_mipmaps, "The pixel font retains direct glyph rasterization")
	for path: String in LICENSE_PATHS:
		_check(FileAccess.file_exists(path) and not FileAccess.get_file_as_string(path).strip_edges().is_empty(), "The font distribution retains its license document: " + path)


func _test_combat_typography() -> void:
	var state := RunState.new()
	state.begin(20261029, "bone")
	var world := CombatWorld.new()
	root.add_child(world)
	world.begin(state)
	world.set_physics_process(false)
	_check(world._number_font == _font and world._dash_evasion_font == _font, "Combat numbers, dodge and pulse results share the UI font")
	_check(CombatWorld.DASH_EVASION_FONT_SIZE == 12 and CombatWorld.SKILL_FEEDBACK_FONT_SIZE == 12, "In-world confirmations use the native pixel size")
	world._on_damage_dealt(Vector2(200, 200), 14.0, "bone", false, 1)
	world._on_player_damaged(2.5, "caster", "projectile", Vector2(300, 200))
	_check(world._numbers.size() == 2, "Accepted outgoing and incoming events create real font-bearing feedback")
	for number: CombatWorld.FloatingNumber in world._numbers:
		_check(number.font_size == (24 if number.player_hit else 12), "Incoming damage remains larger than normal outgoing damage")
		_check(_missing_glyphs(number.text).is_empty() and is_equal_approx(number.text_width, _font.get_string_size(number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size).x), "Real damage text has complete glyphs and a matching cached width")
	world.stop()
	world.queue_free()


func _test_catalog_glyphs() -> void:
	var before: String = _state_signature()
	var text := "秘术余烬生命波次剩余魂屑等级背包商店就绪ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789ⅠⅡⅢ↑↓←→QE+-%／，。"
	text += CombatWorld._damage_text(2.5, true) + CombatWorld._damage_text(42.0, false) + CombatWorld.DASH_EVASION_TEXT
	var content_groups: Array = [GameCatalog.weapons(), GameCatalog.runes(), GameCatalog.relics(), GameCatalog.skills(), GameCatalog.enemies(), GameCatalog.waves()]
	var definitions: int = 0
	for group: Array in content_groups:
		for definition: ContentDef in group:
			text += definition.display_name + definition.description
			definitions += 1
	var missing: PackedStringArray = _missing_glyphs(text)
	_check(definitions > 0 and missing.is_empty(), "The bundled font covers every catalog name/effect and core UI symbol; missing: " + ", ".join(missing))
	_check(_state_signature() == before, "Glyph coverage inspection never advances run randomness or mutates inventory")


func _missing_glyphs(text: String) -> PackedStringArray:
	var seen: Dictionary = {}
	var missing: PackedStringArray = []
	for index: int in text.length():
		var codepoint: int = text.unicode_at(index)
		if codepoint <= 32 or seen.has(codepoint):
			continue
		seen[codepoint] = true
		if not _font.has_char(codepoint):
			missing.append("U+%04X %s" % [codepoint, String.chr(codepoint)])
	return missing


func _test_screen_fonts(screen: String, minimum_texts: int) -> void:
	var controls: Array[Control] = []
	_collect_text_controls(_ui, controls)
	_check(controls.size() >= minimum_texts, "The production %s screen exposes actual text controls" % screen)
	for control: Control in controls:
		var context := "%s/%s" % [screen, str(control.get_path())]
		var font: Font = control.get_theme_font("font")
		var size: int = control.get_theme_font_size("font_size")
		_check(font == _font and font is FontFile and not font is SystemFont, "Visible text shares the bundled font: " + context)
		_check(size in [12, 24, 36, 48], "Visible text uses an integer native pixel size: " + context)
		_check(_missing_glyphs(_text_of(control)).is_empty(), "Visible production text has no missing bundled glyph: " + context)


func _collect_text_controls(node: Node, result: Array[Control]) -> void:
	if node is Control:
		var control := node as Control
		if control.is_visible_in_tree() and not _text_of(control).is_empty():
			result.append(control)
	for child: Node in node.get_children():
		_collect_text_controls(child, result)


func _text_of(control: Control) -> String:
	if control is Label:
		return (control as Label).text
	if control is Button:
		return (control as Button).text
	return ""


func _has_visible_text(text: String) -> bool:
	var controls: Array[Control] = []
	_collect_text_controls(_ui, controls)
	for control: Control in controls:
		if _text_of(control) == text:
			return true
	return false


func _test_backpack_bounds() -> void:
	var grid := _ui.find_child("BackpackGrid", true, false) as BackpackGrid
	var panel := _ui.find_child("BackpackPanel", true, false) as Control
	_check(grid != null and panel != null, "The production shop includes the actual backpack grid and panel")
	if grid == null or panel == null:
		return
	var snapshot: Dictionary = _state.backpack_snapshot()
	_check(int(snapshot["width"]) == 6 and int(snapshot["height"]) == 6, "The measured backpack is a legally expanded six-by-six inventory")
	var full_grid := Rect2(grid.global_position, Vector2.ONE * BackpackGrid.CELL * 6.0)
	_check(grid.get_global_rect().encloses(full_grid) and panel.get_global_rect().encloses(full_grid), "All six rows remain inside the production backpack panel")
	_check(Rect2(Vector2.ZERO, Vector2(LOGICAL_SIZE)).encloses(full_grid), "The six-by-six backpack stays inside the reference game canvas")
	for item: Dictionary in snapshot["items"]:
		var button := grid.get_node_or_null("BackpackItem%d" % int(item["uid"])) as Button
		_check(button != null and button.is_visible_in_tree() and full_grid.encloses(button.get_global_rect()), "A real purchased item stays inside the full grid: " + str(item["id"]))
	var bottom := grid.get_node_or_null("BackpackItem%d" % _bottom_skill_uid) as Button
	_check(bottom != null and bottom.global_position.y >= full_grid.position.y + BackpackGrid.CELL * 5.0, "The boundary check includes an actual item in the sixth row")


func _test_long_key_badges() -> void:
	var bindings: Dictionary = ControlBindings.defaults()
	bindings["pulse"] = KEY_KP_MULTIPLY
	bindings["skill_secondary"] = KEY_PAGEUP
	_check(ControlBindings.binding_error(bindings, "pulse", KEY_KP_MULTIPLY).is_empty() and ControlBindings.binding_error(bindings, "skill_secondary", KEY_PAGEUP).is_empty(), "Long key names are valid gameplay bindings")
	_ui.set_controls(bindings)
	await _settle()
	var grid := _ui.find_child("BackpackGrid", true, false) as BackpackGrid
	if grid == null:
		_check(false, "The live backpack exists for keyboard badge verification")
		return
	var badges: Array[Node] = grid.find_children("SkillKeyBadge", "Label", true, false)
	_check(badges.size() == 2, "Both formally purchased active skills expose a live key badge")
	var expected: PackedStringArray = [ControlBindings.key_label(KEY_KP_MULTIPLY), ControlBindings.key_label(KEY_PAGEUP)]
	for node: Node in badges:
		var badge := node as Label
		var button := badge.get_parent() as Button
		_check(badge.text in expected and badge.text.length() > 1, "Each skill badge renders its full assigned long key label")
		_check(badge.clip_text and badge.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Long key labels retain bounded overflow behavior")
		_check(badge.size.y <= 16.0 and badge.get_theme_font("font").get_height(badge.get_theme_font_size("font_size")) <= 16.0, "A long key and its font metrics still fit the sixteen-pixel badge height")
		_check(button != null and button.get_global_rect().encloses(badge.get_global_rect()), "The key badge remains inside its actual inventory item")
	_test_screen_fonts("shop with long key names", 20)
	_test_backpack_bounds()


func _test_records() -> void:
	var offer: Button = _ui._shop_focus_button("offer_record:2")
	_check(offer != null, "A real offered relic exposes the production record action")
	if offer != null:
		offer.pressed.emit()
		await _settle()
		_check(_ui._overlay_mode == "item_record", "The real shop action opens item details")
		_test_screen_fonts("offered item details", 5)
		_check(_ui.handle_back(), "The offered item record closes through normal back navigation")
		await _settle()
	var grid := _ui.find_child("BackpackGrid", true, false) as BackpackGrid
	if grid == null:
		_check(false, "The backpack remains available for an owned item record")
		return
	grid.select_item(_bottom_skill_uid)
	await _settle()
	var owned: Button = _ui._shop_focus_button("bag_record:%d" % _bottom_skill_uid)
	_check(owned != null, "A formally owned skill exposes its UID-bound production record action")
	if owned != null:
		owned.pressed.emit()
		await _settle()
		_check(_ui._overlay_mode == "item_record", "The real inventory action opens owned skill details")
		_test_screen_fonts("owned skill details", 5)
		_check(_ui.handle_back(), "The owned skill record closes through normal back navigation")
		await _settle()


func _hud_snapshot() -> Dictionary:
	var snapshot: Dictionary = _state.summary()
	snapshot["time_left"] = 45.0
	snapshot["skills"] = []
	for item: Dictionary in _state.active_skills:
		var skill: Dictionary = _state.active_skill_parameters(item)
		skill.merge({"id": item["id"], "uid": item["uid"], "rank": item["rank"], "available": true, "ready": true, "cooldown_remaining": 0.0, "cooldown_duration": skill.get("cooldown", 0.0)}, true)
		(snapshot["skills"] as Array).append(skill)
	return snapshot


func _offer(kind: String, id: String) -> Dictionary:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	return {"kind": kind, "id": id, "price": _state.shop_price(definition), "sold": false}


func _buy(kind: String, id: String) -> int:
	_state.offers.assign([_offer(kind, id)])
	if not _state.buy_offer(0):
		_check(false, "The font fixture purchases real content through RunState: " + id)
		return -1
	_check(true, "The font fixture purchases real content through RunState: " + id)
	return int((_state.backpack_snapshot()["items"] as Array).back()["uid"])


func _state_signature() -> String:
	return JSON.stringify([_state.summary(), _state.backpack_snapshot(), _state.offers, str(_state.rng.state)])
