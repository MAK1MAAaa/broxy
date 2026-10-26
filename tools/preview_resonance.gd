extends SceneTree
## Isolated spatial-resonance fixtures; no profile or persistent store is instantiated.

const CASES: PackedStringArray = ["linked", "unlinked", "rotated", "full"]

class EscapeRouter:
	extends Node
	var ui: GameUI
	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and ui.handle_back():
			get_viewport().set_input_as_handled()

var _state: RunState
var _ui: GameUI

func _initialize() -> void:
	_preview.call_deferred()

static func make_fixture(case_name: String = "linked") -> RunState:
	assert(case_name in CASES, "Unknown resonance fixture")
	var state := RunState.new()
	state.begin(20261025, "bone")
	state.gold = 2500
	state.wave = 4
	assert(state.expand_backpack() and state.expand_backpack(), "The fixture pays for both backpack expansions")
	assert(state.move_item(1, Vector2i(1, 1), false), "Move the starter through a real transaction")
	var partner: int = _purchase(state, "weapon", "bone")
	assert(state.move_item(partner, Vector2i(4, 0), false))
	var ember: int = _purchase(state, "weapon", "ember")
	assert(state.move_item(ember, Vector2i(3, 4), false))
	var damage: int = _purchase(state, "relic", "damage")
	assert(state.move_item(damage, Vector2i(0, 1), false))
	var haste: int = _purchase(state, "relic", "haste")
	assert(state.move_item(haste, Vector2i(2, 2), false))
	var hourglass: int = _purchase(state, "relic", "hourglass")
	assert(state.move_item(hourglass, Vector2i(1, 4), false))
	var pierce: int = _purchase(state, "rune", "pierce")
	assert(state.equip_rune(state.rune_index_for_uid(pierce), 0))
	var bounce: int = _purchase(state, "rune", "bounce")
	assert(state.move_item(bounce, Vector2i(5, 4), false))
	var blast: int = _purchase(state, "rune", "blast")
	assert(state.move_item(blast, Vector2i(5, 5), false))
	if case_name == "unlinked":
		assert(state.move_item(damage, Vector2i(5, 0), false))
		assert(state.move_item(haste, Vector2i(5, 3), false))
		assert(state.move_item(hourglass, Vector2i(3, 3), false))
	elif case_name == "rotated":
		assert(state.move_item(1, Vector2i(1, 1), true))
	elif case_name == "full":
		for index: int in 36:
			if not state.backpack.can_add("relic", "armor"):
				break
			_purchase(state, "relic", "armor")
		assert(state.backpack_snapshot()["used_cells"] == 36, "The full fixture uses all real cells")
	state.offers = [_offer(state, "weapon", "bone"), _offer(state, "weapon", "storm"), _offer(state, "relic", "damage"), _offer(state, "rune", "blast")]
	return state

static func _offer(state: RunState, kind: String, id: String) -> Dictionary:
	return {"kind": kind, "id": id, "price": state.shop_price(BackpackInventory.definition(kind, id)), "sold": false}

static func _purchase(state: RunState, kind: String, id: String) -> int:
	state.offers = [_offer(state, kind, id)]
	assert(state.buy_offer(0), "Resonance fixtures use formal purchases: " + id)
	return int((state.backpack_snapshot()["items"] as Array).back()["uid"])

func _preview() -> void:
	var case_name: String = "linked"
	var capture: String = ""
	var hold: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			capture = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			hold = true
		else:
			_invalid()
			return
	if case_name not in CASES or DisplayServer.get_name() == "headless" or (not capture.is_empty() and not capture.to_lower().ends_with(".png")):
		_invalid()
		return
	if capture.is_empty():
		capture = "res://reports/resonance/%s.png" % case_name
	root.size = Vector2i(1280, 720)
	_state = make_fixture(case_name)
	_ui = GameUI.new()
	root.add_child(_ui)
	var escape := EscapeRouter.new()
	escape.ui = _ui
	root.add_child(escape)
	_ui.bind(_state)
	_ui.show_shop()
	for frame: int in 5:
		await process_frame
	_ui._bag_grid.select_item(1)
	var caption := Label.new()
	caption.text = "邻接共鸣固定验证 · 正式交易与摆放 · 非自然对局 · 不保存档案"
	caption.position = Vector2(420, 3)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", GameUI.CYAN)
	_ui._root.add_child(caption)
	root.title = "秘术余烬 · 邻接共鸣验证 / %s（固定构筑，不保存档案）" % case_name
	_state.changed.connect(_print_state.bind("changed"))
	_print_state("initial")
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(capture)
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error == OK:
		error = root.get_texture().get_image().save_png(path)
	var expected_bonus: float = {"linked": 0.09, "unlinked": 0.0, "rotated": 0.06, "full": 0.18}[case_name]
	var passed: bool = is_equal_approx(float(_state.loadout[0]["resonance_bonus"]), expected_bonus)
	print("RESONANCE_PREVIEW ", JSON.stringify({"case": case_name, "fixture_passed": passed,
		"fixed_fixture": true, "persistent_profile": false, "formal_transactions": true,
		"viewport": [1280, 720], "capture": capture, "capture_result": error,
		"backpack": _state.backpack_snapshot(), "loadout": _state.loadout, "hold": hold}))
	if not hold or not passed or error != OK:
		quit(0 if passed and error == OK else 1)

func _print_state(reason: String) -> void:
	print("RESONANCE_STATE ", JSON.stringify({"reason": reason, "ticks_ms": Time.get_ticks_msec(),
		"gold": _state.gold, "last_error": _state.last_error,
		"backpack": _state.backpack_snapshot(), "loadout": _state.loadout}))

func _invalid() -> void:
	push_error("Use native rendering, --case=linked|unlinked|rotated|full, optional --capture=<path.png> and --hold.")
	quit(2)
