extends SceneTree

const ENCOUNTER = preload("res://scripts/core/boss_encounter.gd")
const STEP: float = 1.0 / 60.0
const BOSS: Vector2 = Vector2(640, 208)
const PLAYER: Vector2 = Vector2(640, 365)
const BOUNDS: Rect2 = ArenaCatalog.WORLD_BOUNDS
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_test_release_and_deadline()
	_test_interrupt_any_order()
	_test_stale_identity_and_overlapping_hits()
	_test_phase_two_latching()
	_test_patterns_and_safe_channels()
	_test_large_steps()
	_test_purity_and_invalid_input()
	_test_relocation()
	_test_bounds_and_stop()
	print("BossEncounter: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _count(events: Array, type: String) -> int:
	var count: int = 0
	for event: Dictionary in events:
		count += 1 if str(event["type"]) == type else 0
	return count

func _first(events: Array, type: String) -> Dictionary:
	for event: Dictionary in events:
		if str(event["type"]) == type:
			return event
	return {}

func _signature(fsm: BossEncounter) -> String:
	return JSON.stringify([fsm.snapshot(), fsm.weakpoints_snapshot(), fsm.telegraph_snapshot()])

func _release(fsm: BossEncounter, ratio: float = 1.0, position: Vector2 = BOSS, player: Vector2 = PLAYER) -> Array[Dictionary]:
	var time: float = float(fsm.snapshot()["charge_left"])
	if time > 0.0:
		_check(_count(fsm.advance(time, position, player, ratio), "attack") == 0, "Advance cannot publish hostile damage before the friendly phase")
	return fsm.finish_friendly_step()

func _charged(ratio: float = 1.0, attack: String = "forest_storm", position: Vector2 = BOSS, player: Vector2 = PLAYER) -> BossEncounter:
	var fsm: BossEncounter = ENCOUNTER.new()
	fsm.begin(position, ratio, BOUNDS)
	var events: Array[Dictionary] = fsm.advance(BossEncounter.OPENING_SECONDS, position, player, ratio)
	_check(_count(events, "telegraph") == 1 and fsm.snapshot()["phase"] == "charge", "The opening creates one actual telegraph and charge")
	for _iteration: int in 4:
		if fsm.snapshot()["attack_id"] == attack:
			return fsm
		_release(fsm, ratio, position, player)
		fsm.advance(BossEncounter.RECOVERY_SECONDS, position, player, ratio)
	_check(false, "The authored sequence must reach the requested attack")
	return fsm

func _break_all(fsm: BossEncounter) -> void:
	var points: Array[Dictionary] = fsm.weakpoints_snapshot()
	for point: Dictionary in points:
		_check(fsm.damage_weakpoint(int(point["uid"]), int(point["cast_id"]), float(point["max_health"]) + 100.0)["hit"], "Every actual living weakpoint accepts damage in the current cast")

func _test_release_and_deadline() -> void:
	var fsm: BossEncounter = _charged()
	var state: Dictionary = fsm.snapshot()
	_check(state["attack_id"] == "forest_storm" and state["weakpoints_remaining"] == 3 and state["hold_position"] and state["damage_multiplier"] == 1.0, "Storm owns three living points and anchors its boss during a normal charge")
	_check(fsm.finish_friendly_step().is_empty(), "A friendly phase before the deadline cannot release the attack")
	var total: float = float(state["charge_total"])
	fsm.advance(total - STEP, BOSS, PLAYER, 1.0)
	_check(is_equal_approx(float(fsm.snapshot()["charge_left"]), STEP) and fsm.finish_friendly_step().is_empty(), "The penultimate charge step remains an honest full friendly opportunity")
	var advance_events: Array[Dictionary] = fsm.advance(STEP, BOSS, PLAYER, 1.0)
	_check(advance_events.is_empty() and fsm.snapshot()["release_pending"] and fsm.snapshot()["phase"] == "charge" and fsm.snapshot()["weakpoints_remaining"] == 3, "The deadline first becomes pending while its points remain hittable")
	var events: Array[Dictionary] = fsm.finish_friendly_step()
	_check(_count(events, "attack") == 3 and _count(events, "cast_released") == 1 and _count(events, "interrupted") == 0, "A missed charge releases precisely its three authored storm strikes")
	for event: Dictionary in events:
		_check(event["attack_id"] == "forest_storm" and event["cast_id"] == state["cast_id"] and event["source"] == "boss_attack:forest_storm:%d" % int(state["cast_id"]), "Every released record retains its precise attack and cast source identity")
	_check(fsm.snapshot()["phase"] == "recovery" and fsm.weakpoints_snapshot().is_empty() and fsm.finish_friendly_step().is_empty(), "Release consumes the pending cast exactly once and retires its points")
	_check(fsm.telegraph_snapshot().is_empty(), "A released cast cannot remain in the current telegraph snapshot")
	var survivor: BossEncounter = _charged()
	var points: Array[Dictionary] = survivor.weakpoints_snapshot()
	for index: int in 2:
		survivor.damage_weakpoint(int(points[index]["uid"]), int(points[index]["cast_id"]), 1000.0)
	_check(survivor.snapshot()["weakpoints_remaining"] == 1 and _count(_release(survivor), "attack") == 3, "One surviving point is sufficient to release the normal attack")
	var fair: BossEncounter = _charged()
	points = fair.weakpoints_snapshot()
	for index: int in 2:
		fair.damage_weakpoint(int(points[index]["uid"]), int(points[index]["cast_id"]), 1000.0)
	fair.advance(float(fair.snapshot()["charge_left"]), BOSS, PLAYER, 1.0)
	var final: Dictionary = fair.damage_weakpoint(int(points[2]["uid"]), int(points[2]["cast_id"]), 1000.0)
	events = fair.finish_friendly_step()
	_check(final["interrupted"] and _count(events, "attack") == 0 and _count(events, "interrupted") == 1 and _count(events, "break_started") == 1, "The final friendly hit on the exact deadline cancels release before entering break")

func _test_interrupt_any_order() -> void:
	var orders: Array = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	for ratio: float in [1.0, 0.49]:
		for order: Array in orders:
			var fsm: BossEncounter = _charged(ratio)
			var points: Array[Dictionary] = fsm.weakpoints_snapshot()
			_check(points.size() == 3 and points.all(func(point: Dictionary) -> bool: return bool(point["active"]) and not point.has("locked") and not point.has("order")), "All three storm points are immediately attackable in either health phase")
			for step: int in order.size():
				var point: Dictionary = points[int(order[step])]
				var result: Dictionary = fsm.damage_weakpoint(int(point["uid"]), int(point["cast_id"]), 1000.0)
				_check(result["hit"] and result["broke"] and result["interrupted"] == (step == 2) and result["damage"] == point["max_health"] and fsm.snapshot()["weakpoints_remaining"] == 2 - step, "Any requested order breaks exactly one current point and interrupts only after the last")
			var state: Dictionary = fsm.snapshot()
			_check(state["phase"] == "break" and state["break_left"] == 1.5 and state["damage_multiplier"] == 1.35 and state["hold_position"] and not state["release_pending"], "A full interrupt exposes the exact anchored one-and-a-half-second boss-only break contract")
			_check(fsm.telegraph_snapshot().is_empty(), "An interrupted cast clears only its current charge telegraph snapshot")
			var notifications: Array[Dictionary] = fsm.finish_friendly_step()
			_check(_count(notifications, "interrupted") == 1 and _count(notifications, "break_started") == 1 and _count(notifications, "attack") == 0 and fsm.finish_friendly_step().is_empty(), "Break notifications are delivered once without publishing the canceled attack")
			fsm.advance(BossEncounter.BREAK_SECONDS - STEP, BOSS, PLAYER, ratio)
			_check(fsm.snapshot()["phase"] == "break" and fsm.snapshot()["damage_multiplier"] == 1.35, "Break amplification remains active through its penultimate physical tick")
			var ended: Array[Dictionary] = fsm.advance(STEP, BOSS, PLAYER, ratio)
			_check(_count(ended, "break_ended") == 1 and fsm.snapshot()["phase"] == "recovery" and fsm.snapshot()["damage_multiplier"] == 1.0, "The last break tick removes amplification without a floating-point extra frame")
		for attack: String in ["root_corridor", "spirit_chorus"]:
			for order: Array in [[0, 1], [1, 0]]:
				var pair: BossEncounter = _charged(ratio, attack)
				var points: Array[Dictionary] = pair.weakpoints_snapshot()
				_check(points.size() == 2 and points.all(func(point: Dictionary) -> bool: return bool(point["active"]) and not point.has("locked") and not point.has("order")), "Both points of a root or summon charge are attackable immediately in either health phase")
				for step: int in order.size():
					var point: Dictionary = points[int(order[step])]
					var hit: Dictionary = pair.damage_weakpoint(int(point["uid"]), int(point["cast_id"]), 1000.0)
					_check(hit["hit"] and hit["broke"] and hit["interrupted"] == (step == 1) and pair.snapshot()["weakpoints_remaining"] == 1 - step, "Either two-point destruction order interrupts only after the second real break")
				var interrupted: Array[Dictionary] = pair.finish_friendly_step()
				_check(_count(interrupted, "interrupted") == 1 and _count(interrupted, "root_lane") == 0 and _count(interrupted, "summon") == 0 and pair.snapshot()["damage_multiplier"] == 1.35, "An interrupted two-point charge cannot publish roots or summon requests")

func _test_stale_identity_and_overlapping_hits() -> void:
	var fsm: BossEncounter = _charged()
	var points: Array[Dictionary] = fsm.weakpoints_snapshot()
	var first: Dictionary = points[0]
	var second: Dictionary = points[1]
	var before: String = _signature(fsm)
	for request: Dictionary in [{"uid": -1, "cast": first["cast_id"]}, {"uid": first["uid"], "cast": int(first["cast_id"]) + 1}]:
		_check(not fsm.damage_weakpoint(int(request["uid"]), int(request["cast"]), 1000.0)["hit"] and _signature(fsm) == before, "A stale cast or unknown UID cannot redirect damage to a current point")
	var half: float = float(first["max_health"]) * 0.5
	_check(fsm.damage_weakpoint(int(first["uid"]), int(first["cast_id"]), half)["damage"] == half and not fsm.damage_weakpoint(int(first["uid"]), int(first["cast_id"]), half)["interrupted"], "Two overlapping accepted hits clamp to one point's remaining real health")
	_check(not fsm.damage_weakpoint(int(first["uid"]), int(first["cast_id"]), half)["hit"] and fsm.weakpoints_snapshot()[1]["health"] == second["health"] and fsm.snapshot()["weakpoints_remaining"] == 2, "Repeated hits after break cannot spill onto a different living point")
	var published: Array[Dictionary] = _release(fsm)
	var history: String = JSON.stringify(published)
	fsm.advance(BossEncounter.RECOVERY_SECONDS, BOSS, PLAYER, 1.0)
	var current: Dictionary = fsm.weakpoints_snapshot()[0]
	_check(current["uid"] != first["uid"] and current["cast_id"] != first["cast_id"], "Each later cast allocates fresh point and cast identities")
	before = _signature(fsm)
	_check(not fsm.damage_weakpoint(int(first["uid"]), int(current["cast_id"]), 1000.0)["hit"] and not fsm.damage_weakpoint(int(current["uid"]), int(first["cast_id"]), 1000.0)["hit"] and _signature(fsm) == before, "Crossing an old UID with a new cast, or vice versa, cannot hit anything")
	_break_all(fsm)
	var canceled: Array[Dictionary] = fsm.finish_friendly_step()
	_check(_count(canceled, "interrupted") == 1 and JSON.stringify(published) == history and _first(canceled, "interrupted")["cast_id"] == current["cast_id"], "A later interruption targets only its own unpublished cast and never mutates historical attacks")
	var coincident: BossEncounter = _charged(0.49, "forest_storm", BOSS, BOSS)
	points = coincident.weakpoints_snapshot()
	_check(points.all(func(point: Dictionary) -> bool: return (point["position"] as Vector2).is_finite()) and points[0]["position"] != points[1]["position"], "Coincident boss and player positions use a finite deterministic layout without stacking point identities")

func _test_phase_two_latching() -> void:
	var fsm: BossEncounter = _charged()
	var old: Dictionary = fsm.snapshot()
	var old_points: Array[Dictionary] = fsm.weakpoints_snapshot()
	fsm.advance(STEP, BOSS + Vector2(10, 0), PLAYER + Vector2(200, 0), 0.5)
	var crossed: Dictionary = fsm.snapshot()
	_check(crossed["phase2"] and not crossed["cast_phase2"] and crossed["cast_id"] == old["cast_id"] and crossed["attack_id"] == old["attack_id"] and crossed["locked_target"] == old["locked_target"] and fsm.weakpoints_snapshot() == old_points, "Crossing exactly fifty percent never rewrites an already charged cast or its fixed world points")
	var release: Array[Dictionary] = _release(fsm, 0.49)
	_check(_count(release, "attack") == 3 and release.all(func(event: Dictionary) -> bool: return not bool(event["phase2"])), "The old cast finishes its original three-strike pattern after the health transition")
	fsm.advance(BossEncounter.RECOVERY_SECONDS, BOSS, PLAYER, 0.8)
	var next: Dictionary = fsm.snapshot()
	_check(next["phase2"] and next["cast_phase2"] and next["attack_id"] == "root_corridor" and next["safe_channels"].size() == 1, "The next cast upgrades to horizontal single-corridor roots and phase two never heals backward")
	_check(next["charge_total"] == BossEncounter.CHARGE_SECONDS["root_corridor"], "Phase changes alter patterns while preserving the published charge duration")
	_release(fsm, 0.49)
	fsm.advance(BossEncounter.RECOVERY_SECONDS, BOSS, PLAYER, 0.49)
	_check(fsm.snapshot()["attack_id"] == "forest_storm" and fsm.weakpoints_snapshot().all(func(point: Dictionary) -> bool: return bool(point["active"])), "Phase-two storm retains three freely attackable points")
	_check(_count(_release(fsm, 0.49), "attack") == 5, "Phase-two storm releases five spatially different strikes")

func _lane_contains(lane: Dictionary, point: Vector2) -> bool:
	var delta: Vector2 = point - (lane["position"] as Vector2)
	var direction: Vector2 = lane["direction"]
	var along: float = delta.dot(direction)
	return along >= 0.0 and along <= float(lane["length"]) and absf(direction.cross(delta)) <= float(lane["width"]) * 0.5

func _test_patterns_and_safe_channels() -> void:
	for ratio: float in [1.0, 0.49]:
		var roots: BossEncounter = _charged(ratio, "root_corridor")
		var state: Dictionary = roots.snapshot()
		var safe: Array = state["safe_channels"]
		var points: Array[Dictionary] = roots.weakpoints_snapshot()
		_check(points.size() == 2 and points.all(func(point: Dictionary) -> bool: return bool(point["active"])), "Root charges use two simultaneous freely attackable points")
		var events: Array[Dictionary] = _release(roots, ratio)
		_check(_count(events, "root_lane") == (4 if ratio < 0.5 else 3) and safe.size() == (1 if ratio < 0.5 else 2), "Root attacks change their actual lane count and safe channels between health phases")
		for channel: Dictionary in safe:
			var direction: Vector2 = channel["direction"]
			_check(direction == (Vector2.RIGHT if ratio < 0.5 else Vector2.DOWN) and channel["cap"] == "square", "Root channels use the explicit finite rectangle orientation")
			for progress: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				for across: float in [-0.49, 0.0, 0.49]:
					var point: Vector2 = channel["position"] + direction * float(channel["length"]) * progress + direction.orthogonal() * float(channel["width"]) * across
					for event: Dictionary in events:
						if event["type"] == "root_lane":
							_check(not _lane_contains(event, point), "No published damaging lane enters a declared safe channel")
		var summons: BossEncounter = _charged(ratio, "spirit_chorus")
		_check(summons.weakpoints_snapshot().size() == 2, "The summon charge has its own two-point interrupt opportunity")
		var spawn: Dictionary = _first(_release(summons, ratio), "summon")
		_check(spawn["role"] == "boss_ghost" and spawn["count"] == (3 if ratio < 0.5 else 2) and spawn["max_alive"] == (6 if ratio < 0.5 else 4) and spawn["positions"].size() == spawn["count"], "Summon requests publish a bounded count and explicit cross-cast live cap")

func _test_large_steps() -> void:
	var fsm: BossEncounter = ENCOUNTER.new()
	fsm.begin(BOSS, 1.0, BOUNDS)
	var events: Array[Dictionary] = fsm.advance(100.0, BOSS, PLAYER, 1.0)
	_check(events.size() <= BossEncounter.MAX_EVENTS_PER_CALL and _count(events, "telegraph") == 1 and _count(events, "attack") == 0 and fsm.snapshot()["release_pending"] and fsm.snapshot()["cast_id"] == 1, "A large step stops at one fair charge boundary without releasing unseen historical casts")
	_break_all(fsm)
	events = fsm.finish_friendly_step()
	_check(_count(events, "interrupted") == 1 and _count(events, "attack") == 0, "Even an overshot deadline gives the current friendly batch its final interrupt opportunity")
	events = fsm.advance(100.0, BOSS, PLAYER, 1.0)
	_check(_count(events, "break_ended") == 1 and _count(events, "telegraph") == 1 and fsm.snapshot()["cast_id"] == 2 and fsm.snapshot()["release_pending"], "A large break/recovery step advances to at most one new charge")
	events = fsm.finish_friendly_step()
	_check(events.size() <= BossEncounter.MAX_EVENTS_PER_CALL and _count(events, "root_lane") == 3 and fsm.finish_friendly_step().is_empty(), "The large-step release remains bounded and idempotent")
	_check(fsm.advance(STEP, BOSS, PLAYER, 1.0).is_empty() and fsm.snapshot()["cast_id"] == 2, "A release cannot retain a hidden backlog that bursts on the next step")

func _test_purity_and_invalid_input() -> void:
	var first: BossEncounter = _charged()
	var second: BossEncounter = _charged()
	_check(_signature(first) == _signature(second), "Identical value inputs create identical encounter state without random choices")
	var before: String = _signature(first)
	var copy: Dictionary = first.snapshot()
	var points: Array[Dictionary] = first.weakpoints_snapshot()
	copy["weakpoints"][0]["health"] = -10.0
	copy["safe_channels"].clear()
	points[0]["position"] = Vector2.INF
	_check(_signature(first) == before and _signature(first) == _signature(second), "Every public snapshot is detached and cannot mutate current health, positions or later events")
	for delta: float in [0.0, -1.0, INF, NAN]:
		_check(first.advance(delta, BOSS, PLAYER, 1.0).is_empty() and _signature(first) == before, "Invalid time does not tick, transition or publish encounter state")
	for request: Dictionary in [{"boss": Vector2.INF, "player": PLAYER, "ratio": 1.0}, {"boss": BOSS, "player": Vector2.INF, "ratio": 1.0}, {"boss": BOSS, "player": PLAYER, "ratio": NAN}]:
		_check(first.advance(STEP, request["boss"], request["player"], request["ratio"]).is_empty() and _signature(first) == before, "Nonfinite actor inputs cannot alter a live cast")
	var point: Dictionary = first.weakpoints_snapshot()[0]
	for amount: float in [0.0, -1.0, INF, NAN]:
		_check(not first.damage_weakpoint(int(point["uid"]), int(point["cast_id"]), amount)["hit"] and _signature(first) == before, "Invalid damage changes neither point identity nor encounter state")
	_check(_release(first) == _release(second) and _signature(first) == _signature(second), "Independent encounters preserve identical future releases after arbitrary pure queries")
	var roots: BossEncounter = ENCOUNTER.new()
	roots.begin(BOSS, 0.49, BOUNDS)
	var preview_events: Array[Dictionary] = roots.advance(BossEncounter.OPENING_SECONDS, BOSS, PLAYER, 0.49)
	var preview: Dictionary = _first(preview_events, "telegraph")
	var safe_copy: Dictionary = roots.snapshot()
	var geometry_copy: Array[Dictionary] = roots.telegraph_snapshot()
	var retained: String = _signature(roots)
	_check(geometry_copy == preview["geometry"] and geometry_copy.size() == 4, "The charge geometry snapshot matches its frozen telegraph event")
	preview["geometry"][0]["position"] = Vector2.INF
	preview["safe_channels"][0]["width"] = 9999.0
	safe_copy["safe_channels"][0]["position"] = Vector2.INF
	geometry_copy[0]["position"] = Vector2.INF
	geometry_copy[0]["width"] = 9999.0
	_check(_signature(roots) == retained and roots.snapshot()["safe_channels"][0]["width"] == 128.0, "Returned telegraph and nested safe-channel dictionaries cannot mutate live frozen collision geometry")
	var released: Array[Dictionary] = _release(roots, 0.49)
	_check(released.filter(func(event: Dictionary) -> bool: return event["type"] == "root_lane").all(func(event: Dictionary) -> bool: return (event["position"] as Vector2).is_finite() and event["width"] == 112.0), "The real release remains exact and finite after external preview edits")

func _inside(bounds: Rect2, point: Vector2) -> bool:
	return point.is_finite() and point.x >= bounds.position.x and point.x <= bounds.end.x and point.y >= bounds.position.y and point.y <= bounds.end.y

func _relocation_positions(fsm: BossEncounter, offset: Vector2 = Vector2(20, 0)) -> Dictionary:
	var positions: Dictionary = {}
	for point: Dictionary in fsm.weakpoints_snapshot():
		positions[int(point["uid"])] = point["position"] + offset
	return positions

func _test_relocation() -> void:
	for ratio: float in [1.0, 0.49]:
		for attack: String in ["forest_storm", "root_corridor", "spirit_chorus"]:
			var fsm: BossEncounter = _charged(ratio, attack)
			var points: Array[Dictionary] = fsm.weakpoints_snapshot()
			var cast_id: int = int(fsm.snapshot()["cast_id"])
			var first_uid: int = int(points[0]["uid"])
			var second_uid: int = int(points[1]["uid"])
			var positions: Dictionary = _relocation_positions(fsm)
			var before: String = _signature(fsm)
			_check(not fsm.relocate_weakpoints(cast_id + 1, positions) and _signature(fsm) == before, "A stale cast cannot relocate any live point")
			var invalid: Array[Dictionary] = []
			var missing: Dictionary = positions.duplicate(true)
			missing.erase(first_uid)
			invalid.append(missing)
			var unknown: Dictionary = missing.duplicate(true)
			unknown[first_uid + 10000] = points[0]["position"]
			invalid.append(unknown)
			for value: Variant in [Vector2.INF, Vector2(NAN, 0), "invalid", BOUNDS.position + Vector2(12, 12)]:
				var malformed: Dictionary = positions.duplicate(true)
				malformed[first_uid] = value
				invalid.append(malformed)
			var overlapping: Dictionary = positions.duplicate(true)
			overlapping[second_uid] = overlapping[first_uid]
			invalid.append(overlapping)
			var too_close: Dictionary = positions.duplicate(true)
			too_close[second_uid] = too_close[first_uid] + Vector2(29.0, 0)
			invalid.append(too_close)
			for request: Dictionary in invalid:
				_check(not fsm.relocate_weakpoints(cast_id, request) and _signature(fsm) == before, "Incomplete, unknown, nonfinite, out-of-bounds or overlapping relocation is rejected atomically")
			_check(fsm.relocate_weakpoints(cast_id, positions), "Every current point relocates together once after complete validation")
			for point: Dictionary in fsm.weakpoints_snapshot():
				_check(point["position"] == positions[int(point["uid"])] and point["health"] == point["max_health"] and point["active"], "Relocation preserves point identity and health while replacing the actual authoritative coordinate")
			var retained: String = _signature(fsm)
			var accepted_position: Vector2 = positions[first_uid]
			positions[first_uid] = Vector2.INF
			_check(_signature(fsm) == retained and not fsm.relocate_weakpoints(cast_id, _relocation_positions(fsm)) and _signature(fsm) == retained, "Accepted input is detached and a second relocation cannot move the same cast again")
			var hit: Dictionary = fsm.damage_weakpoint(first_uid, cast_id, 1.0)
			_check(hit["hit"] and hit["position"] == accepted_position, "Actual weakpoint damage reports its relocated coordinate")
	var spaced: BossEncounter = _charged(1.0, "root_corridor")
	var edge_positions: Dictionary = _relocation_positions(spaced)
	var edge_points: Array[Dictionary] = spaced.weakpoints_snapshot()
	edge_positions[int(edge_points[0]["uid"])] = BOUNDS.position + Vector2(13, 13)
	edge_positions[int(edge_points[1]["uid"])] = BOUNDS.position + Vector2(43, 13)
	_check(spaced.relocate_weakpoints(int(spaced.snapshot()["cast_id"]), edge_positions), "An entire in-bounds circle and exact thirty-pixel minimum spacing are accepted at the world edge")
	var late: BossEncounter = _charged()
	var original: Dictionary = late.weakpoints_snapshot()[0]
	late.damage_weakpoint(int(original["uid"]), int(original["cast_id"]), 1.0)
	var late_before: String = _signature(late)
	_check(not late.relocate_weakpoints(int(original["cast_id"]), _relocation_positions(late)) and _signature(late) == late_before, "The first accepted weakpoint damage closes relocation for the rest of its cast")
	var released: BossEncounter = _charged()
	var released_id: int = int(released.snapshot()["cast_id"])
	var previous_positions: Dictionary = _relocation_positions(released)
	_release(released)
	_check(not released.relocate_weakpoints(released_id, previous_positions), "Already released points cannot be restored by late relocation")
	released.advance(BossEncounter.RECOVERY_SECONDS, BOSS, PLAYER, 1.0)
	_check(released.relocate_weakpoints(int(released.snapshot()["cast_id"]), _relocation_positions(released)), "A new cast resets its one-time placement allowance")
	released.begin(BOSS, 1.0, BOUNDS)
	released.advance(BossEncounter.OPENING_SECONDS, BOSS, PLAYER, 1.0)
	_check(released.relocate_weakpoints(int(released.snapshot()["cast_id"]), _relocation_positions(released)), "A new encounter resets its placement and damage guards")
	var stopped_id: int = int(released.snapshot()["cast_id"])
	var stopped_positions: Dictionary = _relocation_positions(released)
	released.stop()
	_check(not released.relocate_weakpoints(stopped_id, stopped_positions) and released.weakpoints_snapshot().is_empty(), "Stopped encounters cannot accept relocation or recreate points")
	var broken: BossEncounter = _charged()
	var broken_id: int = int(broken.snapshot()["cast_id"])
	var broken_positions: Dictionary = _relocation_positions(broken)
	_break_all(broken)
	_check(not broken.relocate_weakpoints(broken_id, broken_positions) and broken.snapshot()["phase"] == "break", "An interrupted cast cannot relocate after its last point is broken")

func _test_bounds_and_stop() -> void:
	var positions: Array[Vector2] = [BOSS, BOUNDS.position + Vector2(16, 16), BOUNDS.end - Vector2(16, 16),
		Vector2(BOUNDS.position.x + 16, BOUNDS.end.y - 16), Vector2(BOUNDS.end.x - 16, BOUNDS.position.y + 16)]
	for ratio: float in [1.0, 0.49]:
		for position: Vector2 in positions:
			for attack: String in ["forest_storm", "root_corridor", "spirit_chorus"]:
				var fsm: BossEncounter = _charged(ratio, attack, position, position)
				for point: Dictionary in fsm.weakpoints_snapshot():
					var radius: float = float(point["radius"])
					_check(BOUNDS.encloses(Rect2(point["position"] - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)), "The full weakpoint circle stays reachable inside every corner of the playable world")
				for event: Dictionary in _release(fsm, ratio, position, position):
					match str(event["type"]):
						"attack":
							var radius: float = float(event["radius"])
							_check(BOUNDS.encloses(Rect2(event["position"] - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)), "Complete storm warnings stay inside the playable world")
						"root_lane":
							var direction: Vector2 = event["direction"]
							var normal: Vector2 = direction.orthogonal() * float(event["width"]) * 0.5
							var origin: Vector2 = event["position"]
							for corner: Vector2 in [origin - normal, origin + normal, origin + direction * float(event["length"]) - normal, origin + direction * float(event["length"]) + normal]:
								_check(_inside(BOUNDS, corner), "Every finite root-lane corner matches the fully in-bounds authored rectangle")
						"summon":
							for target: Vector2 in event["positions"]:
								_check(_inside(BOUNDS.grow(-32.0), target), "Each bounded summon request preserves its explicit world inset")
	var stopped: BossEncounter = _charged()
	stopped.advance(float(stopped.snapshot()["charge_left"]), BOSS, PLAYER, 1.0)
	stopped.stop()
	_check(stopped.snapshot()["phase"] == "stopped" and stopped.snapshot()["cast_id"] == 0 and stopped.weakpoints_snapshot().is_empty() and stopped.telegraph_snapshot().is_empty() and stopped.finish_friendly_step().is_empty() and stopped.advance(100.0, BOSS, PLAYER, 1.0).is_empty(), "Stopping clears a deadline-pending cast and every point without a terminal attack")
	var dead: BossEncounter = _charged()
	dead.advance(STEP, BOSS, PLAYER, 0.0)
	_check(dead.snapshot()["phase"] == "stopped" and dead.finish_friendly_step().is_empty(), "An authoritative zero-health step stops the encounter before hostile release")
	for invalid: Dictionary in [{"position": Vector2.INF, "ratio": 1.0, "bounds": BOUNDS}, {"position": BOSS, "ratio": 0.0, "bounds": BOUNDS}, {"position": BOSS, "ratio": NAN, "bounds": BOUNDS}, {"position": BOSS, "ratio": 1.0, "bounds": Rect2(0, 0, 500, 500)}]:
		dead.begin(invalid["position"], invalid["ratio"], invalid["bounds"])
		_check(not dead.snapshot()["running"] and dead.weakpoints_snapshot().is_empty() and dead.finish_friendly_step().is_empty(), "Invalid encounter startup leaves a fully stopped state")
