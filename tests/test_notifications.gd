extends SceneTree

var _checks: int = 0
var _failures: int = 0


class MovementKeyProbe:
	extends Node
	var received_movement: bool = false

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_W:
			received_movement = true


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	root.size = Vector2i(1280, 720)
	var state := RunState.new()
	state.begin(144, "ember")
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	await _test_combat_geometry(ui, state)
	await _test_lifetime_and_transitions(ui, state)
	paused = false
	ui.queue_free()
	await process_frame
	print("Notifications: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_combat_geometry(ui: GameUI, state: RunState) -> void:
	ui.show_hud()
	var snapshot: Dictionary = _snapshot(state)
	snapshot["boss_encounter"] = {"active": true, "health": 150.0, "max_health": 300.0,
		"display_name": GameCatalog.enemy("boss").display_name, "phase": "recovery"}
	ui.update_hud(snapshot)
	await _settle()
	var hud: Dictionary = ui.get("_hud")
	var notice: Label = ui.get("_toast")
	var timer: Timer = ui.get("_toast_timer")
	var status: Control = ui.find_child("RitualStatus", true, false)
	var equipment: Control = ui.find_child("RitualEquipment", true, false)
	var status_before: Rect2 = status.get_global_rect()
	var equipment_before: Rect2 = equipment.get_global_rect()
	var occupied_before: Dictionary = {}
	for key: String in ["health", "health_bar", "time", "gold", "level", "xp_bar", "slots"]:
		occupied_before[key] = hud[key].get_global_rect()
	var focused_before: Control = root.gui_get_focus_owner()
	var reachable_art: Rect2 = _reachable_player_art_bounds()
	for message: String in ["新一波通知", "这是用于验证战斗不会显示超长提示的文本。".repeat(30), "首行提示\n".repeat(20)]:
		ui.notify(message)
		await _settle()
		_check(not notice.visible and notice.text.is_empty(), "Combat ignores short, long and multiline notification text")
		_check(timer.is_stopped() and is_zero_approx(timer.time_left), "Ignored combat notifications never start a lifetime timer")
		_check(root.gui_get_focus_owner() == focused_before, "Ignored combat notifications never claim keyboard focus")
		_check(status.get_global_rect() == status_before and equipment.get_global_rect() == equipment_before, "Ignored messages leave both HUD panels unchanged")
		for key: String in occupied_before:
			var control: Control = hud[key]
			_check(control.get_global_rect() == occupied_before[key], "Ignored messages preserve HUD field geometry: " + key)
	var boss: Control = hud["boss"]
	var boss_bar: ProgressBar = hud["boss_bar"]
	_check(boss.visible and boss_bar.value == 150.0 and boss_bar.max_value == 300.0, "The clean combat HUD retains an accurate visible Boss health bar")
	_check(boss is BossHUD and boss.get_global_rect().end.y < 160.0 and boss.get_global_rect().get_center().x == 640.0, "Boss health occupies its own centered upper region")
	_check(_viewport_contains(boss.get_global_rect()) and not boss.get_global_rect().intersects(reachable_art), "The full Boss status clears the reachable player drawing bounds")
	for key: String in occupied_before:
		var control: Control = hud[key]
		var painted: Rect2 = _label_text_bounds(control) if control is Label else control.get_global_rect()
		_check(painted.has_area() and not boss.get_global_rect().intersects(painted), "Boss status preserves the painted HUD field: " + key)
	for node_name: String in ["BossHealthValue", "BossPhase", "BossSkillName", "BossCharge", "BossBreak"]:
		_check(boss.find_child(node_name, true, false) == null, "Boss health has no persistent number, phase or cast widget: " + node_name)
	var boss_name := boss.find_child("BossArrivalName", true, false) as Label
	_check(boss_name != null and not boss_name.visible, "An ordinary snapshot cannot repeat the arrival name")
	_check(_rect_contains(boss.get_global_rect(), boss_bar.get_global_rect()) and boss_bar.size.y >= 6.0, "The complete Boss health meter fits inside its status region")
	_check(notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.focus_mode == Control.FOCUS_NONE, "The hidden notification control never intercepts pointer or keyboard input")
	var probe := MovementKeyProbe.new()
	root.add_child(probe)
	var movement := InputEventKey.new()
	movement.physical_keycode = KEY_W
	movement.keycode = KEY_W
	movement.pressed = true
	root.push_input(movement)
	await _settle()
	_check(probe.received_movement, "Ignored notification calls leave movement keys available to gameplay")
	movement = movement.duplicate()
	movement.pressed = false
	root.push_input(movement)
	probe.queue_free()
	snapshot["boss_encounter"]["health"] = 0.0
	ui.update_hud(snapshot)
	_check(not boss.visible and not notice.visible and notice.text.is_empty(), "Defeating the Boss hides only its own status and never reveals a notification")


func _test_lifetime_and_transitions(ui: GameUI, state: RunState) -> void:
	var notice: Label = ui.get("_toast")
	var timer: Timer = ui.get("_toast_timer")
	ui.show_shop()
	await _settle()
	ui.notify("购买失败：魂屑不足。")
	_check(notice.visible and notice.text == "购买失败：魂屑不足。", "The shop still displays an actionable transaction failure")
	_check(timer.one_shot and is_equal_approx(timer.wait_time, 2.8) and timer.time_left > 2.7, "Shop notifications keep their one-shot 2.8-second lifetime")
	_check(notice.get_theme_font_size("font_size") == 12 and notice.get_global_rect().size.x == 860, "Shop feedback uses the native pixel font size within its established width")
	_check(notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.focus_mode == Control.FOCUS_NONE, "Shop feedback remains noninteractive")
	await create_timer(0.18).timeout
	ui.show_pause()
	paused = true
	await _settle()
	var pause_started: float = timer.time_left
	_check(notice.visible and ui.can_process() and timer.can_process(), "Pausing the shop preserves feedback and its always-processing timer")
	await create_timer(0.35, true).timeout
	_check(notice.visible and timer.time_left < pause_started - 0.25, "Shop feedback keeps counting while the scene tree is paused")
	await create_timer(2.0, true).timeout
	_check(notice.visible and timer.time_left > 0.0, "Paused shop feedback remains visible shortly before its deadline")
	await create_timer(0.5, true).timeout
	_check(not notice.visible and timer.is_stopped(), "Paused shop feedback expires after its own 2.8-second lifetime")
	ui.hide_pause()
	paused = false

	ui.notify("商店改装提示")
	await create_timer(0.4).timeout
	var old_remaining: float = timer.time_left
	ui.notify("符文已装入法器")
	_check(notice.visible and notice.text == "符文已装入法器" and timer.time_left > old_remaining + 0.3 and is_equal_approx(timer.wait_time, 2.8), "A replacement shop operation message restarts the full lifetime")
	await create_timer(2.45).timeout
	_check(notice.visible and timer.time_left > 0.0, "Replacing shop feedback prevents the old deadline from hiding the new message")
	await create_timer(0.55).timeout
	_check(not notice.visible and timer.is_stopped(), "Replacement shop feedback expires after its own deadline")

	ui.notify("进入战斗前的商店通知")
	_check(notice.visible and not timer.is_stopped(), "A genuine active shop message exists before the screen transition")
	ui.show_hud()
	ui.update_hud(_snapshot(state))
	await _settle()
	_check(not notice.visible and notice.text.is_empty() and timer.is_stopped(), "Returning to combat clears the old shop text and stops its timer")
	ui.notify("新一波通知")
	await _settle()
	_check(not notice.visible and notice.text.is_empty() and timer.is_stopped(), "A combat entry message cannot replace cleared shop feedback")
	ui.show_pause()
	paused = true
	ui.notify("暂停中的战斗通知")
	await _settle()
	_check(not notice.visible and notice.text.is_empty() and timer.is_stopped(), "Pausing combat does not restore its suppressed notification text")
	ui.hide_pause()
	paused = false
	await create_timer(2.95).timeout
	_check(not notice.visible and notice.text.is_empty() and timer.is_stopped(), "Old shop deadlines cannot make discarded text reappear in combat")
	ui.show_shop()
	await _settle()
	_check(not notice.visible and notice.text.is_empty() and timer.is_stopped(), "Reopening the shop does not resurrect old combat or shop notifications")
	ui.notify("可继续购买")
	_check(notice.visible and notice.text == "可继续购买" and timer.time_left > 2.7, "Fresh shop feedback remains available after returning from combat")


func _snapshot(state: RunState) -> Dictionary:
	return {"health": state.health, "max_health": state.stat("max_health"), "wave": 1, "time_left": 45.0,
		"gold": state.gold, "level": state.level, "xp": 1, "xp_needed": 10, "loadout": state.loadout}


func _reachable_player_art_bounds() -> Rect2:
	# Axis-clamped camera projection is bounded by its four reachable corners.
	var first: Vector2 = CombatSim.clamp_point(CombatSim.ARENA.position, 16.0)
	var last: Vector2 = CombatSim.clamp_point(CombatSim.ARENA.end, 16.0)
	var centers := Rect2(first - ArenaCatalog.visible_rect(first).position, Vector2.ZERO)
	for point: Vector2 in [first, Vector2(last.x, first.y), last, Vector2(first.x, last.y)]:
		centers = centers.expand(point - ArenaCatalog.visible_rect(point).position)
	# Conservative continuous envelope for CombatWorld._draw_player: texture
	# x +/-34, y -50..18; bob +/-2, lean +/-0.045, world shake +/-4.
	var body_x: float = 34.0 + 52.0 * sin(0.045)
	var body_y: float = 52.0 + 34.0 * sin(0.045)
	# Include glow (44 x 36), flattened seal, and weapon orbit (39 radius,
	# +/-3 vertical bob, 15 px rune arc) rather than just the player's hit circle.
	var horizontal: float = maxf(body_x, maxf(44.0, 39.0 + 15.0)) + 4.0
	var vertical: float = maxf(body_y, 39.0 + 3.0 + 15.0) + 4.0
	return Rect2(centers.position - Vector2(horizontal, vertical), centers.size + Vector2(horizontal, vertical) * 2.0)


func _label_text_bounds(label: Label) -> Rect2:
	# Character bounds come from the laid out Label, including its font fallback
	# and alignment. Nominal Control rectangles can contain large unused space.
	var bounds := Rect2()
	for character: int in label.text.length():
		var glyph: Rect2 = label.get_character_bounds(character)
		if not glyph.has_area():
			continue
		glyph.position += label.global_position
		bounds = bounds.merge(glyph) if bounds.has_area() else glyph
	return bounds


func _viewport_contains(rect: Rect2) -> bool:
	return _rect_contains(Rect2(Vector2.ZERO, Vector2(root.size)), rect)


func _rect_contains(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(0.01).encloses(inner)


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
