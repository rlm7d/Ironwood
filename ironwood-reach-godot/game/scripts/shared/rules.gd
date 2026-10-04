extends RefCounted

## These values define a bounded battlefield approval trial, not final game balance.
const BUILD_ID := "battlefield-006"
const PROTOCOL := 1
const TICK_RATE := 20
const MAP_BOUNDS := {"min_x": -26.0, "max_x": 26.0, "min_z": -19.0, "max_z": 19.0}
const ROLES := ["Builder", "General"]
const SOCKETS := [
	{"id": 0, "x": -13.0, "z": 7.0, "territory": 0},
	{"id": 1, "x": -10.0, "z": 0.0, "territory": 0},
	{"id": 2, "x": -10.0, "z": -10.0, "territory": 0},
	{"id": 3, "x": -20.0, "z": -12.0, "territory": 0},
	{"id": 4, "x": 0.0, "z": 10.0, "territory": 1},
	{"id": 5, "x": 0.0, "z": -10.0, "territory": 1},
	{"id": 6, "x": 11.0, "z": 10.0, "territory": 2},
	{"id": 7, "x": 11.0, "z": -10.0, "territory": 2}
]
const TERRITORIES := [
	{"id": 0, "name": "Home grove", "x": -18.0, "z": 0.0, "secured": true, "remaining": 450},
	{"id": 1, "name": "River crossing", "x": 0.0, "z": 0.0, "secured": false, "remaining": 600},
	{"id": 2, "name": "Eastern ridge", "x": 15.0, "z": 0.0, "secured": false, "remaining": 600}
]
const ABILITY_NAMES := {"Builder": ["Mending", "Tower overcharge"], "General": ["Forced march", "Shield wall"]}

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/tuning.json"))
		assert(parsed is Dictionary, "Missing or invalid authoritative trial tuning")
		_data = parsed
	return _data

static func socket_by_id(id: int) -> Dictionary:
	for item in SOCKETS:
		if item.id == id:
			return item.duplicate(true)
	return {}
