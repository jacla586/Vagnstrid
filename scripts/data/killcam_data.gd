class_name KillcamData
extends Resource
## Killcam timing and camera (data/ui/killcam.tres; Killcam in the player rig).

## Wait after the knock-out before the replay starts (the explosion plays out) (s).
@export var start_delay_s: float = 1.2
## The ghost round flies this fast on screen (m/s; slow motion of the real round)...
@export var replay_speed_mps: float = 320.0
## ...but the flight takes at least / at most this long (s).
@export var min_flight_s: float = 1.2
@export var max_flight_s: float = 3.2
## The camera holds on the impact this long at the end (s).
@export var hold_s: float = 1.8
## Speed assumed for the drop of the drawn path (m/s; ShellData isn't sent).
@export var assumed_shell_speed_mps: float = 600.0
## Chase camera behind and above the ghost round (m), and the end view off the impact.
@export var chase_back_m: float = 6.0
@export var chase_up_m: float = 1.2
@export var hold_distance_m: float = 7.0
