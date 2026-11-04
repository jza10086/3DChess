extends RefCounted
## Original Chinese-chess table and wooden discs. The host supplies the protocol font.

const BOARD_Y: float = 0.24
const RIVER_EXTRA: float = 0.30
const HALF_LENGTH: float = 4.5 + RIVER_EXTRA / 2.0
const RED_GLYPHS: Dictionary = {1: "兵", 2: "马", 3: "相", 4: "车", 6: "帅", 7: "仕", 8: "炮"}
const BLACK_GLYPHS: Dictionary = {1: "卒", 2: "马", 3: "象", 4: "车", 6: "将", 7: "士", 8: "炮"}

static func square_position(square: int) -> Vector3:
	var rank: int = square / 9
	return Vector3(float(square % 9) - 4.0, BOARD_Y, HALF_LENGTH - float(rank) - (RIVER_EXTRA if rank >= 5 else 0.0))

## Select the nearest intersection, including either river bank but not its empty middle.
static func square_at(hit: Vector3) -> int:
	var file: int = int(roundf(hit.x + 4.0))
	if file < 0 or file > 8 or absf(hit.x - float(file) + 4.0) > 0.48:
		return -1
	var from_red: float = HALF_LENGTH - hit.z
	var rank: int = int(roundf(from_red if hit.z >= 0.0 else from_red - RIVER_EXTRA))
	if rank < 0 or rank > 9:
		return -1
	var square: int = rank * 9 + file
	return square if absf(hit.z - square_position(square).z) <= 0.48 else -1

static func build_board(root: Node3D, font: Font) -> void:
	var edge: Material = _material(Color("342317"), 0.42)
	var brass: Material = _material(Color("b39a60"), 0.35, 0.34)
	_box(root, Vector3(9.55, 0.22, 10.85), Vector3(0, -0.11, 0), edge)
	_box(root, Vector3(9.47, 0.18, 10.77), Vector3(0, 0.065, 0), _wood_material(false))
	_box(root, Vector3(9.12, 0.045, 10.42), Vector3(0, 0.166, 0), brass)
	_box(root, Vector3(9.02, 0.06, 10.32), Vector3(0, 0.209, 0), _wood_material(true))
	var ink: Material = _material(Color("5b4329"), 0.8)
	var line_y: float = BOARD_Y + 0.004
	for rank: int in range(10):
		var z: float = square_position(rank * 9).z
		_line(root, Vector3(-4, line_y, z), Vector3(4, line_y, z), 0.022, ink)
	for file: int in range(9):
		var x: float = float(file) - 4.0
		if file == 0 or file == 8:
			_line(root, Vector3(x, line_y, HALF_LENGTH), Vector3(x, line_y, -HALF_LENGTH), 0.026, ink)
		else:
			_line(root, Vector3(x, line_y, HALF_LENGTH), Vector3(x, line_y, 0.65), 0.021, ink)
			_line(root, Vector3(x, line_y, -0.65), Vector3(x, line_y, -HALF_LENGTH), 0.021, ink)
	# Each palace is a three-by-three intersection box, with crossed diagonals.
	for rank: int in [0, 7]:
		_line(root, square_position(rank * 9 + 3) + Vector3(0, 0.004, 0), square_position((rank + 2) * 9 + 5) + Vector3(0, 0.004, 0), 0.021, ink)
		_line(root, square_position(rank * 9 + 5) + Vector3(0, 0.004, 0), square_position((rank + 2) * 9 + 3) + Vector3(0, 0.004, 0), 0.021, ink)
	for rank: int in [2, 7]:
		for file: int in [1, 7]:
			_start_mark(root, rank * 9 + file, ink)
	for rank: int in [3, 6]:
		for file: int in [0, 2, 4, 6, 8]:
			_start_mark(root, rank * 9 + file, ink)
	for edge_z: float in [-HALF_LENGTH - 0.11, HALF_LENGTH + 0.11]:
		_line(root, Vector3(-4.11, line_y, edge_z), Vector3(4.11, line_y, edge_z), 0.035, ink)
	for edge_x: float in [-4.11, 4.11]:
		_line(root, Vector3(edge_x, line_y, -HALF_LENGTH - 0.11), Vector3(edge_x, line_y, HALF_LENGTH + 0.11), 0.035, ink)
	_text(root, "楚 河", Vector3(-2.05, line_y + 0.006, 0), font, 70, 0.008, Color("78522e"), "ChuRiver")
	_text(root, "汉 界", Vector3(2.05, line_y + 0.006, 0), font, 70, 0.008, Color("78522e"), "HanBorder")

static func create_piece(piece: int, font: Font, orientation: int) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Piece"
	var ink_color: Color = Color("a12c24") if piece > 0 else Color("263a34")
	var wood: Material = _wood_material(true)
	var rim: Material = _material(Color("936135"), 0.58)
	_cylinder(root, 0.395, 0.365, 0.055, Vector3(0, 0.032, 0), rim)
	_cylinder(root, 0.395, 0.395, 0.14, Vector3(0, 0.125, 0), wood)
	_cylinder(root, 0.375, 0.395, 0.045, Vector3(0, 0.217, 0), wood)
	var ring: MeshInstance3D = ring_marker(ink_color, 0.331, 0.343)
	ring.position.y = 0.241
	root.add_child(ring)
	var glyphs: Dictionary = RED_GLYPHS if piece > 0 else BLACK_GLYPHS
	var glyph: Label3D = _text(root, str(glyphs.get(absi(piece), "")), Vector3(0, 0.245, 0), font, 96, 0.006, ink_color, "Glyph")
	glyph.rotation.y = PI if orientation < 0 else 0.0
	return root

static func disc_marker(color: Color, radius: float) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.006
	mesh.radial_segments = 56
	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = _unshaded(color)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return marker

static func ring_marker(color: Color, inner: float = 0.428, outer: float = 0.457) -> MeshInstance3D:
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 48
	mesh.ring_segments = 8
	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.mesh = mesh
	marker.scale.y = 0.35
	marker.material_override = _unshaded(color)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return marker

static func _start_mark(root: Node3D, square: int, ink: Material) -> void:
	var at: Vector3 = square_position(square) + Vector3(0, 0.004, 0)
	for dx: int in [-1, 1]:
		if (square % 9 == 0 and dx < 0) or (square % 9 == 8 and dx > 0):
			continue
		for dz: int in [-1, 1]:
			var corner: Vector3 = at + Vector3(float(dx) * 0.08, 0, float(dz) * 0.08)
			_line(root, corner, corner + Vector3(float(dx) * 0.12, 0, 0), 0.018, ink)
			_line(root, corner, corner + Vector3(0, 0, float(dz) * 0.12), 0.018, ink)

static func _text(root: Node3D, text_value: String, at: Vector3, font: Font, font_size: int, pixel_size: float, color: Color, node_name: String) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = node_name
	label.font = font
	label.text = text_value
	label.position = at
	label.rotation.x = -PI / 2.0
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(label)
	return label

static func _line(root: Node3D, start: Vector3, end: Vector3, width: float, material: Material) -> void:
	var delta: Vector3 = end - start
	var instance: MeshInstance3D = _box(root, Vector3(width, 0.006, delta.length()), (start + end) * 0.5, material)
	instance.rotation.y = atan2(delta.x, delta.z)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _box(root: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	root.add_child(instance)
	return instance

static func _cylinder(root: Node3D, top: float, bottom: float, height: float, at: Vector3, material: Material) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 56
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	root.add_child(instance)

static func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

static func _unshaded(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = _material(color, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

static func _wood_material(light: bool) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
	uniform vec3 wood_dark : source_color;
	uniform vec3 wood_light : source_color;
	varying vec3 local_vertex;
	void vertex() { local_vertex = VERTEX; }
	void fragment() {
		float grain = sin(local_vertex.x * 68.0 + sin(local_vertex.z * 3.5) * 1.6);
		float fine = sin(local_vertex.x * 197.0 + local_vertex.z * 4.0);
		ALBEDO = mix(wood_dark, wood_light, 0.57 + grain * 0.055 + fine * 0.025);
		ROUGHNESS = 0.66;
	}"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wood_dark", Color("bb8f55") if light else Color("392416"))
	material.set_shader_parameter("wood_light", Color("dfbb7f") if light else Color("67472b"))
	return material
