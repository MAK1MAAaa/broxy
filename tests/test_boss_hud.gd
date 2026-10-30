extends SceneTree
## Minimal boss health, phase colors and an authoritative arrival clock.

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
	return {"boss_intro_left": 2.4, "boss_encounter": {"active": true,
		"display_name": GameCatalog.enemy("boss").display_name, "health": 150.5,
		"max_health": 300.0, "phase": "charge", "name": BossEncounter.ATTACK_NAMES["forest_storm"],
		"attack_id": "forest_storm", "cast_id": 1, "charge_left": 1.5, "charge_total": 2.0,
		"phase2": false, "cast_phase2": false, "break_left": 0.0, "weakpoints_remaining": 3}}

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
	_check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.focus_mode == Control.FOCUS_NONE, "The boss module never intercepts pointer or controller focus")
	var value: Dictionary = _value()
	hud.update_snapshot(value)
	await _frames()
	_check(hud.visible and hud.health_bar.get_global_rect() == Rect2(360, 70, 560, 14), "The real boss health bar stays centered below the compact timer")
	_check(hud.health_bar.value == 150.5 and hud.health_bar.max_value == 300.0 and not hud.health_bar.show_percentage, "The bar preserves exact health without displaying numeric text")
	_check(hud.get_child_count() == 2 and hud.get_child(0) == hud.health_bar, "Only the health meter and temporary arrival name exist; no hidden legacy status widgets")
	var arrival: Label = hud.find_child("BossArrivalName", true, false)
	_check(arrival.visible and arrival.text == GameCatalog.enemy("boss").display_name, "The true boss name is visible during the world-owned arrival interval")
	_check(arrival.get_global_rect() == Rect2(360, 90, 560, 36), "The temporary name has its own centered line below the bar")
	var fill: StyleBoxFlat = hud.health_bar.get_theme_stylebox("fill")
	_check(fill.bg_color == BossHUD.PHASE_ONE, "Phase one uses its own health color")
	for child: Control in [hud.health_bar, arrival]:
		_check(hud.get_global_rect().encloses(child.get_global_rect()), "Every child fits the independent boss region")
		_check(child.focus_mode == Control.FOCUS_NONE and child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Every boss child leaves controls with gameplay")
	var original: Dictionary = hud.snapshot()
	value["boss_encounter"]["health"] = 1
	value["boss_encounter"]["display_name"] = "changed"
	var returned: Dictionary = hud.snapshot()
	returned["health"] = 0
	_check(hud.snapshot() == original and hud.health_bar.value == 150.5, "Caller and returned snapshot mutations cannot change displayed boss values")
	await _frames(20)
	_check(hud.snapshot() == original and arrival.visible, "Render frames alone never advance the authoritative arrival clock")
	value = _value()
	value["boss_encounter"]["phase2"] = true
	hud.update_snapshot(value)
	fill = hud.health_bar.get_theme_stylebox("fill")
	_check(fill.bg_color == BossHUD.PHASE_TWO and BossHUD.PHASE_ONE != BossHUD.PHASE_TWO, "Phase two has a distinct health color")
	for phase: String in ["charge", "break", "recovery", "stopped"]:
		value["boss_encounter"]["phase"] = phase
		value["boss_encounter"]["break_left"] = 1.5 if phase == "break" else 0.0
		value["boss_intro_left"] = 0.0
		hud.update_snapshot(value)
		fill = hud.health_bar.get_theme_stylebox("fill")
		_check(fill.bg_color == BossHUD.PHASE_TWO, "Attack and break states never erase the phase color: " + phase)
		_check(not arrival.visible and arrival.text.is_empty() and hud.health_bar.visible, "After arrival only the boss health bar remains visible: " + phase)
	for intro: Variant in [-1.0, 0.0, NAN, INF, "2.4", null]:
		value = _value()
		value["boss_intro_left"] = intro
		hud.update_snapshot(value)
		_check(hud.visible and not arrival.visible and arrival.text.is_empty(), "Malformed or expired arrival values cannot reveal a persistent name")
	value = _value()
	value.erase("boss_intro_left")
	hud.update_snapshot(value)
	_check(hud.visible and not arrival.visible, "Snapshots without arrival data still show only boss health")
	value["boss_intro_left"] = 2.4
	value["boss_encounter"]["display_name"] = ""
	hud.update_snapshot(value)
	_check(hud.visible and not arrival.visible, "An empty boss name cannot create a blank arrival overlay")
	for invalid: Variant in [null, [], {}, {"boss_encounter": []}]:
		hud.update_snapshot(_value())
		hud.update_snapshot(invalid)
		_check(not hud.visible and hud.snapshot().is_empty() and arrival.text.is_empty(), "Malformed snapshots clear all previous boss presentation")
	for change: Dictionary in [{"active": false}, {"health": 0}, {"max_health": 0}, {"health": NAN}, {"max_health": INF}]:
		value = _value()
		value["boss_encounter"].merge(change, true)
		hud.update_snapshot(value)
		_check(not hud.visible and hud.snapshot().is_empty(), "Inactive, dead or nonfinite boss values cannot leave a stale health bar")
	hud.update_snapshot(_value())
	root.size = Vector2i(960, 540)
	await _frames()
	_check(hud.health_bar.get_global_rect() == Rect2(360, 70, 560, 14), "The minimum window retains the same centered reference-space bar")
	host.queue_free()
	await _frames()
	print("BossHUD: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
