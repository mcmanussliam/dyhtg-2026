class_name LocalInput
extends RefCounted
## Independent steering per device. Propulsion and spray do not require input.

const KEYBOARD_ONE: int = -1
const KEYBOARD_TWO: int = -2
const CPU: int = -3
const DEAD_ZONE: float = 0.20

var device: int = KEYBOARD_ONE


func sample() -> ChairCommand:
	var command := ChairCommand.new()
	if device >= 0:
		if Input.get_connected_joypads().has(device):
			var axis := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
			if absf(axis) > DEAD_ZONE:
				command.turn = signf(axis) * (absf(axis) - DEAD_ZONE) / (1.0 - DEAD_ZONE)
			var left := Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT)
			var right := Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT)
			if left or right:
				command.turn = float(right) - float(left)
	elif device == KEYBOARD_ONE:
		var left := Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
		var right := (
			Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
		)
		command.turn = float(right) - float(left)
	elif device == KEYBOARD_TWO:
		command.turn = float(Input.is_physical_key_pressed(KEY_L))
		command.turn -= float(Input.is_physical_key_pressed(KEY_J))
	return command
