## Host-selected chess mode plus client-local controls and board presentation.
extends RefCounted

static func schema() -> Dictionary:
	return {
		"schema_format": 3,
		"settings_version": 1,
		"fields": {
			"mode": {
				"type": "string", "control": "select", "default": "chess",
				"values": ["chess", "xiangqi"], "labels": ["国际象棋", "中国象棋"],
				"title": "棋类模式", "description": "由房主选择，所有玩家使用同一模式；修改从下一局生效。",
				"audience": "room", "apply": "next_round"
			},
			"view.show_legal_moves": {
				"type": "bool", "control": "toggle", "default": true,
				"title": "显示合法落点", "description": "选中棋子时标出可走的位置；关闭不改变合法走棋规则。",
				"audience": "local", "apply": "immediate"
			},
			"view.orbit_sensitivity": {
				"type": "float", "control": "number", "default": 1.0,
				"min": 0.25, "max": 2.0, "step": 0.05,
				"title": "视角旋转灵敏度", "description": "调整鼠标右键拖动时的旋转速度。",
				"audience": "local", "apply": "immediate"
			},
			"input.reset_view": _binding("恢复视角", "chess_reset_view", KEY_R),
			"input.details": _binding("棋局、棋谱与规则", "chess_details", KEY_TAB),
			"input.select": _fixed("选择棋子与落点", [{"kind": "mouse", "code": MOUSE_BUTTON_LEFT}]),
			"input.orbit": _fixed("拖动旋转视角", [{"kind": "mouse", "code": MOUSE_BUTTON_RIGHT}]),
			"input.zoom": _fixed("缩放棋盘", [{"kind": "mouse", "code": MOUSE_BUTTON_WHEEL_UP}, {"kind": "mouse", "code": MOUSE_BUTTON_WHEEL_DOWN}]),
			"input.menu": _fixed("关闭浮层 / 打开菜单", [{"kind": "key", "code": KEY_ESCAPE, "physical": false}])
		},
		"layout": [
			{"id": "round", "title": "棋局规则", "expanded": true, "children": [{"field": "mode"}]},
			{"id": "board", "title": "棋盘", "expanded": true, "children": [
				{"field": "view.show_legal_moves"}, {"field": "view.orbit_sensitivity"}]},
			{"id": "controls", "title": "操作", "expanded": true, "children": [
				{"field": "input.reset_view"}, {"field": "input.details"},
				{"field": "input.select"}, {"field": "input.orbit"},
				{"field": "input.zoom"}, {"field": "input.menu"}]}
		]
	}

static func _binding(title: String, action: String, key: int) -> Dictionary:
	return {
		"type": "array", "control": "binding", "title": title, "action": action,
		"default": [{"kind": "key", "code": key, "physical": true}],
		"items": {"type": "object", "format": "binding"}, "max_items": 2,
		"combinations": true, "audience": "local", "apply": "immediate"
	}

static func _fixed(title: String, bindings: Array) -> Dictionary:
	return {
		"type": "array", "control": "binding", "title": title, "default": bindings,
		"items": {"type": "object", "format": "binding"}, "max_items": 2,
		"readonly": true, "audience": "local", "apply": "immediate"
	}
