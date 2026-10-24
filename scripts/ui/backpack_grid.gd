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
	var icon := TextureRect.new()
	icon.texture = load("res://assets/icons/%s.svg" % definition.icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var extent: float = 30.0 if button.size.y < 60 else 42.0
	icon.size = Vector2.ONE * extent
	icon.position = Vector2(6, 12) if button.size.y < 60 and button.size.x > 70 else (button.size - icon.size) * 0.5 + Vector2(0, 3)
	button.add_child(icon)
	var rank := Label.new()
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
	if not (item.get("rune", {}) as Dictionary).is_empty():
		var socket := Label.new()
		socket.text = "◆"
		socket.position = Vector2(button.size.x - 15, 1)
		socket.add_theme_font_size_override("font_size", 11)
		socket.add_theme_color_override("font_color", Color("bfa2e6"))
		socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(socket)

func _style_item(button: Button, item: Dictionary) -> void:
	var definition: ContentDef = _definition(item)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("242533") if state != "pressed" else Color("343448")
		style.border_color = CYAN if int(item["uid"]) == selected_uid or state == "focus" else definition.color.lerp(GOLD, 0.5)
		style.set_border_width_all(2 if int(item["uid"]) == selected_uid or state == "focus" else 1)
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state, style)

func _refresh_selection() -> void:
	for child: Node in get_children():
		if child is ItemButton:
			_style_item(child, _items[child.uid])

func _refresh_preview() -> void:
	holding_changed.emit(held_uid, held_rotated, cursor)
	hint_changed.emit(str(placement_at(cursor).get("error", "")))
	if is_instance_valid(_preview):
		_preview.queue_redraw()

func _draw() -> void:
	for y: int in int(_snapshot.get("max_height", 6)):
		for x: int in int(_snapshot.get("width", 6)):
			var active: bool = y < int(_snapshot.get("height", 4))
			var rect := Rect2(Vector2(x, y) * CELL + Vector2.ONE, Vector2.ONE * (CELL - 2.0))
			draw_rect(rect, Color("1b1c27") if active else Color("11151e"))
			draw_rect(rect, Color("514b47") if active else Color("2d303a"), false, 1.0)
			if not active:
				draw_line(rect.position + Vector2(16, 24), rect.position + Vector2(32, 24), Color("3e3b42"), 1.0)

func draw_preview(canvas: Control) -> void:
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
