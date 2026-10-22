extends SceneTree
## CPU-only sampling of the unmodified production stress simulation.
## Does not instantiate a window, renderer, UI, profile store or audio playback.

const STEP: float = 1.0 / 60.0
const WARMUP: int = 120
const SAMPLES: int = 1200

func _initialize() -> void:
	_profile.call_deferred()

func _profile() -> void:
	var state: RunState = RunState.new()
	state.begin(20261022, "bone")
	var simulation: CombatSim = CombatSim.new()
	simulation.begin(state)
	simulation.populate_stress()
	var world: CombatWorld = CombatWorld.new()
	world.sim = simulation
	world.stress_mode = true
	for index: int in WARMUP:
		simulation.step(STEP, Vector2.ZERO)
		world._maintain_stress()
	var step_times: Array[int] = []
	var maintenance_times: Array[int] = []
	var count_min: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
	var count_max: Vector3i = Vector3i.ZERO
	var wall_start: int = Time.get_ticks_usec()
	for index: int in SAMPLES:
		var start: int = Time.get_ticks_usec()
		simulation.step(STEP, Vector2.ZERO)
		var middle: int = Time.get_ticks_usec()
		world._maintain_stress()
		var finish: int = Time.get_ticks_usec()
		step_times.append(middle - start)
		maintenance_times.append(finish - middle)
		var counts: Vector3i = Vector3i(simulation.enemy_count, simulation.shot_count, simulation.soul_count)
		count_min = Vector3i(mini(count_min.x, counts.x), mini(count_min.y, counts.y), mini(count_min.z, counts.z))
		count_max = Vector3i(maxi(count_max.x, counts.x), maxi(count_max.y, counts.y), maxi(count_max.z, counts.z))
	var wall_usec: int = Time.get_ticks_usec() - wall_start
	var result: Dictionary = {
		"mode": "headless production CombatSim.step + CombatWorld._maintain_stress, no rendering",
		"seed": 20261022,
		"warmup_steps": WARMUP,
		"sample_steps": SAMPLES,
		"simulation_seconds": float(SAMPLES) * STEP,
		"wall_seconds": float(wall_usec) / 1000000.0,
		"step": _stats(step_times),
		"maintain_stress": _stats(maintenance_times),
		"counts_min": {"enemies": count_min.x, "projectiles": count_min.y, "pickups": count_min.z},
		"counts_max": {"enemies": count_max.x, "projectiles": count_max.y, "pickups": count_max.z},
		"complete": simulation.complete,
		"sandbox": simulation.sandbox,
	}
	var output: FileAccess = FileAccess.open("res://reports/profile.json", FileAccess.WRITE)
	if output == null:
		push_error("Cannot write reports/profile.json")
		world.free()
		quit(1)
		return
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("PROFILE ", JSON.stringify(result))
	world.free()
	quit(0 if not simulation.complete and count_min.x == 300 and count_min.y >= 600 and count_min.z == 200 else 1)

func _stats(values: Array[int]) -> Dictionary:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var total: int = 0
	for value: int in sorted:
		total += value
	return {
		"average_ms": float(total) / float(sorted.size()) / 1000.0,
		"maximum_ms": float(sorted.back()) / 1000.0,
		"p99_ms": float(sorted[mini(sorted.size() - 1, int(float(sorted.size()) * 0.99))]) / 1000.0,
	}
