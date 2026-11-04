extends RefCounted
## Pure, deterministic Xiangqi movement and king-safety rules, independent of UI,
## networking and clocks. Intersections are a0 = 0 through i9 = 89. Red is +1,
## starts at ranks 0–4 and moves first; black is -1 and starts at ranks 5–9.
## State: board:Array[int], turn, halfmove (plies since a capture), fullmove,
## ply, revision, last_move, repetitions. Moves: from, to, promotion:0, capture
## (signed piece). Public operations do not mutate their input state or move.
## Checkmate AND stalemate lose. Controller owns resignations and agreed draws.
## Competition repetition, perpetual-check/chase adjudication, no-capture limits
## and dead-position adjudication are intentionally not automated. Counts are
## informational only; orthodox chess draw rules must not be applied here.
## Basic rules: https://www.wxf-xiangqi.org/images/xiangqi-intro/xiangqi-introduction-for-wxf.pdf

const RED: int = 1
const BLACK: int = -1
const PAWN: int = 1
const HORSE: int = 2
const ELEPHANT: int = 3
const ROOK: int = 4
const KING: int = 6
const ADVISOR: int = 7
const CANNON: int = 8
const FILES: String = "abcdefghi"
const PIECE_LETTERS: String = " PNBR KAC"
const INITIAL_FEN: String = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"
const HORSE_OFFSETS: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)]
const DIAGONALS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const STRAIGHTS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func initial_state() -> Dictionary:
	return from_fen(INITIAL_FEN)


## Enumerates legal moves for the side to move, optionally for one intersection.
## Enemy generals are attacked for check detection, never offered as captures.
func legal_moves(state: Dictionary, from_square: int = -1) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	if from_square < -1 or from_square >= 90:
		return moves
	var board: Array = state["board"]
	var side: int = int(state["turn"])
	var first: int = 0 if from_square < 0 else from_square
	var last: int = 90 if from_square < 0 else from_square + 1
	for source: int in range(first, last):
		if int(board[source]) * side <= 0:
			continue
		for move: Dictionary in _pseudo_moves(board, source):
			if not in_check(_apply_unchecked(state, move), side):
				moves.append(move)
	return moves


## Returns an independent new state or {} for an illegal request. Only strict
## integer from/to/promotion fields identify the request; capture is recomputed.
func apply_move(state: Dictionary, move: Dictionary) -> Dictionary:
	if typeof(move.get("from")) != TYPE_INT or typeof(move.get("to")) != TYPE_INT or typeof(move.get("promotion", 0)) != TYPE_INT:
		return {}
	var source: int = int(move["from"])
	var target: int = int(move["to"])
	if source < 0 or source >= 90 or target < 0 or target >= 90 or int(move.get("promotion", 0)) != 0:
		return {}
	for candidate: Dictionary in legal_moves(state, source):
		if int(candidate["to"]) != target:
			continue
		var next: Dictionary = _apply_unchecked(state, candidate)
		var repetitions: Dictionary = state["repetitions"].duplicate()
		var key: String = position_key(next)
		repetitions[key] = int(repetitions.get(key, 0)) + 1
		next["repetitions"] = repetitions
		return next
	return {}


## Includes facing generals, horse legs and cannon screens in attack detection.
func in_check(state: Dictionary, side: int) -> bool:
	var board: Array = state["board"]
	var king_square: int = board.find(side * KING)
	return king_square < 0 or _is_attacked(board, king_square, -side)


## A side with no legal move loses even when not in check. Complex tournament
## adjudication is excluded rather than guessing a repetition or material draw.
func outcome(state: Dictionary) -> Dictionary:
	var result: Dictionary = {"over": false, "reason": "", "winner": 0, "claimable": [] as Array[String]}
	if legal_moves(state).is_empty():
		result["over"] = true
		result["reason"] = "checkmate" if in_check(state, int(state["turn"])) else "stalemate"
		result["winner"] = -int(state["turn"])
	return result


## No automatic or pre-move chess-style draw claim is supported in this mode.
func claimable_after_move(_state: Dictionary, _move: Dictionary) -> Array[String]:
	return []


## Unambiguous Chinese piece names with board coordinates, not competition WXF
## notation. before/move/after describe a legal move accepted by apply_move.
func move_label(before: Dictionary, move: Dictionary, after: Dictionary) -> String:
	var source: int = int(move["from"])
	var target: int = int(move["to"])
	var piece: int = int(before["board"][source])
	var label: String = "%s %s%s%s" % [_piece_name(piece), square_name(source), "×" if int(before["board"][target]) != 0 else "→", square_name(target)]
	var ending: Dictionary = outcome(after)
	if bool(ending["over"]):
		label += " 将死" if String(ending["reason"]) == "checkmate" else " 困毙"
	elif in_check(after, int(after["turn"])):
		label += " 将军"
	return label


func square_name(square: int) -> String:
	if square < 0 or square >= 90:
		return "-"
	return FILES.substr(square % 9, 1) + str(square / 9)


func square_index(coordinate: String) -> int:
	if coordinate.length() != 2:
		return -1
	var file: int = FILES.find(coordinate.substr(0, 1))
	var rank_text: String = coordinate.substr(1, 1)
	if file < 0 or not rank_text.is_valid_int():
		return -1
	var rank: int = rank_text.to_int()
	return rank * 9 + file if rank >= 0 and rank < 10 else -1


## Six-field Xiangqi FEN: n=horse, b=elephant, a=advisor, c=cannon, w=red.
## No castling or en-passant fields. Checks structure and king counts, not full
## historical reachability. Loading cannot restore a game's repetition history.
func from_fen(fen: String) -> Dictionary:
	var fields: PackedStringArray = fen.strip_edges().split(" ", false)
	if fields.size() != 6 or fields[1] not in ["w", "b"] or fields[2] != "-" or fields[3] != "-":
		return {}
	var ranks: PackedStringArray = fields[0].split("/")
	if ranks.size() != 10:
		return {}
	var board: Array[int] = []
	board.resize(90)
	board.fill(0)
	for fen_rank: int in range(10):
		var file: int = 0
		for symbol: String in ranks[fen_rank]:
			if symbol.is_valid_int():
				var empty_count: int = symbol.to_int()
				if empty_count < 1 or empty_count > 9:
					return {}
				file += empty_count
			else:
				var kind: int = PIECE_LETTERS.find(symbol.to_upper())
				if kind <= 0 or file >= 9:
					return {}
				board[(9 - fen_rank) * 9 + file] = kind * (RED if symbol == symbol.to_upper() else BLACK)
				file += 1
		if file != 9:
			return {}
	if board.count(KING) != 1 or board.count(-KING) != 1:
		return {}
	if not fields[4].is_valid_int() or not fields[5].is_valid_int() or fields[4].to_int() < 0 or fields[5].to_int() < 1:
		return {}
	var side: int = RED if fields[1] == "w" else BLACK
	var ply: int = (fields[5].to_int() - 1) * 2 + (1 if side == BLACK else 0)
	var state: Dictionary = {"board": board, "turn": side, "halfmove": fields[4].to_int(), "fullmove": fields[5].to_int(), "ply": ply, "revision": 0, "last_move": {}, "repetitions": {}}
	state["repetitions"][position_key(state)] = 1
	return state


func to_fen(state: Dictionary) -> String:
	return "%s %s - - %d %d" % [_board_fen(state["board"]), "w" if int(state["turn"]) == RED else "b", int(state["halfmove"]), int(state["fullmove"])]


func position_key(state: Dictionary) -> String:
	return "%s %d" % [_board_fen(state["board"]), int(state["turn"])]


## Analysis helper counting legal move trees, without tournament adjudication.
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


func _pseudo_moves(board: Array, source: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var piece: int = int(board[source])
	var side: int = RED if piece > 0 else BLACK
	var kind: int = absi(piece)
	var file: int = source % 9
	var rank: int = source / 9
	match kind:
		PAWN:
			_append_step(moves, board, source, file, rank + side, side)
			if _across_river(rank, side):
				_append_step(moves, board, source, file - 1, rank, side)
				_append_step(moves, board, source, file + 1, rank, side)
		HORSE:
			for offset: Vector2i in HORSE_OFFSETS:
				var leg_file: int = file + (signi(offset.x) if absi(offset.x) == 2 else 0)
				var leg_rank: int = rank + (signi(offset.y) if absi(offset.y) == 2 else 0)
				if _inside(leg_file, leg_rank) and int(board[leg_rank * 9 + leg_file]) == 0:
					_append_step(moves, board, source, file + offset.x, rank + offset.y, side)
		ELEPHANT:
			for offset: Vector2i in DIAGONALS:
				var target_file: int = file + offset.x * 2
				var target_rank: int = rank + offset.y * 2
				if _inside(target_file, target_rank) and not _across_river(target_rank, side) and int(board[(rank + offset.y) * 9 + file + offset.x]) == 0:
					_append_step(moves, board, source, target_file, target_rank, side)
		KING, ADVISOR:
			var directions: Array[Vector2i] = STRAIGHTS if kind == KING else DIAGONALS
			for offset: Vector2i in directions:
				if _in_palace(file + offset.x, rank + offset.y, side):
					_append_step(moves, board, source, file + offset.x, rank + offset.y, side)
		ROOK, CANNON:
			for offset: Vector2i in STRAIGHTS:
				var target_file: int = file + offset.x
				var target_rank: int = rank + offset.y
				var screened: bool = false
				while _inside(target_file, target_rank):
					var target: int = target_rank * 9 + target_file
					var captured: int = int(board[target])
					if kind == ROOK:
						_append_step(moves, board, source, target_file, target_rank, side)
						if captured != 0:
							break
					elif not screened:
						if captured == 0:
							_append_move(moves, source, target)
						else:
							screened = true
					elif captured != 0:
						if captured * side < 0 and absi(captured) != KING:
							_append_move(moves, source, target, captured)
						break
					target_file += offset.x
					target_rank += offset.y
	return moves


func _append_move(moves: Array[Dictionary], source: int, target: int, captured: int = 0) -> void:
	moves.append({"from": source, "to": target, "promotion": 0, "capture": captured})


func _append_step(moves: Array[Dictionary], board: Array, source: int, file: int, rank: int, side: int) -> void:
	if not _inside(file, rank):
		return
	var target: int = rank * 9 + file
	var captured: int = int(board[target])
	if captured * side <= 0 and absi(captured) != KING:
		_append_move(moves, source, target, captured)


## Legal-move probes do not update history; apply_move owns repetition counting.
func _apply_unchecked(state: Dictionary, move: Dictionary) -> Dictionary:
	var next: Dictionary = state.duplicate()
	var board: Array = state["board"].duplicate()
	var source: int = int(move["from"])
	var target: int = int(move["to"])
	var side: int = int(state["turn"])
	board[target] = board[source]
	board[source] = 0
	next["board"] = board
	next["turn"] = -side
	next["halfmove"] = 0 if int(move["capture"]) != 0 else int(state["halfmove"]) + 1
	next["fullmove"] = int(state["fullmove"]) + (1 if side == BLACK else 0)
	next["ply"] = int(state["ply"]) + 1
	next["revision"] = int(state["revision"]) + 1
	next["last_move"] = move.duplicate()
	return next


## Geometric attacks include immobilized pieces. A king must not move into
## their attack, and hypothetical king captures must not recurse through legality.
func _is_attacked(board: Array, target: int, attacker: int) -> bool:
	var file: int = target % 9
	var rank: int = target / 9
	for source: int in range(90):
		var piece: int = int(board[source])
		if piece * attacker <= 0:
			continue
		var source_file: int = source % 9
		var source_rank: int = source / 9
		var dx: int = file - source_file
		var dy: int = rank - source_rank
		match absi(piece):
			PAWN:
				if (dx == 0 and dy == attacker) or (dy == 0 and absi(dx) == 1 and _across_river(source_rank, attacker)):
					return true
			HORSE:
				if (absi(dx) == 2 and absi(dy) == 1) or (absi(dx) == 1 and absi(dy) == 2):
					var leg: int = source + (signi(dx) if absi(dx) == 2 else signi(dy) * 9)
					if int(board[leg]) == 0:
						return true
			ELEPHANT:
				if absi(dx) == 2 and absi(dy) == 2 and not _across_river(rank, attacker) and int(board[source + signi(dx) + signi(dy) * 9]) == 0:
					return true
			ADVISOR:
				if absi(dx) == 1 and absi(dy) == 1 and _in_palace(file, rank, attacker):
					return true
			KING:
				if (absi(dx) + absi(dy) == 1 and _in_palace(file, rank, attacker)) or (dx == 0 and _between_count(board, source, target) == 0):
					return true
			ROOK, CANNON:
				if dx == 0 or dy == 0:
					var screens: int = _between_count(board, source, target)
					if screens == (1 if absi(piece) == CANNON else 0):
						return true
	return false


## Count occupied intersections strictly between two aligned intersections.
func _between_count(board: Array, source: int, target: int) -> int:
	var step: int = signi(target - source) * (9 if source % 9 == target % 9 else 1)
	var count: int = 0
	var square: int = source + step
	while square != target:
		if int(board[square]) != 0:
			count += 1
		square += step
	return count


func _inside(file: int, rank: int) -> bool:
	return file >= 0 and file < 9 and rank >= 0 and rank < 10


func _in_palace(file: int, rank: int, side: int) -> bool:
	return file >= 3 and file <= 5 and (rank >= 0 and rank <= 2 if side == RED else rank >= 7 and rank <= 9)


func _across_river(rank: int, side: int) -> bool:
	return rank >= 5 if side == RED else rank <= 4


func _piece_name(piece: int) -> String:
	match absi(piece):
		PAWN:
			return "兵" if piece > 0 else "卒"
		HORSE:
			return "马"
		ELEPHANT:
			return "相" if piece > 0 else "象"
		ROOK:
			return "车"
		KING:
			return "帅" if piece > 0 else "将"
		ADVISOR:
			return "仕" if piece > 0 else "士"
		CANNON:
			return "炮"
	return ""


func _board_fen(board: Array) -> String:
	var ranks: PackedStringArray = []
	for rank: int in range(9, -1, -1):
		var text: String = ""
		var empty_count: int = 0
		for file: int in range(9):
			var piece: int = int(board[rank * 9 + file])
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
