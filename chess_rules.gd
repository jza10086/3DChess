extends RefCounted
## Pure, deterministic orthodox chess rules. No scene, network, clock or UI state.
## Squares are a1 = 0 through h8 = 63; white pieces are positive, black negative.
## State: board:Array[int], turn, castling bitmask, en_passant (-1 absent),
## halfmove, fullmove, ply, revision, last_move, repetitions (position key/count).
## Moves: from, to, promotion (0 or positive piece kind), capture (signed piece),
## en_passant:bool, castle:bool. All public operations leave their inputs intact.
## The controller owns resignations, agreements and draw claims; outcome() reports
## automatic endings. Dead-material detection is deliberately conservative, not a
## general solver for all blocked/dead positions (FIDE 5.2.2).
## Rules reference: https://handbook.fide.com/chapter/E012023 (articles 3, 5 and 9).

const WHITE: int = 1
const BLACK: int = -1
const PAWN: int = 1
const KNIGHT: int = 2
const BISHOP: int = 3
const ROOK: int = 4
const QUEEN: int = 5
const KING: int = 6
const WHITE_KINGSIDE: int = 1
const WHITE_QUEENSIDE: int = 2
const BLACK_KINGSIDE: int = 4
const BLACK_QUEENSIDE: int = 8
const INITIAL_FEN: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const FILES: String = "abcdefgh"
const PIECE_LETTERS: String = " PNBRQK"
const KNIGHT_OFFSETS: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)]
const DIAGONALS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const STRAIGHTS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const PROMOTIONS: Array[int] = [QUEEN, ROOK, BISHOP, KNIGHT]


func initial_state() -> Dictionary:
	return from_fen(INITIAL_FEN)


## Legal movement for the side to move, optionally restricted to one origin.
## This remains available in drawn positions for analysis; controllers must use
## outcome() to stop play. Returned dictionaries include canonical move flags.
func legal_moves(state: Dictionary, from_square: int = -1) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var board: Array = state["board"]
	var side: int = int(state["turn"])
	for square: int in range(64):
		if from_square >= 0 and square != from_square:
			continue
		if int(board[square]) * side <= 0:
			continue
		for move: Dictionary in _pseudo_moves(state, square):
			var next: Dictionary = _apply_unchecked(state, move)
			if not in_check(next, side):
				moves.append(move)
	return moves


## Returns a new state, or {} for an illegal move or already finished game.
## Only from/to/promotion identify the request; caller-supplied capture/castling
## flags are ignored. Promotion must be explicit. Never mutates state or move.
func apply_move(state: Dictionary, move: Dictionary) -> Dictionary:
	if typeof(move.get("from")) != TYPE_INT or typeof(move.get("to")) != TYPE_INT or typeof(move.get("promotion", 0)) != TYPE_INT:
		return {}
	var source: int = int(move.get("from", -1))
	var target: int = int(move.get("to", -1))
	var promotion: int = int(move.get("promotion", 0))
	if source < 0 or source > 63 or target < 0 or target > 63:
		return {}
	if bool(outcome(state)["over"]):
		return {}
	for candidate: Dictionary in legal_moves(state, source):
		if int(candidate["to"]) != target or int(candidate["promotion"]) != promotion:
			continue
		var next: Dictionary = _apply_unchecked(state, candidate)
		var repetitions: Dictionary = state["repetitions"].duplicate()
		var key: String = position_key(next)
		repetitions[key] = int(repetitions.get(key, 0)) + 1
		next["repetitions"] = repetitions
		return next
	return {}


## Attacks count even when the attacking piece is pinned (FIDE 3.1.3/3.9.1).
func in_check(state: Dictionary, side: int) -> bool:
	var board: Array = state["board"]
	var king_square: int = board.find(side * KING)
	return king_square < 0 or _is_attacked(board, king_square, -side)


## over/reason/winner describe automatic endings; winner is 0 for draws.
## claimable describes claims available NOW to the side having the move.
func outcome(state: Dictionary) -> Dictionary:
	var result: Dictionary = {"over": false, "reason": "", "winner": 0, "claimable": [] as Array[String]}
	var moves: Array[Dictionary] = legal_moves(state)
	if moves.is_empty():
		result["over"] = true
		if in_check(state, int(state["turn"])):
			result["reason"] = "checkmate"
			result["winner"] = -int(state["turn"])
		else:
			result["reason"] = "stalemate"
		return result
	if _dead_material(state["board"]):
		result["reason"] = "dead_material"
	elif int(state["repetitions"].get(position_key(state), 0)) >= 5:
		result["reason"] = "fivefold_repetition"
	elif int(state["halfmove"]) >= 150:
		result["reason"] = "seventy_five_move"
	result["over"] = not String(result["reason"]).is_empty()
	if not bool(result["over"]):
		result["claimable"] = _claimable(state)
	return result


## Pre-move claims: validate an intended move without playing it, then return
## claims it would establish. Caller awards the draw to the CURRENT claimant;
## this does not transfer the right to claim or actually execute the move.
func claimable_after_move(state: Dictionary, move: Dictionary) -> Array[String]:
	var next: Dictionary = apply_move(state, move)
	if next.is_empty():
		return []
	return _claimable(next)


## Standard algebraic notation, including disambiguation, promotion and mate.
## before/move/after must describe a legal move already accepted by apply_move.
func move_label(before: Dictionary, move: Dictionary, after: Dictionary) -> String:
	var source: int = int(move["from"])
	var target: int = int(move["to"])
	var piece: int = absi(int(before["board"][source]))
	var promotion: int = int(move.get("promotion", 0))
	var capture: bool = int(before["board"][target]) != 0 or (piece == PAWN and source % 8 != target % 8)
	var label: String = ""
	if piece == KING and absi(target - source) == 2:
		label = "O-O" if target > source else "O-O-O"
	else:
		if piece != PAWN:
			label = PIECE_LETTERS.substr(piece, 1)
			var ambiguous: bool = false
			var same_file: bool = false
			var same_rank: bool = false
			for other: Dictionary in legal_moves(before):
				var origin: int = int(other["from"])
				if origin == source or int(other["to"]) != target or int(before["board"][origin]) != int(before["board"][source]):
					continue
				ambiguous = true
				same_file = same_file or origin % 8 == source % 8
				same_rank = same_rank or origin / 8 == source / 8
			if ambiguous:
				if not same_file:
					label += FILES.substr(source % 8, 1)
				elif not same_rank:
					label += str(source / 8 + 1)
				else:
					label += square_name(source)
		elif capture:
			label = FILES.substr(source % 8, 1)
		if capture:
			label += "x"
		label += square_name(target)
		if promotion != 0:
			label += "=" + PIECE_LETTERS.substr(promotion, 1)
	if in_check(after, int(after["turn"])):
		label += "#" if legal_moves(after).is_empty() else "+"
	return label


func square_name(square: int) -> String:
	if square < 0 or square > 63:
		return "-"
	return FILES.substr(square % 8, 1) + str(square / 8 + 1)


func square_index(coordinate: String) -> int:
	if coordinate.length() != 2:
		return -1
	var file: int = FILES.find(coordinate.substr(0, 1))
	var rank_text: String = coordinate.substr(1, 1)
	if file < 0 or not rank_text.is_valid_int():
		return -1
	var rank: int = rank_text.to_int() - 1
	return rank * 8 + file if rank >= 0 and rank < 8 else -1


## Parses orthodox six-field FEN. Returns {} for malformed board/fields.
## This checks structure and king counts, not full historical reachability.
## FEN cannot encode repetition history; the loaded position starts at count 1.
func from_fen(fen: String) -> Dictionary:
	var fields: PackedStringArray = fen.strip_edges().split(" ", false)
	if fields.size() != 6 or (fields[1] != "w" and fields[1] != "b"):
		return {}
	var ranks: PackedStringArray = fields[0].split("/")
	if ranks.size() != 8:
		return {}
	var board: Array[int] = []
	board.resize(64)
	board.fill(0)
	for fen_rank: int in range(8):
		var file: int = 0
		for symbol: String in ranks[fen_rank]:
			if symbol.is_valid_int():
				var empty_count: int = symbol.to_int()
				if empty_count < 1 or empty_count > 8:
					return {}
				file += empty_count
			else:
				var kind: int = PIECE_LETTERS.find(symbol.to_upper())
				if kind <= 0 or file >= 8:
					return {}
				board[(7 - fen_rank) * 8 + file] = kind * (WHITE if symbol == symbol.to_upper() else BLACK)
				file += 1
		if file != 8:
			return {}
	if board.count(KING) != 1 or board.count(-KING) != 1:
		return {}
	var castling: int = 0
	if fields[2] != "-":
		for symbol: String in fields[2]:
			var index: int = "KQkq".find(symbol)
			if index < 0 or (castling & (1 << index)) != 0:
				return {}
			castling |= 1 << index
	var en_passant: int = square_index(fields[3])
	if fields[3] != "-" and (en_passant < 0 or en_passant / 8 not in [2, 5]):
		return {}
	if not fields[4].is_valid_int() or not fields[5].is_valid_int() or fields[4].to_int() < 0 or fields[5].to_int() < 1:
		return {}
	var side: int = WHITE if fields[1] == "w" else BLACK
	if en_passant >= 0 and en_passant / 8 != (5 if side == WHITE else 2):
		return {}
	var ply: int = (fields[5].to_int() - 1) * 2 + (1 if side == BLACK else 0)
	var state: Dictionary = {"board": board, "turn": side, "castling": castling, "en_passant": en_passant, "halfmove": fields[4].to_int(), "fullmove": fields[5].to_int(), "ply": ply, "revision": 0, "last_move": {}, "repetitions": {}}
	state["repetitions"][position_key(state)] = 1
	return state


## Standard FEN preserves the raw en-passant target, even when no capture exists.
func to_fen(state: Dictionary) -> String:
	return "%s %s %s %s %d %d" % [_board_fen(state["board"]), "w" if int(state["turn"]) == WHITE else "b", _castling_text(int(state["castling"])), square_name(int(state["en_passant"])), int(state["halfmove"]), int(state["fullmove"])]


## FIDE position identity includes only LEGAL en-passant availability. In
## particular, a pinned en-passant pawn must not break a repetition sequence.
func position_key(state: Dictionary) -> String:
	var en_passant: int = int(state["en_passant"])
	var effective_en_passant: int = -1
	if en_passant >= 0:
		var board: Array = state["board"]
		var side: int = int(state["turn"])
		for file_offset: int in [-1, 1]:
			var source: int = en_passant - side * 8 + file_offset
			if source < 0 or source > 63 or absi(source % 8 - en_passant % 8) != 1 or int(board[source]) != side * PAWN:
				continue
			for move: Dictionary in _pseudo_moves(state, source):
				if bool(move["en_passant"]) and not in_check(_apply_unchecked(state, move), side):
					effective_en_passant = en_passant
	return "%s %d %d %s" % [_board_fen(state["board"]), int(state["turn"]), int(state["castling"]), square_name(effective_en_passant)]


## Analysis helper: counts legal move trees, ignoring game-ending draw rules.
func perft(state: Dictionary, depth: int) -> int:
	if depth <= 0:
		return 1
	var moves: Array[Dictionary] = legal_moves(state)
	if depth == 1:
		return moves.size()
	var nodes: int = 0
	for move: Dictionary in moves:
		nodes += perft(_apply_unchecked(state, move), depth - 1)
	return nodes


func _pseudo_moves(state: Dictionary, source: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var board: Array = state["board"]
	var piece: int = int(board[source])
	var side: int = WHITE if piece > 0 else BLACK
	var kind: int = absi(piece)
	var file: int = source % 8
	var rank: int = source / 8
	if kind == PAWN:
		var next_rank: int = rank + side
		if next_rank < 0 or next_rank > 7:
			return moves
		var forward: int = source + side * 8
		if int(board[forward]) == 0:
			_append_pawn_move(moves, source, forward, 0, false)
			var double_forward: int = source + side * 16
			if rank == (1 if side == WHITE else 6) and int(board[double_forward]) == 0:
				_append_move(moves, source, double_forward)
		for file_offset: int in [-1, 1]:
			var target_file: int = file + file_offset
			if target_file < 0 or target_file > 7:
				continue
			var target: int = next_rank * 8 + target_file
			var captured: int = int(board[target])
			if captured * side < 0 and absi(captured) != KING:
				_append_pawn_move(moves, source, target, captured, false)
			elif target == int(state["en_passant"]) and captured == 0 and int(board[target - side * 8]) == -side * PAWN:
				_append_pawn_move(moves, source, target, -side * PAWN, true)
	elif kind == KNIGHT:
		for offset: Vector2i in KNIGHT_OFFSETS:
			_append_step(moves, board, source, file + offset.x, rank + offset.y, side)
	else:
		var directions: Array[Vector2i] = []
		if kind in [BISHOP, QUEEN, KING]:
			directions.append_array(DIAGONALS)
		if kind in [ROOK, QUEEN, KING]:
			directions.append_array(STRAIGHTS)
		for offset: Vector2i in directions:
			var target_file: int = file + offset.x
			var target_rank: int = rank + offset.y
			while _inside(target_file, target_rank):
				var target: int = target_rank * 8 + target_file
				var captured: int = int(board[target])
				if captured * side > 0 or absi(captured) == KING:
					break
				_append_move(moves, source, target, captured)
				if captured != 0 or kind == KING:
					break
				target_file += offset.x
				target_rank += offset.y
		if kind == KING:
			_append_castles(moves, state, source, side)
	return moves


func _append_move(moves: Array[Dictionary], source: int, target: int, captured: int = 0, promotion: int = 0, en_passant: bool = false, castle: bool = false) -> void:
	moves.append({"from": source, "to": target, "promotion": promotion, "capture": captured, "en_passant": en_passant, "castle": castle})


func _append_pawn_move(moves: Array[Dictionary], source: int, target: int, captured: int, en_passant: bool) -> void:
	if target / 8 in [0, 7]:
		for promotion: int in PROMOTIONS:
			_append_move(moves, source, target, captured, promotion, en_passant)
	else:
		_append_move(moves, source, target, captured, 0, en_passant)


func _append_step(moves: Array[Dictionary], board: Array, source: int, file: int, rank: int, side: int) -> void:
	if not _inside(file, rank):
		return
	var target: int = rank * 8 + file
	var captured: int = int(board[target])
	if captured * side <= 0 and absi(captured) != KING:
		_append_move(moves, source, target, captured)


func _append_castles(moves: Array[Dictionary], state: Dictionary, source: int, side: int) -> void:
	var base: int = 0 if side == WHITE else 56
	var board: Array = state["board"]
	if source != base + 4 or _is_attacked(board, source, -side):
		return
	var rights: int = int(state["castling"])
	var kingside: int = WHITE_KINGSIDE if side == WHITE else BLACK_KINGSIDE
	var queenside: int = WHITE_QUEENSIDE if side == WHITE else BLACK_QUEENSIDE
	if (rights & kingside) != 0 and int(board[base + 7]) == side * ROOK and int(board[base + 5]) == 0 and int(board[base + 6]) == 0:
		if not _is_attacked(board, base + 5, -side) and not _is_attacked(board, base + 6, -side):
			_append_move(moves, source, base + 6, 0, 0, false, true)
	if (rights & queenside) != 0 and int(board[base]) == side * ROOK and int(board[base + 1]) == 0 and int(board[base + 2]) == 0 and int(board[base + 3]) == 0:
		if not _is_attacked(board, base + 3, -side) and not _is_attacked(board, base + 2, -side):
			_append_move(moves, source, base + 2, 0, 0, false, true)


## Internal movement copy intentionally does not update repetition counts.
## Legal-move generation can therefore test king safety without recursion.
func _apply_unchecked(state: Dictionary, move: Dictionary) -> Dictionary:
	var next: Dictionary = state.duplicate()
	var board: Array = state["board"].duplicate()
	var source: int = int(move["from"])
	var target: int = int(move["to"])
	var piece: int = int(board[source])
	var side: int = int(state["turn"])
	var captured: int = int(move["capture"])
	var promotion: int = int(move["promotion"])
	board[source] = 0
	board[target] = piece if promotion == 0 else side * promotion
	if bool(move["en_passant"]):
		board[target - side * 8] = 0
	if bool(move["castle"]):
		var rook_from: int = source + 3 if target > source else source - 4
		var rook_to: int = source + 1 if target > source else source - 1
		board[rook_to] = board[rook_from]
		board[rook_from] = 0
	var rights: int = int(state["castling"])
	if absi(piece) == KING:
		rights &= ~(WHITE_KINGSIDE | WHITE_QUEENSIDE) if side == WHITE else ~(BLACK_KINGSIDE | BLACK_QUEENSIDE)
	# Moving/capturing an original rook permanently removes that corner's right.
	for corner: int in [0, 7, 56, 63]:
		if source == corner or target == corner:
			var right: int = WHITE_QUEENSIDE if corner == 0 else WHITE_KINGSIDE
			if corner >= 56:
				right = BLACK_QUEENSIDE if corner == 56 else BLACK_KINGSIDE
			rights &= ~right
	next["board"] = board
	next["turn"] = -side
	next["castling"] = rights
	next["en_passant"] = (source + target) / 2 if absi(piece) == PAWN and absi(target - source) == 16 else -1
	next["halfmove"] = 0 if absi(piece) == PAWN or captured != 0 else int(state["halfmove"]) + 1
	next["fullmove"] = int(state["fullmove"]) + (1 if side == BLACK else 0)
	next["ply"] = int(state["ply"]) + 1
	next["revision"] = int(state["revision"]) + 1
	next["last_move"] = move.duplicate()
	return next


func _is_attacked(board: Array, square: int, attacker: int) -> bool:
	var file: int = square % 8
	var rank: int = square / 8
	for file_offset: int in [-1, 1]:
		var pawn_file: int = file + file_offset
		var pawn_rank: int = rank - attacker
		if _inside(pawn_file, pawn_rank) and int(board[pawn_rank * 8 + pawn_file]) == attacker * PAWN:
			return true
	for offset: Vector2i in KNIGHT_OFFSETS:
		var knight_file: int = file + offset.x
		var knight_rank: int = rank + offset.y
		if _inside(knight_file, knight_rank) and int(board[knight_rank * 8 + knight_file]) == attacker * KNIGHT:
			return true
	var directions: Array[Vector2i] = []
	directions.append_array(DIAGONALS)
	directions.append_array(STRAIGHTS)
	for direction_index: int in range(directions.size()):
		var offset: Vector2i = directions[direction_index]
		var target_file: int = file + offset.x
		var target_rank: int = rank + offset.y
		var distance: int = 1
		while _inside(target_file, target_rank):
			var piece: int = int(board[target_rank * 8 + target_file])
			if piece != 0:
				if piece * attacker > 0:
					var kind: int = absi(piece)
					if kind == QUEEN or (kind == KING and distance == 1) or (kind == BISHOP and direction_index < 4) or (kind == ROOK and direction_index >= 4):
						return true
				break
			target_file += offset.x
			target_rank += offset.y
			distance += 1
	return false


func _inside(file: int, rank: int) -> bool:
	return file >= 0 and file < 8 and rank >= 0 and rank < 8


func _claimable(state: Dictionary) -> Array[String]:
	var claims: Array[String] = []
	if int(state["repetitions"].get(position_key(state), 0)) >= 3:
		claims.append("threefold_repetition")
	if int(state["halfmove"]) >= 100:
		claims.append("fifty_move")
	return claims


## Recognises K/K, K+single minor/K, and bishop-only positions in which every
## bishop occupies the same colour complex. KNN/K and opposite-colour bishops
## are NOT dead: cooperative legal mating sequences can exist.
func _dead_material(board: Array) -> bool:
	var minors: int = 0
	var knights: int = 0
	var bishop_color: int = -1
	var mixed_bishops: bool = false
	for square: int in range(64):
		var kind: int = absi(int(board[square]))
		if kind == 0 or kind == KING:
			continue
		if kind in [PAWN, ROOK, QUEEN]:
			return false
		minors += 1
		if kind == KNIGHT:
			knights += 1
		else:
			var color: int = (square % 8 + square / 8) % 2
			if bishop_color >= 0 and color != bishop_color:
				mixed_bishops = true
			bishop_color = color
	return minors <= 1 or (knights == 0 and not mixed_bishops)


func _board_fen(board: Array) -> String:
	var ranks: PackedStringArray = []
	for rank: int in range(7, -1, -1):
		var text: String = ""
		var empty_count: int = 0
		for file: int in range(8):
			var piece: int = int(board[rank * 8 + file])
			if piece == 0:
				empty_count += 1
				continue
			if empty_count > 0:
				text += str(empty_count)
				empty_count = 0
			var letter: String = PIECE_LETTERS.substr(absi(piece), 1)
			text += letter if piece > 0 else letter.to_lower()
		if empty_count > 0:
			text += str(empty_count)
		ranks.append(text)
	return "/".join(ranks)


func _castling_text(rights: int) -> String:
	var text: String = ""
	for index: int in range(4):
		if (rights & (1 << index)) != 0:
			text += "KQkq".substr(index, 1)
	return "-" if text.is_empty() else text
