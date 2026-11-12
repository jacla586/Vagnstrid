class_name BotRoleData
extends Resource
## How bots use a type of tank (ChassisData.bot_role -> TankData.bot_role): where they
## go relative to the zone or the front, when they go in, how far they like to fight
## and what their squad does. KothBots and ThunderRoadBots place bots by it, judging
## the moment from what the team knows (TeamSituation); BotController fights by it.
## A tank without one plays as a brawler.

enum Kind { SCOUT, BRAWLER, SNIPER, FLANKER, BREAKER, HARASSER }
## When it goes into the zone / checkpoint: always; when the team has the upper hand
## (or right after its own knock-out of an enemy); behind a brawler it follows; never
## (it watches and moves round the outside).
enum Enter { ALWAYS, ON_ADVANTAGE, WITH_LEAD, NEVER }
## Defending (holding the zone, ThunderRoad defenders): far forward on the flanks; at
## the zone's front edge; behind the zone with long sight lines; on one side behind the
## zone, a reserve that counterattacks; just behind a brawler.
enum Post { FORWARD, ZONE_FRONT, BEHIND_ZONE, FLANK_RESERVE, BEHIND_LEAD }

@export var kind: Kind = Kind.BRAWLER
@export var display_name: String = "Brawler"
## Once its team is in contact (known enemies near the objective) it plays this role
## instead (null: stays): a scout becomes a harasser when the fight starts.
@export var contact_role: BotRoleData

@export_group("Attack")
## Its approach comes in this far off the straight line from its side (deg): the team
## spreads over the map's width (alternating left and right).
@export var axis_spread_deg: float = 15.0
## Holding outside: this far out from the zone's edge (m; 0 = inside).
@export var standoff_min_m: float = 0.0
@export var standoff_max_m: float = 0.0
@export var enters: Enter = Enter.ALWAYS
## Enters too when the team must take the zone (behind, time running out).
@export var enters_on_pressure: bool = false
## Behind the brawler it follows (WITH_LEAD, BEHIND_LEAD) (m).
@export var follow_m: float = 120.0
## A new spot after holding a while in this range (s): scouts keep moving.
@export var hold_min_s: float = 15.0
@export var hold_max_s: float = 35.0
## Hunting: fires from about this far (m, TacticsData.hunt_engage_m otherwise).
@export var hunt_engage_m: float = 0.0
## Facing an enemy whose front it can't get through, it slips sideways to a new spot
## instead of trading shots (scouts).
@export var avoid_front_duels: bool = false

@export_group("Hit and run")
## Fires shots_per_visit rounds from a spot, then dashes dash_min_m..dash_max_m off to the
## side of its target (out of its sight where it can) and comes up again elsewhere;
## held there dash_hold_s before the director's orders take over again.
@export var hit_and_run: bool = false
@export var shots_per_visit: int = 2
@export var dash_min_m: float = 200.0
@export var dash_max_m: float = 400.0
@export var dash_hold_s: float = 6.0
## Against tanks it fires HE at the track facing it (slows an attack: a thrown track
## holds the tank for its repair), when it has HE.
@export var track_he: bool = false
## Harassing: comes up this far from the known enemies, off their flank (m)... It fires
## at whatever it sees at any range; this is only where it chooses to show up.
@export var harass_range_min_m: float = 300.0
@export var harass_range_max_m: float = 500.0
## ...but this share of the time closer, from harass_close_min_m up to harass_range_min_m
## (short sight lines in woods and towns; a surprise from near).
@export_range(0.0, 1.0) var harass_close_share: float = 0.25
@export var harass_close_min_m: float = 120.0

@export_group("Defence")
@export var post: Post = Post.ZONE_FRONT
## Its squad lays the mines first (ThunderRoad defenders).
@export var mines_first: bool = false

@export_group("Squad")
## Sends its squad out after standing this long (s; BotController.SQUAD_MIN_STAND_S
## otherwise) and again this much sooner after a recall (share of the cooldown).
@export var squad_stand_s: float = 6.0
@export_range(0.0, 1.0) var squad_cooldown_share: float = 1.0


## The distance it comes up at this time (harass_* above).
func pick_harass_range(rng: RandomNumberGenerator) -> float:
	if rng.randf() < harass_close_share:
		return rng.randf_range(harass_close_min_m, harass_range_min_m)
	return rng.randf_range(harass_range_min_m, harass_range_max_m)
