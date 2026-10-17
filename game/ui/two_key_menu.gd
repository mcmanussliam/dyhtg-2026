class_name TwoKeyMenu
extends Control
## Explicit two-key selection. Parents own the meaning of each entry.

signal activated(index: int)

var chosen := 0
var option_font_size := 26
var option_row_height := 48
var scrollable := false
var _items := PackedStringArray()
var _rows: Array[Label] = []
var _values := PackedStringArray()
var _value_rows: Array[Label] = []
var _markers: Array[Label] = []
var _disabled_items: Dictionary = {}
var _list: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func set_items(labels: PackedStringArray, values: PackedStringArray = PackedStringArray()) -> void:
	_items = labels
	_values = values
	chosen = clampi(chosen, 0, maxi(0, labels.size() - 1))
	if is_inside_tree():
		_build()


func set_item_enabled(index: int, enabled: bool) -> void:
	if enabled:
		_disabled_items.erase(index)
	else:
		_disabled_items[index] = true
	_refresh()


func _build() -> void:
	if is_instance_valid(_scroll):
		remove_child(_scroll)
		_scroll.queue_free()
	elif is_instance_valid(_list):
		remove_child(_list)
		_list.queue_free()
	_scroll = null
	_rows.clear()
	_value_rows.clear()
	_markers.clear()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10 if not _values.is_empty() else 12)
	if scrollable:
		_scroll = ScrollContainer.new()
		_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_scroll.focus_mode = Control.FOCUS_NONE
		add_child(_scroll)
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(_list)
	else:
		_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_list)
	var column_width := 128.0
	for item in _items:
		column_width = maxf(
			column_width,
			(
				(
					ThemeDB
					. fallback_font
					. get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, option_font_size)
					. x
				)
				+ 28
			)
		)
	for index in _items.size():
		if _values.is_empty():
			var label := _label(28, 64)
			_list.add_child(label)
			_rows.append(label)
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			_list.add_child(row)
			var marker := _label(option_font_size, option_row_height)
			marker.custom_minimum_size.x = 28
			row.add_child(marker)
			_markers.append(marker)
			var label := _label(option_font_size, option_row_height)
			label.custom_minimum_size.x = column_width
			row.add_child(label)
			_rows.append(label)
			var value := _label(option_font_size, option_row_height)
			row.add_child(value)
			_value_rows.append(value)
	_refresh()


func _label(font_size: int, height: float) -> Label:
	var label := Label.new()
	label.custom_minimum_size.y = height
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh() -> void:
	for index in _rows.size():
		_rows[index].add_theme_color_override(
			"font_color",
			Color(0.45, 0.45, 0.45) if _disabled_items.has(index) else Color(1, 1, 1, 0.92)
		)
		if _values.is_empty():
			_rows[index].text = (">  " if index == chosen else "    ") + _items[index]
		else:
			_rows[index].text = _items[index]
			_markers[index].text = ">" if index == chosen else ""
			_value_rows[index].text = _values[index] if index < _values.size() else ""
			_value_rows[index].add_theme_color_override(
				"font_color", Color(1, 1, 1, 0.46 if index == chosen else 0.36)
			)
	if is_instance_valid(_scroll):
		_reveal_chosen.call_deferred()


func _reveal_chosen() -> void:
	# Container sorting and page anchors must settle before calculating visibility.
	if is_instance_valid(_scroll) and chosen < _rows.size():
		_scroll.ensure_control_visible(_rows[chosen])


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _items.is_empty() or event.is_echo():
		return
	if event.is_action_pressed("menu_next"):
		get_viewport().set_input_as_handled()
		chosen = (chosen + 1) % _items.size()
		_refresh()
	elif event.is_action_pressed("menu_activate"):
		get_viewport().set_input_as_handled()
		if not _disabled_items.has(chosen):
			activated.emit(chosen)
