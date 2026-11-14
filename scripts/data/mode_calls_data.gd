class_name ModeCallsData
extends Resource
## Command radio and crew banter for King of the Hill (`KothData.calls`,
## data/modes/koth_calls_sv.tres) and Bot hunt (`FreeFightData.calls`,
## data/modes/free_fight_calls_sv.tres), played by `ModeRadio` through `SquadRadio`.
## Swedish voices, no subtitles (game text is English). ThunderRoad has its own
## (ThunderCallsData).

@export var volume_db: float = 0.0

@export_group("Crew banter")
## The own crew on the intercom: when the match gets going (once the own tank is there),
## and when it is won or lost.
@export var banter_volume_db: float = 2.0
@export var round_start: Array[AudioStream] = []
@export var victory: Array[AudioStream] = []
@export var defeat: Array[AudioStream] = []

@export_group("King of the Hill")
## A zone opens ("Ny anfallsorder! Framåt!").
@export var zone_open: Array[AudioStream] = []
## A zone closed; the next one shows on the map.
@export var zone_next: Array[AudioStream] = []
## More own tanks in the open zone than any other team's, or fewer, held count_hold_s;
## the same news again only after count_cooldown_s.
@export var advantage: Array[AudioStream] = []
@export var outnumbered: Array[AudioStream] = []
@export var count_hold_s: float = 4.0
@export var count_cooldown_s: float = 45.0
## The shrinking zone closes within this long (s).
@export var closing: Array[AudioStream] = []
@export var closing_at_s: float = 30.0
## A team past this share of score_to_win: own ("Lite till! Håll ut!") or the enemy's.
@export var near_win: Array[AudioStream] = []
@export var enemy_near_win: Array[AudioStream] = []
@export var near_win_share: float = 0.85

@export_group("Bot hunt")
## A wave arrives and when it is beaten.
@export var wave_new: Array[AudioStream] = []
@export var wave_cleared: Array[AudioStream] = []
## A teammate (player or bot ally) knocked out, at most every tank_lost_cooldown_s.
@export var tank_lost: Array[AudioStream] = []
@export var tank_lost_cooldown_s: float = 20.0
## The own tank is the last one of its team alive (crew, intercom).
@export var alone: Array[AudioStream] = []
