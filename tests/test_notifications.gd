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
	snapshot["boss_health"] = 150.0
	snapshot["boss_max_health"] = 300.0
	ui.update_hud(snapshot)
	await _settle()
	var hud: Dictionary = ui.get("_hud")
	var notice: Label = ui.get("_toast")
	var status: Control = ui.find_child("RitualStatus", true, false)
	var equipment: Control = ui.find_child("RitualEquipment", true, false)
	var status_before: Rect2 = status.get_global_rect()
	var equipment_before: Rect2 = equipment.get_global_rect()
	var occupied_before: Dictionary = {}
	for key: String in ["health", "health_bar", "wave", "time", "gold", "level", "xp_bar", "slots"]:
		occupied_before[key] = hud[key].get_global_rect()
	ui.notify("购买失败：魂屑不足。")
	await _settle()
	var short_rect: Rect2 = notice.get_global_rect()
	var reachable_art: Rect2 = _reachable_player_art_bounds()
	_check(notice.visible and not notice.text.is_empty(), "Combat notifications become visible with their supplied message")
	_check(not short_rect.intersects(reachable_art), "Combat notices clear every reachable player drawing, including bob, lean, shake, glow and orbiting weapons")
	_check(_viewport_contains(short_rect), "The complete combat notice stays inside the logical viewport")
	_check(status.get_global_rect() == status_before and equipment.get_global_rect() == equipment_before, "Showing a notice does not resize either HUD panel")
	for key: String in occupied_before:
		var control: Control = hud[key]
		_check(control.get_global_rect() == occupied_before[key], "Notice leaves HUD field placement unchanged: " + key)
		var painted: Rect2 = _label_text_bounds(control) if control is Label else control.get_global_rect()
		_check(painted.has_area() and not short_rect.intersects(painted), "Notice preserves the painted HUD field: " + key)
	var boss: Control = hud["boss"]
	var boss_bar: ProgressBar = hud["boss_bar"]
	_check(boss.visible and boss_bar.value == 150.0 and boss_bar.max_value == 300.0, "A live boss retains an accurate visible health bar beside notifications")
	_check(_viewport_contains(boss.get_global_rect()) and not boss.get_global_rect().intersects(reachable_art), "The full boss status clears the same reachable player drawing bounds")
	_check(not short_rect.intersects(boss.get_global_rect()), "Combat notifications and the complete boss status do not overlap")
	for key: String in occupied_before:
		var control: Control = hud[key]
		var painted: Rect2 = _label_text_bounds(control) if control is Label else control.get_global_rect()
		_check(not boss.get_global_rect().intersects(painted), "Boss status preserves the painted HUD field: " + key)
	for node: Node in boss.get_children():
		if node is Label:
			_check(_label_text_bounds(node).has_area() and _rect_contains(boss.get_global_rect(), _label_text_bounds(node)), "Boss name fits completely inside its status region")
	_check(_rect_contains(boss.get_global_rect(), boss_bar.get_global_rect()) and boss_bar.size.y >= 6.0, "The complete boss health meter fits inside its status region")

	for message: String in ["这是用于验证超长战斗提示仍然单行省略的文本。".repeat(30), "首行完整提示\n".repeat(20)]:
		ui.notify(message)
		await _settle()
		_check(notice.text == message and notice.visible, "Long notifications retain the supplied message while displayed")
		_check(notice.get_global_rect() == short_rect, "Long or multiline messages retain the short notice's fixed geometry")
		_check(notice.clip_text and notice.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Overwide notification text uses clipping with an ellipsis")
		var visible_lines: int = notice.get_visible_line_count()
		_check(visible_lines == 1, "Embedded line breaks cannot expand the visible combat notice beyond one line")
		var style: StyleBox = notice.get_theme_stylebox("normal")
		var content_height: float = notice.size.y - style.get_content_margin(SIDE_TOP) - style.get_content_margin(SIDE_BOTTOM)
		_check(float(notice.get_line_height(0)) <= content_height + 0.01, "The notice's visible text line fits within its styled content height")
		_check(_viewport_contains(notice.get_global_rect()) and not notice.get_global_rect().intersects(reachable_art), "Long messages cannot escape the panel into the player drawing region")
		_check(status.get_global_rect() == status_before and equipment.get_global_rect() == equipment_before, "Long messages leave status and equipment panels unchanged")
	_check(notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.focus_mode == Control.FOCUS_NONE, "Combat notices neither consume pointer input nor enter keyboard focus")
	var probe := MovementKeyProbe.new()
	root.add_child(probe)
	var movement := InputEventKey.new()
	movement.physical_keycode = KEY_W
	movement.keycode = KEY_W
	movement.pressed = true
	root.push_input(movement)
	await _settle()
	_check(probe.received_movement, "A visible notification leaves movement keys available to gameplay")
	movement = movement.duplicate()
	movement.pressed = false
	root.push_input(movement)
	probe.queue_free()
	snapshot["boss_health"] = 0.0
	ui.update_hud(snapshot)
	_check(not boss.visible and notice.visible, "Defeating a boss hides its status without hiding an unrelated notice")


func _test_lifetime_and_transitions(ui: GameUI, state: RunState) -> void:
	var notice: Label = ui.get("_toast")
	var timer: Timer = ui.get("_toast_timer")
	ui.notify("暂停前的战斗通知")
	_check(timer.one_shot and is_equal_approx(timer.wait_time, 2.8) and timer.time_left > 2.7, "A notification starts its original one-shot 2.8-second lifetime")
	await create_timer(0.18).timeout
	ui.show_pause()
	paused = true
	await _settle()
	var pause_started: float = timer.time_left
	_check(notice.visible and ui.can_process() and timer.can_process(), "Pausing preserves the current notice and its always-processing lifetime")
	await create_timer(0.35, true).timeout
	_check(notice.visible and timer.time_left < pause_started - 0.25, "The existing notification timer keeps counting while paused")
	await create_timer(2.0, true).timeout
	_check(notice.visible and timer.time_left > 0.0, "The paused notification remains visible shortly before its 2.8-second deadline")
	await create_timer(0.5, true).timeout
	_check(not notice.visible and timer.is_stopped(), "The paused notification expires after its original 2.8-second lifetime")
	ui.hide_pause()
	paused = false

	ui.notify("过渡前的战斗通知")
	await _settle()
	var combat_rect: Rect2 = notice.get_global_rect()
	ui.show_shop()
	await _settle()
	_check(not notice.visible, "Changing from combat to shop hides the old combat notification")
	ui.notify("商店改装提示")
	await _settle()
	_check(notice.visible and notice.text == "商店改装提示", "The shop can immediately display its own notification after combat")
	_check(notice.get_global_rect().size.x > combat_rect.size.x and notice.get_theme_font_size("font_size") > 13, "Short shop notifications regain the established larger presentation")
	_check(notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.focus_mode == Control.FOCUS_NONE, "Restored shop notifications remain noninteractive")
	_check(is_equal_approx(timer.wait_time, 2.8) and timer.time_left > 2.6, "Shop notifications retain the same 2.8-second lifetime")
	ui.show_hud()
	ui.update_hud(_snapshot(state))
	await _settle()
	_check(not notice.visible, "Changing back to combat hides the previous shop notification")
	ui.notify("新一波通知")
	await _settle()
	_check(notice.get_global_rect() == combat_rect and notice.clip_text and notice.get_visible_line_count() == 1, "Returning to combat restores the compact single-line notice")
	await create_timer(0.4).timeout
	var old_remaining: float = timer.time_left
	ui.notify("替代旧通知")
	_check(notice.text == "替代旧通知" and timer.time_left > old_remaining + 0.3 and is_equal_approx(timer.wait_time, 2.8), "A replacement notice restarts the full 2.8-second lifetime")
	await create_timer(2.45).timeout
	_check(notice.visible and timer.time_left > 0.0, "Replacing a notice prevents the old deadline from hiding the new message")
	await create_timer(0.55).timeout
	_check(not notice.visible and timer.is_stopped(), "The replacement notice expires after its own deadline")


func _snapshot(state: RunState) -> Dictionary:
	return {"health": state.health, "max_health": state.stat("max_health"), "wave": 1, "time_left": 45.0,
		"gold": state.gold, "level": state.level, "xp": 1, "xp_needed": 10, "loadout": state.loadout}


func _reachable_player_art_bounds() -> Rect2:
	# CombatSim clamps the body center with a 16 px inset. The rendered texture
	# extends 50 px above that center; checking ARENA alone misses the masked face.
	var centers: Rect2 = Rect2(CombatSim.clamp_point(Vector2(-10000, -10000), 16.0), Vector2.ZERO)
	centers.end = CombatSim.clamp_point(Vector2(10000, 10000), 16.0)
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
