class_name RoundSnapshot
extends RefCounted
## Host-to-client round state, packed for one unreliable message per physics frame.
## Chairs: CHAIR_FLOATS per seat, in seat order, plus one flag byte each. Props: only
## loose furniture that moved recently, as PROP_FLOATS each, keyed by Furniture child index.

## x, y, rotation, velocity x, velocity y, spin, jet strength, impact, spray reach.
## A falling chair reports its fall start velocity and spin instead of live motion.
const CHAIR_FLOATS := 9
## Furniture child index, x, y, rotation, velocity x, velocity y, spin.
const PROP_FLOATS := 7
const ACTIVE := 1
const FALLING := 2
const SPRAYING := 4
## A settled prop is re-sent this many frames, so one dropped packet cannot strand it.
const PROP_REST_FRAMES := 12
const PROP_MOVE_EPSILON := 0.05

var _props: Array[RigidBody2D] = []
var _prop_indices := PackedInt32Array()
var _by_index: Dictionary = {}
var _sent := PackedVector3Array()
var _quiet := PackedInt32Array()


## Index the stage's loose furniture once; both peers build the same scene.
func bind(stage: ArenaStage) -> void:
	var furniture := stage.get_node_or_null("Furniture")
	if furniture == null:
		return
	var index := 0
	for child in furniture.get_children():
		if child is OfficeProp and child.is_movable():
			var body := child as RigidBody2D
			_props.append(body)
			_prop_indices.append(index)
			_by_index[index] = body
			_sent.append(Vector3(body.global_position.x, body.global_position.y, body.rotation))
			_quiet.append(PROP_REST_FRAMES + 1)
		index += 1


## Host: pack every chair and the loose props that moved.
func capture_chairs(chairs: Array[Chair]) -> Array:
	var values := PackedFloat32Array()
	values.resize(chairs.size() * CHAIR_FLOATS)
	var flags := PackedByteArray()
	flags.resize(chairs.size())
	for index in chairs.size():
		var chair := chairs[index]
		var velocity := chair.fall_velocity if chair.falling else chair.linear_velocity
		var spin := chair.fall_spin if chair.falling else chair.angular_velocity
		var base := index * CHAIR_FLOATS
		values[base] = chair.global_position.x
		values[base + 1] = chair.global_position.y
		values[base + 2] = chair.global_rotation
		values[base + 3] = velocity.x
		values[base + 4] = velocity.y
		values[base + 5] = spin
		values[base + 6] = chair.jet_strength
		values[base + 7] = chair.impact
		values[base + 8] = chair.spray_reach
		flags[index] = (
			(ACTIVE if chair.active else 0)
			| (FALLING if chair.falling else 0)
			| (SPRAYING if chair.spraying else 0)
		)
	return [values, flags]


func capture_props() -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for slot in _props.size():
		var body := _props[slot]
		var pose := Vector3(body.global_position.x, body.global_position.y, body.rotation)
		var last := _sent[slot]
		if (
			not body.freeze
			and not body.sleeping
			and (
				absf(pose.x - last.x) > PROP_MOVE_EPSILON
				or absf(pose.y - last.y) > PROP_MOVE_EPSILON
				or absf(pose.z - last.z) > 0.001
			)
		):
			_sent[slot] = pose
			_quiet[slot] = 0
		elif _quiet[slot] <= PROP_REST_FRAMES:
			_quiet[slot] += 1
		if _quiet[slot] > PROP_REST_FRAMES:
			continue
		var velocity := Vector2.ZERO if body.freeze else body.linear_velocity
		values.append(_prop_indices[slot])
		values.append(pose.x)
		values.append(pose.y)
		values.append(pose.z)
		values.append(velocity.x)
		values.append(velocity.y)
		values.append(0.0 if body.freeze else body.angular_velocity)
	return values


## Client: place the host's moving props. Props this peer already dropped stay with 3D.
func apply_props(values: PackedFloat32Array) -> void:
	for base in range(0, values.size() - PROP_FLOATS + 1, PROP_FLOATS):
		var body: RigidBody2D = _by_index.get(int(values[base]))
		if body == null or body.freeze:
			continue
		body.global_position = Vector2(values[base + 1], values[base + 2])
		body.global_rotation = values[base + 3]
		body.linear_velocity = Vector2(values[base + 4], values[base + 5])
		body.angular_velocity = values[base + 6]
		body.sleeping = false
