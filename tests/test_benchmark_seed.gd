extends SceneTree
## Reproducible benchmark seeds must not leak into ordinary player starts or profiles.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const FIXED_SEED: int = 1792123517

class PlayerStartSpy:
	extends "res://scripts/main.gd"
	var requested_seed: int = -1
	var requested_starter: String = ""

	func _ready() -> void:
		pass

	func _begin_run(starter: String, seed_value: int = 0) -> void:
		requested_starter = starter
		requested_seed = seed_value

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	_test_parser()
	_test_ordinary_isolation()
	await _test_real_benchmark_reproducibility()
	print("BenchmarkSeed: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _test_parser() -> void:
	for arguments: PackedStringArray in [PackedStringArray(), PackedStringArray(["--benchmark", "--benchmark-content", "--seconds=300"]), PackedStringArray(["--seed=42"])]:
		_check(MAIN_SCRIPT._benchmark_seed_from_args(arguments) == 0, "Omitting the explicit benchmark seed retains the original time-derived seed path")
	for entry: Array in [["1", 1], ["1792123517", FIXED_SEED], ["00042", 42], ["+42", 42], ["9223372036854775807", 9223372036854775807]]:
		var arguments: PackedStringArray = ["--benchmark", "--benchmark-seed=" + str(entry[0])]
		_check(MAIN_SCRIPT._benchmark_seed_from_args(arguments) == int(entry[1]), "Positive benchmark seeds are parsed without truncation: " + str(entry[0]))
	for value: String in ["", "0", "0000", "-1", "+0", "1.5", "1e3", "abc", "42tail", "++1", " 42", "42 ", "9223372036854775808", "999999999999999999999999999999"]:
		_check(MAIN_SCRIPT._benchmark_seed_from_args(PackedStringArray(["--benchmark-seed=" + value])) == -1, "Invalid or overflowing explicit seeds are rejected rather than silently becoming random: " + value)
	_check(MAIN_SCRIPT._benchmark_seed_from_args(PackedStringArray(["--benchmark-seed"])) == -1, "A benchmark seed switch requires an explicit positive value")
	_check(MAIN_SCRIPT._benchmark_seed_from_args(PackedStringArray(["--benchmark-seed=2", "--benchmark-seed=3"])) == 3, "Repeated valid values follow the existing CLI convention that the last explicit value wins")
	_check(MAIN_SCRIPT._benchmark_seed_from_args(PackedStringArray(["--benchmark-seed=bad", "--benchmark-seed=3"])) == -1, "A malformed explicit request is never concealed by a later valid value")

func _test_ordinary_isolation() -> void:
	var spy: PlayerStartSpy = PlayerStartSpy.new()
	root.add_child(spy)
	for arguments: PackedStringArray in [PackedStringArray(["--benchmark-seed=1792123517"]), PackedStringArray(["--benchmark-seed=bad"]), PackedStringArray()]:
		spy.args = arguments
		spy._start_run("ember")
		_check(spy.requested_seed == 0 and spy.requested_starter == "ember", "Normal player starts do not parse or inherit a benchmark-only seed flag")
	spy.free()

func _benchmark_signature(app: MAIN_SCRIPT) -> String:
	var sim: CombatSim = app.world.sim
	var data: Array = [app.run.summary(), app.run.rng.state, sim.rng.state, sim._shot_free.duplicate(), sim._enemy_free.duplicate(), sim._soul_free.duplicate()]
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			data.append([enemy.slot, enemy.uid, enemy.position, enemy.health, enemy.action_timer])
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			data.append([shot.slot, shot.source, shot.rune, shot.position, shot.velocity, shot.damage, shot.life, shot.return_after, shot.return_speed, shot.returning, shot.return_cancelled])
	for soul: CombatSim.Soul in sim.souls:
		if soul.active:
			data.append([soul.slot, soul.position, soul.value])
	return JSON.stringify(data)

func _test_real_benchmark_reproducibility() -> void:
	var profile_existed: bool = FileAccess.file_exists(GameStore.PATH)
	var original: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if profile_existed else PackedByteArray()
	for mode: String in ["", "--benchmark-runes", "--benchmark-content"]:
		var reference: String = ""
		for repeat: int in 2:
			var app = MAIN.instantiate()
			app.store.persistent = false
			root.add_child(app)
			# Stop both clocks before the next frame so this test cannot save a report.
			app.set_process(false)
			app.world.set_physics_process(false)
			app.args = PackedStringArray(["--benchmark", "--benchmark-seed=%d" % FIXED_SEED, "--seconds=300"])
			if not mode.is_empty():
				app.args.append(mode)
			app._start_benchmark()
			_check(app.run.summary()["seed"] == FIXED_SEED and app._benchmark and not app.store.persistent, "Real Main begins the requested benchmark with the exact report seed in an isolated profile: " + mode)
			_check(app.world.sim.enemy_count == 300 and app.world.sim.shot_count == 600 and app.world.sim.soul_count == 200, "A fixed seed preserves the real benchmark population rather than substituting a lightweight fixture")
			var signature: String = _benchmark_signature(app)
			if repeat == 0:
				reference = signature
			else:
				_check(signature == reference, "Repeated real benchmark starts reproduce all generated pools, positions, damage and both RNGs: " + mode)
			app.queue_free()
			for frame: int in 3:
				await process_frame
	_check(FileAccess.file_exists(GameStore.PATH) == profile_existed and (not profile_existed or FileAccess.get_file_as_bytes(GameStore.PATH) == original), "Parser and real benchmark tests leave the player's profile byte-for-byte unchanged")
