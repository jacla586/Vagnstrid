class_name GroundCoverCellBuild
extends RefCounted
## Builds one GroundCoverField cell's clumps a slice at a time (step() until it returns
## true, then node()), so no frame pays for a whole dense cell (GDScript: ~1.5 µs a clump).
## The clumps are the first share (4^-level) of the cell's fixed random sequence of tries:
## per try a place in the cell; the class of its 2 m square decides whether a clump grows
## there (class density / the densest class), its height and colour. Pass 1 picks the
## clumps, pass 2 writes one MultiMesh buffer with each class in its own stretch (20 floats
## a clump: 3×4 transform rows (turn about y, height), colour, custom = [rank, 0, 0, 0]).

## Terrain heights are sampled on this grid (the terrain's vertex spacing).
const HEIGHT_STEP_M: float = 2.0
## Loop turns between clock checks.
const CHUNK: int = 128

var cell: Vector2i
var level: int

var _gc: GroundCover
var _max_density: float
var _rng := RandomNumberGenerator.new()
var _stage: int = 0   # 0 setup, 1 pick, 2 write, 3 done
var _tries: int = 0
var _inv_full: float = 0.0
var _i: int = 0
var _q: int = 0
var _n: int = 0
var _x0: float = 0.0
var _z0: float = 0.0
var _size: float = 0.0
var _hn: int = 0
var _heights := PackedFloat32Array()
var _gstep: float = 2.0
var _gn: int = 0
var _gx0: int = 0
var _gz0: int = 0
var _grid := PackedByteArray()
var _share := PackedFloat32Array()
var _picks := PackedFloat32Array()
var _counts := PackedInt32Array()
var _start := PackedInt32Array()
var _fill := PackedInt32Array()
var _buf := PackedFloat32Array()
var _color_a: Array[Color] = []
var _color_b: Array[Color] = []
var _height: PackedFloat32Array = PackedFloat32Array()
var _jitter: PackedFloat32Array = PackedFloat32Array()


func _init(gc: GroundCover, c: Vector2i, lvl: int, max_density: float) -> void:
	_gc = gc
	cell = c
	level = lvl
	_max_density = max_density


## Works until the clock passes `deadline_us` (Time.get_ticks_usec(); 0 = no limit).
## True when done.
func step(deadline_us: int) -> bool:
	if _stage == 0:
		_setup()
	while _stage == 1:
		var end: int = mini(_i + CHUNK, _tries)
		_pick(end)
		if _i >= _tries:
			_begin_write()
		elif deadline_us > 0 and Time.get_ticks_usec() > deadline_us:
			return false
	while _stage == 2:
		var end: int = mini(_q + CHUNK, _n)
		_write(end)
		if _q >= _n:
			_stage = 3
		elif deadline_us > 0 and Time.get_ticks_usec() > deadline_us:
			return false
	return true


## The finished cell: a Node3D with one MultiMeshInstance3D per class present.
func node() -> Node3D:
	var root := Node3D.new()
	root.name = "Cell_%d_%d" % [cell.x, cell.y]
	var classes: Array[GroundCoverClassData] = _gc.rules.classes
	for ci: int in _counts.size():
		if _counts[ci] > 0:
			root.add_child(GroundCoverField.make_instances(classes[ci],
					_buf.slice(_start[ci] * 20, _start[ci + 1] * 20), _gc.rules))
	return root


func _setup() -> void:
	var rules: GroundCoverSetData = _gc.rules
	_size = rules.cell_m
	_rng.seed = hash(cell)
	var full_tries: int = int(_size * _size * _max_density)
	_tries = ceili(full_tries / pow(4.0, level))
	_inv_full = 1.0 / float(maxi(full_tries, 1))
	_x0 = cell.x * _size
	_z0 = cell.y * _size
	# class per 2 m square (the data's own cells, centred on multiples of its cell_m)
	var data: GroundCoverData = _gc.data
	_gstep = data.cell_m
	_gn = ceili(_size / _gstep) + 1
	_gx0 = int(roundf(_x0 / _gstep))
	_gz0 = int(roundf(_z0 / _gstep))
	_grid.resize(_gn * _gn)
	var any: bool = false
	for j: int in _gn:
		var r: int = _gz0 + j
		for i: int in _gn:
			var col: int = _gx0 + i
			var v: int = 0
			if col >= 0 and r >= 0 and col < data.width and r < data.height:
				v = data.classes[r * data.width + col]
			_grid[j * _gn + i] = v
			any = any or v > 0
	var classes: Array[GroundCoverClassData] = rules.classes
	var nk: int = classes.size()
	_counts.resize(nk)
	_start.resize(nk + 1)
	if not any:
		_stage = 3
		return
	_share.resize(nk)
	_height.resize(nk)
	_jitter.resize(nk)
	for ci: int in nk:
		var k: GroundCoverClassData = classes[ci]
		var grows: bool = ci > 0 and k != null and k.height_m > 0.0
		_share[ci] = k.density / _max_density if grows else 0.0
		_height[ci] = k.height_m if k != null else 0.0
		_jitter[ci] = k.height_jitter if k != null else 0.0
		_color_a.append(k.color_a.srgb_to_linear() if k != null else Color.BLACK)
		_color_b.append(k.color_b.srgb_to_linear() if k != null else Color.BLACK)
	_hn = int(_size / HEIGHT_STEP_M) + 1
	_heights.resize(_hn * _hn)
	for j: int in _hn:
		for i: int in _hn:
			_heights[j * _hn + i] = _gc.ground_y(_x0 + i * HEIGHT_STEP_M, _z0 + j * HEIGHT_STEP_M)
	_picks.resize(_tries * 5)
	_stage = 1


## Pass 1 up to try `end`: which tries grow a clump (kept: place, randoms, class, rank).
func _pick(end: int) -> void:
	var nk: int = _share.size()
	for i: int in range(_i, end):
		var x: float = _rng.randf() * _size
		var z: float = _rng.randf() * _size
		var r1: float = _rng.randf()
		var r2: float = _rng.randf()
		var r3: float = _rng.randf()
		var ci: int = _grid[(int((_z0 + z) / _gstep + 0.5) - _gz0) * _gn
				+ int((_x0 + x) / _gstep + 0.5) - _gx0]
		if ci <= 0 or ci >= nk or r1 >= _share[ci]:
			continue
		var o: int = _n * 5
		_picks[o] = x
		_picks[o + 1] = z
		_picks[o + 2] = r2
		_picks[o + 3] = r3 * 0.999 + float(ci)   # class in the integer part
		_picks[o + 4] = i * _inv_full
		_counts[ci] += 1
		_n += 1
	_i = end


func _begin_write() -> void:
	for ci: int in _counts.size():
		_start[ci + 1] = _start[ci] + _counts[ci]
	_fill = _start.duplicate()
	_buf.resize(_n * 20)
	_stage = 2


## Pass 2 up to clump `end`: its transform, colour and rank in its class' stretch.
func _write(end: int) -> void:
	var hn: int = _hn
	for q: int in range(_q, end):
		var o: int = q * 5
		var x: float = _picks[o]
		var z: float = _picks[o + 1]
		var r2: float = _picks[o + 2]
		var ci: int = int(_picks[o + 3])
		var a: float = (_picks[o + 3] - ci) * TAU
		# bilinear on the height grid
		var gx: float = x / HEIGHT_STEP_M
		var gz: float = z / HEIGHT_STEP_M
		var ix: int = mini(int(gx), hn - 2)
		var iz: int = mini(int(gz), hn - 2)
		var fx: float = gx - ix
		var fz: float = gz - iz
		var row: int = iz * hn + ix
		var y0: float = _heights[row] + (_heights[row + 1] - _heights[row]) * fx
		var y1: float = _heights[row + hn] + (_heights[row + hn + 1] - _heights[row + hn]) * fx
		var y: float = y0 + (y1 - y0) * fz
		if is_nan(y):
			y = -10000.0   # no terrain here: out of sight
		var h: float = _height[ci] * (1.0 + (r2 * 2.0 - 1.0) * _jitter[ci])
		var ca: Color = _color_a[ci]
		var cb: Color = _color_b[ci]
		var cos_a: float = cos(a)
		var sin_a: float = sin(a)
		var b: int = _fill[ci] * 20
		_fill[ci] += 1
		_buf[b] = cos_a
		_buf[b + 2] = sin_a
		_buf[b + 3] = _x0 + x
		_buf[b + 5] = h
		_buf[b + 7] = y - 0.03
		_buf[b + 8] = -sin_a
		_buf[b + 10] = cos_a
		_buf[b + 11] = _z0 + z
		_buf[b + 12] = ca.r + (cb.r - ca.r) * r2
		_buf[b + 13] = ca.g + (cb.g - ca.g) * r2
		_buf[b + 14] = ca.b + (cb.b - ca.b) * r2
		_buf[b + 15] = 1.0
		_buf[b + 16] = _picks[o + 4]
	_q = end
