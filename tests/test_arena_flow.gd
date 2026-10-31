extends SceneTree
## Map choice enters the shipped Main and survives its real intermission lifecycle.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
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
	for frame: int in 5:
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	_check(MAIN_SCRIPT._arena_from_args(PackedStringArray()) == "reliquary", "Ordinary startup retains the original arena")
	for id: String in ArenaCatalog.IDS:
		_check(MAIN_SCRIPT._arena_from_args(PackedStringArray(["--arena=" + id])) == id, "Explicit diagnostic arena is parsed: " + id)
	for value: String in ["", "unknown", "mire ", "MIRE"]:
		_check(MAIN_SCRIPT._arena_from_args(PackedStringArray(["--arena=" + value])).is_empty(), "Malformed CLI choice is rejected instead of testing a different map")
	_check(MAIN_SCRIPT._arena_from_args(PackedStringArray(["--arena"])).is_empty(), "CLI arena flag needs an explicit value")
	var detached_state := RunState.new()
	detached_state.begin(20261026, "bone", "glacier")
	var detached_world := CombatWorld.new()
	detached_world.set_physics_process(false)
	detached_world.begin(detached_state)
	_check(detached_world.arena_texture == null and detached_world._arena_id == "glacier", "A world begun off-tree keeps render resource initialization in its ready lifecycle")
	root.add_child(detached_world)
	_check(detached_world.arena_texture != null and detached_world.arena_texture.resource_path == ArenaCatalog.texture_path("glacier"), "Attaching an already begun world loads its selected expanded map")
	detached_world.queue_free()
	await _settle()
	var app = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	await _settle()
	for id: String in ArenaCatalog.IDS:
		var choice: Button = app.ui.find_child("Arena_" + id, true, false) as Button
		_check(choice != null, "The real title exposes a map choice: " + id)
		if choice == null:
			continue
		choice.pressed.emit()
		_check(app.ui.selected_arena() == id, "The title callback selects the actual requested arena")
		app._start_run("bone")
		app.world.set_physics_process(false)
		_check(app.run.arena_id == id and app.world._arena_id == id, "Main transfers selection to RunState and CombatWorld")
		var definition: Dictionary = ArenaCatalog.definition(id)
		_check(app.world.arena_texture != null and app.world.arena_texture.resource_path == ArenaCatalog.texture_path(id), "Rendering loads this arena's own expanded texture")
		_check(app.world.arena_texture.get_size() == ArenaCatalog.art_rect().size, "The expanded texture matches world geometry without scaling")
		var before_rng: int = app.world.sim.rng.state
		var hud: Dictionary = app.world.hud_snapshot()
		_check(hud["arena_id"] == id and hud["arena_name"] == definition["name"], "HUD identifies the same map as the simulation")
		_check(hud["terrain_name"] == "" and is_equal_approx(hud["terrain_multiplier"], 1.0), "Every map starts on safe ground")
		if not (definition["zones"] as Array).is_empty():
			var center: Array = definition["zones"][0]["center"]
			app.world.sim.player_position = Vector2(float(center[0]), float(center[1]))
			hud = app.world.hud_snapshot()
			_check(hud["terrain_name"] == definition["terrain_name"] and is_equal_approx(hud["terrain_multiplier"], definition["move_multiplier"]), "HUD uses real terrain occupancy and exact movement value")
		_check(app.world.sim.rng.state == before_rng, "Reading terrain presentation never consumes combat RNG")
		app._pause()
		var elapsed: float = app.world.sim.elapsed
		await _settle()
		_check(paused and app.run.arena_id == id and is_equal_approx(app.world.sim.elapsed, elapsed), "Pause preserves map and wave clock")
		app._resume()
		app.world.sim.sandbox = false
		app.world.sim._spawn_timer = 9999.0
		app.world.sim._cooldowns.fill(9999.0)
		app.world.sim.elapsed = app.world.sim.duration - 0.01
		app.world.sim.step(0.02, Vector2.ZERO)
		await _settle()
		_check(app.screen == MAIN_SCRIPT.Screen.SHOP and not app.world.active, "The normal timer ends the selected map and opens its shop")
		app._next_wave()
		app.world.set_physics_process(false)
		_check(app.run.wave == 2 and app.run.arena_id == id and app.world._arena_id == id, "The next wave retains terrain and selected texture")
		app.run.health = 0.0
		app.world.sim.step(1.0 / 60.0, Vector2.ZERO)
		await _settle()
		_check(app.screen == MAIN_SCRIPT.Screen.RESULT, "Defeat still settles to the result screen on this map")
		app._title()
		await _settle()
		_check(app.ui.selected_arena() == id, "Returning to title preserves the player's selection within this session")
	app.ui.set_selected_arena("mire")
	app.args = PackedStringArray(["--benchmark", "--benchmark-seed=20261026", "--seconds=5"])
	app._start_benchmark()
	app.set_process(false)
	app.world.set_physics_process(false)
	_check(app.run.arena_id == "mire" and app._benchmark_report_path == "res://reports/performance-arena-mire.json", "Terrain benchmarks have their own report path and do not overwrite historic samples")
	app.sound.shutdown()
	app.queue_free()
	await _settle()
	_check(FileAccess.file_exists(GameStore.PATH) == existed, "Map integration does not create a personal profile")
	if existed:
		_check(FileAccess.get_file_as_bytes(GameStore.PATH) == profile, "Map integration preserves personal profile bytes")
	print("ArenaFlow: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
