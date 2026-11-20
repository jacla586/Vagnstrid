#include "vagn_fast.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/ray_cast3d.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

using namespace godot;

void VagnFast::_bind_methods() {
	ClassDB::bind_method(D_METHOD("apply_suspension", "body", "rays", "com_global", "rest_length",
								 "stiffness", "damping", "points", "normals"),
			&VagnFast::apply_suspension);
	ClassDB::bind_method(D_METHOD("apply_track_forces", "body", "left_force", "right_force", "forward",
								 "up", "com_global", "left_points", "left_normals", "right_points",
								 "right_normals"),
			&VagnFast::apply_track_forces);
}

void VagnFast::apply_track_forces(RigidBody3D *body, double left_force, double right_force,
		const Vector3 &forward, const Vector3 &up, const Vector3 &com_global,
		const Array &left_points, const Array &left_normals,
		const Array &right_points, const Array &right_normals) {
	if (body == nullptr) {
		return;
	}
	const Vector3 origin = body->get_global_position();
	Vector3 total_force;
	Vector3 total_torque;
	_track_force(left_force, forward, up, com_global, origin, left_points, left_normals, total_force, total_torque);
	_track_force(right_force, forward, up, com_global, origin, right_points, right_normals, total_force, total_torque);
	if (total_force != Vector3() || total_torque != Vector3()) {
		body->apply_central_force(total_force);
		body->apply_torque(total_torque);
	}
}

void VagnFast::_track_force(double force, const Vector3 &forward, const Vector3 &up,
		const Vector3 &com_global, const Vector3 &origin, const Array &points,
		const Array &normals, Vector3 &total_force, Vector3 &total_torque) {
	const int64_t n = points.size();
	if (n == 0) {
		return;
	}
	const double per_wheel = force / double(n);
	for (int64_t i = 0; i < n; i++) {
		const Vector3 point = points[i];
		const Vector3 normal = normals[i];
		const Vector3 direction = (forward - normal * forward.dot(normal)).normalized();
		const Vector3 at = point + up * (com_global - point).dot(up);
		const Vector3 push = direction * per_wheel;
		total_force += push;
		total_torque += (at - origin).cross(push);
	}
}

void VagnFast::apply_suspension(RigidBody3D *body, const Array &rays, const Vector3 &com_global,
		double rest_length, double stiffness, double damping, Array points, Array normals) {
	if (body == nullptr) {
		return;
	}
	_prepare_suspension(body);
	const auto pose = _suspension_pose.find(body->get_instance_id());
	const bool batched = pose != _suspension_pose.end() && pose->value == body->get_global_transform();
	const Vector3 linear = body->get_linear_velocity();
	const Vector3 angular = body->get_angular_velocity();
	const Vector3 origin = body->get_global_position();
	const int64_t count = rays.size();
	// The springs' forces summed: one central force and one torque for the body
	// (apply_force(f, r) is the force f plus the torque r x f).
	Vector3 total_force;
	Vector3 total_torque;
	for (int64_t i = 0; i < count; i++) {
		RayCast3D *ray = Object::cast_to<RayCast3D>(rays[i]);
		if (ray == nullptr) {
			continue;
		}
		bool hit;
		Vector3 point;
		Vector3 normal;
		const auto found = batched ? _suspension_index.find(ray->get_instance_id()) : _suspension_index.end();
		if (found != _suspension_index.end()) {
			const SuspensionRay &r = _suspension_rays[found->value];
			hit = r.hit;
			point = r.point;
			normal = r.normal;
		} else {
			ray->force_raycast_update();
			hit = ray->is_colliding();
			point = ray->get_collision_point();
			normal = ray->get_collision_normal();
		}
		if (!hit) {
			continue;
		}
		const Transform3D xform = ray->get_global_transform();
		const Vector3 up = xform.basis.get_column(1);
		const double compression = rest_length - xform.origin.distance_to(point);
		const Vector3 point_velocity = linear + angular.cross(point - com_global);
		const double force = stiffness * compression - damping * point_velocity.dot(up);
		const Vector3 push = up * MAX(force, 0.0);
		total_force += push;
		total_torque += (point - origin).cross(push);
		points.append(point);
		normals.append(normal);
	}
	if (total_force != Vector3()) {
		body->apply_central_force(total_force);
		body->apply_torque(total_torque);
	}
}

void VagnFast::_prepare_suspension(RigidBody3D *any_tank) {
	const uint64_t tick = Engine::get_singleton()->get_physics_frames();
	if (tick == _suspension_tick) {
		return;
	}
	_suspension_tick = tick;
	_suspension_rays.clear();
	_suspension_index.clear();
	_suspension_pose.clear();
	_suspension_space = any_tank->get_world_3d()->get_direct_space_state();
	const TypedArray<Node> tanks = any_tank->get_tree()->get_nodes_in_group("tanks");
	for (int64_t t = 0; t < tanks.size(); t++) {
		RigidBody3D *tank = Object::cast_to<RigidBody3D>(tanks[t]);
		if (tank == nullptr || !tank->is_inside_tree() || !tank->is_physics_processing()
				|| tank->is_freeze_enabled() || bool(tank->get("net_puppet"))) {
			continue;
		}
		Node *suspension = tank->get_node_or_null(NodePath("Suspension"));
		if (suspension == nullptr) {
			continue;
		}
		_suspension_pose.insert(tank->get_instance_id(), tank->get_global_transform());
		const RID exclude = tank->get_rid();
		const int64_t children = suspension->get_child_count();
		for (int64_t i = 0; i < children; i++) {
			RayCast3D *ray = Object::cast_to<RayCast3D>(suspension->get_child(i));
			if (ray == nullptr) {
				continue;
			}
			SuspensionRay r;
			r.from = ray->get_global_position();
			r.to = ray->to_global(ray->get_target_position());
			r.mask = ray->get_collision_mask();
			r.exclude = exclude;
			_suspension_index.insert(ray->get_instance_id(), int64_t(_suspension_rays.size()));
			_suspension_rays.push_back(r);
		}
	}
	const int64_t n = int64_t(_suspension_rays.size());
	if (n < 24) {
		for (int64_t i = 0; i < n; i++) {
			_cast_suspension_ray(i);
		}
		return;
	}
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	const int64_t task = pool->add_group_task(callable_mp(this, &VagnFast::_cast_suspension_ray), n, -1,
			true, "suspension rays");
	pool->wait_for_group_task_completion(task);
}

void VagnFast::_cast_suspension_ray(int64_t index) {
	SuspensionRay &r = _suspension_rays[index];
	TypedArray<RID> exclude;
	exclude.append(r.exclude);
	Ref<PhysicsRayQueryParameters3D> query = PhysicsRayQueryParameters3D::create(r.from, r.to, r.mask, exclude);
	const Dictionary hit = _suspension_space->intersect_ray(query);
	if (hit.is_empty()) {
		r.hit = false;
		return;
	}
	r.hit = true;
	r.point = hit["position"];
	r.normal = hit["normal"];
}
