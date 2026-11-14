class_name TutorialStepData
extends Resource
## One stage of the tutorial (TutorialData.steps): a goal the game can check, the English
## instruction on screen ({action} = its key, ControlsPanel.expand) and the instructor's
## Swedish line. Stages with the same `lesson` make one lesson ("STEP 3 OF 9"); holding
## skip_tutorial_step skips the whole lesson.

enum Goal {
	DRIVE_TO,              ## reach the marker TutorialMode puts ahead
	HATCH_OPEN,
	WAIT,                  ## wait_s, then on
	HATCH_CLOSED,
	BINOCULARS_ON_TARGET,  ## binoculars up with the target in the middle
	SPOT_TARGET,           ## the target marked (Tank.spotted)
	HIT_TARGET,            ## a gun round on the target
	STOP_TARGET,           ## the heavy target's track destroyed (or it knocked out)
	SQUAD_IN_POSITION,     ## the squad sent out and holding
	MINE_LAID,             ## "Mina armerad!"
	SQUAD_MOUNTED,         ## the squad back on the tank
	SMOKE_AND_HIDE,        ## smoke fired and out of the attacker's sight
	KNOCK_OUT_ALL,         ## the final test's bots all knocked out
}

@export var lesson: int = 1
@export var title: String = ""
@export var goal: Goal = Goal.WAIT
@export_multiline var text: String = ""
## Said when the stage starts.
@export var voice: AudioStream
## Said when the stage is done ("Bra, där stannar vi.").
@export var done_voice: AudioStream
@export var wait_s: float = 0.0
