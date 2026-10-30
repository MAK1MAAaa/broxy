extends SceneTree
## Real map focus, purchased equipment, textured projectiles and complete damage history.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for index: int in 5:
		await process_frame

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var state := RunState.new()
	state.begin(20261031, "bone")
	state.gold = 10000
	var ui := GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	for physical: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical
		ui.show_title({})
		await _settle()
		var scroll := ui.find_child("ArenaChoiceScroll", true, false) as ScrollContainer
		_check(scroll != null and scroll.follow_focus and scroll.get_global_rect().end.y < 630, "Seven-map selector reserves a bounded title area and follows keyboard focus")
		for id: String in ArenaCatalog.IDS:
			var button := ui.find_child("Arena_" + id, true, false) as Button
			_check(button != null and button.focus_mode == Control.FOCUS_ALL, "Every map has a reachable actual choice: " + id)
			button.grab_focus()
			await _settle()
			_check(scroll.get_global_rect().grow(1).encloses(button.get_global_rect()), "Focusing each map scrolls its entire card into view: " + id)
			button.pressed.emit()
			_check(ui.selected_arena() == id, "The revealed choice selects its actual map")
		var start := ui.find_child("StartTrial", true, false) as Button
		_check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(start.get_global_rect()), "The start action remains inside the viewport after all map choices")
		state.damage_dealt_by_weapon.clear()
		for index: int in GameCatalog.WEAPON_DEFS.size():
			state.damage_dealt_by_weapon[GameCatalog.WEAPON_DEFS[index].id] = float(index + 1)
		ui.show_result(false, "试炼结束", {})
		await _settle()
		var damage_scroll := ui.find_child("DamageContributionScroll", true, false) as ScrollContainer
		_check(damage_scroll != null and damage_scroll.focus_mode == Control.FOCUS_ALL, "Expanded history has a real keyboard-reachable scroll surface")
		for definition: ContentDef in GameCatalog.weapons():
			var row := ui.find_child("Damage_" + definition.id, true, false) as Control
			_check(row != null, "All sixteen historical weapon contributions exist without truncation: " + definition.id)
		var last := ui.find_child("Damage_bone", true, false) as Control
		damage_scroll.ensure_control_visible(last)
		await _settle()
		_check(damage_scroll.scroll_vertical > 0 and damage_scroll.get_global_rect().grow(1).encloses(last.get_global_rect()), "The last historical contribution can actually be revealed inside the bounded result panel")
		damage_scroll.grab_focus()
		var before_scroll: int = damage_scroll.scroll_vertical
		var page := InputEventJoypadButton.new()
		page.device = 0
		page.button_index = JOY_BUTTON_LEFT_SHOULDER
		page.pressed = true
		_check(ui._gamepad_reading_target() == damage_scroll and ui._page_gamepad_reading(page), "Shoulder paging targets the focused damage history rather than the other result scroll")
		await _settle()
		_check(damage_scroll.scroll_vertical < before_scroll, "The real shoulder callback reveals earlier recorded damage without changing the run")
	var sim := CombatSim.new()
	sim.begin(state)
	var painter := ProjectilePainter.new()
	for definition: ContentDef in GameCatalog.weapons().slice(8):
		state.offers.assign([{"kind": "weapon", "id": definition.id, "price": definition.price, "sold": false}])
		var preview: Dictionary = state.weapon_purchase_preview(0)
		_check(preview.get("can_buy", false), "Every new item has a real purchasable backpack projection: " + definition.id)
		ui.show_shop()
		await _settle()
		var buy := ui._shop_focus_button("buy:0")
		_check(buy != null and not buy.disabled, "Each new original weapon has a real shop purchase control")
		var shot: CombatSim.Shot = sim.fire_weapon(definition.id, "", Vector2(640, 365), Vector2.RIGHT)
		_check(shot != null, "Every new weapon fires through the real shared projectile pool")
		painter.rebuild(sim.shots)
		var head: ProjectilePainter.HeadBatch = painter.heads[definition.id + ":"]
		_check(head.texture != null and head.texture.resource_path == AdventureArt.path("res://assets/icons/%s.svg" % definition.icon), "New projectile families display their own original weapon art rather than falling back to the knife")
	ui.queue_free()
	await _settle()
	print("WFExpansionUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
