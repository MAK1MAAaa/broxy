class_name CombatSim
extends RefCounted
## The shipped game and automated policies advance this exact fixed-step simulation.

signal shot_fired
signal enemy_hit
signal enemy_killed(position: Vector2, color: Color)
signal player_hurt
signal damage_dealt(position: Vector2, amount: float, source: String, secondary: bool, target_uid: int)
signal player_damaged(amount: float, source_id: String, kind: String, origin: Vector2)
signal rune_activated(rune_id: String, origin: Vector2, incoming_direction: Vector2, outgoing_direction: Vector2)
signal core_activated(core_id: String, origin: Vector2)
signal dash_started(origin: Vector2, direction: Vector2)
signal dash_evaded(position: Vector2, origin: Vector2, source_id: String, kind: String)
signal pulse_cast(origin: Vector2, affected: int)
signal active_skill_cast(skill_id: String, uid: int, origin: Vector2, direction: Vector2, affected: int, rank: int)
signal hero_skill_cast(hero_id: String, parameters: Dictionary, origin: Vector2, direction: Vector2, affected: int)
signal pinball_bounced(position: Vector2, normal: Vector2, boosted: bool, combo: int)
signal crate_hit(position: Vector2, broke: bool)
signal world_pickup_collected(kind: String, position: Vector2, value: float)
signal boss_weakpoint_hit(uid: int, cast_id: int, position: Vector2, broke: bool)
signal boss_interrupted(position: Vector2)
signal ended(victory: bool, reason: String)

const ARENA: Rect2 = ArenaCatalog.WORLD_BOUNDS
const SPAWN_MARGIN: float = 48.0
const SPAWN_INSET: float = 24.0
const ENEMY_DESPAWN_DISTANCE: float = 1800.0
const CELL: float = 80.0
const ENEMY_LIMIT: int = 340
const SHOT_LIMIT: int = 1600
const DROP_LIMIT: int = 420
const RUSHER_WINDUP: float = 0.65
const CASTER_WINDUP: float = 0.45
const PINBALL_LIFE: float = 1.1
const PINBALL_MAX_LIFE: float = 1.6
const PINBALL_SPEED: float = 650.0
const PINBALL_MAX_SPEED: float = 900.0
const PINBALL_DAMAGE: float = 28.0
const PINBALL_HIT_INTERVAL: float = 0.15
const PINBALL_BOUNCE_LIMIT: int = 12
const PINBALL_STEP_LIMIT: int = 8
const EXPLOSION_REGION_CACHE_LIMIT: int = 1024

class Enemy:
	var active: bool = false
	var slot: int = 0
	var uid: int = 0
	var definition: ContentDef
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var health: float = 0.0
	var max_health: float = 0.0
	var age: float = 0.0
	var action_timer: float = 0.0
	var slow_timer: float = 0.0
	var slow_factor: float = 1.0
	var pulse_hinder_timer: float = 0.0
	var hurt_timer: float = 0.0
	var charge_direction: Vector2 = Vector2.ZERO
	var mode: int = 0
	var radius: float = 16.0
	var hunter: bool = false
	var boss_ghost: bool = false
	var boss_cast_id: int = 0
	var damage_scale: float = 1.0
	var fire_vulnerability_left: float = 0.0
	var fire_vulnerability: float = 0.0
	var positive_conditions: Dictionary = {}
	var positive_attack: float = 0.0
	var positive_speed: float = 0.0
	var positive_defense: float = 0.0

class Shot:
	var active: bool = false
	var slot: int = 0
	var position: Vector2 = Vector2.ZERO
	var previous: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var damage: float = 0.0
	var radius: float = 4.0
	var life: float = 0.0
	var source: String = ""
	var attacker_id: String = ""
	var rune: String = ""
	var weapon_rank: int = 1
	var rune_rank: int = 1
	var resonance_bonus: float = 0.0
	var remaining: int = 0
	var innate_remaining: int = 0
	var return_after: float = 0.0
	var return_speed: float = 0.0
	var returning: bool = false
	var return_cancelled: bool = false
	var hit_ids: Dictionary = {}
	var weakpoint_hit_ids: Dictionary = {}
	var homing: float = 0.0
	var slow: float = 0.0
	var hostile: bool = false
	var low_health_priority: bool = false
	var color: Color = Color.WHITE

class Soul:
	var active: bool = false
	var slot: int = 0
	var position: Vector2 = Vector2.ZERO
	var value: int = 1
	var age: float = 0.0

class WarningZone:
	var shape: String = "circle"
	var direction: Vector2 = Vector2.RIGHT
	var length: float = 0.0
	var width: float = 0.0
	var source_cast_id: int = 0
	var duration: float = 0.3
	var source_id: String = "boss"
	var position: Vector2 = Vector2.ZERO
	var radius: float = 65.0
	var age: float = 0.0
	var delay: float = 1.2
	var damage: float = 16.0
	var triggered: bool = false

class Effect:
	var position: Vector2 = Vector2.ZERO
	var radius: float = 20.0
	var color: Color = Color.WHITE
	var life: float = 0.25
	var total: float = 0.25
	var kind: int = 0

var run: RunState
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var obstacles: ArenaObstacles = ArenaObstacles.new()
var player_position: Vector2 = ARENA.get_center()
var player_velocity: Vector2 = Vector2.ZERO
var player_direction: Vector2 = Vector2.RIGHT
var invulnerability: float = 0.0
var dash_time_left: float = 0.0
var dash_cooldown_left: float = 0.0
var dash_cooldown_total: float = DashRules.COOLDOWN
var dash_direction: Vector2 = Vector2.RIGHT
var dash_invulnerability_left: float = 0.0
var dashes_used: int = 0
var dash_evaded_current: bool = false
var dash_evades: int = 0
var pulse_cooldown_left: float = 0.0
var pulse_cooldown_total: float = PulseRules.COOLDOWN
var last_pulse_radius: float = PulseRules.RADIUS
var pulses_used: int = 0
var pulse_affected: int = 0
var last_pulse_affected: int = 0
var elapsed: float = 0.0
var duration: float = 45.0
var complete: bool = false
var victory: bool = false
var end_reason: String = ""
var enemies: Array[Enemy] = []
var shots: Array[Shot] = []
var souls: Array[Soul] = []
var zones: Array[WarningZone] = []
var effects: Array[Effect] = []
var enemy_count: int = 0
var shot_count: int = 0
var soul_count: int = 0
var boss: Enemy
var boss_encounter: BossEncounter = BossEncounter.new()
var boss_interrupts: int = 0
var weakpoints_broken: int = 0
var weakpoint_damage: float = 0.0
var primary_hits: int = 0
var secondary_hits: int = 0
var damage_by_weapon: Dictionary = {}
var damage_by_skill: Dictionary = {}
var skill_hits: int = 0
var _active_skill_clocks: Dictionary = {}
var _hero_skill_clock: Dictionary = {}
var hero_effects: HeroSkillRuntime = HeroSkillRuntime.new()
var skill_timeline: SkillTimelineRuntime = SkillTimelineRuntime.new()
var weapon_effects: WeaponEffectRuntime = WeaponEffectRuntime.new()
var interactions: ArenaInteractions = ArenaInteractions.new()
var _crate_indices: Dictionary = {}
var _pinball_time_left: float = 0.0
var _pinball_age: float = 0.0
var _pinball_velocity: Vector2 = Vector2.ZERO
var _pinball_bounces: int = 0
var _pinball_combo: int = 0
var _pinball_hits: Dictionary = {}
var _pinball_grid_active: bool = false
var _enemy_free: Array[int] = []
var _shot_free: Array[int] = []
var _soul_free: Array[int] = []
var _grid: Dictionary = {}
var _shot_region_candidates: Dictionary = {}
var _explosion_region_slots: Dictionary = {}
var _target_points: AStar2D = AStar2D.new()
var _largest_enemy_radius: float = 0.0
var _explosion_grid_active: bool = false
var _cooldowns: Array[float] = []
var _uid: int = 0
var _spawn_timer: float = 0.0
var _wave: ContentDef
var sandbox: bool = false
var core_activations: Dictionary = {"frostfire": 0, "bone_chorus": 0}
var _chorus_counts: Dictionary = {}
var _linked_weapons: Dictionary = {}
var _route: Dictionary = {}
var hunter: Enemy

func _init() -> void:
	for index: int in ENEMY_LIMIT:
		var enemy: Enemy = Enemy.new()
		enemy.slot = index
		enemies.append(enemy)
		_enemy_free.append(ENEMY_LIMIT - 1 - index)
	for index: int in SHOT_LIMIT:
		var shot: Shot = Shot.new()
		shot.slot = index
		shots.append(shot)
		_shot_free.append(SHOT_LIMIT - 1 - index)
	for index: int in DROP_LIMIT:
		var soul: Soul = Soul.new()
		soul.slot = index
		souls.append(soul)
		_soul_free.append(DROP_LIMIT - 1 - index)

func begin(state: RunState) -> void:
	run = state
	_explosion_region_slots.clear()
	boss_encounter.stop()
	boss_interrupts = 0
	weakpoints_broken = 0
	weakpoint_damage = 0.0
	obstacles.bounds = ArenaCatalog.play_bounds(run.arena_id)
	interactions.configure(ArenaCatalog.definition(run.arena_id), run.rng.seed, run.wave, obstacles)
	var walls_valid: bool = obstacles.configure_walls(ArenaCatalog.wall_geometry(run.arena_id))
	assert(walls_valid, "Authored terrain walls must be valid")
	_crate_indices.clear()
	for crate: Dictionary in interactions.snapshot()["crates"]:
		_crate_indices["crate:" + str(crate["id"])] = int(crate["index"])
	_pinball_time_left = 0.0
	_pinball_age = 0.0
	_pinball_velocity = Vector2.ZERO
	_pinball_bounces = 0
	_pinball_combo = 0
	_pinball_hits.clear()
	rng.seed = int(run.rng.randi())
	_wave = GameCatalog.wave(run.wave)
	duration = _wave.duration
	_chorus_counts.clear()
	_linked_weapons.clear()
	for uid: int in run.linked_weapon_uids():
		_linked_weapons[uid] = true
	_route = RogueRules.route(run.active_route) if not _wave.boss_wave and run.active_route != "balanced" else {}
	core_activations = {"frostfire": 0, "bone_chorus": 0}
	hunter = null
	player_position = obstacles.free_point(obstacles.bounds.get_center(), 16.0, 16.0)
	dash_time_left = 0.0
	dash_cooldown_left = 0.0
	dash_cooldown_total = _current_dash_cooldown()
	dash_direction = Vector2.RIGHT
	dash_invulnerability_left = 0.0
	dashes_used = 0
	dash_evaded_current = false
	dash_evades = 0
	pulse_cooldown_left = 0.0
	_active_skill_clocks.clear()
	_hero_skill_clock.clear()
	hero_effects.clear()
	skill_timeline.clear()
	weapon_effects.begin(run)
	damage_by_skill.clear()
	skill_hits = 0
	pulse_cooldown_total = _current_pulse_cooldown()
	last_pulse_radius = _current_pulse_radius()
	pulses_used = 0
	pulse_affected = 0
	last_pulse_affected = 0
	for enemy: Enemy in enemies:
		enemy.pulse_hinder_timer = 0.0
	_cooldowns.clear()
	for index: int in run.loadout.size():
		_cooldowns.append(float(index) * 0.14)
	if _wave.boss_wave:
		boss = spawn_enemy("boss", Vector2(640, 208))
		boss.action_timer = 2.5
		boss_encounter.begin(boss.position, 1.0)
	elif run.altar_choice == "accepted" and run.wave == run.altar_wave and not run.hunter_defeated:
		hunter = spawn_enemy("rusher")
		if hunter != null:
			hunter.hunter = true
			hunter.max_health *= RogueRules.HUNTER_HEALTH_FACTOR
			hunter.health = hunter.max_health
	_spawn_timer = 0.6

func step(delta: float, movement: Vector2, dash_pressed: bool = false, pulse_pressed: bool = false, skill_requests: Array[Dictionary] = [], hero_skill_pressed: bool = false) -> void:
	_explosion_grid_active = false
	_pinball_grid_active = false
	if complete or run == null or not is_finite(delta) or delta <= 0.0:
		return
	if run.health <= 0.0:
		_finish(false, _death_reason())
		return
	elapsed += delta
	run.elapsed += delta
	invulnerability = maxf(0.0, invulnerability - delta)
	hero_effects.advance_timers(delta)
	weapon_effects.advance(self, delta)
	interactions.advance(delta)
	_advance_boss_encounter(delta)
	if _has_movement_direction(movement):
		player_direction = movement.normalized()
	_update_pulse(delta, pulse_pressed, skill_requests)
	if not complete:
		if hero_skill_pressed:
			try_hero_skill()
		if not _hero_skill_clock.is_empty():
			_hero_skill_clock["remaining"] = _skill_timer_after(float(_hero_skill_clock["remaining"]), delta)
	if complete:
		return
	if _pinball_time_left > 0.0 or dash_pressed:
		_rebuild_grid()
		_pinball_grid_active = true
	_move_player(delta, movement, dash_pressed)
	_pinball_grid_active = false
	if complete:
		return
	_update_enemies(delta)
	if run.health <= 0.0:
		_finish(false, _death_reason())
		return
	_rebuild_grid()
	_explosion_grid_active = true
	_update_weapons(delta)
	_update_shots(delta)
	if not complete:
		_advance_hero_bombs(delta)
	if not complete:
		_advance_skill_timeline(delta)
	_explosion_grid_active = false
	if complete:
		return
	_dispatch_boss_events(boss_encounter.finish_friendly_step())
	_update_souls(delta)
	_collect_world_pickups()
	_update_zones(delta)
	if complete:
		return
	_update_effects(delta)
	if complete:
		return
	if run.health <= 0.0:
		_finish(false, _death_reason())
		return
	if not sandbox:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_wave_group()
			_spawn_timer += _wave.spawn_interval * float(_route.get("interval_factor", 1.0))
		if elapsed >= duration:
			if _wave.boss_wave:
				_finish(false, "仪式已经完成。请在 90 秒内击败%s。" % GameCatalog.enemy("boss").display_name)
			else:
				collect_remaining_souls()
				_finish(true, "邪潮暂歇")

func _move_player(delta: float, movement: Vector2, dash_pressed: bool) -> void:
	var advances_time: bool = is_finite(delta) and delta > 0.0
	if advances_time:
		if dash_pressed:
			_try_start_dash(movement)
		dash_cooldown_left = _skill_timer_after(dash_cooldown_left, delta)
		dash_invulnerability_left = _skill_timer_after(dash_invulnerability_left, delta)
	var movement_delta: float = delta
	if advances_time and _pinball_time_left > 0.0:
		dash_time_left = _skill_timer_after(dash_time_left, delta)
		var consumed: float = _move_pinball(delta, movement)
		if complete or _pinball_time_left > 0.0:
			return
		dash_time_left = 0.0
		movement_delta = maxf(0.0, delta - consumed)
		if movement_delta <= 0.0:
			return
	if advances_time and dash_time_left > 0.0:
		var dash_delta: float = minf(delta, dash_time_left)
		player_velocity = dash_direction * DashRules.SPEED
		var impact: Dictionary = obstacles.first_hit(player_position, player_velocity * dash_delta, 16.0, 16.0)
		var source_wall: bool = ArenaCatalog.ORIGINAL_STAGE_IDS.has(run.arena_id) and str(impact.get("id", "")).begins_with("wall:")
		if not impact.is_empty() and (str(impact.get("art_id", "")) == "bumper" or source_wall):
			var used: float = dash_delta * clampf(float(impact["t"]), 0.0, 1.0)
			var normal: Vector2 = impact["normal"]
			player_position += player_velocity * used + normal * 0.1
			dash_time_left = _skill_timer_after(dash_time_left, delta)
			_begin_pinball(player_velocity, normal)
			var consumed: float = _move_pinball(delta - used, movement)
			if not complete and _pinball_time_left <= 0.0:
				dash_time_left = 0.0
				_move_ground(maxf(0.0, delta - used - consumed), movement)
			return
		player_position = obstacles.move_body(player_position, player_velocity * dash_delta, 16.0, 16.0)
		player_direction = dash_direction
		dash_time_left = _skill_timer_after(dash_time_left, dash_delta)
		movement_delta = delta - dash_delta
		if movement_delta <= 0.0:
			return
	_move_ground(movement_delta, movement)

func _move_ground(delta: float, movement: Vector2) -> void:
	player_velocity = movement.limit_length() * run.stat("move_speed")
	player_velocity *= ArenaCatalog.movement_multiplier(run.arena_id, player_position)
	player_position = obstacles.move_body(player_position, player_velocity * delta, 16.0, 16.0)
	if _has_movement_direction(movement):
		player_direction = movement.normalized()

func _begin_pinball(velocity: Vector2, normal: Vector2) -> void:
	_pinball_time_left = PINBALL_LIFE
	_pinball_age = 0.0
	_pinball_bounces = 1
	_pinball_combo = 0
	_pinball_hits.clear()
	_pinball_velocity = velocity.bounce(normal).normalized() * PINBALL_SPEED
	player_velocity = _pinball_velocity
	player_direction = _pinball_velocity.normalized()
	pinball_bounced.emit(player_position, normal, true, _pinball_combo)

func pinball_snapshot() -> Dictionary:
	return {"active": _pinball_time_left > 0.0 and not complete, "remaining": _pinball_time_left,
		"velocity": _pinball_velocity, "bounces": _pinball_bounces, "combo": _pinball_combo, "age": _pinball_age}

func _pinball_first_hit(start: Vector2, movement: Vector2) -> Dictionary:
	var result: Dictionary = obstacles.first_hit(start, movement, 16.0, 16.0)
	var nearest: float = float(result.get("t", INF))
	for enemy: Enemy in _pinball_candidates(start, start + movement):
		if not enemy.active or enemy.health <= 0.0 or not enemy.position.is_finite():
			continue
		var offset: Vector2 = start - enemy.position
		var radius: float = 16.0 + enemy.radius
		if offset.length_squared() <= radius * radius and offset.dot(movement) >= 0.0:
			continue
		var fraction: float = _swept_circle_entry_t(start, start + movement, enemy.position, radius)
		var current: Enemy = result.get("enemy")
		if fraction < nearest or (is_finite(fraction) and fraction == nearest and current != null and enemy.uid < current.uid):
			var normal: Vector2 = (start + movement * fraction - enemy.position).normalized()
			if normal.is_zero_approx():
				normal = -movement.normalized()
			nearest = fraction
			result = {"t": fraction, "normal": normal, "enemy": enemy,
				"penetration": maxf(0.0, radius - offset.length())}
	var weak: Dictionary = _weakpoint_first_hit(start, start + movement, 16.0, {}, true)
	if not weak.is_empty() and float(weak["t"]) < nearest:
		var point: Dictionary = weak["point"]
		var offset: Vector2 = start - (point["position"] as Vector2)
		if offset.length_squared() > pow(16.0 + float(point["radius"]), 2) or offset.dot(movement) < 0.0:
			var normal: Vector2 = (start + movement * float(weak["t"]) - (point["position"] as Vector2)).normalized()
			result = {"t": weak["t"], "normal": normal if not normal.is_zero_approx() else -movement.normalized(),
				"weakpoint": point, "id": "weakpoint:" + str(weak["key"]),
				"penetration": maxf(0.0, 16.0 + float(point["radius"]) - offset.length())}
	return result

func _pinball_candidates(start: Vector2, end: Vector2) -> Array[Enemy]:
	if not _pinball_grid_active:
		return enemies
	var result: Array[Enemy] = []
	var padding: Vector2 = Vector2.ONE * (16.0 + _largest_enemy_radius)
	var first := Vector2i(((start.min(end) - padding) / CELL).floor())
	var last := Vector2i(((start.max(end) + padding) / CELL).floor())
	for x: int in range(first.x, last.x + 1):
		for y: int in range(first.y, last.y + 1):
			var bucket: Array = _grid.get(Vector2i(x, y), [])
			for enemy: Enemy in bucket:
				result.append(enemy)
	return result

func _move_pinball(delta: float, movement: Vector2) -> float:
	if delta <= 0.0 or not is_finite(delta):
		return 0.0
	var duration: float = minf(delta, _pinball_time_left)
	_pinball_age += duration
	_pinball_time_left = _skill_timer_after(_pinball_time_left, duration)
	if _has_movement_direction(movement):
		var steering: float = clampf(_pinball_velocity.angle_to(movement), -2.4 * duration, 2.4 * duration)
		_pinball_velocity = _pinball_velocity.rotated(steering)
	var remaining: float = duration
	for iteration: int in PINBALL_STEP_LIMIT:
		if remaining <= 0.000001 or complete:
			break
		var travel: Vector2 = _pinball_velocity * remaining
		var impact: Dictionary = _pinball_first_hit(player_position, travel)
		if impact.is_empty():
			player_position += travel
			remaining = 0.0
			break
		var fraction: float = clampf(float(impact["t"]), 0.0, 1.0)
		var normal: Vector2 = impact["normal"]
		player_position += travel * fraction
		var enemy: Enemy = impact.get("enemy")
		var collider_id: String = str(impact.get("id", ""))
		var boosted: bool = str(impact.get("art_id", "")) == "bumper"
		var target_id: String = "enemy:%d" % enemy.uid if enemy != null else collider_id
		if elapsed - float(_pinball_hits.get(target_id, -INF)) >= PINBALL_HIT_INTERVAL:
			var damage: float = PINBALL_DAMAGE * run.stat("damage") * (1.0 + minf(float(_pinball_combo), 5.0) * 0.1)
			if enemy != null:
				var before: float = enemy.health
				apply_damage(enemy, damage, "skill:pinball")
				if enemy.health < before:
					_pinball_combo += 1
			elif impact.has("weakpoint"):
				_pinball_combo += int(bool(_damage_boss_weakpoint(impact["weakpoint"], damage).get("hit", false)))
			elif _crate_indices.has(collider_id):
				var outcome: Dictionary = _damage_crate(int(_crate_indices[collider_id]), damage)
				_pinball_combo += int(bool(outcome.get("broke", false)))
			_pinball_hits[target_id] = elapsed
		_pinball_bounces += 1
		_pinball_velocity = _pinball_velocity.bounce(normal)
		if boosted:
			_pinball_velocity = _pinball_velocity.normalized() * minf(PINBALL_MAX_SPEED, _pinball_velocity.length() * 1.15)
			_pinball_time_left = minf(maxf(0.0, PINBALL_MAX_LIFE - _pinball_age), _pinball_time_left + 0.15)
		player_position += normal * (0.1 + float(impact.get("penetration", 0.0)))
		pinball_bounced.emit(player_position, normal, boosted, _pinball_combo)
		remaining *= 1.0 - fraction
		if _pinball_bounces >= PINBALL_BOUNCE_LIMIT:
			_pinball_time_left = 0.0
			break
	player_position = obstacles.free_point(player_position, 16.0, 16.0)
	player_velocity = _pinball_velocity
	if not _pinball_velocity.is_zero_approx():
		player_direction = _pinball_velocity.normalized()
	if _pinball_time_left <= 0.0:
		_pinball_velocity = Vector2.ZERO
	if _pinball_bounces >= PINBALL_BOUNCE_LIMIT or complete:
		_pinball_age -= remaining
		return duration - remaining
	return duration

func _damage_crate(index: int, amount: float) -> Dictionary:
	var result: Dictionary = interactions.damage_crate(index, amount)
	if bool(result.get("hit", false)):
		crate_hit.emit(result["position"], bool(result.get("broke", false)))
	return result

func _collect_world_pickups() -> void:
	for pickup: Dictionary in interactions.pickup_candidates(player_position, run.stat("pickup_radius")):
		var kind: String = str(pickup["kind"])
		var value: float = float(pickup["value"])
		var actual: float = 0.0
		match kind:
			"gold":
				actual = float(maxi(0, int(value)))
				run.gold += int(actual)
			"health":
				actual = maxf(0.0, minf(value, run.stat("max_health") - run.health))
			"charge": actual = _charge_owned_skills(value)
		if actual <= 0.0:
			continue
		if interactions.consume_pickup(int(pickup["uid"])):
			if kind == "health":
				actual = run.heal(actual)
				weapon_effects.observe_health(self)
			else:
				run.changed.emit()
			world_pickup_collected.emit(kind, pickup["position"], actual)

func _charge_owned_skills(seconds: float) -> float:
	var actual: float = 0.0
	if not is_finite(seconds) or seconds <= 0.0:
		return actual
	for item: Dictionary in run.active_skills:
		var clock: Dictionary = _active_skill_clocks.get(int(item["uid"]), {})
		if clock.is_empty():
			continue
		var before: float = float(clock["remaining"])
		clock["remaining"] = _skill_timer_after(before, seconds)
		actual = maxf(actual, before - float(clock["remaining"]))
	if not _hero_skill_clock.is_empty():
		var before: float = float(_hero_skill_clock["remaining"])
		_hero_skill_clock["remaining"] = _skill_timer_after(before, seconds)
		actual = maxf(actual, before - float(_hero_skill_clock["remaining"]))
	_sync_legacy_pulse_clock()
	return actual

static func _has_movement_direction(movement: Vector2) -> bool:
	return movement.is_finite() and movement.length_squared() > 0.0

func _try_start_dash(movement: Vector2) -> void:
	if complete or run == null or run.health <= 0.0 or dash_time_left > 0.0 or dash_cooldown_left > 0.0 or not movement.is_finite():
		return
	var direction: Vector2 = movement.normalized() if _has_movement_direction(movement) else player_direction
	if not direction.is_finite() or direction.length_squared() <= 0.01:
		direction = Vector2.RIGHT
	dash_direction = direction.normalized()
	dash_time_left = DashRules.DURATION
	dash_cooldown_total = _current_dash_cooldown()
	dash_cooldown_left = dash_cooldown_total
	dash_invulnerability_left = DashRules.INVULNERABILITY
	dashes_used += 1
	dash_evaded_current = false
	dash_started.emit(player_position, dash_direction)

static func _skill_timer_after(remaining: float, delta: float) -> float:
	var result: float = maxf(0.0, remaining - delta)
	return 0.0 if result < 0.0000001 else result

func _current_dash_cooldown() -> float:
	return DashRules.clamp_cooldown(run.stat("dash_cooldown")) if run != null else DashRules.COOLDOWN

func _current_pulse_cooldown() -> float:
	var slot: int = _pulse_slot()
	return float(run.active_skill_parameters(_skill_item(slot))["cooldown"]) if slot >= 0 else PulseRules.COOLDOWN

func _current_pulse_radius() -> float:
	var slot: int = _pulse_slot()
	return float(run.active_skill_parameters(_skill_item(slot))["radius"]) if slot >= 0 else PulseRules.RADIUS

func dash_snapshot() -> Dictionary:
	return {
		"ready": not complete and run != null and run.health > 0.0 and dash_time_left <= 0.0 and dash_cooldown_left <= 0.0,
		"active": dash_time_left > 0.0,
		"remaining": dash_time_left,
		"cooldown_left": dash_cooldown_left,
		"cooldown_total": dash_cooldown_total if dash_cooldown_left > 0.0 or dash_time_left > 0.0 else _current_dash_cooldown(),
		"next_cooldown_total": _current_dash_cooldown(),
		"direction": dash_direction,
		"uses": dashes_used,
		"evaded": dash_evaded_current,
		"evades": dash_evades,
	}

func _update_pulse(delta: float, pulse_pressed: bool, skill_requests: Array[Dictionary] = []) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if pulse_pressed:
		try_pulse()
	for request: Dictionary in skill_requests:
		if not request.has("slot") or not request.has("uid") or int(request["uid"]) < 0:
			continue
		try_active_skill(int(request["slot"]), int(request["uid"]))
	for uid: int in _active_skill_clocks:
		var clock: Dictionary = _active_skill_clocks[uid]
		clock["remaining"] = _skill_timer_after(float(clock["remaining"]), delta)
	_sync_legacy_pulse_clock()

func _try_cast_pulse() -> void:
	try_pulse()

func try_pulse() -> bool:
	var slot: int = _pulse_slot()
	return try_active_skill(slot) if slot >= 0 else false

func _pulse_slot() -> int:
	if run != null:
		for slot: int in mini(ActiveSkillRules.LIMIT, run.active_skills.size()):
			var item: Dictionary = _skill_item(slot)
			if not item.is_empty() and item.get("id", "") == "pulse":
				return slot
	return -1

func _skill_item(slot: int) -> Dictionary:
	if run == null or slot < 0 or slot >= mini(ActiveSkillRules.LIMIT, run.active_skills.size()):
		return {}
	var projected: Dictionary = run.active_skills[slot]
	var owned: Dictionary = run.backpack_item(int(projected.get("uid", -1)))
	if owned.is_empty() or owned.get("kind", "") != "skill" or owned.get("id", "") != projected.get("id", ""):
		return {}
	return owned

func try_active_skill(slot: int, expected_uid: int = -1) -> bool:
	var item: Dictionary = _skill_item(slot)
	if item.is_empty() or (expected_uid >= 0 and int(item["uid"]) != expected_uid):
		return false
	if complete or run.health <= 0.0 or not player_position.is_finite():
		return false
	var uid: int = int(item["uid"])
	var clock: Dictionary = _active_skill_clocks.get(uid, {})
	if float(clock.get("remaining", 0.0)) > 0.0:
		return false
	var parameters: Dictionary = run.active_skill_parameters(item).duplicate(true)
	if parameters.is_empty():
		return false
	parameters["damage"] = float(parameters.get("damage", 0.0)) * hero_effects.attack_multiplier()
	parameters["damage"] *= hero_effects.skill_multiplier(str(parameters.get("element", "")))
	var direction: Vector2 = _skill_direction()
	var origin: Vector2 = _starfall_origin(direction) if item["id"] == "starfall" else player_position
	_active_skill_clocks[uid] = {"remaining": parameters["cooldown"], "duration": parameters["cooldown"],
		"uses": int(clock.get("uses", 0)) + 1, "parameters": parameters}
	var affected: int = 0
	if item["id"] == "pulse":
		affected = _cast_pulse(origin, direction, parameters)
	else:
		affected = _cast_damage_skill(origin, direction, parameters)
	_sync_legacy_pulse_clock()
	active_skill_cast.emit(str(item["id"]), uid, origin, direction, affected, int(parameters["rank"]))
	return true

func _skill_direction() -> Vector2:
	return player_direction.normalized() if player_direction.is_finite() and player_direction.length_squared() > 0.0 else Vector2.RIGHT

func try_hero_skill(expected_hero: String = "") -> bool:
	if run == null or complete or run.health <= 0.0 or not player_position.is_finite():
		return false
	if not expected_hero.is_empty() and run.hero_id != expected_hero:
		return false
	if float(_hero_skill_clock.get("remaining", 0.0)) > 0.0:
		return false
	var parameters: Dictionary = _next_hero_skill_parameters()
	if parameters.is_empty():
		return false
	var direction: Vector2 = _skill_direction()
	var origin: Vector2 = player_position
	if parameters.get("origin_mode", "player") == "nearest":
		origin = _nearest_skill_origin(direction, float(parameters.get("target_range", 400.0)))
	elif parameters.get("origin_mode", "player") == "forward":
		origin = _clamp_skill_origin(player_position + direction * float(parameters.get("forward_distance", 160.0)))
	if parameters.get("delivery", "instant") == "bombs":
		if not hero_effects.can_spawn_parameters(parameters, origin, direction):
			return false
		var count: int = int(parameters.get("projectiles", 5))
		var impacts: Array[SkillTimelineRuntime.Area] = skill_timeline.reserve_impacts(parameters, origin, direction, count)
		if impacts.size() != count:
			return false
		if not hero_effects.spawn_bombs(parameters, origin, direction, impacts):
			skill_timeline.cancel(impacts)
			return false
	if parameters.get("delivery", "instant") == "areas" and not skill_timeline.enqueue(parameters, origin, direction):
		return false
	hero_effects.set_attack_buff(float(parameters.get("attack_bonus", 0.0)), float(parameters.get("buff_seconds", 0.0)))
	hero_effects.set_skill_buff(float(parameters.get("skill_bonus", 0.0)), float(parameters.get("skill_buff_seconds", 0.0)), str(parameters.get("buff_element", "")))
	_hero_skill_clock = {"hero_id": run.hero_id, "remaining": parameters["cooldown"], "duration": parameters["cooldown"],
		"uses": int(_hero_skill_clock.get("uses", 0)) + 1, "parameters": parameters}
	var affected: int = _cast_hero_delivery(origin, direction, parameters)
	weapon_effects.on_hero_cast(self)
	hero_skill_cast.emit(run.hero_id, parameters.duplicate(true), origin, direction, affected)
	return true

func _next_hero_skill_parameters() -> Dictionary:
	var parameters: Dictionary = run.hero_skill_parameters().duplicate(true)
	if parameters.is_empty():
		return {}
	var static_haste: float = run.stat("skill_haste")
	parameters["cooldown"] = float(parameters["cooldown"]) * (1.0 + static_haste) / (1.0 + static_haste + weapon_effects.haste_bonus())
	var attack: float = hero_effects.attack_multiplier()
	if float(parameters.get("attack_bonus", 0.0)) > 0.0:
		attack = maxf(attack, 1.0 + float(parameters["attack_bonus"]))
	var skill_power: float = hero_effects.skill_multiplier(str(parameters.get("element", "")))
	if parameters.get("element", "") == parameters.get("buff_element", ""):
		skill_power = maxf(skill_power, 1.0 + float(parameters.get("skill_bonus", 0.0)))
	parameters["damage"] = float(parameters.get("damage", 0.0)) * attack * skill_power
	if float(parameters.get("combo_per_hit", 0.0)) > 0.0:
		var combo_bonus: float = minf(float(parameters.get("combo_bonus_cap", 0.5)), float(_pinball_combo) * float(parameters.get("combo_per_hit", 0.005)))
		parameters["damage"] *= 1.0 + maxf(0.0, combo_bonus)
		parameters["combo"] = _pinball_combo
		parameters["combo_bonus"] = combo_bonus
	return parameters

func hero_skill_snapshot() -> Dictionary:
	if run == null:
		return {"available": false, "ready": false}
	var next_parameters: Dictionary = _next_hero_skill_parameters()
	var remaining: float = float(_hero_skill_clock.get("remaining", 0.0))
	var parameters: Dictionary = _hero_skill_clock.get("parameters", next_parameters) if remaining > 0.0 else next_parameters
	var result: Dictionary = parameters.duplicate(true)
	result.merge({"hero_id": run.hero_id, "available": not parameters.is_empty(), "ready": not complete and run.health > 0.0 and remaining <= 0.0,
		"cooldown_remaining": remaining, "cooldown_duration": float(_hero_skill_clock.get("duration", parameters.get("cooldown", 0.0))) if remaining > 0.0 else float(parameters.get("cooldown", 0.0)),
		"uses": int(_hero_skill_clock.get("uses", 0)), "skill_name": str(parameters.get("name", ""))}, true)
	return result

func hero_effects_snapshot() -> Dictionary:
	var value: Dictionary = hero_effects.snapshot()
	value["timeline"] = skill_timeline.snapshot()
	return value

func clear_hero_effects() -> void:
	hero_effects.clear()
	skill_timeline.clear()
	for enemy: Enemy in enemies:
		enemy.fire_vulnerability_left = 0.0
		enemy.fire_vulnerability = 0.0

func _cast_hero_delivery(origin: Vector2, direction: Vector2, parameters: Dictionary) -> int:
	if parameters.get("delivery", "instant") in ["bombs", "areas"]:
		return 0
	var hits: int = clampi(int(parameters.get("hits", 1)), 1, 12)
	var part: Dictionary = parameters.duplicate(true)
	part["damage"] = float(parameters["damage"]) / float(hits)
	var affected: int = 0
	for hit: int in hits:
		if complete:
			break
		affected = maxi(affected, _cast_damage_skill(origin, direction, part))
	if not complete:
		var vulnerability: float = float(parameters.get("fire_vulnerability", 0.0))
		if vulnerability > 0.0:
			for enemy: Enemy in enemies:
				if enemy.active and enemy.health > 0.0 and skill_contains(parameters, origin, direction, enemy.position):
					enemy.fire_vulnerability = clampf(vulnerability, 0.0, 1.0)
					enemy.fire_vulnerability_left = clampf(float(parameters.get("vulnerability_seconds", 4.0)), 0.0, 30.0)
		hero_effects.set_attack_buff(float(parameters.get("attack_bonus", 0.0)), float(parameters.get("buff_seconds", 0.0)))
	return affected

func _advance_hero_bombs(delta: float) -> void:
	for bomb: HeroSkillRuntime.Bomb in hero_effects.bombs:
		if complete:
			return
		if not bomb.active:
			continue
		var travel_delta: float = delta
		if bomb.delay > 0.0:
			bomb.position = player_position + bomb.velocity.normalized() * 18.0
			bomb.previous = bomb.position
			travel_delta = maxf(0.0, delta - bomb.delay)
			bomb.delay = maxf(0.0, bomb.delay - delta)
			if bomb.delay > 0.0000001:
				continue
			bomb.delay = 0.0
		var travel_time: float = minf(travel_delta, bomb.life)
		bomb.previous = bomb.position
		var destination: Vector2 = bomb.position + bomb.velocity * travel_time
		var obstacle: Dictionary = obstacles.first_hit(bomb.position, destination - bomb.position, bomb.collision_radius)
		var nearest: float = float(obstacle.get("t", INF))
		var low: Vector2 = bomb.position.min(destination) - Vector2.ONE * (bomb.collision_radius + _largest_enemy_radius)
		var high: Vector2 = bomb.position.max(destination) + Vector2.ONE * (bomb.collision_radius + _largest_enemy_radius)
		for enemy: Enemy in _shot_candidates(Vector2i((low / CELL).floor()), Vector2i((high / CELL).floor())):
			if enemy.active and enemy.health > 0.0:
				nearest = minf(nearest, _swept_circle_entry_t(bomb.position, destination, enemy.position, bomb.collision_radius + enemy.radius))
		var point: Dictionary = _weakpoint_first_hit(bomb.position, destination, bomb.collision_radius, {})
		if not point.is_empty():
			nearest = minf(nearest, float(point["t"]))
		bomb.position = bomb.position.lerp(destination, nearest) if is_finite(nearest) else destination
		bomb.life = maxf(0.0, bomb.life - travel_delta)
		if is_finite(nearest) or bomb.life <= 0.0:
			var blast: Dictionary = {"id": bomb.source, "shape": "circle", "radius": bomb.blast_radius,
				"damage": bomb.damage, "element": bomb.element}
			var offset: float = delta - travel_delta + travel_time * (nearest if is_finite(nearest) else 1.0)
			hero_effects.detonate(bomb, maxf(0.0, delta - offset))
			if bomb.impact_area != null:
				skill_timeline.activate_impact(bomb.impact_area, bomb.position, offset)
				bomb.impact_area = null
			else:
				_cast_damage_skill(bomb.position, bomb.velocity.normalized(), blast)

func _advance_skill_timeline(delta: float) -> void:
	skill_timeline.advance(delta, player_position)
	var weakness_expiries: Dictionary = {}
	for area: SkillTimelineRuntime.Area in skill_timeline.areas:
		if complete:
			return
		if not skill_timeline.can_contact(area):
			continue
		var area_serial: int = area.serial
		var parameters: Dictionary = area.parameters
		var damage: float = float(parameters.get("damage", 0.0))
		var source: String = "skill:" + str(parameters["id"])
		var element: String = str(parameters.get("element", ""))
		var weakness: float = clampf(float(parameters.get("fire_vulnerability", 0.0)), 0.0, 1.0)
		var weakness_seconds: float = clampf(float(parameters.get("vulnerability_seconds", 0.0)), 0.0, 30.0)
		for enemy: Enemy in enemies:
			if complete or not area.occupied or area.serial != area_serial:
				break
			if not enemy.active or enemy.health <= 0.0:
				continue
			var target_uid: int = enemy.uid
			var key: String = "enemy:%d" % target_uid
			if not skill_contains(parameters, area.origin, area.direction, enemy.position):
				skill_timeline.separate(area, key)
				continue
			var hits: int = skill_timeline.claim_hits(area, key)
			if hits > 0 and area.purpose == "dispel":
				dispel_enemy_condition(enemy)
				continue
			var next_contact: float = float(area.next_contacts.get(key, 0.0))
			for index: int in hits:
				if complete or not area.occupied or area.serial != area_serial or not enemy.active or enemy.uid != target_uid:
					break
				var contact_time: float = elapsed - area.age + next_contact - float(hits - index) * area.interval
				apply_damage(enemy, damage, source, false, 0.0, element)
				if not complete and enemy.active and enemy.uid == target_uid and area.occupied and area.serial == area_serial and weakness > 0.0:
					enemy.fire_vulnerability = weakness
					enemy.fire_vulnerability_left = weakness_seconds
					weakness_expiries[target_uid] = {"enemy": enemy, "expiry": contact_time + weakness_seconds}
		if complete or not area.occupied or area.serial != area_serial or area.purpose != "damage":
			continue
		for point: Dictionary in boss_weakpoints():
			if complete or not area.occupied or area.serial != area_serial:
				break
			var key: String = "point:%d:%d" % [boss_encounter.snapshot()["cast_id"], point["uid"]]
			if skill_contains(parameters, area.origin, area.direction, point["position"]):
				for hit: int in skill_timeline.claim_hits(area, key):
					if complete or not area.occupied or area.serial != area_serial:
						break
					_damage_boss_weakpoint(point, damage)
			else:
				skill_timeline.separate(area, key)
		if complete or not area.occupied or area.serial != area_serial:
			continue
		var reach: float = float(parameters.get("radius", 0.0)) + float(parameters.get("width", 0.0)) * 0.5
		for crate: Dictionary in interactions.damage_candidates(area.origin, reach):
			if complete or not area.occupied or area.serial != area_serial:
				break
			var key: String = "crate:%d" % crate["index"]
			if skill_contains(parameters, area.origin, area.direction, crate["position"]):
				for hit: int in skill_timeline.claim_hits(area, key):
					if complete or not area.occupied or area.serial != area_serial:
						break
					_damage_crate(int(crate["index"]), damage)
			else:
				skill_timeline.separate(area, key)
	for target_uid: int in weakness_expiries:
		var entry: Dictionary = weakness_expiries[target_uid]
		var target: Enemy = entry["enemy"]
		if target.active and target.uid == target_uid and target.fire_vulnerability_left > 0.0:
			target.fire_vulnerability_left = _skill_timer_after(float(entry["expiry"]), elapsed)
			if target.fire_vulnerability_left <= 0.0:
				target.fire_vulnerability = 0.0
	skill_timeline.finish_step()

func _clamp_skill_origin(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, obstacles.bounds.position.x, obstacles.bounds.end.x), clampf(point.y, obstacles.bounds.position.y, obstacles.bounds.end.y))

func _starfall_origin(direction: Vector2) -> Vector2:
	return _nearest_skill_origin(direction, 320.0)

func _nearest_skill_origin(direction: Vector2, target_range: float) -> Vector2:
	var point: Dictionary = _nearest_weakpoint(player_position, target_range)
	if not point.is_empty():
		return point["position"]
	var closest: Enemy
	var distance_squared: float = target_range * target_range
	for enemy: Enemy in enemies:
		if not enemy.active or enemy.health <= 0.0 or not enemy.position.is_finite():
			continue
		var candidate: float = enemy.position.distance_squared_to(player_position)
		if candidate <= distance_squared and (closest == null or candidate < distance_squared):
			closest = enemy
			distance_squared = candidate
	return closest.position if closest != null else _clamp_skill_origin(player_position + direction * 140.0)

func _cast_pulse(origin: Vector2, fallback: Vector2, parameters: Dictionary) -> int:
	last_pulse_radius = float(parameters["radius"])
	pulse_cooldown_total = float(parameters["cooldown"])
	last_pulse_affected = 0
	for enemy: Enemy in enemies:
		if not enemy.active or not (enemy.health > 0.0) or enemy.hunter or enemy.definition.id == "boss":
			continue
		var offset: Vector2 = enemy.position - origin
		if not offset.is_finite() or offset.length_squared() > last_pulse_radius * last_pulse_radius:
			continue
		var direction: Vector2 = offset.normalized() if offset.length_squared() > 0.0 else fallback
		enemy.position = obstacles.move_body(enemy.position, direction * float(parameters["push_distance"]), enemy.radius)
		enemy.pulse_hinder_timer = float(parameters["hinder_seconds"])
		last_pulse_affected += 1
	pulses_used += 1
	pulse_affected += last_pulse_affected
	pulse_cast.emit(origin, last_pulse_affected)
	return last_pulse_affected

func _cast_damage_skill(origin: Vector2, direction: Vector2, parameters: Dictionary) -> int:
	var affected: int = 0
	for enemy: Enemy in enemies:
		if complete:
			break
		if not enemy.active or enemy.health <= 0.0:
			continue
		if not skill_contains(parameters, origin, direction, enemy.position):
			continue
		var before: float = enemy.health
		apply_damage(enemy, float(parameters["damage"]), "skill:" + str(parameters["id"]), false, 0.0, str(parameters.get("element", "")))
		if enemy.health < before:
			affected += 1
	if not complete:
		affected += _damage_boss_points_in_skill(origin, direction, parameters)
		_damage_crates_in_skill(origin, direction, parameters)
	return affected

func _damage_crates_in_skill(origin: Vector2, direction: Vector2, parameters: Dictionary) -> void:
	var amount: float = float(parameters.get("damage", 0.0))
	if amount <= 0.0 or not interactions.has_active_crates():
		return
	var reach: float = float(parameters.get("radius", 0.0))
	if parameters.get("shape", "") == "line":
		reach += float(parameters.get("width", 70.0)) * 0.5
	for crate: Dictionary in interactions.damage_candidates(origin, reach):
		if skill_contains(parameters, origin, direction, crate["position"]):
			_damage_crate(int(crate["index"]), amount)

static func skill_contains(parameters: Dictionary, origin: Vector2, direction: Vector2, point: Vector2) -> bool:
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not point.is_finite():
		return false
	direction = direction.normalized()
	var offset: Vector2 = point - origin
	var radius: float = float(parameters.get("radius", 0.0))
	var shape: String = str(parameters.get("shape", "arc" if parameters.get("id", "") == "arc_slash" else "circle"))
	if shape == "rectangle":
		return absf(direction.dot(offset)) <= float(parameters.get("half_length", 0.0)) and absf(direction.cross(offset)) <= float(parameters.get("width", 0.0)) * 0.5
	if shape == "line":
		var along: float = direction.dot(offset)
		return along >= 0.0 and along <= radius and absf(direction.cross(offset)) <= float(parameters.get("width", 70.0)) * 0.5
	if offset.length_squared() > radius * radius + 0.01:
		return false
	if shape == "double_arc":
		return offset.is_zero_approx() or absf(direction.dot(offset.normalized())) + 0.000001 >= cos(float(parameters.get("half_angle_radians", 0.0)))
	return shape != "arc" or offset.is_zero_approx() or direction.dot(offset.normalized()) + 0.000001 >= cos(float(parameters.get("half_angle_radians", 0.0)))

func _sync_legacy_pulse_clock() -> void:
	var slot: int = _pulse_slot()
	if slot < 0:
		pulse_cooldown_left = 0.0
		return
	var uid: int = int(run.active_skills[slot]["uid"])
	var clock: Dictionary = _active_skill_clocks.get(uid, {})
	pulse_cooldown_left = float(clock.get("remaining", 0.0))
	if not clock.is_empty():
		pulse_cooldown_total = float(clock["duration"])

func active_skill_snapshot(slot: int) -> Dictionary:
	var result: Dictionary = {"slot": slot, "uid": -1, "id": "", "rank": 0, "available": false,
		"ready": false, "cooldown_remaining": 0.0, "cooldown_duration": 0.0, "uses": 0,
		"radius": 0.0, "damage": 0.0, "name": ""}
	var item: Dictionary = _skill_item(slot)
	if item.is_empty():
		return result
	var next_parameters: Dictionary = run.active_skill_parameters(item)
	if next_parameters.is_empty():
		return result
	next_parameters["damage"] = float(next_parameters.get("damage", 0.0)) * hero_effects.attack_multiplier()
	next_parameters["damage"] *= hero_effects.skill_multiplier(str(next_parameters.get("element", "")))
	var uid: int = int(item["uid"])
	var clock: Dictionary = _active_skill_clocks.get(uid, {})
	var remaining: float = float(clock.get("remaining", 0.0))
	var parameters: Dictionary = clock["parameters"] if remaining > 0.0 else next_parameters
	result.merge({"uid": uid, "id": item["id"], "rank": parameters["rank"], "available": true,
		"ready": not complete and run.health > 0.0 and remaining <= 0.0,
		"cooldown_remaining": remaining, "cooldown_duration": float(clock["duration"]) if remaining > 0.0 else float(parameters["cooldown"]),
		"uses": int(clock.get("uses", 0)), "radius": parameters["radius"], "damage": parameters["damage"], "name": parameters["name"],
		"hero_id": parameters.get("hero_id", ""), "skill_name": parameters.get("skill_name", ""), "rear_bonuses": (parameters.get("rear_bonuses", {}) as Dictionary).duplicate(true)}, true)
	return result

func active_skill_snapshots() -> Array:
	var result: Array[Dictionary] = []
	for slot: int in ActiveSkillRules.LIMIT:
		result.append(active_skill_snapshot(slot))
	return result

func pulse_snapshot() -> Dictionary:
	var slot: int = _pulse_slot()
	var current: Dictionary = active_skill_snapshot(slot)
	return {
		"available": current["available"],
		"ready": current["ready"],
		"cooldown_left": current["cooldown_remaining"],
		"cooldown_total": current["cooldown_duration"] if bool(current["available"]) else PulseRules.COOLDOWN,
		"next_cooldown_total": _current_pulse_cooldown(),
		"radius": _current_pulse_radius(),
		"last_cast_radius": last_pulse_radius,
		"uses": pulses_used,
		"affected": pulse_affected,
		"last_affected": last_pulse_affected,
	}

func spawn_enemy(id: String, position: Vector2 = Vector2.INF, deterministic_timer: bool = false) -> Enemy:
	if _enemy_free.is_empty():
		return null
	_explosion_grid_active = false
	_explosion_region_slots.clear()
	var enemy: Enemy = enemies[_enemy_free.pop_back()]
	enemy.active = true
	enemy.definition = GameCatalog.enemy(id)
	enemy.radius = enemy.definition.radius
	enemy.position = obstacles.free_point(_edge_position(enemy.radius) if position == Vector2.INF else position, enemy.radius)
	enemy.velocity = Vector2.ZERO
	_uid += 1
	enemy.uid = _uid
	var scaling: float = 1.0 if id == "boss" else 1.0 + 0.17 * float(run.wave - 1)
	enemy.max_health = enemy.definition.health * scaling
	enemy.health = enemy.max_health
	enemy.radius = enemy.definition.radius
	enemy.age = 0.0
	enemy.action_timer = 1.8 if deterministic_timer else rng.randf_range(1.0, 2.5)
	enemy.mode = 0
	enemy.slow_timer = 0.0
	enemy.slow_factor = 1.0
	enemy.pulse_hinder_timer = 0.0
	enemy.hurt_timer = 0.0
	enemy.hunter = false
	enemy.boss_ghost = false
	enemy.boss_cast_id = 0
	enemy.damage_scale = 1.0
	enemy.fire_vulnerability_left = 0.0
	enemy.fire_vulnerability = 0.0
	enemy.positive_conditions.clear()
	enemy.positive_attack = 0.0
	enemy.positive_speed = 0.0
	enemy.positive_defense = 0.0
	enemy_count += 1
	return enemy

func _edge_position(body_radius: float = 42.0) -> Vector2:
	var view: Rect2 = ArenaCatalog.visible_rect_for(run.arena_id, player_position)
	var ring: Rect2 = view.grow(SPAWN_MARGIN)
	var bounds: Rect2 = obstacles.bounds.grow(-SPAWN_INSET)
	var low: Vector2 = ring.position.max(bounds.position)
	var high: Vector2 = ring.end.min(bounds.end)
	var segments: Array[Rect2] = []
	if high.y > low.y:
		if ring.position.x >= bounds.position.x:
			segments.append(Rect2(Vector2(ring.position.x, low.y), Vector2(0, high.y - low.y)))
		if ring.end.x <= bounds.end.x:
			segments.append(Rect2(Vector2(ring.end.x, low.y), Vector2(0, high.y - low.y)))
	if high.x > low.x:
		if ring.position.y >= bounds.position.y:
			segments.append(Rect2(Vector2(low.x, ring.position.y), Vector2(high.x - low.x, 0)))
		if ring.end.y <= bounds.end.y:
			segments.append(Rect2(Vector2(low.x, ring.end.y), Vector2(high.x - low.x, 0)))
	segments = obstacles.clear_spawn_segments(segments, body_radius)
	var edge_roll: float = rng.randf()
	var position_roll: float = rng.randf()
	var length: float = 0.0
	for segment: Rect2 in segments:
		length += segment.size.length()
	var remaining: float = edge_roll * length
	for segment: Rect2 in segments:
		remaining -= segment.size.length()
		if remaining <= 0.0:
			return segment.position + segment.size * position_roll
	if not segments.is_empty():
		var last: Rect2 = segments.back()
		return last.position + last.size * position_roll
	# The bounded reference view always leaves a hidden edge; retain a safe fallback.
	var fallback: Vector2 = bounds.position if player_position.distance_squared_to(bounds.position) > player_position.distance_squared_to(bounds.end) else bounds.end
	return obstacles.free_point(fallback, body_radius, SPAWN_INSET)

func _spawn_wave_group() -> void:
	if _wave.boss_wave:
		return
	var count: int = 2 + int(run.wave / 2)
	if not _route.is_empty():
		count = maxi(1, ceili(float(count) * float(_route["count_factor"])))
	var weights: Dictionary = _wave.spawn_weights if _route.is_empty() else _route["weights"]
	for index: int in count:
		if enemy_count >= _wave.cap:
			break
		var roll: float = rng.randf()
		var total: float = 0.0
		var selected: String = "chaser"
		for id: String in weights:
			total += float(weights[id])
			if roll <= total:
				selected = id
				break
		spawn_enemy(selected)

func grant_enemy_condition(enemy: Enemy, kind: String, amount: float, seconds: float) -> bool:
	if complete or enemy == null or not enemy.active or enemy.health <= 0.0 or enemy.slot < 0 or enemy.slot >= enemies.size() or enemies[enemy.slot] != enemy:
		return false
	if kind not in ["attack", "speed", "defense"] or not is_finite(amount) or not is_finite(seconds) or amount <= 0.0 or seconds <= 0.0:
		return false
	enemy.positive_conditions[kind] = {"amount": minf(amount, 0.8 if kind == "defense" else 2.0), "remaining": minf(seconds, 30.0)}
	_refresh_enemy_conditions(enemy)
	return true

func dispel_enemy_condition(enemy: Enemy) -> bool:
	if complete or enemy == null or not enemy.active or enemy.health <= 0.0 or enemy.slot < 0 or enemy.slot >= enemies.size() or enemies[enemy.slot] != enemy or enemy.positive_conditions.is_empty():
		return false
	var first: String = str(enemy.positive_conditions.keys()[0])
	enemy.positive_conditions.erase(first)
	_refresh_enemy_conditions(enemy)
	add_effect(enemy.position, Color("b6e7df"), enemy.radius + 8.0, 0.22, 1)
	return true

func _advance_enemy_conditions(enemy: Enemy, delta: float) -> void:
	var changed: bool = false
	for kind: String in enemy.positive_conditions.keys():
		var value: Dictionary = enemy.positive_conditions[kind]
		value["remaining"] = maxf(0.0, float(value["remaining"]) - delta)
		if float(value["remaining"]) <= 0.0000001:
			enemy.positive_conditions.erase(kind)
			changed = true
	if changed:
		_refresh_enemy_conditions(enemy)

func _refresh_enemy_conditions(enemy: Enemy) -> void:
	enemy.positive_attack = float((enemy.positive_conditions.get("attack", {}) as Dictionary).get("amount", 0.0))
	enemy.positive_speed = float((enemy.positive_conditions.get("speed", {}) as Dictionary).get("amount", 0.0))
	enemy.positive_defense = float((enemy.positive_conditions.get("defense", {}) as Dictionary).get("amount", 0.0))

func _update_enemies(delta: float) -> void:
	for enemy: Enemy in enemies:
		if complete:
			return
		if not enemy.active:
			continue
		if not enemy.hunter and enemy.definition.id != "boss" and enemy.position.distance_squared_to(player_position) > ENEMY_DESPAWN_DISTANCE * ENEMY_DESPAWN_DISTANCE:
			enemy.active = false
			enemy_count -= 1
			_enemy_free.append(enemy.slot)
			obstacles.forget_agent(enemy.uid)
			continue
		enemy.age += delta
		enemy.action_timer -= delta
		enemy.hurt_timer = maxf(0.0, enemy.hurt_timer - delta)
		enemy.slow_timer = maxf(0.0, enemy.slow_timer - delta)
		if not enemy.positive_conditions.is_empty():
			_advance_enemy_conditions(enemy, delta)
		if enemy.fire_vulnerability_left > 0.0:
			enemy.fire_vulnerability_left = _skill_timer_after(enemy.fire_vulnerability_left, delta)
			if enemy.fire_vulnerability_left <= 0.0:
				enemy.fire_vulnerability = 0.0
		if is_finite(delta) and delta > 0.0:
			enemy.pulse_hinder_timer = _skill_timer_after(enemy.pulse_hinder_timer, delta)
		var direction: Vector2 = (player_position - enemy.position).normalized()
		var speed: float = enemy.definition.speed
		var distance: float = enemy.position.distance_to(player_position)
		var id: String = enemy.definition.id
		if id == "boss":
			_update_boss(enemy, direction, delta)
		elif id == "rusher":
			if enemy.mode == 0 and enemy.action_timer <= 0.0:
				enemy.mode = 1
				enemy.action_timer = RUSHER_WINDUP
				enemy.charge_direction = direction
			elif enemy.mode == 1:
				speed = 0.0
				if enemy.action_timer <= 0.0:
					enemy.mode = 2
					enemy.action_timer = 0.6
			elif enemy.mode == 2:
				direction = enemy.charge_direction
				speed = 330.0
				if enemy.action_timer <= 0.0:
					enemy.mode = 0
					enemy.action_timer = 2.5
		elif id == "caster":
			if distance < 250.0:
				speed = 0.0
			if distance < 160.0:
				direction = -direction
				speed = 35.0
			if enemy.action_timer <= CASTER_WINDUP:
				enemy.mode = 1
			if enemy.action_timer <= 0.0:
				var aim: Vector2 = (player_position - enemy.position).normalized()
				_hostile_shot(enemy.position, aim * enemy.definition.projectile_speed, enemy.definition.damage * (1.0 + enemy.positive_attack), id)
				enemy.action_timer = enemy.definition.cooldown
				enemy.mode = 0
		if id != "boss":
			var charging: bool = id == "rusher" and speed == 330.0
			speed *= 1.0 + enemy.positive_speed
			if enemy.hunter:
				speed *= RogueRules.HUNTER_SPEED_FACTOR
			if enemy.pulse_hinder_timer > 0.0 and not enemy.hunter:
				var hinder_factor: float = minf(enemy.slow_factor, PulseRules.HINDER_FACTOR) if enemy.slow_timer > 0.0 else PulseRules.HINDER_FACTOR
				speed *= hinder_factor
			elif enemy.slow_timer > 0.0:
				speed *= enemy.slow_factor
			speed *= ArenaCatalog.movement_multiplier(run.arena_id, enemy.position)
			var goal: Vector2 = enemy.position + direction * maxf(distance, 1.0) if id == "caster" and distance < 160.0 else player_position
			var waypoint: Vector2 = obstacles.next_target(enemy.position, goal, enemy.radius, enemy.uid) if not charging and speed > 0.0 else goal
			var routing: bool = not charging and speed > 0.0 and not waypoint.is_equal_approx(goal)
			var displacement: Vector2
			if routing:
				displacement = (waypoint - enemy.position).limit_length(speed * delta)
				enemy.velocity = displacement / delta if delta > 0.0 else Vector2.ZERO
			else:
				# Preserve open-ground pack motion; a locked charge remains straight.
				var side: float = 0.0 if charging else sin(float(enemy.uid) * 2.39996 + enemy.age * 0.35) * 0.24
				enemy.velocity = direction.rotated(side) * speed
				displacement = enemy.velocity * delta
				obstacles.forget_agent(enemy.uid)
			enemy.position = obstacles.move_body(enemy.position, displacement, enemy.radius, 0.0, not charging)
		if distance < enemy.radius + 13.0 and invulnerability <= 0.0:
			var contact_origin: Vector2 = enemy.position
			if dash_invulnerability_left <= 0.0 and not (enemy == boss and bool(boss_encounter.snapshot()["hold_position"])):
				# Retreat/charge movement can point away from the player; recoil is radial.
				var recoil_direction: Vector2 = (contact_origin - player_position).normalized()
				enemy.position = obstacles.move_body(contact_origin, recoil_direction * 18.0, enemy.radius)
			_hurt_player(enemy.definition.damage * enemy.damage_scale * (1.0 + enemy.positive_attack) * (1.0 + 0.09 * float(run.wave - 1)), id, "contact", contact_origin)

func _update_boss(enemy: Enemy, _direction: Vector2, delta: float) -> void:
	if enemy == boss and bool(boss_encounter.snapshot()["hold_position"]):
		enemy.velocity = Vector2.ZERO
		return
	var target: Vector2 = clamp_point(player_position + Vector2(0, -45) + Vector2(sin(enemy.age * 0.35) * 220.0, cos(enemy.age * 0.25) * 100.0), enemy.radius)
	var waypoint: Vector2 = obstacles.next_target(enemy.position, target, enemy.radius, enemy.uid)
	var speed: float = enemy.definition.speed * (enemy.slow_factor if enemy.slow_timer > 0.0 else 1.0)
	speed *= 1.0 + enemy.positive_speed
	speed *= ArenaCatalog.movement_multiplier(run.arena_id, enemy.position)
	var displacement: Vector2 = (waypoint - enemy.position).limit_length(speed * delta)
	enemy.velocity = displacement / delta if delta > 0.0 else Vector2.ZERO
	enemy.position = obstacles.move_body(enemy.position, displacement, enemy.radius)

func boss_weakpoints() -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	if complete or boss == null or not boss.active or boss.health <= 0.0:
		return points
	for point: Dictionary in boss_encounter.weakpoints_snapshot():
		if bool(point["active"]):
			points.append(point)
	return points

func boss_encounter_snapshot() -> Dictionary:
	var value: Dictionary = boss_encounter.snapshot()
	value.merge({"active": not complete and boss != null and boss.active and boss.health > 0.0,
		"health": boss.health if boss != null else 0.0, "max_health": boss.max_health if boss != null else 0.0,
		"display_name": GameCatalog.enemy("boss").display_name, "geometry": boss_encounter.telegraph_snapshot(),
		"interrupts": boss_interrupts, "weakpoints_broken": weakpoints_broken, "weakpoint_damage": weakpoint_damage}, true)
	return value

func _advance_boss_encounter(delta: float) -> void:
	if boss == null or not boss.active or boss.health <= 0.0:
		return
	_dispatch_boss_events(boss_encounter.advance(delta, boss.position, player_position, boss.health / boss.max_health))

func _dispatch_boss_events(events: Array[Dictionary]) -> void:
	if complete or boss == null or not boss.active:
		return
	for event: Dictionary in events:
		match str(event["type"]):
			"telegraph":
				_place_boss_weakpoints(int(event["cast_id"]))
			"attack", "root_lane":
				var zone := WarningZone.new()
				zone.shape = str(event["shape"])
				zone.position = event["position"]
				zone.radius = float(event.get("radius", 0.0))
				zone.direction = event.get("direction", Vector2.RIGHT)
				zone.length = float(event.get("length", 0.0))
				zone.width = float(event.get("width", 0.0))
				zone.damage = float(event["damage"])
				zone.delay = float(event.get("delay", 0.0))
				zone.duration = float(event.get("duration", 0.3))
				zone.source_cast_id = int(event["cast_id"])
				zones.append(zone)
			"summon":
				var alive: int = 0
				for enemy: Enemy in enemies:
					alive += int(enemy.active and enemy.boss_ghost)
				for point: Vector2 in event["positions"]:
					if alive >= int(event["max_alive"]) or enemy_count >= ENEMY_LIMIT:
						break
					var ghost: Enemy = spawn_enemy(str(event["enemy_id"]), point, true)
					if ghost == null:
						break
					ghost.boss_ghost = true
					ghost.boss_cast_id = int(event["cast_id"])
					ghost.max_health *= float(event["health_factor"])
					ghost.health = ghost.max_health
					ghost.damage_scale = float(event["damage_factor"])
					alive += 1

func _place_boss_weakpoints(cast_id: int) -> void:
	var locations: Dictionary = {}
	for point: Dictionary in boss_encounter.weakpoints_snapshot():
		locations[int(point["uid"])] = _safe_weakpoint_position(point["position"], float(point["radius"]), locations)
	var placed: bool = boss_encounter.relocate_weakpoints(cast_id, locations)
	if not placed:
		push_error("The authored boss weakpoints cannot fit the active arena")

func _safe_weakpoint_position(desired: Vector2, radius: float, locations: Dictionary) -> Vector2:
	for attempt: int in 65:
		var offset: Vector2 = Vector2.ZERO if attempt == 0 else Vector2.from_angle(float((attempt - 1) % 16) * TAU / 16.0) * (32.0 + float((attempt - 1) / 16) * 32.0)
		var position: Vector2 = obstacles.free_point(desired + offset, radius + 4.0, radius + 4.0)
		if _weakpoint_position_fits(position, radius, locations):
			return position
	for y: int in range(32, int(ARENA.size.y), 64):
		for x: int in range(32, int(ARENA.size.x), 64):
			var position: Vector2 = ARENA.position + Vector2(x, y)
			if _weakpoint_position_fits(position, radius, locations):
				return position
	return Vector2.INF

func _weakpoint_position_fits(position: Vector2, radius: float, locations: Dictionary) -> bool:
	if not ARENA.grow(-radius - 4.0).has_point(position) or not obstacles.is_free(position, radius + 4.0):
		return false
	for existing: Vector2 in locations.values():
		if position.distance_to(existing) < radius * 2.0 + 4.0:
			return false
	return true

func _nearest_weakpoint(position: Vector2, distance: float, excluded: Dictionary = {}) -> Dictionary:
	var best: float = distance * distance
	var result: Dictionary = {}
	for point: Dictionary in boss_weakpoints():
		var key: String = "%d:%d" % [point["cast_id"], point["uid"]]
		if excluded.has(key):
			continue
		var squared: float = position.distance_squared_to(point["position"])
		if squared < best or (result.is_empty() and squared <= best):
			best = squared
			result = point
	return result

func _weakpoint_first_hit(start: Vector2, end: Vector2, padding: float, excluded: Dictionary = {}, ignore_outward_overlap: bool = false) -> Dictionary:
	var result: Dictionary = {}
	var best: float = INF
	for point: Dictionary in boss_weakpoints():
		var key: String = "%d:%d" % [point["cast_id"], point["uid"]]
		if excluded.has(key):
			continue
		if ignore_outward_overlap:
			var offset: Vector2 = start - (point["position"] as Vector2)
			if offset.length_squared() <= pow(padding + float(point["radius"]), 2) and offset.dot(end - start) >= 0.0:
				continue
		var entry: float = _swept_circle_entry_t(start, end, point["position"], padding + float(point["radius"]))
		if entry < best:
			best = entry
			result = {"t": entry, "point": point, "key": key}
	return result

func _damage_boss_weakpoint(point: Dictionary, amount: float) -> Dictionary:
	if complete or boss == null or not boss.active or boss.health <= 0.0:
		return {}
	var outcome: Dictionary = boss_encounter.damage_weakpoint(int(point["uid"]), int(point["cast_id"]), amount)
	if bool(outcome.get("hit", false)):
		weakpoint_damage += float(outcome["damage"])
		weakpoints_broken += int(bool(outcome["broke"]))
		boss_weakpoint_hit.emit(int(point["uid"]), int(point["cast_id"]), outcome["position"], bool(outcome["broke"]))
		if bool(outcome["interrupted"]):
			boss_interrupts += 1
			boss_interrupted.emit(boss.position)
	return outcome

func _damage_boss_points_in_skill(origin: Vector2, direction: Vector2, spec: Dictionary) -> int:
	var affected: int = 0
	var amount: float = float(spec.get("damage", 0.0))
	if amount <= 0.0:
		return affected
	for point: Dictionary in boss_weakpoints():
		if skill_contains(spec, origin, direction, point["position"]):
			affected += int(bool(_damage_boss_weakpoint(point, amount).get("hit", false)))
	return affected

func _clear_boss_ghosts() -> void:
	for enemy: Enemy in enemies:
		if enemy.active and enemy.boss_ghost:
			_explosion_region_slots.clear()
			enemy.active = false
			enemy_count -= 1
			_enemy_free.append(enemy.slot)
			obstacles.forget_agent(enemy.uid)

func _rebuild_grid() -> void:
	_shot_region_candidates.clear()
	_explosion_region_slots.clear()
	_target_points.clear()
	_largest_enemy_radius = 0.0
	for key: Vector2i in _grid:
		(_grid[key] as Array).clear()
	for enemy: Enemy in enemies:
		if not enemy.active:
			continue
		_largest_enemy_radius = maxf(_largest_enemy_radius, enemy.radius)
		_target_points.add_point(enemy.slot, enemy.position)
		var cell: Vector2i = Vector2i((enemy.position / CELL).floor())
		if not _grid.has(cell):
			_grid[cell] = []
		(_grid[cell] as Array).append(enemy)

func _nearest(position: Vector2, distance: float, excluded: Dictionary = {}) -> Enemy:
	if not _explosion_grid_active or not position.is_finite() or not is_finite(distance) or absf(distance) > CELL * 16.0 or excluded.size() > 16:
		return _nearest_linear(position, distance, excluded)
	# Native point lookup uses pool-slot IDs, preserving the earliest slot on ties.
	var disabled: PackedInt64Array = PackedInt64Array()
	var result: Enemy
	var slot: int = _target_points.get_closest_point(position)
	while slot >= 0:
		var enemy: Enemy = enemies[slot]
		if enemy.position.distance_squared_to(position) >= distance * distance:
			break
		if enemy.active and not excluded.has(enemy.uid):
			result = enemy
			break
		_target_points.set_point_disabled(slot, true)
		if enemy.active:
			disabled.append(slot)
		slot = _target_points.get_closest_point(position)
	for id: int in disabled:
		_target_points.set_point_disabled(id, false)
	return result

func _nearest_linear(position: Vector2, distance: float, excluded: Dictionary) -> Enemy:
	var result: Enemy
	var best: float = distance * distance
	for enemy: Enemy in enemies:
		if not enemy.active or excluded.has(enemy.uid):
			continue
		var squared: float = enemy.position.distance_squared_to(position)
		if squared < best:
			best = squared
			result = enemy
	return result

func _update_weapons(delta: float) -> void:
	while _cooldowns.size() < run.loadout.size():
		_cooldowns.append(0.0)
	if _cooldowns.size() > run.loadout.size():
		_cooldowns.resize(run.loadout.size())
	for index: int in run.loadout.size():
		_cooldowns[index] -= delta
		if _cooldowns[index] > 0.0:
			continue
		var equipped: Dictionary = run.loadout[index]
		var definition: ContentDef = GameCatalog.weapon(str(equipped["id"]))
		var uid: int = int(equipped.get("uid", -index - 1))
		var target: Enemy = _weapon_target(player_position, definition.range, str(equipped["id"]) == "ember" and run.core_id == "frostfire", _linked_weapons.has(uid))
		var point: Dictionary = _nearest_weakpoint(player_position, definition.range)
		if target == null and point.is_empty():
			_cooldowns[index] = 0.08
			continue
		var rune_entry: Dictionary = equipped.get("rune", {})
		var rune: String = str(rune_entry.get("id", ""))
		var aim: Vector2 = point["position"] if not point.is_empty() else target.position
		var angle: float = (aim - player_position).angle()
		var fired: bool = false
		for pellet: int in definition.shots:
			var offset: float = (float(pellet) - float(definition.shots - 1) * 0.5) * definition.spread
			var shot: Shot = fire_weapon(str(equipped["id"]), rune, player_position, Vector2.from_angle(angle + offset), int(equipped.get("rank", 1)), int(rune_entry.get("rank", 1)), float(equipped.get("resonance_bonus", 0.0)))
			if shot != null:
				shot.low_health_priority = _linked_weapons.has(uid)
			fired = fired or shot != null
		if fired and run.core_id == "bone_chorus" and definition.id == "bone":
			_fire_chorus(uid, equipped, rune_entry, angle)
		_cooldowns[index] = definition.cooldown / run.stat("attack_speed")
		shot_fired.emit()

func _fire_chorus(uid: int, equipped: Dictionary, rune_entry: Dictionary, angle: float) -> void:
	_chorus_counts[uid] = int(_chorus_counts.get(uid, 0)) + 1
	if int(_chorus_counts[uid]) % RogueRules.CHORUS_INTERVAL != 0:
		return
	var emitted: bool = false
	for side: float in [-1.0, 1.0]:
		var extra: Shot = fire_weapon("bone", str(rune_entry.get("id", "")), player_position,
			Vector2.from_angle(angle + side * RogueRules.CHORUS_ANGLE), int(equipped.get("rank", 1)), int(rune_entry.get("rank", 1)), float(equipped.get("resonance_bonus", 0.0)))
		if extra != null:
			extra.damage *= RogueRules.CHORUS_FACTOR
			extra.low_health_priority = _linked_weapons.has(uid)
			emitted = true
	if emitted:
		core_activations["bone_chorus"] = int(core_activations["bone_chorus"]) + 1
		core_activated.emit("bone_chorus", player_position)
		add_effect(player_position, Color("e6d8b4"), 24.0, 0.18, 1)

func _weapon_target(point: Vector2, distance: float, slowed_first: bool, low_health_first: bool, excluded: Dictionary = {}) -> Enemy:
	if not slowed_first and not low_health_first:
		return _nearest(point, distance, excluded)
	var result: Enemy
	var best_ratio: float = INF
	var best_distance: float = distance * distance
	for enemy: Enemy in enemies:
		if not enemy.active or excluded.has(enemy.uid) or (slowed_first and enemy.slow_timer <= 0.0):
			continue
		var squared: float = enemy.position.distance_squared_to(point)
		if squared >= distance * distance:
			continue
		var ratio: float = enemy.health / maxf(0.001, enemy.max_health) if low_health_first else 0.0
		if result == null or ratio < best_ratio or (ratio == best_ratio and squared < best_distance):
			result = enemy
			best_ratio = ratio
			best_distance = squared
	if result == null and slowed_first:
		return _weapon_target(point, distance, false, low_health_first, excluded)
	return result

func fire_weapon(weapon_id: String, rune_id: String, position: Vector2, direction: Vector2, weapon_rank: int = 1, rune_rank: int = 1, resonance_bonus: float = 0.0) -> Shot:
	var shot: Shot = _allocate_shot()
	if shot == null:
		return null
	var definition: ContentDef = GameCatalog.weapon(weapon_id)
	shot.position = position
	shot.previous = position
	shot.velocity = direction.normalized() * definition.projectile_speed
	shot.radius = definition.projectile_radius
	shot.weapon_rank = clampi(weapon_rank, 1, 3)
	shot.rune_rank = clampi(rune_rank, 1, 3)
	shot.resonance_bonus = clampf(resonance_bonus, 0.0, BackpackResonance.MAX_BONUS) if is_finite(resonance_bonus) else 0.0
	shot.damage = definition.damage * run.stat("damage") * hero_effects.attack_multiplier() * BackpackInventory.rank_multiplier(shot.weapon_rank) * (1.0 + shot.resonance_bonus)
	shot.source = weapon_id
	shot.attacker_id = ""
	shot.rune = rune_id
	shot.remaining = RuneRules.extra_hits(shot.rune_rank) if rune_id == "pierce" or rune_id == "bounce" else 0
	shot.innate_remaining = definition.innate_pierce
	shot.life = definition.range / maxf(1.0, definition.projectile_speed) + 1.2
	if definition.return_delay > 0.0:
		shot.return_after = definition.return_delay
		shot.return_speed = definition.return_speed if definition.return_speed > 0.0 else definition.projectile_speed
		if definition.return_lifetime > 0.0:
			shot.life = definition.return_lifetime
	shot.homing = definition.homing
	shot.slow = definition.slow
	shot.hostile = false
	shot.color = definition.color
	return shot

func _allocate_shot() -> Shot:
	if _shot_free.is_empty():
		return null
	var shot: Shot = shots[_shot_free.pop_back()]
	shot.active = true
	shot.hit_ids.clear()
	shot.weakpoint_hit_ids.clear()
	shot.remaining = 0
	shot.innate_remaining = 0
	shot.weapon_rank = 1
	shot.rune_rank = 1
	shot.resonance_bonus = 0.0
	shot.return_after = 0.0
	shot.return_speed = 0.0
	shot.returning = false
	shot.return_cancelled = false
	shot.attacker_id = ""
	shot.low_health_priority = false
	shot_count += 1
	return shot

func _hostile_shot(position: Vector2, velocity: Vector2, damage: float, attacker_id: String = "enemy") -> void:
	var shot: Shot = _allocate_shot()
	if shot == null:
		return
	shot.position = position
	shot.previous = position
	shot.velocity = velocity
	shot.damage = damage
	shot.radius = 7.0
	shot.life = 7.0
	shot.hostile = true
	shot.homing = 0.0
	shot.slow = 0.0
	shot.source = "enemy"
	shot.attacker_id = attacker_id
	shot.rune = ""
	shot.remaining = 0
	shot.color = Color("ff775e")

func _update_shots(delta: float) -> void:
	for shot: Shot in shots:
		if complete:
			return
		if not shot.active:
			continue
		shot.life -= delta
		var can_return: bool = not shot.hostile and not shot.return_cancelled and (shot.returning or shot.return_after > 0.0)
		if shot.life <= 0.0 or (not can_return and not ARENA.grow(100.0).has_point(shot.position)):
			_release_shot(shot)
			continue
		if can_return and not shot.returning:
			shot.return_after = maxf(0.0, shot.return_after - delta)
			shot.returning = shot.return_after <= 0.0
		if shot.returning:
			shot.velocity = (player_position - shot.position).normalized() * shot.return_speed
		elif shot.homing > 0.0 and not shot.hostile:
			var target: Enemy = _weapon_target(shot.position, 420.0, shot.source == "ember" and run.core_id == "frostfire", shot.low_health_priority, shot.hit_ids)
			var point: Dictionary = _nearest_weakpoint(shot.position, 420.0, shot.weakpoint_hit_ids)
			if target != null or not point.is_empty():
				var aim: Vector2 = point["position"] if not point.is_empty() else target.position
				var speed: float = shot.velocity.length()
				var desired: Vector2 = (aim - shot.position).normalized()
				var heading: Vector2 = shot.velocity.normalized()
				var weight: float = minf(1.0, shot.homing * delta)
				var turn_cross: float = heading.cross(desired)
				# Opposite vectors keep their heading below half weight, or cancel at half.
				# Only escape that narrow case; exact opposition takes a fixed, RNG-free side.
				if weight > 0.0 and weight <= 0.5 and heading.dot(desired) < 0.0 and absf(turn_cross) <= 0.0001:
					var turn_sign: float = -1.0 if turn_cross < 0.0 else 1.0
					shot.velocity = heading.rotated(turn_sign * weight) * speed
				else:
					shot.velocity = heading.lerp(desired, weight).normalized() * speed
		shot.previous = shot.position
		shot.position += shot.velocity * delta
		var pending_recovery: bool = false
		if shot.returning:
			var recovery_t: float = _swept_circle_entry_t(shot.previous, shot.position, player_position, shot.radius + 12.0)
			if is_finite(recovery_t):
				shot.position = shot.previous.lerp(shot.position, recovery_t)
				pending_recovery = true
		if shot.hostile:
			if _segment_distance_squared(player_position, shot.previous, shot.position) < pow(shot.radius + 12.0, 2):
				var hit_damage: float = shot.damage
				var attacker_id: String = shot.attacker_id
				var hit_origin: Vector2 = shot.position
				_release_shot(shot)
				_hurt_player(hit_damage, attacker_id, "projectile", hit_origin)
			continue
		var impact: Enemy = _first_collision(shot)
		var hit_count: int = 0
		var hit_limit: int = 1 + shot.innate_remaining + shot.remaining
		while shot.active and hit_count < hit_limit:
			var crate: Dictionary = interactions.first_crate_hit(shot.previous, shot.position, shot.radius)
			var enemy_t: float = _swept_circle_entry_t(shot.previous, shot.position, impact.position, shot.radius + impact.radius) if impact != null else INF
			if boss != null and boss.active:
				var point: Dictionary = _weakpoint_first_hit(shot.previous, shot.position, shot.radius, shot.weakpoint_hit_ids)
				if not point.is_empty() and float(point["t"]) <= minf(enemy_t, float(crate.get("t", INF))):
					hit_count += 1
					shot.weakpoint_hit_ids[point["key"]] = true
					_damage_boss_weakpoint(point["point"], shot.damage)
					if shot.innate_remaining > 0:
						shot.innate_remaining -= 1
						continue
					if shot.rune == "pierce" and shot.remaining > 0:
						shot.remaining -= 1
						continue
					_release_shot(shot)
					break
			if not crate.is_empty() and float(crate["t"]) <= enemy_t:
				_damage_crate(int(crate["index"]), shot.damage)
				_release_shot(shot)
				break
			if impact == null:
				break
			hit_count += 1
			shot.hit_ids[impact.uid] = true
			var impact_position: Vector2 = impact.position
			var health_before: float = impact.health
			var incoming_direction: Vector2 = shot.velocity.normalized()
			var frostfire: bool = run.core_id == "frostfire" and shot.source == "ember" and impact.slow_timer > 0.0
			apply_damage(impact, shot.damage, shot.source, false, shot.slow)
			var positive_hit: bool = impact.health < health_before
			if complete:
				_release_shot(shot)
				return
			if frostfire and positive_hit:
				impact.slow_timer = 0.0
				impact.slow_factor = 1.0
				_frostfire_burst(impact_position, shot.damage, shot.source, shot.hit_ids)
				if complete:
					_release_shot(shot)
					return
			# Native penetration precedes the socketed rune and shares its hit exclusions.
			if shot.innate_remaining > 0:
				shot.innate_remaining -= 1
				impact = _first_collision(shot)
				continue
			if shot.rune == "blast":
				_release_shot(shot)
				if positive_hit:
					rune_activated.emit("blast", impact_position, incoming_direction, Vector2.ZERO)
					_explode(impact_position, shot.damage * RuneRules.blast_factor(shot.rune_rank), shot.source, shot.hit_ids, RuneRules.blast_radius(shot.rune_rank))
			elif shot.rune == "pierce" and shot.remaining > 0:
				shot.remaining -= 1
				if positive_hit:
					rune_activated.emit("pierce", impact_position, incoming_direction, incoming_direction)
				impact = _first_collision(shot)
				continue
			elif shot.rune == "bounce" and shot.remaining > 0:
				var target: Enemy = _nearest(impact_position, RuneRules.BOUNCE_RANGE, shot.hit_ids)
				if target != null:
					if shot.return_after > 0.0 or shot.returning:
						shot.return_cancelled = true
						shot.returning = false
						shot.return_after = 0.0
					shot.position = impact_position
					shot.velocity = (target.position - impact_position).normalized() * shot.velocity.length()
					shot.damage *= RuneRules.BOUNCE_DAMAGE_FACTOR
					shot.remaining -= 1
					if shot.return_speed <= 0.0:
						shot.life = maxf(shot.life, 0.7)
					add_effect(impact_position, Color("dcc5ff"), 12.0, 0.18, 1)
					if positive_hit:
						rune_activated.emit("bounce", impact_position, incoming_direction, shot.velocity.normalized())
				else:
					_release_shot(shot)
			else:
				_release_shot(shot)
			break
		if pending_recovery and shot.active and shot.returning:
			_release_shot(shot)

func _frostfire_burst(point: Vector2, damage: float, source: String, excluded: Dictionary) -> void:
	core_activations["frostfire"] = int(core_activations["frostfire"]) + 1
	core_activated.emit("frostfire", point)
	add_effect(point, Color("9de1e6"), RogueRules.FROSTFIRE_RADIUS, 0.32, 3)
	for slot: int in _explosion_slots(point, RogueRules.FROSTFIRE_RADIUS):
		if complete:
			return
		var enemy: Enemy = enemies[slot]
		if enemy.active and not excluded.has(enemy.uid) and enemy.position.distance_squared_to(point) < pow(RogueRules.FROSTFIRE_RADIUS + enemy.radius, 2):
			apply_damage(enemy, damage * RogueRules.FROSTFIRE_FACTOR, source, true)
	if not complete:
		_damage_boss_points_in_skill(point, Vector2.RIGHT, {"shape": "circle", "radius": RogueRules.FROSTFIRE_RADIUS, "damage": damage * RogueRules.FROSTFIRE_FACTOR})
		_damage_crates_in_skill(point, Vector2.RIGHT, {"shape": "circle", "radius": RogueRules.FROSTFIRE_RADIUS, "damage": damage * RogueRules.FROSTFIRE_FACTOR})

func _first_collision(shot: Shot) -> Enemy:
	var result: Enemy
	var nearest_t: float = INF
	var movement: Vector2 = shot.position - shot.previous
	var length_squared: float = movement.length_squared()
	var low: Vector2 = shot.previous.min(shot.position)
	var high: Vector2 = shot.previous.max(shot.position)
	var padding: float = shot.radius + _largest_enemy_radius
	var start: Vector2i = Vector2i(((low - Vector2.ONE * padding) / CELL).floor())
	var end: Vector2i = Vector2i(((high + Vector2.ONE * padding) / CELL).floor())
	for enemy: Enemy in _shot_candidates(start, end):
		if not enemy.active or shot.hit_ids.has(enemy.uid):
			continue
		var radius: float = enemy.radius + shot.radius
		var center: Vector2 = enemy.position
		if center.x < low.x - radius or center.x > high.x + radius or center.y < low.y - radius or center.y > high.y + radius:
			continue
		var offset: Vector2 = shot.previous - center
		var outside: float = offset.length_squared() - radius * radius
		var t: float = 0.0
		if outside > 0.0:
			if length_squared <= 0.000001:
				continue
			var projection: float = offset.dot(movement)
			if projection >= 0.0:
				continue
			var discriminant: float = projection * projection - length_squared * outside
			if discriminant < 0.0:
				continue
			t = (-projection - sqrt(discriminant)) / length_squared
			if t < 0.0 or t > 1.0:
				continue
		if t < nearest_t:
			nearest_t = t
			result = enemy
	return result

func _shot_candidates(first: Vector2i, last: Vector2i) -> Array:
	if first == last:
		return _grid.get(first, [])
	var key := Vector4i(first.x, first.y, last.x, last.y)
	if _explosion_grid_active and _shot_region_candidates.has(key):
		return _shot_region_candidates[key]
	var result: Array = []
	for x: int in range(first.x, last.x + 1):
		for y: int in range(first.y, last.y + 1):
			var cell := Vector2i(x, y)
			if _grid.has(cell):
				result.append_array(_grid[cell])
	if _explosion_grid_active:
		_shot_region_candidates[key] = result
	return result

static func _swept_circle_entry_t(start: Vector2, end: Vector2, center: Vector2, radius: float) -> float:
	# Compare circle entry times, not center projections: different radii can overlap.
	var offset: Vector2 = start - center
	var outside: float = offset.length_squared() - radius * radius
	if outside <= 0.0:
		return 0.0
	var segment: Vector2 = end - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.000001:
		return INF
	var projection: float = offset.dot(segment)
	if projection >= 0.0:
		return INF
	var discriminant: float = projection * projection - length_squared * outside
	if discriminant < 0.0:
		return INF
	var entry: float = (-projection - sqrt(discriminant)) / length_squared
	return entry if entry >= 0.0 and entry <= 1.0 else INF

static func _segment_distance_squared(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	var t: float = clampf((point - start).dot(segment) / maxf(0.0001, segment.length_squared()), 0.0, 1.0)
	return point.distance_squared_to(start + segment * t)

static func clamp_point(point: Vector2, inset: float = 0.0) -> Vector2:
	var bounds: Rect2 = ARENA.grow(-inset)
	return Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.y, bounds.position.y, bounds.end.y))

func apply_damage(enemy: Enemy, amount: float, source: String, secondary: bool = false, slow: float = 0.0, element: String = "") -> void:
	if complete or enemy == null or not enemy.active:
		return
	var target_uid: int = enemy.uid
	var multiplier: float = float(boss_encounter.snapshot()["damage_multiplier"]) if enemy == boss else 1.0
	multiplier *= 1.0 - enemy.positive_defense
	if enemy.fire_vulnerability_left > 0.0:
		if element.is_empty():
			var weapon: ContentDef = GameCatalog.weapon(source)
			element = weapon.element if weapon != null else "physical"
		if element == "fire":
			multiplier *= 1.0 + enemy.fire_vulnerability
	multiplier *= weapon_effects.damage_multiplier(self, source, enemy)
	var actual: float = minf(enemy.health, maxf(0.0, amount) * multiplier)
	if actual <= 0.0:
		return
	enemy.health -= actual
	enemy.hurt_timer = 0.10
	if slow > 0.0:
		enemy.slow_timer = 1.5
		enemy.slow_factor = 1.0 - slow
	if source.begins_with("skill:"):
		var skill_id: String = source.trim_prefix("skill:")
		damage_by_skill[skill_id] = float(damage_by_skill.get(skill_id, 0.0)) + actual
		skill_hits += 1
	else:
		damage_by_weapon[source] = float(damage_by_weapon.get(source, 0.0)) + actual
		run.damage_dealt_by_weapon[source] = float(run.damage_dealt_by_weapon.get(source, 0.0)) + actual
		if secondary:
			secondary_hits += 1
		else:
			primary_hits += 1
	damage_dealt.emit(enemy.position, actual, source, secondary, target_uid)
	if complete or not enemy.active or enemy.uid != target_uid:
		return
	enemy_hit.emit()
	if complete or not enemy.active or enemy.uid != target_uid:
		return
	if enemy.health <= 0.0:
		_kill_enemy(enemy)

func _explode(position: Vector2, amount: float, source: String, excluded: Dictionary, radius: float = RuneRules.BLAST_RADIUS) -> void:
	add_effect(position, Color("df9cfa"), radius, 0.35, 0)
	for slot: int in _explosion_slots(position, radius):
		if complete:
			return
		var enemy: Enemy = enemies[slot]
		if not enemy.active or excluded.has(enemy.uid):
			continue
		if enemy.position.distance_squared_to(position) < pow(radius + enemy.radius, 2):
			# Secondary damage deliberately never enters the rune dispatch path.
			apply_damage(enemy, amount, source, true)
	if not complete:
		_damage_boss_points_in_skill(position, Vector2.RIGHT, {"shape": "circle", "radius": radius, "damage": amount})
		_damage_crates_in_skill(position, Vector2.RIGHT, {"shape": "circle", "radius": radius, "damage": amount})

func _explosion_slots(position: Vector2, radius: float = RuneRules.BLAST_RADIUS) -> PackedInt32Array:
	# Only this step's shot phase has stable positions/radii. Direct calls may follow
	# external edits or an empty/stale grid, so retain their original full scan.
	if not _explosion_grid_active:
		var linear_slots := PackedInt32Array()
		for index: int in enemies.size():
			linear_slots.append(index)
		return linear_slots
	var reach: Vector2 = Vector2.ONE * (radius + _largest_enemy_radius)
	var start: Vector2i = Vector2i(((position - reach) / CELL).floor())
	var end: Vector2i = Vector2i(((position + reach) / CELL).floor())
	var key := Vector4i(start.x, start.y, end.x, end.y)
	if _explosion_region_slots.has(key):
		# Internal consumers only iterate; mutations require their own duplicate.
		return _explosion_region_slots[key]
	var slots := PackedInt32Array()
	for x: int in range(start.x, end.x + 1):
		for y: int in range(start.y, end.y + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not _grid.has(cell):
				continue
			for enemy: Enemy in _grid[cell]:
				if enemy.active:
					slots.append(enemy.slot)
	# Damage/kill/terminal order is observable; preserve the original pool-slot order.
	slots.sort()
	if _explosion_region_slots.size() < EXPLOSION_REGION_CACHE_LIMIT:
		_explosion_region_slots[key] = slots
	return slots

func _kill_enemy(enemy: Enemy) -> void:
	if enemy == null or not enemy.active:
		return
	_explosion_region_slots.clear()
	enemy.active = false
	obstacles.forget_agent(enemy.uid)
	enemy_count -= 1
	_enemy_free.append(enemy.slot)
	run.kills += 1
	if enemy.hunter:
		run.record_hunter_defeat()
	var value: int = 3 if enemy.definition.id == "tank" else 1
	_drop_soul(enemy.position, value)
	add_effect(enemy.position, enemy.definition.color, enemy.radius + 6.0, 0.25, 2)
	enemy_killed.emit(enemy.position, enemy.definition.color)
	if enemy == boss:
		collect_remaining_souls()
		_finish(true, "%s已被击败。你的余烬仍在燃烧。" % GameCatalog.enemy("boss").display_name)

func _drop_soul(position: Vector2, value: int) -> void:
	if _soul_free.is_empty():
		# Capacity pressure must not delete earned currency or experience.
		run.collect_souls(value)
		return
	var soul: Soul = souls[_soul_free.pop_back()]
	soul.active = true
	soul.position = obstacles.free_point(position, 6.0)
	soul.value = value
	soul.age = 0.0
	soul_count += 1

func _update_souls(delta: float) -> void:
	var collected: int = 0
	var radius: float = run.stat("pickup_radius")
	for soul: Soul in souls:
		if not soul.active:
			continue
		soul.age += delta
		var distance: float = soul.position.distance_to(player_position)
		if distance < radius:
			soul.position = soul.position.move_toward(player_position, (280.0 + (radius - distance) * 5.0) * delta)
			if distance < 18.0:
				collected += soul.value
				_release_soul(soul)
	if collected > 0:
		run.collect_souls(collected)

func collect_remaining_souls() -> void:
	var collected: int = 0
	for soul: Soul in souls:
		if soul.active:
			collected += soul.value
			_release_soul(soul)
	if collected > 0:
		run.collect_souls(collected)

static func zone_contains(zone: WarningZone, point: Vector2, padding: float = 10.0) -> bool:
	if zone.shape != "lane":
		return point.distance_squared_to(zone.position) < pow(zone.radius + padding, 2)
	var direction: Vector2 = zone.direction.normalized()
	var offset: Vector2 = point - zone.position
	var along: float = offset.dot(direction)
	var across: float = offset.dot(direction.orthogonal())
	var outside := Vector2(along - clampf(along, 0.0, zone.length), across - clampf(across, -zone.width * 0.5, zone.width * 0.5))
	return outside.length_squared() <= padding * padding

func _update_zones(delta: float) -> void:
	for index: int in range(zones.size() - 1, -1, -1):
		if complete:
			return
		var zone: WarningZone = zones[index]
		zone.age += delta
		var activate: bool = zone.age >= zone.delay and not zone.triggered
		if activate:
			zone.triggered = true
			if zone.shape != "lane":
				add_effect(zone.position, Color("ff705c"), zone.radius, zone.duration)
		var can_damage: bool = zone.age >= zone.delay and zone.age <= zone.delay + zone.duration if zone.source_cast_id > 0 else activate
		if can_damage and zone_contains(zone, player_position):
			_hurt_player(zone.damage, zone.source_id, "ritual", zone.position)
		if zone.age > zone.delay + zone.duration:
			zones.remove_at(index)

func _hurt_player(amount: float, source_id: String = "enemy", kind: String = "contact", origin: Vector2 = Vector2.INF) -> void:
	if complete or invulnerability > 0.0 or run.health <= 0.0:
		return
	if dash_invulnerability_left > 0.0:
		if not dash_evaded_current and is_finite(amount) and amount > 0.0:
			dash_evaded_current = true
			dash_evades += 1
			dash_evaded.emit(player_position, origin if origin.is_finite() else player_position, source_id, kind)
		return
	var actual: float = run.take_damage(amount, source_id, kind)
	if actual <= 0.0:
		return
	weapon_effects.observe_health(self)
	invulnerability = 0.7
	add_effect(player_position, Color("ffc7a0"), 30.0, 0.25, 1)
	player_damaged.emit(actual, source_id, kind, player_position if origin == Vector2.INF else origin)
	player_hurt.emit()
	if run.health <= 0.0:
		_finish(false, _death_reason(source_id, kind))

func _death_reason(source_id: String = "", kind: String = "") -> String:
	if source_id.is_empty():
		source_id = str(run.last_hit.get("source_id", ""))
		kind = str(run.last_hit.get("kind", ""))
	if source_id.is_empty():
		return "生命耗尽，祭坛吞没了最后一簇余烬。"
	var definition: ContentDef = GameCatalog.enemy(source_id)
	var source_name: String = definition.display_name if definition != null else "敌人"
	var attack_name: String = str({"contact": "接触攻击", "projectile": "弹丸", "ritual": "仪式"}.get(kind, "攻击"))
	return "生命耗尽：被%s的%s击败。" % [source_name, attack_name]

func _release_shot(shot: Shot) -> void:
	if not shot.active:
		return
	shot.active = false
	shot_count -= 1
	_shot_free.append(shot.slot)

func _release_soul(soul: Soul) -> void:
	soul.active = false
	soul_count -= 1
	_soul_free.append(soul.slot)

func add_effect(position: Vector2, color: Color, radius: float, life: float, kind: int = 0) -> void:
	if effects.size() >= 90:
		return
	var effect: Effect = Effect.new()
	effect.position = position
	effect.color = color
	effect.radius = radius
	effect.life = life
	effect.total = life
	effect.kind = kind
	effects.append(effect)

func _update_effects(delta: float) -> void:
	for index: int in range(effects.size() - 1, -1, -1):
		effects[index].life -= delta
		if effects[index].life <= 0.0:
			effects.remove_at(index)

func _finish(won: bool, reason: String) -> void:
	if complete:
		return
	complete = true
	clear_hero_effects()
	weapon_effects.clear()
	boss_encounter.stop()
	_clear_boss_ghosts()
	victory = won
	end_reason = reason
	ended.emit(won, reason)

func enemy_conditions_snapshot() -> Array[Dictionary]:
	var value: Array[Dictionary] = []
	for enemy: Enemy in enemies:
		if enemy.active and not enemy.positive_conditions.is_empty():
			value.append({"uid": enemy.uid, "conditions": enemy.positive_conditions.duplicate(true),
				"attack": enemy.positive_attack, "speed": enemy.positive_speed, "defense": enemy.positive_defense})
	return value

func snapshot() -> Dictionary:
	return {
		"health": run.health, "max_health": run.stat("max_health"), "wave": run.wave,
		"time_left": maxf(0.0, duration - elapsed), "gold": run.gold, "level": run.level,
		"xp": run.xp, "xp_needed": run.xp_to_next_level(), "kills": run.kills, "loadout": run.loadout,
		"backpack": run.backpack_snapshot(),
		"dash": dash_snapshot(),
		"pulse": pulse_snapshot(),
		"skills": active_skill_snapshots(),
		"hero_skill": hero_skill_snapshot(),
		"hero_effects": hero_effects_snapshot(),
		"enemy_conditions": enemy_conditions_snapshot(),
		"weapon_effects": weapon_effects.snapshot(),
		"pinball": pinball_snapshot(),
		"boss_encounter": boss_encounter_snapshot(),
		"boss_health": boss.health if boss != null and boss.active else 0.0,
		"boss_max_health": boss.max_health if boss != null else 0.0,
	}

func populate_stress() -> void:
	sandbox = true
	for index: int in 300:
		var enemy: Enemy = spawn_enemy("chaser", Vector2(rng.randf_range(100, 1180), rng.randf_range(150, 610)))
		enemy.health = 100000000.0
		enemy.max_health = enemy.health
	for index: int in 600:
		var shot: Shot = fire_weapon("ember", "", Vector2(rng.randf_range(100, 1180), rng.randf_range(150, 610)), Vector2.from_angle(rng.randf() * TAU))
		shot.damage = 0.0
		shot.life = 1000000.0
	for index: int in 200:
		_drop_soul(Vector2(rng.randf_range(100, 1180), rng.randf_range(150, 610)), 1)
