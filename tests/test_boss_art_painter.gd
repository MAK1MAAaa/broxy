extends SceneTree
## Boss ornaments remain bounded cosmetics driven by real encounter state.

const PAINTER = preload("res://scripts/combat/boss_art_painter.gd")
const ORIGIN: Vector2 = Vector2(640, 400)
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_charge_progress()
	_test_break_fade()
	_test_static_settings()
	_test_bounds_and_budget()
	_test_invalid_states()
	_test_state_purity()
	print("BossArtPainter: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _charge(left: float = 2.5) -> Dictionary:
	return {"active": true, "running": true, "phase": "charge", "charge_left": left, "charge_total": 2.5}

func _broken(left: float = 1.5) -> Dictionary:
	return {"active": true, "running": true, "phase": "break", "break_left": left}

func _test_charge_progress() -> void:
	var first: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _charge(), 0.0, true)
	var middle: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _charge(1.25), 0.0, true)
	var last: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _charge(0.0), 0.0, true)
	_check(first["state"] == "charge" and first["diamonds"].size() == 6, "A live charge presents six small original-body ornaments")
	_check(first["progress"] == 0.0 and middle["progress"] == 0.5 and last["progress"] == 1.0, "Contraction follows the authoritative remaining fraction")
	var anchor: Vector2 = ORIGIN + Vector2(0, -30)
	for index: int in first["diamonds"].size():
		var initial: Vector2 = first["diamonds"][index]["center"]
		var halfway: Vector2 = middle["diamonds"][index]["center"]
		var final: Vector2 = last["diamonds"][index]["center"]
		_check(initial.distance_squared_to(anchor) > halfway.distance_squared_to(anchor) and halfway.distance_squared_to(anchor) > final.distance_squared_to(anchor), "Each charge fragment converges toward the true body anchor")
		_check(first["diamonds"][index]["outline"].size() == 4 and first["diamonds"][index]["fill"].size() == 4, "Energy consists of pixel diamonds, not a new attack radius")
	var timed: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _charge(), 0.25, true)
	_check(timed["diamonds"][0]["center"] == first["diamonds"][0]["center"] and timed["diamonds"][0]["color"] != first["diamonds"][0]["color"], "Cosmetic time affects only the gentle charge glint at a fixed combat clock")

func _test_break_fade() -> void:
	var first: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _broken(), 0.0, true)
	var middle: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _broken(0.75), 0.0, true)
	var late: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _broken(0.15), 0.0, true)
	_check(first["state"] == "break" and first["diamonds"].size() == 4 and first["lines"].size() == 16, "Break uses four gold fragments and four short corner supports")
	_check(first["fade"] == 1.0 and middle["fade"] == 0.5 and is_equal_approx(float(late["fade"]), 0.1), "Gold fades over the actual one-and-a-half-second break clock")
	_check(first["diamonds"][0]["color"].a > middle["diamonds"][0]["color"].a and middle["diamonds"][0]["color"].a > late["diamonds"][0]["color"].a, "The actual emitted gold alpha follows remaining break time")
	_check(PAINTER.geometry_snapshot(ORIGIN, _broken(0.0), 0.0, true).is_empty(), "Expired break cannot leave gold ornaments behind")
	_check(first["diamonds"][0]["color"] != PAINTER.geometry_snapshot(ORIGIN, _charge(), 0.0, true)["diamonds"][0]["color"], "Charge and break have distinct color and silhouette states")

func _test_static_settings() -> void:
	for encounter: Dictionary in [_charge(1.0), _broken(1.0)]:
		var first: Dictionary = PAINTER.geometry_snapshot(ORIGIN, encounter, 0.0, false)
		var last: Dictionary = PAINTER.geometry_snapshot(ORIGIN, encounter, 54321.0, false)
		_check(first == last and not first.is_empty(), "Disabling flash retains the state silhouette without time-based flashing or rotation")
	var early: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _charge(), 0.0, false)
	var late: Dictionary = PAINTER.geometry_snapshot(ORIGIN, _charge(0.0), 0.0, false)
	_check(early["diamonds"] == late["diamonds"] and early["lines"].is_empty(), "The disabled-animation charge keeps static positions and omits moving trails")

func _test_bounds_and_budget() -> void:
	for position: Vector2 in [ORIGIN, Vector2(-900, -400), Vector2(2200, 1100)]:
		for animated: bool in [false, true]:
			for encounter: Dictionary in [_charge(), _charge(1.25), _charge(0.0), _broken(), _broken(0.05)]:
				var geometry: Dictionary = PAINTER.geometry_snapshot(position, encounter, 13.75, animated)
				var bounds: Rect2 = geometry["bounds"]
				var limit := Rect2(position - Vector2(80, 110), Vector2(160, 150))
				_check(bounds.position.is_finite() and bounds.size.is_finite() and limit.encloses(bounds), "All states stay inside a finite near-body budget without a floor aura")
				_check(geometry["diamonds"].size() <= PAINTER.MAX_DIAMONDS and geometry["lines"].size() / 2 <= PAINTER.MAX_LINE_SEGMENTS and int(geometry["draw_commands"]) <= PAINTER.MAX_DRAW_COMMANDS, "Maximum ornaments and rendering submissions are bounded")
				var face := Rect2(position + Vector2(-28, -70), Vector2(56, 58))
				var clear: bool = true
				for diamond: Dictionary in geometry["diamonds"]:
					for point: Vector2 in diamond["outline"]:
						clear = clear and point.is_finite() and point == point.round() and not face.has_point(point)
				_check(clear, "Pixel outlines retain the mask and weapon center instead of covering the character")

func _test_invalid_states() -> void:
	for value: Dictionary in [{}, {"phase": "recovery"}, {"phase": "stopped"}, {"phase": "other"},
		{"phase": "charge", "charge_left": 1.0, "charge_total": 0.0},
		{"phase": "charge", "charge_left": NAN, "charge_total": 2.5},
		{"phase": "charge", "charge_left": 1.0, "charge_total": "2.5"},
		{"phase": "break", "break_left": INF}, {"phase": "break", "break_left": -1.0}]:
		_check(PAINTER.geometry_snapshot(ORIGIN, value, 0.0, true).is_empty(), "Missing, resting and malformed states cannot manufacture live effects")
	var inactive: Dictionary = _charge()
	inactive["active"] = false
	_check(PAINTER.geometry_snapshot(ORIGIN, inactive, 0.0, true).is_empty(), "A completed encounter never retains charge ornaments")
	_check(PAINTER.geometry_snapshot(Vector2.INF, _charge(), 0.0, true).is_empty() and PAINTER.geometry_snapshot(ORIGIN, _charge(), NAN, true).is_empty(), "Nonfinite drawing inputs cannot reach CanvasItem commands")
	PAINTER.draw(null, ORIGIN, _charge(), 0.0, true)

func _test_state_purity() -> void:
	var state := RunState.new()
	state.begin(20261030, "bone", "reliquary", "alk")
	state.wave = 8
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim.invulnerability = 9999.0
	sim._cooldowns.fill(9999.0)
	sim.step(BossEncounter.OPENING_SECONDS, Vector2.ZERO)
	var encounter: Dictionary = sim.boss_encounter_snapshot()
	var before: String = _signature(sim)
	var original: String = JSON.stringify(encounter)
	for frame: int in 30:
		var geometry: Dictionary = PAINTER.geometry_snapshot(sim.boss.position, encounter, float(frame) * 0.25, frame % 2 == 0)
		if not geometry.is_empty():
			geometry["diamonds"][0]["center"] = Vector2.INF
	_check(_signature(sim) == before and JSON.stringify(encounter) == original, "Repeated geometry queries and caller mutations leave real boss timers, combat, inventory and all three RNGs untouched")
	var actual: Dictionary = PAINTER.geometry_snapshot(sim.boss.position, encounter, 0.0, true)
	_check(actual["diamonds"][0]["center"].is_finite(), "A previous returned snapshot cannot alter future geometry")

func _signature(sim: CombatSim) -> String:
	return JSON.stringify([sim.snapshot(), sim.boss_encounter_snapshot(), sim.boss_weakpoints(), sim.interactions.snapshot(),
		str(sim.rng.state), str(sim.run.rng.state), str(sim.interactions._rng.state), sim.run.backpack_snapshot()])
