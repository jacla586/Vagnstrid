class_name RadioData
extends Resource
## The squad's radio calls to its own tank (data/squads/radio_sv.tres): what is said
## (subtitle) and the recordings. Contacts give a clock direction from the tank's hull
## (12 = straight ahead): `armour[h - 1]`, `infantry[h - 1]`.

@export var under_attack: AudioStream
@export var under_attack_text: String = "Vi är under anfall!"
@export var returning: AudioStream
@export var returning_text: String = "Återvänder till vagnen."
@export var in_position: AudioStream
@export var in_position_text: String = "I position."
## Twelve recordings each, one per clock hour (1..12).
@export var armour: Array[AudioStream] = []
@export var armour_text: String = "Pansar, klockan %s!"
@export var infantry: Array[AudioStream] = []
@export var infantry_text: String = "Fientliga skyttar, klockan %s!"
@export var clock_words: PackedStringArray = ["ett", "två", "tre", "fyra", "fem", "sex",
		"sju", "åtta", "nio", "tio", "elva", "tolv"]
@export var volume_db: float = 0.0
## The same kind of call isn't repeated within this long (s); contacts count per clock hour.
@export var repeat_cooldown_s: float = 10.0
## Calls waiting while one plays; older ones are dropped beyond this.
@export var max_queue: int = 2
## How long the subtitle stays after the call (s).
@export var subtitle_extra_s: float = 1.5
