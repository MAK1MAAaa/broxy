extends SceneTree
## Native pressure fixture: real Main and World, synthetic load, no personal profile IO.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SEED: int = 20261028
const WARMUP_SECONDS: float = 5.0
const TARGET_ENEMIES: int = 300
const TARGET_PROJECTILES: int = 600
const TARGET_PICKUPS: int = 200
const MIN_FPS: float = 58.0
const MAX_P99_MS: float = 33.0
const BACKPACK_SKILL_FX_LIMIT: int = 8

var _seconds: float = 60.0
var _output: String = "res://reports/dash/performance.json"
var _app: Node
var _caption: Label
var _running: bool = false
var _sampling: bool = false
var _finished: bool = false
var _started_usec: int = 0
var _sample_started_usec: int = 0
var _last_frame_usec: int = 0
var _frame_samples: Array[float] = []
var _dash_start_count: int = 0
var _sample_dash_start_count: int = 0
var _afterimage_peak: int = 0
var _sample_afterimage_peak: int = 0
var _sample_evades_start: int = 0
var _evasion_feedback_peak: int = 0
var _sample_evasion_feedback_peak: int = 0
var _rune_peak: int = 0
var _grounding_peak: int = 0
var _sample_grounding_peak: int = 0
var _grounding_draw_peak: int = 0
var _physics_steps: int = 0
var _sample_physics_steps: int = 0
var _pre_step_minimum: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
var _last_pre_step_counts: Vector3i = Vector3i.ZERO
var _last_caption_text: String = ""
var _next_right: bool = true
var _evasion_probes: bool = false
var _evasion_probes_spawned: int = 0
var _pulse_cycles: bool = false
var _skill_relics: bool = false
var _input_prompts: bool = false
var _prompt_next_switch: float = 0.0
var _prompt_wants_gamepad: bool = true
var _prompt_switches: int = 0
var _sample_prompt_switches_start: int = 0
var _prompt_drift_events: int = 0
var _prompt_drift_changed_kind: bool = false
var _sample_pulses_start: int = 0
var _sample_affected_start: int = 0
var _pulse_feedback_peak: int = 0
var _sample_pulse_feedback_peak: int = 0
var _skill_feedback: bool = false
var _skill_feedback_peak: int = 0
var _sample_skill_feedback_peak: int = 0
var _positive_pulse_casts: int = 0
var _zero_pulse_casts: int = 0
var _sample_positive_pulse_start: int = 0
var _sample_zero_pulse_start: int = 0
var _skill_audio_playing_peak: int = 0
var _skill_audio_streams_observed: Dictionary = {}
var _backpack_skills: bool = false
var _backpack_skill_ids: Array[String] = []
var _hero_skills: bool = false
var _hero_id: String = "alk"
var _sample_hero_uses_start: int = 0
var _pinball_probes: bool = false
var _pinball_cycles: int = 0
var _pinball_bounces: int = 0
var _sample_pinball_cycles_start: int = 0
var _sample_pinball_bounces_start: int = 0
var _backpack_skill_uids: Dictionary = {}
var _backpack_skill_purchases: Array[Dictionary] = []
var _backpack_skill_requests: Dictionary = {}
var _backpack_skill_casts: Dictionary = {}
var _backpack_skill_positive_casts: Dictionary = {}
var _backpack_skill_affected: Dictionary = {}
var _backpack_skill_cast_log: Array[Dictionary] = []
var _backpack_skill_invalid_events: int = 0
var _sample_skill_uses_start: Dictionary = {}
var _sample_skill_requests_start: Dictionary = {}
var _sample_skill_casts_start: Dictionary = {}
var _sample_skill_positive_start: Dictionary = {}
var _sample_skill_affected_start: Dictionary = {}
var _sample_skill_damage_start: Dictionary = {}
var _backpack_pulse_control_casts: int = 0
var _backpack_pulse_control_targets: int = 0
var _sample_backpack_pulse_control_start: int = 0
var _sample_backpack_pulse_targets_start: int = 0
var _backpack_skill_fx_peak: int = 0
var _sample_backpack_skill_fx_peak: int = 0
var _backpack_skill_fx_capacity: int = 0
var _backpack_skill_fx_invalid: bool = false

func _initialize() -> void:
	_start.call_deferred()

func _parse_arguments() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			var value: String = argument.trim_prefix("--seconds=")
			if not value.is_valid_float():
				push_error("--seconds requires a finite number of at least 5")
				return false
			_seconds = value.to_float()
			if not is_finite(_seconds) or _seconds < 5.0:
				push_error("--seconds requires a finite number of at least 5")
				return false
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
			if _output.is_empty() or _output.get_extension().to_lower() != "json":
				push_error("--output requires a JSON report path")
				return false
		elif argument == "--evasion-probes":
			_evasion_probes = true
		elif argument == "--pulse-cycles":
			_pulse_cycles = true
		elif argument == "--skill-relics":
			_skill_relics = true
		elif argument == "--input-prompts":
			_input_prompts = true
		elif argument == "--skill-feedback":
			_skill_feedback = true
		elif argument == "--backpack-skills":
			_backpack_skills = true
		elif argument == "--hero-skills":
			_hero_skills = true
		elif argument.begins_with("--hero="):
			_hero_id = argument.trim_prefix("--hero=")
			if not HeroCatalog.IDS.has(_hero_id):
				push_error("--hero requires an implemented character")
				return false
		elif argument == "--pinball-probes":
			_pinball_probes = true
		else:
			push_error("Supported arguments: --seconds=<at least 5> --output=<report.json> [--evasion-probes] [--pulse-cycles] [--skill-relics] [--input-prompts] [--skill-feedback] [--backpack-skills] [--hero-skills] [--hero=<implemented id>] [--pinball-probes]")
			return false
	if _backpack_skills and (_pulse_cycles or _skill_feedback or _skill_relics or _input_prompts):
		push_error("--backpack-skills cannot be combined with --pulse-cycles, --skill-feedback, --skill-relics, or --input-prompts")
		return false
	if _backpack_skills:
		_backpack_skill_ids = _legal_backpack_skill_pair()
		if _backpack_skill_ids.size() != ActiveSkillRules.LIMIT:
			push_error("The selected hero does not have two legal backpack companions")
			return false
	return true

func _legal_backpack_skill_pair() -> Array[String]:
	var candidates: Array[String] = ["starfall", "arc_slash", "pulse"]
	var starfall_hero: HeroDef = HeroCatalog.rear_for_skill("starfall")
	if starfall_hero != null and starfall_hero.id == _hero_id:
		candidates.assign(["pulse", "arc_slash", "starfall"])
	var result: Array[String] = []
	for id: String in candidates:
		var hero: HeroDef = HeroCatalog.rear_for_skill(id)
		if hero != null and hero.id != _hero_id and GameCatalog.skill(id) != null:
			result.append(id)
			if result.size() == ActiveSkillRules.LIMIT:
				break
	return result

func _start() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Dash pressure requires a visible native window; headless results are rejected")
		quit(2)
		return
	if not _parse_arguments():
		quit(2)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	_app = MAIN.instantiate()
	_app.store.persistent = false
	root.add_child(_app)
	_app.set_process(false)
	_app.set_process_unhandled_key_input(false)
	# This flag only suppresses focus-loss handling; it never enables the bot here.
	_app.args = PackedStringArray(["--autoplay"])
	# Suppress earned-upgrade modals without invoking Main's benchmark clock.
	_app._benchmark = true
	_app.ui.set_selected_arena("mire")
	_app.ui.set_selected_hero(_hero_id)
	_app._begin_run("bone", SEED)
	if (_pulse_cycles or _skill_feedback or _skill_relics) and not _equip_pulse_skill():
		_abort("Could not purchase the pressure fixture's pulse skill box")
		return
	if _backpack_skills:
		for path: String in _backpack_skill_source_paths():
			if not FileAccess.file_exists(path):
				_abort("Missing backpack-skill fingerprint input: " + path)
				return
		if not _equip_backpack_skills():
			_abort("Could not purchase the pressure fixture's two backpack skills")
			return
		_app.world.sim.active_skill_cast.connect(_observe_backpack_skill_cast)
	if _input_prompts:
		_app.ui.get_node("InputDeviceTracker").device_changed.connect(func(_kind: String, _device: int) -> void: _prompt_switches += 1)
	if _skill_relics and not _equip_skill_relics():
		_abort("Could not purchase and merge the pressure fixture's skill relics")
		return
	_app.run.core_id = "bone_chorus"
	_app.world.autopilot = false
	_app.world.stress_mode = false
	_app.world.sim.populate_stress()
	_app.world.enable_rune_stress(true)
	_app.world.apply_visual_settings(_app.store.settings)
	if _skill_feedback:
		for path: String in _audio_input_paths():
			if not FileAccess.file_exists(path):
				_abort("Missing skill-audio fingerprint input: " + path)
				return
		_app.world.sim.pulse_cast.connect(_observe_pulse_cast)
	root.title = "秘术余烬 · 冲刺压力夹具（非自然对局，不保存设置与成绩）"
	_make_caption()
	_dash_start_count = _app.world.sim.dashes_used
	_started_usec = Time.get_ticks_usec()
	_last_frame_usec = _started_usec
	# SceneTree emits this signal before every Node._physics_process callback.
	# World retains its own normal fixed-step callback and consumes the real queue.
	physics_frame.connect(_before_world_physics)
	if _pinball_probes:
		_app.world.sim.pinball_bounced.connect(_observe_pinball_bounce)
	_running = true
	_update_caption(_started_usec)
	var start_report: Dictionary = {
		"scenario": "backpack-skill-content-pressure" if _backpack_skills else "dash-content-pressure", "natural_run": false,
		"warmup_seconds": WARMUP_SECONDS, "duration_seconds": _seconds,
		"seed": SEED, "arena_id": "mire", "core_id": "bone_chorus",
		"load_targets": _counts(Vector3i(TARGET_ENEMIES, TARGET_PROJECTILES, TARGET_PICKUPS)),
		"settings": _app.store.settings.duplicate(true),
		"persistent_profile": _app.store.persistent, "output": _output,
		"evasion_probes": _evasion_probes,
		"pulse_cycles": _pulse_cycles,
		"active_skills": _app.run.active_skills.duplicate(true),
		"skill_relics": _skill_relics,
		"input_prompts": _input_prompts,
		"backpack_skills": _backpack_skills,
	}
	if _backpack_skills:
		start_report["backpack_skill_ids"] = _backpack_skill_ids.duplicate()
		start_report["backpack_skill_purchases"] = _backpack_skill_purchases.duplicate(true)
		start_report["active_skill_fx_capacity"] = _app.world._active_skill_painter.snapshot()["capacity"]
		start_report["source_files"] = _source_fingerprint()["files"]
	if _skill_feedback:
		start_report["skill_feedback"] = true
		start_report["source_files"] = _source_fingerprint()["files"]
		start_report["audio_source_files"] = _audio_source_fingerprint()["files"]
	print("DASH_BENCHMARK_START ", JSON.stringify(start_report))

func _equip_pulse_skill() -> bool:
	var definition: ContentDef = GameCatalog.skill("pulse")
	_app.run.gold += definition.price
	_app.run.offers.assign([{"kind": "skill", "id": definition.id, "rank": 1, "price": definition.price, "sold": false}])
	if not _app.run.buy_offer(0):
		return false
	_app.run.offers.clear()
	return _app.run.active_skills.size() == 1 and _app.run.active_skills[0]["id"] == "pulse"

func _equip_backpack_skills() -> bool:
	for id: String in _backpack_skill_ids:
		var definition: ContentDef = GameCatalog.skill(id)
		var uid: int = int(_app.run.backpack_snapshot()["next_uid"])
		_app.run.gold += definition.price
		_app.run.offers.assign([{"kind": "skill", "id": id, "rank": 1, "price": definition.price, "sold": false}])
		if not _app.run.buy_offer(0):
			return false
		var item: Dictionary = _app.run.backpack_item(uid)
		if item.is_empty() or item["id"] != id or int(item["rank"]) != 1 or int(item["paid"]) != definition.price:
			return false
		_backpack_skill_uids[id] = uid
		_backpack_skill_purchases.append(item)
	_app.run.offers.clear()
	if _app.run.active_skills.size() != _backpack_skill_ids.size():
		return false
	for slot: int in _backpack_skill_ids.size():
		if str(_app.run.active_skills[slot]["id"]) != _backpack_skill_ids[slot]:
			return false
	return true

func _equip_skill_relics() -> bool:
	# Fixture-only money and stock; every item, merge and occupied cell is real.
	_app.run.gold = 1000
	for id: String in ["fold_clasp", "echo_stone"]:
		var uids: Array[int] = []
		for copy: int in 4:
			var definition: ContentDef = GameCatalog.relic(id)
			_app.run.offers.assign([{"kind": "relic", "id": id, "price": definition.price, "sold": false}])
			if not _app.run.buy_offer(0):
				return false
			var items: Array = _app.run.backpack_snapshot()["items"]
			uids.append(int(items.back()["uid"]))
		if not _app.run.merge_items(uids[1], uids[0]) or not _app.run.merge_items(uids[3], uids[2]) or not _app.run.merge_items(uids[2], uids[0]):
			return false
	_app.run.offers.clear()
	return is_equal_approx(_app.run.stat("dash_cooldown"), 1.2) and is_equal_approx(_app.run.stat("pulse_radius"), 216.0) and is_equal_approx(_app.run.stat("pulse_cooldown"), 11.2)

func _make_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	_app.add_child(layer)
	_caption = Label.new()
	_caption.theme = _app.ui._root.theme
	_caption.position = Vector2(26, 103)
	_caption.add_theme_font_size_override("font_size", 14)
	_caption.add_theme_color_override("font_color", Color("dcd4c0"))
	_caption.add_theme_color_override("font_shadow_color", Color("090b12"))
	_caption.add_theme_constant_override("shadow_outline_size", 3)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.focus_mode = Control.FOCUS_NONE
	layer.add_child(_caption)

func _update_caption(now: int) -> void:
	var elapsed: float = float(now - (_sample_started_usec if _sampling else _started_usec)) / 1000000.0
	var phase: String = "采样 %d / %.0f秒" % [int(elapsed), _seconds] if _sampling else "预热 %d / 5秒" % int(elapsed)
	var text: String = "冲刺压力夹具 · 非自然对局 · 不保存档案\n%s · 300敌人 / 600弹体 / 200掉落 · 松开移动输入并保持摇杆回中" % phase
	if text != _last_caption_text:
		_caption.text = text
		_last_caption_text = text

func _movement_keys_held() -> bool:
	return ControlBindings.movement().length_squared() > 0.0

func _before_world_physics() -> void:
	if not _running or _finished:
		return
	var world: CombatWorld = _app.world
	if paused or not world.active or world.sim == null or world.sim.complete:
		_abort("The pressure fixture unexpectedly paused or ended")
		return
	if _movement_keys_held():
		_abort("Movement keys must stay released and sticks centered in this facing-only pressure fixture")
		return
	if _input_prompts:
		_exercise_input_prompts()
	if _pinball_probes and bool(world.sim.dash_snapshot()["ready"]):
		var arena: Dictionary = ArenaCatalog.definition(world.sim.run.arena_id)
		for obstacle: Dictionary in arena["obstacles"]:
			if str(obstacle["id"]) == "east_bumper":
				var center := Vector2(float(obstacle["center"][0]), float(obstacle["center"][1]))
				world.sim.player_position = world.sim.obstacles.free_point(center - Vector2(float(obstacle["radius"]) + 48.0, 0), 16.0, 16.0)
				_next_right = true
				break
	world.sim.run.health = world.sim.run.stat("max_health")
	world._maintain_stress()
	if _pinball_probes:
		while world.sim.enemy_count < TARGET_ENEMIES:
			var enemy: CombatSim.Enemy = world.sim.spawn_enemy("chaser", Vector2(world.sim.rng.randf_range(100, 1180), world.sim.rng.randf_range(175, 553)))
			if enemy == null:
				_abort("The pressure fixture cannot replenish its required enemy count")
				return
			enemy.health = 1000000000.0
			enemy.max_health = enemy.health
	var counts := Vector3i(world.sim.enemy_count, world.sim.shot_count, world.sim.soul_count)
	_last_pre_step_counts = counts
	_physics_steps += 1
	if _sampling:
		_sample_physics_steps += 1
		_pre_step_minimum = Vector3i(mini(_pre_step_minimum.x, counts.x), mini(_pre_step_minimum.y, counts.y), mini(_pre_step_minimum.z, counts.z))
	_observe_feedback()
	if _backpack_skills and not _request_ready_backpack_skills(world):
		return
	if _hero_skills and bool(world.sim.hero_skill_snapshot()["ready"]):
		if not world.request_hero_skill():
			_abort("A ready World rejected the pressure fixture's main-character skill")
			return
	if _pulse_cycles and bool(world.sim.pulse_snapshot()["ready"]):
		if not world.request_pulse():
			_abort("A ready real World rejected the explicit pressure pulse request")
			return
	if bool(world.sim.dash_snapshot()["ready"]):
		world.sim.player_direction = Vector2.RIGHT if _next_right else Vector2.LEFT
		if not world.request_dash():
			_abort("A ready real World rejected the explicit pressure dash request")
			return
		if _evasion_probes:
			# This opt-in fixture isolates the new feedback from old received-hit immunity.
			world.sim.invulnerability = 0.0
			var before: int = world.sim.shot_count
			var point: Vector2 = world.sim.player_position + world.sim.player_direction * (DashRules.SPEED / float(Engine.physics_ticks_per_second))
			world.sim._hostile_shot(point, Vector2.ZERO, 8.0, "caster")
			if world.sim.shot_count != before + 1:
				_abort("The evasion fixture could not allocate its real hostile projectile")
				return
			_evasion_probes_spawned += 1
		_next_right = not _next_right

func _request_ready_backpack_skills(world: CombatWorld) -> bool:
	for slot: int in _backpack_skill_ids.size():
		var id: String = _backpack_skill_ids[slot]
		var skill: Dictionary = world.sim.active_skill_snapshot(slot)
		if not bool(skill.get("available", false)) or str(skill.get("id", "")) != id or int(skill.get("uid", -1)) != int(_backpack_skill_uids[id]):
			_abort("The pressure fixture lost its purchased backpack skill: " + id)
			return false
		if bool(skill.get("ready", false)):
			if not world.request_skill(slot):
				_abort("A ready real World rejected the backpack skill request: " + id)
				return false
			_backpack_skill_requests[id] = int(_backpack_skill_requests.get(id, 0)) + 1
	return true

func _observe_pinball_bounce(_point: Vector2, _normal: Vector2, boosted: bool, _combo: int) -> void:
	_pinball_bounces += 1
	var ball: Dictionary = _app.world.sim.pinball_snapshot()
	if boosted and int(ball["bounces"]) == 1 and float(ball["age"]) == 0.0:
		_pinball_cycles += 1

func _exercise_input_prompts() -> void:
	var before: Dictionary = _app.ui.input_device_snapshot()
	var drift := InputEventJoypadMotion.new()
	drift.device = 0
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.10 if _physics_steps % 2 == 0 else 0.18
	Input.parse_input_event(drift)
	_prompt_drift_events += 1
	_prompt_drift_changed_kind = _prompt_drift_changed_kind or _app.ui.input_device_snapshot() != before
	if _app.world.sim.elapsed < _prompt_next_switch:
		return
	_prompt_next_switch = _app.world.sim.elapsed + 0.5
	for pressed: bool in [true, false]:
		if _prompt_wants_gamepad:
			var pad := InputEventJoypadButton.new()
			pad.device = 0
			pad.button_index = JOY_BUTTON_Y
			pad.pressed = pressed
			Input.parse_input_event(pad)
		else:
			var key := InputEventKey.new()
			key.keycode = KEY_F6
			key.physical_keycode = KEY_F6
			key.pressed = pressed
			Input.parse_input_event(key)
	_prompt_wants_gamepad = not _prompt_wants_gamepad

func _observe_feedback() -> void:
	var grounding: Dictionary = _app.world._grounding_painter.get_stats()
	_grounding_peak = maxi(_grounding_peak, int(grounding["active_count"]))
	_grounding_draw_peak = maxi(_grounding_draw_peak, int(grounding["draw_commands"]))
	if _sampling:
		_sample_grounding_peak = maxi(_sample_grounding_peak, int(grounding["active_count"]))
	var count: int = _app.world.dash_afterimage_count()
	var evasion_active: int = 1 if bool(_app.world.dash_evasion_feedback_snapshot()["active"]) else 0
	var pulse_active: int = 1 if bool(_app.world.pulse_feedback_snapshot()["active"]) else 0
	_pulse_feedback_peak = maxi(_pulse_feedback_peak, pulse_active)
	_evasion_feedback_peak = maxi(_evasion_feedback_peak, evasion_active)
	_afterimage_peak = maxi(_afterimage_peak, count)
	_rune_peak = maxi(_rune_peak, _app.world._rune_flashes.size())
	if _backpack_skills:
		_observe_backpack_skill_fx()
	if _skill_feedback:
		var active: int = 1 if bool(_app.world.skill_feedback_snapshot().get("active", false)) else 0
		_skill_feedback_peak = maxi(_skill_feedback_peak, active)
		if _sampling:
			_sample_skill_feedback_peak = maxi(_sample_skill_feedback_peak, active)
		var skill_voices: int = 0
		for voice: AudioStreamPlayer in _app.sound.voices:
			if voice.playing and voice.stream != null:
				var sound_name: String = voice.stream.resource_path.get_file().get_basename()
				if sound_name in ["dash", "pulse", "pulse_hit", "evade"]:
					skill_voices += 1
					_skill_audio_streams_observed[sound_name] = true
		_skill_audio_playing_peak = maxi(_skill_audio_playing_peak, skill_voices)
	if _sampling:
		_sample_afterimage_peak = maxi(_sample_afterimage_peak, count)
		_sample_evasion_feedback_peak = maxi(_sample_evasion_feedback_peak, evasion_active)
		_sample_pulse_feedback_peak = maxi(_sample_pulse_feedback_peak, pulse_active)

func _observe_pulse_cast(_origin: Vector2, affected: int) -> void:
	if affected > 0:
		_positive_pulse_casts += 1
	else:
		_zero_pulse_casts += 1

func _observe_backpack_skill_fx() -> void:
	var effects: Dictionary = _app.world._active_skill_painter.snapshot()
	var active: int = int(effects["active"])
	_backpack_skill_fx_capacity = int(effects["capacity"])
	_backpack_skill_fx_peak = maxi(_backpack_skill_fx_peak, active)
	_backpack_skill_fx_invalid = _backpack_skill_fx_invalid or active < 0 or active > BACKPACK_SKILL_FX_LIMIT or _backpack_skill_fx_capacity != BACKPACK_SKILL_FX_LIMIT
	if _sampling:
		_sample_backpack_skill_fx_peak = maxi(_sample_backpack_skill_fx_peak, active)

func _observe_backpack_skill_cast(id: String, uid: int, origin: Vector2, direction: Vector2, affected: int, rank: int) -> void:
	if not _backpack_skills:
		return
	if not _backpack_skill_ids.has(id) or uid != int(_backpack_skill_uids.get(id, -1)) or rank != 1 or affected < 0 or not origin.is_finite() or not direction.is_finite():
		_backpack_skill_invalid_events += 1
		return
	_backpack_skill_casts[id] = int(_backpack_skill_casts.get(id, 0)) + 1
	_backpack_skill_affected[id] = int(_backpack_skill_affected.get(id, 0)) + affected
	if affected > 0:
		_backpack_skill_positive_casts[id] = int(_backpack_skill_positive_casts.get(id, 0)) + 1
	var controlled_uids: Array[int] = []
	if id == "pulse" and affected > 0:
		for enemy: CombatSim.Enemy in _app.world.sim.enemies:
			if enemy.active and enemy.health > 0.0 and not enemy.hunter and enemy.definition.id != "boss" and enemy.pulse_hinder_timer > 0.0:
				controlled_uids.append(enemy.uid)
		if not controlled_uids.is_empty():
			_backpack_pulse_control_casts += 1
			_backpack_pulse_control_targets += controlled_uids.size()
	_backpack_skill_cast_log.append({"id": id, "uid": uid, "rank": rank, "affected": affected,
		"origin": [origin.x, origin.y], "direction": [direction.x, direction.y],
		"elapsed": _app.world.sim.elapsed, "sample": _sampling, "controlled_target_uids": controlled_uids})
	_observe_backpack_skill_fx()

func _begin_backpack_skill_sample() -> void:
	_sample_backpack_pulse_control_start = _backpack_pulse_control_casts
	_sample_backpack_pulse_targets_start = _backpack_pulse_control_targets
	for slot: int in _backpack_skill_ids.size():
		var id: String = _backpack_skill_ids[slot]
		_sample_skill_uses_start[id] = int(_app.world.sim.active_skill_snapshot(slot)["uses"])
		_sample_skill_requests_start[id] = int(_backpack_skill_requests.get(id, 0))
		_sample_skill_casts_start[id] = int(_backpack_skill_casts.get(id, 0))
		_sample_skill_positive_start[id] = int(_backpack_skill_positive_casts.get(id, 0))
		_sample_skill_affected_start[id] = int(_backpack_skill_affected.get(id, 0))
		_sample_skill_damage_start[id] = float(_app.world.sim.damage_by_skill.get(id, 0.0))

func _process(_delta: float) -> bool:
	if not _running or _finished:
		return false
	var now: int = Time.get_ticks_usec()
	_observe_feedback()
	if not _sampling and float(now - _started_usec) / 1000000.0 >= WARMUP_SECONDS:
		_sampling = true
		_sample_started_usec = now
		_last_frame_usec = now
		_sample_dash_start_count = _app.world.sim.dashes_used
		_sample_evades_start = _app.world.sim.dash_evades
		_sample_pulses_start = _app.world.sim.pulses_used
		_sample_affected_start = _app.world.sim.pulse_affected
		_sample_prompt_switches_start = _prompt_switches
		_sample_positive_pulse_start = _positive_pulse_casts
		_sample_zero_pulse_start = _zero_pulse_casts
		if _backpack_skills:
			_begin_backpack_skill_sample()
		_sample_hero_uses_start = int(_app.world.sim.hero_skill_snapshot()["uses"])
		_sample_pinball_cycles_start = _pinball_cycles
		_sample_pinball_bounces_start = _pinball_bounces
	elif _sampling:
		_frame_samples.append(float(now - _last_frame_usec) / 1000.0)
		_last_frame_usec = now
	_update_caption(now)
	if _sampling and float(now - _sample_started_usec) / 1000000.0 >= _seconds:
		_finish_report(now)
	return false

func _counts(value: Vector3i) -> Dictionary:
	return {"enemies": value.x, "projectiles": value.y, "pickups": value.z}

func _collect_sources(directory: String, paths: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension() in ["gd", "tscn", "tres", "json"]:
			paths.append(directory.path_join(file))
	for child: String in DirAccess.get_directories_at(directory):
		_collect_sources(directory.path_join(child), paths)

func _source_fingerprint() -> Dictionary:
	var paths: Array[String] = ["res://project.godot", "res://tools/benchmark_dash.gd"]
	for id: String in ArenaCatalog.IDS:
		paths.append(ArenaCatalog.texture_path(id))
	paths.append("res://assets/worldflipper/manifest.json")
	for id: String in ["monument", "planter", "bumper"]:
		paths.append("res://assets/worldflipper/props/%s.png" % id)
	for id: String in ["player", "chaser", "rusher", "tank", "caster", "boss"]:
		paths.append(AdventureArt.path("res://assets/sprites/%s.svg" % id))
	paths.append(WorldFlipperPlayerArt.ATLAS_PATH)
	for directory: String in ["res://scripts", "res://data", "res://scenes"]:
		_collect_sources(directory, paths)
	if _skill_feedback:
		paths.append_array(_audio_input_paths())
	if _backpack_skills:
		for path: String in _backpack_skill_source_paths():
			if not paths.has(path):
				paths.append(path)
	paths.sort()
	var manifest := PackedStringArray()
	var files: Dictionary = {}
	for path: String in paths:
		var digest: String = FileAccess.get_sha256(path)
		files[path] = digest
		manifest.append(path + ":" + digest)
	return {"hash": "\n".join(manifest).sha256_text(), "algorithm": "sha256-path-and-content-manifest", "files": files}

func _backpack_skill_source_paths() -> Array[String]:
	return ["res://scripts/data/active_skill_rules.gd", "res://scripts/data/hero_catalog.gd", "res://scripts/data/pulse_rules.gd",
		"res://scripts/combat/combat_sim.gd", "res://scripts/combat/combat_world.gd", "res://scripts/combat/active_skill_painter.gd",
		"res://data/skills/pulse.tres", "res://data/skills/starfall.tres", "res://data/skills/arc_slash.tres",
		"res://assets/starfall/icons/skill_pulse.svg", "res://assets/starfall/icons/skill_starfall.svg",
		"res://assets/starfall/icons/skill_arc_slash.svg", "res://assets/starfall/manifest.json",
		"res://assets/worldflipper/icons/skill_pulse.png", "res://assets/audio/pulse.wav", "res://assets/audio/pulse_hit.wav"]

func _audio_input_paths() -> Array[String]:
	var paths: Array[String] = ["res://assets/manifest.json", "res://tools/audio_skills.py", "res://tools/generate_assets.py"]
	for name: String in SoundBank.NAMES:
		paths.append("res://assets/audio/%s.wav" % name)
	paths.append("res://assets/audio/ambience.wav")
	paths.sort()
	return paths

func _audio_source_fingerprint() -> Dictionary:
	var files: Dictionary = {}
	var manifest := PackedStringArray()
	for path: String in _audio_input_paths():
		var digest: String = FileAccess.get_sha256(path)
		files[path] = digest
		manifest.append(path + ":" + digest)
	return {"hash": "\n".join(manifest).sha256_text(), "files": files}

func _stop_updates() -> void:
	_running = false
	_finished = true
	if physics_frame.is_connected(_before_world_physics):
		physics_frame.disconnect(_before_world_physics)
	_app.world.set_physics_process(false)
	_app.world.clear_pending_actions()
	if _input_prompts:
		var neutral := InputEventJoypadMotion.new()
		neutral.device = 0
		neutral.axis = JOY_AXIS_LEFT_X
		Input.parse_input_event(neutral)

func _backpack_skill_results(sim: CombatSim) -> Dictionary:
	var skills: Dictionary = {}
	var uses: Dictionary = {}
	var sampled_uses: Dictionary = {}
	var minimum_uses: Dictionary = {}
	var pulse_required: bool = _backpack_skill_ids.has("pulse")
	var sample_control_casts: int = _backpack_pulse_control_casts - _sample_backpack_pulse_control_start
	var sample_control_targets: int = _backpack_pulse_control_targets - _sample_backpack_pulse_targets_start
	var pulse_valid: bool = not pulse_required or (sample_control_casts > 0 and sample_control_targets > 0)
	var valid: bool = sim.run.active_skills.size() == _backpack_skill_ids.size() and _backpack_skill_invalid_events == 0 and pulse_valid
	for slot: int in _backpack_skill_ids.size():
		var id: String = _backpack_skill_ids[slot]
		var current: Dictionary = sim.active_skill_snapshot(slot)
		var total_uses: int = int(current["uses"])
		var sample_uses: int = total_uses - int(_sample_skill_uses_start.get(id, 0))
		var requests: int = int(_backpack_skill_requests.get(id, 0))
		var sample_requests: int = requests - int(_sample_skill_requests_start.get(id, 0))
		var casts: int = int(_backpack_skill_casts.get(id, 0))
		var sample_casts: int = casts - int(_sample_skill_casts_start.get(id, 0))
		var positives: int = int(_backpack_skill_positive_casts.get(id, 0))
		var sample_positives: int = positives - int(_sample_skill_positive_start.get(id, 0))
		var affected: int = int(_backpack_skill_affected.get(id, 0))
		var damage: float = float(sim.damage_by_skill.get(id, 0.0))
		var sample_damage: float = damage - float(_sample_skill_damage_start.get(id, 0.0))
		var parameters: Dictionary = ActiveSkillRules.parameters(id, 1, {})
		var required: int = maxi(1, floori(_seconds / float(parameters["cooldown"])) - 1)
		var ownership_valid: bool = bool(current["available"]) and str(current["id"]) == id and int(current["uid"]) == int(_backpack_skill_uids[id])
		var effect_valid: bool = (damage == 0.0 and sample_damage == 0.0 and sample_control_casts > 0 and sample_control_targets > 0) if id == "pulse" else sample_damage > 0.0
		var casts_valid: bool = ownership_valid and total_uses == requests and total_uses == casts and sample_uses >= required and sample_requests == sample_uses and sample_casts == sample_uses and sample_positives > 0 and effect_valid
		valid = valid and casts_valid
		uses[id] = total_uses
		sampled_uses[id] = sample_uses
		minimum_uses[id] = required
		skills[id] = {"slot": slot, "uid": current["uid"], "rank": current["rank"], "uses": total_uses,
			"sample_uses": sample_uses, "requests": requests, "sample_requests": sample_requests,
			"cast_events": casts, "sample_cast_events": sample_casts, "positive_casts": positives,
			"sample_positive_casts": sample_positives, "affected": affected,
			"sample_affected": affected - int(_sample_skill_affected_start.get(id, 0)),
			"damage": damage, "sample_damage": sample_damage, "minimum_sample_uses": required,
			"effect_kind": "control" if id == "pulse" else "damage", "effect_valid": effect_valid,
			"sample_control_casts": sample_control_casts if id == "pulse" else 0,
			"sample_control_observed_targets": sample_control_targets if id == "pulse" else 0,
			"cooldown_duration": current["cooldown_duration"], "cooldown_remaining": current["cooldown_remaining"],
			"ownership_and_real_casts_valid": casts_valid}
	return {"valid": valid, "skills": skills, "uses": uses, "sample_uses": sampled_uses, "minimum_uses": minimum_uses,
		"pulse_control": {"required": pulse_required, "positive_control_casts": _backpack_pulse_control_casts,
			"observed_controlled_targets": _backpack_pulse_control_targets, "sample_positive_control_casts": sample_control_casts,
			"sample_observed_controlled_targets": sample_control_targets, "valid": pulse_valid}}

func _finish_report(now: int) -> void:
	_stop_updates()
	var sorted: Array[float] = _frame_samples.duplicate()
	sorted.sort()
	var total_ms: float = 0.0
	for value: float in sorted:
		total_ms += value
	var p99: float = sorted[clampi(ceili(float(sorted.size()) * 0.99) - 1, 0, sorted.size() - 1)] if not sorted.is_empty() else INF
	var fps: float = 1000.0 * float(sorted.size()) / total_ms if total_ms > 0.0 else 0.0
	var sim: CombatSim = _app.world.sim
	var sampled_dashes: int = sim.dashes_used - _sample_dash_start_count
	var minimum_dashes: int = maxi(2, floori(_seconds / sim.run.stat("dash_cooldown")) - 1)
	var load_valid: bool = _sample_physics_steps > 0 and _pre_step_minimum.x >= TARGET_ENEMIES and _pre_step_minimum.y >= TARGET_PROJECTILES and _pre_step_minimum.z >= TARGET_PICKUPS
	var feedback_valid: bool = sampled_dashes >= minimum_dashes and _sample_afterimage_peak > 0 and _afterimage_peak <= CombatWorld.DASH_AFTERIMAGE_LIMIT
	var evasion_valid: bool = not _evasion_probes or (sim.dash_evades - _sample_evades_start >= minimum_dashes and _sample_evasion_feedback_peak == 1)
	var minimum_pulses: int = maxi(1, floori(_seconds / sim.run.stat("pulse_cooldown")) - 1)
	var pulse_valid: bool = not _pulse_cycles or (sim.pulses_used - _sample_pulses_start >= minimum_pulses and sim.pulse_affected > _sample_affected_start and _sample_pulse_feedback_peak == 1)
	var defaults_valid: bool = _app.store.settings == {"volume": 0.65, "shake": true, "flash": true} and _app.store.controls == ControlBindings.defaults() and not _app.store.persistent
	var prompt_valid: bool = not _input_prompts or (_prompt_switches - _sample_prompt_switches_start >= floori(_seconds * 1.8) and _prompt_drift_events > 0 and not _prompt_drift_changed_kind)
	var source: Dictionary = _source_fingerprint()
	var report: Dictionary = {
		"scenario": "backpack-skill-content-pressure" if _backpack_skills else "dash-content-pressure", "natural_run": false,
		"duration_seconds": _seconds, "actual_duration_seconds": float(now - _sample_started_usec) / 1000000.0,
		"warmup_seconds": WARMUP_SECONDS, "actual_warmup_seconds": float(_sample_started_usec - _started_usec) / 1000000.0,
		"samples": sorted.size(), "average_fps": fps, "p99_frame_ms": p99,
		"dashes_used": sim.dashes_used - _dash_start_count, "sample_dashes_used": sampled_dashes,
		"warmup_dashes_used": _sample_dash_start_count - _dash_start_count,
		"afterimage_peak": _afterimage_peak, "sample_afterimage_peak": _sample_afterimage_peak,
		"afterimage_capacity": CombatWorld.DASH_AFTERIMAGE_LIMIT, "rune_visual_peak": _rune_peak,
		"evades": sim.dash_evades, "sample_evades": sim.dash_evades - _sample_evades_start,
		"evasion_feedback_peak": _evasion_feedback_peak, "sample_evasion_feedback_peak": _sample_evasion_feedback_peak,
		"evasion_probes": _evasion_probes, "evasion_probes_spawned": _evasion_probes_spawned,
		"pulse_cycles": _pulse_cycles, "pulses_used": sim.pulses_used, "sample_pulses_used": sim.pulses_used - _sample_pulses_start,
		"skill_relics": _skill_relics,
		"backpack_skills": _backpack_skills,
		"skill_stats": {"dash_cooldown": sim.run.stat("dash_cooldown"), "pulse_radius": sim.run.stat("pulse_radius"), "pulse_cooldown": sim.run.stat("pulse_cooldown"), "move_speed": sim.run.stat("move_speed")},
		"pulse_affected": sim.pulse_affected, "sample_pulse_affected": sim.pulse_affected - _sample_affected_start,
		"pulse_feedback_peak": _pulse_feedback_peak, "sample_pulse_feedback_peak": _sample_pulse_feedback_peak,
		"pre_step_counts_exclude_one_optional_probe_shot": _evasion_probes,
		"physics_steps": _physics_steps, "sample_physics_steps": _sample_physics_steps,
		"load_targets": _counts(Vector3i(TARGET_ENEMIES, TARGET_PROJECTILES, TARGET_PICKUPS)),
		"enemies": _last_pre_step_counts.x, "projectiles": _last_pre_step_counts.y, "pickups": _last_pre_step_counts.z,
		"counts_measurement_phase": "physics_frame_before_combat_world",
		"minimum_pre_step_counts": _counts(_pre_step_minimum),
		"after_step_counts_at_end": _counts(Vector3i(sim.enemy_count, sim.shot_count, sim.soul_count)),
		"settings": _app.store.settings.duplicate(true), "persistent_profile": _app.store.persistent,
		"controls": _app.store.controls.duplicate(true), "connected_gamepads": Array(Input.get_connected_joypads()),
		"input_prompts": _input_prompts, "prompt_switches": _prompt_switches,
		"sample_prompt_switches": _prompt_switches - _sample_prompt_switches_start,
		"prompt_drift_events": _prompt_drift_events, "prompt_drift_changed_device": _prompt_drift_changed_kind,
		"main_process_enabled": _app.is_processing(), "main_benchmark_upgrade_suppression": _app._benchmark,
		"world_stress_mode": _app.world.stress_mode, "world_autopilot": _app.world.autopilot,
		"seed": SEED, "run_seed": sim.run.summary()["seed"], "arena_id": sim.run.arena_id,
		"core_id": sim.run.core_id, "core_activations": sim.core_activations.duplicate(true),
		"weapon_ids": Array(_app.world.stress_weapon_ids),
		"damage_by_weapon": sim.run.damage_dealt_by_weapon.duplicate(true),
		"primary_hits": sim.primary_hits, "secondary_hits": sim.secondary_hits,
		"counter_scope": "total dash/feedback/hit/damage/core counters include warmup; sample-prefixed counters exclude it",
		"dash_rules": {"duration": DashRules.DURATION, "speed": DashRules.SPEED, "cooldown": DashRules.COOLDOWN, "invulnerability": DashRules.INVULNERABILITY},
		"projectile_families_at_end": _app.world._projectile_painter.get_stats()["family_counts"],
		"source_hash": source["hash"], "source_hash_algorithm": source["algorithm"], "source_files": source["files"],
		"engine": Engine.get_version_info(), "os": OS.get_name(), "display_server": DisplayServer.get_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"internal_resolution": "1280x720", "window_size": [root.size.x, root.size.y], "window_visible": root.visible,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"fixture_overrides": ["300 enemies with synthetic high health", "600 real content/rune projectiles replenished before each World step", "200 synthetic pickups replenished before each World step", "full player health restored before each World step", "bone_chorus core assigned directly", "earned-upgrade modals suppressed by Main._benchmark while Main._process is disabled", "facing alternates right/left on real dash readiness; no synthetic movement input", "autoplay argument only prevents focus-loss pause; World autopilot remains disabled"],
		"thresholds": {"minimum_fps": MIN_FPS, "maximum_p99_frame_ms": MAX_P99_MS, "minimum_sample_dashes": minimum_dashes, "minimum_afterimage_peak": 1},
		"checks": {"performance": fps >= MIN_FPS and p99 <= MAX_P99_MS, "load": load_valid, "dash_feedback": feedback_valid, "evasion_feedback": evasion_valid, "pulse_control": pulse_valid, "default_settings_and_no_profile": defaults_valid},
		"passed": fps >= MIN_FPS and p99 <= MAX_P99_MS and load_valid and feedback_valid and evasion_valid and pulse_valid and defaults_valid and prompt_valid,
	}
	if _backpack_skills:
		var results: Dictionary = _backpack_skill_results(sim)
		var fx_valid: bool = not _backpack_skill_fx_invalid and _backpack_skill_fx_capacity == BACKPACK_SKILL_FX_LIMIT and _backpack_skill_fx_peak <= BACKPACK_SKILL_FX_LIMIT and _sample_backpack_skill_fx_peak > 0 and _sample_backpack_skill_fx_peak <= BACKPACK_SKILL_FX_LIMIT
		var skill_sources: Dictionary = {}
		var source_valid: bool = true
		for path: String in _backpack_skill_source_paths():
			if not (source["files"] as Dictionary).has(path):
				source_valid = false
			else:
				skill_sources[path] = source["files"][path]
		report["active_skills"] = sim.run.active_skills.duplicate(true)
		report["backpack_skill_ids"] = _backpack_skill_ids.duplicate()
		report["backpack_skill_purchases"] = _backpack_skill_purchases.duplicate(true)
		report["backpack_skill_results"] = results["skills"]
		report["backpack_pulse_control"] = results["pulse_control"]
		report["active_skill_uses"] = results["uses"]
		report["sample_active_skill_uses"] = results["sample_uses"]
		report["backpack_skill_cast_events"] = _backpack_skill_cast_log.duplicate(true)
		report["backpack_skill_invalid_events"] = _backpack_skill_invalid_events
		report["active_skill_fx_peak"] = _backpack_skill_fx_peak
		report["sample_active_skill_fx_peak"] = _sample_backpack_skill_fx_peak
		report["active_skill_fx_capacity"] = _backpack_skill_fx_capacity
		report["active_skill_fx_invalid"] = _backpack_skill_fx_invalid
		report["damage_by_skill"] = sim.damage_by_skill.duplicate(true)
		report["skill_hits"] = sim.skill_hits
		report["backpack_skill_source_files"] = skill_sources
		report["thresholds"]["minimum_sample_skill_uses"] = results["minimum_uses"]
		report["thresholds"]["maximum_active_skill_fx"] = BACKPACK_SKILL_FX_LIMIT
		report["thresholds"]["minimum_sample_positive_control_casts"] = 1 if _backpack_skill_ids.has("pulse") else 0
		report["checks"]["backpack_skill_inventory_and_real_casts"] = results["valid"]
		report["checks"]["backpack_pulse_real_control"] = results["pulse_control"]["valid"]
		report["checks"]["backpack_skill_fx_pool"] = fx_valid
		report["checks"]["backpack_skill_source_coverage"] = source_valid
		report["passed"] = bool(report["passed"]) and bool(results["valid"]) and fx_valid and source_valid
		report["fixture_overrides"].append("fixture grants exact prices and explicit stock, then purchases the legal rank-I companions %s through RunState.buy_offer into two real backpack skill slots" % ", ".join(_backpack_skill_ids))
		report["fixture_overrides"].append("each ready purchased UID is queued only through World.request_skill(slot); output skills require positive sampled damage, while pulse requires positive sampled active_skill_cast affected counts plus observed legal enemies with pulse_hinder_timer > 0 and zero pulse damage; pressure counts and performance thresholds stay unchanged")
	report["grounding"] = {"peak_including_warmup": _grounding_peak, "sample_peak": _sample_grounding_peak,
		"draw_command_peak": _grounding_draw_peak, "capacity": GroundingPainter.CAPACITY}
	report["checks"]["grounding_budget"] = _sample_grounding_peak > 0 and _grounding_peak <= GroundingPainter.CAPACITY and _grounding_draw_peak == 1
	report["passed"] = bool(report["passed"]) and bool(report["checks"]["grounding_budget"])
	if _pulse_cycles:
		report["fixture_overrides"].append("real Q requests at readiness; pulse control occurs before the normal World fixed step movement, while synthetic pressure positions are replenished each frame")
	if _pulse_cycles or _skill_feedback or _skill_relics:
		report["fixture_overrides"].append("fixture grants the pulse price and explicit stock, then purchases one rank-I pulse box occupying two real backpack cells before any pulse request")
	if _skill_relics:
		report["fixture_overrides"].append("fixture grants money and explicit stock, then actually purchases eight skill relics and merges them into one rank-III item of each kind in the real backpack")
	if _input_prompts:
		report["fixture_overrides"].append("parsed Y and unbound F6 alternate input prompts every half-second; each physics step injects sub-deadzone left-stick drift; these events do not request combat skills")
		report["checks"]["input_prompt_switching_and_drift"] = prompt_valid
	if _evasion_probes:
		report["fixture_overrides"].append("each accepted dash clears old received-hit immunity and adds one stationary, positive-damage hostile projectile at its next-step position; normal collision and dash immunity decide the result")
	if _skill_feedback:
		var sample_positive: int = _positive_pulse_casts - _sample_positive_pulse_start
		var feedback_validity: bool = _skill_feedback_peak <= 1 and _sample_skill_feedback_peak == 1 and sample_positive > 0
		var audio_source: Dictionary = _audio_source_fingerprint()
		var observed_streams: Array = _skill_audio_streams_observed.keys()
		observed_streams.sort()
		report["skill_feedback"] = true
		report["skill_feedback_peak"] = _skill_feedback_peak
		report["sample_skill_feedback_peak"] = _sample_skill_feedback_peak
		report["positive_pulse_casts"] = _positive_pulse_casts
		report["zero_pulse_casts"] = _zero_pulse_casts
		report["sample_positive_pulse_casts"] = sample_positive
		report["sample_zero_pulse_casts"] = _zero_pulse_casts - _sample_zero_pulse_start
		report["skill_audio_playing_peak"] = _skill_audio_playing_peak
		report["skill_audio_streams_observed"] = observed_streams
		report["audio_voice_capacity"] = _app.sound.voices.size()
		report["audio_source_hash"] = audio_source["hash"]
		report["audio_source_files"] = audio_source["files"]
		report["checks"]["skill_feedback_single_slot_and_real_control"] = feedback_validity
		report["passed"] = bool(report["passed"]) and feedback_validity
		report["fixture_overrides"].append("skill-feedback option only observes real control results and native player streams; enemy layout and skill request timing stay unchanged; zero-target coverage is reported honestly and tested separately")
	if _hero_skills:
		var hero: Dictionary = _app.world.sim.hero_skill_snapshot()
		var uses: int = int(hero["uses"]) - _sample_hero_uses_start
		var minimum_uses: int = maxi(1, floori(_seconds / float(hero["cooldown_duration"])) - 1)
		report["hero_skills"] = true
		report["hero_id"] = hero["hero_id"]
		report["sample_hero_skill_uses"] = uses
		report["thresholds"]["minimum_sample_hero_skill_uses"] = minimum_uses
		report["checks"]["real_main_character_casts"] = uses >= minimum_uses
		report["passed"] = bool(report["passed"]) and uses >= minimum_uses
		report["fixture_overrides"].append("main-character option repeatedly requests the real independent R skill; its cooldown, damage and shared fixed effect pool remain production rules")
	if _pinball_probes:
		var cycles: int = _pinball_cycles - _sample_pinball_cycles_start
		var bounces: int = _pinball_bounces - _sample_pinball_bounces_start
		var minimum_cycles: int = maxi(1, floori(_seconds / DashRules.COOLDOWN) - 1)
		report["pinball_probes"] = true
		report["sample_pinball_cycles"] = cycles
		report["sample_pinball_bounces"] = bounces
		report["thresholds"]["minimum_sample_pinball_cycles"] = minimum_cycles
		report["checks"]["real_pinball_cycles_and_reflections"] = cycles >= minimum_cycles and bounces > cycles
		report["passed"] = bool(report["passed"]) and bool(report["checks"]["real_pinball_cycles_and_reflections"])
		report["fixture_overrides"].append("before each ready dash, the fixture positions the player before the authored east bumper; the real dash triggers ball mode and normal collision resolves its flight, enemy damage and reflections; enemies retired by the wider movement are replenished to keep all 300 simulation agents active")
	var absolute: String = ProjectSettings.globalize_path(_output)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		_abort("Could not create report directory: %s" % error_string(directory_error))
		return
	var file: FileAccess = FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		_abort("Could not open report: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_abort("Could not write report: %s" % error_string(write_error))
		return
	print("DASH_BENCHMARK_RESULT ", JSON.stringify(report))
	_app._quit_game(0 if bool(report["passed"]) else 1)

func _abort(message: String) -> void:
	push_error(message)
	_stop_updates()
	_app._quit_game(2)
