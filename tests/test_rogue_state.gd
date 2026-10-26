extends SceneTree
## Decisions use the shipped RunState and formal inventory transactions.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_core_transactions()
	_test_altar_and_reserved_reward()
	_test_routes()
	_test_position_links()
	_test_readonly_snapshots()
	print("RogueState: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(starter: String = "bone") -> RunState:
	var state := RunState.new()
	state.begin(20261026, starter)
	state.gold = 10000
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var next_uid: int = int(state.backpack_snapshot()["next_uid"])
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	_check(state.buy_offer(0), "The formal fixture purchase succeeds: " + kind + "/" + id)
	return next_uid

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, str(state.rng.state), state._next_rune_uid])

func _fill(state: RunState) -> void:
	while state.backpack.can_add("relic", "damage"):
		_buy(state, "relic", "damage")

func _test_core_transactions() -> void:
	var state: RunState = _state()
	var before: String = _signature(state)
	_check(not state.choose_core("frostfire") and _signature(state) == before, "A core cannot be chosen during live combat")
	state.finish_wave()
	before = _signature(state)
	_check(not state.choose_core("missing") and _signature(state) == before, "An invalid core does not alter inventory, gold, RNG or UID")
	var gold: int = state.gold
	var rng_state: int = state.rng.state
	_check(state.choose_core("frostfire"), "A completed ordinary wave permits one core choice")
	_check(state.core_id == "frostfire" and state.loadout.size() == 3, "Frostfire supplies both required weapon identities alongside the original weapon")
	_check(state.gold == gold and state.rng.state == rng_state and state.xp == 0, "Choosing a core consumes neither currency nor RNG and grants no experience")
	var grants: Array[int] = []
	for weapon: Dictionary in state.loadout:
		_check(int(weapon["paid"]) == 0 and int(weapon["rank"]) == 1, "A starter or granted core weapon has rank1 and zero resale basis")
		if str(weapon["id"]) in ["frost", "ember"]:
			grants.append(int(weapon["uid"]))
	before = _signature(state)
	_check(not state.choose_core("bone_chorus") and _signature(state) == before, "A second core cannot replace the first or repeat a grant")
	for uid: int in grants:
		_check(state.sell_item(uid) and state.gold == gold, "Selling a free core weapon cannot create currency")
	state.begin(20261027, "frost")
	state.finish_wave()
	_check(state.core_id.is_empty() and state.choose_core("frostfire") and state.loadout.size() == 2, "Restart resets the core and an already-owned required weapon is not duplicated")
	_check(state.loadout[0]["id"] == "frost" and state.loadout[1]["id"] == "ember", "An owned required weapon retains its UID and only the missing weapon is supplied")
	var chorus: RunState = _state()
	chorus.finish_wave()
	_check(chorus.choose_core("bone_chorus") and chorus.loadout.size() == 2, "Bone chorus supplies one additional bone even when its starter is already owned")
	var granted_bone: Dictionary = chorus.loadout[1]
	_check(granted_bone["id"] == "bone" and int(granted_bone["paid"]) == 0 and int(granted_bone["rank"]) == 1, "The additional chorus weapon is a real free rank1 inventory item")
	gold = chorus.gold
	_check(chorus.sell_item(int(granted_bone["uid"])) and chorus.gold == gold, "Selling the additional chorus weapon does not create currency")
	before = _signature(chorus)
	_check(not chorus.choose_core("bone_chorus") and _signature(chorus) == before, "Selling its gift cannot reopen the one-time chorus transaction")
	var full_chorus: RunState = _state()
	_fill(full_chorus)
	full_chorus.finish_wave()
	before = _signature(full_chorus)
	_check(not full_chorus.choose_core("bone_chorus") and _signature(full_chorus) == before and full_chorus.core_id.is_empty(), "An existing bone does not bypass the mandatory extra gift's real capacity check")
	_check(full_chorus.expand_backpack() and full_chorus.choose_core("bone_chorus") and full_chorus.loadout.size() == 2, "A rejected chorus can be retried once a real backpack row is purchased")
	var ember_chorus: RunState = _state("ember")
	ember_chorus.finish_wave()
	_check(ember_chorus.choose_core("bone_chorus") and ember_chorus.loadout.size() == 2 and ember_chorus.loadout[1]["id"] == "bone", "An alternate starter still receives exactly one chorus bone")
	var partial: RunState = _state()
	for count: int in 18:
		_buy(partial, "relic", "damage")
	partial.finish_wave()
	_check(partial.backpack.can_add("weapon", "frost") and int(partial.backpack_snapshot()["used_cells"]) == 21, "The capacity fixture has room for the first core grant but not both")
	before = _signature(partial)
	_check(not partial.choose_core("frostfire") and _signature(partial) == before and partial.core_id.is_empty(), "A failed second grant rolls back the first grant, next UID, projections and core selection")
	var removed: int = -1
	for item: Dictionary in partial.backpack_snapshot()["items"]:
		if str(item["kind"]) == "relic":
			removed = int(item["uid"])
			break
	_check(partial.sell_item(removed), "The player can make room through a real sale after a rejected core")
	partial.gold = 10000
	_check(partial.expand_backpack() and partial.expand_backpack() and partial.choose_core("frostfire"), "The same unspent core can be chosen after real capacity expansion")
	state.wave = 8
	state.core_id = ""
	before = _signature(state)
	_check(not state.choose_core("bone_chorus") and _signature(state) == before, "No core grant is available after the final boss wave")

func _test_altar_and_reserved_reward() -> void:
	var state: RunState = _state()
	_check(not state.choose_altar(true), "The altar cannot be accepted before its scheduled wave")
	state.finish_wave()
	state.next_wave()
	_check(not state.choose_altar(true), "A live second wave cannot be skipped into its altar")
	state.finish_wave()
	var before: String = _signature(state)
	_check(not state.claim_altar_rune("pierce") and _signature(state) == before, "A rune reward cannot be claimed before defeating its hunter")
	_check(state.choose_altar(true) and state.altar_choice == "accepted" and state.altar_wave == 3, "Accepting the second-wave altar schedules one hunter for wave3")
	before = _signature(state)
	_check(not state.choose_altar(false) and _signature(state) == before, "A second altar click cannot reverse the recorded decision")
	state.record_hunter_defeat()
	_check(not state.hunter_defeated and not state.rune_reward_pending, "A defeat signal from the wrong wave grants nothing")
	state.next_wave()
	var changed: Array[int] = [0]
	state.changed.connect(func() -> void: changed[0] += 1)
	state.record_hunter_defeat()
	_check(state.hunter_defeated and state.rune_reward_pending and changed[0] == 0, "The scheduled hunter sets one reserved reward without emitting mid-combat UI changes")
	before = _signature(state)
	state.record_hunter_defeat()
	_check(_signature(state) == before and changed[0] == 0, "Repeated hunter death callbacks cannot duplicate the reward")
	_check(not state.claim_altar_rune("pierce"), "The player must survive to a wave-end before claiming the reserve")
	state.finish_wave()
	_fill(state)
	before = _signature(state)
	_check(not state.claim_altar_rune("pierce") and _signature(state) == before and state.rune_reward_pending, "A full backpack preserves the unclaimed reward and allocation state")
	state.next_wave()
	_check(state.rune_reward_pending, "A reward remains reserved when the player proceeds without space")
	state.finish_wave()
	var sold_uid: int = -1
	for item: Dictionary in state.backpack_snapshot()["items"]:
		if str(item["kind"]) == "relic":
			sold_uid = int(item["uid"])
			break
	_check(state.sell_item(sold_uid), "A real sale opens a reward cell")
	before = _signature(state)
	_check(not state.claim_altar_rune("missing") and _signature(state) == before, "An invalid reward identity does not consume the reserve")
	var gold: int = state.gold
	var rng_state: int = state.rng.state
	_check(state.claim_altar_rune("pierce") and not state.rune_reward_pending and state.rune_bag.size() == 1, "A chosen reward enters inventory once capacity exists")
	var rune: Dictionary = state.rune_bag[0]
	_check(int(rune["rank"]) == 1 and int(rune["paid"]) == 0 and state.gold == gold and state.rng.state == rng_state, "The reserved rune is free rank1 and does not alter currency or randomness")
	before = _signature(state)
	_check(not state.claim_altar_rune("blast") and _signature(state) == before, "Repeated reward claims cannot create a second rune")
	_check(state.sell_item(int(rune["uid"])) and state.gold == gold, "The free reward has no sell-for-currency exploit")
	var declined: RunState = _state()
	declined.finish_wave()
	declined.next_wave()
	declined.finish_wave()
	_check(declined.choose_altar(false) and declined.altar_choice == "declined" and declined.altar_wave == -1, "Declining the optional altar schedules no enemy or payment")
	declined.next_wave()
	declined.record_hunter_defeat()
	_check(not declined.hunter_defeated and not declined.rune_reward_pending, "A declined altar cannot acquire a reward through a defeat callback")
	state.begin(99, "bone")
	_check(state.altar_choice.is_empty() and state.altar_wave == -1 and not state.hunter_defeated and not state.rune_reward_pending, "Restart clears all altar and reserve flags")

func _test_routes() -> void:
	for route: String in ["balanced", "swarm", "bulwark"]:
		var state: RunState = _state()
		var before: String = _signature(state)
		_check(not state.choose_route(route) and _signature(state) == before, "Route choices cannot mutate a running wave")
		state.finish_wave()
		var wallet: int = state.gold
		var xp: int = state.xp
		var rng_state: int = state.rng.state
		_check(state.choose_route(route) and state.next_route == route, "The chosen route is visible before starting its wave")
		var changed: Array[int] = [0]
		state.changed.connect(func() -> void: changed[0] += 1)
		_check(state.choose_route(route) and changed[0] == 0, "Repeating the current route is idempotent")
		_check(state.gold == wallet and state.rng.state == rng_state, "Choosing a route has no immediate money or RNG side effect")
		state.next_wave()
		_check(state.active_route == route and state.next_route == "balanced", "Starting consumes the selected route for exactly one wave")
		state.finish_wave()
		var reward: int = int(RogueRules.route(route)["reward"])
		_check(state.gold == wallet + 34 + reward and state.xp == xp, "Route income is added once outside the minimum budget and does not grant XP: " + route)
		wallet = state.gold
		state.finish_wave()
		_check(state.gold == wallet, "Repeated settlement cannot duplicate a route reward")
		state.next_wave()
		_check(state.active_route == "balanced", "An unselected subsequent wave returns to its original enemy route")
	var boss: RunState = _state()
	boss.wave = 7
	boss.finish_wave()
	var before: String = _signature(boss)
	_check(not boss.choose_route("swarm") and _signature(boss) == before, "The last shop cannot replace the final boss with a route")
	boss.next_route = "bulwark"
	boss.next_wave()
	_check(boss.wave == 8 and boss.active_route == "balanced", "Even a stale route cannot alter the boss wave")
	var state: RunState = _state()
	state.finish_wave()
	before = _signature(state)
	_check(not state.choose_route("missing") and _signature(state) == before, "Invalid route identities are rejected without consuming state")
	state.begin(123, "bone")
	_check(state.next_route == "balanced" and state.active_route == "balanced", "Restart restores both route slots")

func _test_position_links() -> void:
	var state: RunState = _state()
	var bone: int = int(state.loadout[0]["uid"])
	var candle: int = _buy(state, "relic", "grave_candle")
	_check(state.linked_weapon_uids().is_empty(), "A candle beside a weapon does not count as a vertical link")
	_check(state.move_item(candle, Vector2i(0,3), false) and state.linked_weapon_uids() == [bone], "A candle directly below a weapon links it through a shared horizontal span")
	var second_bone: int = _buy(state, "weapon", "bone")
	_check(state.linked_weapon_uids() == [bone,second_bone], "A wide candle can link both touching one-column weapons")
	_check(state.backpack_snapshot()["linked_weapons"] == state.linked_weapon_uids(), "The grid snapshot exposes the same linked weapon UID set")
	_check(state.move_item(candle, Vector2i(4,3), false) and state.linked_weapon_uids().is_empty(), "Breaking the shared span immediately removes the targeting link")
	_check(state.move_item(second_bone, Vector2i(5,0), false), "The second weapon can be moved out of the rotation footprint")
	_check(state.move_item(bone, Vector2i(0,0), true) and state.move_item(candle, Vector2i(2,1), false) and state.linked_weapon_uids() == [bone], "Rotated weapon dimensions drive the vertical touching edge")
	var wide: RunState = _state("ember")
	var ember: int = int(wide.loadout[0]["uid"])
	var one: int = _buy(wide, "relic", "grave_candle")
	var two: int = _buy(wide, "relic", "grave_candle")
	_check(wide.move_item(one, Vector2i(0,2), true) and wide.move_item(two, Vector2i(1,2), true), "Two rotated candles legally fit below a wide weapon")
	_check(wide.linked_weapon_uids() == [ember], "Multiple candles affect one weapon only once and keep their direction toward screen-up")
	_check(wide.sell_item(one) and wide.linked_weapon_uids() == [ember] and wide.sell_item(two) and wide.linked_weapon_uids().is_empty(), "Selling linked relics updates the real targeting set without stale marks")

func _test_readonly_snapshots() -> void:
	var state: RunState = _state()
	state.finish_wave()
	var before: String = _signature(state)
	var last_error: String = state.last_error
	var changed: Array[int] = [0]
	state.changed.connect(func() -> void: changed[0] += 1)
	var expected: Dictionary = state.rogue_choices()
	var detached: Dictionary = state.rogue_choices()
	detached["core_options"][0]["name"] = "changed"
	detached["core_options"][0]["weapons"].clear()
	detached["route_options"][1]["weights"].clear()
	detached["linked_weapons"].append(999)
	var bag: Dictionary = state.backpack_snapshot()
	bag["linked_weapons"].append(888)
	_check(state.rogue_choices() == expected and _signature(state) == before and state.last_error == last_error and changed[0] == 0, "Decision and link snapshots are deep detached and preserve errors, RNG, UID, wallet and signals")
	_check(RogueRules.core("unknown").is_empty() and RogueRules.route("unknown").is_empty(), "Unknown rule definitions return no selectable content")
