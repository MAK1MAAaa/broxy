extends SceneTree
## Real purchases and previews expose actor ownership without inventing locked R damage.

var _checks: int = 0
var _failures: int = 0
var _ui: GameUI

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

func _state(hero_id: String) -> RunState:
	var state := RunState.new()
	state.begin(20261102, "bone", "reliquary", hero_id)
	state.gold = 10000
	while state.backpack.height < 6:
		_check(state.expand_backpack(), "The fixture expands through the real inventory transaction")
	return state

func _offer(state: RunState, id: String, kind: String = "weapon") -> void:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers.assign([{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}])

func _buy(state: RunState, id: String, kind: String = "weapon") -> int:
	_offer(state, id, kind)
	_check(state.buy_offer(0), "The fixture purchases a real backpack item: " + id)
	var items: Array = state.backpack_snapshot()["items"]
	return int(items.back()["uid"])

func _party(state: RunState) -> void:
	_buy(state, "starfall", "skill")
	_buy(state, "arc_slash", "skill")

func _signature(state: RunState) -> String:
	return JSON.stringify([state.summary(), state.backpack_snapshot(), state.offers, state.hero_skill_parameters(), str(state.rng.state)])

func _show(state: RunState) -> void:
	_ui.bind(state)
	_ui.show_shop()
	await _settle()

func _cells(parent: Node, name: String) -> Array[Node]:
	var panel: Node = parent.find_child(name, true, false)
	if panel == null:
		return []
	var grid: Node = panel.find_child("EquipmentActors", true, false)
	return grid.get_children() if grid != null else []

func _check_changes(parent: Node, name: String, expected: Dictionary) -> void:
	var cells: Array[Node] = _cells(parent, name)
	_check(cells.size() == expected.size(), "The comparison retains every real actor, including unaffected actors: " + name)
	for cell: Node in cells:
		var id: String = str(cell.get_meta("hero_id", ""))
		var delta := cell.find_child("EquipmentActorDelta", true, false) as Label
		_check(expected.has(id) and delta != null and delta.text == str(expected.get(id, "")), "The real actor's relative skill change matches its owner/element scope: " + id)
		var portrait := cell.find_child("ContentIcon_hero_" + id, true, false) as TextureRect
		_check(portrait != null and portrait.texture != null and portrait.texture.resource_path == HeroCatalog.definition(id).idle_path, "Each comparison uses the exact actor's original portrait: " + id)
		_check((cell as Control).focus_mode == Control.FOCUS_NONE, "Read-only actor comparisons do not add keyboard focus stops")

func _check_owner(parent: Node, hero_id: String) -> void:
	var owner: Node = parent.find_child("EquipmentOwner", true, false)
	var portrait := owner.find_child("EquipmentOwnerPortrait", true, false) as TextureRect if owner != null else null
	var name_label := owner.find_child("EquipmentOwnerName", true, false) as Label if owner != null else null
	_check(owner != null and owner.get_meta("owner_ref", {}) == {"kind": "main"}, "The equipment identifies its actual main-character ownership")
	_check(portrait != null and portrait.texture != null and portrait.texture.resource_path == HeroCatalog.definition(hero_id).idle_path, "The owner is shown with the actual main-character portrait")
	_check(name_label != null and name_label.text == HeroCatalog.definition(hero_id).display_name, "The owner name comes from the selected main character")

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_ui = GameUI.new()
	root.add_child(_ui)
	_test_rank_amounts()
	_test_purchase_rank_contract()
	await _test_projectile_purchase_details()
	await _test_blocked_projectile_details()
	for physical: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical
		await _test_purchase_scopes("mordiga", "fist_0006", {"mordiga": "0%", "hanabi": "+22.5%", "celtie": "0%"})
		await _test_purchase_scopes("mordiga", "bow_0006", {"mordiga": "+47.5%", "hanabi": "0%", "celtie": "0%"})
		await _test_purchase_scopes("falsche", "book_0002", {"falsche": "+22.5%", "hanabi": "0%", "celtie": "0%"})
	await _test_merge_and_sale()
	await _test_long_owner_and_focus()
	await _test_actual_cast_stacks()
	_ui.queue_free()
	await _settle()
	print("EquipmentUI: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_rank_amounts() -> void:
	for entry: Array in [["bow_0006", 1, "47.5%"], ["bow_0006", 2, "95%"], ["bow_0006", 3, "190%"],
		["sword_0005", 2, "320%"], ["sword_0005", 3, "640%"], ["book_0002", 2, "45%"], ["fist_0006", 3, "90%"], ["staff_0001", 3, "20% ×4"]]:
		var text: String = _ui._weapon_passives_text(GameCatalog.weapon(str(entry[0])), int(entry[1]))
		_check(text.contains(str(entry[2])), "Passive text reads the exact rank array once: " + str(entry))
	_check(not _ui._weapon_passives_text(GameCatalog.weapon("bow_0006"), 2).contains("190%"), "Rank-II Crossbow is not multiplied by its rank weight twice")
	_check(_ui._relative_skill_percent(0.0, 0.0) == "—" and _ui._relative_skill_percent(0.0, 30.0) == "—", "Zero-base skills show no invented relative damage value")
	_check(_ui._relative_skill_percent(100.0, 150.0) == "+50%" and _ui._relative_skill_percent(100.0, 50.0) == "-50%", "The comparison reports signed after/before changes rather than nominal absolute damage")

func _test_purchase_rank_contract() -> void:
	var state: RunState = _state("mordiga")
	_offer(state, "bow_0006")
	state.offers[0]["rank"] = 3
	var before: String = _signature(state)
	var preview: Dictionary = state.weapon_purchase_preview(0)
	var changes: Array = preview["actor_skill_changes"]
	_check(_signature(state) == before and changes.size() == 1, "Weapon purchase projections are pure even when an external offer carries a skill-only rank field")
	_check(state.buy_offer(0) and int(state.backpack_snapshot()["items"].back()["rank"]) == 1, "Weapon purchases retain the existing rank-I transaction; merging supplies higher equipment ranks")
	_check(is_equal_approx(float(changes[0]["damage_after"]), float(state.hero_skill_parameters()["damage"])) and is_equal_approx(state.stat("skill_damage"), 1.475), "The actual scoped rank-I purchase matches its preview instead of projecting the unrelated offer rank")

func _test_projectile_purchase_details() -> void:
	for adjacent: bool in [false, true]:
		var state: RunState = _state("mordiga")
		var relic_uid: int = _buy(state, "echo_stone", "relic") if adjacent else -1
		_offer(state, "sword_0005")
		state.offers[0]["rank"] = 3
		var preview: Dictionary = state.weapon_purchase_preview(0)
		_check(bool(preview["has_projection"]), "Durendal has a real automatic purchase placement")
		_check(is_equal_approx(float(preview["resonance_bonus"]), 0.03 if adjacent else 0.0), "The purchase projection retains the actual automatic-placement resonance")
		_check((relic_uid in preview["resonance_sources"]) == adjacent, "The projected resonance identifies the real adjacent relic UID")
		_check(is_equal_approx(float(preview["damage"]), 62.4 * (1.03 if adjacent else 1.0)), "Durendal's purchase damage includes its own160-percent attack bonus exactly once")
		var expected: String = "每枚 %.1f伤害 · %d枚/次 · 间隔 %.2f秒" % [float(preview["damage"]), int(preview["shots"]), float(preview["interval"])]
		var before: String = _signature(state)
		await _show(state)
		_ui._show_offer_record(0, _ui._shop_epoch, state.offers[0].duplicate(true))
		await _settle()
		var record: Node = _ui.find_child("ItemRecord", true, false)
		var stats := record.find_child("EquipmentProjectileStats", true, false) as Label if record != null else null
		_check(stats != null and stats.text == expected, "Unowned equipment details use projected damage, interval and shots without multiplying offer rank or current stats again")
		_check(_signature(state) == before, "Reading projectile purchase details leaves the real placement, currency and RNG untouched")
		if stats == null:
			return
		var offered_text: String = stats.text
		_ui._close_item_record(_ui._shop_epoch)
		await _settle()
		_check(state.buy_offer(0), "The projected Durendal is bought through the real production transaction")
		var uid: int = int(state.backpack_snapshot()["items"].back()["uid"])
		var item: Dictionary = state.backpack_item(uid)
		_check(is_equal_approx(state.weapon_damage(item), float(preview["damage"])), "Actual purchased projectile damage equals the independent purchase projection")
		var equipped: Dictionary = state.loadout[state.weapon_index_for_uid(uid)]
		_check(is_equal_approx(float(equipped["resonance_bonus"]), float(preview["resonance_bonus"])), "The actual purchased item's adjacent resonance equals its preview")
		await _show(state)
		_ui._bp_select(uid, _ui._shop_epoch)
		_ui._show_owned_item_record(uid, _ui._shop_epoch)
		await _settle()
		record = _ui.find_child("ItemRecord", true, false)
		stats = record.find_child("EquipmentProjectileStats", true, false) as Label if record != null else null
		_check(stats != null and stats.text == offered_text, "Durendal's projectile details remain identical before and after the actual purchase, including automatic resonance")
		_ui._close_item_record(_ui._shop_epoch)
		await _settle()

func _test_blocked_projectile_details() -> void:
	var state: RunState = _state("mordiga")
	_buy(state, "sword_0005")
	while state.backpack.can_add("relic", "echo_stone"):
		_buy(state, "echo_stone", "relic")
	_offer(state, "sword_0005")
	var preview: Dictionary = state.weapon_purchase_preview(0)
	_check(state.backpack_snapshot()["used_cells"] == state.backpack_snapshot()["total_cells"] and not bool(preview["has_projection"]) and float(preview["damage"]) == 0.0, "A genuinely full backpack has no fictional second-Durendal purchase projection")
	_check(is_equal_approx(state.stat("damage"), 2.6), "The blocked fixture already owns an attack modifier so base parameters differ from current damage")
	var before: String = _signature(state)
	await _show(state)
	_ui._show_offer_record(0, _ui._shop_epoch, state.offers[0].duplicate(true))
	await _settle()
	var record: Node = _ui.find_child("ItemRecord", true, false)
	var stats := record.find_child("EquipmentProjectileStats", true, false) as Label if record != null else null
	_check(stats != null and stats.text == "基础 · 每枚 24.0伤害 · 1枚/次 · 间隔 1.25秒", "Without a valid placement, details explicitly show native base parameters rather than zero or invented post-purchase damage")
	if record == null:
		return
	_check(_cells(record, "EquipmentPurchaseActors").is_empty(), "A blocked placement does not fabricate post-purchase actor comparisons")
	_check(_signature(state) == before, "Viewing blocked purchase details preserves the full inventory, current stats and RNG")
	_ui._close_item_record(_ui._shop_epoch)
	await _settle()
	_check(not state.buy_offer(0) and _signature(state) == before, "The corresponding actual purchase also fails without changing inventory or currency")

func _test_purchase_scopes(hero_id: String, weapon_id: String, expected: Dictionary) -> void:
	var state: RunState = _state(hero_id)
	_party(state)
	_offer(state, weapon_id)
	var before: String = _signature(state)
	await _show(state)
	var buy: Button = _ui._shop_focus_button("buy:0")
	_check(buy != null and not buy.disabled and buy.focus_mode == Control.FOCUS_ALL, "The existing real purchase button remains available")
	_ui._show_offer_record(0, _ui._shop_epoch, state.offers[0].duplicate(true))
	await _settle()
	var record: Node = _ui.find_child("ItemRecord", true, false)
	_check(record != null, "Existing offer details open the actual equipment purchase comparison")
	if record == null:
		return
	_check_owner(record, hero_id)
	_check_changes(record, "EquipmentPurchaseActors", expected)
	var keys: PackedStringArray = []
	for cell: Node in _cells(record, "EquipmentPurchaseActors"):
		keys.append((cell.find_child("EquipmentActorKey", true, false) as Label).text)
	_check(keys == PackedStringArray(["R", "Q", "E"]), "Avatar comparisons identify the current real R/Q/E slots")
	_ui._on_input_device_changed("gamepad", 0)
	await _settle()
	keys.clear()
	for cell: Node in _cells(record, "EquipmentPurchaseActors"):
		keys.append((cell.find_child("EquipmentActorKey", true, false) as Label).text)
	_check(keys == PackedStringArray(["RB", "X", "Y"]), "The same comparison respects gamepad input prompts")
	_ui._on_input_device_changed("keyboard", -1)
	var close := record.find_child("CloseItemRecord", true, false) as Button
	_check(close != null and root.gui_get_focus_owner() == close and close.focus_mode == Control.FOCUS_ALL, "The existing modal return action retains keyboard focus")
	var bounds := Rect2(Vector2.ZERO, Vector2(1280, 720))
	_check(bounds.grow(1.0).encloses((record as Control).get_global_rect()), "Equipment details remain inside the scaled reference viewport")
	_ui._root.queue_redraw()
	await _settle()
	_check(_signature(state) == before, "Offer inspection, input prompts and drawing never buy or mutate run/inventory/RNG")
	close.pressed.emit()
	await _settle()
	_check(_ui._overlay_mode.is_empty(), "The real modal close callback restores the existing shop")
	var before_damage: float = float(state.hero_skill_parameters().get("damage", 0.0))
	var preview: Dictionary = state.weapon_purchase_preview(0)
	var projected: Array = preview.get("actor_skill_changes", [])
	_check(state.buy_offer(0), "The inspected item can be bought through the actual transaction")
	for actor: Dictionary in projected:
		if (actor["actor_ref"] as Dictionary).get("kind", "") == "main":
			_check(is_equal_approx(float(actor["damage_before"]), before_damage) and is_equal_approx(float(actor["damage_after"]), float(state.hero_skill_parameters().get("damage", 0.0))), "Nominal purchase projection agrees with the actual permanent actor parameters")

func _test_merge_and_sale() -> void:
	var state: RunState = _state("mordiga")
	_party(state)
	var first: int = _buy(state, "bow_0006")
	var second: int = _buy(state, "bow_0006")
	var damage: float = float(state.hero_skill_parameters()["damage"])
	var before: String = _signature(state)
	await _show(state)
	_ui._bp_select(second, _ui._shop_epoch)
	await _settle()
	_check_owner(_ui._bag_details, "mordiga")
	_check_changes(_ui._bag_details, "EquipmentMergeActors", {"mordiga": "0%", "hanabi": "0%", "celtie": "0%"})
	_check(_signature(state) == before, "Reading real merge/sale previews leaves both source UIDs and stats unchanged")
	var merge := _ui.find_child("MergeBackpackItem%d" % first, true, false) as Button
	_check(merge != null and not merge.disabled, "The selected source retains the real merge operation")
	if merge == null:
		return
	merge.pressed.emit()
	await _settle()
	_check(state.backpack_item(second).is_empty() and int(state.backpack_item(first).get("rank", 0)) == 2, "Actual merge preserves the target UID and its equipment owner")
	_check(is_equal_approx(float(state.hero_skill_parameters()["damage"]), damage), "Two rank-I scoped bonuses equal the actual rank-II scope without double multiplication")
	var passives := _ui.find_child("BackpackEquipmentPassives", true, false) as Label
	_check(passives != null and passives.text.contains("95%") and not passives.text.contains("190%"), "Merged inspection shows rank-II's configured95 percent")
	_check_changes(_ui._bag_details, "EquipmentSaleActors", {"mordiga": "-48.7%", "hanabi": "0%", "celtie": "0%"})
	var sale := _ui.find_child("SellBackpackItem", true, false) as Button
	var sale_preview: Dictionary = state.sell_preview(first)
	_check(sale != null and sale.focus_mode == Control.FOCUS_ALL, "The original sale button remains reachable")
	if sale != null:
		sale.pressed.emit()
		await _settle()
	_check(state.backpack_item(first).is_empty(), "The previewed sale executes the actual selected inventory removal")
	for actor: Dictionary in sale_preview.get("actor_skill_changes", []):
		if (actor["actor_ref"] as Dictionary).get("kind", "") == "main":
			_check(is_equal_approx(float(actor["damage_after"]), float(state.hero_skill_parameters()["damage"])), "Sale's relative preview was derived from the actual remaining actor parameters")

func _test_long_owner_and_focus() -> void:
	var state: RunState = _state("mordiga")
	var uid: int = _buy(state, "sword_0005")
	var hero: HeroDef = HeroCatalog.definition("mordiga")
	var original_name: String = hero.display_name
	hero.display_name = "莫迪亚迦莫迪亚迦莫迪亚迦莫迪亚迦"
	for physical: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = physical
		await _show(state)
		_ui._bp_select(uid, _ui._shop_epoch)
		await _settle()
		var label := _ui.find_child("EquipmentOwnerName", true, false) as Label
		_check(label != null and label.clip_text and label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Long owner names have explicit bounded ellipsis rather than growing the backpack layout")
		if label != null:
			_check(label.size.x <= _ui._bag_details.size.x and label.size.x > 0.0, "The actual long name remains within the available details width")
		var move := _ui.find_child("MoveBackpackItem", true, false) as Button
		move.grab_focus()
		await _settle()
		_check(root.gui_get_focus_owner() == move and move.find_next_valid_focus() is Button, "New read-only ownership controls preserve the existing shop focus route")
	hero.display_name = original_name

func _test_actual_cast_stacks() -> void:
	var state: RunState = _state("falsche")
	var uid: int = _buy(state, "staff_0001")
	var sim := CombatSim.new()
	sim.begin(state)
	sim.sandbox = true
	sim._cooldowns.fill(99999.0)
	_ui.bind(state)
	_ui.show_hud()
	_ui.update_hud(sim.snapshot())
	await _settle()
	for cast: int in range(1, 6):
		while not bool(sim.hero_skill_snapshot()["ready"]):
			sim.step(1.0 / 60.0, Vector2.ZERO)
		_check(sim.try_hero_skill(), "The stack HUD receives an actual successful production R cast")
		_ui.update_hud(sim.snapshot())
		await _settle()
		var row := _ui.find_child("EquipmentCastPips_%d" % uid, true, false) as Control
		_check(row != null, "A real equipped Old Staff UID has its own stack meter")
		if row == null:
			continue
		var stacks: int = mini(4, cast)
		_check((row.find_child("EquipmentCastCount", true, false) as Label).text == "%d/4" % stacks, "HUD stack count follows actual UID stacks and the four-layer cap")
		for index: int in 4:
			var pip := row.get_node("EquipmentCastPip%d" % index) as ColorRect
			_check((pip.color == GameUI.HUD_GOLD) == (index < stacks), "The four actual pips match the runtime's committed cast count")
		var total := _ui.find_child("EquipmentPartySkillDamage", true, false) as Label
		_check(total != null and total.text == "技伤 +%d%%" % (stacks * 5), "HUD reads the top-level runtime party skill bonus")
	var before: String = JSON.stringify([sim.snapshot(), _signature(state)])
	_ui._root.queue_redraw()
	await _settle()
	_check(JSON.stringify([sim.snapshot(), _signature(state)]) == before, "Drawing stack pips cannot commit another cast, write equipment state or alter the run")
	_ui.update_hud({"health": state.health, "max_health": state.stat("max_health"), "loadout": state.loadout})
	await _settle()
	var count := _ui.find_child("EquipmentCastCount", true, false) as Label
	_check(count != null and count.text == "0/4", "Older snapshots without runtime fields are handled without stale fabricated stacks")
