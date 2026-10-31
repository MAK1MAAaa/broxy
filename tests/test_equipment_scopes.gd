extends SceneTree
## Scoped equipment uses actual actors and the same pure inventory forecasts as casts.

const FIXTURE_IDS: Array[String] = ["scope_owner", "scope_health", "scope_fire", "scope_dark", "scope_party"]
const LEGACY_WEAPONS: Array[String] = ["bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring", "sword_0012", "spear_0005", "sword_0004", "axe_0009", "book_0009", "sword_0007", "axe_0024", "sword_0011"]
var _checks: int = 0
var _failures: int = 0
var _saved: Dictionary = {}
var _definitions: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _fixture(id: String, modifiers: Array[Dictionary]) -> void:
	var definition := ContentDef.new()
	definition.id = id
	definition.kind = "weapon"
	definition.inventory_size = Vector2i.ONE
	definition.equipment_owner = "main"
	definition.equipment_modifiers = modifiers
	definition.damage = 10.0
	definition.element = "dark"
	_saved[id] = GameCatalog._weapon_index.get(id)
	_definitions[id] = definition
	GameCatalog._weapon_index[id] = definition

func _install() -> void:
	_fixture("scope_owner", [{"stat": "skill_damage", "target": "owner", "amount_by_rank": [0.25, 0.45, 0.75]}])
	_fixture("scope_health", [
		{"stat": "damage", "target": "owner", "amount_by_rank": [0.5, 0.5, 0.5]},
		{"stat": "max_health_ratio", "target": "owner", "amount_by_rank": [0.15, 0.15, 0.15]},
	])
	_fixture("scope_fire", [{"stat": "skill_damage", "target": "party_element", "element": "fire", "amount_by_rank": [0.2, 0.4, 0.6]}])
	_fixture("scope_dark", [{"stat": "skill_damage", "target": "party_element", "element": "dark", "amount_by_rank": [0.3, 0.45, 0.6]}])
	_fixture("scope_party", [{"stat": "skill_damage", "target": "party", "amount_by_rank": [0.1, 0.2, 0.3]}])

func _restore() -> void:
	for id: String in FIXTURE_IDS:
		if _saved[id] == null:
			GameCatalog._weapon_index.erase(id)
		else:
			GameCatalog._weapon_index[id] = _saved[id]

func _state(hero: String = "mordiga") -> RunState:
	var state := RunState.new()
	state.begin(20261101, "bone", "reliquary", hero)
	state.gold = 10000
	while state.backpack.height < BackpackInventory.MAX_HEIGHT:
		_check(state.expand_backpack(), "The fixture expands through the actual inventory transaction")
	return state

func _offer(state: RunState, id: String, kind: String = "weapon") -> void:
	state.offers.assign([{"id": id, "kind": kind, "rank": 1, "price": 1, "sold": false}])

func _buy(state: RunState, id: String, kind: String = "weapon") -> int:
	_offer(state, id, kind)
	var uid: int = int(state.backpack.snapshot()["next_uid"])
	_check(state.buy_offer(0), "A fixture purchase uses the real shop transaction: " + id)
	return uid

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, state.inventory_revision, state.healing_events,
		state._equipment_scopes, str(state.rng.state)])

func _run() -> void:
	_install()
	_test_actor_scope_and_additive_buckets()
	_test_dark_actor_and_duplicate_rears()
	_test_owner_storage_merge_and_previews()
	_test_health_ratio_and_transactions()
	_test_projection_validation()
	_test_legacy_baselines()
	_restore()
	print("EquipmentScopes: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_actor_scope_and_additive_buckets() -> void:
	var state: RunState = _state()
	_buy(state, "starfall", "skill")
	_buy(state, "arc_slash", "skill")
	var fire: Dictionary = state.active_skills[0]
	var wind: Dictionary = state.active_skills[1]
	var main: Dictionary = state.main_actor_ref()
	var fire_ref: Dictionary = state.rear_actor_ref(fire)
	var wind_ref: Dictionary = state.rear_actor_ref(wind)
	var hero_before: float = float(state.hero_skill_parameters()["damage"])
	var fire_before: float = float(state.active_skill_parameters(fire)["damage"])
	var wind_before: float = float(state.active_skill_parameters(wind)["damage"])
	_check(state.actor_context(main)["element"] == "water" and state.actor_context(fire_ref)["element"] == "fire" and state.actor_context(wind_ref)["element"] == "wind", "Main and rear elements come from actual character definitions rather than weapon or skill presentation")
	_buy(state, "scope_owner")
	_check(is_equal_approx(float(state.hero_skill_parameters()["damage"]), hero_before * 1.25), "An own skill modifier changes only the owner's R parameters")
	_check(state.active_skill_parameters(fire)["damage"] == fire_before and state.active_skill_parameters(wind)["damage"] == wind_before, "Same-party fire and wind skills receive no main-owner skill modifier")
	_buy(state, "scope_health")
	_check(is_equal_approx(state.stat("damage"), 1.5) and is_equal_approx(state.stat_for_actor("damage", fire_ref), 1.0), "Own ATK is a main actor bucket and does not become the rear's shared starting stat")
	_check(is_equal_approx(state.weapon_damage(state.loadout[0]), GameCatalog.weapon("bone").damage * 1.5 * (1.0 + float(state.loadout[0]["resonance_bonus"]))), "Own ATK applies to an existing main-character weapon, not only to the granting equipment")
	_buy(state, "scope_fire")
	_buy(state, "scope_dark")
	_check(is_equal_approx(float(state.active_skill_parameters(fire)["damage"]), fire_before * 1.2) and state.active_skill_parameters(wind)["damage"] == wind_before, "An element beneficiary selects the actual fire rear while excluding the wind rear")
	_check(is_equal_approx(float(state.hero_skill_parameters()["damage"]), hero_before * 1.5 * 1.25), "A water main holding a dark-colored fire-buff weapon receives neither fire nor dark party skill bonus")
	_buy(state, "scope_party")
	_check(is_equal_approx(state.stat_for_actor("skill_damage", main), 1.35) and is_equal_approx(state.stat_for_actor("skill_damage", fire_ref), 1.3) and is_equal_approx(state.stat_for_actor("skill_damage", wind_ref), 1.1), "Owner, element and whole-party skill sources share one additive bucket per actor")
	_check(is_equal_approx(float(state.hero_skill_parameters(0.15)["damage"]), hero_before * 1.5 * 1.5) and is_equal_approx(float(state.active_skill_parameters(fire, 0.15)["damage"]), fire_before * 1.45), "A controlled dynamic skill bonus is added once inside the actor skill bucket before multiplying ATK")
	_check(state.hero_skill_parameters(INF) == state.hero_skill_parameters() and state.active_skill_parameters(fire, NAN) == state.active_skill_parameters(fire), "Non-finite dynamic preview bonuses cannot contaminate locked skill parameters")
	var forged: Dictionary = fire.duplicate(true)
	forged["id"] = "arc_slash"
	_check(state.rear_actor_ref(forged).is_empty() and state.actor_context({"kind": "rear", "skill_uid": 999999}).is_empty(), "An actor identity requires the actual owned UID and matching skill definition")
	forged = fire.duplicate(true)
	forged["rank"] = 3
	_check(state.active_skill_parameters(forged) == state.active_skill_parameters(fire), "A real rear UID cannot use a caller-forged rank in the cast parameter API")

func _test_dark_actor_and_duplicate_rears() -> void:
	var state: RunState = _state("falsche")
	_buy(state, "starfall", "skill")
	_buy(state, "starfall", "skill")
	var first: Dictionary = state.active_skills[0]
	var second: Dictionary = state.active_skills[1]
	var first_ref: Dictionary = state.rear_actor_ref(first)
	var second_ref: Dictionary = state.rear_actor_ref(second)
	_check(first_ref != second_ref and state.actor_context(first_ref)["hero_id"] == state.actor_context(second_ref)["hero_id"], "Two identical rear characters retain distinct inventory-instance actor identities")
	_buy(state, "scope_dark")
	_buy(state, "scope_fire")
	_check(is_equal_approx(state.stat("skill_damage"), 1.3) and is_equal_approx(state.stat_for_actor("skill_damage", first_ref), 1.2) and is_equal_approx(state.stat_for_actor("skill_damage", second_ref), 1.2), "The dark main and both independent fire rears receive only their own element beneficiary")
	_check(state.sell_item(int(first["uid"])) and state.actor_context(first_ref).is_empty(), "Selling one rear invalidates exactly that actor reference")
	_check(is_equal_approx(state.stat_for_actor("skill_damage", first_ref), 1.0) and is_equal_approx(state.stat_for_actor("skill_damage", second_ref), 1.2), "A missing rear does not inherit a same-name surviving UID's element modifier")

func _test_owner_storage_merge_and_previews() -> void:
	var state: RunState = _state()
	_check(not state.backpack_item(1).has("owner_ref") and not state.loadout[0].has("owner_ref"), "Legacy inventory and loadout records retain their original key schema")
	_offer(state, "scope_owner")
	var before: String = _signature(state)
	var purchase: Dictionary = state.weapon_purchase_preview(0)
	_check(purchase["owner_ref"] == {"kind": "main"} and _signature(state) == before, "A scoped purchase forecasts its explicit main owner without mutating the live inventory")
	var target_uid: int = int(state.backpack.snapshot()["next_uid"])
	_check(state.buy_offer(0), "The forecast owner purchase commits")
	_check(state.backpack_item(target_uid)["owner_ref"] == purchase["owner_ref"] and state.loadout[state.weapon_index_for_uid(target_uid)]["owner_ref"] == purchase["owner_ref"], "Backpack and combat loadout preserve the exact explicit owner reference")
	var copied: Dictionary = state.backpack_item(target_uid)
	copied["owner_ref"]["kind"] = "rear"
	_check(state.backpack_item(target_uid)["owner_ref"] == {"kind": "main"}, "Returned owner references are detached from live storage")
	var source_uid: int = _buy(state, "scope_owner")
	var target: Dictionary = state.backpack_item(target_uid)
	_check(state.move_item(target_uid, Vector2i(int(target["x"]), int(target["y"])), not bool(target["rotated"])) and state.backpack_item(target_uid)["owner_ref"] == {"kind": "main"}, "Rotation preserves the owner rather than creating a new actor assignment")
	before = _signature(state)
	var merge: Dictionary = state.merge_preview(source_uid, target_uid)
	_check(merge["can_merge"] and merge["owner_ref"] == {"kind": "main"} and _signature(state) == before, "Merge forecasts preserve the target owner and do not commit either source UID")
	_check(is_equal_approx(float(merge["stat_changes"][0]["after"]), 1.45), "A rank-array merge recomputes one rank-II bonus instead of applying the old exponential rank multiplier")
	_check(state.merge_items(source_uid, target_uid) and state.backpack_item(source_uid).is_empty() and state.backpack_item(target_uid)["owner_ref"] == {"kind": "main"} and is_equal_approx(state.stat("skill_damage"), 1.45), "The actual merge retains target UID/owner and matches its scoped stat forecast")
	_offer(state, "starfall", "skill")
	before = _signature(state)
	var skill: Dictionary = state.skill_purchase_preview(0)
	_check(_signature(state) == before and state.buy_offer(0) and skill["parameters"] == state.active_skill_parameters(state.active_skills[0]), "A projected purchased skill uses its prospective UID and exactly matches its real actor parameters")
	var entries: Array = state.backpack.snapshot()["items"]
	_check(is_equal_approx(state.actor_stat_for_items("skill_damage", state.main_actor_ref(), entries), state.stat("skill_damage")), "Detached actor projections and cached actual attributes use the same scope rule")
	before = _signature(state)
	var sale: Dictionary = state.sell_preview(target_uid)
	_check(sale["can_sell"] and sale["owner_ref"] == {"kind": "main"} and _signature(state) == before, "A sale preview retains attribution and does not remove the granting item")
	_check(state.sell_item(target_uid) and is_equal_approx(state.stat("skill_damage"), 1.0), "A committed sale removes exactly the sold owner's modifier")

func _test_health_ratio_and_transactions() -> void:
	var state: RunState = _state("alk")
	state.health = 40.0
	_offer(state, "scope_health")
	var forecast: Dictionary = state.weapon_purchase_preview(0)
	var uid: int = int(state.backpack.snapshot()["next_uid"])
	_check(is_equal_approx(float(forecast["health_after"]), 40.0) and state.buy_offer(0), "New personal HP equipment never forecasts or grants purchase healing")
	_check(is_equal_approx(state.stat("max_health"), 115.0) and state.health == 40.0 and state.healing_events == 0, "Main maximum HP applies the ratio to the existing flat base without a healing event")
	_offer(state, "vitality", "relic")
	var relic: Dictionary = state.relic_purchase_preview(0)
	_check(state.buy_offer(0) and is_equal_approx(state.health, float(relic["health_after"])) and state.healing_events == 1, "Legacy relic purchase recovery remains identical to its forecast with scoped HP present")
	_check(GameCatalog.relic("vitality").amount == 20.0 and is_equal_approx(state.stat("max_health"), 120.0 * 1.15) and is_equal_approx(state.projected_upgrade_stat("max_health", 12.0), 132.0 * 1.15), "The actual20-HP relic and the separate12-HP upgrade are added before the owner HP ratio")
	state.pending_upgrades = 1
	state._upgrade_options.assign([{"id": "vitality", "stat": "max_health", "amount": 12.0}])
	_check(state.choose_upgrade("vitality") and is_equal_approx(state.stat("max_health"), 132.0 * 1.15), "An actual flat HP upgrade reaches the same scoped maximum as its scalar preview")
	state.health = 140.0
	var heals: int = state.healing_events
	var sale: Dictionary = state.sell_preview(uid)
	_check(state.sell_item(uid) and is_equal_approx(state.health, float(sale["health_after"])) and is_equal_approx(state.health, 132.0) and state.healing_events == heals, "Selling ratio HP clamps to the exact projected ceiling without recovery")
	state.health = 0.0
	var first: int = _buy(state, "scope_health")
	_check(state.health == 0.0 and state.healing_events == heals, "Buying new personal HP equipment cannot resurrect a dead owner")
	var second: int = _buy(state, "scope_health")
	state.health = 160.0
	var merged: Dictionary = state.merge_preview(second, first)
	_check(state.merge_items(second, first) and is_equal_approx(state.health, float(merged["health_after"])) and is_equal_approx(state.health, 132.0 * 1.15) and state.healing_events == heals, "A merge that removes one ratio source only clamps HP and never invents healing")
	_offer(state, "scope_owner")
	state.gold = 0
	var before: String = _signature(state)
	state.weapon_purchase_preview(0)
	_check(not state.buy_offer(0) and _signature(state) == before, "A rejected purchase preserves UID, gold, scopes, health, healing count, inventory revision and RNG")

func _test_projection_validation() -> void:
	var entries: Array = [{"uid": 1, "kind": "weapon", "id": "scope_owner", "rank": 1, "owner_ref": {"kind": "main"}}]
	var first: Dictionary = EquipmentScopeRules.project(entries, "alk", _definitions)
	_check(is_equal_approx(float(first["main"]["skill_damage"]), 0.25), "The pure projector accepts injected ContentDef fixtures without requiring resource assets")
	first["main"]["skill_damage"] = 999.0
	_check(is_equal_approx(float(EquipmentScopeRules.project(entries, "alk", _definitions)["main"]["skill_damage"]), 0.25), "Projection results are detached and cannot alter source modifiers")
	entries[0]["owner_ref"] = {"kind": "rear", "skill_uid": 10}
	_check(EquipmentScopeRules.project(entries, "alk", _definitions).is_empty(), "This batch's explicitly main-owned content fails closed for a forged rear owner")
	var invalid := ContentDef.new()
	invalid.id = "invalid_scope"
	invalid.equipment_owner = "main"
	invalid.equipment_modifiers = [
		{"stat": "skill_damage", "target": "party", "amount_by_rank": [0.1, INF, 0.3]},
		{"stat": "damage", "target": "party", "amount_by_rank": [-1.0, 0.2, 0.3]},
		{"stat": "skill_damage", "target": "unknown", "amount_by_rank": [0.1, 0.2, 0.3]},
		{"stat": "skill_damage", "target": "party_element", "amount_by_rank": [0.1, 0.2, 0.3]},
		{"stat": "move_speed", "target": "party", "amount_by_rank": [1.0, 2.0, 3.0]},
	]
	var bad_entries: Array = [{"uid": 1, "kind": "weapon", "id": invalid.id, "rank": 1, "owner_ref": {"kind": "main"}}]
	_check(EquipmentScopeRules.project(bad_entries, "alk", {invalid.id: invalid}).is_empty(), "Unknown selectors/stats, missing element and invalid rank arrays do not create executable bonuses")

func _test_legacy_baselines() -> void:
	for id: String in LEGACY_WEAPONS:
		_check(GameCatalog.weapon(id).equipment_owner.is_empty() and GameCatalog.weapon(id).equipment_modifiers.is_empty(), "Existing weapon resources retain their original shared adaptation: " + id)
	for hero: String in HeroCatalog.IDS:
		var state: RunState = _state(hero)
		var raw: Dictionary = HeroCatalog.hero_skill_parameters(hero, {"damage": state.stat("damage") * state.stat("skill_damage"), "skill_haste": state.stat("skill_haste"), "summon_damage": state.stat("summon_damage")})
		_check(state.hero_skill_parameters() == raw and not state.backpack_item(1).has("owner_ref"), "The old default hero projection and starter record remain unchanged: " + hero)
		var skill: String = "arc_slash" if hero == "hanabi" else "starfall"
		_buy(state, skill, "skill")
		_buy(state, "axe_0024")
		var parameters: Dictionary = ActiveSkillRules.parameters(skill, 1, {"damage": state.stat("damage") * state.stat("skill_damage"), "skill_haste": state.stat("skill_haste"), "summon_damage": state.stat("summon_damage"), "pulse_radius": state.stat("pulse_radius"), "pulse_cooldown": state.stat("pulse_cooldown")})
		_check(state.active_skill_parameters(state.active_skills[0]) == parameters, "Legacy shared Parashu skill damage still applies to the actual rear exactly once: " + hero)
