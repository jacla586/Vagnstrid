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
	ClassDB::bind_method(D_METHOD("prefetch_sight", "tank", "args"), &VagnFast::prefetch_sight);
}

bool VagnFast::_in_sector(const Vector3 &eye, const Vector3 &point, bool open, double turret_yaw,
		double half_angle) {
	if (open) {
		return true;
	}
	const Vector3 flat(point.x - eye.x, 0.0, point.z - eye.z);
	const Vector3 turret_forward(Math::sin(turret_yaw) * -1.0, 0.0, -Math::cos(turret_yaw));
	return flat.angle_to(turret_forward) <= half_angle;
}

Dictionary VagnFast::prefetch_sight(Node3D *tank, const Dictionary &args) {
	Dictionary out;
	if (tank == nullptr) {
		return out;
	}
	const Vector3 eye = args["eye"];
	const double full = args["full_range"];
	const bool open = args["open"];
	const double turret_yaw = args["turret_yaw"];
	const double half_angle = args["half_angle"];
	const Array exclude = args["exclude"];
	_sight_exclude.clear();
	for (int64_t i = 0; i < exclude.size(); i++) {
		_sight_exclude.append(RID(exclude[i]));
	}
	const Variant target = args["target"];
	const Dictionary look_wait = args["look_wait"];
	const double near2 = args["near2_m"];
	const double far4 = args["far4_m"];
	const double tank_range = args["tank_range"];
	const Variant squad_target = args["squad_target"];
	const Dictionary squad_look_wait = args["squad_look_wait"];
	const double squad_range = args["squad_range"];
	const double squad_every2 = args["squad_every2_m"];
	const Vector3 here = tank->get_global_position();
	const int64_t team = tank->get("team");
	_sight_rays.clear();
	_sight_space = tank->get_world_3d()->get_direct_space_state();
	auto want = [&](const Vector3 &point, Object *collider) {
		if (collider == nullptr || eye.distance_to(point) > full
				|| !_in_sector(eye, point, open, turret_yaw, half_angle)) {
			return;
		}
		SightRay r;
		r.from = eye;
		r.to = point;
		r.target = collider->get_instance_id();
		_sight_rays.push_back(r);
	};
	SceneTree *tree = tank->get_tree();
	const TypedArray<Node> tanks = tree->get_nodes_in_group("tanks");
	for (int64_t i = 0; i < tanks.size(); i++) {
		Node3D *other = Object::cast_to<Node3D>(tanks[i]);
		if (other == nullptr || !bool(tank->call("is_enemy_of", other)) || bool(other->call("is_knocked_out"))) {
			continue;
		}
		const Variant key = other;
		const double d = here.distance_to(other->get_global_position());
		const int64_t per_look = d > far4 ? 4 : (d > near2 ? 2 : 1);
		if (key != target && int64_t(look_wait.get(key, 0)) + 1 < per_look) {
			continue;
		}
		if (eye.distance_to(other->get_global_position()) > tank_range) {
			continue;
		}
		const Array points = other->call("get_spot_points");
		for (int64_t k = 0; k < points.size(); k++) {
			want(other->to_global(points[k]), other);
		}
		if (bool(other->call("is_commander_exposed"))) {
			want(other->call("get_commander_hitbox_position"), Object::cast_to<Object>(other->call("get_commander_hitbox")));
		}
	}
	const TypedArray<Node> squads = tree->get_nodes_in_group("squads");
	for (int64_t i = 0; i < squads.size(); i++) {
		Node3D *enemy = Object::cast_to<Node3D>(squads[i]);
		if (enemy == nullptr || !bool(enemy->call("is_out")) || int64_t(enemy->call("get_team")) == team) {
			continue;
		}
		const double d = here.distance_to(enemy->get_global_position());
		if (d > squad_range) {
			continue;
		}
		const Variant key = enemy;
		if (key != squad_target && d > squad_every2 && int64_t(squad_look_wait.get(key, 0)) + 1 < 2) {
			continue;
		}
		const Array hitboxes = enemy->call("get_hitboxes");
		for (int64_t k = 0; k < hitboxes.size(); k++) {
			Object *hb = hitboxes[k];
			if (hb != nullptr && bool(enemy->call("is_soldier_exposed", hb->get("index")))) {
				want(hb->call("get_aim_point"), hb);
			}
		}
	}
	const int64_t n = int64_t(_sight_rays.size());
	if (n == 0) {
		return out;
	}
	if (n < 24) {
		for (int64_t i = 0; i < n; i++) {
			_cast_sight_ray(i);
		}
	} else {
		WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
		const int64_t task = pool->add_group_task(callable_mp(this, &VagnFast::_cast_sight_ray), n, -1, true,
				"sight rays");
		pool->wait_for_group_task_completion(task);
	}
	for (int64_t i = 0; i < n; i++) {
		out[_sight_rays[i].to] = _sight_rays[i].seen;
	}
	return out;
}

void VagnFast::_cast_sight_ray(int64_t index) {
	SightRay &r = _sight_rays[index];
	const Vector3 dir = (r.to - r.from).normalized();
	Ref<PhysicsRayQueryParameters3D> query = PhysicsRayQueryParameters3D::create(r.from, r.to + dir * 0.5,
			0xFFFFFFFF, _sight_exclude);
	query->set_collide_with_areas(true);
	const Dictionary hit = _sight_space->intersect_ray(query);
	r.seen = !hit.is_empty() && uint64_t(int64_t(hit["collider_id"])) == r.target;
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
