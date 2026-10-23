extends SceneTree
## Main-scene signals carry reservations across an accelerated wave boundary.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MAIN_SCRIPT = preload("res://scripts/main.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.size = Vector2i(1280, 720)
	var existed: bool = FileAccess.file_exists(GameStore.PATH)
	var profile_before: PackedByteArray = FileAccess.get_file_as_bytes(GameStore.PATH) if existed else PackedByteArray()
	var app: Node = MAIN.instantiate()
	app.store.persistent = false
	root.add_child(app)
	await _settle()
	app._start_run("bone")
	var state: RunState = app.run
	state.begin(20261026, "bone")
	app.world.begin(state)
	app.world.set_physics_process(false)
	await _end_wave(app)
	_check(app.screen == MAIN_SCRIPT.Screen.SHOP and state.wave == 1, "A production ended signal opens the first shop")
	state.gold = 0
	var original: Dictionary = state.offers[0].duplicate(true)
	var source: Button = app.ui._shop_focus_button("lock:0")
	_check(source != null, "The production shop exposes a reservation without enough gold")
	if source != null:
		source.grab_focus()
		_key(KEY_ENTER)
	await _settle()
	_check(state.is_offer_locked(0) and state.gold == 0, "Real ui_accept reserves an unaffordable item for free")
	var next: Button = app.ui._shop_focus_button("next_wave")
	_check(next != null, "The full shop still exposes the normal next-wave action")
	if next != null:
		next.grab_focus()
		_key(KEY_ENTER)
	app.world.set_physics_process(false)
	_check(app.screen == MAIN_SCRIPT.Screen.COMBAT and state.wave == 2 and state.offers.is_empty(), "Next-wave input clears visible stock and starts the normal wave")
	_check(state.locked_offer_count() == 1, "The reservation survives while no shop offers exist")
	await _end_wave(app)
	_check(app.screen == MAIN_SCRIPT.Screen.SHOP and state.wave == 2, "The second production settlement regenerates the shop")
	var offer: Dictionary = state.offers[0]
	var definition: ContentDef = GameCatalog.weapon(str(original["id"]))
	_check(state.is_offer_locked(0) and offer["id"] == original["id"] and offer["kind"] == original["kind"], "The same weapon remains in its original slot after combat")
	_check(int(offer["price"]) == state.shop_price(definition) and int(offer["price"]) > int(original["price"]), "A reservation uses the second-wave price instead of freezing the first price")
	_check(state.offers.any(func(item: Dictionary) -> bool: return item["kind"] == "rune"), "Reserved weapon slot zero does not remove the second-shop rune guarantee")
	state.gold = int(offer["price"])
	state.changed.emit()
	await _settle()
	var buy: Button = app.ui._shop_focus_button("buy:0")
	_check(buy != null and not buy.disabled, "The new-wave price is actionable after the UI refresh")
	if buy != null:
		buy.grab_focus()
		_key(KEY_ENTER)
	await _settle()
	_check(state.offers[0]["sold"] and state.gold == 0 and state.locked_offer_count() == 0, "The normal buy path charges the repriced offer and releases its lock")
	_check(state.loadout.size() == 2 and int(state.loadout[1]["paid"]) == int(offer["price"]), "The purchased weapon records the actual new-wave paid value")
	app._start_run("bone")
	app.world.set_physics_process(false)
	_check(state.wave == 1 and state.locked_offer_count() == 0 and state.offers.is_empty(), "A production restart clears reservations and old offers")
	app._title()
	_check(FileAccess.file_exists(GameStore.PATH) == existed and (not existed or FileAccess.get_file_as_bytes(GameStore.PATH) == profile_before), "Shop and restart integration leaves the personal profile byte-for-byte unchanged")
	print("ShopLockFlow: %d assertions, %d failures; accelerated wave-end fixture, not a balance test" % [_checks, _failures])
	app._quit_game(0 if _failures == 0 else 1)


func _end_wave(app: Node) -> void:
	var simulation: CombatSim = app.world.sim
	simulation.elapsed = simulation.duration - 0.01
	simulation.step(0.02, Vector2.ZERO)
	await _settle()
	var choices: int = 0
	while app.screen == MAIN_SCRIPT.Screen.UPGRADE and choices < 20:
		for node: Node in app.ui.find_children("*", "Button", true, false):
			if node.text == "选择强化":
				node.pressed.emit()
				break
		choices += 1
		await _settle()


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, false)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
