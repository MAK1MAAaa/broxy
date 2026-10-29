extends SceneTree
## Skill feedback follows simulation snapshots without reclaiming the concise HUD or input.

class InputProbe:
	extends Node
	var movement: bool = false
	var dash: bool = false
	var pointer: bool = false

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			movement = movement or event.physical_keycode == KEY_W
			dash = dash or event.physical_keycode == KEY_SPACE

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			pointer = true

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI
var _state: RunState

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_state = RunState.new()
	_state.begin(20261028, "bone", "mire")
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(_state)
	await _test_snapshot_states()
	await _test_input_passthrough()
	await _test_resolutions_and_boss()
	await _test_lifecycle()
	_ui.queue_free()
	await process_frame
	print("DashUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _snapshot() -> Dictionary:
	return {"health": 100.0, "max_health": 100.0, "wave": 1, "time_left": 45.0,
		"gold": 0, "level": 1, "xp": 0, "xp_needed": 42, "loadout": _state.loadout}

func _dash(ready: bool = true, active: bool = false, cooldown_left: float = 0.0, total: float = 2.4) -> Dictionary:
	return {"ready": ready, "active": active, "remaining": 0.2 if active else 0.0,
		"cooldown_left": cooldown_left, "cooldown_total": total, "direction": Vector2.RIGHT, "uses": 1}

func _update(dash: Dictionary) -> void:
	var value: Dictionary = _snapshot()
	value["dash"] = dash
	_ui.update_hud(value)

func _indicator() -> Control:
	return _ui._hud["dash"] as Control

func _label() -> Label:
	return _ui._hud["dash_label"] as Label

func _bar() -> ProgressBar:
	return _ui._hud["dash_bar"] as ProgressBar

func _test_snapshot_states() -> void:
	_ui.show_hud()
	_ui.update_hud(_snapshot())
	await _settle()
	_check(not _indicator().visible and _label().text.is_empty(), "Legacy snapshots without dash state do not add a false ready indicator")
	_update(_dash())
	await _settle()
	_check(_indicator().visible and _label().text == "冲刺 · 空格" and is_equal_approx(_bar().value, 1.0), "A ready snapshot names the action and its key with a full meter")
	var instruction: String = _indicator().tooltip_text
	_check(instruction.contains("空格") and instruction.contains("面向") and instruction.contains("132") and instruction.contains("2.4") and instruction.contains("减速"), "The optional tooltip explains direction, distance, cooldown and terrain escape")
	_check(_indicator().focus_mode == Control.FOCUS_NONE and _indicator().mouse_filter == Control.MOUSE_FILTER_PASS, "The hoverable skill wrapper never claims focus or stops pointer propagation")
	for child: Node in _indicator().get_children():
		_check(child is Control and child.focus_mode == Control.FOCUS_NONE and child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The skill label and meter are noninteractive")
	_check(_indicator().get_signal_connection_list("gui_input").is_empty(), "The skill does not attach an input handler that can accept gameplay events")
	_check(not _indicator().is_processing() and not _indicator().is_physics_processing() and _indicator().find_children("*", "Timer", true, false).is_empty(), "The skill has no per-frame countdown or timer")
	_update(_dash(false, true, 2.4))
	_check(_label().text == "冲刺中" and _bar().value == 0.0, "An active dash is distinct from ready and recovering states")
	_update(_dash(false, false, 1.8))
	_check(_label().text == "冲刺 1.8秒" and is_equal_approx(_bar().value, 0.25), "Cooldown seconds and meter use the same authoritative remaining time")
	var unchanged: Array = [_label().text, _bar().value]
	paused = true
	await _settle()
	_check(unchanged == [_label().text, _bar().value], "Without a new snapshot the skill cannot silently count down during a scene-tree pause")
	paused = false
	_update(_dash(false, false, 0.04))
	_check(_label().text == "冲刺 0.1秒" and _bar().value < 1.0, "A positive fractional cooldown is never rounded into a misleading zero-second ready state")
	_update(_dash(false, false, 0.0, 0.0))
	_check(_label().text == "冲刺" and _bar().value == 0.0, "An unavailable zero-duration state neither divides by zero nor advertises readiness")
	_update(_dash(false, false, NAN, NAN))
	_check(_label().text == "冲刺" and is_finite(_bar().value), "Malformed diagnostic timing does not produce non-finite progress")
	_update(_dash())
	_check(_label().text == "冲刺 · 空格" and _bar().value == 1.0, "A fresh ready snapshot fully restores feedback after recovery")
	var benchmark: Dictionary = _snapshot()
	benchmark["benchmark"] = true
	benchmark["dash"] = _dash()
	benchmark["enemies"] = 300
	benchmark["projectiles"] = 600
	_ui.update_hud(benchmark)
	_check(not _indicator().visible and _label().text.is_empty() and _bar().value == 0.0, "Benchmark mode suppresses and clears irrelevant skill information")
	_update(_dash())
	_check(_indicator().visible and _label().text == "冲刺 · 空格", "Returning to an ordinary snapshot restores the skill without rebuilding the HUD")
	var dead: Dictionary = _snapshot()
	dead["health"] = 0.0
	dead["dash"] = _dash(false, true, 2.4)
	_ui.update_hud(dead)
	_check(not _indicator().visible, "A zero-health terminal snapshot does not leave an active skill advertised")

func _key(code: Key) -> void:
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

func _test_input_passthrough() -> void:
	_update(_dash())
	await _settle()
	var probe := InputProbe.new()
	root.add_child(probe)
	var focused: Control = root.gui_get_focus_owner()
	var point: Vector2 = _indicator().get_global_rect().get_center()
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
	await process_frame
	await _key(KEY_W)
	await _key(KEY_SPACE)
	_check(probe.pointer and probe.movement and probe.dash, "Hovering and clicking the skill leaves movement, dash and pointer events available to gameplay")
	_check(root.gui_get_focus_owner() == focused, "The skill hover and click path cannot steal keyboard focus")
	probe.queue_free()
	await _settle()

func _test_resolutions_and_boss() -> void:
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		_ui.show_hud()
		await _settle()
		_check(root.size == physical_size and root.get_visible_rect().size.is_equal_approx(Vector2(1280, 720)), "The actual window uses the reference viewport at " + str(physical_size))
		for boss_alive: bool in [false, true]:
			var snapshot: Dictionary = _snapshot()
			snapshot["dash"] = _dash(false, false, 1.8)
			snapshot["wave"] = 8 if boss_alive else 1
			snapshot["boss_encounter"] = {"active": boss_alive, "health": 100.0, "max_health": 200.0,
				"display_name": GameCatalog.enemy("boss").display_name, "phase": "recovery"}
			_ui.update_hud(snapshot)
			await _settle()
			var status := _ui.find_child("RitualStatus", true, false) as Control
			var skill: Rect2 = _indicator().get_global_rect()
			var boss: Control = _ui._hud["boss"]
			_check(status.get_global_rect().grow(0.1).encloses(skill) and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(skill), "The compact skill remains fully inside the status panel: " + str(physical_size))
			_check(_indicator().size.x <= 108.0 and _bar().size.y >= 5.0 and _bar().size.y <= 6.0, "Skill width and meter height stay within the compact layout budget")
			_check(_label().size.x + 0.1 >= _label().get_minimum_size().x and _label().size.y + 0.1 >= _label().get_minimum_size().y, "The cooldown label is completely readable without clipping")
			_check(boss.visible == boss_alive and (not boss_alive or boss.get_global_rect() == Rect2(240, 104, 800, 50) and not boss.get_global_rect().intersects(skill)), "Boss health remains in its independent region below the topbar without overlapping the skill")
			_check(not _ui._hud.has("bag_info") and _ui.find_child("HUDMapInfo", true, false) == null, "A skill does not restore the removed lower-right descriptions")
			_ui.notify("空格冲刺与地图说明".repeat(12))
			_check(not _ui._toast.visible and _ui._toast.text.is_empty() and _ui._toast_timer.is_stopped(), "Skill updates preserve the removed battle notification area")

func _test_lifecycle() -> void:
	_ui.show_result(false, "试炼结束", {})
	await _settle()
	_check(_ui.find_child("DashSkill", true, false) == null, "The result screen removes the completed combat skill controls")
	_update(_dash())
	_check(_ui.find_child("DashSkill", true, false) == null, "A late combat snapshot cannot recreate skill controls over the result screen")
	_ui.show_hud()
	_update(_dash())
	await _settle()
	_check(_indicator().visible and _label().text == "冲刺 · 空格" and _bar().value == 1.0, "A new combat HUD does not retain the previous cooldown or active label")
