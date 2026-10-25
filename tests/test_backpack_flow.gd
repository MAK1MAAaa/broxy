extends SceneTree
## The playable Main uses the spatial inventory across shopping, battle and restart.

const MAIN = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var profile_existed: bool = FileAccess.file_exists(GameStore.PATH)
	var original: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if profile_existed else PackedByteArray()
	var app = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args = PackedStringArray(["--autoplay"])
	app._begin_run("bone", 20261024)
	var state: RunState = app.run
	app.world.set_physics_process(false)
	var initial: CombatSim = app.world.sim
	var starter_uid: int = int(app.run.loadout[0]["uid"])
	_check(app.run.backpack_snapshot()["height"] == 4 and app.run.loadout.size() == 1, "A playable new run begins with its one real boxed starter")
	initial.elapsed = initial.duration - STEP * 0.5
	initial._spawn_timer = 1000.0
	initial.step(STEP, Vector2.ZERO)
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.SHOP and not app.world.active, "The ordinary successful-wave signal reaches backpack shopping")
	_check(_grid(app.ui) != null, "The real shop renders the spatial backpack rather than legacy weapon slots")
	app.run.gold = 1000
	state.offers = [{"kind": "weapon", "id": "bone", "price": 19, "sold": false}]
	app.ui.show_shop()
	_check(app.run.buy_offer(0) and app.run.loadout.size() == 2, "A shop purchase enters the real backpack and combat projection")
	var purchased_uid: int = int(app.run.loadout[1]["uid"])
	_check(app.run.merge_items(purchased_uid, starter_uid), "The same two stored weapons can be explicitly merged")
	_check(app.run.loadout.size() == 1 and int(app.run.loadout[0]["rank"]) == 2, "The battlefield projection contains one second-rank weapon")
	_check(app.run.move_item(starter_uid, Vector2i(5, 0), false), "The merged boxed weapon can be manually relocated")
	await _settle()
	var stored: Dictionary = app.run.backpack_item(starter_uid)
	_check(int(stored["x"]) == 5 and int(stored["rank"]) == 2, "The shop refresh preserves placement and rank by UID")
	var next: Button = _button(app.ui, "开始下一波")
	_check(next != null, "The current backpack shop retains a reachable next-wave action")
	if next != null:
		next.pressed.emit()
	app.world.set_physics_process(false)
	var battle: CombatSim = app.world.sim
	_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and battle != initial and app.run.wave == 2, "Starting the wave uses the arranged inventory in a fresh wave simulation")
	_check(app.run.backpack_item(starter_uid) == stored and int(app.run.loadout[0]["uid"]) == starter_uid, "Wave transition preserves the exact item record and its combat identity")
	var enemy: CombatSim.Enemy = battle.spawn_enemy("tank", battle.player_position + Vector2(150, 0))
	enemy.health = 1000.0
	enemy.max_health = enemy.health
	battle._cooldowns.fill(0.0)
	battle.step(STEP, Vector2.ZERO)
	var ranked_shots: int = 0
	for shot: CombatSim.Shot in battle.shots:
		if shot.active and not shot.hostile and shot.source == "bone":
			ranked_shots += 1
			_check(is_equal_approx(shot.damage, GameCatalog.weapon("bone").damage * 2.0 * app.run.stat("damage")), "Automatic combat fires the merged item's actual second-rank damage")
	_check(ranked_shots > 0, "The merged weapon actually fires through the normal dispatcher")
	app._pause()
	var paused_time: float = battle.elapsed
	app.world.set_physics_process(true)
	await _settle()
	_check(paused and app.paused and battle.elapsed == paused_time, "Backpack-based combat still respects the real pause state")
	app._resume()
	await physics_frame
	await physics_frame
	app.world.set_physics_process(false)
	_check(not paused and not app.paused and battle.elapsed > paused_time, "The same arranged loadout resumes without replacing the battle")
	app._title()
	app._begin_run("ember", 20261025)
	app.world.set_physics_process(false)
	_check(app.run.backpack_snapshot()["height"] == 4 and app.run.backpack_snapshot()["items"].size() == 1, "Restart clears all placements, merges and expansions")
	_check(app.run.loadout[0]["id"] == "ember" and int(app.run.loadout[0]["rank"]) == 1, "The new starter is independent of the previous merged weapon")
	app._title()
	_check(FileAccess.file_exists(GameStore.PATH) == profile_existed and (not profile_existed or FileAccess.get_file_as_bytes(GameStore.PATH) == original), "Backpack integration fixtures never change the player's profile")
	print("BackpackFlow: %d assertions, %d failures" % [_checks, _failures])
	app._quit_game(0 if _failures == 0 else 1)

func _grid(node: Node) -> Node:
	if node is BackpackGrid:
		return node
	for child: Node in node.get_children():
		var found: Node = _grid(child)
		if found != null:
			return found
	return null

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child: Node in node.get_children():
		var found: Button = _button(child, text)
		if found != null:
			return found
	return null
