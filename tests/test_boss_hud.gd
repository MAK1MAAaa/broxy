extends SceneTree
## Independent boss geometry, real scalar values and event-driven clock presentation.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _frames(count: int = 2) -> void:
	for index: int in count:
		await process_frame

func _value() -> Dictionary:
	return {"boss_encounter": {"active": true, "display_name": GameCatalog.enemy("boss").display_name, "health": 150.0,
		"max_health": 300.0, "phase": "charge", "name": BossEncounter.ATTACK_NAMES["forest_storm"], "attack_id": "forest_storm",
		"cast_id": 1, "charge_left": 1.5, "charge_total": 2.0, "phase2": true,
		"cast_phase2": false, "break_left": 0.0, "weakpoints_remaining": 3}}

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var hud := BossHUD.new()
	host.add_child(hud)
	await _frames()
	_check(not hud.visible and not hud.is_processing() and not hud.is_physics_processing(), "An empty boss module is hidden and never polls gameplay")
	_check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.focus_mode == Control.FOCUS_NONE, "The boss module does not intercept movement, pointer or controller focus")
	var value: Dictionary = _value()
	hud.update_snapshot(value)
	await _frames()
	_check(hud.visible and hud.get_global_rect() == Rect2(240, 104, 800, 50), "The real boss module occupies its own exact region below the unchanged 86px topbar; actual=" + str(hud.get_global_rect()))
	_check(hud.health_bar.value == 150.0 and hud.health_bar.max_value == 300.0, "The actual health meter retains both true boss values")
	_check((hud.find_child("BossName", true, false) as Label).text == GameCatalog.enemy("boss").display_name, "The primary row shows the real boss name")
	_check((hud.find_child("BossPhase", true, false) as Label).text == "阶段 2", "The phase marker follows actual half-health phase2")
	_check((hud.find_child("BossSkillName", true, false) as Label).text == BossEncounter.ATTACK_NAMES["forest_storm"], "Charge displays the current named cast rather than generic help copy")
	_check(hud.charge_bar.visible and is_equal_approx(hud.charge_bar.value, 0.25), "Charge progress uses true elapsed fraction of the cast's locked duration")
	for node_name: String in ["BossName", "BossHealthValue", "BossPhase", "BossHealth", "BossSkillName", "BossCharge"]:
		var control: Control = hud.find_child(node_name, true, false)
		_check(hud.get_global_rect().encloses(control.get_global_rect()), "Every actual child fits the fixed independent boss region: " + node_name)
	var original: Dictionary = hud.snapshot()
	value["boss_encounter"]["health"] = 1
	value["boss_encounter"]["name"] = "changed"
	var returned: Dictionary = hud.snapshot()
	returned["health"] = 0
	_check(hud.snapshot() == original and hud.health_bar.value == 150, "Neither caller mutations nor returned snapshots can mutate displayed boss state")
	await _frames(20)
	_check(hud.snapshot() == original and is_equal_approx(hud.charge_bar.value, 0.25), "Presentation frames alone never advance the authoritative boss timer")
	value = _value()
	value["boss_encounter"]["phase"] = "break"
	value["boss_encounter"]["break_left"] = 2.4
	hud.update_snapshot(value)
	await _frames()
	var broken: Label = hud.find_child("BossBreak", true, false)
	_check(broken.visible and broken.text == "破防 2.4", "Break displays the real status and remaining time")
	_check(not hud.charge_bar.visible and not (hud.find_child("BossSkillName", true, false) as Label).visible, "Break clears the interrupted cast and charge progress")
	for phase: String in ["stopped", "recovery"]:
		value["boss_encounter"]["phase"] = phase
		hud.update_snapshot(value)
		_check(not broken.visible and not hud.charge_bar.visible, "Recovery and stopped do not retain stale break or charge indicators: " + phase)
	for invalid: Variant in [null, [], {}, {"boss_encounter": []}]:
		hud.update_snapshot(_value())
		hud.update_snapshot(invalid)
		_check(not hud.visible and hud.snapshot().is_empty(), "Malformed snapshots clear the complete previous boss state")
	for change: Dictionary in [{"active": false}, {"health": 0}, {"max_health": 0}, {"health": NAN}, {"max_health": INF}]:
		value = _value()
		value["boss_encounter"].merge(change, true)
		hud.update_snapshot(value)
		_check(not hud.visible and hud.snapshot().is_empty(), "Inactive, dead or nonfinite bosses cannot retain a visible stale health/cast bar")
	host.queue_free()
	await _frames()
	print("BossHUD: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
