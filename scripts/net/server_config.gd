class_name ServerConfig
extends RefCounted
## The dedicated server's settings file (`server.cfg`, ConfigFile section "server"), beside
## the log or where `--config` says. `data/server/server.tres` (ServerData) gives the
## defaults; the file overrides them and is read again before every match, so it can be
## edited (by hand or through AdminLink's `config_set`) while the server runs. Written with
## every key on first start so there is something to edit.

const SECTION: String = "server"
## Keys the file and AdminLink know, with the ServerData property each sets.
const KEYS: PackedStringArray = ["team_size", "weather", "scenarios", "result_s", "vote_s",
		"max_match_s"]


## The defaults with the file's values on top (a fresh ServerData; `defaults` untouched).
static func read(path: String, defaults: ServerData) -> ServerData:
	var out := defaults.duplicate() as ServerData
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	var values: Dictionary = {}
	for key: String in KEYS:
		if cfg.has_section_key(SECTION, key):
			values[key] = cfg.get_value(SECTION, key)
	apply(out, values)
	return out


## Sets `data` from `values` (only known keys, checked and clamped). Returns the keys it
## refused, with why.
static func apply(data: ServerData, values: Dictionary) -> Dictionary:
	var refused: Dictionary = {}
	for key: Variant in values:
		var v: Variant = values[key]
		match str(key):
			"team_size":
				data.team_size = clampi(int(v), 0, MatchSettings.MAX_TEAM_SIZE)
			"weather":
				var w: String = str(v)
				if w == Weather.RANDOM or Weather.PRESETS.has(w):
					data.weather = w
				else:
					refused[key] = "unknown weather (random, %s)" % ", ".join(Weather.PRESETS)
			"scenarios":
				var paths: PackedStringArray = []
				var bad: PackedStringArray = []
				var items: Array = v if v is Array or v is PackedStringArray \
						else str(v).split(",", false)
				for item: Variant in items:
					var p: String = scenario_path(str(item).strip_edges())
					if p == "":
						bad.append(str(item))
					elif not paths.has(p):
						paths.append(p)
				if bad.is_empty():
					data.scenarios = paths
				else:
					refused[key] = "unknown scenarios: %s" % ", ".join(bad)
			"result_s":
				data.result_s = clampf(float(v), 1.0, 600.0)
			"vote_s":
				data.vote_s = clampf(float(v), 3.0, 600.0)
			"max_match_s":
				data.max_match_s = clampf(float(v), 30.0, 86400.0)
			_:
				refused[key] = "unknown setting"
	return refused


## Writes every key of `data` to `path`.
static func write(path: String, data: ServerData) -> Error:
	var cfg := ConfigFile.new()
	var d: Dictionary = to_dict(data)
	for key: String in KEYS:
		cfg.set_value(SECTION, key, d[key])
	return cfg.save(path)


## The settings as plain values (scenarios as names, not paths).
static func to_dict(data: ServerData) -> Dictionary:
	var names: Array = []
	for p: String in data.scenarios:
		names.append(p.get_file().get_basename())
	return {"team_size": data.team_size, "weather": data.weather, "scenarios": names,
			"result_s": data.result_s, "vote_s": data.vote_s, "max_match_s": data.max_match_s}


## A scenario's res:// path from its name ("vidingsjo_koth") or path; "" if there is none.
static func scenario_path(name_or_path: String) -> String:
	if name_or_path.begins_with("res://"):
		return name_or_path if ResourceLoader.exists(name_or_path) else ""
	for p: String in MainMenu.find_maps():
		if p.get_file().get_basename() == name_or_path:
			return p
	return ""
