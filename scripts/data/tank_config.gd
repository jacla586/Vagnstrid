class_name TankConfig
extends Resource
## A tank built in the garage: which parts (ids from the builder catalogue), nothing
## else. TankBuilder turns it into TankData; the network sends it as a Dictionary.

@export var display_name: String = "My tank"
@export var chassis: StringName = &"medium"
@export var gun: StringName = &"gun_75"
@export var armour: StringName = &"standard"
@export var camo: bool = false


func to_dict() -> Dictionary:
	return {"n": display_name, "c": String(chassis), "g": String(gun), "a": String(armour), "k": camo}


static func from_dict(d: Dictionary) -> TankConfig:
	var c := TankConfig.new()
	c.display_name = d.get("n", "Tank")
	c.chassis = StringName(d.get("c", "medium"))
	c.gun = StringName(d.get("g", "gun_75"))
	c.armour = StringName(d.get("a", "standard"))
	c.camo = bool(d.get("k", false))
	return c


## A short key for caching built TankData.
func key() -> String:
	return "%s/%s/%s/%s" % [chassis, gun, armour, camo]
