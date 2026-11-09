class_name EffectData
extends Resource
## A short visual effect (data/effects/*.tres): particle bursts and a fading light,
## played by EffectFx.play(). Cosmetic only: nothing in play reads it.

@export var bursts: Array[BurstData] = []
@export_group("Light")
@export var light_color: Color = Color(1.0, 0.7, 0.4)
## 0 = no light.
@export var light_energy: float = 0.0
@export var light_range_m: float = 6.0
@export var light_time_s: float = 0.15
