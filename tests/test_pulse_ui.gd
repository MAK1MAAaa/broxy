extends SceneTree
## The instant pulse shares the compact HUD without driving its own clock or consuming input.

class InputProbe:
	extends Node
	var movement: bool = false
	var dash: bool = false
	var pulse: bool = false
	var pointer_count: int = 0

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			movement = movement or event.physical_keycode == KEY_W
			dash = dash or event.physical_keycode == KEY_SPACE
			pulse = pulse or event.physical_keycode == KEY_Q

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			pointer_count += 1

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
	await _test_states_and_compatibility()
	await _test_input_passthrough()
	await _test_layouts()
	await _test_lifecycle()
	_ui.queue_free()
	await process_frame
	print("PulseUI: %d assertions, %d failures" % [_checks, _failures])
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
		"gold": 0, "level": 1, "xp": 0, "xp_needed": 42, "loadout": _state.loadout,
		"dash": {"ready": true, "active": false, "remaining": 0.0, "cooldown_left": 0.0,
			"cooldown_total": 2.4, "direction": Vector2.RIGHT, "uses": 0}}

func _pulse(ready: bool = true, remaining: float = 0.0, total: float = 8.0) -> Dictionary:
	return {"ready": ready, "cooldown_left": remaining, "cooldown_total": total,
		"radius": 144.0, "uses": 2, "affected": 5, "last_affected": 3}

func _update(pulse: Dictionary) -> void:
	var value: Dictionary = _snapshot()
	value["pulse"] = pulse
	_ui.update_hud(value)

func _skill(key: String = "pulse") -> Control:
	return _ui._hud[key] as Control

func _label(key: String = "pulse") -> Label:
	return _ui._hud[key + "_label"] as Label

func _bar(key: String = "pulse") -> ProgressBar:
	return _ui._hud[key + "_bar"] as ProgressBar

func _test_states_and_compatibility() -> void:
	_ui.show_hud()
	_ui.update_hud(_snapshot())
	await _settle()
	_check(not _skill().visible and _label().text.is_empty() and _bar().value == 0.0, "A legacy snapshot without pulse state leaves its new indicator hidden")
	_check(_skill("dash").visible and _label("dash").text == "冲刺 · 空格" and _skill("dash").name == "DashSkill", "Adding a pulse preserves the existing dash keys, node name and ready label")
	_update(_pulse())
	await _settle()
	_check(_skill().name == "PulseSkill" and _label().name == "PulseStatus" and _bar().name == "PulseCooldown", "The pulse exposes its agreed stable public node names")
	_check(_skill().visible and _label().text == "脉冲 · Q" and _bar().value == 1.0, "A ready instantaneous pulse shows its key and a full cooldown meter")
	_check(_skill().get_parent() == _skill("dash").get_parent() and _skill().get_index() == _skill("dash").get_index() + 1, "Both skills share the status row with pulse immediately after dash")
	var instruction: String = _skill().tooltip_text
	_check(instruction.contains("Q") and instruction.contains("144") and instruction.contains("70") and instruction.contains("减速") and instruction.contains("8秒") and instruction.contains("首领") and instruction.contains("追猎者") and instruction.contains("不能挡弹"), "The optional tooltip provides range, control effect, cooldown and defensive limits")
	_check(_skill("dash").tooltip_text == "空格：向当前移动方向冲刺；静止时沿面向。\n短冲距离约132，冷却2.4秒；起始短暂闪避，可冲离减速地形。", "The shared indicator builder leaves the dash instructions unchanged")
	for key: String in ["dash", "pulse"]:
		_check(_skill(key).focus_mode == Control.FOCUS_NONE and _skill(key).mouse_filter == Control.MOUSE_FILTER_PASS and _skill(key).get_signal_connection_list("gui_input").is_empty(), "The hoverable skill wrapper never focuses or accepts gameplay input: " + key)
		for child: Node in _skill(key).get_children():
			_check(child is Control and child.focus_mode == Control.FOCUS_NONE and child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Skill text and meter remain input-transparent: " + key)
		_check(not _skill(key).is_processing() and not _skill(key).is_physics_processing() and _skill(key).find_children("*", "Timer", true, false).is_empty(), "A skill adds neither a polling callback nor an independent UI timer: " + key)
		_check(_bar(key).step == 0.0, "A skill meter preserves fractional cooldown progress without Range step rounding: " + key)
	var pulse: Dictionary = _pulse(false, 7.9)
	var before: Dictionary = pulse.duplicate(true)
	_update(pulse)
	_check(_label().text == "脉冲 7.9秒" and is_equal_approx(_bar().value, 0.0125) and pulse == before, "Cooldown text and progress read the authoritative eight-second snapshot without altering its counters (text=%s, progress=%.16f)" % [_label().text, _bar().value])
	var frozen: Array = [_label().text, _bar().value, _label("dash").text, _bar("dash").value]
	paused = true
	await _settle()
	_check(frozen == [_label().text, _bar().value, _label("dash").text, _bar("dash").value], "Neither skill can silently count down without snapshots during a real scene-tree pause")
	paused = false
	_update(_pulse(false, 0.04))
	_check(_label().text == "脉冲 0.1秒" and is_equal_approx(_bar().value, 0.995) and _bar().value < 1.0, "A positive fractional cooldown never appears as a zero-second ready skill (text=%s, progress=%.16f)" % [_label().text, _bar().value])
	_update(_pulse(false, 0.0, 0.0))
	_check(_label().text == "脉冲" and _bar().value == 0.0, "An unavailable zero-duration state does not divide by zero or advertise readiness")
	_update(_pulse(false, NAN, NAN))
	_check(_label().text == "脉冲" and is_finite(_bar().value), "Non-finite diagnostic timing cannot create non-finite progress")
	for missing: Variant in [null, "invalid", [], {}]:
		var value: Dictionary = _snapshot()
		value["pulse"] = missing
		_ui.update_hud(value)
		_check(not _skill().visible and _label().text.is_empty() and _skill("dash").visible, "Missing or malformed pulse data remains compatible with the existing dash HUD")
	var mixed: Dictionary = _snapshot()
	mixed["pulse"] = _pulse(false, 7.9)
	mixed["dash"]["ready"] = false
	mixed["dash"]["active"] = true
	mixed["dash"]["cooldown_left"] = 2.4
	_ui.update_hud(mixed)
	_check(_label("dash").text == "冲刺中" and _bar("dash").value == 0.0 and _label().text == "脉冲 7.9秒", "An active dash and a recovering instantaneous pulse keep independent states")
	var benchmark: Dictionary = _snapshot()
	benchmark["pulse"] = _pulse()
	benchmark["benchmark"] = true
	_ui.update_hud(benchmark)
	_check(not _skill().visible and not _skill("dash").visible and _label().text.is_empty() and _bar().value == 0.0, "The ordinary benchmark suppresses both unrelated skill indicators")
	var dead: Dictionary = _snapshot()
	dead["pulse"] = _pulse()
	dead["health"] = 0.0
	_ui.update_hud(dead)
	_check(not _skill().visible and not _skill("dash").visible, "A dead-player snapshot advertises neither skill")
	_update(_pulse())
	_check(_skill().visible and _skill("dash").visible and _label().text == "脉冲 · Q", "An ordinary fresh snapshot restores both skill indicators")

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
	_update(_pulse())
	await _settle()
	var probe := InputProbe.new()
	root.add_child(probe)
	var focused: Control = root.gui_get_focus_owner()
	for key: String in ["dash", "pulse"]:
		var point: Vector2 = _skill(key).get_global_rect().get_center()
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
		await _key(KEY_Q)
	_check(probe.pointer_count == 2 and probe.movement and probe.dash and probe.pulse, "Pointer clicks and real W, Space and Q events propagate through both visible skill areas")
	_check(root.gui_get_focus_owner() == focused, "Hovering and clicking either skill never steals the gameplay keyboard focus")
	probe.queue_free()
	await _settle()

func _test_layouts() -> void:
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		_ui.show_hud()
		await _settle()
		_check(root.size == physical_size and root.get_visible_rect().size.is_equal_approx(Vector2(1280, 720)), "The actual window retains the reference viewport at " + str(physical_size))
		for boss_alive: bool in [false, true]:
			var value: Dictionary = _snapshot()
			value["pulse"] = _pulse(false, 7.9)
			value["dash"]["ready"] = false
			value["dash"]["cooldown_left"] = 1.8
			value["gold"] = 9999
			value["level"] = 25
			value["wave"] = 8 if boss_alive else 1
			value["boss_health"] = 100.0 if boss_alive else 0.0
			value["boss_max_health"] = 200.0 if boss_alive else 0.0
			_ui.update_hud(value)
			await _settle()
			var status := _ui.find_child("RitualStatus", true, false) as Control
			var boss: Control = _ui._hud["boss"]
			_check(not _skill().get_global_rect().intersects(_skill("dash").get_global_rect()) and _skill().get_global_rect().position.x > _skill("dash").get_global_rect().end.x, "Both skills remain visibly separated in ordinary and Boss combat")
			for key: String in ["dash", "pulse"]:
				var rect: Rect2 = _skill(key).get_global_rect()
				_check(_skill(key).visible and status.get_global_rect().grow(0.1).encloses(rect) and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(rect), "Both visible skill controls stay within the status panel: " + key)
				_check(_skill(key).size.x >= 100.0 and _skill(key).size.x <= 108.0 and _bar(key).size.y >= 5.0 and _bar(key).size.y <= 6.0, "The skill and its progress bar respect the compact minimum-size budget: " + key)
				_check(_label(key).size.x + 0.1 >= _label(key).get_minimum_size().x and _label(key).size.y + 0.1 >= _label(key).get_minimum_size().y and (not boss_alive or not boss.get_global_rect().intersects(rect)), "Skill text is readable and stays clear of the Boss second row: " + key)
			var values_fit: bool = (_ui._hud["health"].get_parent() as Control).size.x >= 260.0
			for key: String in ["health", "wave", "time", "gold", "level"]:
				var label: Label = _ui._hud[key]
				values_fit = values_fit and label.size.x + 0.1 >= label.get_minimum_size().x and status.get_global_rect().grow(0.1).encloses(label.get_global_rect())
			_check(values_fit and boss.visible == boss_alive, "Adding a second skill preserves the health width, every existing value and Boss visibility")
			_check(not _ui._hud.has("bag_info") and _ui.find_child("HUDMapInfo", true, false) == null, "The skill does not restore removed lower-right descriptions")
			_ui.notify("脉冲技能与地图说明".repeat(12))
			_check(not _ui._toast.visible and _ui._toast.text.is_empty() and _ui._toast_timer.is_stopped(), "Both skills preserve the removed battle notification area")

func _test_lifecycle() -> void:
	_ui.show_result(false, "试炼结束", {})
	await _settle()
	_check(_ui.find_child("PulseSkill", true, false) == null and _ui.find_child("DashSkill", true, false) == null, "The result screen removes both combat skill controls")
	_update(_pulse())
	_check(_ui.find_child("PulseSkill", true, false) == null, "A late combat snapshot cannot rebuild pulse feedback on the result screen")
	_ui.show_hud()
	_update(_pulse())
	await _settle()
	_check(_skill().visible and _label().text == "脉冲 · Q" and _bar().value == 1.0 and _label("dash").text == "冲刺 · 空格", "A new combat HUD restores both skills without stale cooldown state")
