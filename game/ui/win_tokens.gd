class_name WinTokens
extends TextureRect
## One transparent render surface per score row, regardless of token count.

var token_count := 0
var animate_newest := false
var _tokens: Array[Node3D] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	RenderStyle.configure_composite(self)
	custom_minimum_size = Vector2(350, 64)
	if token_count <= 0:
		set_process(false)
		return
	var viewport := SubViewport.new()
	RenderStyle.configure_viewport(viewport, Vector2i(1400, 256), true)
	add_child(viewport)
	texture = viewport.get_texture()
	RenderStyle.setup_world(viewport, true, Color.BLACK, false)
	RenderStyle.orthographic_camera(viewport, 7.5, Vector3(3.25, 0, 10), Vector3(3.25, 0, 0), true)
	var world := Node3D.new()
	viewport.add_child(world)
	var gold_surface := ModelGeometry.material(Color("ffc85e"), 0.55, 0.25)
	var mesh := _star_mesh()
	for index in token_count:
		var token := ModelGeometry.instance(world, mesh, Vector3(index * 1.38, 0, 0), gold_surface)
		token.rotation.z = -0.08
		_tokens.append(token)


func _process(delta: float) -> void:
	_time += delta
	for index in _tokens.size():
		_tokens[index].rotation.y = sin(_time * 0.9 + index * 0.4) * 0.3
		if animate_newest and index == _tokens.size() - 1:
			var amount := clampf(_time * 2.2, 0, 1)
			_tokens[index].scale = Vector3.ONE * lerpf(0.05, 1.0, ease(amount, 0.4))


func _star_mesh() -> ArrayMesh:
	var ring: Array[Vector2] = []
	for index in 10:
		var angle := -PI * 0.5 + index * TAU / 10
		ring.append(Vector2(cos(angle), sin(angle)) * (0.59 if index % 2 == 0 else 0.28))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 10:
		var first := ring[index]
		var second := ring[(index + 1) % 10]
		# Raised centres and inset rear form a bevelled solid star.
		_triangle(
			surface,
			Vector3(0, 0, 0.22),
			Vector3(first.x, -first.y, 0.04),
			Vector3(second.x, -second.y, 0.04)
		)
		_triangle(
			surface,
			Vector3(0, 0, -0.16),
			Vector3(second.x, -second.y, -0.04),
			Vector3(first.x, -first.y, -0.04)
		)
		_triangle(
			surface,
			Vector3(first.x, -first.y, 0.04),
			Vector3(first.x, -first.y, -0.04),
			Vector3(second.x, -second.y, -0.04)
		)
		_triangle(
			surface,
			Vector3(first.x, -first.y, 0.04),
			Vector3(second.x, -second.y, -0.04),
			Vector3(second.x, -second.y, 0.04)
		)
	surface.generate_normals()
	return surface.commit()


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
