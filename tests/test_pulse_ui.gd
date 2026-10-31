extends SceneTree
## Backpack-owned active skills expose two independent, input-transparent HUD slots.

class InputProbe:
	extends Node
	var keys: Array[int] = []
	var pointer_count: int = 0
	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			keys.append(event.physical_keycode)
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
	await _test_states()
	await _test_input_passthrough()
	await _test_layouts()
	await _test_backpack_skills()
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
		"dash": {"ready": true, "active": false, "cooldown_left": 0.0, "cooldown_total": 2.4}}

func _equipped(id: String = "pulse", uid: int = 10, remaining: float = 0.0, total: float = 8.0) -> Dictionary:
	return {"slot": 0, "uid": uid, "id": id, "name": GameCatalog.skill(id).display_name,
		"rank": 1, "available": true, "ready": remaining <= 0.0, "cooldown_remaining": remaining,
		"cooldown_duration": total, "radius": 144.0, "damage": 0.0, "uses": 2}

func _update(first: Dictionary = {}, second: Dictionary = {}) -> void:
	var value: Dictionary = _snapshot()
	value["skills"] = [first, second]
	_ui.update_hud(value)

func _skill(key: String = "pulse") -> Control:
	return _ui._hud[key] as Control

func _label(key: String = "pulse") -> Label:
	return _ui._hud[key + "_label"] as Label

func _bar(key: String = "pulse") -> ProgressBar:
	return _ui._hud[key + "_bar"] as ProgressBar

func _time(key: String = "pulse") -> Label:
	return _ui._hud[key + "_time"] as Label

func _test_states() -> void:
	_ui.show_hud()
	_ui.update_hud(_snapshot())
	await _settle()
	_check(_skill().visible and _label().text == "空槽" and _bar().value == 0.0, "A snapshot without backpack skills shows an empty first slot")
	_check(_skill("secondary").visible and _label("secondary").text == "空槽", "The second active skill slot remains visibly empty")
	_check(_skill("dash").visible and _label("dash").text == "冲刺" and (_ui._hud["dash_key"] as Label).text == "空格", "Dash remains independently available without backpack skills")
	var legacy: Dictionary = _snapshot()
	legacy["pulse"] = {"ready": true, "cooldown_left": 0.0, "cooldown_total": 8.0}
	_ui.update_hud(legacy)
	_check(_label().text == "空槽", "Legacy free-pulse data cannot unlock a backpack skill")
	_update(_equipped(), _equipped("arc_slash", 11, 3.0, 6.0))
	_check(_label().text == GameCatalog.skill("pulse").display_name and _bar().value == 1.0 and _time().text == "就绪", "The first equipped rear character displays its actual identity and readiness")
	_check(_label("secondary").text == GameCatalog.skill("arc_slash").display_name and _time("secondary").text == "3.0" and is_equal_approx(_bar("secondary").value, 0.5), "The second rear character has an independent identity and cooldown")
	_check(_skill().name == "PulseSkill" and _label().name == "PulseStatus" and _bar().name == "PulseCooldown", "The first slot retains stable legacy node names")
	_check((_ui._hud["pulse_key"] as Label).text == "Q" and (_ui._hud["secondary_key"] as Label).text == "E", "Both keyboard skill bindings are visible")
	_check((_ui._hud["pulse_icon"] as TextureRect).texture != null and (_ui._hud["secondary_icon"] as TextureRect).texture != null, "Both equipped skills have real icon resources")
	var source: Dictionary = _equipped("starfall", 12, 7.9, 8.0)
	var before: Dictionary = source.duplicate(true)
	_update(source)
	_check(_label().text == GameCatalog.skill("starfall").display_name and _time().text == "7.9" and is_equal_approx(_bar().value, 0.0125) and source == before, "HUD reads authoritative cooldowns without changing the snapshot")
	var frozen: Array = [_time().text, _bar().value]
	paused = true
	await _settle()
	_check(frozen == [_time().text, _bar().value], "Skill cooldowns do not advance without authoritative snapshots during pause")
	paused = false
	_update(_equipped("pulse", 10, 0.04))
	_check(_time().text == "0.1" and _bar().value < 1.0, "A positive fractional cooldown does not appear ready")
	var invalid: Dictionary = _equipped("pulse", 10, NAN, NAN)
	invalid["ready"] = false
	_update(invalid)
	_check(_time().text == "—" and is_finite(_bar().value), "Non-finite timing cannot create invalid meter progress")
	for malformed: Variant in [null, "invalid", {}, [null], [{"id": "missing", "uid": 10, "available": true}]]:
		var value: Dictionary = _snapshot()
		value["skills"] = malformed
		_ui.update_hud(value)
		_check(_label().text == "空槽" and _skill("dash").visible, "Malformed skill state leaves an empty slot and preserves dash")
	for state_key: String in ["benchmark", "health"]:
		var value: Dictionary = _snapshot()
		value["skills"] = [_equipped(), _equipped("starfall", 11)]
		value[state_key] = true if state_key == "benchmark" else 0.0
		_ui.update_hud(value)
		_check(not _skill().visible and not _skill("secondary").visible and not _skill("dash").visible, "Dead-player and benchmark states hide all combat skill controls")
	_update(_equipped())
	_check(_skill().visible and _label().text == GameCatalog.skill("pulse").display_name and _skill("dash").visible, "Fresh combat state restores equipped rear character feedback")

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
	_update(_equipped(), _equipped("starfall", 11))
	await _settle()
	var probe := InputProbe.new()
	root.add_child(probe)
	var focused: Control = root.gui_get_focus_owner()
	for key: String in ["dash", "pulse", "secondary"]:
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
		_check(_skill(key).focus_mode == Control.FOCUS_NONE and _skill(key).get_signal_connection_list("gui_input").is_empty(), "Skill cards never take keyboard focus or gameplay input: " + key)
	for code: Key in [KEY_W, KEY_SPACE, KEY_Q, KEY_E]:
		await _key(code)
	_check(probe.pointer_count == 3 and probe.keys.has(KEY_W) and probe.keys.has(KEY_SPACE) and probe.keys.has(KEY_Q) and probe.keys.has(KEY_E), "Pointer and gameplay keys propagate through every skill control")
	_check(root.gui_get_focus_owner() == focused, "Skill cards never steal gameplay focus")
	probe.queue_free()
	await _settle()

func _test_layouts() -> void:
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		_ui.show_hud()
		for boss_alive: bool in [false, true]:
			var value: Dictionary = _snapshot()
			value["skills"] = [_equipped(), _equipped("starfall", 11, 7.9)]
			value["gold"] = 9999
			value["level"] = 25
			value["boss_encounter"] = {"active": boss_alive, "health": 100.0, "max_health": 200.0,
				"display_name": GameCatalog.enemy("boss").display_name, "phase": "recovery"}
			var weapons: Array = []
			for index: int in 8:
				weapons.append(_state.loadout[0].duplicate(true))
			value["loadout"] = weapons
			_ui.update_hud(value)
			await _settle()
			var equipment := _ui.find_child("RitualEquipment", true, false) as Control
			var abilities := _ui.find_child("RitualAbilities", true, false) as Control
			var viewport := Rect2(Vector2.ZERO, Vector2(1280, 720))
			for key: String in ["pulse", "secondary"]:
				var rect: Rect2 = _skill(key).get_global_rect()
				_check(abilities.get_global_rect().grow(0.1).encloses(rect) and viewport.encloses(rect), "Both active skill cards fit inside the right-hand abilities panel at " + str(physical_size))
				_check(not rect.intersects((_ui._hud["slots"] as Control).get_global_rect()), "Skill cards do not overlap eight weapon cards")
			_check(not _skill().get_global_rect().intersects(_skill("secondary").get_global_rect()), "The two active skills never overlap")
			_check(abilities.get_global_rect().grow(0.1).encloses(_skill("dash").get_global_rect()), "Independent dash shares the right-hand frame with skills")
			_check((_ui._hud["slots"] as Control).get_child_count() == 8 and equipment.get_global_rect().grow(0.1).encloses((_ui._hud["slots"] as Control).get_global_rect()), "Two skill cards preserve all eight visible left-hand weapon slots")
			_check(not _ui._hud.has("bag_info") and _ui.find_child("HUDMapInfo", true, false) == null, "Skill controls preserve the removed explanatory HUD copy")

func _test_backpack_skills() -> void:
	_state.offers = [{"kind": "skill", "id": "pulse", "rank": 1, "price": 0}, {"kind": "skill", "id": "starfall", "rank": 2, "price": 0}]
	_check(_state.buy_offer(0) and _state.buy_offer(1), "The UI fixture buys two real backpack skills")
	_ui.show_shop()
	await _settle()
	var capacity := _ui.find_child("BackpackCapacity", true, false) as Label
	_check(capacity != null and capacity.text.contains("后排 2/2"), "The backpack exposes the two-character rear capacity through a compact value")
	for index: int in 2:
		var uid: int = int(_state.active_skills[index]["uid"])
		var button := _ui.find_child("BackpackItem%d" % uid, true, false) as Control
		var badge := button.get_node_or_null("SkillKeyBadge") as Label
		_check(badge != null and badge.text == ("Q" if index == 0 else "E"), "Backpack skills expose their stable UID-based keyboard slot")
		_ui._bp_select(uid, _ui._shop_epoch)
		_check(_ui.find_child("BackpackSkillStats", true, false) != null and _ui.find_child("BackpackSkillSlot", true, false) != null and _ui.find_child("BackpackResonance", true, false) == null, "Skill details show parameters and slot without weapon resonance")
	var old_uids: Array[int] = []
	for skill: Dictionary in _state.active_skills:
		old_uids.append(int(skill["uid"]))
	_ui._on_input_device_changed("gamepad", 0)
	for index: int in 2:
		var button := _ui.find_child("BackpackItem%d" % old_uids[index], true, false) as Control
		_check((button.get_node("SkillKeyBadge") as Label).text == ("X" if index == 0 else "Y"), "Backpack skill badges follow the active input device")
	_ui._on_input_device_changed("keyboard", -1)
	var custom: Dictionary = ControlBindings.defaults()
	custom["pulse"] = KEY_CAPSLOCK
	custom["skill_secondary"] = KEY_PAGEUP
	_ui.set_controls(custom)
	await _settle()
	for index: int in 2:
		var button := _ui.find_child("BackpackItem%d" % old_uids[index], true, false) as Control
		var badge := button.get_node("SkillKeyBadge") as Label
		var expected_key: String = ControlBindings.key_label(KEY_CAPSLOCK if index == 0 else KEY_PAGEUP)
		_check(badge.text == expected_key and badge.size.x <= 20.1 and button.get_global_rect().encloses(badge.get_global_rect()), "A real long keyboard binding remains within its backpack skill box without losing the configured key")
	_ui.set_controls(ControlBindings.defaults())
	_state.offers = [{"kind": "skill", "id": "arc_slash", "rank": 2, "price": 0}]
	_ui.show_shop()
	await _settle()
	var buy: Button = _ui._shop_focus_button("buy:0")
	_check(buy != null and buy.text.contains("后排已满 2/2") and not buy.disabled and buy.focus_mode == Control.FOCUS_ALL, "The rear character cap is visible while the blocked offer remains keyboard accessible")
	var offer := _ui.find_child("Offer1", true, false) as Control
	var rank_badge := offer.find_child("OfferRank", true, false) as Label
	var category := offer.find_child("OfferDescription", true, false) as Label
	_check(rank_badge != null and rank_badge.is_visible_in_tree() and rank_badge.text == "Ⅱ阶" and category != null and category.text == GameUI._rear_skill_name("arc_slash"), "A second-rank rear offer displays its actual rank and skill name")

func _test_lifecycle() -> void:
	_ui.show_result(false, "试炼结束", {})
	await _settle()
	_check(_ui.find_child("PulseSkill", true, false) == null and _ui.find_child("SecondarySkill", true, false) == null, "Result screens remove both active skill cards")
	_update(_equipped())
	_check(_ui.find_child("PulseSkill", true, false) == null, "Late combat snapshots cannot recreate skill controls on a result screen")
	_ui.show_hud()
	_update(_equipped())
	await _settle()
	_check(_label().text == GameCatalog.skill("pulse").display_name and _bar().value == 1.0 and _label("secondary").text == "空槽", "A fresh HUD has no stale second rear character or cooldown state")
