## The cats: spawning, navigation, procedural animation, and the whole AI state
## machine. Faithful port of THE CATS + CAT ANIMATION + the updateCat loop of
## game.js (~1278-1792, 3305-3682).
##
## Cross-phase hooks are stubbed the same way Furniture/Interactor stub theirs:
## the computer (Phase 4) and the day loop / boss / vet overlay / audio / HUD
## (Phase 5) are represented by Global flags + Global.msg. Everything cat-shaped
## — nav grid pathing, per-activity poses, hazard/distraction seeking, hopping
## onto furniture, the shared hearts, hiding, window escapes, eating, barf — is
## live and driven from _process.
class_name Cats
extends Node3D

# ---------- wiring (set by Main before _ready runs its spawn) ----------
var furniture: Furniture
var player: Node3D
var camera: Camera3D
var interactor                       # Interactor — held item/cat lives there
var game                             # Game orchestrator (vet overlay + heart flash)
var audio: GameAudio                 # synthesized meows
var nav: Nav
var walls: Array = []                # world.walls, for collide_cat

var cats: Array[Cat] = []
var pending_adopts: Array = []       # {name, color_def} — new cats arrive next morning

var _now := 0.0                      # seconds clock for animation phase
var laser_dot: MeshInstance3D
var laser_t := 0.0
var _barf_counter := 0
var barf_pendings: Array = []        # [{t, pos:Vector3}]
var meow_loop_t := 2.1

# furniture a cat may hop onto: x/z/h = top spot, ax/az = approach offset into
# open room space, r = footprint radius (for dropping a held cat onto it)
const PERCHES := [
	{"name": "couch",           "x": -6.5, "z": 5.2,  "lvl": 0.0,  "h": 0.47, "ax": 0.0,  "az": -1.1, "r": 1.3},
	{"name": "coffee table",    "x": -4.6, "z": 3.0,  "lvl": 0.0,  "h": 0.45, "ax": 0.9,  "az": 0.0,  "r": 0.75},
	{"name": "dining table",    "x": 5.5,  "z": 3.5,  "lvl": 0.0,  "h": 0.82, "ax": 0.0,  "az": 1.2,  "r": 1.1},
	{"name": "kitchen counter", "x": 5.0,  "z": -5.3, "lvl": 0.0,  "h": 0.9,  "ax": 0.0,  "az": 1.0,  "r": 1.0},
	{"name": "bed",             "x": -6.5, "z": -4.9, "lvl": 3.0,  "h": 0.55, "ax": 0.0,  "az": 1.3,  "r": 1.2},
	{"name": "guest bed",       "x": -6.5, "z": 5.0,  "lvl": 3.0,  "h": 0.5,  "ax": 0.0,  "az": -1.3, "r": 1.1},
	{"name": "basement couch",  "x": -4.0, "z": 4.5,  "lvl": -3.0, "h": 0.44, "ax": 0.0,  "az": -1.1, "r": 1.2},
	{"name": "workbench",       "x": 5.5,  "z": -5.4, "lvl": -3.0, "h": 0.9,  "ax": 0.0,  "az": 1.0,  "r": 1.0},
]

func _ready() -> void:
	# the red laser dot, parked far below the world until fired
	laser_dot = Geom.box(0.15, 0.03, 0.15, 0xff2222, 0, -99, 0, self)

# ============================================================
# spawning
# ============================================================
func spawn_cat(name_: String, color_def: Dictionary, chaos: float) -> Cat:
	var c := Cat.new(name_, color_def, chaos, self)
	# one padded click volume that rides the cat, tagged for the interactor
	var pad := Geom.hit_pad(c.g, 0.45, 0, 0.28, 0)
	if furniture != null:
		furniture.register_interact(pad, {"act": "cat", "cat_ref": c})
	cats.append(c)
	return c

func pers(text: String, c: Cat) -> String:
	# swap the first "the cat"/"the cat's" for this cat's name
	var re := RegEx.new()
	re.compile("(?i)the cat('s)?")
	var m := re.search(text)
	if m == null:
		return text
	var poss := m.get_string(1)
	return text.substr(0, m.get_start()) + c.cat_name + poss + text.substr(m.get_end())

func cat_names_joined() -> String:
	var ns: Array = []
	for c in cats:
		ns.append(c.cat_name)
	return " & ".join(ns)

# yaw facing from a perch/surface back toward its approach side (≈ room centre)
func face_room_yaw(p: Dictionary) -> float:
	return atan2(-p.az, p.ax)

# ============================================================
# procedural poses
# ============================================================
func _sit_base(c: Cat, t: float) -> void:
	c.body.rotation.z = 0.5
	c.body.position = Vector3(-0.05, 0.26, 0)
	c.head.position = Vector3(0.24, 0.56, 0)
	c.legs[2].position.y = 0.06; c.legs[2].scale.y = 0.55
	c.legs[3].position.y = 0.06; c.legs[3].scale.y = 0.55
	c.legs[0].position = Vector3(0.2, 0.12, 0.1)
	c.legs[1].position = Vector3(0.2, 0.12, -0.1)
	c.tail.position = Vector3(-0.2, 0.08, 0.14)
	c.tail.rotation.y = 1.1 + sin(t * 1.5) * 0.15

func _rear_up_base(c: Cat, t: float) -> void:
	c.body.rotation.z = 0.95
	c.body.position = Vector3(-0.1, 0.34, 0)
	c.head.position = Vector3(0.1, 0.66, 0)
	c.head.rotation.z = -0.35
	c.legs[2].position = Vector3(-0.16, 0.1, 0.1)
	c.legs[3].position = Vector3(-0.16, 0.1, -0.1)
	c.legs[0].position = Vector3(0.12, 0.42, 0.1);  c.legs[0].rotation.z = -0.9
	c.legs[1].position = Vector3(0.12, 0.42, -0.1); c.legs[1].rotation.z = -0.9
	c.tail.position = Vector3(-0.34, 0.12, 0)
	c.tail.rotation.y = sin(t * 3) * 0.4

func _back_base(c: Cat, t: float) -> void:
	c.body.position.y = 0.16
	c.head.position = Vector3(0.34, 0.2, 0.06)
	c.head.rotation.x = 2.7
	c.tail.position = Vector3(-0.38, 0.1, 0)
	for i in range(4):
		c.legs[i].position.y = 0.34

func _apply_pose(key: String, c: Cat, t: float) -> void:
	match key:
		"stand":
			pass
		"walk":
			var w := sin(t * 11)
			c.legs[0].rotation.z = w * 0.6;  c.legs[3].rotation.z = w * 0.6
			c.legs[1].rotation.z = -w * 0.6; c.legs[2].rotation.z = -w * 0.6
			c.tail.rotation.z = 0.5
			c.tail.rotation.y = sin(t * 6) * 0.4
		"sit":
			_sit_base(c, t)
		"beg":
			_sit_base(c, t)
			c.head.rotation.z = 0.45 + max(0.0, sin(t * 3.2)) * 0.12
		"loaf":
			c.body.position.y = 0.15
			c.body.scale.y = 1 + sin(t * 2) * 0.04
			c.head.position = Vector3(0.3, 0.32, 0)
			for i in range(4):
				c.legs[i].scale.y = 0.3; c.legs[i].position.y = 0.03
			c.tail.position = Vector3(-0.16, 0.1, 0.15)
			c.tail.rotation.y = 1.35
		"curl":
			c.body.position.y = 0.13
			c.body.scale.y = 1 + sin(t * 1.6) * 0.05
			c.head.position = Vector3(0.22, 0.2, 0.06)
			c.head.rotation.z = -0.4
			for i in range(4):
				c.legs[i].scale.y = 0.25; c.legs[i].position.y = 0.03
			c.tail.position = Vector3(-0.1, 0.06, 0.17)
			c.tail.rotation.y = 1.5
		"roll":
			_back_base(c, t)
			for i in range(4):
				c.legs[i].rotation.z = sin(t * 7 + i * 1.8) * 0.5
				c.legs[i].position.y = 0.34 + sin(t * 5 + i * 2.2) * 0.04
			c.tail.rotation.y = sin(t * 7) * 0.8
		"tangle":
			_back_base(c, t)
			for i in range(4):
				c.legs[i].rotation.z = sin(t * 16 + i * 1.8) * 0.8
				c.legs[i].position.y = 0.34 + sin(t * 13 + i * 2.2) * 0.07
			c.head.rotation.x = 2.7 + sin(t * 10) * 0.3
			c.tail.rotation.y = sin(t * 15) * 1.0
		"eat":
			c.head.position = Vector3(0.4, 0.2 + abs(sin(t * 7)) * 0.04, 0)
			c.head.rotation.z = -0.75
			c.tail.rotation.z = 0.35
			c.tail.rotation.y = sin(t * 2.5) * 0.25
		"paw":
			_sit_base(c, t)
			c.head.position = Vector3(0.26, 0.5, 0)
			c.head.rotation.z = -0.25
			c.legs[0].position = Vector3(0.24, 0.24, 0.1)
			c.legs[0].rotation.z = -1.0 + sin(t * 9) * 0.7
		"fish":
			_sit_base(c, t)
			c.head.position = Vector3(0.28, 0.48, 0)
			c.head.rotation.z = -0.4
			c.legs[0].position = Vector3(0.27, 0.2, 0.06)
			c.legs[0].rotation.z = -1.3 + sin(t * 3.2) * 0.45
		"headIn":
			c.body.rotation.z = -0.45
			c.body.position = Vector3(0.02, 0.3, 0)
			c.head.position = Vector3(0.42, 0.12, 0)
			c.head.rotation.z = -0.5 + sin(t * 6) * 0.08
			c.legs[0].position = Vector3(0.2, 0.05, 0.1);  c.legs[0].scale.y = 0.55
			c.legs[1].position = Vector3(0.2, 0.05, -0.1); c.legs[1].scale.y = 0.55
			c.legs[2].position = Vector3(-0.2, 0.18, 0.1);  c.legs[2].scale.y = 1.25
			c.legs[3].position = Vector3(-0.2, 0.18, -0.1); c.legs[3].scale.y = 1.25
			c.tail.position = Vector3(-0.38, 0.5, 0)
			c.tail.rotation.z = 0.9
			c.tail.rotation.y = sin(t * 6) * 0.5
		"sniffHigh":
			_rear_up_base(c, t)
			c.head.rotation.z = -0.35 + sin(t * 5) * 0.1
		"climb":
			_rear_up_base(c, t)
			c.legs[0].position.y = 0.42 + sin(t * 12) * 0.07
			c.legs[1].position.y = 0.42 - sin(t * 12) * 0.07
		"scratch":
			_rear_up_base(c, t)
			c.legs[0].position.y = 0.44 + sin(t * 8) * 0.09
			c.legs[1].position.y = 0.44 - sin(t * 8) * 0.09
			c.tail.rotation.y = sin(t * 4) * 0.5
		"pounce":
			var cyc := fmod(t * 0.8, 1.0)
			if cyc < 0.6:
				c.body.position.y = 0.17
				c.head.position = Vector3(0.35, 0.3, 0)
				c.body.rotation.x = sin(t * 14) * 0.08
				c.tail.rotation.y = sin(t * 12) * 0.7
				for i in range(4):
					c.legs[i].scale.y = 0.6; c.legs[i].position.y = 0.05
			else:
				var k := (cyc - 0.6) / 0.4
				var arc := sin(PI * k) * 0.3
				c.body.position.y = 0.24 + arc
				c.head.position = Vector3(0.33, 0.42 + arc, 0)
				c.tail.position.y = 0.34 + arc
				for i in range(4):
					c.legs[i].position.y = 0.12 + arc
					c.legs[i].rotation.z = -0.5 if i < 2 else 0.5
		"watch":
			_sit_base(c, t)
			c.head.rotation.x = sin(t * 1.7) * 0.3
			c.head.position.y = 0.56 + max(0.0, sin(t * 0.9)) * 0.03
		"groom":
			_sit_base(c, t)
			c.head.position = Vector3(0.16, 0.34, 0.1)
			c.head.rotation.y = -0.7 + sin(t * 8) * 0.12
			c.head.rotation.z = -0.5
		"dangle":
			for i in range(4):
				c.legs[i].rotation.z = sin(t * 2 + i) * 0.25
			c.tail.rotation.y = sin(t * 1.5) * 0.3
		"jump":
			c.body.rotation.z = 0.22
			c.head.position = Vector3(0.36, 0.5, 0)
			c.legs[0].rotation.z = -0.9; c.legs[1].rotation.z = -0.9
			c.legs[2].rotation.z = 0.8;  c.legs[3].rotation.z = 0.8
			c.tail.rotation.z = 0.5
		_:
			pass

func animate_cat(c: Cat) -> void:
	if c.mode == "carrier":
		return
	var t := _now + c.chaos * 13.0
	c.reset_pose()
	var key := "stand"
	match c.mode:
		"walk": key = "walk"
		"hop": key = "jump"
		"danger":
			var h = furniture.hazards.get(c.target)
			key = h.get("anim", "paw") if h != null else "paw"
		"outside": key = "sit"
		"distracted":
			var d = furniture.distracts.get(c.distract_id) if c.distract_id != null else null
			if c.distract_id == "laser":
				key = "pounce"
			elif d != null:
				key = d.anim
			else:
				key = "curl"
		"eating": key = "eat"
		"waitFood", "pester": key = "beg"
		"hiddenNap": key = "curl"
		"held": key = "dangle"
		"introSit": key = "sit"
		"perched": key = "loaf" if c.idle_pose == "roll" else c.idle_pose
		"wander": key = c.idle_pose
	_apply_pose(key, c, t)

func pick_idle_pose() -> String:
	var r := randf()
	return "sit" if r < 0.45 else ("loaf" if r < 0.7 else ("roll" if r < 0.85 else "groom"))

func start_hop(c: Cat, to: Vector3, upward: bool) -> void:
	c.mode = "hop"
	c.hop_upward = upward
	c.hop_t = 0.0
	c.hop_dur = 0.5 if upward else 0.45
	c.hop_from = c.g.position
	c.hop_to = to
	c.g.rotation.y = atan2(-(to.z - c.hop_from.z), to.x - c.hop_from.x)

# ============================================================
# navigation / routing
# ============================================================
func route_to(c: Cat, x: float, y: float, z: float) -> Array:
	var from := Global.nearest_level(c.g.position.y)
	var to := Global.nearest_level(y)
	var UP_IN := Vector2(1.6, -1.5)
	var UP_OUT := Vector2(1.6, -5.45)
	var DN_IN := Vector2(-1.45, -1.5)
	var DN_OUT := Vector2(-1.45, -5.45)
	var hops: Array = []
	if from == 0.0 and to == 3.0:
		hops.append({"e": UP_IN, "x": UP_OUT, "l": 3.0})
	elif from == 3.0 and to == 0.0:
		hops.append({"e": UP_OUT, "x": UP_IN, "l": 0.0})
	elif from == 0.0 and to == -3.0:
		hops.append({"e": DN_IN, "x": DN_OUT, "l": -3.0})
	elif from == -3.0 and to == 0.0:
		hops.append({"e": DN_OUT, "x": DN_IN, "l": 0.0})
	elif from == 3.0 and to == -3.0:
		hops.append({"e": UP_OUT, "x": UP_IN, "l": 0.0})
		hops.append({"e": DN_IN, "x": DN_OUT, "l": -3.0})
	elif from == -3.0 and to == 3.0:
		hops.append({"e": DN_OUT, "x": DN_IN, "l": 0.0})
		hops.append({"e": UP_IN, "x": UP_OUT, "l": 3.0})
	var pts: Array = []
	var cur := Vector2(c.g.position.x, c.g.position.z)
	var lvl := from
	for h in hops:
		var e: Vector2 = h.e
		var xo: Vector2 = h.x
		pts.append_array(nav.grid_path(lvl, cur.x, cur.y, e.x, e.y))
		pts.append([xo.x, xo.y])   # ramp traversal (ground_y handles the slope)
		cur = xo
		lvl = h.l
	pts.append_array(nav.grid_path(lvl, cur.x, cur.y, x, z))
	return pts

func cat_go_to(c: Cat, x: float, y: float, z: float, next_mode, target_id = null) -> void:
	var lvl := Global.nearest_level(c.g.position.y)
	if c.g.position.y > lvl + 0.25:
		# up on something — hop down to the floor first, then walk
		var sf = c.surf if c.surf != null else c.perch
		var tx: float = (sf.x + sf.ax) if sf != null else c.g.position.x
		var tz: float = (sf.z + sf.az) if sf != null else c.g.position.z
		c.surf = null
		c.after_hop = null
		c.go_after_hop = {"x": x, "y": y, "z": z, "next_mode": next_mode, "target_id": target_id}
		start_hop(c, Vector3(tx, lvl, tz), false)
		return
	c.waypoints = route_to(c, x, y, z)
	c.mode = "walk"
	c.next_mode = next_mode
	c.target = target_id
	c.dest = {"x": x, "y": y, "z": z}
	c.stuck_t = 0.0
	c.repathed = false

# ============================================================
# hazards + danger
# ============================================================
func hazard_armed(h) -> bool:
	if h == null:
		return false
	return (h.type == "toggle" and h.armed) \
		or (h.type == "item" and not h.stashed and not h.held) \
		or (h.type == "barf" and not h.cleaned)

func enter_danger(c: Cat, h: Dictionary) -> void:
	c.mode = "danger"
	c.target = h.id
	c.hurt_t = 8.0
	c.danger_age = 0.0
	c.hearts_lost_here = 0
	Global.msg("🙀 " + pers(h.dangerText, c), "danger")
	Global.msg("(faint meowing from %s)" % Global.room_name(c.g.position.x, c.g.position.y, c.g.position.z), "")

func dismount_then_wander(c: Cat) -> void:
	var lvl := Global.nearest_level(c.g.position.y)
	if c.g.position.y > lvl + 0.25:
		var sf = c.surf if c.surf != null else c.perch
		var tx: float = (sf.x + sf.ax) if sf != null else c.g.position.x + 0.7
		var tz: float = (sf.z + sf.az) if sf != null else c.g.position.z + 0.7
		c.surf = null
		start_hop(c, Vector3(tx, lvl, tz), false)
	else:
		c.mode = "wander"
		c.idle_t = 2 + randf() * 2
		c.idle_pose = pick_idle_pose()

func armed_hazard_list() -> Array:
	var out: Array = []
	for h in furniture.hazards.values():
		if h.type == "barf":
			if not h.cleaned:
				out.append(h)
			continue
		if int(h.get("tier", 99)) > Global.phase:
			continue
		if h.type == "toggle" and h.armed:
			out.append(h)
		elif h.type == "item" and not h.stashed and not h.held and not h.get("safeItem", false):
			out.append(h)
	return out

func cat_decide(c: Cat) -> void:
	if Global.game_over or not Global.tutorial_done:
		c.idle_t = 1.0
		return
	var armed := armed_hazard_list()
	var base := 0.14 if Global.phase == 1 else (0.32 if Global.phase == 2 else 0.5)
	var seek_chance: float = min(0.75, base * c.chaos)
	var bowl_full: bool = furniture.bowl_full
	var bowl_pos: Vector3 = furniture.bowl.position
	if bowl_full and c.full <= 0 and randf() < 0.5:
		cat_go_to(c, bowl_pos.x, 0, bowl_pos.z, "eating")
		return
	if bowl_full and c.full > 0 and randf() < 0.35:
		# a full cat going back for seconds — that's the overeating hazard
		cat_go_to(c, bowl_pos.x, 0, bowl_pos.z, "eating")
		return
	if not armed.is_empty() and randf() < seek_chance:
		var h: Dictionary = armed[randi() % armed.size()]
		var p: Vector3 = h.mesh.position
		var sf = h.get("curSurface")
		if sf != null:
			cat_go_to(c, sf.x + sf.ax, p.y, sf.z + sf.az, "danger", h.id)
		else:
			cat_go_to(c, p.x, p.y, p.z, "danger", h.id)
		return
	# early game the cat mostly wants YOU
	if Global.in_computer and randf() < (0.5 if Global.phase == 1 else 0.35):
		var ply: Vector3 = player.global_position if player != null else Vector3.ZERO
		cat_go_to(c, ply.x + 0.5, Global.nearest_level(ply.y), ply.z, "pester")
		return
	# sometimes: jump up on the furniture, because it's there
	if randf() < 0.16:
		var lvl := Global.nearest_level(c.g.position.y)
		var opts: Array = []
		for p in PERCHES:
			if p.lvl == lvl:
				opts.append(p)
		if not opts.is_empty():
			var pr: Dictionary = opts[randi() % opts.size()]
			c.perch = pr
			cat_go_to(c, pr.x + pr.ax, lvl, pr.z + pr.az, "hopUp")
			return
	# wander — the main floor during the tutorial-ish phase, then the whole house
	var lvls: Array = [0.0] if Global.phase == 1 else Global.LEVELS
	var lvl2: float = lvls[randi() % lvls.size()]
	var pt := nav.random_nav_point(lvl2)
	cat_go_to(c, pt.x, lvl2, pt.y, "wanderIdle")

# ============================================================
# distractions
# ============================================================
func distract_time(c: Cat, d: Dictionary) -> float:
	var uses: int = int(c.distract_uses.get(d.id, 0))
	return max(Global.DISTRACT_MIN, d.time / pow(2, uses))

func on_toy(c: Cat, id: String) -> bool:
	return c.distract_id == id and \
		(c.mode == "distracted" or (c.mode == "walk" and c.next_mode == "distracted"))

func distract_cat(id: String) -> void:
	var d = furniture.distracts.get(id)
	if d == null or not d.owned:
		return
	# one cat per distraction: a cat already on this toy locks it until done
	var occupant: Cat = null
	for c in cats:
		if on_toy(c, id):
			occupant = c
			break
	if occupant != null:
		Global.msg("→ %s: %s is already on it (%ds left)" % [d.label, occupant.cat_name, int(max(1, ceil(occupant.distract_t)))], "")
		return
	# eligible = free to be lured (not held/away/eating, not busy with a different toy)
	var eligible: Array[Cat] = []
	for c in cats:
		var m := c.mode
		if m in ["held", "carrier", "outside", "hiddenNap", "waitFood", "eating", "hop"]:
			continue
		if c.distract_id != null and c.distract_id != id and \
			(m == "distracted" or (m == "walk" and c.next_mode == "distracted")):
			continue
		eligible.append(c)
	if eligible.is_empty():
		Global.msg("Nobody is interested right now. Tough crowd.")
		return
	# grab the single nearest eligible cat
	var chosen: Cat = eligible[0]
	var best := INF
	var dpos: Vector3 = d.pos
	for cand in eligible:
		var dx: float = cand.g.position.x - dpos.x
		var dz: float = cand.g.position.z - dpos.z
		var dist := dx * dx + dz * dz
		if dist < best:
			best = dist
			chosen = cand
	end_danger(chosen, false)
	var t := distract_time(chosen, d)
	chosen.distract_uses[d.id] = int(chosen.distract_uses.get(d.id, 0)) + 1
	var sf = d.get("surface")
	if sf != null:
		cat_go_to(chosen, sf.x + sf.ax, dpos.y, sf.z + sf.az, "distracted")
	else:
		cat_go_to(chosen, dpos.x, dpos.y, dpos.z, "distracted")
	chosen.distract_t = t
	chosen.distract_id = d.id
	var bored := ("is pretty bored of it (%ds)" % int(round(t))) if t <= Global.DISTRACT_MIN + 0.01 else ("(%ds)" % int(round(t)))
	Global.msg("→ %s: %s %s" % [d.label, chosen.cat_name, bored], "good")

func end_danger(c: Cat, announce := true) -> void:
	if c.mode == "danger" or c.mode == "outside":
		if announce:
			Global.msg("%s is safe. For now." % c.cat_name, "good")
		c.outside = false
		c.outside_haz = null
		dismount_then_wander(c)

# ============================================================
# hearts / hurt / vet
# ============================================================
func hurt_cat(c: Cat, reason: String) -> void:
	if Global.hearts <= 1:
		return   # the cat never dies — the vet run is already happening
	Global.hearts -= 1
	Global.hearts_lost_today += 1
	Global.hearts_changed.emit(Global.hearts)
	if audio != null:
		audio.play_hurt_meow(c.g.position)
	if game != null:
		game.flash_hearts()
	Global.msg("💔 %s (%d hearts left)" % [pers(reason, c), Global.hearts], "danger")
	if Global.hearts <= 1:
		vet_visit(c)

## The gameplay half of the emergency vet run. The full overlay + economy screen
## is Phase 5; here we do the state reset so cats/hearts don't wedge.
func vet_visit(c: Cat) -> void:
	if Global.vet_today:
		return
	Global.vet_today = true
	var bill := Global.money
	Global.money = 0
	Global.hearts = Global.HEART_MAX
	Global.hearts_changed.emit(Global.hearts)
	for h in furniture.hazards.values():
		if h.type == "toggle" and h.armed:
			h.armed = false
			furniture.apply_toggle_vis(h)
	for cc in cats:
		end_danger(cc, false)
		cc.mode = "wander"
		cc.idle_t = 6.0
		cc.outside = false
		cc.outside_haz = null
		cc.surf = null
		cc.after_hop = null
		cc.go_after_hop = null
		var lvl := Global.nearest_level(cc.g.position.y)
		if lvl != cc.g.position.y:
			cc.g.position.y = lvl
	Global.day_stage = "evening"
	if game != null:
		game.on_vet(c, bill)
	else:
		Global.msg("🏥 VET EMERGENCY: %s was down to its last heart. The bill was $%d — exactly what you had." % [c.cat_name, bill], "danger")

# ============================================================
# collision (shorter than the player — cats squeeze under things)
# ============================================================
func collide_cat(nx: float, nz: float, y: float) -> Vector2:
	var r := 0.2
	for w in walls:
		if y + 0.55 < w.minY or y + 0.08 > w.maxY:
			continue
		var cx: float = clampf(nx, w.minX, w.maxX)
		var cz: float = clampf(nz, w.minZ, w.maxZ)
		var dx := nx - cx
		var dz := nz - cz
		var d2 := dx * dx + dz * dz
		if d2 < r * r:
			var d := sqrt(d2)
			if d == 0.0:
				d = 0.001
			nx = cx + (dx / d) * r
			nz = cz + (dz / d) * r
	return Vector2(nx, nz)

# ============================================================
# barf + laser
# ============================================================
func spawn_barf(x: float, y: float, z: float) -> void:
	var b := Geom.box(0.35, 0.06, 0.35, 0x88aa33, x, y + 0.04, z, self)
	var id := "barf%d" % _barf_counter
	_barf_counter += 1
	furniture.hazards[id] = {"id": id, "type": "barf", "mesh": b, "cleaned": false,
		"name": "cat barf", "anim": "eat", "tier": 1, "stashed": false, "held": false,
		"dangerText": "The cat is EATING ITS OWN BARF. Why. WHY."}
	furniture.register_interact(b, {"act": "barf", "id": id})
	Global.msg("Someone barfed somewhere... find it before it gets re-eaten.", "danger")

## Left-clicking the floor while holding the laser pointer (called by Interactor).
func fire_laser(point: Vector3) -> void:
	laser_dot.position = Vector3(point.x, point.y, point.z)
	laser_t = 8.0
	var floor_y := Global.nearest_level(point.y)
	for c in cats:
		var m := c.mode
		if m in ["held", "carrier", "outside", "hiddenNap", "waitFood", "eating", "hop"]:
			continue
		end_danger(c, false)
		cat_go_to(c, point.x, floor_y, point.z, "distracted")
		c.distract_t = 8.0
		c.distract_id = "laser"
	Global.msg("The red dot. The cats MUST have the red dot.", "good")

# ============================================================
# picking up / putting down a cat (Interactor routes the clicks here)
# ============================================================
func pick_up_cat(c: Cat) -> void:
	var cam_pos: Vector3 = camera.global_position
	if cam_pos.distance_to(c.g.position) > 3.4:
		return
	if c.no_hold_t > 0:
		Global.msg("😾 %s is not in the mood to be held right now. (%ds)" % [c.cat_name, int(ceil(c.no_hold_t))])
		return
	if c.mode == "hiddenNap":
		Global.msg("😌 There you are! %s was just asleep in %s. False alarm." % [c.cat_name, Global.room_name(c.g.position.x, c.g.position.y, c.g.position.z)], "good")
	end_danger(c, false)
	interactor.held = c
	c.mode = "held"
	c.held_t = 12.0
	c.squirm_warned = false
	c.outside = false
	c.outside_haz = null
	c.surf = null
	c.after_hop = null
	c.go_after_hop = null
	interactor._set_held_text("🤚 Holding: %s (purring). Right-click to put down (bonus: drop it on the cat bed)." % c.cat_name.to_upper())
	Global.msg("You scooped up %s. It is furious and also purring." % c.cat_name, "good")

func drop_cat_at(c: Cat) -> void:
	interactor.held = null
	interactor._set_held_text("")
	var cam_pos: Vector3 = camera.global_position
	var fwd := -camera.global_transform.basis.z
	var ply: Vector3 = player.global_position
	var px := ply.x + fwd.x * 0.8
	var pz := ply.z + fwd.z * 0.8
	c.g.position = Vector3(px, Global.ground_y(px, pz, ply.y), pz)
	# hand-delivered to the cat bed → a longer, bonus distraction
	var cat_bed: Node3D = furniture.cat_bed
	if cat_bed != null and c.g.position.distance_to(cat_bed.position) < 1.2:
		var d: Dictionary = furniture.distracts["bed"]
		var t: float = max(Global.DISTRACT_MIN, distract_time(c, d) + 7)
		c.distract_uses["bed"] = int(c.distract_uses.get("bed", 0)) + 1
		c.mode = "distracted"
		c.distract_t = t
		c.distract_id = "bed"
		c.waypoints = []
		Global.msg("%s curls up in the bed. %d blissful seconds of productivity." % [c.cat_name, int(round(t))], "good")
		return
	# dropped onto furniture? settle the cat ON it, facing the room
	var lvl := Global.nearest_level(ply.y)
	for p in PERCHES:
		if p.lvl != lvl or Vector2(px - p.x, pz - p.z).length() > float(p.get("r", 0.9)):
			continue
		c.g.position = Vector3(px, lvl + p.h, pz)
		c.g.rotation.y = face_room_yaw(p)
		c.mode = "perched"
		c.perch = p
		c.perch_t = 10 + randf() * 15
		c.idle_pose = "sit" if randf() < 0.55 else "loaf"
		c.waypoints = []
		Global.msg("%s settles on the %s." % [c.cat_name, p.name], "good")
		return
	if furniture.bowl_full and c.full <= 0:
		var bp: Vector3 = furniture.bowl.position
		cat_go_to(c, bp.x, 0, bp.z, "eating")
		return
	c.mode = "wander"
	c.idle_t = 1.5

# ============================================================
# release the cats from the carrier (openCarrier). The intro tutorial gating is
# Phase 5; here the cats simply toddle out and go about their business.
# ============================================================
func release_cats() -> void:
	for i in range(cats.size()):
		var c: Cat = cats[i]
		c.g.visible = true
		c.g.position = Vector3(-0.6, 0, 1.05)
		c.mode = "walk"
		c.next_mode = "introSit"
		var wx := -0.5 + (i - (cats.size() - 1) / 2.0) * 0.85
		var wz := 0.65 - (i % 2) * 0.25
		c.waypoints = [[wx, wz]]
	Global.msg("The cats wobble out of the carrier and stretch.", "good")

## The bowl was just filled — hungry wandering cats come running (busy/full cats
## don't). Mirrors the loop in the web build's fillBowl.
func on_bowl_filled() -> void:
	var bp: Vector3 = furniture.bowl.position
	for c in cats:
		if c.full > 0:
			continue
		if c.mode == "wander" or (c.mode == "walk" and c.next_mode == "wanderIdle"):
			cat_go_to(c, bp.x, 0, bp.z, "eating")

## Stand-in for the Phase-5 tutorial button: flip the settled-in cats to active
## and arm the starter hazard, so the AI runs without the day loop.
func begin_play() -> void:
	for c in cats:
		if c.mode == "introSit" or c.mode == "walk":
			c.mode = "wander"
			c.idle_t = 0.5 + randf()
	var toilet = furniture.hazards.get("toilet1")
	if toilet != null:
		toilet.armed = true
		furniture.apply_toggle_vis(toilet)

## The "…it's too quiet" hide event (Phase 5's day loop schedules this; exposed
## as a method so it can be triggered without the day loop).
func trigger_quiet() -> bool:
	var cands: Array[Cat] = []
	for c in cats:
		if c.mode == "wander" or c.mode == "walk":
			cands.append(c)
	if cands.is_empty():
		return false
	var c: Cat = cands[randi() % cands.size()]
	var lvl: float = Global.LEVELS[randi() % Global.LEVELS.size()]
	var pt := nav.random_nav_point(lvl)
	cat_go_to(c, pt.x, lvl, pt.y, "hiddenNap")
	Global.msg("🤫 ...it's too quiet. TOO quiet. What is %s doing?" % c.cat_name, "danger")
	return true

# ============================================================
# per-frame update
# ============================================================
func _process(dt: float) -> void:
	_now = Time.get_ticks_msec() / 1000.0
	if Global.tutorial_done:
		Global.play_clock += dt
	# fullness decay + barf spawning
	for c in cats:
		if c.full > 0:
			c.full -= dt
	for i in range(barf_pendings.size() - 1, -1, -1):
		barf_pendings[i].t -= dt
		if barf_pendings[i].t <= 0:
			var p: Vector3 = barf_pendings[i].pos
			spawn_barf(p.x, Global.nearest_level(p.y), p.z)
			barf_pendings.remove_at(i)
	# laser dot lifetime
	if laser_t > 0:
		laser_t -= dt
		if laser_t <= 0:
			laser_dot.position.y = -99
	# the cats
	for c in cats:
		update_cat(c, dt)
	# status lines (HUD arrives in Phase 5; emit for whoever's listening)
	var parts: Array = []
	for c in cats:
		match c.mode:
			"danger": parts.append("😿 %s: meowing from %s" % [c.cat_name, Global.room_name(c.g.position.x, c.g.position.y, c.g.position.z)])
			"outside": parts.append("🙀 %s IS OUTSIDE!" % c.cat_name)
			"distracted": parts.append("😸 %s: happily distracted" % c.cat_name)
			"held": parts.append("😻 %s (purring)" % c.cat_name)
			"pester": parts.append("😼 %s wants YOUR attention" % c.cat_name)
			"waitFood": parts.append("🍽 %s is HUNGRY — fill the food bowl!" % c.cat_name)
			"hiddenNap": parts.append("🤫 %s: ...suspiciously quiet. Go find it." % c.cat_name)
	Global.cat_status.emit(parts)

func update_cat(c: Cat, dt: float) -> void:
	animate_cat(c)
	if c.no_hold_t > 0:
		c.no_hold_t -= dt

	if c.mode == "carrier" or c.mode == "introSit":
		return

	if c.mode == "hop":
		c.hop_t += dt
		var k: float = min(1.0, c.hop_t / c.hop_dur)
		c.g.position.x = c.hop_from.x + (c.hop_to.x - c.hop_from.x) * k
		c.g.position.z = c.hop_from.z + (c.hop_to.z - c.hop_from.z) * k
		c.g.position.y = c.hop_from.y + (c.hop_to.y - c.hop_from.y) * k + sin(PI * k) * 0.4
		if k >= 1.0:
			if c.go_after_hop != null:
				var g2 = c.go_after_hop
				c.go_after_hop = null
				cat_go_to(c, g2.x, g2.y, g2.z, g2.next_mode, g2.target_id)
				return
			if c.after_hop != null:
				var a = c.after_hop
				c.after_hop = null
				c.surf = a.sf
				if a.mode == "danger":
					var h = furniture.hazards.get(a.target)
					if hazard_armed(h):
						enter_danger(c, h)
						var p: Vector3 = h.mesh.position
						c.g.rotation.y = atan2(-(p.z - c.g.position.z), p.x - c.g.position.x)
					else:
						dismount_then_wander(c)
				else:
					c.mode = "distracted"
					c.g.rotation.y = face_room_yaw(a.sf)
				return
			if c.hop_upward:
				c.mode = "perched"
				c.perch_t = 8 + randf() * 14
				c.idle_pose = "sit" if randf() < 0.55 else "loaf"
				if c.perch != null:
					c.g.rotation.y = face_room_yaw(c.perch)
			else:
				c.mode = "wander"
				c.idle_t = 1.5
		return

	if c.mode == "perched":
		c.perch_t -= dt
		if c.perch_t <= 0 and c.perch != null:
			var lvl := Global.nearest_level(c.g.position.y)
			start_hop(c, Vector3(c.perch.x + c.perch.ax, lvl, c.perch.z + c.perch.az), false)
		return

	if c.mode == "held":
		c.held_t -= dt
		if c.held_t <= 3 and not c.squirm_warned:
			c.squirm_warned = true
			Global.msg("😾 %s is getting squirmy..." % c.cat_name)
		if c.held_t <= 0:
			interactor.held = null
			interactor._set_held_text("")
			var dir := -camera.global_transform.basis.z
			var ply: Vector3 = player.global_position
			var px := ply.x + dir.x * 0.7
			var pz := ply.z + dir.z * 0.7
			c.g.position = Vector3(px, Global.ground_y(px, pz, ply.y), pz)
			c.mode = "wander"
			c.idle_t = 1.5
			c.no_hold_t = 20.0
			Global.msg("🐈 %s squirmed out of your arms! It needs some space now." % c.cat_name, "danger")
			return
		var dir2 := -camera.global_transform.basis.z
		var cam_pos: Vector3 = camera.global_position
		c.g.position = Vector3(cam_pos.x + dir2.x * 0.6, cam_pos.y - 0.7, cam_pos.z + dir2.z * 0.6)
		c.g.rotation.y = player.yaw + PI / 2.0
		return

	if c.mode == "outside":
		c.hurt_t -= dt
		if c.hurt_t <= 0:
			c.hurt_t = 8.0
			hurt_cat(c, c.outside_text if c.outside_text != "" else "The cat is having adventures outside. Bad ones.")
		return

	if c.mode == "walk":
		if c.waypoints.is_empty():
			_arrive(c)
			return
		var wp: Array = c.waypoints[0]
		var tx: float = wp[0]
		var tz: float = wp[1]
		var dx := tx - c.g.position.x
		var dz := tz - c.g.position.z
		var d := sqrt(dx * dx + dz * dz)
		var arrive_r := 0.45 if c.waypoints.size() == 1 else 0.3
		if d < arrive_r:
			c.waypoints.pop_front()
			c.stuck_t = 0.0
			return
		var tension: float = min(1.0, Global.play_clock / 540.0)
		var sp := c.speed * (1 + tension * 0.4) * dt
		var nx := c.g.position.x + (dx / d) * sp
		var nz := c.g.position.z + (dz / d) * sp
		var col := collide_cat(nx, nz, c.g.position.y)
		nx = col.x
		nz = col.y
		var moved := Vector2(nx - c.g.position.x, nz - c.g.position.z).length()
		if moved < sp * 0.35:
			c.stuck_t += dt
			if c.stuck_t > 2.5:
				c.waypoints.pop_front()
				c.stuck_t = 0.0
				return
			if c.stuck_t > 1.2 and not c.repathed and c.dest != null:
				c.repathed = true
				c.waypoints = route_to(c, c.dest.x, c.dest.y, c.dest.z)
				return
		else:
			c.stuck_t = 0.0
			c.repathed = false
		c.g.position.x = nx
		c.g.position.z = nz
		c.g.position.y = Global.ground_y(c.g.position.x, c.g.position.z, c.g.position.y)
		c.g.rotation.y = atan2(-dz, dx)
		c.g.position.y += abs(sin(_now * 0.012 * 1000.0 + c.chaos * 5)) * 0.04
		return

	if c.mode == "danger":
		c.hurt_t -= dt
		c.danger_age += dt
		var h = furniture.hazards.get(c.target)
		if not hazard_armed(h):
			end_danger(c)
			return
		if c.hurt_t <= 0:
			c.hurt_t = 7.0
			hurt_cat(c, h.dangerText)
			c.hearts_lost_here += 1
			if c.hearts_lost_here >= 2 and not h.get("isWindow", false):
				Global.msg("😾 %s got bored of that particular near-death experience and wandered off." % c.cat_name, "")
				dismount_then_wander(c)
				c.idle_t = 4.0
				return
		if h.get("isWindow", false) and c.danger_age > 10 and not c.outside:
			c.mode = "outside"
			c.outside = true
			c.outside_haz = h.id
			c.outside_text = h.outsideText
			c.hurt_t = 8.0
			c.g.position = h.outsidePos
			Global.msg("🙀 " + pers(h.outsideText, c) + " Go to the window and grab it!", "danger")
		return

	if c.mode == "waitFood":
		if furniture.bowl_full:
			c.morning_eat = true
			var bp: Vector3 = furniture.bowl.position
			cat_go_to(c, bp.x, 0, bp.z, "eating")
		return

	if c.mode == "hiddenNap":
		c.nap_t -= dt
		var ply: Vector3 = player.global_position
		var pd := Vector2(c.g.position.x - ply.x, c.g.position.z - ply.z).length()
		if pd < 2.6 and abs(c.g.position.y - ply.y) < 1.6:
			Global.msg("😌 Found %s — fast asleep in %s. False alarm." % [c.cat_name, Global.room_name(c.g.position.x, c.g.position.y, c.g.position.z)], "good")
			c.mode = "distracted"
			c.distract_t = 25.0
			c.distract_id = null
		elif c.nap_t <= 0:
			Global.msg("%s woke up from a secret nap somewhere. Refreshed. Dangerous." % c.cat_name)
			c.mode = "wander"
			c.idle_t = 1.0
		return

	if c.mode == "eating":
		c.eat_t -= dt
		if c.eat_t <= 0:
			_finish_eating(c)
		return

	if c.mode == "distracted":
		c.distract_t -= dt
		if c.distract_t <= 0:
			dismount_then_wander(c)
		return

	if c.mode == "pester":
		c.pester_t -= dt
		var ply: Vector3 = player.global_position
		var dx := ply.x - c.g.position.x
		var dz := ply.z - c.g.position.z
		var d := sqrt(dx * dx + dz * dz)
		if d > 1.0:
			var nx := c.g.position.x + (dx / d) * c.speed * dt
			var nz := c.g.position.z + (dz / d) * c.speed * dt
			var col := collide_cat(nx, nz, c.g.position.y)
			c.g.position.x = col.x
			c.g.position.z = col.y
			c.g.position.y = Global.ground_y(c.g.position.x, c.g.position.z, c.g.position.y)
		if c.pester_t <= 0:
			c.mode = "wander"
			c.idle_t = 1.0
		return

	# wander / idle
	c.idle_t -= dt
	if c.idle_t <= 0:
		cat_decide(c)

# arrived at the end of a walk — enter the queued next activity
func _arrive(c: Cat) -> void:
	var nm = c.next_mode
	if nm == "introSit":
		c.mode = "introSit"
	elif nm == "danger":
		var h = furniture.hazards.get(c.target)
		if hazard_armed(h):
			var sf = h.get("curSurface")
			if sf != null:
				c.after_hop = {"mode": "danger", "target": c.target, "sf": sf}
				start_hop(c, Vector3(sf.x, Global.nearest_level(c.g.position.y) + sf.h, sf.z), true)
			else:
				enter_danger(c, h)
		else:
			c.mode = "wander"; c.idle_t = 1.0
	elif nm == "eating":
		if furniture.bowl_full:
			c.mode = "eating"
			c.eat_t = 3.5
		else:
			c.mode = "wander"; c.idle_t = 1.0
	elif nm == "distracted":
		var d = furniture.distracts.get(c.distract_id) if c.distract_id != null else null
		var sf = d.get("surface") if d != null else null
		if sf != null:
			c.after_hop = {"mode": "distracted", "sf": sf}
			start_hop(c, Vector3(sf.x, Global.nearest_level(c.g.position.y) + sf.h, sf.z), true)
		else:
			c.mode = "distracted"
	elif nm == "hiddenNap":
		c.mode = "hiddenNap"
		c.nap_t = 75.0
	elif nm == "pester":
		c.mode = "pester"
		c.pester_t = 12.0
		Global.msg("😼 %s has arrived to help you type." % c.cat_name, "danger")
	elif nm == "hopUp" and c.perch != null:
		var lvl := Global.nearest_level(c.g.position.y)
		start_hop(c, Vector3(c.perch.x, lvl + c.perch.h, c.perch.z), true)
	else:
		c.mode = "wander"
		c.idle_t = 2 + randf() * 3
		c.idle_pose = pick_idle_pose()

func _finish_eating(c: Cat) -> void:
	if c.morning_eat:
		c.morning_eat = false
		c.full = 50.0
		c.mode = "distracted"
		c.distract_t = 40.0
		c.distract_id = null
		Global.msg("😸 %s had breakfast. Content — for a while." % c.cat_name, "good")
		var anyone := false
		for cc in cats:
			if cc.mode == "waitFood" or cc.morning_eat:
				anyone = true
				break
		if not anyone:
			furniture.bowl_full = false
			furniture.bowl_food.visible = false
		return
	if furniture.bowl_full:
		var others := false
		for cc in cats:
			if cc != c and (cc.mode == "waitFood" or cc.morning_eat):
				others = true
				break
		if not others:
			furniture.bowl_full = false
			furniture.bowl_food.visible = false
		if c.full > 0:
			hurt_cat(c, "The cat ate WAY too much. It regrets nothing.")
			barf_pendings.append({"t": 8.0, "pos": c.g.position})
			c.full = 60.0
		else:
			c.full = 50.0
			Global.msg("😸 %s ate. Full and content (for now)." % c.cat_name, "good")
	c.mode = "wander"
	c.idle_t = 3.0
