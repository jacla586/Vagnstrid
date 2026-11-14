class_name ThunderCallsData
extends Resource
## ThunderRoad's command radio ("Ledning"), no subtitles (ThunderPanel shows what happens in
## English instead): calls to the own team when a checkpoint is
## taken or lost, during and after the ceasefire, when the clock runs short and when the
## own tank leaves its corridor. Played by `ThunderPanel` through `SquadRadio`.

@export var volume_db: float = 0.0
## Mid-ceasefire call to the attackers when this share of the pause is left.
@export var regroup_call_share: float = 0.5
## Clock calls at these seconds left (attack and defend lists in the same order).
@export var clock_call_s: PackedFloat32Array = PackedFloat32Array([120.0, 60.0])
## "Return to your positions" again only after this long.
@export var return_cooldown_s: float = 20.0

## Rare extras (humour): instead of the plain call, at this chance.
@export var lost_rare: AudioStream
@export var lost_rare_chance: float = 0.08
@export var return_rare: AudioStream
@export var return_rare_chance: float = 0.15
## "Systemet stänger klockan tre!" instead of the attackers' last clock call.
@export var attack_clock_last_rare: AudioStream
@export var attack_clock_last_rare_chance: float = 0.25

@export_group("Crew banter")
## The own crew on the intercom: one picked at random when a round starts (once the own
## tank may move), and when the match is won or lost.
@export var banter_volume_db: float = 2.0
@export var round_start: Array[AudioStream] = []
@export var victory: Array[AudioStream] = []
@export var defeat: Array[AudioStream] = []

@export_group("Attackers")
## A checkpoint taken, more to come.
@export var taken: AudioStream
## The last checkpoint taken.
@export var secured: AudioStream
## Mid-ceasefire.
@export var regrouping: AudioStream
@export var attack_clock: Array[AudioStream] = []
## Fighting retreat (retreat_instead_of_pause): instead of `taken`, one of these ("Tryck på!").
@export var advance: Array[AudioStream] = []
## This long after a capture, if defenders are left behind: "Städa bort eftersläntrarna!".
@export var stragglers: Array[AudioStream] = []
@export var stragglers_delay_s: float = 4.0
## The next checkpoint opens.
@export var next_open: Array[AudioStream] = []

@export_group("Defenders")
@export var lost: AudioStream
## "Fall tillbaka till ÅSA <n>!": one per checkpoint number (1-based: [0] is ÅSA 1); the
## text takes the number.
@export var fall_back: Array[AudioStream] = []
## The ceasefire / retreat is over: `enemy_coming` or one of `enemy_coming_more`.
@export var enemy_coming: AudioStream
@export var enemy_coming_more: Array[AudioStream] = []
## A teammate left behind was knocked out: "Vi har förlorat en vagn!".
@export var tank_lost: AudioStream
@export var tank_lost_cooldown_s: float = 15.0
## The round ended with the attackers short: the line held.
@export var held: AudioStream
@export var defend_clock: Array[AudioStream] = []

@export_group("Left behind (crew)")
## The own tank left behind after a capture (ThunderRoadMode.is_left_behind), on the intercom:
## when it starts, at `left_behind_late_s` left, and when it gets back past the line.
@export var left_behind: Array[AudioStream] = []
@export var left_behind_late: AudioStream
@export var left_behind_late_s: float = 10.0
@export var made_it_back: Array[AudioStream] = []

@export_group("Both")
## The own tank outside its corridor.
@export var return_to_lines: AudioStream
