"""Adds a team-1 bot and PlayerRespawn to a corridor map scene and puts the PlayerRig at
the route start (geodata/<map>/korridor.json). Run once, after build_geodata_scene.gd.
  geodata/.venv/bin/python -I tools/corridor_map_scene.py <map> <EnemyName>
"""
import json, math, re, sys
from pathlib import Path
name, enemy = sys.argv[1], sys.argv[2]
out = Path('geodata') / name / 'out'
info = json.load(open(out / 'heightmap_info.json')); oe, on = info['origin_sweref_of_pixel_0_0']
route = json.load(open(Path('geodata') / name / 'korridor.json'))['rutt_sweref']
pts = [p for r in json.load(open(out / 'roads.json'))['roads'] for p in r['points']]
def g(e, n):
    x, z = e - oe, on - n
    q = min(pts, key=lambda q: (q[0] - x) ** 2 + (q[2] - z) ** 2)
    return x, q[1], z
def along(i0, step, dist):
    a = g(*route[i0]); i = i0
    while 0 <= i + step < len(route) and math.dist(route[i0], route[i]) < dist:
        i += step
    return a, g(*route[i])
def tf(a, b, lift):
    dx, dz = b[0] - a[0], b[2] - a[2]
    yaw = math.atan2(-dx, -dz); c, s = math.cos(yaw), math.sin(yaw)
    return "Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.2f, %.2f, %.2f)" % (c, -s, s, c, a[0], a[1] + lift, a[2])
s0, s1 = along(0, 1, 40)
e0, e1 = along(len(route) - 1, -1, 40)
p = Path('scenes/maps') / f'{name}.tscn'; t = p.read_text()
assert 'name="Enemies"' not in t
m = re.search(r'\[ext_resource type="PackedScene" path="res://scenes/player/player_rig.tscn" id="([^"]+)"\]\n', t)
ext = '''[ext_resource type="PackedScene" path="res://scenes/tank/tank.tscn" id="7_tank"]
[ext_resource type="Script" uid="uid://t1duuxcrtose" path="res://scripts/control/bot_controller.gd" id="8_botctrl"]
[ext_resource type="Resource" uid="uid://xul8ehta6d3o" path="res://data/bots/bot_regular.tres" id="9_botdata"]
[ext_resource type="Script" uid="uid://bc1odctfft7i4" path="res://scripts/control/respawn_at_start.gd" id="10_respawn"]
'''
t = t[:m.end()] + ext + t[m.end():]
t = re.sub(r'(\[node name="PlayerRig"[^\n]*\n)transform = [^\n]*\n', lambda mm: mm.group(1) + 'transform = ' + tf(s0, s1, 1.5) + '\n', t)
base = 1402552000
t = t.rstrip('\n') + f'''

[node name="Enemies" type="Node3D" parent="." unique_id={base + 1}]

[node name="{enemy}" parent="Enemies" unique_id={base + 2} instance=ExtResource("7_tank")]
transform = {tf(e0, e1, 1.5)}
team = 1

[node name="{enemy}Controller" type="Node" parent="Enemies" unique_id={base + 3} node_paths=PackedStringArray("tank")]
script = ExtResource("8_botctrl")
bot_data = ExtResource("9_botdata")
tank = NodePath("../{enemy}")
pivot_turn_deg = 100.0
unstick_after_s = 3.0

[node name="PlayerRespawn" type="Node" parent="." unique_id={base + 4} node_paths=PackedStringArray("tank")]
script = ExtResource("10_respawn")
tank = NodePath("../PlayerRig/Tank")
'''
p.write_text(t)
print('player', s0, '-> enemy', e0)
