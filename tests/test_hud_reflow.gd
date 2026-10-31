extends SceneTree
## Layout contract for the combat HUD, using real skill snapshots and a full equipment fixture.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI
var _sim: CombatSim

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var state := RunState.new()
	state.begin(20261031, "bone", "mire")
	state.offers.assign([{"kind": "skill", "id": "pulse", "rank": 1, "price": 0}, {"kind": "skill", "id": "arc_slash", "rank": 1, "price": 0}])
	_check(state.buy_offer(0) and state.buy_offer(1), "The fixture purchases both actual backpack skills")
	_sim = CombatSim.new()
	_sim.begin(state)
	_ui = GameUI.new()
	root.add_child(_ui)
	_ui.bind(state)
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical_size
		_ui.show_hud()
		var value: Dictionary = _sim.snapshot()
		# Eight visible slots are presentation capacity; gameplay ownership remains untouched.
		var weapons: Array = []
		for index: int in 8:
			var item: Dictionary = state.loadout[0].duplicate(true)
			item["uid"] = 100 + index
			item["rank"] = index % 4 + 1
			weapons.append(item)
		value["loadout"] = weapons
		value["health"] = 73.0
		value["max_health"] = 125.0
		value["level"] = 25
		value["xp"] = 37
		value["xp_needed"] = 100
		value["gold"] = 9999
		var retained: Dictionary = value.duplicate(true)
		var sim_before: Dictionary = _sim.snapshot().duplicate(true)
		_ui.update_hud(value)
		await _settle()
		_test_side_frames(physical_size)
		_test_vitals()
		_test_top()
		_check(value == retained and _sim.snapshot() == sim_before, "HUD layout cannot mutate source snapshots or advance simulation")
		_ui._on_input_device_changed("gamepad", 0)
		await _settle()
		_test_side_frames(physical_size)
		_check((_ui._hud["pulse_key"] as Label).text == "X" and (_ui._hud["secondary_key"] as Label).text == "Y" and (_ui._hud["hero_key"] as Label).text == "RB", "The shared abilities frame retains separate controller prompts")
		_ui._on_input_device_changed("keyboard", -1)
		value["benchmark"] = true
		value["enemies"] = 300
		value["projectiles"] = 600
		_ui.update_hud(value)
		await _settle()
		_test_top()
	root.size = Vector2i(1280, 720)
	_ui.queue_free()
	await _settle()
	print("HUDReflow: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_side_frames(physical_size: Vector2i) -> void:
	var weapons := _ui.find_child("RitualEquipment", true, false) as PanelContainer
	var abilities := _ui.find_child("RitualAbilities", true, false) as PanelContainer
	_check(weapons != null and abilities != null, "Both equipment groups have real framed containers")
	if weapons == null or abilities == null:
		return
	var viewport := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var left: Rect2 = weapons.get_global_rect()
	var right: Rect2 = abilities.get_global_rect()
	_check(viewport.encloses(left) and viewport.encloses(right) and left.end.x <= 220 and right.position.x >= 1060, "Weapons stay at the left edge and abilities stay at the right edge: " + str(physical_size))
	_check(left.position.y > 150 and right.position.y > 150 and not left.intersects(right), "Side frames leave the central fighting area clear")
	for frame: PanelContainer in [weapons, abilities]:
		var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
		_check(style != null and style.bg_color.a > 0.15 and style.bg_color.a < 0.9, "Each side frame uses a genuinely translucent fill")
		_check(frame.mouse_filter != Control.MOUSE_FILTER_STOP and frame.focus_mode == Control.FOCUS_NONE, "Decorative side frames cannot capture combat focus")
	var slots: Control = _ui._hud["slots"]
	_check(slots is GridContainer and (slots as GridContainer).columns == 2 and slots.get_child_count() == 8, "Eight weapons use two compact columns in the left frame")
	for child: Node in slots.get_children():
		var card := child as Control
		_check(card != null and left.grow(0.1).encloses(card.get_global_rect()), "Every visible weapon card fits inside its left frame")
	var previous := Rect2()
	for key: String in ["pulse", "secondary", "hero", "dash"]:
		var card: Control = _ui._hud[key]
		var area: Rect2 = card.get_global_rect()
		_check(card.visible and abilities.is_ancestor_of(card) and right.grow(0.1).encloses(area), "Every skill and dash share the right-hand translucent frame: " + key)
		_check(not left.intersects(area) and not previous.intersects(area), "Ability cards never overlap weapons or their preceding card: " + key)
		previous = area
	var map: Control = _ui._hud["minimap"]
	_check(not map.get_global_rect().intersects(left) and not map.get_global_rect().intersects(right), "The existing minimap stays separate from both side frames")

func _test_vitals() -> void:
	var hp: ProgressBar = _ui._hud["health_bar"]
	var xp: ProgressBar = _ui._hud["xp_bar"]
	var health: Label = _ui._hud["health"]
	var level: Label = _ui._hud["level"]
	_check(hp.value == 73 and hp.max_value == 125 and xp.value == 37 and xp.max_value == 100, "Both bottom meters preserve authoritative current and maximum values")
	_check(hp.get_global_rect().get_center().x == 640 and xp.get_global_rect().get_center().x == 640 and hp.global_position.y >= 600, "Player health and experience align at bottom center")
	_check(xp.global_position.y >= hp.get_global_rect().end.y and xp.get_global_rect().end.y <= 704, "Experience sits directly below health within the bottom safe area")
	_check(not _has_panel_ancestor(hp) and not _has_panel_ancestor(xp), "Player health and experience have no enclosing panel frame")
	_check(hp.get_global_rect().grow(0.1).encloses(health.get_global_rect()) and health.global_position.x < hp.global_position.x + 20, "Health numbers occupy the left inside of the actual health bar")
	_check(xp.get_global_rect().grow(0.1).encloses(level.get_global_rect()) and level.global_position.x < xp.global_position.x + 20, "Level occupies the left inside of the actual experience bar: bar=%s label=%s" % [xp.get_global_rect(), level.get_global_rect()])
	_check(health.text.contains("73") and health.text.contains("125") and level.text.contains("25"), "The embedded labels carry real health and level numbers")
	for label: Label in [health, level]:
		_check(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT and label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER and label.size.y >= label.get_minimum_size().y, "Embedded labels stay left aligned, centered and vertically readable")
		_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.focus_mode == Control.FOCUS_NONE, "Embedded vital labels never intercept combat input")

func _test_top() -> void:
	var status := _ui.find_child("RitualStatus", true, false) as Control
	var labels: Array[Label] = _visible_labels(status)
	var timer: Label = _ui._hud["time"]
	var gold: Label = _ui._hud["gold"]
	_check(labels.size() == 2 and labels.has(timer) and labels.has(gold), "The top group contains only countdown and soul quantity in every mode")
	_check(not _ui._hud.has("wave") and not status.is_ancestor_of(_ui._hud["health"]) and not status.is_ancestor_of(_ui._hud["level"]) and not status.is_ancestor_of(_ui._hud["dash"]), "Wave, player vitals and dash cannot return to the top group")
	_check(status.get_global_rect().end.y <= 64 and timer.text.contains(":") and gold.text.contains("魂屑") and gold.text.contains("9999"), "The compact top group retains its real countdown and soul count")
	for label: Label in labels:
		_check(status.get_global_rect().grow(0.1).encloses(label.get_global_rect()) and label.size.y >= label.get_minimum_size().y, "Both top values fit their compact group without clipping")

func _has_panel_ancestor(node: Node) -> bool:
	var current: Node = node.get_parent()
	while current != null and current != _ui:
		if current is Panel or current is PanelContainer:
			return true
		current = current.get_parent()
	return false

func _visible_labels(node: Node) -> Array[Label]:
	var result: Array[Label] = []
	if node is Label and node.is_visible_in_tree():
		result.append(node)
	for child: Node in node.get_children():
		result.append_array(_visible_labels(child))
	return result
