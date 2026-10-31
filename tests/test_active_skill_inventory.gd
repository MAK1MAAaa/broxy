extends SceneTree
## Real inventory transactions enforce skill ownership, slot identity and the two-item cap.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_catalog_and_parameters()
	_test_direct_limit()
	_test_purchase_and_slots()
	_test_merge_and_sale()
	_test_skill_boundaries()
	_test_shop_distribution()
	_test_ranked_shop()
	print("ActiveSkillInventory: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone")
	state.gold = 10000
	return state

func _offer(id: String, kind: String = "skill") -> Dictionary:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	return {"kind": kind, "id": id, "price": definition.price, "sold": false}

func _buy(state: RunState, id: String, kind: String = "skill") -> int:
	state.offers = [_offer(id, kind)]
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	_check(state.buy_offer(0), "A priced backpack transaction buys " + id)
	return uid

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, state.rng.state])

func _test_catalog_and_parameters() -> void:
	_check(GameCatalog.skills().size() == 3 and ActiveSkillRules.LIMIT == 2, "Three skills share the two-item inventory limit")
	var sizes: Dictionary = {"pulse": Vector2i(2, 1), "starfall": Vector2i(2, 2), "arc_slash": Vector2i(2, 1)}
	var prices: Dictionary = {"pulse": 20, "starfall": 26, "arc_slash": 24}
	for definition: ContentDef in GameCatalog.skills():
		_check(definition.kind == "skill" and definition.inventory_size == sizes[definition.id] and definition.price == prices[definition.id], "Skill definitions expose their real type, footprint and price: " + definition.id)
		_check(definition.icon == "skill_" + definition.id and BackpackInventory.definition("skill", definition.id) == definition, "Skill definition dispatch resolves the dedicated icon: " + definition.id)
	for rank: int in range(1, 4):
		var pulse: Dictionary = ActiveSkillRules.parameters("pulse", rank, {})
		_check(pulse["radius"] == 144.0 + float(rank - 1) * 12.0 and pulse["cooldown"] == 8.0 and pulse["damage"] == 0.0, "Pulse rank changes only its baseline radius")
		_check(pulse["push_distance"] == 70.0 and pulse["hinder_factor"] == 0.65 and pulse["hinder_seconds"] == 1.0, "Pulse retains its independent crowd-control parameters")
		var starfall: Dictionary = ActiveSkillRules.parameters("starfall", rank, {"damage": 1.5})
		var slash: Dictionary = ActiveSkillRules.parameters("arc_slash", rank, {"damage": 1.5})
		_check(starfall["radius"] == 112.0 + float(rank - 1) * 8.0 and starfall["damage"] == [48.0, 72.0, 108.0][rank - 1] and starfall["cooldown"] == 10.0, "Starfall projects its rank and global damage multiplier")
		_check(slash["radius"] == 148.0 + float(rank - 1) * 8.0 and slash["damage"] == [36.0, 54.0, 81.0][rank - 1] and slash["cooldown"] == 6.0 and is_equal_approx(float(slash["half_angle_radians"]), deg_to_rad(50.0)), "Arc slash keeps a one-hundred-degree cone across ranks")
	var capped: Dictionary = ActiveSkillRules.parameters("pulse", 3, {"pulse_radius": 216.0, "pulse_cooldown": 99.0})
	_check(capped["radius"] == 216.0 and capped["cooldown"] == 16.0, "Pulse growth retains the original radius and cooldown caps")
	_check(ActiveSkillRules.parameters("missing", 1, {}).is_empty(), "Unknown skill IDs have no usable parameters")
	_check(ActiveSkillRules.parameters("starfall", 1, {"damage": INF})["damage"] == 32.0, "Invalid stat inputs cannot produce a nonfinite cast")

func _test_direct_limit() -> void:
	var bag := BackpackInventory.new()
	var first: Dictionary = bag.add("skill", "pulse", 20, 3)
	var second: Dictionary = bag.add("skill", "pulse", 20)
	_check(not first.is_empty() and not second.is_empty(), "Third-rank and duplicate skill boxes each use one legal slot")
	var before: Dictionary = bag.snapshot()
	_check(bag.find_space("skill", "starfall").is_empty() and not bag.can_add("skill", "starfall"), "Geometry queries reject a third skill despite free cells")
	_check(bag.add("skill", "starfall", 26).is_empty() and bag.last_error == "主动技能已达上限（2）。" and bag.snapshot() == before, "Direct grants cannot bypass the skill cap or consume a UID")
	_check(bag.move(int(first["uid"]), Vector2i(5, 0), true), "The cap does not prevent rotating a skill already in the backpack")
	_check(not bag.add("relic", "damage", 18).is_empty(), "The skill limit leaves non-skill purchases available")

func _test_purchase_and_slots() -> void:
	var state: RunState = _state()
	_check(state.active_skills.is_empty() and state.loadout.size() == 1 and state.backpack_snapshot()["items"].size() == 1, "A new run grants only its starter weapon and no free active skill")
	state.offers = [_offer("pulse")]
	var initial: String = _signature(state)
	var purchase: Dictionary = state.skill_purchase_preview(0)
	_check(purchase["can_buy"] and purchase["rank"] == 1 and purchase["parameters"]["radius"] == 144.0 and purchase["gold_after"] == state.gold - 20 and _signature(state) == initial, "An available skill preview forecasts its exact rank, parameters and paid wallet")
	var pulse: int = _buy(state, "pulse")
	_check(state.active_skills[0]["x"] == purchase["placement"]["x"] and state.active_skills[0]["y"] == purchase["placement"]["y"] and state.gold == purchase["gold_after"], "The successful transaction uses the previewed automatic placement and price")
	var slash: int = _buy(state, "arc_slash")
	_check(state.active_skills.size() == 2 and int(state.active_skills[0]["uid"]) == pulse and int(state.active_skills[1]["uid"]) == slash, "Q and E projections follow stable purchase identities")
	_check(state.move_item(pulse, Vector2i(5, 1), true), "A two-cell skill can be placed vertically")
	_check(state.active_skills[0] == state.backpack_item(pulse) and state.active_skills[1] == state.backpack_item(slash), "Projection preserves exact position, rotation, identity and paid metadata")
	state.offers = [_offer("starfall")]
	var before: String = _signature(state)
	var emissions: Array[int] = [0]
	state.changed.connect(func() -> void: emissions[0] += 1)
	var preview: Dictionary = state.skill_purchase_preview(0)
	_check(preview == state.skill_purchase_preview(0) and _signature(state) == before and emissions[0] == 0, "Repeated blocked purchase forecasts are pure and deterministic")
	_check(not preview["can_buy"] and not preview["placement_available"] and preview["gold_after"] == state.gold and preview["error"] == "主动技能已达上限（2）。", "A full skill loadout retains its explicit purchase refusal")
	_check(not state.buy_offer(0) and state.last_error == preview["error"] and _signature(state) == before, "Failed purchase preserves wallet, offers, inventory, UID and random state")
	var summary: Dictionary = state.summary()
	summary["active_skills"][0]["rank"] = 3
	_check(state.active_skills[0]["rank"] == 1, "Run summaries do not expose mutable skill ownership")

func _test_merge_and_sale() -> void:
	var state: RunState = _state()
	var target: int = _buy(state, "pulse")
	var source: int = _buy(state, "pulse")
	var before: String = _signature(state)
	var preview: Dictionary = state.merge_preview(source, target)
	_check(preview["can_merge"] and preview["skill_before"]["radius"] == 144.0 and preview["skill_after"]["radius"] == 156.0 and preview["cells_freed"] == 2 and _signature(state) == before, "Skill merge forecasts the real rank increase without mutating the run")
	_check(state.merge_items(source, target) and state.active_skills.size() == 1 and state.active_skills[0]["uid"] == target and state.active_skills[0]["rank"] == 2 and state.active_skills[0]["paid"] == 40, "Same-tier merge retains target identity and total paid value")
	_check(state.backpack.can_add("skill", "starfall") and state.backpack_item(source).is_empty(), "Merging releases exactly one skill slot and removes its source")
	_buy(state, "starfall")
	var wallet: int = state.gold
	_check(state.sell_item(target) and state.gold == wallet + 20 and state.active_skills.size() == 1 and state.active_skills[0]["id"] == "starfall", "Selling an upgraded skill synchronizes ownership and refunds half its real cost")
	state.begin(17, "frost")
	_check(state.active_skills.is_empty() and state.backpack_snapshot()["next_uid"] == 2, "Restart clears all skill identities without changing the starter UID contract")

func _test_skill_boundaries() -> void:
	var state: RunState = _state()
	var pulse: int = _buy(state, "pulse")
	var rune: int = _buy(state, "pierce", "rune")
	var before: String = _signature(state)
	_check(not state.backpack.equip(rune, pulse) and _signature(state) == before, "Weapon runes cannot attach to active skill boxes")
	_buy(state, "echo_stone", "relic")
	var parameters: Dictionary = state.active_skill_parameters(state.active_skills[0])
	_check(parameters["radius"] == 162.0 and is_equal_approx(float(parameters["cooldown"]), 8.8), "Echo stone affects an equipped pulse through the same projected stats")
	var weapon: Dictionary = state.loadout[0]
	_check((weapon["resonance_sources"] as Array).find(pulse) == -1 and not state.relic_counts.has("pulse") and state.rune_bag.size() == 1, "Skills never become relic resonance sources or loose runes")
	var full: RunState = _state()
	for index: int in 21:
		full.backpack.add("rune", "pierce")
	full._sync_backpack_projection()
	full.offers = [_offer("starfall")]
	before = _signature(full)
	_check(full.purchase_error(0) == "背包空间不足。" and not full.buy_offer(0) and _signature(full) == before, "Real grid capacity still rejects a skill before any resource is spent")

func _test_shop_distribution() -> void:
	var seen: Dictionary = {}
	for seed_value: int in range(1, 41):
		var state := RunState.new()
		state.begin(seed_value, "bone")
		state.generate_shop()
		_check(state.offers.size() == 4 and state.offers[0]["kind"] == "weapon" and state.offers[1]["kind"] == "skill" and state.offers[1]["id"] == "pulse" and state.offers[1]["rank"] == 1, "The first shop guarantees a weapon and an affordable first-rank pulse within four offers")
		state.wave = 3
		state.generate_shop()
		for offer: Dictionary in state.offers:
			seen[str(offer["kind"])] = true
			_check(BackpackInventory.definition(str(offer["kind"]), str(offer["id"])) != null, "Every random shop kind resolves an explicit content definition")
	_check(seen.has("skill") and seen.has("weapon") and seen.has("rune") and seen.has("relic"), "Later shops retain all four content pools")
	var locked: RunState = _state()
	locked.generate_shop()
	_check(locked.set_offer_locked(0, true) and locked.set_offer_locked(2, true), "Two retained goods use the existing lock contract")
	locked.generate_shop()
	var has_pulse: bool = false
	for offer: Dictionary in locked.offers:
		has_pulse = has_pulse or (offer["kind"] == "skill" and offer["id"] == "pulse")
	_check(locked.offers.size() == 4 and locked.is_offer_locked(0) and locked.is_offer_locked(2) and has_pulse, "A retained shop preserves both locks and the guaranteed pulse")

func _test_ranked_shop() -> void:
	var ranks_seen: Dictionary = {}
	for seed_value: int in range(1, 61):
		var generated := RunState.new()
		generated.begin(seed_value, "bone")
		generated.wave = 4
		generated.generate_shop()
		for offer: Dictionary in generated.offers:
			if str(offer["kind"]) != "skill":
				continue
			var rank: int = int(offer["rank"])
			ranks_seen[rank] = true
			_check(rank in [1, 2] and int(offer["price"]) == generated.shop_price(GameCatalog.skill(str(offer["id"]))) * rank, "Later skill offers use only first or second rank with their matching wave price")
	_check(ranks_seen.has(1) and ranks_seen.has(2), "The later shop can naturally supply both ranks without directly selling a third-rank item")
	var state: RunState = _state()
	state.wave = 4
	var offer: Dictionary = _offer("arc_slash")
	offer["rank"] = 2
	offer["price"] = state.shop_price(GameCatalog.skill("arc_slash")) * 2
	state.offers = [offer.duplicate(true)]
	var preview: Dictionary = state.skill_purchase_preview(0)
	_check(preview["can_buy"] and preview["rank"] == 2 and preview["parameters"]["damage"] == 36.0 and preview["radius"] == 156.0, "Second-rank purchase previews use the actual offered tier")
	_check(state.buy_offer(0) and state.active_skills[0]["rank"] == 2 and state.active_skills[0]["paid"] == offer["price"], "A second-rank offer enters the backpack with its real tier and total price")
	var target: int = int(state.active_skills[0]["uid"])
	state.offers = [offer.duplicate(true)]
	_check(state.buy_offer(0) and state.active_skills.size() == 2, "A second purchased second-rank box fits the strict two-item cap")
	var source: int = int(state.active_skills[1]["uid"])
	state.offers = [offer.duplicate(true)]
	var full: String = _signature(state)
	_check(state.purchase_error(0) == "主动技能已达上限（2）。" and not state.buy_offer(0) and _signature(state) == full, "A third second-rank purchase remains an atomic refusal before manual merge")
	_check(state.merge_items(source, target) and state.active_skills.size() == 1 and state.active_skills[0]["rank"] == 3 and state.active_skill_parameters(state.active_skills[0])["damage"] == 54.0, "Two purchased second-rank boxes can manually reach third rank without ever exceeding two items")
	for invalid_rank: Variant in [0, 3, -1, 1.5, "2"]:
		var invalid: RunState = _state()
		var malformed: Dictionary = _offer("pulse")
		malformed["rank"] = invalid_rank
		invalid.offers = [malformed]
		var before: String = _signature(invalid)
		_check(invalid.purchase_error(0) == "无效的主动技能阶级。" and not invalid.buy_offer(0) and _signature(invalid) == before, "An invalid offered rank cannot spend currency, alter inventory or consume identity")
		_check(invalid.shop_lock_error(0) == "无效的主动技能阶级。" and not invalid.set_offer_locked(0, true) and invalid.locked_offer_count() == 0, "An invalid offered rank cannot create a retained shop entry")
	var retained: RunState = _state()
	retained.wave = 4
	retained.offers = [offer.duplicate(true)]
	_check(retained.set_offer_locked(0, true), "A legal second-rank skill offer can be retained")
	retained.next_wave()
	retained.generate_shop()
	_check(retained.is_offer_locked(0) and retained.offers[0]["rank"] == 2 and retained.offers[0]["price"] == retained.shop_price(GameCatalog.skill("arc_slash")) * 2, "Retained skill goods preserve tier and reprice by that tier across waves")
	retained.offers[0]["rank"] = 1
	_check(not retained.is_offer_locked(0), "A changed skill tier cannot impersonate the previously locked offer")
