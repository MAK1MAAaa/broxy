extends SceneTree
## Parsed R/RB events, selected runtime art, modal cleanup and isolated profile migration.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0
var _app: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _start(hero_id: String = "alk") -> CombatSim:
	_app._title()
	_app.ui.set_selected_hero(hero_id)
	_app._start_run(HeroCatalog.definition(hero_id).starter_weapon)
	_app.world.set_physics_process(false)
	var sim: CombatSim = _app.world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	var focused: Control = root.gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	return sim

func _key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame

func _button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	ControlBindings.install(ControlBindings.defaults())
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.args = PackedStringArray(["--autoplay"])
	await _settle()
	for id: String in HeroCatalog.IDS:
		var sim: CombatSim = _start(id)
		var hero: HeroDef = HeroCatalog.definition(id)
		_check(sim.run.hero_id == id and sim.run.loadout[0]["id"] == hero.starter_weapon, "Selected character reaches the real Main/Run/World: " + id)
		_check(_app.world.textures["player"].resource_path == hero.idle_path and _app.world._player_atlas.resource_path == hero.atlas_path, "The actual renderer loads selected idle and atlas: " + id)
		for frame: int in 9:
			var region: Rect2 = WorldFlipperPlayerArt.frame_rect(frame, hero.frame_size)
			_check(Rect2(Vector2.ZERO, _app.world._player_atlas.get_size()).encloses(region) and region.size == Vector2.ONE * hero.frame_size, "Selected character uses its complete source frame: %s/%d" % [id, frame])
		await _key(KEY_R)
		_check(_app.world._hero_skill_pending and sim.hero_skill_snapshot()["uses"] == 0, "R queues without casting outside a fixed step: " + id)
		_app.world._physics_process(STEP)
		_check(sim.hero_skill_snapshot()["uses"] == 1 and sim.run.active_skills.is_empty(), "Real R casts with an empty rear inventory: " + id)
		await _key(KEY_R, true, true)
		await _key(KEY_R, false)
		_app.world._physics_process(STEP)
		_check(sim.hero_skill_snapshot()["uses"] == 1 and not _app.world._hero_skill_pending, "Held R and cooldown presses never buffer a second cast: " + id)
		_check(_app.world._active_skill_painter.snapshot()["active"] == 0, "R areas and physical bombs never enter the cosmetic instant-hit pool: " + id)
		if id == "hanabi":
			var delivery: Dictionary = sim.hero_effects_snapshot()
			_check(delivery["reserved_bombs"] == 5 and delivery["active_bombs"] == 0 and delivery["explosions"] == 0, "Actual Hanabi input reserves five bombs during its original-action windup")
			for frame: int in 52:
				_app.world._physics_process(STEP)
			_check(sim.hero_effects_snapshot()["reserved_bombs"] == 5, "Hanabi has no physical bomb before the 55th simulation frame")
			_app.world._physics_process(STEP)
			delivery = sim.hero_effects_snapshot()
			_check(delivery["reserved_bombs"] == 0 and int(delivery["active_bombs"]) + int(delivery["explosions"]) == 5, "At the 55th real frame all five reserved bombs become physical deliveries")
		else:
			var delivery: Dictionary = sim.skill_timeline.snapshot()
			_check(int(delivery["occupied"]) == HeroCatalog.definition(id).main_skill["timeline"].size(), "R input creates the hero's real timed areas: " + id)
			_check(not SkillAreaPainter.geometry_snapshot(delivery, true)["commands"].is_empty(), "The actual area renderer exposes a visible pending telegraph: " + id)
	var sim: CombatSim = _start("hanabi")
	await _button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await _button(JOY_BUTTON_RIGHT_SHOULDER, false)
	_app.world._physics_process(STEP)
	_check(sim.hero_skill_snapshot()["uses"] == 1, "Parsed gamepad RB casts the independent hero skill")
	sim = _start()
	await _key(KEY_R)
	_app._pause()
	_check(not _app.world._hero_skill_pending, "Pause clears a queued R")
	var remaining: float = float(sim.hero_skill_snapshot()["cooldown_remaining"])
	_app.world._physics_process(STEP)
	_check(sim.hero_skill_snapshot()["uses"] == 0 and sim.hero_skill_snapshot()["cooldown_remaining"] == remaining, "A paused world neither casts nor advances R")
	_app._resume()
	await _key(KEY_R, false)
	_app.world._physics_process(STEP)
	_check(sim.hero_skill_snapshot()["uses"] == 0, "Resume cannot replay the canceled request")
	_check(_app.world.request_hero_skill(), "Ready R can queue after resume")
	_app.world._physics_process(STEP)
	_check(sim.hero_skill_snapshot()["uses"] == 1 and sim.skill_timeline.snapshot()["occupied"] > 0, "A resumed request starts its actual skill timeline")
	_app._pause()
	var pending_delivery: String = JSON.stringify(sim.hero_effects_snapshot())
	remaining = float(sim.hero_skill_snapshot()["cooldown_remaining"])
	_app.world._physics_process(STEP)
	_check(JSON.stringify(sim.hero_effects_snapshot()) == pending_delivery and sim.hero_skill_snapshot()["cooldown_remaining"] == remaining, "Pause freezes both an already pending delivery and its real cooldown")
	_app._resume()
	_app.world._physics_process(STEP)
	_check(float(sim.hero_skill_snapshot()["cooldown_remaining"]) < remaining, "Resume advances the existing cast without replaying R")
	_app.world.stop()
	_check(not _app.world._hero_skill_pending and not _app.world.request_hero_skill(), "Stopped combat clears and rejects R")
	_test_profile()
	_app.queue_free()
	await _settle()
	ControlBindings.install(ControlBindings.defaults())
	print("HeroSkillFlow: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_profile() -> void:
	var path: String = "user://hero-profile-%d.cfg" % Time.get_ticks_usec()
	var profile := ConfigFile.new()
	profile.set_value("best", "wave", 5)
	var legacy: Dictionary = {"move_up": KEY_I, "move_down": KEY_K, "move_left": KEY_J, "move_right": KEY_L, "dash": KEY_R, "pulse": KEY_F, "skill_secondary": KEY_E}
	for key: String in legacy:
		profile.set_value("controls", key, legacy[key])
	_check(profile.save(path) == OK, "A dedicated old profile fixture is saved")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var store := GameStore.new(path)
	store.load_profile()
	_check(store.selected_hero == "alk" and store.best["wave"] == 5 and store.controls["hero_skill"] == KEY_C, "Legacy profiles gain Alk and a free R-action key without losing records")
	for key: String in legacy:
		_check(store.controls[key] == legacy[key], "Existing physical binding remains intact: " + key)
	_check(FileAccess.get_file_as_bytes(path) == before, "Loading a legacy profile does not silently rewrite it")
	store.selected_hero = "hanabi"
	_check(store.save_profile() == OK, "Character selection is explicitly persisted")
	var reloaded := GameStore.new(path)
	reloaded.load_profile()
	_check(reloaded.selected_hero == "hanabi" and reloaded.controls == store.controls and reloaded.best == store.best, "Character, controls and records survive a real profile reload")
	_check(profile.load(path) == OK, "The persisted profile remains readable")
	profile.set_value("progress", "hero", true)
	_check(profile.save(path) == OK, "A malformed identity is tested in the isolated fixture")
	reloaded.load_profile()
	_check(reloaded.selected_hero == "alk" and reloaded.controls == store.controls, "Malformed hero identity falls back without resetting controls")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "The temporary profile is removed")
