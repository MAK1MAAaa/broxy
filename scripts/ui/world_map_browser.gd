class_name WorldMapBrowser
extends VBoxContainer

signal selected(id: String)
signal closed

const INK := Color("253d54")
const GOLD := Color("8a5b20")

var selected_id: String = ""
var _group: OptionButton
var _search: LineEdit
var _grid: GridContainer
var _previous: Button
var _next: Button
var _counter: Label
var _back: Button
var _groups: Array[Dictionary] = []
var _matches: Array[String] = []
var _page: int = 0
var _epoch: int = 0


func _ready() -> void:
	name = "WorldMapBrowser"
	add_theme_constant_override("separation", 12)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 12)
	add_child(filters)
	_group = OptionButton.new()
	_group.name = "MapChapter"
	_group.custom_minimum_size = Vector2(224, 40)
	_group.add_theme_font_size_override("font_size", 18)
	_group.add_item("全部地图")
	_groups = WorldMapCatalog.groups()
	var selected_group: String = str(WorldMapCatalog.entry(selected_id).get("group", ""))
	for row: Dictionary in _groups:
		_group.add_item(str(row["name"]))
		if str(row["id"]) == selected_group:
			_group.select(_group.item_count - 1)
	if selected_group.is_empty() and not _groups.is_empty():
		_group.select(1)
	filters.add_child(_group)
	_group.item_selected.connect(_on_group_changed)
	_search = LineEdit.new()
	_search.name = "MapSearch"
	_search.placeholder_text = "地图名称 / 编号"
	_search.custom_minimum_size.y = 40
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", 18)
	var search_style := StyleBoxFlat.new()
	search_style.bg_color = Color("f0ead8")
	search_style.border_color = Color("c9ba9a")
	search_style.set_border_width_all(1)
	search_style.content_margin_left = 12
	search_style.content_margin_right = 8
	_search.add_theme_stylebox_override("normal", search_style)
	var search_focus := search_style.duplicate() as StyleBoxFlat
	search_focus.border_color = INK
	search_focus.set_border_width_all(2)
	_search.add_theme_stylebox_override("focus", search_focus)
	_search.add_theme_color_override("font_color", INK)
	_search.add_theme_color_override("font_placeholder_color", Color("526575"))
	_search.add_theme_color_override("caret_color", INK)
	_search.text_changed.connect(_on_search_changed)
	filters.add_child(_search)
	_grid = GridContainer.new()
	_grid.name = "MapPage"
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	add_child(_grid)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	add_child(footer)
	_previous = _button("上一页", _change_page.bind(-1))
	_previous.name = "MapPrevious"
	footer.add_child(_previous)
	_counter = Label.new()
	_counter.name = "MapPageNumber"
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_counter.add_theme_font_size_override("font_size", 20)
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_counter)
	_next = _button("下一页", _change_page.bind(1))
	_next.name = "MapNext"
	footer.add_child(_next)
	_back = _button("返回", _close)
	_back.name = "MapBack"
	footer.add_child(_back)
	_filter_results()
	var selected_index: int = _matches.find(selected_id)
	_page = maxi(0, selected_index) / WorldMapCatalog.PAGE_SIZE
	_render_page(true)


func _on_group_changed(_index: int) -> void:
	_page = 0
	_filter_results()
	_render_page(false)


func _on_search_changed(_value: String) -> void:
	_page = 0
	_filter_results()
	_render_page(false)


func _filter_results() -> void:
	_matches.clear()
	var group_id: String = str(_groups[_group.selected - 1]["id"]) if _group.selected > 0 else ""
	var query: String = _search.text.strip_edges().to_lower()
	for id: String in WorldMapCatalog.ids():
		var item: Dictionary = WorldMapCatalog.entry(id)
		if not group_id.is_empty() and str(item["group"]) != group_id:
			continue
		var searchable: String = "%s %s %s" % [item["name"], item["canonical_layout_id"], item["field_id"]]
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		_matches.append(id)


func _change_page(delta: int) -> void:
	_page = clampi(_page + delta, 0, maxi(0, ceili(float(_matches.size()) / WorldMapCatalog.PAGE_SIZE) - 1))
	_render_page(true)


func _render_page(refocus: bool) -> void:
	_epoch += 1
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var cards: Array[Button] = []
	var first: int = _page * WorldMapCatalog.PAGE_SIZE
	for index: int in range(first, mini(first + WorldMapCatalog.PAGE_SIZE, _matches.size())):
		var id: String = _matches[index]
		var item: Dictionary = WorldMapCatalog.entry(id)
		var card := _button("", _choose.bind(id, _epoch))
		card.name = "WorldMap_" + id
		card.custom_minimum_size = Vector2(248, 148)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.clip_contents = true
		card.toggle_mode = true
		card.button_pressed = id == selected_id
		card.tooltip_text = str(item["name"])
		ButtonSkin.apply(card, "choice")
		_grid.add_child(card)
		cards.append(card)
		var inset := MarginContainer.new()
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["left", "right", "top", "bottom"]:
			inset.add_theme_constant_override("margin_" + side, 8)
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(inset)
		var body := VBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 6)
		inset.add_child(body)
		var image := TextureRect.new()
		image.texture = WorldMapCatalog.preview_texture(id)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(image)
		var label := Label.new()
		label.text = str(item["name"])
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", GOLD if id == selected_id else INK)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(label)
	if cards.is_empty():
		var empty := Label.new()
		empty.name = "MapEmpty"
		empty.text = "无匹配地图"
		empty.custom_minimum_size = Vector2(248, 308)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 22)
		_grid.add_child(empty)
	else:
		_grid.custom_minimum_size.y = 308
	var pages: int = maxi(1, ceili(float(_matches.size()) / WorldMapCatalog.PAGE_SIZE))
	_counter.text = "%d / %d" % [_page + 1, pages]
	_previous.disabled = _page == 0
	_next.disabled = _page + 1 >= pages
	_wire_focus(cards)
	if refocus:
		var focus: Control = _back
		for card: Button in cards:
			if focus == _back or card.button_pressed:
				focus = card
		_focus_current.call_deferred(focus, _epoch)
	elif get_viewport().gui_get_focus_owner() == null:
		_focus_current.call_deferred(_search, _epoch)


func _focus_current(control: Control, epoch: int) -> void:
	if epoch == _epoch and is_inside_tree() and is_instance_valid(control) and control.is_inside_tree() and is_ancestor_of(control):
		control.grab_focus()


func _close() -> void:
	if is_inside_tree():
		closed.emit()


func _wire_focus(cards: Array[Button]) -> void:
	var controls: Array[Control] = [_group, _search]
	controls.append_array(cards)
	if not _previous.disabled:
		controls.append(_previous)
	if not _next.disabled:
		controls.append(_next)
	controls.append(_back)
	for index: int in controls.size():
		var control: Control = controls[index]
		control.focus_previous = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
	for index: int in cards.size():
		var card: Button = cards[index]
		card.focus_neighbor_left = card.get_path_to(cards[index - 1] if index % 3 > 0 else card)
		card.focus_neighbor_right = card.get_path_to(cards[index + 1] if index % 3 < 2 and index + 1 < cards.size() else card)
		card.focus_neighbor_top = card.get_path_to(cards[index - 3] if index >= 3 else _group if index == 0 else _search)
		card.focus_neighbor_bottom = card.get_path_to(cards[index + 3] if index + 3 < cards.size() else _back)
	_group.focus_neighbor_bottom = _group.get_path_to(cards[0] if not cards.is_empty() else _back)
	_search.focus_neighbor_bottom = _search.get_path_to(cards[mini(1, cards.size() - 1)] if not cards.is_empty() else _back)
	_back.focus_neighbor_top = _back.get_path_to(cards.back() if not cards.is_empty() else _search)
	for control: Control in [_previous, _next]:
		control.focus_neighbor_top = control.get_path_to(cards[0] if not cards.is_empty() else _search)


func _choose(id: String, epoch: int) -> void:
	if epoch == _epoch and is_inside_tree() and WorldMapCatalog.contains(id):
		selected.emit(id)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(112, 42)
	button.add_theme_font_size_override("font_size", 18)
	ButtonSkin.apply(button)
	button.pressed.connect(action)
	return button
