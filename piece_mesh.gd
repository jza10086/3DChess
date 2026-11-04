extends RefCounted
## Original, lathed Staunton-inspired pieces. No imported meshes or global state.

static func create(piece: int) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Piece"
	var white: bool = piece > 0
	var body: StandardMaterial3D = _material(Color("dbd2b8") if white else Color("283234"), 0.34 if white else 0.37)
	var detail: StandardMaterial3D = _material(Color("bda875") if white else Color("74847c"), 0.32, 0.35)
	var dark: StandardMaterial3D = _material(Color("6d5b41") if white else Color("101619"), 0.42)
	var type: int = absi(piece)
	var width: float = 0.84 if type == 1 else 1.0
	root.scale = Vector3(width, width, width)
	_lathe(root, PackedVector2Array([Vector2(0.0, 0.015), Vector2(0.24, 0.015), Vector2(0.31, 0.045), Vector2(0.34, 0.09), Vector2(0.34, 0.13), Vector2(0.31, 0.17), Vector2(0.29, 0.19), Vector2(0.28, 0.24), Vector2(0.24, 0.27), Vector2(0.0, 0.27)]), body)
	_lathe(root, PackedVector2Array([Vector2(0.30, 0.055), Vector2(0.327, 0.07), Vector2(0.327, 0.082), Vector2(0.30, 0.095)]), detail)
	match type:
		1:
			_lathe(root, PackedVector2Array([Vector2(0.23, 0.24), Vector2(0.20, 0.31), Vector2(0.15, 0.39), Vector2(0.12, 0.56), Vector2(0.15, 0.60), Vector2(0.19, 0.63), Vector2(0.19, 0.68), Vector2(0.13, 0.72)]), body)
			_sphere(root, 0.205, Vector3(0, 0.86, 0), body)
		2:
			_lathe(root, PackedVector2Array([Vector2(0.25, 0.25), Vector2(0.23, 0.30), Vector2(0.21, 0.36), Vector2(0.20, 0.41), Vector2(0, 0.41)]), body)
			_knight(root, body, detail, dark)
		3:
			_stem(root, 0.88, body)
			_lathe(root, PackedVector2Array([Vector2(0, 0.88), Vector2(0.14, 0.88), Vector2(0.20, 0.94), Vector2(0.23, 1.04), Vector2(0.21, 1.15), Vector2(0.15, 1.26), Vector2(0.045, 1.39), Vector2(0, 1.41)]), body)
			_sphere(root, 0.065, Vector3(0, 1.40, 0), body)
			# The dark diagonal inlay gives the mitre its traditional cleft silhouette.
			var cut: MeshInstance3D = _box(root, Vector3(0.035, 0.25, 0.035), Vector3(0.07, 1.22, 0.158), dark)
			cut.rotation.z = -0.49
		4:
			_lathe(root, PackedVector2Array([Vector2(0.25, 0.24), Vector2(0.24, 0.33), Vector2(0.20, 0.40), Vector2(0.18, 0.84), Vector2(0.24, 0.89), Vector2(0.27, 0.94), Vector2(0.27, 1.06), Vector2(0.0, 1.06)]), body)
			for index: int in range(6):
				var angle: float = TAU * float(index) / 6.0
				var merlon: MeshInstance3D = _box(root, Vector3(0.17, 0.19, 0.16), Vector3(sin(angle) * 0.19, 1.13, cos(angle) * 0.19), body)
				merlon.rotation.y = angle
			_cylinder(root, 0.18, 0.18, 0.016, Vector3(0, 1.065, 0), dark)
		5:
			_stem(root, 0.97, body)
			_lathe(root, PackedVector2Array([Vector2(0.13, 0.94), Vector2(0.16, 1.02), Vector2(0.23, 1.13), Vector2(0.25, 1.22), Vector2(0.20, 1.25), Vector2(0.0, 1.25)]), body)
			for index: int in range(8):
				var angle: float = TAU * float(index) / 8.0
				var point: Vector3 = Vector3(sin(angle) * 0.235, 1.29, cos(angle) * 0.235)
				_cylinder(root, 0.035, 0.065, 0.18, point, body)
				_sphere(root, 0.055, point + Vector3(0, 0.105, 0), body)
			_sphere(root, 0.09, Vector3(0, 1.32, 0), detail)
		6:
			_stem(root, 1.04, body)
			_lathe(root, PackedVector2Array([Vector2(0.14, 1.02), Vector2(0.20, 1.09), Vector2(0.20, 1.15), Vector2(0.15, 1.19), Vector2(0.13, 1.27), Vector2(0, 1.29)]), body)
			_box(root, Vector3(0.10, 0.38, 0.11), Vector3(0, 1.44, 0), body)
			_box(root, Vector3(0.34, 0.10, 0.11), Vector3(0, 1.49, 0), body)
	if not white:
		root.rotation.y = PI
	return root

static func _stem(root: Node3D, top: float, material: Material) -> void:
	_lathe(root, PackedVector2Array([Vector2(0.25, 0.24), Vector2(0.23, 0.31), Vector2(0.18, 0.39), Vector2(0.13, top - 0.20), Vector2(0.15, top - 0.12), Vector2(0.21, top - 0.08), Vector2(0.23, top - 0.04), Vector2(0.23, top), Vector2(0.14, top + 0.025)]), material)

static func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result

static func _lathe(root: Node3D, profile: PackedVector2Array, material: Material) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = 40
	for ring: int in range(profile.size() - 1):
		for segment: int in range(segments):
			var a: float = TAU * float(segment) / float(segments)
			var b: float = TAU * float(segment + 1) / float(segments)
			var p0: Vector3 = Vector3(cos(a) * profile[ring].x, profile[ring].y, sin(a) * profile[ring].x)
			var p1: Vector3 = Vector3(cos(b) * profile[ring].x, profile[ring].y, sin(b) * profile[ring].x)
			var p2: Vector3 = Vector3(cos(b) * profile[ring + 1].x, profile[ring + 1].y, sin(b) * profile[ring + 1].x)
			var p3: Vector3 = Vector3(cos(a) * profile[ring + 1].x, profile[ring + 1].y, sin(a) * profile[ring + 1].x)
			for vertex: Vector3 in [p0, p1, p2, p0, p2, p3]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = material
	root.add_child(instance)

static func _sphere(root: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 28
	mesh.rings = 14
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	root.add_child(instance)
	return instance

static func _cylinder(root: Node3D, top: float, bottom: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 40
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	root.add_child(instance)
	return instance

static func _box(root: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	root.add_child(instance)
	return instance

static func _knight(root: Node3D, body: Material, detail: Material, dark: Material) -> void:
	# A solid, chamfered horse with a slight presentation angle. Its cheeks and
	# neck stay visible from either seat instead of becoming an edge-on strip.
	var horse: Node3D = Node3D.new()
	horse.name = "Horse"
	horse.rotation.y = -1.0
	root.add_child(horse)
	var outline: PackedVector2Array = PackedVector2Array([
		Vector2(0.20, 0.38), Vector2(0.27, 0.53), Vector2(0.26, 0.78), Vector2(0.20, 1.06),
		Vector2(0.12, 1.27), Vector2(0.07, 1.43), Vector2(-0.015, 1.34), Vector2(-0.13, 1.40),
		Vector2(-0.14, 1.22), Vector2(-0.27, 1.13), Vector2(-0.42, 0.92), Vector2(-0.40, 0.82),
		Vector2(-0.27, 0.80), Vector2(-0.09, 0.94), Vector2(-0.02, 0.87), Vector2(-0.06, 0.63),
		Vector2(-0.21, 0.44), Vector2(-0.20, 0.38)
	])
	_extrude(horse, outline, 0.19, body)
	for index: int in range(5):
		var t: float = float(index) / 4.0
		var mane: MeshInstance3D = _box(horse, Vector3(0.10, 0.12, 0.075), Vector3(0, 0.70 + t * 0.51, 0.265 - t * 0.115), detail)
		mane.rotation.x = -0.24
	for side: int in [-1, 1]:
		_sphere(horse, 0.030, Vector3(float(side) * 0.192, 1.105, -0.16), dark)
		_sphere(horse, 0.015, Vector3(float(side) * 0.19, 0.895, -0.345), dark)

static func _extrude(root: Node3D, outline: PackedVector2Array, half_width: float, material: Material) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inset: PackedVector2Array = PackedVector2Array()
	var center: Vector2 = Vector2(-0.04, 0.87)
	for point: Vector2 in outline:
		inset.append(center + (point - center) * 0.91)
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(inset)
	for side: int in [-1, 1]:
		var expected: Vector3 = Vector3(float(side), 0, 0)
		for offset: int in range(0, triangles.size(), 3):
			var a: Vector2 = inset[triangles[offset]]
			var b: Vector2 = inset[triangles[offset + 1]]
			var c: Vector2 = inset[triangles[offset + 2]]
			_triangle(surface, Vector3(side * half_width, a.y, a.x), Vector3(side * half_width, b.y, b.x), Vector3(side * half_width, c.y, c.x), expected)
	var widths: Array[float] = [-half_width, -half_width * 0.62, half_width * 0.62, half_width]
	for layer: int in range(3):
		var left: PackedVector2Array = inset if layer == 0 else outline
		var right: PackedVector2Array = inset if layer == 2 else outline
		for index: int in range(outline.size()):
			var next: int = (index + 1) % outline.size()
			var delta: Vector2 = outline[next] - outline[index]
			var expected: Vector3 = Vector3(-0.60 if layer == 0 else (0.60 if layer == 2 else 0.0), -delta.x, delta.y).normalized()
			var a: Vector3 = Vector3(widths[layer], left[index].y, left[index].x)
			var b: Vector3 = Vector3(widths[layer + 1], right[index].y, right[index].x)
			var c: Vector3 = Vector3(widths[layer + 1], right[next].y, right[next].x)
			var d: Vector3 = Vector3(widths[layer], left[next].y, left[next].x)
			_triangle(surface, a, b, c, expected)
			_triangle(surface, a, c, d, expected)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = material
	root.add_child(instance)

## Godot uses clockwise front faces. Explicit winding and face normals keep
## the closed horse mesh consistent at concave profile edges and chamfers.
static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	if normal.dot(outward) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
		normal = -normal
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
