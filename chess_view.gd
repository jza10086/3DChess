extends Control
## Full-frame chess presentation. Rules, network authority, and menu blocking belong to game.gd.

signal square_selected(square: int)
signal promotion_selected(piece: int)
signal resign_requested()
signal draw_offered()
signal draw_accepted()
signal draw_declined()
signal draw_claimed()

const XiangqiMesh: Script = preload("xiangqi_mesh.gd")
const INK: Color = Color(0.96, 0.95, 0.91, 1.0)
const PieceScenes: Dictionary = {
	"chess": {
		-1: preload("pieces/chess_dark_1.tscn"),
		-2: preload("pieces/chess_dark_2.tscn"),
		-3: preload("pieces/chess_dark_3.tscn"),
		-4: preload("pieces/chess_dark_4.tscn"),
		-5: preload("pieces/chess_dark_5.tscn"),
		-6: preload("pieces/chess_dark_6.tscn"),
		1: preload("pieces/chess_light_1.tscn"),
		2: preload("pieces/chess_light_2.tscn"),
		3: preload("pieces/chess_light_3.tscn"),
		4: preload("pieces/chess_light_4.tscn"),
		5: preload("pieces/chess_light_5.tscn"),
		6: preload("pieces/chess_light_6.tscn"),
	},
	"xiangqi": {
		-1: preload("pieces/xiangqi_dark_1.tscn"),
		-2: preload("pieces/xiangqi_dark_2.tscn"),
		-3: preload("pieces/xiangqi_dark_3.tscn"),
		-4: preload("pieces/xiangqi_dark_4.tscn"),
		-8: preload("pieces/xiangqi_dark_cannon.tscn"),
		-6: preload("pieces/xiangqi_dark_6.tscn"),
		-7: preload("pieces/xiangqi_dark_7.tscn"),
		1: preload("pieces/xiangqi_light_1.tscn"),
		2: preload("pieces/xiangqi_light_2.tscn"),
		3: preload("pieces/xiangqi_light_3.tscn"),
		4: preload("pieces/xiangqi_light_4.tscn"),
		8: preload("pieces/xiangqi_light_cannon.tscn"),
		6: preload("pieces/xiangqi_light_6.tscn"),
		7: preload("pieces/xiangqi_light_7.tscn"),
	},
}
const BOARD_Y: float = 0.24

var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if _ready_done:
			%BoardInput.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		if not value:
			_orbiting = false
		_refresh_control_states()

@onready var board_viewport: Viewport = get_viewport()
@onready var world: Node3D = %World
@onready var camera: Camera3D = %Camera

var _mode: String = "chess"
var i18n: RefCounted
const DefaultText: Translation = preload("i18n/zh_Hans.po")
var _board_geometry: Node3D
@onready var _title_label: Label = %TitleLabel
@onready var _rules_label: Label = %RulesLabel
var _pieces: Node3D
var _markers: Node3D
var _hover_marker: MeshInstance3D
var _board_cache: Array = []
var _position: Dictionary = {}
var _presentation: Dictionary = {}
@onready var _status_label: Label = %StatusLabel
@onready var _white_label: Label = %WhiteLabel
@onready var _black_label: Label = %BlackLabel
@onready var _seat_label: Label = %SeatLabel
@onready var _last_move_label: Label = %LastMoveLabel
@onready var _resign_button: Button = %ResignButton
@onready var _draw_button: Button = %DrawButton
@onready var _claim_button: Button = %ClaimButton
@onready var _offer_bar: HBoxContainer = %OfferBar
@onready var _accept_button: Button = %AcceptButton
@onready var _decline_button: Button = %DeclineButton
@onready var _details: Control = %Details
@onready var _history_label: RichTextLabel = %HistoryLabel
@onready var _promotion: Control = %Promotion
var _promotion_buttons: Array[Button] = []
@onready var _confirm_resign: Control = %ConfirmResign
@onready var _hud: Control = %Hud
@onready var _help_label: Label = %HelpLabel
@onready var _details_button: Button = %DetailsButton
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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	%BoardInput.mouse_filter = Control.MOUSE_FILTER_STOP if input_enabled else Control.MOUSE_FILTER_IGNORE
	_pieces = world.get_node("Pieces")
	_markers = world.get_node("MoveMarkers")
	for node: Button in _hud.find_children("*", "Button", true, false):
		if node.has_meta("action_button"):
			_action_buttons.append(node)
		if node.has_meta("promotion_button"):
			_promotion_buttons.append(node)
	_select_board()
	_refresh_mode_text()
	_refresh_input_hints()
	_ready_done = true
	resized.connect(_layout_hud)
	_layout_hud()
	_update_camera()
	if not _position.is_empty():
		set_model(_position, _presentation)

## Select a room's ruleset before tree insertion, or rebuild only board geometry later.
## Lighting nodes remain stable because the protocol settings runtime owns their quality.
func configure_mode(mode: String) -> void:
	assert(mode in ["chess", "xiangqi"], "Unknown chess presentation mode")
	var changed: bool = mode != _mode
	_mode = mode
	if not _ready_done:
		_distance = 20.5 if _mode == "xiangqi" else 18.0
		return
	if changed:
		_hover_marker.hide()
		_select_board()
		_position.clear()
		_presentation.clear()
		_board_cache.clear()
		_rebuild_pieces([])
		_orient_xiangqi_labels()
		_rebuild_markers()
		_promotion.hide()
		reset_camera()
	_refresh_mode_text()

func _select_board() -> void:
	var eastern: bool = _mode == "xiangqi"
	world.get_node("XiangqiBoard").visible = eastern
	world.get_node("ChessBoard").visible = not eastern
	_board_geometry = world.get_node("XiangqiBoard" if eastern else "ChessBoard")
	_hover_marker = world.get_node("XiangqiHover" if eastern else "ChessHover")

func _refresh_mode_text() -> void:
	if not is_instance_valid(_title_label):
		return
	var red_name: String = "红方" if _mode == "xiangqi" else "白方"
	_title_label.text = "中国象棋" if _mode == "xiangqi" else "国际象棋"
	_white_label.text = _side_name(red_name, str(_presentation.get("white_name", red_name)))
	_black_label.text = _side_name("黑方", str(_presentation.get("black_name", "黑方")))
	var local_side: int = int(_presentation.get("local_side", 0))
	_seat_label.text = ("执红" if _mode == "xiangqi" else "执白") if local_side == 1 else ("执黑" if local_side == -1 else "观战")
	_white_label.add_theme_color_override("font_color", Color("eaa995") if _mode == "xiangqi" else INK)
	_rules_label.text = _rules_text()

func _side_name(side: String, player_name: String) -> String:
	var values: Dictionary = {"side": side, "player": player_name}
	return DefaultText.get_message(&"hud.seat").format(values) if i18n == null else i18n.text(&"hud.seat", values)

func _orient_xiangqi_labels() -> void:
	if _mode != "xiangqi":
		return
	for river_name: String in ["ChuRiver", "HanBorder"]:
		var river_label: Node3D = _board_geometry.get_node(river_name) as Node3D
		river_label.rotation.y = PI if _orientation_side < 0 else 0.0
		river_label.position.x = (-2.05 if river_name == "ChuRiver" else 2.05) * _orientation_side

## The model is immutable presentation input. Rebuild geometry only after board changes.
func set_model(position: Dictionary, presentation: Dictionary) -> void:
	var mode: String = str(presentation.get("mode", _mode))
	if mode != _mode:
		configure_mode(mode)
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

func _rebuild_pieces(board: Array) -> void:
	for child: Node in _pieces.get_children():
		_pieces.remove_child(child)
		child.queue_free()
	for square: int in range(mini(board.size(), _square_count())):
		var piece: int = int(board[square])
		if piece == 0:
			continue
		var shape: PackedScene = PieceScenes[_mode][piece]
		var instance: Node3D = shape.instantiate()
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

func _unshaded(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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

func _board_input(event: InputEvent) -> void:
	if _handle_view_action(event):
		get_viewport().set_input_as_handled()
		return
	if not _view_input_allowed() or _promotion.visible or _confirm_resign.visible or _details.visible:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mouse_event.pressed
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if bool(_presentation.get("can_act", false)) and _local_turn():
				var square: int = _square_at_point(mouse_event.position)
				if square >= 0:
					square_selected.emit(square)
					get_viewport().set_input_as_handled()
		elif mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_distance = clampf(_distance + (-0.7 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.7), 13.0 if _mode == "xiangqi" else 11.8, 24.0 if _mode == "xiangqi" else 21.0)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _orbiting:
			_yaw -= motion.relative.x * 0.006 * _orbit_sensitivity
			_pitch = clampf(_pitch + motion.relative.y * 0.005 * _orbit_sensitivity, 0.48, 1.30)
			_update_camera()
			get_viewport().set_input_as_handled()
		_update_hover()

func _unhandled_key_input(event: InputEvent) -> void:
	if _handle_view_action(event):
		get_viewport().set_input_as_handled()

func _control_input(event: InputEvent) -> void:
	if _handle_view_action(event):
		get_viewport().set_input_as_handled()

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

func _rules_text() -> String:
	var controls: String = "选中己方棋子，再选择落点。默认亮点表示可走位置，边框表示可吃子。可在本地设置关闭落点提示。"
	var view_controls: String = "左键走棋，右键拖动旋转，滚轮缩放。复位与棋局快捷键可在本地设置修改。"
	if _mode == "xiangqi":
		return controls + "\n\n红方先行。帅将、仕士限九宫，相象不过河；马受蹩腿限制，相象受塞眼限制，炮隔一子吃子。兵卒过河后可横走，不可后退。\n\n不得让帅将照面或使己方被将军。无合法着法的一方判负，包括困毙。\n\n可提议和棋或认输。本模式不裁定复杂长将、长捉等循环争议，请双方协商和棋。\n\n" + view_controls
	return controls + "\n\n支持王车易位、吃过路兵和兵升变；被将军时必须解除将军。\n\n三次重复或五十回合可申请和棋。需要声明下一步时，点击「申请和棋」后在棋盘选择着法；再次申请可取消声明。\n\n五次重复及七十五回合自动和棋。\n\n" + view_controls

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
