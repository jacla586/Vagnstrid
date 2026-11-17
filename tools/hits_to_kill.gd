extends SceneTree
## How many hits does it take to knock a tank out? Fires simulated volleys at a target
## preset with every preset's gun (AP and HE) from several directions and ranges, through
## the game's own rules (Armour.resolve, TankDamage.apply_hit, fire ticking between shots,
## plate wear), and prints the median number of hits to a knock-out per case.
##   godot --headless --path . --script res://tools/hits_to_kill.gd -- [target] [trials] [csv] [--spots]
## --spots: instead, every gun's AP at 400 m aimed at one part only (hull or turret) from the
## front, side and rear: how many hits on that part alone knock it out.
## target: a preset in data/configs without .tres (default 4_kv2); trials per case (200);
## csv: optional path for every case's numbers.
## Each shot aims at the hull's centre with a normal spread (SPREAD_BASE_M + SPREAD_PER_M ×
## range), so it lands anywhere on the tank, mostly mid-hull; shots that miss are fired
## again (only hits count). Impact speed and descent angle come from Ballistics at the
## range. The turret points straight ahead; the target stands still and doesn't repair.

const TANK_SCENE: String = "res://scenes/tank/tank.tscn"
const DIRECTIONS: Array = [["front", 0.0], ["front30", 30.0], ["side", 90.0], ["rear", 180.0]]
const RANGES_M: Array[float] = [100.0, 400.0, 800.0]
const SPREAD_BASE_M: float = 0.35
const SPREAD_PER_M: float = 0.0007
## A case gives up after this many hits (shown as ">N").
const MAX_HITS: int = 40
const MISS_TRIES: int = 50

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var spots: bool = args.has("--spots")
	if spots:
		args.remove_at(args.find("--spots"))
	var target_name: String = args[0] if args.size() > 0 else "4_kv2"
	var trials: int = int(args[1]) if args.size() > 1 else 200
	var csv_path: String = args[2] if args.size() > 2 else ""
	_rng.seed = 1
	var target_cfg: TankConfig = load("res://data/configs/%s.tres" % target_name)
	var data: TankData = TankBuilder.build(target_cfg)
	var tank: Tank = (load(TANK_SCENE) as PackedScene).instantiate()
	tank.config = target_cfg
	tank.data = data
	tank.position = Vector3(0.0, 2.0, 0.0)
	root.add_child(tank)
	tank.freeze = true
	for i: int in 4:
		await physics_frame
	if spots:
		_spots_report(tank, trials)
		tank.queue_free()
		quit()
		return
	print("\nTarget %s: %.0f hp; median hits to knock out (KO %% on the first hit) [ammo/fire/hp share of KOs]"
			% [tank.get_type_name(), tank.data.structure_hp])
	print("spread %.2f m + %.1f mm/m, %d trials per case, turret ahead, no repairs\n"
			% [SPREAD_BASE_M, SPREAD_PER_M * 1000.0, trials])
	var header: String = "%-18s" % "gun / round"
	for d: Array in DIRECTIONS:
		for r: float in RANGES_M:
			header += "%13s" % ("%s %dm" % [d[0], int(r)])
	print(header)
	var csv: PackedStringArray = ["shooter,round,direction,range_m,median_hits,mean_hits,first_hit_ko,ko_ammo,ko_fire,ko_hp,impact_mps"]
	var files: PackedStringArray = DirAccess.get_files_at("res://data/configs")
	for f: String in files:
		if not f.ends_with(".tres"):
			continue
		var cfg: TankConfig = load("res://data/configs/" + f)
		var shooter: TankData = TankBuilder.build(cfg)
		for shell: ShellData in shooter.ammo:
			var line: String = "%-18s" % ("%s %s" % [cfg.display_name, shell.short_name])
			var why: String = ""
			for d: Array in DIRECTIONS:
				for r: float in RANGES_M:
					var s: Dictionary = _case(tank, shell, shooter.reload_time_s, d[1], r, trials)
					var med: String = (">%d" % MAX_HITS) if s["median"] > MAX_HITS else str(s["median"])
					line += "%13s" % ("%s (%d%%)" % [med, roundi(100.0 * s["first"])])
					csv.append("%s,%s,%s,%d,%s,%.2f,%.3f,%.3f,%.3f,%.3f,%.0f" % [cfg.display_name,
							shell.short_name, d[0], int(r), med, s["mean"], s["first"], s["ammo"],
							s["fire"], s["hp"], s["speed"]])
					if d[0] == "side" and r == 400.0:
						why = "   side 400 m KOs: ammo %d%% fire %d%% hp %d%%" % [roundi(100.0 * s["ammo"]),
								roundi(100.0 * s["fire"]), roundi(100.0 * s["hp"])]
			print(line + why)
	if csv_path != "":
		var out := FileAccess.open(csv_path, FileAccess.WRITE)
		out.store_string("\n".join(csv) + "\n")
		out.close()
		print("\nwrote ", csv_path)
	tank.queue_free()
	quit()


## Impact speed and the shell's flight direction at `range_m` (flat fire from gun height).
func _impact(shell: ShellData, range_m: float) -> Array:
	var k: float = Ballistics.drag_factor(shell)
	var angle: float = Ballistics.superelevation_for_range(shell, range_m)
	var pos := Vector3.ZERO
	var vel := Vector3(0.0, sin(angle), -cos(angle)) * shell.muzzle_velocity_mps
	var dt: float = Ballistics.physics_step()
	var t: float = 0.0
	while -pos.z < range_m and t < Ballistics.MAX_FLIGHT_TIME:
		var pv: PackedVector3Array = Ballistics.integrate(pos, vel, k, dt)
		pos = pv[0]
		vel = pv[1]
		t += dt
	return [vel.length(), asin(clampf(-vel.y / maxf(vel.length(), 0.001), -1.0, 1.0))]


func _case(tank: Tank, shell: ShellData, reload_s: float, dir_deg: float, range_m: float,
		trials: int, want_part: String = "") -> Dictionary:
	var imp: Array = _impact(shell, range_m)
	var speed: float = imp[0]
	var drop: float = imp[1]
	var a: float = deg_to_rad(dir_deg)
	var from_dir := Vector3(-sin(a) * cos(drop), sin(drop), -cos(a) * cos(drop))
	var dir: Vector3 = -from_dir
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(dir).normalized()
	var centre: Vector3 = _part_centre(tank, dir, want_part)
	var spread: float = SPREAD_BASE_M + SPREAD_PER_M * range_m
	var space: PhysicsDirectSpaceState3D = tank.get_world_3d().direct_space_state
	var dmg := TankDamage.new(tank.data)
	var counts: Array[int] = []
	var first: int = 0
	var by: Dictionary = {"ammo": 0, "fire": 0, "hp": 0}
	for trial: int in trials:
		dmg.reset()
		var hits: int = 0
		while not dmg.knocked_out and hits <= MAX_HITS:
			if hits > 0:   # the reload between shots: a fire burns on
				var t: float = 0.0
				while t < reload_s and not dmg.knocked_out:
					dmg.tick(0.25, false)
					t += 0.25
				if dmg.knocked_out:
					by["fire"] += 1
					break
			_shot(tank, space, dmg, shell, speed, dir, centre, centre + right * _rng.randfn(0.0, spread)
					+ up * _rng.randfn(0.0, spread), want_part)
			hits += 1
			if dmg.knocked_out:
				by["ammo" if dmg.ammo_exploded else "hp"] += 1
		counts.append(hits)
		if hits == 1 and dmg.knocked_out:
			first += 1
	counts.sort()
	var total: float = 0.0
	for c: int in counts:
		total += c
	var kos: float = maxf(by["ammo"] + by["fire"] + by["hp"], 1.0)
	return {"median": counts[counts.size() / 2], "mean": total / counts.size(),
			"first": first / float(trials), "ammo": by["ammo"] / kos, "fire": by["fire"] / kos,
			"hp": by["hp"] / kos, "speed": speed}


## One hit: aims at `aim`, re-aiming round it until the ray finds the tank.
func _shot(tank: Tank, space: PhysicsDirectSpaceState3D, dmg: TankDamage, shell: ShellData,
		speed: float, dir: Vector3, centre: Vector3, aim: Vector3, want_part: String = "") -> bool:
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(dir).normalized()
	var hit: Dictionary = {}
	for i: int in MISS_TRIES:
		var start: Vector3 = aim - dir * 30.0
		var q := PhysicsRayQueryParameters3D.create(start, start + dir * 60.0, 1)
		hit = space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] == tank \
				and (want_part == "" or _part_of(tank, hit) == want_part):
			break
		hit = {}
		# missed: a fresh aim point (the spread pulled in, so a hit comes)
		var s: float = 0.4 + 0.6 * (1.0 - i / float(MISS_TRIES))
		aim = centre + right * _rng.randfn(0.0, s) + up * _rng.randfn(0.0, s)
	if hit.is_empty():
		return false
	var turret: Node3D = tank.get("_turret")
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var part: String = _part_of(tank, hit)
	var frame: Node3D = turret if part == "turret" else tank
	var face: String = tank.call("_face_for_normal",
			frame.global_basis.orthonormalized().inverse() * normal)
	var local_point: Vector3 = frame.to_local(point)
	var plate: float = dmg.armour_mm(part, face, local_point)
	var result: HitResult = Armour.resolve(shell, speed, plate,
			Armour.impact_angle(dir * speed, normal),
			Armour.ricochet_angle(tank.data.armour, shell.caliber_mm, plate))
	dmg.apply_hit(shell, result, part, face, local_point, tank.to_local(point),
			tank.global_basis.orthonormalized().inverse() * dir, turret.to_local(point),
			turret.global_basis.orthonormalized().inverse() * dir)
	return true


func _part_of(tank: Tank, hit: Dictionary) -> String:
	var node: Node = tank.call("_shape_node", int(hit["shape"]))
	if node == tank.get("_turret_shape") or (tank.get("_turret_shapes") as Array).has(node):
		return "turret"
	return "hull"


## Where to aim at a part seen along `dir`: the middle of the heights where rays straight
## through the tank's middle hit that part ("" = the old aim, a quarter up the hull).
func _part_centre(tank: Tank, dir: Vector3, part: String) -> Vector3:
	var base: Vector3 = tank.global_position + Vector3(0.0, tank.data.hull_size.y * 0.25, 0.0)
	if part == "":
		return base
	var space: PhysicsDirectSpaceState3D = tank.get_world_3d().direct_space_state
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var lo: float = INF
	var hi: float = -INF
	for i: int in 160:
		var y: float = -2.0 + i * 0.03
		var start: Vector3 = tank.global_position + Vector3(0.0, y, 0.0) - flat * 30.0
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start + flat * 60.0, 1))
		if not hit.is_empty() and hit["collider"] == tank and _part_of(tank, hit) == part:
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if lo > hi:
		return base
	return tank.global_position + Vector3(0.0, (lo + hi) * 0.5, 0.0)


## Every gun's AP at 400 m on each part from the front, side and rear: hits to knock out.
func _spots_report(tank: Tank, trials: int) -> void:
	const RANGE: float = 400.0
	var spots: Array = [["hull front", "hull", 0.0], ["hull side", "hull", 90.0], ["hull rear", "hull", 180.0],
			["turret front", "turret", 0.0], ["turret side", "turret", 90.0], ["turret rear", "turret", 180.0]]
	var shooters: Array = []
	for f: String in DirAccess.get_files_at("res://data/configs"):
		if f.ends_with(".tres"):
			var cfg: TankConfig = load("res://data/configs/" + f)
			shooters.append([cfg.display_name, TankBuilder.build(cfg)])
	print("\n%s, %.0f hp: AP hits on that spot alone to knock it out, %d m (median of %d)"
			% [tank.get_type_name(), tank.data.structure_hp, int(RANGE), trials])
	var header: String = "%-14s" % "spot"
	for sh: Array in shooters:
		header += "%10s" % sh[0]
	print(header)
	for sp: Array in spots:
		var line: String = "%-14s" % sp[0]
		for sh: Array in shooters:
			var data: TankData = sh[1]
			var s: Dictionary = _case(tank, data.ammo[0], data.reload_time_s, sp[2], RANGE, trials, sp[1])
			line += "%10s" % ((">%d" % MAX_HITS) if s["median"] > MAX_HITS else str(s["median"]))
		print(line)
