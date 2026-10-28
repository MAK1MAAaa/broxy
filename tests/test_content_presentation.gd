extends SceneTree
## New silhouettes, shared impact budgets, and the full native shop inventory.

const PROJECTILE_SCRIPT = preload("res://scripts/combat/projectile_painter.gd")
const IMPACT_SCRIPT = preload("res://scripts/combat/impact_painter.gd")
const NEW_IDS: PackedStringArray = ["crescent", "storm", "comet", "moon_charm", "pilgrim", "bulwark", "hourglass", "return_ring", "blood_pact", "grave_candle"]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	root.size = Vector2i(1280, 720)
	_test_projectile_signatures()
	_test_atlas_frames_and_transforms()
	_test_impact_aliases()
	await _test_content_stress()
	await _test_full_shop()
	print("ContentPresentation: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _test_projectile_signatures() -> void:
	var painter = PROJECTILE_SCRIPT.new()
	var state := RunState.new()
	state.begin(20261023, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(10000.0)
	for id: String in ["crescent", "storm", "comet"]:
		for rune: String in ["", "pierce", "bounce", "blast"]:
			sim.fire_weapon(id, rune, Vector2(300, 300), Vector2.RIGHT)
	var before: String = _signature(sim)
	painter.rebuild(sim.shots)
	_check(_signature(sim) == before, "Building all new projectile/rune silhouettes preserves both RNGs and the combat state")
	for id: String in ["crescent", "storm", "comet"]:
		for rune: String in ["", "pierce", "bounce", "blast"]:
			var key: String = id + ":" + rune
			_check(painter.trails.has(key), "The new weapon/rune family is prepared: " + key)
			if not painter.trails.has(key):
				continue
			_check(painter.heads.has(key), "The new source/rune family has a real head batch: " + key)
			if not painter.heads.has(key):
				continue
			var head = painter.heads[key]
			_check(head.source == id and head.multimesh.visible_instance_count == int(painter.family_counts[key]), "Every projectile receives its source-specific atlas head: " + key)
			_check(head.frame == PROJECTILE_SCRIPT.HEAD_SOURCES.find(id) and head.cursor == head.multimesh.visible_instance_count, "The prepared family uses its correct texture frame and complete visible instance range: " + key)
	var stats: Dictionary = painter.get_stats()
	_check(stats["allocated_instances"] <= CombatSim.SHOT_LIMIT * 3 and stats["head_instances"] == stats["friendly_count"], "New silhouettes use real head instances within the original GPU budget")
	var empty: Array[CombatSim.Shot] = []
	painter.rebuild(empty)
	_check(painter.trails.is_empty() and painter.heads.is_empty(), "Removing new projectiles releases every trail and head drawing family")


func _test_impact_aliases() -> void:
	var painter = IMPACT_SCRIPT.new()
	for source: String in ["bone", "crescent", "frost", "storm", "scatter", "comet"]:
		painter.add_hit(Vector2(500, 300), source, 15)
		painter.add_hit(Vector2(500, 300), source, 15)
	_check(painter.active_count() == 6, "Shared impact shapes retain distinct weapon sources while merging repeat hits from the same source and target")
	painter.rebuild()
	_check(painter.get_stats()["draw_commands"] == 6, "Six weapon sources share three compatible outlined shape batches")
	for phase: int in 2:
		painter.advance(0.045)
		for source: String in ["bone", "crescent", "frost", "storm", "ember", "scatter", "comet"]:
			painter.add_hit(Vector2(500, 300), source, 16 + phase)
	painter.rebuild()
	_check(painter.active_count() == 20, "Impact aliases retain marks independently at all three fade stages")
	_check(painter.get_stats()["draw_commands"] <= 24, "All seven weapons remain within twenty-four outlined impact draw commands")
	painter.clear()
	_check(painter.get_stats()["free_marks"] == 32 and painter.active_count() == 0, "Impact aliases reuse the original bounded pool")


func _test_atlas_frames_and_transforms() -> void:
	var expected_sources: PackedStringArray = ["bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring"]
	_check(PROJECTILE_SCRIPT.HEAD_SOURCES == expected_sources and PROJECTILE_SCRIPT.HEAD_FRAME_SIZE == 64 and is_equal_approx(PROJECTILE_SCRIPT.HEAD_WORLD_SIZE, 32.0), "Eight authored head frames have a stable source order and two texture pixels per world pixel")
	var shots: Array[CombatSim.Shot] = []
	var expected: Dictionary = {}
	for source: String in expected_sources:
		expected[source + ":"] = []
		for angle: float in [0.0, 0.31, 0.9, 2.7, 5.9]:
			for scale: float in [0.5, 1.0, 1.75]:
				var shot := CombatSim.Shot.new()
				shot.active = true
				shot.source = source
				shot.position = Vector2(342.25, 390.75)
				shot.radius = GameCatalog.weapon(source).projectile_radius * scale
				shot.velocity = Vector2.from_angle(angle) * 17.0
				shot.color = GameCatalog.weapon(source).color
				shots.append(shot)
				expected[source + ":"].append(Transform2D(angle, Vector2.ONE * scale, 0.0, shot.position))
		var stationary := CombatSim.Shot.new()
		stationary.active = true
		stationary.source = source
		stationary.radius = GameCatalog.weapon(source).projectile_radius
		stationary.position = Vector2(120.5, 240.25)
		stationary.velocity = Vector2.ZERO
		shots.append(stationary)
		expected[source + ":"].append(Transform2D(0.0, stationary.position))
	var painter = PROJECTILE_SCRIPT.new()
	painter.rebuild(shots)
	_check(painter.atlas_texture != null and painter.atlas_texture.get_width() == 512 and painter.atlas_texture.get_height() == 64, "The real shared texture resolves all eight complete atlas cells")
	for source: String in expected_sources:
		var key: String = source + ":"
		_check(painter.heads.has(key), "Atlas transform fixture retains source " + source)
		if not painter.heads.has(key):
			continue
		var head = painter.heads[key]
		var frame: int = expected_sources.find(source)
		_check(head.frame == frame and head.source == source and is_equal_approx(head.base_radius, GameCatalog.weapon(source).projectile_radius), "Source frame and scaling baseline come from the matching definition: " + source)
		_check(head.cursor == 16 and head.multimesh.visible_instance_count == 16, "All fifteen rotated/scaled heads plus a zero-speed head are genuinely visible: " + source)
		var arrays: Array = head.multimesh.mesh.surface_get_arrays(0)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var correct_uvs: bool = vertices.size() >= 4 and vertices.size() == uvs.size()
		var bounds := Rect2(Vector2.INF, Vector2.ZERO)
		for index: int in vertices.size():
			var point := Vector2(vertices[index].x, vertices[index].y)
			var uv := Vector2((float(frame) + point.x / 32.0 + 0.5) / 8.0, point.y / 32.0 + 0.5)
			correct_uvs = correct_uvs and point.is_finite() and absf(point.x) == 16.0 and absf(point.y) == 16.0 and uvs[index].is_equal_approx(uv)
			bounds = Rect2(point, Vector2.ZERO) if index == 0 else bounds.expand(point)
		_check(correct_uvs and bounds.is_equal_approx(Rect2(-16, -16, 32, 32)), "Quad vertices map only to their own complete UV cell without frame bleed: " + source)
		for index: int in head.cursor:
			var transform: Transform2D = _head_transform(head.buffer, index)
			_check(transform.is_equal_approx(expected[key][index]), "Real head buffer preserves position, rotation and radius scale, including zero-speed RIGHT: %s/%d" % [source, index])
			var offset: int = index * PROJECTILE_SCRIPT.INSTANCE_STRIDE
			_check(Color(head.buffer[offset + 8], head.buffer[offset + 9], head.buffer[offset + 10], head.buffer[offset + 11]).is_equal_approx(Color.WHITE), "Baked source colors and white cores stay untinted: %s/%d" % [source, index])
			if DisplayServer.get_name() != "headless":
				_check(head.multimesh.get_instance_transform_2d(index).is_equal_approx(transform), "Native visible head transform matches the prepared buffer: %s/%d" % [source, index])
	var before: String = _head_signature(painter)
	for repeat: int in 3:
		painter.rebuild(shots)
	_check(_head_signature(painter) == before, "Repeated atlas preparation preserves mesh UVs and every head transform")


static func _head_transform(buffer: PackedFloat32Array, index: int) -> Transform2D:
	var offset: int = index * PROJECTILE_SCRIPT.INSTANCE_STRIDE
	return Transform2D(Vector2(buffer[offset], buffer[offset + 4]), Vector2(buffer[offset + 1], buffer[offset + 5]), Vector2(buffer[offset + 3], buffer[offset + 7]))


static func _head_signature(painter) -> String:
	var result: Dictionary = {}
	for key: String in painter.heads:
		var head = painter.heads[key]
		result[key] = [head.frame, head.base_radius, head.buffer, head.multimesh.mesh.surface_get_arrays(0)]
	return JSON.stringify(result)


func _test_content_stress() -> void:
	var state := RunState.new()
	state.begin(20261023, "bone")
	var world := CombatWorld.new()
	var sound := SoundBank.new()
	root.add_child(sound)
	world.sound = sound
	root.add_child(world)
	world.begin(state)
	world.set_physics_process(false)
	world.stress_mode = true
	world.enable_rune_stress(true)
	_check(world.content_stress_mode and world.stress_weapon_ids.size() == GameCatalog.weapons().size(), "The explicit content pressure fixture includes every catalog weapon")
	var sources: Dictionary = {}
	var runes: Dictionary = {}
	var positive: int = 0
	for shot: CombatSim.Shot in world.sim.shots:
		if shot.active and not shot.hostile:
			sources[shot.source] = true
			runes[shot.rune] = true
			if shot.damage > 0.0:
				positive += 1
	_check(positive == 600 and sources.size() == GameCatalog.weapons().size() and runes.size() == 3, "The fixture contains six hundred positive-damage friendly shots across all catalog sources and three runes")
	var before: String = _signature(world.sim)
	var painter = PROJECTILE_SCRIPT.new()
	painter.rebuild(world.sim.shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["friendly_count"] == 600 and stats["family_counts"].size() == GameCatalog.weapons().size() * GameCatalog.runes().size(), "The projectile painter retains all catalog weapon/rune pressure families")
	_check(stats["allocated_instances"] <= 4800 and stats["total_visible_instances"] <= 4800, "The full content pressure fixture preserves the original 4800-instance budget")
	_check(_signature(world.sim) == before, "Content pressure render preparation does not mutate RNG, shots, or simulation")
	world.queue_free()
	sound.queue_free()
	await _settle()


func _test_full_shop() -> void:
	var state := RunState.new()
	state.begin(20261023, "bone")
	state.collect_souls(4000)
	_check(state.expand_backpack() and state.expand_backpack(), "The fixed shop build pays for both rows of the real thirty-six-cell backpack")
	for id: String in ["storm", "return_ring"]:
		_check(_purchase(state, "weapon", GameCatalog.weapon(id)), "The shop fixture legally buys backpack weapon " + id)
	for index: int in 3:
		var id: String = ["pierce", "bounce", "blast"][index]
		_check(_purchase(state, "rune", GameCatalog.rune(id)) and state.equip_rune(0, index), "The fixture formally sockets its purchased rune: " + id)
	for definition: ContentDef in GameCatalog.relics():
		_check(_purchase(state, "relic", definition), "All fourteen catalog relic kinds can be represented by real occupied boxes: " + definition.id)
	for id: String in ["bounce", "blast"]:
		_check(_purchase(state, "rune", GameCatalog.rune(id)), "A loose rune occupies its own physical cell: " + id)
	while state.backpack.can_add("relic", "armor"):
		var bought: bool = _purchase(state, "relic", GameCatalog.relic("armor"))
		_check(bought, "Small relic boxes fill the remaining legal cells")
		if not bought:
			break
	var snapshot: Dictionary = state.backpack_snapshot()
	_check(snapshot["height"] == 6 and snapshot["used_cells"] == 36 and snapshot["total_cells"] == 36, "The populated shop fixture is a legal full expanded grid rather than the obsolete unlimited stack inventory")
	state.offers = [
		{"kind": "weapon", "id": "crescent", "price": 26, "sold": false},
		{"kind": "weapon", "id": "storm", "price": 28, "sold": false},
		{"kind": "relic", "id": "moon_charm", "price": 24, "sold": false},
		{"kind": "relic", "id": "hourglass", "price": 24, "sold": false},
	]
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	for group: Array in [GameCatalog.weapons(), GameCatalog.runes(), GameCatalog.relics()]:
		for definition: ContentDef in group:
			var texture: Texture2D = ui._icon_texture(definition)
			_check(texture != null and texture.get_width() == 64 and texture.get_height() == 64, "Every original inventory icon still resolves at its declared native size: " + definition.id)
	ui.show_shop()
	await _settle()
	var panel: Control = ui.find_child("BackpackPanel", true, false) as Control
	var grid: Control = ui.find_child("BackpackGrid", true, false) as Control
	var scroll: ScrollContainer = ui.find_child("BackpackDetailsScroll", true, false) as ScrollContainer
	_check(panel != null and grid != null and scroll != null, "The inventory is presented as a backpack grid with an independently scrollable details viewport")
	if panel != null and grid != null and scroll != null:
		_check(root.get_visible_rect().grow(1).encloses(panel.get_global_rect()) and root.get_visible_rect().grow(1).encloses(grid.get_global_rect()) and root.get_visible_rect().grow(1).encloses(scroll.get_global_rect()), "The backpack panel, complete six-by-six board and details viewport fit in 720p")
		_check(grid.size.x >= 300 and grid.size.y >= 300 and scroll.follow_focus, "All thirty-six cells remain visible while detail actions can follow keyboard focus")
		var grave_uid: int = -1
		for item: Dictionary in snapshot["items"]:
			var box: Button = grid.find_child("BackpackItem%d" % int(item["uid"]), true, false) as Button
			_check(box != null and grid.get_global_rect().grow(1).encloses(box.get_global_rect()), "Every stored box has its actual occupied shape inside the grid: " + str(item["uid"]))
			if item["id"] == "grave_candle":
				grave_uid = int(item["uid"])
		var inspected: Button = grid.find_child("BackpackItem%d" % grave_uid, true, false) as Button
		_check(inspected != null and inspected.tooltip_text.contains(GameCatalog.relic("grave_candle").description), "The owned relic box retains its full original tradeoff description in the tooltip")
		if inspected != null:
			inspected.grab_focus()
		await _settle()
		var before: Dictionary = state.summary()
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = true
		root.push_input(key, false)
		await process_frame
		key = InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		root.push_input(key, false)
		await _settle()
		var title: Label = ui.find_child("BackpackItemTitle", true, false) as Label
		var details: Label = ui.find_child("BackpackItemEffect", true, false) as Label
		_check(title != null and title.text.contains(GameCatalog.relic("grave_candle").display_name) and details != null and details.text.contains("拾取范围 +38") and details.text.contains("移速 -8"), "Keyboard inspection exposes the selected relic's positive and negative ranked effects")
		_check(state.summary() == before and str(ui._screen) == "shop" and str(ui._overlay_mode).is_empty(), "Inline backpack inspection is read-only and stays in the shop")
		var sale: Button = ui.find_child("SellBackpackItem", true, false) as Button
		_check(sale != null, "The selected item's action remains keyboard reachable through its details viewport")
		if sale != null:
			sale.grab_focus()
			await _settle()
			_check(scroll.get_global_rect().grow(1).encloses(sale.get_global_rect()), "Following keyboard focus brings an item action into the visible details viewport")
	var offer: Control = ui.find_child("Offer1", true, false)
	var description: Label = offer.find_child("OfferDescription", true, false) if offer != null else null
	_check(description != null and description.text.contains("首目标") and description.text.contains("第二") and description.tooltip_text == GameCatalog.weapon("crescent").description, "The compact moon-scythe card preserves first-target and second-hit rules with its full formal tooltip")
	_check(offer != null and root.get_visible_rect().encloses(offer.get_global_rect()), "The moon-scythe shop card fits inside the full native layout")
	for index: int in range(1, 5):
		_check(ui.find_child("Offer%d" % index, true, false) != null, "The backpack redesign retains each of the four formal shop quotes")
	var next: Button = ui._shop_focus_button("next_wave")
	_check(next != null and root.get_visible_rect().encloses(next.get_global_rect()), "The full thirty-six-cell backpack leaves the next-wave action visible in 720p")
	_check(_chrome_inside(ui), "Visible shop chrome and scroll viewports fit the reference viewport without mistaking clipped content for overflow")
	ui.queue_free()
	await _settle()


func _purchase(state: RunState, kind: String, definition: ContentDef) -> bool:
	state.offers = [{"kind": kind, "id": definition.id, "price": definition.price, "sold": false}]
	return state.buy_offer(0)


func _chrome_inside(node: Node) -> bool:
	if node is ScrollContainer and node.is_visible_in_tree() and not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
		return false
	if node is Button and node.is_visible_in_tree():
		var ancestor: Node = node.get_parent()
		var in_scroll: bool = false
		while ancestor != null:
			if ancestor is ScrollContainer:
				in_scroll = true
				break
			ancestor = ancestor.get_parent()
		if not in_scroll and not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
			return false
	for child: Node in node.get_children():
		if not _chrome_inside(child):
			return false
	return true


func _signature(sim: CombatSim) -> String:
	var data: Array = [sim.rng.state, sim.run.rng.state, sim.snapshot(), sim.run.summary(), sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		data.append([shot.active, shot.position, shot.velocity, shot.damage, shot.remaining,
			shot.source, shot.rune, shot.life, shot.hit_ids.duplicate()])
	return JSON.stringify(data)


func _settle() -> void:
	for frame: int in 4:
		await process_frame
