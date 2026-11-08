class_name FieldTreePhysics
extends RefCounted
## Physics for the laser trees of a TreeField, made directly in the PhysicsServer3D
## (hundreds of thousands of trees: nodes would be far too heavy).
##
## Per chunk one static body with a cylinder per trunk (layer 1 "world": stops tanks
## and shells) and one area with a cylinder per crown (layer 5 "vision_blocker":
## blocks sight only). Cylinder shapes are shared between trees of about the same size.
## Bodies and areas report the TreeField as their collider, so ray hits reach
## TreeField.on_shell_hit() and Vision/Explosion compare colliders as usual.
## Shape index i in a chunk's body and area belongs to tree (chunk first + i).

const LAYER_WORLD: int = 1
## Shared shapes are rounded to these steps (m).
const TRUNK_RADIUS_STEP: float = 0.025
const TRUNK_HEIGHT_STEP: float = 1.0
const CANOPY_RADIUS_STEP: float = 0.25
const CANOPY_HEIGHT_STEP: float = 0.5
const MIN_CANOPY_RADIUS: float = 0.5
const MIN_CANOPY_HEIGHT: float = 1.0

var _bodies: Array[RID] = []
var _areas: Array[RID] = []
var _shapes: Dictionary = {}  # Vector2(radius, height) -> cylinder shape RID
## Canopy shape transform (chunk space) per tree, for tipping it over when felled.
var _canopy_transforms: Array[Transform3D] = []


## Builds trunks and crowns for all trees. `chunk_origins` are global chunk transforms;
## tree positions are relative to their chunk centre.
func build(space: RID, owner_id: int, chunk_origins: Array[Transform3D],
		chunk_first: PackedInt32Array, chunk_count: PackedInt32Array,
		positions: PackedVector3Array, heights: PackedFloat32Array,
		crown_radii: PackedFloat32Array, trunk_diameters: PackedFloat32Array,
		species: Array[FieldTreeData], types: PackedByteArray) -> void:
	_canopy_transforms.resize(positions.size())
	for c: int in chunk_origins.size():
		# A chunk holds one type; bushes (no trunk) only get the sight-blocking crowns.
		var trunks: bool = chunk_count[c] > 0 and species[types[chunk_first[c]]].has_trunk
		var body: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, chunk_origins[c])
		var area: RID = PhysicsServer3D.area_create()
		PhysicsServer3D.area_set_transform(area, chunk_origins[c])
		for i: int in range(chunk_first[c], chunk_first[c] + chunk_count[c]):
			var data: FieldTreeData = species[types[i]]
			var h: float = heights[i]
			var p: Vector3 = positions[i]
			var trunk_h: float = maxf(snappedf(h * data.trunk_height_fraction, TRUNK_HEIGHT_STEP),
					TRUNK_HEIGHT_STEP)
			var trunk_r: float = maxf(snappedf(trunk_diameters[i] * 0.5, TRUNK_RADIUS_STEP),
					TRUNK_RADIUS_STEP)
			if trunks:
				PhysicsServer3D.body_add_shape(body, _shape(trunk_r, trunk_h),
						Transform3D(Basis(), p + Vector3(0.0, trunk_h * 0.5, 0.0)))
			var canopy_h: float = maxf(snappedf(h * (1.0 - data.crown_base_fraction),
					CANOPY_HEIGHT_STEP), MIN_CANOPY_HEIGHT)
			var canopy_r: float = maxf(snappedf(crown_radii[i] * data.canopy_radius_factor,
					CANOPY_RADIUS_STEP), MIN_CANOPY_RADIUS)
			var canopy := Transform3D(Basis(), p + Vector3(0.0, h - canopy_h * 0.5, 0.0))
			_canopy_transforms[i] = canopy
			PhysicsServer3D.area_add_shape(area, _shape(canopy_r, canopy_h), canopy)
		PhysicsServer3D.body_set_collision_layer(body, LAYER_WORLD)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		PhysicsServer3D.body_attach_object_instance_id(body, owner_id)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.area_set_collision_layer(area, Vision.LAYER_VISION_BLOCKER)
		PhysicsServer3D.area_set_collision_mask(area, 0)
		PhysicsServer3D.area_set_monitorable(area, false)
		PhysicsServer3D.area_attach_object_instance_id(area, owner_id)
		PhysicsServer3D.area_set_space(area, space)
		_bodies.append(body)
		_areas.append(area)


## Removes a felled tree's trunk collider.
func disable_trunk(chunk: int, shape_index: int) -> void:
	PhysicsServer3D.body_set_shape_disabled(_bodies[chunk], shape_index, true)


## Tips the crown over around the tree's foot (`foot` in chunk space).
func tip_canopy(chunk: int, shape_index: int, tree: int, foot: Vector3, tilt: Basis) -> void:
	var upright: Transform3D = _canopy_transforms[tree]
	var tipped := Transform3D(tilt, foot + tilt * (upright.origin - foot))
	PhysicsServer3D.area_set_shape_transform(_areas[chunk], shape_index, tipped)


## A felled tree stands again: trunk collider back on, crown upright.
func restore(chunk: int, shape_index: int, tree: int) -> void:
	PhysicsServer3D.body_set_shape_disabled(_bodies[chunk], shape_index, false)
	PhysicsServer3D.area_set_shape_transform(_areas[chunk], shape_index, _canopy_transforms[tree])


func free_all() -> void:
	for rid: RID in _bodies:
		PhysicsServer3D.free_rid(rid)
	for rid: RID in _areas:
		PhysicsServer3D.free_rid(rid)
	for rid: RID in _shapes.values():
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()
	_areas.clear()
	_shapes.clear()


func _shape(radius: float, height: float) -> RID:
	var key := Vector2(radius, height)
	if not _shapes.has(key):
		var shape: RID = PhysicsServer3D.cylinder_shape_create()
		PhysicsServer3D.shape_set_data(shape, {"radius": radius, "height": height})
		_shapes[key] = shape
	return _shapes[key]
