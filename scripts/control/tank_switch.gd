class_name TankSwitch
extends RefCounted
## Changing the player's tank type during a match (Esc menu). A tank can't be rebuilt
## in place (model, armour shapes, modules, squad all come from its data at start), so
## the old tank goes and a new one comes: offline a fresh PlayerRig, online NetGame
## despawns and spawns (NetGame.respawn_player). A change is a respawn: the new tank
## comes at once at the team's spawn, never where the old one was. Fresh from a spawn
## (FRESH_S, not hit yet) that's free; later it counts as a loss, like abandoning the
## tank. A knocked-out tank waits: the new type comes at the respawn (Tank.repaired).
## The choice is the garage's (TankConfigs.select), so it also sticks for the next match.

const RIG_SCENE: String = "res://scenes/player/player_rig.tscn"
## Within this long of (re)spawning and not hit yet, changing tank costs nothing (s).
## Later it counts as a loss, so a change is never a free repair or escape.
const FRESH_S: float = 60.0

## Offline: another tank was picked while the change had to wait for a respawn.
static var pending_offline: bool = false


## True if changing `tank` for another type now is free (alive, fresh, unhit).
static func is_fresh(tank: Tank) -> bool:
	return tank != null and not tank.is_knocked_out() and tank.get_hits_this_life().is_empty() \
			and tank.get_life_seconds() < FRESH_S


## The player leaves `tank` for another type now: a loss unless fresh (is_fresh).
static func count_change(tank: Tank) -> void:
	if is_fresh(tank):
		return
	if KothMode.instance != null:
		KothMode.instance.count_loss(tank)
	if ThunderRoadMode.instance != null:
		ThunderRoadMode.instance.count_loss(tank)


## True if `tank` is not of the type `cfg` (null cfg: no wish).
static func wants_other(tank: Tank, cfg: TankConfig) -> bool:
	if tank == null or cfg == null:
		return false
	return tank.config == null or tank.config.key() != cfg.key()


## Offline: where a new player tank of `tank`'s team starts now (the mode's spawn, else
## where the map's respawn puts it, else where `tank` is).
static func offline_spawn_for(tank: Tank) -> Transform3D:
	if ThunderRoadMode.instance != null:
		return ThunderRoadMode.instance.spawn_for_new(tank.team, tank)
	var mode: KothMode = KothMode.instance
	if mode != null and mode.has_started():
		return mode.get_free_spawn(tank.team, tank)
	for node: Node in tank.get_tree().current_scene.find_children("*", "", true, false):
		var respawn := node as RespawnAtStart
		if respawn != null and respawn.tank == tank:
			return respawn.get_start()
	return tank.global_transform


## Offline: replaces the player's rig (the parent of `old`) by a new one whose tank is
## built from the selected config, at `at`, on the same team. Respawn nodes follow it.
static func replace_offline(old: Tank, at: Transform3D) -> void:
	if not is_instance_valid(old) or old.is_queued_for_deletion():
		return
	var rig: Node = old.get_parent()
	var parent: Node = rig.get_parent()
	var new_rig: Node3D = (load(RIG_SCENE) as PackedScene).instantiate()
	var tank: Tank = new_rig.get_node("Tank")
	tank.team = old.team
	old.leave_wreck()
	var rig_name: StringName = rig.name
	rig.name = "%sOld" % rig_name
	new_rig.name = rig_name
	parent.add_child(new_rig)
	tank.global_transform = at
	tank.reset_physics_interpolation()
	carry_stats(old, tank)
	for node: Node in parent.get_tree().current_scene.find_children("*", "", true, false):
		var respawn := node as RespawnAtStart
		if respawn != null and respawn.tank == old:
			respawn.set_tank(tank)
	rig.queue_free()


## The game mode's stats rows (KO, losses, points) go from `from` to `to`.
static func carry_stats(from: Tank, to: Tank) -> void:
	if KothMode.instance != null:
		KothMode.instance.carry_stats(from, to)
	if ThunderRoadMode.instance != null:
		ThunderRoadMode.instance.carry_stats(from, to)
