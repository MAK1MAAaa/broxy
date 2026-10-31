extends SceneTree
## Equipment forecasts describe each real projectile and preserve every rune identity.

const STEP: float = 1.0 / 60.0
const RUNES: Array[String] = ["pierce", "bounce", "blast"]

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_resource_contract()
	_test_inventory_matrix()
	_test_invalid_queries()
	_test_slot_identity()
	_test_real_pierce_and_bounce()
	_test_real_blast()
	print("RuneEquipPreview: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _buy(state: RunState, kind: String, id: String) -> bool:
	var definition: ContentDef = GameCatalog.rune(id) if kind == "rune" else GameCatalog.weapon(id)
	state.offers = [{"kind": kind, "id": id, "price": definition.price, "sold": false}]
	return state.buy_offer(0)

func _fixture(weapon: String, incoming: String, previous: String = "", full: bool = false) -> RunState:
	var state: RunState = RunState.new()
	state.begin(20261023, weapon)
	state.collect_souls(1000)
	if not previous.is_empty():
		_check(_buy(state, "rune", previous) and state.equip_rune(0, 0), "Fixture legally equips the original rune")
	if full:
		for index: int in range(36):
			var snapshot: Dictionary = state.backpack_snapshot()
			if int(snapshot["total_cells"]) - int(snapshot["used_cells"]) <= 1:
				break
			_check(_buy(state, "rune", RUNES[index % RUNES.size()]), "Fixture legally fills every reserve cell except the incoming rune's final cell")
	_check(_buy(state, "rune", incoming), "Fixture legally acquires the selected rune")
	if full:
		_check(state.backpack_snapshot()["used_cells"] == state.backpack_snapshot()["total_cells"], "The full replacement matrix uses a genuinely full backpack")
	state.upgrade_choices()
	state.last_error = "保留原错误"
	return state

func _snapshot(state: RunState) -> Dictionary:
	return {
		"summary": state.summary(), "backpack": state.backpack_snapshot(), "offers": state.offers.duplicate(true), "rng": state.rng.state,
		"rng_seed": state.rng.seed, "uid": state._next_rune_uid, "error": state.last_error,
		"bonuses": state._upgrade_bonuses.duplicate(true), "choices": state._upgrade_options.duplicate(true),
		"income": state._wave_income, "settled": state._wave_finished, "rerolls": state.rerolls,
	}

func _uids(state: RunState) -> Array[int]:
	var result: Array[int] = []
	for rune: Dictionary in state.rune_bag:
		result.append(int(rune["uid"]))
	for weapon: Dictionary in state.loadout:
		var rune: Dictionary = weapon.get("rune", {})
		if not rune.is_empty():
			result.append(int(rune["uid"]))
	result.sort()
	return result

func _query(state: RunState, bag_index: int, weapon_index: int = 0) -> Dictionary:
	var before: Dictionary = _snapshot(state)
	var emissions: Array[int] = [0]
	var observe: Callable = func() -> void: emissions[0] += 1
	state.changed.connect(observe)
	var preview: Dictionary = state.rune_equip_preview(bag_index, weapon_index)
	_check(state.rune_equip_preview(bag_index, weapon_index) == preview and _snapshot(state) == before and emissions[0] == 0, "Repeated equipment previews preserve state, RNG, rune UID, old error and changed signal")
	state.changed.disconnect(observe)
	return preview

func _test_resource_contract() -> void:
	_check(RuneRules.EXTRA_HITS == 2 and RuneRules.BOUNCE_RANGE == 230.0 and RuneRules.BOUNCE_DAMAGE_FACTOR == 0.75 and RuneRules.BLAST_RADIUS == 68.0 and RuneRules.BLAST_DAMAGE_FACTOR == 0.55, "Central rules retain the shipped numeric behavior")
	_check(GameCatalog.rune("pierce").amount == RuneRules.EXTRA_HITS and GameCatalog.rune("bounce").amount == RuneRules.EXTRA_HITS, "Rune resources advertise the real additional-hit budget")
	_check(GameCatalog.rune("bounce").range == RuneRules.BOUNCE_RANGE and GameCatalog.rune("blast").amount == RuneRules.BLAST_RADIUS and GameCatalog.rune("blast").damage == RuneRules.BLAST_DAMAGE_FACTOR, "Rune resource range and splash multiplier match the real dispatcher")

func _test_inventory_matrix() -> void:
	for weapon: ContentDef in GameCatalog.weapons():
		for incoming: String in RUNES:
			for previous: String in ["", "pierce", "bounce", "blast"]:
				for full: bool in [false, true]:
					var state: RunState = _fixture(weapon.id, incoming, previous, full)
					var oracle: RunState = _fixture(weapon.id, incoming, previous, full)
					var selected: int = state.rune_bag.size() - 1
					var before: Dictionary = _snapshot(state)
					var preview: Dictionary = _query(state, selected)
					var label: String = "%s/%s/old=%s/full=%s" % [weapon.id, incoming, previous, full]
					_check(preview["weapon_index"] == 0 and preview["weapon_id"] == weapon.id and preview["rune_id"] == incoming and preview["shots"] == weapon.shots, "Preview identifies the exact destination and independent volley size: " + label)
					_check(preview["incoming_rune"] == state.rune_bag[selected] and preview["returned_rune"] == state.loadout[0]["rune"], "Incoming and returned records preserve paid price and UID: " + label)
					_check(is_equal_approx(float(preview["damage"]), state.weapon_damage(state.loadout[0])) and is_equal_approx(float(preview["resonance_bonus"]), float(state.loadout[0].get("resonance_bonus", 0.0))), "Rune preview includes current actual weapon damage and local resonance: " + label)
					var expected_bag: Array[Dictionary] = state.rune_bag.duplicate(true)
					expected_bag.remove_at(selected)
					if not previous.is_empty():
						expected_bag.append(state.loadout[0]["rune"].duplicate(true))
					expected_bag.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first["uid"]) < int(second["uid"]))
					_check(preview["bag_before"] == state.rune_bag.size() and preview["bag_after"] == expected_bag.size(), "Full-bag replacement stays full while an empty socket frees one reserve slot: " + label)
					_check(preview["innate_pierce"] == weapon.innate_pierce and preview["trigger_hit"] == 1 + weapon.innate_pierce and preview["max_direct_targets"] == 1 + weapon.innate_pierce + (0 if incoming == "blast" else RuneRules.EXTRA_HITS), "Per-projectile trigger and theoretical target limit include native penetration: " + label)
					var scales: Array[float] = []
					if incoming == "bounce":
						for hit: int in 1 + weapon.innate_pierce:
							scales.append(1.0)
						for jump: int in range(1, RuneRules.EXTRA_HITS + 1):
							scales.append(pow(RuneRules.BOUNCE_DAMAGE_FACTOR, jump))
					_check(preview["bounce_scales"] == scales and preview["bounce_range"] == (RuneRules.BOUNCE_RANGE if incoming == "bounce" else 0.0), "Only bounce exposes its actual decay sequence and search range: " + label)
					_check(preview["blast_radius"] == (RuneRules.BLAST_RADIUS if incoming == "blast" else 0.0) and preview["blast_multiplier"] == (RuneRules.BLAST_DAMAGE_FACTOR if incoming == "blast" else 0.0), "Only blast exposes its actual splash extent and damage multiplier: " + label)
					var incoming_cell: Dictionary = oracle.backpack_item(int(preview["incoming_rune"]["uid"]))
					_check(oracle.equip_rune(selected, 0) and oracle.loadout[0]["rune"] == preview["incoming_rune"] and oracle.rune_bag == expected_bag and oracle.rune_bag.size() == int(preview["bag_after"]), "Forecast matches the independent real transaction including stable UID order: " + label)
					if not previous.is_empty():
						var restored: Dictionary = oracle.backpack_item(int(preview["returned_rune"]["uid"]))
						_check(restored["x"] == incoming_cell["x"] and restored["y"] == incoming_cell["y"], "Replacement returns the previous rune to the exact cell vacated by its incoming UID: " + label)
					_check(_uids(oracle) == _uids(state) and oracle.gold == state.gold and oracle._next_rune_uid == state._next_rune_uid and oracle.rng.state == state.rng.state, "Real replacement preserves both same-name rune identities, paid amounts, money and RNG: " + label)
					var incoming_copy: Dictionary = preview["incoming_rune"]
					var returned_copy: Dictionary = preview["returned_rune"]
					incoming_copy["paid"] = -999
					if not returned_copy.is_empty():
						returned_copy["uid"] = -999
					(preview["bounce_scales"] as Array).append(-1.0)
					_check(_snapshot(state) == before, "Mutating forecast records never changes either real owner: " + label)

func _test_invalid_queries() -> void:
	var state: RunState = _fixture("crescent", "blast", "pierce", true)
	for indices: Vector2i in [Vector2i(-1, 0), Vector2i(state.rune_bag.size(), 0), Vector2i(0, -1), Vector2i(0, state.loadout.size())]:
		_check(_query(state, indices.x, indices.y).is_empty(), "Invalid reserve or weapon indices return an empty pure forecast")
	state.rune_bag[0]["id"] = "missing"
	_check(_query(state, 0).is_empty(), "An unknown incoming definition has no forecast")
	state.rune_bag[0]["id"] = "pierce"
	state.loadout[0]["id"] = "missing"
	_check(_query(state, 0).is_empty(), "An unknown weapon definition has no forecast")
	state.loadout[0]["id"] = "crescent"
	state.loadout[0]["rune"]["id"] = "missing"
	_check(_query(state, 0).is_empty(), "An unknown returned definition has no forecast")
	var empty: RunState = RunState.new()
	empty.begin(20261023, "crescent")
	_check(_query(empty, 0).is_empty(), "An empty real backpack reserve has no selected rune")

func _test_slot_identity() -> void:
	var state: RunState = _fixture("bone", "bounce")
	_check(state.expand_backpack() and state.expand_backpack(), "Distinct destination fixtures purchase enough real space for their weapon footprints")
	for id: String in ["crescent", "storm", "scatter", "frost"]:
		_check(_buy(state, "weapon", id), "Fixture legally stores each distinct destination weapon")
	_check(state.loadout.size() == 5, "Preview destinations include weapons beyond the former four-slot limit")
	for index: int in state.loadout.size():
		var preview: Dictionary = _query(state, 0, index)
		_check(preview["weapon_index"] == index and preview["weapon_id"] == state.loadout[index]["id"], "Every slot is previewed without selecting a different weapon")

func _simulation(weapon: String) -> CombatSim:
	var state: RunState = RunState.new()
	state.begin(1234, weapon)
	var sim: CombatSim = CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(1100, 550)
	return sim

func _target(sim: CombatSim, point: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", point)
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	enemy.action_timer = 9999.0
	enemy.slow_timer = 9999.0
	enemy.slow_factor = 0.0
	return enemy

func _events(sim: CombatSim) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var sim_ref: WeakRef = weakref(sim)
	sim.rune_activated.connect(func(id: String, point: Vector2, _incoming: Vector2, _outgoing: Vector2) -> void:
		var current: CombatSim = sim_ref.get_ref() as CombatSim
		events.append({"id": id, "point": point, "hits": current.primary_hits})
	)
	return events

func _advance(sim: CombatSim, frames: int = 120) -> void:
	for frame: int in frames:
		sim.step(STEP, Vector2.ZERO)

func _test_real_pierce_and_bounce() -> void:
	for weapon: ContentDef in GameCatalog.weapons():
		var personal_attack: float = 2.6 if weapon.id == "sword_0005" else 1.0
		for rune: String in ["pierce", "bounce"]:
			var state: RunState = _fixture(weapon.id, rune)
			var preview: Dictionary = _query(state, 0)
			var sim: CombatSim = _simulation(weapon.id)
			var events: Array[Dictionary] = _events(sim)
			var targets: Array[CombatSim.Enemy] = []
			for index: int in 5:
				targets.append(_target(sim, Vector2(300 + index * 50, 300)))
			var shot: CombatSim.Shot = sim.fire_weapon(weapon.id, rune, Vector2(230, 300), Vector2.RIGHT)
			_advance(sim)
			var limit: int = int(preview["max_direct_targets"])
			_check(sim.primary_hits == limit and shot.hit_ids.size() == limit and not shot.active, "A real single projectile respects its advertised distinct-target limit: " + weapon.id + "/" + rune)
			_check(events.size() == RuneRules.EXTRA_HITS and int(events[0]["hits"]) == int(preview["trigger_hit"]), "Rune feedback begins only after advertised native penetration: " + weapon.id + "/" + rune)
			for index: int in targets.size():
				var scale: float = float(preview["bounce_scales"][index]) if rune == "bounce" and index < limit else 1.0
				var expected: float = weapon.damage * personal_attack * scale if index < limit else 0.0
				_check(is_equal_approx(10000.0 - targets[index].health, expected), "Actual direct damage matches advertised bounce decay without repeat UID hits")
			_advance(sim)
			_check(sim.primary_hits == limit, "An exhausted projectile cannot revisit a previous UID")
	var distant: CombatSim = _simulation("bone")
	_target(distant, Vector2(300, 300))
	_target(distant, Vector2(540, 300))
	var events: Array[Dictionary] = _events(distant)
	distant.fire_weapon("bone", "bounce", Vector2(230, 300), Vector2.RIGHT)
	_advance(distant)
	_check(distant.primary_hits == 1 and events.is_empty(), "The theoretical bounce maximum is not promised when no target is inside the actual search range")

func _test_real_blast() -> void:
	for weapon: ContentDef in GameCatalog.weapons():
		var personal_attack: float = 2.6 if weapon.id == "sword_0005" else 1.0
		var state: RunState = _fixture(weapon.id, "blast")
		var preview: Dictionary = _query(state, 0)
		var sim: CombatSim = _simulation(weapon.id)
		var events: Array[Dictionary] = _events(sim)
		var direct: Array[CombatSim.Enemy] = []
		for index: int in int(preview["trigger_hit"]):
			direct.append(_target(sim, Vector2(300 + index * 50, 300)))
		var center: Vector2 = direct.back().position
		var splash: CombatSim.Enemy = _target(sim, center + Vector2(0, 50))
		var outside: CombatSim.Enemy = _target(sim, center + Vector2(0, 100))
		sim.fire_weapon(weapon.id, "blast", Vector2(230, 300), Vector2.RIGHT)
		_advance(sim)
		_check(sim.primary_hits == int(preview["max_direct_targets"]) and events.size() == 1 and int(events[0]["hits"]) == int(preview["trigger_hit"]) and events[0]["point"] == center, "Blast occurs at the advertised direct hit and world position: " + weapon.id)
		for enemy: CombatSim.Enemy in direct:
			_check(is_equal_approx(10000.0 - enemy.health, weapon.damage * personal_attack), "Blast excludes every previously direct-hit UID from secondary damage while preserving owner attack")
		_check(is_equal_approx(10000.0 - splash.health, weapon.damage * personal_attack * float(preview["blast_multiplier"])) and outside.health == 10000.0 and sim.secondary_hits == 1, "Real splash uses owner attack and the advertised radius and multiplier without secondary recursion")
	var lone: CombatSim = _simulation("crescent")
	var events: Array[Dictionary] = _events(lone)
	_target(lone, Vector2(300, 300))
	lone.fire_weapon("crescent", "blast", Vector2(230, 300), Vector2.RIGHT)
	_advance(lone, 240)
	_check(lone.primary_hits == 1 and lone.secondary_hits == 0 and events.is_empty() and lone.shot_count == 0, "A crescent with only one real target expires without a second-hit blast")
