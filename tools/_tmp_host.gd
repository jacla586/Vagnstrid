extends SceneTree
var t := 0.0
var fired := false
func _physics_process(d: float) -> bool:
	t += d
	var g: NetGame = NetSession.instance.game if NetSession.instance else null
	if g != null and not fired and g.tanks.size() > 0 and g.teams.size() > 1 and g.tank_of_peer(g.teams.keys()[1]) != null and t > 30.0:
		fired = true
		ThunderRoadMode.instance._end_round()
		print("HOST ended round 1")
	if t > 120.0: quit()
	return false
