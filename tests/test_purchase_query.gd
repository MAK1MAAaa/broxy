extends SceneTree

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var probe := RunState.new()
	if not probe.has_method("purchase_error"):
		_check(false, "RunState provides a read-only purchase_error query")
		_finish()
		return
	_test_rejection_order()
	_test_capacity_and_identity()
	_test_success_boundaries()
	_test_rich_state_queries()
	_finish()


func _new_run() -> RunState:
	var state := RunState.new()
	state.begin(144, "bone")
	return state


func _offer(kind: String, item_id: String, price: int = 20, sold: bool = false) -> Dictionary:
	return {"kind": kind, "id": item_id, "price": price, "sold": sold}


func _test_rejection_order() -> void:
	var state: RunState = _new_run()
	state.offers = [_offer("unknown", "missing", 20, true)]
	_expect_rejection(state, -1, "无效的商品。", "Negative index is rejected before offer checks")
	_expect_rejection(state, 1, "无效的商品。", "An index past the last offer is invalid")
	_expect_rejection(state, 0, "这件商品已售出。", "Sold state precedes price, type and identity checks")
	state.offers = [_offer("unknown", "missing", 20)]
	_expect_rejection(state, 0, "魂屑不足。", "Insufficient currency precedes unknown type and identity")
	state.gold = 100
	for entry: Array in [["weapon", "法器不存在。"], ["rune", "符文不存在。"], ["relic", "遗物不存在。"]]:
		state.offers = [_offer(str(entry[0]), "missing", 20)]
		_expect_rejection(state, 0, str(entry[1]), "Unknown catalog identity: " + str(entry[0]))
	state.offers = [_offer("unknown", "bone", 20)]
	_expect_rejection(state, 0, "未知的商品类型。", "An affordable unknown type has the original error")
	state.offers = [{}]
	_expect_rejection(state, 0, "未知的商品类型。", "A missing type defaults to the original unknown-type error")
	state.offers.clear()
	_expect_rejection(state, 0, "无效的商品。", "An empty shop has no valid purchase index")


func _test_capacity_and_identity() -> void:
	var state: RunState = _new_run()
	state.gold = 1000
	# Fill capacities through successful transactions; do not forge inventory sizes.
	for index: int in 3:
		state.offers = [_offer("weapon", "bone")]
		_check(state.buy_offer(0), "Duplicate legal weapons fill slots through public purchases")
	for index: int in 4:
		state.offers = [_offer("rune", "pierce")]
		_check(state.buy_offer(0), "Legal rune purchases fill the reserve bag")
	for index: int in 3:
		state.offers = [_offer("relic", "damage")]
		_check(state.buy_offer(0), "Legal relic purchases fill its three-stack cap")
	_check(state.loadout.size() == 4 and state.rune_bag.size() == 4 and int(state.relic_counts["damage"]) == 3,
		"The fixture reaches four weapons, four reserve runes and three relic stacks")
	var caps: Array[Array] = [
		["weapon", "bone", "法器槽已满，请先出售一件法器。"],
		["rune", "pierce", "备用符文已满，请先装备或出售。"],
		["relic", "damage", "该遗物已达到3层上限。"],
	]
	for entry: Array in caps:
		state.offers = [_offer(str(entry[0]), str(entry[1]))]
		_expect_rejection(state, 0, str(entry[2]), "Capacity rejection: " + str(entry[0]))
	for entry: Array in [["weapon", "法器不存在。"], ["rune", "符文不存在。"], ["relic", "遗物不存在。"]]:
		state.offers = [_offer(str(entry[0]), "missing")]
		_expect_rejection(state, 0, str(entry[1]), "Unknown identity precedes capacity: " + str(entry[0]))
	state.gold = 0
	for entry: Array in caps:
		state.offers = [_offer(str(entry[0]), str(entry[1]))]
		_expect_rejection(state, 0, "魂屑不足。", "Insufficient money precedes capacity: " + str(entry[0]))

	state.gold = 100
	state.health = 50.0
	state.offers = [_offer("relic", "vitality", 22)]
	_expect_query(state, 0, "", "An unrelated relic remains legal despite other filled capacities")
	_check(state.buy_offer(0) and state.gold == 78 and state.health == 70.0 and state.stat("max_health") == 120.0,
		"A legal vitality transaction charges 22 and increases current and maximum health by 20")
	_check(state.equip_rune(0, 0), "Equipping a reserve rune legally frees a bag slot")
	state.offers = [_offer("rune", "bounce", 18)]
	_expect_query(state, 0, "", "An equipped rune does not consume reserve capacity")
	_check(state.buy_offer(0) and state.rune_bag.size() == 4 and int(state.rune_bag[3]["uid"]) == 5,
		"Rejected purchases and read queries consume no rune UID before the next real purchase")


func _test_success_boundaries() -> void:
	var exact: RunState = _new_run()
	exact.gold = 24
	exact.offers = [_offer("weapon", "bone", 24)]
	_expect_query(exact, 0, "", "A balance exactly equal to the price is sufficient")
	_expect_success_signal(exact, "The exact-balance purchase emits once and clears the previous error")
	_check(exact.gold == 0 and exact.loadout.size() == 2 and exact.loadout[0]["id"] == "bone" and exact.loadout[1]["id"] == "bone"
		and int(exact.loadout[1]["paid"]) == 24 and bool(exact.offers[0]["sold"]),
		"The exact-balance purchase spends exactly 24 and permits an identical second weapon")
	_expect_rejection(exact, 0, "这件商品已售出。", "The real successful offer cannot be repurchased at zero remaining gold")

	var free: RunState = _new_run()
	free.offers = [_offer("rune", "blast", 0)]
	_expect_query(free, 0, "", "A zero-price rune is affordable with a zero balance")
	_expect_success_signal(free, "A zero-price purchase retains normal success feedback")
	_check(free.gold == 0 and free.rune_bag.size() == 1 and free.rune_bag[0] == {"id": "blast", "paid": 0, "uid": 1}
		and bool(free.offers[0]["sold"]), "A free rune is still a single owned, sold and UID-assigned item")
	free.offers = [{"kind": "weapon", "id": "frost"}]
	_expect_query(free, 0, "", "A missing optional price and sold flag retain the existing free-unsold defaults")
	_check(free.buy_offer(0) and free.gold == 0 and int(free.loadout[1]["paid"]) == 0 and bool(free.offers[0]["sold"]),
		"Defaulted optional offer fields preserve their existing transaction behavior")


func _test_rich_state_queries() -> void:
	var state: RunState = _new_run()
	state.collect_souls(102)
	var choices: Array[Dictionary] = state.upgrade_choices()
	_check(state.choose_upgrade(str(choices[0]["id"])), "The read-only fixture includes a legally selected upgrade bonus")
	state.upgrade_choices()
	state.take_damage(11.0, "caster", "projectile")
	state.generate_shop()
	state.offers = [_offer("weapon", "scatter", 20), _offer("rune", "pierce", 18), _offer("relic", "armor", 20), _offer("unknown", "missing", 20)]
	for index: int in 3:
		_expect_query(state, index, "", "Rich state remains untouched by an affordable query: " + str(index))
	_expect_query(state, 3, "未知的商品类型。", "Rich state remains untouched by a rejected query")
	_check(state.pending_upgrades == 1 and not state.get("_upgrade_bonuses").is_empty() and not state.get("_upgrade_options").is_empty()
		and state.hits_taken == 1, "Query purity is checked with nonempty bonuses, cached choices and damage history")


func _expect_query(state: RunState, index: int, expected: String, label: String) -> void:
	state.last_error = "保留前次操作错误"
	var before: Dictionary = _snapshot(state)
	var emissions: Array[int] = [0]
	var observe: Callable = func() -> void: emissions[0] += 1
	state.changed.connect(observe)
	var stable: bool = true
	for repetition: int in 3:
		stable = str(state.call("purchase_error", index)) == expected and stable
	_check(stable, label + " — literal error and repeated result")
	_check(_snapshot(state) == before and emissions[0] == 0, label + " — query is read-only and emits no changed signal")
	state.changed.disconnect(observe)


func _expect_rejection(state: RunState, index: int, expected: String, label: String) -> void:
	_expect_query(state, index, expected, label)
	var before: Dictionary = _snapshot(state)
	var emissions: Array[int] = [0]
	var observe: Callable = func() -> void: emissions[0] += 1
	state.changed.connect(observe)
	_check(not state.buy_offer(index) and state.last_error == expected and emissions[0] == 1,
		label + " — real purchase retains the old error and one changed signal")
	var after: Dictionary = _snapshot(state)
	after["last_error"] = before["last_error"]
	_check(after == before, label + " — rejected purchase preserves currency, inventory, offers, bonuses and rune UIDs")
	state.changed.disconnect(observe)


func _expect_success_signal(state: RunState, label: String) -> void:
	var emissions: Array[int] = [0]
	var observe: Callable = func() -> void: emissions[0] += 1
	state.changed.connect(observe)
	var previous_rng: int = state.rng.state
	_check(state.buy_offer(0) and state.last_error.is_empty() and emissions[0] == 1 and state.rng.state == previous_rng, label)
	state.changed.disconnect(observe)


func _snapshot(state: RunState) -> Dictionary:
	return {"summary": state.summary(), "offers": state.offers.duplicate(true), "last_error": state.last_error,
		"rng_state": state.rng.state, "rng_seed": state.rng.seed, "next_rune_uid": state.get("_next_rune_uid"),
		"bonuses": state.get("_upgrade_bonuses").duplicate(true), "choices": state.get("_upgrade_options").duplicate(true),
		"wave_income": state.get("_wave_income"), "wave_finished": state.get("_wave_finished"), "rerolls": state.rerolls}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _finish() -> void:
	print("PurchaseQuery: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
