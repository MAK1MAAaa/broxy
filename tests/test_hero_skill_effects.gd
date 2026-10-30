extends SceneTree
## Real original-trait adaptations: timed power, twelve hits, dual arcs and swept bombs.

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

func _sim(id: String) -> CombatSim:
	var state := RunState.new()
	state.begin(20261031, "", "reliquary", id)
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.invulnerability = 9999.0
	sim._cooldowns.fill(9999.0)
	sim.obstacles.configure([])
	sim.interactions = ArenaInteractions.new()
	sim.player_position = Vector2(640, 360)
	sim.player_direction = Vector2.RIGHT
	return sim

func _target(sim: CombatSim, offset: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + offset)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	return enemy

func _run() -> void:
	_test_alk()
	_test_clarisse()
	_test_celtie()
	_test_hanabi()
	_test_pool_and_clear()
	_test_sources_and_scaling()
	print("HeroSkillEffects: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_alk() -> void:
	var sim: CombatSim = _sim("alk")
	var front: CombatSim.Enemy = _target(sim, Vector2(90, 0))
	var back: CombatSim.Enemy = _target(sim, Vector2(-90, 0))
	var damage: float = sim.run.hero_skill_parameters()["damage"]
	var permanent: float = sim.run.stat("damage")
	_check(sim.try_hero_skill(), "Alk casts the actual surrounding shockwave")
	_check(is_equal_approx(10000.0 - front.health, damage) and is_equal_approx(10000.0 - back.health, damage), "Alk hits both sides rather than only an old forward arc")
	var effect: Dictionary = sim.hero_effects_snapshot()
	_check(effect["attack_left"] == 5.0 and is_equal_approx(float(effect["attack_bonus"]), 0.2), "The real cast grants bounded temporary attack power")
	var shot: CombatSim.Shot = sim.fire_weapon("bone", "", sim.player_position, Vector2.RIGHT)
	_check(is_equal_approx(shot.damage, GameCatalog.weapon("bone").damage * permanent * 1.2), "Temporary attack power changes the actual emitted weapon shot")
	sim._release_shot(shot)
	effect["attack_bonus"] = 20.0
	_check(is_equal_approx(sim.hero_effects.attack_multiplier(), 1.2) and sim.run.stat("damage") == permanent, "Reading or mutating effect snapshots cannot turn a temporary buff into permanent stats")
	sim.step(5.0, Vector2.ZERO)
	_check(sim.hero_effects_snapshot()["attack_left"] == 0.0 and sim.hero_effects.attack_multiplier() == 1.0 and sim.run.stat("damage") == permanent, "Actual simulation time expires the attack buff exactly")

func _test_clarisse() -> void:
	var sim: CombatSim = _sim("clarisse")
	var front: CombatSim.Enemy = _target(sim, Vector2(160, 0))
	var rear: CombatSim.Enemy = _target(sim, Vector2(-80, 0))
	var records: Array[float] = []
	sim.damage_dealt.connect(func(_position: Vector2, amount: float, source: String, _secondary: bool, uid: int) -> void:
		if source == "skill:hero_clarisse" and uid == front.uid:
			records.append(amount)
	)
	var damage: float = sim.run.hero_skill_parameters()["damage"]
	_check(sim.try_hero_skill(), "Clarisse casts the actual forward explosion")
	_check(records.size() == 12 and is_equal_approx(10000.0 - front.health, damage), "Twelve actual damage receipts preserve the cast's total adapted damage")
	_check(rear.health == 10000.0 and rear.fire_vulnerability_left == 0.0, "The front explosion does not apply damage or vulnerability behind the caster")
	_check(front.fire_vulnerability_left == 4.0 and is_equal_approx(front.fire_vulnerability, 0.25), "A surviving hit target receives the actual bounded fire weakness")
	var before: float = front.health
	sim.apply_damage(front, 10.0, "test", false, 0.0, "fire")
	_check(is_equal_approx(before - front.health, 12.5), "Subsequent fire damage consumes the real target modifier")
	before = front.health
	sim.apply_damage(front, 10.0, "test", false, 0.0, "wind")
	_check(is_equal_approx(before - front.health, 10.0), "Other elements cannot receive fire weakness amplification")
	sim.step(4.0, Vector2.ZERO)
	before = front.health
	sim.apply_damage(front, 10.0, "test", false, 0.0, "fire")
	_check(front.fire_vulnerability_left == 0.0 and is_equal_approx(before - front.health, 10.0), "The target modifier expires through actual enemy updates")

func _test_celtie() -> void:
	var sim: CombatSim = _sim("celtie")
	var front: CombatSim.Enemy = _target(sim, Vector2(90, 0))
	var back: CombatSim.Enemy = _target(sim, Vector2(-90, 0))
	var side: CombatSim.Enemy = _target(sim, Vector2(0, 90))
	sim._pinball_combo = 40
	var base: float = sim.run.hero_skill_parameters()["damage"]
	_check(sim.try_hero_skill(), "Celtie casts with a real existing pinball combo")
	_check(is_equal_approx(10000.0 - front.health, base * 1.2) and is_equal_approx(10000.0 - back.health, base * 1.2) and side.health == 10000.0, "Both opposite arcs use the combo bonus and exclude perpendicular space")
	_check(sim.hero_skill_snapshot()["combo"] == 40 and is_equal_approx(float(sim.hero_skill_snapshot()["combo_bonus"]), 0.2), "The cooldown snapshot locks the actual combo used for this cast")
	var capped: CombatSim = _sim("celtie")
	capped._pinball_combo = 9999
	_check(capped.try_hero_skill() and capped.hero_skill_snapshot()["damage"] == base * 1.5, "Even arbitrarily large combo values respect the adapted fifty-percent cap")

func _test_hanabi() -> void:
	var sim: CombatSim = _sim("hanabi")
	var target: CombatSim.Enemy = _target(sim, Vector2(110, 0))
	var sim_rng: int = sim.rng.state
	var run_rng: int = sim.run.rng.state
	_check(sim.try_hero_skill(), "Hanabi casts five independently moving bombs")
	var effect: Dictionary = sim.hero_effects_snapshot()
	_check(effect["active_bombs"] == 5 and effect["explosions"] == 0 and target.health == 10000.0 and sim.skill_hits == 0, "Casting cannot apply an invisible instant line or pre-impact damage")
	var positions: Dictionary = {}
	for bomb: Dictionary in effect["bombs"]:
		positions[bomb["position"]] = true
		_check(bomb["life"] == 1.2 and bomb["velocity"].length() > 0.0, "Every actual bomb owns its own lifetime and motion")
	_check(positions.size() == 5, "The five bomb trajectories have distinct initial positions")
	var saved: Dictionary = sim.hero_effects_snapshot()
	effect["bombs"][0]["position"] = Vector2.INF
	_check(sim.hero_effects_snapshot() == saved, "External presentation edits cannot move physical bombs")
	for frame: int in 80:
		sim.step(STEP, Vector2.ZERO)
	_check(target.health < 10000.0 and sim.damage_by_skill.get("hero_hanabi", 0.0) > 0.0 and sim.damage_by_weapon.is_empty(), "Actual bomb contact and explosions reach skill damage accounting")
	_check(float(sim.damage_by_skill.get("hero_hanabi", 0.0)) <= float(sim.run.hero_skill_parameters()["damage"]) + 0.000001, "Five deliveries cannot deal more than their shared total damage budget to one target")
	_check(sim.hero_effects_snapshot()["active_bombs"] == 0 and sim.hero_effects_snapshot()["explosions"] == 5, "Every bomb detonates once through collision or lifetime; none leaks")
	_check(sim.rng.state == sim_rng and sim.run.rng.state == run_rng, "Bomb fan, sweep collisions and explosions consume no simulation or shop randomness")
	var sweep: CombatSim = _sim("hanabi")
	var swept: CombatSim.Enemy = _target(sweep, Vector2(140, 0))
	_check(sweep.try_hero_skill(), "The large-step sweep fixture uses a real cast")
	sweep.step(0.7, Vector2.ZERO)
	_check(swept.health < 10000.0, "A long but valid physics interval cannot tunnel bombs through a target")
	var wall: CombatSim = _sim("hanabi")
	wall.obstacles.configure([{"id": "test_wall", "center": wall.player_position + Vector2(80, 0), "radius": 32.0}])
	_check(wall.try_hero_skill(), "The solid-obstacle fixture uses a real cast")
	wall.step(0.5, Vector2.ZERO)
	_check(wall.hero_effects_snapshot()["explosions"] > 0, "Bombs detonate on the real ground collision system")

func _test_pool_and_clear() -> void:
	var runtime := HeroSkillRuntime.new()
	var parameters: Dictionary = HeroCatalog.hero_skill_parameters("hanabi", {})
	for cast: int in 4:
		_check(runtime.spawn_bombs(parameters, Vector2(640, 360), Vector2.RIGHT), "The bounded pool admits exactly four complete five-bomb casts")
	var before: Dictionary = runtime.snapshot()
	_check(not runtime.spawn_bombs(parameters, Vector2.ZERO, Vector2.RIGHT) and runtime.snapshot() == before and before["active_bombs"] == HeroSkillRuntime.BOMB_LIMIT, "An exhausted pool rejects a complete cast transaction without overwriting live bombs")
	runtime.clear()
	_check(runtime.snapshot()["active_bombs"] == 0 and runtime.bombs.size() == HeroSkillRuntime.BOMB_LIMIT, "Clearing reuses the fixed pool instead of reallocating active entities")
	var sim: CombatSim = _sim("hanabi")
	_check(sim.try_hero_skill(), "Lifecycle fixture starts a live delivery")
	sim._finish(false, "fixture")
	_check(sim.hero_effects_snapshot()["active_bombs"] == 0, "Terminal combat clears pending physical skill deliveries")
	sim.begin(sim.run)
	_check(sim.hero_effects_snapshot()["active_bombs"] == 0 and sim.hero_skill_snapshot()["uses"] == 0, "A new wave starts with no old bombs and a fresh R clock")

func _test_sources_and_scaling() -> void:
	var names: Dictionary = {"alk": "粉碎流星", "clarisse": "炼金爆发", "celtie": "风神·解放", "hanabi": "红牡丹"}
	for id: String in HeroCatalog.IDS:
		var hero: HeroDef = HeroCatalog.definition(id)
		var base: Dictionary = HeroCatalog.hero_skill_parameters(id, {})
		var modified: Dictionary = HeroCatalog.hero_skill_parameters(id, {"damage": 2.0, "skill_haste": 0.25, "summon_damage": 1.5})
		_check(hero.source_skill_name == names[id] and base["name"] == names[id] and hero.source_url.begins_with("https://wiki.biligame.com/worldflipper/") and hero.source_skill_weight > 0 and not hero.adaptation_notes.is_empty(), "Every adapted skill keeps a checkable source name, source weight and explicit adaptation: " + id)
		_check(is_equal_approx(float(modified["damage"]), float(base["damage"]) * (3.0 if id == "hanabi" else 2.0)) and is_equal_approx(float(modified["cooldown"]), float(base["cooldown"]) / 1.25), "Skill damage, haste and summon scaling apply exactly once: " + id)
