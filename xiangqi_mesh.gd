extends RefCounted
## Original Chinese-chess table and wooden discs; the view supplies its inscription font.

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

# Shared procedural resources are built once, including one font mask per inscription.
static var _wood_texture: ImageTexture
static var _wood_shader: Shader
static var _letter_shader: Shader
static var _letter_masks: Dictionary = {}

static func build_board(root: Node3D, font: Font) -> void:
	_box(root, Vector3(9.55, 0.22, 10.85), Vector3(0, -0.11, 0), _wood_material(1, Color("30231b"), Color("5c4231")))
	_box(root, Vector3(9.47, 0.18, 10.77), Vector3(0, 0.065, 0), _wood_material(1, Color("432d21"), Color("70523c")))
	_box(root, Vector3(9.12, 0.045, 10.42), Vector3(0, 0.166, 0), _wood_material(1, Color("5e422e"), Color("967650")))
	_box(root, Vector3(9.02, 0.06, 10.32), Vector3(0, 0.209, 0), _wood_material(0, Color("80634c"), Color("b19a80")))
	_river_text(root, "楚 河", Vector3(-2.05, BOARD_Y + 0.001, 0), font, "ChuRiver")
	_river_text(root, "汉 界", Vector3(2.05, BOARD_Y + 0.001, 0), font, "HanBorder")

static func create_piece(piece: int, font: Font) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Piece"
	var ink: Color = Color("7d2921") if piece > 0 else Color("29251f")
	var wood_offset: Vector2 = Vector2(float(absi(piece)) * 0.117, float(piece) * 0.071)
	var side: ShaderMaterial = _wood_material(1, Color("846448"), Color("b89b77"), wood_offset)
	_turned_disc(root, side)
	var glyphs: Dictionary = RED_GLYPHS if piece > 0 else BLACK_GLYPHS
	var mask: Texture2D = _letter_mask(font, str(glyphs.get(absi(piece), "")))
	var face: ShaderMaterial = _wood_material(2, Color("a68c6e"), Color("cfb99a"), wood_offset)
	face.set_shader_parameter("ink_color", ink)
	face.set_shader_parameter("letter_mask", mask)
	face.set_shader_parameter("letter_scale", Vector2(0.73, 0.73))
	var glyph: MeshInstance3D = _plane(root, Vector2(0.744, 0.744), Vector3(0, 0.24, 0), face)
	glyph.name = "Glyph"
	glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Each side faces its own player, independent of the viewing camera.
	glyph.rotation.y = PI if piece < 0 else 0.0
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

## Carved appearance uses a recessed height field, not cut-through/CSG geometry.
## Masks come from the supplied inscription font's raster cache.
static func _letter_mask(font: Font, text_value: String) -> Texture2D:
	var key: String = str(font.get_instance_id()) + ":" + text_value
	if _letter_masks.has(key):
		return _letter_masks[key] as Texture2D
	var size: int = 192
	var line: TextLine = TextLine.new()
	line.add_string(text_value, font, size)
	var server: TextServer = TextServerManager.get_primary_interface()
	var canvas: Image = Image.create(int(ceilf(line.get_size().x)) + 16, int(ceilf(line.get_size().y)) + 16, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(1, 1, 1, 0))
	var pen: Vector2 = Vector2(8, 8 + line.get_line_ascent())
	for glyph: Dictionary in server.shaped_text_get_glyphs(line.get_rid()):
		var rid: RID = glyph.font_rid
		var index: int = glyph.index
		var cache_size: Vector2i = Vector2i(size, 0)
		server.font_render_glyph(rid, cache_size, index)
		var atlas_index: int = server.font_get_glyph_texture_idx(rid, cache_size, index)
		if atlas_index >= 0:
			var atlas: Image = server.font_get_texture_image(rid, cache_size, atlas_index)
			var rect: Rect2i = Rect2i(server.font_get_glyph_uv_rect(rid, cache_size, index))
			var offset: Vector2 = server.font_get_glyph_offset(rid, cache_size, index) + Vector2(glyph.offset)
			var crop: Image = atlas.get_region(rect)
			crop.convert(Image.FORMAT_RGBA8)
			canvas.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(pen + offset))
		pen.x += float(glyph.advance) * int(glyph.repeat)
	var used: Rect2i = canvas.get_used_rect()
	var padding: int = 8
	var width: int = maxi(used.size.x, size) + padding * 2
	var height: int = maxi(used.size.y, size) + padding * 2
	var mask: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1, 1, 1, 0))
	mask.blit_rect(canvas, used, (Vector2i(width, height) - used.size) / 2)
	# Keep the ink silhouette crisp while softening the cavity's bevel height.
	var height_map: Image = mask.duplicate()
	height_map.resize(maxi(width / 3, 1), maxi(height / 3, 1), Image.INTERPOLATE_BILINEAR)
	height_map.resize(width, height, Image.INTERPOLATE_BILINEAR)
	for y: int in range(height):
		for x: int in range(width):
			var pixel: Color = mask.get_pixel(x, y)
			pixel.r = height_map.get_pixel(x, y).a
			mask.set_pixel(x, y, pixel)
	mask.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(mask)
	_letter_masks[key] = texture
	return texture

static func _river_text(root: Node3D, text_value: String, at: Vector3, font: Font, node_name: String) -> void:
	if _letter_shader == null:
		_letter_shader = Shader.new()
		_letter_shader.code = """shader_type spatial;
		render_mode cull_back, depth_draw_opaque;
		uniform sampler2D letter_mask : filter_linear_mipmap, repeat_disable;
		uniform vec3 ink_color : source_color = vec3(0.28, 0.16, 0.09);
		void fragment() {
			vec2 texel = 2.4 / vec2(textureSize(letter_mask, 0));
			float cut = texture(letter_mask, UV).a;
			float left = texture(letter_mask, UV - vec2(texel.x, 0.0)).a;
			float right = texture(letter_mask, UV + vec2(texel.x, 0.0)).a;
			float up = texture(letter_mask, UV - vec2(0.0, texel.y)).a;
			float down = texture(letter_mask, UV + vec2(0.0, texel.y)).a;
			float edge = max(max(left, right), max(up, down));
			ALBEDO = mix(vec3(0.52, 0.39, 0.26), ink_color, cut);
			ALBEDO *= 0.78 + 0.22 * cut - max(cut - down, 0.0) * 0.28;
			NORMAL_MAP = normalize(vec3((right - left) * 0.95, (up - down) * 0.95, 1.0)) * 0.5 + 0.5;
			ROUGHNESS = 0.84;
			SPECULAR = 0.18;
			ALPHA = max(cut, edge * 0.7);
		}"""
	var mask: Texture2D = _letter_mask(font, text_value)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _letter_shader
	material.set_shader_parameter("letter_mask", mask)
	material.set_shader_parameter("ink_color", Color("60402b"))
	var plane: MeshInstance3D = _plane(root, Vector2(float(mask.get_width()) / float(mask.get_height()) * 0.58, 0.58), at, material)
	plane.name = node_name

static func _plane(root: Node3D, dimensions: Vector2, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = dimensions
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	return instance

static func _box(root: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	root.add_child(instance)
	return instance

## A softly turned rim catches the key light without adding ornamental trim.
static func _turned_disc(root: Node3D, material: Material) -> void:
	var profile: PackedVector2Array = PackedVector2Array([
		Vector2(0.345, 0.002), Vector2(0.370, 0.011), Vector2(0.390, 0.028),
		Vector2(0.398, 0.052), Vector2(0.398, 0.173), Vector2(0.394, 0.199),
		Vector2(0.384, 0.223), Vector2(0.372, 0.24)])
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var segments: int = 64
	for row: int in range(profile.size()):
		var tangent: Vector2 = profile[mini(row + 1, profile.size() - 1)] - profile[maxi(row - 1, 0)]
		var normal: Vector2 = Vector2(tangent.y, -tangent.x).normalized()
		for segment: int in range(segments + 1):
			var angle: float = TAU * float(segment) / float(segments)
			vertices.append(Vector3(cos(angle) * profile[row].x, profile[row].y, sin(angle) * profile[row].x))
			normals.append(Vector3(cos(angle) * normal.x, normal.y, sin(angle) * normal.x))
			if row < profile.size() - 1 and segment < segments:
				var a: int = row * (segments + 1) + segment
				var b: int = a + segments + 1
				indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
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

## Pack long grain, pores and finish variation into one reusable, original data texture.
static func _grain_texture() -> ImageTexture:
	if _wood_texture != null:
		return _wood_texture
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 87475
	noise.frequency = 0.021
	noise.fractal_octaves = 3
	var image: Image = Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for y: int in range(512):
		for x: int in range(512):
			var warp: float = noise.get_noise_2d(float(x) * 0.58, float(y) * 0.22)
			var broad: float = noise.get_noise_2d(float(x) * 1.2, float(y) * 0.12)
			var thread: float = float(x) * 0.48 + warp * 9.0 + sin(float(y) * 0.012) * 0.55
			var growth: float = pow(0.5 + 0.5 * sin(thread), 7.0)
			var fiber: float = noise.get_noise_2d(float(x) * 7.0, float(y) * 0.48)
			var pore: float = smoothstep(0.17, 0.48, fiber)
			var tone: float = clampf(0.62 + broad * 0.19 + warp * 0.10 + fiber * 0.08 - growth * 0.08 - pore * 0.08, 0.0, 1.0)
			image.set_pixel(x, y, Color(tone, 0.5 + fiber * 0.42, 0.66 - growth * 0.20 - pore * 0.25, 0.5 + broad * 0.30))
	image.generate_mipmaps()
	_wood_texture = ImageTexture.create_from_image(image)
	return _wood_texture

static func _wood_material(surface: int, dark: Color, light: Color, grain_offset: Vector2 = Vector2.ZERO) -> ShaderMaterial:
	if _wood_shader == null:
		_wood_shader = Shader.new()
		_wood_shader.code = """shader_type spatial;
		uniform sampler2D wood_map : filter_linear_mipmap, repeat_enable;
		uniform sampler2D letter_mask : filter_linear_mipmap, repeat_disable;
		uniform vec3 wood_dark : source_color;
		uniform vec3 wood_light : source_color;
		uniform vec3 ink_color : source_color = vec3(0.24, 0.13, 0.07);
		uniform vec2 grain_offset = vec2(0.0);
		uniform vec2 letter_scale = vec2(1.0);
		uniform int surface = 1;
		varying vec3 wood_position;
		varying vec3 wood_normal;
		void vertex() { wood_position = VERTEX; wood_normal = NORMAL; }
		float segment_distance(vec2 p, vec2 a, vec2 b) {
			vec2 delta = b - a;
			return length(p - a - delta * clamp(dot(p - a, delta) / dot(delta, delta), 0.0, 1.0));
		}
		float start_mark(vec2 p) {
			p = abs(p);
			return min(segment_distance(p, vec2(0.08), vec2(0.20, 0.08)), segment_distance(p, vec2(0.08), vec2(0.08, 0.20)));
		}
		float board_cut(vec2 p) {
			vec2 q = abs(p);
			float horizontal = length(vec2(max(q.x - 4.0, 0.0), q.y - (0.65 + clamp(round(q.y - 0.65), 0.0, 4.0))));
			float vertical = length(vec2(p.x - clamp(round(p.x), -4.0, 4.0), max(0.65 - q.y, max(q.y - 4.65, 0.0))));
			float edge = length(vec2(q.x - 4.0, max(q.y - 4.65, 0.0)));
			float border = min(length(vec2(q.x - 4.11, max(q.y - 4.76, 0.0))), length(vec2(max(q.x - 4.11, 0.0), q.y - 4.76)));
			float palace = min(segment_distance(vec2(p.x, q.y), vec2(-1.0, 2.65), vec2(1.0, 4.65)), segment_distance(vec2(p.x, q.y), vec2(1.0, 2.65), vec2(-1.0, 4.65)));
			float cannon = start_mark(vec2(q.x - 3.0, q.y - 2.65));
			float soldier = start_mark(vec2(p.x - clamp(round(p.x * 0.5), -2.0, 2.0) * 2.0, q.y - 1.65));
			if (q.x > 4.0) { soldier = 1.0; }
			return min(min(min(horizontal, vertical), min(edge, border)), min(palace, min(cannon, soldier)));
		}
		void fragment() {
			vec2 p = wood_position.xz;
			vec2 grain_uv = p / vec2(9.02, 10.32) + vec2(0.5) + grain_offset;
			// End grain and shallow lathe marks distinguish the rim from the flat face.
			float side = 1.0 - abs(wood_normal.y);
			grain_uv.y += wood_position.y * side * 0.18;
			vec4 grain = texture(wood_map, grain_uv);
			float detail = texture(wood_map, grain_uv * vec2(3.0, 0.55)).g;
			vec3 wood = mix(wood_dark, wood_light, clamp((grain.r - 0.32) * 1.45 + (detail - 0.5) * 0.18, 0.0, 1.0));
			float lathe = (1.0 - smoothstep(0.001, 0.004, min(abs(wood_position.y - 0.071), abs(wood_position.y - 0.158)))) * side;
			wood *= 1.0 - lathe * 0.14;
			float cut = 0.0;
			float lip = 0.0;
			float depth = 0.0;
			vec3 pigment = ink_color;
			if (surface == 0 && wood_normal.y > 0.5) {
				float distance = board_cut(p);
				float aa = max(fwidth(distance) * 0.7, 0.001);
				cut = 1.0 - smoothstep(0.010 - aa, 0.016 + aa, distance);
				lip = (1.0 - smoothstep(0.016, 0.025 + aa, distance)) - cut;
				depth = cut * 0.011;
			}
			if (surface == 2) {
				float radius = length(p);
				if (radius > 0.372) { discard; }
				float ring_distance = abs(radius - 0.330);
				float aa = max(fwidth(ring_distance) * 0.6, 0.0007);
				float ring = 1.0 - smoothstep(0.005 - aa, 0.010 + aa, ring_distance);
				vec2 letter_uv = (UV - vec2(0.5)) / letter_scale + vec2(0.5);
				float letter = texture(letter_mask, letter_uv).a;
				vec2 texel = 2.5 / vec2(textureSize(letter_mask, 0));
				vec3 local_light = transpose(mat3(MODEL_MATRIX)) * vec3(-0.45, 0.8, 0.38);
				vec2 bevel_step = texel * normalize(local_light.xz);
				float toward_light = texture(letter_mask, letter_uv + bevel_step).a;
				float away_from_light = texture(letter_mask, letter_uv - bevel_step).a;
				wood = mix(wood, wood_dark * 0.45, max(toward_light - letter, 0.0) * 0.72);
				pigment *= 1.0 - max(letter - toward_light, 0.0) * 0.38;
				cut = max(ring, letter);
				lip = max((1.0 - smoothstep(0.010, 0.017 + aa, ring_distance)) - ring, max(away_from_light - letter, 0.0) * 0.85);
				depth = max(texture(letter_mask, letter_uv).r * 0.014, ring * 0.008);
			}
			ALBEDO = mix(wood * (1.0 + lip * 0.23), pigment * (0.76 + grain.g * 0.18), cut);
			ROUGHNESS = clamp(0.46 + grain.a * 0.20 + cut * 0.21, 0.0, 1.0);
			SPECULAR = 0.28;
			float relief = grain.b * 0.002 + detail * 0.0006 - depth;
			vec3 dx = dFdx(VERTEX);
			vec3 dy = dFdy(VERTEX);
			vec3 r1 = cross(dy, NORMAL);
			vec3 r2 = cross(NORMAL, dx);
			float determinant = dot(dx, r1);
			vec3 gradient = sign(determinant) * (dFdx(relief) * r1 + dFdy(relief) * r2);
			NORMAL = normalize(abs(determinant) * NORMAL - gradient);
		}"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _wood_shader
	material.set_shader_parameter("wood_map", _grain_texture())
	material.set_shader_parameter("wood_dark", dark)
	material.set_shader_parameter("wood_light", light)
	material.set_shader_parameter("surface", surface)
	material.set_shader_parameter("grain_offset", grain_offset)
	material.set_shader_parameter("ink_color", Color("533723"))
	return material
