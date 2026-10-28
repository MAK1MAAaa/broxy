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
var _arena_id: String = "reliquary"
var _arena_name: String = "秘仪祭坛"
var _arena_color: Color = Color(0.78, 0.67, 0.50)
var soul_texture: Texture2D
var glow_texture: Texture2D
var seal_texture: Texture2D
var _hud_clock: float = 0.0
var _shake: float = 0.0
var _visual_time: float = 0.0
var _last_kills: int = 0
var autopilot: bool = false
var stress_mode: bool = false
var rune_stress_mode: bool = false
var content_stress_mode: bool = false
var stress_weapon_ids: PackedStringArray = PackedStringArray(["bone", "frost", "ember", "scatter"])
var benchmark_time_left: float = 0.0

const NUMBER_LIMIT: int = 48
const RUNE_FLASH_LIMIT: int = 32
const RUNE_FLASH_LIFE: float = 0.24
const RUNE_KINDS: Dictionary = {"pierce": 0, "bounce": 1, "blast": 2}
const RUNE_COLORS: Array[Color] = [Color("b8d6b2"), Color("9ec5dc"), Color("dfbc87")]
const ENEMY_HIT_VISUAL_REVISION: String = "tempered-hit-v1"
const ENEMY_HIT_PULSE_SECONDS: float = 0.06
const ENEMY_HIT_TIMER_CUTOFF: float = 0.04
const ENEMY_HIT_PEAK_GAIN: float = 0.22
const PLAYER_FOREGROUND_VISUAL_REVISION: String = "foreground-player-v1"
const DASH_AFTERIMAGE_LIMIT: int = 6
const DASH_AFTERIMAGE_LIFE: float = 0.16
const DASH_AFTERIMAGE_INTERVAL: float = 0.03
const DASH_EVASION_LIFE: float = 0.32
const DASH_EVASION_TEXT: String = "闪避"
const DASH_EVASION_FONT_SIZE: int = 14

class DashAfterimage:
	var position: Vector2 = Vector2.ZERO
	var lean: float = 0.0
	var life: float = 0.0

var _dash_pending: bool = false
var _dash_afterimages: Array[DashAfterimage] = []
var _dash_afterimage_next: int = 0
var _dash_afterimage_clock: float = 0.0
var _dash_evasion_remaining: float = 0.0
var _dash_evasion_pulse_remaining: float = 0.0
var _dash_evasion_dash: int = -1
var _dash_evasion_font: Font
var _dash_evasion_text_width: float = 32.0

class RuneFlash:
	var kind: int = 0
	var origin: Vector2 = Vector2.ZERO
	var incoming: Vector2 = Vector2.ZERO
	var outgoing: Vector2 = Vector2.ZERO
	var life: float = 0.0

class RuneLineBatch:
	var points: PackedVector2Array = PackedVector2Array()
	var color: Color = Color.WHITE

var _rune_pool: Array[RuneFlash] = []
var _rune_free: Array[RuneFlash] = []
var _rune_flashes: Array[RuneFlash] = []
var _rune_batches: Array[RuneLineBatch] = []

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
var _number_lookup: Dictionary = {}
var _number_font: Font
var _feedback_serial: int = 0
var _damage_flash: float = 0.0
var _damage_direction: Vector2 = Vector2.ZERO

const PROJECTILE_PAINTER_SCRIPT = preload("res://scripts/combat/projectile_painter.gd")
var _projectile_painter: PROJECTILE_PAINTER_SCRIPT = PROJECTILE_PAINTER_SCRIPT.new()
const ENEMY_TELEGRAPH_SCRIPT = preload("res://scripts/combat/enemy_telegraph_painter.gd")
var _enemy_telegraphs: ENEMY_TELEGRAPH_SCRIPT = ENEMY_TELEGRAPH_SCRIPT.new()
const IMPACT_PAINTER_SCRIPT = preload("res://scripts/combat/impact_painter.gd")
var _impact_painter: IMPACT_PAINTER_SCRIPT = IMPACT_PAINTER_SCRIPT.new()

func _init() -> void:
	for index: int in DASH_AFTERIMAGE_LIMIT:
		_dash_afterimages.append(DashAfterimage.new())
	for index: int in NUMBER_LIMIT:
		_number_pool.append(FloatingNumber.new())
	for index: int in RUNE_FLASH_LIMIT:
		_rune_pool.append(RuneFlash.new())
	# Three fade stages per family keep the render-command budget fixed at 18.
	for kind: int in 3:
		for stage: int in 3:
			var batch := RuneLineBatch.new()
			batch.color = Color(RUNE_COLORS[kind], [0.80, 0.58, 0.30][stage])
			_rune_batches.append(batch)
	_reset_feedback()

func _ready() -> void:
	_number_font = ThemeDB.fallback_font
	_dash_evasion_font = GameUI.create_ui_font()
	_dash_evasion_text_width = _dash_evasion_font.get_string_size(DASH_EVASION_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, DASH_EVASION_FONT_SIZE).x
	arena_texture = load(str(ArenaCatalog.definition(_arena_id)["texture"])) as Texture2D
	soul_texture = load("res://assets/icons/soul.svg")
	glow_texture = load("res://assets/fx/glow.svg")
	seal_texture = load("res://assets/fx/seal.svg")
	for id: String in ["player", "chaser", "rusher", "tank", "caster", "boss"]:
		textures[id] = load("res://assets/sprites/%s.svg" % id)
	for definition: ContentDef in GameCatalog.weapons():
		textures[definition.id] = load("res://assets/icons/%s.svg" % definition.icon)
	queue_redraw()

func apply_visual_settings(value: Dictionary) -> void:
	settings = value
	# Settings remain responsive while the scene tree pauses combat updates.
	if not bool(settings.get("flash", true)):
		_impact_painter.clear()
		_clear_dash_afterimages()
		_dash_evasion_pulse_remaining = 0.0
	queue_redraw()

func begin(state: RunState) -> void:
	var arena: Dictionary = ArenaCatalog.definition(state.arena_id)
	_arena_id = str(arena["id"])
	_arena_name = str(arena["name"])
	# Keep off-tree simulation fixtures free of render resources; _ready handles
	# a world begun before it is attached, using the same selected arena.
	if is_node_ready():
		arena_texture = load(str(arena["texture"])) as Texture2D
	_arena_color = Color(str(arena["preview_color"])) if _arena_id != "reliquary" else Color(0.78, 0.67, 0.50)
	sim = CombatSim.new()
	sim.begin(state)
	sim.ended.connect(_on_ended)
	sim.shot_fired.connect(func() -> void: sound.play("shoot", -24.0))
	sim.enemy_hit.connect(func() -> void: sound.play("hit", -24.0))
	sim.enemy_killed.connect(func(_position: Vector2, _color: Color) -> void: sound.play("death", -22.0))
	sim.player_hurt.connect(_on_player_hurt)
	sim.damage_dealt.connect(_on_damage_dealt)
	sim.player_damaged.connect(_on_player_damaged)
	sim.rune_activated.connect(_on_rune_activated)
	sim.dash_started.connect(_on_dash_started)
	sim.dash_evaded.connect(_on_dash_evaded)
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
	if is_inside_tree() and get_tree().paused:
		clear_pending_actions()
		return
	_visual_time += delta
	_advance_feedback(delta)
	_advance_dash_afterimages(delta)
	_advance_dash_evasion_feedback(delta)
	var movement: Vector2 = _movement()
	if autopilot:
		movement = BotPolicy.movement(sim)
	var dash_pressed: bool = _dash_pending and not stress_mode and not autopilot
	clear_pending_actions()
	sim.step(delta, movement, dash_pressed)
	_record_dash_motion(delta)
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

func request_dash() -> bool:
	if not active or sim == null or sim.complete or _dash_pending or stress_mode or autopilot:
		return false
	if (is_inside_tree() and get_tree().paused) or sim.run == null or sim.run.health <= 0.0:
		return false
	if sim.dash_time_left > 0.0 or sim.dash_cooldown_left > 0.0:
		return false
	_dash_pending = true
	return true

func clear_pending_actions() -> void:
	_dash_pending = false

func dash_afterimage_count() -> int:
	var count: int = 0
	for afterimage: DashAfterimage in _dash_afterimages:
		count += 1 if afterimage.life > 0.0 else 0
	return count

func _on_dash_started(origin: Vector2, direction: Vector2) -> void:
	_clear_dash_evasion_feedback()
	_dash_afterimage_clock = 0.0
	_add_dash_afterimage(origin, direction)
	if sound != null:
		sound.play("rune", -20.0)
	hud_changed.emit(hud_snapshot())

func dash_evasion_feedback_snapshot() -> Dictionary:
	return {
		"active": _dash_evasion_remaining > 0.0,
		"remaining": _dash_evasion_remaining,
		"pulse_remaining": _dash_evasion_pulse_remaining,
		"text": DASH_EVASION_TEXT if _dash_evasion_remaining > 0.0 else "",
	}

func _on_dash_evaded(point: Vector2, _origin: Vector2, _source_id: String, _kind: String) -> void:
	if not active or sim == null or sim.complete or not point.is_finite() or sim.dashes_used <= 0 or _dash_evasion_dash == sim.dashes_used:
		return
	_dash_evasion_dash = sim.dashes_used
	_dash_evasion_remaining = DASH_EVASION_LIFE
	_dash_evasion_pulse_remaining = DASH_EVASION_LIFE if bool(settings.get("flash", true)) else 0.0
	if sound != null:
		sound.play_cue("rune", -22.0, "dash_evasion")
	hud_changed.emit(hud_snapshot())
	queue_redraw()

func _advance_dash_evasion_feedback(delta: float) -> void:
	_dash_evasion_remaining = maxf(0.0, _dash_evasion_remaining - delta)
	_dash_evasion_pulse_remaining = maxf(0.0, _dash_evasion_pulse_remaining - delta)

func _clear_dash_evasion_feedback() -> void:
	_dash_evasion_remaining = 0.0
	_dash_evasion_pulse_remaining = 0.0
	_dash_evasion_dash = -1

func _add_dash_afterimage(point: Vector2, direction: Vector2) -> void:
	if not bool(settings.get("flash", true)) or not point.is_finite() or not direction.is_finite():
		return
	var afterimage: DashAfterimage = _dash_afterimages[_dash_afterimage_next]
	afterimage.position = point
	afterimage.lean = clampf(direction.x * 0.12, -0.045, 0.045)
	afterimage.life = DASH_AFTERIMAGE_LIFE
	_dash_afterimage_next = (_dash_afterimage_next + 1) % DASH_AFTERIMAGE_LIMIT

func _record_dash_motion(delta: float) -> void:
	if not active or sim == null or sim.complete or sim.dash_time_left <= 0.0 or not bool(settings.get("flash", true)):
		_dash_afterimage_clock = 0.0
		return
	_dash_afterimage_clock += delta
	if _dash_afterimage_clock >= DASH_AFTERIMAGE_INTERVAL:
		_dash_afterimage_clock = fmod(_dash_afterimage_clock, DASH_AFTERIMAGE_INTERVAL)
		_add_dash_afterimage(sim.player_position, sim.dash_direction)

func _advance_dash_afterimages(delta: float) -> void:
	for afterimage: DashAfterimage in _dash_afterimages:
		afterimage.life = maxf(0.0, afterimage.life - delta)

func _clear_dash_afterimages() -> void:
	for afterimage: DashAfterimage in _dash_afterimages:
		afterimage.life = 0.0
	_dash_afterimage_next = 0
	_dash_afterimage_clock = 0.0

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
	if not point.is_finite() or not is_finite(amount) or amount <= 0.0:
		return
	_spawn_number(point + Vector2(0, -22), amount, source, false, secondary, target_uid)
	# Damage events identify the enemy center, not an impact normal or contact point.
	if active and sim != null and not sim.complete and not secondary and bool(settings.get("flash", true)):
		_impact_painter.add_hit(point, source, target_uid)

func _on_player_damaged(amount: float, _source_id: String, _kind: String, origin: Vector2) -> void:
	_dash_evasion_remaining = 0.0
	_dash_evasion_pulse_remaining = 0.0
	_spawn_number(sim.player_position + Vector2(0, -40), amount, "player", true, false)
	_damage_flash = 0.22
	_damage_direction = (origin - sim.player_position).normalized() if origin.is_finite() else Vector2.ZERO

func _on_rune_activated(rune_id: String, origin: Vector2, incoming: Vector2, outgoing: Vector2) -> void:
	if not RUNE_KINDS.has(rune_id) or not origin.is_finite() or not incoming.is_finite() or not outgoing.is_finite() or _rune_free.is_empty():
		return
	var flash: RuneFlash = _rune_free.pop_back()
	flash.kind = int(RUNE_KINDS[rune_id])
	flash.origin = origin
	flash.incoming = incoming.normalized()
	flash.outgoing = outgoing.normalized()
	flash.life = RUNE_FLASH_LIFE
	_rune_flashes.append(flash)

func _reset_feedback() -> void:
	clear_pending_actions()
	_clear_dash_afterimages()
	_clear_dash_evasion_feedback()
	_enemy_telegraphs.clear()
	_impact_painter.clear()
	_numbers.clear()
	_number_lookup.clear()
	_number_free.clear()
	for number: FloatingNumber in _number_pool:
		number.life = 0.0
		_number_free.append(number)
	_feedback_serial = 0
	_damage_flash = 0.0
	_damage_direction = Vector2.ZERO
	_rune_flashes.clear()
	_rune_free.clear()
	for flash: RuneFlash in _rune_pool:
		flash.life = 0.0
		_rune_free.append(flash)
	for batch: RuneLineBatch in _rune_batches:
		batch.points.clear()

func _spawn_number(point: Vector2, amount: float, source: String, player_hit: bool, secondary: bool, target_uid: int = -1) -> void:
	if amount <= 0.0:
		return
	# Merge near-simultaneous hits at the same target instead of covering packs in text.
	if _number_lookup.has(source):
		var targets: Dictionary = _number_lookup[source]
		if targets.has(target_uid):
			for number: FloatingNumber in targets[target_uid]:
				if number.player_hit == player_hit and number.total - number.life < 0.075 and number.position.distance_squared_to(point) < 24.0 * 24.0:
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
	if not _number_lookup.has(source):
		_number_lookup[source] = {}
	var targets: Dictionary = _number_lookup[source]
	if not targets.has(target_uid):
		targets[target_uid] = []
	targets[target_uid].append(number)

func _update_number_text(number: FloatingNumber) -> void:
	number.text = _damage_text(number.amount, number.player_hit)
	number.text_width = _number_font.get_string_size(number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size).x if _number_font != null else float(number.text.length() * number.font_size) * 0.6

static func _damage_text(amount: float, player_hit: bool) -> String:
	var value: String = str(roundi(amount)) if is_equal_approx(amount, roundf(amount)) else "%.1f" % amount
	return ("−" if player_hit else "") + value

func _advance_feedback(delta: float) -> void:
	_impact_painter.advance(delta)
	_damage_flash = maxf(0.0, _damage_flash - delta)
	for index: int in range(_rune_flashes.size() - 1, -1, -1):
		var flash: RuneFlash = _rune_flashes[index]
		flash.life -= delta
		if flash.life <= 0.0:
			_rune_flashes.remove_at(index)
			_rune_free.append(flash)
	for index: int in range(_numbers.size() - 1, -1, -1):
		var number: FloatingNumber = _numbers[index]
		number.life -= delta
		if number.life <= 0.0:
			_numbers.remove_at(index)
			var targets: Dictionary = _number_lookup[number.source]
			var candidates: Array = targets[number.target_uid]
			candidates.erase(number)
			if candidates.is_empty():
				targets.erase(number.target_uid)
			if targets.is_empty():
				_number_lookup.erase(number.source)
			_number_free.append(number)
		else:
			number.position += number.velocity * delta

func _on_ended(victory: bool, reason: String) -> void:
	active = false
	clear_pending_actions()
	_clear_dash_afterimages()
	_clear_dash_evasion_feedback()
	_enemy_telegraphs.clear()
	_impact_painter.clear()
	hud_changed.emit(hud_snapshot())
	wave_ended.emit(victory, reason)

func hud_snapshot() -> Dictionary:
	var value: Dictionary = sim.snapshot()
	value["arena_id"] = _arena_id
	value["arena_name"] = _arena_name
	value["terrain_name"] = ArenaCatalog.terrain_name(_arena_id, sim.player_position)
	value["terrain_multiplier"] = ArenaCatalog.movement_multiplier(_arena_id, sim.player_position)
	value["rogue"] = {"core_id": sim.run.core_id, "active_route": sim.run.active_route,
		"hunter_alive": sim.hunter != null and sim.hunter.active and sim.hunter.hunter,
		"hunter_defeated": sim.run.hunter_defeated}
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
	_draw_player_ground()
	_draw_effects()
	_draw_impact_feedback()
	_draw_rune_feedback()
	_draw_outgoing_feedback()
	_draw_player()
	_draw_dash_evasion_feedback()
	_draw_feedback()
	# Hostile projectiles and telegraphs stay above all friendly spell effects.
	_draw_danger()

func _draw_impact_feedback() -> void:
	_impact_painter.rebuild(bool(settings.get("flash", true)))
	_impact_painter.draw(self)

func _draw_rune_feedback() -> void:
	_rebuild_rune_lines()
	for batch: RuneLineBatch in _rune_batches:
		if batch.points.is_empty():
			continue
		draw_multiline(batch.points, Color(0.025, 0.035, 0.06, batch.color.a * 0.8), 4.0, true)
		draw_multiline(batch.points, batch.color, 1.8, true)

func _rebuild_rune_lines() -> void:
	for batch: RuneLineBatch in _rune_batches:
		batch.points.clear()
	for flash: RuneFlash in _rune_flashes:
		var progress: float = clampf(1.0 - flash.life / RUNE_FLASH_LIFE, 0.0, 1.0)
		var stage: int = mini(2, int(progress * 3.0))
		var batch: RuneLineBatch = _rune_batches[flash.kind * 3 + stage]
		var axis: Vector2 = flash.outgoing
		var side: Vector2 = axis.orthogonal()
		var point: Vector2 = flash.origin
		if flash.kind == 0 and axis.length_squared() > 0.1:
			var head: Vector2 = point + axis * (14.0 + progress * 14.0)
			var tail: Vector2 = point - axis * 9.0
			_rune_segment(batch, tail + side * 4.0, head + side * 4.0)
			_rune_segment(batch, tail - side * 4.0, head - side * 4.0)
			_rune_segment(batch, head + side * 7.0, head + axis * 8.0)
			_rune_segment(batch, head - side * 7.0, head + axis * 8.0)
		elif flash.kind == 1:
			_rune_diamond(batch, point, 4.0 + progress * 2.0)
			# Only a short corner is drawn; the projectile must still travel to its target.
			if flash.incoming.length_squared() > 0.1:
				_rune_segment(batch, point - flash.incoming * 14.0, point)
			if axis.length_squared() > 0.1:
				var head: Vector2 = point + axis * (18.0 + progress * 10.0)
				_rune_segment(batch, point, head)
				_rune_segment(batch, head - axis * 6.0 + side * 4.0, head)
				_rune_segment(batch, head - axis * 6.0 - side * 4.0, head)
		elif flash.kind == 2:
			# Decorative rays stay inside the real 68 px explosion ring.
			var inner: float = 12.0 + progress * 18.0
			for index: int in 8:
				var direction: Vector2 = Vector2.from_angle(float(index) * TAU / 8.0)
				_rune_segment(batch, point + direction * inner, point + direction * (inner + 8.0 * (1.0 - progress)))
			_rune_diamond(batch, point, 4.0)
		else:
			# Stationary overlapping shots get a neutral impact mark, not a fake direction.
			_rune_diamond(batch, point, 4.0)

func _rune_segment(batch: RuneLineBatch, start: Vector2, end: Vector2) -> void:
	batch.points.append(start)
	batch.points.append(end)

func _rune_diamond(batch: RuneLineBatch, center: Vector2, radius: float) -> void:
	var top: Vector2 = center + Vector2.UP * radius
	var right: Vector2 = center + Vector2.RIGHT * radius
	var bottom: Vector2 = center + Vector2.DOWN * radius
	var left: Vector2 = center + Vector2.LEFT * radius
	_rune_segment(batch, top, right)
	_rune_segment(batch, right, bottom)
	_rune_segment(batch, bottom, left)
	_rune_segment(batch, left, top)

func _draw_outgoing_feedback() -> void:
	_draw_numbers(false)

func _draw_numbers(player_hit: bool) -> void:
	for number: FloatingNumber in _numbers:
		if number.player_hit == player_hit:
			_draw_number(number)

func _draw_number(number: FloatingNumber) -> void:
	if _number_font == null:
		return
	var alpha: float = minf(1.0, number.life / 0.24)
	var point: Vector2 = number.position - Vector2(number.text_width * 0.5, 0)
	draw_string_outline(_number_font, point, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size, 3, Color(0.025, 0.035, 0.06, alpha * 0.9))
	draw_string(_number_font, point, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size, Color(number.color, alpha))

func _draw_feedback() -> void:
	_draw_numbers(true)
	_draw_player_damage_direction()

func _draw_dash_evasion_feedback() -> void:
	if _dash_evasion_remaining <= 0.0 or sim == null:
		return
	if _dash_evasion_pulse_remaining > 0.0 and bool(settings.get("flash", true)):
		_draw_dash_evasion_pulse(sim.player_position + Vector2(0, 6))
	_draw_dash_evasion_text(_dash_evasion_text_anchor())

func _dash_evasion_text_anchor() -> Vector2:
	var anchor: Vector2 = sim.player_position + Vector2(0, -62)
	if anchor.y - 16.0 < 110.0:
		anchor.y = sim.player_position.y + 72.0
	var half_width: float = _dash_evasion_text_width * 0.5
	anchor.x = clampf(anchor.x, half_width + 8.0, 1280.0 - half_width - 8.0)
	return anchor

func _draw_dash_evasion_pulse(center: Vector2) -> void:
	var strength: float = clampf(_dash_evasion_pulse_remaining / DASH_EVASION_LIFE, 0.0, 1.0)
	var radius: float = 17.0 + (1.0 - strength) * 2.0
	draw_arc(center, radius, PI * 0.12, PI * 0.88, 12, Color(0.68, 0.88, 0.90, strength * 0.24), 1.25, true)

func _draw_dash_evasion_text(anchor: Vector2) -> void:
	if _dash_evasion_font == null:
		return
	var point: Vector2 = anchor - Vector2(_dash_evasion_text_width * 0.5, 0)
	draw_string_outline(_dash_evasion_font, point, DASH_EVASION_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, DASH_EVASION_FONT_SIZE, 3, Color("0c121a"))
	draw_string(_dash_evasion_font, point, DASH_EVASION_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, DASH_EVASION_FONT_SIZE, Color("d0e6df"))

func _draw_player_damage_direction() -> void:
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
		draw_circle(point, 1.0 if index % 3 else 1.5, Color(_arena_color, alpha))
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
			var tint: Color = _enemy_tint(enemy)
			if enemy.hunter:
				draw_arc(enemy.position + Vector2(0, 5), enemy.radius + 8.0, 0, TAU, 28, Color("c87866"), 2.0, true)
			draw_texture_rect(texture, Rect2(enemy.position + Vector2(-width * 0.5, -size * 0.66 + bob), Vector2(width, size)), false, tint)
			if enemy.hunter:
				_draw_hunter_mark(enemy, size)
			if id == "tank" and enemy.health < enemy.max_health:
				var origin: Vector2 = enemy.position + Vector2(-17, -size * 0.55)
				draw_line(origin, origin + Vector2(34, 0), Color("242533"), 3.0)
				draw_line(origin, origin + Vector2(34.0 * enemy.health / enemy.max_health, 0), Color("a9a7a3"), 2.0)

func _draw_hunter_mark(enemy: CombatSim.Enemy, size: float) -> void:
	var crest: Vector2 = enemy.position + Vector2(0, -size * 0.66 - 7)
	draw_polyline(PackedVector2Array([crest + Vector2(-9, 4), crest + Vector2(-8, -4), crest + Vector2(-3, 0), crest + Vector2(0, -7), crest + Vector2(3, 0), crest + Vector2(8, -4), crest + Vector2(9, 4), crest + Vector2(-9, 4)]), Color("e0ba7b"), 1.5, true)
	var origin: Vector2 = crest + Vector2(-20, 11)
	draw_line(origin, origin + Vector2(40, 0), Color("292131"), 4.0)
	draw_line(origin, origin + Vector2(40 * clampf(enemy.health / enemy.max_health, 0.0, 1.0), 0), Color("d79b78"), 2.0)

func _enemy_tint(enemy: CombatSim.Enemy) -> Color:
	var base: Color = Color("b4e9ed") if enemy.slow_timer > 0.0 else Color.WHITE
	if not bool(settings.get("flash", true)) or not is_finite(enemy.hurt_timer) or enemy.hurt_timer <= ENEMY_HIT_TIMER_CUTOFF:
		return base
	# The simulation retains its 100ms receipt; only the first 60ms brighten the art.
	var progress: float = clampf((enemy.hurt_timer - ENEMY_HIT_TIMER_CUTOFF) / ENEMY_HIT_PULSE_SECONDS, 0.0, 1.0)
	var gain: float = 1.0 + ENEMY_HIT_PEAK_GAIN * progress * progress
	return Color(base.r * gain, base.g * gain, base.b * gain, 1.0)

func _draw_friendly_shots() -> void:
	_projectile_painter.rebuild(sim.shots)
	_projectile_painter.draw(self)

func _draw_player_ground() -> void:
	var center: Vector2 = sim.player_position
	draw_texture_rect(glow_texture, Rect2(center - Vector2(44, 34), Vector2(88, 70)), false, Color(0.89, 0.78, 1.0, 0.35))
	draw_set_transform(center + Vector2(0, 9), 0.0, Vector2(1.0, 0.48))
	draw_texture_rect(seal_texture, Rect2(-Vector2.ONE * 32.0, Vector2.ONE * 64.0), false, Color(1.0, 0.95, 0.85, 0.55 + sin(_visual_time * 1.6) * 0.08))
	draw_set_transform(Vector2.ZERO)

func _player_tint() -> Color:
	var tint: Color = Color.WHITE
	if sim.dash_time_left > 0.0:
		return Color("d7e7e6") if bool(settings.get("flash", true)) else tint
	if sim.invulnerability > 0.0 and bool(settings.get("flash", true)):
		tint.a = 0.55 + sin(_visual_time * 35.0) * 0.30
	return tint

func _draw_player() -> void:
	_draw_dash_afterimages()
	var center: Vector2 = sim.player_position
	var bob: float = sin(_visual_time * 9.0) * minf(2.0, sim.player_velocity.length() * 0.012)
	var tint: Color = _player_tint()
	var lean: float = clampf(sim.player_velocity.x * 0.0002, -0.045, 0.045)
	draw_set_transform(center, lean)
	draw_texture_rect(textures["player"], Rect2(Vector2(-34, -50 + bob), Vector2(68, 68)), false, tint)
	draw_set_transform(Vector2.ZERO)
	var orbit_count: int = mini(8, sim.run.loadout.size())
	for index: int in orbit_count:
		var equipped: Dictionary = sim.run.loadout[index]
		var angle: float = -PI * 0.75 + float(index) * TAU / float(orbit_count) + sin(_visual_time * 0.6) * 0.12
		var orbit: Vector2 = center + Vector2.from_angle(angle) * 39.0 + Vector2(0, sin(_visual_time * 2.0 + float(index)) * 3.0)
		var definition: ContentDef = GameCatalog.weapon(str(equipped["id"]))
		draw_circle(orbit, 14.0, Color(definition.color, 0.07))
		draw_texture_rect(textures[str(equipped["id"])], Rect2(orbit - Vector2(12, 12), Vector2(24, 24)), false)
		var rune: Dictionary = equipped.get("rune", {})
		if not rune.is_empty():
			var rune_color: Color = GameCatalog.rune(str(rune["id"])).color
			draw_arc(orbit, 15.0, _visual_time * 0.5, _visual_time * 0.5 + PI * 1.4, 12, Color(rune_color, 0.65), 1.0, true)
	if sim.run.loadout.size() > orbit_count and _number_font != null:
		var extra: String = "+%d" % (sim.run.loadout.size() - orbit_count)
		var width: float = _number_font.get_string_size(extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var point: Vector2 = center + Vector2(-width * 0.5, 28.0)
		draw_string_outline(_number_font, point, extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color("0d111b"))
		draw_string(_number_font, point, extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f0e5cc"))

func _draw_dash_afterimages() -> void:
	if not bool(settings.get("flash", true)) or not textures.has("player"):
		return
	for offset: int in DASH_AFTERIMAGE_LIMIT:
		var index: int = (_dash_afterimage_next + offset) % DASH_AFTERIMAGE_LIMIT
		var afterimage: DashAfterimage = _dash_afterimages[index]
		if afterimage.life <= 0.0:
			continue
		var opacity: float = 0.16 * clampf(afterimage.life / DASH_AFTERIMAGE_LIFE, 0.0, 1.0)
		draw_set_transform(afterimage.position, afterimage.lean)
		draw_texture_rect(textures["player"], Rect2(Vector2(-34, -50), Vector2(68, 68)), false, Color(0.70, 0.88, 0.90, opacity))
	draw_set_transform(Vector2.ZERO)

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
		elif effect.kind == 3:
			var radius: float = effect.radius * (0.3 + progress * 0.7)
			draw_arc(effect.position, radius, 0, TAU, 24, color, 2.0, true)
			for index: int in 6:
				var direction: Vector2 = Vector2.from_angle(float(index) * TAU / 6.0)
				draw_line(effect.position + direction * radius * 0.45, effect.position + direction * radius, Color("c9dbed", color.a), 1.5, true)
			draw_arc(effect.position, radius * 0.55, 0, TAU, 20, Color("e4bb8c", color.a * 0.7), 1.0, true)
		else:
			for index: int in 5:
				var direction: Vector2 = Vector2.from_angle(float(index) * TAU / 5.0)
				var point: Vector2 = effect.position + direction * effect.radius * progress
				draw_line(point, point + direction * 5.0 * (1.0 - progress), color, 2.0, true)

func _draw_danger() -> void:
	if active:
		_enemy_telegraphs.rebuild(sim.enemies)
		_enemy_telegraphs.draw(self)
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
	# Live hostile rounds remain above all warning strokes.
	for shot: CombatSim.Shot in sim.shots:
		if not shot.active or not shot.hostile:
			continue
		draw_circle(shot.position, shot.radius + 3.0, Color("542e35"))
		draw_circle(shot.position, shot.radius, Color("ff8666"))
		draw_arc(shot.position, shot.radius, 0, TAU, 12, Color("ffdfb1"), 1.5, true)
		draw_circle(shot.position, 2.5, Color("fff2d7"))

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
		var weapon: String = stress_weapon_ids[sim.shot_count % stress_weapon_ids.size()] if rune_stress_mode else "bone"
		var rune_id: String = ["pierce", "bounce", "blast"][sim.shot_count % 3] if rune_stress_mode else "pierce"
		var shot: CombatSim.Shot = sim.fire_weapon(weapon, rune_id, Vector2(sim.rng.randf_range(100, 1180), sim.rng.randf_range(160, 610)), Vector2.from_angle(sim.rng.randf() * TAU))
		if not rune_stress_mode:
			shot.damage = 0.0
		shot.life = 10000.0
	while sim.soul_count < 200:
		sim._drop_soul(Vector2(sim.rng.randf_range(100, 1180), sim.rng.randf_range(160, 610)), 1)

func enable_rune_stress(include_content: bool = false) -> void:
	# Explicit QA variant: use real weapon damage and all rune families instead of
	# the baseline's zero-damage filler. Keep the original benchmark reproducible.
	rune_stress_mode = true
	content_stress_mode = include_content
	stress_weapon_ids = PackedStringArray(["bone", "frost", "ember", "scatter"])
	if include_content:
		stress_weapon_ids.clear()
		for definition: ContentDef in GameCatalog.weapons():
			stress_weapon_ids.append(definition.id)
	for shot: CombatSim.Shot in sim.shots:
		if shot.active:
			sim._release_shot(shot)
	_maintain_stress()
