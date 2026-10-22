extends SceneTree
## Main-scene transitions, using production simulation and signals.
## Boss fixtures accelerate terminal conditions; they do not establish balance.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0
var _profile_existed: bool = false
var _profile_before: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	root.size = Vector2i(1280, 720)
	_profile_existed = FileAccess.file_exists(GameStore.PATH)
	if _profile_existed:
		_profile_before = FileAccess.get_file_as_bytes(GameStore.PATH)
	var app = MAIN.instantiate()
	# Set this before _ready: neither profile loading nor results may touch user data.
	app.store.persistent = false
	root.add_child(app)
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.TITLE, "Main scene starts on the title")
	_check(not app.store.persistent, "Integration fixtures never persist profile changes")

	app._start_run("bone")
	var state: RunState = app.run
	var world: CombatWorld = app.world
	state.begin(2026, "bone")
	world.begin(state)
	world.set_physics_process(false)
	var first: CombatSim = world.sim
	_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and world.active, "Starting from the title enters active combat")
	_check(is_equal_approx(first.duration, 45.0) and not first.sandbox and not world.stress_mode, "Normal combat uses the 45-second wave rather than the benchmark sandbox")
	var steps: int = 0
	# One extra tick accommodates floating-point accumulation at the boundary.
	while not first.complete and steps < 2701:
		first.step(STEP, BotPolicy.movement(first))
		steps += 1
	_check(first.complete and first.victory, "The fixed-seed first wave ends successfully after normal simulation")
	_check(first.elapsed >= 45.0 and first.elapsed <= 45.0 + STEP + 0.001, "Ordinary wave completion happens at the 45-second boundary")
	_check(not world.active, "The ended signal stops the combat world immediately")
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.UPGRADE or app.screen == MAIN_SCRIPT.Screen.SHOP, "Wave completion reaches an upgrade or shop screen after deferred transition")
	_check(is_equal_approx(state.health, state.stat("max_health")), "The wave-end altar restores full health before shopping")
	var choices: int = 0
	while app.screen == MAIN_SCRIPT.Screen.UPGRADE and choices < 20:
		var choice: Button = _find_button(app.ui, "选择强化")
		_check(choice != null, "Pending upgrades expose a selectable UI choice")
		if choice == null:
			break
		choice.pressed.emit()
		choices += 1
		await _settle()
	_check(state.pending_upgrades == 0 and app.screen == MAIN_SCRIPT.Screen.SHOP, "Finishing pending upgrades opens the shop through the real UI signal")
	_check(state.offers.size() == 4 and not world.active, "The shop has four offers while combat remains stopped")
	_check(not state.damage_dealt_by_weapon.is_empty() and state.damage_dealt_by_weapon == first.damage_by_weapon, "The first wave contributes real health loss to the run's weapon report")
	var damage_before_next: Dictionary = state.damage_dealt_by_weapon.duplicate()
	var next: Button = _find_button(app.ui, "开始下一波")
	_check(next != null, "The shop provides a next-wave entry")
	if next != null:
		next.pressed.emit()
	_check(state.wave == 2 and app.screen == MAIN_SCRIPT.Screen.COMBAT and world.active, "The next-wave entry starts wave two")
	_check(is_zero_approx(world.sim.elapsed) and not world.sim.complete and not world.sim.sandbox, "The next wave gets a fresh normal simulation and reset timer")
	_check(state.damage_dealt_by_weapon == damage_before_next, "Starting another wave preserves accumulated weapon contributions")
	_check(world._numbers.is_empty(), "A new wave clears the previous wave's transient combat numbers")

	# Let the actual physics loop run briefly to verify pause/resume, not wall-clock duration.
	world.set_physics_process(true)
	app._pause()
	var paused_elapsed: float = world.sim.elapsed
	await _settle()
	_check(paused and app.paused and is_equal_approx(world.sim.elapsed, paused_elapsed), "Pausing stops the production wave timer")
	_check(_find_button(app.ui, "继续试炼") != null and app.ui.can_process(), "Pause UI remains actionable while combat is paused")
	app._resume()
	await physics_frame
	await physics_frame
	await physics_frame
	_check(not paused and not app.paused and world.sim.elapsed > paused_elapsed, "Resuming allows the production wave timer to advance")
	world.set_physics_process(false)

	# Exercise timeout through CombatSim.ended -> CombatWorld -> deferred main transition.
	app._start_run("bone")
	_check(state.damage_dealt_by_weapon.is_empty() and is_zero_approx(state.damage_taken) and state.hits_taken == 0 and state.last_hit.is_empty(), "A new run resets all combat-report fields before another encounter")
	state.wave = 8
	world.begin(state)
	world.set_physics_process(false)
	app.screen = MAIN_SCRIPT.Screen.COMBAT
	var timeout: CombatSim = world.sim
	_check(timeout.boss != null and is_equal_approx(timeout.duration, 90.0), "Final-wave fixture uses the real boss and 90-second deadline")
	timeout.elapsed = timeout.duration - 0.01
	timeout.step(0.02, Vector2.ZERO)
	await _settle()
	_check(timeout.complete and not timeout.victory and not world.active, "A living boss at the deadline ends combat as a defeat")
	_check(app.screen == MAIN_SCRIPT.Screen.RESULT and _has_label(app.ui, "试炼终止"), "Boss timeout reaches the defeat result screen")
	_check(int(app.store.best["runs"]) == 1 and int(app.store.best["wins"]) == 0, "Timeout records one in-memory loss")
	var restart: Button = _find_button(app.ui, "再次试炼")
	_check(restart != null, "Defeat offers a restart")
	if restart != null:
		restart.pressed.emit()
	_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and state.wave == 1 and world.active and is_zero_approx(world.sim.elapsed), "Restart returns to fresh first-wave combat")

	state.wave = 8
	world.begin(state)
	world.set_physics_process(false)
	app.screen = MAIN_SCRIPT.Screen.COMBAT
	var victory: CombatSim = world.sim
	_check(victory.boss != null and victory.boss.active, "Boss-kill fixture begins with a live boss")
	if victory.boss != null:
		victory.apply_damage(victory.boss, victory.boss.health + 1.0, "bone")
	await _settle()
	_check(victory.complete and victory.victory and not world.active, "Applying lethal damage to the boss ends the final wave")
	_check(is_equal_approx(float(state.damage_dealt_by_weapon.get("bone", 0.0)), victory.boss.max_health), "Victory reports actual boss health removed rather than attempted overkill damage")
	_check(app.screen == MAIN_SCRIPT.Screen.RESULT and _has_label(app.ui, "余烬未灭"), "Boss defeat reaches the victory result screen")
	_check(int(app.store.best["runs"]) == 2 and int(app.store.best["wins"]) == 1, "Victory records one in-memory win without writing a profile")
	var menu: Button = _find_button(app.ui, "返回主菜单")
	_check(menu != null, "Results expose a return-to-title action")
	if menu != null:
		menu.pressed.emit()
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.TITLE and not world.active and not paused, "Returning to title leaves combat stopped and the tree unpaused")
	_check(app.store.save_profile() == OK, "Nonpersistent store safely accepts save requests from close/settings paths")
	_check(_profile_unchanged(), "Starting, results, title and save requests leave the personal profile byte-for-byte unchanged")

	# Follow a real lethal damage event through provenance, feedback and the result UI.
	app._start_run("bone")
	world.set_physics_process(false)
	state.health = 8.0
	world.sim._hurt_player(20.0, "caster", "projectile", Vector2(820, 300))
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.RESULT and _has_text(app.ui, "盲眼祭司"), "Lethal projectile provenance reaches the visible result instead of a generic death message")
	_check(state.last_hit.get("source_id", "") == "caster" and state.last_hit.get("kind", "") == "projectile", "The run retains the real attacker and attack type at the terminal event")
	_check(is_equal_approx(state.damage_taken, 8.0) and is_equal_approx(float(state.last_hit.get("amount", 0.0)), 8.0), "The report records only the player's remaining health rather than lethal overkill")
	_check(state.hits_taken == 1 and not world._numbers.is_empty(), "One accepted lethal hit produces one report entry and visible world feedback")
	var report_before: Dictionary = state.summary()
	world.sim._hurt_player(50.0, "rusher", "contact", Vector2(600, 300))
	_check(state.summary() == report_before, "Events after terminal defeat cannot overwrite the final report")
	app._start_run("bone")
	world.set_physics_process(false)
	_check(state.damage_dealt_by_weapon.is_empty() and state.last_hit.is_empty() and is_zero_approx(state.damage_taken) and state.hits_taken == 0, "Restarting after a sourced death clears every previous combat statistic")
	_check(world._numbers.is_empty(), "Restarting after defeat removes the previous incoming-damage number")
	app._title()
	_check(_profile_unchanged(), "Damage reports and repeated restarts remain in-run and never overwrite personal settings or best scores")
	await _test_terminal_pause_boundary(app)
	print("Flow: %d assertions, %d failures; first wave %d fixed ticks; boss terminal conditions are fixtures, not balance tests" % [_checks, _failures, steps])
	# Use the production quit path, including sound shutdown, after all checks.
	app._quit_game(0 if _failures == 0 else 1)


func _test_terminal_pause_boundary(app: Node) -> void:
	for scenario: String in ["shop_escape", "upgrade_focus", "boss_escape", "timeout_focus"]:
		app._start_run("bone")
		var state: RunState = app.run
		var world: CombatWorld = app.world
		state.begin(2027, "bone")
		if scenario.begins_with("boss") or scenario.begins_with("timeout"):
			state.wave = 8
		elif scenario.begins_with("upgrade"):
			state.collect_souls(state.xp_to_next_level())
		world.begin(state)
		world.set_physics_process(false)
		var simulation: CombatSim = world.sim
		# An actual input/focus event arrives after ended but before deferred settlement.
		simulation.ended.connect(func(_won: bool, _reason: String) -> void:
			if scenario.ends_with("escape"):
				var escape := InputEventKey.new()
				escape.keycode = KEY_ESCAPE
				escape.pressed = true
				root.push_input(escape, false)
			else:
				app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		)
		if scenario.begins_with("boss"):
			simulation.apply_damage(simulation.boss, simulation.boss.health + 1.0, "bone")
		else:
			simulation.elapsed = simulation.duration - 0.001
			simulation.step(0.01, Vector2.ZERO)
		_check(simulation.complete and paused and app.paused, "The terminal-frame fixture actually pauses before deferred settlement: " + scenario)
		await _settle()
		_check(not paused and not app.paused and app.ui._overlay.get_child_count() == 0, "Settlement clears both pause states and the overlay: " + scenario)
		if state.wave == 8:
			_check(app.screen == MAIN_SCRIPT.Screen.RESULT, "Boss victory and timeout remain actionable results after terminal-frame pause: " + scenario)
		else:
			var expected: int = MAIN_SCRIPT.Screen.UPGRADE if scenario.begins_with("upgrade") else MAIN_SCRIPT.Screen.SHOP
			_check(app.screen == expected, "Terminal-frame pause preserves the intended settlement route: " + scenario)
			while app.screen == MAIN_SCRIPT.Screen.UPGRADE:
				var choice: Button = _find_button(app.ui, "选择强化")
				if choice == null:
					_check(false, "Upgrade remains usable after a terminal-frame focus event")
					break
				choice.pressed.emit()
				await _settle()
			var next: Button = _find_button(app.ui, "开始下一波")
			_check(next != null, "The completed route exposes the next-wave control: " + scenario)
			if next != null:
				next.pressed.emit()
			world.set_physics_process(true)
			await physics_frame
			await physics_frame
			await physics_frame
			_check(world.can_process() and world.sim.elapsed > 0.0 and not paused and not app.paused, "Next-wave physics advances without a hidden pause: " + scenario)
			world.set_physics_process(false)
		app._title()
	_check(_profile_unchanged(), "Terminal-frame pause regressions do not write personal progression")


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null


func _has_label(node: Node, text: String) -> bool:
	if node is Label and node.text == text and node.is_visible_in_tree():
		return true
	for child: Node in node.get_children():
		if _has_label(child, text):
			return true
	return false


func _has_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in node.text and node.is_visible_in_tree():
		return true
	for child: Node in node.get_children():
		if _has_text(child, fragment):
			return true
	return false


func _profile_unchanged() -> bool:
	if FileAccess.file_exists(GameStore.PATH) != _profile_existed:
		return false
	return not _profile_existed or FileAccess.get_file_as_bytes(GameStore.PATH) == _profile_before
