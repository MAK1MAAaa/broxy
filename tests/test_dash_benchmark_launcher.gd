extends SceneTree
## Exercise the shared pressure launcher without starting its native load fixture.

const BENCHMARK = preload("res://scripts/diagnostics/dash_benchmark.gd")
const ALGORITHM: String = "sha256-utf8-lf-text-and-raw-binary"
const REQUIRED: Array[String] = [
	"res://project.godot", "res://tools/benchmark_dash.gd",
	"res://scripts/diagnostics/dash_benchmark.gd", "res://scripts/main.gd",
]
const TEXT_EXTENSIONS: Array[String] = ["gd", "json", "tres", "godot", "py", "sh", "ps1", "gdshader", "tscn", "svg", "cfg"]

class LauncherProbe extends "res://scripts/diagnostics/dash_benchmark.gd":
	var starts: int = 0
	var errors: Array[String] = []

	func _start() -> void:
		starts += 1

	func _argument_error(message: String) -> void:
		errors.append(message)


var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile_existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile_before: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if profile_existed else PackedByteArray()
	_test_defaults_and_arguments()
	_test_hero_backpack_arguments()
	_test_rejected_arguments()
	_test_manifest_schema()
	_test_source_digest()
	_test_real_source_binding()
	await _test_factory_and_lifecycle()
	_check(FileAccess.file_exists(GameStore.PATH) == profile_existed, "Launcher checks never create or remove the personal profile")
	if profile_existed:
		_check(FileAccess.get_file_as_bytes(GameStore.PATH) == profile_before, "Launcher checks leave every personal-profile byte unchanged")
	print("DashBenchmarkLauncher: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _test_defaults_and_arguments() -> void:
	var probe := LauncherProbe.new()
	_check(probe._parse_arguments(PackedStringArray()), "Empty arguments preserve the formal fixture defaults")
	_check(probe._seconds == 60.0 and probe._hero_id == "alk" and probe._arena_id == "mire", "The shared launcher retains its duration, hero and authored-map defaults")
	_check(BENCHMARK.WARMUP_SECONDS == 5.0 and BENCHMARK.MIN_FPS == 58.0 and BENCHMARK.MAX_P99_MS == 33.0, "Launcher migration preserves warmup and acceptance thresholds")
	_check(BENCHMARK.TARGET_ENEMIES == 300 and BENCHMARK.TARGET_PROJECTILES == 600 and BENCHMARK.TARGET_PICKUPS == 200, "Launcher migration retains all three actual-load targets")
	_check(not probe._running and not probe._sampling and probe._app == null and probe.starts == 0, "Parsing an unparented launcher never starts sampling or creates Main")
	probe.free()
	probe = LauncherProbe.new()
	var arguments := PackedStringArray(["--wf-dash-benchmark", "--seconds=5", "--output=user://dash-launcher.JSON", "--arena=wf_main_4_4_4_l0", "--hero=falsche", "--evasion-probes", "--pinball-probes", "--backpack-skills", "--hero-skills", "--equipment-scopes"])
	_check(probe._parse_arguments(arguments), "The release CLI flag accepts the same scoped fixture as the source wrapper")
	_check(probe._seconds == 5.0 and probe._output == "user://dash-launcher.JSON" and probe._hero_id == "falsche" and probe._arena_id == "wf_main_4_4_4_l0", "Valid arguments preserve their exact requested values")
	_check(probe._evasion_probes and probe._pinball_probes and probe._backpack_skills and probe._hero_skills and probe._equipment_scopes, "Every compatible pressure option reaches the shared fixture")
	_check(probe.errors.is_empty() and probe._app == null and probe._frame_samples.is_empty(), "Argument acceptance does not manufacture frames or a benchmark result")
	probe.free()
	for option: String in ["--pulse-cycles", "--skill-relics", "--input-prompts", "--skill-feedback"]:
		probe = LauncherProbe.new()
		_check(probe._parse_arguments(PackedStringArray([option])), "Legacy isolated probe remains available: " + option)
		probe.free()
	for id: String in ArenaCatalog.IDS:
		probe = LauncherProbe.new()
		_check(probe._parse_arguments(PackedStringArray(["--arena=" + id])), "Every authored arena remains available: " + id)
		probe.free()


func _test_hero_backpack_arguments() -> void:
	for hero_id: String in HeroCatalog.IDS:
		var probe := LauncherProbe.new()
		_check(probe._parse_arguments(PackedStringArray(["--hero=" + hero_id, "--backpack-skills", "--hero-skills", "--equipment-scopes"])), "Each real hero has a legal scoped benchmark: " + hero_id)
		_check(probe._backpack_skill_ids.size() == ActiveSkillRules.LIMIT and ActiveSkillRules.LIMIT == 2, "The fixture fills exactly two legal backpack skill slots: " + hero_id)
		var seen: Dictionary = {}
		for skill_id: String in probe._backpack_skill_ids:
			var owner: HeroDef = HeroCatalog.rear_for_skill(skill_id)
			_check(GameCatalog.skill(skill_id) != null and owner != null and owner.id != hero_id, "The backpack uses a real companion distinct from the main hero: " + hero_id + "/" + skill_id)
			_check(not seen.has(skill_id), "The two actual backpack companions are distinct: " + hero_id)
			seen[skill_id] = true
		probe.free()


func _test_rejected_arguments() -> void:
	var invalid: Array = [
		["--seconds="], ["--seconds=abc"], ["--seconds=4.999"], ["--seconds=-5"],
		["--seconds=nan"], ["--seconds=inf"], ["--seconds=1e999"],
		["--output="], ["--output=user://report.txt"], ["--hero=unknown"],
		["--arena=unknown"], ["--arena=wf_main_12_1_1_l0"], ["--unsupported"],
		["--equipment-scopes"], ["--equipment-scopes", "--backpack-skills"],
		["--equipment-scopes", "--hero-skills"],
	]
	for option: String in ["--pulse-cycles", "--skill-relics", "--input-prompts", "--skill-feedback"]:
		invalid.append(["--backpack-skills", option])
	for arguments: Array in invalid:
		var probe := LauncherProbe.new()
		_check(not probe._parse_arguments(PackedStringArray(arguments)), "Invalid or incompatible CLI arguments are rejected: " + str(arguments))
		_check(not probe.errors.is_empty() and probe._app == null and not probe._running, "Rejected arguments report a reason without starting a load: " + str(arguments))
		probe.free()


func _files_hash(files: Dictionary) -> String:
	var paths: Array = files.keys()
	paths.sort()
	var lines := PackedStringArray()
	for path: String in paths:
		lines.append(path + ":" + str(files[path]))
	return "\n".join(lines).sha256_text()


func _manifest(files: Dictionary) -> Dictionary:
	return {"schema_version": 1, "algorithm": ALGORITHM, "files": files.duplicate(), "source_hash": _files_hash(files)}


func _reject_manifest(probe: LauncherProbe, value: Dictionary, message: String) -> void:
	probe.errors.clear()
	_check(not probe._validate_manifest(value) and not probe.errors.is_empty(), message)


func _test_manifest_schema() -> void:
	var files: Dictionary = {}
	for path: String in REQUIRED:
		files[path] = "a".repeat(64)
	var valid: Dictionary = _manifest(files)
	var probe := LauncherProbe.new()
	_check(probe._validate_manifest(valid) and probe.errors.is_empty(), "A canonical manifest validates without reading or executing its declared source")
	var changed: Dictionary = valid.duplicate(true)
	changed["schema_version"] = 2
	_reject_manifest(probe, changed, "Unknown manifest schemas are rejected")
	changed = valid.duplicate(true)
	changed["algorithm"] = "sha256-path-and-content-manifest"
	_reject_manifest(probe, changed, "The old raw-text algorithm cannot silently validate a new canonical manifest")
	changed = valid.duplicate(true)
	changed["files"] = []
	_reject_manifest(probe, changed, "The manifest input table must be a dictionary")
	changed = valid.duplicate(true)
	changed["source_hash"] = "b".repeat(64)
	_reject_manifest(probe, changed, "A well-formed but incorrect composed source hash is rejected")
	for path: String in REQUIRED:
		var incomplete: Dictionary = files.duplicate()
		incomplete.erase(path)
		_reject_manifest(probe, _manifest(incomplete), "Required source bindings cannot be omitted: " + path)
	for path: String in [BENCHMARK.SOURCE_MANIFEST_PATH, BENCHMARK.LEDGER_PATH, "user://source.gd", "res://scripts/../main.gd", "res://scripts\\main.gd", "res://scripts/line\nbreak.gd", "res://scripts/line\rbreak.gd"]:
		var unsafe: Dictionary = files.duplicate()
		unsafe[path] = "a".repeat(64)
		_reject_manifest(probe, _manifest(unsafe), "Self/cyclic and noncanonical source paths are rejected even with a matching aggregate hash: " + path)
	for digest: String in ["A".repeat(64), "a".repeat(63), "g".repeat(64), ""]:
		var malformed: Dictionary = files.duplicate()
		malformed[REQUIRED[0]] = digest
		_reject_manifest(probe, _manifest(malformed), "Every input needs a lowercase 64-digit hexadecimal digest")
	_check(probe._source_manifest.is_empty() and probe._live_runtime_inputs.is_empty(), "Pure schema checks never install a partly validated manifest")
	probe.free()


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "A temporary digest fixture can be opened: " + path)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


func _test_source_digest() -> void:
	var probe := LauncherProbe.new()
	var prefix: String = "user://dash-launcher-digest-%d-" % Time.get_ticks_usec()
	var text: String = "extends Node\n# 中文来源\n"
	var created: Array[String] = []
	for suffix: String in TEXT_EXTENSIONS:
		var path: String = prefix + "text." + suffix
		for ending: String in ["\n", "\r\n", "\r"]:
			if _write_bytes(path, text.replace("\n", ending).to_utf8_buffer()):
				if not created.has(path):
					created.append(path)
				_check(probe._source_digest(path) == text.sha256_text(), "Text source hashes normalize line endings without changing the original file: " + suffix)
				_check(FileAccess.get_file_as_bytes(path) == text.replace("\n", ending).to_utf8_buffer(), "Canonical hashing does not rewrite the text fixture: " + suffix)
	var binary: PackedByteArray = PackedByteArray([0, 255, 13, 10, 128, 13, 65])
	var binary_path: String = prefix + "binary.png"
	if _write_bytes(binary_path, binary):
		created.append(binary_path)
		_check(probe._source_digest(binary_path) == _raw_hash(binary), "Binary provenance preserves all original bytes including CRLF and invalid UTF-8")
		_check(probe._source_digest(binary_path) != _raw_hash(PackedByteArray([0, 255, 10, 128, 13, 65])), "Binary line endings are never normalized")
	for path: String in created:
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "The exact temporary digest fixture is removed: " + path)
	probe.free()


func _raw_hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _canonical_hash(path: String) -> String:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if TEXT_EXTENSIONS.has(path.get_extension().to_lower()):
		return _raw_hash(bytes.get_string_from_utf8().replace("\r\n", "\n").replace("\r", "\n").to_utf8_buffer())
	return _raw_hash(bytes)


func _test_real_source_binding() -> void:
	var probe := LauncherProbe.new()
	var loaded: bool = probe._load_source_manifest()
	_check(loaded and probe.errors.is_empty(), "The packaged source manifest binds to the current launcher and actual runtime resources: " + str(probe.errors))
	if not loaded:
		probe.free()
		return
	var base: Dictionary = probe._source_manifest["files"]
	_check(not base.has(BENCHMARK.SOURCE_MANIFEST_PATH) and not base.has(BENCHMARK.LEDGER_PATH), "The embedded manifest excludes its own bytes and the coverage ledger to avoid a provenance cycle")
	_check(probe._source_manifest_sha256 == FileAccess.get_sha256(BENCHMARK.SOURCE_MANIFEST_PATH), "The actual manifest JSON bytes retain their own independent report digest")
	var live_source: bool = FileAccess.file_exists("res://project.godot")
	_check(probe._source_hash_origin == ("live_source" if live_source else "embedded_build_manifest"), "The report distinguishes live source verification from an embedded build manifest")
	if live_source:
		for path: String in base:
			_check(FileAccess.file_exists(path) and _canonical_hash(path) == base[path], "Every live-source input is independently checked using canonical text and raw binary bytes: " + path)
	var fingerprint: Dictionary = probe._source_fingerprint()
	var reported: Dictionary = fingerprint["files"]
	var ledger_sha: String = _raw_hash(FileAccess.get_file_as_bytes(BENCHMARK.LEDGER_PATH))
	_check(probe._live_runtime_inputs == {BENCHMARK.LEDGER_PATH: ledger_sha}, "The ledger is separately captured from its actual runtime raw bytes")
	_check(reported.size() == base.size() + 1 and reported.get(BENCHMARK.LEDGER_PATH) == ledger_sha, "The pressure fingerprint merges the live ledger with all embedded source bindings")
	_check(fingerprint["algorithm"] == ALGORITHM and fingerprint["hash"] == _files_hash(reported), "The pressure fingerprint hashes the complete sorted source-plus-live-ledger table")
	_check(fingerprint["hash"] != probe._source_manifest["source_hash"], "The pressure fingerprint cannot omit the live ledger and reuse the build-only hash")
	reported.erase(REQUIRED[0])
	_check((probe._source_fingerprint()["files"] as Dictionary).has(REQUIRED[0]) and base.has(REQUIRED[0]), "A returned fingerprint cannot mutate the retained source manifest")
	for path: String in ["res://scripts/main.gd", "res://scenes/main.tscn", "res://data/heroes/alk.tres", "res://assets/worldflipper/icons/skill_pulse.png"]:
		_check(probe._runtime_input_available(path) and probe._declared_input_available(path), "Real runtime resources resolve in both source and imported release form: " + path)
	_check(not probe._runtime_input_available("res://data/heroes/missing-benchmark-fixture.tres"), "A missing runtime resource is not accepted as build provenance")
	_check(not probe._declared_input_available("res://data/heroes/missing-benchmark-fixture.tres"), "An undeclared runtime input cannot pass resource validation")
	var provenance: Dictionary = probe._build_provenance_inputs()
	for path: String in ["res://tools/benchmark_dash.gd", "res://tools/build_dash_benchmark_manifest.py", "res://project.godot"]:
		_check(provenance.has(path) and probe._is_build_provenance(path), "Build provenance remains declared in the report: " + path)
		_check(not probe._runtime_input_available(path) and probe._declared_input_available(path), "Build provenance does not require external build scripts inside the runtime pack: " + path)
	var declared_count: int = probe._runtime_resources_checked.size()
	probe._declared_input_available("res://scripts/main.gd")
	_check(probe._runtime_resources_checked.size() == declared_count, "Repeated resource checks do not duplicate the runtime audit list")
	probe.free()


func _test_factory_and_lifecycle() -> void:
	var probe := LauncherProbe.new()
	probe._stop_updates()
	probe._stop_updates()
	_check(probe._finished and not probe._running and probe._app == null, "Stopping before Main exists is safe and idempotent")
	var app: Node = probe._instantiate_main()
	_check(app != null and app.get_parent() == null and not app.is_inside_tree(), "The real Main factory returns an unparented scene before any ready/profile callbacks")
	_check(app.has_meta("wf_dash_benchmark_child") and bool(app.get_meta("wf_dash_benchmark_child")), "The Main child is marked before tree entry to prevent recursive CLI redirection")
	_check(not app.store.persistent and app.world == null and app.ui == null, "Personal profile IO is disabled before the real Main begins initialization")
	app.store.load_profile()
	_check(app.store.save_profile() == OK and not app.store.persistent, "The real child store suppresses both profile load and save")
	app.free()
	probe.free()
	probe = LauncherProbe.new()
	root.add_child(probe)
	await process_frame
	await process_frame
	_check(probe.starts == 1 and probe._app == null and not probe._running, "The real deferred ready lifecycle dispatches once without starting the substituted pressure sampler")
	probe._connect_frame_signals()
	probe._connect_frame_signals()
	_check(process_frame.is_connected(probe._on_process_frame) and physics_frame.is_connected(probe._before_world_physics), "The shared frame hooks connect to actual SceneTree frame signals")
	_check(_connection_count(process_frame, probe._on_process_frame) == 1 and _connection_count(physics_frame, probe._before_world_physics) == 1, "Repeated frame setup cannot double-step the pressure fixture")
	await process_frame
	_check(probe._frame_samples.is_empty() and probe._physics_steps == 0 and probe.starts == 1, "Connected but stopped hooks do not fabricate physical steps or sampled frames")
	probe._disconnect_frame_signals()
	probe._disconnect_frame_signals()
	_check(not process_frame.is_connected(probe._on_process_frame) and not physics_frame.is_connected(probe._before_world_physics), "Explicit frame teardown is idempotent")
	probe._connect_frame_signals()
	var process_callback: Callable = probe._on_process_frame
	var physics_callback: Callable = probe._before_world_physics
	root.remove_child(probe)
	_check(not process_frame.is_connected(process_callback) and not physics_frame.is_connected(physics_callback), "Tree exit disconnects both actual frame hooks before the launcher is freed")
	probe.free()


func _connection_count(signal_value: Signal, callback: Callable) -> int:
	var count: int = 0
	for connection: Dictionary in signal_value.get_connections():
		if connection["callable"] == callback:
			count += 1
	return count
