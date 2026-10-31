extends Node

enum Screen { TITLE, COMBAT, UPGRADE, SHOP, RESULT }

var run: RunState = RunState.new()
var store: GameStore = GameStore.new()
var world: CombatWorld
var ui: GameUI
var sound: SoundBank
var screen: Screen = Screen.TITLE
var paused: bool = false
var args: PackedStringArray
var _screenshot_clock: float = -1.0
var _screenshot_path: String = ""
var _benchmark: bool = false
var _benchmark_seconds: float = 300.0
var _benchmark_report_path: String = "res://reports/performance.json"
var _benchmark_start: int = 0
var _benchmark_warmup: int = 0
var _frame_samples: Array[float] = []
var _last_frame_usec: int = 0
var _peak_rune_flashes: int = 0
var _run_generation: int = 0
var _upgrade_request_sim: CombatSim
var _upgrade_request_generation: int = -1
var _combat_upgrade_sim: CombatSim
var _combat_upgrade_generation: int = -1
var _wf_actions_preview_redirecting: bool = false

func _ready() -> void:
	if "--wf-dash-benchmark" in OS.get_cmdline_user_args() and not has_meta("wf_dash_benchmark_child"):
		store.persistent = false
		_wf_actions_preview_redirecting = true
		process_mode = Node.PROCESS_MODE_DISABLED
		_start_wf_dash_benchmark.call_deferred()
		return
	if "--wf-equipment-preview" in OS.get_cmdline_user_args() and not has_meta("wf_equipment_preview_child"):
		store.persistent = false
		_wf_actions_preview_redirecting = true
		process_mode = Node.PROCESS_MODE_DISABLED
		_start_wf_equipment_preview.call_deferred()
		return
	if "--wf-actions-preview" in OS.get_cmdline_user_args() and not has_meta("wf_actions_preview_child"):
		store.persistent = false
		_wf_actions_preview_redirecting = true
		process_mode = Node.PROCESS_MODE_DISABLED
		_start_wf_actions_preview.call_deferred()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# VSync schedules presentation; a second 60 Hz software limiter can miss vblank.
	Engine.max_fps = 0
	args = OS.get_cmdline_user_args()
	var selected_arena: String = _arena_from_args(args)
	if selected_arena.is_empty():
		push_error("--arena requires an authored arena or a playable JP map-layer ID")
		get_tree().quit(2)
		return
	# Direct CLI validation must be as isolated as the standalone preview fixtures.
	# Preserve a caller's explicit persistent=false even for ordinary startup.
	for diagnostic: String in ["--smoke", "--autoplay", "--shop-preview", "--benchmark", "--capture-only"]:
		if diagnostic in args:
			store.persistent = false
			break
	store.load_profile()
	ControlBindings.install(store.controls)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	sound = SoundBank.new()
	add_child(sound)
	sound.set_volume(float(store.settings["volume"]))
	world = CombatWorld.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.sound = sound
	world.apply_visual_settings(store.settings)
	add_child(world)
	ui = GameUI.new()
	add_child(ui)
	ui.bind(run)
	ui.set_selected_arena(selected_arena)
	ui.set_settings(store.settings)
	ui.set_controls(store.controls)
	ui.set_progress(store.unlocked_starters)
	ui.set_selected_hero(store.selected_hero)
	ui.start_requested.connect(_start_run)
	ui.next_wave_requested.connect(_next_wave)
	ui.resume_requested.connect(_resume)
	ui.menu_requested.connect(_title)
	ui.quit_requested.connect(_quit_game)
	ui.setting_changed.connect(_setting_changed)
	ui.controls_changed.connect(_controls_changed)
	ui.feedback.connect(func(name: String) -> void: sound.play(name, -12.0))
	ui.upgrades_finished.connect(_upgrades_finished)
	world.hud_changed.connect(ui.update_hud)
	world.wave_ended.connect(_wave_ended)
	run.changed.connect(_on_run_changed)
	_title()
	if "--smoke" in args:
		_start_run("bone")
		_screenshot_clock = 3.0
		_screenshot_path = "res://reports/gameplay.png"
	if "--autoplay" in args:
		_start_run("bone")
		world.autopilot = true
		get_window().title = "秘术余烬 · 自动流程验证（不保存设置与成绩）"
		ui.notify("自动走位验证 · 升级时暂停，选择后继续当前波次")
	if "--shop-preview" in args:
		_start_run("bone")
		world.stop()
		run.collect_souls(120)
		run.finish_wave()
		run.generate_shop()
		screen = Screen.SHOP
		ui.show_shop()
	if "--benchmark" in args:
		_start_benchmark()
	for argument: String in args:
		if argument.begins_with("--capture="):
			_screenshot_path = argument.trim_prefix("--capture=")
			_screenshot_clock = 2.0
	for argument: String in args:
		if argument.begins_with("--capture-delay="):
			_screenshot_clock = maxf(0.5, argument.trim_prefix("--capture-delay=").to_float())

func _start_wf_dash_benchmark() -> void:
	var diagnostic_script := load("res://scripts/diagnostics/dash_benchmark.gd") as Script
	if diagnostic_script == null or not diagnostic_script.can_instantiate():
		push_error("The embedded dash benchmark diagnostic is unavailable")
		get_tree().quit(2)
		return
	var diagnostic: Node = diagnostic_script.new()
	get_tree().root.add_child(diagnostic)
	queue_free()

func _start_wf_actions_preview() -> void:
	# Runtime loading avoids a preload cycle: the diagnostic instantiates MAIN.
	var diagnostic_script := load("res://scripts/diagnostics/wf_actions_preview.gd") as Script
	if diagnostic_script == null:
		push_error("The embedded World Flipper preview diagnostic is unavailable")
		get_tree().quit(2)
		return
	var diagnostic: Node = diagnostic_script.new()
	get_tree().root.add_child(diagnostic)
	queue_free()

func _start_wf_equipment_preview() -> void:
	var diagnostic_script := load("res://scripts/diagnostics/wf_equipment_preview.gd") as Script
	if diagnostic_script == null:
		push_error("The embedded equipment preview diagnostic is unavailable")
		get_tree().quit(2)
		return
	var diagnostic: Node = diagnostic_script.new()
	get_tree().root.add_child(diagnostic)
	queue_free()

func _start_run(starter: String) -> void:
	if not store.starter_unlocked(starter) and starter != HeroCatalog.definition(ui.selected_hero()).starter_weapon:
		ui.notify("此起始法器尚未解锁。")
		return
	_begin_run(starter)

func _begin_run(starter: String, seed_value: int = 0) -> void:
	_invalidate_combat_upgrades()
	get_tree().paused = false
	paused = false
	store.selected_hero = HeroCatalog.normalize_id(ui.selected_hero())
	store.save_profile()
	run.begin(seed_value if seed_value > 0 else int(Time.get_unix_time_from_system()) ^ Time.get_ticks_usec(), starter, ui.selected_arena(), store.selected_hero)
	screen = Screen.COMBAT
	ui.show_hud()
	world.begin(run)
	sound.play("level", -15.0)
	ui.notify(str(ArenaCatalog.definition(run.arena_id)["name"]) + " · 试炼开始")

func _next_wave() -> void:
	if screen != Screen.SHOP or paused or get_tree().paused:
		return
	_invalidate_combat_upgrades()
	run.next_wave()
	screen = Screen.COMBAT
	ui.show_hud()
	world.begin(run)
	sound.play("level", -17.0)
	var wave_note: String = "第 %d 波 · %s" % [run.wave, str(RogueRules.route(run.active_route).get("name", "原途"))]
	if not run.core_id.is_empty():
		wave_note += " · " + str(RogueRules.core(run.core_id)["name"])
	if run.altar_choice == "accepted" and run.wave == run.altar_wave and not run.hunter_defeated:
		wave_note += " · 追猎者现身"
	ui.notify(wave_note)

func _wave_ended(won: bool, reason: String) -> void:
	# Deferring avoids replacing a simulation while its final signal is still on the stack.
	_finish_wave_for_sim.call_deferred(won, reason, world.sim, _run_generation)

func _finish_wave_for_sim(won: bool, reason: String, simulation: CombatSim, generation: int) -> void:
	if generation != _run_generation or simulation != world.sim:
		return
	_finish_wave(won, reason)

func _finish_wave(won: bool, reason: String) -> void:
	if screen != Screen.COMBAT and not (screen == Screen.UPGRADE and _combat_upgrades_active()):
		return
	_invalidate_combat_upgrades()
	# A pause can arrive between ended and this deferred transition. Settlement
	# replaces the overlay, so clear both pause states before leaving combat.
	_resume()
	if not won or run.wave == GameCatalog.WAVE_DEFS.size():
		screen = Screen.RESULT
		store.record_run(run, won)
		ui.set_progress(store.unlocked_starters)
		sound.play("victory" if won else "defeat", -8.0)
		ui.show_result(won, reason, store.best)
		if not store.last_unlocks.is_empty():
			var names: PackedStringArray = []
			for id: String in store.last_unlocks:
				names.append(GameCatalog.weapon(id).display_name)
			ui.notify("已解锁起始法器：" + "、".join(names))
		return
	run.finish_wave()
	if run.pending_upgrades > 0:
		screen = Screen.UPGRADE
		sound.play("level", -12.0)
		ui.show_upgrades()
	else:
		_open_shop()

func _open_shop() -> void:
	if (screen != Screen.COMBAT and screen != Screen.UPGRADE) or _combat_upgrades_active():
		return
	_invalidate_combat_upgrades()
	# The last upgrade can settle after a pause input but before its deferred shop.
	# Replacing that overlay must also release the actual scene-tree pause.
	_resume()
	screen = Screen.SHOP
	run.generate_shop()
	ui.show_shop()
	sound.play("buy", -15.0)

func _on_run_changed() -> void:
	if not _can_open_combat_upgrades():
		return
	var simulation: CombatSim = world.sim
	if _upgrade_request_sim == simulation and _upgrade_request_generation == _run_generation:
		return
	_upgrade_request_sim = simulation
	_upgrade_request_generation = _run_generation
	_open_combat_upgrades.call_deferred(simulation, _run_generation)

func _can_open_combat_upgrades() -> bool:
	return (
		screen == Screen.COMBAT and not _benchmark and not paused
		and run.pending_upgrades > 0 and run.health > 0.0
		and world != null and world.active and world.sim != null and not world.sim.complete
	)

func _open_combat_upgrades(simulation: CombatSim, generation: int) -> void:
	if _upgrade_request_sim != simulation or _upgrade_request_generation != generation:
		return
	_upgrade_request_sim = null
	_upgrade_request_generation = -1
	if generation != _run_generation or simulation != world.sim or not _can_open_combat_upgrades():
		return
	_combat_upgrade_sim = simulation
	_combat_upgrade_generation = generation
	screen = Screen.UPGRADE
	world.clear_pending_actions()
	get_tree().paused = true
	ui.show_upgrades(true)
	sound.play("level", -12.0)

func _combat_upgrades_active() -> bool:
	return _combat_upgrade_sim != null and _combat_upgrade_generation == _run_generation and world != null and _combat_upgrade_sim == world.sim

func _upgrades_finished() -> void:
	if screen != Screen.UPGRADE or run.pending_upgrades > 0:
		return
	if _combat_upgrade_sim != null and not _combat_upgrades_active():
		return
	if not _combat_upgrades_active():
		_open_shop()
		return
	if not world.active or world.sim.complete:
		return
	_combat_upgrade_sim = null
	_combat_upgrade_generation = -1
	screen = Screen.COMBAT
	ui.show_hud()
	ui.update_hud(world.hud_snapshot())
	get_tree().paused = paused
	if paused:
		ui.show_pause()

func _invalidate_combat_upgrades() -> void:
	_run_generation += 1
	if world != null:
		world.clear_pending_actions()
	_upgrade_request_sim = null
	_upgrade_request_generation = -1
	_combat_upgrade_sim = null
	_combat_upgrade_generation = -1

func _title() -> void:
	_invalidate_combat_upgrades()
	get_window().title = "秘术余烬" if store.persistent else "秘术余烬 · 验证模式（不保存设置与成绩）"
	get_tree().paused = false
	paused = false
	screen = Screen.TITLE
	if world != null:
		world.stop()
	if ui != null:
		ui.hide_pause()
		ui.set_progress(store.unlocked_starters)
		ui.show_title(store.best)

func _pause() -> void:
	if screen == Screen.TITLE or screen == Screen.RESULT or _benchmark:
		return
	world.clear_pending_actions()
	paused = true
	get_tree().paused = true
	ui.show_pause()

func _resume() -> void:
	paused = false
	get_tree().paused = _combat_upgrades_active()
	ui.hide_pause()
	_on_run_changed()

func _setting_changed(key: String, value: Variant) -> void:
	store.settings[key] = value
	world.apply_visual_settings(store.settings)
	if key == "volume":
		sound.set_volume(float(value))
	store.save_profile()

func _controls_changed(value: Dictionary) -> void:
	store.controls = ControlBindings.normalize(value)
	ControlBindings.install(store.controls)
	ui.set_controls(store.controls)
	world.clear_pending_actions()
	store.save_profile()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_control_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_handle_control_input(event)

func _handle_control_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		if event.keycode == KEY_ESCAPE:
			_handle_back_input(true)
			return
		if event.keycode == KEY_F11 or (event.keycode == KEY_F and event.alt_pressed):
			var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
	elif event is InputEventJoypadButton:
		if not event.pressed:
			return
		if event.button_index == JOY_BUTTON_B:
			_handle_back_input(false)
			return
		if event.button_index == JOY_BUTTON_START:
			if paused:
				_resume()
			else:
				_pause()
			get_viewport().set_input_as_handled()
			return
	else:
		return
	if not _can_request_combat_skill():
		return
	if ControlBindings.pressed(event, "dash"):
		world.request_dash()
		get_viewport().set_input_as_handled()
	elif ControlBindings.pressed(event, "pulse"):
		world.request_pulse()
		get_viewport().set_input_as_handled()
	elif ControlBindings.pressed(event, "skill_secondary"):
		world.request_skill(1)
		get_viewport().set_input_as_handled()
	elif ControlBindings.pressed(event, "hero_skill"):
		world.request_hero_skill()
		get_viewport().set_input_as_handled()

func _handle_back_input(allow_pause: bool) -> void:
	if ui.handle_back():
		pass
	elif paused:
		_resume()
	elif allow_pause:
		_pause()
	else:
		return
	get_viewport().set_input_as_handled()

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected or _benchmark or screen != Screen.COMBAT or world == null or not world.active or world.sim == null or world.sim.complete:
		return
	world.clear_pending_actions()
	if not paused:
		_pause()

func _can_request_combat_skill() -> bool:
	return (
		screen == Screen.COMBAT and not paused and not get_tree().paused and not _benchmark
		and world != null and world.active and world.sim != null and not world.sim.complete
		and run.health > 0.0
	)

func _notification(what: int) -> void:
	if _wf_actions_preview_redirecting:
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and (screen == Screen.COMBAT or _combat_upgrades_active()) and not paused and not _benchmark and not ("--smoke" in args) and not ("--autoplay" in args):
		_pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		store.save_profile()
		_quit_game()

func _quit_game(code: int = 0) -> void:
	sound.shutdown()
	await get_tree().create_timer(0.08, true).timeout
	get_tree().quit(code)

func _process(delta: float) -> void:
	if _screenshot_clock > 0.0:
		_screenshot_clock -= delta
		if _screenshot_clock <= 0.0:
			_capture.call_deferred()
	if _benchmark:
		_record_benchmark()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var result: Error = screenshot.save_png(_screenshot_path)
	print("CAPTURE ", _screenshot_path, " result=", result)
	if "--smoke" in args or "--capture-only" in args:
		_quit_game(0 if result == OK else 1)

static func _arena_from_args(arguments: PackedStringArray) -> String:
	var selected: String = "reliquary"
	for argument: String in arguments:
		if argument == "--arena":
			return ""
		if argument.begins_with("--arena="):
			selected = argument.trim_prefix("--arena=")
			if not ArenaCatalog.contains(selected):
				return ""
	return selected

static func _benchmark_seed_from_args(arguments: PackedStringArray) -> int:
	var seed_value: int = 0
	for argument: String in arguments:
		if argument == "--benchmark-seed":
			return -1
		if not argument.begins_with("--benchmark-seed="):
			continue
		var value: String = argument.trim_prefix("--benchmark-seed=")
		if value != value.strip_edges() or not value.is_valid_int():
			return -1
		var digits: String = value.trim_prefix("+").lstrip("0")
		if digits.is_empty() or digits.begins_with("-") or digits.length() > 19:
			return -1
		if digits.length() == 19 and digits > "9223372036854775807":
			return -1
		seed_value = digits.to_int()
	return seed_value

func _start_benchmark() -> void:
	var seed_value: int = _benchmark_seed_from_args(args)
	if seed_value < 0:
		push_error("--benchmark-seed requires a positive integer within the signed 64-bit range")
		_quit_game(2)
		return
	var core: String = ""
	for argument: String in args:
		if argument.begins_with("--benchmark-core="):
			core = argument.trim_prefix("--benchmark-core=")
			if RogueRules.core(core).is_empty():
				push_error("--benchmark-core requires frostfire or bone_chorus")
				_quit_game(2)
				return
	_benchmark_report_path = "res://reports/performance-rogue-%s.json" % core if not core.is_empty() else "res://reports/performance.json"
	_begin_run("bone", seed_value)
	if run.arena_id != "reliquary":
		_benchmark_report_path = "res://reports/performance-arena-%s%s.json" % [run.arena_id, "-" + core if not core.is_empty() else ""]
	# Diagnostic pressure bypasses shopping, so select the requested behavior
	# directly without granting equipment or touching persistent unlocks.
	run.core_id = core
	_benchmark = true
	world.stress_mode = true
	world.rune_stress_mode = false
	world.sim.populate_stress()
	_peak_rune_flashes = 0
	if "--benchmark-runes" in args or "--benchmark-content" in args:
		world.enable_rune_stress("--benchmark-content" in args)
	_benchmark_start = Time.get_ticks_usec()
	_last_frame_usec = _benchmark_start
	_benchmark_warmup = _benchmark_start + 5000000
	for argument: String in args:
		if argument.begins_with("--seconds="):
			_benchmark_seconds = maxf(5.0, argument.trim_prefix("--seconds=").to_float())
	world.benchmark_time_left = _benchmark_seconds + 5.0
	get_window().title = "秘术余烬 · 性能压力测试（非普通关卡，不保存设置与成绩）"
	if world.rune_stress_mode:
		get_window().title = "秘术余烬 · 符文反馈压力测试（非普通关卡，不保存设置与成绩）"
	if world.content_stress_mode:
		get_window().title = "秘术余烬 · 多法器压力测试（非普通关卡，不保存设置与成绩）"
	ui.update_hud(world.hud_snapshot())
	ui.notify("性能压力测试 · 不结算关卡 · 采样结束后自动关闭")
	print("BENCHMARK_START 300 enemies / 600 projectiles / 200 drops, ", _benchmark_seconds, "s + 5s warmup")
	if world.rune_stress_mode:
		print("BENCHMARK_SCENARIO ", "content-feedback" if world.content_stress_mode else "rune-feedback", ": positive weapon damage, all rune families; weapons=", world.stress_weapon_ids)

func _record_benchmark() -> void:
	var now: int = Time.get_ticks_usec()
	_peak_rune_flashes = maxi(_peak_rune_flashes, world._rune_flashes.size())
	world.benchmark_time_left = maxf(0.0, _benchmark_seconds - float(now - _benchmark_warmup) / 1000000.0)
	if now > _benchmark_warmup:
		_frame_samples.append(float(now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now
	if float(now - _benchmark_warmup) / 1000000.0 < _benchmark_seconds:
		return
	_frame_samples.sort()
	var total: float = 0.0
	for value: float in _frame_samples:
		total += value
	var p99: float = _frame_samples[mini(_frame_samples.size() - 1, int(float(_frame_samples.size()) * 0.99))]
	var fps: float = 1000.0 * float(_frame_samples.size()) / maxf(1.0, total)
	var result: Dictionary = {"duration_seconds": _benchmark_seconds, "samples": _frame_samples.size(), "average_fps": fps, "p99_frame_ms": p99, "enemies": world.sim.enemy_count, "projectiles": world.sim.shot_count, "pickups": world.sim.soul_count, "internal_resolution": "1280x720", "os": OS.get_name(), "renderer": "gl_compatibility", "passed": fps >= 58.0 and p99 <= 33.0}
	result["scenario"] = "rune-feedback" if world.rune_stress_mode else "baseline"
	if world.content_stress_mode:
		result["scenario"] = "content-feedback"
	result["weapon_ids"] = Array(world.stress_weapon_ids) if world.rune_stress_mode else ["bone"]
	if world.content_stress_mode:
		result["damage_by_weapon"] = run.damage_dealt_by_weapon.duplicate()
		result["projectile_families_at_end"] = world._projectile_painter.get_stats()["family_counts"]
		result["projectile_visual_revision"] = ProjectilePainter.VISUAL_REVISION
	result["settings"] = store.settings.duplicate()
	result["persistent_profile"] = store.persistent
	result["run_seed"] = run.summary()["seed"]
	result["arena_id"] = run.arena_id
	result["rune_visual_peak"] = _peak_rune_flashes
	var impact_stats: Dictionary = world._impact_painter.get_stats()
	result["impact_visual_revision"] = "primary-impact-v1"
	result["enemy_hit_visual_revision"] = CombatWorld.ENEMY_HIT_VISUAL_REVISION
	result["impact_visual_peak"] = impact_stats["peak_active"]
	result["impact_visual_capacity"] = impact_stats["capacity"]
	result["impact_draw_commands_at_end"] = impact_stats["draw_commands"]
	result["primary_hits"] = world.sim.primary_hits
	result["secondary_hits"] = world.sim.secondary_hits
	result["core_id"] = run.core_id
	result["core_activations"] = world.sim.core_activations.duplicate()
	var output: FileAccess = FileAccess.open(_benchmark_report_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	print("BENCHMARK_RESULT ", JSON.stringify(result))
	_benchmark = false
	_quit_game(0 if bool(result["passed"]) else 1)
