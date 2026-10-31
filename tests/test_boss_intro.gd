extends SceneTree
## Arrival text belongs to a real encounter clock, never to a rebuilt HUD.

const STEP: float = 1.0 / 60.0
var _checks: int = 0
var _failures: int = 0

class SilentSound extends SoundBank:
	func _ready() -> void:
		pass
	func play(_id: String, _loudness: float = -10.0) -> void:
		pass
	func play_cue(_id: String, _loudness: float, _cue: String) -> void:
		pass

class StationaryWorld extends CombatWorld:
	func _movement() -> Vector2:
		return Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for index: int in 3:
		await process_frame

func _begin(world: CombatWorld, ui: GameUI, wave: int = 8) -> void:
	var state := RunState.new()
	state.begin(20261031, "bone", "reliquary", "alk")
	state.wave = wave
	ui.bind(state)
	ui.show_hud()
	world.begin(state)
	world.sim.sandbox = true
	world.sim._cooldowns.fill(9999.0)
	if world.sim.boss != null:
		world.sim.boss.definition = world.sim.boss.definition.duplicate() as ContentDef
		world.sim.boss.definition.speed = 0.0

func _step(world: CombatWorld, count: int = 1) -> void:
	for index: int in count:
		world.sim.run.health = world.sim.run.stat("max_health")
		world._physics_process(STEP)

func _arrival(ui: GameUI) -> Label:
	return (ui._hud["boss"] as BossHUD).find_child("BossArrivalName", true, false) as Label

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1280, 720)
	var sound := SilentSound.new()
	root.add_child(sound)
	var world := StationaryWorld.new()
	world.sound = sound
	root.add_child(world)
	world.set_physics_process(false)
	world.apply_visual_settings({"shake": false, "flash": true})
	var ui := GameUI.new()
	root.add_child(ui)
	world.hud_changed.connect(ui.update_hud)
	_begin(world, ui)
	await _settle()
	_check(world.sim.boss != null and world.sim.boss.active, "The fixture begins the actual eighth-wave boss encounter")
	_check(is_equal_approx(float(world.hud_snapshot()["boss_intro_left"]), CombatWorld.BOSS_INTRO_SECONDS), "The actual encounter begins with the complete arrival interval")
	_check(_arrival(ui).is_visible_in_tree() and _arrival(ui).text == GameCatalog.enemy("boss").display_name, "The real begin signal displays the actual boss name")
	_step(world, 30)
	var before: float = float(world.hud_snapshot()["boss_intro_left"])
	_check(is_equal_approx(before, CombatWorld.BOSS_INTRO_SECONDS - 0.5), "Only actual fixed steps reduce the arrival interval")
	var elapsed: float = world.sim.elapsed
	var simulation: Dictionary = world.sim.snapshot()
	for repeat: int in 5:
		ui.update_hud(world.hud_snapshot())
	await _settle()
	_check(world.sim.elapsed == elapsed and world.sim.snapshot() == simulation and float(world.hud_snapshot()["boss_intro_left"]) == before, "Snapshot reads, UI updates and render frames change neither simulation nor arrival time")
	paused = true
	world.apply_visual_settings({"shake": false, "flash": false})
	_step(world, 30)
	await _settle()
	_check(world.sim.elapsed == elapsed and float(world.hud_snapshot()["boss_intro_left"]) == before and _arrival(ui).is_visible_in_tree(), "Pause and visual settings freeze the remaining real interval")
	paused = false
	ui.show_hud()
	ui.update_hud(world.hud_snapshot())
	await _settle()
	_check(float(world.hud_snapshot()["boss_intro_left"]) == before and _arrival(ui).is_visible_in_tree(), "Rebuilding the live HUD preserves the remaining interval instead of restarting it")
	_step(world, 120)
	ui.update_hud(world.hud_snapshot())
	await _settle()
	_check(world.sim.elapsed > CombatWorld.BOSS_INTRO_SECONDS and float(world.hud_snapshot()["boss_intro_left"]) == 0.0, "The interval expires after 2.4 seconds of actual combat time")
	_check((ui._hud["boss"] as BossHUD).visible and not _arrival(ui).visible and _arrival(ui).text.is_empty(), "The live boss retains only its health bar after arrival")
	ui.show_hud()
	ui.update_hud(world.hud_snapshot())
	await _settle()
	_check(not _arrival(ui).visible and float(world.hud_snapshot()["boss_intro_left"]) == 0.0, "Rebuilding an expired HUD never replays the boss name")
	_begin(world, ui)
	await _settle()
	_check(world.sim.elapsed == 0.0 and is_equal_approx(float(world.hud_snapshot()["boss_intro_left"]), CombatWorld.BOSS_INTRO_SECONDS) and _arrival(ui).is_visible_in_tree(), "A genuinely new eighth-wave encounter receives its own single arrival interval")
	world.sim.apply_damage(world.sim.boss, world.sim.boss.max_health * 2.0, "bone")
	ui.update_hud(world.hud_snapshot())
	_check(float(world.hud_snapshot()["boss_intro_left"]) == 0.0 and not (ui._hud["boss"] as BossHUD).visible, "A real boss defeat immediately clears arrival and health presentation")
	_begin(world, ui)
	world.stop()
	ui.update_hud(world.hud_snapshot())
	_check(float(world.hud_snapshot()["boss_intro_left"]) == 0.0, "Stopping an encounter immediately clears its arrival interval")
	_begin(world, ui, 1)
	await _settle()
	_check(world.sim.boss == null and float(world.hud_snapshot()["boss_intro_left"]) == 0.0 and not (ui._hud["boss"] as BossHUD).visible, "Ordinary waves have no boss arrival or health presentation")
	world.stop()
	ui.queue_free()
	world.queue_free()
	sound.queue_free()
	await _settle()
	print("BossIntro: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
