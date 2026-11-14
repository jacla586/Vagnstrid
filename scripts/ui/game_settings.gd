class_name GameSettings
extends RefCounted
## The player's settings (SettingsPanel): controls, sound, graphics, display; kept in
## user://settings.cfg (sections "input", "audio", "video") beside MatchSettings.
## NetSession applies them at start; the panel on every change. Readers: the cameras
## (mouse_factor, invert_y), WeatherView (shadows, SSAO, glow; it watches `version`),
## GroundCover (grass_factor, at map load). Defaults and presets: SettingsData.

const SETTINGS_PATH: String = "user://settings.cfg"
const DATA_PATH: String = "res://data/ui/settings.tres"
const EFFECTS_BUS: StringName = &"Effects"
const VOICE_BUS: StringName = &"Voice"
## The graphics preset when the player changed a single graphics setting.
const CUSTOM: int = -1

## Bumped on every change, so watchers know to apply again.
static var version: int = 0

static var mouse_factor: float = 1.0
static var invert_y: bool = false
static var volume_master: float = 100.0
static var volume_effects: float = 100.0
static var volume_voice: float = 100.0
static var preset: int = 2
static var render_scale: float = 1.0
static var shadows: int = 2
static var ssao: bool = true
static var glow: bool = true
static var aa: int = 2
static var grass: int = 1
static var detail: int = 1
static var window_mode: int = 0
static var vsync: bool = true
static var fps_cap: int = 0

static var _data: SettingsData
static var _loaded: bool = false


static func data() -> SettingsData:
	if _data == null:
		_data = load(DATA_PATH) as SettingsData
	return _data


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var d: SettingsData = data()
	mouse_factor = d.mouse_factor_default
	volume_master = d.volume_default
	volume_effects = d.volume_default
	volume_voice = d.volume_default
	fps_cap = d.fps_cap_default
	set_preset_values(d.preset_default)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	mouse_factor = clampf(float(cfg.get_value("input", "mouse_factor", mouse_factor)),
			d.mouse_factor_min, d.mouse_factor_max)
	invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	volume_master = clampf(float(cfg.get_value("audio", "master", volume_master)), 0.0, 100.0)
	volume_effects = clampf(float(cfg.get_value("audio", "effects", volume_effects)), 0.0, 100.0)
	volume_voice = clampf(float(cfg.get_value("audio", "voice", volume_voice)), 0.0, 100.0)
	preset = int(cfg.get_value("video", "preset", preset))
	render_scale = clampf(float(cfg.get_value("video", "render_scale", render_scale)), 0.5, 1.0)
	shadows = clampi(int(cfg.get_value("video", "shadows", shadows)), 0, d.shadow_names.size() - 1)
	ssao = bool(cfg.get_value("video", "ssao", ssao))
	glow = bool(cfg.get_value("video", "glow", glow))
	aa = clampi(int(cfg.get_value("video", "aa", aa)), 0, d.aa_names.size() - 1)
	grass = clampi(int(cfg.get_value("video", "grass", grass)), 0, d.grass_names.size() - 1)
	detail = clampi(int(cfg.get_value("video", "detail", detail)), 0, d.detail_names.size() - 1)
	window_mode = clampi(int(cfg.get_value("video", "window", window_mode)), 0, d.window_names.size() - 1)
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	fps_cap = maxi(int(cfg.get_value("video", "fps_cap", fps_cap)), 0)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # keep MatchSettings' section
	cfg.set_value("input", "mouse_factor", mouse_factor)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("audio", "master", volume_master)
	cfg.set_value("audio", "effects", volume_effects)
	cfg.set_value("audio", "voice", volume_voice)
	cfg.set_value("video", "preset", preset)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "shadows", shadows)
	cfg.set_value("video", "ssao", ssao)
	cfg.set_value("video", "glow", glow)
	cfg.set_value("video", "aa", aa)
	cfg.set_value("video", "grass", grass)
	cfg.set_value("video", "detail", detail)
	cfg.set_value("video", "window", window_mode)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_cap", fps_cap)
	cfg.save(SETTINGS_PATH)


## The graphics values of preset `i` (no saving or applying).
static func set_preset_values(i: int) -> void:
	var d: SettingsData = data()
	i = clampi(i, 0, d.preset_names.size() - 1)
	preset = i
	render_scale = d.preset_render_scale[i]
	shadows = d.preset_shadows[i]
	ssao = d.preset_ssao[i]
	glow = d.preset_glow[i]
	aa = d.preset_aa[i]
	grass = d.preset_grass[i]
	detail = d.preset_detail[i]


## After a change: save, apply to the window, viewport and buses, tell the watchers.
static func changed(tree: SceneTree) -> void:
	save_settings()
	apply_all(tree)


static func apply_all(tree: SceneTree) -> void:
	load_settings()
	_apply_display()
	_apply_viewport(tree.root)
	_apply_audio()
	version += 1


static func shadow_distance_m() -> float:
	load_settings()
	return data().shadow_distances_m[shadows]


static func grass_factor() -> float:
	load_settings()
	return data().grass_factors[grass]


## Mouse motion as the cameras take it: the factor, and y flipped if wanted.
static func look(relative: Vector2) -> Vector2:
	load_settings()
	return Vector2(relative.x, -relative.y if invert_y else relative.y) * mouse_factor


static func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_WINDOWED
	if window_mode == 1:
		want = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif window_mode == 2:
		want = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var now: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	var windowed_now: bool = now != DisplayServer.WINDOW_MODE_FULLSCREEN \
			and now != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if not (want == DisplayServer.WINDOW_MODE_WINDOWED and windowed_now) and now != want:
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap


static func _apply_viewport(vp: Viewport) -> void:
	var d: SettingsData = data()
	vp.scaling_3d_scale = render_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.999 \
			else Viewport.SCALING_3D_MODE_BILINEAR
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == 2
	vp.msaa_3d = Viewport.MSAA_2X if aa == 3 else (Viewport.MSAA_4X if aa == 4 else Viewport.MSAA_DISABLED)
	vp.mesh_lod_threshold = d.detail_lod_thresholds[detail]
	RenderingServer.directional_shadow_atlas_set_size(d.shadow_atlas_px[shadows], true)


static func _apply_audio() -> void:
	_set_bus(&"Master", volume_master)
	_set_bus(EFFECTS_BUS, volume_effects)
	_set_bus(VOICE_BUS, volume_voice)


static func _set_bus(bus_name: StringName, percent: float) -> void:
	var i: int = AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, percent <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(percent, 0.01) / 100.0))
