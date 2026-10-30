extends SceneTree
## Independent hero casts use real damage and recorded geometry, without borrowing rear UIDs.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _sim(hero_id: String) -> CombatSim:
	var state := RunState.new()
	state.begin(20261030, "", "reliquary", hero_id)
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.invulnerability = 1000.0
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(640, 360)
	sim.player_direction = Vector2.RIGHT
	return sim

func _target(sim: CombatSim, position: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", position)
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	return enemy

func _run() -> void:
	for id: String in HeroCatalog.IDS:
		var sim: CombatSim = _sim(id)
		var target: CombatSim.Enemy = _target(sim, sim.player_position + Vector2(80, 0))
		var untouched: CombatSim.Enemy = _target(sim, sim.player_position + Vector2(-700, 0))
		var inventory: String = JSON.stringify(sim.run.backpack_snapshot())
		var random_state: int = sim.rng.state
		var store_random: int = sim.run.rng.state
		var parameters: Dictionary = sim.run.hero_skill_parameters()
		_check(sim.try_hero_skill(), "Every selected hero can cast R without a rear item: " + id)
		_check(is_equal_approx(10000.0 - target.health, 0.0 if id == "hanabi" else float(parameters["damage"])), "Instant casts use actual damage while bombs must first travel: " + id)
		_check(untouched.health == 10000.0, "A target beyond the actual cast geometry is not hit: " + id)
		_check(sim.hero_skill_snapshot()["uses"] == 1 and not sim.hero_skill_snapshot()["ready"], "R owns a real cooldown and use count: " + id)
		_check(not sim.try_hero_skill() and not sim.try_active_skill(0), "Cooling R cannot recast and never grants a Q item: " + id)
		_check(JSON.stringify(sim.run.backpack_snapshot()) == inventory and sim.run.active_skills.is_empty(), "Hero skill never occupies or grants a backpack slot: " + id)
		_check(sim.rng.state == random_state and sim.run.rng.state == store_random, "The deterministic hero cast consumes neither RNG: " + id)
		_check(is_equal_approx(float(sim.damage_by_skill.get("hero_" + id, 0.0)), 0.0 if id == "hanabi" else float(parameters["damage"])) and sim.skill_hits == (0 if id == "hanabi" else 12 if id == "clarisse" else 1), "Hero damage reaches real skill accounting: " + id)
		var saved: String = JSON.stringify(sim.hero_skill_snapshot())
		sim.step(0.0, Vector2.ZERO, false, false, [], true)
		sim.step(NAN, Vector2.ZERO, false, false, [], true)
		_check(JSON.stringify(sim.hero_skill_snapshot()) == saved, "Invalid time cannot consume or tick R: " + id)
		sim.step(STEP, Vector2.ZERO)
		_check(is_equal_approx(float(sim.hero_skill_snapshot()["cooldown_remaining"]), float(parameters["cooldown"]) - STEP), "Cooldown advances only in a valid simulation step: " + id)
		var source: Dictionary = sim.hero_skill_snapshot()
		source["damage"] = -99.0
		_check(sim.hero_skill_snapshot()["damage"] == parameters["damage"], "Public R snapshots cannot mutate the recorded cast: " + id)
		for frame: int in int(round(float(parameters["cooldown"]) / STEP)) - 1:
			sim.step(STEP, Vector2.ZERO)
		_check(sim.hero_skill_snapshot()["ready"] and sim.hero_skill_snapshot()["cooldown_remaining"] == 0.0, "The exact 60Hz cooldown boundary is ready without an extra floating-point frame: " + id)
		sim.complete = true
		_check(not sim.try_hero_skill(), "Terminal combat rejects R: " + id)
	_test_shapes()
	_test_rear_independence()
	_test_effects()
	print("HeroSkillCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_shapes() -> void:
	var origin := Vector2(640, 360)
	for id: String in HeroCatalog.IDS:
		var parameters: Dictionary = HeroCatalog.hero_skill_parameters(id, {})
		var radius: float = float(parameters["radius"])
		_check(CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2(radius, 0)), "The exact forward boundary is included: " + id)
		_check(not CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2(radius + 1.0, 0)), "The forward boundary does not leak: " + id)
		_check(not CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, Vector2.INF), "Non-finite targets are rejected: " + id)
		if parameters["shape"] == "line":
			var half_width: float = float(parameters["width"]) * 0.5
			_check(CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2(80, half_width)), "Hanabi beam includes its actual side boundary")
			_check(not CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2(80, half_width + 1.0)), "Hanabi beam cannot hit beyond its width")
			_check(not CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2(-1, 0)), "Hanabi beam cannot hit behind its origin")
		elif parameters["shape"] in ["arc", "double_arc"]:
			var angle: float = float(parameters["half_angle_radians"])
			_check(CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2.from_angle(angle) * 100.0), "Sword cast includes the exact arc boundary")
			_check(not CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2.from_angle(angle + 0.01) * 100.0), "Sword cast cannot hit outside the displayed arc")

func _test_rear_independence() -> void:
	var sim: CombatSim = _sim("alk")
	for id: String in ["starfall", "arc_slash"]:
		_check(not sim.run.backpack.add("skill", id).is_empty(), "The fixture owns an actual rear character: " + id)
	sim.run._sync_backpack_projection()
	_check(sim.try_active_skill(0) and sim.try_active_skill(1) and sim.try_hero_skill(), "Q, E and R can all cast from their independent clocks")
	_check(sim.run.active_skills.size() == 2 and sim.run.backpack.add("skill", "pulse").is_empty(), "R does not increase the two-rear cap")
	var remaining: float = float(sim.hero_skill_snapshot()["cooldown_remaining"])
	var uses: int = int(sim.hero_skill_snapshot()["uses"])
	_check(sim.run.sell_item(int(sim.run.active_skills[0]["uid"])), "A real rear character can be sold during the fixture")
	_check(float(sim.hero_skill_snapshot()["cooldown_remaining"]) == remaining and sim.hero_skill_snapshot()["uses"] == uses, "Rear sale cannot refresh the main hero cooldown")
	_check(not sim.try_hero_skill("hanabi"), "A stale hero identity cannot redirect an input")
	var state: RunState = sim.run
	sim.begin(state)
	_check(sim.hero_skill_snapshot()["ready"] and sim.hero_skill_snapshot()["uses"] == 0, "A new wave starts its own main-hero clock")

func _test_effects() -> void:
	var painter = preload("res://scripts/combat/active_skill_painter.gd").new()
	for index: int in 24:
		var hero_id: String = HeroCatalog.IDS[index % HeroCatalog.IDS.size()]
		if hero_id != "hanabi":
			_check(painter.add_hero_cast(HeroCatalog.hero_skill_parameters(hero_id, {}), Vector2(640, 360), Vector2.RIGHT, true), "Instant heroes have a drawable cast; actual bombs use their runtime snapshot: " + hero_id)
	_check(painter.snapshot()["active"] == 8, "Hero casts share the existing bounded effect pool")
	painter.disable_animation()
	_check(painter.snapshot()["animated"] == 0, "Flash suppression covers every hero shape")
	painter.advance(0.27)
	_check(painter.snapshot()["active"] == 0, "All hero effects expire")
