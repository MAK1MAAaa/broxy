extends SceneTree
## Real mid-wave feedback plus a drawing-pass spy, without profile access.

const SEED: int = 20261029
const STEP: float = 1.0 / 60.0
const FRAMES: int = 16
const CASES: PackedStringArray = ["blast", "hurt", "flash_off", "danger"]

class SilentSoundBank extends SoundBank:
	func _ready() -> void:
		pass

class PassSpy extends CombatWorld:
	var passes: Array[String] = []
	var number_ids: Array[int] = []
	func _draw_atmosphere() -> void:
		passes.append("atmosphere")
	func _draw_ground_contacts() -> void:
		passes.append("contacts")
	func _draw_souls() -> void:
		passes.append("souls")
	func _draw_enemies() -> void:
		passes.append("enemies")
	func _draw_friendly_shots() -> void:
		passes.append("friendly")
	func _draw_player_ground() -> void:
		passes.append("ground")
	func _draw_effects() -> void:
		passes.append("effects")
	func _draw_impact_feedback() -> void:
		passes.append("impact")
	func _draw_rune_feedback() -> void:
		passes.append("rune")
	func _draw_outgoing_feedback() -> void:
		passes.append("outgoing")
		super._draw_outgoing_feedback()
	func _draw_player() -> void:
		passes.append("player")
	func _draw_feedback() -> void:
		passes.append("incoming")
		super._draw_feedback()
	func _draw_number(number: FloatingNumber) -> void:
		passes.append("loss" if number.player_hit else "damage")
		number_ids.append(number.get_instance_id())
	func _draw_player_damage_direction() -> void:
		passes.append("direction")
	func _draw_danger() -> void:
		passes.append("danger")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for case_name: String in CASES:
		_test_real_passes(case_name)
	await _test_paused_world()
	print("PlayerForeground: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


static func make_state() -> RunState:
	var state := RunState.new()
	state.begin(SEED, "bone")
	state.wave = 6
	state.collect_souls(1200)
	for id: String in ["crescent", "comet", "return_ring"]:
		var definition: ContentDef = GameCatalog.weapon(id)
		state.offers = [{"kind": "weapon", "id": id, "price": state.shop_price(definition), "sold": false}]
		assert(state.buy_offer(0), "The fixture must buy each weapon through the formal transaction")
	for index: int in 4:
		var id: String = ["blast", "pierce", "bounce", "blast"][index]
		state.offers = [{"kind": "rune", "id": id, "price": state.shop_price(GameCatalog.rune(id)), "sold": false}]
		assert(state.buy_offer(0) and state.equip_rune(0, index), "The fixture must legally buy and equip each rune")
	return state


static func prepare(world, case_name: String) -> Dictionary:
	world.settings = {"shake": false, "flash": case_name != "flash_off"}
	world.begin(make_state())
	world.set_physics_process(false)
	var sim: CombatSim = world.sim
	sim.sandbox = true
	sim._cooldowns.fill(9999.0)
	sim.player_position = Vector2(640, 400)
	for offset: Vector2 in [Vector2(40, -45), Vector2(70, -20), Vector2(72, -60), Vector2(5, -65), Vector2(-30, -60), Vector2(-70, -15)]:
		sim.spawn_enemy("tank", sim.player_position + offset)
	for frame: int in FRAMES:
		world._advance_feedback(STEP)
		if frame == 8 and case_name in ["hurt", "flash_off"]:
			sim.spawn_enemy("chaser", sim.player_position + Vector2(12, 0))
		if frame == 0:
			var direction: Vector2 = Vector2(40, -45).normalized()
			for equipped: Dictionary in sim.run.loadout:
				sim.fire_weapon(str(equipped["id"]), str(equipped["rune"]["id"]), sim.player_position, direction)
		sim.step(STEP, Vector2.ZERO)
	if case_name == "danger":
		# Explicit layer fixture, not a naturally generated ritual or projectile.
		var warning := CombatSim.WarningZone.new()
		warning.position = sim.player_position + Vector2(0, -24)
		warning.radius = 42.0
		warning.age = 0.65
		sim.zones.append(warning)
		sim._hostile_shot(sim.player_position + Vector2(0, -24), Vector2.ZERO, 8.0, "caster")
	world._visual_time = 3.0 * PI / 70.0
	world.queue_redraw()
	var incoming: int = 0
	var outgoing: int = 0
	for number in world._numbers:
		incoming += 1 if number.player_hit else 0
		outgoing += 0 if number.player_hit else 1
	var passed: bool = sim.run.wave == 6 and sim.run.loadout.size() == 4 and sim.run.rune_bag.is_empty()
	passed = passed and not sim.complete and sim.primary_hits > 0 and sim.secondary_hits > 0 and outgoing > 0
	if case_name in ["hurt", "flash_off"]:
		passed = passed and sim.run.health < sim.run.stat("max_health") and incoming > 0 and sim.invulnerability > 0.0 and world._damage_flash > 0.0
	return {"passed": passed, "seed": SEED, "frames": FRAMES, "wave": sim.run.wave,
		"test_budget": 1200, "formal_purchases": true, "stress_mode": false,
		"primary_hits": sim.primary_hits, "secondary_hits": sim.secondary_hits,
		"incoming_numbers": incoming, "outgoing_numbers": outgoing,
		"damage_flash": world._damage_flash,
		"manual_danger_fixture": case_name == "danger"}


static func state_hash(world) -> String:
	var sim: CombatSim = world.sim
	var result: Array = [sim.rng.state, sim.run.rng.state, sim.run.summary(), sim.snapshot(), sim.invulnerability,
		sim.primary_hits, sim.secondary_hits, sim.damage_by_weapon, sim._shot_free.duplicate()]
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			result.append([shot.slot, shot.source, shot.rune, shot.hostile, shot.position, shot.previous,
				shot.velocity, shot.radius, shot.damage, shot.life, shot.remaining, shot.innate_remaining,
				shot.hit_ids.duplicate(), shot.return_after, shot.return_speed, shot.returning, shot.return_cancelled])
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			result.append([enemy.uid, enemy.definition.id, enemy.position, enemy.velocity, enemy.health,
				enemy.age, enemy.mode, enemy.action_timer, enemy.hurt_timer, enemy.slow_timer])
	for effect: CombatSim.Effect in sim.effects:
		result.append([effect.position, effect.radius, effect.color, effect.life, effect.total, effect.kind])
	for zone: CombatSim.WarningZone in sim.zones:
		result.append([zone.position, zone.radius, zone.age, zone.delay, zone.triggered])
	return JSON.stringify(result).sha256_text()


static func feedback_hash(world) -> String:
	var result: Array = [world._visual_time, world._damage_flash, world._damage_direction,
		world._number_free.size(), world._rune_free.size(), world._impact_painter.active_count()]
	for number in world._numbers:
		result.append([number.position, number.velocity, number.amount, number.text, number.text_width,
			number.source, number.target_uid, number.player_hit, number.color, number.life, number.total, number.font_size])
	for flash in world._rune_flashes:
		result.append([flash.kind, flash.origin, flash.incoming, flash.outgoing, flash.life])
	return JSON.stringify(result).sha256_text()


func _test_real_passes(case_name: String) -> void:
	var sound := SilentSoundBank.new()
	var world := PassSpy.new()
	world.sound = sound
	var record: Dictionary = prepare(world, case_name)
	_check(record["passed"], "The sixth-wave fixture legally equips four weapons and produces actual hits: " + case_name)
	var before: String = state_hash(world)
	var feedback: String = feedback_hash(world)
	var ordered: Array[int] = []
	for incoming: bool in [false, true]:
		for number in world._numbers:
			if number.player_hit == incoming:
				ordered.append(number.get_instance_id())
	for repeat: int in 3:
		world.passes.clear()
		world.number_ids.clear()
		world._draw()
		var passes: Array[String] = world.passes
		_check(passes.find("contacts") < passes.find("ground") and passes.find("ground") < passes.find("enemies")
			and passes.find("enemies") < passes.find("effects") and passes.find("effects") < passes.find("impact")
			and passes.find("impact") < passes.find("rune") and passes.find("rune") < passes.find("outgoing")
			and passes.find("outgoing") < passes.find("player") and passes.find("player") < passes.find("incoming")
			and passes.find("incoming") < passes.find("direction") and passes.back() == "danger",
			"Executed drawing passes preserve the player foreground and final threat priority")
		var numbers_in_passes: bool = true
		for index: int in passes.size():
			if passes[index] == "damage":
				numbers_in_passes = numbers_in_passes and index < passes.find("player")
			elif passes[index] == "loss":
				numbers_in_passes = numbers_in_passes and index > passes.find("player") and index < passes.find("danger")
		_check(numbers_in_passes and world.number_ids == ordered, "Each actual number is drawn exactly once, preserving relative order and incoming priority")
		_check(state_hash(world) == before and feedback_hash(world) == feedback, "Repeated draw passes are read-only for both RNGs, simulation, timers and feedback pools")
	_check(world._number_pool.size() == 48 and world._number_free.size() + world._numbers.size() == 48
		and world._rune_pool.size() == 32, "Foreground splitting retains the existing feedback object budgets")
	if case_name in ["hurt", "flash_off"]:
		_check(world._damage_flash > 0.0, "The real incoming direction receipt remains alive at the captured frame")
		var tint: Color = world._player_tint()
		_check(is_equal_approx(tint.a, 1.0 if case_name == "flash_off" else 0.25), "The original invulnerability minimum and flash-off opacity remain unchanged")
	world.free()
	sound.free()


func _test_paused_world() -> void:
	var sound := SilentSoundBank.new()
	root.add_child(sound)
	var world := CombatWorld.new()
	world.sound = sound
	root.add_child(world)
	var record: Dictionary = prepare(world, "hurt")
	_check(record["passed"], "The paused real world starts with outgoing and incoming feedback")
	var before: String = state_hash(world)
	var feedback: String = feedback_hash(world)
	paused = true
	world.set_physics_process(true)
	for frame: int in 4:
		world.queue_redraw()
		await process_frame
	_check(state_hash(world) == before and feedback_hash(world) == feedback, "Paused scene-tree redraws never advance combat, invulnerability, numbers or visual time")
	world.set_physics_process(false)
	paused = false
	world.queue_free()
	sound.queue_free()
	await process_frame
