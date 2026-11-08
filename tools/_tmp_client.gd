extends SceneTree
var t := 0.0
var seen_break := false
func _process(d: float) -> bool:
	t += d
	var m: ThunderRoadMode = ThunderRoadMode.instance
	if m == null: return false
	if not seen_break and m.is_in_break():
		seen_break = true
		print("CLIENT break, left ", snappedf(m.get_break_left(), 0.1), " round ", m.get_round())
	if seen_break and not m.is_in_break():
		print("CLIENT round ", m.get_round(), " wrecks ", get_nodes_in_group("wrecks").size())
		quit()
	if t > 110.0:
		print("CLIENT timeout"); quit()
	return false
