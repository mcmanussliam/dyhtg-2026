class_name TwoKeyMenu
extends Control
## Explicit two-key selection. Parents own the meaning of each entry.

signal activated(index: int)

var chosen := 0
var _items := PackedStringArray()
var _rows: Array[Label] = []
var _list: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func set_items(labels: PackedStringArray) -> void:
	_items = labels
	chosen = clampi(chosen, 0, maxi(0, labels.size() - 1))
	if is_inside_tree():
		_build()


func _build() -> void:
	if is_instance_valid(_list):
		remove_child(_list)
		_list.queue_free()
	_rows.clear()
	_list = VBoxContainer.new()
	_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_list.add_theme_constant_override("separation", 12)
	add_child(_list)
	for index in _items.size():
		var label := Label.new()
		label.custom_minimum_size.y = 64
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(label)
		_rows.append(label)
	_refresh()


func _refresh() -> void:
	for index in _rows.size():
		_rows[index].text = (">  " if index == chosen else "    ") + _items[index]


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _items.is_empty() or event.is_echo():
		return
	if event.is_action_pressed("menu_next"):
		get_viewport().set_input_as_handled()
		chosen = (chosen + 1) % _items.size()
		_refresh()
	elif event.is_action_pressed("menu_activate"):
		get_viewport().set_input_as_handled()
		activated.emit(chosen)
