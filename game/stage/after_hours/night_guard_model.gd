class_name NightGuardModel
extends Node3D
## A seated guard on the shared chair rig: navy reflective vest, peaked cap and a
## flashlight whose real spotlight shadows match the gameplay sight test.

const UNIFORM := Color("44507a")
const PATROL_BEAM := Color(1.0, 0.92, 0.74)
const ALERT_BEAM := Color(1.0, 0.42, 0.32)
const BEAM_HEIGHT := 0.83  # Seat rig hand height above the floor, in model metres.

var _chair: ChairModel
var _pivot: Node3D
var _light: SpotLight3D
var _lens: StandardMaterial3D
var _marker: Node3D
var _alert := false


func build(sight_range: float, half_angle: float) -> void:
	name = "NightGuard"
	_chair = ChairModel.new()
	add_child(_chair)
	_chair.build(UNIFORM, load("res://game/character/skins/high_vis/high_vis.tres"), &"none")
	_chair.extinguisher.hide()
	_cap(_chair.body)
	_pivot = Node3D.new()
	_pivot.name = "Flashlight"
	_chair.office_chair.seat_rig.add_child(_pivot)
	var casing := ModelGeometry.material(Color("2d3238"), 0.3, 0.5)
	ModelGeometry.cylinder(_pivot, Vector3(0, 0.34, 0.34), Vector3(0, 0.35, 0.56), 0.04, casing)
	ModelGeometry.cylinder(
		_pivot, Vector3(0, 0.35, 0.55), Vector3(0, 0.355, 0.63), 0.052, casing, 0.066
	)
	_lens = ModelGeometry.material(PATROL_BEAM)
	_lens.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ModelGeometry.ellipsoid(_pivot, Vector3(0, 0.355, 0.632), Vector3(0.06, 0.06, 0.012), _lens)
	_light = SpotLight3D.new()
	_light.name = "Beam"
	_light.position = Vector3(0, 0.355, 0.64)
	# Spotlights shine down -Z; aim forward and dip so the pool spans the sight range.
	_light.rotation = Vector3(-atan2(BEAM_HEIGHT, sight_range * 0.62), PI, 0)
	_light.spot_range = sight_range * 1.2
	_light.spot_angle = rad_to_deg(half_angle) * 1.06
	_light.spot_angle_attenuation = 0.35
	_light.spot_attenuation = 0.2
	_light.light_energy = 16.0
	_light.light_color = PATROL_BEAM
	_light.shadow_enabled = RenderStyle.shadow_quality != 0
	_light.shadow_bias = 0.06
	_pivot.add_child(_light)
	_marker = Node3D.new()
	_marker.name = "AlertMarker"
	_chair.body.add_child(_marker)
	var red := ModelGeometry.material(Color("ff4a3d"))
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ModelGeometry.capsule(_marker, Vector3(0, 1.62, 0), Vector3(0, 1.80, 0), 0.04, red)
	ModelGeometry.ellipsoid(_marker, Vector3(0, 1.50, 0), Vector3.ONE * 0.045, red)
	_marker.hide()


## Flashlight yaw relative to the guard's body, in 2D radians.
func aim(relative_angle: float) -> void:
	_pivot.rotation.y = -relative_angle


func set_alert(enabled: bool) -> void:
	if enabled == _alert:
		return
	_alert = enabled
	_marker.visible = enabled
	_light.light_color = ALERT_BEAM if enabled else PATROL_BEAM
	_lens.albedo_color = _light.light_color


func animate(delta: float, time: float, speed: float) -> void:
	_chair.animate(delta, time, speed / 650.0, 0, Vector2.ZERO, Vector2(0, speed))
	if _alert:
		_marker.position.y = sin(time * 9.0) * 0.03


func _cap(body: Node3D) -> void:
	# Same snug head-space fit as CharacterHats, built privately for the guard.
	var root := Node3D.new()
	root.name = "GuardCap"
	root.position.y = -0.045
	root.scale = Vector3(0.94, 1, 0.94)
	body.add_child(root)
	var navy := ModelGeometry.material(Color("262d45"), 0, 0.85)
	var visor := ModelGeometry.material(Color("15181f"), 0.1, 0.35)
	var badge := ModelGeometry.material(Color("e7bd4b"), 0.4, 0.4)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.20, 0), Vector3(0.262, 0.11, 0.25), navy)
	ModelGeometry.cylinder(
		root, Vector3(0, 1.20, -0.01), Vector3(0, 1.33, -0.01), 0.255, navy, 0.285
	)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.33, -0.01), Vector3(0.285, 0.03, 0.285), navy)
	ModelGeometry.cushion(root, Vector3(0, 1.205, 0.24), Vector3(0.36, 0.025, 0.17), 0.011, visor)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.275, 0.262), Vector3(0.034, 0.038, 0.012), badge)
	StaticModelBatcher.merge_direct(root, [&"guard_cap"])
