extends SceneTree
## Confirmation requires a real damage interception and never changes the dash outcome.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_contact()
	_test_projectile_and_ritual()
	_test_no_hit()
	_test_once_per_dash()
	_test_invalid_damage_and_origin()
	_test_original_protection()
	_test_vulnerable_tail()
	_test_lifecycle_and_invariants()
	print("DashEvasion: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _sim(arena: String = "reliquary") -> CombatSim:
	var state := RunState.new()
	state.begin(20261028, "bone", arena)
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim

func _events(sim: CombatSim) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	sim.dash_evaded.connect(func(point: Vector2, origin: Vector2, source_id: String, kind: String) -> void:
		events.append({"position": point, "origin": origin, "source_id": source_id, "kind": kind}))
	return events

func _still_enemy(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _hostile(sim: CombatSim, point: Vector2) -> CombatSim.Shot:
	sim._hostile_shot(point, Vector2(1500, 0), 8.0, "caster")
	for shot: CombatSim.Shot in sim.shots:
		if shot.active and shot.hostile:
			return shot
	return null

func _ritual(sim: CombatSim, point: Vector2) -> CombatSim.WarningZone:
	var zone := CombatSim.WarningZone.new()
	zone.position = point
	zone.radius = 24.0
	zone.delay = STEP * 0.5
	zone.damage = 16.0
	zone.source_id = "boss"
	sim.zones.append(zone)
	return zone

func _outcome(sim: CombatSim) -> Array:
	return [
		sim.player_position, sim.player_velocity, sim.player_direction,
		sim.dash_time_left, sim.dash_cooldown_left, sim.dash_direction,
		sim.dash_invulnerability_left, sim.dashes_used, sim.invulnerability,
		sim.run.health, sim.run.gold, sim.run.xp, sim.run.kills,
		sim.run.damage_taken, sim.run.hits_taken, sim.run.last_hit.duplicate(true),
		sim.damage_by_weapon.duplicate(true), sim.run.damage_dealt_by_weapon.duplicate(true),
		sim.rng.state, sim.run.rng.state, sim.effects.size(),
	]

func _test_contact() -> void:
	for arena: String in ArenaCatalog.IDS:
		var sim: CombatSim = _sim(arena)
		var events: Array[Dictionary] = _events(sim)
		var enemy: CombatSim.Enemy = _still_enemy(sim, sim.player_position + Vector2(19, 0))
		var contact_origin: Vector2 = enemy.position
		sim.step(STEP, Vector2.RIGHT, true)
		_check(events.size() == 1 and sim.dash_evaded_current and sim.dash_evades == 1, "Actual protected contact confirms the dash in " + arena)
		if events.size() == 1:
			_check(events[0] == {"position": sim.player_position, "origin": contact_origin, "source_id": "chaser", "kind": "contact"}, "Contact confirmation reports the actual player and attacker positions")
		_check(enemy.position == contact_origin and sim.run.health == 100.0 and sim.run.hits_taken == 0 and sim.invulnerability == 0.0, "Confirmed contact causes neither damage, recoil nor new hit protection")
		var before: Array = _outcome(sim)
		sim._update_enemies(STEP)
		_check(events.size() == 1 and sim.dash_evades == 1 and _outcome(sim) == before, "Repeated overlapping contact neither confirms twice nor changes gameplay state")
		_check(sim.dash_snapshot()["evaded"] and sim.dash_snapshot()["evades"] == 1 and sim.snapshot()["dash"] == sim.dash_snapshot(), "Both snapshot paths expose the confirmed dash and cumulative count")

func _test_projectile_and_ritual() -> void:
	var sim: CombatSim = _sim()
	var events: Array[Dictionary] = _events(sim)
	sim.step(STEP, Vector2.RIGHT, true)
	var shot: CombatSim.Shot = _hostile(sim, sim.player_position + Vector2(-25, 0))
	sim.step(STEP, Vector2.ZERO)
	_check(not shot.active and events.size() == 1 and sim.dash_evades == 1, "An actual intercepted hostile projectile confirms the evasion and is consumed")
	if events.size() == 1:
		_check(events[0] == {"position": sim.player_position, "origin": shot.position, "source_id": "caster", "kind": "projectile"}, "Projectile confirmation preserves the real attack metadata")
	_check(sim.run.health == 100.0 and sim.run.damage_taken == 0.0 and sim.invulnerability == 0.0, "Projectile confirmation grants no damage or extra hit protection")
	sim = _sim()
	events = _events(sim)
	sim.step(STEP, Vector2.RIGHT, true)
	var zone: CombatSim.WarningZone = _ritual(sim, sim.player_position)
	sim.step(STEP, Vector2.ZERO)
	_check(zone.triggered and events.size() == 1 and sim.dash_evades == 1, "An actual overlapping ritual detonation confirms the evasion")
	if events.size() == 1:
		_check(events[0] == {"position": sim.player_position, "origin": zone.position, "source_id": "boss", "kind": "ritual"}, "Ritual confirmation preserves its actual source and position")
	_check(sim.run.health == 100.0 and sim.run.hits_taken == 0 and sim.invulnerability == 0.0, "A confirmed ritual still causes no player damage or extra protection")

func _test_no_hit() -> void:
	var sim: CombatSim = _sim()
	var events: Array[Dictionary] = _events(sim)
	_still_enemy(sim, sim.player_position + Vector2(120, 0))
	var shot: CombatSim.Shot = _hostile(sim, sim.player_position + Vector2(-25, -120))
	var zone: CombatSim.WarningZone = _ritual(sim, sim.player_position + Vector2(0, -120))
	sim.step(STEP, Vector2.RIGHT, true)
	_check(shot.active and zone.triggered and events.is_empty() and sim.dash_evades == 0 and not sim.dash_evaded_current, "Nearby contact, a passing projectile and a missed ritual do not confirm an evasion")
	_check(sim.run.health == 100.0 and not sim.dash_snapshot()["evaded"] and sim.dash_snapshot()["evades"] == 0, "Starting a dash without an interception leaves the success state empty")
	for arena: String in ArenaCatalog.IDS:
		sim = _sim(arena)
		events = _events(sim)
		var origin: Vector2 = sim.player_position
		for frame: int in 12:
			sim.step(STEP, Vector2.RIGHT, frame == 0)
		_check(sim.player_position.distance_to(origin + Vector2(132, 0)) < 0.003 and events.is_empty() and sim.dash_evades == 0, "An empty dash retains its original distance without a success event in " + arena)

func _test_once_per_dash() -> void:
	var sim: CombatSim = _sim()
	var events: Array[Dictionary] = _events(sim)
	sim.step(STEP, Vector2.RIGHT, true)
	var enemy: CombatSim.Enemy = _still_enemy(sim, sim.player_position + Vector2(8, 0))
	sim._update_enemies(STEP)
	var shot: CombatSim.Shot = _hostile(sim, sim.player_position + Vector2(-25, 0))
	var zone: CombatSim.WarningZone = _ritual(sim, sim.player_position)
	sim._update_shots(STEP)
	sim._update_zones(STEP)
	_check(not shot.active and zone.triggered and events.size() == 1 and sim.dash_evades == 1, "Three real attack paths in one protected dash produce exactly one confirmation")
	_check(sim.run.health == 100.0 and enemy.position == sim.player_position + Vector2(8, 0), "Suppressing duplicate confirmation preserves protection and contact recoil rules")
	sim._try_start_dash(Vector2.LEFT)
	_check(sim.dash_evaded_current and sim.dash_evades == 1 and sim.dashes_used == 1, "A rejected cooldown request cannot clear the current dash result")
	enemy.active = false
	sim.step(2.4, Vector2.ZERO)
	_check(sim.dash_snapshot()["ready"] and sim.dash_evaded_current and sim.dash_evades == 1, "The completed dash retains its result until a new activation")
	sim.step(STEP, Vector2.LEFT, true)
	_check(not sim.dash_evaded_current and sim.dash_evades == 1 and events.size() == 1, "A new dash resets its local success flag without erasing the cumulative count")
	zone = _ritual(sim, sim.player_position)
	sim._update_zones(STEP)
	_check(zone.triggered and events.size() == 2 and sim.dash_evaded_current and sim.dash_evades == 2, "The next deliberate dash can confirm one new actual evasion")

func _test_invalid_damage_and_origin() -> void:
	var sim: CombatSim = _sim()
	var events: Array[Dictionary] = _events(sim)
	sim.step(STEP, Vector2.RIGHT, true)
	var before: Array = _outcome(sim)
	for amount: float in [0.0, -1.0, INF, -INF, NAN]:
		sim._hurt_player(amount, "caster", "projectile")
		_check(events.is_empty() and sim.dash_evades == 0 and not sim.dash_evaded_current and _outcome(sim) == before, "Zero, negative and nonfinite blocked damage cannot create success or alter the protected player")
	sim._hurt_player(8.0, "caster", "projectile")
	_check(events.size() == 1 and sim.dash_evades == 1 and _outcome(sim) == before, "A later finite positive interception still confirms without gameplay side effects")
	for origin: Vector2 in [Vector2.INF, Vector2(NAN, 0), Vector2(0, -INF), Vector2(420, 300)]:
		sim = _sim()
		events = _events(sim)
		sim.step(STEP, Vector2.RIGHT, true)
		sim._hurt_player(3.0, "boss", "ritual", origin)
		var expected: Vector2 = origin if origin.is_finite() else sim.player_position
		_check(events.size() == 1 and events[0]["origin"] == expected and events[0]["position"] == sim.player_position, "Signal origins preserve finite attack positions and fall back to the player for invalid positions")

func _test_original_protection() -> void:
	var sim: CombatSim = _sim()
	var events: Array[Dictionary] = _events(sim)
	sim.invulnerability = 0.03
	var enemy: CombatSim.Enemy = _still_enemy(sim, sim.player_position + Vector2(19, 0))
	var origin: Vector2 = enemy.position
	sim.step(STEP, Vector2.RIGHT, true)
	sim._hurt_player(8.0, "caster", "projectile")
	_check(sim.invulnerability > 0.0 and sim.dash_invulnerability_left > 0.0 and events.is_empty() and sim.dash_evades == 0, "Existing hit protection takes priority over overlapping dash protection for every incoming attack")
	_check(enemy.position == origin and sim.run.health == 100.0, "Overlapping protection still prevents contact recoil and damage")
	sim.step(STEP, Vector2.ZERO)
	_check(sim.invulnerability == 0.0 and events.size() == 1 and sim.dash_evades == 1, "An actual contact after old protection expires can confirm while the original dash shield remains")
	sim = _sim()
	events = _events(sim)
	sim.invulnerability = 0.5
	sim.step(STEP, Vector2.RIGHT, true)
	var shot: CombatSim.Shot = _hostile(sim, sim.player_position + Vector2(-25, 0))
	var zone: CombatSim.WarningZone = _ritual(sim, sim.player_position)
	sim.step(STEP, Vector2.ZERO)
	_check(not shot.active and zone.triggered and events.is_empty() and sim.dash_evades == 0 and sim.run.health == 100.0, "Real projectile and ritual interceptions under old hit protection do not confirm a dash evasion")
	sim = _sim()
	events = _events(sim)
	sim.invulnerability = 0.5
	_still_enemy(sim, sim.player_position + Vector2(8, 0))
	sim.step(STEP, Vector2.ZERO)
	sim._hurt_player(8.0, "caster", "projectile")
	_check(events.is_empty() and sim.dash_evades == 0 and sim.run.health == 100.0, "Ordinary hit protection without a dash never emits success")

func _test_vulnerable_tail() -> void:
	for kind: String in ["contact", "projectile", "ritual"]:
		var sim: CombatSim = _sim()
		var events: Array[Dictionary] = _events(sim)
		for frame: int in 8:
			sim.step(STEP, Vector2.RIGHT, frame == 0)
		_check(sim.dash_time_left > 0.0 and sim.dash_invulnerability_left == 0.0, "The damage fixture targets the original vulnerable tail rather than the short shield")
		if kind == "contact":
			_still_enemy(sim, sim.player_position + Vector2(19, 0))
		elif kind == "projectile":
			_hostile(sim, sim.player_position + Vector2(-25, 0))
		else:
			_ritual(sim, sim.player_position)
		sim.step(STEP, Vector2.ZERO)
		_check(sim.run.health < 100.0 and sim.run.hits_taken == 1 and sim.run.last_hit["kind"] == kind and is_equal_approx(sim.invulnerability, 0.7), "The vulnerable dash tail retains ordinary damage and received-hit protection: " + kind)
		_check(events.is_empty() and sim.dash_evades == 0 and not sim.dash_evaded_current, "A real vulnerable-tail hit cannot falsely confirm an evasion: " + kind)

func _test_lifecycle_and_invariants() -> void:
	var sim: CombatSim = _sim()
	var events: Array[Dictionary] = _events(sim)
	sim.step(STEP, Vector2.RIGHT, true)
	var before: Array = _outcome(sim)
	sim._hurt_player(8.0, "caster", "projectile", sim.player_position - Vector2(20, 0))
	_check(events.size() == 1 and _outcome(sim) == before, "A confirmation consumes neither RNG stream and changes no movement, timer, health, reward, damage or effect state")
	_check(DashRules.DURATION == 0.2 and DashRules.SPEED == 660.0 and DashRules.COOLDOWN == 2.4 and DashRules.INVULNERABILITY == 0.12, "Confirmation leaves the original dash parameters unchanged")
	var state := RunState.new()
	state.begin(20261029, "ember", "glacier")
	sim.begin(state)
	_check(not sim.dash_evaded_current and sim.dash_evades == 0 and not sim.dash_snapshot()["evaded"] and sim.dash_snapshot()["evades"] == 0, "Beginning another wave resets both local and cumulative evasion state")
	sim = _sim()
	events = _events(sim)
	sim.step(STEP, Vector2.RIGHT, true)
	sim._finish(true, "terminal evasion fixture")
	before = _outcome(sim)
	sim._hurt_player(8.0, "caster", "projectile")
	sim.step(STEP, Vector2.LEFT, true)
	_check(events.is_empty() and sim.dash_evades == 0 and _outcome(sim) == before, "Terminal simulations neither confirm attacks nor advance the stopped skill")
	sim = _sim()
	events = _events(sim)
	sim.step(STEP, Vector2.RIGHT, true)
	sim.run.health = 0.0
	sim._hurt_player(8.0, "caster", "projectile")
	_check(events.is_empty() and sim.dash_evades == 0 and sim.run.health == 0.0, "A dead player cannot produce a late evasion confirmation")
