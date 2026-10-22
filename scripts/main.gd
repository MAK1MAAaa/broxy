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
var _benchmark_start: int = 0
var _benchmark_warmup: int = 0
var _frame_samples: Array[float] = []
var _last_frame_usec: int = 0
var _peak_rune_flashes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# VSync schedules presentation; a second 60 Hz software limiter can miss vblank.
	Engine.max_fps = 0
	args = OS.get_cmdline_user_args()
	store.load_profile()
	sound = SoundBank.new()
	add_child(sound)
	sound.set_volume(float(store.settings["volume"]))
	world = CombatWorld.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.sound = sound
	world.settings = store.settings
	add_child(world)
	ui = GameUI.new()
	add_child(ui)
	ui.bind(run)
	ui.set_settings(store.settings)
	ui.start_requested.connect(_start_run)
	ui.next_wave_requested.connect(_next_wave)
	ui.resume_requested.connect(_resume)
	ui.menu_requested.connect(_title)
	ui.quit_requested.connect(_quit_game)
	ui.setting_changed.connect(_setting_changed)
	ui.feedback.connect(func(name: String) -> void: sound.play(name, -12.0))
	ui.upgrades_finished.connect(_open_shop)
	world.hud_changed.connect(ui.update_hud)
	world.wave_ended.connect(_wave_ended)
	_title()
	if "--smoke" in args:
		_start_run("bone")
		_screenshot_clock = 3.0
		_screenshot_path = "res://reports/gameplay.png"
	if "--autoplay" in args:
		_start_run("bone")
		world.autopilot = true
		get_window().title = "秘术余烬 · 自动流程验证"
		ui.notify("自动走位验证 · 普通关卡在 45 秒后正常结算")
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

func _start_run(starter: String) -> void:
	get_tree().paused = false
	paused = false
	run.begin(int(Time.get_unix_time_from_system()) ^ Time.get_ticks_usec(), starter)
	screen = Screen.COMBAT
	ui.show_hud()
	world.begin(run)
	sound.play("level", -15.0)
	ui.notify("移动躲避 · 法器自动攻击 · 收集魂屑，波间改装")

func _next_wave() -> void:
	if screen != Screen.SHOP:
		return
	run.next_wave()
	screen = Screen.COMBAT
	ui.show_hud()
	world.begin(run)
	sound.play("level", -17.0)
	ui.notify("第 %d 波 · %s" % [run.wave, GameCatalog.wave(run.wave).display_name])

func _wave_ended(won: bool, reason: String) -> void:
	# Deferring avoids replacing a simulation while its final signal is still on the stack.
	_finish_wave.call_deferred(won, reason)

func _finish_wave(won: bool, reason: String) -> void:
	if screen != Screen.COMBAT:
		return
	# A pause can arrive between ended and this deferred transition. Settlement
	# replaces the overlay, so clear both pause states before leaving combat.
	_resume()
	if not won or run.wave == GameCatalog.WAVE_DEFS.size():
		screen = Screen.RESULT
		store.record_run(run, won)
		sound.play("victory" if won else "defeat", -8.0)
		ui.show_result(won, reason, store.best)
		return
	run.finish_wave()
	if run.pending_upgrades > 0:
		screen = Screen.UPGRADE
		sound.play("level", -12.0)
		ui.show_upgrades()
	else:
		_open_shop()

func _open_shop() -> void:
	if screen != Screen.COMBAT and screen != Screen.UPGRADE:
		return
	screen = Screen.SHOP
	run.generate_shop()
	ui.show_shop()
	sound.play("buy", -15.0)

func _title() -> void:
	get_window().title = "秘术余烬"
	get_tree().paused = false
	paused = false
	screen = Screen.TITLE
	if world != null:
		world.stop()
	if ui != null:
		ui.hide_pause()
		ui.show_title(store.best)

func _pause() -> void:
	if screen == Screen.TITLE or screen == Screen.RESULT or _benchmark:
		return
	paused = true
	get_tree().paused = true
	ui.show_pause()

func _resume() -> void:
	paused = false
	get_tree().paused = false
	ui.hide_pause()

func _setting_changed(key: String, value: Variant) -> void:
	store.settings[key] = value
	world.settings = store.settings
	if key == "volume":
		sound.set_volume(float(value))
	store.save_profile()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if paused:
				_resume()
			else:
				_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11 or (event.keycode == KEY_F and event.alt_pressed):
			var fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == Screen.COMBAT and not paused and not _benchmark and not ("--smoke" in args) and not ("--autoplay" in args):
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

func _start_benchmark() -> void:
	_start_run("bone")
	_benchmark = true
	world.stress_mode = true
	world.rune_stress_mode = false
	world.sim.populate_stress()
	_peak_rune_flashes = 0
	if "--benchmark-runes" in args:
		world.enable_rune_stress()
	_benchmark_start = Time.get_ticks_usec()
	_last_frame_usec = _benchmark_start
	_benchmark_warmup = _benchmark_start + 5000000
	for argument: String in args:
		if argument.begins_with("--seconds="):
			_benchmark_seconds = maxf(5.0, argument.trim_prefix("--seconds=").to_float())
	world.benchmark_time_left = _benchmark_seconds + 5.0
	get_window().title = "秘术余烬 · 性能压力测试（非普通关卡）"
	if world.rune_stress_mode:
		get_window().title = "秘术余烬 · 符文反馈压力测试（非普通关卡）"
	ui.update_hud(world.hud_snapshot())
	ui.notify("性能压力测试 · 不结算关卡 · 采样结束后自动关闭")
	print("BENCHMARK_START 300 enemies / 600 projectiles / 200 drops, ", _benchmark_seconds, "s + 5s warmup")
	if world.rune_stress_mode:
		print("BENCHMARK_SCENARIO rune-feedback: positive weapon damage, all rune families")

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
	result["rune_visual_peak"] = _peak_rune_flashes
	result["primary_hits"] = world.sim.primary_hits
	result["secondary_hits"] = world.sim.secondary_hits
	var output: FileAccess = FileAccess.open("res://reports/performance.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	print("BENCHMARK_RESULT ", JSON.stringify(result))
	_benchmark = false
	_quit_game(0 if bool(result["passed"]) else 1)
