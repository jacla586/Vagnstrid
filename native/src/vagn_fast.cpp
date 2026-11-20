#include "vagn_fast.h"

#include <godot_cpp/classes/ray_cast3d.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void VagnFast::_bind_methods() {
	ClassDB::bind_method(D_METHOD("apply_suspension", "body", "rays", "com_global", "rest_length",
								 "stiffness", "damping", "points", "normals"),
			&VagnFast::apply_suspension);
}

void VagnFast::apply_suspension(RigidBody3D *body, const Array &rays, const Vector3 &com_global,
		double rest_length, double stiffness, double damping, Array points, Array normals) {
	if (body == nullptr) {
		return;
	}
	const Vector3 linear = body->get_linear_velocity();
	const Vector3 angular = body->get_angular_velocity();
	const Vector3 origin = body->get_global_position();
	const int64_t count = rays.size();
	for (int64_t i = 0; i < count; i++) {
		RayCast3D *ray = Object::cast_to<RayCast3D>(rays[i]);
		if (ray == nullptr) {
			continue;
		}
		ray->force_raycast_update();
		if (!ray->is_colliding()) {
			continue;
		}
		const Vector3 point = ray->get_collision_point();
		const Transform3D xform = ray->get_global_transform();
		const Vector3 up = xform.basis.get_column(1);
		const double compression = rest_length - xform.origin.distance_to(point);
		const Vector3 point_velocity = linear + angular.cross(point - com_global);
		const double force = stiffness * compression - damping * point_velocity.dot(up);
		body->apply_force(up * MAX(force, 0.0), point - origin);
		points.append(point);
		normals.append(ray->get_collision_normal());
	}
}
