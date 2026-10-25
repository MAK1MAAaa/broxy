extends SceneTree
## Production Main, real pickups and choices; accelerated terminal fixtures are not balance tests.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")
const STEP: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0
var _profile_existed: bool = false
var _profile_before: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.size = Vector2i(1280, 720)
	_profile_existed = FileAccess.file_exists(GameStore.PATH)
	if _profile_existed:
		_profile_before = FileAccess.get_file_as_bytes(GameStore.PATH)
	var app: Node = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	app.set_process(false)
	app.args = PackedStringArray()
	await _settle()
	await _test_pickup_timing(app)
	await _test_frozen_world(app)
	await _test_live_vitality(app)
	await _test_multiple_and_coalescing(app)
	await _test_manual_pause_and_settings(app)
	await _test_last_choice_pause(app)
	await _test_terminal_priority(app)
	await _test_stale_callbacks(app)
	await _test_benchmark_and_preview(app)
	app._title()
	_check(FileAccess.file_exists(GameStore.PATH) == _profile_existed and (not _profile_existed or FileAccess.get_file_as_bytes(GameStore.PATH) == _profile_before), "Live upgrades, settings and terminal fixtures never change the personal profile")
	print("CombatUpgrades: %d assertions, %d failures; deterministic pickups and accelerated boundaries, not a balance test" % [_checks, _failures])
	app._quit_game(0 if _failures == 0 else 1)


func _start(app: Node, seed_value: int = 20261028) -> CombatSim:
	app._benchmark = false
	app._begin_run("bone", seed_value)
	app.world.set_physics_process(false)
	var simulation: CombatSim = app.world.sim
	simulation.sandbox = true
	simulation._cooldowns.fill(1000.0)
	return simulation


func _only_choice(state: RunState, id: String) -> void:
	state._upgrade_options.clear()
	for option: Dictionary in RunState.UPGRADE_POOL:
		if str(option["id"]) == id:
			state._upgrade_options.append(option.duplicate(true))
			return


func _choose(app: Node, id: String = "") -> bool:
	var scope: Node = app.ui if id.is_empty() else app.ui.find_child("Upgrade_" + id, true, false)
	if scope == null:
		_check(false, "The requested production upgrade card exists: " + id)
		return false
	var button: Button = _button(scope, "选择强化")
	_check(button != null, "The production upgrade exposes a real choice button")
	if button == null:
		return false
	button.pressed.emit()
	return true


func _test_pickup_timing(app: Node) -> void:
	var ordinary_elapsed: float = 0.0
	for expanded: bool in [false, true]:
		var simulation: CombatSim = _start(app)
		var state: RunState = app.run
		if expanded:
			state.relic_counts["grave_candle"] = 1
		state.xp = state.xp_to_next_level() - 1
		_only_choice(state, "damage")
		simulation._drop_soul(simulation.player_position + Vector2(100, 0), 1)
		for frame: int in 30:
			simulation.step(STEP, Vector2.ZERO)
			if state.pending_upgrades > 0:
				break
		await _settle()
		if not expanded:
			ordinary_elapsed = simulation.elapsed
			_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and state.pending_upgrades == 0 and simulation.soul_count == 1, "At base radius 76, a soul 100 pixels away does not produce a live upgrade")
			continue
		_check(is_equal_approx(state.stat("pickup_radius"), 114.0) and is_equal_approx(state.stat("move_speed"), 212.0), "The real grave candle retains both its pickup benefit and movement cost")
		_check(simulation.elapsed < ordinary_elapsed and simulation.soul_count == 0 and state.pending_upgrades == 1, "The expanded radius collects the same real soul and reaches the same XP threshold earlier")
		_check(app.screen == MAIN_SCRIPT.Screen.UPGRADE and paused and not app.paused and app.world.active, "A collected soul opens an upgrade pause without treating it as manual pause or ending the wave")
		_check(app.run.offers.is_empty() and app.world.sim == simulation, "Live progression has not generated a shop or replaced combat")
		var before: float = state.stat("damage")
		_choose(app, "damage")
		await _settle()
		_check(is_equal_approx(state.stat("damage"), before + 0.12), "Choosing the actual damage card applies its existing bonus during this wave")
		_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and not paused and app.world.sim == simulation and not simulation.complete, "The live damage upgrade returns to the same unfinished wave")
		var shot: CombatSim.Shot = simulation.fire_weapon("bone", "", simulation.player_position, Vector2.RIGHT)
		_check(is_equal_approx(shot.damage, GameCatalog.weapon("bone").damage * state.stat("damage")), "The next real projectile uses the newly chosen damage immediately")
	app._title()


func _test_frozen_world(app: Node) -> void:
	var simulation: CombatSim = _start(app)
	var world: CombatWorld = app.world
	var enemy: CombatSim.Enemy = simulation.spawn_enemy("tank", Vector2(1000, 300))
	enemy.action_timer = 0.7
	enemy.slow_timer = 0.8
	enemy.slow_factor = 0.7
	var ring: CombatSim.Shot = simulation.fire_weapon("return_ring", "pierce", simulation.player_position + Vector2(80, 0), Vector2.RIGHT)
	ring.return_after = STEP
	simulation._update_shots(STEP)
	simulation._drop_soul(Vector2(1000, 600), 1)
	simulation.add_effect(Vector2(850, 500), Color.WHITE, 20.0, 1.0)
	var zone := CombatSim.WarningZone.new()
	zone.position = Vector2(900, 400)
	zone.age = 0.2
	zone.delay = 1.2
	simulation.zones.append(zone)
	simulation.apply_damage(enemy, 1.0, "bone")
	simulation._hurt_player(1.0, "caster", "projectile", Vector2(300, 200))
	simulation.rune_activated.emit("bounce", Vector2(900, 300), Vector2.RIGHT, Vector2.DOWN)
	_only_choice(app.run, "damage")
	app.run.collect_souls(app.run.xp_to_next_level())
	await _settle()
	world.set_physics_process(true)
	_check(paused and world.is_physics_processing() and not world.can_process() and app.ui.can_process(), "Tree pause freezes real physics while the existing upgrade UI can process input")
	_check(ring.active and ring.returning and simulation.soul_count > 0 and not world._numbers.is_empty() and not world._rune_flashes.is_empty() and world._impact_painter.active_count() > 0, "The freeze fixture contains live return flight, a soul, numbers, rune feedback and an impact")
	var before: String = _world_signature(app)
	for frame: int in 4:
		await physics_frame
		await process_frame
	_check(_world_signature(app) == before, "All simulation timers, pooled objects, cooldowns, RNG and world feedback remain frozen during live upgrade")
	_choose(app, "damage")
	# Stop automatic stepping before the final deferred UI signal restores combat.
	world.set_physics_process(false)
	await _settle()
	_check(app.world.sim == simulation and app.world.active and not paused and app.screen == MAIN_SCRIPT.Screen.COMBAT, "Finishing the upgrade preserves the same world and simulation")
	_check(simulation.shot_count > 0 and not world._numbers.is_empty() and not world._rune_flashes.is_empty(), "Restoring HUD does not clear live projectiles or combat feedback")
	var elapsed_before: float = simulation.elapsed
	var shot_before: Vector2 = simulation.shots[0].position
	world.set_physics_process(true)
	for frame: int in 3:
		await physics_frame
	world.set_physics_process(false)
	_check(simulation.elapsed > elapsed_before and simulation.shots[0].position != shot_before, "The resumed production physics advances the original timer and return projectile")
	_check(_world_signature(app) != before, "World feedback and simulation resume advancing after the upgrade")
	app._title()


func _test_live_vitality(app: Node) -> void:
	var simulation: CombatSim = _start(app)
	app.run.health = 25.0
	_only_choice(app.run, "vitality")
	app.run.collect_souls(app.run.xp_to_next_level())
	await _settle()
	_check(is_equal_approx(app.run.health, 25.0), "Opening live upgrades does not run the altar's full-heal settlement")
	_choose(app, "vitality")
	_check(is_equal_approx(app.run.health, 37.0) and is_equal_approx(app.run.stat("max_health"), 112.0), "The existing vitality choice immediately adds 12 maximum and current health in combat")
	await _settle()
	_check(app.world.sim == simulation and app.run.wave == 1 and app.run.offers.is_empty() and is_equal_approx(app.run.health, 37.0), "Live vitality cannot settle income, restore full health or create the next wave")
	_check("37" in str(app.ui._hud["health"].text), "Restoring the HUD immediately displays the upgraded current health")
	app._title()


func _test_multiple_and_coalescing(app: Node) -> void:
	var simulation: CombatSim = _start(app)
	var epoch_before: int = app.ui._upgrade_epoch
	app.run.collect_souls(200)
	var pending: int = app.run.pending_upgrades
	for emission: int in 8:
		app.run.changed.emit()
	await _settle()
	_check(pending > 1 and app.screen == MAIN_SCRIPT.Screen.UPGRADE and paused, "One pickup batch can queue several live upgrades")
	_check(app.ui._upgrade_epoch == epoch_before + 1, "Repeated live state changes coalesce into one deferred upgrade entry")
	var epoch: int = app.ui._upgrade_epoch
	var rng_state: int = app.run.rng.state
	for emission: int in 8:
		app.run.changed.emit()
	# UI state refresh may redraw a card set, but must preserve its cached random choices.
	await _settle()
	_check(app.run.rng.state == rng_state and app.world.sim == simulation and app.ui._upgrade_epoch > epoch, "Repeated state events do not reroll cached choices or replace the simulation")
	var chosen: int = 0
	while app.screen == MAIN_SCRIPT.Screen.UPGRADE and chosen < pending + 1:
		var expected_pending: int = app.run.pending_upgrades - 1
		var button: Button = _button(app.ui, "选择强化")
		if button == null:
			_check(false, "Every queued live upgrade remains actionable")
			break
		button.pressed.emit()
		button.pressed.emit()
		_check(app.run.pending_upgrades == expected_pending, "A repeated old button cannot consume two pending upgrades")
		chosen += 1
		await _settle()
		if app.run.pending_upgrades > 0:
			_check(paused and not app.paused and app.screen == MAIN_SCRIPT.Screen.UPGRADE, "Multiple choices keep combat frozen until the last upgrade is resolved")
	_check(chosen == pending and app.run.pending_upgrades == 0 and app.screen == MAIN_SCRIPT.Screen.COMBAT and not paused, "All queued upgrades finish exactly once and return directly to combat")
	_check(app.run.offers.is_empty() and app.world.sim == simulation, "Resolving several upgrades never runs the shop or restarts the wave")
	var untouched: String = _world_signature(app)
	app.ui.upgrades_finished.emit()
	_check(_world_signature(app) == untouched and app.screen == MAIN_SCRIPT.Screen.COMBAT, "A duplicate completion signal after returning to combat has no effect")
	app._title()


func _test_manual_pause_and_settings(app: Node) -> void:
	var simulation: CombatSim = _start(app)
	_only_choice(app.run, "damage")
	app.run.collect_souls(app.run.xp_to_next_level())
	app._pause()
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and app.paused and paused and app.ui._overlay_mode == "pause", "A manual pause before deferred upgrade entry keeps the manual overlay and defers the choice")
	app._resume()
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.UPGRADE and not app.paused and paused and app.world.sim == simulation, "Resuming manual pause picks up the pending live upgrade without resuming simulation underneath it")
	_escape()
	_check(app.paused and paused and app.ui._overlay_mode == "pause", "Esc over a live upgrade creates a separate manual pause")
	var settings: Button = _button(app.ui, "设置")
	_check(settings != null, "The live-upgrade pause exposes the existing settings route")
	if settings != null:
		settings.pressed.emit()
	await _settle()
	_check(app.ui._overlay_mode == "settings_pause" and paused, "Settings opened over live upgrades keep the world paused")
	app.ui.setting_changed.emit("volume", 0.0)
	_escape()
	_check(app.ui._overlay_mode == "pause" and app.paused and paused, "The first Esc returns from settings to manual pause")
	_escape()
	_check(app.screen == MAIN_SCRIPT.Screen.UPGRADE and not app.paused and paused and app.ui._overlay_mode.is_empty(), "The second Esc closes only manual pause and leaves the upgrade freeze intact")
	app._resume()
	_check(paused and not app.paused, "An extra resume request cannot unfreeze an unresolved live upgrade")
	_choose(app, "damage")
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and not paused, "The actual final choice releases the upgrade freeze")
	app._title()


func _test_last_choice_pause(app: Node) -> void:
	for focus_out: bool in [false, true]:
		var simulation: CombatSim = _start(app)
		_only_choice(app.run, "damage")
		app.run.collect_souls(app.run.xp_to_next_level())
		await _settle()
		_choose(app, "damage")
		if focus_out:
			app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		else:
			_escape()
		_check(app.paused and paused, "The last-choice boundary accepts manual pause or focus loss before deferred completion")
		await _settle()
		_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and app.world.sim == simulation and app.paused and paused and app.ui._overlay_mode == "pause", "Completion restores the real HUD and preserves the boundary's manual pause")
		_check(app.ui._hud.has("health") and _button(app.ui, "继续试炼") != null and app.run.offers.is_empty(), "The preserved pause has actionable controls over HUD, without an accidental shop")
		app._resume()
		_check(not paused and not app.paused and app.screen == MAIN_SCRIPT.Screen.COMBAT, "Explicit resume releases the preserved manual pause after the final choice")
	app._title()


func _test_terminal_priority(app: Node) -> void:
	for scenario: String in ["wave", "death", "boss"]:
		var simulation: CombatSim = _start(app)
		if scenario == "boss":
			app.run.wave = 8
			app.world.begin(app.run)
			simulation = app.world.sim
			app.world.set_physics_process(false)
			simulation._cooldowns.fill(1000.0)
		_only_choice(app.run, "damage")
		app.run.collect_souls(app.run.xp_to_next_level())
		if scenario == "wave":
			simulation.sandbox = false
			simulation.elapsed = simulation.duration - 0.001
			simulation.step(0.01, Vector2.ZERO)
		elif scenario == "death":
			simulation._hurt_player(10000.0, "caster", "projectile", Vector2.ZERO)
		else:
			simulation.apply_damage(simulation.boss, simulation.boss.health + 1.0, "bone")
		_check(simulation.complete and not app.world.active, "The terminal-priority fixture ends the actual simulation before queued upgrade entry: " + scenario)
		await _settle()
		_check(not paused and not app.paused and app._combat_upgrade_sim == null, "A same-frame terminal event wins over live upgrade pause: " + scenario)
		if scenario == "wave":
			_check(app.screen == MAIN_SCRIPT.Screen.UPGRADE and is_equal_approx(app.run.health, app.run.stat("max_health")), "Ordinary wave completion keeps the original altar-upgrade fallback")
			_choose(app, "damage")
			await _settle()
			_check(app.screen == MAIN_SCRIPT.Screen.SHOP and app.run.offers.size() == 4, "A wave-end upgrade still finishes by opening the actual shop")
		else:
			_check(app.screen == MAIN_SCRIPT.Screen.RESULT and app.run.offers.is_empty(), "Death or final victory opens a result instead of a live upgrade or shop: " + scenario)
		app._title()


func _test_stale_callbacks(app: Node) -> void:
	for destination: String in ["restart", "title", "preview", "replacement"]:
		var old: CombatSim = _start(app)
		app.run.collect_souls(app.run.xp_to_next_level())
		if destination == "restart":
			_start(app, 20261029)
		elif destination == "title":
			app._title()
		elif destination == "preview":
			app.world.stop()
			app.run.finish_wave()
			app.run.generate_shop()
			app.screen = MAIN_SCRIPT.Screen.SHOP
			app.ui.show_shop()
		else:
			app.world.begin(app.run)
			app.world.set_physics_process(false)
			app.world.sim.sandbox = true
			app.run.changed.emit()
		var expected: CombatSim = app.world.sim
		await _settle()
		if destination == "replacement":
			_check(app.screen == MAIN_SCRIPT.Screen.UPGRADE and app._combat_upgrade_sim == expected and expected != old and paused, "An old Sim request cannot clear the replacement Sim's own queued upgrade")
		else:
			var expected_screen: int = MAIN_SCRIPT.Screen.COMBAT if destination == "restart" else MAIN_SCRIPT.Screen.TITLE if destination == "title" else MAIN_SCRIPT.Screen.SHOP
			_check(app.screen == expected_screen and app._combat_upgrade_sim == null and not paused, "Stale live-upgrade entry cannot reopen an abandoned screen: " + destination)
		app._title()
	# Ended is deferred independently: a completed old wave must not settle a fresh run.
	var terminal: CombatSim = _start(app)
	terminal.sandbox = false
	terminal.elapsed = terminal.duration - 0.001
	terminal.step(0.01, Vector2.ZERO)
	var fresh: CombatSim = _start(app, 20261030)
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and app.world.sim == fresh and app.run.offers.is_empty() and app.run.wave == 1, "An old deferred ended callback cannot settle or replace a restarted run")
	# The last card schedules its completion after an additional UI refresh.
	_only_choice(app.run, "damage")
	app.run.collect_souls(app.run.xp_to_next_level())
	await _settle()
	_choose(app, "damage")
	var restarted: CombatSim = _start(app, 20261031)
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and app.world.sim == restarted and app.run.offers.is_empty() and not paused, "An old final-choice refresh or completion cannot reopen the shop in a new run")
	app._title()


func _test_benchmark_and_preview(app: Node) -> void:
	for mode: String in ["--benchmark", "--benchmark-runes", "--benchmark-content"]:
		app.args = PackedStringArray(["--benchmark", "--benchmark-seed=20261028"])
		if mode != "--benchmark":
			app.args.append(mode)
		app._start_benchmark()
		app.world.set_physics_process(false)
		var simulation: CombatSim = app.world.sim
		app.run.collect_souls(app.run.xp_to_next_level())
		await _settle()
		_check(app._benchmark and app.screen == MAIN_SCRIPT.Screen.COMBAT and app.world.sim == simulation and not paused and app._combat_upgrade_sim == null, "A real benchmark setup never pauses for pending upgrades: " + mode)
		app._benchmark = false
		app._title()
	app.args = PackedStringArray()
	_start(app)
	app.world.stop()
	app.run.collect_souls(120)
	app.run.finish_wave()
	app.run.generate_shop()
	app.screen = MAIN_SCRIPT.Screen.SHOP
	app.ui.show_shop()
	await _settle()
	_check(app.screen == MAIN_SCRIPT.Screen.SHOP and not app.world.active and not paused and app._combat_upgrade_sim == null, "The production shop-preview sequence retains its shop despite run.changed and pending upgrades")
	app._title()


func _world_signature(app: Node) -> String:
	var world: CombatWorld = app.world
	var simulation: CombatSim = world.sim
	var data: Array = [simulation.elapsed, app.run.elapsed, simulation.player_position, simulation.player_velocity, simulation.invulnerability, simulation._spawn_timer, simulation._cooldowns.duplicate(), simulation.rng.state, app.run.rng.state, simulation.enemy_count, simulation.shot_count, simulation.soul_count, world._hud_clock, world._visual_time, world._shake, world.position, world._damage_flash, world._damage_direction]
	for enemy: CombatSim.Enemy in simulation.enemies:
		if enemy.active:
			data.append([enemy.slot, enemy.uid, enemy.position, enemy.velocity, enemy.health, enemy.age, enemy.action_timer, enemy.slow_timer, enemy.slow_factor, enemy.hurt_timer, enemy.mode])
	for shot: CombatSim.Shot in simulation.shots:
		if shot.active:
			data.append([shot.slot, shot.position, shot.previous, shot.velocity, shot.damage, shot.life, shot.remaining, shot.innate_remaining, shot.return_after, shot.returning, shot.return_cancelled, shot.hit_ids.duplicate()])
	for soul: CombatSim.Soul in simulation.souls:
		if soul.active:
			data.append([soul.slot, soul.position, soul.value, soul.age])
	for zone: CombatSim.WarningZone in simulation.zones:
		data.append([zone.position, zone.age, zone.delay, zone.triggered])
	for effect: CombatSim.Effect in simulation.effects:
		data.append([effect.position, effect.life, effect.total, effect.radius])
	for number: CombatWorld.FloatingNumber in world._numbers:
		data.append([number.position, number.velocity, number.life, number.amount, number.text])
	for flash: CombatWorld.RuneFlash in world._rune_flashes:
		data.append([flash.kind, flash.origin, flash.life])
	for mark in world._impact_painter._marks:
		data.append([mark.origin, mark.age, mark.life])
	return var_to_str(data)


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _button(child, text)
		if found != null:
			return found
	return null


func _escape() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		root.push_input(event, false)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
