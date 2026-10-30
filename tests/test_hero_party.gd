extends SceneTree
## Character identity, real party bonuses and forecasts share one inventory contract.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_main_characters()
	_test_rear_identity_and_ranks()
	_test_shop_excludes_main_character()
	_test_real_party_transactions()
	_test_purchase_forecasts()
	_test_merge_forecasts()
	_test_relic_and_weapon_forecasts()
	_test_health_boundaries()
	print("HeroParty: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(hero_id: String = "alk") -> RunState:
	var state := RunState.new()
	state.begin(20261030, "", "reliquary", hero_id)
	state.gold = 10000
	return state

func _offer(kind: String, id: String, rank: int = 1) -> Dictionary:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	return {"kind": kind, "id": id, "rank": rank, "price": definition.price * rank, "sold": false}

func _buy(state: RunState, kind: String, id: String, rank: int = 1) -> int:
	state.offers = [_offer(kind, id, rank)]
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	_check(state.buy_offer(0), "Real purchase succeeds: " + kind + "/" + id)
	return uid

func _snapshot(state: RunState) -> Dictionary:
	var stats: Dictionary = {}
	for key: String in RunState.BASE_STATS:
		stats[key] = state.stat(key)
	return {"summary": state.summary(), "offers": state.offers.duplicate(true), "stats": stats,
		"rng_state": state.rng.state, "rng_seed": state.rng.seed, "error": state.last_error}

func _test_main_characters() -> void:
	var starters: Dictionary = {"alk": "bone", "clarisse": "ember", "celtie": "frost", "hanabi": "scatter", "nasir": "ember", "mordiga": "frost", "falsche": "crescent"}
	var shapes: Dictionary = {"alk": "circle", "clarisse": "circle", "celtie": "rectangle", "hanabi": "circle", "nasir": "circle", "mordiga": "circle", "falsche": "circle"}
	var damages: Dictionary = {"alk": 50.0, "clarisse": 60.0, "celtie": 35.0, "hanabi": 45.0, "nasir": 90.0, "mordiga": 65.0, "falsche": 100.0}
	var cooldowns: Dictionary = {"alk": 8.0, "clarisse": 12.0, "celtie": 7.0, "hanabi": 9.0, "nasir": 12.0, "mordiga": 10.0, "falsche": 13.0}
	var legacy_ids: Array[String] = ["alk", "clarisse", "celtie", "hanabi"]
	_check(HeroCatalog.IDS == ["alk", "clarisse", "celtie", "hanabi", "nasir", "mordiga", "falsche"] and HeroCatalog.LEGACY_IDS == legacy_ids and HeroCatalog.normalize_id("missing") == "alk", "Seven characters preserve all four legacy identities and a deterministic fallback")
	var profiles_value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/worldflipper/action_profiles.json"))
	_check(profiles_value is Dictionary, "The added characters have an actual compiled action-profile registry")
	var profiles: Dictionary = profiles_value if profiles_value is Dictionary else {}
	for id: String in HeroCatalog.IDS:
		var hero: HeroDef = HeroCatalog.definition(id)
		var state: RunState = _state(id)
		_check(hero.id == id and hero.starter_weapon == starters[id] and state.hero_id == id and state.loadout[0]["id"] == starters[id], "A selected hero owns the corresponding default weapon: " + id)
		var expected_portrait: String = "res://assets/worldflipper/portraits/" + id + ".png" if id in legacy_ids else "res://assets/worldflipper/roster/" + id + "/portrait.png"
		_check(not hero.display_name.is_empty() and hero.idle_path.begins_with("res://assets/worldflipper/") and hero.atlas_path.ends_with(".png") and hero.portrait_path == expected_portrait, "Character identity owns all three source-art paths: " + id)
		for path: String in [hero.idle_path, hero.atlas_path, hero.portrait_path]:
			_check(ResourceLoader.exists(path, "Texture2D"), "Character art resolves to a real imported resource: " + id + "/" + path)
		_check(hero.frame_size == (96 if id == "alk" else 128) and hero.foot_anchor == (Vector2(48, 93) if id == "alk" else Vector2(64, 125)), "Per-character art retains its complete frame and foot anchor: " + id)
		if id not in legacy_ids:
			var profile: Dictionary = {}
			for candidate: Dictionary in profiles.get("profiles", []):
				if str(candidate.get("canonical_id", "")) == hero.source_id:
					profile = candidate
					break
			var source: Dictionary = profile.get("root_source", {})
			_check(bool(profile.get("runtime_profile_ready", false)) and str(profile.get("skill_id", "")) == str(hero.action_evidence.get("catalog_skill_id", "")) and str(profile.get("action_ref", "")) == str(hero.action_evidence.get("action_ref", "")), "An added character binds its actual canonical compiled action profile: " + id)
			_check(not source.is_empty() and source.get("sha256") == hero.action_evidence.get("action_sha256") and source.get("git_blob_sha1") == hero.action_evidence.get("git_blob_sha1") and profiles.get("source_commit") == hero.action_evidence.get("source_commit"), "The playable resource preserves its compiled source hashes and fixed commit: " + id)
			_check(not hero.main_skill.get("timeline", []).is_empty() and hero.main_skill["timeline"].size() == profile.get("timeline", []).size(), "An added character uses its real compiled timeline rather than a fallback skill: " + id)
		for key: String in RunState.BASE_STATS:
			_check(is_equal_approx(state.stat(key), float(RunState.BASE_STATS[key]) + float(hero.base_bonuses.get(key, 0.0))), "Main-character bonuses reach actual stats: " + id + "/" + key)
		_check(state.health == state.stat("max_health") and state.active_skills.is_empty() and state.backpack_snapshot()["items"].size() == 1, "R starts available independently of backpack ownership: " + id)
		var before: Dictionary = _snapshot(state)
		var parameters: Dictionary = state.hero_skill_parameters()
		_check(parameters["id"] == "hero_" + id and parameters["hero_id"] == id and parameters["rank"] == 1 and parameters["shape"] == shapes[id], "R exposes a real character-specific identity and geometry: " + id)
		_check(is_equal_approx(float(parameters["damage"]), float(damages[id]) * state.stat("damage")) and parameters["cooldown"] == cooldowns[id], "R uses the same actual damage multiplier and independent cooldown: " + id)
		_check(parameters["origin_mode"] == ("forward" if id == "clarisse" else "player"), "R origin is explicit for simulation: " + id)
		parameters["damage"] = -100.0
		_check(_snapshot(state) == before and state.hero_skill_parameters()["damage"] >= 0.0, "R previews consume neither cells, UID, RNG nor mutable definition state: " + id)
		_check(state.summary()["hero_id"] == id and state.summary()["hero"]["name"] == hero.display_name, "Summary retains the real selected identity: " + id)
	var legacy := RunState.new()
	legacy.begin(7, "frost")
	_check(legacy.hero_id == "alk" and legacy.loadout[0]["id"] == "frost", "The original two-argument start preserves old starter selection")
	legacy.begin(7, "invalid", "missing", "missing")
	_check(legacy.hero_id == "alk" and legacy.loadout[0]["id"] == "bone" and legacy.active_skills.is_empty(), "Invalid legacy selections cannot create a partial party")
	for invalid: Variant in [INF, NAN, "invalid"]:
		_check(HeroCatalog.hero_skill_parameters("alk", {"damage": invalid})["damage"] == 50.0, "Malformed projected stats cannot create a nonfinite hero cast")

func _test_rear_identity_and_ranks() -> void:
	var ids: Dictionary = {"pulse": "clarisse", "starfall": "hanabi", "arc_slash": "celtie"}
	var keys: Dictionary = {"pulse": "damage", "starfall": "max_health", "arc_slash": "attack_speed"}
	var amounts: Dictionary = {"pulse": 0.08, "starfall": 12.0, "arc_slash": 0.06}
	_check(ActiveSkillRules.LIMIT == 2 and HeroCatalog.rear_for_skill("missing") == null and HeroCatalog.rear_bonuses("missing", 1).is_empty(), "Only actual rear characters use the existing two slots")
	for id: String in ids:
		for rank: int in range(1, 4):
			var hero: HeroDef = HeroCatalog.rear_for_skill(id)
			var bonuses: Dictionary = HeroCatalog.rear_bonuses(id, rank)
			var parameters: Dictionary = ActiveSkillRules.parameters(id, rank, {})
			_check(hero.id == ids[id] and parameters["hero_id"] == hero.id and parameters["name"] == hero.display_name and GameCatalog.skill(id).display_name == hero.display_name, "Rear identity is shared by catalog, item and cast: " + id)
			_check(is_equal_approx(float(bonuses[keys[id]]), float(amounts[id]) * [1.0, 2.0, 4.0][rank - 1]) and parameters["rear_bonuses"] == bonuses, "Rear attributes use exact one/two/four rank weights: " + id)
			_check(not str(parameters["skill_name"]).is_empty() and parameters["id"] == id and parameters["rank"] == rank, "Stable skill IDs and independent skill names survive the character conversion: " + id)
			bonuses[keys[id]] = -1000.0
			_check(float(HeroCatalog.rear_bonuses(id, rank)[keys[id]]) > 0.0, "Callers cannot mutate shared rear bonus definitions")

func _test_shop_excludes_main_character() -> void:
	for hero_id: String in HeroCatalog.IDS:
		for seed_value: int in range(1, 25):
			var state := RunState.new()
			state.begin(seed_value, "", "reliquary", hero_id)
			for wave_number: int in [1, 4]:
				state.wave = wave_number
				state.generate_shop()
				_check(state.offers.size() == 4, "Character filtering keeps a complete shop")
				for offer: Dictionary in state.offers:
					if offer["kind"] == "skill":
						_check(HeroCatalog.rear_for_skill(str(offer["id"])).id != hero_id, "Generated companions never duplicate the selected main character")
		for definition: ContentDef in GameCatalog.skills():
			var state: RunState = _state(hero_id)
			if HeroCatalog.rear_for_skill(definition.id).id != hero_id:
				continue
			state.offers = [_offer("skill", definition.id)]
			var before: Dictionary = _snapshot(state)
			var preview: Dictionary = state.skill_purchase_preview(0)
			_check(not preview["can_buy"] and not preview["has_projection"] and preview["error"] == "主角不能同时作为后排。" and _snapshot(state) == before, "An injected self-companion has a pure explicit refusal")
			_check(not state.buy_offer(0) and state.backpack_snapshot()["items"] == before["summary"]["backpack"]["items"] and state.gold == before["summary"]["gold"] and state.rng.state == before["rng_state"], "A rejected self-companion cannot spend or consume identity")
			_check(not state.set_offer_locked(0, true) and state.locked_offer_count() == 0, "A rejected self-companion cannot be retained by shop locks")

func _test_real_party_transactions() -> void:
	var state: RunState = _state()
	var pulse: int = _buy(state, "skill", "pulse")
	var slash: int = _buy(state, "skill", "arc_slash")
	_check(is_equal_approx(state.stat("damage"), 1.08) and is_equal_approx(state.stat("attack_speed"), 1.06), "Purchased companions affect real damage and attack speed")
	_check(state.active_skills[0]["uid"] == pulse and state.active_skills[1]["uid"] == slash, "Q/E maintain ascending stable item identities")
	_check(state.move_item(pulse, Vector2i(5, 1), true) and state.active_skills[0]["uid"] == pulse and state.active_skills[0]["rotated"], "Rotating and moving a rear character preserves its active slot identity")
	state.offers = [_offer("skill", "starfall")]
	var before: Dictionary = _snapshot(state)
	_check(not state.buy_offer(0) and state.active_skills.size() == 2 and state.backpack_snapshot()["next_uid"] == before["summary"]["backpack"]["next_uid"], "R does not bypass or consume the two-companion cap")
	_check(state.sell_item(pulse) and is_equal_approx(state.stat("damage"), 1.0) and state.active_skills[0]["uid"] == slash, "Selling a companion removes its actual bonus and projects remaining identity")
	_check(state.sell_item(slash) and is_equal_approx(state.stat("attack_speed"), 1.0), "Selling the second companion clears the cached speed bonus")

func _assert_forecast(state: RunState, preview: Dictionary) -> void:
	for change: Dictionary in preview.get("stat_changes", []):
		_check(is_equal_approx(float(change["after"]), state.stat(str(change["key"]))), "Projected party attribute equals the actual transaction: " + str(change["key"]))
	for change: Dictionary in preview.get("weapon_changes", []):
		var slot: int = state.weapon_index_for_uid(int(change["uid"]))
		_check(slot >= 0 and is_equal_approx(float(change["damage_after"]), state.weapon_damage(state.loadout[slot])) and is_equal_approx(float(change["interval_after"]), GameCatalog.weapon(str(change["id"])).cooldown / state.stat("attack_speed")), "Projected weapon damage and interval equal the real party")
	if preview.has("health_after"):
		_check(is_equal_approx(float(preview["health_after"]), state.health), "Projected health equals the real transaction")

func _test_purchase_forecasts() -> void:
	for hero_id: String in HeroCatalog.IDS:
		for definition: ContentDef in GameCatalog.skills():
			if HeroCatalog.rear_for_skill(definition.id).id == hero_id:
				continue
			for rank: int in [1, 2]:
				var state: RunState = _state(hero_id)
				state.health = 40.0
				state.offers = [_offer("skill", definition.id, rank)]
				var before: Dictionary = _snapshot(state)
				var preview: Dictionary = state.skill_purchase_preview(0)
				_check(preview["can_buy"] and preview == state.skill_purchase_preview(0) and _snapshot(state) == before, "Repeated companion forecasts preserve inventory, resources, health and RNG")
				_check(state.buy_offer(0) and preview["parameters"] == state.active_skill_parameters(state.active_skills[0]), "Purchased skill parameters include their own final party context")
				_assert_forecast(state, preview)
	var linked: RunState = _state()
	_buy(linked, "skill", "pulse", 2)
	linked.offers = [_offer("skill", "starfall")]
	var preview: Dictionary = linked.skill_purchase_preview(0)
	_check(is_equal_approx(float(preview["damage"]), 32.0 * 1.16) and linked.buy_offer(0), "A second companion's damage preview includes the equipped first companion")
	_check(is_equal_approx(float(preview["damage"]), float(linked.active_skill_parameters(linked.active_skills[1])["damage"])), "The purchased second companion casts at the forecast damage")

func _test_merge_forecasts() -> void:
	for id: String in ["pulse", "starfall", "arc_slash"]:
		for rank: int in [1, 2]:
			var state: RunState = _state()
			var target: int = _buy(state, "skill", id, rank)
			var source: int = _buy(state, "skill", id, rank)
			state.health = 38.0
			var before: Dictionary = _snapshot(state)
			var preview: Dictionary = state.merge_preview(source, target)
			_check(preview["can_merge"] and _snapshot(state) == before and preview == state.merge_preview(source, target), "Merge forecasts are pure for every companion and legal source rank")
			_check(state.merge_items(source, target) and state.active_skills.size() == 1 and state.active_skills[0]["uid"] == target and state.backpack_item(source).is_empty(), "A merge retains the target's identity and frees the source slot")
			_check(preview["skill_after"] == state.active_skill_parameters(state.active_skills[0]), "Merged skill damage and control parameters use the post-merge party")
			_assert_forecast(state, preview)
			for change: Dictionary in preview["stat_changes"]:
				_check(is_equal_approx(float(change["before"]), float(change["after"])), "One/two/four weighting preserves aggregate companion attributes during a same-tier merge")
			_check(state.sell_item(target) and state.health == 38.0 and state.stat("damage") == 1.0 and state.stat("attack_speed") == 1.0 and state.stat("max_health") == 100.0, "Selling the merged companion removes all rank-weighted attributes without healing")

func _test_relic_and_weapon_forecasts() -> void:
	var state: RunState = _state("hanabi")
	_buy(state, "skill", "pulse", 2)
	_buy(state, "skill", "arc_slash", 2)
	state.health = 37.0
	state.offers = [_offer("relic", "moon_charm")]
	var before: Dictionary = _snapshot(state)
	var relic: Dictionary = state.relic_purchase_preview(0)
	_check(_snapshot(state) == before and state.buy_offer(0), "Relic comparisons preserve the existing main character and two-companion context")
	_assert_forecast(state, relic)
	_check(is_equal_approx(state.projected_upgrade_stat("damage", 0.12), state.stat("damage") + 0.12), "Upgrade projections include both hero and rear attributes")
	state.offers = [_offer("weapon", "bone")]
	var weapon: Dictionary = state.weapon_purchase_preview(0)
	var uid: int = int(state.backpack_snapshot()["next_uid"])
	_check(weapon["can_buy"] and state.buy_offer(0), "Weapon comparison remains purchasable with a full rear party")
	var item: Dictionary = state.backpack_item(uid)
	_check(is_equal_approx(float(weapon["damage"]), state.weapon_damage(item)) and is_equal_approx(float(weapon["interval"]), GameCatalog.weapon("bone").cooldown / state.stat("attack_speed")), "New-weapon forecast uses actual companion damage, speed and placement resonance")
	_check(is_equal_approx(float(state.hero_skill_parameters()["damage"]), 45.0 * state.stat("damage")), "Relics and companions also affect the independent R skill")

func _test_health_boundaries() -> void:
	var state: RunState = _state()
	var first: int = _buy(state, "skill", "starfall")
	_check(state.stat("max_health") == 112.0 and state.health == 100.0, "Recruiting a max-health companion creates capacity without free healing")
	state.health = 110.0
	_check(state.sell_item(first) and state.health == 100.0 and state.stat("max_health") == 100.0, "Losing companion max health clamps current health to the real remaining cap")
	state.health = 34.0
	first = _buy(state, "skill", "starfall", 2)
	_check(state.health == 34.0 and state.stat("max_health") == 124.0 and state.sell_item(first) and state.health == 34.0, "Recruiting and dismissing a ranked companion never heals a wounded player")
	_buy(state, "skill", "pulse")
	state.begin(9, "", "reliquary", "hanabi")
	_check(state.hero_id == "hanabi" and state.health == 108.0 and state.active_skills.is_empty() and state.stat("damage") == 1.0 and state.backpack_snapshot()["next_uid"] == 2, "Restart resets prior companions, UID and cached bonuses before applying the selected hero")
