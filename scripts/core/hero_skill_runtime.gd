class_name HeroSkillRuntime
extends RefCounted
## Bounded state for temporary attack power and physical Hanabi bomb deliveries.

const BOMB_LIMIT: int = 20
const BURST_LIMIT: int = 20
const BURST_LIFE: float = 0.24

class Bomb:
	var active: bool = false
	var uid: int = 0
	var position: Vector2 = Vector2.ZERO
	var previous: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var collision_radius: float = 9.0
	var blast_radius: float = 64.0
	var damage: float = 0.0
	var life: float = 0.0
	var total: float = 0.0
	var source: String = "hero_hanabi"
	var element: String = "fire"

class Burst:
	var active: bool = false
	var uid: int = 0
	var position: Vector2 = Vector2.ZERO
	var radius: float = 0.0
	var life: float = 0.0
	var source: String = "hero_hanabi"

var bombs: Array[Bomb] = []
var _bursts: Array[Burst] = []
var attack_bonus: float = 0.0
var attack_left: float = 0.0
var peak_bombs: int = 0
var explosions: int = 0
var _serial: int = 0
var _next_burst: int = 0

func _init() -> void:
	for index: int in BOMB_LIMIT:
		bombs.append(Bomb.new())
	for index: int in BURST_LIMIT:
		_bursts.append(Burst.new())

func clear() -> void:
	for bomb: Bomb in bombs:
		bomb.active = false
	for burst: Burst in _bursts:
		burst.active = false
	attack_bonus = 0.0
	attack_left = 0.0
	peak_bombs = 0
	explosions = 0
	_serial = 0
	_next_burst = 0

func advance_timers(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	attack_left = maxf(0.0, attack_left - delta)
	if attack_left < 0.0000001:
		attack_left = 0.0
		attack_bonus = 0.0
	for burst: Burst in _bursts:
		if burst.active:
			burst.life = maxf(0.0, burst.life - delta)
			burst.active = burst.life > 0.0

func set_attack_buff(amount: float, seconds: float) -> void:
	if not is_finite(amount) or not is_finite(seconds) or amount <= 0.0 or seconds <= 0.0:
		return
	attack_bonus = clampf(amount, 0.0, 1.0)
	attack_left = minf(seconds, 30.0)

func attack_multiplier() -> float:
	return 1.0 + attack_bonus if attack_left > 0.0 else 1.0

func can_spawn(count: int) -> bool:
	if count <= 0 or count > BOMB_LIMIT:
		return false
	var available: int = 0
	for bomb: Bomb in bombs:
		if not bomb.active:
			available += 1
	return available >= count

func spawn_bombs(parameters: Dictionary, origin: Vector2, direction: Vector2) -> bool:
	var count: int = int(parameters.get("projectiles", 5))
	var speed: float = float(parameters.get("projectile_speed", 280.0))
	var lifetime: float = float(parameters.get("projectile_life", 1.2))
	var damage: float = float(parameters.get("damage", 0.0))
	var radius: float = float(parameters.get("radius", 64.0))
	var spread: float = float(parameters.get("spread", 1.0))
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not can_spawn(count):
		return false
	for number: float in [speed, lifetime, damage, radius, spread]:
		if not is_finite(number) or number < 0.0:
			return false
	if speed <= 0.0 or lifetime <= 0.0 or radius <= 0.0:
		return false
	var index: int = 0
	for bomb: Bomb in bombs:
		if bomb.active:
			continue
		var offset: float = (float(index) / float(count - 1) - 0.5) * spread if count > 1 else 0.0
		var heading: Vector2 = direction.normalized().rotated(offset)
		_serial += 1
		bomb.active = true
		bomb.uid = _serial
		bomb.position = origin + heading * 18.0
		bomb.previous = bomb.position
		bomb.velocity = heading * speed
		bomb.collision_radius = 9.0
		bomb.blast_radius = radius
		bomb.damage = damage / float(count)
		bomb.life = lifetime
		bomb.total = lifetime
		bomb.source = str(parameters.get("id", "hero_hanabi"))
		bomb.element = str(parameters.get("element", "fire"))
		index += 1
		if index == count:
			break
	peak_bombs = maxi(peak_bombs, active_count())
	return true

func active_count() -> int:
	var count: int = 0
	for bomb: Bomb in bombs:
		if bomb.active:
			count += 1
	return count

func detonate(bomb: Bomb) -> void:
	if not bomb.active:
		return
	bomb.active = false
	explosions += 1
	var burst: Burst = _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % BURST_LIMIT
	burst.active = true
	burst.uid = bomb.uid
	burst.position = bomb.position
	burst.radius = bomb.blast_radius
	burst.life = BURST_LIFE
	burst.source = bomb.source

func snapshot() -> Dictionary:
	var visible_bombs: Array[Dictionary] = []
	for bomb: Bomb in bombs:
		if bomb.active:
			visible_bombs.append({"uid": bomb.uid, "position": bomb.position, "previous": bomb.previous,
				"velocity": bomb.velocity, "collision_radius": bomb.collision_radius, "blast_radius": bomb.blast_radius,
				"life": bomb.life, "total": bomb.total, "source": bomb.source})
	var visible_bursts: Array[Dictionary] = []
	for burst: Burst in _bursts:
		if burst.active:
			visible_bursts.append({"uid": burst.uid, "position": burst.position, "radius": burst.radius,
				"life": burst.life, "total": BURST_LIFE, "source": burst.source})
	return {"attack_bonus": attack_bonus, "attack_left": attack_left, "bombs": visible_bombs,
		"bursts": visible_bursts, "active_bombs": visible_bombs.size(), "peak_bombs": peak_bombs, "explosions": explosions}
