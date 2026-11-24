#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <vector>

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
	// The rays come from one batch per physics tick (every tank's, cast together on
	// worker threads: bodies don't move while the tick's callbacks run); a tank moved
	// since (placed, set upright) casts its own.
	void apply_suspension(RigidBody3D *body, const Array &rays, const Vector3 &com_global,
			double rest_length, double stiffness, double damping, Array points, Array normals);

	// Tank._apply_track_force for both tracks: each track's force shared over its
	// wheels on the ground, along the ground at each wheel, acting at the centre of
	// mass' height; summed into one central force and one torque.
	void apply_track_forces(RigidBody3D *body, double left_force, double right_force,
			const Vector3 &forward, const Vector3 &up, const Vector3 &com_global,
			const Array &left_points, const Array &left_normals,
			const Array &right_points, const Array &right_normals);

	// BotController._prefetch_sight: the sight lines of one look round (the same points
	// and skipping as the look round: far tanks every 2nd/4th scan, far squads every
	// 2nd, less those out of range or the periscope's sector), cast together on worker
	// threads as Vision.has_line_of_sight. Returns point -> in sight. `args` keys: eye,
	// full_range, open, turret_yaw, half_angle, exclude (RIDs), target, look_wait,
	// near2_m, far4_m, tank_range, squad_target, squad_look_wait, squad_range, squad_every2_m.
	Dictionary prefetch_sight(Node3D *tank, const Dictionary &args);

	// Squad._prefetch_sight: the squad leader's sight lines of one look round (tanks at
	// TANK_LOOK_HEIGHTS, far ones every 2nd scan; exposed enemy soldiers), with the
	// vegetation layers seen through by distance (Vision.has_line_of_sight_through).
	// `args` keys: eye, full_range, margin, moving, origin, heading, cone_half, exclude,
	// look_wait, every2_m, heights, see_through (Arrays of floats), shot_mask, crown_mask.
	Dictionary prefetch_squad_sight(Node3D *squad, const Dictionary &args);

	// The world picture both read: every tank and squad asked once per physics tick (and
	// once more in a frame between ticks, as bodies moved in the step), not once per
	// reader. A state change later in the same tick only costs a ray: the readers'
	// GDScript still decides and casts its own ray for a point that isn't here.
	int64_t world_version() const { return _world_key; }

private:
	struct WorldTank {
		Object *node = nullptr;
		uint64_t id = 0;
		int64_t team = -1;
		bool knocked_out = false;
		Vector3 position;
		std::vector<Vector3> spot_points; // world space
		bool commander_exposed = false;
		Vector3 head;
		Object *head_box = nullptr;
	};
	struct WorldSoldier {
		Object *hitbox = nullptr;
		Vector3 position;
		Vector3 aim;
		bool exposed = false;
	};
	struct WorldSquad {
		Object *node = nullptr;
		uint64_t id = 0;
		int64_t team = -1;
		bool out = false;
		Vector3 position;
		std::vector<WorldSoldier> soldiers;
	};
	int64_t _world_key = -1;
	std::vector<WorldTank> _world_tanks;
	std::vector<WorldSquad> _world_squads;
	void _ensure_world(SceneTree *tree);

	struct SightRay {
		Vector3 from;
		Vector3 to;
		uint64_t target = 0;
		bool seen = false;
		int32_t blockers = -2; // -2 every layer; >= -1 solid things + that many crowns
	};
	uint32_t _sight_shot_mask = 0xFFFFFFFF;
	uint32_t _sight_crown_mask = 0;
	void _run_sight_rays();
	std::vector<SightRay> _sight_rays;
	TypedArray<RID> _sight_exclude;
	PhysicsDirectSpaceState3D *_sight_space = nullptr;
	void _cast_sight_ray(int64_t index);
	static bool _in_sector(const Vector3 &eye, const Vector3 &point, bool open, double turret_yaw,
			double half_angle);

	static void _track_force(double force, const Vector3 &forward, const Vector3 &up,
			const Vector3 &com_global, const Vector3 &origin, const Array &points,
			const Array &normals, Vector3 &total_force, Vector3 &total_torque);

	struct SuspensionRay {
		Vector3 from;
		Vector3 to;
		uint32_t mask = 0;
		RID exclude;
		bool hit = false;
		Vector3 point;
		Vector3 normal;
	};
	uint64_t _suspension_tick = UINT64_MAX;
	std::vector<SuspensionRay> _suspension_rays;
	HashMap<uint64_t, int64_t> _suspension_index; // RayCast3D instance id -> ray
	HashMap<uint64_t, Transform3D> _suspension_pose; // tank instance id -> pose at the cast
	PhysicsDirectSpaceState3D *_suspension_space = nullptr;

	void _prepare_suspension(RigidBody3D *any_tank);
	void _cast_suspension_ray(int64_t index);
};

} // namespace godot
