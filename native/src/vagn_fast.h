#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

// Hot loops moved out of GDScript. Each method mirrors a GDScript function that stays
// as the fallback; keep them in step (the GDScript names are in the comments).
class VagnFast : public Object {
	GDCLASS(VagnFast, Object)

protected:
	static void _bind_methods();

public:
	// Tank._apply_suspension: casts each RayCast3D (force_raycast_update) and pushes
	// the body up with a spring-damper where it hits; appends the hit points and normals.
	void apply_suspension(RigidBody3D *body, const Array &rays, const Vector3 &com_global,
			double rest_length, double stiffness, double damping, Array points, Array normals);
};

} // namespace godot
