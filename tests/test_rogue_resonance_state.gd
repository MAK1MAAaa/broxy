extends SceneTree
## Combined core rewards, candle priority and PR4 resonance use real inventory UIDs.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_grants_and_snapshot_isolation()
	_test_candle_updates_both_effects()
	_test_combined_forecasts()
	_test_full_grant_rollback_and_reward()
	print("RogueResonanceState: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261026, "bone")
	state.gold = 10000
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	_check(state.buy_offer(0), "The combined fixture purchases its real item: " + id)
	return uid

func _weapon(state: RunState, uid: int) -> Dictionary:
	var index: int = state.weapon_index_for_uid(uid)
	return state.loadout[index] if index >= 0 else {}

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, str(state.rng.seed), str(state.rng.state), state._next_rune_uid])

func _test_grants_and_snapshot_isolation() -> void:
	for core: String in ["bone_chorus", "frostfire"]:
		var state: RunState = _state()
		var armor: int = _buy(state, "relic", "armor")
		var gift_uid: int = int(state.backpack_snapshot()["next_uid"])
		state.finish_wave()
		var gold: int = state.gold
		var rng_before: int = state.rng.state
		_check(state.choose_core(core), "A real core grant survives the combined state implementation: " + core)
		var gift: Dictionary = _weapon(state, gift_uid)
		_check(not gift.is_empty() and int(gift["paid"]) == 0 and int(gift["rank"]) == 1 and gift["id"] == ("bone" if core == "bone_chorus" else "frost"), "The granted weapon has its actual new UID, free purchase basis and expected identity")
		_check(gift["resonance_sources"] == [armor] and is_equal_approx(float(gift["resonance_bonus"]), 0.03), "The actual grant placement touches the purchased armor and receives its UID-based resonance metadata")
		var expected: float = GameCatalog.weapon(str(gift["id"])).damage * 1.03
		_check(is_equal_approx(state.weapon_damage(gift), expected) and is_equal_approx(state.weapon_damage(state.backpack_item(gift_uid)), expected), "Projected and raw granted-item queries agree on the same live local damage")
		_check(state.gold == gold and state.rng.state == rng_before and state.core_id == core, "Resonance evaluation does not charge, draw RNG or discard the selected core")
		_check(state.choose_route("swarm"), "The combined core can retain an independent next-wave route")
		var before: String = _signature(state)
		var changed: Array[int] = [0]
		state.changed.connect(func() -> void: changed[0] += 1)
		var snapshot: Dictionary = state.backpack_snapshot()
		_check(snapshot.has("linked_weapons") and snapshot.has("resonance"), "A grid snapshot retains both directional links and local resonance")
		snapshot["linked_weapons"].append(999)
		snapshot["resonance"][gift_uid]["source_uids"].append(999)
		snapshot["resonance"][gift_uid]["bonus"] = 99.0
		var summary: Dictionary = state.summary()
		summary["rogue"]["core_id"] = "wrong"
		summary["loadout"][0]["resonance_sources"].clear()
		_check(_signature(state) == before and changed[0] == 0, "Mutating either nested projection cannot alter core, route, resonance cache, RNG, currency, UIDs or signals")
		_check(state.move_item(armor, Vector2i(5,3), false) and _weapon(state,gift_uid)["resonance_sources"].is_empty() and _weapon(state,gift_uid)["resonance_bonus"] == 0.0, "Moving a real source recomputes metadata for gifted weapons")
		_check(state.core_id == core and state.next_route == "swarm", "Arranging a source never resets a core or pending route")

func _test_candle_updates_both_effects() -> void:
	var state: RunState = _state()
	state.finish_wave()
	_check(state.choose_core("bone_chorus"), "The directional fixture obtains its second bone through the actual core")
	var first: int = int(state.loadout[0]["uid"])
	var second: int = int(state.loadout[1]["uid"])
	var candle: int = _buy(state,"relic","grave_candle")
	_check(state.linked_weapon_uids().is_empty() and _weapon(state,first)["resonance_bonus"] == 0.0 and is_equal_approx(float(_weapon(state,second)["resonance_bonus"]),0.03), "A candle beside the second bone grants local resonance without directional priority")
	var gold: int = state.gold
	var rng_before: int = state.rng.state
	_check(state.move_item(candle,Vector2i(0,3),false), "The actual wide candle can move below both legal weapon footprints")
	_check(state.linked_weapon_uids() == [first,second] and state.backpack_snapshot()["linked_weapons"] == [first,second], "Touching the bottom edge activates both directional weapon UIDs")
	for uid: int in [first,second]:
		_check(_weapon(state,uid)["resonance_sources"] == [candle] and is_equal_approx(float(_weapon(state,uid)["resonance_bonus"]),0.03), "The same candle move updates both weapons' independent resonance cache")
	_check(state.gold == gold and state.rng.state == rng_before and state.core_id == "bone_chorus", "Changing both candle effects preserves the core, currency and random stream")
	_check(state.move_item(candle,Vector2i(4,3),false) and state.linked_weapon_uids().is_empty(), "Moving the candle away removes directional priority")
	_check(_weapon(state,first)["resonance_bonus"] == 0.0 and _weapon(state,second)["resonance_bonus"] == 0.0, "The same away move clears both local resonance bonuses")

func _test_combined_forecasts() -> void:
	var state: RunState = _state()
	var armor: int = _buy(state,"relic","armor")
	state.finish_wave()
	_check(state.choose_core("bone_chorus") and state.choose_route("bulwark"), "The forecast fixture establishes an actual core and pending route")
	var first: int = int(state.loadout[0]["uid"])
	var gifted: int = int(state.loadout[1]["uid"])
	var before: String = _signature(state)
	var error_before: String = state.last_error
	var preview: Dictionary = state.merge_preview(gifted,first)
	_check(preview["can_merge"] and is_equal_approx(float(preview["damage_before"]),14.0*1.03) and is_equal_approx(float(preview["source_damage_before"]),14.0*1.03), "A core-gift merge forecasts each real neighboring weapon's local damage")
	_check(is_equal_approx(float(preview["damage_after"]),28.0*1.03) and is_equal_approx(float(preview["resonance_after"]),0.03), "The merge forecasts the surviving UID's rank and actual shared relic edge")
	_check(_signature(state) == before and state.last_error == error_before, "Merge projection leaves the core, route and cache snapshot untouched")
	_check(state.merge_items(gifted,first) and is_equal_approx(state.weapon_damage(_weapon(state,first)),float(preview["damage_after"])), "The actual gifted-weapon merge matches its local-damage forecast")
	_check(state.backpack_item(gifted).is_empty() and state.core_id == "bone_chorus" and state.next_route == "bulwark", "The consumed gift leaves no stale UID and preserves independent rogue choices")
	state.offers = [{"kind":"weapon","id":"frost","price":24,"sold":false}]
	before = _signature(state)
	preview = state.weapon_purchase_preview(0)
	_check(preview["can_buy"] and preview["resonance_sources"] == [armor] and is_equal_approx(float(preview["damage"]),11.0*1.03), "Weapon shopping still previews its actual placement resonance while a core is selected")
	_check(_signature(state) == before, "Weapon projection cannot reset rogue or cache state")
	_check(state.buy_offer(0) and is_equal_approx(state.weapon_damage(state.loadout.back()),float(preview["damage"])), "The purchased weapon matches the combined-state damage forecast")
	var incoming: int = _buy(state,"rune","pierce")
	before = _signature(state)
	preview = state.rune_equip_preview(state.rune_index_for_uid(incoming),state.weapon_index_for_uid(first))
	_check(is_equal_approx(float(preview["damage"]),state.weapon_damage(_weapon(state,first))) and is_equal_approx(float(preview["resonance_bonus"]),0.03), "Rune projection retains current rank-weighted local damage")
	_check(_signature(state) == before and state.equip_rune(state.rune_index_for_uid(incoming),state.weapon_index_for_uid(first)), "A read-only rune forecast can be followed by its actual socket transaction")
	_check(state.core_id == "bone_chorus" and state.next_route == "bulwark" and _weapon(state,first)["rune"]["uid"] == incoming and _weapon(state,first)["resonance_sources"] == [armor], "Socketing preserves the core, route and actual resonance sources")
	state.offers = [{"kind":"relic","id":"damage","price":18,"sold":false}]
	before = _signature(state)
	preview = state.relic_purchase_preview(0)
	_check(preview["can_buy"] and not preview["weapon_changes"].is_empty() and _signature(state) == before, "Relic projection combines global and local changes without disturbing rogue choices")
	_check(state.buy_offer(0), "The predicted relic purchase commits through normal transaction checks")
	for change: Dictionary in preview["weapon_changes"]:
		var actual: Dictionary = _weapon(state,int(change["uid"]))
		_check(is_equal_approx(state.weapon_damage(actual),float(change["damage_after"])) and is_equal_approx(float(actual["resonance_bonus"]),float(change["resonance_after"])), "The purchased relic's actual global/local damage agrees with each UID-specific projection")
	_check(state.core_id == "bone_chorus" and state.next_route == "bulwark", "Purchasing a projected relic keeps the selected core and next route")

func _test_full_grant_rollback_and_reward() -> void:
	var state: RunState = _state()
	for number: int in 18:
		_buy(state,"relic","damage")
	state.finish_wave()
	state.next_wave()
	state.finish_wave()
	_check(state.choose_altar(true) and state.choose_route("bulwark"), "The nearly-full fixture records actual independent altar and route choices")
	_check(state.backpack.can_add("weapon","frost") and int(state.backpack_snapshot()["used_cells"]) == 21, "There is space for the first frostfire gift but not its complete pair")
	var before: String = _signature(state)
	var old_error: String = state.last_error
	_check(not state.choose_core("frostfire") and _signature(state) == before and state.last_error != old_error, "A multi-gift failure preserves all resonance, items, UID, wallet, RNG and rogue flags except its rejection text")
	_check(state.core_id.is_empty() and state.altar_choice == "accepted" and state.next_route == "bulwark", "Rejected core selection cannot discard an accepted hunter or route")
	state.next_wave()
	state.record_hunter_defeat()
	state.finish_wave()
	var resonance: Dictionary = state.backpack_snapshot()["resonance"]
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	_check(state.claim_altar_rune("blast"), "An earned altar rune enters its real spare cell through the production claim")
	_check(state.rune_bag.back()["uid"] == uid and int(state.rune_bag.back()["paid"]) == 0 and state.backpack_snapshot()["resonance"] == resonance, "The reward has a fresh free UID and loose runes do not become resonance sources")
	_check(state.hunter_defeated and not state.rune_reward_pending and state.active_route == "bulwark" and state.core_id.is_empty(), "Reward projection keeps completed hunter and active route state")
