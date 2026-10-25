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
signal ended(victory: bool, reason: String)

const ARENA: Rect2 = Rect2(66, 140, 1148, 450)
const CELL: float = 80.0
const ENEMY_LIMIT: int = 340
const SHOT_LIMIT: int = 1600
const DROP_LIMIT: int = 420
const RUSHER_WINDUP: float = 0.65
const CASTER_WINDUP: float = 0.45

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
	var hurt_timer: float = 0.0
	var charge_direction: Vector2 = Vector2.ZERO
	var mode: int = 0
	var radius: float = 16.0

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
	var remaining: int = 0
	var innate_remaining: int = 0
	var return_after: float = 0.0
	var return_speed: float = 0.0
	var returning: bool = false
	var return_cancelled: bool = false
	var hit_ids: Dictionary = {}
	var homing: float = 0.0
	var slow: float = 0.0
	var hostile: bool = false
	var color: Color = Color.WHITE

class Soul:
	var active: bool = false
	var slot: int = 0
	var position: Vector2 = Vector2.ZERO
	var value: int = 1
	var age: float = 0.0

class WarningZone:
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
var player_position: Vector2 = ARENA.get_center()
var player_velocity: Vector2 = Vector2.ZERO
var player_direction: Vector2 = Vector2.RIGHT
var invulnerability: float = 0.0
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
var primary_hits: int = 0
var secondary_hits: int = 0
var damage_by_weapon: Dictionary = {}
var _enemy_free: Array[int] = []
var _shot_free: Array[int] = []
var _soul_free: Array[int] = []
var _grid: Dictionary = {}
var _largest_enemy_radius: float = 0.0
var _explosion_grid_active: bool = false
var _cooldowns: Array[float] = []
var _uid: int = 0
var _spawn_timer: float = 0.0
var _wave: ContentDef
var _boss_cycle: int = 0
var sandbox: bool = false

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
	rng.seed = int(run.rng.randi())
	_wave = GameCatalog.wave(run.wave)
	duration = _wave.duration
	player_position = ARENA.get_center()
	_cooldowns.clear()
	for index: int in run.loadout.size():
		_cooldowns.append(float(index) * 0.14)
	if _wave.boss_wave:
		boss = spawn_enemy("boss", Vector2(640, 208))
		boss.action_timer = 2.5
	_spawn_timer = 0.6

func step(delta: float, movement: Vector2) -> void:
	_explosion_grid_active = false
	if complete:
		return
	elapsed += delta
	run.elapsed += delta
	invulnerability = maxf(0.0, invulnerability - delta)
	player_velocity = movement.limit_length() * run.stat("move_speed")
	player_position = clamp_point(player_position + player_velocity * delta, 16.0)
	if movement.length_squared() > 0.01:
		player_direction = movement.normalized()
	_update_enemies(delta)
	if run.health <= 0.0:
		_finish(false, _death_reason())
		return
	_rebuild_grid()
	_explosion_grid_active = true
	_update_weapons(delta)
	_update_shots(delta)
	_explosion_grid_active = false
	if complete:
		return
	_update_souls(delta)
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
			_spawn_timer += _wave.spawn_interval
		if elapsed >= duration:
			if _wave.boss_wave:
				_finish(false, "仪式已经完成。请在 90 秒内击败无面祭司。")
			else:
				collect_remaining_souls()
				_finish(true, "邪潮暂歇")

func spawn_enemy(id: String, position: Vector2 = Vector2.INF) -> Enemy:
	if _enemy_free.is_empty():
		return null
	_explosion_grid_active = false
	var enemy: Enemy = enemies[_enemy_free.pop_back()]
	enemy.active = true
	enemy.definition = GameCatalog.enemy(id)
	enemy.position = _edge_position() if position == Vector2.INF else position
	enemy.velocity = Vector2.ZERO
	_uid += 1
	enemy.uid = _uid
	var scaling: float = 1.0 if id == "boss" else 1.0 + 0.17 * float(run.wave - 1)
	enemy.max_health = enemy.definition.health * scaling
	enemy.health = enemy.max_health
	enemy.radius = enemy.definition.radius
	enemy.age = 0.0
	enemy.action_timer = rng.randf_range(1.0, 2.5)
	enemy.mode = 0
	enemy.slow_timer = 0.0
	enemy.slow_factor = 1.0
	enemy.hurt_timer = 0.0
	enemy_count += 1
	return enemy

func _edge_position() -> Vector2:
	var point: Vector2
	match rng.randi_range(0, 3):
		0: point = Vector2(ARENA.position.x, rng.randf_range(ARENA.position.y, ARENA.end.y))
		1: point = Vector2(ARENA.end.x, rng.randf_range(ARENA.position.y, ARENA.end.y))
		2: point = Vector2(rng.randf_range(ARENA.position.x, ARENA.end.x), ARENA.position.y)
		_: point = Vector2(rng.randf_range(ARENA.position.x, ARENA.end.x), ARENA.end.y)
	# Spawning never creates an unavoidable contact hit at a boundary.
	if point.distance_squared_to(player_position) < 180.0 * 180.0:
		point = ARENA.get_center() * 2.0 - point
	return point

func _spawn_wave_group() -> void:
	var count: int = 2 + int(run.wave / 2)
	if _wave.boss_wave:
		count = 2 if boss != null and boss.health > boss.max_health * 0.5 else 3
	for index: int in count:
		if enemy_count >= _wave.cap:
			break
		var roll: float = rng.randf()
		var total: float = 0.0
		var selected: String = "chaser"
		for id: String in _wave.spawn_weights:
			total += float(_wave.spawn_weights[id])
			if roll <= total:
				selected = id
				break
		spawn_enemy(selected)

func _update_enemies(delta: float) -> void:
	for enemy: Enemy in enemies:
		if complete:
			return
		if not enemy.active:
			continue
		enemy.age += delta
		enemy.action_timer -= delta
		enemy.hurt_timer = maxf(0.0, enemy.hurt_timer - delta)
		enemy.slow_timer = maxf(0.0, enemy.slow_timer - delta)
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
				_hostile_shot(enemy.position, aim * enemy.definition.projectile_speed, enemy.definition.damage, id)
				enemy.action_timer = enemy.definition.cooldown
				enemy.mode = 0
		if id != "boss":
			if enemy.slow_timer > 0.0:
				speed *= enemy.slow_factor
			# A small deterministic orbit separates packs without an O(n²) rigid-body solver.
			var side: float = sin(float(enemy.uid) * 2.39996 + enemy.age * 0.35) * 0.24
			enemy.velocity = direction.rotated(side) * speed
			enemy.position = clamp_point(enemy.position + enemy.velocity * delta)
		if distance < enemy.radius + 13.0 and invulnerability <= 0.0:
			var contact_origin: Vector2 = enemy.position
			# Retreat/charge movement can point away from the player; recoil is radial.
			var recoil_direction: Vector2 = (contact_origin - player_position).normalized()
			enemy.position = clamp_point(contact_origin + recoil_direction * 18.0)
			_hurt_player(enemy.definition.damage * (1.0 + 0.09 * float(run.wave - 1)), id, "contact", contact_origin)

func _update_boss(enemy: Enemy, direction: Vector2, delta: float) -> void:
	var target: Vector2 = Vector2(640, 320) + Vector2(sin(enemy.age * 0.35) * 220.0, cos(enemy.age * 0.25) * 100.0)
	var displacement: Vector2 = target - enemy.position
	var speed: float = enemy.definition.speed
	if enemy.slow_timer > 0.0:
		speed *= enemy.slow_factor
	enemy.position += displacement.limit_length(speed * delta)
	if enemy.action_timer > 0.0:
		return
	_boss_cycle += 1
	var phase_two: bool = enemy.health < enemy.max_health * 0.5
	match _boss_cycle % 3:
		0:
			var number: int = 14 if phase_two else 10
			for index: int in number:
				var angle: float = TAU * float(index) / float(number) + enemy.age * 0.3
				_hostile_shot(enemy.position, Vector2.from_angle(angle) * 145.0, 14.0, enemy.definition.id)
		1:
			for offset: int in 3:
				var zone: WarningZone = WarningZone.new()
				zone.source_id = enemy.definition.id
				zone.position = clamp_point(player_position + Vector2(float(offset - 1) * 110.0, float(offset % 2) * 65.0), 80.0)
				zone.radius = 64.0
				zone.damage = 20.0
				zones.append(zone)
		2:
			for index: int in 5:
				_hostile_shot(enemy.position, direction.rotated(float(index - 2) * 0.17) * 195.0, 13.0, enemy.definition.id)
			for index: int in (4 if phase_two else 2):
				spawn_enemy("chaser", clamp_point(enemy.position + Vector2.from_angle(float(index) * 2.4) * 100.0))
	enemy.action_timer = 1.8 if phase_two else 2.6

func _rebuild_grid() -> void:
	_largest_enemy_radius = 0.0
	for key: Vector2i in _grid:
		(_grid[key] as Array).clear()
	for enemy: Enemy in enemies:
		if not enemy.active:
			continue
		_largest_enemy_radius = maxf(_largest_enemy_radius, enemy.radius)
		var cell: Vector2i = Vector2i((enemy.position / CELL).floor())
		if not _grid.has(cell):
			_grid[cell] = []
		(_grid[cell] as Array).append(enemy)

func _nearest(position: Vector2, distance: float, excluded: Dictionary = {}) -> Enemy:
	# Outside the stable shot-phase window, keep direct/stale-grid calls unchanged.
	# Very wide or non-finite diagnostic queries also favor the bounded pool scan.
	if not _explosion_grid_active or not position.is_finite() or not is_finite(distance) or absf(distance) > CELL * 16.0:
		return _nearest_linear(position, distance, excluded)
	if distance == 0.0:
		return null
	var result: Enemy
	var best: float = distance * distance
	var center: Vector2i = Vector2i((position / CELL).floor())
	var max_ring: int = int(floorf(absf(distance) / CELL)) + 1
	for ring: int in range(max_ring + 1):
		var side: int = ring * 2
		var count: int = 1 if ring == 0 else ring * 8
		for index: int in count:
			var cell: Vector2i = center
			if ring > 0:
				var offset: int = index % side
				match int(index / side):
					0: cell += Vector2i(-ring + offset, -ring)
					1: cell += Vector2i(ring, -ring + offset)
					2: cell += Vector2i(ring - offset, ring)
					3: cell += Vector2i(-ring, ring - offset)
			if not _grid.has(cell):
				continue
			for enemy: Enemy in _grid[cell]:
				if not enemy.active or excluded.has(enemy.uid):
					continue
				var squared: float = enemy.position.distance_squared_to(position)
				if squared < best or (result != null and squared == best and enemy.slot < result.slot):
					best = squared
					result = enemy
		var left: float = float(center.x - ring) * CELL
		var top: float = float(center.y - ring) * CELL
		var right: float = float(center.x + ring + 1) * CELL
		var bottom: float = float(center.y + ring + 1) * CELL
		var edge: float = maxf(0.0, minf(minf(position.x - left, right - position.x), minf(position.y - top, bottom - position.y)))
		# Match Vector2's distance precision, and only prune conservatively. Selection
		# ties above stay exact; a next-ring equal-distance lower slot must still win.
		var lower_bound: float = Vector2(edge, 0.0).length_squared()
		if lower_bound > best and not is_equal_approx(lower_bound, best):
			break
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
		var target: Enemy = _nearest(player_position, definition.range)
		if target == null:
			_cooldowns[index] = 0.08
			continue
		var rune_entry: Dictionary = equipped.get("rune", {})
		var rune: String = str(rune_entry.get("id", ""))
		var angle: float = (target.position - player_position).angle()
		for pellet: int in definition.shots:
			var offset: float = (float(pellet) - float(definition.shots - 1) * 0.5) * definition.spread
			fire_weapon(str(equipped["id"]), rune, player_position, Vector2.from_angle(angle + offset), int(equipped.get("rank", 1)), int(rune_entry.get("rank", 1)))
		_cooldowns[index] = definition.cooldown / run.stat("attack_speed")
		shot_fired.emit()

func fire_weapon(weapon_id: String, rune_id: String, position: Vector2, direction: Vector2, weapon_rank: int = 1, rune_rank: int = 1) -> Shot:
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
	shot.damage = definition.damage * run.stat("damage") * BackpackInventory.rank_multiplier(shot.weapon_rank)
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
	shot.remaining = 0
	shot.innate_remaining = 0
	shot.weapon_rank = 1
	shot.rune_rank = 1
	shot.return_after = 0.0
	shot.return_speed = 0.0
	shot.returning = false
	shot.return_cancelled = false
	shot.attacker_id = ""
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
			var target: Enemy = _nearest(shot.position, 420.0, shot.hit_ids)
			if target != null:
				var speed: float = shot.velocity.length()
				var desired: Vector2 = (target.position - shot.position).normalized()
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
		while impact != null and shot.active and hit_count < hit_limit:
			hit_count += 1
			shot.hit_ids[impact.uid] = true
			var impact_position: Vector2 = impact.position
			var health_before: float = impact.health
			var incoming_direction: Vector2 = shot.velocity.normalized()
			apply_damage(impact, shot.damage, shot.source, false, shot.slow)
			var positive_hit: bool = impact.health < health_before
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

func _first_collision(shot: Shot) -> Enemy:
	var result: Enemy
	var nearest_t: float = INF
	var padding: float = shot.radius + _largest_enemy_radius
	var start: Vector2i = Vector2i(((shot.previous.min(shot.position) - Vector2.ONE * padding) / CELL).floor())
	var end: Vector2i = Vector2i(((shot.previous.max(shot.position) + Vector2.ONE * padding) / CELL).floor())
	for x: int in range(start.x, end.x + 1):
		for y: int in range(start.y, end.y + 1):
			var key: Vector2i = Vector2i(x, y)
			if not _grid.has(key):
				continue
			var bucket: Array = _grid[key]
			for enemy: Enemy in bucket:
				if not enemy.active or shot.hit_ids.has(enemy.uid):
					continue
				var radius: float = enemy.radius + shot.radius
				var t: float = _swept_circle_entry_t(shot.previous, shot.position, enemy.position, radius)
				if t < nearest_t:
					nearest_t = t
					result = enemy
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

func apply_damage(enemy: Enemy, amount: float, source: String, secondary: bool = false, slow: float = 0.0) -> void:
	if complete or not enemy.active:
		return
	var actual: float = minf(enemy.health, maxf(0.0, amount))
	if actual <= 0.0:
		return
	enemy.health -= actual
	enemy.hurt_timer = 0.10
	if slow > 0.0:
		enemy.slow_timer = 1.5
		enemy.slow_factor = 1.0 - slow
	damage_by_weapon[source] = float(damage_by_weapon.get(source, 0.0)) + actual
	run.damage_dealt_by_weapon[source] = float(run.damage_dealt_by_weapon.get(source, 0.0)) + actual
	if secondary:
		secondary_hits += 1
	else:
		primary_hits += 1
	damage_dealt.emit(enemy.position, actual, source, secondary, enemy.uid)
	enemy_hit.emit()
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

func _explosion_slots(position: Vector2, radius: float = RuneRules.BLAST_RADIUS) -> PackedInt32Array:
	var slots: PackedInt32Array = PackedInt32Array()
	# Only this step's shot phase has stable positions/radii. Direct calls may follow
	# external edits or an empty/stale grid, so retain their original full scan.
	if not _explosion_grid_active:
		for index: int in enemies.size():
			slots.append(index)
		return slots
	var reach: Vector2 = Vector2.ONE * (radius + _largest_enemy_radius)
	var start: Vector2i = Vector2i(((position - reach) / CELL).floor())
	var end: Vector2i = Vector2i(((position + reach) / CELL).floor())
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
	return slots

func _kill_enemy(enemy: Enemy) -> void:
	enemy.active = false
	enemy_count -= 1
	_enemy_free.append(enemy.slot)
	run.kills += 1
	var value: int = 3 if enemy.definition.id == "tank" else 1
	_drop_soul(enemy.position, value)
	add_effect(enemy.position, enemy.definition.color, enemy.radius + 6.0, 0.25, 2)
	enemy_killed.emit(enemy.position, enemy.definition.color)
	if enemy == boss:
		collect_remaining_souls()
		_finish(true, "无面祭司已被击败。你的余烬仍在燃烧。")

func _drop_soul(position: Vector2, value: int) -> void:
	if _soul_free.is_empty():
		# Capacity pressure must not delete earned currency or experience.
		run.collect_souls(value)
		return
	var soul: Soul = souls[_soul_free.pop_back()]
	soul.active = true
	soul.position = position
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

func _update_zones(delta: float) -> void:
	for index: int in range(zones.size() - 1, -1, -1):
		if complete:
			return
		var zone: WarningZone = zones[index]
		zone.age += delta
		if zone.age >= zone.delay and not zone.triggered:
			zone.triggered = true
			add_effect(zone.position, Color("ff705c"), zone.radius, 0.4)
			if zone.position.distance_to(player_position) < zone.radius + 10.0:
				_hurt_player(zone.damage, zone.source_id, "ritual", zone.position)
		if zone.age > zone.delay + 0.3:
			zones.remove_at(index)

func _hurt_player(amount: float, source_id: String = "enemy", kind: String = "contact", origin: Vector2 = Vector2.INF) -> void:
	if complete or invulnerability > 0.0 or run.health <= 0.0:
		return
	var actual: float = run.take_damage(amount, source_id, kind)
	if actual <= 0.0:
		return
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
	victory = won
	end_reason = reason
	ended.emit(won, reason)

func snapshot() -> Dictionary:
	return {
		"health": run.health, "max_health": run.stat("max_health"), "wave": run.wave,
		"time_left": maxf(0.0, duration - elapsed), "gold": run.gold, "level": run.level,
		"xp": run.xp, "xp_needed": run.xp_to_next_level(), "kills": run.kills, "loadout": run.loadout,
		"backpack": run.backpack_snapshot(),
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
