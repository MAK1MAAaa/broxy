class_name BackpackGrid
extends Control
## Snapshot-only grid input. Inventory transactions belong to RunState/GameUI.

signal item_selected(uid: int)
signal move_requested(uid: int, cell: Vector2i, rotated: bool)
signal merge_requested(source_uid: int, target_uid: int)
signal rune_requested(source_uid: int, target_uid: int)
signal holding_changed(uid: int, rotated: bool, cell: Vector2i)
signal hint_changed(text: String)

const CELL: float = 50.0
const INK := Color("10141e")
const BONE := Color("f0e5cc")
const GOLD := Color("c4a76f")
const CYAN := Color("89d8d2")
const RED := Color("df888d")

class ItemButton extends Button:
	var owner_grid: Control
	var uid: int
	func _get_drag_data(at_position: Vector2) -> Variant:
		return owner_grid.native_drag(uid, at_position)
	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		return owner_grid.accept_drop(position + at_position, data)
	func _drop_data(at_position: Vector2, data: Variant) -> void:
		owner_grid.drop_at(position + at_position, data)

class PreviewLayer extends Control:
	var owner_grid: Control
	func _draw() -> void:
		owner_grid.draw_preview(self)

class ItemArtwork extends Control:
	var owner_grid: Control
	var item: Dictionary
	func _draw() -> void:
		owner_grid.draw_item_material(self, item)

var session_epoch: int = 0
var interaction_enabled: bool = true
var selected_uid: int = -1
var held_uid: int = -1
var held_rotated: bool = false
var cursor: Vector2i = Vector2i.ZERO
var _snapshot: Dictionary = {}
var _items: Dictionary = {}
var _preview: PreviewLayer
var _grab_offset: Vector2i = Vector2i.ZERO
var _native_dragging: bool = false
var _native_committed: bool = false
var _drop_target_cell: Vector2i = Vector2i.ZERO
var _resonance_contacts: Array[Dictionary] = []

func configure(snapshot: Dictionary, epoch: int, selected: int = -1) -> void:
	_snapshot = snapshot.duplicate(true)
	session_epoch = epoch
	selected_uid = selected
	_items.clear()
	for item: Dictionary in _snapshot.get("items", []):
		_items[int(item["uid"])] = item
	custom_minimum_size = Vector2(float(_snapshot.get("width", 6)) * CELL, float(_snapshot.get("max_height", 6)) * CELL)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for item: Dictionary in _snapshot.get("items", []):
		_make_item(item)
	_preview = PreviewLayer.new()
	_preview.owner_grid = self
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_preview)
	_refresh_resonance()
	queue_redraw()

func snapshot_item(uid: int) -> Dictionary:
	return (_items[uid] as Dictionary).duplicate(true) if _items.has(uid) else {}

func select_item(uid: int) -> void:
	if not interaction_enabled or not _items.has(uid):
		return
	selected_uid = uid
	_refresh_selection()
	item_selected.emit(uid)

func begin_placement(uid: int, rotated: Variant = null, cell: Variant = null) -> void:
	if not interaction_enabled or not _items.has(uid):
		return
	held_uid = uid
	selected_uid = uid
	held_rotated = bool(_items[uid].get("rotated", false)) if rotated == null else bool(rotated)
	cursor = Vector2i(int(_items[uid]["x"]), int(_items[uid]["y"])) if cell == null else Vector2i(cell)
	_drop_target_cell = cursor
	_grab_offset = Vector2i.ZERO
	grab_focus()
	_refresh_selection()
	_refresh_preview()

func cancel_placement() -> bool:
	if held_uid < 0:
		return false
	held_uid = -1
	_grab_offset = Vector2i.ZERO
	_native_dragging = false
	holding_changed.emit(-1, false, Vector2i.ZERO)
	hint_changed.emit("已取消整理，物品仍在原位。")
	_refresh_resonance()
	if is_instance_valid(_preview):
		_preview.queue_redraw()
	return true

func rotate_held() -> void:
	if held_uid < 0 or not interaction_enabled:
		return
	var old_offset: Vector2i = _grab_offset
	var old_size: Vector2i = _item_size(_items[held_uid], held_rotated)
	if _native_dragging:
		_grab_offset = Vector2i(old_offset.y, old_size.x - 1 - old_offset.x) if held_rotated else Vector2i(old_size.y - 1 - old_offset.y, old_offset.x)
		cursor += old_offset - _grab_offset
	else:
		_grab_offset = Vector2i.ZERO
	held_rotated = not held_rotated
	_refresh_preview()

func placement_at(cell: Vector2i) -> Dictionary:
	if held_uid < 0 or not _items.has(held_uid):
		return {"valid": false, "error": "请先拿起物品。"}
	var item: Dictionary = _items[held_uid]
	var target_cell: Vector2i = _drop_target_cell if _native_dragging else cell
	for other: Dictionary in _snapshot.get("items", []):
		if int(other["uid"]) == held_uid:
			continue
		var target_area := Rect2i(Vector2i(int(other["x"]), int(other["y"])), _item_size(other, bool(other.get("rotated", false))))
		if not target_area.has_point(target_cell):
			continue
		if str(item["kind"]) == "rune" and str(other["kind"]) == "weapon":
			return {"valid": true, "kind": "rune", "target": int(other["uid"]), "error": "松手或Enter装入符文，原符文退回腾出的格子。"}
		if item["kind"] == other["kind"] and item["id"] == other["id"] and int(item.get("rank", 1)) == int(other.get("rank", 1)) and int(item.get("rank", 1)) < 3:
			return {"valid": true, "kind": "merge", "target": int(other["uid"]), "error": "松手或Enter合成：%s阶 + %s阶 → %s阶。" % [item.get("rank", 1), other.get("rank", 1), int(item.get("rank", 1)) + 1]}
	var dimensions: Vector2i = _item_size(item, held_rotated)
	var area := Rect2i(cell, dimensions)
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(int(_snapshot.get("width", 6)), int(_snapshot.get("height", 4))))
	if not bounds.encloses(area):
		return {"valid": false, "error": "超出已解锁背包，R可旋转。"}
	var overlaps: Array[Dictionary] = []
	for other: Dictionary in _snapshot.get("items", []):
		if int(other["uid"]) == held_uid:
			continue
		var other_area := Rect2i(Vector2i(int(other["x"]), int(other["y"])), _item_size(other, bool(other.get("rotated", false))))
		if area.intersects(other_area):
			overlaps.append(other)
	if overlaps.is_empty():
		return {"valid": true, "kind": "move", "error": "点击或Enter放置；R旋转，Esc取消。"}
	return {"valid": false, "error": "格子已被占用；同名同阶物品才可合成。"}

func commit_placement() -> void:
	if held_uid < 0 or not interaction_enabled:
		return
	grab_focus()
	var placement: Dictionary = placement_at(cursor)
	if not bool(placement.get("valid", false)):
		hint_changed.emit(str(placement["error"]))
		return
	match str(placement["kind"]):
		"merge": merge_requested.emit(held_uid, int(placement["target"]))
		"rune": rune_requested.emit(held_uid, int(placement["target"]))
		_: move_requested.emit(held_uid, cursor, held_rotated)

func native_drag(uid: int, offset: Vector2) -> Variant:
	if not interaction_enabled or not _items.has(uid):
		return null
	select_item(uid)
	begin_placement(uid)
	_grab_offset = _native_grab_cell(offset)
	_native_dragging = true
	_native_committed = false
	var preview := Label.new()
	preview.text = _definition(_items[uid]).display_name + "  R旋转"
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", BONE)
	set_drag_preview(preview)
	return {"type": "embers_backpack", "uid": uid, "epoch": session_epoch}

func accept_drop(point: Vector2, data: Variant) -> bool:
	if not interaction_enabled or not data is Dictionary or data.get("type", "") != "embers_backpack" or int(data.get("epoch", -1)) != session_epoch or int(data.get("uid", -1)) != held_uid:
		return false
	_drop_target_cell = Vector2i((point / CELL).floor())
	cursor = _drop_target_cell - _grab_offset
	_refresh_preview()
	return bool(placement_at(cursor).get("valid", false))

func drop_at(point: Vector2, data: Variant) -> void:
	if accept_drop(point, data):
		_native_committed = true
		commit_placement()

func _can_drop_data(point: Vector2, data: Variant) -> bool:
	return accept_drop(point, data)

func _drop_data(point: Vector2, data: Variant) -> void:
	drop_at(point, data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _native_dragging:
		_native_dragging = false
		if not _native_committed:
			cancel_placement()

func _gui_input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	if event is InputEventMouseMotion and held_uid >= 0 and not _native_dragging:
		cursor = Vector2i((event.position / CELL).floor())
		_refresh_preview()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and held_uid >= 0:
		cursor = Vector2i((event.position / CELL).floor())
		commit_placement()
		accept_event()
	elif event is InputEventKey:
		_handle_key(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if held_uid >= 0 and interaction_enabled and is_visible_in_tree() and event is InputEventKey:
		_handle_key(event)

func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo or held_uid < 0:
		return
	match event.keycode:
		KEY_R: rotate_held()
		KEY_ESCAPE: cancel_placement()
		KEY_ENTER, KEY_KP_ENTER: commit_placement()
		KEY_LEFT: cursor.x -= 1
		KEY_RIGHT: cursor.x += 1
		KEY_UP: cursor.y -= 1
		KEY_DOWN: cursor.y += 1
		_: return
	if not _native_dragging:
		cursor.x = clampi(cursor.x, 0, int(_snapshot.get("width", 6)) - 1)
		cursor.y = clampi(cursor.y, 0, int(_snapshot.get("height", 4)) - 1)
	_refresh_preview()
	get_viewport().set_input_as_handled()

func _activate_item(uid: int) -> void:
	if held_uid >= 0:
		var item: Dictionary = _items[uid]
		cursor = Vector2i(int(item["x"]), int(item["y"]))
		commit_placement()
	else:
		select_item(uid)

func _make_item(item: Dictionary) -> void:
	var uid: int = int(item["uid"])
	var definition: ContentDef = _definition(item)
	var button := ItemButton.new()
	button.name = "BackpackItem%d" % uid
	button.owner_grid = self
	button.uid = uid
	button.position = Vector2(int(item["x"]), int(item["y"])) * CELL + Vector2.ONE * 2.0
	button.size = Vector2(_item_size(item, bool(item.get("rotated", false)))) * CELL - Vector2.ONE * 4.0
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta("shop_focus_id", "bag:%d" % uid)
	button.pressed.connect(_activate_item.bind(uid))
	button.focus_entered.connect(func() -> void:
		if held_uid < 0:
			select_item(uid))
	button.tooltip_text = "%s · %d阶\n占格 %d×%d；拖拽移动，R旋转。\n%s" % [definition.display_name, int(item.get("rank", 1)), _item_size(item, bool(item.get("rotated", false))).x, _item_size(item, bool(item.get("rotated", false))).y, definition.description]
	add_child(button)
	_style_item(button, item)
	var artwork := ItemArtwork.new()
	artwork.name = "BoxMaterial"
	artwork.owner_grid = self
	artwork.item = item.duplicate(true)
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.focus_mode = Control.FOCUS_NONE
	artwork.size = button.size
	button.add_child(artwork)
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.texture = load("res://assets/icons/%s.svg" % definition.icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var extent: float = 30.0 if button.size.y < 60 else 42.0
	icon.size = Vector2.ONE * extent
	icon.position = Vector2(6, 12) if button.size.y < 60 and button.size.x > 70 else (button.size - icon.size) * 0.5 + Vector2(0, 3)
	button.add_child(icon)
	var rank := Label.new()
	rank.name = "ItemRank"
	rank.text = ["", "Ⅰ", "Ⅱ", "Ⅲ"][clampi(int(item.get("rank", 1)), 1, 3)]
	rank.position = Vector2(5, 1)
	rank.add_theme_font_size_override("font_size", 12)
	rank.add_theme_color_override("font_color", CYAN if int(item.get("rank", 1)) == 2 else Color("d8b5f1") if int(item.get("rank", 1)) == 3 else GOLD)
	rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(rank)
	if button.size.y > 60 or button.size.x > 70:
		var label := Label.new()
		label.text = definition.display_name
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", BONE)
		label.position = Vector2(40, 17) if button.size.y < 60 else Vector2(3, button.size.y - 19)
		label.size = Vector2(button.size.x - label.position.x - 3, 18)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
	var rune: Dictionary = item.get("rune", {})
	if not rune.is_empty():
		var definition_rune: ContentDef = GameCatalog.rune(str(rune["id"]))
		var socket := TextureRect.new()
		socket.name = "SocketRuneBadge"
		socket.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		socket.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		socket.texture = load("res://assets/icons/%s.svg" % definition_rune.icon)
		socket.position = Vector2(button.size.x - 19, 3)
		socket.size = Vector2(16, 16)
		socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.set_meta("rune_id", str(rune["id"]))
		socket.set_meta("rune_rank", int(rune.get("rank", 1)))
		button.add_child(socket)

func _style_item(button: Button, item: Dictionary) -> void:
	var definition: ContentDef = _definition(item)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = _material_color(str(item["kind"]))
		if state == "pressed":
			style.bg_color = style.bg_color.lightened(0.12)
		elif state == "hover":
			style.bg_color = style.bg_color.lightened(0.05)
		style.border_color = CYAN if int(item["uid"]) == selected_uid or state == "focus" else definition.color.lerp(GOLD, 0.5)
		style.set_border_width_all(2 if int(item["uid"]) == selected_uid or state == "focus" else 1)
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state, style)

func _refresh_selection() -> void:
	for child: Node in get_children():
		if child is ItemButton:
			_style_item(child, _items[child.uid])
	_refresh_resonance()

func _refresh_preview() -> void:
	holding_changed.emit(held_uid, held_rotated, cursor)
	hint_changed.emit(str(placement_at(cursor).get("error", "")))
	_refresh_resonance()
	if is_instance_valid(_preview):
		_preview.queue_redraw()

func _draw() -> void:
	for y: int in int(_snapshot.get("max_height", 6)):
		for x: int in int(_snapshot.get("width", 6)):
			var active: bool = y < int(_snapshot.get("height", 4))
			var rect := Rect2(Vector2(x, y) * CELL + Vector2.ONE, Vector2.ONE * (CELL - 2.0))
			draw_rect(rect, Color("252127") if active else Color("11151e"))
			draw_rect(rect, Color("615247") if active else Color("2d303a"), false, 1.0)
			if active:
				draw_line(rect.position + Vector2(4, 5), rect.position + Vector2(43, 5), Color("40323a"), 1.0)
				draw_line(rect.position + Vector2(5, 43), rect.position + Vector2(43, 43), Color("171720"), 1.0)
				for stitch: int in 3:
					var stitch_y: float = float(12 + stitch * 11)
					draw_line(rect.position + Vector2(4, stitch_y), rect.position + Vector2(6, stitch_y + 3), Color("51413d"), 1.0)
			if not active:
				draw_line(rect.position + Vector2(16, 24), rect.position + Vector2(32, 24), Color("3e3b42"), 1.0)

func draw_preview(canvas: Control) -> void:
	for contact: Dictionary in _resonance_contacts:
		var points: PackedVector2Array = contact["points"]
		var direction: Vector2 = (points[1] - points[0]).normalized()
		var first: Vector2 = points[0] + direction * 7.0
		var last: Vector2 = points[1] - direction * 7.0
		canvas.draw_line(first, last, Color(CYAN, 0.12), 7.0, true)
		canvas.draw_line(first, last, Color(GOLD, 0.9), 2.0, true)
		canvas.draw_circle(first, 2.1, CYAN)
		canvas.draw_circle(last, 2.1, CYAN)
	if held_uid < 0 or not _items.has(held_uid):
		return
	var placement: Dictionary = placement_at(cursor)
	var tint: Color = CYAN if bool(placement.get("valid", false)) else RED
	if placement.get("kind", "") == "merge":
		tint = GOLD
	var rect := Rect2(Vector2(cursor) * CELL + Vector2.ONE * 2.0, Vector2(_item_size(_items[held_uid], held_rotated)) * CELL - Vector2.ONE * 4.0)
	if placement.get("kind", "") in ["merge", "rune"] and _items.has(int(placement.get("target", -1))):
		var target: Dictionary = _items[int(placement["target"])]
		rect = Rect2(Vector2(int(target["x"]), int(target["y"])) * CELL + Vector2.ONE * 2.0, Vector2(_item_size(target, bool(target.get("rotated", false)))) * CELL - Vector2.ONE * 4.0)
	canvas.draw_rect(rect, Color(tint, 0.22))
	canvas.draw_rect(rect, tint, false, 2.0)

func resonance_contacts() -> Array[Dictionary]:
	return _resonance_contacts.duplicate(true)

func _refresh_resonance() -> void:
	_resonance_contacts.clear()
	var focused: int = held_uid if held_uid >= 0 else selected_uid
	if not _items.has(focused):
		if is_instance_valid(_preview):
			_preview.queue_redraw()
		return
	var layout: Array = (_snapshot.get("items", []) as Array).duplicate(true)
	if held_uid >= 0:
		var placement: Dictionary = placement_at(cursor)
		if not bool(placement.get("valid", false)) or str(placement.get("kind", "")) != "move":
			if is_instance_valid(_preview):
				_preview.queue_redraw()
			return
		for item: Dictionary in layout:
			if int(item["uid"]) == held_uid:
				item["x"] = cursor.x
				item["y"] = cursor.y
				item["rotated"] = held_rotated
	var by_uid: Dictionary = {}
	for item: Dictionary in layout:
		by_uid[int(item["uid"])] = item
	var resonance: Dictionary = BackpackResonance.evaluate(layout)
	for weapon_uid: int in resonance:
		for relic_uid: int in resonance[weapon_uid].get("source_uids", []):
			if focused != weapon_uid and focused != relic_uid:
				continue
			if not by_uid.has(weapon_uid) or not by_uid.has(relic_uid):
				continue
			var segment: PackedVector2Array = BackpackResonance.contact_segment(by_uid[weapon_uid], by_uid[relic_uid])
			if segment.size() == 2:
				_resonance_contacts.append({"weapon_uid": weapon_uid, "relic_uid": relic_uid,
					"points": PackedVector2Array([segment[0] * CELL, segment[1] * CELL])})
	if is_instance_valid(_preview):
		_preview.queue_redraw()

func draw_item_material(canvas: Control, item: Dictionary) -> void:
	var extent: Vector2 = canvas.size
	var kind: String = str(item["kind"])
	var tint: Color = _definition(item).color.lerp(GOLD, 0.65)
	canvas.draw_rect(Rect2(Vector2(4, 4), Vector2(extent.x - 8, 10)), Color(tint, 0.045))
	canvas.draw_line(Vector2(5, extent.y - 5), Vector2(extent.x - 5, extent.y - 5), Color("12141c"), 2.0)
	if kind == "weapon":
		canvas.draw_line(Vector2(5, 19), Vector2(extent.x - 5, 7), Color(tint, 0.08), 1.0)
	elif kind == "relic":
		for row: int in range(20, int(extent.y) - 8, 12):
			canvas.draw_line(Vector2(5, row), Vector2(8, row + 2), Color(tint, 0.11), 1.0)
	else:
		canvas.draw_rect(Rect2(Vector2(6, 6), extent - Vector2.ONE * 12), Color(tint, 0.08), false, 1.0)
	for corner: Vector2 in [Vector2(4, 4), Vector2(extent.x - 4, 4), Vector2(4, extent.y - 4), extent - Vector2.ONE * 4]:
		var horizontal: float = 1.0 if corner.x < extent.x * 0.5 else -1.0
		var vertical: float = 1.0 if corner.y < extent.y * 0.5 else -1.0
		canvas.draw_line(corner, corner + Vector2(7 * horizontal, 0), Color(tint, 0.48), 1.0)
		canvas.draw_line(corner, corner + Vector2(0, 7 * vertical), Color(tint, 0.48), 1.0)
	var rank: int = clampi(int(item.get("rank", 1)), 1, 3)
	var rank_tint: Color = CYAN if rank == 2 else Color("d8b5f1") if rank == 3 else GOLD
	for mark: int in rank:
		var mark_y: float = float(22 + mark * 5)
		canvas.draw_line(Vector2(3, mark_y), Vector2(6, mark_y), Color(rank_tint, 0.85), 1.0, true)
	var rune: Dictionary = item.get("rune", {})
	if not rune.is_empty():
		canvas.draw_rect(Rect2(Vector2(extent.x - 20, 2), Vector2(18, 18)), Color("191725"))
		canvas.draw_rect(Rect2(Vector2(extent.x - 20, 2), Vector2(18, 18)), Color("746382"), false, 1.0)
		for mark: int in clampi(int(rune.get("rank", 1)), 1, 3):
			var mark_x: float = extent.x - 17 + float(mark * 4)
			canvas.draw_line(Vector2(mark_x, 21), Vector2(mark_x + 2, 21), Color("bfa2e6"), 1.0)

static func _material_color(kind: String) -> Color:
	match kind:
		"weapon": return Color("242a34")
		"relic": return Color("2e272c")
	return Color("282537")

static func _definition(item: Dictionary) -> ContentDef:
	match str(item["kind"]):
		"rune": return GameCatalog.rune(str(item["id"]))
		"relic": return GameCatalog.relic(str(item["id"]))
	return GameCatalog.weapon(str(item["id"]))

static func _item_size(item: Dictionary, rotated: bool) -> Vector2i:
	var dimensions: Vector2i = _definition(item).inventory_size
	return Vector2i(dimensions.y, dimensions.x) if rotated else dimensions

static func _native_grab_cell(button_offset: Vector2) -> Vector2i:
	return Vector2i(((button_offset + Vector2.ONE * 2.0) / CELL).floor())
