extends SceneTree
## Real dash-to-ball transitions, swept damage, topology and useful world pickups.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_dash_and_motion()
	_test_damage_and_order()
	_test_pickups()
	_test_sweep_index_matches_linear()
	print("PinballCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _fixture(rows: Array = [], crates: Array = []) -> CombatSim:
	var state := RunState.new()
	state.begin(20261030, "bone")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.invulnerability = 1000.0
	sim._cooldowns.fill(9999.0)
	sim.obstacles.bounds = Rect2(0, 0, 1280, 720)
	sim.interactions.configure({"id": "fixture", "obstacles": rows, "crates": crates}, 20261030, 1, sim.obstacles)
	sim._crate_indices.clear()
	for crate: Dictionary in sim.interactions.snapshot()["crates"]:
		sim._crate_indices["crate:" + str(crate["id"])] = int(crate["index"])
	sim.player_position = Vector2(640, 360)
	sim.player_direction = Vector2.RIGHT
	return sim

func _barrel() -> Array:
	return [{"id": "box", "center": Vector2(800, 360), "radius": 18.0, "art_id": "barrel", "max_health": 24.0}]

func _ball(sim: CombatSim) -> void:
	sim._begin_pinball(Vector2.LEFT * CombatSim.PINBALL_SPEED, Vector2.LEFT)

func _test_dash_and_motion() -> void:
	var sim: CombatSim = _fixture([{"id": "pad", "center": Vector2(800, 360), "radius": 30.0, "art_id": "bumper"}])
	var combat_rng: int = sim.rng.state
	var shop_rng: int = sim.run.rng.state
	sim.step(0.2, Vector2.ZERO, true)
	_check(sim.pinball_snapshot()["active"] and sim.dashes_used == 1 and sim.pinball_snapshot()["bounces"] == 1, "A real dash into the authored bumper becomes one ball state")
	_check(sim.player_velocity.x < 0.0 and sim.obstacles.is_free(sim.player_position, 16.0, 16.0), "Bumper contact reflects and keeps the real player outside the collider")
	_check(sim.dash_cooldown_left > 0.0 and sim.dash_invulnerability_left == 0.0, "Ball movement does not grant new dash immunity or refresh its clock")
	_check(sim.rng.state == combat_rng and sim.run.rng.state == shop_rng, "Dash and bumper response do not consume combat or shop randomness")
	var before: String = JSON.stringify(sim.pinball_snapshot())
	sim.step(0.0, Vector2.ZERO)
	sim.step(NAN, Vector2.ZERO)
	_check(JSON.stringify(sim.pinball_snapshot()) == before, "Invalid time cannot advance ball state")
	var large: CombatSim = _fixture()
	large.player_position = Vector2(1100, 360)
	_ball(large)
	large.step(0.8, Vector2.ZERO)
	var small: CombatSim = _fixture()
	small.player_position = Vector2(1100, 360)
	_ball(small)
	for frame: int in 32:
		small.step(0.025, Vector2.ZERO)
	_check(large.pinball_snapshot()["bounces"] == 2 and large.player_velocity.x < 0.0 and large.player_position.x < 1264.0, "A large step reflects at the world wall and spends its remaining distance")
	_check(large.player_position.distance_to(small.player_position) < 0.2 and large.pinball_snapshot()["bounces"] == small.pinball_snapshot()["bounces"], "Large and small steps agree on continuous wall collision")
	sim = _fixture()
	_ball(sim)
	sim._pinball_time_left = 0.01
	sim.step(0.1, Vector2.RIGHT)
	_check(not sim.pinball_snapshot()["active"] and is_equal_approx(sim.player_position.x, 640.0 + 6.5 + 19.8) and sim.player_velocity == Vector2.RIGHT * 220.0, "Ball expiry spends the unused frame as normal movement")
	sim = _fixture()
	sim.player_position = Vector2(1260, 360)
	_ball(sim)
	sim._pinball_bounces = CombatSim.PINBALL_BOUNCE_LIMIT - 1
	sim.step(0.1, Vector2.LEFT)
	_check(not sim.pinball_snapshot()["active"] and sim.pinball_snapshot()["bounces"] == CombatSim.PINBALL_BOUNCE_LIMIT and sim.player_velocity == Vector2.LEFT * 220.0, "The bounce limit returns the remaining frame to ordinary input")
	_check(sim.player_position.x < 1260.0, "Bounce-limit cleanup neither tunnels through the wall nor discards all remaining control")

func _target(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", point)
	enemy.health = 500.0
	enemy.max_health = 500.0
	return enemy

func _test_damage_and_order() -> void:
	var sim: CombatSim = _fixture()
	var enemy: CombatSim.Enemy = _target(sim, Vector2(800, 360))
	_ball(sim)
	sim.step(0.2, Vector2.ZERO)
	_check(is_equal_approx(enemy.health, 500.0 - CombatSim.PINBALL_DAMAGE) and sim.pinball_snapshot()["combo"] == 1, "A swept player ball deals actual enemy damage and starts its combo")
	_check(sim.damage_by_skill.get("pinball", 0.0) == CombatSim.PINBALL_DAMAGE and sim.skill_hits == 1 and sim.player_velocity.x < 0.0, "Ball damage uses real accounting and an actual enemy reflection")
	sim = _fixture([], _barrel())
	var broke: Array[bool] = []
	sim.crate_hit.connect(func(_point: Vector2, broken: bool) -> void: broke.append(broken))
	var rng_state: int = sim.rng.state
	var shop_state: int = sim.run.rng.state
	_ball(sim)
	sim.step(0.25, Vector2.ZERO)
	_check(not sim.interactions.snapshot()["crates"][0]["active"] and sim.obstacles.is_free(Vector2(800, 360), 16.0), "A real ball breaks the barrel and immediately opens its physical cell")
	_check(broke == [true] and sim.run.kills == 0 and sim.run.xp == 0, "Box breaking dispatches once and never pretends to kill a monster")
	_check(sim.rng.state == rng_state and sim.run.rng.state == shop_state, "A probabilistic crate reward remains independent of both main random streams")
	for enemy_first: bool in [false, true]:
		sim = _fixture([], _barrel())
		enemy = _target(sim, Vector2(720 if enemy_first else 900, 360))
		var shot: CombatSim.Shot = sim.fire_weapon("bone", "", Vector2(640, 360), Vector2.RIGHT)
		shot.velocity = Vector2(1000, 0)
		shot.damage = 100.0
		sim._rebuild_grid()
		sim._update_shots(0.5)
		_check(not shot.active, "The direct shot is consumed by its actual first target")
		_check((enemy.health == 400.0 and sim.interactions.snapshot()["crates"][0]["active"]) if enemy_first else (enemy.health == 500.0 and not sim.interactions.snapshot()["crates"][0]["active"]), "Projectile comparison uses collider entry time across NPC and crate: " + str(enemy_first))
	sim = _fixture([], _barrel())
	sim.player_position = Vector2(700, 360)
	_check(sim.try_hero_skill() and not sim.interactions.snapshot()["crates"][0]["active"], "The independent hero's real arc can break scenery")

func _test_pickups() -> void:
	var sim: CombatSim = _fixture()
	var point: Vector2 = sim.player_position
	for pickup: Dictionary in [{"uid": 1, "kind": "health", "value": 8.0}, {"uid": 2, "kind": "charge", "value": 1.5}, {"uid": 3, "kind": "gold", "value": 3.0}]:
		pickup["position"] = point
		pickup["age"] = 0.0
		sim.interactions._pickups.append(pickup)
	sim._collect_world_pickups()
	_check(sim.run.gold == 3 and sim.interactions.snapshot()["pickups"].size() == 2, "Only useful rewards are consumed; full health and ready skills leave their items")
	sim.run.health = 95.0
	sim.run.backpack.add("skill", "pulse")
	sim.run.backpack.add("skill", "arc_slash")
	sim.run._sync_backpack_projection()
	_check(sim.try_active_skill(0) and sim.try_active_skill(1) and sim.try_hero_skill(), "All three actual skill clocks are running for the charge fixture")
	sim.dash_cooldown_left = 2.0
	sim._collect_world_pickups()
	_check(sim.run.health == 100.0 and sim.interactions.snapshot()["pickups"].is_empty(), "Healing applies only missing health and the useful charge is consumed")
	_check(is_equal_approx(float(sim.active_skill_snapshot(0)["cooldown_remaining"]), 6.5) and is_equal_approx(float(sim.active_skill_snapshot(1)["cooldown_remaining"]), 4.5) and is_equal_approx(float(sim.hero_skill_snapshot()["cooldown_remaining"]), 6.5), "Charge reduces the two owned UID clocks and independent R by actual seconds")
	_check(sim.dash_cooldown_left == 2.0 and sim.run.active_skills.size() == 2, "Charge neither refreshes dash nor grants a third rear slot")
	var uid: int = int(sim.run.active_skills[0]["uid"])
	_check(sim.run.sell_item(uid), "The real charge fixture can sell a companion")
	var sold_remaining: float = float(sim._active_skill_clocks[uid]["remaining"])
	sim._charge_owned_skills(1.5)
	_check(sim._active_skill_clocks[uid]["remaining"] == sold_remaining, "Sold companion clocks do not receive world-item charge")

func _test_sweep_index_matches_linear() -> void:
	var sim: CombatSim = _fixture()
	for index: int in 48:
		var enemy: CombatSim.Enemy = _target(sim, Vector2(80 + (index % 8) * 144, 110 + floori(float(index) / 8.0) * 92))
		enemy.radius = [12.0, 28.0, 64.0, 88.0][index % 4]
	sim._rebuild_grid()
	for start: Vector2 in [Vector2(79.9, 260), Vector2(80, 260), Vector2(80.1, 260), Vector2(400, 400)]:
		for movement: Vector2 in [Vector2(30, 10), Vector2(300, 120), Vector2(-200, -170), Vector2(800, 0)]:
			sim._pinball_grid_active = false
			var expected: Dictionary = sim._pinball_first_hit(start, movement)
			sim._pinball_grid_active = true
			var indexed: Dictionary = sim._pinball_first_hit(start, movement)
			_check(indexed.is_empty() == expected.is_empty(), "The spatial ball query preserves exact hit existence across cell boundaries")
			if not expected.is_empty():
				_check(indexed.get("enemy") == expected.get("enemy") and indexed.get("id", "") == expected.get("id", "") and is_equal_approx(float(indexed["t"]), float(expected["t"])), "Indexed ball sweeps select the same earliest body or wall as the independent full scan")
	sim._pinball_grid_active = false
