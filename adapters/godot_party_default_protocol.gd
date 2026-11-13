extends RefCounted

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"dependencies": {}}

## Chess publishes ordinary round ranks, not resource stakes or parent rewards.

func check_request(request: Dictionary) -> Dictionary:
	if request.get("mode") != "standard":
		return {"ok": false, "code": "chess_standard_only", "message": "国际象棋仅支持普通排名局。"}
	return {"ok": true}

func make_config(request: Dictionary) -> Dictionary:
	return request.duplicate(true)

func map_result(result: Dictionary, _request: Dictionary) -> Dictionary:
	return result.duplicate(true)
