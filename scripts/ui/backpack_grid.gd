class_name BackpackGrid
extends Control
## Snapshot-only grid input. Inventory transactions belong to RunState/GameUI.

signal item_selected(uid: int)
signal move_requested(uid: int, cell: Vector2i, rotated: bool)
signal merge_requested(source_uid: int, target_uid: int)
signal rune_requested(source_uid: int, target_uid: int)
signal holding_changed(uid: int, rotated: bool, cell: Vector2i)
signal hint_changed(text: String)
signal placement_cancelled(uid: int)

const CELL: float = 50.0
const INK := Color("fff9e8")
const BONE := Color("253d54")
const GOLD := Color("8a5b20")
const CYAN := Color("14766f")
const RED := Color("b83c50")
const PURPLE := Color("765093")

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
var interaction_enabled: bool = true:
	set(value):
		interaction_enabled = value
		if not value:
			_reset_joy_axes()
		_refresh_selection()
		if is_instance_valid(_preview):
			_preview.queue_redraw()
var selected_uid: int = -1
var held_uid: int = -1
var held_rotated: bool = false
var cursor: Vector2i = Vector2i.ZERO
var _snapshot: Dictionary = {}
var _items: Dictionary = {}
var _icons: Dictionary = {}
var _preview: PreviewLayer
var _grab_offset: Vector2i = Vector2i.ZERO
var _native_dragging: bool = false
var _native_committed: bool = false
var _drop_target_cell: Vector2i = Vector2i.ZERO
var _resonance_contacts: Array[Dictionary] = []
var _joy_axis_x: int = 0
var _joy_axis_y: int = 0
var _input_device: String = "keyboard"
var _native_preview_label: Label
var _skill_keys: PackedStringArray = ["Q", "E"]

func set_skill_bindings(bindings: Dictionary) -> void:
	_skill_keys = [ControlBindings.key_label(int(bindings.get("pulse", KEY_Q))), ControlBindings.key_label(int(bindings.get("skill_secondary", KEY_E)))]
	_refresh_skill_badges()

func _skill_slot(uid: int) -> int:
	var uids: Array[int] = []
	for item: Dictionary in _snapshot.get("items", []):
		if str(item.get("kind", "")) == "skill":
			uids.append(int(item["uid"]))
	uids.sort()
	return uids.find(uid)

func _skill_key(uid: int) -> String:
	var slot: int = _skill_slot(uid)
	if slot < 0 or slot >= 2:
		return ""
	return ("X" if slot == 0 else "Y") if _input_device == "gamepad" else _skill_keys[slot]

func _refresh_skill_badges() -> void:
	for child: Node in get_children():
		if child is ItemButton:
			var badge := child.get_node_or_null("SkillKeyBadge") as Label
			if badge != null:
				badge.text = _skill_key(child.uid)

func set_input_device(kind: String) -> void:
	var next: String = "gamepad" if kind == "gamepad" else "keyboard"
	if next == _input_device:
		return
	_input_device = next
	_refresh_skill_badges()
	for child: Node in get_children():
		if child is ItemButton and _items.has(child.uid):
			child.tooltip_text = _item_tooltip(_items[child.uid])
	if _native_dragging and is_instance_valid(_native_preview_label) and _items.has(held_uid):
		_native_preview_label.text = _native_preview_text(_items[held_uid])
	if held_uid >= 0 and _items.has(held_uid):
		hint_changed.emit(str(placement_at(cursor).get("error", "")))

func configure(snapshot: Dictionary, epoch: int, selected: int = -1) -> void:
	_snapshot = snapshot.duplicate(true)
	session_epoch = epoch
	selected_uid = selected
	_items.clear()
	_icons.clear()
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
	_preview.name = "PlacementPreview"
	_preview.owner_grid = self
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.clip_contents = true
	_preview.size = custom_minimum_size
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
	_reset_joy_axes()
	selected_uid = uid
	held_rotated = bool(_items[uid].get("rotated", false)) if rotated == null else bool(rotated)
	cursor = Vector2i(int(_items[uid]["x"]), int(_items[uid]["y"])) if cell == null else Vector2i(cell)
	_drop_target_cell = cursor
	_grab_offset = Vector2i.ZERO
	grab_focus()
	_refresh_selection()
	_refresh_preview()

func cancel_placement(restore_focus: bool = false) -> bool:
	if held_uid < 0:
		return false
	var source_uid: int = held_uid
	var native_drag: bool = _native_dragging
	held_uid = -1
	_reset_joy_axes()
	_grab_offset = Vector2i.ZERO
	_native_dragging = false
	_refresh_selection()
	holding_changed.emit(-1, false, Vector2i.ZERO)
	hint_changed.emit("已取消整理，物品仍在原位。")
	_refresh_resonance()
	if is_instance_valid(_preview):
		_preview.queue_redraw()
	if restore_focus and not native_drag:
		placement_cancelled.emit(source_uid)
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

func placement_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if not interaction_enabled or held_uid < 0 or not _items.has(held_uid):
		return targets
	var source: Dictionary = _items[held_uid]
	for other: Dictionary in _snapshot.get("items", []):
		var uid: int = int(other["uid"])
		if uid == held_uid:
			continue
		if str(source["kind"]) == "rune" and str(other["kind"]) == "weapon":
			targets.append({"uid": uid, "kind": "rune", "result_rank": int(source.get("rank", 1)), "replacing": not (other.get("rune", {}) as Dictionary).is_empty()})
		elif source["kind"] == other["kind"] and source["id"] == other["id"] and int(source.get("rank", 1)) == int(other.get("rank", 1)) and int(source.get("rank", 1)) < 3:
			targets.append({"uid": uid, "kind": "merge", "result_rank": int(other.get("rank", 1)) + 1})
	return targets

func placement_at(cell: Vector2i) -> Dictionary:
	if held_uid < 0 or not _items.has(held_uid):
		return {"valid": false, "error": "请先拿起物品。"}
	var item: Dictionary = _items[held_uid]
	var item_name: String = _definition(item).display_name
	var targets: Array[Dictionary] = placement_targets()
	var candidate_hint: String = _candidate_hint(targets)
	var target_cell: Vector2i = _drop_target_cell if _native_dragging else cell
	for candidate: Dictionary in targets:
		var other: Dictionary = _items[int(candidate["uid"])]
		var target_area := Rect2i(Vector2i(int(other["x"]), int(other["y"])), _item_size(other, bool(other.get("rotated", false))))
		if not target_area.has_point(target_cell):
			continue
		var target_name: String = _definition(other).display_name
		if str(candidate["kind"]) == "rune":
			var replacing: bool = bool(candidate["replacing"])
			var hint: String = "%s：%s · %d阶 → %s。" % [_placement_confirm("装入"), item_name, int(candidate["result_rank"]), target_name]
			if replacing:
				var old_rune: Dictionary = other["rune"]
				hint = "%s：%s · %d阶 → %s；%s退回腾出的格子。" % [_placement_confirm("换符"), item_name, int(candidate["result_rank"]), target_name, GameCatalog.rune(str(old_rune["id"])).display_name]
			return {"valid": true, "kind": "rune", "target": int(other["uid"]), "result_rank": int(candidate["result_rank"]), "replacing": replacing, "error": hint + _placement_actions() + candidate_hint}
		return {"valid": true, "kind": "merge", "target": int(other["uid"]), "result_rank": int(candidate["result_rank"]), "error": "%s%s：%d阶 + %d阶 → %d阶。%s%s" % [_placement_confirm("合成"), target_name, int(item.get("rank", 1)), int(other.get("rank", 1)), int(candidate["result_rank"]), _placement_actions(), candidate_hint]}
	var dimensions: Vector2i = _item_size(item, held_rotated)
	var area := Rect2i(cell, dimensions)
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(int(_snapshot.get("width", 6)), int(_snapshot.get("height", 4))))
	if not bounds.encloses(area):
		var rotation_hint: String = "R可旋转。"
		if _input_device == "gamepad":
			rotation_hint = "请拖回背包范围后松手。" if _native_dragging else "X可旋转，B取消。"
		return {"valid": false, "error": "%s超出已解锁背包，%s%s" % [item_name, rotation_hint, candidate_hint]}
	var overlaps: Array[Dictionary] = []
	for other: Dictionary in _snapshot.get("items", []):
		if int(other["uid"]) == held_uid:
			continue
		var other_area := Rect2i(Vector2i(int(other["x"]), int(other["y"])), _item_size(other, bool(other.get("rotated", false))))
		if area.intersects(other_area):
			overlaps.append(other)
	if overlaps.is_empty():
		if _input_device == "gamepad":
			var instruction: String = "松手放置%s。%s" % [item_name, candidate_hint] if _native_dragging else "A放置%s；X旋转，B取消。%s" % [item_name, candidate_hint]
			return {"valid": true, "kind": "move", "error": instruction}
		return {"valid": true, "kind": "move", "error": "点击或Enter放置%s；R旋转，Esc取消。%s" % [item_name, candidate_hint]}
	return {"valid": false, "error": "格子已被占用；%s需移至空格，或与同名同阶物品合成。%s%s" % [item_name, _placement_actions(), candidate_hint]}

func _placement_confirm(action: String) -> String:
	if _input_device != "gamepad":
		return "松手或Enter" + action
	return ("松手" if _native_dragging else "A") + action

func _placement_actions() -> String:
	return "X旋转，B取消。" if _input_device == "gamepad" and not _native_dragging else ""

func _item_tooltip(item: Dictionary) -> String:
	var definition: ContentDef = _definition(item)
	var dimensions: Vector2i = _item_size(item, bool(item.get("rotated", false)))
	var instructions: String = "拖拽移动，R旋转。" if _input_device != "gamepad" else "选择后在「拿起」按钮按A拿起；持物时X旋转、B取消。"
	var text: String = "%s · %d阶\n占格 %d×%d；%s\n%s" % [definition.display_name, int(item.get("rank", 1)), dimensions.x, dimensions.y, instructions, definition.description]
	if int(item.get("uid", -1)) in _snapshot.get("linked_weapons", []):
		text += "\n烛引生效：正下方引魂烛使其优先攻击生命比例最低的敌人。"
	return text

func _native_preview_text(item: Dictionary) -> String:
	return _definition(item).display_name + ("  松手确认" if _input_device == "gamepad" else "  R旋转")

func commit_placement() -> void:
	if held_uid < 0 or not interaction_enabled:
		return
	grab_focus()
	var placement: Dictionary = placement_at(cursor)
	if not bool(placement.get("valid", false)):
		hint_changed.emit(str(placement["error"]))
		return
	var source_uid: int = held_uid
	var destination: Vector2i = cursor
	var rotated: bool = held_rotated
	var target_uid: int = int(placement.get("target", -1))
	match str(placement["kind"]):
		"merge": merge_requested.emit(source_uid, target_uid)
		"rune": rune_requested.emit(source_uid, target_uid)
		_: move_requested.emit(source_uid, destination, rotated)

func native_drag(uid: int, offset: Vector2) -> Variant:
	if not interaction_enabled or not _items.has(uid):
		return null
	select_item(uid)
	begin_placement(uid)
	_grab_offset = _native_grab_cell(offset)
	_native_dragging = true
	_native_committed = false
	var preview := Label.new()
	preview.text = _native_preview_text(_items[uid])
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", BONE)
	_native_preview_label = preview
	set_drag_preview(preview)
	if _input_device == "gamepad":
		hint_changed.emit(str(placement_at(cursor).get("error", "")))
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

func _input(event: InputEvent) -> void:
	if held_uid < 0 or not interaction_enabled or not is_visible_in_tree() or _native_dragging:
		return
	if event is InputEventJoypadButton:
		if not event.pressed:
			return
		match event.button_index:
			JOY_BUTTON_A: commit_placement()
			JOY_BUTTON_B: cancel_placement(true)
			JOY_BUTTON_X: rotate_held()
			JOY_BUTTON_DPAD_LEFT: cursor.x -= 1
			JOY_BUTTON_DPAD_RIGHT: cursor.x += 1
			JOY_BUTTON_DPAD_UP: cursor.y -= 1
			JOY_BUTTON_DPAD_DOWN: cursor.y += 1
			_: return
		_finish_joy_placement_input()
	elif event is InputEventJoypadMotion:
		var previous: int = 0
		var next: int = 0
		if event.axis == JOY_AXIS_LEFT_X:
			previous = _joy_axis_x
			next = _joy_axis_direction(event.axis_value, previous)
			_joy_axis_x = next
			if next != 0 and next != previous:
				cursor.x += next
		elif event.axis == JOY_AXIS_LEFT_Y:
			previous = _joy_axis_y
			next = _joy_axis_direction(event.axis_value, previous)
			_joy_axis_y = next
			if next != 0 and next != previous:
				cursor.y += next
		else:
			return
		_finish_joy_placement_input()

static func _joy_axis_direction(value: float, previous: int) -> int:
	if not is_finite(value) or absf(value) <= 0.25:
		return 0
	if value >= 0.55:
		return 1
	if value <= -0.55:
		return -1
	return previous

func _reset_joy_axes() -> void:
	_joy_axis_x = 0
	_joy_axis_y = 0

func _finish_joy_placement_input() -> void:
	if held_uid >= 0:
		cursor.x = clampi(cursor.x, 0, int(_snapshot.get("width", 6)) - 1)
		cursor.y = clampi(cursor.y, 0, int(_snapshot.get("height", 4)) - 1)
		_refresh_preview()
	get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if held_uid >= 0 and interaction_enabled and is_visible_in_tree() and event is InputEventKey:
		_handle_key(event)

func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo or held_uid < 0:
		return
	match event.keycode:
		KEY_R: rotate_held()
		KEY_ESCAPE: cancel_placement(true)
		KEY_ENTER, KEY_KP_ENTER: commit_placement()
		KEY_LEFT: cursor.x -= 1
		KEY_RIGHT: cursor.x += 1
		KEY_UP: cursor.y -= 1
		KEY_DOWN: cursor.y += 1
		_: return
	if held_uid >= 0:
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
	button.tooltip_text = _item_tooltip(item)
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
	button.focus_entered.connect(artwork.queue_redraw)
	button.focus_exited.connect(artwork.queue_redraw)
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.texture = load(AdventureArt.path("res://assets/icons/%s.svg" % definition.icon))
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icons[uid] = icon.texture
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
	rank.add_theme_color_override("font_color", CYAN if int(item.get("rank", 1)) == 2 else Color("765093") if int(item.get("rank", 1)) == 3 else GOLD)
	rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(rank)
	if str(item["kind"]) == "skill":
		var badge := Label.new()
		badge.name = "SkillKeyBadge"
		badge.text = _skill_key(uid)
		badge.clip_text = true
		badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		badge.position = Vector2(button.size.x - 24, 1)
		badge.size = Vector2(20, 16)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", CYAN)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
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
		socket.texture = load(AdventureArt.path("res://assets/icons/%s.svg" % definition_rune.icon))
		socket.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		socket.position = Vector2(button.size.x - 19, 3)
		socket.size = Vector2(16, 16)
		socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.set_meta("rune_id", str(rune["id"]))
		socket.set_meta("rune_rank", int(rune.get("rank", 1)))
		button.add_child(socket)
	if uid in _snapshot.get("linked_weapons", []):
		var link := Label.new()
		link.name = "CandleLink"
		link.text = "↑"
		link.position = Vector2(button.size.x - 14, 24)
		link.add_theme_font_size_override("font_size", 12)
		link.add_theme_color_override("font_color", Color("356936"))
		link.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(link)

func _style_item(button: Button, item: Dictionary) -> void:
	var definition: ContentDef = _definition(item)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = _material_color(str(item["kind"]))
		if state in ["pressed", "hover_pressed"]:
			style.bg_color = style.bg_color.lightened(0.12)
		elif state == "hover":
			style.bg_color = style.bg_color.lightened(0.05)
		style.border_color = CYAN if int(item["uid"]) == selected_uid else definition.color.lerp(GOLD, 0.5)
		style.set_border_width_all(2 if int(item["uid"]) == selected_uid else 1)
		style.set_corner_radius_all(0)
		style.anti_aliasing = false
		button.add_theme_stylebox_override(state, style)
	var focus := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("focus", focus)

func _refresh_selection() -> void:
	for child: Node in get_children():
		if child is ItemButton:
			_style_item(child, _items[child.uid])
			child.modulate = Color(0.7, 0.72, 0.77) if interaction_enabled and child.uid == held_uid else Color.WHITE
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
			draw_rect(rect, Color("e5d9bc") if active else Color("cbd6d0"))
			draw_rect(rect, Color("b4a487") if active else Color("a6b5ab"), false, 1.0)
			draw_line(rect.position + Vector2.ONE, rect.position + Vector2(rect.size.x - 1, 1), Color("d0c3a5") if active else Color("bdcbc3"), 1.0)
			draw_line(rect.position + Vector2.ONE, rect.position + Vector2(1, rect.size.y - 1), Color("d0c3a5") if active else Color("bdcbc3"), 1.0)
			draw_line(rect.position + Vector2(1, rect.size.y - 2), rect.end - Vector2.ONE * 2.0, Color("f7eed8") if active else Color("e2e9e1"), 1.0)
			if active:
				for stitch_y: int in [14, 32]:
					draw_line(rect.position + Vector2(5, stitch_y), rect.position + Vector2(7, stitch_y + 2), Color("ccbea0"), 1.0)
			else:
				var center: Vector2 = rect.get_center().floor()
				var lock_tint := Color("8c9f95")
				draw_rect(Rect2(center + Vector2(-5, -1), Vector2(10, 8)), lock_tint)
				draw_polyline(PackedVector2Array([center + Vector2(-3, -1), center + Vector2(-3, -5), center + Vector2(3, -5), center + Vector2(3, -1)]), lock_tint, 2.0)
				draw_rect(Rect2(center + Vector2(-1, 1), Vector2(2, 3)), Color("dce5dc"))

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
	if not interaction_enabled or held_uid < 0 or not _items.has(held_uid):
		return
	var bounds := Rect2(Vector2.ZERO, Vector2(int(_snapshot.get("width", 6)), int(_snapshot.get("max_height", 6))) * CELL)
	for target: Dictionary in placement_targets():
		_draw_target(canvas, target, bounds)
	var placement: Dictionary = placement_at(cursor)
	var tint: Color = CYAN if bool(placement.get("valid", false)) else RED
	if placement.get("kind", "") == "merge":
		tint = GOLD
	elif placement.get("kind", "") == "rune":
		tint = PURPLE
	var rect := Rect2(Vector2(cursor) * CELL + Vector2.ONE * 2.0, Vector2(_item_size(_items[held_uid], held_rotated)) * CELL - Vector2.ONE * 4.0)
	if placement.get("kind", "") in ["merge", "rune"] and _items.has(int(placement.get("target", -1))):
		var target: Dictionary = _items[int(placement["target"])]
		rect = _item_rect(target)
	var clipped: Rect2 = rect.intersection(bounds.grow(-1.0))
	if not clipped.has_area():
		return
	canvas.draw_rect(clipped, Color(tint, 0.18))
	if str(placement.get("kind", "")) not in ["merge", "rune"]:
		_draw_held_cells(canvas, tint, bounds)
		var texture: Texture2D = _icons.get(held_uid) as Texture2D
		var extent: float = minf(42.0, minf(rect.size.x, rect.size.y) - 12.0)
		var icon_rect := Rect2(rect.get_center() - Vector2.ONE * extent * 0.5, Vector2.ONE * extent)
		# Keep the icon's original shape when a native grab crosses the grid edge.
		if texture != null and bounds.encloses(icon_rect):
			canvas.draw_texture_rect(texture, icon_rect, false, Color(1, 1, 1, 0.85))
	canvas.draw_rect(clipped, tint, false, 2.0)

func _draw_held_cells(canvas: Control, tint: Color, bounds: Rect2) -> void:
	var dimensions: Vector2i = _item_size(_items[held_uid], held_rotated)
	for y: int in dimensions.y:
		for x: int in dimensions.x:
			var rect := Rect2(Vector2(cursor + Vector2i(x, y)) * CELL + Vector2.ONE * 5.0, Vector2.ONE * (CELL - 10.0))
			var clipped: Rect2 = rect.intersection(bounds.grow(-1.0))
			if clipped.has_area():
				canvas.draw_rect(clipped, Color(tint, 0.55), false, 1.0)

func _draw_target(canvas: Control, target: Dictionary, bounds: Rect2) -> void:
	var rect: Rect2 = _item_rect(_items[int(target["uid"])]).grow(-2.0)
	if not bounds.encloses(rect):
		return
	var tint: Color = GOLD if str(target["kind"]) == "merge" else PURPLE
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var directions := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for index: int in 4:
		canvas.draw_line(corners[index], corners[index] + Vector2(directions[index].x * 7.0, 0), tint, 2.0)
		canvas.draw_line(corners[index], corners[index] + Vector2(0, directions[index].y * 7.0), tint, 2.0)
	var center := Vector2(rect.get_center().x, rect.position.y + 8.0)
	canvas.draw_rect(Rect2(center - Vector2(7, 6), Vector2(14, 13)), Color(INK, 0.9))
	if str(target["kind"]) == "merge":
		canvas.draw_polyline(PackedVector2Array([center + Vector2(-4, 1), center + Vector2(0, -3), center + Vector2(4, 1)]), tint, 2.0)
		canvas.draw_line(center + Vector2(0, -2), center + Vector2(0, 5), tint, 2.0)
	else:
		canvas.draw_polyline(PackedVector2Array([center + Vector2(0, -4), center + Vector2(4, 0), center + Vector2(0, 4), center + Vector2(-4, 0), center + Vector2(0, -4)]), tint, 2.0)

static func _item_rect(item: Dictionary) -> Rect2:
	return Rect2(Vector2(int(item["x"]), int(item["y"])) * CELL + Vector2.ONE * 2.0, Vector2(_item_size(item, bool(item.get("rotated", false)))) * CELL - Vector2.ONE * 4.0)

static func _candidate_hint(targets: Array[Dictionary]) -> String:
	var merges: int = 0
	var runes: int = 0
	for target: Dictionary in targets:
		merges += 1 if str(target["kind"]) == "merge" else 0
		runes += 1 if str(target["kind"]) == "rune" else 0
	var hints: PackedStringArray = []
	if merges > 0:
		hints.append("旧金↑合成候选%d件" % merges)
	if runes > 0:
		hints.append("灰紫◇装符候选%d件" % runes)
	return "；".join(hints) + "。" if not hints.is_empty() else "暂无合成或装符候选。"

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
	canvas.draw_rect(Rect2(Vector2(4, 4), Vector2(extent.x - 8, 8)), Color(1, 1, 1, 0.35))
	canvas.draw_line(Vector2(4, extent.y - 5), Vector2(extent.x - 4, extent.y - 5), Color("adbea9"), 2.0)
	if kind == "weapon":
		canvas.draw_line(Vector2(5, 16), Vector2(extent.x - 5, 16), Color(tint, 0.22), 3.0)
	elif kind == "relic":
		for row: int in range(20, int(extent.y) - 8, 10):
			canvas.draw_rect(Rect2(Vector2(5, row), Vector2(2, 3)), Color(tint, 0.35))
	elif kind == "skill":
		canvas.draw_rect(Rect2(Vector2(5, 17), extent - Vector2(10, 22)), Color(CYAN, 0.28), false, 1.0)
		for offset: int in 3:
			var point := Vector2(extent.x - 8 - offset * 5, extent.y - 7)
			canvas.draw_line(point, point + Vector2(3, -3), Color(CYAN, 0.45), 1.0)
	else:
		canvas.draw_rect(Rect2(Vector2(6, 6), extent - Vector2.ONE * 12), Color(PURPLE, 0.16), false, 1.0)
	for corner: Vector2 in [Vector2(4, 4), Vector2(extent.x - 6, 4), Vector2(4, extent.y - 6), extent - Vector2.ONE * 6]:
		canvas.draw_rect(Rect2(corner, Vector2(2, 2)), Color(GOLD, 0.65))
	var rank: int = clampi(int(item.get("rank", 1)), 1, 3)
	var rank_tint: Color = CYAN if rank == 2 else PURPLE if rank == 3 else GOLD
	for mark: int in rank:
		var mark_y: float = float(22 + mark * 5)
		canvas.draw_rect(Rect2(Vector2(3, mark_y), Vector2(3, 2)), rank_tint)
	var rune: Dictionary = item.get("rune", {})
	if not rune.is_empty():
		canvas.draw_rect(Rect2(Vector2(extent.x - 20, 2), Vector2(18, 18)), Color("f8f1ff"))
		canvas.draw_rect(Rect2(Vector2(extent.x - 20, 2), Vector2(18, 18)), Color("9671ad"), false, 1.0)
		for mark: int in clampi(int(rune.get("rank", 1)), 1, 3):
			var mark_x: float = extent.x - 17 + float(mark * 4)
			canvas.draw_rect(Rect2(Vector2(mark_x, 21), Vector2(2, 1)), PURPLE)
	var button := canvas.get_parent() as Button
	if button != null and button.has_focus():
		_draw_item_focus(canvas)

func _draw_item_focus(canvas: Control) -> void:
	var extent: Vector2 = canvas.size
	var focus_tint := Color("edbc65")
	for corner: Vector2 in [Vector2.ZERO, Vector2(extent.x, 0), Vector2(0, extent.y), extent]:
		var left: bool = corner.x == 0.0
		var top: bool = corner.y == 0.0
		var horizontal := Rect2(corner + Vector2(0 if left else -7, 0 if top else -2), Vector2(7, 2))
		var vertical := Rect2(corner + Vector2(0 if left else -2, 0 if top else -7), Vector2(2, 7))
		canvas.draw_rect(horizontal.grow(1.0).intersection(Rect2(Vector2.ZERO, extent)), BONE)
		canvas.draw_rect(vertical.grow(1.0).intersection(Rect2(Vector2.ZERO, extent)), BONE)
		canvas.draw_rect(horizontal, focus_tint)
		canvas.draw_rect(vertical, focus_tint)

static func _material_color(kind: String) -> Color:
	match kind:
		"weapon": return Color("dceef0")
		"relic": return Color("f6e6bd")
		"skill": return Color("d7eee7")
	return Color("e9e0f2")

static func _definition(item: Dictionary) -> ContentDef:
	match str(item["kind"]):
		"rune": return GameCatalog.rune(str(item["id"]))
		"relic": return GameCatalog.relic(str(item["id"]))
		"skill": return GameCatalog.skill(str(item["id"]))
	return GameCatalog.weapon(str(item["id"]))

static func _item_size(item: Dictionary, rotated: bool) -> Vector2i:
	var dimensions: Vector2i = _definition(item).inventory_size
	return Vector2i(dimensions.y, dimensions.x) if rotated else dimensions

static func _native_grab_cell(button_offset: Vector2) -> Vector2i:
	return Vector2i(((button_offset + Vector2.ONE * 2.0) / CELL).floor())
