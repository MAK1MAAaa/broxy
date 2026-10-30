extends SceneTree
## New content exercises the production catalog, transactions and projectile dispatcher.

const STEP: float = 1.0 / 60.0
const NEW_WEAPONS: Array[String] = ["crescent", "storm", "comet"]
const NEW_RELICS: Array[String] = ["moon_charm", "pilgrim", "bulwark", "hourglass"]

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_catalog_and_affordability()
	_test_weapon_rune_matrix()
	_test_crescent_penetration()
	_test_crescent_rune_order()
	_test_pool_reuse()
	_test_compound_relics()
	_test_live_stats()
	_test_profile_compatibility()
	print("Content expansion: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _run(starter: String = "bone") -> RunState:
	var state: RunState = RunState.new()
	state.begin(2026, starter)
	return state

func _simulation(starter: String = "bone") -> CombatSim:
	var sim: CombatSim = CombatSim.new()
	sim.begin(_run(starter))
	sim.sandbox = true
	sim.player_position = Vector2(1100, 550)
	sim._cooldowns.fill(9999.0)
	return sim

func _target(sim: CombatSim, position: Vector2) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("chaser", position)
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	enemy.slow_timer = 9999.0
	enemy.slow_factor = 0.0
	enemy.action_timer = 9999.0
	return enemy

func _advance(sim: CombatSim, frames: int = 90) -> void:
	for frame: int in frames:
		sim.step(STEP, Vector2.ZERO)

func _buy(state: RunState, kind: String, id: String) -> bool:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"id": id, "kind": kind, "price": state.shop_price(definition), "sold": false}]
	return state.buy_offer(0)

func _activations(sim: CombatSim) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var sim_ref: WeakRef = weakref(sim)
	sim.rune_activated.connect(func(id: String, origin: Vector2, _incoming: Vector2, _outgoing: Vector2) -> void:
		var current: CombatSim = sim_ref.get_ref() as CombatSim
		records.append({"id": id, "origin": origin, "primary_hits": current.primary_hits})
	)
	return records

func _test_catalog_and_affordability() -> void:
	_check(GameCatalog.weapons().size() == 16 and GameCatalog.relics().size() == 14, "Catalog exposes sixteen weapons and fourteen relics")
	var ids: Dictionary = {}
	for group: Array in [GameCatalog.weapons(), GameCatalog.relics()]:
		for definition: ContentDef in group:
			_check(not ids.has(definition.id), "Expanded content has unique ids: " + definition.id)
			ids[definition.id] = true
	for id: String in NEW_WEAPONS:
		var state: RunState = _run(id)
		_check(state.loadout[0]["id"] == id, "New weapon is a valid starter: " + id)
		state.finish_wave()
		_check(_buy(state, "weapon", id) and state.gold == 28 - GameCatalog.weapon(id).price, "First-wave guaranteed income buys new weapon: " + id)
		_check(not state.buy_offer(0), "Sold new weapon cannot be purchased twice: " + id)
		state.gold = 1000
		while state.backpack.can_add("weapon", id):
			var bought: bool = _buy(state, "weapon", id)
			_check(bought, "New weapons fill actual grid space through formal purchases: " + id)
			if not bought:
				break
		var packed: Dictionary = state.backpack_snapshot()
		_check(packed["used_cells"] == state.loadout.size() * 6 and not state.backpack.can_add("weapon", id), "Actual six-cell footprints exhaust valid placements, including fragmented empty cells: " + id)
		var before: Dictionary = state.summary()
		_check(not _buy(state, "weapon", id) and state.summary() == before and state.last_error.contains("背包"), "A full grid rejects another weapon atomically: " + id)
		var target_uid: int = int(state.loadout[0]["uid"])
		var source_uid: int = int(state.loadout.back()["uid"])
		_check(state.merge_items(source_uid, target_uid) and state.backpack_item(target_uid)["rank"] == 2, "Two explicitly selected copies merge in place: " + id)
		_check(state.backpack_snapshot()["used_cells"] == int(packed["used_cells"]) - 6 and _buy(state, "weapon", id), "The merge frees physical cells for a new purchase: " + id)
	var narrow: RunState = _run()
	narrow.gold = 1000
	for copy: int in 4:
		_check(_buy(narrow, "weapon", "bone"), "Narrow weapons use their three real cells")
	_check(narrow.loadout.size() == 5 and narrow.backpack_snapshot()["used_cells"] == 15, "Five weapons are legal when their boxes fit; no four-slot gate remains")
	for seed_value: int in range(64):
		var state: RunState = _run()
		state.begin(seed_value, "bone")
		state.finish_wave()
		state.generate_shop()
		_check(state.offers[0]["kind"] == "weapon" and state.buy_offer(0), "Expanded first-wave guaranteed shop remains affordable: seed " + str(seed_value))
	var storm: ContentDef = GameCatalog.weapon("storm")
	var scatter: ContentDef = GameCatalog.weapon("scatter")
	var comet: ContentDef = GameCatalog.weapon("comet")
	_check(storm.shots == 2 and storm.spread < scatter.spread * 0.25 and storm.projectile_speed > scatter.projectile_speed, "Storm has a narrow fast double beam distinct from Scatter's three-way fan")
	_check(comet.damage > GameCatalog.weapon("ember").damage and comet.projectile_speed < GameCatalog.weapon("ember").projectile_speed and comet.projectile_radius > 8.0, "Comet trades rate and travel speed for a larger heavy hit")
	_check(GameCatalog.weapon("bone").damage == 14.0 and GameCatalog.weapon("bone").cooldown == 0.46 and GameCatalog.weapon("frost").damage == 11.0 and GameCatalog.weapon("frost").slow == 0.25 and GameCatalog.weapon("ember").damage == 29.0 and scatter.damage == 8.0 and scatter.shots == 3, "Existing weapon damage and defining behaviors retain their values")

func _test_weapon_rune_matrix() -> void:
	for weapon: ContentDef in GameCatalog.weapons():
		for rune: ContentDef in GameCatalog.runes():
			var sim: CombatSim = _simulation(weapon.id)
			var events: Array[Dictionary] = _activations(sim)
			sim.player_position = Vector2(200, 300)
			sim.run.gold = 1000
			_check(_buy(sim.run, "rune", rune.id) and sim.run.equip_rune(0, 0), "The physical rune enters the backpack and is formally equipped: " + weapon.id + "/" + rune.id)
			for index: int in 4:
				_target(sim, Vector2(340 + index * 55, 300))
			sim._cooldowns[0] = 0.0
			sim.step(STEP, Vector2.ZERO)
			_check(sim.shot_count == weapon.shots, "Production firing emits configured pellets: " + weapon.id + "/" + rune.id)
			sim._cooldowns.fill(9999.0)
			_advance(sim)
			_check(sim.primary_hits > 0 and float(sim.run.damage_dealt_by_weapon.get(weapon.id, 0.0)) > 0.0, "Combination attributes actual damage: " + weapon.id + "/" + rune.id)
			_check(not events.is_empty(), "Every weapon executes its equipped rune: " + weapon.id + "/" + rune.id)
			for event: Dictionary in events:
				_check(event["id"] == rune.id, "Feedback corresponds only to the equipped rune")

func _test_crescent_penetration() -> void:
	for rune: String in ["", "pierce"]:
		var sim: CombatSim = _simulation()
		var events: Array[Dictionary] = _activations(sim)
		var targets: Array[CombatSim.Enemy] = []
		for index: int in 5:
			targets.append(_target(sim, Vector2(300 + index * 50, 300)))
		var shot: CombatSim.Shot = sim.fire_weapon("crescent", rune, Vector2(250, 300), Vector2.RIGHT)
		# Cover all five circles in one fixed step to exercise the real impact budget.
		shot.velocity = Vector2(18000, 0)
		sim.step(STEP, Vector2.ZERO)
		var expected_hits: int = 2 if rune.is_empty() else 4
		_check(sim.primary_hits == expected_hits and shot.hit_ids.size() == expected_hits and not shot.active, "Crescent completes its full distinct-target budget in one step: " + rune)
		for index: int in 5:
			_check(is_equal_approx(targets[index].health, 10000.0 - (18.0 if index < expected_hits else 0.0)), "Crescent damages each permitted UID once and preserves later targets")
		_check(events.size() == (0 if rune.is_empty() else 2), "Native penetration emits no rune feedback; Pierce emits only two rune continuations")
		if events.size() == 2:
			_check(events[0]["primary_hits"] == 2 and events[1]["primary_hits"] == 3, "Pierce feedback starts after native penetration and ends before the fourth hit")
		_advance(sim)
		_check(sim.primary_hits == expected_hits, "Released crescent cannot repeat a previous UID")
	var old: CombatSim = _simulation()
	for index: int in 4:
		_target(old, Vector2(300 + index * 50, 300))
	var needle: CombatSim.Shot = old.fire_weapon("bone", "pierce", Vector2(250, 300), Vector2.RIGHT)
	needle.velocity = Vector2(18000, 0)
	old.step(STEP, Vector2.ZERO)
	_check(old.primary_hits == 3 and not needle.active, "Existing piercing weapons retain their three-target budget")

func _test_crescent_rune_order() -> void:
	var bounce: CombatSim = _simulation()
	var bounce_events: Array[Dictionary] = _activations(bounce)
	var targets: Array[CombatSim.Enemy] = []
	for point: Vector2 in [Vector2(300, 300), Vector2(355, 300), Vector2(410, 340), Vector2(465, 300)]:
		targets.append(_target(bounce, point))
	var shot: CombatSim.Shot = bounce.fire_weapon("crescent", "bounce", Vector2(230, 300), Vector2.RIGHT)
	_advance(bounce)
	_check(bounce.primary_hits == 4 and shot.hit_ids.size() == 4 and not shot.active, "Crescent penetrates then bounces through four distinct targets")
	for index: int in 4:
		var expected_damage: float = 18.0 * pow(0.75, maxi(0, index - 1))
		_check(is_equal_approx(10000.0 - targets[index].health, expected_damage), "Native penetration keeps full damage and only rune bounces decay damage")
	_check(bounce_events.size() == 2 and bounce_events[0]["primary_hits"] == 2 and bounce_events[1]["primary_hits"] == 3, "Bounce starts after the second direct hit")
	var blast: CombatSim = _simulation()
	var blast_events: Array[Dictionary] = _activations(blast)
	var first: CombatSim.Enemy = _target(blast, Vector2(300, 300))
	var second: CombatSim.Enemy = _target(blast, Vector2(355, 300))
	var neighbor: CombatSim.Enemy = _target(blast, Vector2(385, 345))
	blast.fire_weapon("crescent", "blast", Vector2(230, 300), Vector2.RIGHT)
	_advance(blast)
	_check(blast.primary_hits == 2 and blast.secondary_hits == 1, "Crescent blast follows native penetration with one secondary neighbor")
	_check(first.health == 9982.0 and second.health == 9982.0 and is_equal_approx(10000.0 - neighbor.health, 9.9), "Blast excludes both previously hit UIDs from repeated damage")
	_check(blast_events.size() == 1 and blast_events[0]["origin"] == second.position and blast_events[0]["primary_hits"] == 2, "Blast feedback originates only at the second direct impact")
	var isolated: CombatSim = _simulation()
	var isolated_events: Array[Dictionary] = _activations(isolated)
	_target(isolated, Vector2(300, 300))
	isolated.fire_weapon("crescent", "blast", Vector2(230, 300), Vector2.RIGHT)
	_advance(isolated, 240)
	_check(isolated.primary_hits == 1 and isolated.secondary_hits == 0 and isolated_events.is_empty() and isolated.shot_count == 0, "A crescent with no second target expires without a blast or false feedback")
	var comet: CombatSim = _simulation()
	var direct: CombatSim.Enemy = _target(comet, Vector2(300, 300))
	var splash: CombatSim.Enemy = _target(comet, Vector2(350, 340))
	comet.fire_weapon("comet", "blast", Vector2(230, 300), Vector2.RIGHT)
	_advance(comet)
	_check(direct.health == 9946.0 and is_equal_approx(10000.0 - splash.health, 29.7), "Comet blast derives its secondary damage from the real heavy primary")

func _test_pool_reuse() -> void:
	var sim: CombatSim = _simulation()
	var native: CombatSim.Shot = sim.fire_weapon("crescent", "pierce", Vector2(250, 300), Vector2.RIGHT)
	var slot: int = native.slot
	native.hit_ids[999] = true
	sim._release_shot(native)
	sim._hostile_shot(Vector2(250, 300), Vector2.RIGHT, 5.0, "caster")
	var hostile: CombatSim.Shot = sim.shots[slot]
	_check(hostile.active and hostile.hostile and hostile.innate_remaining == 0 and hostile.remaining == 0 and hostile.hit_ids.is_empty() and hostile.rune.is_empty(), "Enemy pool reuse clears native and rune penetration plus hit exclusions")
	sim._release_shot(hostile)
	var ordinary: CombatSim.Shot = sim.fire_weapon("bone", "", Vector2(250, 300), Vector2.RIGHT)
	_check(ordinary.slot == slot and ordinary.innate_remaining == 0 and ordinary.remaining == 0 and not ordinary.hostile and ordinary.attacker_id.is_empty(), "Ordinary friendly reuse clears all hostile and crescent counters")
	sim._release_shot(ordinary)
	var returned: CombatSim.Shot = sim.fire_weapon("crescent", "bounce", Vector2(250, 300), Vector2.RIGHT)
	_check(returned.slot == slot and returned.innate_remaining == 1 and returned.remaining == 2 and returned.hit_ids.is_empty(), "Crescent reuse restores independent native and rune budgets")

func _test_compound_relics() -> void:
	for id: String in NEW_RELICS:
		var definition: ContentDef = GameCatalog.relic(id)
		var state: RunState = _run()
		state.gold = 1000
		state.health = 20.0
		var item_uids: Array[int] = []
		for layer: int in range(1, 5):
			_check(_buy(state, "relic", id), "Compound relic purchases through the real transaction: " + id)
			item_uids.append(int(state.backpack_snapshot()["next_uid"]) - 1)
			_check(is_equal_approx(state.stat(definition.stat), float(RunState.BASE_STATS[definition.stat]) + definition.amount * layer) and is_equal_approx(state.stat(definition.bonus_stat), float(RunState.BASE_STATS[definition.bonus_stat]) + definition.bonus_amount * layer), "Both relic properties scale additively per layer: " + id)
			_check(is_equal_approx(state.health, 20.0 + (12.0 * layer if id == "bulwark" else 0.0)), "Only purchased maximum-health growth restores health: " + id)
			var sold_snapshot: Dictionary = state.summary()
			_check(not state.buy_offer(0) and state.summary() == sold_snapshot, "Sold relic cannot duplicate either property or healing: " + id)
		var health_before: float = state.health
		var properties: Array[float] = [state.stat(definition.stat), state.stat(definition.bonus_stat)]
		_check(state.merge_items(item_uids[1], item_uids[0]) and state.merge_items(item_uids[3], item_uids[2]) and state.merge_items(item_uids[2], item_uids[0]), "Four purchased relic boxes explicitly combine through both supported ranks: " + id)
		_check(state.backpack_item(item_uids[0])["rank"] == 3 and state.relic_counts[id] == 4 and state.stat(definition.stat) == properties[0] and state.stat(definition.bonus_stat) == properties[1], "Rank three retains all four base contributions without an obsolete three-layer cap: " + id)
		_check(state.health == health_before, "Merging maximum-health relics does not grant another heal: " + id)
		_check(state.gold == 1000 - definition.price * 4, "Only the four successful purchases consume gold; explicit merges are free: " + id)
	var poor: RunState = _run()
	poor.health = 20.0
	_check(not _buy(poor, "relic", "bulwark") and poor.health == 20.0 and poor.stat("max_health") == 100.0 and poor.relic_counts.is_empty(), "Insufficient funds grants neither bulwark properties nor healing")
	var healthy: RunState = _run()
	healthy.gold = 100
	_check(_buy(healthy, "relic", "bulwark") and healthy.health == 112.0, "Buying bulwark at full health fills only the new maximum-health increment")
	healthy.health = 10.0
	healthy.finish_wave()
	_check(healthy.health == 112.0, "Wave altar respects the expanded maximum-health property")
	var stacked: RunState = _run()
	stacked.gold = 1000
	for id: String in NEW_RELICS:
		_buy(stacked, "relic", id)
	_buy(stacked, "relic", "damage")
	_buy(stacked, "relic", "haste")
	_check(is_equal_approx(stacked.stat("damage"), 1.17) and is_equal_approx(stacked.stat("attack_speed"), 1.40), "Compound bonuses and hourglass tradeoff combine with existing offensive relics")
	_check(stacked.stat("move_speed") == 232.0 and stacked.stat("pickup_radius") == 90.0 and stacked.stat("armor") == 1.0 and stacked.stat("max_health") == 112.0, "All four compound relics combine without leaking into unrelated statistics")

func _test_live_stats() -> void:
	var sim: CombatSim = _simulation("storm")
	sim.run.gold = 1000
	_buy(sim.run, "relic", "moon_charm")
	_buy(sim.run, "relic", "hourglass")
	_target(sim, Vector2(400, 300))
	sim.player_position = Vector2(200, 300)
	sim._cooldowns[0] = 0.0
	sim.step(STEP, Vector2.RIGHT)
	_check(is_equal_approx(sim._cooldowns[0], 0.5 / 1.28), "Production firing uses both compound attack-speed properties")
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			var local_bonus: float = float(sim.run.loadout[0].get("resonance_bonus", 0.0))
			_check(is_equal_approx(shot.damage, 9.0 * 1.02 * (1.0 + local_bonus)) and is_equal_approx(shot.resonance_bonus, local_bonus), "Production damage preserves moon charm and hourglass global tradeoffs while adding the actual local resonance")
	_buy(sim.run, "relic", "pilgrim")
	var before: Vector2 = sim.player_position
	sim.step(STEP, Vector2.RIGHT)
	_check(is_equal_approx(sim.player_position.distance_to(before), 232.0 * STEP), "Pilgrim changes actual player movement")
	var soul_point: Vector2 = sim.player_position + Vector2(85, 0)
	sim._drop_soul(soul_point, 1)
	sim._update_souls(STEP)
	var attracted: bool = false
	for soul: CombatSim.Soul in sim.souls:
		if soul.active:
			attracted = soul.position.distance_to(sim.player_position) < 85.0
	_check(attracted, "Pilgrim attracts a soul beyond the original 76-pixel pickup range")
	_buy(sim.run, "relic", "bulwark")
	var actual: float = sim.run.take_damage(11.0)
	_check(is_equal_approx(actual, 10.0), "Bulwark armor participates in the production damage reduction formula")

func _test_profile_compatibility() -> void:
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	var profile: GameStore = GameStore.new()
	profile.persistent = false
	var original_settings: Dictionary = profile.settings.duplicate()
	for starter: String in NEW_WEAPONS:
		var state: RunState = _run(starter)
		state.gold = 1000
		for id: String in NEW_RELICS:
			_buy(state, "relic", id)
		profile.record_run(state, true)
	_check(profile.settings == original_settings and profile.best == {"wave": 1, "kills": 0, "wins": 3, "runs": 3}, "Expanded loadouts record results using the existing profile schema")
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == before), "New content and its tests leave the player's existing profile bytes unchanged")
