extends SceneTree
## Verify source animation timing through the shipped world and real inventory UI.

const STEP: float = 1.0 / 60.0
const FAN_ROOT := "res://assets/worldflipper/"
const ATLAS_PATH := FAN_ROOT + "sprites/player-atlas.png"
const WEAPONS: PackedStringArray = ["bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring"]
const SOURCE_WEAPONS: Dictionary = {
	"bone": "Camping Knife", "frost": "Moon Dance", "ember": "Spiteful Staff", "scatter": "Hyperion Bow",
	"crescent": "Grim Scythe", "storm": "Lightcrest Tome", "comet": "Spiteful Spear", "return_ring": "Amulet of Ruin",
}
const FRAME_RECTS: Array[Rect2] = [
	Rect2(0, 0, 96, 96), Rect2(96, 0, 96, 96), Rect2(192, 0, 96, 96), Rect2(288, 0, 96, 96),
	Rect2(0, 96, 96, 96), Rect2(96, 96, 96, 96), Rect2(192, 96, 96, 96), Rect2(288, 96, 96, 96),
	Rect2(0, 192, 96, 96),
]

class SilentSound extends SoundBank:
	func _ready() -> void:
		pass
	func play(_name: String, _loudness: float = -10.0) -> void:
		pass
	func play_cue(_name: String, _loudness: float, _cue_id: String) -> void:
		pass

class ProbeWorld extends CombatWorld:
	var movement: Vector2 = Vector2.ZERO
	var drawn_frames: Array[int] = []
	func _movement() -> Vector2:
		return movement
	func _draw_player_texture(frame_index: int, bob: float, tint: Color) -> void:
		drawn_frames.append(frame_index)
		super._draw_player_texture(frame_index, bob, tint)

var _checks: int = 0
var _failures: int = 0
var _native_draw_checked: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_test_manifest_provenance()
	_test_imported_animation()
	_test_source_timing()
	await _test_real_world_animation()
	await _test_purchased_weapon_icons()
	print("WorldFlipperArt: %d assertions, %d failures; native draw checks=%s; no physical-input or visual-approval claim" % [_checks, _failures, _native_draw_checked])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _test_manifest_provenance() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FAN_ROOT + "manifest.json"))
	_check(parsed is Dictionary and parsed.get("assets") is Array and parsed.get("sources") is Array, "The shipped original-game resources have a readable source manifest")
	if not parsed is Dictionary or not parsed.get("assets") is Array or not parsed.get("sources") is Array:
		return
	var sources: Dictionary = {}
	for source: Dictionary in parsed["sources"]:
		sources[str(source["id"])] = source
	var assets: Dictionary = {}
	for asset: Dictionary in parsed["assets"]:
		assets[str(asset["id"])] = asset
	var expected_ids: PackedStringArray = ["player"]
	expected_ids.append_array(WEAPONS)
	for id: String in expected_ids:
		var asset: Dictionary = assets.get(id, {})
		var expected_path: String = "assets/worldflipper/sprites/player.png" if id == "player" else "assets/worldflipper/icons/%s.png" % id
		var source_id: String = "alk_neutral" if id == "player" else "weapon_" + id
		var source: Dictionary = sources.get(source_id, {})
		_check(str(asset.get("path", "")) == expected_path and asset.get("source_ids", []) == [source_id] and FileAccess.get_sha256("res://" + expected_path) == str(asset.get("sha256", "")), "The exact runtime replacement is tied to its complete checked-in source-derived bytes: " + id)
		_check(str(source.get("sha256", "")).length() == 64 and str(source.get("url", "")).begins_with("https://") and str(source.get("source_page", "")).begins_with("https://") and (str(source.get("pose", "")) == "neutral" if id == "player" else str(source.get("game_id", "")) == id and str(source.get("name", "")) == str(SOURCE_WEAPONS[id])), "Each replacement records the intended original character or weapon source: " + id)


func _test_imported_animation() -> void:
	var neutral := load(FAN_ROOT + "sprites/player.png") as Texture2D
	var atlas := load(ATLAS_PATH) as Texture2D
	_check(neutral != null and neutral.get_size() == Vector2(96, 96), "The selected original character has an imported ninety-six-pixel static canvas")
	_check(atlas != null and atlas.get_size() == Vector2(384, 288), "Both original four-frame cycles share the expected imported atlas")
	_check(FileAccess.file_exists(FAN_ROOT + "NOTICE.txt") and not FileAccess.get_file_as_string(FAN_ROOT + "NOTICE.txt").strip_edges().is_empty(), "The original-game artwork retains its source and copyright notice")
	if neutral == null or atlas == null:
		return
	var static_image: Image = neutral.get_image()
	var atlas_image: Image = atlas.get_image()
	_check(static_image != null and atlas_image != null, "The actual imported character textures expose their normalized pixel data")
	if static_image == null or atlas_image == null:
		return
	_check(not static_image.get_used_rect().has_area() or Rect2i(12, 3, 72, 90).encloses(static_image.get_used_rect()), "The character silhouette stays within its preserved source placement and transparent margins")
	_check(static_image.get_used_rect().has_area() and _binary_alpha(static_image), "The static character contains an opaque pixel silhouette without interpolated alpha")
	_check(atlas_image.get_region(Rect2i(0, 0, 96, 96)).get_data() == static_image.get_data(), "Atlas frame zero exactly preserves the static character pixels")
	for index: int in FRAME_RECTS.size():
		var region: Rect2 = WorldFlipperPlayerArt.frame_rect(index)
		_check(region == FRAME_RECTS[index], "The animation frame selects its actual atlas cell: " + str(index))
		var frame: Image = atlas_image.get_region(Rect2i(region))
		_check(frame.get_used_rect().has_area() and Rect2i(12, 3, 72, 90).encloses(frame.get_used_rect()) and _binary_alpha(frame), "Every sampled original frame has a bounded crisp silhouette: " + str(index))
		_check(_integer_scaled(frame), "Every character frame retains three-by-three source pixels: " + str(index))
	_check(atlas_image.get_region(Rect2i(96, 192, 288, 96)).is_invisible(), "Unused atlas cells are transparent rather than leaking neighboring art")
	for start: int in [1, 5]:
		var first: Image = atlas_image.get_region(Rect2i(FRAME_RECTS[start]))
		var changed: bool = false
		for offset: int in range(1, 4):
			changed = changed or first.get_data() != atlas_image.get_region(Rect2i(FRAME_RECTS[start + offset])).get_data()
		_check(changed, "The real front/back walk cycle contains changing source frames: " + str(start))


func _binary_alpha(image: Image) -> bool:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var alpha: float = image.get_pixel(x, y).a
			if not is_zero_approx(alpha) and not is_equal_approx(alpha, 1.0):
				return false
	return true


func _integer_scaled(image: Image) -> bool:
	for y: int in range(0, image.get_height(), 3):
		for x: int in range(0, image.get_width(), 3):
			var source: Color = image.get_pixel(x, y)
			for dy: int in 3:
				for dx: int in 3:
					if not source.is_equal_approx(image.get_pixel(x + dx, y + dy)):
						return false
	return true


func _test_source_timing() -> void:
	var times: Array[float] = [0.0, 0.079, 0.08, 0.179, 0.18, 0.279, 0.28, 0.379, 0.38, 0.459, 0.46]
	var front_frames: Array[int] = [1, 1, 2, 2, 3, 3, 4, 4, 1, 1, 2]
	for index: int in times.size():
		_check(WorldFlipperPlayerArt.frame_index(Vector2.DOWN, times[index]) == front_frames[index] and WorldFlipperPlayerArt.frame_index(Vector2.UP, times[index]) == front_frames[index] + 4, "Imported front/back animation honors the 80/100/100/100 millisecond timeline at %.3fs" % times[index])
	_check(WorldFlipperPlayerArt.frame_index(Vector2.ZERO, 0.28) == 0 and not WorldFlipperPlayerArt.flip_for(Vector2.ZERO), "An idle character selects its distinct neutral pose")
	_check(WorldFlipperPlayerArt.frame_index(Vector2.LEFT, 0.1) == 2 and WorldFlipperPlayerArt.flip_for(Vector2.LEFT), "Leftward movement reuses and mirrors the front cycle")
	_check(WorldFlipperPlayerArt.frame_index(Vector2(-1, -1), 0.1) == 6 and not WorldFlipperPlayerArt.flip_for(Vector2(-1, -1)), "Upward diagonal movement preserves the original back cycle orientation")


func _world() -> ProbeWorld:
	var sound := SilentSound.new()
	root.add_child(sound)
	var world := ProbeWorld.new()
	world.sound = sound
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	world.set_physics_process(false)
	var state := RunState.new()
	state.begin(20261029, "bone")
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	return world


func _test_real_world_animation() -> void:
	var world: ProbeWorld = _world()
	_check(world._player_atlas != null and world._player_atlas.resource_path == ATLAS_PATH and world.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "The shipped CombatWorld loads the normalized original animation with nearest filtering")
	_check(world._player_frame_index() == 0 and not world._player_flip_h(), "A real newly begun battle starts in the neutral pose")
	world.movement = Vector2.DOWN
	var origin: Vector2 = world.sim.player_position
	world._physics_process(0.079)
	_check(world.sim.player_position.y > origin.y and world._player_frame_index() == 1, "The real fixed update moves the player and displays the first front pose before eighty milliseconds")
	world._physics_process(0.002)
	_check(world._player_frame_index() == 2, "The actual world advances the source front animation at its eighty-millisecond boundary")
	world.movement = Vector2.UP
	world._physics_process(0.1)
	_check(world.sim.player_velocity.y < 0.0 and world._player_frame_index() == 7 and not world._player_flip_h(), "A real direction change switches to the timed back cycle")
	world.movement = Vector2.LEFT
	world._physics_process(STEP)
	_check(world.sim.player_velocity.x < 0.0 and world._player_frame_index() == 3 and world._player_flip_h(), "Real leftward movement selects the corresponding mirrored front frame")
	world.movement = Vector2.ZERO
	world._physics_process(STEP)
	_check(world.sim.player_direction == Vector2.LEFT and world._player_frame_index() == 0 and not world._player_flip_h(), "Releasing movement returns to neutral while simulation facing remains unchanged")
	var pool_ids: Array[int] = _pool_ids(world)
	world.movement = Vector2.LEFT
	var dash_origin: Vector2 = world.sim.player_position
	_check(world.request_dash(), "The real animation fixture queues one valid dash")
	world._physics_process(STEP)
	var first: CombatWorld.DashAfterimage = world._dash_afterimages[0]
	_check(world.sim.dashes_used == 1 and world.sim.player_position.x < dash_origin.x and first.life > 0.0 and first.position == dash_origin, "The real dash emits a pooled afterimage at its original position before moving")
	_check(first.frame_index == 3 and first.flip_h, "Dash start captures the moving front frame and mirror even though the previous player velocity was zero")
	var stored_frame: int = first.frame_index
	var stored_flip: bool = first.flip_h
	world.movement = Vector2.UP
	world._physics_process(0.05)
	_check(first.frame_index == stored_frame and first.flip_h == stored_flip and world._player_frame_index() == 4 and world._player_flip_h(), "Old ghosts retain their sampled pose while the active dash advances its own animation and preserves its burst direction")
	var before_pause: String = _world_signature(world)
	paused = true
	world.set_physics_process(true)
	await _settle()
	world._physics_process(STEP)
	_check(_world_signature(world) == before_pause, "A real SceneTree pause freezes combat, source animation time and every afterimage sample")
	world.set_physics_process(false)
	paused = false
	world._physics_process(STEP)
	_check(world._visual_time > 0.29 and world.sim.elapsed > 0.29, "Resuming advances the same simulation and source animation clock")
	world.sim.spawn_enemy("chaser", world.sim.player_position + Vector2(180, 0))
	world.sim.fire_weapon("bone", "pierce", world.sim.player_position, Vector2.RIGHT)
	world.sim._drop_soul(world.sim.player_position + Vector2(60, 0), 1)
	var before_draw: String = _world_signature(world)
	var expected_frame: int = world._player_frame_index()
	world.drawn_frames.clear()
	for frame: int in 3:
		world.queue_redraw()
		await _settle()
	if DisplayServer.get_name() != "headless":
		_native_draw_checked = true
		_check(world.drawn_frames.has(expected_frame) and world.drawn_frames.has(stored_frame), "Native drawing consumes both the current animation pose and the previously sampled afterimage pose")
	_check(_world_signature(world) == before_draw, "Repeated real draw requests cannot advance animation, ghosts, combat, economy, inventory or either random stream")
	world.stop()
	_check(world.dash_afterimage_count() == 0 and _pool_ids(world) == pool_ids, "Stopping clears animation ghosts while keeping the same six allocated slots")
	var next_state := RunState.new()
	next_state.begin(20261030, "frost")
	world.begin(next_state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	_check(world.dash_afterimage_count() == 0 and _pool_ids(world) == pool_ids and world._player_frame_index() == 0, "Beginning a later battle cannot inherit old animated ghosts or movement poses")
	world.sound.queue_free()
	world.queue_free()
	await _settle()


func _pool_ids(world: CombatWorld) -> Array[int]:
	var result: Array[int] = []
	for afterimage: CombatWorld.DashAfterimage in world._dash_afterimages:
		result.append(afterimage.get_instance_id())
	_check(result.size() == 6, "The source animation retains the fixed six-slot dash feedback budget")
	return result


func _world_signature(world: CombatWorld) -> String:
	var trails: Array = []
	for afterimage: CombatWorld.DashAfterimage in world._dash_afterimages:
		trails.append([afterimage.position, afterimage.lean, afterimage.life, afterimage.frame_index, afterimage.flip_h])
	var entities: Array = []
	for enemy: CombatSim.Enemy in world.sim.enemies:
		if enemy.active:
			entities.append([enemy.uid, enemy.definition.id, enemy.position, enemy.velocity, enemy.health, enemy.age, enemy.action_timer])
	for shot: CombatSim.Shot in world.sim.shots:
		if shot.active:
			entities.append([shot.slot, shot.position, shot.previous, shot.velocity, shot.damage, shot.life, shot.hit_ids])
	for soul: CombatSim.Soul in world.sim.souls:
		if soul.active:
			entities.append([soul.slot, soul.position, soul.value, soul.age])
	return JSON.stringify([_run_signature(world.sim.run), world.sim.snapshot(), world.sim.player_position, world.sim.player_velocity, world.sim.player_direction, str(world.sim.rng.state), world._visual_time, trails, entities])


func _test_purchased_weapon_icons() -> void:
	var state := RunState.new()
	state.begin(20261029, "bone")
	state.gold = 10000
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	for id: String in WEAPONS:
		var definition: ContentDef = GameCatalog.weapon(id)
		var expected: String = FAN_ROOT + "icons/%s.png" % id
		var texture := load(expected) as Texture2D
		_check(texture != null and texture.get_size() == Vector2(64, 64) and texture.get_image().get_used_rect().has_area() and _binary_alpha(texture.get_image()), "Each selected weapon imports as an actual crisp sixty-four-pixel icon: " + id)
		state.offers.assign([{"kind": "weapon", "id": id, "price": state.shop_price(definition), "sold": false}])
		ui.show_shop()
		await _settle()
		var offer := ui.find_child("Offer1", true, false) as Control
		_check(offer != null and _count_texture(offer, expected) == 1, "The actual shop offer routes the original weapon icon: " + id)
		if not await _press(ui, "buy:0"):
			continue
		var item: Dictionary = (state.backpack_snapshot()["items"] as Array).back()
		var uid: int = int(item["uid"])
		_check(str(item["id"]) == id and str(item["kind"]) == "weapon", "The artwork fixture buys the intended real inventory item: " + id)
		var button := ui._bag_grid.get_node_or_null("BackpackItem%d" % uid) as Button
		_check(button != null and _count_texture(button, expected) == 1, "The purchased UID displays the original weapon icon inside the real backpack: " + id)
		var before: String = _run_signature(state)
		ui._bag_grid.select_item(uid)
		await _settle()
		_check(_count_texture(ui._bag_details, expected) == 1 and _run_signature(state) == before, "Inspecting the actual bought weapon selects its original art without changing inventory or randomness: " + id)
		await _press(ui, "bag_sell:%d" % uid)
	ui.queue_free()
	await _settle()


func _press(ui: GameUI, id: String) -> bool:
	var button: Button = ui._shop_focus_button(id)
	_check(button != null and not button.disabled, "The artwork fixture uses an enabled production transaction action: " + id)
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	await _settle()
	return true


func _count_texture(node: Node, expected: String) -> int:
	if node == null:
		return 0
	var count: int = 0
	if node is TextureRect and node.texture != null and node.texture.resource_path == expected:
		count += 1
		_check(node.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "The actual original-game UI icon retains local nearest filtering")
	for child: Node in node.get_children():
		count += _count_texture(child, expected)
	return count


func _run_signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.loadout, state.rune_bag, state.offers, str(state.rng.seed), str(state.rng.state)])
