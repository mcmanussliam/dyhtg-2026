class_name GameSession
extends Node2D
## A physics sandbox. Stage geometry is separate from future round rules.

const CHAIR_SCENE: PackedScene = preload("res://game/chair/chair.tscn")
const COLOURS: Array[Color] = [Color("ece2d0"), Color("d0e2dc"), Color("ead5df"), Color("dfdbed")]

var chairs: Array[Chair] = []
var bindings: Array[LocalInput] = []
var pilots: Array[PracticePilot] = []
var _reset_pending: bool = false
var _spray := SpraySystem.new()

@onready var stage: PhysicsStage = $Stage
@onready var hud: GameHud = $Interface/Hud


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_device_connection)
	_add_binding(LocalInput.KEYBOARD_ONE)
	_add_binding(LocalInput.CPU)
	for device in Input.get_connected_joypads():
		_join_controller(device)
	_reset_session()


func _physics_process(delta: float) -> void:
	if _reset_pending or get_tree().paused:
		return
	for index in chairs.size():
		var chair := chairs[index]
		if bindings[index].device == LocalInput.CPU:
			chair.command = pilots[index].sample(chair, chairs, stage.play_bounds)
		else:
			chair.command = bindings[index].sample()
		chair.step(delta)
	for chair in chairs:
		_spray.apply(chair, chairs, delta)


func _process(_delta: float) -> void:
	var labels := PackedStringArray()
	for binding in bindings:
		labels.append(_binding_label(binding))
	hud.chairs = chairs
	hud.labels = labels
	hud.paused = get_tree().paused


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				request_restart()
			KEY_ESCAPE:
				get_tree().paused = not get_tree().paused
			KEY_F2:
				bindings[1].device = (
					LocalInput.KEYBOARD_TWO
					if bindings[1].device == LocalInput.CPU
					else LocalInput.CPU
				)
			KEY_J, KEY_L:
				if bindings[1].device == LocalInput.CPU:
					bindings[1].device = LocalInput.KEYBOARD_TWO
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A:
			_join_controller(event.device)
		elif event.button_index == JOY_BUTTON_START:
			request_restart()


func request_restart() -> void:
	if _reset_pending:
		return
	_reset_pending = true
	_reset_session.call_deferred()


func _reset_session() -> void:
	get_tree().paused = false
	for chair in chairs:
		$Chairs.remove_child(chair)
		chair.queue_free()
	chairs.clear()
	pilots.clear()
	_reset_pending = false
	for index in bindings.size():
		var chair := CHAIR_SCENE.instantiate() as Chair
		chair.configure(index, COLOURS[index], Vector2.LEFT if index % 2 == 0 else Vector2.RIGHT)
		chair.position = stage.spawn_position(index)
		$Chairs.add_child(chair)
		chairs.append(chair)
		pilots.append(PracticePilot.new())


func _add_binding(device: int) -> void:
	var binding := LocalInput.new()
	binding.device = device
	bindings.append(binding)


func _join_controller(device: int) -> void:
	for binding in bindings:
		if binding.device == device:
			return
	for binding in bindings:
		if binding.device < 0:
			binding.device = device
			return
	if bindings.size() < 4:
		_add_binding(device)
		if not chairs.is_empty():
			request_restart()


func _on_device_connection(device: int, connected: bool) -> void:
	if connected:
		return
	for index in bindings.size():
		if bindings[index].device == device:
			bindings[index].device = LocalInput.KEYBOARD_ONE if index == 0 else LocalInput.CPU


func _binding_label(binding: LocalInput) -> String:
	if binding.device >= 0:
		return "CONTROLLER"
	if binding.device == LocalInput.CPU:
		return "AI"
	return "LEFT / RIGHT" if binding.device == LocalInput.KEYBOARD_ONE else "J / L"
