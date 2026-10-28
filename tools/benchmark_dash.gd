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
var _sample_pulses_start: int = 0
var _sample_affected_start: int = 0
var _pulse_feedback_peak: int = 0
var _sample_pulse_feedback_peak: int = 0

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
		else:
			push_error("Supported arguments: --seconds=<at least 5> --output=<report.json> [--evasion-probes] [--pulse-cycles] [--skill-relics]")
			return false
	return true

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
	_app._begin_run("bone", SEED)
	if _skill_relics and not _equip_skill_relics():
		_abort("Could not purchase and merge the pressure fixture's skill relics")
		return
	_app.run.core_id = "bone_chorus"
	_app.world.autopilot = false
	_app.world.stress_mode = false
	_app.world.sim.populate_stress()
	_app.world.enable_rune_stress(true)
	_app.world.apply_visual_settings(_app.store.settings)
	root.title = "秘术余烬 · 冲刺压力夹具（非自然对局，不保存设置与成绩）"
	_make_caption()
	_dash_start_count = _app.world.sim.dashes_used
	_started_usec = Time.get_ticks_usec()
	_last_frame_usec = _started_usec
	# SceneTree emits this signal before every Node._physics_process callback.
	# World retains its own normal fixed-step callback and consumes the real queue.
	physics_frame.connect(_before_world_physics)
	_running = true
	_update_caption(_started_usec)
	print("DASH_BENCHMARK_START ", JSON.stringify({
		"scenario": "dash-content-pressure", "natural_run": false,
		"warmup_seconds": WARMUP_SECONDS, "duration_seconds": _seconds,
		"seed": SEED, "arena_id": "mire", "core_id": "bone_chorus",
		"load_targets": _counts(Vector3i(TARGET_ENEMIES, TARGET_PROJECTILES, TARGET_PICKUPS)),
		"settings": _app.store.settings.duplicate(true),
		"persistent_profile": _app.store.persistent, "output": _output,
		"evasion_probes": _evasion_probes,
		"pulse_cycles": _pulse_cycles,
		"skill_relics": _skill_relics,
	}))

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
	world.sim.run.health = world.sim.run.stat("max_health")
	world._maintain_stress()
	var counts := Vector3i(world.sim.enemy_count, world.sim.shot_count, world.sim.soul_count)
	_last_pre_step_counts = counts
	_physics_steps += 1
	if _sampling:
		_sample_physics_steps += 1
		_pre_step_minimum = Vector3i(mini(_pre_step_minimum.x, counts.x), mini(_pre_step_minimum.y, counts.y), mini(_pre_step_minimum.z, counts.z))
	_observe_feedback()
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

func _observe_feedback() -> void:
	var count: int = _app.world.dash_afterimage_count()
	var evasion_active: int = 1 if bool(_app.world.dash_evasion_feedback_snapshot()["active"]) else 0
	var pulse_active: int = 1 if bool(_app.world.pulse_feedback_snapshot()["active"]) else 0
	_pulse_feedback_peak = maxi(_pulse_feedback_peak, pulse_active)
	_evasion_feedback_peak = maxi(_evasion_feedback_peak, evasion_active)
	_afterimage_peak = maxi(_afterimage_peak, count)
	_rune_peak = maxi(_rune_peak, _app.world._rune_flashes.size())
	if _sampling:
		_sample_afterimage_peak = maxi(_sample_afterimage_peak, count)
		_sample_evasion_feedback_peak = maxi(_sample_evasion_feedback_peak, evasion_active)
		_sample_pulse_feedback_peak = maxi(_sample_pulse_feedback_peak, pulse_active)

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
	for directory: String in ["res://scripts", "res://data", "res://scenes"]:
		_collect_sources(directory, paths)
	paths.sort()
	var manifest := PackedStringArray()
	var files: Dictionary = {}
	for path: String in paths:
		var digest: String = FileAccess.get_file_as_string(path).sha256_text()
		files[path] = digest
		manifest.append(path + ":" + digest)
	return {"hash": "\n".join(manifest).sha256_text(), "algorithm": "sha256-path-and-content-manifest", "files": files}

func _stop_updates() -> void:
	_running = false
	_finished = true
	if physics_frame.is_connected(_before_world_physics):
		physics_frame.disconnect(_before_world_physics)
	_app.world.set_physics_process(false)
	_app.world.clear_pending_actions()

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
	var source: Dictionary = _source_fingerprint()
	var report: Dictionary = {
		"scenario": "dash-content-pressure", "natural_run": false,
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
		"passed": fps >= MIN_FPS and p99 <= MAX_P99_MS and load_valid and feedback_valid and evasion_valid and pulse_valid and defaults_valid,
	}
	if _pulse_cycles:
		report["fixture_overrides"].append("real Q requests at readiness; pulse control occurs before the normal World fixed step movement, while synthetic pressure positions are replenished each frame")
	if _skill_relics:
		report["fixture_overrides"].append("fixture grants money and explicit stock, then actually purchases eight skill relics and merges them into one rank-III item of each kind in the real backpack")
	if _evasion_probes:
		report["fixture_overrides"].append("each accepted dash clears old received-hit immunity and adds one stationary, positive-damage hostile projectile at its next-step position; normal collision and dash immunity decide the result")
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
