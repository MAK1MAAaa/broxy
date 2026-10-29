extends SceneTree
## Catalog identity follows real transactions through every inventory overview.

const NAMES: Dictionary = {
	"bone": "野营刀", "frost": "月之舞", "ember": "怨嗟之杖", "scatter": "海伯利安之弓",
	"crescent": "悲叹死镰", "storm": "光芒龙典", "comet": "怨嗟逆枪", "return_ring": "止战徽记",
}
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.offers, str(state.rng.state), state.damage_dealt_by_weapon])

func _count_icon(node: Node, definition: ContentDef) -> int:
	var count: int = 0
	if node is TextureRect and node.texture != null and node.texture.resource_path == AdventureArt.path("res://assets/icons/%s.svg" % definition.icon):
		_check(node.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Runtime item art keeps nearest filtering: " + definition.id)
		count += 1
	for child: Node in node.get_children():
		count += _count_icon(child, definition)
	return count

func _has_text(node: Node, text: String) -> bool:
	if node is Label and node.text.contains(text):
		return true
	for child: Node in node.get_children():
		if _has_text(child, text):
			return true
	return false

func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers.assign([{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}])
	if not state.buy_offer(0):
		_check(false, "Fixture buys the real catalog item: " + kind + "/" + id)
		return -1
	return int(state.backpack_snapshot()["items"].back()["uid"])

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	for id: String in NAMES:
		_check(GameCatalog.weapon(id).display_name == NAMES[id], "Weapon names match their verified original-game images: " + id)
	var core_text: String = str(RogueRules.core("frostfire")["description"]) + str(RogueRules.core("bone_chorus")["description"])
	_check(core_text.contains(NAMES["bone"]) and core_text.contains(NAMES["frost"]) and core_text.contains(NAMES["ember"]), "Core descriptions resolve the actual current catalog identity")
	var painter := ProjectilePainter.new()
	_check(painter.atlas_texture.resource_path == AdventureArt.FAN_ROOT + "fx/projectile_heads.png", "Actual combat projectiles use the same original weapon family")
	var atlas: Image = painter.atlas_texture.get_image()
	for index: int in ProjectilePainter.HEAD_SOURCES.size():
		var id: String = ProjectilePainter.HEAD_SOURCES[index]
		var icon := load(AdventureArt.FAN_ROOT + "icons/%s.png" % id) as Texture2D
		_check(atlas.get_region(Rect2i(index * 64, 0, 64, 64)).get_data() == icon.get_image().get_data(), "The projectile frame contains the complete corresponding weapon image: " + id)
	await _test_title()
	await _test_transactions()
	await _test_overviews()
	print("ContentIdentity: %d assertions, %d failures; native=%s" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)

func _test_title() -> void:
	var state := RunState.new()
	state.begin(20261030, "bone")
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.set_progress(["bone", "ember", "frost", "scatter"])
	ui.show_title({})
	await _settle()
	var grid := ui.find_child("StarterChoices", true, false) as GridContainer
	_check(grid != null and grid.columns == 2, "The title lays out complete weapon identities in two columns")
	var area := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for id: String in ["bone", "ember", "frost", "scatter"]:
		var button := ui.find_child("Starter_" + id, true, false) as Button
		var definition: ContentDef = GameCatalog.weapon(id)
		_check(button != null and button.text == definition.display_name and button.icon != null and button.icon.resource_path == AdventureArt.path("res://assets/icons/%s.svg" % id), "Starter cards use the complete name and original icon: " + id)
		if button != null:
			var font: Font = button.get_theme_font("font")
			var text_width: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
			_check(area.encloses(button.get_global_rect()) and button.size.x >= text_width + 36.0 + 28.0, "The full starter name and icon fit without trimming: " + id)
	ui.queue_free()
	await _settle()

func _test_transactions() -> void:
	var state := RunState.new()
	state.begin(20261030, "bone")
	state.gold = 10000
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	var definitions: Array[ContentDef] = []
	definitions.append_array(GameCatalog.weapons())
	definitions.append_array(GameCatalog.relics())
	definitions.append_array(GameCatalog.runes())
	definitions.append_array(GameCatalog.skills())
	for definition: ContentDef in definitions:
		var path: String = AdventureArt.path("res://assets/icons/%s.svg" % definition.icon)
		_check(path.begins_with(AdventureArt.FAN_ROOT) and path.ends_with(".png") and ResourceLoader.exists(path), "Every purchasable item has source-game runtime art: " + definition.kind + "/" + definition.id)
		state.offers.assign([{"kind": definition.kind, "id": definition.id, "price": state.shop_price(definition), "sold": false}])
		ui.show_shop()
		await _settle()
		var offer: Node = ui.find_child("Offer1", true, false)
		_check(offer != null and _has_text(offer, definition.display_name) and _count_icon(offer, definition) == 1, "Actual offers show the same name and icon: " + definition.id)
		var buy: Button = ui._shop_focus_button("buy:0")
		var gold: int = state.gold
		var price: int = int(state.offers[0]["price"])
		var random_state: int = state.rng.state
		_check(buy != null and not buy.disabled, "The item can be purchased through its real shop action: " + definition.id)
		if buy == null or buy.disabled:
			continue
		buy.pressed.emit()
		await _settle()
		var uid: int = int(state.backpack_snapshot()["items"].back()["uid"])
		var item: Dictionary = state.backpack_item(uid)
		_check(item["id"] == definition.id and item["kind"] == definition.kind and state.gold == gold - price and state.rng.state == random_state, "Artwork changes neither real purchase identity, price nor RNG: " + definition.id)
		var box: Node = ui._bag_grid.get_node_or_null("BackpackItem%d" % uid)
		_check(box != null and _count_icon(box, definition) == 1, "The actual purchased UID has the same backpack art: " + definition.id)
		ui._bag_grid.select_item(uid)
		await _settle()
		var before: String = _signature(state)
		_check(_has_text(ui._bag_details, definition.display_name) and _count_icon(ui._bag_details, definition) == 1, "Selected inventory details preserve that identity: " + definition.id)
		ui._bag_grid.queue_redraw()
		await _settle()
		_check(_signature(state) == before, "Inspecting and redrawing item identity does not mutate inventory or randomness: " + definition.id)
		var sell: Button = ui._shop_focus_button("bag_sell:%d" % uid)
		_check(sell != null and not sell.disabled, "The identity fixture releases the actual purchased item through the shop")
		if sell != null and not sell.disabled:
			sell.pressed.emit()
			await _settle()
	ui.queue_free()
	await _settle()

func _test_overviews() -> void:
	var state := RunState.new()
	state.begin(20261030, "bone")
	state.gold = 1000
	_buy(state, "relic", "damage")
	_buy(state, "skill", "pulse")
	_buy(state, "rune", "pierce")
	_check(state.equip_rune(0, 0), "The result fixture attaches a genuinely purchased rune")
	_buy(state, "rune", "bounce")
	for definition: ContentDef in GameCatalog.weapons():
		state.damage_dealt_by_weapon[definition.id] = 100.0 + float(GameCatalog.WEAPON_DEFS.find(definition))
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.show_result(false, "固定结算预览", {})
	await _settle()
	var before: String = _signature(state)
	var inventory: Node = ui.find_child("ResultBuildItems", true, false)
	var snapshot: Dictionary = state.backpack_snapshot()
	_check(inventory != null and inventory.get_child_count() == snapshot["items"].size(), "The result lists every real backpack UID, including all four item kinds")
	for item: Dictionary in snapshot["items"]:
		var uid: int = int(item["uid"])
		var definition: ContentDef = BackpackInventory.definition(str(item["kind"]), str(item["id"]))
		var row: Node = ui.find_child("ResultItem_%d" % uid, true, false)
		_check(row != null and int(row.get_meta("backpack_uid", -1)) == uid and _has_text(row, definition.display_name) and _count_icon(row, definition) >= 1, "Result inventory preserves the actual UID, icon, name and rank: " + str(uid))
		var rune: Dictionary = item.get("rune", {})
		if not rune.is_empty():
			var socket: Node = ui.find_child("ResultSocket_%d" % uid, true, false)
			var rune_definition: ContentDef = GameCatalog.rune(str(rune["id"]))
			_check(socket != null and _has_text(socket, rune_definition.display_name) and _count_icon(socket, rune_definition) == 1, "Attached runes also retain their own source icon and current name")
	for definition: ContentDef in GameCatalog.weapons():
		var contribution: Node = ui.find_child("Damage_" + definition.id, true, false)
		_check(contribution != null and _has_text(contribution, definition.display_name) and _count_icon(contribution, definition) == 1, "Damage history retains identity even for a sold weapon: " + definition.id)
	_check(_signature(state) == before, "Opening the complete result inventory never changes a run")
	state.offers.assign([{"kind": "relic", "id": "haste", "price": 22, "sold": false}])
	ui.show_shop()
	await _settle()
	var compare: Button = ui._shop_focus_button("compare:0")
	_check(compare != null and not compare.disabled, "The comparison fixture has a real enabled shop action")
	if compare != null and not compare.disabled:
		compare.pressed.emit()
	await _settle()
	var identity: Node = ui.find_child("ComparisonWeapon0Identity", true, false)
	_check(identity != null and _count_icon(identity, GameCatalog.weapon("bone")) == 1 and _has_text(identity, GameCatalog.weapon("bone").display_name), "Purchase comparison keeps the equipped weapon's actual icon and name")
	ui.queue_free()
	await _settle()
