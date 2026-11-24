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
	ClassDB::bind_method(D_METHOD("prefetch_squad_sight", "squad", "args"), &VagnFast::prefetch_squad_sight);
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

void VagnFast::_ensure_world(SceneTree *tree) {
	Engine *engine = Engine::get_singleton();
	const int64_t key = engine->is_in_physics_frame() ? int64_t(engine->get_physics_frames()) * 2
													  : int64_t(engine->get_process_frames()) * 2 + 1;
	if (key == _world_key) {
		return;
	}
	_world_key = key;
	_world_tanks.clear();
	_world_squads.clear();
	const TypedArray<Node> tanks = tree->get_nodes_in_group("tanks");
	_world_tanks.reserve(tanks.size());
	for (int64_t i = 0; i < tanks.size(); i++) {
		Node3D *t = Object::cast_to<Node3D>(tanks[i]);
		if (t == nullptr || !t->has_method("get_spot_points")) {
			continue;
		}
		WorldTank w;
		w.node = t;
		w.id = t->get_instance_id();
		w.team = t->get("team");
		w.knocked_out = t->call("is_knocked_out");
		w.position = t->get_global_position();
		if (!w.knocked_out) {
			const Array points = t->call("get_spot_points");
			w.spot_points.reserve(points.size());
			for (int64_t k = 0; k < points.size(); k++) {
				w.spot_points.push_back(t->to_global(points[k]));
			}
			w.commander_exposed = t->call("is_commander_exposed");
			if (w.commander_exposed) {
				w.head = t->call("get_commander_hitbox_position");
				w.head_box = Object::cast_to<Object>(t->call("get_commander_hitbox"));
			}
		}
		_world_tanks.push_back(std::move(w));
	}
	const TypedArray<Node> squads = tree->get_nodes_in_group("squads");
	_world_squads.reserve(squads.size());
	for (int64_t i = 0; i < squads.size(); i++) {
		Node3D *s = Object::cast_to<Node3D>(squads[i]);
		if (s == nullptr || !s->has_method("get_hitboxes")) {
			continue;
		}
		WorldSquad w;
		w.node = s;
		w.id = s->get_instance_id();
		w.team = s->call("get_team");
		w.out = s->call("is_out");
		w.position = s->get_global_position();
		if (w.out) {
			const Array hitboxes = s->call("get_hitboxes");
			w.soldiers.reserve(hitboxes.size());
			for (int64_t k = 0; k < hitboxes.size(); k++) {
				Node3D *hb = Object::cast_to<Node3D>(hitboxes[k]);
				if (hb == nullptr) {
					continue;
				}
				WorldSoldier soldier;
				soldier.hitbox = hb;
				soldier.exposed = s->call("is_soldier_exposed", hb->get("index"));
				if (soldier.exposed) {
					soldier.position = hb->get_global_position();
					soldier.aim = hb->call("get_aim_point");
				}
				w.soldiers.push_back(soldier);
			}
		}
		_world_squads.push_back(std::move(w));
	}
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
	const uint64_t own_id = tank->get_instance_id();
	auto id_of = [](const Variant &v) -> uint64_t {
		if (v.get_type() != Variant::OBJECT) {
			return 0;
		}
		Object *o = v;
		return o != nullptr ? uint64_t(o->get_instance_id()) : 0;
	};
	const uint64_t target_id = id_of(target);
	const uint64_t squad_target_id = id_of(squad_target);
	_sight_rays.clear();
	_sight_space = tank->get_world_3d()->get_direct_space_state();
	_sight_shot_mask = 0xFFFFFFFF;
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
	_ensure_world(tank->get_tree());
	for (const WorldTank &other : _world_tanks) {
		if (other.id == own_id || other.team == team || other.knocked_out) {
			continue;
		}
		const double d = here.distance_to(other.position);
		const int64_t per_look = d > far4 ? 4 : (d > near2 ? 2 : 1);
		if (other.id != target_id && int64_t(look_wait.get(Variant(other.node), 0)) + 1 < per_look) {
			continue;
		}
		if (eye.distance_to(other.position) > tank_range) {
			continue;
		}
		for (const Vector3 &p : other.spot_points) {
			want(p, other.node);
		}
		if (other.commander_exposed) {
			want(other.head, other.head_box);
		}
	}
	for (const WorldSquad &enemy : _world_squads) {
		if (!enemy.out || enemy.team == team) {
			continue;
		}
		const double d = here.distance_to(enemy.position);
		if (d > squad_range) {
			continue;
		}
		if (enemy.id != squad_target_id && d > squad_every2
				&& int64_t(squad_look_wait.get(Variant(enemy.node), 0)) + 1 < 2) {
			continue;
		}
		for (const WorldSoldier &s : enemy.soldiers) {
			if (s.exposed) {
				want(s.aim, s.hitbox);
			}
		}
	}
	_run_sight_rays();
	for (const SightRay &r : _sight_rays) {
		out[r.to] = r.seen;
	}
	return out;
}

Dictionary VagnFast::prefetch_squad_sight(Node3D *squad, const Dictionary &args) {
	Dictionary out;
	if (squad == nullptr) {
		return out;
	}
	const Vector3 eye = args["eye"];
	const double full = args["full_range"];
	const double margin = args["margin"];
	const bool moving = args["moving"];
	const Vector3 origin = args["origin"];
	const Vector3 heading = args["heading"];
	const double cone_half = args["cone_half"];
	const Array exclude = args["exclude"];
	const Dictionary look_wait = args["look_wait"];
	const double every2 = args["every2_m"];
	const Array heights = args["heights"];
	const Array see_through = args["see_through"];
	_sight_shot_mask = uint32_t(int64_t(args["shot_mask"]));
	_sight_crown_mask = uint32_t(int64_t(args["crown_mask"]));
	_sight_exclude.clear();
	for (int64_t i = 0; i < exclude.size(); i++) {
		_sight_exclude.append(RID(exclude[i]));
	}
	const int64_t team = squad->call("get_team");
	const uint64_t own_id = squad->get_instance_id();
	_sight_rays.clear();
	_sight_space = squad->get_world_3d()->get_direct_space_state();
	auto in_cone = [&](const Vector3 &p) {   // Squad._in_view_cone
		if (!moving) {
			return true;
		}
		const Vector3 to_p(p.x - origin.x, 0.0, p.z - origin.z);
		return to_p.length() < 1.0 || heading.angle_to(to_p.normalized()) <= cone_half;
	};
	auto want = [&](const Vector3 &point, Object *collider) {   // Squad._want_sight
		const double d = eye.distance_to(point);
		if (collider == nullptr || d > full || !in_cone(point)) {
			return;
		}
		int32_t layers = 0;   // Squad._layers_seen_through
		for (int64_t k = 0; k < see_through.size(); k++) {
			if (d <= double(see_through[k])) {
				layers = int32_t(k + 1);
			}
		}
		SightRay r;
		r.from = eye;
		r.to = point;
		r.target = collider->get_instance_id();
		r.blockers = layers;
		_sight_rays.push_back(r);
	};
	_ensure_world(squad->get_tree());
	for (const WorldTank &other : _world_tanks) {
		if (other.knocked_out || other.team == team) {
			continue;
		}
		const double away = eye.distance_to(other.position);
		if (int64_t(look_wait.get(Variant(other.node), 0)) + 1 < 2 && away > every2) {
			continue;
		}
		if (away > full + margin) {
			continue;
		}
		for (int64_t k = 0; k < heights.size(); k++) {
			want(other.position + Vector3(0.0, double(heights[k]), 0.0), other.node);
		}
		if (other.commander_exposed) {
			want(other.head, other.head_box);
		}
	}
	for (const WorldSquad &enemy : _world_squads) {
		if (enemy.id == own_id || !enemy.out || enemy.team == team) {
			continue;
		}
		for (const WorldSoldier &s : enemy.soldiers) {
			if (s.exposed && eye.distance_to(s.position) <= full + margin) {
				want(s.aim, s.hitbox);
			}
		}
	}
	_run_sight_rays();
	for (const SightRay &r : _sight_rays) {
		out[r.to] = r.seen;
	}
	return out;
}

void VagnFast::_run_sight_rays() {
	const int64_t n = int64_t(_sight_rays.size());
	if (n == 0) {
		return;
	}
	if (n < 24) {
		for (int64_t i = 0; i < n; i++) {
			_cast_sight_ray(i);
		}
		return;
	}
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	const int64_t task = pool->add_group_task(callable_mp(this, &VagnFast::_cast_sight_ray), n, -1, true,
			"sight rays");
	pool->wait_for_group_task_completion(task);
}

// SightRays._one: Vision.has_line_of_sight (blockers -2) or has_line_of_sight_through.
void VagnFast::_cast_sight_ray(int64_t index) {
	SightRay &r = _sight_rays[index];
	const Vector3 dir = (r.to - r.from).normalized();
	Ref<PhysicsRayQueryParameters3D> query = PhysicsRayQueryParameters3D::create(r.from, r.to + dir * 0.5,
			r.blockers == -2 ? 0xFFFFFFFF : _sight_shot_mask, _sight_exclude);
	query->set_collide_with_areas(true);
	const Dictionary hit = _sight_space->intersect_ray(query);
	if (hit.is_empty() || uint64_t(int64_t(hit["collider_id"])) != r.target) {
		r.seen = false;
		return;
	}
	if (r.blockers < 0) {
		r.seen = true;
		return;
	}
	const Vector3 hit_pos = hit["position"];
	const double stop = r.from.distance_to(hit_pos);
	Ref<PhysicsRayQueryParameters3D> crowns = PhysicsRayQueryParameters3D::create(r.from, hit_pos,
			_sight_crown_mask, _sight_exclude);
	crowns->set_collide_with_areas(true);
	crowns->set_collide_with_bodies(false);
	int32_t count = 0;
	Vector3 start = r.from;
	RID last_rid;
	int64_t last_shape = -1;
	for (int32_t k = 0; k < r.blockers * 2 + 4; k++) {
		crowns->set_from(start);
		const Dictionary c = _sight_space->intersect_ray(crowns);
		if (c.is_empty()) {
			r.seen = true;
			return;
		}
		const Vector3 p = c["position"];
		const RID rid = c["rid"];
		const int64_t shape = c["shape"];
		if (rid != last_rid || shape != last_shape) {
			count++;
			if (count > r.blockers) {
				r.seen = false;
				return;
			}
		}
		last_rid = rid;
		last_shape = shape;
		start = p + dir * 0.05;
		if (r.from.distance_to(start) >= stop) {
			r.seen = true;
			return;
		}
	}
	r.seen = false;
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
