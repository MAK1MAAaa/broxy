class_name CombatWorld
extends Node2D

signal wave_ended(victory: bool, reason: String)
signal hud_changed(snapshot: Dictionary)

var sim: CombatSim
var active: bool = false
var sound: SoundBank
var settings: Dictionary = {"shake": true, "flash": true}
var textures: Dictionary = {}
var _player_atlas: Texture2D
var _presentation_dirty: bool = true
var arena_texture: Texture2D
var _obstacle_textures: Dictionary = {}
var _arena_obstacles: Array[Dictionary] = []
var _interaction_textures: Dictionary = {}
var _interaction_widths: Dictionary = {"barrel": 24.0, "chest": 44.0, "gold": 12.0, "health": 26.0, "charge": 26.0}
var _interaction_feet: Dictionary = {"barrel": Vector2(64, 112), "chest": Vector2(48, 88), "gold": Vector2(32, 61), "health": Vector2(32, 61), "charge": Vector2(32, 61)}
var _bumper_flashes: Array[Dictionary] = []
var _crate_flashes: Array[Dictionary] = []
var _weakpoint_texture: Texture2D
var _boss_receipts: Array[WeakpointReceipt] = []
var _camera: Camera2D
var _arena_id: String = "reliquary"
var _arena_name: String = "沙漠遗迹"
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
const DASH_EVASION_FONT_SIZE: int = 12
const PULSE_FEEDBACK_LIFE: float = 0.30
const SKILL_FEEDBACK_LIFE: float = 0.45
const SKILL_FEEDBACK_FONT_SIZE: int = 12
const PULSE_HINDER_TINT: Color = Color("c1b2d8")
const OBSTACLE_ART_WIDTHS: Dictionary = {"monument": 44.0, "planter": 54.0, "bumper": 69.0}
const INTERACTION_ROOT: String = "res://assets/worldflipper/interactions/"
const BUMPER_FLASH_LIMIT: int = 8
const CRATE_FLASH_LIMIT: int = 16
const BUMPER_FLASH_LIFE: float = 0.18
const CRATE_FLASH_LIFE: float = 0.12
const CRATE_BREAK_LIFE: float = 0.32
const BALL_FRAME_ENDS: Array[float] = [0.12, 0.18, 0.24, 0.30, 0.36, 0.42, 0.48]
const WEAKPOINT_ATLAS_PATH: String = "res://assets/worldflipper/boss/weakpoint-atlas.png"
const WEAKPOINT_HIT_LIFE: float = 0.10
const WEAKPOINT_BREAK_LIFE: float = 0.22
const WEAKPOINT_LIMIT: int = 3
const BOSS_INTRO_SECONDS: float = 2.4

class WeakpointReceipt:
	var uid: int = -1
	var cast_id: int = -1
	var position: Vector2 = Vector2.ZERO
	var broke: bool = false
	var life: float = 0.0

class DashAfterimage:
	var position: Vector2 = Vector2.ZERO
	var lean: float = 0.0
	var life: float = 0.0
	var frame_index: int = 0
	var flip_h: bool = false

var _dash_pending: bool = false
var _pulse_pending: bool = false
var _secondary_skill_pending: bool = false
var _hero_skill_pending: bool = false
var _hero_pending_id: String = ""
var _pulse_pending_uid: int = -1
var _secondary_pending_uid: int = -1
var _pulse_remaining: float = 0.0
var _pulse_origin: Vector2 = Vector2.ZERO
var _pulse_radius: float = 0.0
var _pulse_affected: int = 0
var _pulse_animated: bool = false
var _pulse_feedback_use: int = -1
var _skill_feedback_remaining: float = 0.0
var _skill_feedback_text: String = ""
var _skill_feedback_affected: int = 0
var _skill_feedback_origin: Vector2 = Vector2.ZERO
var _skill_feedback_anchor: Vector2 = Vector2.ZERO
var _skill_feedback_text_width: float = 0.0
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
	var font_size: int = 12

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
const ACTIVE_SKILL_PAINTER_SCRIPT = preload("res://scripts/combat/active_skill_painter.gd")
var _active_skill_painter: ACTIVE_SKILL_PAINTER_SCRIPT = ACTIVE_SKILL_PAINTER_SCRIPT.new()
const GROUNDING_PAINTER_SCRIPT = preload("res://scripts/combat/grounding_painter.gd")
var _grounding_painter: GROUNDING_PAINTER_SCRIPT = GROUNDING_PAINTER_SCRIPT.new()

func _init() -> void:
	for index: int in WEAKPOINT_LIMIT:
		_boss_receipts.append(WeakpointReceipt.new())
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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ControlBindings.ensure_installed()
	_number_font = GameTypography.font()
	_dash_evasion_font = GameTypography.font()
	_dash_evasion_text_width = _dash_evasion_font.get_string_size(DASH_EVASION_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, DASH_EVASION_FONT_SIZE).x
	arena_texture = load(ArenaCatalog.texture_path(_arena_id)) as Texture2D
	for id: String in ["monument", "planter", "bumper"]:
		_obstacle_textures[id] = load("res://assets/worldflipper/props/%s.png" % id) as Texture2D
	for entry: Array in [["ball", "ball-atlas"], ["barrel", "barrel-atlas"], ["chest", "chest"], ["health", "health"], ["charge", "charge"], ["gold", "mana"]]:
		_interaction_textures[str(entry[0])] = load(INTERACTION_ROOT + str(entry[1]) + ".png") as Texture2D
	_cache_interaction_geometry()
	_weakpoint_texture = load(WEAKPOINT_ATLAS_PATH) as Texture2D
	_camera = Camera2D.new()
	_camera.name = "ExplorationCamera"
	_camera.top_level = true
	_camera.enabled = false
	_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(_camera)
	soul_texture = load(AdventureArt.path("res://assets/icons/soul.svg"))
	glow_texture = load(AdventureArt.path("res://assets/fx/glow.svg"))
	seal_texture = load(AdventureArt.path("res://assets/fx/seal.svg"))
	for id: String in ["player", "chaser", "rusher", "tank", "caster", "boss"]:
		textures[id] = load(AdventureArt.path("res://assets/sprites/%s.svg" % id))
	_load_hero_art()
	for definition: ContentDef in GameCatalog.weapons():
		textures[definition.id] = load(AdventureArt.path("res://assets/icons/%s.svg" % definition.icon))
	_update_camera()
	_request_redraw()

func _request_redraw() -> void:
	_presentation_dirty = true
	if is_inside_tree() and get_tree().paused:
		_presentation_dirty = false
		queue_redraw()

func _process(_delta: float) -> void:
	if _presentation_dirty:
		_presentation_dirty = false
		queue_redraw()

func apply_visual_settings(value: Dictionary) -> void:
	settings = value
	# Settings remain responsive while the scene tree pauses combat updates.
	if not bool(settings.get("flash", true)):
		_impact_painter.clear()
		_clear_dash_afterimages()
		_dash_evasion_pulse_remaining = 0.0
		_pulse_animated = false
		_active_skill_painter.disable_animation()
		_bumper_flashes.clear()
		_crate_flashes.clear()
	_request_redraw()

func begin(state: RunState) -> void:
	var arena: Dictionary = ArenaCatalog.definition(state.arena_id)
	_arena_id = str(arena["id"])
	_arena_name = str(arena["name"])
	# Keep off-tree simulation fixtures free of render resources; _ready handles
	# a world begun before it is attached, using the same selected arena.
	if is_node_ready():
		arena_texture = load(ArenaCatalog.texture_path(_arena_id)) as Texture2D
	_arena_color = Color(str(arena["preview_color"])) if _arena_id != "reliquary" else Color(0.78, 0.67, 0.50)
	sim = CombatSim.new()
	sim.begin(state)
	if is_node_ready():
		_load_hero_art()
	_arena_obstacles.clear()
	for obstacle: Dictionary in sim.obstacles.snapshot():
		if not str(obstacle["id"]).begins_with("crate:"):
			_arena_obstacles.append(obstacle)
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
	sim.pulse_cast.connect(_on_pulse_cast)
	sim.active_skill_cast.connect(_on_active_skill_cast)
	sim.hero_skill_cast.connect(_on_hero_skill_cast)
	sim.pinball_bounced.connect(_on_pinball_bounced)
	sim.crate_hit.connect(_on_crate_hit)
	sim.world_pickup_collected.connect(_on_world_pickup_collected)
	sim.boss_weakpoint_hit.connect(_on_boss_weakpoint_hit)
	sim.boss_interrupted.connect(_on_boss_interrupted)
	_reset_feedback()
	active = true
	_last_kills = state.kills
	_hud_clock = 0.0
	_shake = 0.0
	position = Vector2.ZERO
	_update_camera()
	hud_changed.emit(hud_snapshot())
	_request_redraw()

func stop() -> void:
	active = false
	_reset_feedback()
	position = Vector2.ZERO
	if is_instance_valid(_camera) and _camera.is_current():
		_camera.position = ArenaCatalog.MAX_VIEW_SIZE * 0.5
		_camera.force_update_scroll()
		_camera.enabled = false
	_request_redraw()

func camera_view() -> Rect2:
	return ArenaCatalog.visible_rect(sim.player_position if sim != null else CombatSim.ARENA.get_center())

func _update_camera() -> void:
	if not active or sim == null or not is_instance_valid(_camera):
		return
	_camera.position = ArenaCatalog.camera_center(sim.player_position)
	_camera.enabled = true
	if not _camera.is_current():
		_camera.make_current()
	_camera.force_update_scroll()

func _feedback_safe_rect() -> Rect2:
	var view: Rect2 = camera_view()
	var safe := Rect2(view.position + Vector2(196, 150), view.size - Vector2(392, 262))
	return safe.intersection(CombatSim.ARENA.grow(-8.0))

func _boss_alive() -> bool:
	return active and sim != null and sim.boss != null and sim.boss.active and sim.boss.health > 0.0

func _cosmetic_visible_rect() -> Rect2:
	var view: Rect2 = camera_view()
	var padding: Vector2 = position.abs() + Vector2.ONE * 4.0
	return Rect2(view.position - padding, view.size + padding * 2.0)

static func effect_draw_bounds(effect: CombatSim.Effect) -> Rect2:
	var extent: float = absf(effect.radius) * 1.4 + 8.0
	return Rect2(effect.position - Vector2.ONE * extent, Vector2.ONE * extent * 2.0)

static func soul_draw_bounds(soul: CombatSim.Soul) -> Rect2:
	var size: float = 12.0 if soul.value == 1 else 17.0
	return Rect2(soul.position - Vector2(size * 0.5, size * 0.5 + 2.0), Vector2(size, size + 4.0))

static func number_draw_bounds(number: FloatingNumber) -> Rect2:
	var padding: float = float(number.font_size) * 0.5 + 4.0
	var drift: Vector2 = number.velocity.abs() * minf(maxf(number.life, 0.0), 1.0 / 30.0)
	var half := Vector2(maxf(0.0, number.text_width) * 0.5 + padding, float(number.font_size) * 2.0 + 4.0)
	half += drift
	return Rect2(number.position - half, half * 2.0)

func _physics_process(delta: float) -> void:
	if not active or sim == null:
		return
	if is_inside_tree() and get_tree().paused:
		clear_pending_actions()
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_visual_time += delta
	_advance_feedback(delta)
	_advance_dash_afterimages(delta)
	_advance_dash_evasion_feedback(delta)
	_advance_pulse_feedback(delta)
	_advance_interaction_feedback(delta)
	_advance_boss_feedback(delta)
	_active_skill_painter.advance(delta)
	var movement: Vector2 = _movement()
	if autopilot:
		movement = BotPolicy.movement(sim)
	var dash_pressed: bool = _dash_pending and not stress_mode and not autopilot
	var hero_pressed: bool = _hero_skill_pending and not stress_mode and not autopilot and _hero_pending_id == sim.run.hero_id
	var skill_requests: Array[Dictionary] = []
	if not stress_mode and not autopilot:
		if _pulse_pending:
			skill_requests.append({"slot": 0, "uid": _pulse_pending_uid})
		if _secondary_skill_pending:
			skill_requests.append({"slot": 1, "uid": _secondary_pending_uid})
	clear_pending_actions()
	sim.step(delta, movement, dash_pressed, false, skill_requests, hero_pressed)
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
	_update_camera()
	_request_redraw()

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
	_pulse_pending = false
	_secondary_skill_pending = false
	_hero_skill_pending = false
	_hero_pending_id = ""
	_pulse_pending_uid = -1
	_secondary_pending_uid = -1

func request_pulse() -> bool:
	return request_skill(0)

func request_hero_skill() -> bool:
	if not active or sim == null or sim.complete or stress_mode or autopilot or _hero_skill_pending:
		return false
	if (is_inside_tree() and get_tree().paused) or sim.run == null or sim.run.health <= 0.0:
		return false
	if not bool(sim.hero_skill_snapshot().get("ready", false)):
		return false
	_hero_skill_pending = true
	_hero_pending_id = sim.run.hero_id
	return true

func request_skill(slot: int) -> bool:
	if slot < 0 or slot >= ActiveSkillRules.LIMIT:
		return false
	if not active or sim == null or sim.complete or stress_mode or autopilot:
		return false
	if (slot == 0 and _pulse_pending) or (slot == 1 and _secondary_skill_pending):
		return false
	if (is_inside_tree() and get_tree().paused) or sim.run == null or sim.run.health <= 0.0:
		return false
	var skill: Dictionary = sim.active_skill_snapshot(slot)
	if not bool(skill.get("available", false)) or not bool(skill.get("ready", false)):
		return false
	if slot == 0:
		_pulse_pending = true
		_pulse_pending_uid = int(skill["uid"])
	else:
		_secondary_skill_pending = true
		_secondary_pending_uid = int(skill["uid"])
	return true

func _on_active_skill_cast(id: String, uid: int, origin: Vector2, direction: Vector2, affected: int, rank: int) -> void:
	if id == "pulse" or not active or sim == null or sim.complete:
		return
	var parameters: Dictionary = ActiveSkillRules.parameters(id, rank, {})
	if parameters.is_empty() or uid < 0:
		return
	_active_skill_painter.add_cast(id, origin, direction, float(parameters["radius"]), bool(settings.get("flash", true)))
	if affected > 0:
		_shake = maxf(_shake, 1.4 if id == "starfall" else 0.8)
	if sound != null:
		sound.play_cue("pulse_hit" if affected > 0 else "pulse", -22.0, "active_skill:%d" % uid)
	hud_changed.emit(hud_snapshot())

func _on_hero_skill_cast(hero_id: String, parameters: Dictionary, origin: Vector2, direction: Vector2, affected: int) -> void:
	if not active or sim == null or sim.complete:
		return
	_active_skill_painter.add_hero_cast(parameters, origin, direction, bool(settings.get("flash", true)))
	if affected > 0:
		_shake = maxf(_shake, 1.8)
	if sound != null:
		sound.play_cue("pulse_hit" if affected > 0 else "pulse", -19.0, "hero_skill:" + hero_id)
	hud_changed.emit(hud_snapshot())
	_request_redraw()

func _on_pinball_bounced(point: Vector2, normal: Vector2, boosted: bool, combo: int) -> void:
	if not active or sim == null or sim.complete or not point.is_finite() or not normal.is_finite():
		return
	if bool(settings.get("flash", true)):
		var nearest: Dictionary = {}
		var distance: float = INF
		for obstacle: Dictionary in _arena_obstacles:
			if not boosted:
				break
			if str(obstacle["art_id"]) != "bumper":
				continue
			var separation: float = point.distance_squared_to(obstacle["center"])
			if separation < distance and separation <= pow(float(obstacle["radius"]) + 56.0, 2.0):
				nearest = obstacle
				distance = separation
		if not nearest.is_empty():
			_add_interaction_flash(_bumper_flashes, nearest["center"], BUMPER_FLASH_LIFE, BUMPER_FLASH_LIMIT)
		_shake = maxf(_shake, 0.9 if boosted else 0.45)
	if sound != null:
		sound.play("rune", -23.0)
	hud_changed.emit(hud_snapshot())
	_request_redraw()

func _on_crate_hit(point: Vector2, broke: bool) -> void:
	if not active or sim == null or sim.complete or not point.is_finite():
		return
	if bool(settings.get("flash", true)) and not broke:
		_add_interaction_flash(_crate_flashes, point, CRATE_FLASH_LIFE, CRATE_FLASH_LIMIT)
	if sound != null:
		sound.play("death" if broke else "hit", -25.0)
	_request_redraw()

func _on_world_pickup_collected(kind: String, point: Vector2, value: float) -> void:
	if not active or sim == null or sim.complete or not point.is_finite() or not is_finite(value) or value <= 0.0:
		return
	var source: String = "pickup:" + kind
	_spawn_number(point + Vector2(0, -24), value, source, false, false)
	var targets: Dictionary = _number_lookup.get(source, {})
	var candidates: Array = targets.get(-1, [])
	if not candidates.is_empty():
		var number: FloatingNumber = candidates.back()
		number.text = ("−" if kind == "charge" else "+") + _damage_text(number.amount, false) + ("秒" if kind == "charge" else "")
		number.color = Color("9fd5a0") if kind == "health" else Color("c8b7e9") if kind == "charge" else Color("efca7d")
		number.text_width = _number_font.get_string_size(number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size).x if _number_font != null else float(number.text.length() * number.font_size) * 0.6
	if sound != null:
		sound.play("rune" if kind == "charge" else "level" if kind == "health" else "buy", -24.0)
	hud_changed.emit(hud_snapshot())
	_request_redraw()

func _on_boss_weakpoint_hit(uid: int, cast_id: int, point: Vector2, broke: bool) -> void:
	if not _boss_alive() or uid < 0 or cast_id < 0 or not point.is_finite():
		return
	var selected: WeakpointReceipt = _boss_receipts[0]
	for receipt: WeakpointReceipt in _boss_receipts:
		if receipt.uid == uid and receipt.cast_id == cast_id:
			selected = receipt
			break
		if receipt.life < selected.life:
			selected = receipt
	selected.uid = uid
	selected.cast_id = cast_id
	selected.position = point
	selected.broke = broke
	selected.life = WEAKPOINT_BREAK_LIFE if broke else WEAKPOINT_HIT_LIFE
	if sound != null:
		sound.play("death" if broke else "hit", -22.0)
	hud_changed.emit(hud_snapshot())
	_request_redraw()

func _on_boss_interrupted(point: Vector2) -> void:
	if not _boss_alive() or not point.is_finite():
		return
	if bool(settings.get("flash", true)):
		_impact_painter.add_hit(point, "storm", -1)
		_shake = maxf(_shake, 1.2)
	if sound != null:
		sound.play_cue("pulse_hit", -18.0, "boss_interrupt")
	hud_changed.emit(hud_snapshot())
	_request_redraw()

func _clear_boss_feedback() -> void:
	for receipt: WeakpointReceipt in _boss_receipts:
		receipt.uid = -1
		receipt.cast_id = -1
		receipt.life = 0.0

func _advance_boss_feedback(delta: float) -> void:
	if not _boss_alive():
		_clear_boss_feedback()
		return
	var cast_id: int = int(sim.boss_encounter.snapshot().get("cast_id", -1))
	for receipt: WeakpointReceipt in _boss_receipts:
		receipt.life = maxf(0.0, receipt.life - delta) if receipt.cast_id == cast_id else 0.0

static func weakpoint_draw_rect(point: Vector2) -> Rect2:
	return Rect2(point - Vector2(16, 16), Vector2(32, 32))

static func weakpoint_source_rect(frame: int) -> Rect2:
	return Rect2(Vector2(frame * 96, 0), Vector2(96, 96)) if frame >= 0 and frame < 3 else Rect2()

func boss_weakpoint_presentation_snapshot() -> Array[Dictionary]:
	var value: Array[Dictionary] = []
	if not _boss_alive():
		return value
	var encounter: Dictionary = sim.boss_encounter.snapshot()
	var cast_id: int = int(encounter.get("cast_id", -1))
	var total: float = float(encounter.get("charge_total", 0.0))
	var red: bool = total > 0.0 and float(encounter.get("charge_left", total)) <= total * 0.3
	var flashing: bool = bool(settings.get("flash", true))
	for point: Dictionary in sim.boss_weakpoints():
		if value.size() >= WEAKPOINT_LIMIT:
			break
		if not bool(point.get("active", false)) or float(point.get("health", 0.0)) <= 0.0:
			continue
		var center: Vector2 = point["position"]
		if not center.is_finite():
			continue
		var tint: Color = Color.WHITE
		for receipt: WeakpointReceipt in _boss_receipts:
			if flashing and receipt.life > 0.0 and not receipt.broke and receipt.uid == int(point["uid"]) and receipt.cast_id == cast_id:
				tint = Color(1.25, 1.10, 0.85)
				center = receipt.position
		value.append({"uid": int(point["uid"]), "cast_id": int(point["cast_id"]), "position": center,
			"frame": 1 if red else 0, "rect": weakpoint_draw_rect(center), "tint": tint, "broken": false})
	for receipt: WeakpointReceipt in _boss_receipts:
		if receipt.life > 0.0 and receipt.broke and receipt.cast_id == cast_id:
			value.append({"uid": receipt.uid, "cast_id": receipt.cast_id, "position": receipt.position,
				"frame": 2, "rect": weakpoint_draw_rect(receipt.position), "tint": Color.WHITE, "broken": true})
	return value

func _draw_boss_weakpoints() -> void:
	if _weakpoint_texture == null:
		return
	var visible: Rect2 = _cosmetic_visible_rect()
	for point: Dictionary in boss_weakpoint_presentation_snapshot():
		if (point["rect"] as Rect2).intersects(visible):
			draw_texture_rect_region(_weakpoint_texture, point["rect"], weakpoint_source_rect(int(point["frame"])), point["tint"])

func boss_danger_snapshot() -> Dictionary:
	if not _boss_alive():
		return {}
	var encounter: Dictionary = sim.boss_encounter.snapshot()
	if str(encounter.get("phase", "")) != "charge":
		return {}
	var total: float = float(encounter.get("charge_total", 0.0))
	var progress: float = clampf(1.0 - float(encounter.get("charge_left", 0.0)) / total, 0.0, 1.0) if total > 0.0 else 0.0
	return {"cast_id": int(encounter["cast_id"]), "progress": progress,
		"geometry": sim.boss_encounter.telegraph_snapshot(), "safe_channels": encounter.get("safe_channels", []).duplicate(true)}

static func _add_interaction_flash(pool: Array[Dictionary], point: Vector2, life: float, limit: int) -> void:
	for flash: Dictionary in pool:
		if point.distance_squared_to(flash["position"]) < 1.0:
			flash["life"] = life
			return
	if pool.size() >= limit:
		pool.pop_front()
	pool.append({"position": point, "life": life})

func _advance_interaction_feedback(delta: float) -> void:
	_advance_interaction_pool(_bumper_flashes, delta)
	_advance_interaction_pool(_crate_flashes, delta)

static func _advance_interaction_pool(pool: Array[Dictionary], delta: float) -> void:
	for index: int in range(pool.size() - 1, -1, -1):
		pool[index]["life"] = maxf(0.0, float(pool[index]["life"]) - delta)
		if float(pool[index]["life"]) <= 0.0:
			pool.remove_at(index)

static func _interaction_flash(pool: Array[Dictionary], point: Vector2, duration: float) -> float:
	for flash: Dictionary in pool:
		if point.distance_squared_to(flash["position"]) < 1.0:
			return clampf(float(flash["life"]) / duration, 0.0, 1.0)
	return 0.0

static func ball_frame_index(age: float) -> int:
	var phase: float = fposmod(maxf(age, 0.0), BALL_FRAME_ENDS[-1]) if is_finite(age) else 0.0
	for index: int in BALL_FRAME_ENDS.size():
		if phase < BALL_FRAME_ENDS[index]:
			return index
	return BALL_FRAME_ENDS.size() - 1

static func crate_break_frame(age: float) -> int:
	if not is_finite(age) or age < 0.0 or age >= CRATE_BREAK_LIFE:
		return -1
	return mini(9, 2 + int(age / 0.04))

func interaction_presentation_snapshot() -> Dictionary:
	var result: Dictionary = {"crates": [], "pickups": [], "pinball": {"active": false}, "bumper_feedback_count": _bumper_flashes.size(), "crate_feedback_count": _crate_flashes.size()}
	if not active or sim == null or sim.interactions == null:
		return result
	var state: Dictionary = sim.interactions.snapshot()
	for crate: Dictionary in state.get("crates", []):
		var alive: bool = bool(crate["active"])
		var frame: int = 1 if alive else crate_break_frame(float(crate["break_age"]))
		if frame < 0:
			continue
		var art_id: String = str(crate["art_id"])
		var chest: bool = alive and art_id == "chest"
		var texture_id: String = "chest" if chest else "barrel"
		var factor: float = float(crate["radius"]) * 2.0 / float(_interaction_widths[texture_id])
		var pressure: float = _interaction_flash(_crate_flashes, crate["position"], CRATE_FLASH_LIFE) if alive else 0.0
		var stretch := Vector2(1.0 + pressure * 0.06, 1.0 - pressure * 0.10)
		var extent := Vector2.ONE * (96.0 if chest else 128.0) * factor * stretch
		var foot: Vector2 = _interaction_feet[texture_id] * factor * stretch
		if not alive and not bool(settings.get("flash", true)):
			frame = 2
		result["crates"].append({"uid": crate["uid"], "position": crate["position"], "radius": crate["radius"], "active": alive,
			"frame": frame, "texture": texture_id, "rect": Rect2(crate["position"] - foot, extent), "pressure": pressure})
	for pickup: Dictionary in state.get("pickups", []):
		var kind: String = str(pickup["kind"])
		if kind not in ["gold", "health", "charge"]:
			continue
		var bob: float = sin(float(pickup.get("age", 0.0)) * 5.0) * 1.5 if bool(settings.get("flash", true)) else 0.0
		var visible_width: float = 16.0 if kind == "gold" else 18.0
		var factor: float = visible_width / float(_interaction_widths[kind])
		var texture: Texture2D = _interaction_textures.get(kind) as Texture2D
		var source_size: Vector2 = texture.get_size() if texture != null else Vector2.ONE * 64.0
		result["pickups"].append({"uid": pickup["uid"], "kind": kind, "position": pickup["position"],
			"rect": Rect2(pickup["position"] - _interaction_feet[kind] * factor - Vector2(0, bob), source_size * factor)})
	var ball: Dictionary = sim.pinball_snapshot()
	ball["hero_id"] = sim.run.hero_id
	ball["identity_texture"] = HeroCatalog.definition(sim.run.hero_id).idle_path
	ball["identity_rect"] = _ball_identity_rect()
	ball["frame"] = ball_frame_index(float(ball.get("age", 0.0))) if bool(settings.get("flash", true)) else 0
	ball["rect"] = Rect2(sim.player_position - Vector2.ONE * 24.0, Vector2.ONE * 48.0)
	result["pinball"] = ball
	return result

func _cache_interaction_geometry() -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(INTERACTION_ROOT + "interaction-art.json"))
	var assets: Dictionary = value.get("assets", {}) if value is Dictionary else {}
	for id: String in _interaction_feet:
		var definition: Dictionary = assets.get("mana" if id == "gold" else id, {})
		var foot: Variant = definition.get("foot_anchor")
		if foot is Array and foot.size() == 2:
			_interaction_feet[id] = Vector2(float(foot[0]), float(foot[1]))
	for id: String in _interaction_widths:
		var texture: Texture2D = _interaction_textures.get(id) as Texture2D
		if texture == null:
			continue
		var pixels: Image = texture.get_image()
		if id == "barrel":
			pixels = pixels.get_region(Rect2i(128, 0, 128, 128))
		var width: int = pixels.get_used_rect().size.x
		if width > 0:
			_interaction_widths[id] = float(width)

func pulse_feedback_snapshot() -> Dictionary:
	return {
		"active": _pulse_remaining > 0.0,
		"remaining": _pulse_remaining,
		"origin": _pulse_origin,
		"radius": _pulse_radius,
		"affected": _pulse_affected,
		"animated": _pulse_remaining > 0.0 and _pulse_animated and bool(settings.get("flash", true)),
	}

func skill_feedback_snapshot() -> Dictionary:
	return {
		"active": _skill_feedback_remaining > 0.0,
		"remaining": _skill_feedback_remaining,
		"text": _skill_feedback_text,
		"affected": _skill_feedback_affected,
		"origin": _skill_feedback_origin,
		"anchor": _skill_feedback_anchor,
		"text_width": _skill_feedback_text_width,
	}

func _on_pulse_cast(origin: Vector2, affected: int) -> void:
	if not active or sim == null or sim.complete or not origin.is_finite():
		return
	var pulse: Dictionary = sim.snapshot().get("pulse", {})
	var radius: float = float(pulse.get("last_cast_radius", 0.0))
	var uses: int = int(pulse.get("uses", 0))
	if uses <= 0 or uses == _pulse_feedback_use or not is_finite(radius) or radius <= 0.0:
		return
	_pulse_feedback_use = uses
	_pulse_origin = origin
	_pulse_radius = radius
	_pulse_affected = maxi(0, affected)
	_pulse_remaining = PULSE_FEEDBACK_LIFE
	_pulse_animated = bool(settings.get("flash", true))
	_skill_feedback_affected = _pulse_affected
	_skill_feedback_origin = origin
	_skill_feedback_text = "受控 ×%d" % _pulse_affected if _pulse_affected > 0 else "未受控"
	_skill_feedback_text_width = _dash_evasion_font.get_string_size(_skill_feedback_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SKILL_FEEDBACK_FONT_SIZE).x if _dash_evasion_font != null else 0.0
	var half_width: float = _skill_feedback_text_width * 0.5
	var safe: Rect2 = _feedback_safe_rect()
	var anchor_y: float = origin.y + 54.0
	if anchor_y > safe.end.y:
		anchor_y = origin.y - 62.0
	_skill_feedback_anchor = Vector2(
		clampf(origin.x, safe.position.x + half_width, safe.end.x - half_width),
		clampf(anchor_y, safe.position.y + SKILL_FEEDBACK_FONT_SIZE, safe.end.y))
	_skill_feedback_remaining = SKILL_FEEDBACK_LIFE if _damage_flash <= 0.0 and _dash_evasion_remaining <= 0.0 else 0.0
	if sound != null:
		sound.play_cue("pulse_hit" if _pulse_affected > 0 else "pulse", -20.0, "pulse")
	hud_changed.emit(hud_snapshot())
	_request_redraw()

func _advance_pulse_feedback(delta: float) -> void:
	_skill_feedback_remaining = maxf(0.0, _skill_feedback_remaining - delta)
	if _skill_feedback_remaining < 0.0000001:
		_skill_feedback_remaining = 0.0
	_pulse_remaining = maxf(0.0, _pulse_remaining - delta)
	if _pulse_remaining < 0.0000001:
		_pulse_remaining = 0.0
		_pulse_animated = false

func _clear_pulse_feedback() -> void:
	_pulse_remaining = 0.0
	_pulse_origin = Vector2.ZERO
	_pulse_radius = 0.0
	_pulse_affected = 0
	_pulse_animated = false
	_pulse_feedback_use = -1
	_skill_feedback_remaining = 0.0
	_skill_feedback_text = ""
	_skill_feedback_affected = 0
	_skill_feedback_origin = Vector2.ZERO
	_skill_feedback_anchor = Vector2.ZERO
	_skill_feedback_text_width = 0.0

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
		sound.play_cue("dash", -20.0, "dash")
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
	_skill_feedback_remaining = 0.0
	_dash_evasion_remaining = DASH_EVASION_LIFE
	_dash_evasion_pulse_remaining = DASH_EVASION_LIFE if bool(settings.get("flash", true)) else 0.0
	if sound != null:
		sound.play_cue("evade", -22.0, "dash_evasion")
	hud_changed.emit(hud_snapshot())
	_request_redraw()

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
	afterimage.frame_index = WorldFlipperPlayerArt.frame_index(direction, _visual_time)
	afterimage.flip_h = WorldFlipperPlayerArt.flip_for(direction)
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
	return ControlBindings.movement()

func _on_player_hurt() -> void:
	_shake = 4.0
	sound.play("hurt", -7.0)
	hud_changed.emit(hud_snapshot())

func _on_damage_dealt(point: Vector2, amount: float, source: String, secondary: bool, target_uid: int = -1) -> void:
	if not point.is_finite() or not is_finite(amount) or amount <= 0.0:
		return
	var height: float = -38.0 if source == "skill:starfall" else -22.0
	_spawn_number(point + Vector2(0, height), amount, source, false, secondary, target_uid)
	# Damage events identify the enemy center, not an impact normal or contact point.
	if active and sim != null and not sim.complete and not secondary and bool(settings.get("flash", true)):
		_impact_painter.add_hit(point, source, target_uid)

func _on_player_damaged(amount: float, _source_id: String, _kind: String, origin: Vector2) -> void:
	_dash_evasion_remaining = 0.0
	_dash_evasion_pulse_remaining = 0.0
	_skill_feedback_remaining = 0.0
	if sound != null:
		sound.cancel_cue("dash_evasion")
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
	if sound != null:
		sound.stop_combat_cues()
	clear_pending_actions()
	_clear_dash_afterimages()
	_clear_dash_evasion_feedback()
	_clear_pulse_feedback()
	_bumper_flashes.clear()
	_crate_flashes.clear()
	_clear_boss_feedback()
	_enemy_telegraphs.clear()
	_impact_painter.clear()
	_active_skill_painter.clear()
	_grounding_painter.clear()
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
	number.font_size = 24 if player_hit else 12
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
	return ("-" if player_hit else "") + value

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
	if sound != null:
		sound.stop_combat_cues()
	clear_pending_actions()
	_clear_dash_afterimages()
	_clear_dash_evasion_feedback()
	_clear_pulse_feedback()
	_bumper_flashes.clear()
	_crate_flashes.clear()
	_clear_boss_feedback()
	_enemy_telegraphs.clear()
	_impact_painter.clear()
	_active_skill_painter.clear()
	_grounding_painter.clear()
	hud_changed.emit(hud_snapshot())
	wave_ended.emit(victory, reason)

func hud_snapshot() -> Dictionary:
	var value: Dictionary = sim.snapshot()
	value["boss_intro_left"] = maxf(0.0, BOSS_INTRO_SECONDS - sim.elapsed) if _boss_alive() else 0.0
	value["arena_id"] = _arena_id
	value["arena_name"] = _arena_name
	value["terrain_name"] = ArenaCatalog.terrain_name(_arena_id, sim.player_position)
	value["terrain_multiplier"] = ArenaCatalog.movement_multiplier(_arena_id, sim.player_position)
	value["minimap"] = minimap_snapshot()
	value["rogue"] = {"core_id": sim.run.core_id, "active_route": sim.run.active_route,
		"hunter_alive": sim.hunter != null and sim.hunter.active and sim.hunter.hunter,
		"hunter_defeated": sim.run.hunter_defeated}
	if stress_mode:
		value["benchmark"] = true
		value["time_left"] = benchmark_time_left
		value["enemies"] = sim.enemy_count
		value["projectiles"] = sim.shot_count
	return value

func minimap_snapshot() -> Dictionary:
	if sim == null:
		return {}
	var enemies: Array[Dictionary] = []
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active and enemy.health > 0.0 and enemy.position.is_finite():
			enemies.append({"position": enemy.position, "boss": enemy.definition.id == "boss", "hunter": enemy.hunter})
	var zones: Array[Dictionary] = []
	for zone: Dictionary in ArenaCatalog.definition(_arena_id)["zones"]:
		zones.append({"center": Vector2(float(zone["center"][0]), float(zone["center"][1])),
			"radius": Vector2(float(zone["radius"][0]), float(zone["radius"][1]))})
	var obstacles: Array[Dictionary] = sim.obstacles.snapshot()
	for obstacle: Dictionary in obstacles:
		obstacle["kind"] = "crate" if str(obstacle["id"]).begins_with("crate:") else "prop"
	var interactions: Dictionary = sim.interactions.snapshot()
	return {"bounds": CombatSim.ARENA, "player": sim.player_position, "facing": sim.player_direction,
		"view": camera_view(), "enemies": enemies, "zones": zones, "arena_id": _arena_id,
		"obstacles": obstacles, "pickups": interactions.get("pickups", []), "pinball_active": bool(sim.pinball_snapshot().get("active", false))}

func _draw() -> void:
	if arena_texture != null:
		draw_texture_rect(arena_texture, ArenaCatalog.art_rect(), false)
	if sim == null:
		return
	_draw_atmosphere()
	_draw_pulse_feedback()
	_draw_ground_contacts()
	_draw_obstacles()
	_draw_player_ground()
	_draw_souls()
	_draw_enemies()
	_draw_boss_art()
	_draw_friendly_shots()
	_draw_effects()
	_active_skill_painter.draw(self)
	_draw_impact_feedback()
	_draw_rune_feedback()
	_draw_boss_weakpoints()
	_draw_outgoing_feedback()
	_draw_player()
	_draw_skill_feedback()
	_draw_dash_evasion_feedback()
	_draw_feedback()
	# Hostile projectiles and telegraphs stay above all friendly spell effects.
	_draw_danger()

func _draw_ground_contacts() -> void:
	if not active or sim == null:
		_grounding_painter.clear()
		return
	_grounding_painter.rebuild(sim, camera_view())
	_grounding_painter.draw(self)

func _draw_obstacles() -> void:
	var visible: Rect2 = camera_view()
	for obstacle: Dictionary in _arena_obstacles:
		var center: Vector2 = obstacle["center"]
		var radius: float = obstacle["radius"]
		var art_id: String = obstacle["art_id"]
		var texture: Texture2D = _obstacle_textures.get(art_id) as Texture2D
		if texture == null:
			continue
		# All normalized props share a foot anchor; their opaque width fills the collider.
		var source_width: float = OBSTACLE_ART_WIDTHS.get(art_id, 69.0)
		var scale: float = radius * 2.0 / source_width
		var pressure: float = _interaction_flash(_bumper_flashes, center, BUMPER_FLASH_LIFE) if art_id == "bumper" else 0.0
		var stretch := Vector2(1.0 + pressure * 0.08, 1.0 - pressure * 0.14)
		var extent := Vector2.ONE * 96.0 * scale * stretch
		var target := Rect2(center - Vector2(48, 84) * scale * stretch, extent)
		if target.intersects(visible):
			draw_texture_rect(texture, target, false, Color(1.0 + pressure * 0.18, 1.0 + pressure * 0.18, 1.0 + pressure * 0.12))
	_draw_interactions()

func _draw_interactions() -> void:
	var state: Dictionary = interaction_presentation_snapshot()
	var visible: Rect2 = camera_view()
	for crate: Dictionary in state["crates"]:
		var target: Rect2 = crate["rect"]
		var texture: Texture2D = _interaction_textures.get(str(crate["texture"])) as Texture2D
		if texture == null or not target.intersects(visible):
			continue
		if bool(crate["active"]):
			_draw_interaction_shadow(crate["position"], float(crate["radius"]) * 0.95, 0.20)
		if str(crate["texture"]) == "chest":
			draw_texture_rect(texture, target, false)
		else:
			var frame: int = int(crate["frame"])
			draw_texture_rect_region(texture, target, Rect2(Vector2(frame % 4, floorf(float(frame) / 4.0)) * 128.0, Vector2.ONE * 128.0))
	for pickup: Dictionary in state["pickups"]:
		var target: Rect2 = pickup["rect"]
		var texture: Texture2D = _interaction_textures.get(str(pickup["kind"])) as Texture2D
		if texture == null or not target.intersects(visible):
			continue
		_draw_interaction_shadow(pickup["position"], 8.0 if str(pickup["kind"]) == "gold" else 9.0, 0.16)
		draw_texture_rect(texture, target, false)

func _draw_interaction_shadow(center: Vector2, radius: float, opacity: float) -> void:
	draw_set_transform(center + Vector2(0, 1), 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, radius, Color(Color("253d54"), opacity))
	draw_set_transform(Vector2.ZERO)

func _draw_skill_feedback() -> void:
	if _skill_feedback_remaining <= 0.0 or _dash_evasion_font == null:
		return
	_draw_skill_feedback_text(_skill_feedback_anchor)

func _draw_skill_feedback_text(anchor: Vector2) -> void:
	var point: Vector2 = anchor - Vector2(_skill_feedback_text_width * 0.5, 0)
	var color: Color = Color("d4c5e2") if _skill_feedback_affected > 0 else Color("b5aebd")
	draw_string_outline(_dash_evasion_font, point, _skill_feedback_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SKILL_FEEDBACK_FONT_SIZE, 1, Color("0c121a"))
	draw_string(_dash_evasion_font, point, _skill_feedback_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SKILL_FEEDBACK_FONT_SIZE, color)

func _draw_pulse_feedback() -> void:
	if _pulse_remaining <= 0.0 or _pulse_radius <= 1.0:
		return
	_draw_pulse_range(_pulse_origin, _pulse_radius)
	if _pulse_animated and bool(settings.get("flash", true)):
		var progress: float = clampf(1.0 - _pulse_remaining / PULSE_FEEDBACK_LIFE, 0.0, 1.0)
		_draw_pulse_animation(_pulse_origin, _pulse_radius * (0.20 + progress * 0.72), progress)

func _draw_pulse_range(origin: Vector2, radius: float) -> void:
	draw_arc(origin, radius - 1.0, 0.0, TAU, 72, Color(0.13, 0.35, 0.45, 0.48), 1.0, true)

func _draw_pulse_animation(origin: Vector2, radius: float, progress: float) -> void:
	var tint: Color = Color(0.12, 0.52, 0.56, (1.0 - progress) * 0.28)
	draw_arc(origin, radius, 0.0, TAU, 48, tint, 1.0, true)
	for index: int in 6:
		var direction: Vector2 = Vector2.from_angle(float(index) * TAU / 6.0)
		draw_line(origin + direction * maxf(0.0, _pulse_radius - 7.0), origin + direction * maxf(0.0, _pulse_radius - 2.0), tint, 1.0, true)

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
	var visible: Rect2 = _cosmetic_visible_rect()
	for number: FloatingNumber in _numbers:
		if number.player_hit == player_hit and number_draw_bounds(number).intersects(visible):
			_draw_number(number)

func _draw_number(number: FloatingNumber) -> void:
	if _number_font == null:
		return
	var alpha: float = minf(1.0, number.life / 0.24)
	var point: Vector2 = number.position - Vector2(number.text_width * 0.5, 0)
	draw_string_outline(_number_font, point, number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, number.font_size, 2 if number.font_size >= 24 else 1, Color(0.025, 0.035, 0.06, alpha * 0.9))
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
	var safe: Rect2 = _feedback_safe_rect()
	if anchor.y - 16.0 < safe.position.y:
		anchor.y = sim.player_position.y + 72.0
	var half_width: float = _dash_evasion_text_width * 0.5
	anchor.x = clampf(anchor.x, safe.position.x + half_width, safe.end.x - half_width)
	anchor.y = clampf(anchor.y, safe.position.y + 16.0, safe.end.y)
	return anchor

func _draw_dash_evasion_pulse(center: Vector2) -> void:
	var strength: float = clampf(_dash_evasion_pulse_remaining / DASH_EVASION_LIFE, 0.0, 1.0)
	var radius: float = 17.0 + (1.0 - strength) * 2.0
	draw_arc(center, radius, PI * 0.12, PI * 0.88, 12, Color(0.68, 0.88, 0.90, strength * 0.24), 1.25, true)

func _draw_dash_evasion_text(anchor: Vector2) -> void:
	if _dash_evasion_font == null:
		return
	var point: Vector2 = anchor - Vector2(_dash_evasion_text_width * 0.5, 0)
	draw_string_outline(_dash_evasion_font, point, DASH_EVASION_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, DASH_EVASION_FONT_SIZE, 1, Color("0c121a"))
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
	var view: Rect2 = camera_view()
	for index: int in 22:
		var phase: float = float(index) * 2.39996
		var point := Vector2(
			view.position.x + 40.0 + fposmod(float(index) * 127.3 + sin(_visual_time * 0.12 + phase) * 19.0, view.size.x - 80.0),
			view.position.y + 100.0 + fposmod(float(index) * 73.7 - _visual_time * (2.0 + float(index % 3)), view.size.y - 220.0))
		var alpha: float = 0.07 + (sin(_visual_time * 0.7 + phase) + 1.0) * 0.035
		draw_circle(point, 1.0 if index % 3 else 1.5, Color(_arena_color, alpha))

func _draw_souls() -> void:
	var visible: Rect2 = _cosmetic_visible_rect()
	for soul: CombatSim.Soul in sim.souls:
		if not soul.active or not soul_draw_bounds(soul).intersects(visible):
			continue
		_draw_soul(soul)

func _draw_soul(soul: CombatSim.Soul) -> void:
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
			var tint: Color = _enemy_tint(enemy)
			if enemy.hunter:
				draw_arc(enemy.position + Vector2(0, 5), enemy.radius + 8.0, 0, TAU, 28, Color("c87866"), 2.0, true)
			draw_texture_rect(texture, enemy_draw_rect(enemy, bob, breathing), false, tint)
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

func enemy_draw_rect(enemy: CombatSim.Enemy, bob: float, breathing: float) -> Rect2:
	var size: float = enemy.radius * 3.0 + 15.0
	var impact: float = 0.0
	if bool(settings.get("flash", true)) and is_finite(enemy.hurt_timer):
		impact = clampf((enemy.hurt_timer - ENEMY_HIT_TIMER_CUTOFF) / ENEMY_HIT_PULSE_SECONDS, 0.0, 1.0)
		impact *= impact * (0.5 if enemy.definition.id == "boss" else 1.0)
	var width: float = size * (1.0 + breathing) * (1.0 + impact * 0.04)
	var height: float = size * (1.0 - impact * 0.05)
	var bottom: float = enemy.position.y + size * 0.34 + bob
	return Rect2(Vector2(enemy.position.x - width * 0.5, bottom - height), Vector2(width, height))

func _enemy_tint(enemy: CombatSim.Enemy) -> Color:
	var base: Color = Color.WHITE
	if enemy.slow_timer > 0.0:
		base = Color("b4e9ed")
	elif enemy.pulse_hinder_timer > 0.0 and not enemy.hunter and enemy.definition.id != "boss":
		base = PULSE_HINDER_TINT
	if not bool(settings.get("flash", true)) or not is_finite(enemy.hurt_timer) or enemy.hurt_timer <= ENEMY_HIT_TIMER_CUTOFF:
		return base
	# The simulation retains its 100ms receipt; only the first 60ms brighten the art.
	var progress: float = clampf((enemy.hurt_timer - ENEMY_HIT_TIMER_CUTOFF) / ENEMY_HIT_PULSE_SECONDS, 0.0, 1.0)
	var gain: float = 1.0 + ENEMY_HIT_PEAK_GAIN * progress * progress
	return Color(base.r * gain, base.g * gain, base.b * gain, 1.0)

func _draw_friendly_shots() -> void:
	_projectile_painter.rebuild(sim.shots, _cosmetic_visible_rect())
	_projectile_painter.draw(self)

func _draw_player_ground() -> void:
	var center: Vector2 = sim.player_position
	draw_texture_rect(glow_texture, Rect2(center - Vector2(44, 34), Vector2(88, 70)), false, Color(0.89, 0.78, 1.0, 0.16))
	draw_set_transform(center + Vector2(0, 9), 0.0, Vector2(1.0, 0.48))
	draw_texture_rect(seal_texture, Rect2(-Vector2.ONE * 32.0, Vector2.ONE * 64.0), false, Color(1.0, 0.95, 0.85, 0.24 + sin(_visual_time * 1.6) * 0.03))
	draw_set_transform(Vector2.ZERO)

func _player_tint() -> Color:
	var tint: Color = Color.WHITE
	if sim.dash_time_left > 0.0:
		return Color("d7e7e6") if bool(settings.get("flash", true)) else tint
	if sim.invulnerability > 0.0 and bool(settings.get("flash", true)):
		tint.a = 0.55 + sin(_visual_time * 35.0) * 0.30
	return tint

func _player_motion() -> Vector2:
	if sim == null:
		return Vector2.ZERO
	return sim.dash_direction if sim.dash_time_left > 0.0 else sim.player_velocity


func _player_frame_index() -> int:
	return WorldFlipperPlayerArt.frame_index(_player_motion(), _visual_time)


func _player_flip_h() -> bool:
	return WorldFlipperPlayerArt.flip_for(_player_motion())


func _draw_player_texture(frame_index: int, bob: float, tint: Color) -> void:
	var hero: HeroDef = HeroCatalog.definition(sim.run.hero_id if sim != null and sim.run != null else "alk")
	var scale_factor: float = 68.0 / 96.0
	var target := Rect2(Vector2(-hero.foot_anchor.x * scale_factor, 15.875 - hero.foot_anchor.y * scale_factor + bob), Vector2.ONE * hero.frame_size * scale_factor)
	if frame_index > 0 and _player_atlas != null:
		draw_texture_rect_region(_player_atlas, target, WorldFlipperPlayerArt.frame_rect(frame_index, hero.frame_size), tint)
	else:
		draw_texture_rect(textures["player"], target, false, tint)

func _load_hero_art() -> void:
	var hero: HeroDef = HeroCatalog.definition(sim.run.hero_id if sim != null and sim.run != null else "alk")
	textures["player"] = load(hero.idle_path) as Texture2D
	_player_atlas = load(hero.atlas_path) as Texture2D


func _draw_player() -> void:
	var center: Vector2 = sim.player_position
	var bob: float = sin(_visual_time * 9.0) * minf(2.0, sim.player_velocity.length() * 0.012)
	var tint: Color = _player_tint()
	var lean: float = clampf(sim.player_velocity.x * 0.0002, -0.045, 0.045)
	if active and bool(sim.pinball_snapshot().get("active", false)):
		_draw_ball_player(tint)
	else:
		_draw_dash_afterimages()
		draw_set_transform(center, lean, Vector2(-1.0 if _player_flip_h() else 1.0, 1.0))
		_draw_player_texture(_player_frame_index(), bob, tint)
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
		draw_string_outline(_number_font, point, extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 1, Color("0d111b"))
		draw_string(_number_font, point, extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f0e5cc"))

func _draw_ball_player(tint: Color) -> void:
	var ball: Dictionary = sim.pinball_snapshot()
	var frame: int = ball_frame_index(float(ball.get("age", 0.0))) if bool(settings.get("flash", true)) else 0
	var orb: Texture2D = _interaction_textures.get("ball") as Texture2D
	var center: Vector2 = sim.player_position
	var animated: bool = bool(settings.get("flash", true))
	if animated:
		var velocity: Vector2 = ball.get("velocity", Vector2.ZERO)
		var streaks: PackedVector2Array = ball_speed_lines(center, velocity)
		for index: int in range(0, streaks.size(), 2):
			draw_line(streaks[index], streaks[index + 1], Color(Color("253d54"), 0.72), 2.0)
			draw_line(streaks[index], streaks[index + 1], Color(Color("efca7d"), 0.85), 1.0)
		draw_circle(center, 17.0, Color(Color("efca7d"), 0.06))
	draw_arc(center, 18.0, 0.0, TAU, 40, Color("253d54"), 2.0)
	draw_arc(center, 18.0, 0.0, TAU, 40, Color("efca7d"), 1.0)
	if orb != null:
		draw_texture_rect_region(orb, Rect2(center - Vector2.ONE * 24.0, Vector2.ONE * 48.0), Rect2(Vector2(frame * 64, 0), Vector2.ONE * 64.0))
	if not textures.has("player"):
		return
	var target: Rect2 = _ball_identity_rect()
	# The original character remains legible inside the shared energy form.
	for offset: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_texture_rect(textures["player"], Rect2(target.position + offset, target.size), false, Color("253d54"))
	draw_texture_rect(textures["player"], target, false, tint)

static func ball_speed_lines(center: Vector2, velocity: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not center.is_finite() or not velocity.is_finite() or velocity.is_zero_approx():
		return result
	var backward: Vector2 = -velocity.normalized()
	var tangent: Vector2 = backward.orthogonal()
	for side: float in [-1.0, 1.0]:
		result.append(center + backward * 22.0 + tangent * side * 7.0)
		result.append(center + backward * 35.0 + tangent * side * 7.0)
	return result

func _ball_identity_rect() -> Rect2:
	var hero: HeroDef = HeroCatalog.definition(sim.run.hero_id)
	var factor: float = 32.0 / float(hero.frame_size)
	return Rect2(sim.player_position + Vector2(-hero.foot_anchor.x * factor, 10.0 - hero.foot_anchor.y * factor), Vector2.ONE * 32.0)

func _draw_dash_afterimages() -> void:
	if not bool(settings.get("flash", true)) or not textures.has("player"):
		return
	for offset: int in DASH_AFTERIMAGE_LIMIT:
		var index: int = (_dash_afterimage_next + offset) % DASH_AFTERIMAGE_LIMIT
		var afterimage: DashAfterimage = _dash_afterimages[index]
		if afterimage.life <= 0.0:
			continue
		var opacity: float = 0.16 * clampf(afterimage.life / DASH_AFTERIMAGE_LIFE, 0.0, 1.0)
		draw_set_transform(afterimage.position, afterimage.lean, Vector2(-1.0 if afterimage.flip_h else 1.0, 1.0))
		_draw_player_texture(afterimage.frame_index, 0.0, Color(0.70, 0.88, 0.90, opacity))
	draw_set_transform(Vector2.ZERO)

func _draw_effects() -> void:
	var visible: Rect2 = _cosmetic_visible_rect()
	for effect: CombatSim.Effect in sim.effects:
		if effect_draw_bounds(effect).intersects(visible):
			_draw_effect(effect)

func _draw_effect(effect: CombatSim.Effect) -> void:
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
	var current: Dictionary = boss_danger_snapshot()
	for corridor: Dictionary in current.get("safe_channels", []):
		_draw_danger_shape(corridor, 0.0, true)
	for shape: Dictionary in current.get("geometry", []):
		_draw_danger_shape(shape, float(current.get("progress", 0.0)))
	for zone: CombatSim.WarningZone in sim.zones:
		if zone.triggered and zone.source_cast_id <= 0:
			continue
		var shape: Dictionary = {"shape": zone.shape, "position": zone.position, "radius": zone.radius,
			"direction": zone.direction, "length": zone.length, "width": zone.width}
		_draw_danger_shape(shape, clampf(zone.age / zone.delay, 0.0, 1.0) if zone.delay > 0.0 else 1.0)
	# Live hostile rounds remain above all warning strokes.
	for shot: CombatSim.Shot in sim.shots:
		if not shot.active or not shot.hostile:
			continue
		draw_circle(shot.position, shot.radius + 3.0, Color("542e35"))
		draw_circle(shot.position, shot.radius, Color("ff8666"))
		draw_arc(shot.position, shot.radius, 0, TAU, 12, Color("ffdfb1"), 1.5, true)
		draw_circle(shot.position, 2.5, Color("fff2d7"))

static func lane_polygon(shape: Dictionary) -> PackedVector2Array:
	return DangerPainter.lane_polygon(shape)

func _draw_danger_shape(shape: Dictionary, progress: float, safe: bool = false) -> void:
	DangerPainter.draw(self, shape, progress, safe)

func _draw_boss_art() -> void:
	if _boss_alive():
		BossArtPainter.draw(self, sim.boss.position, sim.boss_encounter.snapshot(), _visual_time, bool(settings.get("flash", true)))

func _maintain_stress() -> void:
	# This deliberately retains 300 enemies, 600 live moving projectiles and 200 drops.
	sim.run.health = sim.run.stat("max_health")
	for enemy: CombatSim.Enemy in sim.enemies:
		if enemy.active:
			enemy.position.x = wrapf(enemy.position.x + 0.9, 100.0, 1180.0)
			enemy.position.y = 175.0 + float(enemy.slot % 15) * 27.0
			enemy.position = sim.obstacles.free_point(enemy.position, enemy.radius)
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
