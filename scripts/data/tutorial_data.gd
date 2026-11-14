class_name TutorialData
extends Resource
## The tutorial (TutorialMode, data/modes/tutorial.tres): its stages in order and the
## rules for placing marks, targets and bots round the player.

@export var steps: Array[TutorialStepData] = []

@export_group("Voice")
@export var welcome: AudioStream
## "Okej, vi hoppar vidare." after a skip.
@export var skip: AudioStream
## "Du kör som min svärmor. Försök igen." when the tank is knocked out or overturned.
@export var restart: AudioStream
## The instructor's "Hörru, Rally-Kalle, lugna ner dig lite!": in the tutorial in place of the
## crew's crash lines (SquadRadio).
@export var crash: AudioStream
## "Kort! Höj siktet ett streck..." when a round at the gunnery target lands short.
@export var short_hint: AudioStream
@export var short_hint_text: String = "SHORT! RAISE THE SIGHT ONE MARK ON THE RANGE SCALE"
## "Långt! Sänk siktet ett streck." when one lands beyond it.
@export var long_hint: AudioStream
@export var long_hint_text: String = "LONG! LOWER THE SIGHT ONE MARK"
## (Gunnery hints share this cooldown.)
@export var short_hint_cooldown_s: float = 8.0
## "Öppna luckan först..." for binoculars asked for with the hatch shut.
@export var hatch_first_hint: AudioStream
@export var hatch_first_text: String = "OPEN THE HATCH FIRST: BINOCULARS NEED AN OPEN HATCH"
## "Den studsar!..." for an AP round at the heavy target.
@export var bounce_hint: AudioStream
@export var bounce_text: String = "IT BOUNCES! LOAD HE AND AIM AT THE TRACK"
## "En nere, en kvar!" when the final test is down to one.
@export var one_left: AudioStream
@export var one_left_text: String = "ONE DOWN, ONE TO GO"
@export var hint_cooldown_s: float = 8.0
@export var volume_db: float = -2.0

@export_group("Flow")
## Hold skip_tutorial_step this long to skip a lesson (never by accident).
@export var skip_hold_s: float = 3.0
## Pause after a stage is done before the next starts (the tick shows).
@export var done_pause_s: float = 2.5
## Knocked out or overturned: back where it last stood upright after this.
@export var respawn_s: float = 5.0
@export var overturned_s: float = 2.5

@export_group("Placing")
## Where the player's tank starts (Vector3.ZERO: where the map's PlayerRig stands) and the
## way it faces (degrees, 0 = north/-z, turning left). Picked where long sight lines open
## ahead (Vidingsjö: a survey of open ground and sight from the commander's eye).
@export var start_position: Vector3 = Vector3.ZERO
@export var start_yaw_deg: float = 0.0
@export var marker_distance_m: float = 90.0
@export var marker_radius_m: float = 15.0
## The first target (binoculars, spotting, gunnery): stands still, in sight, cover preferred.
@export var target_min_m: float = 300.0
@export var target_max_m: float = 450.0
## Half angle round the tank's front where things are placed.
@export var cone_deg: float = 55.0
## The target must be within this of the binoculars' middle, held binocular_hold_s.
@export var binocular_aim_deg: float = 5.0
@export var binocular_hold_s: float = 0.8
@export var target_config: TankConfig
## The ammunition lesson's target: heavy (AP hardly bites), stands still.
@export var heavy_config: TankConfig
@export var heavy_min_m: float = 180.0
@export var heavy_max_m: float = 280.0
## The smoke lesson's attacker (a bot that fires) and how long out of its sight counts.
@export var attacker_min_m: float = 450.0
@export var attacker_max_m: float = 600.0
@export var hide_hold_s: float = 2.0
## ...and backed (or driven) this far from where the lesson started.
@export var retreat_m: float = 20.0
## The final test.
@export var final_count: int = 2
@export var final_min_m: float = 600.0
@export var final_max_m: float = 850.0
## Final bots drive towards the player this often (0: never, they hold their area), to this far from it.
@export var hunt_every_s: float = 15.0
@export var hunt_close_m: float = 250.0
@export var bot_crew: BotData
@export var bot_configs: Array[TankConfig] = []

@export_group("End")
@export var end_title: String = "TRAINING COMPLETE"
@export_multiline var end_text: String = ""
## "Bot hunt" on the end screen.
@export var next_scenario: String = "res://scenes/scenarios/vidingsjo_free.tscn"
