class_name CombatWorld
extends Node2D

signal wave_ended(victory: bool, reason: String)
signal hud_changed(snapshot: Dictionary)

var sim: CombatSim
var active: bool = false
var sound: SoundBank
var settings: Dictionary = {"shake": true, "flash": true}
var textures: Dictionary = {}
var arena_texture: Texture2D
var soul_texture: Texture2D
var glow_texture: Texture2D
var seal_texture: Texture2D
var _hud_clock: float = 0.0
var _shake: float = 0.0
var _visual_time: float = 0.0
var _last_kills: int = 0
var autopilot: bool = false
var stress_mode: bool = false
var benchmark_time_left: float = 0.0

const NUMBER_LIMIT: int = 48

class FloatingNumber:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var amount: float = 0.0
	var text: String = ""
	var text_width: float = 0.0
	var source: String = ""
	var target_uid: int = -1
	var color: Color = Color.WHITE
	var life: float = 0.0
	var total: float = 0.6
	var player_hit: bool = false
	var font_size: int = 16

var _number_pool: Array[FloatingNumber] = []
var _number_free: Array[FloatingNumber] = []
var _numbers: Array[FloatingNumber] = []
var _number_font: Font
var _feedback_serial: int = 0
var _damage_flash: float = 0.0
var _damage_direction: Vector2 = Vector2.ZERO

class TrailBatch:
	var points: PackedVector2Array = PackedVector2Array()
	var wings: PackedVector2Array = PackedVector2Array()
	var color: Color = Color.WHITE
	var width: float = 3.0

var _trail_batches: Dictionary = {}

func _init() -> void:
	for index: int in NUMBER_LIMIT:
		_number_pool.append(FloatingNumber.new())
	_reset_feedback()

func _ready() -> void:
	_number_font = ThemeDB.fallback_font
	arena_texture = load("res://assets/arena.svg")
	soul_texture = load("res://assets/icons/soul.svg")
	glow_texture = load("res://assets/fx/glow.svg")
	seal_texture = load("res://assets/fx/seal.svg")
	for id: String in ["player", "chaser", "rusher", "tank", "caster", "boss"]:
		textures[id] = load("res://assets/sprites/%s.svg" % id)
	for definition: ContentDef in GameCatalog.weapons():
		textures[definition.id] = load("res://assets/icons/%s.svg" % definition.icon)
	queue_redraw()

func begin(state: RunState) -> void:
	sim = CombatSim.new()
	sim.begin(state)
	sim.ended.connect(_on_ended)
	sim.shot_fired.connect(func() -> void: sound.play("shoot", -24.0))
	sim.enemy_hit.connect(func() -> void: sound.play("hit", -24.0))
	sim.enemy_killed.connect(func(_position: Vector2, _color: Color) -> void: sound.play("death", -22.0))
	sim.player_hurt.connect(_on_player_hurt)
	sim.damage_dealt.connect(_on_damage_dealt)
	sim.player_damaged.connect(_on_player_damaged)
	_reset_feedback()
	active = true
	_last_kills = state.kills
	_hud_clock = 0.0
	_shake = 0.0
	position = Vector2.ZERO
	hud_changed.emit(hud_snapshot())
	queue_redraw()

func stop() -> void:
	active = false
	_reset_feedback()
	position = Vector2.ZERO
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not active or sim == null:
		return
	_visual_time += delta
	_advance_feedback(delta)
	var movement: Vector2 = _movement()
	if autopilot:
		movement = BotPolicy.movement(sim)
	sim.step(delta, movement)
	if stress_mode:
		_maintain_stress()
	_hud_clock += delta
	if _hud_clock >= 0.1:
		_hud_clock = 0.0
		hud_changed.emit(hud_snapshot())
	_shake = maxf(0.0, _shake - delta * 22.0)
	if bool(settings.get("shake", true)) and _shake > 0.0:
		position = Vector2(sin(_visual_time * 99.0), cos(_visual_time * 83.0)) * _shake
	else:
		position = Vector2.ZERO
	queue_redraw()

func _movement() -> Vector2:
	var value: Vector2 = Vector2.ZERO
	value.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	value.y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	return value.limit_length()

func _on_player_hurt() -> void:
	_shake = 4.0
	sound.play("hurt", -7.0)
	hud_changed.emit(hud_snapshot())

func _on_damage_dealt(point: Vector2, amount: float, source: String, secondary: bool, target_uid: int = -1) -> void:
	_spawn_number(point + Vector2(0, -22), amount, source, false, secondary, target_uid)

func _on_player_damaged(amount: float, _source_id: String, _kind: String, origin: Vector2) -> void:
	_spawn_number(sim.player_position + Vector2(0, -40), amount, "player", true, false)
	_damage_flash = 0.22
	_damage_direction = (origin - sim.player_position).normalized() if origin.is_finite() else Vector2.ZERO

func _reset_feedback() -> void:
	_numbers.clear()
	_number_free.clear()
	for number: FloatingNumber in _number_pool:
		number.life = 0.0
		_number_free.append(number)
	_feedback_serial = 0
	_damage_flash = 0.0
	_damage_direction = Vector2.ZERO

func _spawn_number(point: Vector2, amount: float, source: String, player_hit: bool, secondary: bool, target_uid: int = -1) -> void:
	if amount <= 0.0:
		return
	# Merge near-simultaneous hits at the same target instead of covering packs in text.
	for number: FloatingNumber in _numbers:
		if number.player_hit == player_hit and number.source == source and number.target_uid == target_uid and number.total - number.life < 0.075 and number.position.distance_squared_to(point) < 24.0 * 24.0:
			number.amount += amount
			_update_number_text(number)
			return
	# Keep room for incoming damage even while many enemies are hit together.
	if _number_free.is_empty() or (not player_hit and _number_free.size() <= 4):
		return
	var number: FloatingNumber = _number_free.pop_back()
	number.position = point
	number.amount = amount
	number.source = source
	number.target_uid = target_uid
	number.player_hit = player_hit
	number.total = 0.75 if player_hit else 0.6
	number.life = number.total
	number.font_size = 21 if player_hit else (13 if secondary else 16)
	number.color = Color("ffb39a") if player_hit else (Color("c7a9e1") if secondary else Color("f2e6c9"))
	_update_number_text(number)
	_feedback_serial += 1
	number.velocity = Vector2(sin(float(_feedback_serial) * 2.39996) * 12.0, -32.0 if player_hit else -24.0)
	# Render incoming loss after outgoing damage even when later attacks arrive nearby.
	var insertion: int = _numbers.size()
	if not player_hit:
		for index: int in _numbers.size():
			if _numbers[index].player_hit:
				insertion = index
				break
	_numbers.insert(insertion, number)

func _update_number_text(number: FloatingNumber) -> void:
	number.text = _damage_text(number.amount, number.player_hit)
	number.text_width = _number_font.get_string_size(number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size).x if _number_font != null else float(number.text.length() * number.font_size) * 0.6

static func _damage_text(amount: float, player_hit: bool) -> String:
	var value: String = str(roundi(amount)) if is_equal_approx(amount, roundf(amount)) else "%.1f" % amount
	return ("−" if player_hit else "") + value

func _advance_feedback(delta: float) -> void:
	_damage_flash = maxf(0.0, _damage_flash - delta)
	for index: int in range(_numbers.size() - 1, -1, -1):
		var number: FloatingNumber = _numbers[index]
		number.life -= delta
		if number.life <= 0.0:
			_numbers.remove_at(index)
			_number_free.append(number)
		else:
			number.position += number.velocity * delta

func _on_ended(victory: bool, reason: String) -> void:
	active = false
	hud_changed.emit(hud_snapshot())
	wave_ended.emit(victory, reason)

func hud_snapshot() -> Dictionary:
	var value: Dictionary = sim.snapshot()
	if stress_mode:
		value["benchmark"] = true
		value["time_left"] = benchmark_time_left
		value["enemies"] = sim.enemy_count
		value["projectiles"] = sim.shot_count
	return value

func _draw() -> void:
	if arena_texture != null:
		draw_texture_rect(arena_texture, Rect2(Vector2.ZERO, Vector2(1280, 720)), false)
	if sim == null:
		return
	_draw_atmosphere()
	_draw_souls()
	_draw_enemies()
	_draw_friendly_shots()
	_draw_player()
	_draw_effects()
	_draw_feedback()
	# Hostile projectiles and telegraphs stay above all friendly spell effects.
	_draw_danger()

func _draw_feedback() -> void:
	if _number_font != null:
		for number: FloatingNumber in _numbers:
			var alpha: float = minf(1.0, number.life / 0.24)
			var point: Vector2 = number.position - Vector2(number.text_width * 0.5, 0)
			draw_string_outline(_number_font, point, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size, 3, Color(0.025, 0.035, 0.06, alpha * 0.9))
			draw_string(_number_font, point, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size, Color(number.color, alpha))
	if _damage_flash > 0.0 and bool(settings.get("flash", true)):
		var alpha: float = _damage_flash / 0.22
		var center: Vector2 = sim.player_position + Vector2(0, -8)
		draw_arc(center, 29.0, 0.0, TAU, 24, Color(1.0, 0.47, 0.34, alpha * 0.5), 2.0, true)
		if _damage_direction.length_squared() > 0.1:
			var tangent: Vector2 = _damage_direction.orthogonal() * 6.0
			var tip: Vector2 = center + _damage_direction * 25.0
			var base: Vector2 = center + _damage_direction * 38.0
			draw_colored_polygon(PackedVector2Array([tip, base + tangent, base - tangent]), Color(1.0, 0.63, 0.48, alpha * 0.8))

func _draw_atmosphere() -> void:
	# Analytic motion keeps atmosphere cosmetic and out of the simulation RNG.
	for index: int in 22:
		var phase: float = float(index) * 2.39996
		var point := Vector2(
			90.0 + fposmod(float(index) * 127.3 + sin(_visual_time * 0.12 + phase) * 19.0, 1100.0),
			150.0 + fposmod(float(index) * 73.7 - _visual_time * (2.0 + float(index % 3)), 420.0))
		var alpha: float = 0.07 + (sin(_visual_time * 0.7 + phase) + 1.0) * 0.035
		draw_circle(point, 1.0 if index % 3 else 1.5, Color(0.78, 0.67, 0.50, alpha))
	if sim.boss != null and sim.boss.active:
		var pulse: float = 0.32 + sin(_visual_time * 1.5) * 0.05
		draw_texture_rect(glow_texture, Rect2(sim.boss.position - Vector2(110, 100), Vector2(220, 180)), false, Color(0.73, 0.59, 0.85, pulse))

func _draw_souls() -> void:
	for soul: CombatSim.Soul in sim.souls:
		if not soul.active:
			continue
		var size: float = 12.0 if soul.value == 1 else 17.0
		var offset: Vector2 = Vector2(0, sin(soul.age * 3.0 + float(soul.slot)) * 2.0)
		draw_texture_rect(soul_texture, Rect2(soul.position + offset - Vector2.ONE * size * 0.5, Vector2.ONE * size), false)

func _draw_enemies() -> void:
	# Grouping textures preserves renderer batching even with hundreds of opponents.
	for id: String in ["chaser", "rusher", "tank", "caster", "boss"]:
		var texture: Texture2D = textures[id]
		for enemy: CombatSim.Enemy in sim.enemies:
			if not enemy.active or enemy.definition.id != id:
				continue
			var size: float = enemy.radius * 3.0 + 15.0
			var stride: float = sin(enemy.age * (9.0 if id == "rusher" else 4.0) + float(enemy.uid))
			var bob: float = stride * (1.0 if id == "tank" else 2.0)
			var breathing: float = sin(enemy.age * 2.0 + float(enemy.uid)) * 0.015
			var width: float = size * (1.0 + breathing)
			var tint: Color = Color.WHITE
			if enemy.slow_timer > 0.0:
				tint = Color("b4e9ed")
			if enemy.hurt_timer > 0.0 and bool(settings.get("flash", true)):
				tint = Color(1.7, 1.5, 1.5, 1.0)
			draw_texture_rect(texture, Rect2(enemy.position + Vector2(-width * 0.5, -size * 0.66 + bob), Vector2(width, size)), false, tint)
			if id == "tank" and enemy.health < enemy.max_health:
				var origin: Vector2 = enemy.position + Vector2(-17, -size * 0.55)
				draw_line(origin, origin + Vector2(34, 0), Color("242533"), 3.0)
				draw_line(origin, origin + Vector2(34.0 * enemy.health / enemy.max_health, 0), Color("a9a7a3"), 2.0)

func _draw_friendly_shots() -> void:
	for batch: TrailBatch in _trail_batches.values():
		batch.points.clear()
		batch.wings.clear()
	for shot: CombatSim.Shot in sim.shots:
		if not shot.active or shot.hostile:
			continue
		var direction: Vector2 = shot.velocity.normalized()
		var trail_length: float = 25.0 if shot.source == "frost" else 18.0
		if shot.source == "scatter":
			trail_length = 9.0
		var tail: Vector2 = shot.position - direction * trail_length
		var color: Color = shot.color
		if shot.source == "ember":
			# Friendly fire stays pale gold; hostile rounds retain saturated coral.
			color = Color("dab779")
		if shot.rune == "blast":
			color = color.lerp(Color("dca0fa"), 0.35)
		if shot.source == "ember":
			draw_circle(shot.position, shot.radius * 2.0, Color(color, 0.10))
			draw_line(tail - direction * 6.0, shot.position, Color(color, 0.4), shot.radius * 1.2, true)
			draw_circle(shot.position, shot.radius, color)
			draw_circle(shot.position, shot.radius * 0.4, Color("f8efe2"))
		else:
			var key: String = shot.source + ":" + shot.rune
			if not _trail_batches.has(key):
				_trail_batches[key] = TrailBatch.new()
			var batch: TrailBatch = _trail_batches[key]
			batch.color = color
			batch.width = shot.radius * 1.2
			batch.points.append(tail)
			batch.points.append(shot.position)
			if shot.rune == "pierce" or shot.source == "frost":
				var wing: Vector2 = direction.orthogonal() * 3.0
				batch.wings.append(tail + wing)
				batch.wings.append(shot.position + direction * 5.0)
				batch.wings.append(tail - wing)
				batch.wings.append(shot.position + direction * 5.0)
			draw_circle(shot.position, shot.radius * 0.55, Color("f5efe0"))
		if shot.rune == "bounce":
			draw_arc(shot.position, shot.radius + 3.0, 0.0, TAU, 8, Color("c7b0f3"), 1.0, true)
		elif shot.rune == "pierce" and shot.source == "ember":
			var wing: Vector2 = direction.orthogonal() * 3.0
			draw_line(tail + wing, shot.position + direction * 5.0, Color(color, 0.65), 1.0, true)
			draw_line(tail - wing, shot.position + direction * 5.0, Color(color, 0.65), 1.0, true)
	# One multiline command per visual family replaces thousands of individual trails.
	for batch: TrailBatch in _trail_batches.values():
		if batch.points.is_empty():
			continue
		draw_multiline(batch.points, Color(batch.color, 0.20), batch.width * 2.33, true)
		draw_multiline(batch.points, batch.color, batch.width, true)
		if not batch.wings.is_empty():
			draw_multiline(batch.wings, Color(batch.color, 0.65), 1.0, true)

func _draw_player() -> void:
	var center: Vector2 = sim.player_position
	var bob: float = sin(_visual_time * 9.0) * minf(2.0, sim.player_velocity.length() * 0.012)
	draw_texture_rect(glow_texture, Rect2(center - Vector2(44, 34), Vector2(88, 70)), false, Color(0.89, 0.78, 1.0, 0.35))
	draw_set_transform(center + Vector2(0, 9), 0.0, Vector2(1.0, 0.48))
	draw_texture_rect(seal_texture, Rect2(-Vector2.ONE * 32.0, Vector2.ONE * 64.0), false, Color(1.0, 0.95, 0.85, 0.55 + sin(_visual_time * 1.6) * 0.08))
	draw_set_transform(Vector2.ZERO)
	var tint: Color = Color.WHITE
	if sim.invulnerability > 0.0 and bool(settings.get("flash", true)):
		tint.a = 0.55 + sin(_visual_time * 35.0) * 0.30
	var lean: float = clampf(sim.player_velocity.x * 0.0002, -0.045, 0.045)
	draw_set_transform(center, lean)
	draw_texture_rect(textures["player"], Rect2(Vector2(-34, -50 + bob), Vector2(68, 68)), false, tint)
	draw_set_transform(Vector2.ZERO)
	for index: int in sim.run.loadout.size():
		var equipped: Dictionary = sim.run.loadout[index]
		var angle: float = -PI * 0.75 + float(index) * PI * 0.5 + sin(_visual_time * 0.6) * 0.12
		var orbit: Vector2 = center + Vector2.from_angle(angle) * 39.0 + Vector2(0, sin(_visual_time * 2.0 + float(index)) * 3.0)
		var definition: ContentDef = GameCatalog.weapon(str(equipped["id"]))
		draw_circle(orbit, 14.0, Color(definition.color, 0.07))
		draw_texture_rect(textures[str(equipped["id"])], Rect2(orbit - Vector2(12, 12), Vector2(24, 24)), false)
		var rune: Dictionary = equipped.get("rune", {})
		if not rune.is_empty():
			var rune_color: Color = GameCatalog.rune(str(rune["id"])).color
			draw_arc(orbit, 15.0, _visual_time * 0.5, _visual_time * 0.5 + PI * 1.4, 12, Color(rune_color, 0.65), 1.0, true)

func _draw_effects() -> void:
	for effect: CombatSim.Effect in sim.effects:
		var progress: float = 1.0 - effect.life / effect.total
		var color: Color = effect.color
		color.a = (1.0 - progress) * 0.65
		if effect.kind == 0:
			draw_circle(effect.position, effect.radius * (0.5 + progress * 0.5), Color(color, color.a * 0.08))
			draw_arc(effect.position, effect.radius * (0.3 + progress * 0.7), 0, TAU, 28, color, 2.5 * (1.0 - progress) + 0.5, true)
			draw_arc(effect.position, effect.radius * (0.12 + progress * 0.55), 0, TAU, 20, Color(color, color.a * 0.45), 1.0, true)
		elif effect.kind == 1:
			draw_arc(effect.position, effect.radius * (0.7 + progress * 0.7), 0, TAU, 12, color, 1.5, true)
			var ray: float = effect.radius * (0.3 + progress * 0.3)
			draw_line(effect.position - Vector2(ray, 0), effect.position + Vector2(ray, 0), Color(color, color.a * 0.65), 1.0, true)
		else:
			for index: int in 5:
				var direction: Vector2 = Vector2.from_angle(float(index) * TAU / 5.0)
				var point: Vector2 = effect.position + direction * effect.radius * progress
				draw_line(point, point + direction * 5.0 * (1.0 - progress), color, 2.0, true)

func _draw_danger() -> void:
	for shot: CombatSim.Shot in sim.shots:
		if not shot.active or not shot.hostile:
			continue
		draw_circle(shot.position, shot.radius + 3.0, Color("542e35"))
		draw_circle(shot.position, shot.radius, Color("ff8666"))
		draw_arc(shot.position, shot.radius, 0, TAU, 12, Color("ffdfb1"), 1.5, true)
		draw_circle(shot.position, 2.5, Color("fff2d7"))
	for zone: CombatSim.WarningZone in sim.zones:
		if zone.triggered:
			continue
		var progress: float = minf(1.0, zone.age / zone.delay)
		draw_circle(zone.position, zone.radius, Color(0.9, 0.22, 0.16, 0.10 + progress * 0.06))
		draw_arc(zone.position, zone.radius, 0, TAU, 40, Color("b85246"), 1.3, true)
		draw_arc(zone.position, zone.radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, Color("ffbe88"), 3.0, true)
		for index: int in 8:
			var direction: Vector2 = Vector2.from_angle(float(index) * TAU / 8.0)
			draw_line(zone.position + direction * (zone.radius - 4.0), zone.position + direction * (zone.radius + 3.0), Color("efaa7c"), 1.3, true)
		draw_line(zone.position - Vector2(8, 0), zone.position + Vector2(8, 0), Color("ffb68a"), 1.0, true)
		draw_line(zone.position - Vector2(0, 8), zone.position + Vector2(0, 8), Color("ffb68a"), 1.0, true)
	for enemy: CombatSim.Enemy in sim.enemies:
		if not enemy.active:
			continue
		if enemy.definition.id == "rusher" and enemy.mode == 1:
			var end: Vector2 = enemy.position + enemy.charge_direction * 130.0
			draw_line(enemy.position, end, Color(1.0, 0.45, 0.30, 0.45), 8.0, true)
			draw_line(enemy.position, end, Color("ffd6a6"), 1.5, true)
		elif enemy.definition.id == "caster" and enemy.mode == 1:
			draw_arc(enemy.position + Vector2(0, -14), 17, 0, TAU, 16, Color("ffbb8a"), 2.0, true)

func _maintain_stress() -> void:
	# This deliberately retains 300 enemies, 600 live moving projectiles and 200 drops.
	sim.run.health = sim.run.stat("max_health")
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemy.position.x = wrapf(enemy.position.x + 0.9, 100.0, 1180.0)
			enemy.position.y = 175.0 + float(enemy.slot % 15) * 27.0
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			shot.position = Vector2(wrapf(shot.position.x, 85.0, 1195.0), wrapf(shot.position.y, 135.0, 620.0))
	while sim.shot_count < 600:
		var shot: CombatSim.Shot = sim.fire_weapon("bone", "pierce", Vector2(sim.rng.randf_range(100, 1180), sim.rng.randf_range(160, 610)), Vector2.from_angle(sim.rng.randf() * TAU))
		shot.damage = 0.0
		shot.life = 10000.0
	while sim.soul_count < 200:
		sim._drop_soul(Vector2(sim.rng.randf_range(100, 1180), sim.rng.randf_range(160, 610)), 1)
