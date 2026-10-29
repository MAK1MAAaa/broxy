extends SceneTree
## Checks rendered numbers, source identities and current shop interactions against actual layout.

const FIXTURE = preload("res://tools/preview_resonance.gd")
var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_ui = GameUI.new()
	root.add_child(_ui)
	var escape := FIXTURE.EscapeRouter.new()
	escape.ui = _ui
	root.add_child(escape)
	await _test_details_and_forecast()
	await _test_modal_numbers()
	await _test_placement_and_stale_source()
	await _test_full_and_unlinked()
	_ui.queue_free()
	escape.queue_free()
	print("ResonanceUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _show(state: RunState) -> void:
	_ui.bind(state)
	_ui.show_shop()
	await _settle()
	_ui._bag_grid.select_item(1)
	await _settle()

func _label(name: String) -> Label:
	return _ui.find_child(name, true, false) as Label

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	root.push_input(event)
	await _settle()

func _test_details_and_forecast() -> void:
	var state: RunState = FIXTURE.make_fixture("linked")
	await _show(state)
	var bonus: float = float(state.loadout[0]["resonance_bonus"])
	_check(is_equal_approx(bonus, 0.09), "Three formally placed first-rank relics create the fixture's real nine-percent local bonus")
	var stats: Label = _label("BackpackWeaponStats")
	_check(stats != null and stats.text.contains("%.1f伤害" % state.weapon_damage(state.loadout[0])), "Selected-weapon details display the actual UID's effective damage")
	var resonance: Label = _label("BackpackResonance")
	_check(resonance != null and resonance.text.contains("+9%") and resonance.tooltip_text.contains("18%") and resonance.tooltip_text.contains("3/6/12%"), "The compact contribution retains its actual rank and cap rules in the tooltip")
	for uid: int in [4, 5, 6]:
		_check(resonance.tooltip_text.contains("#%d" % uid), "A contributing relic remains identifiable by stable UID in the tooltip: %d" % uid)
	var merge: Button = _ui.find_child("MergeBackpackItem2", true, false) as Button
	var scroll: ScrollContainer = _ui.find_child("BackpackDetailsScroll", true, false) as ScrollContainer
	var summary: Label = _label("BackpackResonanceSummary")
	_check(summary != null and summary.text == "共鸣+9% · 3件遗物" and scroll.get_global_rect().encloses(summary.get_global_rect()), "The initial details viewport exposes a compact local bonus and source count")
	_check(merge != null and scroll.get_global_rect().encloses(merge.get_global_rect()), "The first merge remains visible at 720p before the longer resonance explanation")
	_check(merge != null and merge.tooltip_text.contains("当前两件") and merge.tooltip_text.contains("共鸣"), "Merge explains the position-dependent combined damage rather than promising doubled local bonuses")
	var preview: Dictionary = state.weapon_purchase_preview(0)
	var offer: Node = _ui.find_child("Offer1", true, false)
	var forecast: Label = offer.find_child("WeaponStats", true, false) as Label
	_check(preview["has_projection"] and forecast.text == _ui._weapon_stats_text(GameCatalog.weapon("bone"), 1, float(preview["resonance_bonus"])) and forecast.text.contains("%.1f伤害" % float(preview["damage"])), "Weapon offers retain the compact weapon-stat format while using real automatic-placement damage")
	_check(forecast.tooltip_text.contains("自动落点") and forecast.tooltip_text.contains(_ui._rune_percent(float(preview["resonance_bonus"]))), "Forecast scope and its local bonus are inspectable")
	_ui._bag_grid.select_item(4)
	_check(_label("BackpackResonance").tooltip_text.contains("骨针 #1") and _label("BackpackResonance").tooltip_text.contains("合成或出售"), "The selected relic's tooltip identifies its affected weapon and layout-changing actions")
	_ui.show_hud()
	_ui.update_hud({"health": state.health, "max_health": state.stat("max_health"), "wave": 4, "time_left": 45.0, "loadout": state.loadout})
	await _settle()
	var hud: Control = _ui.find_child("EquipmentSlot1", true, false) as Control
	_check(hud != null and hud.tooltip_text.contains("%.1f伤害" % state.weapon_damage(state.loadout[0])) and hud.tooltip_text.contains("+9%"), "The HUD tooltip uses the same effective damage and local bonus")

func _test_modal_numbers() -> void:
	var state: RunState = FIXTURE.make_fixture("linked")
	await _show(state)
	var signature: String = JSON.stringify(state.backpack_snapshot())
	var preview: Dictionary = state.relic_purchase_preview(2)
	_ui._shop_focus_button("compare:2").pressed.emit()
	await _settle()
	for change: Dictionary in preview["weapon_changes"]:
		var row: Label = _label("ComparisonWeapon%dDamage" % int(change["slot"]))
		_check(row != null and row.text.contains("%.1f → %.1f" % [float(change["damage_before"]), float(change["damage_after"])]), "Relic comparison matches actual global and local purchase projections")
		_check(row != null and row.text.contains("共鸣 %s → %s" % [_ui._rune_percent(float(change["resonance_before"])), _ui._rune_percent(float(change["resonance_after"]))]), "Relic comparison exposes the local contribution separately")
	await _key(KEY_ESCAPE)
	_check(_ui._overlay_mode.is_empty() and JSON.stringify(state.backpack_snapshot()) == signature, "Esc closes the pure relic comparison without moving or purchasing")
	_ui._bag_grid.select_item(8)
	_ui._shop_focus_button("rune_preview:0").pressed.emit()
	await _settle()
	var stats: Label = _label("RuneEquipWeaponStats")
	_check(stats != null and stats.text.contains("%.1f伤害" % state.weapon_damage(state.loadout[0])) and stats.text.contains("+9%"), "Rune preview includes the actual ranked weapon and resonance damage")
	_check(stats != null and stats.text.contains("装符不改变共边关系"), "Rune preview explains why socketing preserves physical resonance")
	await _key(KEY_ESCAPE)
	_check(_ui._overlay_mode.is_empty() and JSON.stringify(state.backpack_snapshot()) == signature, "Rune preview remains read-only and closes through the real Esc path")

func _test_placement_and_stale_source() -> void:
	var state: RunState = FIXTURE.make_fixture("linked")
	await _show(state)
	var stale_merge: Button = _ui.find_child("MergeBackpackItem2", true, false) as Button
	_ui._bag_grid.select_item(4)
	var signature: String = JSON.stringify(state.backpack_snapshot())
	stale_merge.pressed.emit()
	_check(JSON.stringify(state.backpack_snapshot()) == signature, "A prior selected weapon's merge callback cannot act after selecting a contributing relic")
	_ui._bag_grid.select_item(1)
	_ui._shop_focus_button("bag_move:1").pressed.emit()
	await _settle()
	_check(root.gui_get_focus_owner() == _ui._bag_grid, "The new explanatory controls do not steal placement focus")
	await _key(KEY_R)
	await _key(KEY_ENTER)
	_check(state.backpack_item(1)["rotated"] and is_equal_approx(float(state.loadout[0]["resonance_bonus"]), 0.06), "Real keyboard rotation and placement changes three contact sources to two")
	_check(_label("BackpackWeaponStats").text.contains("%.1f伤害" % state.weapon_damage(state.loadout[0])) and _label("BackpackResonance").text.contains("+6%"), "The successful placement rebuilds both actual damage and local contribution")

func _test_full_and_unlinked() -> void:
	var state: RunState = FIXTURE.make_fixture("full")
	await _show(state)
	_check(state.backpack_snapshot()["used_cells"] == 36 and _label("BackpackResonance").text.contains("+18%"), "The legal full-grid fixture exposes capped resonance")
	var offer: Node = _ui.find_child("Offer1", true, false)
	var forecast: Label = offer.find_child("WeaponStats", true, false) as Label
	_check(not state.weapon_purchase_preview(0)["has_projection"] and forecast.text.contains("背包无空位"), "A full grid never invents an incoming weapon's contact bonus or damage")
	_ui._shop_focus_button("compare:2").pressed.emit()
	await _settle()
	_check(_label("ComparisonStatus").text.contains("不新增邻接共鸣"), "A blocked relic's global-only hypothesis explicitly excludes a fabricated contact")
	await _key(KEY_ESCAPE)
	state = FIXTURE.make_fixture("unlinked")
	await _show(state)
	_check(_label("BackpackResonance").text.contains("+0%") and _label("BackpackResonance").tooltip_text.contains("尚无共边遗物"), "A non-adjacent arrangement retains its zero contribution and explains the absence of sources in its tooltip")
	var grid: Control = _ui.find_child("BackpackGrid", true, false) as Control
	var details: ScrollContainer = _ui.find_child("BackpackDetailsScroll", true, false) as ScrollContainer
	_check(root.get_visible_rect().encloses(grid.get_global_rect()) and root.get_visible_rect().encloses(details.get_global_rect()), "The complete grid and independent details viewport remain within 720p")
