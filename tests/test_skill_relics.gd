extends SceneTree
## Active-skill relic growth uses the same priced inventory transactions and forecasts as every relic.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_catalog_and_defaults()
	_test_ranked_transactions()
	_test_purchase_projections()
	_test_caps_and_tradeoffs()
	_test_atomic_failures()
	_test_resonance_and_restart()
	print("SkillRelics: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261028, "bone")
	state.collect_souls(4000)
	return state

func _offer(id: String, kind: String = "relic") -> Dictionary:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	return {"kind": kind, "id": id, "price": definition.price, "sold": false}

func _buy(state: RunState, id: String, kind: String = "relic") -> int:
	state.offers = [_offer(id, kind)]
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	var wallet: int = state.gold
	var bought: bool = state.buy_offer(0)
	_check(bought and state.gold == wallet - int(state.offers[0]["price"]), "A real priced purchase enters the shared backpack: " + id)
	return uid if bought else -1

func _stats(state: RunState) -> Dictionary:
	var result: Dictionary = {}
	for key: String in RunState.BASE_STATS:
		result[key] = state.stat(key)
	return result

func _snapshot(state: RunState) -> Dictionary:
	return {"summary": state.summary(), "stats": _stats(state), "offers": state.offers.duplicate(true),
		"rng_state": state.rng.state, "rng_seed": state.rng.seed, "next_uid": state._next_rune_uid,
		"bonuses": state._upgrade_bonuses.duplicate(true), "upgrade_options": state._upgrade_options.duplicate(true)}

func _ranked(state: RunState, id: String, rank: int) -> int:
	var target: int = _buy(state, id)
	if target < 0:
		return -1
	for previous_rank: int in range(1, rank):
		var source: int = _ranked(state, id, previous_rank)
		var stats_before: Dictionary = _stats(state)
		var wallet: int = state.gold
		var before: Dictionary = state.backpack_snapshot()
		var forecast: Dictionary = state.merge_preview(source, target)
		_check(bool(forecast.get("can_merge", false)) and int(forecast.get("cells_freed", 0)) == 1, "A same-rank skill relic advertises a real one-cell merge: " + id)
		_check(state.merge_items(source, target), "Formal merges grow the skill relic: " + id)
		_check(_stats(state) == stats_before and state.gold == wallet, "Merging keeps both copies' combined skill benefits and costs without spending: " + id)
		_check(int(state.backpack_snapshot()["used_cells"]) == int(before["used_cells"]) - 1 and int(state.backpack_snapshot()["next_uid"]) == int(before["next_uid"]), "A merge releases one cell and preserves the next identity")
		var item: Dictionary = state.backpack_item(target)
		_check(state.backpack_item(source).is_empty() and int(item["rank"]) == previous_rank + 1 and int(item["paid"]) == 22 * int(BackpackInventory.rank_multiplier(previous_rank + 1)), "The target identity retains rank and every actual purchase payment")
	return target

func _test_catalog_and_defaults() -> void:
	_check(GameCatalog.relics().size() == 14, "The formal catalog has fourteen relics")
	for id: String in ["fold_clasp", "echo_stone"]:
		var definition: ContentDef = GameCatalog.relic(id)
		_check(definition != null and definition.id == id and definition.kind == "relic" and definition.price == 22, "A skill relic is available through the normal catalog: " + id)
		_check(BackpackInventory.size_for("relic", id) == Vector2i.ONE and BackpackInventory.size_for("relic", id, true) == Vector2i.ONE, "A skill relic remains one cell when rotated: " + id)
	var state: RunState = _state()
	_check(is_equal_approx(state.stat("dash_cooldown"), 2.4) and is_equal_approx(state.stat("pulse_radius"), 144.0) and is_equal_approx(state.stat("pulse_cooldown"), 8.0), "A fresh run retains all previous skill defaults")
	_check(state.stat("move_speed") == 220.0 and state.stat("damage") == 1.0 and state.stat("attack_speed") == 1.0, "Adding skill attributes preserves the existing movement and attack defaults")
	var original_upgrades: Array[String] = ["damage", "haste", "speed", "vitality", "armor", "magnet"]
	for index: int in original_upgrades.size():
		_check(str(RunState.UPGRADE_POOL[index]["id"]) == original_upgrades[index], "Existing level-up choices retain their original order and identity")
	_check(RunState.UPGRADE_POOL.size() == original_upgrades.size(), "Skill relics do not enter the level-up pool")

func _test_ranked_transactions() -> void:
	for id: String in ["fold_clasp", "echo_stone"]:
		for rank: int in range(1, 4):
			var state: RunState = _state()
			var wallet: int = state.gold
			var uid: int = _ranked(state, id, rank)
			var weight: int = 1 << (rank - 1)
			_check(int(state.relic_counts.get(id, 0)) == weight and int(state.backpack_item(uid).get("rank", 0)) == rank, "Rank projects exactly 1/2/4 attribute weight: %s/%d" % [id, rank])
			_check(state.gold == wallet - 22 * weight and int(state.backpack_snapshot()["used_cells"]) == 4, "A ranked relic pays for every copy and retains a single cell")
			if id == "fold_clasp":
				_check(is_equal_approx(state.stat("dash_cooldown"), 2.4 - 0.3 * weight) and state.stat("move_speed") == 220.0 - 6.0 * weight, "Fold clasp tiers pair faster dash recharge with the real movement cost")
				_check(state.stat("pulse_radius") == 144.0 and state.stat("pulse_cooldown") == 8.0, "Fold clasp does not alter pulse rules")
			else:
				_check(state.stat("pulse_radius") == 144.0 + 18.0 * weight and is_equal_approx(state.stat("pulse_cooldown"), 8.0 + 0.8 * weight), "Echo stone tiers pair a larger range with slower recharge")
				_check(state.stat("dash_cooldown") == 2.4 and state.stat("move_speed") == 220.0, "Echo stone does not alter dash recharge or movement")
			var before_sale: int = state.gold
			_check(state.sell_item(uid) and state.gold == before_sale + 11 * weight and state.backpack_item(uid).is_empty(), "Selling refunds half the exact combined payment and removes the ranked identity")
			_check(state.relic_counts.is_empty() and state.stat("dash_cooldown") == 2.4 and state.stat("move_speed") == 220.0 and state.stat("pulse_radius") == 144.0 and state.stat("pulse_cooldown") == 8.0, "Selling the last skill relic restores every skill property and downside")

func _test_purchase_projections() -> void:
	for id: String in ["fold_clasp", "echo_stone"]:
		var state: RunState = _state()
		_ranked(state, id, 3)
		_buy(state, "speed")
		state.health = 57.0
		state.offers = [_offer(id)]
		var before: Dictionary = _snapshot(state)
		var emissions: Array[int] = [0]
		var observe: Callable = func() -> void: emissions[0] += 1
		state.changed.connect(observe)
		var preview: Dictionary = state.relic_purchase_preview(0)
		_check(state.relic_purchase_preview(0) == preview and _snapshot(state) == before and emissions[0] == 0, "Repeated skill forecasts are read-only, deterministic and signal-free: " + id)
		state.changed.disconnect(observe)
		_check(bool(preview["can_buy"]) and int(preview["stack_before"]) == 4 and int(preview["stack_after"]) == 5, "A purchase alongside a third-rank relic forecasts a separate weight-one box")
		_check(state.buy_offer(0), "The independently forecast skill purchase succeeds")
		_check(state.gold == int(preview["gold_after"]) and state.health == float(preview["health_after"]) and state.health == 57.0, "Skill projection wallet and unchanged health match the real purchase")
		for change: Dictionary in preview["stat_changes"]:
			var key: String = str(change["key"])
			_check(is_equal_approx(float(change["before"]), float(before["stats"][key])) and is_equal_approx(float(change["after"]), state.stat(key)) and is_equal_approx(float(change["delta"]), state.stat(key) - float(before["stats"][key])), "Skill projection uses the actual clamped before/after property: " + key)
		for change: Dictionary in preview["weapon_changes"]:
			var slot: int = int(change["slot"])
			_check(is_equal_approx(float(change["damage_after"]), state.weapon_damage(state.loadout[slot])) and is_equal_approx(float(change["interval_after"]), GameCatalog.weapon(str(state.loadout[slot]["id"])).cooldown / state.stat("attack_speed")), "Skill relic forecasts retain real weapon geometry and intervals")

func _test_caps_and_tradeoffs() -> void:
	var fold: RunState = _state()
	for index: int in 5:
		_buy(fold, "fold_clasp")
	_check(is_equal_approx(fold.stat("dash_cooldown"), 1.2) and fold.stat("move_speed") == 190.0, "Stacking past the dash cooldown floor still pays all five movement costs")
	fold.offers = [_offer("fold_clasp")]
	var forecast: Dictionary = fold.relic_purchase_preview(0)
	_check(is_equal_approx(float(forecast["stat_changes"][0]["delta"]), 0.0) and is_equal_approx(float(forecast["stat_changes"][1]["delta"]), -6.0), "A capped dash forecast reports no extra cooldown gain and the continuing movement cost")
	var echo: RunState = _state()
	for index: int in 11:
		_buy(echo, "echo_stone")
	_check(echo.stat("pulse_radius") == 216.0 and echo.stat("pulse_cooldown") == 16.0 and int(echo.relic_counts["echo_stone"]) == 11, "Multiple echo boxes respect the independent range and cooldown caps without discarding ownership")
	var last: Dictionary = echo.backpack_snapshot()["items"][-1]
	_check(echo.sell_item(int(last["uid"])) and echo.stat("pulse_radius") == 216.0 and echo.stat("pulse_cooldown") == 16.0, "Selling an over-cap copy correctly retains capped totals")
	last = echo.backpack_snapshot()["items"][-1]
	_check(echo.sell_item(int(last["uid"])) and is_equal_approx(echo.stat("pulse_cooldown"), 15.2) and echo.stat("pulse_radius") == 216.0, "Selling below the cooldown cap recovers the real recharge cost")
	_check(fold.stat("damage") == 1.0 and fold.stat("attack_speed") == 1.0 and echo.stat("max_health") == 100.0, "Skill tradeoffs do not introduce unrelated global damage, attack speed or health changes")

func _assert_failed_purchase_atomic(state: RunState, message: String) -> void:
	var before: Dictionary = _snapshot(state)
	var error: String = state.purchase_error(0)
	var preview: Dictionary = state.relic_purchase_preview(0)
	_check(not error.is_empty() and not bool(preview["can_buy"]) and int(preview["gold_after"]) == state.gold, "A blocked skill offer retains its formal refusal and actual wallet: " + message)
	_check(not state.buy_offer(0) and _snapshot(state) == before and state.last_error == error, "A failed skill transaction preserves inventory, ownership, stats, money and RNG: " + message)

func _test_atomic_failures() -> void:
	var poor: RunState = _state()
	poor.gold = 21
	poor.offers = [_offer("fold_clasp")]
	_assert_failed_purchase_atomic(poor, "insufficient gold")
	var full: RunState = _state()
	for index: int in 21:
		_buy(full, "pierce", "rune")
	_check(int(full.backpack_snapshot()["used_cells"]) == int(full.backpack_snapshot()["total_cells"]), "Twenty-one legal single-cell rune purchases fill the starter's remaining grid")
	full.offers = [_offer("echo_stone")]
	_assert_failed_purchase_atomic(full, "full real grid")
	var mixed: RunState = _state()
	var clasp: int = _buy(mixed, "fold_clasp")
	var stone: int = _buy(mixed, "echo_stone")
	var before: Dictionary = _snapshot(mixed)
	_check(not mixed.merge_items(clasp, stone) and _snapshot(mixed) == before, "Different skill relics cannot merge and a refusal preserves both benefits and costs")
	before = _snapshot(mixed)
	_check(not mixed.move_item(clasp, Vector2i(-1, 0), false) and _snapshot(mixed) == before, "An invalid skill-relic placement cannot change inventory projections")
	before = _snapshot(mixed)
	_check(not mixed.sell_item(-1) and _snapshot(mixed) == before, "An invalid sale cannot alter skill stats or wallet")
	var sold: Dictionary = mixed.relic_purchase_preview(0)
	_check(not bool(sold["can_buy"]) and not bool(sold["has_projection"]) and (sold["stat_changes"] as Array).is_empty(), "A sold skill offer cannot forecast or purchase a second copy")

func _test_resonance_and_restart() -> void:
	for id: String in ["fold_clasp", "echo_stone"]:
		var state: RunState = _state()
		var relic_uid: int = _ranked(state, id, 3)
		var stats_before: Dictionary = _stats(state)
		_check(state.move_item(relic_uid, Vector2i(1, 1), false), "A ranked skill relic can be manually placed beside the starter")
		_check(is_equal_approx(float(state.loadout[0]["resonance_bonus"]), 0.12) and is_equal_approx(state.weapon_damage(state.loadout[0]), 14.0 * 1.12), "A third-rank skill relic provides the normal twelve-percent shared-edge weapon resonance")
		_check(state.move_item(relic_uid, Vector2i(5, 3), true), "A single-cell skill relic can rotate and move away from the starter")
		_check(float(state.loadout[0]["resonance_bonus"]) == 0.0 and _stats(state) == stats_before, "Moving or rotating removes only geometric resonance and retains global skill growth")
		state.begin(20261029, "frost")
		_check(state.relic_counts.is_empty() and state.loadout.size() == 1 and str(state.loadout[0]["id"]) == "frost" and int(state.backpack_snapshot()["used_cells"]) == 3, "A new run discards all old skill relics and retains the selected starter")
		_check(state.stat("dash_cooldown") == 2.4 and state.stat("pulse_radius") == 144.0 and state.stat("pulse_cooldown") == 8.0 and state.stat("move_speed") == 220.0, "Restart restores every skill default and removes movement penalties")
