extends SceneTree
## Real purchases, casts, damage and healing exercise equipment passives by UID.

const STEP: float = 1.0 / 60.0
const NEW_WEAPONS: Array[String] = ["sword_0012", "spear_0005", "sword_0004", "axe_0009", "book_0009", "sword_0007", "axe_0024", "sword_0011"]
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)


func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261031, "bone", "reliquary", "alk")
	state.gold = 10000
	while state.backpack.height < BackpackInventory.MAX_HEIGHT:
		_check(state.expand_backpack(), "Actual inventory expansion succeeds for the equipment fixture")
	return state


func _offer(state: RunState, id: String, kind: String = "weapon") -> void:
	state.offers.assign([{"kind": kind, "id": id, "price": 1, "rank": 1, "sold": false}])


func _buy(state: RunState, id: String, kind: String = "weapon") -> int:
	_offer(state, id, kind)
	var uid: int = int(state.backpack.snapshot()["next_uid"])
	_check(state.buy_offer(0), "Actual purchase succeeds: " + id)
	return uid


func _sim(state: RunState, boss_wave: bool = false) -> CombatSim:
	if boss_wave:
		state.wave = 8
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	return sim


func _wait_for_hero(sim: CombatSim) -> bool:
	for frame: int in 1200:
		if float(sim._hero_skill_clock.get("remaining", 0.0)) <= 0.0:
			return not sim.complete
		sim.step(STEP, Vector2.ZERO)
	return false


func _move_rotated(state: RunState, uid: int) -> bool:
	var item: Dictionary = state.backpack_item(uid)
	var rotated: bool = not bool(item["rotated"])
	for y: int in state.backpack.height:
		for x: int in BackpackInventory.WIDTH:
			var cell := Vector2i(x, y)
			if state.backpack._fits(state.backpack._items, "weapon", str(item["id"]), cell, rotated, uid):
				return state.move_item(uid, cell, rotated)
	return false


func _run() -> void:
	for id: String in NEW_WEAPONS:
		_check(GameCatalog.weapon(id) != null, "The actual equipment catalog includes " + id)
	if _failures == 0:
		_test_first_shop_affordability()
		_test_static_projections()
		_test_skill_damage()
		_test_cast_haste()
		_test_conditional_damage()
		_test_rescue_and_healing()
	print("WeaponEffects: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_first_shop_affordability() -> void:
	var later_expensive: bool = false
	for seed_value: int in range(64):
		var state := RunState.new()
		state.begin(seed_value + 20261031, "bone")
		state.finish_wave()
		state.generate_shop()
		var affordable: bool = false
		var valid_first_pool: bool = true
		for index: int in state.offers.size():
			var offer: Dictionary = state.offers[index]
			if offer["kind"] == "weapon":
				valid_first_pool = valid_first_pool and int(offer["price"]) <= 28
				affordable = affordable or state.purchase_error(index).is_empty()
		_check(state.gold == 28 and affordable and valid_first_pool, "The actual zero-kill first-wave shop guarantees an affordable weapon without raising income: seed " + str(seed_value))
		state.next_wave()
		for index: int in 8:
			var later: Dictionary = state._make_offer("weapon")
			later_expensive = later_expensive or GameCatalog.weapon(str(later["id"])).price > 28
	_check(later_expensive, "Later waves retain the full catalog including expensive new weapons")


func _test_static_projections() -> void:
	var state: RunState = _state()
	state.health = 50.0
	_offer(state, "sword_0007")
	var before: Dictionary = state.summary()
	var before_rng: int = state.rng.state
	var before_heals: int = state.healing_events
	var forecast: Dictionary = state.weapon_purchase_preview(0)
	_check(forecast["health_before"] == 50.0 and forecast["health_after"] == 58.0, "A real Cutlass purchase forecast restores only its added maximum-health increment")
	_check(forecast["stat_changes"].size() == 1 and forecast["stat_changes"][0]["key"] == "max_health" and forecast["stat_changes"][0]["delta"] == 8.0, "Weapon forecasts include real equipment stat changes")
	_check(state.summary() == before and state.rng.state == before_rng and state.healing_events == before_heals, "Querying equipment bonuses does not spend gold, heal, move items or consume random state")
	var first: int = int(state.backpack.snapshot()["next_uid"])
	_check(state.buy_offer(0), "The forecasted Cutlass transaction commits")
	_check(state.stat("max_health") == 108.0 and state.health == forecast["health_after"] and state.healing_events == 1, "Committed maximum health and its one actual healing event match the purchase forecast")
	var second: int = _buy(state, "sword_0007")
	_check(state.stat("max_health") == 116.0 and state.health == 66.0, "Distinct weapons add their own static bonuses")
	var health: float = state.health
	var merged: Dictionary = state.merge_preview(second, first)
	_check(merged["can_merge"] and merged["stat_changes"][0]["after"] == 116.0 and merged["health_after"] == health, "Rank-two merge preserves the combined static contribution without forecasting free healing")
	_check(state.merge_items(second, first), "Two real Cutlasses merge through the inventory transaction")
	_check(state.stat("max_health") == 116.0 and state.health == health and state.backpack_item(first)["rank"] == 2, "The rank-weighted cache matches the merged item and preserves its UID")
	var revision: int = state.inventory_revision
	_check(_move_rotated(state, first), "The actual equipment can be rotated into a valid placement")
	_check(state.inventory_revision > revision and state.stat("max_health") == 116.0 and state.health == health, "Layout rebuilds refresh cached equipment stats without healing or losing rank")
	_check(state.sell_item(first), "The rank-two equipment can be sold while the starter remains")
	_check(state.stat("max_health") == 100.0 and state.health == health, "Selling removes the exact cached static bonus without free recovery")
	_check(state.stat("skill_damage") == 1.0 and state.stat("skill_haste") == 0.0 and state.stat("summon_damage") == 1.0, "Unmodified skill stats have explicit neutral defaults")


func _test_skill_damage() -> void:
	var state: RunState = _state()
	_buy(state, "starfall", "skill")
	var hero_before: Dictionary = state.hero_skill_parameters()
	var rear_before: Dictionary = state.active_skill_parameters(state.active_skills[0])
	var weapon_before: float = state.weapon_damage(state.loadout[0])
	_offer(state, "axe_0024")
	var forecast: Dictionary = state.weapon_purchase_preview(0)
	_check(forecast["stat_changes"][0]["key"] == "skill_damage" and is_equal_approx(forecast["stat_changes"][0]["after"], 1.28), "Parashu previews the actual skill-only multiplier")
	_check(state.buy_offer(0), "The real Parashu purchase commits")
	_check(is_equal_approx(state.stat("skill_damage"), 1.28), "Equipped Parashu updates the cached skill multiplier")
	_check(is_equal_approx(float(state.hero_skill_parameters()["damage"]), float(hero_before["damage"]) * 1.28), "R parameters apply equipment skill damage once")
	_check(is_equal_approx(float(state.active_skill_parameters(state.active_skills[0])["damage"]), float(rear_before["damage"]) * 1.28), "Backpack rear-skill parameters use the same skill multiplier")
	_check(is_equal_approx(state.weapon_damage(state.loadout[0]), weapon_before), "Skill-only equipment does not strengthen ordinary weapon projectiles")
	var sim: CombatSim = _sim(state)
	var expected_damage: float = float(hero_before["damage"]) * 1.28 * 1.2
	_check(is_equal_approx(float(sim.hero_skill_snapshot()["damage"]), expected_damage), "R prediction includes Parashu and Alk's opening attack buff once each")
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + Vector2(40, 0))
	enemy.health = 10000.0
	enemy.max_health = 10000.0
	enemy.slow_timer = 1000.0
	enemy.slow_factor = 0.0
	_check(sim.try_hero_skill(), "The real R cast accepts the new equipment parameters")
	_check(is_equal_approx(float(sim._hero_skill_clock["parameters"]["damage"]), expected_damage), "The locked cast retains each skill and attack multiplier exactly once")
	for frame: int in 43:
		sim.step(STEP, Vector2.ZERO)
	_check(enemy.health == 10000.0 and sim.skill_hits == 0, "Equipment cannot turn Alk's pending area into instant damage")
	sim.step(STEP, Vector2.ZERO)
	_check(is_equal_approx(10000.0 - enemy.health, expected_damage) and is_equal_approx(float(sim.damage_by_skill.get("hero_alk", 0.0)), expected_damage) and sim.skill_hits == 1, "The first real area hit applies Parashu and the opening buff once to actual damage and contribution")


func _test_cast_haste() -> void:
	var state: RunState = _state()
	var uid: int = _buy(state, "sword_0012")
	var sim: CombatSim = _sim(state)
	var base: float = float(state.hero_skill_parameters()["cooldown"])
	_check(sim.weapon_effects.haste_bonus() == 0.0, "Cast haste starts with no free stacks")
	_check(sim.try_hero_skill(), "The first real R cast succeeds")
	_check(is_equal_approx(float(sim._hero_skill_clock["duration"]), base) and is_equal_approx(sim.weapon_effects.haste_bonus(), 0.025), "The successful cast stacks haste for the next cast while retaining its own locked cooldown")
	var snap: Dictionary = sim.weapon_effects.snapshot()
	var locked: float = float(sim._hero_skill_clock["remaining"])
	_check(not sim.try_hero_skill() and sim.weapon_effects.snapshot() == snap, "A refused cast cannot grant another equipment stack")
	_check(_move_rotated(state, uid), "The cast-haste weapon is moved through the real inventory")
	_check(is_equal_approx(sim.weapon_effects.haste_bonus(), 0.025) and float(sim._hero_skill_clock["remaining"]) == locked, "Moving or rotating the same UID preserves stacks and the already locked cooldown")
	_check(_wait_for_hero(sim) and sim.try_hero_skill(), "A second cast succeeds after actual fixed steps consume its cooldown")
	_check(is_equal_approx(float(sim._hero_skill_clock["duration"]), base / 1.025), "The next real R cooldown uses the previously earned haste exactly once")
	for index: int in 12:
		_check(_wait_for_hero(sim) and sim.try_hero_skill(), "Repeated casts after actual cooldowns exercise the bounded equipment stack")
	_check(is_equal_approx(sim.weapon_effects.haste_bonus(), 0.15), "Cast haste stops at its authored per-weapon cap")
	var copied: Dictionary = sim.weapon_effects.snapshot()
	copied["items"][0]["cast_stacks"] = 0
	_check(is_equal_approx(sim.weapon_effects.haste_bonus(), 0.15), "Mutating a returned runtime snapshot cannot change equipment stacks")
	state.finish_wave()
	state.next_wave()
	sim.begin(state)
	sim.sandbox = true
	_check(sim.weapon_effects.haste_bonus() == 0.0, "A new wave resets equipment event stacks")


func _test_conditional_damage() -> void:
	var state: RunState = _state()
	for id: String in ["spear_0005", "sword_0004", "book_0009", "axe_0009"]:
		_buy(state, id)
	var sim: CombatSim = _sim(state, true)
	var normal: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + Vector2(180, 0))
	normal.health = 10000.0
	normal.max_health = 10000.0
	_check(sim.weapon_effects.damage_multiplier(sim, "bone", normal) == 1.0, "Inactive ball equipment has no unconditional damage bonus")
	sim._pinball_time_left = 1.0
	_check(is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "bone", normal), 1.3), "Maltet and Ameno apply to weapon damage during actual ballification")
	_check(is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "skill:hero_alk", normal), 1.3), "The same active ball bonuses apply to a real player R source")
	_check(is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "skill:pinball", normal), 1.55), "Senji adds its separate bonus only to canonical direct ball damage")
	for source: String in ["caster", "boss", "skill:enemy_blast", "unknown"]:
		_check(sim.weapon_effects.damage_multiplier(sim, source, normal) == 1.0, "Unrecognized and hostile sources never inherit player equipment: " + source)
	var before: float = normal.health
	sim.apply_damage(normal, 10.0, "bone")
	_check(is_equal_approx(before - normal.health, 13.0) and is_equal_approx(float(sim.damage_by_weapon["bone"]), 13.0), "Actual weapon hit and weapon contribution record the once-modified effective damage")
	before = normal.health
	sim.apply_damage(normal, 10.0, "bone", true)
	_check(is_equal_approx(before - normal.health, 13.0), "A secondary hit applies the equipment modifier once, not once per chain depth")
	sim._pinball_time_left = 0.0
	_check(sim.weapon_effects.damage_multiplier(sim, "bone", normal) == 1.0 and is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "skill:pinball", normal), 1.55), "Ordinary shots lose the active bonus while the final actual swept ball hit retains its own source semantics")
	var boss: CombatSim.Enemy = sim.boss
	sim.boss_encounter.advance(2.0, boss.position, sim.player_position, 1.0)
	for point: Dictionary in sim.boss_encounter.weakpoints_snapshot():
		sim.boss_encounter.damage_weakpoint(int(point["uid"]), int(point["cast_id"]), float(point["max_health"]) * 2.0)
	_check(sim.boss_encounter.snapshot()["phase"] == "break", "Breaking every real weakpoint enters the authoritative break state")
	_check(is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "bone", boss), 1.15) and sim.weapon_effects.damage_multiplier(sim, "bone", normal) == 1.0, "Thor's adapted break bonus applies to this broken boss and no ordinary target")
	before = boss.health
	sim.apply_damage(boss, 10.0, "bone")
	_check(is_equal_approx(before - boss.health, 10.0 * BossEncounter.BREAK_DAMAGE_MULTIPLIER * 1.15), "Boss break vulnerability and the equipment bonus each apply once to actual damage")
	sim.boss_encounter.advance(BossEncounter.BREAK_SECONDS + 0.01, boss.position, sim.player_position, boss.health / boss.max_health)
	_check(sim.weapon_effects.damage_multiplier(sim, "bone", boss) == 1.0, "The extra equipment damage ends with the actual break window")


func _test_rescue_and_healing() -> void:
	var state: RunState = _state()
	var uid: int = _buy(state, "sword_0011")
	var sim: CombatSim = _sim(state)
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + Vector2(200, 0))
	state.health = 70.0
	sim.weapon_effects.observe_health(sim)
	_check(state.health == 70.0 and sim.weapon_effects.snapshot()["rescues"] == 0, "Heim's rescue waits until health is actually below its threshold")
	state.health = 100.0
	sim._hurt_player(35.0, "tank", "contact")
	_check(is_equal_approx(state.health, 85.0) and is_equal_approx(state.damage_taken, 35.0) and state.hits_taken == 1, "A real nonlethal hit triggers one rescue without erasing damage history")
	_check(sim.weapon_effects.snapshot()["rescues"] == 1 and state.healing_events == 1 and is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "bone", enemy), 1.03), "Actual rescue healing grants one healing-damage stack")
	var snapshot: Dictionary = sim.weapon_effects.snapshot()
	snapshot["items"][0]["rescued"] = false
	for index: int in 4:
		sim.weapon_effects.observe_health(sim)
	_check(state.health == 85.0 and sim.weapon_effects.snapshot()["rescues"] == 1, "Repeated observations and mutated presentation copies cannot manufacture another rescue")
	var healing: float = state.heal(100.0)
	sim.weapon_effects.observe_health(sim)
	_check(healing == 15.0 and state.healing_events == 2 and is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "bone", enemy), 1.06), "Only the effective portion of a real heal creates a second event")
	_check(state.heal(100.0) == 0.0 and state.heal(NAN) == 0.0 and state.heal(-10.0) == 0.0, "Overheal and malformed healing cannot create effective recovery")
	sim.weapon_effects.observe_health(sim)
	_check(state.healing_events == 2 and is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "bone", enemy), 1.06), "No-op healing does not add damage stacks")
	for index: int in 8:
		state.take_damage(1.0)
		state.heal(1.0)
	sim.weapon_effects.observe_health(sim)
	_check(is_equal_approx(sim.weapon_effects.damage_multiplier(sim, "bone", enemy), 1.15), "Each actual heal event is observed even when net health is unchanged, and the bonus is capped")
	state.health = 40.0
	_check(_move_rotated(state, uid), "The used rescue weapon changes its actual grid layout")
	sim.weapon_effects.observe_health(sim)
	_check(state.health == 40.0 and sim.weapon_effects.snapshot()["rescues"] == 1, "A layout rebuild cannot refresh a consumed rescue on the same UID")
	var retained: Dictionary = state.backpack_item(uid)
	_check(state.sell_item(uid), "Selling the rescue item uses the actual transaction")
	sim.weapon_effects.observe_health(sim)
	# Replaying a previously held UID models stale inventory restoration, not a new purchase.
	state.backpack._items.append(retained)
	state._sync_backpack_projection()
	sim.weapon_effects.observe_health(sim)
	_check(state.health == 40.0 and sim.weapon_effects.snapshot()["rescues"] == 1, "Restoring a previously consumed UID cannot refresh its per-wave charge")
	state.finish_wave()
	state.next_wave()
	# CombatWorld.begin creates a fresh simulation while retaining the run inventory.
	sim = _sim(state)
	_check(sim.weapon_effects.snapshot()["rescues"] == 0 and not sim.weapon_effects.snapshot()["items"][0]["rescued"], "The real fresh-wave simulation begins with the held UID's rescue unused")
	sim._hurt_player(35.0, "tank", "contact")
	_check(is_equal_approx(state.health, 85.0) and sim.weapon_effects.snapshot()["rescues"] == 1, "A new wave genuinely resets the same weapon's rescue charge")
	sim.invulnerability = 0.0
	sim._hurt_player(1000.0, "boss", "ritual")
	var events: int = state.healing_events
	_check(state.health == 0.0 and sim.complete and not sim.weapon_effects.snapshot()["active"], "Lethal damage clears equipment state without reviving the player")
	_check(state.heal(100.0) == 0.0 and state.health == 0.0 and state.healing_events == events, "Healing a dead player cannot generate resurrection or event stacks")
