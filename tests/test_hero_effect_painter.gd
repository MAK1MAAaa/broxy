extends SceneTree
## Real bounded delivery snapshots feed the exact commands used by the native painter.

var _checks: int = 0
var _failures: int = 0

class DrawFixture extends Node2D:
	var value: Dictionary = {}
	var draws: int = 0
	func _draw() -> void:
		HeroEffectPainter.draw(self, value, true)
		draws += 1

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _sim() -> CombatSim:
	var state := RunState.new()
	state.begin(20261031, "", "reliquary", "hanabi")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.invulnerability = 9999.0
	sim._cooldowns.fill(9999.0)
	sim.obstacles.configure([])
	sim.interactions = ArenaInteractions.new()
	sim.player_position = Vector2(640, 360)
	sim.player_direction = Vector2.RIGHT
	return sim

func _casts(sim: CombatSim, count: int = 4) -> void:
	for cast: int in count:
		sim._charge_owned_skills(9999.0)
		_check(sim.try_hero_skill(), "The pressure fixture grants charge through the real cooldown helper and queues a complete five-bomb delivery")

func _run() -> void:
	var sim: CombatSim = _sim()
	_casts(sim)
	var reserved: Dictionary = sim.hero_effects_snapshot()
	var preparing: Dictionary = HeroEffectPainter.geometry_snapshot(reserved, true)
	_check(reserved["reserved_bombs"] == 20 and reserved["active_bombs"] == 0 and preparing["preparing_count"] == 20 and preparing["commands"].size() == 80, "Four real casts reserve all twenty slots and show charge tells without pretending the bombs have launched")
	_check_geometry(preparing, 0, 0, 7, 20)
	sim.step(55.0 / 60.0, Vector2.ZERO)
	var live: Dictionary = sim.hero_effects_snapshot()
	_check(live["active_bombs"] == 20, "The actual skill runtime reaches its declared twenty-bomb capacity")
	var geometry: Dictionary = HeroEffectPainter.geometry_snapshot(live, true)
	_check(geometry["bomb_count"] == 20 and geometry["burst_count"] == 0 and geometry["commands"].size() == 100, "Every real bomb has exactly the five bounded native paint commands")
	_check_geometry(geometry, 20, 0, 7)
	sim.step(1.2, Vector2.ZERO)
	var burst: Dictionary = sim.hero_effects_snapshot()
	_check(burst["active_bombs"] == 0 and burst["bursts"].size() == 20 and burst["explosions"] == 20, "Real simulation expiry produces one blast receipt per bomb")
	sim._charge_owned_skills(9999.0)
	var unavailable: Dictionary = sim.hero_effects_snapshot()
	_check(not sim.try_hero_skill() and sim.hero_effects_snapshot() == unavailable, "Twenty persistent impact areas reject a new five-area reservation without overwriting actual blasts")
	sim.step(0.5, Vector2.ZERO)
	_casts(sim, 3)
	sim.step(55.0 / 60.0, Vector2.ZERO)
	sim.step(1.2, Vector2.ZERO)
	_casts(sim, 1)
	var mixed: Dictionary = sim.hero_effects_snapshot()
	geometry = HeroEffectPainter.geometry_snapshot(mixed, true)
	_check(geometry["bomb_count"] == 0 and geometry["preparing_count"] == 5 and geometry["burst_count"] == 15 and geometry["commands"].size() == 125 and geometry["commands"].size() <= HeroEffectPainter.MAX_COMMANDS, "Old real blasts and newly reserved bombs retain their complete bounded native commands")
	_check_geometry(geometry, 0, 15, 7, 5)
	var static_geometry: Dictionary = HeroEffectPainter.geometry_snapshot(mixed, false)
	_check(static_geometry["bomb_count"] == 0 and static_geometry["preparing_count"] == 5 and static_geometry["burst_count"] == 15 and static_geometry["commands"].size() == 35, "Disabling flash retains actual moving bodies and one exact range ring per blast without radial flashes")
	_check_geometry(static_geometry, 0, 15, 1, 5)
	var before: String = _signature(sim)
	var original: String = JSON.stringify(mixed)
	for repeat: int in 25:
		var returned: Dictionary = HeroEffectPainter.geometry_snapshot(mixed, repeat % 2 == 0)
		returned["commands"].clear()
		returned["bounds"].clear()
	_check(_signature(sim) == before and JSON.stringify(mixed) == original, "Repeated geometry queries and caller edits cannot mutate physical delivery, clocks, inventory or any private RNG")
	var canvas := DrawFixture.new()
	canvas.value = mixed
	root.add_child(canvas)
	for frame: int in 3:
		await process_frame
	if DisplayServer.get_name() != "headless":
		_check(canvas.draws > 0, "The exact twenty-bomb/twenty-burst state also reaches a real native CanvasItem draw")
	_check(_signature(sim) == before, "Native draw frames do not advance the authoritative bomb or blast clocks")
	canvas.queue_free()
	sim.clear_hero_effects()
	var cleared: Dictionary = HeroEffectPainter.geometry_snapshot(sim.hero_effects_snapshot(), true)
	_check(cleared["commands"].is_empty() and cleared["bounds"].is_empty(), "Stopping a delivery leaves no stale native art or bounds")
	await process_frame
	print("HeroEffectPainter: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check_geometry(value: Dictionary, bombs: int, bursts: int, burst_commands: int, preparing: int = 0) -> void:
	var bounds: Array = value["bounds"]
	var commands: Array = value["commands"]
	_check(bounds.size() == bombs + bursts + preparing and commands.size() <= HeroEffectPainter.MAX_COMMANDS, "Every authoritative entity receives one finite bounded paint region")
	for index: int in commands.size():
		var command: Dictionary = commands[index]
		var entity: int = index / 5 if index < bombs * 5 else bombs + (index - bombs * 5) / 4 if index < bombs * 5 + preparing * 4 else bombs + preparing + (index - bombs * 5 - preparing * 4) / burst_commands
		var extent: Rect2
		match str(command["kind"]):
			"line":
				var from: Vector2 = command["from"]
				var to: Vector2 = command["to"]
				extent = Rect2(from.min(to), (to - from).abs()).grow(float(command["width"]) * 0.5)
			"rect":
				extent = command["rect"]
			"arc":
				var center: Vector2 = command["center"]
				var radius: float = command["radius"]
				extent = Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0).grow(1.0)
		_check(extent.position.is_finite() and extent.size.is_finite() and bounds[entity].grow(0.002).encloses(extent), "Actual native geometry including stroke width remains inside the matching physical delivery's declared bounds")

func _signature(sim: CombatSim) -> String:
	return JSON.stringify([sim.snapshot(), sim.run.backpack_snapshot(), sim.run.summary(), sim.interactions.snapshot(),
		str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state)])
