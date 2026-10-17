class_name ChairModel
extends Node3D
## 3D presentation rig; rigid-body movement remains exclusively in Chair.

var body: Node3D
var face_colour: Color
var office_chair: OfficeChairModel
var extinguisher: ExtinguisherModel
var _compression := 0.0
var _compression_velocity := 0.0
var _tilt := Vector2.ZERO
var _tilt_velocity := Vector2.ZERO


func build(tint: Color, skin: CharacterSkin = null) -> void:
	if skin == null or not skin.is_valid():
		skin = SkinCatalog.default_definition()
	face_colour = tint.lightened(skin.face_lightening)
	office_chair = OfficeChairModel.new()
	add_child(office_chair)
	office_chair.build(tint)
	body = Node3D.new()
	body.name = "Character"
	body.position.y = 0.04
	office_chair.seat_rig.add_child(body)
	var torso := MeshInstance3D.new()
	torso.name = "ContinuousBody"
	torso.mesh = skin.body_mesh
	var skin_shader := ShaderMaterial.new()
	skin_shader.shader = skin.body_shader
	skin_shader.set_shader_parameter("skin_colour", tint)
	skin_shader.set_shader_parameter("face_colour", face_colour)
	if skin.chest_logo != null:
		skin_shader.set_shader_parameter("chest_logo", skin.chest_logo)
	torso.material_override = skin_shader
	body.add_child(torso)
	extinguisher = ExtinguisherModel.new()
	extinguisher.position = Vector3(0, 0.13, 0.38)
	office_chair.seat_rig.add_child(extinguisher)
	extinguisher.build()


func hit(local_impulse: Vector2) -> void:
	var strength := minf(local_impulse.length(), 500.0)
	_compression_velocity += strength * 0.0022
	var direction := local_impulse.normalized()
	_tilt_velocity += Vector2(direction.y, -direction.x) * strength * 0.006
	_tilt_velocity = _tilt_velocity.limit_length(3.0)


func animate(
	delta: float, time: float, speed: float, impact: float, lean: Vector2, local_motion: Vector2
) -> void:
	var step := minf(delta, 0.033)
	_compression_velocity += (-_compression * 150.0 - _compression_velocity * 15.0) * step
	_compression = clampf(_compression + _compression_velocity * step, -0.012, 0.09)
	_tilt_velocity += (-_tilt * 75.0 - _tilt_velocity * 8.5) * step
	_tilt = (_tilt + _tilt_velocity * step).limit_length(0.19)
	office_chair.animate(
		delta, speed, local_motion, _compression, _tilt + Vector2(lean.x, -lean.y) * 0.003
	)
	var breath := sin(time * 3.0) * 0.012
	body.scale = Vector3(1.0 + impact * 0.10 + breath, 1.0 - impact * 0.14 - breath, 1.0)
	body.rotation.x = lean.x * 0.012 - _tilt.x * 0.7
	body.rotation.z = -lean.y * 0.012 - _tilt.y * 0.7
	body.position.y = 0.04 + sin(time * 8) * speed * 0.008
