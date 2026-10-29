extends SceneTree
## Real wave-eight combat resolves boss points alongside the existing pools and attacks.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_opening_and_priority()
	_test_earliest_projectile_collision()
	_test_separate_uids_and_penetration()
	_test_no_weakpoint_blast_chain()
	_test_actual_skill_and_ball_damage()
	_test_outward_overlap_and_held_contact()
	_test_interrupt_multiplier_and_pool_purity()
	_test_deadline_and_stale_cast()
	_test_summon_caps_and_terminal_cleanup()
	_test_lane_geometry_and_live_window()
	_test_real_arena_placement_and_snapshot_purity()
	print("BossCombat: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _fixture(skills: Array[String] = [], arena: String = "reliquary", clean: bool = true) -> CombatSim:
	var state := RunState.new()
	state.begin(20261030, "bone", arena, "alk")
	for id: String in skills:
		_check(not state.backpack.add("skill", id).is_empty(), "Boss fixture owns the actual backpack skill: " + id)
	state._sync_backpack_projection()
	state.wave = 8
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.invulnerability = 9999.0
	sim._cooldowns.fill(9999.0)
	if clean:
		_configure(sim, [])
	sim.boss.definition = sim.boss.definition.duplicate() as ContentDef
	sim.boss.definition.speed = 0.0
	sim.boss.position = Vector2(640, 360)
	sim.player_position = Vector2(640, 600)
	sim.player_direction = Vector2.UP
	sim.boss_encounter.begin(sim.boss.position, 1.0)
	return sim

func _configure(sim: CombatSim, crates: Array) -> void:
	sim.interactions.configure({"id": "boss_fixture", "obstacles": [], "crates": crates}, 20261030, 8, sim.obstacles)
	sim._crate_indices.clear()
	for crate: Dictionary in sim.interactions.snapshot()["crates"]:
		sim._crate_indices["crate:" + str(crate["id"])] = int(crate["index"])

func _charge(sim: CombatSim) -> void:
	sim.step(BossEncounter.OPENING_SECONDS, Vector2.ZERO)
	_check(sim.boss_encounter_snapshot()["phase"] == "charge" and sim.boss_weakpoints().size() >= 2, "Real wave8 enters its first charge after the1.8second opening")

func _npc(sim: CombatSim, position: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", position)
	enemy.health = 500.0
	enemy.max_health = 500.0
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _shot(sim: CombatSim, origin: Vector2, rune: String = "", damage: float = 5.0) -> CombatSim.Shot:
	var shot: CombatSim.Shot = sim.fire_weapon("bone", rune, origin, Vector2.RIGHT)
	shot.damage = damage
	shot.velocity = Vector2(1000, 0)
	shot.radius = 2.0
	shot.life = 10.0
	return shot

func _fire_step(sim: CombatSim, delta: float = 0.4) -> void:
	sim._rebuild_grid()
	sim._update_shots(delta)

func _break_all(sim: CombatSim) -> void:
	for point: Dictionary in sim.boss_weakpoints():
		_check(bool(sim._damage_boss_weakpoint(point, 10000.0).get("hit", false)), "A real current point accepts accepted boss weakpoint damage")

func _point(sim: CombatSim, uid: int) -> Dictionary:
	for point: Dictionary in sim.boss_encounter.weakpoints_snapshot():
		if int(point["uid"]) == uid:
			return point
	return {}

func _rng(sim: CombatSim) -> Array[int]:
	return [sim.rng.state, sim.run.rng.state]

func _signature(sim: CombatSim) -> String:
	return JSON.stringify([sim.snapshot(), sim.boss_weakpoints(), sim.boss_encounter_snapshot(), sim.interactions.snapshot(), _rng(sim)])

func _test_opening_and_priority() -> void:
	var sim: CombatSim = _fixture(["starfall"])
	_check(sim.run.wave == 8 and sim.boss != null and sim.enemy_count == 1 and sim.boss_encounter_snapshot()["phase"] == "recovery", "Wave8 creates the real boss and opening recovery without fake enemies for points")
	sim.step(BossEncounter.OPENING_SECONDS - STEP, Vector2.ZERO)
	_check(sim.boss_weakpoints().is_empty() and sim.zones.is_empty(), "The opening does not expose charge points one frame early")
	sim.step(STEP, Vector2.ZERO)
	_check(sim.boss_encounter_snapshot()["phase"] == "charge" and sim.boss_weakpoints().size() == 3, "The exact opening boundary creates three real storm points")
	var points: Array[Dictionary] = sim.boss_weakpoints()
	var nearest: Vector2 = points[2]["position"]
	var npc: CombatSim.Enemy = _npc(sim, sim.player_position + Vector2(80, 0))
	var before_rng: Array[int] = _rng(sim)
	sim._rebuild_grid()
	sim._cooldowns.fill(0.0)
	sim._update_weapons(STEP)
	var automatic: CombatSim.Shot
	for shot: CombatSim.Shot in sim.shots:
		if shot.active and not shot.hostile:
			automatic = shot
			break
	_check(automatic != null and automatic.velocity.normalized().dot((nearest - sim.player_position).normalized()) > 0.9999, "The actual automatic weapon aims at a live point before a closer NPC")
	if automatic != null:
		sim._release_shot(automatic)
	sim._cooldowns.fill(9999.0)
	var ember: CombatSim.Shot = sim.fire_weapon("ember", "", sim.player_position, Vector2.RIGHT)
	sim._update_shots(STEP)
	_check(ember.active and ember.velocity.y < 0.0, "Real homing prioritizes a point above the player over the nearer NPC on the right")
	sim._release_shot(ember)
	var origins: Array[Vector2] = []
	sim.active_skill_cast.connect(func(_id: String, _uid: int, origin: Vector2, _direction: Vector2, _affected: int, _rank: int) -> void: origins.append(origin))
	_check(sim.try_active_skill(0) and origins.size() == 1 and origins[0] == nearest, "Actual starfall centers on a priority weakpoint")
	_check(sim.weakpoints_broken == 1 and npc.health == 500.0 and _rng(sim) == before_rng, "Targeting and starfall damage use no RNG or invented NPC damage")
	sim = _fixture()
	_charge(sim)
	points = sim.boss_weakpoints()
	for index: int in 2:
		sim._damage_boss_weakpoint(points[index], 10000.0)
	nearest = points[2]["position"]
	sim.player_position = nearest + Vector2(320, 0)
	_check(sim._starfall_origin(Vector2.RIGHT) == nearest, "A point exactly320pixels away remains inside the established starfall target boundary")

func _test_earliest_projectile_collision() -> void:
	for first: String in ["npc", "crate", "weakpoint"]:
		var sim: CombatSim = _fixture()
		_charge(sim)
		var weak: Dictionary = sim.boss_weakpoints()[0]
		var y: float = (weak["position"] as Vector2).y
		var crate_x: float = 470.0 if first == "crate" else 620.0
		var npc_x: float = 470.0 if first == "npc" else 700.0
		_configure(sim, [{"id": "front_box", "center": Vector2(crate_x, y), "radius": 18.0, "art_id": "barrel", "max_health": 24.0}])
		var npc: CombatSim.Enemy = _npc(sim, Vector2(npc_x, y))
		var shot: CombatSim.Shot = _shot(sim, Vector2(400, y))
		_fire_step(sim)
		var crate: Dictionary = sim.interactions.snapshot()["crates"][0]
		_check(not shot.active, "A nonpiercing shot ends at the earliest physical target: " + first)
		_check(is_equal_approx(npc.health, 495.0 if first == "npc" else 500.0), "NPC damage follows actual TOI against crate and point: " + first)
		_check(is_equal_approx(float(crate["health"]), 19.0 if first == "crate" else 24.0), "Crate damage follows actual TOI against NPC and point: " + first)
		_check(is_equal_approx(float(_point(sim, int(weak["uid"]))["health"]), 19.0 if first == "weakpoint" else 24.0), "Weakpoint damage follows actual TOI against NPC and crate: " + first)

func _test_separate_uids_and_penetration() -> void:
	var sim: CombatSim = _fixture()
	_charge(sim)
	var points: Array[Dictionary] = sim.boss_weakpoints()
	var y: float = (points[0]["position"] as Vector2).y
	var npc: CombatSim.Enemy = _npc(sim, Vector2(680, y))
	_check(npc.uid == int(points[1]["uid"]), "The fixture exercises an actual overlapping NPC and weakpoint numeric UID")
	var shot: CombatSim.Shot = _shot(sim, Vector2(600, y), "pierce")
	_fire_step(sim, 0.22)
	var key: String = "%d:%d" % [points[1]["cast_id"], points[1]["uid"]]
	_check(shot.hit_ids.has(npc.uid) and shot.weakpoint_hit_ids.has(key), "NPC UID and cast-qualified point UID have independent real hit exclusions")
	_check(npc.health == 495.0 and _point(sim, int(points[1]["uid"]))["health"] == 19.0 and sim.primary_hits == 1 and sim.weakpoint_damage == 5.0, "Both independent targets take exactly one accepted hit")
	_check(shot.active and shot.remaining == 0, "The NPC and point consume both real rank1extra hits while preserving the final third-target opportunity")
	sim = _fixture()
	_charge(sim)
	points = sim.boss_weakpoints()
	y = (points[0]["position"] as Vector2).y
	npc = _npc(sim, Vector2(640, y))
	var fourth: CombatSim.Enemy = _npc(sim, Vector2(860, y))
	shot = _shot(sim, Vector2(400, y), "pierce")
	_fire_step(sim, 0.6)
	_check(_point(sim, int(points[0]["uid"]))["health"] == 19.0 and npc.health == 495.0 and _point(sim, int(points[1]["uid"]))["health"] == 19.0 and fourth.health == 500.0, "The real three-target budget hits point1NPCpoint2 and leaves the fourth collinear NPC untouched")
	_check(not shot.active and shot.remaining == 0 and shot.hit_ids.size() == 1 and shot.weakpoint_hit_ids.size() == 2, "Two weakpoint exclusions and one NPC exclusion share a finite budget without extra penetration or UID pollution")

func _test_no_weakpoint_blast_chain() -> void:
	var sim: CombatSim = _fixture()
	_charge(sim)
	var point: Dictionary = sim.boss_weakpoints()[0]
	var position: Vector2 = point["position"]
	var npc: CombatSim.Enemy = _npc(sim, position + Vector2(0, 50))
	var rune_events: Array[int] = [0]
	sim.rune_activated.connect(func(_id: String, _position: Vector2, _incoming: Vector2, _outgoing: Vector2) -> void: rune_events[0] += 1)
	var shot: CombatSim.Shot = _shot(sim, position - Vector2(100, 0), "blast")
	var xp: int = sim.run.xp
	_fire_step(sim, 0.15)
	_check(not shot.active and sim.weakpoint_damage == 5.0 and npc.health == 500.0, "A direct blast-rune projectile can damage the point but creates no secondary NPC explosion")
	_check(rune_events[0] == 0 and sim.secondary_hits == 0 and sim.run.xp == xp and sim.run.kills == 0, "Weakpoint hits neither dispatch rune chains nor award NPC experience or kills")

func _test_actual_skill_and_ball_damage() -> void:
	var sim: CombatSim = _fixture(["pulse"])
	_charge(sim)
	var point: Dictionary = sim.boss_weakpoints()[2]
	sim.player_position = (point["position"] as Vector2) + Vector2(0, 60)
	var before: String = JSON.stringify(sim.boss_encounter.weakpoints_snapshot())
	_check(sim.try_pulse() and JSON.stringify(sim.boss_encounter.weakpoints_snapshot()) == before and sim.weakpoint_damage == 0.0, "Owned zero-damage pulse cannot break or damage a point")
	sim = _fixture(["starfall", "arc_slash"])
	_charge(sim)
	_check(sim.try_active_skill(0) and sim.weakpoints_broken == 1, "Q's real damage skill breaks its selected point")
	point = sim.boss_weakpoints()[0]
	sim.player_position = (point["position"] as Vector2) - Vector2(100, 0)
	sim.player_direction = Vector2.RIGHT
	_check(sim.try_active_skill(1) and sim.weakpoints_broken == 2, "E's real arc geometry and positive damage break another point")
	sim = _fixture()
	_charge(sim)
	point = sim.boss_weakpoints()[2]
	sim.player_position = (point["position"] as Vector2) + Vector2(0, 70)
	sim.player_direction = Vector2.UP
	_check(sim.try_hero_skill() and sim.hero_skill_snapshot()["uses"] == 1 and sim.weakpoints_broken == 1, "R uses the selected hero's actual cast geometry and damage against a point")
	sim = _fixture()
	_charge(sim)
	point = sim.boss_weakpoints()[0]
	sim._explode(point["position"], 9.0, "ember", {}, 30.0)
	_check(sim.weakpoint_damage == 9.0 and _point(sim, int(point["uid"]))["health"] == 15.0, "A genuine area explosion independently damages a point without inventing a direct projectile hit")
	sim = _fixture()
	_charge(sim)
	point = sim.boss_weakpoints()[2]
	sim.player_position = (point["position"] as Vector2) + Vector2(0, 80)
	sim._begin_pinball(Vector2.DOWN * CombatSim.PINBALL_SPEED, Vector2.DOWN)
	sim.step(0.2, Vector2.ZERO)
	_check(sim.weakpoints_broken == 1 and sim.pinball_snapshot()["combo"] == 1 and sim.player_velocity.y > 0.0, "The swept player ball deals real point damage and reflects rather than passing through")

func _test_outward_overlap_and_held_contact() -> void:
	var sim: CombatSim = _fixture()
	_charge(sim)
	var points: Array[Dictionary] = sim.boss_weakpoints()
	var first: Dictionary = points[0]
	var second: Dictionary = points[1]
	var start: Vector2 = (first["position"] as Vector2) + Vector2(14, 0)
	var impact: Dictionary = sim._pinball_first_hit(start, Vector2(260, 0))
	_check(impact.has("weakpoint") and int(impact["weakpoint"]["uid"]) == int(second["uid"]), "An outward-overlapping pointA cannot hide the forward swept pointB")
	sim.player_position = start
	sim._begin_pinball(Vector2.LEFT * CombatSim.PINBALL_SPEED, Vector2.LEFT)
	sim.step(0.4, Vector2.ZERO)
	_check(_point(sim, int(first["uid"]))["health"] == 24.0 and not _point(sim, int(second["uid"]))["active"] and sim.player_velocity.x < 0.0, "The actual outgoing ball leaves pointA untouched then damages and reflects from pointB")
	sim = _fixture()
	_charge(sim)
	var held: Vector2 = sim.boss.position
	sim.player_position = held + Vector2(0, 20)
	sim.invulnerability = 0.0
	var health: float = sim.run.health
	sim.step(STEP, Vector2.ZERO)
	_check(sim.run.health < health and sim.boss.position == held and sim.boss.velocity == Vector2.ZERO, "Real contact during charge damages the player without recoiling the held boss")
	_break_all(sim)
	sim.invulnerability = 0.0
	health = sim.run.health
	sim.step(STEP, Vector2.ZERO)
	_check(sim.run.health < health and sim.boss.position == held and sim.boss.velocity == Vector2.ZERO, "Break vulnerability also keeps the boss anchored under actual player contact")

func _test_interrupt_multiplier_and_pool_purity() -> void:
	var sim: CombatSim = _fixture()
	_charge(sim)
	var npc: CombatSim.Enemy = _npc(sim, Vector2(1800, 500))
	var counts: Array[int] = [sim.enemy_count, sim._enemy_free.size(), sim.run.xp, sim.run.kills, sim.soul_count]
	var random_state: Array[int] = _rng(sim)
	var interrupts: Array[int] = [0]
	sim.boss_interrupted.connect(func(_position: Vector2) -> void: interrupts[0] += 1)
	_break_all(sim)
	_check(sim.boss_encounter_snapshot()["phase"] == "break" and sim.boss_interrupts == 1 and interrupts[0] == 1 and sim.boss_weakpoints().is_empty(), "All real points break the current cast and publish one interruption")
	_check([sim.enemy_count, sim._enemy_free.size(), sim.run.xp, sim.run.kills, sim.soul_count] == counts and _rng(sim) == random_state, "Points consume no NPC slots, XP, kills, souls or either RNG stream")
	_check(sim.weakpoints_broken == 3 and sim.weakpoint_damage == 72.0 and sim.boss.health == sim.boss.max_health, "Point damage has separate accepted accounting and cannot directly remove boss HP")
	var health: float = sim.boss.health
	sim.apply_damage(sim.boss, 10.0, "bone")
	sim.apply_damage(npc, 10.0, "bone")
	_check(is_equal_approx(health - sim.boss.health, 13.5) and npc.health == 490.0, "The1.35break vulnerability applies exclusively to the boss")
	sim.step(BossEncounter.BREAK_SECONDS, Vector2.ZERO)
	health = sim.boss.health
	sim.apply_damage(sim.boss, 10.0, "bone")
	_check(is_equal_approx(health - sim.boss.health, 10.0) and sim.boss_encounter_snapshot()["phase"] == "recovery", "The exact break expiry removes vulnerability before recovery damage")
	_check(sim.zones.is_empty(), "An interrupted current charge never publishes its canceled hostile geometry")

func _test_deadline_and_stale_cast() -> void:
	var sim: CombatSim = _fixture()
	_charge(sim)
	var points: Array[Dictionary] = sim.boss_weakpoints()
	for index: int in 2:
		sim._damage_boss_weakpoint(points[index], 10000.0)
	sim.player_position = (points[2]["position"] as Vector2) + Vector2(0, 60)
	sim.player_direction = Vector2.UP
	sim.step(float(sim.boss_encounter_snapshot()["charge_left"]) - STEP, Vector2.ZERO)
	_check(sim.boss_encounter_snapshot()["phase"] == "charge" and sim.boss_weakpoints().size() == 1, "A real final living point remains available on the penultimate cast frame")
	sim.step(STEP, Vector2.ZERO, false, false, [], true)
	_check(sim.boss_interrupts == 1 and sim.boss_encounter_snapshot()["phase"] == "break" and sim.zones.is_empty(), "The deadline frame accepts actual R damage before releasing the pending attack")
	var old: Dictionary = points[2].duplicate(true)
	sim._advance_boss_encounter(BossEncounter.BREAK_SECONDS + BossEncounter.AFTER_BREAK_RECOVERY_SECONDS)
	var current: Dictionary = sim.boss_encounter_snapshot()
	var damage: float = sim.weakpoint_damage
	_check(current["phase"] == "charge" and int(current["cast_id"]) > int(old["cast_id"]), "A subsequent real cast owns a distinct cast identity")
	_check(not bool(sim._damage_boss_weakpoint(old, 10000.0).get("hit", false)) and sim.weakpoint_damage == damage, "A stale point record cannot damage or interrupt the new cast")
	_check(not sim.try_hero_skill() and not sim.try_hero_skill("hanabi"), "The previous R cooldown and selected hero identity still reject stale recasts")

func _release(sim: CombatSim) -> void:
	sim._advance_boss_encounter(float(sim.boss_encounter_snapshot()["charge_left"]))
	sim._dispatch_boss_events(sim.boss_encounter.finish_friendly_step())

func _summon_once(sim: CombatSim) -> void:
	if sim.boss_encounter_snapshot()["phase"] != "charge":
		sim._advance_boss_encounter(BossEncounter.RECOVERY_SECONDS)
	for _attempt: int in 5:
		if sim.boss_encounter_snapshot()["attack_id"] == "spirit_chorus":
			_release(sim)
			return
		_release(sim)
		sim._advance_boss_encounter(BossEncounter.RECOVERY_SECONDS)
	_check(false, "The actual boss sequence must reach spirit chorus")

func _ghost_count(sim: CombatSim) -> int:
	var result: int = 0
	for enemy: CombatSim.Enemy in sim.enemies:
		result += int(enemy.active and enemy.boss_ghost)
	return result

func _test_summon_caps_and_terminal_cleanup() -> void:
	var sim: CombatSim = _fixture()
	_charge(sim)
	for iteration: int in 3:
		var random_state: Array[int] = _rng(sim)
		_summon_once(sim)
		_check(_ghost_count(sim) == mini(4, (iteration + 1) * 2), "Real phase1 chorus respects the total four-ghost cap across casts")
		_check(_rng(sim) == random_state, "Authored phase1ghost spawns use deterministic timers and preserve both RNG streams")
	_check(sim.enemy_count == 5 and sim._enemy_free.size() == CombatSim.ENEMY_LIMIT - 5, "Ghosts occupy genuine bounded NPC slots while points do not")
	sim.boss.health = sim.boss.max_health * 0.4
	for iteration: int in 2:
		var random_state: Array[int] = _rng(sim)
		_summon_once(sim)
		_check(_ghost_count(sim) == 6, "Phase2 respects a total six-ghost cap including phase1 survivors")
		_check(_rng(sim) == random_state, "Phase2summons and cap refusals preserve combat and store RNG")
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active and enemy.boss_ghost:
			_check(enemy.boss_cast_id > 0 and is_equal_approx(enemy.damage_scale, 0.75) and sim.obstacles.is_free(enemy.position, enemy.radius), "Summons retain their actual cast identity, scaling and safe spawn position")
	var npc: CombatSim.Enemy = _npc(sim, Vector2(1900, 700))
	sim.apply_damage(sim.boss, sim.boss.health + 1000.0, "bone")
	_check(sim.complete and sim.victory and _ghost_count(sim) == 0 and not sim.boss_encounter_snapshot()["running"], "Killing the real boss stops its FSM and retires every summoned ghost")
	_check(npc.active and sim.enemy_count == 1 and sim._enemy_free.size() == CombatSim.ENEMY_LIMIT - 1, "Terminal ghost cleanup preserves ordinary NPC slots and returns each ghost slot exactly once")
	var free_count: int = sim._enemy_free.size()
	sim._finish(false, "duplicate")
	_check(sim._enemy_free.size() == free_count and sim.victory, "Repeated terminal cleanup cannot duplicate pool entries or rewrite victory")
	sim = _fixture()
	_charge(sim)
	_summon_once(sim)
	sim._finish(false, "fixture loss")
	_check(sim.complete and not sim.victory and _ghost_count(sim) == 0 and sim.boss_weakpoints().is_empty(), "Loss also clears all boss summons and weakpoint availability")

func _lane() -> CombatSim.WarningZone:
	var zone := CombatSim.WarningZone.new()
	zone.shape = "lane"
	zone.position = Vector2(400, 250)
	zone.direction = Vector2.RIGHT
	zone.length = 300.0
	zone.width = 100.0
	zone.delay = 0.2
	zone.duration = 0.45
	zone.damage = 16.0
	zone.source_cast_id = 1
	return zone

func _test_lane_geometry_and_live_window() -> void:
	var lane: CombatSim.WarningZone = _lane()
	_check(CombatSim.zone_contains(lane, Vector2(400, 200), 0.0) and CombatSim.zone_contains(lane, Vector2(700, 300), 0.0), "Lane geometry includes its exact square start/end corners")
	_check(not CombatSim.zone_contains(lane, Vector2(700.01, 250), 0.0) and not CombatSim.zone_contains(lane, Vector2(550, 300.01), 0.0), "Lane centers immediately beyond either square bound remain outside")
	_check(CombatSim.zone_contains(lane, Vector2(707, 307), 10.0) and not CombatSim.zone_contains(lane, Vector2(708, 308), 10.0), "Player-radius padding uses true distance to a rectangle corner rather than an inflated square or capsule")
	var sim: CombatSim = _fixture()
	sim.invulnerability = 0.0
	sim.player_position = Vector2(100, 100)
	sim.zones.append(lane)
	var health: float = sim.run.health
	sim._update_zones(0.2)
	_check(lane.triggered and sim.run.health == health, "The lane can become active while the player is outside")
	sim.player_position = Vector2(550, 250)
	sim._update_zones(0.1)
	_check(sim.run.health == health - 16.0 and sim.run.last_hit["kind"] == "ritual", "Entering during the live lane window causes actual ritual damage")
	sim.invulnerability = 0.0
	health = sim.run.health
	sim._update_zones(0.5)
	_check(sim.run.health == health and sim.zones.is_empty(), "An expired triggered lane cannot deal late damage")
	sim = _fixture()
	sim.invulnerability = 0.0
	sim.player_position = Vector2(550, 250)
	sim.zones.append(_lane())
	health = sim.run.health
	sim._update_zones(1.0)
	_check(sim.run.health == health and sim.zones.is_empty(), "A large step past an untriggered lane's entire live window cannot invent a retroactive hit")

func _test_real_arena_placement_and_snapshot_purity() -> void:
	for arena: String in ArenaCatalog.IDS:
		for ratio: float in [1.0, 0.4]:
			for location: Vector2 in [Vector2(-1000, -450), Vector2(640, 208), Vector2(2040, 960)]:
				var sim: CombatSim = _fixture([], arena, false)
				_check(sim.obstacles.snapshot().size() == 24, "Every actual authored map retains its24ground colliders during boss placement: " + arena)
				sim.boss.position = sim.obstacles.free_point(location, sim.boss.radius)
				sim.boss.health = sim.boss.max_health * ratio
				sim.boss_encounter.begin(sim.boss.position, ratio)
				var random_state: Array[int] = _rng(sim)
				_charge(sim)
				var points: Array[Dictionary] = sim.boss_weakpoints()
				for point: Dictionary in points:
					_check(sim.obstacles.is_free(point["position"], float(point["radius"]) + 4.0), "A relocated living point is outside static props, crates and bumpers: " + arena)
					for other: Dictionary in points:
						if int(point["uid"]) != int(other["uid"]):
							_check((point["position"] as Vector2).distance_to(other["position"]) >= BossEncounter.WEAKPOINT_RADIUS * 2.0 + 4.0, "Relocation preserves distinct nonoverlapping attackable point circles")
				var signature: String = _signature(sim)
				var snapshot: Dictionary = sim.boss_encounter_snapshot()
				var copied: Array = snapshot["weakpoints"]
				if not copied.is_empty():
					copied[0]["health"] = -1000.0
					copied[0]["position"] = Vector2.INF
				for query: int in 5:
					sim.snapshot()
					sim.boss_weakpoints()
					sim.boss_encounter_snapshot()
				_check(_signature(sim) == signature and _rng(sim) == random_state, "Snapshots are defensive and actual point placement plus repeated UI queries consume neither RNG")
