class_name ModuleLayoutData
extends Resource
## Where a tank type's modules sit. Shared by tank types with the same body; the
## tank builder will make one per design.

@export var modules: Array[ModuleData] = []
