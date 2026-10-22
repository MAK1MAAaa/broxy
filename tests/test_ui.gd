extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _started: String = ""
var _sounds: Array[String] = []
var _settings: Dictionary = {}
var _upgrade_completions: int = 0
var _next_wave_requests: int = 0

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
	var state: RunState = RunState.new()
	state.begin(114, "ember")
	var ui: GameUI = GameUI.new()
	root.add_child(ui)
	ui.bind(state)
	ui.start_requested.connect(_on_start)
	ui.feedback.connect(_on_feedback)
	ui.setting_changed.connect(_on_setting)
	ui.upgrades_finished.connect(_on_upgrades_finished)
	ui.next_wave_requested.connect(func() -> void: _next_wave_requests += 1)
	ui.set_settings({"volume": 0.4, "shake": false, "flash": true})
	_test_chinese_font(ui)
	var content_groups: Array = [GameCatalog.weapons(), GameCatalog.runes(), GameCatalog.relics()]
	var icon_count: int = 0
	for group: Array in content_groups:
		for definition: ContentDef in group:
			var texture: Texture2D = ui._icon_texture(definition)
			_check(texture != null and texture.get_width() > 0 and texture.get_height() > 0, "Catalog icon resolves to a usable texture: " + definition.id)
			icon_count += 1
	_check(icon_count == 13, "All four weapon, three rune and six relic icons are validated")
	ui.show_title({})
	await _settle()
	_check(ui.find_child("MenuArtwork", true, false) != null, "Title displays the supplied menu artwork")
	_check(_buttons_inside(ui), "Title buttons fit in 1280 by 720")
	_check(_text_inside(ui), "Title text remains inside the reference viewport without vertical clipping")
	var illustration_space: Control = ui.find_child("IllustrationBreathingSpace", true, false)
	_check(illustration_space != null and illustration_space.size.x >= 400 and illustration_space.size.y >= 300, "Title reserves a substantial unobstructed area for its illustration")
	_check(_decorations_ignore_input(ui), "Title ornamentation never intercepts input or runs per-frame processing")
	_press(ui, GameCatalog.weapon("ember").display_name)
	await _settle()
	_press(ui, "进入试炼")
	_check(_started == "ember", "Selected starter is emitted when starting a run")

	ui.show_hud()
	ui.update_hud({"health": 100, "max_health": 100, "wave": 1, "time_left": 305.0, "benchmark": true, "enemies": 300, "projectiles": 600, "loadout": state.loadout})
	_check(_has_label(ui, "性能测试") and _has_label(ui, "采样  05:05"), "Benchmark HUD names the performance test and shows the real sampling countdown")
	_check(_has_label(ui, "敌人  300") and _has_label(ui, "投射物  600"), "Benchmark HUD displays pressure-test entity counts")
	_check(not _has_label(ui, "剩余  00:45") and not _has_label(ui, "波次  1 / 8"), "Benchmark HUD does not masquerade as a normal 45-second wave")
	ui.update_hud({"health": 100, "max_health": 100, "wave": 1, "time_left": 45.0, "loadout": state.loadout})
	_check(_has_label(ui, "波次  1 / 8") and _has_label(ui, "剩余  00:45") and not _has_label(ui, "性能测试"), "Normal-wave snapshots restore the ordinary wave and timer labels")
	await _settle()
	var status: Control = ui.find_child("RitualStatus", true, false)
	var equipment: Control = ui.find_child("RitualEquipment", true, false)
	_check(status != null and status.get_global_rect().end.y <= 100, "Restyled status panel stays within the original top HUD footprint")
	_check(equipment != null and equipment.get_global_rect().position.y >= 616, "Restyled equipment panel does not cover more of the combat area")
	_check(_text_inside(ui), "HUD text stays inside the reference viewport without clipping")
	await _test_boss_hud(ui, state.loadout)
	ui.update_hud({"health": 100, "max_health": 100, "wave": 8, "time_left": 45.0, "loadout": state.loadout, "boss_health": 100.0, "boss_max_health": 200.0})
	ui.notify("这是用于验证战斗提示固定宽度的长文本。".repeat(30))
	await _settle()
	var hud_notice: Label = ui.get("_toast")
	var notice_rect: Rect2 = hud_notice.get_global_rect()
	var boss_status: Control = ui.get("_hud")["boss"]
	_check(notice_rect.position == Vector2(24, 106) and not notice_rect.intersects(CombatSim.ARENA), "Battle notifications remain in safe space above the playable arena")
	_check(boss_status.visible and not notice_rect.intersects(boss_status.get_global_rect()), "Battle notifications never overlap a visible boss status bar")
	_check(notice_rect.size == Vector2(370, 30) and hud_notice.clip_text and hud_notice.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Long battle notifications truncate inside a fixed-size notice without expanding it")
	_check(hud_notice.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Battle notifications never intercept movement or targeting input")
	ui.show_pause()
	paused = true
	await _settle()
	_check(ui.can_process(), "UI remains interactive while the scene tree is paused")
	_press(ui, "设置")
	await _settle()
	var slider: HSlider = _first_slider(ui)
	_check(slider != null and is_equal_approx(slider.value, 0.4), "Settings display the loaded volume")
	if slider != null:
		slider.value = 0.25
	_check(is_equal_approx(float(_settings.get("volume", -1)), 0.25), "Volume changes are emitted immediately")
	_press(ui, "返回")
	await _settle()
	_check(_find_button(ui, "继续试炼") != null and paused, "Returning from pause settings restores the paused menu")
	_check(_buttons_inside(ui), "Pause buttons fit in 1280 by 720")
	ui.hide_pause()
	paused = false

	ui.show_title({})
	_check(not hud_notice.visible, "Screen changes continue to hide an existing notification")
	_press(ui, "设置")
	await _settle()
	_press(ui, "返回")
	await _settle()
	_check(_find_button(ui, "进入试炼") != null and _find_button(ui, "继续试炼") == null, "Title settings return to the title without opening the pause menu")
	ui.show_result(false, "试炼结束", {})
	await _settle()
	_started = ""
	_press(ui, "再次试炼")
	_check(_started == "ember", "Result restart preserves the chosen starting weapon")
	_check(_buttons_inside(ui), "Result buttons fit in 1280 by 720")

	state.gold = 1000
	state.offers = [
		{"id": "frost", "kind": "weapon", "price": 21, "sold": false},
		{"id": "pierce", "kind": "rune", "price": 22, "sold": false},
		{"id": "damage", "kind": "relic", "price": 23, "sold": false},
		{"id": "blast", "kind": "rune", "price": 24, "sold": false},
	]
	ui.show_shop()
	await _settle()
	ui.notify("商店改装提示")
	await _settle()
	_check(hud_notice.get_global_rect() == Rect2(210, 502, 860, 40) and hud_notice.get_theme_font_size("font_size") == 16, "Shop notifications restore their original centered size and font after leaving combat")
	_check(hud_notice.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Restored shop notifications remain noninteractive")
	_check(_buttons_inside(ui), "Shop buttons fit in 1280 by 720")
	_check(_text_inside(ui), "Shop item and price text fits with the full-size icons")
	_check(_focus_id() == "buy:0", "A new shop starts with an available purchase rather than the leave-shop action")
	await _accept_focus()
	_check(state.loadout.size() == 2 and state.gold == 979, "Buying through the UI mutates inventory and charges the displayed cost")
	_check(not _sounds.is_empty() and _sounds.back() == "buy", "Successful purchases request the buy sound")
	_check(_focus_id() == "buy:1", "After buying an offer the keyboard focus moves to the next available offer")
	await _accept_focus()
	_check(state.rune_bag.size() == 1, "Purchased runes appear in the reserve bag")
	_check(_focus_id() == "equip:0", "Buying a rune selects it and focuses the first equip target")
	_check(_has_label_containing(ui, GameCatalog.rune("pierce").description), "The selected rune effect stays visible with an equip instruction")
	await _accept_focus()
	_check(state.rune_bag.is_empty() and state.loadout[0]["rune"].get("id", "") == "pierce", "Selecting a reserve rune and a weapon equips it")
	_check(_sounds.back() == "rune", "Rune equip requests the rune sound")
	var toast: Label = ui.get("_toast")
	_check(toast.visible and toast.text.contains(GameCatalog.weapon("ember").display_name) and toast.text.contains(GameCatalog.rune("pierce").display_name), "Successful equip visibly confirms both target weapon and rune")
	_check(_effect_tooltip(ui, GameCatalog.rune("pierce").description) != null, "Equipped shop runes retain a hoverable effect description")
	_check(_focus_id() == "unequip:0", "After equip the keyboard focus remains on the changed equipment slot")
	await _accept_focus()
	_check(state.rune_bag.size() == 1 and state.loadout[0]["rune"].is_empty(), "Unequip returns the rune to the reserve bag")
	_check(_sounds.back() == "rune", "Rune unequip requests the rune sound")
	_check(_focus_id().begins_with("rune:"), "Unequip moves keyboard focus to the returned reserve rune")
	await _accept_focus()
	_check(_focus_id() == "equip:0", "Selecting a reserve rune with ui_accept focuses an equip target")
	await _accept_focus()
	_check(state.rune_bag.is_empty() and _next_wave_requests == 0, "The complete keyboard buy-select-equip path never accidentally starts the next wave")
	ui.show_hud()
	ui.update_hud({"health": state.health, "max_health": state.stat("max_health"), "wave": 1, "time_left": 45.0, "loadout": state.loadout})
	await _settle()
	var hud_tooltip: Control = _effect_tooltip(ui, GameCatalog.rune("pierce").description)
	_check(hud_tooltip != null and hud_tooltip.focus_mode == Control.FOCUS_NONE, "HUD equipment exposes rune effects without acquiring keyboard focus")
	var probe := MovementKeyProbe.new()
	root.add_child(probe)
	var movement := InputEventKey.new()
	movement.physical_keycode = KEY_W
	movement.keycode = KEY_W
	movement.pressed = true
	root.push_input(movement)
	await _settle()
	_check(probe.received_movement, "Movement keys pass through tooltip-enabled HUD controls")
	probe.queue_free()
	ui.show_shop()
	await _settle()
	_press(ui, "卸符")
	await _settle()
	_press(ui, "出售")
	await _settle()
	_check(state.rune_bag.is_empty() and _sounds.back() == "buy", "Selling a rune requests the buy sound")
	_check(_focus_id() != "next_wave", "Selling the last reserve rune restores a usable shopping control")
	_press(ui, "售")
	await _settle()
	_check(state.loadout.size() == 1 and _sounds.back() == "buy", "Selling a weapon updates the displayed build and requests feedback")
	_check(_focus_id().begins_with("sell_weapon:"), "Selling a weapon keeps focus on a neighboring weapon action")
	var before_failure: int = _sounds.size()
	_press(ui, "售")
	await _settle()
	_check(state.loadout.size() == 1 and _sounds.size() == before_failure, "Rejected sales preserve the last weapon and emit no success sound")
	var refresh: Button = _find_button_prefix(ui, "刷新  ")
	_check(refresh != null, "Shop displays a refresh button")
	if refresh != null:
		refresh.pressed.emit()
	await _settle()
	_check(state.rerolls == 1 and _sounds.back() == "buy", "Shop refresh requests the buy sound")
	_check(_focus_id() == "reroll", "Refreshing preserves the refresh action's keyboard focus")

	state.pending_upgrades = 2
	ui.show_upgrades()
	await _settle()
	_check(_buttons_inside(ui), "Upgrade choices fit in 1280 by 720")
	_check(_text_inside(ui), "Upgrade choice text remains readable within the viewport")
	_press(ui, "选择强化")
	await _settle()
	_check(state.pending_upgrades == 1 and _sounds.back() == "level", "An upgrade consumes one pending choice and requests the level sound")
	_press(ui, "选择强化")
	await _settle()
	_check(state.pending_upgrades == 0 and _upgrade_completions == 1, "Completing all choices emits the transition exactly once")

	state.loadout = [
		{"id": "bone", "paid": 20, "rune": {"id": "pierce", "paid": 12, "uid": 20}},
		{"id": "frost", "paid": 20, "rune": {"id": "bounce", "paid": 12, "uid": 21}},
		{"id": "ember", "paid": 20, "rune": {"id": "blast", "paid": 12, "uid": 22}},
		{"id": "scatter", "paid": 20, "rune": {}},
	]
	state.rune_bag = [
		{"id": "pierce", "paid": 12, "uid": 23},
		{"id": "bounce", "paid": 12, "uid": 24},
		{"id": "blast", "paid": 12, "uid": 25},
		{"id": "pierce", "paid": 12, "uid": 26},
	]
	state.relic_counts = {"damage": 3, "haste": 3, "speed": 3, "vitality": 3, "armor": 3, "magnet": 3}
	ui.show_shop()
	await _settle()
	_check(_buttons_inside(ui), "Fully populated shop fits in 1280 by 720")
	_check(_text_inside(ui), "A full loadout, reserve bag and relic collection do not clip shop text")
	_check(_decorations_ignore_input(ui), "Shop ornamentation cannot block inventory interactions")
	var reached_reserve: bool = await _tab_to_focus("rune:24")
	_check(reached_reserve, "Native keyboard traversal can reach a specific reserve rune in a full shop")
	if reached_reserve:
		await _accept_focus()
		_check(_focus_id() == "equip:0" and _has_label_containing(ui, GameCatalog.rune("bounce").description), "Selecting a full-bag rune focuses the equip target and exposes its exact effect")
		_check(_buttons_inside(ui) and _text_inside(ui), "The selected-rune guide fits a fully populated shop")
		await _accept_focus()
		_check(int(state.loadout[0]["rune"].get("uid", 0)) == 24 and state.rune_bag.size() == 4, "Keyboard swapping with a full reserve equips the chosen rune and keeps all reserve slots")
		_check(_next_wave_requests == 0, "Full-inventory keyboard equip does not request the next wave")
	state.damage_dealt_by_weapon = {"bone": 320.0, "frost": 90.0, "ember": 240.0, "scatter": 15.0}
	state.damage_taken = 123.5
	state.hits_taken = 7
	state.last_hit = {"amount": 12.5, "source_id": "caster", "kind": "projectile", "wave": 8, "elapsed": 315.0}
	ui.show_result(false, "被咒术师的弹幕击倒，最后承伤12.5。", {})
	await _settle()
	_check(_buttons_inside(ui) and _text_inside(ui), "A four-weapon result with received-damage statistics preserves all text and restart/menu actions")
	_check(_has_label_containing(ui, "实际承伤  123.5") and _has_label_containing(ui, "受击  7 次"), "Results show actual accumulated damage received and hit count")
	_check(_has_label(ui, "最后承伤：%s / 弹丸 · 生命损失 12.5 · 第8波" % GameCatalog.enemy("caster").display_name), "Results distinguish the most recent hit source, type and life loss from total received damage")
	_check(_buttons_inside(ui) and _text_inside(ui), "The last-hit line fits beside four weapon contributions and the full final loadout")
	_check(_has_label(ui, "被咒术师的弹幕击倒，最后承伤12.5。"), "Results present the recorded death reason without replacing its source")
	_check(_has_label(ui, "实际总伤害  665.0"), "Results sum only the actual recorded life loss rather than inventing DPS")
	for definition: ContentDef in GameCatalog.weapons():
		var contribution: Node = ui.find_child("Damage_" + definition.id, true, false)
		_check(contribution != null and _has_label(contribution, definition.display_name), "A recorded weapon has a visible contribution row: " + definition.id)
	state.loadout.remove_at(2)
	ui.show_result(false, "试炼结束", {})
	await _settle()
	_check(ui.find_child("Damage_ember", true, false) != null, "Damage from a previously sold weapon remains in the result breakdown")
	state.last_hit = {"amount": 7.5, "source_id": "future_enemy", "kind": "future_attack", "wave": 3}
	var timeout_reason := "仪式已经完成。请在 90 秒内击败无面祭司。"
	ui.show_result(false, timeout_reason, {})
	await _settle()
	_check(_has_label(ui, "最后承伤：未知来源 / 未知攻击 · 生命损失 7.5 · 第3波"), "Unrecognized last-hit source and kind have readable fallbacks without exposing internal IDs")
	_check(_has_label(ui, timeout_reason), "Last-hit history never replaces a boss-timeout result reason with a supposed killing blow")
	state.last_hit = {"amount": 0.0, "source_id": "boss", "kind": "ritual", "wave": 8}
	ui.show_result(false, timeout_reason, {})
	await _settle()
	_check(ui.find_child("LastHit", true, false) == null, "A zero-damage last-hit entry does not fabricate a received hit")
	state.damage_dealt_by_weapon.clear()
	state.damage_taken = 0.0
	state.hits_taken = 0
	state.last_hit.clear()
	ui.show_result(false, "尚未交战", {})
	await _settle()
	_check(_has_label(ui, "尚无实际伤害记录") and ui.find_child("Damage_bone", true, false) == null, "Zero recorded damage shows an explicit empty state without fabricated weapon contributions")
	_check(_has_label_containing(ui, "实际承伤  0.0") and _has_label_containing(ui, "受击  0 次"), "A zero-stat result reports zero received damage and hits")
	_check(ui.find_child("LastHit", true, false) == null, "Empty last-hit data omits the last-hit line entirely")
	_check(_buttons_inside(ui) and _text_inside(ui), "The empty result keeps restart and menu fully visible")
	state.damage_dealt_by_weapon = {"bone": 10.0}
	state.damage_taken = 5.0
	state.hits_taken = 1
	state.last_hit = {"amount": 5.0, "source_id": "chaser", "kind": "contact", "wave": 1, "elapsed": 1.0}
	var restart_run: Callable = func(starter: String) -> void:
		state.begin(4096, starter)
		ui.show_hud()
	ui.start_requested.connect(restart_run)
	ui.show_result(false, "重开回归场景", {})
	await _settle()
	await _accept_focus()
	_check(state.damage_dealt_by_weapon.is_empty() and is_zero_approx(state.damage_taken) and state.hits_taken == 0 and state.last_hit.is_empty(), "Accepting the focused restart emits a real start signal and clears all prior-run combat statistics")
	_check(_has_label(ui, "波次  1 / 8") and not _has_label(ui, "实际总伤害  10.0"), "Restarted HUD contains no stale result statistics")
	ui.start_requested.disconnect(restart_run)
	ui.show_result(false, "新局尚未交战", {})
	await _settle()
	_check(_has_label(ui, "尚无实际伤害记录"), "A subsequent empty new-run result does not resurrect previous damage contributions")
	ui.queue_free()
	await process_frame
	print("UI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_boss_hud(ui: GameUI, loadout: Array) -> void:
	var status_before: Rect2 = ui.find_child("RitualStatus", true, false).get_global_rect()
	var equipment_before: Rect2 = ui.find_child("RitualEquipment", true, false).get_global_rect()
	var boss_snapshot: Dictionary = {"health": 100, "max_health": 100, "wave": 3, "time_left": 45.0,
		"loadout": loadout, "boss_health": 150.0, "boss_max_health": 300.0}
	var wave_label: Label = ui._hud["wave"]
	var timer_label: Label = ui._hud["time"]
	var boss_status: Control = ui._hud["boss"]
	var boss_bar: ProgressBar = ui._hud["boss_bar"]
	_check(GameUI.CORAL.is_equal_approx(Color("ed9a86")), "Boss urgency uses the specified stable coral color")
	ui.update_hud(boss_snapshot)
	_check(wave_label.text == "击败首领" and timer_label.text == "限时  00:45", "A living boss changes the objective and timer even outside wave eight")
	_check(boss_status.visible and boss_bar.value == 150.0 and boss_bar.max_value == 300.0, "Boss objective uses actual positive health and maximum health")
	_check(timer_label.get_theme_color("font_color").is_equal_approx(GameUI.BONE), "Boss time above ten seconds keeps the ordinary bone color")
	ui.notify("首领限时验证提示")
	await _settle()
	_check(ui.find_child("RitualStatus", true, false).get_global_rect() == status_before and ui.find_child("RitualEquipment", true, false).get_global_rect() == equipment_before and _text_inside(ui), "Boss instructions keep the original readable HUD footprint")
	var notice: Label = ui._toast
	_check(not notice.get_global_rect().intersects(boss_status.get_global_rect()) and not notice.get_global_rect().intersects(CombatSim.ARENA), "Boss instructions preserve safe notification space above the arena")
	for boundary: Array in [[10.001, "限时  00:11", false], [10.0, "限时  00:10", true], [9.99, "限时  00:10", true], [0.0, "限时  00:00", true]]:
		boss_snapshot["time_left"] = float(boundary[0])
		ui.update_hud(boss_snapshot)
		_check(timer_label.text == boundary[1], "Boss timer rounds upward at the actual-time boundary: " + str(boundary[0]))
		var expected: Color = GameUI.CORAL if boundary[2] else GameUI.BONE
		_check(timer_label.get_theme_color("font_color").is_equal_approx(expected), "Urgency uses actual remaining seconds rather than the rounded label: " + str(boundary[0]))
	for repeat: int in 3:
		ui.update_hud(boss_snapshot)
	_check(timer_label.get_theme_color("font_color").is_equal_approx(GameUI.CORAL) and timer_label.text == "限时  00:00", "Repeated identical boss snapshots preserve a stable urgency color and timer")
	boss_snapshot["time_left"] = 45.0
	ui.update_hud(boss_snapshot)
	_check(timer_label.get_theme_color("font_color").is_equal_approx(GameUI.BONE), "A later nonurgent boss snapshot resets the previous urgency color")
	boss_snapshot["wave"] = 8
	boss_snapshot["time_left"] = 9.99
	ui.update_hud(boss_snapshot)
	boss_snapshot["boss_health"] = 0.0
	ui.update_hud(boss_snapshot)
	_check(not boss_status.visible and wave_label.text == "波次  8 / 8" and timer_label.text == "剩余  00:10", "Zero boss health restores the ordinary objective and timer even on wave eight")
	_check(timer_label.get_theme_color("font_color").is_equal_approx(GameUI.BONE), "A defeated boss cannot leave urgency color on the normal-wave timer")
	boss_snapshot["boss_health"] = 150.0
	ui.update_hud(boss_snapshot)
	boss_snapshot["boss_max_health"] = 0.0
	ui.update_hud(boss_snapshot)
	_check(not boss_status.visible and wave_label.text == "波次  8 / 8" and timer_label.text == "剩余  00:10" and timer_label.get_theme_color("font_color").is_equal_approx(GameUI.BONE), "Positive current health without a positive maximum is not a living-boss HUD")
	boss_snapshot["boss_max_health"] = 300.0
	ui.update_hud(boss_snapshot)
	boss_snapshot["benchmark"] = true
	ui.update_hud(boss_snapshot)
	_check(wave_label.text == "性能测试" and timer_label.text == "采样  00:10", "Benchmark labels take priority over a live boss and its short remaining time")
	_check(timer_label.get_theme_color("font_color").is_equal_approx(GameUI.BONE), "Benchmark sampling never inherits the boss failure-countdown color")
	boss_snapshot.erase("benchmark")
	boss_snapshot["time_left"] = -0.25
	ui.update_hud(boss_snapshot)
	_check(timer_label.text == "限时  00:00" and timer_label.get_theme_color("font_color").is_equal_approx(GameUI.CORAL), "Negative remaining boss time clamps to the visible zero-second boundary")
	ui.show_hud()
	wave_label = ui._hud["wave"]
	timer_label = ui._hud["time"]
	boss_status = ui._hud["boss"]
	_check(wave_label.text == "波次  1 / 8" and timer_label.text == "剩余  00:45" and not boss_status.visible and timer_label.get_theme_color("font_color").is_equal_approx(GameUI.BONE), "A rebuilt HUD starts with ordinary labels and no stale boss urgency")
	boss_snapshot["time_left"] = 10.0
	ui.update_hud(boss_snapshot)
	_check(wave_label.text == "击败首领" and timer_label.text == "限时  00:10" and boss_status.visible and timer_label.get_theme_color("font_color").is_equal_approx(GameUI.CORAL), "A fresh boss snapshot restores urgency after HUD reconstruction")
	ui.notify("重建后的首领提示")
	await _settle()
	_check(ui.find_child("RitualStatus", true, false).get_global_rect() == status_before and ui.find_child("RitualEquipment", true, false).get_global_rect() == equipment_before and not notice.get_global_rect().intersects(boss_status.get_global_rect()), "HUD reconstruction retains the original layout and notification separation")
	ui.update_hud({"health": 100, "max_health": 100, "wave": 1, "time_left": 45.0, "loadout": loadout})
	_check(wave_label.text == "波次  1 / 8" and timer_label.text == "剩余  00:45" and timer_label.get_theme_color("font_color").is_equal_approx(GameUI.BONE), "Ordinary snapshots fully restore timer labels and color after the boss sequence")


func _settle() -> void:
	# Container layout and deferred refreshes both need a complete frame.
	await process_frame
	await process_frame
	await process_frame


func _focus_id() -> String:
	var owner := root.gui_get_focus_owner()
	return "" if owner == null else str(owner.get_meta("shop_focus_id", ""))


func _accept_focus() -> void:
	_check(root.gui_get_focus_owner() is Button, "ui_accept has an actionable focused button")
	_send_action("ui_accept")
	await _settle()


func _tab_to_focus(focus_id: String) -> bool:
	for step: int in range(48):
		if _focus_id() == focus_id:
			return true
		_send_action("ui_focus_next")
		await process_frame
	return false


func _send_action(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	root.push_input(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	root.push_input(release)


func _has_label_containing(node: Node, text: String) -> bool:
	if node is Label and node.is_visible_in_tree() and node.text.contains(text):
		return true
	for child: Node in node.get_children():
		if _has_label_containing(child, text):
			return true
	return false


func _effect_tooltip(node: Node, description: String) -> Control:
	if node is Control and node.is_visible_in_tree() and node.tooltip_text.contains(description) and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return node as Control
	for child: Node in node.get_children():
		var found := _effect_tooltip(child, description)
		if found != null:
			return found
	return null


func _test_chinese_font(ui: GameUI) -> void:
	var interface: Control = ui.get("_root")
	var font: Font = interface.theme.default_font
	_check(font.has_char("敌".unicode_at(0)), "The actual theme font covers the enemy character that previously rendered as a box")
	_check(font.has_char("杀".unicode_at(0)), "The actual theme font covers the kill character that previously rendered as a box")
	var sample: String = "敌杀范围击中魂屑法器符文生命护甲移速拾取试炼祭坛恢复商店选择开始暂停余烬"
	var missing: PackedStringArray = []
	for character: String in sample:
		if not font.has_char(character.unicode_at(0)):
			missing.append(character)
	_check(missing.is_empty(), "The actual theme font covers common Chinese UI characters; missing: " + "".join(missing))
	var line: TextLine = TextLine.new()
	line.add_string(sample, font, 17)
	var ts: TextServer = TextServerManager.get_primary_interface()
	var glyphs: Array[Dictionary] = ts.shaped_text_get_glyphs(line.get_rid())
	var invalid: PackedStringArray = []
	var shaped: Dictionary = {}
	for glyph: Dictionary in glyphs:
		var character: String = sample.substr(int(glyph["start"]), int(glyph["end"]) - int(glyph["start"]))
		var font_rid: RID = glyph["font_rid"]
		if not font_rid.is_valid() or int(glyph["index"]) <= 0:
			invalid.append(character)
		else:
			shaped[character] = true
	_check(not glyphs.is_empty() and invalid.is_empty(), "Real Chinese shaping produces valid font RIDs and glyph indices; invalid: " + "".join(invalid))
	_check(shaped.has("敌") and shaped.has("杀"), "The previously missing enemy and kill characters have real shaped glyphs")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _press(node: Node, text: String) -> void:
	var button: Button = _find_button(node, text)
	_check(button != null, "Button exists: " + text)
	if button != null:
		button.pressed.emit()


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null


func _find_button_prefix(node: Node, prefix: String) -> Button:
	if node is Button and node.text.begins_with(prefix) and node.is_visible_in_tree():
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button_prefix(child, prefix)
		if found != null:
			return found
	return null


func _first_slider(node: Node) -> HSlider:
	if node is HSlider:
		return node as HSlider
	for child: Node in node.get_children():
		var found: HSlider = _first_slider(child)
		if found != null:
			return found
	return null


func _has_label(node: Node, text: String) -> bool:
	if node is Label and node.text == text and node.is_visible_in_tree():
		return true
	for child: Node in node.get_children():
		if _has_label(child, text):
			return true
	return false


func _buttons_inside(node: Node) -> bool:
	if node is Button and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		if rect.position.x < -1 or rect.position.y < -1 or rect.end.x > 1281 or rect.end.y > 721:
			push_error("Button exceeds viewport: %s %s" % [node.text, rect])
			return false
	for child: Node in node.get_children():
		if not _buttons_inside(child):
			return false
	return true


func _text_inside(node: Node) -> bool:
	if node is Label and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		if rect.position.x < -1 or rect.position.y < -1 or rect.end.x > 1281 or rect.end.y > 721 or node.size.y + 1.0 < node.get_minimum_size().y:
			push_error("Text exceeds its readable area: %s %s minimum=%s" % [node.text, rect, node.get_minimum_size()])
			return false
	for child: Node in node.get_children():
		if not _text_inside(child):
			return false
	return true


func _decorations_ignore_input(node: Node) -> bool:
	if node.name == "RitualFrame" or node.name == "PageOrnament":
		if not node is Control or node.mouse_filter != Control.MOUSE_FILTER_IGNORE or node.focus_mode != Control.FOCUS_NONE or node.is_processing():
			return false
	for child: Node in node.get_children():
		if not _decorations_ignore_input(child):
			return false
	return true


func _on_start(starter: String) -> void:
	_started = starter


func _on_feedback(sound: String) -> void:
	_sounds.append(sound)


func _on_setting(key: String, value: Variant) -> void:
	_settings[key] = value


func _on_upgrades_finished() -> void:
	_upgrade_completions += 1
