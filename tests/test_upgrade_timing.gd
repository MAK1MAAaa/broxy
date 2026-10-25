extends "res://tests/simulate_runs.gd"
## The automated runner must apply the same wave-local upgrades as the playable flow.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_live_pickup()
	_test_multiple_choices()
	_test_terminal_fallback()
	_test_live_healing()
	print("UpgradeTiming: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _simulation(seed_value: int) -> CombatSim:
	var state := RunState.new()
	state.begin(seed_value, "bone")
	var simulation := CombatSim.new()
	simulation.begin(state)
	simulation.sandbox = true
	simulation._cooldowns.fill(1000.0)
	return simulation

func _test_live_pickup() -> void:
	var simulation: CombatSim = _simulation(2026)
	var state: RunState = simulation.run
	simulation._drop_soul(simulation.player_position, state.xp_to_next_level())
	var trace: Array[Dictionary] = []
	_advance_combat_tick(simulation, state, trace)
	_check(state.level == 2 and state.pending_upgrades == 0, "An actual collected drop is converted to a selected upgrade during the live wave")
	_check(trace.size() == 1 and trace[0]["context"] == "combat" and float(trace[0]["wave_elapsed"]) > 0.0, "The trace distinguishes a live-wave choice from the intermission fallback")
	_check(simulation.elapsed == DELTA and state.gold == 42 and state.wave == 1 and not simulation.complete, "Choosing advances no additional combat time, spends no gold and does not finish the wave")
	var chosen: String = trace[0]["id"]
	var option: Dictionary = {}
	for candidate: Dictionary in RunState.UPGRADE_POOL:
		if candidate["id"] == chosen:
			option = candidate
	var key: String = option["stat"]
	_check(is_equal_approx(state.stat(key), float(RunState.BASE_STATS[key]) + float(option["amount"])), "The selected production upgrade is already reflected in the running simulation's state")
	_advance_combat_tick(simulation, state, trace)
	_check(trace.size() == 1 and simulation.elapsed == DELTA * 2.0, "A later live tick resumes normally without a duplicate choice")

func _test_multiple_choices() -> void:
	var simulation: CombatSim = _simulation(2030)
	var state: RunState = simulation.run
	simulation._drop_soul(simulation.player_position, 42 + 60 + 78)
	var trace: Array[Dictionary] = []
	_advance_combat_tick(simulation, state, trace)
	_check(state.level == 4 and state.pending_upgrades == 0 and trace.size() == 3, "One collected batch resolves all three earned upgrades without losing a level")
	var same_boundary: bool = true
	for entry: Dictionary in trace:
		same_boundary = same_boundary and entry["context"] == "combat" and entry["wave_elapsed"] == trace[0]["wave_elapsed"]
	_check(same_boundary and simulation.elapsed == DELTA, "All queued choices share the same paused combat boundary")

func _test_terminal_fallback() -> void:
	var simulation: CombatSim = _simulation(2026)
	simulation.sandbox = false
	simulation.elapsed = simulation.duration - DELTA * 0.5
	simulation._spawn_timer = 1000.0
	simulation._drop_soul(Vector2(1100, 550), 42)
	var trace: Array[Dictionary] = []
	_advance_combat_tick(simulation, simulation.run, trace)
	_check(simulation.complete and simulation.victory and simulation.run.pending_upgrades == 1 and trace.is_empty(), "A same-tick win takes priority; the final soul sweep does not masquerade as an in-combat upgrade")
	var terminal_elapsed: float = simulation.elapsed
	_advance_combat_tick(simulation, simulation.run, trace)
	_check(simulation.elapsed == terminal_elapsed and trace.is_empty(), "A completed simulation neither advances nor grants queued choices through the combat path")
	_choose_upgrades(simulation.run, trace)
	_check(trace.size() == 1 and trace[0]["context"] == "intermission" and simulation.run.pending_upgrades == 0, "The normal intermission fallback still resolves terminal soul income")
	var defeated: CombatSim = _simulation(2028)
	defeated.run.collect_souls(42)
	defeated._finish(false, "fixture defeat")
	trace.clear()
	_advance_combat_tick(defeated, defeated.run, trace)
	_check(trace.is_empty() and defeated.run.pending_upgrades == 1, "Defeat never applies an extra posthumous combat upgrade")

func _test_live_healing() -> void:
	var simulation: CombatSim
	for seed_value: int in range(2026, 2056):
		var candidate: CombatSim = _simulation(seed_value)
		candidate.run.collect_souls(42)
		if candidate.run.upgrade_choices().any(func(option: Dictionary) -> bool: return option["id"] == "vitality"):
			simulation = candidate
			break
	_check(simulation != null, "A natural three-choice fixture includes vitality without injecting an extra option")
	if simulation == null:
		return
	simulation.run.health = 30.0
	var trace: Array[Dictionary] = []
	_choose_upgrades(simulation.run, trace, "combat", simulation.elapsed)
	_check(trace.size() == 1 and trace[0]["id"] == "vitality", "The existing low-health policy preference remains unchanged")
	_check(simulation.run.health == 42.0 and simulation.run.stat("max_health") == 112.0 and simulation.elapsed == 0.0, "A live vitality choice adds the existing twelve health and maximum without advancing combat")
