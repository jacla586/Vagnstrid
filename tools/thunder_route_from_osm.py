"""ThunderRoad scenario from OSM roads.

Chains named roads from a geodata map's roads.json (Godot coordinates) between a start
and an end point, and writes a scenario scene inheriting the map: a ThunderRoad node
(ThunderRoadMode) with the route as a Path3D and checkpoints as Marker3Ds (movable in the
editor), plus ThunderRoadBots.

  geodata/.venv/bin/python -I tools/thunder_route_from_osm.py [--join=M] <map> <out.tscn> \\
      <NodeName> <start x,z> <end x,z> <road name> [<road name> ...]

--join=M: join road pieces whose points are this close (default 15 m; more across
roundabouts whose ring has another name).

Or take a ready route (any roads and paths, e.g. a corridor map's korridor.json with
"rutt_sweref": [[E, N], ...] from start to end) instead of road names:
  ... --path=geodata/road_to_science/korridor.json road_to_science <out.tscn> <NodeName>
Heights come from the nearest point in roads.json.

Example (Vidingsjö, Haningeleden):
  ... vidingsjo scenes/scenarios/vidingsjo_thunder_red.tscn VidingsjoThunderRed \\
      20,190 2667,2000 Haningeleden
Overwrites the scene: rerun only on a new route (checkpoint moves are lost).
"""
import heapq
import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JOIN_M = 15.0        # ends of different road pieces this close are joined
STEP_M = 20.0        # route points this far apart
SPACING_M = 330.0    # aimed checkpoint spacing (250-400 m)


def load_roads(map_name: str, names: list[str]) -> list[list[tuple[float, float, float]]]:
    data = json.loads((ROOT / "geodata" / map_name / "out" / "roads.json").read_text())
    lines = []
    for road in data["roads"]:
        if road["name"] in names and road["highway"] not in ("footway", "path", "cycleway", "steps"):
            lines.append([tuple(p) for p in road["points"]])
    if not lines:
        sys.exit("no roads named %s" % names)
    return lines


def build_graph(lines):
    """Nodes = all road points; edges along each line and between close points."""
    pts: list[tuple[float, float, float]] = []
    edges: dict[int, list[tuple[int, float]]] = {}

    def add_edge(a: int, b: int) -> None:
        d = math.dist((pts[a][0], pts[a][2]), (pts[b][0], pts[b][2]))
        edges.setdefault(a, []).append((b, d))
        edges.setdefault(b, []).append((a, d))

    for line in lines:
        first = len(pts)
        pts.extend(line)
        for i in range(first, len(pts) - 1):
            add_edge(i, i + 1)
    cell: dict[tuple[int, int], list[int]] = {}
    for i, p in enumerate(pts):
        cell.setdefault((int(p[0] // JOIN_M), int(p[2] // JOIN_M)), []).append(i)
    for i, p in enumerate(pts):
        cx, cz = int(p[0] // JOIN_M), int(p[2] // JOIN_M)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for j in cell.get((cx + dx, cz + dz), []):
                    if j > i and math.dist((p[0], p[2]), (pts[j][0], pts[j][2])) <= JOIN_M:
                        add_edge(i, j)
    return pts, edges


def load_path(map_name: str, path_file: str) -> list[tuple[float, float, float]]:
    """Route from SWEREF points (korridor.json), in Godot coordinates, heights from roads.json."""
    out_dir = ROOT / "geodata" / map_name / "out"
    info = json.loads((out_dir / "heightmap_info.json").read_text())
    oe, on = info["origin_sweref_of_pixel_0_0"]
    road_pts = [p for road in json.loads((out_dir / "roads.json").read_text())["roads"] for p in road["points"]]
    cell: dict[tuple[int, int], list] = {}
    for p in road_pts:
        cell.setdefault((int(p[0] // 20), int(p[2] // 20)), []).append(p)
    route = []
    for e, n in json.loads((ROOT / path_file).read_text())["rutt_sweref"]:
        x, z = e - oe, on - n
        near = [q for dx in (-1, 0, 1) for dz in (-1, 0, 1)
                for q in cell.get((int(x // 20) + dx, int(z // 20) + dz), [])]
        if not near:
            sys.exit("no road point near %.0f, %.0f" % (x, z))
        y = min(near, key=lambda q: (q[0] - x) ** 2 + (q[2] - z) ** 2)[1]
        route.append((x, y, z))
    return route


def nearest(pts, x: float, z: float, among=None) -> int:
    pool = range(len(pts)) if among is None else among
    return min(pool, key=lambda i: (pts[i][0] - x) ** 2 + (pts[i][2] - z) ** 2)


def component(edges, start: int) -> list[int]:
    """All points connected to `start` (bits of a road that join nothing are skipped)."""
    seen = {start}
    stack = [start]
    while stack:
        for j, _ in edges.get(stack.pop(), []):
            if j not in seen:
                seen.add(j)
                stack.append(j)
    return list(seen)


def shortest(pts, edges, a: int, b: int) -> list[int]:
    dist = {a: 0.0}
    prev: dict[int, int] = {}
    queue = [(0.0, a)]
    while queue:
        d, i = heapq.heappop(queue)
        if i == b:
            break
        if d > dist.get(i, math.inf):
            continue
        for j, w in edges.get(i, []):
            nd = d + w
            if nd < dist.get(j, math.inf):
                dist[j] = nd
                prev[j] = i
                heapq.heappush(queue, (nd, j))
    if b not in dist:
        sys.exit("start and end are not connected by these roads")
    path = [b]
    while path[-1] != a:
        path.append(prev[path[-1]])
    return path[::-1]


def resample(points, step: float):
    out = [points[0]]
    carry = 0.0
    for p, q in zip(points, points[1:]):
        seg = math.dist((p[0], p[2]), (q[0], q[2]))
        t = step - carry
        while t <= seg:
            f = t / seg
            out.append(tuple(p[k] + (q[k] - p[k]) * f for k in range(3)))
            t += step
        carry = seg - (t - step)
    if math.dist((out[-1][0], out[-1][2]), (points[-1][0], points[-1][2])) > 1.0:
        out.append(points[-1])
    return out


def length(points) -> float:
    return sum(math.dist((p[0], p[2]), (q[0], q[2])) for p, q in zip(points, points[1:]))


def point_at(points, s: float):
    for p, q in zip(points, points[1:]):
        seg = math.dist((p[0], p[2]), (q[0], q[2]))
        if s <= seg:
            f = s / seg if seg > 0 else 0.0
            return tuple(p[k] + (q[k] - p[k]) * f for k in range(3))
        s -= seg
    return points[-1]


def fmt(v: float) -> str:
    return ("%.2f" % v).rstrip("0").rstrip(".")


def main() -> None:
    global JOIN_M
    path_file = ""
    for arg in list(sys.argv[1:]):
        if arg.startswith("--join="):
            JOIN_M = float(arg.split("=", 1)[1])
            sys.argv.remove(arg)
        elif arg.startswith("--path="):
            path_file = arg.split("=", 1)[1]
            sys.argv.remove(arg)
    if len(sys.argv) < (4 if path_file else 7):
        sys.exit(__doc__)
    map_name, out, node_name = sys.argv[1], sys.argv[2], sys.argv[3]
    if path_file:
        path = load_path(map_name, path_file)
    else:
        sx, sz = (float(v) for v in sys.argv[4].split(","))
        ex, ez = (float(v) for v in sys.argv[5].split(","))
        pts, edges = build_graph(load_roads(map_name, sys.argv[6:]))
        end = nearest(pts, ex, ez)
        start = nearest(pts, sx, sz, component(edges, end))
        path = [pts[i] for i in shortest(pts, edges, start, end)]
    route = resample(path, STEP_M)
    total = length(route)
    n = max(1, round(total / SPACING_M))
    # The first spacing stays free: a drive to the fight before the first checkpoint.
    checkpoints = [point_at(route, total * k / n) for k in range(2, n + 1)]
    print("%s: %.0f m, %d route points, %d checkpoints %.0f m apart"
          % (node_name, total, len(route), n - 1, total / n))

    rng = random.Random(node_name)
    uid = lambda: rng.randint(10 ** 8, 2 ** 31 - 1)
    curve = ", ".join("0, 0, 0, 0, 0, 0, %s, %s, %s" % (fmt(p[0]), fmt(p[1] + 0.5), fmt(p[2]))
                      for p in route)
    tilts = ", ".join("0" for _ in route)
    lines = [
        '[gd_scene format=3]',
        '',
        '[ext_resource type="PackedScene" path="res://scenes/maps/%s.tscn" id="1_base"]' % map_name,
        '[ext_resource type="Script" path="res://scripts/modes/thunder_road_mode.gd" id="2_mode"]',
        '[ext_resource type="Resource" path="res://data/modes/thunder_road.tres" id="3_data"]',
        '[ext_resource type="Script" path="res://scripts/modes/thunder_road_bots.gd" id="4_bots"]',
        '',
        '[sub_resource type="Curve3D" id="Curve3D_route"]',
        '_data = {',
        '"points": PackedVector3Array(%s),' % curve,
        '"tilts": PackedFloat32Array(%s)' % tilts,
        '}',
        'point_count = %d' % len(route),
        '',
        '[node name="%s" unique_id=%d instance=ExtResource("1_base")]' % (node_name, uid()),
        '',
        '[node name="ThunderRoad" type="Node3D" parent="." unique_id=%d]' % uid(),
        'script = ExtResource("2_mode")',
        'data = ExtResource("3_data")',
        '',
        '[node name="Route" type="Path3D" parent="ThunderRoad" unique_id=%d]' % uid(),
        'curve = SubResource("Curve3D_route")',
        '',
        '[node name="Checkpoints" type="Node3D" parent="ThunderRoad" unique_id=%d]' % uid(),
        '',
    ]
    for k, p in enumerate(checkpoints, 1):
        lines += [
            '[node name="CP%d" type="Marker3D" parent="ThunderRoad/Checkpoints" unique_id=%d]' % (k, uid()),
            'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)' % (fmt(p[0]), fmt(p[1]), fmt(p[2])),
            '',
        ]
    lines += [
        '[node name="ThunderRoadBots" type="Node" parent="." unique_id=%d node_paths=PackedStringArray("mode")]' % uid(),
        'script = ExtResource("4_bots")',
        'mode = NodePath("../ThunderRoad")',
        '',
    ]
    (ROOT / out).write_text("\n".join(lines))
    print("wrote", out)


if __name__ == "__main__":
    main()
