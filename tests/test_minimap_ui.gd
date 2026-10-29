extends SceneTree
## Real HUD layout and immutable minimap snapshots across viewports and input.

const BOUNDS: Rect2 = Rect2(-1082, -535, 3444, 1800)
var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

class InputProbe extends Node:
	var pointer: bool = false
	var movement: bool = false
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			pointer = true
		elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_W:
			movement = true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_test_projection_and_validation()
	_test_bounded_markers()
	_test_interaction_markers()
	var state := RunState.new()
	state.begin(20261028, "bone", "mire")
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(state)
	await _test_hud_layouts()
	await _test_input_and_pause()
	await _test_lifecycle()
	_ui.queue_free()
	await process_frame
	print("MinimapUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _map_snapshot() -> Dictionary:
	return {"bounds": BOUNDS, "player": BOUNDS.get_center(), "facing": Vector2.RIGHT,
		"view": Rect2(BOUNDS.get_center() - Vector2(640, 360), Vector2(1280, 720)),
		"arena_id": "mire", "zones": [{"center": Vector2(310, 275), "radius": Vector2(150, 68)}],
		"obstacles": [{"center": Vector2(200, 560), "radius": 30.0}, {"center": Vector2(-650, -220), "radius": 36.0}],
		"enemies": [{"position": Vector2(740, 365), "boss": false, "hunter": false},
			{"position": Vector2(1060, 500), "boss": true, "hunter": false},
			{"position": Vector2(250, 600), "boss": false, "hunter": true}]}

func _hud_snapshot(boss: bool = false) -> Dictionary:
	return {"health": 100.0, "max_health": 100.0, "wave": 8 if boss else 1, "time_left": 45.0,
		"gold": 0, "level": 1, "xp": 0, "xp_needed": 42, "loadout": _ui.run.loadout,
		"boss_health": 100.0 if boss else 0.0, "boss_max_health": 200.0 if boss else 0.0,
		"minimap": _map_snapshot()}

func _map() -> MinimapView:
	return _ui._hud["minimap"] as MinimapView

func _test_projection_and_validation() -> void:
	var map := MinimapView.new()
	map.size = Vector2(192, 126)
	var value: Dictionary = _map_snapshot()
	map.update_snapshot(value)
	var area: Rect2 = map.map_rect()
	_check(map.presentation_snapshot()["valid"] and map.visible, "A valid world snapshot enables the map without requiring a frame loop")
	_check(area.has_area() and Rect2(Vector2.ZERO, map.size).encloses(area), "The aspect-fitted map remains inside its own control")
	_check(is_equal_approx(area.size.x / area.size.y, BOUNDS.size.x / BOUNDS.size.y), "World projection preserves the larger map's aspect ratio")
	_check(map.world_to_map(BOUNDS.position).is_equal_approx(area.position) and map.world_to_map(BOUNDS.end).is_equal_approx(area.end), "Negative world origins and both outer corners map exactly")
	_check(map.world_to_map(BOUNDS.get_center()).is_equal_approx(area.get_center()), "The unchanged world center remains centered in the full map")
	_check(map.world_to_map(BOUNDS.end + Vector2(10000, 10000)).is_equal_approx(area.end), "Out-of-bounds projection clamps before applying map scale")
	_check(map.world_to_map(Vector2.INF) == Vector2.ZERO, "Nonfinite diagnostic projection never reaches draw geometry")
	var saved: Dictionary = map.presentation_snapshot()
	value["enemies"][0]["position"] = Vector2.INF
	value["zones"][0]["radius"] = Vector2.INF
	value["obstacles"][0]["radius"] = INF
	saved["enemies"].clear()
	saved["obstacles"].clear()
	_check(map.presentation_snapshot()["enemy_count"] == 3 and map.presentation_snapshot()["zones"][0]["radius"] == Vector2(150, 68), "Input data and returned snapshots cannot mutate the retained render state")
	_check(map.presentation_snapshot()["obstacle_count"] == 2 and map.presentation_snapshot()["obstacles"][0]["radius"] == 30.0, "Input and returned obstacle geometry are isolated from retained render state")
	for invalid: Variant in [null, {}, "bad", {"bounds": Rect2(0, 0, 0, 2), "player": Vector2.ZERO}, {"bounds": Rect2(Vector2.ZERO, Vector2(INF, 100)), "player": Vector2.ZERO}, {"bounds": BOUNDS, "player": Vector2.INF}]:
		map.update_snapshot(invalid)
		_check(not map.presentation_snapshot()["valid"] and not map.visible and map.presentation_snapshot()["enemy_count"] == 0, "Malformed snapshots clear the prior map rather than leaving ghost markers")
	value = _map_snapshot()
	value["player"] = BOUNDS.end + Vector2(400, 400)
	value["facing"] = Vector2(NAN, 0)
	value["view"] = Rect2(Vector2(INF, 0), Vector2(1, 1))
	value["enemies"].append_array([null, {"position": Vector2.INF}, {"position": BOUNDS.end + Vector2.ONE}])
	value["zones"].append_array([{}, {"center": Vector2.ZERO, "radius": Vector2(-1, 1)}, {"center": Vector2.INF, "radius": Vector2.ONE}])
	value["obstacles"].append_array([{}, null, {"center": Vector2.ZERO, "radius": -1}, {"center": Vector2.INF, "radius": 30}, {"center": Vector2.ZERO, "radius": INF}, {"center": Vector2.ZERO, "radius": "30"}, {"center": BOUNDS.end + Vector2.ONE, "radius": 1}, {"center": Vector2.ZERO, "radius": 10000}, {"center": BOUNDS.end, "radius": 10}])
	map.update_snapshot(value)
	var clean: Dictionary = map.presentation_snapshot()
	_check(clean["valid"] and clean["player"] == BOUNDS.end and clean["facing"] == Vector2.UP and not (clean["view"] as Rect2).has_area(), "Optional malformed direction and view values fall back without invalidating a real player")
	_check(clean["enemy_count"] == 3 and clean["zone_count"] == 1, "Invalid and off-map entities never create misleading edge markers")
	_check(clean["obstacle_count"] == 2, "Invalid obstacle centers, nonnumeric/negative/nonfinite/oversized radii never reach rendering")
	map.free()

func _test_bounded_markers() -> void:
	var map := MinimapView.new()
	map.size = Vector2(192, 126)
	var value: Dictionary = _map_snapshot()
	var enemies: Array[Dictionary] = []
	for index: int in 500:
		enemies.append({"position": Vector2(400 + index, 350), "boss": false, "hunter": false})
	enemies.append({"position": Vector2(1000, 300), "boss": true, "hunter": false})
	enemies.append({"position": Vector2(1000, 500), "boss": false, "hunter": true})
	value["enemies"] = enemies
	var zones: Array[Dictionary] = []
	for index: int in 100:
		zones.append({"center": Vector2(400 + index, 300), "radius": Vector2(30, 20)})
	value["zones"] = zones
	var obstacles: Array[Dictionary] = []
	for index: int in 100:
		obstacles.append({"center": Vector2(200 + index, 560), "radius": 30.0})
	value["obstacles"] = obstacles
	map.update_snapshot(value)
	var snapshot: Dictionary = map.presentation_snapshot()
	_check(snapshot["enemy_count"] == MinimapView.ENEMY_LIMIT and snapshot["zone_count"] == MinimapView.ZONE_LIMIT, "Crowded snapshots retain a fixed marker and terrain budget")
	_check(snapshot["obstacle_count"] == MinimapView.OBSTACLE_LIMIT, "Obstacle draw work has a fixed snapshot budget")
	_check(snapshot["enemies"][0]["boss"] and snapshot["enemies"][1]["hunter"], "Boss and hunter remain visible when ordinary enemy dots reach capacity")
	value = _map_snapshot()
	value["view"] = Rect2(BOUNDS.position - Vector2.ONE * 300, BOUNDS.size + Vector2.ONE * 600)
	map.update_snapshot(value)
	_check((map.presentation_snapshot()["view"] as Rect2).is_equal_approx(BOUNDS), "An oversized camera view is clipped to real map bounds")
	map.free()

func _test_interaction_markers() -> void:
	var map := MinimapView.new()
	map.size = Vector2(192, 126)
	var value: Dictionary = _map_snapshot()
	value["obstacles"].append_array([
		{"center": BOUNDS.get_center(), "radius": 18.0, "kind": "crate", "active": true},
		{"center": BOUNDS.get_center() + Vector2(80, 0), "radius": 18.0, "kind": "crate", "active": false},
	])
	value["pinball_active"] = true
	value["pickups"] = [{"position": Vector2(0, 0), "kind": "health"}, {"position": Vector2(80, 0), "kind": "charge"}, {"position": Vector2(160, 0), "kind": "gold"},
		null, {"position": Vector2.INF, "kind": "gold"}, {"position": BOUNDS.end + Vector2.ONE, "kind": "health"}, {"position": Vector2.ZERO, "kind": "unknown"}, {"position": Vector2.ZERO, "kind": "gold", "active": false}]
	map.update_snapshot(value)
	var retained: Dictionary = map.presentation_snapshot()
	_check(retained["crate_count"] == 1 and retained["obstacle_count"] == 3, "The minimap includes only active breakable colliders beside ordinary scenery")
	_check(retained["pickup_count"] == 3 and retained["pinball_active"], "Only actual finite gold, health and charge positions produce pickup markers")
	retained["pickups"].clear()
	value["pickups"][0]["position"] = Vector2.INF
	_check(map.presentation_snapshot()["pickup_count"] == 3 and map.presentation_snapshot()["pickups"][0]["position"] == Vector2.ZERO, "Caller and returned pickup snapshots cannot mutate retained map state")
	var crowd: Array[Dictionary] = []
	for index: int in 500:
		crowd.append({"position": Vector2(index, 100), "kind": "gold"})
	value["pickups"] = crowd
	map.update_snapshot(value)
	_check(map.presentation_snapshot()["pickup_count"] == MinimapView.PICKUP_LIMIT and map.presentation_snapshot()["pickup_limit"] == 24, "Dense drop snapshots keep a strict bounded pickup draw budget")
	map.update_snapshot({})
	_check(map.presentation_snapshot()["pickup_count"] == 0 and map.presentation_snapshot()["crate_count"] == 0 and not map.presentation_snapshot()["pinball_active"], "A replaced or invalid map cannot retain ghost drops, broken crates or ball state")
	map.free()

func _test_hud_layouts() -> void:
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		_ui.show_hud()
		for boss: bool in [false, true]:
			_ui.update_hud(_hud_snapshot(boss))
			await _settle()
			var minimap: MinimapView = _map()
			var area: Rect2 = minimap.get_global_rect()
			var status := _ui.find_child("RitualStatus", true, false) as Control
			var equipment := _ui.find_child("RitualEquipment", true, false) as Control
			_check(minimap.visible and minimap.presentation_snapshot()["enemy_count"] == 3, "A real HUD snapshot feeds terrain and enemy markers at " + str(physical_size))
			_check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(area) and area.position.y >= 104.0 and area.size.is_equal_approx(Vector2(192, 126)), "The minimap stays anchored inside the reference viewport with its compact budget")
			_check(not area.intersects(status.get_global_rect()) and not area.intersects(equipment.get_global_rect()), "The map never overlaps status or equipped skill controls")
			if boss:
				_check(not area.intersects((_ui._hud["boss"] as Control).get_global_rect()), "Boss health stays separate from the map")
			_check(minimap.mouse_filter == Control.MOUSE_FILTER_IGNORE and minimap.focus_mode == Control.FOCUS_NONE and minimap.get_child_count() == 0, "The map has no labels, legend controls or focus targets")
			_check(not minimap.is_processing() and not minimap.is_physics_processing() and minimap.get_signal_connection_list("gui_input").is_empty(), "HUD events update the map without polling or input handlers")

func _test_input_and_pause() -> void:
	root.size = Vector2i(1280, 720)
	_ui.update_hud(_hud_snapshot())
	await _settle()
	var probe := InputProbe.new()
	root.add_child(probe)
	var focused: Control = root.gui_get_focus_owner()
	var point: Vector2 = _map().get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	var click := InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click)
	await process_frame
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = true
	root.push_input(key)
	await process_frame
	key = key.duplicate()
	key.pressed = false
	root.push_input(key)
	await process_frame
	_check(probe.pointer and probe.movement and root.gui_get_focus_owner() == focused, "Clicking the map does not steal movement, pointer events or keyboard focus")
	var before: Dictionary = _map().presentation_snapshot()
	paused = true
	await _settle()
	_check(_map().presentation_snapshot() == before, "Paused HUD map state cannot advance without a new authoritative snapshot")
	paused = false
	probe.queue_free()
	await _settle()

func _test_lifecycle() -> void:
	var without_map: Dictionary = _hud_snapshot()
	without_map.erase("minimap")
	_ui.update_hud(without_map)
	_check(not _map().visible and not _map().presentation_snapshot()["valid"], "Legacy snapshots never leave a stale map visible")
	_ui.update_hud(_hud_snapshot())
	_check(_map().visible, "A valid snapshot restores the map after absent data")
	_ui.show_title({})
	await _settle()
	_check(_ui.find_child("ArenaMinimap", true, false) == null, "Leaving combat frees the map instead of overlaying menu art")
	_ui.show_hud()
	await _settle()
	_check(not _map().visible and _map().presentation_snapshot()["enemy_count"] == 0, "A new HUD starts without the previous wave's enemy dots")
