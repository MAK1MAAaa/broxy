extends SceneTree
## Independent cell-edge oracles and real inventory transactions verify local resonance.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_geometry()
	_test_weights_and_isolation()
	_test_generated_contacts()
	_test_transactions_and_cache()
	_test_purchase_forecasts()
	_test_merge_forecasts()
	print("ResonanceRules: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _entry(uid: int, kind: String, id: String, cell: Vector2i, rank: int = 1, rotated: bool = false) -> Dictionary:
	return {"uid": uid, "kind": kind, "id": id, "x": cell.x, "y": cell.y, "rank": rank, "rotated": rotated}

func _state(starter: String = "bone") -> RunState:
	var state := RunState.new()
	state.begin(20261025, starter)
	state.gold = 10000
	return state

func _offer(kind: String, id: String) -> Dictionary:
	return {"kind": kind, "id": id, "price": 20, "sold": false}

func _buy(state: RunState, kind: String, id: String) -> int:
	state.offers = [_offer(kind, id)]
	_check(state.buy_offer(0), "Real fixture purchase fits: " + id)
	return int(state.backpack_snapshot()["next_uid"]) - 1

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.offers, state.last_error, str(state.rng.state), state._next_rune_uid])

func _test_geometry() -> void:
	var weapon: Dictionary = _entry(1, "weapon", "bone", Vector2i(1, 1))
	var relic: Dictionary = _entry(2, "relic", "damage", Vector2i(0, 2))
	var expected := PackedVector2Array([Vector2(1, 2), Vector2(1, 3)])
	_check(BackpackResonance.contact_segment(weapon, relic) == expected and BackpackResonance.contact_segment(relic, weapon) == expected, "Shared edges have canonical endpoints independent of argument order")
	for cell: Vector2i in [Vector2i(0, 4), Vector2i(0, 5), Vector2i(1, 2)]:
		relic["x"] = cell.x
		relic["y"] = cell.y
		_check(BackpackResonance.contact_segment(weapon, relic).is_empty(), "Corner contact, gaps and overlaps are not shared edges: " + str(cell))
	weapon = _entry(1, "weapon", "ember", Vector2i(2, 2))
	relic = _entry(2, "relic", "blood_pact", Vector2i(2, 1))
	_check(BackpackResonance.contact_segment(weapon, relic) == PackedVector2Array([Vector2(2, 2), Vector2(4, 2)]), "A two-cell horizontal edge returns its complete shared interval")
	_check(is_equal_approx(float(BackpackResonance.evaluate([weapon, relic])[1]["bonus"]), 0.03), "A multi-cell edge counts its relic only once")
	weapon = _entry(1, "weapon", "bone", Vector2i(2, 1))
	relic = _entry(2, "relic", "grave_candle", Vector2i(0, 3))
	_check(not BackpackResonance.contact_segment(weapon, relic).is_empty(), "The wide candle reaches the weapon's left edge")
	relic["rotated"] = true
	_check(BackpackResonance.contact_segment(weapon, relic).is_empty(), "Rotation uses the actual swapped footprint rather than its original bounds")
	_check(BackpackResonance.contact_segment({}, weapon).is_empty() and BackpackResonance.evaluate([{}, "invalid", 0]).is_empty(), "Malformed or unknown content cannot create a resonance source")

func _test_weights_and_isolation() -> void:
	var weapon: Dictionary = _entry(1, "weapon", "bone", Vector2i(2, 1))
	for rank: int in range(1, 4):
		var relic: Dictionary = _entry(2, "relic", "armor", Vector2i(1, 2), rank)
		var result: Dictionary = BackpackResonance.evaluate([weapon, relic])[1]
		var weight: int = 1 << (rank - 1)
		_check(result["weight"] == weight and is_equal_approx(float(result["raw_bonus"]), weight * 0.03) and is_equal_approx(float(result["bonus"]), weight * 0.03), "Ranks one/two/three contribute weights one/two/four: " + str(rank))
	var left: Dictionary = _entry(10, "relic", "armor", Vector2i(1, 2), 3)
	var right: Dictionary = _entry(11, "relic", "damage", Vector2i(3, 1), 3)
	var result: Dictionary = BackpackResonance.evaluate([weapon, right, left, left.duplicate(true)])[1]
	_check(result["weight"] == 8 and is_equal_approx(float(result["raw_bonus"]), 0.24) and is_equal_approx(float(result["bonus"]), 0.18) and result["source_uids"] == [10, 11], "Unique UID sources are sorted, deduplicated and capped at eighteen percent")
	var entries: Array = [_entry(1, "weapon", "bone", Vector2i.ZERO), _entry(2, "relic", "damage", Vector2i(1, 0)), _entry(3, "relic", "armor", Vector2i(2, 0)), _entry(4, "rune", "pierce", Vector2i(1, 1)), _entry(5, "weapon", "frost", Vector2i(4, 0))]
	var before: String = JSON.stringify(entries)
	var map: Dictionary = BackpackResonance.evaluate(entries)
	_check(map[1]["source_uids"] == [2] and map[5]["source_uids"].is_empty() and map[5]["bonus"] == 0.0, "Relics do not conduct through each other and loose runes do not grant resonance")
	map[1]["source_uids"].append(999)
	_check(JSON.stringify(entries) == before and BackpackResonance.evaluate(entries)[1]["source_uids"] == [2], "Evaluation and returned arrays cannot mutate the input or later results")

func _cells(entry: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var dimensions: Vector2i = BackpackInventory.size_for(entry["kind"], entry["id"], entry["rotated"])
	for row: int in dimensions.y:
		for column: int in dimensions.x:
			result[Vector2i(int(entry["x"]) + column, int(entry["y"]) + row)] = true
	return result

func _cell_edge_oracle(first: Dictionary, second: Dictionary) -> bool:
	var a: Dictionary = _cells(first)
	var b: Dictionary = _cells(second)
	for cell: Vector2i in a:
		if b.has(cell):
			return false
	for cell: Vector2i in a:
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if b.has(cell + direction):
				return true
	return false

func _test_generated_contacts() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 20261025
	var weapons: Array[ContentDef] = GameCatalog.weapons()
	var relics: Array[ContentDef] = GameCatalog.relics()
	for trial: int in 180:
		var weapon: Dictionary = _entry(1, "weapon", weapons[trial % weapons.size()].id, Vector2i(random.randi_range(-1, 5), random.randi_range(-1, 5)), 1, random.randi_range(0, 1) == 1)
		var relic: Dictionary = _entry(2, "relic", relics[trial % relics.size()].id, Vector2i(random.randi_range(-1, 5), random.randi_range(-1, 5)), 1 + trial % 3, random.randi_range(0, 1) == 1)
		var adjacent: bool = _cell_edge_oracle(weapon, relic)
		var segment: PackedVector2Array = BackpackResonance.contact_segment(weapon, relic)
		_check((not segment.is_empty()) == adjacent and (segment.is_empty() or (segment.size() == 2 and segment[0] != segment[1])), "Rectangle contact matches an independent occupied-cell oracle: " + str(trial))
		var expected: float = float(1 << (int(relic["rank"]) - 1)) * 0.03 if adjacent else 0.0
		_check(is_equal_approx(float(BackpackResonance.evaluate([weapon, relic])[1]["bonus"]), expected), "Generated geometry grants precisely one rank-weighted source: " + str(trial))

func _test_transactions_and_cache() -> void:
	var state: RunState = _state()
	var armor: int = _buy(state, "relic", "armor")
	var base: float = GameCatalog.weapon("bone").damage
	_check(state.stat("damage") == 1.0 and is_equal_approx(state.weapon_damage(state.loadout[0]), base * 1.03) and state.loadout[0]["resonance_sources"] == [armor], "A real adjacent purchase updates only the weapon-local damage bonus")
	var snapshot: Dictionary = state.backpack_snapshot()
	snapshot["resonance"][1]["source_uids"].append(999)
	snapshot["resonance"][1]["bonus"] = 99.0
	_check(state.backpack_snapshot()["resonance"][1]["source_uids"] == [armor] and is_equal_approx(state.weapon_damage(state.backpack_item(1)), base * 1.03), "Snapshots deeply isolate the cache and raw item queries resolve their real UID")
	var diagnostic: Dictionary = state.backpack_item(1)
	diagnostic["resonance_bonus"] = NAN
	_check(state.weapon_damage(diagnostic) == base, "Non-finite local multipliers cannot enter a weapon forecast")
	diagnostic["resonance_bonus"] = 2.0
	_check(is_equal_approx(state.weapon_damage(diagnostic), base * 1.18), "Explicit diagnostic records obey the same resonance ceiling as combat")
	var gold: int = state.gold
	var rng_before: int = state.rng.state
	_check(state.move_item(armor, Vector2i(5, 3), false) and state.loadout[0]["resonance_bonus"] == 0.0 and state.weapon_damage(state.loadout[0]) == base, "Moving away removes the cached resonance immediately")
	_check(state.gold == gold and state.rng.state == rng_before and int(state.loadout[0]["uid"]) == 1, "Manual arrangement changes neither identity, money nor RNG")
	var before: Dictionary = state.backpack_snapshot()
	_check(not state.move_item(armor, Vector2i(-1, 0), false) and state.backpack_snapshot() == before, "Rejected placement preserves both item geometry and resonance cache")
	_check(state.move_item(armor, Vector2i(1, 0), false) and is_equal_approx(float(state.loadout[0]["resonance_bonus"]), 0.03), "Restoring an edge restores its bonus")
	_check(state.sell_item(armor) and state.loadout[0]["resonance_bonus"] == 0.0, "Selling a source removes its cached local effect")
	state.begin(2027, "ember")
	_check(state.backpack_snapshot()["resonance"].size() == 1 and state.loadout[0]["resonance_bonus"] == 0.0 and state.loadout[0]["resonance_sources"].is_empty(), "New runs do not inherit resonance sources or cached bonuses")

func _test_purchase_forecasts() -> void:
	var state: RunState = _state()
	_buy(state, "relic", "armor")
	state.offers = [_offer("weapon", "frost")]
	state.gold = 0
	var before: String = _signature(state)
	var preview: Dictionary = state.weapon_purchase_preview(0)
	var saved: Dictionary = preview.duplicate(true)
	_check(not preview["can_buy"] and preview["has_projection"] and preview["placement"]["cell"] == Vector2i(2, 0) and is_equal_approx(float(preview["resonance_bonus"]), 0.03), "Unaffordable weapons may forecast their actual deterministic empty-cell placement")
	_check(_signature(state) == before, "Weapon forecasts preserve layout, cached resonance, wallet, errors and RNG")
	preview["placement"]["x"] = 999
	preview["resonance_sources"].append(999)
	_check(state.weapon_purchase_preview(0) == saved and _signature(state) == before, "Weapon purchase forecasts return isolated nested records")
	state.gold = 1000
	_check(state.buy_offer(0), "The funded forecasted weapon transaction succeeds")
	_check(is_equal_approx(state.weapon_damage(state.loadout.back()), float(saved["damage"])) and state.loadout.back()["resonance_sources"] == saved["resonance_sources"], "Actual purchased damage and sources match the forecast")
	preview = state.weapon_purchase_preview(0)
	_check(not preview["has_projection"] and preview["placement"].is_empty() and preview["damage"] == 0.0, "A sold weapon does not advertise another placement or false resonance")
	_check(state.weapon_purchase_preview(-1).is_empty() and state.weapon_purchase_preview(1).is_empty(), "Invalid weapon offer indices have no projection")
	state.offers = [_offer("relic", "damage")]
	_check(state.weapon_purchase_preview(0).is_empty(), "Non-weapon offers have no weapon forecast")
	state = _state()
	state.offers = [_offer("relic", "damage")]
	preview = state.relic_purchase_preview(0)
	_check(preview["placement_available"] and is_equal_approx(float(preview["weapon_changes"][0]["damage_after"]), GameCatalog.weapon("bone").damage * 1.15 * 1.03), "Relic forecasts combine the real purchase cell with its additive global effect")
	_check(state.buy_offer(0) and is_equal_approx(state.weapon_damage(state.loadout[0]), float(preview["weapon_changes"][0]["damage_after"])), "The real relic purchase matches both local and global projected damage")
	for index: int in 36:
		if not state.backpack.can_add("rune", "pierce"):
			break
		_buy(state, "rune", "pierce")
	state.offers = [_offer("relic", "damage")]
	preview = state.relic_purchase_preview(0)
	_check(not preview["can_buy"] and preview["has_projection"] and not preview["placement_available"] and preview["placement"].is_empty(), "Full-grid relic forecasts explicitly separate global hypotheses from unavailable placement")
	_check(is_equal_approx(float(preview["weapon_changes"][0]["resonance_after"]), 0.03) and is_equal_approx(float(preview["weapon_changes"][0]["damage_after"]), GameCatalog.weapon("bone").damage * 1.30 * 1.03), "Full-grid hypotheses retain existing resonance without inventing a new neighboring source")
	state.offers = [_offer("weapon", "bone")]
	preview = state.weapon_purchase_preview(0)
	_check(not preview["has_projection"] and preview["placement"].is_empty() and preview["damage"] == 0.0, "A full backpack does not invent a weapon purchase placement")
	var rune_preview: Dictionary = state.rune_equip_preview(0, 0)
	_check(is_equal_approx(float(rune_preview["damage"]), state.weapon_damage(state.loadout[0])) and is_equal_approx(float(rune_preview["resonance_bonus"]), 0.03), "Rune previews expose unchanged current local damage while only changing the socket")

func _test_merge_forecasts() -> void:
	var state: RunState = _state()
	var source: int = _buy(state, "weapon", "bone")
	_buy(state, "relic", "armor")
	var base: float = GameCatalog.weapon("bone").damage
	var before: String = _signature(state)
	var preview: Dictionary = state.merge_preview(source, 1)
	_check(is_equal_approx(float(preview["damage_before"]), base) and is_equal_approx(float(preview["source_damage_before"]), base * 1.03) and is_equal_approx(float(preview["combined_damage_before"]), base * 2.03), "Merge previews distinguish source and target damage when their neighbors differ")
	_check(is_equal_approx(float(preview["damage_after"]), base * 2.0) and preview["resonance_after"] == 0.0 and _signature(state) == before, "Merged-target forecasts use the actual remaining layout without mutating inventory")
	_check(state.merge_items(source, 1) and is_equal_approx(state.weapon_damage(state.loadout[0]), float(preview["damage_after"])), "Actual weapon merge agrees with the independent forecast")
	state = _state()
	var neighboring: int = _buy(state, "relic", "armor")
	var distant: int = _buy(state, "relic", "armor")
	preview = state.merge_preview(neighboring, distant)
	_check(preview["weapon_changes"].size() == 1 and is_equal_approx(float(preview["weapon_changes"][0]["resonance_before"]), 0.03) and preview["weapon_changes"][0]["resonance_after"] == 0.0, "Relic merge previews reveal local power lost when the adjacent source is consumed")
	_check(state.merge_items(neighboring, distant) and state.relic_counts["armor"] == 2 and state.weapon_damage(state.loadout[0]) == base, "Relic merges preserve global weight while recalculating local geometry")
