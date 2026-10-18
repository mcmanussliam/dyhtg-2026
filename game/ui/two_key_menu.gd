class_name TwoKeyMenu
extends Control
## Explicit two-key selection. Parents own the meaning of each entry.
## Every menu shares one row size, gap and marker column, with optional values.

signal activated(index: int)

const FONT_SIZE := 28
const ROW_HEIGHT := 64
const ROW_GAP := 12
const MARKER_WIDTH := 28

var chosen := 0
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
	_list.add_theme_constant_override("separation", ROW_GAP)
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
					. get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
					. x
				)
				+ 28
			)
		)
	for index in _items.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		_list.add_child(row)
		var marker := _label()
		marker.custom_minimum_size.x = MARKER_WIDTH
		row.add_child(marker)
		_markers.append(marker)
		var label := _label()
		row.add_child(label)
		_rows.append(label)
		if not _values.is_empty():
			label.custom_minimum_size.x = column_width
			var value := _label()
			row.add_child(value)
			_value_rows.append(value)
	_refresh()


## Height of a menu showing `rows` entries.
static func height_for(rows: int) -> int:
	return rows * ROW_HEIGHT + maxi(rows - 1, 0) * ROW_GAP


func _label() -> Label:
	var label := Label.new()
	label.custom_minimum_size.y = ROW_HEIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh() -> void:
	for index in _rows.size():
		var colour := (
			Color(0.45, 0.45, 0.45) if _disabled_items.has(index) else Color(1, 1, 1, 0.92)
		)
		_rows[index].add_theme_color_override("font_color", colour)
		_markers[index].add_theme_color_override("font_color", colour)
		_rows[index].text = _items[index]
		_markers[index].text = ">" if index == chosen else ""
		if not _values.is_empty():
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
