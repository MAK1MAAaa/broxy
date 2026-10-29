extends SceneTree
## Exercise imported art through the real world, title, purchases, merges and sockets.

const SPRITE_SIZES: Dictionary = {
	"player": Vector2(96, 96), "chaser": Vector2(64, 64),
	"rusher": Vector2(64, 64), "tank": Vector2(80, 80),
	"caster": Vector2(72, 72), "boss": Vector2(160, 160),
}
const ART_ROOT: String = "res://assets/starfall/"
const FAN_ROOT: String = "res://assets/worldflipper/"
const FAN_OVERRIDES: Dictionary = {
	"res://assets/sprites/player.svg": FAN_ROOT + "sprites/player.png",
	"res://assets/sprites/chaser.svg": FAN_ROOT + "sprites/chaser.png",
	"res://assets/sprites/rusher.svg": FAN_ROOT + "sprites/rusher.png",
	"res://assets/sprites/tank.svg": FAN_ROOT + "sprites/tank.png",
	"res://assets/sprites/caster.svg": FAN_ROOT + "sprites/caster.png",
	"res://assets/sprites/boss.svg": FAN_ROOT + "sprites/boss.png",
	"res://assets/icons/bone.svg": FAN_ROOT + "icons/bone.png",
	"res://assets/icons/frost.svg": FAN_ROOT + "icons/frost.png",
	"res://assets/icons/ember.svg": FAN_ROOT + "icons/ember.png",
	"res://assets/icons/scatter.svg": FAN_ROOT + "icons/scatter.png",
	"res://assets/icons/crescent.svg": FAN_ROOT + "icons/crescent.png",
	"res://assets/icons/storm.svg": FAN_ROOT + "icons/storm.png",
	"res://assets/icons/comet.svg": FAN_ROOT + "icons/comet.png",
	"res://assets/icons/return_ring.svg": FAN_ROOT + "icons/return_ring.png",
}

class SilentSound extends SoundBank:
	func _ready() -> void:
		pass

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	_test_path_contract()
	_test_imported_family()
	await _test_world_resources_and_redraws()
	await _test_real_inventory_presentation()
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile), "Art integration leaves the personal profile unchanged")
	print("AdventureArt: %d assertions, %d failures; native rendering=%s; no physical-input or visual-approval claim" % [_checks, _failures, DisplayServer.get_name() != "headless"])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _test_path_contract() -> void:
	_check(AdventureArt.FAN_ROOT == FAN_ROOT, "The authorized original-game resources have an isolated presentation root")
	for source: String in FAN_OVERRIDES:
		var expected: String = str(FAN_OVERRIDES[source])
		_check(AdventureArt.path(source) == expected and AdventureArt.path(expected) == expected, "The original-game override has an exact stable route: " + source)
	_check(AdventureArt.path(ART_ROOT + "sprites/chaser.svg") == ART_ROOT + "sprites/chaser.svg", "The preserved previous enemy artwork remains available through its explicit path")
	_check(AdventureArt.path("res://assets/maps/mire.svg") == ART_ROOT + "maps/mire.svg", "An original map selects its replacement without changing catalog data")
	_check(AdventureArt.path("res://assets/menu_art.svg") == ART_ROOT + "menu_art.png", "Legacy menu references retain their preserved static illustration")
	for source: String in ["res://assets/audio/dash.wav", "res://assets/icons/example.png", "res://other/example.svg", "https://example.test/example.svg", ""]:
		_check(AdventureArt.path(source) == source, "Audio, non-SVG and external resources keep their original path: " + source)
	_check(AdventureArt.path(ART_ROOT + "icons/bone.svg") == ART_ROOT + "icons/bone.svg", "Explicit legacy artwork remains available without being rerouted")

func _expected_sprite(id: String) -> String:
	return str(FAN_OVERRIDES.get("res://assets/sprites/%s.svg" % id, ART_ROOT + "sprites/%s.svg" % id))

func _expected_icon(icon: String) -> String:
	return str(FAN_OVERRIDES.get("res://assets/icons/%s.svg" % icon, ART_ROOT + "icons/%s.svg" % icon))

func _expect_texture(texture: Texture2D, expected_path: String, expected_size: Vector2, label: String) -> void:
	_check(texture != null and texture.resource_path == expected_path and texture.get_size() == expected_size, "A real imported texture has the intended path and unchanged canvas: " + label)

func _test_imported_family() -> void:
	for id: String in SPRITE_SIZES:
		var texture := load(ART_ROOT + "sprites/%s.svg" % id) as Texture2D
		_expect_texture(texture, ART_ROOT + "sprites/%s.svg" % id, SPRITE_SIZES[id], id)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	_check(parsed is Dictionary and parsed.get("assets") is Array, "The preserved original asset manifest is available to the integration fixture")
	if not parsed is Dictionary or not parsed.get("assets") is Array:
		return
	var icons: int = 0
	for entry: Dictionary in parsed["assets"]:
		var icon_source: String = str(entry.get("path", ""))
		if not icon_source.begins_with("assets/icons/") or not icon_source.ends_with(".svg"):
			continue
		icons += 1
		var expected: String = ART_ROOT + icon_source.trim_prefix("assets/")
		_expect_texture(load(expected) as Texture2D, expected, Vector2(64, 64), icon_source)
	_check(icons == 26, "The replacement family covers every one of the 26 existing inventory and pickup icons")
	for definition: ContentDef in GameCatalog.skills():
		var path: String = ART_ROOT + "icons/%s.svg" % definition.icon
		_expect_texture(load(path) as Texture2D, path, Vector2(64, 64), definition.id)
	for id: String in ArenaCatalog.IDS:
		var map_source: String = str(ArenaCatalog.definition(id)["texture"])
		_check(map_source.begins_with("res://assets/") and not map_source.begins_with(ART_ROOT), "The actual map catalog retains its original resource identity: " + id)
		var expected: String = ART_ROOT + map_source.trim_prefix("res://assets/")
		_expect_texture(load(expected) as Texture2D, expected, Vector2(1280, 720), id)
	_expect_texture(load(ART_ROOT + "fx/projectile_heads.svg") as Texture2D, ART_ROOT + "fx/projectile_heads.svg", Vector2(512, 64), "eight-frame projectile atlas")
	for name: String in ["glow", "seal"]:
		_expect_texture(load(ART_ROOT + "fx/%s.svg" % name) as Texture2D, ART_ROOT + "fx/%s.svg" % name, Vector2(96, 96), name)
	var menu := load(ART_ROOT + "menu_art.png") as Texture2D
	_check(menu != null and menu.get_width() > 0 and menu.get_height() > 0, "The generated menu illustration is an actual imported PNG")

func _run_signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.loadout, state.rune_bag, state.offers, str(state.rng.seed), str(state.rng.state), state.health, state.elapsed])

func _sim_signature(sim: CombatSim) -> String:
	var entities: Array = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			entities.append([enemy.uid, enemy.definition.id, enemy.position, enemy.velocity, enemy.health, enemy.age, enemy.action_timer, enemy.mode])
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			entities.append([shot.slot, shot.source, shot.rune, shot.position, shot.previous, shot.velocity, shot.damage, shot.radius, shot.life, shot.remaining, shot.hit_ids, shot.hostile])
	for soul: CombatSim.Soul in sim.souls:
		if soul.active:
			entities.append([soul.slot, soul.position, soul.value, soul.age])
	for zone: CombatSim.WarningZone in sim.zones:
		entities.append([zone.source_id, zone.position, zone.radius, zone.age, zone.damage, zone.triggered])
	return JSON.stringify([sim.snapshot(), sim.player_position, sim.player_velocity, sim.player_direction, sim.dash_snapshot(), sim.pulse_snapshot(), str(sim.rng.seed), str(sim.rng.state), entities])

func _test_world_resources_and_redraws() -> void:
	var sound := SilentSound.new()
	root.add_child(sound)
	for id: String in ArenaCatalog.IDS:
		var state := RunState.new()
		state.begin(20261028, "bone", id)
		var world := CombatWorld.new()
		world.sound = sound
		world.set_physics_process(false)
		root.add_child(world)
		world.begin(state)
		world.set_physics_process(false)
		_expect_texture(world.arena_texture, ArenaCatalog.texture_path(id), ArenaCatalog.art_rect().size, "expanded world arena " + id)
		_check(world.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "The actual world uses local nearest filtering: " + id)
		for sprite: String in SPRITE_SIZES:
			_expect_texture(world.textures.get(sprite) as Texture2D, _expected_sprite(sprite), SPRITE_SIZES[sprite], "world " + sprite)
		for definition: ContentDef in GameCatalog.weapons():
			_expect_texture(world.textures.get(definition.id) as Texture2D, _expected_icon(definition.icon), Vector2(64, 64), "orbit " + definition.id)
		_expect_texture(world.soul_texture, ART_ROOT + "icons/soul.svg", Vector2(64, 64), "world pickup")
		_expect_texture(world.glow_texture, ART_ROOT + "fx/glow.svg", Vector2(96, 96), "world glow")
		_expect_texture(world.seal_texture, ART_ROOT + "fx/seal.svg", Vector2(96, 96), "world seal")
		_expect_texture(world._projectile_painter.atlas_texture, ART_ROOT + "fx/projectile_heads.svg", Vector2(512, 64), "world projectile painter")
		world.sim.spawn_enemy("chaser", Vector2(710, 330))
		world.sim.fire_weapon("bone", "pierce", Vector2(540, 365), Vector2.RIGHT)
		world.sim._drop_soul(Vector2(480, 400), 1)
		var before_run: String = _run_signature(state)
		var before_sim: String = _sim_signature(world.sim)
		for frame: int in 3:
			world.queue_redraw()
			await _settle()
		_check(_run_signature(state) == before_run and _sim_signature(world.sim) == before_sim, "Queued rendering with real enemies, shots and pickups preserves economic, combat and RNG state: " + id)
		world.stop()
		world.queue_free()
		await _settle()
	sound.queue_free()
	await _settle()

func _count_texture(node: Node, expected: String) -> int:
	if node == null:
		return 0
	var result: int = 0
	if node is TextureRect and node.texture != null and node.texture.resource_path == expected:
		result += 1
		var expected_filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_LINEAR if expected in [TitleCover.BASE_PATH, TitleCover.DEFAULT_PORTRAIT_PATH] else CanvasItem.TEXTURE_FILTER_NEAREST
		_check(node.texture_filter == expected_filter, "A rendered UI texture uses filtering appropriate to its pixel art or illustration: " + expected)
	for child: Node in node.get_children():
		result += _count_texture(child, expected)
	return result

func _has_text(node: Node, expected: String) -> bool:
	if node is Label and node.text == expected:
		return true
	for child: Node in node.get_children():
		if _has_text(child, expected):
			return true
	return false

func _first_slider(node: Node) -> HSlider:
	if node is HSlider:
		return node
	for child: Node in node.get_children():
		var result: HSlider = _first_slider(child)
		if result != null:
			return result
	return null

func _test_visible_volume_theme(ui: GameUI) -> void:
	ui._show_settings(false)
	await _settle()
	var slider: HSlider = _first_slider(ui._overlay)
	_check(slider != null and slider.custom_minimum_size.y == 34 and slider.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "The actual settings slider keeps its input footprint and uses a crisp local thumb")
	if slider != null:
		for name: String in ["slider", "grabber_area", "grabber_area_highlight"]:
			var track := slider.get_theme_stylebox(name) as StyleBoxFlat
			_check(track != null and track.get_minimum_size().y >= 6 and track.get_border_width_min() >= 1, "The real slider track has a nonzero visible height and outline: " + name)
		for name: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
			var texture: Texture2D = slider.get_theme_icon(name)
			_check(texture != null and texture.get_size() == Vector2(14, 18), "Each actual slider thumb has the intended small pixel canvas: " + name)
			if texture == null:
				continue
			var image: Image = texture.get_image()
			_check(image != null and image.get_used_rect() == Rect2i(0, 0, 14, 18), "The actual thumb contains opaque pixels spanning its intended alpha bounds: " + name)
			if image != null:
				_check(is_zero_approx(image.get_pixel(0, 0).a) and image.get_pixel(0, 9).is_equal_approx(GameUI.BONE) and image.get_pixel(13, 9).is_equal_approx(GameUI.BONE), "The thumb has transparent corners and a dark visible silhouette: " + name)
				var face: Color = image.get_pixel(7, 9)
				_check(is_equal_approx(face.a, 1.0) and not face.is_equal_approx(GameUI.BONE) and not face.is_equal_approx(Color.WHITE), "The thumb face remains colored and distinct from its outline and the pale panel: " + name)
	ui.hide_pause()
	await _settle()

func _press_shop_action(ui: GameUI, id: String) -> bool:
	var button: Button = ui._shop_focus_button(id)
	_check(button != null and not button.disabled, "The real UI exposes an enabled transaction action: " + id)
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	await _settle()
	return true

func _offer(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	var price: int = state.shop_price(definition)
	state.offers = [{"kind": kind, "id": id, "price": price, "sold": false}]
	return price

func _last_uid(state: RunState) -> int:
	var items: Array = state.backpack_snapshot()["items"]
	return int(items.back()["uid"]) if not items.is_empty() else -1

func _item_art(ui: GameUI, uid: int, icon: String) -> void:
	var button := ui._bag_grid.find_child("BackpackItem%d" % uid, false, false) as Button
	_check(button != null, "The actual stored UID has a rendered backpack button: " + str(uid))
	if button == null:
		return
	var texture := button.find_child("ItemIcon", false, false) as TextureRect
	_check(texture != null and texture.texture != null and texture.texture.resource_path == _expected_icon(icon) and texture.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "The stored item icon uses the replacement after a real inventory transaction")

func _test_real_inventory_presentation() -> void:
	var state := RunState.new()
	state.begin(20261028, "bone")
	state.collect_souls(500)
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	var font := ui._root.theme.default_font as FontFile
	_check(font != null and font.resource_path == "res://assets/fonts/fusion-pixel-12px-proportional-zh-hans.otf" and font.has_char(0x79d8) and font.has_char(0x672f), "The actual UI uses the bundled Fusion Pixel Chinese font")
	_check(font != null and font.antialiasing == TextServer.FONT_ANTIALIASING_NONE and font.hinting == TextServer.HINTING_NONE and is_equal_approx(font.oversampling, 1.0) and not font.allow_system_fallback, "The bundled font keeps native pixel rendering without system fallback")
	_check(ui._root.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST, "The whole interface is not forced to nearest filtering")
	var before: String = _run_signature(state)
	ui.show_title({})
	await _settle()
	_check(_count_texture(ui._page, TitleCover.BASE_PATH) == 1, "The real title displays its full-screen animated cover's actual base texture")
	var starter := ui.find_child("Starter_bone", true, false) as Button
	_check(starter != null and starter.icon != null and starter.icon.resource_path == _expected_icon("bone") and starter.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "The actual starter choice loads its new icon without changing its identity")
	for id: String in ArenaCatalog.IDS:
		var map_source: String = str(ArenaCatalog.definition(id)["texture"])
		_check(_count_texture(ui._page, ART_ROOT + map_source.trim_prefix("res://assets/")) == 1, "The title's real map thumbnail uses the replacement: " + id)
	_check(_run_signature(state) == before, "Opening and drawing the title leaves inventory and RNG unchanged")
	await _test_visible_volume_theme(ui)
	_check(_run_signature(state) == before, "Opening and closing the actual settings preview changes no inventory or RNG state")
	var target: int = int(state.loadout[0]["uid"])
	var price: int = _offer(state, "weapon", "bone")
	ui.show_shop()
	await _settle()
	_check(_count_texture(ui._page.find_child("Offer1", true, false), _expected_icon("bone")) == 1, "A real unsold offer displays its replacement art")
	var wallet: int = state.gold
	var rng_state: int = state.rng.state
	if not await _press_shop_action(ui, "buy:0"):
		ui.queue_free()
		await _settle()
		return
	var source: int = _last_uid(state)
	_check(source != target and not state.backpack_item(source).is_empty() and state.gold == wallet - price and state.rng.state == rng_state, "Buying through the real UI pays the actual price and creates the intended same-rank item")
	_item_art(ui, source, "bone")
	ui._bag_grid.select_item(source)
	await _settle()
	_check(_count_texture(ui._bag_details, _expected_icon("bone")) == 1, "The purchased item's actual detail view uses the new art")
	wallet = state.gold
	if not await _press_shop_action(ui, "bag_merge:%d" % target):
		ui.queue_free()
		await _settle()
		return
	_check(state.backpack_item(source).is_empty() and int(state.backpack_item(target).get("rank", 0)) == 2 and state.gold == wallet and state.rng.state == rng_state, "The real merge consumes the source, upgrades its target and preserves wallet and RNG")
	_item_art(ui, target, "bone")
	var item_button := ui._bag_grid.find_child("BackpackItem%d" % target, false, false)
	var rank := item_button.find_child("ItemRank", false, false) as Label if item_button != null else null
	_check(rank != null and rank.text == "Ⅱ", "The new art retains the actual merged rank numeral")
	price = _offer(state, "rune", "pierce")
	ui.show_shop()
	await _settle()
	wallet = state.gold
	if await _press_shop_action(ui, "buy:0"):
		var rune_uid: int = _last_uid(state)
		_check(state.gold == wallet - price and str(state.backpack_item(rune_uid).get("id", "")) == "pierce", "The rune socket fixture purchases its actual inventory source")
		ui._bag_grid.select_item(rune_uid)
		await _settle()
		if await _press_shop_action(ui, "bag_equip:%d" % target):
			_check(state.backpack_item(rune_uid).is_empty() and int(state.backpack_item(target).get("rune", {}).get("uid", -1)) == rune_uid, "Installing through the real UI consumes the bought rune and retains its actual UID")
			var button := ui._bag_grid.find_child("BackpackItem%d" % target, false, false)
			var badge := button.find_child("SocketRuneBadge", false, false) as TextureRect if button != null else null
			_check(badge != null and badge.texture != null and badge.texture.resource_path == ART_ROOT + "icons/pierce.svg" and badge.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "The installed socket keeps its new rune texture and local nearest filtering")
	before = _run_signature(state)
	ui.show_hud()
	ui.update_hud({"health": state.health, "max_health": state.stat("max_health"), "wave": state.wave, "time_left": 45.0, "gold": state.gold, "level": state.level, "loadout": state.loadout})
	await _settle()
	_check(_count_texture(ui._page, _expected_icon("bone")) == 1 and _has_text(ui._page, GameCatalog.rune("pierce").display_name + " Ⅰ"), "Actual HUD equipment retains its replacement texture and explicit attached-rune identity")
	ui.show_title({})
	await _settle()
	ui.show_shop()
	await _settle()
	ui._bag_grid.queue_redraw()
	ui._root.queue_redraw()
	await _settle()
	_check(_run_signature(state) == before, "Rebuilding and drawing title, HUD and shop after purchases changes no economic, inventory or RNG state")
	ui.queue_free()
	await _settle()
