class_name CharacterSkin
extends Resource
## Authored body artwork only. Skins never change the chair's collision or movement.
## SkinCatalog registers stable IDs; shared meshes/shaders remain immutable per model.

# Preserve the numeric IDs authored in existing resources.
enum Garment { NONE, TSHIRT, HOODIE, TANK_TOP = 4, HIGH_VIS = 6 }

@export var garment: Garment = Garment.NONE
@export var garment_mesh: Mesh
@export var garment_shader: Shader
@export var pocket_mesh: Mesh

@export var id: StringName = &""
@export var display_name := ""
@export var body_mesh: Mesh
@export var body_shader: Shader
@export var chest_logo: Texture2D
@export_range(0.0, 1.0) var face_lightening := 0.42


func is_valid() -> bool:
	return (
		id != &""
		and not display_name.strip_edges().is_empty()
		and body_mesh != null
		and body_shader != null
		and (garment == Garment.NONE or (garment_mesh != null and garment_shader != null))
	)
