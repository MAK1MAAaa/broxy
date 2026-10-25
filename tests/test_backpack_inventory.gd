extends SceneTree
## Production grid transactions, independent overlap oracle and rank/identity invariants.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_start_and_geometry()
	_test_capacity_and_atomicity()
	_test_rune_swap_and_sale()
	_test_merging()
	_test_relics_and_limits()
	_test_queries_and_expansion()
	_test_generated_moves()
	print("BackpackInventory: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261024, "bone")
	state.gold = 100000
	return state

func _offer(kind: String, id: String) -> Dictionary:
	return {"kind": kind, "id": id, "price": BackpackInventory.definition(kind, id).price, "sold": false}

func _buy(state: RunState, kind: String, id: String) -> int:
	state.offers = [_offer(kind, id)]
	var uid: int = state.backpack_snapshot()["next_uid"]
	var success: bool = state.buy_offer(0)
	_check(success, "Formal purchase succeeds in the prepared grid: " + id)
	return uid if success else -1

func _uids(state: RunState, kind: String, id: String = "") -> Array[int]:
	var result: Array[int] = []
	for entry: Dictionary in state.backpack_snapshot()["items"]:
		if entry["kind"] == kind and (id.is_empty() or entry["id"] == id):
			result.append(int(entry["uid"]))
	return result

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, state.rng.state, state._next_rune_uid])

func _layout_valid(state: RunState) -> bool:
	var snapshot: Dictionary = state.backpack_snapshot()
	var occupied: Dictionary = {}
	var identities: Dictionary = {}
	for entry: Dictionary in snapshot["items"]:
		var uid: int = entry["uid"]
		if identities.has(uid):
			return false
		identities[uid] = true
		var rune: Dictionary = entry.get("rune", {})
		if not rune.is_empty():
			if identities.has(rune["uid"]):
				return false
			identities[rune["uid"]] = true
		var size: Vector2i = BackpackInventory.size_for(entry["kind"], entry["id"], entry["rotated"])
		for y: int in range(entry["y"], entry["y"] + size.y):
			for x: int in range(entry["x"], entry["x"] + size.x):
				var cell := Vector2i(x, y)
				if x < 0 or x >= snapshot["width"] or y < 0 or y >= snapshot["height"] or occupied.has(cell):
					return false
				occupied[cell] = uid
	return occupied.size() == snapshot["used_cells"]

func _test_start_and_geometry() -> void:
	var state: RunState = _state()
	var snapshot: Dictionary = state.backpack_snapshot()
	_check(snapshot["width"] == 6 and snapshot["height"] == 4 and snapshot["total_cells"] == 24 and snapshot["used_cells"] == 3, "The starter really occupies three cells in a 6x4 grid")
	_check(state.loadout.size() == 1 and state.loadout[0]["uid"] == 1 and state.loadout[0]["rank"] == 1 and _layout_valid(state), "Starter identity, tier and combat projection agree with grid storage")
	_check(state.move_item(1, Vector2i(5, 1), false), "Moving ignores the item's own former cells")
	_check(state.move_item(1, Vector2i(3, 3), true) and BackpackInventory.size_for("weapon", "bone", true) == Vector2i(3, 1), "A 1x3 weapon rotates into a real 3x1 footprint at the bottom edge")
	var before: String = _signature(state)
	_check(not state.move_item(1, Vector2i(5, 3), true) and _signature(state) == before, "Out-of-bounds rotation refuses without moving, spending or changing UID/RNG")
	var ember: int = _buy(state, "weapon", "ember")
	before = _signature(state)
	_check(not state.move_item(ember, Vector2i(3, 2), false) and _signature(state) == before, "An overlapping two-by-two item is rejected atomically")
	var copied: Dictionary = state.backpack_snapshot()
	copied["items"][0]["x"] = 99
	_check(state.backpack_item(1)["x"] == 3 and _layout_valid(state), "Snapshots are deep copies rather than a second mutable inventory")

func _test_capacity_and_atomicity() -> void:
	var state: RunState = _state()
	for index: int in 7:
		_buy(state, "weapon", "bone")
	_check(state.loadout.size() == 8 and state.backpack_snapshot()["used_cells"] == 24, "Real grid space replaces the old four-weapon cap")
	state.offers = [_offer("weapon", "frost")]
	var before: String = _signature(state)
	_check(state.purchase_error(0) == "背包空间不足。" and not state.buy_offer(0) and _signature(state) == before, "Full-grid purchase leaves wallet, quote, UID and RNG unchanged")
	state = _state()
	state.gold = 0
	state.offers = [_offer("relic", "damage")]
	before = _signature(state)
	_check(not state.buy_offer(0) and state.last_error == "魂屑不足。" and _signature(state) == before, "An unaffordable fitting item never enters storage or consumes a UID")
	state.offers[0]["price"] = -1
	before = _signature(state)
	_check(not state.buy_offer(0) and _signature(state) == before, "Malformed negative prices cannot mint currency")
	var bag := BackpackInventory.new()
	for y: int in 4:
		for x: int in [0, 2, 4]:
			var entry: Dictionary = bag.add("rune", "pierce")
			_check(not entry.is_empty() and bag.move(entry["uid"], Vector2i(x, y), false), "Checkerboard storage fixture places one-cell blockers")
	_check(bag.snapshot()["used_cells"] == 12 and not bag.can_add("weapon", "ember"), "Twelve free cells do not imply a two-by-two contiguous item fits")

func _fill_runes(state: RunState) -> void:
	for index: int in 36:
		if not state.backpack.can_add("rune", "pierce"):
			return
		_buy(state, "rune", "pierce")

func _test_rune_swap_and_sale() -> void:
	var state: RunState = _state()
	var incoming: int = _buy(state, "rune", "bounce")
	_check(state.equip_rune(state.rune_index_for_uid(incoming), 0), "Equipping moves a real loose rune into the starter socket")
	_check(state.backpack_item(incoming).is_empty() and state.loadout[0]["rune"]["uid"] == incoming, "Socketed runes retain identity and release their loose grid cell")
	_fill_runes(state)
	_check(state.rune_bag.size() > 4 and state.backpack_snapshot()["used_cells"] == 24, "Spare rune storage also uses geometry rather than the old four-rune cap")
	var next_uid: int = state.rune_bag[0]["uid"]
	var former: Dictionary = state.backpack_item(next_uid)
	_check(state.equip_rune(state.rune_index_for_uid(next_uid), 0), "A full-grid swap uses the incoming rune's vacated cell")
	var returned: Dictionary = state.backpack_item(incoming)
	_check(returned["x"] == former["x"] and returned["y"] == former["y"] and state.loadout[0]["rune"]["uid"] == next_uid and _layout_valid(state), "The old socket rune returns once to the exact freed cell")
	var before: String = _signature(state)
	_check(not state.unequip_rune(0) and _signature(state) == before, "Removing a socket rune without a free cell is atomic")
	_check(not state.sell_weapon(0) and _signature(state) == before, "Selling the final weapon is rejected even when its rune could be returned")
	state = _state()
	var second: int = _buy(state, "weapon", "bone")
	var attached: int = _buy(state, "rune", "blast")
	_check(state.equip_rune(state.rune_index_for_uid(attached), state.weapon_index_for_uid(second)), "Second weapon receives the purchased rune")
	_fill_runes(state)
	var gold_before: int = state.gold
	_check(state.sell_item(second) and state.gold == gold_before + 9, "Selling refunds half the actual weapon purchase value")
	_check(not state.backpack_item(attached).is_empty() and state.backpack_item(second).is_empty() and _layout_valid(state), "A sold weapon's rune is returned, never deleted or copied")

func _test_merging() -> void:
	var state: RunState = _state()
	var second: int = _buy(state, "weapon", "bone")
	var target_rune: int = _buy(state, "rune", "pierce")
	var source_rune: int = _buy(state, "rune", "bounce")
	state.equip_rune(state.rune_index_for_uid(target_rune), 0)
	state.equip_rune(state.rune_index_for_uid(source_rune), state.weapon_index_for_uid(second))
	var before: String = _signature(state)
	var preview: Dictionary = state.merge_preview(second, 1)
	_check(preview["can_merge"] and preview["rank_after"] == 2 and preview["returned_rune"]["uid"] == source_rune and preview["cells_freed"] == 2, "Merge preview reports the upgrade, returned rune and net freed cells")
	_check(_signature(state) == before, "Merge forecasting does not touch state or either transaction identity counter")
	_check(state.merge_items(second, 1), "Two matching weapons merge explicitly")
	var target: Dictionary = state.backpack_item(1)
	_check(target["rank"] == 2 and target["paid"] == 18 and target["rune"]["uid"] == target_rune and state.backpack_item(second).is_empty(), "Target UID/socket/value survive while exactly one source weapon is consumed")
	_check(state.backpack_item(source_rune)["id"] == "bounce" and _layout_valid(state), "Conflicting source socket is restored as one real loose rune")
	var third: int = _buy(state, "weapon", "bone")
	var fourth: int = _buy(state, "weapon", "bone")
	_check(state.merge_items(fourth, third) and state.merge_items(third, 1) and state.loadout[0]["rank"] == 3, "Four first-rank weapons form one third-rank weapon through two explicit merge stages")
	_check(state.backpack_item(1)["paid"] == 54 and BackpackInventory.rank_multiplier(3) == 4.0, "Merged purchase value and the third-rank combat factor remain exact")
	before = _signature(state)
	_check(not state.merge_items(1, 1) and _signature(state) == before, "Self-merge cannot duplicate a weapon")
	var bag := BackpackInventory.new()
	var a: Dictionary = bag.add("rune", "pierce", 18, 3)
	var b: Dictionary = bag.add("rune", "pierce", 18, 3)
	_check(not bag.merge(a["uid"], b["uid"]) and bag.snapshot()["items"].size() == 2, "Third rank is a hard merge ceiling")
	state = _state()
	var a_rune: int = _buy(state, "rune", "blast")
	var b_rune: int = _buy(state, "rune", "blast")
	_check(state.merge_items(a_rune, b_rune) and state.rune_bag[0]["rank"] == 2, "Spare runes participate in the same two-item rank upgrade")
	var rune_preview: Dictionary = state.rune_equip_preview(0, 0)
	_check(is_equal_approx(rune_preview["blast_radius"], 78.0) and is_equal_approx(rune_preview["blast_multiplier"], 0.65), "Equipment forecasts use the rank-two rune's actual blast rules")

func _test_relics_and_limits() -> void:
	var state: RunState = _state()
	var heart_a: int = _buy(state, "relic", "vitality")
	state.health = 70.0
	var heart_b: int = _buy(state, "relic", "vitality")
	_check(state.health == 90.0 and state.stat("max_health") == 140.0, "A purchased heart adds its real maximum-health delta and heals only that amount")
	_check(state.merge_items(heart_a, heart_b) and state.health == 90.0 and state.stat("max_health") == 140.0 and state.relic_counts["vitality"] == 2, "Relic merging preserves total attribute weight and never grants free healing")
	state.health = 135.0
	_check(state.sell_item(heart_b) and state.health == 100.0 and state.stat("max_health") == 100.0, "Selling a ranked health relic clamps current health to the new maximum")
	for index: int in 4:
		_buy(state, "relic", "damage")
	_check(state.relic_counts["damage"] == 4, "Relics are individual grid items with no old three-layer purchase limit")
	state.offers = [_offer("relic", "damage")]
	_check(state.set_offer_locked(0, true), "Owning four units does not invalidate a lock for another relic")
	state = _state()
	for index: int in 7:
		state.backpack.add("relic", "grave_candle", 72, 3)
	state._sync_backpack_projection()
	_check(state.stat("move_speed") == 60.0, "A mechanically reachable high-rank negative layout respects the minimum move speed")
	state = _state()
	for index: int in 4:
		state.backpack.add("relic", "blood_pact", 88, 3)
	state._sync_backpack_projection()
	_check(state.stat("attack_speed") == 0.25 and state.projected_upgrade_stat("attack_speed", 0.10) == 0.25, "Upgrade projections clamp the raw total rather than adding to an already clamped floor")
	_check(state.stat("damage") > 1.0 and _layout_valid(state), "Positive and negative ranked relic attributes both participate in the real grid projection")

func _test_queries_and_expansion() -> void:
	var state: RunState = _state()
	state.offers = [_offer("relic", "blood_pact")]
	var before: String = _signature(state)
	var emitted: Array[int] = [0]
	state.changed.connect(func() -> void: emitted[0] += 1)
	var preview: Dictionary = state.relic_purchase_preview(0)
	state.backpack_snapshot()
	state.backpack.find_space("weapon", "comet")
	state.merge_preview(1, 1)
	_check(preview["has_projection"] and _signature(state) == before and emitted[0] == 0, "Space and transaction previews remain pure, including rejected merge queries")
	var gold_before: int = state.gold
	_check(state.expand_backpack() and state.backpack_snapshot()["height"] == 5 and state.gold == gold_before - 32, "The first paid expansion adds six real cells")
	_check(state.expand_backpack() and state.backpack_snapshot()["height"] == 6 and state.gold == gold_before - 80, "The second expansion uses its separate price and reaches six rows")
	before = _signature(state)
	_check(not state.expand_backpack() and _signature(state) == before, "An expansion beyond the maximum neither spends nor changes layout")
	state.begin(2027, "ember")
	_check(state.backpack_snapshot()["height"] == 4 and state.backpack_snapshot()["next_uid"] == 2 and state.loadout[0]["id"] == "ember" and state.relic_counts.is_empty(), "Restart resets grid size, identities, upgrades and inventory together")
	state.gold = 31
	before = _signature(state)
	_check(not state.expand_backpack() and _signature(state) == before, "Insufficient expansion funds never unlock a row")

func _test_generated_moves() -> void:
	var state: RunState = _state()
	_buy(state, "weapon", "ember")
	_buy(state, "weapon", "storm")
	_buy(state, "relic", "blood_pact")
	_buy(state, "relic", "armor")
	_buy(state, "rune", "pierce")
	var random := RandomNumberGenerator.new()
	random.seed = 20261024
	var uid_order: Array = state.loadout.map(func(entry: Dictionary) -> int: return entry["uid"])
	for trial: int in 160:
		var snapshot: Dictionary = state.backpack_snapshot()
		var entry: Dictionary = snapshot["items"][random.randi_range(0, snapshot["items"].size() - 1)]
		var cell := Vector2i(random.randi_range(-1, 6), random.randi_range(-1, 4))
		var rotated: bool = random.randi_range(0, 1) == 1
		var size: Vector2i = BackpackInventory.size_for(entry["kind"], entry["id"], rotated)
		var expected: bool = cell.x >= 0 and cell.y >= 0 and cell.x + size.x <= 6 and cell.y + size.y <= 4
		for other: Dictionary in snapshot["items"]:
			if other["uid"] != entry["uid"]:
				var other_size: Vector2i = BackpackInventory.size_for(other["kind"], other["id"], other["rotated"])
				expected = expected and not Rect2i(cell, size).intersects(Rect2i(Vector2i(other["x"], other["y"]), other_size))
		var before: String = _signature(state)
		var accepted: bool = state.move_item(entry["uid"], cell, rotated)
		_check(accepted == expected and _layout_valid(state), "Generated placement matches an independent rectangle oracle: %d" % trial)
		if not accepted:
			_check(_signature(state) == before, "Rejected generated placement is atomic: %d" % trial)
	_check(state.loadout.map(func(entry: Dictionary) -> int: return entry["uid"]) == uid_order, "Moving and rotating items never reorder weapon cooldown identities")
