class_name Alive
extends RefCounted
## Lists that may hold freed objects (bots removed when a player joins, tanks gone with a
## respawn). A release build doesn't check a freed object when it is assigned to a typed
## variable or passed to a typed array's erase()/has(): it reads the dead object and
## crashes (the dedicated server, ThunderRoadMode._wave, 2026-11-26). So: loop over such a
## list as Variant and check is_instance_valid before typing (the loops that do), or prune
## it first with these, which never touch an element beyond its ObjectDB id.


## Removes freed objects (and nulls) from `list` in place, typed arrays included.
static func prune(list: Array) -> void:
	for i: int in range(list.size() - 1, -1, -1):
		if not is_instance_valid(list[i]):
			list.remove_at(i)


## Removes entries whose key is a freed object (or null).
static func prune_keys(dict: Dictionary) -> void:
	for key: Variant in dict.keys():
		if not is_instance_valid(key):
			dict.erase(key)
