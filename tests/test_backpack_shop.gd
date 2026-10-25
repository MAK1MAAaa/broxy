extends "res://tests/simulate_runs.gd"
## Checks the backpack shopping policy and immutable observation records.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_observations()
	_test_expansion()
	_test_policy_transactions()
	print("BackpackShop: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261024, "bone")
	state.gold = 1000
	return state

func _offer(kind: String, id: String, price: int = 20, sold: bool = false) -> Dictionary:
	return {"kind": kind, "id": id, "price": price, "sold": sold}

func _buy(state: RunState, kind: String, id: String) -> int:
	state.offers = [_offer(kind, id)]
	_check(state.buy_offer(0), "Policy fixture uses the real inventory transaction: " + id)
	return int(state.backpack_snapshot()["items"].back()["uid"])

func _test_observations() -> void:
	var state: RunState = _state()
	state.offers = [_offer("weapon", "bone"), _offer("weapon", "bone"), _offer("rune", "bounce"), _offer("relic", "damage", 20, true)]
	var signature: String = JSON.stringify(state.backpack_snapshot())
	var rng_before: int = state.rng.state
	var observations: Array[Dictionary] = []
	_observe_shop(state, "pierce", observations, "initial", "fixture")
	_check(JSON.stringify(state.backpack_snapshot()) == signature and state.rng.state == rng_before, "Policy observation changes neither layout nor RNG")
	_check(observations[0]["offers"].size() == 4 and observations[0]["evaluations"].size() == 4, "Every offer keeps its independent evaluation")
	_check(observations[0]["evaluations"][2]["reason"] == "target_rune_mismatch" and observations[0]["evaluations"][3]["reason"] == "sold", "Rejected policy offers keep explicit reasons and null scores")
	state.gold = 20
	state.rerolls = MAX_REROLLS
	var trace: Array[Dictionary] = []
	_shop(state, "pierce", trace, observations)
	_check(state.offers[0]["sold"] and not state.offers[1]["sold"], "Equal policy scores retain the first-offer tie break")
	_check(not observations[0]["offers"][0]["sold"] and observations[0]["backpack"]["items"].size() == 1, "Later purchases and merges cannot rewrite earlier observations")
	_check(int(state.loadout[0]["rank"]) == 2 and state.loadout.size() == 1, "The explicit policy merge upgrades the bought duplicate")
	_check(observations.back()["reason"] == "reroll_limit", "The policy records its refresh stopping condition")
	_check(JSON.parse_string(JSON.stringify(observations)) != null, "Observation records remain valid JSON")

func _test_expansion() -> void:
	var state: RunState = _state()
	while state.backpack.can_add("relic", "armor"):
		_buy(state, "relic", "armor")
	state.gold = 100
	state.offers = [_offer("weapon", "ember")]
	_check(_evaluate_offer(state, state.offers[0], "pierce")["reason"] == "backpack_full", "A useful weapon is rejected by real footprint capacity")
	_check(_evaluate_offer(state, state.offers[0], "pierce", true)["reason"] == "eligible", "Expansion planning may inspect preference independently of space")
	var trace: Array[Dictionary] = []
	_check(_expand_for_offer(state, "pierce", trace) and state.gold == 68 and state.backpack_snapshot()["height"] == 5, "Expansion pays the formal first-row price")
	_check(_expand_for_offer(state, "pierce", trace) and state.gold == 20 and state.backpack_snapshot()["height"] == 6, "A two-row footprint may require the second paid expansion")
	_check(state.backpack.can_add("weapon", "ember") and state.buy_offer(0), "Expansion makes the previously blocked footprint actually purchasable")
	_check(trace.size() == 2 and trace[0]["paid"] == 32 and trace[1]["paid"] == 48, "Every expansion is separately observable")
	_check(not _expand_for_offer(state, "pierce", trace), "Maximum backpack height stops expansion")

func _test_policy_transactions() -> void:
	var state: RunState = _state()
	_buy(state, "weapon", "bone")
	_buy(state, "weapon", "bone")
	_buy(state, "weapon", "bone")
	for index: int in 4:
		_buy(state, "rune", "pierce")
	var gold: int = state.gold
	var trace: Array[Dictionary] = []
	_manage_backpack(state, "pierce", trace)
	_check(state.loadout.size() == 1 and state.loadout[0]["rank"] == 3, "Policy makes the three explicit merges needed for a third-rank weapon")
	_check(state.loadout[0]["rune"].get("rank", 0) == 3 and state.rune_bag.is_empty(), "Policy merges loose runes before equipping their actual rank")
	_check(state.gold == gold, "Policy inventory management adds no rewards")
	var merges: int = 0
	for event: Dictionary in trace:
		if event["action"] == "merge":
			merges += 1
			_check(event["to_rank"] == int(event["from_rank"]) + 1 and event["used_cells_after"] < event["used_cells_before"], "Each policy merge records real rank and space changes")
	_check(merges == 6, "Weapon and rune upgrades each require three recorded merges")
	var before: String = JSON.stringify(state.backpack_snapshot())
	var trace_count: int = trace.size()
	_manage_backpack(state, "pierce", trace)
	_check(JSON.stringify(state.backpack_snapshot()) == before and trace.size() == trace_count, "Repeated management terminates once no merge or rank improvement remains")
