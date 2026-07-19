## One cat: its procedural mesh and its full behaviour state. Faithful port of
## the `makeCat` / `buildCatMesh` object from game.js (~1283-1330).
##
## The web build split the cat into `c` (mesh refs) and `c.state`; GDScript is
## happiest with typed fields, so both are flattened onto this RefCounted. All
## the animation / AI / movement logic lives in Cats.gd and operates on a Cat.
class_name Cat
extends RefCounted

# ---------- identity + mesh ----------
var cat_name: String
var color_key: String         # CAT_COLORS key (persisted in the save)
var chaos: float
var speed: float
var g: Node3D                 # the group node (position/rotation in world space)
var body: MeshInstance3D
var head: MeshInstance3D
var tail: MeshInstance3D
var ears: Array = []          # [MeshInstance3D, MeshInstance3D]
var legs: Array = []          # [MeshInstance3D x4] — 0,1 front · 2,3 back
var base_pose: Array = []     # [{p, pos:Vector3, rot:Vector3, scl:Vector3}]

# ---------- behaviour state (was c.state) ----------
var mode: String = "carrier"  # carrier|introSit|wander|walk|danger|distracted|
                              # pester|held|outside|eating|hop|perched|waitFood|hiddenNap
var waypoints: Array = []
var next_mode = null          # String or null
var target = null             # hazard id (String) or null
var dest = null               # {x,y,z} or null
var idle_t: float = 2.0
var hurt_t: float = 0.0
var distract_t: float = 0.0
var eat_t: float = 0.0
var pester_t: float = 0.0
var danger_age: float = 0.0
var hearts_lost_here: int = 0
var stuck_t: float = 0.0
var repathed: bool = false
var outside: bool = false
var outside_haz = null
var outside_text: String = ""
var full: float = 0.0
var distract_uses: Dictionary = {}   # per-day boredom with each toy
var distract_id = null
var morning_eat: bool = false
var nap_t: float = 0.0
var idle_pose: String = "sit"
var perch = null              # PERCHES entry the cat is heading to / on, or null
var hop_t: float = 0.0
var hop_dur: float = 0.5
var hop_upward: bool = false
var hop_from: Vector3 = Vector3.ZERO
var hop_to: Vector3 = Vector3.ZERO
var perch_t: float = 0.0
var held_t: float = 0.0
var no_hold_t: float = 0.0
var squirm_warned: bool = false
var surf = null               # elevated surface the cat is currently on, or null
var after_hop = null          # {mode, target, sf} — enter after an upward hop
var go_after_hop = null       # deferred catGoTo args — walk here after hopping down

const IS_CAT := true          # tag so the interactor can distinguish a held cat

func _init(name_: String, color_def: Dictionary, chaos_: float, parent: Node3D) -> void:
	cat_name = name_
	color_key = String(color_def.get("key", "orange"))
	chaos = chaos_
	speed = 1.7 + 0.5 * chaos
	_build_mesh(color_def, parent)

func _build_mesh(color_def: Dictionary, parent: Node3D) -> void:
	var body_c: int = color_def.body
	var dark_c: int = color_def.dark
	var eye_c: int = color_def.eye
	g = Geom.grp(0, 0, 0, parent)
	body = Geom.box(0.55, 0.28, 0.32, body_c, 0, 0.24, 0, g)
	head = Geom.box(0.26, 0.24, 0.24, body_c, 0.33, 0.42, 0, g)
	# ears + eyes ride on the head so head animation carries them
	ears = [
		Geom.box(0.08, 0.1, 0.06, body_c, 0.09, 0.16, 0.07, head),
		Geom.box(0.08, 0.1, 0.06, body_c, 0.09, 0.16, -0.07, head),
	]
	Geom.box(0.04, 0.04, 0.02, eye_c, 0.135, 0.04, 0.06, head)
	Geom.box(0.04, 0.04, 0.02, eye_c, 0.135, 0.04, -0.06, head)
	tail = Geom.box(0.3, 0.07, 0.07, dark_c, -0.4, 0.34, 0, g)
	legs = []
	for lp in [[0.18, 0.1], [0.18, -0.1], [-0.18, 0.1], [-0.18, -0.1]]:
		legs.append(Geom.box(0.07, 0.2, 0.07, dark_c, lp[0], 0.1, lp[1], g))
	# snapshot the rest pose so animation can reset each frame
	var parts: Array = [body, head, tail]
	parts.append_array(legs)
	for p in parts:
		base_pose.append({"p": p, "pos": p.position, "rot": p.rotation, "scl": p.scale})
	g.visible = false

## Restore every animated part to its rest transform (called before each pose).
func reset_pose() -> void:
	for b in base_pose:
		var p: Node3D = b.p
		p.position = b.pos
		p.rotation = b.rot
		p.scale = b.scl
	body.scale = Vector3.ONE
