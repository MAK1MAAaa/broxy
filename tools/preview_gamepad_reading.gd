extends SceneTree
## Paid long-content fixtures and parsed shoulder-button input; no profile is loaded or saved.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const CASES: PackedStringArray = ["relic", "rune", "backpack", "result"]

var _app: Node

static func _purchase(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers.assign([{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}])
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	return uid if state.buy_offer(0) else -1

static func make_fixture() -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone")
	state.collect_souls(4000)
	if not state.expand_backpack() or not state.expand_backpack():
		return null
	var runes: Array[int] = []
	for copy: int in 4:
		var uid: int = _purchase(state, "rune", "bounce")
		if uid < 0:
			return null
		runes.append(uid)
	if not state.merge_items(runes[1], runes[0]) or not state.merge_items(runes[3], runes[2]) or not state.merge_items(runes[2], runes[0]) or not state.move_item(runes[0], Vector2i(5, 5), false):
		return null
	for copy: int in 8:
		if _purchase(state, "weapon", "bone") < 0:
			return null
	if _purchase(state, "weapon", "return_ring") < 0 or _purchase(state, "relic", "hourglass") < 0:
		return null
	var blast: int = _purchase(state, "rune", "blast")
	if blast < 0 or not state.equip_rune(state.rune_index_for_uid(blast), 9):
		return null
	state.wave = 4
	state.finish_wave()
	state.pending_upgrades = 0
	state.offers.clear()
	for entry: Array in [["relic", "hourglass"], ["weapon", "comet"], ["rune", "pierce"], ["relic", "echo_stone"]]:
		var definition: ContentDef = BackpackInventory.definition(str(entry[0]), str(entry[1]))
		state.offers.append({"kind": entry[0], "id": entry[1], "price": state.shop_price(definition), "sold": false})
	return state

static func make_result_fixture() -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone")
	state.collect_souls(4000)
	if not state.expand_backpack() or not state.expand_backpack():
		return null
	for id: String in ["frost", "ember", "crescent", "scatter", "storm", "comet", "return_ring"]:
		var uid: int = _purchase(state, "weapon", id)
		if uid < 0:
			return null
		if id == "comet" and not state.move_item(uid, Vector2i(4, 3), true):
			return null
	var simulation := CombatSim.new()
	simulation.begin(state)
	simulation.sandbox = true
	simulation._cooldowns.fill(9999.0)
	var target: CombatSim.Enemy = simulation.spawn_enemy("tank", simulation.player_position + Vector2(60, 0))
	if target == null:
		return null
	target.definition = target.definition.duplicate() as ContentDef
	target.definition.speed = 0.0
	target.health = 100000.0
	target.max_health = 100000.0
	target.action_timer = 9999.0
	for owned: Dictionary in state.loadout:
		var definition: ContentDef = GameCatalog.weapon(str(owned["id"]))
		simulation.fire_weapon(definition.id, "", simulation.player_position, Vector2.RIGHT)
		for frame: int in 24:
			simulation.step(1.0 / 60.0, Vector2.ZERO)
		if float(state.damage_dealt_by_weapon.get(definition.id, 0.0)) <= 0.0:
			return null
	state.take_damage(14.0, "caster", "projectile")
	state.pending_upgrades = 0
	return state

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var case_name: String = "relic"
	var output: String = ""
	var hold: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			hold = true
		else:
			quit(2)
			return
	if DisplayServer.get_name() == "headless" or case_name not in CASES or (not output.is_empty() and not output.to_lower().ends_with(".png")):
		push_error("Use native --case=relic|rune|backpack|result [--capture=path.png] [--hold]")
		quit(2)
		return
	if output.is_empty():
		output = "res://reports/gamepad-reading/%s.png" % case_name
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.args = PackedStringArray(["--autoplay"])
	_app.set_process(false)
	_app.sound.set_volume(0.0)
	_app.world.stop()
	_app.world.set_physics_process(false)
	var state: RunState = make_result_fixture() if case_name == "result" else make_fixture()
	if state == null:
		push_error("The reading fixture could not purchase and arrange its actual inventory")
		_app._quit_game(1)
		return
	_app.run = state
	_app.ui.bind(state)
	_app.screen = MAIN_SCRIPT.Screen.SHOP
	_app.ui.show_shop()
	await _settle()
	var scroll_name: String = "BackpackDetailsScroll"
	if case_name == "relic":
		await _activate("compare:0")
		scroll_name = "ComparisonScroll"
	elif case_name == "rune":
		await _activate("bag:%d" % int(state.rune_bag[0]["uid"]))
		await _activate("rune_preview:9")
		scroll_name = "RuneEquipScroll"
	elif case_name == "backpack":
		await _activate("bag:%d" % int(state.rune_bag[0]["uid"]))
		var source: Button = _action("reroll")
		if source != null:
			source.grab_focus()
	else:
		_app.screen = MAIN_SCRIPT.Screen.RESULT
		_app.ui.show_result(false, "固定构筑阅读验证：八类真实购买法器与实际命中记录。", {})
		scroll_name = "ResultBuildScroll"
		await _settle()
	var scroll := _app.ui.find_child(scroll_name, true, false) as ScrollContainer
	if scroll == null:
		push_error("Missing reading scroll: " + scroll_name)
		_app._quit_game(1)
		return
	var before: Dictionary = {"summary": state.summary(), "offers": state.offers.duplicate(true), "rng": state.rng.state}
	for page: int in 24:
		await _joy(JOY_BUTTON_RIGHT_SHOULDER)
		if scroll.scroll_vertical >= maxi(0, int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)):
			break
	var unchanged: bool = before == {"summary": state.summary(), "offers": state.offers.duplicate(true), "rng": state.rng.state}
	root.title = "秘术余烬 · 手柄翻页 / %s（固定构筑，不保存档案）" % case_name
	await _settle()
	await RenderingServer.frame_post_draw
	var result: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	var guide: Label = _app.ui._overlay.find_child("ReadingGuide", true, false) as Label
	if guide == null:
		guide = _app.ui._page.find_child("ReadingGuide", true, false) as Label
	var focus: Control = root.gui_get_focus_owner()
	print("GAMEPAD_READING_PREVIEW ", JSON.stringify({"case": case_name, "capture_result": result, "persistent_profile": _app.store.persistent, "fixture_passed": unchanged, "weapons": state.loadout.size(), "occupied_cells": state.backpack_snapshot()["used_cells"], "scroll": scroll_name, "scroll_position": scroll.scroll_vertical, "scroll_limit": maxi(0, int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)), "reading_guide": guide.text if guide != null else "", "focus": focus.name if focus != null else "", "connected_gamepads": Input.get_connected_joypads(), "synthetic_gamepad_events": true}))
	if not hold or result != OK or not unchanged:
		_app._quit_game(0 if result == OK and unchanged else 1)

func _action(id: String) -> Button:
	for node: Node in _app.ui.find_children("*", "Button", true, false):
		if str(node.get_meta("shop_focus_id", "")) == id:
			return node as Button
	return null

func _activate(id: String) -> void:
	var button: Button = _action(id)
	if button == null:
		push_error("Missing real reading fixture button: " + id)
		return
	button.grab_focus()
	await _joy(JOY_BUTTON_A)

func _joy(button: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await _settle()

func _settle() -> void:
	for frame: int in 5:
		await process_frame
