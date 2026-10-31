extends SceneTree
## Real inventory fixtures exercise the resonance grid without changing its input geometry.

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_material_and_socket_family()
	await _test_contact_selection_and_geometry()
	await _test_placement_preview_is_pure()
	print("ResonanceGrid: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _state() -> RunState:
	var state := RunState.new()
	state.begin(20261025, "bone")
	state.gold = 10000
	return state

func _buy(state: RunState, kind: String, id: String) -> int:
	var definition: ContentDef = BackpackInventory.definition(kind, id)
	state.offers = [{"kind": kind, "id": id, "price": state.shop_price(definition), "sold": false}]
	_check(state.buy_offer(0), "The visual fixture purchases a real stored item: " + id)
	return int(state.backpack_snapshot()["items"].back()["uid"])

func _ranked(state: RunState, kind: String, id: String, rank: int, existing: int = -1) -> int:
	if rank == 1:
		return existing if existing >= 0 else _buy(state, kind, id)
	var first: int = _ranked(state, kind, id, rank - 1, existing)
	var second: int = _ranked(state, kind, id, rank - 1)
	_check(state.merge_items(second, first), "The visual fixture formally merges its rank: " + id)
	return first

func _grid(state: RunState, selected: int = -1) -> BackpackGrid:
	var grid := BackpackGrid.new()
	root.add_child(grid)
	grid.configure(state.backpack_snapshot(), 10, selected)
	grid.size = Vector2(300, 300)
	return grid

func _dispose(grid: BackpackGrid) -> void:
	grid.queue_free()
	await process_frame

func _test_material_and_socket_family() -> void:
	for rune_id: String in ["pierce", "bounce", "blast"]:
		for rank: int in range(1, 4):
			var state: RunState = _state()
			var weapon_uid: int = _ranked(state, "weapon", "bone", rank, int(state.loadout[0]["uid"]))
			var rune_uid: int = _ranked(state, "rune", rune_id, rank)
			_check(state.equip_rune(state.rune_index_for_uid(rune_uid), state.weapon_index_for_uid(weapon_uid)), "The actual ranked rune is attached before drawing")
			var grid: BackpackGrid = _grid(state, weapon_uid)
			await process_frame
			var button := grid.find_child("BackpackItem%d" % weapon_uid, true, false) as Button
			_check(button != null and button.position == Vector2(2, 2) and button.size == Vector2(46, 146), "Material decoration preserves the three-cell item's exact drag geometry")
			_check(str(button.get_meta("shop_focus_id", "")) == "bag:%d" % weapon_uid, "Material decoration preserves the stable item focus identity")
			var material := button.find_child("BoxMaterial", false, false) as Control
			_check(material != null and material.size == button.size and int((material.get("item") as Dictionary)["rank"]) == rank, "The material layer receives the item's actual rank for its engraved marks")
			var rank_label := button.find_child("ItemRank", false, false) as Label
			_check(rank_label != null and rank_label.text == ["", "Ⅰ", "Ⅱ", "Ⅲ"][rank], "Engraved marks retain the explicit rank numeral")
			var badge := button.find_child("SocketRuneBadge", false, false) as TextureRect
			var expected_rune_path: String = AdventureArt.FAN_ROOT + "icons/%s.png" % GameCatalog.rune(rune_id).icon
			_check(badge != null and badge.texture != null and badge.texture.resource_path == expected_rune_path, "Each socket badge uses its real rune family's supplied PNG art: " + rune_id)
			_check(str(badge.get_meta("rune_id", "")) == rune_id and int(badge.get_meta("rune_rank", 0)) == rank, "The socket identity and engraving rank match the attached rune")
			_check(badge.get_rect().size == Vector2(16, 16) and Rect2(Vector2.ZERO, button.size).encloses(badge.get_rect()), "The actual socket control remains sixteen pixels and cannot escape its parent box")
			_check(button.get_global_rect().encloses(badge.get_global_rect()), "The settled socket badge is enclosed by its weapon in native viewport coordinates")
			var passive: bool = true
			for child: Node in button.get_children():
				if child is Control:
					passive = passive and child.mouse_filter == Control.MOUSE_FILTER_IGNORE and child.focus_mode == Control.FOCUS_NONE and not child.is_processing()
			_check(passive and not material.is_physics_processing(), "All material, icon, rank and socket decoration leaves native input to the item button")
			_check(button.get_child_count() <= 6 and grid.get_child_count() == 2, "The decorated one-item grid has a fixed, bounded number of nodes")
			await _dispose(grid)

func _contact_state() -> RunState:
	var state: RunState = _state()
	var relic: int = _buy(state, "relic", "damage")
	_check(state.move_item(relic, Vector2i(1, 1), false), "The contact fixture places one actual relic on the weapon's right edge")
	var remote: int = _buy(state, "relic", "armor")
	_check(state.move_item(remote, Vector2i(4, 3), false), "The second relic is intentionally remote")
	return state

func _test_contact_selection_and_geometry() -> void:
	var state: RunState = _contact_state()
	var uid: int = int(state.loadout[0]["uid"])
	var grid: BackpackGrid = _grid(state)
	_check(grid.resonance_contacts().is_empty(), "Unselected inventory does not illuminate a full connection network")
	grid.select_item(uid)
	var contacts: Array[Dictionary] = grid.resonance_contacts()
	_check(contacts.size() == 1 and contacts[0]["weapon_uid"] == uid and contacts[0]["relic_uid"] == 2, "Selecting a weapon shows only its actual adjacent relic")
	var points: PackedVector2Array = contacts[0]["points"]
	_check(points == PackedVector2Array([Vector2(50, 50), Vector2(50, 100)]), "A one-cell shared edge maps directly to the correct fifty-pixel grid seam")
	contacts[0]["weapon_uid"] = -1
	_check(grid.resonance_contacts()[0]["weapon_uid"] == uid, "Exposed contact metadata is a copy rather than mutable display state")
	grid.select_item(3)
	_check(grid.resonance_contacts().is_empty(), "A remote selected relic has no invented connection")
	var frost: int = _buy(state, "weapon", "frost")
	_check(state.move_item(frost, Vector2i(2, 1), false), "The second weapon is placed on the same relic's opposite edge")
	grid.configure(state.backpack_snapshot(), 11, 2)
	contacts = grid.resonance_contacts()
	_check(contacts.size() == 2, "Selecting a support relic exposes both directly connected weapons")
	grid.select_item(frost)
	_check(grid.resonance_contacts().size() == 1 and grid.resonance_contacts()[0]["weapon_uid"] == frost, "Switching to a weapon filters out another weapon's relation")
	await _dispose(grid)

func _test_placement_preview_is_pure() -> void:
	var state: RunState = _contact_state()
	var uid: int = int(state.loadout[0]["uid"])
	var before: String = JSON.stringify(state.backpack_snapshot())
	var grid: BackpackGrid = _grid(state, uid)
	grid.begin_placement(uid, false, Vector2i(2, 0))
	_check(grid.placement_at(grid.cursor)["kind"] == "move" and grid.resonance_contacts().size() == 1, "A legal ghost evaluates the temporary layout before any transaction")
	_check(grid.resonance_contacts()[0]["points"] == PackedVector2Array([Vector2(100, 50), Vector2(100, 100)]), "The temporary contact follows the proposed left edge instead of the item's stored edge")
	grid.rotate_held()
	_check(grid.placement_at(grid.cursor)["valid"] and grid.resonance_contacts().is_empty(), "Rotating the legal ghost changes a former shared edge into a non-resonating corner")
	grid.cursor = Vector2i(6, 0)
	grid._refresh_preview()
	_check(not grid.placement_at(grid.cursor)["valid"] and grid.resonance_contacts().is_empty(), "An out-of-bounds ghost cannot advertise hypothetical resonance")
	_check(JSON.stringify(state.backpack_snapshot()) == before and grid.snapshot_item(uid)["x"] == 0, "Previewing valid and invalid layouts does not modify the state or stored grid snapshot")
	grid.cancel_placement()
	_check(grid.resonance_contacts().size() == 1 and grid.resonance_contacts()[0]["points"] == PackedVector2Array([Vector2(50, 50), Vector2(50, 100)]), "Canceling restores the actual stored relation")
	var source: int = _buy(state, "weapon", "bone")
	before = JSON.stringify(state.backpack_snapshot())
	grid.configure(state.backpack_snapshot(), 12, source)
	grid.begin_placement(source, false, Vector2i.ZERO)
	_check(grid.placement_at(grid.cursor)["kind"] == "merge" and grid.resonance_contacts().is_empty(), "A merge target does not pretend the source ghost was placed as a separate weapon")
	grid.cancel_placement()
	var rune: int = _buy(state, "rune", "blast")
	before = JSON.stringify(state.backpack_snapshot())
	grid.configure(state.backpack_snapshot(), 13, rune)
	grid.begin_placement(rune, false, Vector2i.ZERO)
	_check(grid.placement_at(grid.cursor)["kind"] == "rune" and grid.resonance_contacts().is_empty(), "A socket drop does not invent a loose-rune adjacency bonus")
	_check(JSON.stringify(state.backpack_snapshot()) == before, "Merge and socket hover previews remain read-only")
	await _dispose(grid)
