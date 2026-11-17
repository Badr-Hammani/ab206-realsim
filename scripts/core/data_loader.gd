extends RefCounted
## Loads the aircraft data file. Values carry source + confidence (see data/bell206b3.json).

const DATA_PATH := "res://data/bell206b3.json"

static func load_aircraft(path: String = DATA_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open aircraft data: " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Aircraft data is not valid JSON: " + path)
		return {}
	return parsed
