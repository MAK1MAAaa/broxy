extends SceneTree
## Real casts reserve complete deliveries before committing per-equipment party stacks.

const STEP: float = 1.0 / 60.0
const HEALTH: float = 1000000.0
var _checks: int = 0
var _failures: int = 0

class CapturingRuntime extends WeaponEffectRuntime:
	var last_token: Variant
	func preview_main_cast(sim: CombatSim) -> Dictionary:
		var value: Dictionary = super.preview_main_cast(sim)
		last_token = value.get("token")
		return value

class RejectingRuntime extends WeaponEffectRuntime:
	func commit_main_cast(_sim: CombatSim, _candidate: Variant) -> bool:
		return false

class MutatingRuntime extends WeaponEffectRuntime:
	var moved: bool = false
	func commit_main_cast(sim: CombatSim, candidate: Variant) -> bool:
		var item: Dictionary = sim.run.backpack_item(1)
		moved = sim.run.move_item(1, Vector2i(int(item["x"]), int(item["y"])), bool(item["rotated"]))
		return super.commit_main_cast(sim, candidate)

class ObservedHealingRuntime extends WeaponEffectRuntime:
	var healing_observations: int = 0
	func _consume_healing_events() -> void:
		healing_observations += 1
		super._consume_healing_events()

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state(hero: String = "mordiga") -> RunState:
	var state := RunState.new()
	state.begin(20261101, "bone", "reliquary", hero)
	state.gold = 10000
	while state.backpack.height < BackpackInventory.MAX_HEIGHT:
		_check(state.expand_backpack(), "Equipment cast fixtures expand through the real inventory")
	return state

func _buy(state: RunState, id: String, kind: String = "weapon") -> int:
	state.offers.assign([{"id": id, "kind": kind, "rank": 1, "price": 1, "sold": false}])
	var uid: int = int(state.backpack.snapshot()["next_uid"])
	_check(state.buy_offer(0), "The real cast fixture purchases " + id)
	return uid

func _sim(state: RunState) -> CombatSim:
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.invulnerability = 99999.0
	sim.obstacles.configure([])
	sim.interactions = ArenaInteractions.new()
	sim.player_position = Vector2(640, 360)
	sim.player_direction = Vector2.RIGHT
	_quiet_weapons(sim)
	return sim

func _quiet_weapons(sim: CombatSim) -> void:
	sim._cooldowns.resize(sim.run.loadout.size())
	sim._cooldowns.fill(99999.0)

func _target(sim: CombatSim, offset: Vector2 = Vector2(80, 0)) -> CombatSim.Enemy:
	var enemy: CombatSim.Enemy = sim.spawn_enemy("tank", sim.player_position + offset, true)
	enemy.definition = enemy.definition.duplicate() as ContentDef
	enemy.definition.speed = 0.0
	enemy.action_timer = 99999.0
	enemy.health = HEALTH
	enemy.max_health = HEALTH
	return enemy

func _steps(sim: CombatSim, count: int) -> void:
	for frame: int in count:
		sim.step(STEP, Vector2.ZERO)

func _ready(sim: CombatSim) -> bool:
	_quiet_weapons(sim)
	for frame: int in 1200:
		if float(sim._hero_skill_clock.get("remaining", 0.0)) <= 0.0:
			return not sim.complete
		sim.step(STEP, Vector2.ZERO)
	return false

func _stacks(sim: CombatSim, uid: int) -> int:
	return int((sim.weapon_effects._records.get(uid, {}) as Dictionary).get("party_cast_stacks", 0))

func _signature(sim: CombatSim) -> String:
	return JSON.stringify([sim.snapshot(), sim.run.summary(), sim.run.inventory_revision, sim.run.healing_events,
		sim.skill_timeline._serial, sim.hero_effects._serial,
		str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)])

func _area() -> Dictionary:
	return {"id": "hero_fixture", "damage": 10.0, "timeline": [{"delay": 0.0, "duration": 1.0, "hits": 1, "damage_weight": 1.0, "shape": "circle", "radius": 20.0}]}

func _run() -> void:
	_test_current_cast_and_rear_addition()
	_test_caps_and_real_deliveries()
	_test_rank_merge_sale_and_wave()
	_test_rejections_and_reservation_rollback()
	_test_tokens_and_reentry()
	_test_invalid_rules_and_legacy_snapshot()
	_test_zero_impact_fast_path_and_pending_healing()
	_test_fast_path_preserves_legacy_rescue_and_damage()
	print("EquipmentCasts: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_current_cast_and_rear_addition() -> void:
	var state: RunState = _state()
	_buy(state, "bow_0006")
	_buy(state, "sword_0005")
	_buy(state, "fist_0006")
	var staff: int = _buy(state, "staff_0001")
	_buy(state, "starfall", "skill")
	_buy(state, "arc_slash", "skill")
	var sim: CombatSim = _sim(state)
	var enemy: CombatSim.Enemy = _target(sim)
	var base: float = float(HeroCatalog.definition("mordiga").main_skill["damage"])
	var expected: float = base * 2.6 * (1.0 + 0.475 + 0.05)
	var before: String = _signature(sim)
	for index: int in 4:
		_check(is_equal_approx(float(sim.hero_skill_snapshot()["damage"]), expected) and sim.weapon_effects.current_party_skill_damage(sim) == 0.0, "Ready R previews include the prospective current-cast layer without granting it")
	_check(_signature(sim) == before and _stacks(sim, staff) == 0, "Repeated R/QE snapshots and pure previews do not advance stacks or any random stream")
	_check(sim.try_hero_skill() and _stacks(sim, staff) == 1 and is_equal_approx(float(sim._hero_skill_clock["parameters"]["damage"]), expected), "One successful real R commits one old-staff layer and locks the additive Crossbow/Durendal/current-cast result")
	var fire_damage: float = 32.0 * (1.0 + 0.225 + 0.05)
	var wind_damage: float = 24.0 * 1.05
	_check(is_equal_approx(float(sim.active_skill_snapshot(0)["damage"]), fire_damage) and is_equal_approx(float(sim.active_skill_snapshot(1)["damage"]), wind_damage), "Ready rear snapshots consume current party layers and their own element without inheriting main-owner ATK or skill damage")
	var health: float = enemy.health
	_check(sim.try_active_skill(0) and is_equal_approx(health - enemy.health, fire_damage) and _stacks(sim, staff) == 1, "A real fire rear hit consumes the existing additive party layer without triggering another layer")
	_check(sim.try_active_skill(1) and _stacks(sim, staff) == 1, "A real wind rear cast also cannot trigger the main owner's staff")
	_steps(sim, 37)
	_check(float(sim.damage_by_skill.get("hero_mordiga", 0.0)) == 0.0, "Equipment cannot bypass the original source R delay")
	_steps(sim, 1)
	_check(is_equal_approx(float(sim.damage_by_skill.get("hero_mordiga", 0.0)), expected), "The delayed real R deals the once-added locked skill budget")

func _test_caps_and_real_deliveries() -> void:
	var state: RunState = _state("falsche")
	var uid: int = _buy(state, "staff_0001")
	var sim: CombatSim = _sim(state)
	_target(sim)
	var events: Array[int] = [0]
	var reference: WeakRef = weakref(sim)
	var reentry: Array[bool] = []
	sim.damage_dealt.connect(func(_point: Vector2, _amount: float, source: String, _secondary: bool, _uid: int) -> void:
		if source == "skill:hero_falsche":
			events[0] += 1
			var current: CombatSim = reference.get_ref() as CombatSim
			if current != null:
				reentry.append(current.try_hero_skill())
	)
	var expected_total: float = 0.0
	for cast: int in 5:
		_check(_ready(sim) and sim.try_hero_skill(), "The aura recasts only after its actual cooldown")
		var stacks: int = mini(cast + 1, 4)
		expected_total += 100.0 * (1.0 + stacks * 0.05)
		_steps(sim, 600)
		_check(_stacks(sim, uid) == stacks and events[0] == (cast + 1) * 30 and sim.skill_timeline._occupied == 0, "Every full ten-second/thirty-hit aura grants exactly one successful-cast layer, capped at four")
	_check(is_equal_approx(float(sim.damage_by_skill.get("hero_falsche", 0.0)), expected_total), "The five actual aura budgets use the source-declared per-layer rate exactly once")
	_check(reentry.size() == 150 and not reentry.has(true), "Every actual aura damage callback observes the locked cooldown and cannot synchronously duplicate a cast")
	var bombs_state: RunState = _state("hanabi")
	var bombs_uid: int = _buy(bombs_state, "staff_0001")
	var bombs: CombatSim = _sim(bombs_state)
	_target(bombs, Vector2(130, 0))
	_check(bombs.try_hero_skill() and bombs.hero_effects.active_count() == 5 and bombs.skill_timeline._occupied == 5 and _stacks(bombs, bombs_uid) == 1, "A real five-bomb R atomically reserves all bombs/impact areas but grants only one layer")
	var locked: Dictionary = bombs.hero_skill_snapshot()
	var part: float = float(locked["damage"]) / 5.0
	var stored_damage: float = 0.0
	for bomb: HeroSkillRuntime.Bomb in bombs.hero_effects.bombs:
		if bomb.active:
			stored_damage += bomb.damage
	_check(is_equal_approx(stored_damage, float(locked["damage"])) and bombs_state.sell_item(bombs_uid) and bombs.hero_skill_snapshot() == locked and bombs.weapon_effects.current_party_skill_damage(bombs) == 0.0, "Selling the source during real bomb preparation removes future bonuses but cannot alter the locked five-projectile damage budget")
	_quiet_weapons(bombs)
	_steps(bombs, 180)
	var actual: float = float(bombs.damage_by_skill.get("hero_hanabi", 0.0))
	_check(bombs.hero_effects.explosions == 5 and _stacks(bombs, bombs_uid) == 1 and actual > 0.0 and is_equal_approx(actual / part, roundf(actual / part)) and actual / part <= 5.000001, "Actual launches, collisions and five explosions use the pre-sale per-bomb amount and cannot multiply the cast stack event")

func _test_rank_merge_sale_and_wave() -> void:
	var state: RunState = _state()
	var target: int = _buy(state, "staff_0001")
	var source: int = _buy(state, "staff_0001")
	var sim: CombatSim = _sim(state)
	_check(sim.try_hero_skill() and _stacks(sim, target) == 1 and _stacks(sim, source) == 1, "Two owned UIDs maintain independent successful-cast counters")
	_check(state.merge_items(source, target) and is_equal_approx(sim.weapon_effects.current_party_skill_damage(sim), 0.10) and _stacks(sim, target) == 1, "Rank-II merge reads its authored rate and retains only target layers rather than adding consumed-UID layers")
	_check(_ready(sim) and sim.try_hero_skill() and _stacks(sim, target) == 2 and is_equal_approx(sim.weapon_effects.current_party_skill_damage(sim), 0.20), "Rank-II R uses two layers at the declared0.10 rate")
	var next_target: int = _buy(state, "staff_0001")
	var next_source: int = _buy(state, "staff_0001")
	_check(state.merge_items(next_source, next_target) and state.merge_items(next_target, target), "The actual inventory constructs rank III through two legal merges")
	_check(_stacks(sim, target) == 2 and is_equal_approx(sim.weapon_effects.current_party_skill_damage(sim), 0.40), "Rank III changes the rate to0.20 while retaining the target's two real layers")
	_check(_ready(sim) and sim.try_hero_skill() and is_equal_approx(sim.weapon_effects.current_party_skill_damage(sim), 0.60), "Rank-III current-cast damage includes its third real layer")
	var frozen: Dictionary = sim.hero_skill_snapshot()
	_check(state.sell_item(target) and sim.weapon_effects.current_party_skill_damage(sim) == 0.0 and sim.hero_skill_snapshot() == frozen, "Selling the granting UID stops future party bonuses without changing its already-locked R")
	var replacement: int = _buy(state, "staff_0001")
	_check(replacement != target and _stacks(sim, replacement) == 0 and sim.weapon_effects.current_party_skill_damage(sim) == 0.0, "A new same-name purchase cannot inherit an archived sold UID's layers")
	_check(_ready(sim) and sim.try_hero_skill() and _stacks(sim, replacement) == 1, "The new UID earns only its own first real layer")
	state.finish_wave()
	state.next_wave()
	sim.begin(state)
	_check(_stacks(sim, replacement) == 0 and sim.weapon_effects.current_party_skill_damage(sim) == 0.0, "The explicit project wave boundary resets old-staff layers")

func _test_rejections_and_reservation_rollback() -> void:
	for hero: String in ["falsche", "hanabi"]:
		var state: RunState = _state(hero)
		var uid: int = _buy(state, "staff_0001")
		var sim: CombatSim = _sim(state)
		var count: int = 24 if hero == "falsche" else 22
		for index: int in count:
			_check(sim.skill_timeline.enqueue(_area(), sim.player_position, Vector2.RIGHT), "The rejection fixture owns old valid shared areas")
		var before: String = _signature(sim)
		_check(not sim.try_hero_skill() and _signature(sim) == before and _stacks(sim, uid) == 0, "An insufficient real shared pool leaves all old areas, stack counters, cooldown and RNG unchanged: " + hero)
		var rollback: CombatSim = _sim(state)
		var rejector := RejectingRuntime.new()
		rejector.begin(state)
		rollback.weapon_effects = rejector
		_check(rollback.skill_timeline.enqueue(_area(), rollback.player_position + Vector2(300, 0), Vector2.RIGHT), "The rollback fixture retains a pre-existing unrelated area")
		before = _signature(rollback)
		_check(not rollback.try_hero_skill() and _signature(rollback) == before and _stacks(rollback, uid) == 0, "A rejected commit restores only its newly reserved areas/bombs and telemetry, preserving the old area: " + hero)
	var state: RunState = _state("hanabi")
	var uid: int = _buy(state, "staff_0001")
	var sim: CombatSim = _sim(state)
	for index: int in 4:
		_check(sim.hero_effects.spawn_bombs(state.hero_skill_parameters(), sim.player_position, Vector2.RIGHT), "The bomb pool fixture fills its real bounded storage")
	var before: String = _signature(sim)
	_check(not sim.try_hero_skill() and _signature(sim) == before and _stacks(sim, uid) == 0, "A full physical bomb pool rejects R without granting layers or reserving impact areas")
	var plain: CombatSim = _sim(state)
	before = _signature(plain)
	_check(not plain.try_hero_skill("mordiga") and _signature(plain) == before, "A mismatched expected character cannot trigger an owner event")
	plain.player_position = Vector2.INF
	before = _signature(plain)
	_check(not plain.try_hero_skill() and _signature(plain) == before, "A non-finite cast position does not trigger equipment or pools")
	plain.player_position = Vector2(640, 360)
	state.health = 0.0
	before = _signature(plain)
	_check(not plain.try_hero_skill() and _signature(plain) == before, "A dead owner cannot acquire a layer or cooldown")
	state.health = 100.0
	plain.complete = true
	before = _signature(plain)
	_check(not plain.try_hero_skill() and _signature(plain) == before, "A finished simulation cannot acquire a layer or cooldown")

func _test_tokens_and_reentry() -> void:
	var state: RunState = _state()
	var uid: int = _buy(state, "staff_0001")
	var sim: CombatSim = _sim(state)
	var before: String = _signature(sim)
	for invalid: Variant in [null, {}, 1, "token"]:
		_check(not sim.weapon_effects.commit_main_cast(sim, invalid) and _signature(sim) == before, "Illegal token types cannot commit any event")
	var preview: Dictionary = sim.weapon_effects.preview_main_cast(sim)
	preview["token"].payload["plan"]["bonus"] = 999.0
	_check(not sim.weapon_effects.commit_main_cast(sim, preview["token"]) and _signature(sim) == before, "A modified token cannot authorize forged global skill damage")
	preview = sim.weapon_effects.preview_main_cast(sim)
	var item: Dictionary = state.backpack_item(uid)
	_check(state.move_item(uid, Vector2i(int(item["x"]), int(item["y"])), bool(item["rotated"])), "A real inventory revision changes after a preview")
	before = _signature(sim)
	_check(not sim.weapon_effects.commit_main_cast(sim, preview["token"]) and _signature(sim) == before, "Even a same-UID layout revision invalidates a stale preview token without resetting its layers")
	var capturer := CapturingRuntime.new()
	capturer.begin(state)
	sim.weapon_effects = capturer
	var reference: WeakRef = weakref(sim)
	var attempts: Array[bool] = []
	sim.hero_skill_cast.connect(func(_hero: String, _parameters: Dictionary, _origin: Vector2, _direction: Vector2, _affected: int) -> void:
		var current: CombatSim = reference.get_ref() as CombatSim
		if current != null:
			attempts.append(current.try_hero_skill())
	)
	_check(sim.try_hero_skill() and attempts == [false] and _stacks(sim, uid) == 1, "The real cast event observes an established cooldown and cannot synchronously grant a second layer")
	var consumed: Variant = capturer.last_token
	_check(_ready(sim), "The replay fixture advances the actual cooldown")
	before = _signature(sim)
	_check(not capturer.commit_main_cast(sim, consumed) and _signature(sim) == before, "A consumed token remains invalid after cooldown expiry")
	var epoch_state := RunState.new()
	epoch_state.begin(20261101, "staff_0001", "reliquary", "mordiga")
	var epoch_sim: CombatSim = _sim(epoch_state)
	var token: Variant = epoch_sim.weapon_effects.preview_main_cast(epoch_sim)["token"]
	epoch_state.begin(20261101, "staff_0001", "reliquary", "mordiga")
	before = _signature(epoch_sim)
	_check(not epoch_sim.weapon_effects.commit_main_cast(epoch_sim, token) and _signature(epoch_sim) == before, "Restarting the same run object with identical seed/UID/revision still invalidates its previous epoch token")
	var mutant: CombatSim = _sim(state)
	var changing := MutatingRuntime.new()
	changing.begin(state)
	mutant.weapon_effects = changing
	var pools: Dictionary = mutant.hero_effects_snapshot()
	_check(not mutant.try_hero_skill() and changing.moved and mutant.hero_effects_snapshot() == pools and _stacks(mutant, uid) == 0 and mutant._hero_skill_clock.is_empty(), "An inventory change between preview and commit cancels the new reservation rather than accepting a stale cast")

func _test_invalid_rules_and_legacy_snapshot() -> void:
	var definition: ContentDef = GameCatalog.weapon("staff_0001")
	var item: Dictionary = {"uid": 2, "id": definition.id, "rank": 1, "owner_ref": {"kind": "rear", "skill_uid": 3}}
	_check(WeaponEffectRuntime._party_cast_rule(definition, item).is_empty(), "A forged rear owner cannot become a whole-party successful-main-cast source")
	var invalid: ContentDef = definition.duplicate() as ContentDef
	item["owner_ref"] = {"kind": "main"}
	for change: Dictionary in [{"max_stacks": 5}, {"amount_by_rank": [0.05, INF, 0.2]}, {"amount_by_rank": [0.05, -0.1, 0.2]}, {"applies_to_current_cast": false}]:
		invalid.equipment_effects = definition.equipment_effects.duplicate(true)
		invalid.equipment_effects[0].merge(change, true)
		_check(WeaponEffectRuntime._party_cast_rule(invalid, item).is_empty(), "Invalid scope/rate/cap/time policies cannot create a global party modifier")
	var state: RunState = _state("alk")
	_buy(state, "sword_0012")
	var sim: CombatSim = _sim(state)
	var baseline: Dictionary = sim.weapon_effects.snapshot()
	_check(not baseline.has("party_skill_damage") and not baseline["items"][0].has("party_cast_stacks"), "The old equipment snapshot schema has no new staff-only zero fields")
	var cooldown: float = float(state.hero_skill_parameters()["cooldown"])
	_check(sim.try_hero_skill() and is_equal_approx(float(sim._hero_skill_clock["duration"]), cooldown) and is_equal_approx(sim.weapon_effects.haste_bonus(), 0.025), "Legacy Prometheus still grants next-cast haste after locking its first unchanged cooldown")
	var cap_id: String = "staff_cap_fixture"
	var previous: Variant = GameCatalog._weapon_index.get(cap_id)
	var capped: ContentDef = definition.duplicate(true) as ContentDef
	capped.id = cap_id
	capped.inventory_size = Vector2i.ONE
	capped.equipment_effects = [{"kind": "cast_party_skill_damage", "amount_by_rank": [3.0, 6.0, 12.0], "max_stacks": 4, "applies_to_current_cast": true}]
	GameCatalog._weapon_index[cap_id] = capped
	var cap_state: RunState = _state()
	var cap_uid: int = _buy(cap_state, cap_id)
	var cap_sim: CombatSim = _sim(cap_state)
	for index: int in 4:
		_check(_ready(cap_sim) and cap_sim.try_hero_skill() and _stacks(cap_sim, cap_uid) == index + 1 and is_equal_approx(cap_sim.weapon_effects.current_party_skill_damage(cap_sim), minf(8.0, float(index + 1) * 3.0)), "A real purchased high-rate fixture obeys both independent four-stack and global8.0 bounds")
	if previous == null:
		GameCatalog._weapon_index.erase(cap_id)
	else:
		GameCatalog._weapon_index[cap_id] = previous

func _test_zero_impact_fast_path_and_pending_healing() -> void:
	var state: RunState = _state()
	var staff: int = _buy(state, "staff_0001")
	var sim: CombatSim = _sim(state)
	var observed := ObservedHealingRuntime.new()
	observed.begin(state)
	sim.weapon_effects = observed
	var target: CombatSim.Enemy = _target(sim)
	var effects: Dictionary = observed.snapshot()
	sim.apply_damage(target, 10.0, "bone")
	_check(is_equal_approx(HEALTH - target.health, 10.0) and observed.healing_observations == 0 and observed.snapshot() == effects, "Staff-only impacts with no pending healing return the exact neutral multiplier without traversing healing observers")
	state.health = 50.0
	_check(state.heal(10.0) == 10.0 and state.healing_events == 1, "The pending-event fixture creates a real successful heal")
	sim.apply_damage(target, 10.0, "bone")
	_check(observed.healing_observations == 1 and int(observed._records[staff]["heal_seen"]) == 1 and is_equal_approx(HEALTH - target.health, 20.0), "A pending heal bypasses the fast return and updates the non-heal-damage Staff's publicly visible heal_seen exactly once")
	effects = observed.snapshot()
	sim.apply_damage(target, 10.0, "bone", true)
	_check(observed.healing_observations == 1 and observed.snapshot() == effects and is_equal_approx(HEALTH - target.health, 30.0), "After the real event is consumed, secondary hits use the same neutral fast path without mutating equipment state")
	state.heal(1.0)
	sim.apply_damage(target, 10.0, "unrecognized_fixture")
	_check(observed.healing_observations == 1 and int(observed._records[staff]["heal_seen"]) == 1, "An unknown source preserves the original rule that it cannot consume a pending player healing event")
	_check(observed.damage_multiplier(sim, "bone", null) == 1.0 and observed.healing_observations == 1 and int(observed._records[staff]["heal_seen"]) == 1, "A missing target does not consume deferred healing merely because its source is friendly")
	sim.complete = true
	_check(observed.damage_multiplier(sim, "bone", target) == 1.0 and observed.healing_observations == 1 and int(observed._records[staff]["heal_seen"]) == 1, "An invalid or completed simulation likewise leaves pending healing observations untouched")
	sim.complete = false
	sim.apply_damage(target, 10.0, "bone")
	_check(observed.healing_observations == 2 and int(observed._records[staff]["heal_seen"]) == 2, "The next valid player hit still consumes the previously deferred real event")

func _test_fast_path_preserves_legacy_rescue_and_damage() -> void:
	var state: RunState = _state()
	var staff: int = _buy(state, "staff_0001")
	var heim: int = _buy(state, "sword_0011")
	var sim: CombatSim = _sim(state)
	var observed := ObservedHealingRuntime.new()
	observed.begin(state)
	sim.weapon_effects = observed
	var target: CombatSim.Enemy = _target(sim)
	state.health = 80.0
	sim.invulnerability = 0.0
	sim._hurt_player(35.0, "tank", "contact")
	_check(is_equal_approx(state.health, 65.0) and state.healing_events == 1 and bool(observed._records[heim]["rescued"]) and int(observed._records[heim]["heal_stacks"]) == 1 and int(observed._records[staff]["heal_seen"]) == 1, "A real nonlethal hit retains Heimdall's rescue, one healing event and both equipped UID observations")
	var health: float = target.health
	sim.apply_damage(target, 10.0, "bone")
	_check(is_equal_approx(health - target.health, 10.3), "The nonzero legacy heal-damage bonus cannot be skipped by the impact fast return")
	state.heal(10.0)
	health = target.health
	sim.apply_damage(target, 10.0, "bone", true)
	_check(int(observed._records[heim]["heal_stacks"]) == 2 and int(observed._records[staff]["heal_seen"]) == 2 and is_equal_approx(health - target.health, 10.6), "A later heal between simulation steps is consumed before the next real secondary hit and raises its legacy bonus once")
	_check(state.sell_item(heim), "The legacy damage-granting UID can be sold while Staff remains")
	health = target.health
	var observations: int = observed.healing_observations
	sim.apply_damage(target, 10.0, "bone")
	_check(is_equal_approx(health - target.health, 10.0) and observed.healing_observations == observations, "An inventory refresh removes the sold impact bonus and immediately enables the neutral path without inventing a heal")
	var replacement: int = _buy(state, "sword_0011")
	sim.apply_damage(target, 10.0, "bone")
	_check(replacement != heim and int(observed._records[replacement]["heal_stacks"]) == 0 and not bool(observed._records[replacement]["rescued"]), "A new same-name legacy UID cannot inherit archived healing layers or rescue use")
	var ball_state: RunState = _state()
	_buy(ball_state, "staff_0001")
	_buy(ball_state, "spear_0005")
	var ball: CombatSim = _sim(ball_state)
	var ball_target: CombatSim.Enemy = _target(ball)
	ball._pinball_time_left = 1.0
	ball.apply_damage(ball_target, 10.0, "bone")
	_check(is_equal_approx(HEALTH - ball_target.health, 12.0), "A cached nonzero legacy ball-mode bonus prevents the neutral path even when no healing is pending")
