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
	enemy.slow_timer = 1000.0
	enemy.slow_factor = 0.0
	return enemy

func _run() -> void:
	for id: String in HeroCatalog.IDS:
		var sim: CombatSim = _sim(id)
		var target: CombatSim.Enemy = _target(sim, sim.player_position + Vector2(40, 0))
		var untouched: CombatSim.Enemy = _target(sim, sim.player_position + Vector2(-700, 0))
		var inventory: String = JSON.stringify(sim.run.backpack_snapshot())
		var random_state: int = sim.rng.state
		var store_random: int = sim.run.rng.state
		var parameters: Dictionary = sim.hero_skill_snapshot()
		_check(sim.try_hero_skill(), "Every selected hero can cast R without a rear item: " + id)
		_check(target.health == 10000.0 and sim.skill_hits == 0, "A cast cannot deal damage before its actual area or bomb delivery: " + id)
		_check(untouched.health == 10000.0, "A target beyond the actual cast geometry is not hit: " + id)
		_check(sim.hero_skill_snapshot()["uses"] == 1 and not sim.hero_skill_snapshot()["ready"], "R owns a real cooldown and use count: " + id)
		_check(not sim.try_hero_skill() and not sim.try_active_skill(0), "Cooling R cannot recast and never grants a Q item: " + id)
		_check(JSON.stringify(sim.run.backpack_snapshot()) == inventory and sim.run.active_skills.is_empty(), "Hero skill never occupies or grants a backpack slot: " + id)
		_check(sim.rng.state == random_state and sim.run.rng.state == store_random, "The deterministic hero cast consumes neither RNG: " + id)
		_check(float(sim.damage_by_skill.get("hero_" + id, 0.0)) == 0.0, "Pending delivery cannot fabricate skill contribution: " + id)
		var saved: String = JSON.stringify(sim.hero_skill_snapshot())
		var effects_saved: String = JSON.stringify(sim.hero_effects_snapshot())
		sim.step(0.0, Vector2.ZERO, false, false, [], true)
		sim.step(NAN, Vector2.ZERO, false, false, [], true)
		_check(JSON.stringify(sim.hero_skill_snapshot()) == saved, "Invalid time cannot consume or tick R: " + id)
		_check(JSON.stringify(sim.hero_effects_snapshot()) == effects_saved, "Invalid time cannot advance a pending area or bomb: " + id)
		sim.step(STEP, Vector2.ZERO)
		_check(is_equal_approx(float(sim.hero_skill_snapshot()["cooldown_remaining"]), float(parameters["cooldown"]) - STEP), "Cooldown advances only in a valid simulation step: " + id)
		var source: Dictionary = sim.hero_skill_snapshot()
		source["damage"] = -99.0
		_check(sim.hero_skill_snapshot()["damage"] == parameters["damage"], "Public R snapshots cannot mutate the recorded cast: " + id)
		var delivery_end: float = 0.0
		for phase: Dictionary in parameters.get("timeline", []):
			delivery_end = maxf(delivery_end, float(phase["delay"]) + float(phase["duration"]))
		if parameters.get("delivery", "") == "bombs":
			delivery_end = float(parameters.get("cast_delay", 0.0)) + float(parameters.get("projectile_life", 0.0)) + float(parameters.get("explosion_duration", 0.0))
		var delivery_frames: int = maxi(180, ceili(delivery_end / STEP) + 2)
		for frame: int in delivery_frames - 1:
			sim.step(STEP, Vector2.ZERO)
		var expected_damage: float = float(parameters["damage"]) * (1.240625 if id == "clarisse" else 1.0)
		_check(is_equal_approx(10000.0 - target.health, expected_damage), "Real delivery deals locked damage once, including Clarisse's post-first-hit fire weakness: " + id)
		_check(untouched.health == 10000.0, "Completed deliveries do not damage targets outside their geometry: " + id)
		_check(is_equal_approx(float(sim.damage_by_skill.get("hero_" + id, 0.0)), expected_damage) and sim.skill_hits == (30 if id == "falsche" else 5 if id == "hanabi" else 15 if id == "clarisse" else 1), "Every delivered hit reaches authoritative skill accounting: " + id)
		var delivered: Dictionary = sim.hero_effects_snapshot()
		_check(delivered["timeline"]["occupied"] == 0 and delivered["active_bombs"] == 0 and delivered["reserved_bombs"] == 0, "All delivery areas and bombs expire after real steps: " + id)
		for frame: int in int(round(float(parameters["cooldown"]) / STEP)) - delivery_frames:
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
		if parameters["shape"] == "rectangle":
			var half_width: float = float(parameters["width"]) * 0.5
			_check(CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2(-radius, 0)), "Celtie's actual rectangle includes its rear strike")
			_check(CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2(80, half_width)), "The rectangular strike includes its side boundary")
			_check(not CombatSim.skill_contains(parameters, origin, Vector2.RIGHT, origin + Vector2(80, half_width + 1.0)), "The rectangular strike cannot damage outside the displayed width")
		elif parameters["shape"] == "line":
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
		_check(not painter.add_hero_cast(HeroCatalog.hero_skill_parameters(hero_id, {}), Vector2(640, 360), Vector2.RIGHT, true), "Area and bomb deliveries never create a cosmetic instant hit: " + hero_id)
	_check(painter.snapshot()["active"] == 0, "The cosmetic pool stays empty for physical R deliveries")
	painter.disable_animation()
	_check(painter.snapshot()["animated"] == 0, "Flash suppression covers every hero shape")
	painter.advance(0.27)
	_check(painter.snapshot()["active"] == 0, "All hero effects expire")
	for hero_id: String in ["alk", "clarisse", "celtie"]:
		var sim: CombatSim = _sim(hero_id)
		_check(sim.try_hero_skill(), "The fixture starts a real area delivery: " + hero_id)
		var snapshot: Dictionary = sim.skill_timeline.snapshot()
		var visual: Dictionary = SkillAreaPainter.geometry_snapshot(snapshot, true)
		var quiet: Dictionary = SkillAreaPainter.geometry_snapshot(snapshot, false)
		_check(not visual["commands"].is_empty() and not visual["bounds"].is_empty(), "The real pending area has visible telegraph geometry: " + hero_id)
		_check(not quiet["commands"].is_empty() and quiet["commands"].size() <= visual["commands"].size(), "Flash suppression retains the authoritative outline with bounded effects: " + hero_id)
		for frame: int in 180:
			sim.step(STEP, Vector2.ZERO)
		_check(SkillAreaPainter.geometry_snapshot(sim.skill_timeline.snapshot(), true)["commands"].is_empty(), "Visual geometry expires with the actual delivery, without a separate cosmetic clock: " + hero_id)
	var timeline := SkillTimelineRuntime.new()
	var parameters: Dictionary = HeroCatalog.hero_skill_parameters("alk", {})
	for index: int in SkillTimelineRuntime.LIMIT:
		_check(timeline.enqueue(parameters, Vector2(640, 360), Vector2.RIGHT), "Each available area slot accepts one real delivery")
	_check(not timeline.enqueue(parameters, Vector2(640, 360), Vector2.RIGHT) and timeline.snapshot()["occupied"] == SkillTimelineRuntime.LIMIT, "The authoritative delivery pool rejects overflow without replacing live casts")
	_check(SkillAreaPainter.geometry_snapshot(timeline.snapshot(), true)["commands"].size() <= SkillAreaPainter.MAX_COMMANDS, "The area painter obeys its bounded command budget")
	timeline.advance(3.0, Vector2(640, 360))
	timeline.finish_step()
	_check(timeline.snapshot()["occupied"] == 0, "Every real area slot is released after its delivery lifetime")
