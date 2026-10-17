class_name CharacterSkin
extends Resource
## Authored body artwork only. Skins never change the chair's collision or movement.

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
	)
