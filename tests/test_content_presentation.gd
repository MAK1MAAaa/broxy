extends SceneTree
## New silhouettes, shared impact budgets, and the full native shop inventory.

const PROJECTILE_SCRIPT = preload("res://scripts/combat/projectile_painter.gd")
const IMPACT_SCRIPT = preload("res://scripts/combat/impact_painter.gd")
const NEW_IDS: PackedStringArray = ["crescent", "storm", "comet", "moon_charm", "pilgrim", "bulwark", "hourglass"]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	root.size = Vector2i(1280, 720)
	_test_projectile_signatures()
	_test_cached_sigil_equivalence()
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
			var points: PackedVector2Array = painter.trails[key].sigils
			var per_shot: int = 32 if id == "crescent" else 12 if id == "storm" else 20
			_check(points.size() == per_shot * int(painter.family_counts[key]), "Every projectile receives its own bounded crescent, lightning, or star geometry: " + key)
			var finite: bool = true
			for point: Vector2 in points:
				finite = finite and point.is_finite()
			_check(finite and points.size() % 2 == 0, "Sigil segments contain finite independent endpoint pairs: " + key)
	var stats: Dictionary = painter.get_stats()
	_check(stats["allocated_instances"] <= CombatSim.SHOT_LIMIT * 3, "New silhouettes do not add projectile GPU instances")
	var empty: Array[CombatSim.Shot] = []
	painter.rebuild(empty)
	_check(painter.trails.is_empty(), "Removing new projectiles also releases every sigil drawing family")


func _test_impact_aliases() -> void:
	var painter = IMPACT_SCRIPT.new()
	for source: String in ["bone", "crescent", "frost", "storm", "scatter", "comet"]:
		painter.add_hit(Vector2(500, 300), source, 15)
		painter.add_hit(Vector2(500, 300), source, 15)
	_check(painter.active_count() == 6, "Shared impact shapes retain distinct weapon sources while merging repeat hits from the same source and target")
	painter.rebuild()
	_check(painter.get_stats()["draw_commands"] == 3, "Six weapon sources share three compatible shape batches")
	for phase: int in 2:
		painter.advance(0.045)
		for source: String in ["bone", "crescent", "frost", "storm", "ember", "scatter", "comet"]:
			painter.add_hit(Vector2(500, 300), source, 16 + phase)
	painter.rebuild()
	_check(painter.active_count() == 20, "Impact aliases retain marks independently at all three fade stages")
	_check(painter.get_stats()["draw_commands"] <= 12, "All seven weapons remain within the existing twelve impact draw commands")
	painter.clear()
	_check(painter.get_stats()["free_marks"] == 32 and painter.active_count() == 0, "Impact aliases reuse the original bounded pool")


func _test_cached_sigil_equivalence() -> void:
	var painter = PROJECTILE_SCRIPT.new()
	var original_templates: String = JSON.stringify(painter._sigil_shapes)
	for source: String in ["crescent", "storm", "comet"]:
		for angle: float in [0.0, 0.31, 0.9, 2.7, 5.9]:
			for radius: float in [1.0, 11.0, 19.0]:
				var shot := CombatSim.Shot.new()
				shot.source = source
				shot.position = Vector2(342.25, 390.75)
				shot.radius = radius
				var direction: Vector2 = Vector2.from_angle(angle)
				var expected: PackedVector2Array = _original_sigil(shot, direction)
				var actual := PackedVector2Array()
				painter._append_sigil(actual, shot, direction)
				var equivalent: bool = actual.size() == expected.size()
				for index: int in mini(actual.size(), expected.size()):
					equivalent = equivalent and actual[index].distance_squared_to(expected[index]) < 0.000001
				_check(equivalent, "Cached native transforms preserve the authored endpoint order and position: %s %.2f %.0f" % [source, angle, radius])
	_check(JSON.stringify(painter._sigil_shapes) == original_templates, "Per-projectile native transforms never mutate cached local silhouettes")


static func _original_sigil(shot: CombatSim.Shot, direction: Vector2) -> PackedVector2Array:
	# Frozen mathematical oracle from the initial authored version. This protects
	# handedness, endpoint ordering and radius scaling during CPU preparation changes.
	var points := PackedVector2Array()
	var side: Vector2 = direction.orthogonal()
	if shot.source == "crescent":
		var center: Vector2 = shot.position - direction * 5.0
		for index: int in 8:
			var angle_a: float = -PI * 0.5 + float(index) * PI / 8.0
			var angle_b: float = -PI * 0.5 + float(index + 1) * PI / 8.0
			for depth: float in [12.0, 6.0]:
				points.append(center + direction * cos(angle_a) * depth + side * sin(angle_a) * 10.0)
				points.append(center + direction * cos(angle_b) * depth + side * sin(angle_b) * 10.0)
	elif shot.source == "storm":
		for sign_value: float in [-1.0, 1.0]:
			var offsets: Array[Vector2] = [Vector2(-11, sign_value * 3), Vector2(-4, sign_value * 6),
				Vector2(-6, sign_value), Vector2(5, 0)]
			for index: int in 3:
				points.append(shot.position + direction * offsets[index].x + side * offsets[index].y)
				points.append(shot.position + direction * offsets[index + 1].x + side * offsets[index + 1].y)
	elif shot.source == "comet":
		var radius: float = shot.radius + 3.0
		for index: int in 5:
			var axis: Vector2 = direction.rotated(float(index) * TAU / 5.0)
			var next_axis: Vector2 = direction.rotated((float(index) + 0.5) * TAU / 5.0)
			var end_axis: Vector2 = direction.rotated(float(index + 1) * TAU / 5.0)
			points.append(shot.position + axis * radius)
			points.append(shot.position + next_axis * radius * 0.43)
			points.append(shot.position + next_axis * radius * 0.43)
			points.append(shot.position + end_axis * radius)
	return points


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
	_check(world.content_stress_mode and world.stress_weapon_ids.size() == 7, "The explicit content pressure fixture includes all seven catalog weapons")
	var sources: Dictionary = {}
	var runes: Dictionary = {}
	var positive: int = 0
	for shot: CombatSim.Shot in world.sim.shots:
		if shot.active and not shot.hostile:
			sources[shot.source] = true
			runes[shot.rune] = true
			if shot.damage > 0.0:
				positive += 1
	_check(positive == 600 and sources.size() == 7 and runes.size() == 3, "The fixture contains six hundred positive-damage friendly shots across seven sources and three runes")
	var before: String = _signature(world.sim)
	var painter = PROJECTILE_SCRIPT.new()
	painter.rebuild(world.sim.shots)
	var stats: Dictionary = painter.get_stats()
	_check(stats["friendly_count"] == 600 and stats["family_counts"].size() == 21, "The projectile painter retains all twenty-one content pressure families")
	_check(stats["allocated_instances"] <= 4800 and stats["total_visible_instances"] <= 4800, "The full content pressure fixture preserves the original 4800-instance budget")
	_check(_signature(world.sim) == before, "Content pressure render preparation does not mutate RNG, shots, or simulation")
	world.queue_free()
	sound.queue_free()
	await _settle()


func _test_full_shop() -> void:
	var state := RunState.new()
	state.begin(20261023, "bone")
	state.collect_souls(4000)
	for id: String in ["crescent", "storm", "comet"]:
		_check(_purchase(state, "weapon", GameCatalog.weapon(id)), "The shop fixture legally buys new weapon " + id)
	for id: String in ["pierce", "bounce", "blast", "pierce"]:
		_check(_purchase(state, "rune", GameCatalog.rune(id)), "The shop fixture legally fills the reserve with " + id)
	for definition: ContentDef in GameCatalog.relics():
		for stack: int in RunState.RELIC_CAP:
			_check(_purchase(state, "relic", definition), "The shop fixture legally buys relic stack %s/%d" % [definition.id, stack + 1])
	state.offers = [
		{"kind": "weapon", "id": "crescent", "price": 26, "sold": false},
		{"kind": "weapon", "id": "storm", "price": 28, "sold": false},
		{"kind": "relic", "id": "moon_charm", "price": 24, "sold": false},
		{"kind": "relic", "id": "hourglass", "price": 24, "sold": false},
	]
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	for id: String in NEW_IDS:
		var definition: ContentDef = GameCatalog.weapon(id) if GameCatalog.weapon(id) != null else GameCatalog.relic(id)
		var texture: Texture2D = ui._icon_texture(definition)
		_check(texture != null and texture.get_width() == 64 and texture.get_height() == 64, "The new icon resolves at its declared native size: " + id)
	ui.show_shop()
	await _settle()
	var scroll: ScrollContainer = ui.find_child("RelicInventoryScroll", true, false)
	var grid: GridContainer = ui.find_child("RelicInventoryGrid", true, false)
	_check(scroll != null and grid != null and grid.get_child_count() == 10, "Every owned relic has a named, counted inspection control")
	if scroll != null and grid != null:
		var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
		_check(scrollbar.max_value > scrollbar.page and scroll.follow_focus, "The ten-relic inventory scrolls and follows keyboard focus")
		_check(root.get_visible_rect().encloses(scroll.get_global_rect()), "The relic inventory viewport remains fully inside 720p")
		var last: Button = grid.get_child(grid.get_child_count() - 1)
		last.grab_focus()
		await _settle()
		_check(scroll.get_global_rect().grow(1).encloses(last.get_global_rect()), "Keyboard focus scrolls the final relic into view")
		_check(last.tooltip_text.contains(GameCatalog.relic("hourglass").description), "Relic details retain the complete formal tradeoff description")
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
		var details: Label = ui.find_child("RelicDetailsDescription", true, false)
		_check(details != null and details.text.contains(GameCatalog.relic("hourglass").description), "Pressing Enter on an inspection control exposes its full description")
		_check(details != null and root.get_visible_rect().encloses(details.get_global_rect()) and details.size.y >= details.get_minimum_size().y, "The full tradeoff text is actually readable inside its native dialog")
		_check(state.summary() == before, "Inspecting an owned relic never mutates currency, stacks, or inventory")
		_check(ui.handle_back(), "Escape closes relic details without pausing the shop")
		await _settle()
		_check(root.gui_get_focus_owner() == last, "Closing relic details restores keyboard focus to the inspected inventory item")
	var offer: Control = ui.find_child("Offer1", true, false)
	var description: Label = offer.find_child("OfferDescription", true, false) if offer != null else null
	_check(description != null and description.text.contains("首目标") and description.text.contains("第二目标") and description.tooltip_text == GameCatalog.weapon("crescent").description, "The compact moon-scythe card preserves the first-target and second-target rules, with the full explanation in its tooltip")
	_check(offer != null and root.get_visible_rect().encloses(offer.get_global_rect()), "The moon-scythe shop card fits inside the full native layout")
	var next: Button = ui._shop_focus_button("next_wave")
	_check(next != null and root.get_visible_rect().encloses(next.get_global_rect()), "The full ten-relic build leaves the next-wave action fully visible inside 720p")
	_check(_buttons_inside(ui), "Every control in the fully populated shop remains inside the reference viewport")
	ui.queue_free()
	await _settle()


func _purchase(state: RunState, kind: String, definition: ContentDef) -> bool:
	state.offers = [{"kind": kind, "id": definition.id, "price": definition.price, "sold": false}]
	return state.buy_offer(0)


func _buttons_inside(node: Node) -> bool:
	if node is Button and node.is_visible_in_tree() and not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
		return false
	for child: Node in node.get_children():
		if not _buttons_inside(child):
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
