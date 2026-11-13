extends Control

## Host-authoritative chess. Only this package owns moves, seat selection and round scores.
## The protocol supplies preparation/results; the parent receives one final result afterwards.
const Rules: Script = preload("chess_rules.gd")
const XiangqiRules: Script = preload("xiangqi_rules.gd")
const ACTION_TOPIC: StringName = &"chess/action"
const STATE_TOPIC: StringName = &"chess/state"
enum Phase { PREPARING, RUNNING, SETTLING, STOPPED }

var api: PartyAPI
var mode: String = "chess"
var request: Dictionary
var phase: Phase = Phase.PREPARING
var board_state: Dictionary = {}
var local_side: int = 0
var sides: Array[String] = []
var _rules: RefCounted = Rules.new()
@export var pages: CanvasLayer
var _version: int = 0
var _published_version: int = -1
var _published_ply: int = 0
var _history: Array[String] = []
var _selected: int = -1
var _promotion_move: Dictionary = {}
var _claim_mode: bool = false
var _claim_moves: Array[Dictionary] = []
var _claimable: Array = []
var _pending: bool = false
var _draw_offer: int = 0
var _offered_on_ply: Dictionary = {}
var _notice: String = ""
var _last_blocked: bool = true
@onready var _view: Control = $ChessView

func party_setup(context: PartyAPI, config: Dictionary) -> void:
	api = context
	request = config.duplicate(true)
	mode = str(api.get_settings().get("mode", "chess"))
	if mode not in ["chess", "xiangqi"]:
		api.fail("chess_mode", "未知棋类模式。")
		return
	_rules = XiangqiRules.new() if mode == "xiangqi" else Rules.new()
	get_node("ChessView").i18n = api.i18n
	get_node("ChessView").configure_mode(mode)

func _ready() -> void:
	board_state = _rules.initial_state()
	_view.square_selected.connect(_select_square)
	_view.promotion_selected.connect(_promote)
	_view.resign_requested.connect(func() -> void: _send_action("resign"))
	_view.draw_offered.connect(func() -> void: _send_action("offer_draw"))
	_view.draw_accepted.connect(func() -> void: _send_action("accept_draw"))
	_view.draw_declined.connect(func() -> void: _send_action("decline_draw"))
	_view.draw_claimed.connect(_claim_draw)
	if api == null:
		_view.set_model(board_state, {"status": "请从 GodotParty 房间开始对局", "can_act": false})
		_view.input_enabled = false
		return
	var players: Array[Dictionary] = api.get_players()
	if players.size() < 2:
		api.fail("chess_players", "棋局需要至少两位玩家。")
		return
	for player: Dictionary in players:
		sides.append(player.player_id)
	sides.sort()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = api.get_seed()
	# A parent may select two participants. An ordinary larger round chooses two seats;
	# remaining participants watch and are explicitly unranked, never treated as opponents.
	for index: int in range(sides.size() - 1, 0, -1):
		var other: int = random.randi_range(0, index)
		var swap: String = sides[index]
		sides[index] = sides[other]
		sides[other] = swap
	sides.resize(2)
	for player: Dictionary in players:
		if player.is_local:
			local_side = _side_for_id(player.player_id)
	_view.configure_input(api.input)
	api.config.effective_changed.connect(_preferences_changed)
	_preferences_changed(PackedStringArray(), PackedStringArray())
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)
	_refresh()
	assert(pages != null, "Assign ProtocolPages in the game scene")
	var error: Error = pages.prepare(self, api, request, _begin_play)
	if error != OK:
		api.fail("chess_prepare", error_string(error))
		return
	_update_briefing()

func _update_briefing() -> void:
	if not is_instance_valid(pages) or not is_instance_valid(pages.briefing):
		return
	var briefing_script: Script = pages.briefing.get_script()
	var content: Dictionary = briefing_script.read_content(scene_file_path.get_base_dir().path_join("manifest.json"), api)
	content.title = "中国象棋" if mode == "xiangqi" else "国际象棋"
	if mode == "xiangqi":
		content.introduction = "红方先行。车走直线，马走日且不能蹩腿，相象走田且不能塞眼、不能过河，炮隔一子吃子，兵卒过河后可横走。将帅与仕士不能离开九宫，将帅不能照面。被将死或无合法着法的一方输棋。长将、长捉及无吃子回合不自动裁决，可提议和棋或认输。胜1分，和棋各0.5分。"
		content.cover = load(scene_file_path.get_base_dir().path_join("assets/xiangqi_cover.svg")) as Texture2D
	else:
		content.introduction = "白方先行，将死对方国王获胜。支持王车易位、吃过路兵与四种升变。三次重复或五十回合可申请和棋，五次重复、七十五回合、逼和及常见子力不足自动和棋。胜1分，和棋各0.5分。"
	content.controls = [
		{"binding": "鼠标左键", "description": "选择棋子，再选择合法落点"},
		{"binding": "鼠标右键 / 滚轮", "description": "旋转视角 / 缩放棋盘"},
		{"binding": api.input.binding_text(&"chess_reset_view") + " / " + api.input.binding_text(&"chess_details") + " / Esc", "description": "恢复视角 / 棋局与规则 / 菜单"}]
	pages.briefing.update_content(content)

func _preferences_changed(_common_keys: PackedStringArray, _own_keys: PackedStringArray) -> void:
	_view.apply_preferences(bool(api.config.get_own(&"view.show_legal_moves", true)), float(api.config.get_own(&"view.orbit_sensitivity", 1.0)))
	_update_briefing()

func party_start() -> void:
	if is_instance_valid(pages):
		pages.transport_started()

func godot_party_graphics_targets() -> Dictionary:
	return _view.graphics_targets() if is_instance_valid(_view) else {}

func _begin_play() -> void:
	if phase != Phase.PREPARING:
		return
	phase = Phase.RUNNING
	if api.is_host():
		_publish()
	_refresh()
	_players_changed()

func _process(_delta: float) -> void:
	if api == null or phase != Phase.RUNNING:
		return
	var blocked: bool = api.input.input_blocked
	_view.input_enabled = not blocked
	if blocked != _last_blocked:
		_last_blocked = blocked
		_refresh()

func _side_for_id(player_id: String) -> int:
	var index: int = sides.find(player_id)
	return 1 if index == 0 else (-1 if index == 1 else 0)

func _sender_side(sender: Dictionary) -> int:
	for player: Dictionary in api.get_players():
		if player.connected and player.peer_id == sender.get("peer_id") and player.player_id in sender.get("player_ids", []):
			return _side_for_id(player.player_id)
	return 0

func _can_act() -> bool:
	return api != null and phase == Phase.RUNNING and local_side != 0 and not _pending and not api.input.input_blocked

func _select_square(square: int) -> void:
	if not _can_act() or local_side != int(board_state.turn) or not _promotion_move.is_empty():
		return
	_notice = ""
	if _selected >= 0:
		for move: Dictionary in _rules.legal_moves(board_state, _selected):
			if int(move.to) != square:
				continue
			if int(move.promotion) != 0:
				_promotion_move = {"from": _selected, "to": square}
				_view.show_promotion(true)
				return
			_play_or_claim(move)
			return
	_selected = square if square >= 0 and square < board_state.board.size() and int(board_state.board[square]) * local_side > 0 else -1
	_refresh()

func _promote(piece: int) -> void:
	if not _can_act() or _promotion_move.is_empty():
		return
	if piece == 0:
		_promotion_move.clear()
		_selected = -1
		_view.show_promotion(false)
		_refresh()
		return
	if piece not in [2, 3, 4, 5]:
		return
	var move: Dictionary = _promotion_move.duplicate()
	move.promotion = piece
	_promotion_move.clear()
	_view.show_promotion(false)
	_play_or_claim(move)

func _play_or_claim(move: Dictionary) -> void:
	var logical_move: Dictionary = {"from": move.from, "to": move.to, "promotion": move.get("promotion", 0)}
	if _claim_mode:
		if _rules.claimable_after_move(board_state, logical_move).is_empty():
			_notice = "这步不能申请和棋，请选择其他着法。"
			_refresh()
			return
		_send_action("claim_draw", {"move": logical_move})
	else:
		_send_action("move", logical_move)

func _claim_draw() -> void:
	if mode != "chess" or not _can_act() or local_side != int(board_state.turn):
		return
	if _claim_mode:
		_claim_mode = false
		_notice = ""
		_selected = -1
		_refresh()
		return
	if not _claimable.is_empty():
		_send_action("claim_draw")
	elif not _claim_moves.is_empty():
		_claim_mode = true
		_selected = -1
		_notice = "选择将形成三次重复或五十回合的着法，申请和棋。"
		_refresh()

## Only logical actions cross the network. Host derives identity from authenticated sender data.
func _send_action(kind: String, data: Dictionary = {}) -> void:
	if not _can_act():
		return
	_pending = true
	var error: Error = api.net.send_to_host(ACTION_TOPIC, {"session": api.session_id,
		"scope": api.scope_id, "revision": _version, "kind": kind, "data": data})
	if error != OK:
		_pending = false
		api.fail("chess_send", error_string(error))
	_refresh()

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if phase == Phase.STOPPED or not payload is Dictionary:
		return
	if payload.get("session") != api.session_id or payload.get("scope") != api.scope_id:
		return
	if topic == &"chess/rejected" and sender.get("peer_id") == 1:
		_pending = false
		_notice = "操作未被接受，请根据当前棋局重新选择。"
		_refresh()
		return
	if topic == STATE_TOPIC:
		if api.is_host() or sender.get("peer_id") != 1 or not payload.get("revision") is int or payload.revision < _version:
			return
		if payload.get("kind") == "initial":
			if not _valid_snapshot(payload):
				return
			board_state = payload.position.duplicate(true)
			_history.assign(payload.history)
		elif payload.get("kind") == "change":
			if payload.revision <= _version or payload.get("draw_offer") not in [-1, 0, 1] or not payload.get("finished") is bool:
				return
			if payload.has("move"):
				if not payload.move is Dictionary or not _valid_move(payload.move):
					return
				var next: Dictionary = _rules.apply_move(board_state, payload.move)
				if next.is_empty():
					api.fail("chess_move_order", "收到无法应用于当前棋局的着法")
					return
				_history.append(_rules.move_label(board_state, payload.move, next))
				board_state = next
		else:
			return
		_version = payload.revision
		_draw_offer = int(payload.draw_offer)
		if payload.finished:
			phase = Phase.SETTLING
			_view.input_enabled = false
		_reset_selection()
		_refresh()
	elif topic == ACTION_TOPIC and api.is_host() and phase == Phase.RUNNING:
		var side: int = _sender_side(sender)
		if side == 0 or not payload.get("revision") is int or not payload.get("kind") is String or not payload.get("data") is Dictionary:
			return
		if payload.revision != _version:
			_reject_action(sender.peer_id)
			return
		var previous: int = _version
		_accept_action(side, payload.kind, payload.data)
		if _version == previous:
			_reject_action(sender.peer_id)

func _valid_snapshot(value: Dictionary) -> bool:
	if value.get("variant") != mode:
		return false
	if not value.get("revision") is int or value.revision < _version or not value.get("position") is Dictionary:
		return false
	var state: Dictionary = value.position
	if not state.get("board") is Array or state.board.size() != (90 if mode == "xiangqi" else 64) or state.get("turn") not in [1, -1]:
		return false
	for piece: Variant in state.board:
		if not piece is int or absi(piece) not in ([0, 1, 2, 3, 4, 6, 7, 8] if mode == "xiangqi" else [0, 1, 2, 3, 4, 5, 6]):
			return false
	var counters: Array[String] = ["halfmove", "fullmove", "ply", "revision"]
	if mode == "chess":
		counters.append_array(["castling", "en_passant"])
	for key: String in counters:
		if not state.get(key) is int:
			return false
	if not state.get("repetitions") is Dictionary or not state.get("last_move") is Dictionary:
		return false
	if not value.get("history") is Array or value.get("draw_offer") not in [-1, 0, 1] or not value.get("finished") is bool:
		return false
	for entry: Variant in value.history:
		if not entry is String:
			return false
	return true

func _accept_action(side: int, kind: String, data: Dictionary) -> void:
	match kind:
		"move":
			if side == int(board_state.turn) and _valid_move(data):
				var next: Dictionary = _rules.apply_move(board_state, data)
				if not next.is_empty():
					_history.append(_rules.move_label(board_state, data, next))
					board_state = next
					if _draw_offer == -side:
						_draw_offer = 0
					_version += 1
					var result: Dictionary = _rules.outcome(board_state)
					if result.over:
						_finish_game(int(result.winner), result.reason)
						return
		"resign":
			# In orthodox chess a bare king cannot win; Xiangqi resignation always loses.
			var can_mate: bool = mode == "xiangqi"
			for piece: int in board_state.board:
				if piece * -side > 0 and absi(piece) != 6:
					can_mate = true
			_finish_game(-side if can_mate else 0, "resignation")
			return
		"offer_draw":
			if side == int(board_state.turn) and _draw_offer == 0 and _offered_on_ply.get(side, -1) != int(board_state.ply):
				_draw_offer = side
				_offered_on_ply[side] = int(board_state.ply)
				_version += 1
		"accept_draw":
			if _draw_offer == -side:
				_finish_game(0, "agreement")
				return
		"decline_draw":
			if _draw_offer == -side:
				_draw_offer = 0
				_version += 1
		"claim_draw":
			if mode == "chess" and side == int(board_state.turn):
				var claims: Array = _rules.outcome(board_state).claimable
				if data.has("move") and data.move is Dictionary and _valid_move(data.move):
					claims = _rules.claimable_after_move(board_state, data.move)
				if not claims.is_empty():
					_finish_game(0, str(claims[0]))
					return
	_reset_selection()
	_publish()

func _valid_move(move: Dictionary) -> bool:
	return move.get("from") is int and move.get("to") is int and move.get("promotion", 0) is int \
		and move.from >= 0 and move.from < board_state.board.size() and move.to >= 0 and move.to < board_state.board.size() \
		and move.get("promotion", 0) in ([0] if mode == "xiangqi" else [0, 2, 3, 4, 5])

func _publish() -> Error:
	_pending = false
	if _published_version == _version:
		_refresh()
		return OK
	var message: Dictionary = {"session": api.session_id, "scope": api.scope_id, "revision": _version,
		"variant": mode, "draw_offer": _draw_offer, "finished": phase == Phase.SETTLING}
	if _published_version < 0:
		message["kind"] = "initial"
		message["position"] = board_state
		message["history"] = _history
	else:
		message["kind"] = "change"
		if board_state.ply != _published_ply:
			message["move"] = board_state.last_move
	var error: Error = api.net.broadcast(STATE_TOPIC, message, MultiplayerPeer.TRANSFER_MODE_RELIABLE, false)
	if error != OK:
		party_stop(&"chess_state")
		api.fail("chess_state", error_string(error))
		return error
	_published_version = _version
	_published_ply = board_state.ply
	_refresh()
	return OK

func _reject_action(peer: int) -> void:
	var error: Error = api.net.send_to_peer(peer, &"chess/rejected", {"session": api.session_id, "scope": api.scope_id})
	if error != OK:
		api.fail("chess_rejection", error_string(error))

func _reset_selection() -> void:
	_pending = false
	_selected = -1
	_claim_mode = false
	_promotion_move.clear()
	_notice = ""
	_view.show_promotion(false)

func _players_changed() -> void:
	if phase != Phase.RUNNING:
		return
	if api.is_host():
		var connected: Array[int] = []
		for player: Dictionary in api.get_players():
			var side: int = _side_for_id(player.player_id)
			if side != 0 and player.connected:
				connected.append(side)
		if connected.size() < 2:
			_finish_game(connected[0] if connected.size() == 1 else 0, "disconnect")
			return
	_refresh()

func _finish_game(winner: int, reason: String) -> void:
	if phase != Phase.RUNNING or not api.is_host():
		return
	phase = Phase.SETTLING
	_version += 1
	_view.input_enabled = false
	var rows: Array[Dictionary] = []
	for player: Dictionary in api.get_players():
		var side: int = _side_for_id(player.player_id)
		var ranked: bool = player.connected and side != 0
		var rank: int = (1 if winner == 0 or winner == side else 2) if ranked else 0
		var score: float = (0.5 if winner == 0 else (1.0 if winner == side else 0.0)) if ranked else 0.0
		rows.append({"player_id": player.player_id, "rank": rank,
			"status": ("completed" if ranked else "unranked") if player.connected else "withdrawn",
			"metrics": {"score": score}})
	var result: Dictionary = {"request_id": request.request_id, "reason": "completed", "rankings": rows,
		"columns": [{"key": "score", "title": "本轮分数", "format": "decimal"}],
		"game_data": {"variant": mode, "outcome": reason, "winner": winner, "moves": _history, "fen": _rules.to_fen(board_state)}}
	var error: Error = _publish()
	if error != OK:
		return
	error = pages.present(result)
	if error != OK:
		api.fail("chess_result", error_string(error))

func _refresh() -> void:
	if not is_node_ready() or board_state.is_empty():
		return
	var white_name: String = "红方" if mode == "xiangqi" else "白方"
	var black_name: String = "黑方"
	if api != null:
		for player: Dictionary in api.get_players():
			if _side_for_id(player.player_id) == 1:
				white_name = player.name
			elif _side_for_id(player.player_id) == -1:
				black_name = player.name
	var check_square: int = -1
	var turn: int = int(board_state.turn)
	var checked: bool = _rules.in_check(board_state, turn)
	if checked:
		check_square = board_state.board.find(6 * turn)
	var targets: Array[int] = []
	if _selected >= 0:
		for move: Dictionary in _rules.legal_moves(board_state, _selected):
			if int(move.to) not in targets:
				targets.append(int(move.to))
	var outcome: Dictionary = _rules.outcome(board_state)
	_claimable = outcome.claimable
	_claim_moves.clear()
	var may_repeat: bool = int(board_state.halfmove) >= 99
	for count: Variant in board_state.repetitions.values():
		if int(count) >= 2:
			may_repeat = true
	if mode == "chess" and may_repeat and turn == local_side:
		for move: Dictionary in _rules.legal_moves(board_state):
			if not _rules.claimable_after_move(board_state, move).is_empty():
				_claim_moves.append(move)
	var status: String = (("红方行棋" if mode == "xiangqi" else "白方行棋") if turn == 1 else "黑方行棋") + (" · 将军" if checked else "")
	if local_side == 0:
		status += " · 观战"
	elif turn == local_side:
		status += " · 轮到你了"
	if phase == Phase.SETTLING:
		status = "本局结束"
	elif not _notice.is_empty():
		status = _notice
	var previous: Dictionary = board_state.get("last_move", {})
	_view.set_model(board_state, {"mode": mode, "white_name": white_name, "black_name": black_name, "local_side": local_side,
		"selected": _selected, "targets": targets, "last_from": int(previous.get("from", -1)),
		"last_to": int(previous.get("to", -1)), "check_square": check_square, "status": status,
		"history": _history, "can_act": _can_act(), "draw_offer": _draw_offer,
		"finished": phase != Phase.RUNNING,
		"claim_mode": _claim_mode,
		"claimable": not _claimable.is_empty() or not _claim_moves.is_empty()})

func party_stop(_reason: StringName) -> void:
	if phase == Phase.STOPPED:
		return
	phase = Phase.STOPPED
	if is_instance_valid(pages):
		pages.stop()
	if api != null:
		if api.config.effective_changed.is_connected(_preferences_changed):
			api.config.effective_changed.disconnect(_preferences_changed)
		if api.net.message_received.is_connected(_message):
			api.net.message_received.disconnect(_message)
		if api.players_changed.is_connected(_players_changed):
			api.players_changed.disconnect(_players_changed)
	if is_instance_valid(_view):
		_view.input_enabled = false
	set_process(false)
