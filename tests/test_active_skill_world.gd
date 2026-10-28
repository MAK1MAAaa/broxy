extends SceneTree
## Queue identity, real cast feedback and cosmetic hit geometry through CombatWorld.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

class SilentSound extends SoundBank:
	var cues: Array[String] = []
	func _ready() -> void:
		pass
	func play_cue(_name: String, _volume: float, cue: String) -> void:
		cues.append(cue)

class World extends CombatWorld:
	func _movement() -> Vector2:
		return Vector2.UP

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_requests()
	_test_real_audio_dispatch()
	_test_effect_pool()
	_test_hit_geometry()
	for frame: int in 3:
		await process_frame
	await create_timer(0.1, true).timeout
	print("ActiveSkillWorld: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _world(ids: Array[String] = []) -> World:
	var world := World.new()
	world.sound = SilentSound.new()
	world.settings = {"flash": true, "shake": false}
	var state := RunState.new()
	state.begin(20261028, "bone")
	for id: String in ids:
		_check(not state.backpack.add("skill", id).is_empty(), "Fixture owns a real skill box: " + id)
	state._sync_backpack_projection()
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	return world

func _dispose(world: World) -> void:
	world.sound.free()
	world.free()

func _test_requests() -> void:
	var world: World = _world()
	_check(not world.request_skill(0) and not world.request_pulse() and not world.request_skill(1), "An empty backpack cannot queue either skill")
	_check(world.request_dash(), "Dash requires no backpack item")
	world._physics_process(STEP)
	_check(world.sim.dashes_used == 1 and world.sim.pulses_used == 0, "An empty backpack still performs its independent dash")
	_dispose(world)
	world = _world(["starfall", "arc_slash"])
	_check(not world.request_skill(-1) and not world.request_skill(2), "Only the two public skill slots can be queued")
	_check(world.request_pulse() and world.request_skill(1) and not world.request_skill(1), "Legacy slot-one API queues the actual starfall while E queues the second skill once")
	_check(world.sim.active_skill_snapshot(0)["uses"] == 0, "Input does not cast outside the physical step")
	world._physics_process(STEP)
	_check(world.sim.active_skill_snapshot(0)["uses"] == 1 and world.sim.active_skill_snapshot(1)["uses"] == 1, "Both queued skills consume one real fixed frame")
	_check(world._active_skill_painter.snapshot()["active"] == 2 and world.sound.cues.size() == 2, "Actual non-pulse casts generate bounded feedback and one cue each")
	world.apply_visual_settings({"flash": false, "shake": false})
	_check(world._active_skill_painter.snapshot()["animated"] == 0, "Turning flash off immediately removes animation from live effects")
	world.apply_visual_settings({"flash": true, "shake": false})
	_check(world._active_skill_painter.snapshot()["animated"] == 0, "Re-enabling flash cannot replay suppressed effects")
	world.stop()
	_check(world._active_skill_painter.snapshot()["active"] == 0, "Stopping clears skill effects")
	_dispose(world)
	world = _world(["pulse", "arc_slash"])
	_check(world.request_skill(1), "The second item queues by UID")
	var second_uid: int = int(world.sim.active_skill_snapshot(1)["uid"])
	_check(world.sim.run.sell_item(int(world.sim.active_skill_snapshot(0)["uid"])), "A real sale changes the slot projection before consumption")
	world._physics_process(STEP)
	_check(world.sim.active_skill_snapshot(0)["uid"] == second_uid and world.sim.active_skill_snapshot(0)["uses"] == 0, "A stale queued slot never redirects its cast to a different occupant")
	_check(world.request_skill(0), "The surviving item is usable from its new slot")
	world.clear_pending_actions()
	world._physics_process(STEP)
	_check(world.sim.active_skill_snapshot(0)["uses"] == 0 and not world._secondary_skill_pending, "Modal/focus cleanup cancels both pending skill slots")
	_dispose(world)

func _test_effect_pool() -> void:
	var painter = preload("res://scripts/combat/active_skill_painter.gd").new()
	_check(not painter.add_cast("pulse", Vector2.ZERO, Vector2.RIGHT, 144.0, true) and not painter.add_cast("starfall", Vector2.INF, Vector2.RIGHT, 112.0, true), "Invalid geometry and the separately rendered pulse are rejected")
	for index: int in 40:
		painter.add_cast("starfall", Vector2(400, 300), Vector2.RIGHT, 112.0, true)
	_check(painter.snapshot() == {"capacity": 8, "active": 8, "animated": 8}, "Cosmetic spam keeps the fixed eight-cast budget")
	painter.advance(0.0)
	painter.advance(NAN)
	_check(painter.snapshot()["active"] == 8, "Invalid time cannot corrupt the cosmetic pool")
	painter.advance(0.27)
	_check(painter.snapshot()["active"] == 0, "All cast art expires within its short lifetime")

func _test_real_audio_dispatch() -> void:
	var world: World = _world(["starfall", "arc_slash"])
	world.sound.free()
	var bank := SoundBank.new()
	root.add_child(bank)
	if DisplayServer.get_name() == "headless":
		for name: String in ["pulse", "pulse_hit"]:
			bank.streams[name] = load("res://assets/audio/%s.wav" % name)
		for index: int in 12:
			var voice := AudioStreamPlayer.new()
			bank.add_child(voice)
			bank.voices.append(voice)
	bank.set_volume(0.15)
	world.sound = bank
	world.request_skill(0)
	world.request_skill(1)
	world._physics_process(STEP)
	var live: int = bank.voices.filter(func(voice: AudioStreamPlayer) -> bool: return voice.playing and voice.stream == bank.streams["pulse"]).size()
	_check(live == 2, "Two same-frame successful casts dispatch two real audio voices without shared-tag throttling")
	world.stop()
	_check(bank.voices.all(func(voice: AudioStreamPlayer) -> bool: return not voice.playing), "Combat cleanup stops both UID-tagged real skill voices")
	bank.shutdown()
	_dispose(world)

func _test_hit_geometry() -> void:
	var world: World = _world()
	for id: String in ["chaser", "boss"]:
		var enemy: CombatSim.Enemy = world.sim.spawn_enemy(id, Vector2(500, 350))
		enemy.hurt_timer = 0.0
		var base: Rect2 = world.enemy_draw_rect(enemy, 1.0, 0.01)
		var position_before: Vector2 = enemy.position
		var radius_before: float = enemy.radius
		enemy.hurt_timer = 0.1
		var hit: Rect2 = world.enemy_draw_rect(enemy, 1.0, 0.01)
		var factor: float = 0.5 if id == "boss" else 1.0
		_check(is_equal_approx(hit.size.x / base.size.x, 1.0 + factor * 0.04) and is_equal_approx(hit.size.y / base.size.y, 1.0 - factor * 0.05), "Actual receipt creates the restrained hit silhouette: " + id)
		_check(is_equal_approx(hit.end.y, base.end.y) and is_equal_approx(hit.get_center().x, base.get_center().x), "Hit art keeps its ground anchor and horizontal center: " + id)
		_check(enemy.position == position_before and enemy.radius == radius_before, "Cosmetic hit geometry never changes simulation collision: " + id)
		world.apply_visual_settings({"flash": false})
		_check(world.enemy_draw_rect(enemy, 1.0, 0.01).is_equal_approx(base), "Flash-off restores the original silhouette: " + id)
		world.apply_visual_settings({"flash": true})
		enemy.hurt_timer = 0.04
		_check(world.enemy_draw_rect(enemy, 1.0, 0.01).is_equal_approx(base), "The final forty milliseconds no longer deform art: " + id)
	_dispose(world)
