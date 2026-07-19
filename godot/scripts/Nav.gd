## Cat navigation grid — faithful port of the NAV GRID section of game.js
## (~1158-1276). A coarse per-level walkability grid, BFS pathfinding, and a
## line-of-sight "string pull" that straightens the path. Kept 1:1 (rather than
## Godot's NavigationAgent3D) because the multi-level routing in Cats.route_to
## drives explicit ramp hops between these per-floor grids.
class_name Nav
extends RefCounted

const CELL := 0.35
const X0 := -8.0
const Z0 := -6.0
const NX := 46
const NZ := 35

var grids: Dictionary = {}   # level (float) -> PackedByteArray (1 = walkable)

func _init(walls: Array) -> void:
	_build(walls)

func idx(ix: int, iz: int) -> int:
	return ix * NZ + iz

func cell(x: float, z: float) -> Vector2i:
	var ix := clampi(int(floor((x - X0) / CELL)), 0, NX - 1)
	var iz := clampi(int(floor((z - Z0) / CELL)), 0, NZ - 1)
	return Vector2i(ix, iz)

func world(ix: int, iz: int) -> Vector2:
	return Vector2(X0 + (ix + 0.5) * CELL, Z0 + (iz + 0.5) * CELL)

func _build(walls: Array) -> void:
	# stair footprints are traversed by explicit ramp segments, never grid paths
	var stair_rects: Array = []
	for s in Global.STAIRS:
		stair_rects.append({
			"minX": s.minX - 0.05, "maxX": s.maxX + 0.05,
			"minZ": min(s.z0, s.z1), "maxZ": max(s.z0, s.z1),
			"lvls": [s.y0, s.y1]})
	for lvl in Global.LEVELS:
		var g := PackedByteArray()
		g.resize(NX * NZ)
		for ix in range(NX):
			for iz in range(NZ):
				# a cell is walkable if its centre, inflated by the cat radius,
				# clears every wall. R must exceed collideCat's r=0.2 or paths
				# hug corners the collider then blocks.
				var cx := X0 + (ix + 0.5) * CELL
				var cz := Z0 + (iz + 0.5) * CELL
				var R := 0.24
				var blocked := false
				for w in walls:
					if w.maxY < lvl + 0.1 or w.minY > lvl + 0.5:
						continue
					if w.minX - R < cx and w.maxX + R > cx and w.minZ - R < cz and w.maxZ + R > cz:
						blocked = true
						break
				if not blocked:
					for r in stair_rects:
						if (r.lvls as Array).has(lvl) and r.minX < cx and r.maxX > cx and r.minZ < cz and r.maxZ > cz:
							blocked = true
							break
				g[idx(ix, iz)] = 0 if blocked else 1
		grids[lvl] = g

func nearest_ok_cell(g: PackedByteArray, ix: int, iz: int) -> Vector2i:
	if g[idx(ix, iz)] != 0:
		return Vector2i(ix, iz)
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if max(abs(dx), abs(dz)) != r:
					continue
				var nx := ix + dx
				var nz := iz + dz
				if nx < 0 or nz < 0 or nx >= NX or nz >= NZ:
					continue
				if g[idx(nx, nz)] != 0:
					return Vector2i(nx, nz)
	return Vector2i(-1, -1)

func los(g: PackedByteArray, a: Vector2i, b: Vector2i) -> bool:
	var wa := world(a.x, a.y)
	var wb := world(b.x, b.y)
	var d := wa.distance_to(wb)
	var steps: int = max(2, int(ceil(d / 0.1)))
	# sample the centre line plus two parallels offset by the cat's radius so a
	# string-pulled shortcut can't clip a corner the collider would catch
	var px := 0.0
	var pz := 0.0
	if d > 0.0:
		px = -(wb.y - wa.y) / d * 0.14
		pz = (wb.x - wa.x) / d * 0.14
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var x := wa.x + (wb.x - wa.x) * t
		var z := wa.y + (wb.y - wa.y) * t
		var offsets: Array[Vector2] = [Vector2(0, 0), Vector2(px, pz), Vector2(-px, -pz)]
		for off in offsets:
			var c := cell(x + off.x, z + off.y)
			if g[idx(c.x, c.y)] == 0:
				return false
	return true

## Path from (ax,az) to (bx,bz) on the given level, returned as an Array of
## [x, z] float pairs. Falls back to the direct point when no grid path exists.
func grid_path(lvl: float, ax: float, az: float, bx: float, bz: float) -> Array:
	if not grids.has(lvl):
		return [[bx, bz]]
	var g: PackedByteArray = grids[lvl]
	var sc := cell(ax, az)
	var tc := cell(bx, bz)
	var s := nearest_ok_cell(g, sc.x, sc.y)
	var t := nearest_ok_cell(g, tc.x, tc.y)
	if s.x < 0 or t.x < 0:
		return [[bx, bz]]
	var prev := PackedInt32Array()
	prev.resize(NX * NZ)
	prev.fill(-1)
	var si := idx(s.x, s.y)
	var ti := idx(t.x, t.y)
	prev[si] = si
	var q: Array = [si]
	var found := si == ti
	var qi := 0
	while qi < q.size() and not found:
		var cur: int = q[qi]
		qi += 1
		var ccx := cur / NZ
		var ccz := cur % NZ
		var deltas: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for step in deltas:
			var nx := ccx + step.x
			var nz := ccz + step.y
			if nx < 0 or nz < 0 or nx >= NX or nz >= NZ:
				continue
			var ni := idx(nx, nz)
			if g[ni] == 0 or prev[ni] != -1:
				continue
			prev[ni] = cur
			if ni == ti:
				found = true
				break
			q.append(ni)
	if not found:
		return [[bx, bz]]
	var cells: Array = []
	var cur2 := ti
	while true:
		cells.append(Vector2i(cur2 / NZ, cur2 % NZ))
		if cur2 == prev[cur2]:
			break
		cur2 = prev[cur2]
	cells.reverse()
	# string-pull: skip ahead while line of sight stays clear
	var pts: Array = []
	var i := 0
	while i < cells.size() - 1:
		var j := cells.size() - 1
		while j > i + 1 and not los(g, cells[i], cells[j]):
			j -= 1
		var w := world(cells[j].x, cells[j].y)
		pts.append([w.x, w.y])
		i = j
	pts.append([bx, bz])
	return pts

func random_nav_point(lvl: float) -> Vector2:
	if not grids.has(lvl):
		return Vector2.ZERO
	var g: PackedByteArray = grids[lvl]
	for tries in range(40):
		var ix := randi() % NX
		var iz := randi() % NZ
		if g[idx(ix, iz)] != 0:
			return world(ix, iz)
	return Vector2.ZERO
