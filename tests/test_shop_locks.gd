extends SceneTree
## Shop reservations preserve player choices without changing an unlocked shop's RNG.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_lock_contract()
	_test_refresh_and_unlock()
	_test_cross_wave_guarantees()
	_test_ranked_skill_reservations()
	_test_transactions_and_backpack_capacity()
	_test_begin_and_queries()
	_test_zero_lock_reference()
	print("ShopLocks: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(seed_value: int = 2026) -> RunState:
	var state: RunState = RunState.new()
	state.begin(seed_value, "bone")
	state.gold = 10000
	return state

func _offer(kind: String, id: String, price: int = -1, rank: int = 1) -> Dictionary:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	var result: Dictionary = {"kind": kind, "id": id, "price": definition.price if price < 0 else price, "sold": false}
	if kind == "skill":
		result["rank"] = rank
		if price < 0:
			result["price"] = definition.price * rank
	return result

func _stock(state: RunState) -> void:
	state.offers = [
		_offer("weapon", "crescent"), _offer("rune", "blast"),
		_offer("relic", "hourglass"), _offer("relic", "pilgrim"),
	]

func _fill_backpack(state: RunState) -> void:
	var retained: Dictionary = state.offers[3].duplicate(true)
	for count: int in range(36):
		if not state.backpack.can_add("rune", "pierce"):
			break
		state.offers[3] = _offer("rune", "pierce")
		_check(state.buy_offer(3), "One-cell purchases fill real backpack space without changing reserved slots")
	state.offers[3] = retained
	var snapshot: Dictionary = state.backpack_snapshot()
	_check(snapshot["used_cells"] == snapshot["total_cells"], "The lock fixture reaches a genuinely full backpack")

func _snapshot(state: RunState) -> Dictionary:
	return {
		"summary": state.summary(), "offers": state.offers.duplicate(true),
		"locks": state._locked_offers.duplicate(true), "rng": state.rng.state, "rng_seed": state.rng.seed,
		"uid": state._next_rune_uid, "error": state.last_error, "rerolls": state.rerolls,
		"choices": state._upgrade_options.duplicate(true), "bonuses": state._upgrade_bonuses.duplicate(true),
		"income": state._wave_income, "settled": state._wave_finished,
	}

func _expect_rejected_lock(state: RunState, index: int, expected: String) -> void:
	var before: Dictionary = _snapshot(state)
	_check(state.shop_lock_error(index) == expected and _snapshot(state) == before, "Lock rejection query is exact and read-only: " + expected)
	_check(not state.set_offer_locked(index, true) and state.last_error == expected, "Lock transaction reports the formal rejection: " + expected)
	var after: Dictionary = _snapshot(state)
	after["error"] = before["error"]
	_check(after == before, "Rejected lock preserves money, inventory, locks, offers and RNG")

func _test_lock_contract() -> void:
	var state: RunState = _state()
	_stock(state)
	state.gold = 0
	var before: Dictionary = _snapshot(state)
	_check(RunState.SHOP_LOCK_CAP == 2 and state.set_offer_locked(0, true) and state.set_offer_locked(3, true), "Two unaffordable unsold items can be reserved without paying")
	_check(state.is_offer_locked(0) and state.is_offer_locked(3) and state.locked_offer_count() == 2 and state.gold == 0 and state.rng.state == before["rng"] and state.offers == before["offers"], "Locks are independent snapshots rather than mutations to old offer dictionaries")
	_check(state.shop_lock_error(0).is_empty(), "An existing lock does not reject itself at the global cap")
	var stable: Dictionary = _snapshot(state)
	_check(state.set_offer_locked(0, true) and _snapshot(state) == stable, "Setting an existing lock is idempotent")
	_expect_rejected_lock(state, 1, "最多锁定2件商品，请先解锁一件。")
	_check(state.set_offer_locked(0, false) and not state.is_offer_locked(0) and state.locked_offer_count() == 1 and state.offers == before["offers"], "Unlocking frees capacity without changing the visible stock")
	_check(state.set_offer_locked(1, true) and state.locked_offer_count() == 2, "A released reservation can be assigned to another item")
	_expect_rejected_lock(state, -1, "无效的商品。")
	_expect_rejected_lock(state, 4, "无效的商品。")
	state.offers[2]["sold"] = true
	_expect_rejected_lock(state, 2, "已售商品无法锁定。")
	state.offers[2] = {"kind": "relic", "id": "missing", "price": 20, "sold": false}
	_expect_rejected_lock(state, 2, "商品不存在，无法锁定。")
	state.offers[2] = {"kind": "unknown", "id": "bone", "price": 20, "sold": false}
	_expect_rejected_lock(state, 2, "商品不存在，无法锁定。")
	var temporary: RunState = _state()
	_stock(temporary)
	_fill_backpack(temporary)
	_check(temporary.set_offer_locked(0, true) and temporary.set_offer_locked(1, true), "A full backpack does not prevent reserving a future weapon or rune purchase")

func _test_refresh_and_unlock() -> void:
	var state: RunState = _state(37)
	_stock(state)
	_check(state.set_offer_locked(0, true) and state.set_offer_locked(3, true), "Refresh fixture retains nonadjacent slots")
	var retained: Dictionary = state.offers[0].duplicate(true)
	var final: Dictionary = state.offers[3].duplicate(true)
	var changed_unlocked: bool = false
	for refresh: int in 4:
		var old_stock: Array[Dictionary] = state.offers.duplicate(true)
		var cost: int = state.reroll_cost()
		var gold: int = state.gold
		_check(state.reroll_shop() and state.gold == gold - cost and state.rerolls == refresh + 1, "Refreshing locked stock retains the normal paid escalating price")
		_check(state.offers.size() == 4 and state.offers[0] == retained and state.offers[3] == final and state.is_offer_locked(0) and state.is_offer_locked(3), "Every refresh restores reserved identities and original positions")
		changed_unlocked = changed_unlocked or state.offers[1] != old_stock[1] or state.offers[2] != old_stock[2]
	_check(changed_unlocked, "Unlocked slots actually receive new random stock")
	state.gold = 0
	var before_failed: Dictionary = _snapshot(state)
	_check(not state.reroll_shop(), "Insufficient funds still rejects a refresh")
	var after_failed: Dictionary = _snapshot(state)
	after_failed["error"] = before_failed["error"]
	_check(after_failed == before_failed, "Failed refresh preserves locked stock, RNG and reroll count")
	state.gold = 1000
	_check(state.set_offer_locked(0, false), "An existing reservation can be released after several refreshes")
	var changed: bool = false
	for refresh: int in 8:
		_check(state.reroll_shop(), "Unlocked stock remains refreshable")
		changed = changed or state.offers[0] != retained
	_check(changed and state.is_offer_locked(3) and not state.is_offer_locked(0), "Releasing a reservation returns only that slot to the random pool")

func _has_kind(state: RunState, kind: String) -> bool:
	for offer: Dictionary in state.offers:
		if str(offer.get("kind", "")) == kind:
			return true
	return false

func _test_cross_wave_guarantees() -> void:
	for locked_slot: int in [0, 3]:
		var state: RunState = _state()
		_stock(state)
		_check(state.set_offer_locked(locked_slot, true), "Cross-wave fixture reserves a concrete item")
		var retained: Dictionary = state.offers[locked_slot].duplicate(true)
		_check(state.reroll_shop(), "Cross-wave fixture incurs a normal refresh count")
		state.next_wave()
		_check(state.offers.is_empty() and state.locked_offer_count() == 1 and state.rerolls == 0, "Starting combat clears displayed offers and rerolls but keeps the reservation")
		state.generate_shop()
		_check(state.offers[locked_slot]["id"] == retained["id"] and state.offers[locked_slot]["kind"] == retained["kind"] and int(state.offers[locked_slot]["price"]) == state.shop_price(GameCatalog.weapon("crescent") if locked_slot == 0 else GameCatalog.relic("pilgrim")), "The new wave restores the same slot using current-wave prices rather than freezing a discount")
		_check(_has_kind(state, "rune") and state.is_offer_locked(locked_slot), "Second-wave rune guarantee survives a reserved non-rune item")
		if locked_slot == 0:
			_check(state.offers[1]["kind"] == "rune", "A reserved first slot moves the unsatisfied guarantee to the first free slot")
		else:
			_check(state.offers[0]["kind"] == "rune", "An unreserved first slot keeps the original second-wave guarantee")
	var first: RunState = _state()
	first.offers = [_offer("relic", "hourglass"), _offer("rune", "bounce"), _offer("relic", "pilgrim"), _offer("weapon", "comet")]
	_check(first.set_offer_locked(0, true) and first.set_offer_locked(1, true), "Both first slots can be reserved without disabling a guaranteed type")
	first.generate_shop()
	_check(first.offers[2]["kind"] == "weapon" and first.offers[3]["kind"] == "skill" and first.offers[3]["id"] == "pulse" and first.offers[3]["rank"] == 1 and first.is_offer_locked(0) and first.is_offer_locked(1), "First-wave weapon and first-rank pulse guarantees use the remaining two slots without replacing either lock")
	var matched: RunState = _state(71)
	_stock(matched)
	_check(matched.set_offer_locked(1, true), "A rune can be held for the next wave")
	matched.next_wave()
	var reference: RunState = _state(71)
	reference.wave = 2
	var expected: Array[Dictionary] = []
	for slot: int in 4:
		if slot == 1:
			var rune_offer: Dictionary = _offer("rune", "blast")
			rune_offer["price"] = reference.shop_price(GameCatalog.rune("blast"))
			expected.append(rune_offer)
		else:
			expected.append(_reference_offer(reference, _reference_kind(reference)))
	matched.generate_shop()
	_check(matched.offers == expected and matched.rng.state == reference.rng.state, "A locked rune already satisfies the second-wave guarantee without adding another forced draw")

func _test_ranked_skill_reservations() -> void:
	var state: RunState = _state(83)
	state.wave = 4
	var starfall: ContentDef = GameCatalog.skill("starfall")
	var pulse: ContentDef = GameCatalog.skill("pulse")
	state.offers = [_offer("skill", "starfall", state.shop_price(starfall) * 2, 2),
		_offer("skill", "pulse", state.shop_price(pulse), 1), _offer("weapon", "comet"), _offer("rune", "blast")]
	_check(state.set_offer_locked(0, true) and state.set_offer_locked(1, true), "A real second-rank output skill and first-rank pulse can reserve their original slots")
	var retained: Array[Dictionary] = [state.offers[0].duplicate(true), state.offers[1].duplicate(true)]
	_check(state.reroll_shop() and state.offers[0] == retained[0] and state.offers[1] == retained[1], "Same-wave refresh preserves both skill ranks, exact prices and reserved positions")
	state.next_wave()
	state.generate_shop()
	_check(state.is_offer_locked(0) and state.is_offer_locked(1) and state.offers[0]["id"] == "starfall" and state.offers[0]["rank"] == 2 and state.offers[1]["id"] == "pulse" and state.offers[1]["rank"] == 1,
		"Cross-wave stock retains each reserved skill identity, rank and original slot")
	_check(state.offers[0]["price"] == state.shop_price(starfall) * 2 and state.offers[1]["price"] == state.shop_price(pulse) and int(state.offers[0]["price"]) > int(retained[0]["price"]),
		"Cross-wave skill reservations use the new wave's price multiplied by the retained tier")
	var paid: int = int(state.offers[0]["price"])
	_check(state.buy_offer(0) and state.active_skills.size() == 1 and state.active_skills[0]["id"] == "starfall" and state.active_skills[0]["rank"] == 2 and state.active_skills[0]["paid"] == paid and not state.is_offer_locked(0) and state.is_offer_locked(1),
		"Buying the repriced second-rank reservation installs its actual tier and releases only its own lock")

func _test_transactions_and_backpack_capacity() -> void:
	var state: RunState = _state()
	state.offers = [_offer("weapon", "crescent"), _offer("weapon", "crescent"), _offer("rune", "pierce"), _offer("relic", "hourglass")]
	_check(state.set_offer_locked(0, true) and state.set_offer_locked(1, true) and state.buy_offer(0), "A locked offer remains a normal purchasable item")
	_check(not state.is_offer_locked(0) and state.is_offer_locked(1) and state.locked_offer_count() == 1 and state.offers[0]["sold"], "Buying one identical item releases only its own reservation")
	state.gold = 0
	var before: Dictionary = _snapshot(state)
	_check(not state.buy_offer(1), "An unaffordable reserved purchase is still rejected")
	var after: Dictionary = _snapshot(state)
	after["error"] = before["error"]
	_check(after == before and state.is_offer_locked(1), "A failed purchase does not consume the reservation")
	var relic: RunState = _state()
	for layer: int in 2:
		relic.offers = [_offer("relic", "moon_charm")]
		_check(relic.buy_offer(0), "Relic fixture stores two separate copies through formal purchases")
	relic.offers = [_offer("relic", "moon_charm"), _offer("relic", "moon_charm"), _offer("weapon", "comet"), _offer("rune", "blast")]
	_check(relic.set_offer_locked(0, true) and relic.set_offer_locked(2, true) and relic.buy_offer(1), "A third relic copy remains an ordinary spatial purchase")
	_check(relic.is_offer_locked(0) and relic.is_offer_locked(2) and relic.locked_offer_count() == 2, "Buying a third duplicate preserves the other relic reservation and unrelated weapon lock")
	_fill_backpack(relic)
	var full_before: Dictionary = _snapshot(relic)
	_check(relic.shop_lock_error(0).is_empty() and relic.purchase_error(0) == "背包空间不足。" and _snapshot(relic) == full_before, "Full-grid purchase eligibility is read-only and does not make the reservation obsolete")
	_check(not relic.buy_offer(0) and relic.last_error == "背包空间不足。", "A reserved relic still needs real space before purchase")
	var full_after: Dictionary = _snapshot(relic)
	full_after["error"] = full_before["error"]
	_check(full_after == full_before and relic.is_offer_locked(0) and relic.is_offer_locked(2), "A full-grid refusal preserves both locks, money, layout, UIDs and RNG")
	_check(relic.expand_backpack() and relic.is_offer_locked(0) and relic.is_offer_locked(2), "Buying another backpack row preserves existing reservations")
	_check(relic.buy_offer(0) and int(relic.relic_counts["moon_charm"]) == 4, "Expanded real space permits a fourth separate copy of the reserved relic")
	_check(not relic.is_offer_locked(0) and relic.is_offer_locked(2) and relic.locked_offer_count() == 1, "A successful purchase releases only its own lock after capacity becomes available")
	var malformed: RunState = _state()
	_stock(malformed)
	_check(malformed.set_offer_locked(2, true), "Invalidation fixture starts with a legal reservation")
	malformed._locked_offers[2]["id"] = "missing"
	malformed.generate_shop()
	_check(malformed.locked_offer_count() == 0 and malformed._locked_offers.is_empty(), "Generation cleans reservations for definitions that no longer exist")

func _test_begin_and_queries() -> void:
	var state: RunState = _state()
	_stock(state)
	_check(state.set_offer_locked(2, true), "Read-only fixture reserves one item")
	state.last_error = "保留查询前错误"
	var before: Dictionary = _snapshot(state)
	var emissions: Array[int] = [0]
	var observe: Callable = func() -> void: emissions[0] += 1
	state.changed.connect(observe)
	for repeat: int in 3:
		_check(state.is_offer_locked(2) and not state.is_offer_locked(-1) and state.locked_offer_count() == 1 and state.shop_lock_error(1).is_empty(), "Lock state and eligibility can be inspected repeatedly")
	_check(_snapshot(state) == before and emissions[0] == 0, "Lock queries do not mutate snapshots, clear errors, emit changed or advance RNG")
	state.changed.disconnect(observe)
	state.begin(2027, "ember")
	_check(state._locked_offers.is_empty() and state.locked_offer_count() == 0 and state.offers.is_empty(), "A restarted run clears every reservation rather than carrying the previous build")
	state.generate_shop()
	_check(state.offers[0]["kind"] == "weapon" and state.locked_offer_count() == 0, "The restarted first shop returns to the normal guarantee")

func _reference_kind(state: RunState) -> String:
	var roll: float = state.rng.randf()
	if roll < 0.35:
		return "weapon"
	if roll < 0.55:
		return "rune"
	return "relic" if roll < 0.8 else "skill"

func _reference_offer(state: RunState, kind: String) -> Dictionary:
	var pool: Array[ContentDef] = []
	match kind:
		"weapon": pool = GameCatalog.weapons()
		"rune": pool = GameCatalog.runes()
		"relic": pool = GameCatalog.relics()
		"skill": pool = GameCatalog.skills()
	var definition: ContentDef = pool[state.rng.randi_range(0, pool.size() - 1)]
	var result: Dictionary = {"id": definition.id, "kind": kind, "price": state.shop_price(definition), "sold": false}
	if kind == "skill":
		var rank: int = 2 if state.wave >= 4 and state.rng.randf() < 0.35 else 1
		result["rank"] = rank
		result["price"] = state.shop_price(definition) * rank
	return result

func _reference_generate(state: RunState) -> void:
	# Kind selection is still consumed for guaranteed slots; a forced pulse skips
	# definition/rank draws. This reference does not call the production RNG helpers.
	state.offers.clear()
	for index: int in 4:
		var kind: String = _reference_kind(state)
		if index == 0 and state.wave == 1:
			kind = "weapon"
		elif index == 0 and state.wave == 2:
			kind = "rune"
		if index == 1 and state.wave == 1:
			var pulse: ContentDef = GameCatalog.skill("pulse")
			state.offers.append({"id": "pulse", "kind": "skill", "rank": 1, "price": state.shop_price(pulse), "sold": false})
			continue
		state.offers.append(_reference_offer(state, kind))
	state.last_error = ""

func _test_zero_lock_reference() -> void:
	var seen_kinds: Dictionary = {}
	var saw_second_rank_skill: bool = false
	for seed_value: int in [0, 1, 2, 37, 71, 2026, 2027, 2028, 2032, 2035]:
		for number: int in range(1, 9):
			for owns_duplicates: bool in [false, true]:
				var current: RunState = _state(seed_value)
				var reference: RunState = _state(seed_value)
				current.wave = number
				reference.wave = number
				if owns_duplicates:
					for copy: int in 3:
						current.offers = [_offer("relic", "damage")]
						reference.offers = [_offer("relic", "damage")]
						_check(current.buy_offer(0) and reference.buy_offer(0), "Reference fixtures own duplicate relics through real spatial purchases")
				for refresh: int in 4:
					if refresh == 0:
						current.generate_shop()
					else:
						_check(current.reroll_shop(), "Unlocked current shop remains legally refreshable")
						reference.gold -= reference.reroll_cost()
						reference.rerolls += 1
					_reference_generate(reference)
					_check(_snapshot(current) == _snapshot(reference), "Zero-lock four-pool generation preserves complete stock, exact RNG, costs and state: %d/%d/%s/%d" % [seed_value, number, owns_duplicates, refresh])
					if number == 1:
						_check(current.offers[0]["kind"] == "weapon" and current.offers[1]["kind"] == "skill" and current.offers[1]["id"] == "pulse" and current.offers[1]["rank"] == 1, "Every first-wave refresh retains the weapon and first-rank pulse guarantees")
					for offer: Dictionary in current.offers:
						var skill: bool = offer["kind"] == "skill"
						seen_kinds[offer["kind"]] = true
						_check(offer.size() == (5 if skill else 4) and offer.has_all(["id", "kind", "price", "sold"]) and not offer.has("locked") and offer.has("rank") == skill,
							"Only real skill offers extend the original four stock fields with an explicit tier")
						if skill:
							var rank: int = int(offer["rank"])
							_check(rank in [1, 2] and (number >= 4 or rank == 1) and offer["price"] == current.shop_price(GameCatalog.skill(str(offer["id"]))) * rank,
								"Skill stock has a legal wave-dependent tier and its exact tier-multiplied price")
							saw_second_rank_skill = saw_second_rank_skill or rank == 2
	_check(seen_kinds.size() == 4 and seen_kinds.has_all(["weapon", "rune", "relic", "skill"]) and saw_second_rank_skill, "The seeded reference matrix exercises all four pools and later second-rank skill offers")
