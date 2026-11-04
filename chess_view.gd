extends Control
## Full-frame chess presentation. Rules, network authority, and menu blocking belong to game.gd.

signal square_selected(square: int)
signal promotion_selected(piece: int)
signal resign_requested()
signal draw_offered()
signal draw_accepted()
signal draw_declined()
signal draw_claimed()

const PieceMesh: Script = preload("piece_mesh.gd")
const XiangqiMesh: Script = preload("xiangqi_mesh.gd")
const INK: Color = Color(0.96, 0.95, 0.91, 1.0)
const BOARD_Y: float = 0.24

var input_enabled: bool = true:
	set(value):
		input_enabled = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		if not value:
			_orbiting = false
		_refresh_control_states()

@onready var board_viewport: Viewport = get_viewport()
@onready var world: Node3D = %World
@onready var camera: Camera3D = %Camera

var _mode: String = "chess"
var _piece_font: Font
var _board_geometry: Node3D
var _title_label: Label
var _rules_label: Label
var _pieces: Node3D
var _markers: Node3D
var _hover_marker: MeshInstance3D
var _board_cache: Array = []
var _position: Dictionary = {}
var _presentation: Dictionary = {}
var _status_label: Label
var _white_label: Label
var _black_label: Label
var _seat_label: Label
var _last_move_label: Label
var _resign_button: Button
var _draw_button: Button
var _claim_button: Button
var _offer_bar: HBoxContainer
var _accept_button: Button
var _decline_button: Button
var _details: Control
var _history_label: RichTextLabel
var _promotion: Control
var _promotion_buttons: Array[Button] = []
var _confirm_resign: Control
var _hud: Control
var _help_label: Label
var _details_button: Button
var _input_context: PartyInput
var _show_legal_moves: bool = true
var _orbit_sensitivity: float = 1.0
var _yaw: float = 0.22
var _pitch: float = 0.90
var _distance: float = 18.0
var _base_yaw: float = 0.22
var _orientation_side: int = 1
var _orbiting: bool = false
var _hover_square: int = -1
var _ready_done: bool = false
var _action_buttons: Array[Button] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if input_enabled else Control.MOUSE_FILTER_IGNORE
	_build_world()
	_build_hud()
	_ready_done = true
	resized.connect(_layout_hud)
	_layout_hud()
	_update_camera()
	if not _position.is_empty():
		set_model(_position, _presentation)

## Select a room's ruleset before tree insertion, or rebuild only board geometry later.
## Lighting nodes remain stable because the protocol settings runtime owns their quality.
func configure_mode(mode: String, font: Font) -> void:
	assert(mode in ["chess", "xiangqi"], "Unknown chess presentation mode")
	var changed: bool = mode != _mode or font != _piece_font
	_mode = mode
	_piece_font = font
	if not _ready_done:
		_distance = 20.5 if _mode == "xiangqi" else 18.0
		return
	if changed:
		for node: Node3D in [_board_geometry, _pieces, _markers, _hover_marker]:
			world.remove_child(node)
			node.queue_free()
		_board_cache.clear()
		_build_board_scene()
		var board: Array = _position.get("board", [])
		_rebuild_pieces(board)
		_orient_xiangqi_labels()
		_board_cache = board.duplicate()
		_rebuild_markers()
		_promotion.hide()
		reset_camera()
	_refresh_mode_text()

func _refresh_mode_text() -> void:
	if not is_instance_valid(_title_label):
		return
	var red_name: String = "红方" if _mode == "xiangqi" else "白方"
	_title_label.text = "中国象棋" if _mode == "xiangqi" else "国际象棋"
	_white_label.text = red_name + "　" + str(_presentation.get("white_name", red_name))
	_black_label.text = "黑方　" + str(_presentation.get("black_name", "黑方"))
	var local_side: int = int(_presentation.get("local_side", 0))
	_seat_label.text = ("执红" if _mode == "xiangqi" else "执白") if local_side == 1 else ("执黑" if local_side == -1 else "观战")
	_white_label.add_theme_color_override("font_color", Color("eaa995") if _mode == "xiangqi" else INK)
	_rules_label.text = _rules_text()

func _orient_xiangqi_labels() -> void:
	if _mode != "xiangqi":
		return
	for river_name: String in ["ChuRiver", "HanBorder"]:
		var river_label: Label3D = _board_geometry.get_node(river_name) as Label3D
		river_label.rotation.y = PI if _orientation_side < 0 else 0.0
		river_label.position.x = (-2.05 if river_name == "ChuRiver" else 2.05) * _orientation_side
	for piece: Node in _pieces.get_children():
		var glyph: Label3D = piece.get_node("Glyph") as Label3D
		glyph.rotation.y = PI if _orientation_side < 0 else 0.0

## The model is immutable presentation input. Rebuild geometry only after board changes.
func set_model(position: Dictionary, presentation: Dictionary) -> void:
	var mode: String = str(presentation.get("mode", _mode))
	if mode != _mode:
		configure_mode(mode, _piece_font)
	_position = position.duplicate(true)
	_presentation = presentation.duplicate(true)
	if not _ready_done:
		return
	var board: Array = position.get("board", [])
	if board != _board_cache:
		_rebuild_pieces(board)
		_board_cache = board.duplicate()
	var local_side: int = int(presentation.get("local_side", 0))
	var orientation: int = -1 if local_side < 0 else 1
	if orientation != _orientation_side:
		_orientation_side = orientation
		_base_yaw = PI + 0.22 if orientation < 0 else 0.22
		reset_camera()
		_orient_xiangqi_labels()
	_rebuild_markers()
	_status_label.text = str(presentation.get("status", ""))
	_refresh_mode_text()
	_last_move_label.text = _last_move_text()
	var history: Array = presentation.get("history", [])
	_history_label.text = _format_history(history)
	var offer: int = int(presentation.get("draw_offer", 0))
	_offer_bar.visible = offer != 0 and local_side != 0 and offer != local_side
	_claim_button.visible = (bool(presentation.get("claimable", false)) or bool(presentation.get("claim_mode", false))) and local_side != 0
	_claim_button.text = "取消和棋申请" if bool(presentation.get("claim_mode", false)) else "申请和棋"
	_draw_button.text = "已提议和棋" if offer != 0 and offer == local_side else "提议和棋"
	_refresh_control_states()

func show_promotion(visible_value: bool) -> void:
	if is_instance_valid(_promotion):
		_promotion.visible = visible_value and _mode != "xiangqi"
		if visible_value:
			_details.hide()
		_orbiting = false
		_refresh_control_states()

func reset_camera() -> void:
	_yaw = _base_yaw
	_pitch = 0.90
	_distance = 20.5 if _mode == "xiangqi" else 18.0
	_update_camera()

func _build_world() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("121c1d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b5c2b8")
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "LightingEnvironment"
	world_environment.environment = environment
	world.add_child(world_environment)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-56, -28, 0)
	key.light_color = Color("fff1d5")
	key.light_energy = 0.85
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 30.0
	key.shadow_bias = 0.035
	world.add_child(key)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(2, 5, -6)
	fill.light_color = Color("a8c5dc")
	fill.light_energy = 0.45
	fill.omni_range = 18
	world.add_child(fill)
	var floor_material: StandardMaterial3D = _material(Color("111d1d"), 0.93)
	_box(Vector3(200, 0.1, 200), Vector3(0, -0.33, 0), floor_material)
	_build_board_scene()

func _build_board_scene() -> void:
	_board_geometry = Node3D.new()
	_board_geometry.name = "BoardGeometry"
	world.add_child(_board_geometry)
	if _mode == "xiangqi":
		XiangqiMesh.build_board(_board_geometry, _piece_font)
	else:
		_build_chess_board()

	_pieces = Node3D.new()
	_pieces.name = "Pieces"
	world.add_child(_pieces)
	_markers = Node3D.new()
	_markers.name = "MoveMarkers"
	world.add_child(_markers)
	_hover_marker = _flat_marker(Color(0.93, 0.94, 0.72, 0.12), 0.98)
	_hover_marker.visible = false
	world.add_child(_hover_marker)

func _build_chess_board() -> void:
	var wood: ShaderMaterial = _wood_material()
	_box(Vector3(9.02, 0.22, 9.02), Vector3(0, -0.11, 0), _material(Color("281c14"), 0.48))
	_box(Vector3(8.96, 0.16, 8.96), Vector3(0, 0.07, 0), wood)
	_box(Vector3(8.30, 0.045, 8.30), Vector3(0, 0.165, 0), _material(Color("c6ae77"), 0.31, 0.4))
	_box(Vector3(8.14, 0.055, 8.14), Vector3(0, 0.193, 0), _material(Color("30261b"), 0.45))
	var light_square: Material = _material(Color("c2bda4"), 0.64)
	var dark_square: Material = _material(Color("3c5a49"), 0.64)
	for square: int in range(64):
		var file: int = square % 8
		var rank: int = square / 8
		var point: Vector3 = _square_position(square)
		point.y = 0.225
		_box(Vector3(0.994, 0.03, 0.994), point, light_square if (file + rank) % 2 != 0 else dark_square)
	for index: int in range(8):
		var coordinate: float = float(index) - 3.5
		_board_letter("abcdefgh"[index], Vector3(coordinate, 0.157, 4.26), 0)
		_board_letter("abcdefgh"[7 - index], Vector3(-coordinate, 0.157, -4.26), PI)
		_board_letter(str(index + 1), Vector3(-4.26, 0.157, -coordinate), 0)
		_board_letter(str(8 - index), Vector3(4.26, 0.157, coordinate), PI)

func _rebuild_pieces(board: Array) -> void:
	for child: Node in _pieces.get_children():
		_pieces.remove_child(child)
		child.queue_free()
	for square: int in range(mini(board.size(), _square_count())):
		var piece: int = int(board[square])
		if piece == 0:
			continue
		var instance: Node3D = XiangqiMesh.create_piece(piece, _piece_font, _orientation_side) if _mode == "xiangqi" else PieceMesh.create(piece)
		instance.position = _square_position(square)
		_pieces.add_child(instance)

func _rebuild_markers() -> void:
	for child: Node in _markers.get_children():
		_markers.remove_child(child)
		child.queue_free()
	for field: String in ["last_from", "last_to"]:
		var square: int = int(_presentation.get(field, -1))
		if square >= 0 and square < _square_count():
			var last_marker: MeshInstance3D = _flat_marker(Color(0.79, 0.71, 0.35, 0.21), 0.985)
			last_marker.position = _square_position(square) + Vector3(0, 0.006, 0)
			_markers.add_child(last_marker)
	var selected: int = int(_presentation.get("selected", -1))
	if selected >= 0 and selected < _square_count():
		var selected_marker: MeshInstance3D = _flat_marker(Color(0.78, 0.89, 0.49, 0.40), 0.985)
		selected_marker.position = _square_position(selected) + Vector3(0, 0.012, 0)
		_markers.add_child(selected_marker)
		_square_outline(selected, Color("d6e7a8"))
	var targets: Array = _presentation.get("targets", []) if _show_legal_moves else []
	for target: Variant in targets:
		var square: int = int(target)
		if square < 0 or square >= _square_count():
			continue
		var occupied: bool = _board_cache.size() == _square_count() and int(_board_cache[square]) != 0
		if occupied:
			_square_outline(square, Color("d1e3a2"))
		else:
			var dot: MeshInstance3D = MeshInstance3D.new()
			var mesh: CylinderMesh = CylinderMesh.new()
			mesh.top_radius = 0.115
			mesh.bottom_radius = 0.115
			mesh.height = 0.012
			mesh.radial_segments = 32
			dot.mesh = mesh
			dot.material_override = _unshaded(Color(0.76, 0.86, 0.58, 0.72))
			dot.position = _square_position(square) + Vector3(0, 0.018, 0)
			_markers.add_child(dot)
	var check_square: int = int(_presentation.get("check_square", -1))
	if check_square >= 0 and check_square < _square_count():
		var check_marker: MeshInstance3D = _flat_marker(Color(0.83, 0.29, 0.22, 0.44), 0.985)
		check_marker.position = _square_position(check_square) + Vector3(0, 0.009, 0)
		_markers.add_child(check_marker)
		_square_outline(check_square, Color("d3816e"))

func _square_outline(square: int, color: Color) -> void:
	if _mode == "xiangqi":
		var ring: MeshInstance3D = XiangqiMesh.ring_marker(color)
		ring.position = _square_position(square) + Vector3(0, 0.025, 0)
		_markers.add_child(ring)
		return
	var at: Vector3 = _square_position(square) + Vector3(0, 0.022, 0)
	for edge: int in range(4):
		var horizontal: bool = edge < 2
		var marker: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(0.95, 0.008, 0.026) if horizontal else Vector3(0.026, 0.008, 0.95)
		marker.mesh = mesh
		marker.material_override = _unshaded(color)
		marker.position = at + (Vector3(0, 0, -0.46 if edge == 0 else 0.46) if horizontal else Vector3(-0.46 if edge == 2 else 0.46, 0, 0))
		_markers.add_child(marker)

func _square_count() -> int:
	return 90 if _mode == "xiangqi" else 64

func _square_position(square: int) -> Vector3:
	if _mode == "xiangqi":
		return XiangqiMesh.square_position(square)
	return Vector3(float(square % 8) - 3.5, BOARD_Y, 3.5 - float(square / 8))

func _board_letter(text_value: String, at: Vector3, turn: float) -> void:
	var label: Label3D = Label3D.new()
	label.text = text_value
	label.position = at
	label.rotation = Vector3(-PI / 2.0, 0, turn)
	label.font_size = 42
	label.pixel_size = 0.005
	label.modulate = Color("e1c896")
	label.outline_size = 0
	label.no_depth_test = false
	_board_geometry.add_child(label)

func _box(box_size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	(_board_geometry if is_instance_valid(_board_geometry) else world).add_child(instance)
	return instance

func _flat_marker(color: Color, side: float) -> MeshInstance3D:
	if _mode == "xiangqi":
		return XiangqiMesh.disc_marker(color, side * 0.47)
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(side, side)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _unshaded(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result

func _unshaded(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = _material(color, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _wood_material() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
	varying vec3 local_vertex;
	void vertex() { local_vertex = VERTEX; }
	void fragment() {
		float grain = sin(local_vertex.x * 85.0 + sin(local_vertex.z * 3.0) * 1.4);
		float fine = sin(local_vertex.x * 231.0 + local_vertex.z * 5.0);
		ALBEDO = mix(vec3(0.045, 0.020, 0.009), vec3(0.085, 0.043, 0.018), 0.52 + grain * 0.17 + fine * 0.045);
		ROUGHNESS = 0.41;
	}"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	return material

func _update_camera() -> void:
	if not is_instance_valid(camera):
		return
	var aspect: float = size.x / maxf(size.y, 1.0)
	var narrow_factor: float = maxf(1.0, 1.36 / maxf(aspect, 0.1))
	var radius: float = _distance * narrow_factor
	camera.position = Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * radius
	camera.look_at(Vector3(0, -0.25, 0), Vector3.UP)

## Local preferences affect presentation only, never the host's legal-move rules.
func configure_input(input_context: PartyInput) -> void:
	_input_context = input_context
	_refresh_input_hints()

func apply_preferences(show_moves: bool, orbit_sensitivity: float) -> void:
	_show_legal_moves = show_moves
	_orbit_sensitivity = orbit_sensitivity
	if _ready_done:
		_rebuild_markers()
	_refresh_input_hints()

func _gui_input(event: InputEvent) -> void:
	if _handle_view_action(event):
		accept_event()
		return
	if not _view_input_allowed() or _promotion.visible or _confirm_resign.visible or _details.visible:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mouse_event.pressed
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if bool(_presentation.get("can_act", false)) and _local_turn():
				var square: int = _square_at_point(mouse_event.position)
				if square >= 0:
					square_selected.emit(square)
					accept_event()
		elif mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_distance = clampf(_distance + (-0.7 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.7), 13.0 if _mode == "xiangqi" else 11.8, 24.0 if _mode == "xiangqi" else 21.0)
			_update_camera()
			accept_event()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _orbiting:
			_yaw -= motion.relative.x * 0.006 * _orbit_sensitivity
			_pitch = clampf(_pitch + motion.relative.y * 0.005 * _orbit_sensitivity, 0.48, 1.30)
			_update_camera()
			accept_event()
		_update_hover()

func _unhandled_key_input(event: InputEvent) -> void:
	if _handle_view_action(event):
		get_viewport().set_input_as_handled()

func _control_input(event: InputEvent) -> void:
	if _handle_view_action(event):
		accept_event()

func _view_input_allowed() -> bool:
	return input_enabled and is_visible_in_tree() and (_input_context == null or not _input_context.input_blocked)

func _handle_view_action(event: InputEvent) -> bool:
	if not _ready_done or not _view_input_allowed() or not event.is_pressed() or event.is_echo():
		return false
	if event.is_action_pressed(&"ui_cancel"):
		if _promotion.visible:
			promotion_selected.emit(0)
		elif _confirm_resign.visible:
			_confirm_resign.hide()
		elif _details.visible:
			_details.hide()
		else:
			return false
		return true
	if _promotion.visible or _confirm_resign.visible:
		return false
	if _matches_view_action(event, &"chess_details"):
		_toggle_details()
		return true
	if _matches_view_action(event, &"chess_reset_view"):
		reset_camera()
		return true
	return false

## View-only shortcuts are also available to spectators. The public bindings
## still own the mapping, while input_blocked and pressed/echo checks gate use.
func _matches_view_action(event: InputEvent, action: StringName) -> bool:
	if _input_context == null:
		return false
	for binding: Dictionary in _input_context.get_bindings(action):
		if binding.is_empty():
			continue
		var mapped: InputEventWithModifiers
		if binding.kind == "mouse":
			var mouse: InputEventMouseButton = InputEventMouseButton.new()
			mouse.button_index = int(binding.code)
			mapped = mouse
		else:
			var key: InputEventKey = InputEventKey.new()
			if binding.physical:
				key.physical_keycode = int(binding.code)
			else:
				key.keycode = int(binding.code)
			mapped = key
		for modifier: String in ["ctrl", "alt", "shift", "meta"]:
			mapped.set(modifier + "_pressed", binding.get(modifier, false) or (binding.kind == "key" and binding.code == {"ctrl": KEY_CTRL, "alt": KEY_ALT, "shift": KEY_SHIFT, "meta": KEY_META}[modifier]))
		if mapped.is_match(event, true):
			return true
	return false

func _refresh_input_hints() -> void:
	if not is_instance_valid(_help_label):
		return
	var reset_binding: String = _input_context.binding_text(&"chess_reset_view") if _input_context != null else "未绑定"
	var details_binding: String = _input_context.binding_text(&"chess_details") if _input_context != null else "未绑定"
	_help_label.text = "左键：走棋　右键：旋转　滚轮：缩放\n%s：复位　%s：棋局　Esc：菜单" % [reset_binding, details_binding]
	_details_button.tooltip_text = "棋谱、规则与对局操作（%s）" % details_binding

func _square_at_mouse() -> int:
	return _square_at_point(get_local_mouse_position())

func _square_at_point(point: Vector2) -> int:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return -1
	point *= board_viewport.get_visible_rect().size / size
	var origin: Vector3 = camera.project_ray_origin(point)
	var direction: Vector3 = camera.project_ray_normal(point)
	if absf(direction.y) < 0.001:
		return -1
	var distance: float = (BOARD_Y - origin.y) / direction.y
	if distance < 0:
		return -1
	var hit: Vector3 = origin + direction * distance
	if _mode == "xiangqi":
		return XiangqiMesh.square_at(hit)
	var file: int = int(floor(hit.x + 4.0))
	var rank: int = int(floor(4.0 - hit.z))
	return rank * 8 + file if file >= 0 and file < 8 and rank >= 0 and rank < 8 else -1

func _update_hover() -> void:
	_hover_square = _square_at_mouse() if input_enabled and bool(_presentation.get("can_act", false)) and _local_turn() else -1
	_hover_marker.visible = _hover_square >= 0 and not _orbiting
	if _hover_marker.visible:
		_hover_marker.position = _square_position(_hover_square) + Vector3(0, 0.03, 0)

## Public scoped graphics targets consumed by the protocol's settings runtime.
func graphics_targets() -> Dictionary:
	if not _ready_done:
		return {}
	return {"world": world.get_node("LightingEnvironment"), "sun": world.get_node("KeyLight"), "materials_root": world}

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_title_label = _hud_label("中国象棋" if _mode == "xiangqi" else "国际象棋", 26)
	_title_label.name = "Title"
	_title_label.position = Vector2(28, 24)
	_title_label.size = Vector2(392, 38)
	_hud.add_child(_title_label)
	_status_label = _hud_label("等待开局", 22)
	_status_label.name = "Status"
	_status_label.position = Vector2(28, 64)
	_status_label.size = Vector2(760, 72)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_child(_status_label)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "Actions"
	actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	actions.offset_left = 28
	actions.offset_top = -92
	actions.offset_right = 288
	actions.offset_bottom = -28
	actions.add_theme_constant_override("separation", 16)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(actions)
	_details_button = _button("棋局")
	_details_button.custom_minimum_size = Vector2(260, 64)
	_details_button.set_meta("view_utility", true)
	_details_button.pressed.connect(_toggle_details)
	actions.add_child(_details_button)
	_action_buttons.append(_details_button)
	# A response is only surfaced at the edge when the opponent actually offers a draw.
	_offer_bar = HBoxContainer.new()
	_offer_bar.name = "DrawOffer"
	_offer_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_offer_bar.offset_left = 28
	_offer_bar.offset_top = -168
	_offer_bar.offset_bottom = -104
	_offer_bar.add_theme_constant_override("separation", 16)
	_offer_bar.add_child(_hud_label("对方提议和棋", 22))
	_accept_button = _button("接受")
	_accept_button.pressed.connect(_accept_draw)
	_offer_bar.add_child(_accept_button)
	_decline_button = _button("继续对局")
	_decline_button.pressed.connect(_decline_draw)
	_offer_bar.add_child(_decline_button)
	_offer_bar.visible = false
	_hud.add_child(_offer_bar)
	_action_buttons.append_array([_accept_button, _decline_button])
	_help_label = _hud_label("", 22)
	_help_label.name = "ControlsHint"
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_help_label.offset_left = -820
	_help_label.offset_right = -28
	_help_label.offset_top = -94
	_help_label.offset_bottom = -28
	_hud.add_child(_help_label)
	_build_details()
	_build_promotion()
	_build_resign_dialog()
	_refresh_input_hints()

func _build_details() -> void:
	_details = _modal_root("Details")
	var panel: PanelContainer = _modal_panel(_details, Vector2(700, 760))
	var column: VBoxContainer = _padded_column(panel)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	var title: Label = _label("棋局", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var close: Button = _button("关闭")
	close.pressed.connect(_toggle_details)
	row.add_child(close)
	var tabs: TabContainer = TabContainer.new()
	tabs.name = "DetailsTabs"
	tabs.focus_mode = Control.FOCUS_CLICK
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.gui_input.connect(_control_input)
	column.add_child(tabs)
	var game_tab: MarginContainer = MarginContainer.new()
	game_tab.name = "对局"
	tabs.add_child(game_tab)
	var game_column: VBoxContainer = _padded_column(game_tab)
	_seat_label = _label("", 22)
	game_column.add_child(_seat_label)
	_white_label = _label("", 22)
	_black_label = _label("", 22)
	for label: Label in [_white_label, _black_label]:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		game_column.add_child(label)
	_last_move_label = _label("", 21)
	game_column.add_child(_last_move_label)
	game_column.add_child(HSeparator.new())
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 16)
	game_column.add_child(action_row)
	_draw_button = _button("提议和棋")
	_draw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draw_button.pressed.connect(_offer_draw)
	action_row.add_child(_draw_button)
	_resign_button = _button("认输")
	_resign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resign_button.pressed.connect(_ask_resign)
	action_row.add_child(_resign_button)
	_claim_button = _button("申请和棋")
	_claim_button.pressed.connect(_claim_draw)
	_claim_button.visible = false
	game_column.add_child(_claim_button)
	var reset_button: Button = _button("恢复视角")
	reset_button.set_meta("view_utility", true)
	reset_button.pressed.connect(_reset_pressed)
	game_column.add_child(reset_button)
	_action_buttons.append_array([_draw_button, _resign_button, _claim_button, reset_button])
	var history_tab: MarginContainer = MarginContainer.new()
	history_tab.name = "棋谱"
	tabs.add_child(history_tab)
	var history_column: VBoxContainer = _padded_column(history_tab)
	_history_label = RichTextLabel.new()
	_history_label.name = "MoveHistory"
	_history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_label.scroll_following = true
	_history_label.selection_enabled = true
	_history_label.focus_mode = Control.FOCUS_CLICK
	_history_label.gui_input.connect(_control_input)
	_history_label.text = "对局开始后，这里显示走棋记录。"
	history_column.add_child(_history_label)
	var rules_tab: MarginContainer = MarginContainer.new()
	rules_tab.name = "规则"
	tabs.add_child(rules_tab)
	var rules_column: VBoxContainer = _padded_column(rules_tab)
	_rules_label = _label(_rules_text(), 21)
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_column.add_child(_rules_label)

func _rules_text() -> String:
	var controls: String = "选中己方棋子，再选择落点。默认亮点表示可走位置，边框表示可吃子。可在本地设置关闭落点提示。"
	var view_controls: String = "左键走棋，右键拖动旋转，滚轮缩放。复位与棋局快捷键可在本地设置修改。"
	if _mode == "xiangqi":
		return controls + "\n\n红方先行。帅将、仕士限九宫，相象不过河；马受蹩腿限制，相象受塞眼限制，炮隔一子吃子。兵卒过河后可横走，不可后退。\n\n不得让帅将照面或使己方被将军。无合法着法的一方判负，包括困毙。\n\n可提议和棋或认输。本模式不裁定复杂长将、长捉等循环争议，请双方协商和棋。\n\n" + view_controls
	return controls + "\n\n支持王车易位、吃过路兵和兵升变；被将军时必须解除将军。\n\n三次重复或五十回合可申请和棋。需要声明下一步时，点击「申请和棋」后在棋盘选择着法；再次申请可取消声明。\n\n五次重复及七十五回合自动和棋。\n\n" + view_controls

func _build_promotion() -> void:
	_promotion = _modal_root("Promotion")
	var panel: PanelContainer = _modal_panel(_promotion, Vector2(700, 300))
	var column: VBoxContainer = _padded_column(panel)
	column.add_child(_label("兵升变", 26))
	column.add_child(_label("选择新的棋子，或按 Esc 返回棋盘。", 22))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var choices: Array[int] = [5, 4, 3, 2]
	var names: Array[String] = ["后", "车", "象", "马"]
	for index: int in range(choices.size()):
		var button: Button = _button(names[index])
		button.custom_minimum_size = Vector2(140, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_promote.bind(choices[index]))
		row.add_child(button)
		_promotion_buttons.append(button)

func _build_resign_dialog() -> void:
	_confirm_resign = _modal_root("ResignConfirmation")
	var panel: PanelContainer = _modal_panel(_confirm_resign, Vector2(520, 280))
	var column: VBoxContainer = _padded_column(panel)
	column.add_child(_label("确认认输？", 26))
	column.add_child(_label("本局将结束，对方获胜。", 22))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	var cancel: Button = _button("继续对局")
	cancel.pressed.connect(_cancel_resign)
	row.add_child(cancel)
	var confirm: Button = _button("确认认输")
	confirm.pressed.connect(_confirm_resign_pressed)
	row.add_child(confirm)
	_action_buttons.append_array([cancel, confirm])

func _modal_root(node_name: String) -> Control:
	var overlay: Control = Control.new()
	overlay.name = node_name
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	overlay.gui_input.connect(_control_input)
	_hud.add_child(overlay)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.06, 0.52)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	return overlay

func _modal_panel(overlay: Control, dimensions: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -dimensions.x / 2
	panel.offset_right = dimensions.x / 2
	panel.offset_top = -dimensions.y / 2
	panel.offset_bottom = dimensions.y / 2
	overlay.add_child(panel)
	return panel

func _padded_column(parent: Control) -> VBoxContainer:
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	parent.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	return column

func _label(text_value: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _hud_label(text_value: String, font_size: int) -> Label:
	var label: Label = _label(text_value, font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.12, 0.16, 1.0))
	label.add_theme_constant_override("outline_size", 5)
	return label

func _button(text_value: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	# Tab is an authored view shortcut, not implicit focus traversal.
	button.focus_mode = Control.FOCUS_CLICK
	button.custom_minimum_size = Vector2(108, 56)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.gui_input.connect(_control_input)
	return button

func _layout_hud() -> void:
	_update_camera()

func _refresh_control_states() -> void:
	if not _ready_done:
		return
	_hud.visible = input_enabled
	_hud.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED if input_enabled else Control.MOUSE_BEHAVIOR_DISABLED
	var participant: bool = int(_presentation.get("local_side", 0)) != 0
	var active: bool = not bool(_presentation.get("finished", false))
	var can_act: bool = bool(_presentation.get("can_act", false))
	var promotion_open: bool = _promotion.visible
	for button: Button in _action_buttons:
		var utility: bool = bool(button.get_meta("view_utility", false))
		button.disabled = not input_enabled or (not utility and (not participant or not active or not can_act)) or promotion_open
	if not _local_turn():
		_draw_button.disabled = true
		_claim_button.disabled = true
	if int(_presentation.get("draw_offer", 0)) == int(_presentation.get("local_side", 0)) and int(_presentation.get("draw_offer", 0)) != 0:
		_draw_button.disabled = true
	for button: Button in _promotion_buttons:
		button.disabled = not input_enabled or not participant or not active or not can_act
	if not input_enabled:
		_hover_marker.visible = false
	if not active:
		_confirm_resign.visible = false

func _last_move_text() -> String:
	var history: Array = _presentation.get("history", [])
	if history.is_empty():
		return ""
	return "上一手  " + str(history.back())

func _format_history(history: Array) -> String:
	if history.is_empty():
		return "对局开始后，这里显示走棋记录。"
	var lines: PackedStringArray = PackedStringArray()
	for index: int in range(0, history.size(), 2):
		var line: String = "%d.   %s" % [index / 2 + 1, str(history[index])]
		if index + 1 < history.size():
			line += "      " + str(history[index + 1])
		lines.append(line)
	return "\n".join(lines)

func _offer_draw() -> void:
	if _view_input_allowed():
		_details.hide()
		draw_offered.emit()

func _accept_draw() -> void:
	if _view_input_allowed():
		draw_accepted.emit()

func _decline_draw() -> void:
	if _view_input_allowed():
		draw_declined.emit()

func _claim_draw() -> void:
	if _view_input_allowed():
		_details.hide()
		draw_claimed.emit()

func _promote(piece: int) -> void:
	if _view_input_allowed():
		promotion_selected.emit(piece)

func _ask_resign() -> void:
	if _view_input_allowed():
		_details.hide()
		_confirm_resign.visible = true
		_orbiting = false

func _cancel_resign() -> void:
	if _view_input_allowed():
		_confirm_resign.visible = false

func _confirm_resign_pressed() -> void:
	if _view_input_allowed():
		_confirm_resign.visible = false
		resign_requested.emit()

func _toggle_details() -> void:
	if _view_input_allowed():
		_details.visible = not _details.visible
		_orbiting = false
		_hover_marker.hide()

func _reset_pressed() -> void:
	if _view_input_allowed():
		_details.hide()
		reset_camera()

func _local_turn() -> bool:
	return int(_position.get("turn", 1)) == int(_presentation.get("local_side", 0))
