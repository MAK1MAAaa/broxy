extends SceneTree
## Real Main, settings and inventory input fixtures; no personal profile IO.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const CASES: PackedStringArray = ["settings", "capture", "conflict", "remapped", "gamepad", "backpack", "interactive"]
const STEP: float = 1.0 / 60.0
var _app: Node
var _case: String = "settings"
var _destination: String = "res://reports/controls/settings.png"
var _hold: bool = false
var _pulse_events: Array[Dictionary] = []
var _dash_events: Array[Dictionary] = []
var _last_live_uses: Vector2i = Vector2i(-1, -1)

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			_case = argument.trim_prefix("--case=")
		elif argument.begins_with("--capture="):
			_destination = argument.trim_prefix("--capture=")
		elif argument == "--hold":
			_hold = true
		else:
			_invalid()
			return
	if DisplayServer.get_name() == "headless" or _case not in CASES or not _destination.to_lower().ends_with(".png"):
		_invalid()
		return
	root.size = Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	_app.sound.set_volume(0.0)
	if _case == "interactive":
		_app.ui.controls_changed.connect(func(bindings: Dictionary) -> void:
			print("CONTROLS_BOUND ", JSON.stringify({"bindings": bindings, "persistent_profile": _app.store.persistent})))
		_app.world.hud_changed.connect(_log_live_skills)
	await _settle()
	if _case in ["settings", "capture", "conflict", "remapped", "interactive"]:
		_app.ui._show_settings(false)
		await _settle()
		if not _press_button("ControlsSettings"):
			return
		await _settle()
		if _case in ["capture", "conflict"]:
			if not _press_button("Bind_dash"):
				return
			await _settle()
			if _case == "conflict":
				await _key(KEY_Q)
		elif _case == "remapped":
			if not _press_button("Bind_dash"):
				return
			await _settle()
			await _key(KEY_E)
			if not _press_button("Bind_pulse"):
				return
			await _settle()
			await _key(KEY_R)
			_app.ui.handle_back()
			_app.ui.handle_back()
			await _start_combat()
			await _key(KEY_SPACE)
			await _key(KEY_Q)
			_app.world._physics_process(STEP)
			if _app.world.sim.dashes_used != 0 or _app.world.sim.pulses_used != 0:
				_fail("Old skill keys still work after a real settings remap")
				return
			await _key(KEY_E)
			await _key(KEY_R)
			_app.world._physics_process(STEP)
	elif _case == "gamepad":
		await _start_combat()
		await _joy(JOY_BUTTON_A)
		await _joy(JOY_BUTTON_X)
		_app.world._physics_process(STEP)
	elif _case == "backpack":
		_app._begin_run("bone", 20261028)
		_app.world.set_physics_process(false)
		_app.world.stop()
		_app.run.gold = 200
		_app.run.finish_wave()
		_app.run.generate_shop()
		_app.ui.show_shop()
		await _settle()
		var uid: int = int(_app.run.loadout[0]["uid"])
		_app.ui._bp_select(uid, _app.ui._shop_epoch)
		var pickup: Button = _app.ui._shop_focus_button("bag_move:%d" % uid)
		if pickup == null:
			_fail("The real backpack pickup action is missing")
			return
		pickup.grab_focus()
		await _joy(JOY_BUTTON_A)
		await _joy(JOY_BUTTON_X)
		await _joy(JOY_BUTTON_DPAD_RIGHT)
		await _joy(JOY_BUTTON_DPAD_DOWN)
		await _joy(JOY_BUTTON_A)
		await _settle()
		var item: Dictionary = _app.run.backpack_item(uid)
		if not bool(item["rotated"]) or int(item["x"]) != 1 or int(item["y"]) != 1:
			_fail("Gamepad placement did not reach the real inventory transaction")
			return
		_app.ui._bp_pick_up(uid)
		await _joy(JOY_BUTTON_DPAD_RIGHT)
	await _settle()
	root.title = "秘术余烬 · 操作设置验证 / %s（固定场景，不保存档案）" % _case
	await RenderingServer.frame_post_draw
	var absolute: String = ProjectSettings.globalize_path(_destination)
	var result: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result == OK:
		result = root.get_texture().get_image().save_png(absolute)
	var sim: CombatSim = _app.world.sim
	print("CONTROLS_PREVIEW ", JSON.stringify({"case": _case, "capture_result": result, "persistent_profile": _app.store.persistent,
		"bindings": _app.store.controls, "connected_gamepads": Input.get_connected_joypads(), "synthetic_gamepad_case": _case in ["gamepad", "backpack"],
		"dash": sim.dash_snapshot() if sim != null else {}, "pulse": sim.pulse_snapshot() if sim != null else {},
		"backpack": _app.run.backpack_snapshot(), "overlay": _app.ui._overlay_mode}))
	if result != OK or not _hold:
		_app._quit_game(0 if result == OK else 1)
		return
	if _case == "interactive":
		# The human-facing settings page stays live for real system key capture.
		_app.set_meta("controls_interactive_fixture", true)

func _log_live_skills(snapshot: Dictionary) -> void:
	var dash: Dictionary = snapshot.get("dash", {})
	var pulse: Dictionary = snapshot.get("pulse", {})
	var uses := Vector2i(int(dash.get("uses", 0)), int(pulse.get("uses", 0)))
	if uses == _last_live_uses:
		return
	_last_live_uses = uses
	print("CONTROLS_ACTIVITY ", JSON.stringify({"dash_uses": uses.x, "pulse_uses": uses.y,
		"bindings": _app.store.controls, "persistent_profile": _app.store.persistent}))

func _start_combat() -> void:
	_app._begin_run("bone", 20261028)
	_app.world.set_physics_process(false)
	_app.world.sim.sandbox = true
	_app.world.sim._cooldowns.fill(9999.0)
	for offset: Vector2 in [Vector2(100, 0), Vector2(-100, 0), Vector2(0, 80)]:
		var enemy: CombatSim.Enemy = _app.world.sim.spawn_enemy("chaser", _app.world.sim.player_position + offset)
		enemy.definition = enemy.definition.duplicate() as ContentDef
		enemy.definition.speed = 0.0
		enemy.action_timer = 9999.0
	_app.world.sim.dash_started.connect(func(point: Vector2, direction: Vector2) -> void:
		_dash_events.append({"origin": [point.x, point.y], "direction": [direction.x, direction.y]})
		print("CONTROLS_DASH ", JSON.stringify(_dash_events.back())))
	_app.world.sim.pulse_cast.connect(func(point: Vector2, affected: int) -> void:
		_pulse_events.append({"origin": [point.x, point.y], "affected": affected})
		print("CONTROLS_PULSE ", JSON.stringify(_pulse_events.back())))
	await _settle()

func _press_button(name: String) -> bool:
	var button := _app.ui.find_child(name, true, false) as Button
	if button == null:
		_fail("Missing actual UI button: " + name)
		return false
	button.pressed.emit()
	return true

func _key(code: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func _joy(button: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func _settle() -> void:
	for frame: int in 5:
		await process_frame

func _fail(message: String) -> void:
	push_error(message)
	_app._quit_game(1)

func _invalid() -> void:
	push_error("Use native --case=settings|capture|conflict|remapped|gamepad|backpack|interactive [--capture=path.png] [--hold]")
	quit(2)
