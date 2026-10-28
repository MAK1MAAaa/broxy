extends SceneTree
## Skill relics expose their real tradeoffs without adding another combat clock or focus target.

class InputProbe:
	extends Node
	var keys: Array[int] = []
	var clicks: int = 0

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			keys.append(int(event.physical_keycode))

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			clicks += 1

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_ui = GameUI.new()
	root.add_child(_ui)
	await _test_relic_tables_and_details()
	await _test_hud_and_input()
	_ui.queue_free()
	await process_frame
	print("SkillRelicUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone", "mire")
	state.gold = 3000
	return state

func _offer(state: RunState, id: String) -> void:
	state.offers = [{"kind": "relic", "id": id, "price": 22, "sold": false}]

func _buy(state: RunState, id: String) -> int:
	_offer(state, id)
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	_check(state.buy_offer(0), "The UI fixture buys its physical skill relic through RunState: " + id)
	return uid

func _test_relic_tables_and_details() -> void:
	for id: String in ["fold_clasp", "echo_stone"]:
		var state: RunState = _state()
		var first: int = _buy(state, id)
		var second: int = _buy(state, id)
		var definition: ContentDef = GameCatalog.relic(id)
		var texture: Texture2D = _ui._icon_texture(definition)
		_check(texture != null and texture.get_width() == 64 and texture.get_height() == 64, "Each new relic has its own usable centered 64-pixel icon: " + id)
		_offer(state, id)
		_ui.bind(state)
		_ui.show_shop()
		await _settle()
		_ui._bp_select(first, _ui._shop_epoch)
		await _settle()
		var footprint := _ui.find_child("BackpackFootprint", true, false) as Label
		var detail: String = _ui._backpack_effect_text(state.backpack_item(first))
		var merge := _ui.find_child("BackpackMergePreview", true, false) as Label
		_check(footprint != null and footprint.text == "占格 1×1", "The selected skill relic occupies one real backpack cell: " + id)
		if id == "fold_clasp":
			_check(detail.contains("冲刺冷却 -0.3秒") and detail.contains("移速 -6") and detail.contains("最低1.2秒"), "Clasp details preserve the fractional cooldown benefit, movement cost and lower limit")
			_check(merge != null and merge.text.contains("-0.3秒 → -0.6秒") and merge.text.contains("-6 → -12"), "The clasp merge forecast shows rank scaling without rounding seconds to zero")
		else:
			_check(detail.contains("脉冲半径 +18") and detail.contains("脉冲冷却 +0.8秒") and detail.contains("上限216"), "Stone details state the enlarged pulse, longer cooldown and actual range cap")
			_check(merge != null and merge.text.contains("+18 → +36") and merge.text.contains("+0.8秒 → +1.6秒"), "The stone merge forecast keeps the positive range and cooldown cost separate")
		var compare: Button = _ui._shop_focus_button("compare:0")
		_check(compare != null, "Skill relic purchases retain the standard comparison action: " + id)
		if compare != null:
			compare.pressed.emit()
		await _settle()
		_check(_ui._overlay_mode == "relic_comparison", "The real comparison callback opens its existing focus-isolated overlay: " + id)
		if id == "fold_clasp":
			_assert_change("dash_cooldown", "0.3", "减少", GameUI.CYAN)
			_assert_change("move_speed", "6", "减少", GameUI.RED)
		else:
			_assert_change("pulse_radius", "18", "增加", GameUI.CYAN)
			_assert_change("pulse_cooldown", "0.8", "增加", GameUI.RED)
		for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
			root.size = physical_size
			await _settle()
			var scroll := _ui.find_child("ComparisonScroll", true, false) as ScrollContainer
			var close := _ui.find_child("CloseRelicComparison", true, false) as Button
			_check(scroll != null and close != null and root.get_visible_rect().encloses(scroll.get_global_rect()) and root.get_visible_rect().encloses(close.get_global_rect()), "The skill comparison and return control fit the actual scaled window: %s / %s" % [id, physical_size])
			if scroll != null:
				_check((scroll.get_child(0) as Control).get_combined_minimum_size().x <= scroll.size.x + 1.0, "Skill labels and seconds do not introduce horizontal clipping: " + id)
		_ui.hide_pause()
		_check(state.merge_items(second, first), "A real merge promotes the skill relic while preserving combined global effects: " + id)
		await _settle()
		var ranked: String = _ui._backpack_effect_text(state.backpack_item(first))
		_check(ranked.contains("-0.6秒") if id == "fold_clasp" else ranked.contains("+36") and ranked.contains("+1.6秒"), "The selected merged relic immediately shows its second-rank contribution: " + id)
		if id == "fold_clasp":
			_buy(state, id)
			_buy(state, id)
			_offer(state, id)
			_ui.show_shop()
			await _settle()
			_ui._shop_focus_button("compare:0").pressed.emit()
			await _settle()
			_assert_change("dash_cooldown", "保持不变", "保持不变", GameUI.MUTED)
			_assert_change("move_speed", "6", "减少", GameUI.RED)
			_ui.hide_pause()
	root.size = Vector2i(1280, 720)

func _assert_change(key: String, amount: String, direction: String, expected: Color) -> void:
	var change := _ui.find_child("ComparisonStat_" + key, true, false) as Label
	_check(change != null and change.text.contains(amount) and change.text.contains(direction) and change.get_theme_color("font_color").is_equal_approx(expected), "The comparison describes the actual benefit or cost with correct direction, precision and color: " + key)

func _test_hud_and_input() -> void:
	var state: RunState = _state()
	var clasp: int = _buy(state, "fold_clasp")
	var stone: int = _buy(state, "echo_stone")
	state.offers = [{"kind": "skill", "id": "pulse", "price": 0}]
	_check(state.buy_offer(0), "The skill-lifetime fixture equips an actual backpack pulse")
	var skill_item: Dictionary = state.active_skills[0]
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	_ui.bind(state)
	_ui.show_hud()
	_ui.update_hud(sim.snapshot())
	await _settle()
	_check((_ui._hud["dash"] as Control).tooltip_text.contains("冷却2.1秒"), "The ready dash tooltip reads its actual relic-modified cooldown")
	_check((_ui._hud["pulse"] as Control).tooltip_text.contains("范围162") and (_ui._hud["pulse"] as Control).tooltip_text.contains("冷却8.8秒") and (_ui._hud["pulse_label"] as Label).text == "秘术脉冲" and (_ui._hud["pulse_key"] as Label).text == "Q", "The equipped pulse tooltip exposes both the range benefit and cooldown cost")
	sim.step(1.0 / 60.0, Vector2.RIGHT, true, true)
	for frame: int in 15:
		sim.step(1.0 / 60.0, Vector2.ZERO)
	_check(state.sell_item(clasp) and state.sell_item(stone), "The lifetime fixture changes its build through real relic sales")
	_ui.update_hud(sim.snapshot())
	await _settle()
	var dash: Dictionary = sim.dash_snapshot()
	var pulse: Dictionary = sim.pulse_snapshot()
	var dash_bar: ProgressBar = _ui._hud["dash_bar"]
	var pulse_bar: ProgressBar = _ui._hud["pulse_bar"]
	_check(is_equal_approx(dash_bar.value, 1.0 - float(dash["cooldown_left"]) / 2.1) and is_equal_approx(pulse_bar.value, 1.0 - float(pulse["cooldown_left"]) / 8.8), "Selling a modifier does not change either in-flight cooldown meter denominator")
	var dash_tip: String = (_ui._hud["dash"] as Control).tooltip_text
	var pulse_tip: String = (_ui._hud["pulse"] as Control).tooltip_text
	_check(dash_tip.contains("冷却2.4秒") and dash_tip.contains("本次冷却总长2.1秒"), "The dash hover separates the next build's cooldown from the active cast")
	var next_skill: Dictionary = state.active_skill_parameters(skill_item)
	_check(pulse_tip.contains("范围162") and pulse_tip.contains("冷却8.8秒") and is_equal_approx(float(next_skill["radius"]), 144.0) and is_equal_approx(float(next_skill["cooldown"]), 8.0), "The active skill HUD preserves the completed cast's parameters while the build projects the next cast independently")
	var frozen: Array = [dash_bar.value, pulse_bar.value, dash_tip, pulse_tip]
	paused = true
	await _settle()
	_check(frozen == [dash_bar.value, pulse_bar.value, (_ui._hud["dash"] as Control).tooltip_text, (_ui._hud["pulse"] as Control).tooltip_text], "Both modified HUD skills remain frozen without authoritative snapshots during pause")
	paused = false
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		await _settle()
		for key: String in ["dash", "pulse"]:
			var skill: Control = _ui._hud[key]
			var label: Label = _ui._hud[key + "_label"]
			_check(root.get_visible_rect().encloses(skill.get_global_rect()) and label.size.x + 0.1 >= label.get_minimum_size().x and skill.focus_mode == Control.FOCUS_NONE, "Modified skill indicators remain compact and readable at " + str(physical_size))
		_check(not _ui._hud.has("bag_info") and _ui.find_child("HUDMapInfo", true, false) == null and not _ui._toast.visible, "Skill growth keeps the removed combat descriptions and notifications absent")
	var probe := InputProbe.new()
	root.add_child(probe)
	var focus: Control = root.gui_get_focus_owner()
	var point: Vector2 = (_ui._hud["pulse"] as Control).get_global_rect().get_center()
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
	for code: Key in [KEY_W, KEY_SPACE, KEY_Q]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = true
		root.push_input(event)
		await process_frame
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
		await process_frame
	_check(probe.clicks == 1 and probe.keys.has(KEY_W) and probe.keys.has(KEY_SPACE) and probe.keys.has(KEY_Q), "The richer skill tooltips keep pointer, movement and both skill keys available to gameplay")
	_check(root.gui_get_focus_owner() == focus, "The skill growth HUD never steals keyboard focus")
	probe.queue_free()
	await _settle()
	for frame: int in 100:
		sim.step(0.1, Vector2.ZERO)
	_ui.update_hud(sim.snapshot())
	_check((_ui._hud["pulse_time"] as Label).text == "就绪" and (_ui._hud["pulse"] as Control).tooltip_text.contains("范围144") and (_ui._hud["pulse"] as Control).tooltip_text.contains("冷却8秒"), "After recovery the ready skill displays the current build's next-cast parameters")
