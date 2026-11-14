class_name SettingsData
extends Resource
## The player's settings menu (SettingsPanel, GameSettings; data/ui/settings.tres):
## defaults, ranges and the graphics presets. Nothing here changes what bots see or
## what hides a tank: only how the picture is drawn (fog, trees and the far
## vegetation stay as they are on every level, so a low level never sees more).

@export_group("Controls")
## Mouse look speed: a factor on every camera's own sensitivity.
@export var mouse_factor_default: float = 1.0
@export var mouse_factor_min: float = 0.25
@export var mouse_factor_max: float = 3.0

@export_group("Sound")
## Volumes in percent: everything, effects (guns, engines, the world), voices (radio, crew).
@export var volume_default: float = 100.0

@export_group("Graphics presets")
## Preset names, low to high; each array below has one value per preset.
@export var preset_names: PackedStringArray = ["Low", "Medium", "High"]
@export var preset_default: int = 2
## 3D resolution share (FSR 1 upscaling below 1).
@export var preset_render_scale: PackedFloat32Array = [0.67, 0.85, 1.0]
## Index into shadow_names / shadow_distances_m.
@export var preset_shadows: PackedInt32Array = [1, 2, 3]
@export var preset_ssao: Array[bool] = [false, true, true]
@export var preset_glow: Array[bool] = [false, true, true]
## Index into aa_names.
@export var preset_aa: PackedInt32Array = [1, 1, 2]
## Index into grass_names / grass_factors.
@export var preset_grass: PackedInt32Array = [0, 1, 2]
## Index into detail_names / detail_lod_thresholds.
@export var preset_detail: PackedInt32Array = [0, 1, 1]

@export_group("Graphics choices")
## Sun shadows: off or out to this far (m), with this shadow map size (px).
@export var shadow_names: PackedStringArray = ["Off", "Near", "Normal", "Far"]
@export var shadow_distances_m: PackedFloat32Array = [0.0, 220.0, 450.0, 700.0]
@export var shadow_atlas_px: PackedInt32Array = [2048, 2048, 4096, 4096]
## Anti-aliasing: none, FXAA, TAA, MSAA 2x, MSAA 4x.
@export var aa_names: PackedStringArray = ["Off", "FXAA", "TAA", "MSAA 2x", "MSAA 4x"]
## Grass blades out to this share of GroundCoverSetData.blade_range_m (the far
## vegetation, which hides men lying in a field, follows, so it never shows more).
@export var grass_names: PackedStringArray = ["Short", "Normal", "Long"]
@export var grass_factors: PackedFloat32Array = [0.6, 1.0, 1.4]
## Mesh detail: Godot's mesh LOD threshold (pixels of error; higher = simpler meshes).
@export var detail_names: PackedStringArray = ["Low", "Normal", "High"]
@export var detail_lod_thresholds: PackedFloat32Array = [2.5, 1.0, 0.5]

@export_group("Display")
@export var window_names: PackedStringArray = ["Windowed", "Fullscreen", "Exclusive fullscreen"]
## Frame rate caps (0 = none).
@export var fps_caps: PackedInt32Array = [0, 30, 60, 90, 120, 144]
@export var fps_cap_default: int = 0
