## Builds the house: exterior, floors, staircases, and all walls.
## Faithful port of the "build the house" section of game.js. Collision is done
## with real Godot static bodies (instead of the web build's hand-rolled AABB
## list); staircases use an invisible ramp collider under decorative steps,
## which reproduces the original groundY ramp-walk behavior.
class_name World
extends Node3D

const WALL_H := 2.8
const WALL_COLOR := 0xd8d2c4

var col: StaticBody3D   # shared static body that owns every collision shape

# AABB list of every solid wall segment, mirroring the web build's `walls[]`.
# The cat nav grid + collideCat need these; the player uses real physics instead.
var walls: Array = []   # [{minX,maxX,minY,maxY,minZ,maxZ}]

func _ready() -> void:
	col = StaticBody3D.new()
	add_child(col)
	_build_exterior()
	_build_floors()
	_build_stairs()
	_build_perimeter_walls()
	_build_interior_walls()

# ---------- collision + wall helpers ----------

## Add a box collision shape to the shared static body.
func _add_collision(w: float, h: float, d: float, x: float, y: float, z: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, d)
	cs.shape = shape
	cs.position = Vector3(x, y, z)
	col.add_child(cs)

## Visual box + collision (a solid wall segment).
func wall(w: float, h: float, d: float, x: float, y: float, z: float, color: int = WALL_COLOR) -> MeshInstance3D:
	var m := Geom.box(w, h, d, color, x, y, z, self)
	_add_collision(w, h, d, x, y, z)
	# record the AABB for the cat nav grid / collideCat (mirrors addWallBox)
	walls.append({"minX": x - w / 2.0, "maxX": x + w / 2.0,
		"minY": y - h / 2.0, "maxY": y + h / 2.0,
		"minZ": z - d / 2.0, "maxZ": z + d / 2.0})
	return m

## Wall run along an axis ('x' or 'z') with gaps for doors/windows.
func wall_run(axis: String, fixed: float, from: float, to: float, base_y: float, gaps: Array = [], color: int = WALL_COLOR, h: float = WALL_H) -> void:
	var segs: Array = []
	var cur := from
	var sorted_gaps := gaps.duplicate()
	sorted_gaps.sort_custom(func(a, b): return a[0] < b[0])
	for g in sorted_gaps:
		segs.append([cur, g[0]])
		cur = g[1]
	segs.append([cur, to])
	for seg in segs:
		var a: float = seg[0]
		var b: float = seg[1]
		if b - a < 0.05:
			continue
		var length := b - a
		var mid := (a + b) / 2.0
		if axis == "x":
			wall(length, h, 0.2, mid, base_y + h / 2.0, fixed, color)
		else:
			wall(0.2, h, length, fixed, base_y + h / 2.0, mid, color)

## Floor slab with optional rectangular holes (for open stairwells).
func floor_slab(y: float, color: int, holes: Array = []) -> void:
	var X0 := -8.0
	var X1 := 8.0
	var Z0 := -6.0
	var Z1 := 6.0
	var xs := [X0, X1]
	for h in holes:
		xs.append(h.minX)
		xs.append(h.maxX)
	xs.sort()
	for i in range(xs.size() - 1):
		var xa: float = xs[i]
		var xb: float = xs[i + 1]
		if xb - xa < 0.01:
			continue
		var cx := (xa + xb) / 2.0
		var zs := [Z0, Z1]
		for h in holes:
			if cx > h.minX and cx < h.maxX:
				zs.append(h.minZ)
				zs.append(h.maxZ)
		zs.sort()
		for j in range(zs.size() - 1):
			var za: float = zs[j]
			var zb: float = zs[j + 1]
			if zb - za < 0.01:
				continue
			var cz := (za + zb) / 2.0
			var in_hole := false
			for h in holes:
				if cx > h.minX and cx < h.maxX and cz > h.minZ and cz < h.maxZ:
					in_hole = true
					break
			if not in_hole:
				Geom.box(xb - xa, 0.2, zb - za, color, cx, y - 0.1, cz, self)
				_add_collision(xb - xa, 0.2, zb - za, cx, y - 0.1, cz)

# ---------- exterior ----------

func _build_exterior() -> void:
	# grass ring around the house footprint
	Geom.box(120, 0.2, 51.5, 0x7fae62, 0, -0.12, -32.15, self)
	Geom.box(120, 0.2, 51.5, 0x7fae62, 0, -0.12, 32.15, self)
	Geom.box(51.5, 0.2, 13.3, 0x7fae62, -34.25, -0.12, 0, self)
	Geom.box(51.5, 0.2, 13.3, 0x7fae62, 34.25, -0.12, 0, self)
	# trees ring
	for i in range(14):
		var a := (float(i) / 14.0) * PI * 2.0
		var r := 22.0 + float(i % 4) * 5.0
		var tx := cos(a) * r
		var tz := sin(a) * r
		Geom.box(1.2, 3.2, 1.2, 0x5b8f4a, tx, 2.2, tz, self)
		Geom.box(0.5, 1.6, 0.5, 0x7a5a3a, tx, 0.6, tz, self)
	# fence
	for f in [[36.0, 0.3, 0.0, 15.0], [36.0, 0.3, 0.0, -15.0], [0.3, 30.0, 18.0, 0.0], [0.3, 30.0, -18.0, 0.0]]:
		Geom.box(f[0], 1.1, f[1], 0xb09a7a, f[2], 0.55, f[3], self)
	# roof ledge outside upstairs bedroom window
	Geom.box(4, 0.25, 3, 0x8a6a4a, -10, 2.95, -4, self)

# ---------- floors ----------

func _build_floors() -> void:
	floor_slab(-3, 0x9a8f80)                                                         # basement
	floor_slab(0, 0xc2a678, [{"minX": -2.4, "maxX": -0.45, "minZ": -6, "maxZ": -1.9}]) # main
	floor_slab(3, 0xb5936a, [{"minX": 0.7, "maxX": 2.5, "minZ": -5.1, "maxZ": -1.9}])  # upstairs
	# roof/ceiling above upstairs (visual only)
	Geom.box(16.6, 0.3, 12.6, 0x9a5d4a, 0, 3 + WALL_H + 0.15, 0, self)

# ---------- stairs ----------

func _build_stairs() -> void:
	for s in Global.STAIRS:
		var cx: float = (s.minX + s.maxX) / 2.0
		var w: float = s.maxX - s.minX
		var N := 12
		var run_len: float = abs(s.z1 - s.z0)
		# decorative visible steps (no collision)
		for i in range(N):
			var t := (float(i) + 0.5) / float(N)
			var z: float = s.z0 + (s.z1 - s.z0) * t
			var y: float = s.y0 + (s.y1 - s.y0) * t
			var c := 0x8a7a5f if i % 2 else 0x94826a
			Geom.box(w, 0.26, run_len / float(N) + 0.05, c, cx, y - 0.13, z, self)
		# invisible ramp collider spanning the run (reproduces groundY ramp walk)
		var horiz: float = abs(s.z1 - s.z0)
		var vert: float = s.y1 - s.y0
		var ramp_len := sqrt(horiz * horiz + vert * vert)
		var mid_z: float = (s.z0 + s.z1) / 2.0
		var mid_y: float = (s.y0 + s.y1) / 2.0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(w, 0.3, ramp_len)
		cs.shape = shape
		cs.position = Vector3(cx, mid_y, mid_z)
		# Incline: rotate about X so the slab's long (local +Z) axis follows the
		# run from (z0,y0) to (z1,y1). Under a rotation of phi about X, local +Z
		# maps to (0, -sin phi, cos phi); matching that to the run direction
		# (dz, dy) gives phi = atan2(-dy, dz).
		var angle := atan2(-(s.y1 - s.y0), s.z1 - s.z0)
		cs.rotation = Vector3(angle, 0, 0)
		col.add_child(cs)

	# stairwell core wall between the up and down runs (basement+main only)
	wall(0.7, 5.78, 3.3, 0.4, -0.11, -3.5, 0xcbbfa8)
	# upstairs railings (thin, waist height)
	wall(0.1, 0.95, 3.1, 0.72, 3.48, -3.45, 0xb9a077)
	wall(1.8, 0.95, 0.1, 1.6, 3.48, -1.85, 0xb9a077)
	# railing posts + top rails (visual only)
	for p in [[0.72, -4.95], [0.72, -3.45], [0.72, -1.9], [1.25, -1.85], [2.4, -1.85]]:
		Geom.box(0.09, 1.0, 0.09, 0x8a6a4a, p[0], 3.5, p[1], self)
	Geom.box(0.14, 0.06, 3.1, 0x8a6a4a, 0.72, 3.98, -3.45, self)
	Geom.box(1.8, 0.06, 0.14, 0x8a6a4a, 1.6, 3.98, -1.85, self)
	# railings around the main-floor opening (down run)
	wall(0.12, 4.4, 4.1, -2.42, -0.9, -3.95, 0x9a8a6a)
	wall(0.12, 4.4, 3.3, -0.5, -0.85, -3.5, 0x9a8a6a)

# ---------- perimeter walls ----------

func _build_perimeter_walls() -> void:
	var win_kitchen_gap := [4.4, 5.6]
	var win_bed_gap := [-4.6, -3.4]
	# main level perimeter
	wall_run("x", -6, -8, 8, 0, [win_kitchen_gap], WALL_COLOR)
	wall_run("x", 6, -8, 8, 0, [], WALL_COLOR)
	wall_run("z", -8, -6, 6, 0, [], WALL_COLOR)
	wall_run("z", 8, -6, 6, 0, [], WALL_COLOR)
	# window sills (block player, cat can hop over)
	wall(1.2, 1.0, 0.2, 5.0, 0.5, -6)
	wall(1.2, 0.6, 0.2, 5.0, WALL_H - 0.3, -6)  # header
	# upstairs perimeter
	wall_run("x", -6, -8, 8, 3, [], WALL_COLOR)
	wall_run("x", 6, -8, 8, 3, [], WALL_COLOR)
	wall_run("z", -8, -6, 6, 3, [win_bed_gap], WALL_COLOR)
	wall_run("z", 8, -6, 6, 3, [], WALL_COLOR)
	wall(0.2, 1.0, 1.2, -8, 3.5, -4)
	wall(0.2, 0.6, 1.2, -8, 3 + WALL_H - 0.3, -4)
	# basement perimeter
	wall_run("x", -6, -8, 8, -3, [], 0xa8a094)
	wall_run("x", 6, -8, 8, -3, [], 0xa8a094)
	wall_run("z", -8, -6, 6, -3, [], 0xa8a094)
	wall_run("z", 8, -6, 6, -3, [], 0xa8a094)

# ---------- interior walls ----------

func _build_interior_walls() -> void:
	wall_run("z", -2.5, -6, 6, 0, [[-1.7, -0.5], [2.2, 3.5]], 0xe8e0d0)
	wall_run("z", 2.5, -6, 6, 0, [[-1.7, -0.5], [2.2, 3.5]], 0xe8e0d0)
	wall_run("x", 0, -8, -2.5, 0, [[-6.2, -5.0]], 0xe8e0d0)
	wall_run("x", 0, 2.5, 8, 0, [[5.0, 6.2]], 0xe8e0d0)
	wall_run("x", 3.6, -2.5, 2.5, 0, [[-0.6, 0.6]], 0xe8e0d0)   # main bathroom front wall
	# upstairs
	wall_run("z", -1, -6, 6, 3, [[-3.5, -2.2], [2.2, 3.5]], 0xe8e0d0)
	wall_run("x", 0, -8, -1, 3, [], 0xe8e0d0)
	wall_run("z", 2.5, -6, -1, 3, [[-1.9, -1.0]], 0xe8e0d0)     # closet
	wall_run("x", -1, 2.5, 8, 3, [], 0xe8e0d0)
	wall_run("z", 2.5, 2, 6, 3, [[3.4, 4.6]], 0xe8e0d0)         # upstairs bath
	wall_run("x", 2, 2.5, 8, 3, [], 0xe8e0d0)
	# basement: one divider
	wall_run("x", 0, -8, 8, -3, [[-1.2, 1.2]], 0xb8b0a4)
