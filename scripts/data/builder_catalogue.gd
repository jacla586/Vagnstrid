class_name BuilderCatalogue
extends Resource
## Everything the garage can build from (data/builder/catalogue.tres).

@export var chassis: Array[ChassisData] = []
@export var rules: BuilderRules


func find_chassis(id: StringName) -> ChassisData:
	for c: ChassisData in chassis:
		if c.id == id:
			return c
	return null
