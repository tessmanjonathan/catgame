## All furniture, props and interactables. Faithful port of the
## "FURNITURE + INTERACTABLES" section of game.js (~lines 302-1157).
##
## The registries (hazards / containers / distracts) and the register/add
## helpers mirror the web build 1:1. Instead of tagging meshes with `userData`
## and ray-casting triangles, each interactable records a simple sphere/AABB
## click volume (built from the prop's `hit_pad` or its mesh bounds); Interactor
## does the crosshair ray test against `interactables`.
##
## Cat / computer / phone / bowl-feeding behaviour is stubbed here and in
## Interactor — those systems arrive in Phases 3-5. The props, their visual
## armed/safe states, pick-up / stash / drop, and the hint text are all live.
class_name Furniture
extends Node3D

var _p: Node3D                 # default parent (self) for the primitive wrappers

var hazards := {}              # id -> hazard record
var containers := {}           # id -> container record
var distracts := {}            # id -> distraction record
var interactables: Array = []  # click records: {node, act, id, label, kind, ...}

# references other systems need later
var monitor: Node3D
var phone: Node3D
var bowl: Node3D
var bowl_food: MeshInstance3D
var bowl_full := false
var cat_bed: Node3D
var carrier: Node3D
var carrier_door: Node3D
var carrier_open := false

func _ready() -> void:
	_p = self
	_build_office()
	_build_kitchen()
	_build_main_bath()
	_build_tv_room()
	_build_dining()
	_build_bedroom()
	_build_guest_bedroom()
	_build_up_bath()
	_build_closet()
	_build_laundry()
	_build_den()
	_build_carrier()
	_build_shop_distractions()
	_build_daily_traps()

# ---------- primitive wrappers (parent defaults to self) ----------
func bx(w: float, h: float, d: float, color: int, x: float, y: float, z: float, parent: Node3D = _p) -> MeshInstance3D:
	return Geom.box(w, h, d, color, x, y, z, parent)
func cy(rt: float, rb: float, h: float, color: int, x: float, y: float, z: float, parent: Node3D = _p, seg: int = 10) -> MeshInstance3D:
	return Geom.cyl(rt, rb, h, color, x, y, z, parent, seg)
func sp(r: float, color: int, x: float, y: float, z: float, parent: Node3D = _p) -> MeshInstance3D:
	return Geom.sph(r, color, x, y, z, parent)
func cn(r: float, h: float, color: int, x: float, y: float, z: float, parent: Node3D = _p, seg: int = 8) -> MeshInstance3D:
	return Geom.cone(r, h, color, x, y, z, parent, seg)
func gp(x: float, y: float, z: float, parent: Node3D = _p) -> Node3D:
	return Geom.grp(x, y, z, parent)
func win_mesh(w: float, h: float, d: float, color: int, opacity: float, x: float, y: float, z: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Geom.translucent(color, opacity)
	mi.position = Vector3(x, y, z)
	add_child(mi)
	return mi

## Record an enlarged click volume for a small prop (three.js hitPad). Stored as
## metadata so register_interact turns it into a sphere click test.
func hit_pad(node: Node3D, r: float, x: float = 0.0, y: float = 0.12, z: float = 0.0) -> void:
	node.set_meta("pad", [r, Vector3(x, y, z)])

# ---------- registries ----------
func register_interact(node: Node3D, data: Dictionary) -> Node3D:
	node.set_meta("interact", data)
	var rec := {"node": node, "act": data.get("act", ""), "id": data.get("id", ""), "label": data.get("label", "")}
	if node.has_meta("pad"):
		var pad: Array = node.get_meta("pad")
		rec["kind"] = "sphere"
		rec["center"] = pad[1]
		rec["r"] = float(pad[0])
	else:
		var ab := _local_aabb(node)
		rec["kind"] = "box"
		rec["center"] = ab.position + ab.size * 0.5
		rec["half"] = ab.size * 0.5
	interactables.append(rec)
	return node

func add_toggle_hazard(id: String, mesh: Node3D, opts: Dictionary):
	var h := {"id": id, "type": "toggle", "mesh": mesh, "tier": 2, "everFixed": false, "armed": false}
	for k in opts:
		h[k] = opts[k]
	h["curSurface"] = opts.get("surface", null)
	hazards[id] = h
	register_interact(mesh, {"act": "toggle", "id": id})
	apply_toggle_vis(h)
	return h

func apply_toggle_vis(h: Dictionary) -> void:
	if h.has("on_vis") and h["on_vis"] is Callable:
		(h["on_vis"] as Callable).call(h["armed"])
	elif h["mesh"] is MeshInstance3D:
		var col: int = h.get("armedColor", 0xcc4444) if h["armed"] else h.get("safeColor", 0x66aa66)
		(h["mesh"] as MeshInstance3D).material_override = Geom.mat(col)

func add_item_hazard(id: String, mesh: Node3D, opts: Dictionary):
	var h := {"id": id, "type": "item", "mesh": mesh, "tier": 2,
		"stashed": false, "held": false, "home": mesh.position}
	for k in opts:
		h[k] = opts[k]
	h["curSurface"] = opts.get("surface", null)
	hazards[id] = h
	register_interact(mesh, {"act": "item", "id": id})
	return h

func add_container(id: String, mesh: Node3D, label: String, cap: int = 2, shop = null) -> void:
	containers[id] = {"id": id, "label": label, "cap": cap, "used": 0, "mesh": mesh,
		"owned": shop == null, "price": (int(shop["price"]) if shop != null else 0),
		"unlock": (int(shop.get("unlock", 1)) if shop != null else 1), "pending": false}
	register_interact(mesh, {"act": "container", "id": id, "label": label})
	if shop != null:
		mesh.visible = false

func add_distraction(id: String, mesh: Node3D, label: String, time: float, shop = null, anim: String = "sit", surface = null) -> void:
	distracts[id] = {"id": id, "pos": mesh.position, "time": time, "label": label, "mesh": mesh,
		"anim": anim, "surface": surface, "owned": shop == null,
		"price": (int(shop["price"]) if shop != null else 0),
		"unlock": (int(shop.get("unlock", 1)) if shop != null else 1), "pending": false}
	register_interact(mesh, {"act": "distract", "id": id, "label": label})
	if shop != null:
		mesh.visible = false

# ---------- shared prop builders ----------
func build_toilet(x: float, z: float, y: float) -> Dictionary:
	var g := gp(x, y, z)
	cy(0.26, 0.3, 0.36, 0xffffff, 0, 0.2, -0.08, g)          # bowl
	bx(0.46, 0.55, 0.22, 0xf4f4f4, 0, 0.45, 0.26, g)         # tank
	bx(0.3, 0.04, 0.08, 0xdddddd, 0, 0.75, 0.26, g)          # flush button
	var lid := bx(0.48, 0.05, 0.5, 0xf8f8f8, 0, 0.4, -0.08, g)
	var water := cy(0.2, 0.2, 0.03, 0x66bbee, 0, 0.39, -0.08, g)
	return {"g": g, "lid": lid, "water": water}

func toilet_vis(t: Dictionary, armed: bool) -> void:
	(t["water"] as MeshInstance3D).visible = armed
	var lid := t["lid"] as MeshInstance3D
	if armed:
		lid.position = Vector3(0, 0.62, 0.12)
		lid.rotation.x = PI * 0.45
	else:
		lid.position = Vector3(0, 0.4, -0.08)
		lid.rotation.x = 0.0

func build_plant(x: float, y: float, z: float, leaf: int = 0x3a8a3a, tall: float = 0.5) -> Node3D:
	var g := gp(x, y, z)
	cy(0.15, 0.11, 0.24, 0xb0603a, 0, 0.12, 0, g)            # terracotta pot
	cy(0.03, 0.03, tall * 0.7, 0x5a7a3a, 0, 0.24 + tall * 0.3, 0, g)
	sp(0.22, leaf, 0, 0.3 + tall * 0.6, 0, g)
	sp(0.15, leaf, 0.13, 0.22 + tall * 0.6, 0.07, g)
	sp(0.14, leaf, -0.11, 0.27 + tall * 0.6, -0.09, g)
	return g

# ============================================================
# OFFICE (main, x -8..-2.5, z -6..0)
# ============================================================
func _build_office() -> void:
	bx(2.2, 0.1, 1.0, 0x8a6a4a, -6.8, 0.85, -3)                            # desk
	bx(0.15, 0.85, 0.9, 0x7a5a3a, -7.8, 0.42, -3)
	bx(0.15, 0.85, 0.9, 0x7a5a3a, -5.8, 0.42, -3)
	monitor = gp(-6.9, 0.9, -3.35)
	bx(1.1, 0.7, 0.08, 0x222833, 0, 0.6, 0, monitor)                       # screen bezel
	cy(0.05, 0.05, 0.24, 0x333a44, 0, 0.12, 0, monitor)                    # stand
	bx(0.42, 0.04, 0.26, 0x333a44, 0, 0.02, 0, monitor)                    # base
	# placeholder screen (the live typing-minigame SubViewport is Phase 4)
	bx(1.0, 0.62, 0.01, 0x0a0e14, 0, 0.6, 0.05, monitor)
	register_interact(monitor, {"act": "computer"})
	var kb := gp(-6.8, 0.9, -2.85)
	bx(0.8, 0.05, 0.32, 0x333a44, 0, 0.03, 0, kb)
	for i in range(3):
		bx(0.72, 0.02, 0.07, 0x8892a0, 0, 0.06, -0.1 + i * 0.1, kb)        # key rows
	register_interact(kb, {"act": "computer"})
	# office chair
	var chair := gp(-6.8, 0, -2.2)
	bx(0.52, 0.08, 0.5, 0x444a55, 0, 0.52, 0, chair)                       # seat
	var ch_back := bx(0.5, 0.66, 0.09, 0x444a55, 0, 0.88, 0.3, chair)      # backrest
	ch_back.rotation.x = 0.12
	for sx in [-0.3, 0.3]:
		bx(0.06, 0.22, 0.06, 0x333944, sx, 0.63, 0.1, chair)              # armrest posts
		bx(0.09, 0.04, 0.34, 0x222222, sx, 0.76, 0.02, chair)             # arm pads
	cy(0.05, 0.05, 0.42, 0x222222, 0, 0.3, 0, chair)                       # gas lift
	for i in range(5):                                                     # 5-star base
		var a := i * PI * 2.0 / 5.0
		var leg := bx(0.34, 0.04, 0.06, 0x222222, cos(a) * 0.17, 0.06, sin(a) * 0.17, chair)
		leg.rotation.y = -a
		sp(0.035, 0x111111, cos(a) * 0.32, 0.035, sin(a) * 0.32, chair)
	# desk phone
	phone = gp(-5.95, 0.9, -3.3)
	bx(0.34, 0.09, 0.24, 0x1f8f1f, 0, 0.05, 0, phone)
	bx(0.3, 0.07, 0.09, 0x26b526, 0, 0.13, -0.06, phone)                   # handset
	bx(0.16, 0.02, 0.1, 0x0a5a0a, 0.05, 0.1, 0.05, phone)                  # keypad
	hit_pad(phone, 0.3, 0, 0.1, 0)
	register_interact(phone, {"act": "phone"})
	# bookshelf with books
	var bookshelf := gp(-3.0, 0, -5.5)
	bx(1.4, 1.8, 0.4, 0x7a5a3a, 0, 0.9, 0, bookshelf)
	var bookc := [0xaa4444, 0x4466aa, 0x44aa66, 0xccaa44, 0x8844aa, 0xcc6633]
	for sh in range(3):
		for i in range(6):
			bx(0.13, 0.32 + (i % 3) * 0.03, 0.28, bookc[(sh * 6 + i) % 6], -0.5 + i * 0.2, 0.42 + sh * 0.55, 0.08, bookshelf)
	# high wall shelf (shop item)
	var hi_shelf := gp(-5.0, 2.1, -5.72)
	bx(1.5, 0.07, 0.42, 0x8a6a4a, 0, 0, 0, hi_shelf)                       # plank
	bx(0.06, 0.32, 0.34, 0x7a5a3a, -0.55, -0.2, 0.02, hi_shelf)            # brackets
	bx(0.06, 0.32, 0.34, 0x7a5a3a, 0.55, -0.2, 0.02, hi_shelf)
	bx(0.3, 0.24, 0.28, 0xaa8855, -0.4, 0.16, 0, hi_shelf)                 # a stored box
	cy(0.08, 0.08, 0.22, 0x8899aa, 0.35, 0.15, 0, hi_shelf)               # jar
	add_container("hishelf", hi_shelf, "high office shelf", 3, {"price": 50, "unlock": 2})
	# round cat bed
	cat_bed = gp(-7.2, 0, -0.8)
	cy(0.45, 0.5, 0.18, 0x9a6aa0, 0, 0.09, 0, cat_bed)
	cy(0.34, 0.34, 0.09, 0xc9a9d0, 0, 0.17, 0, cat_bed)
	add_distraction("bed", cat_bed, "cat bed", 15, null, "curl")

# ============================================================
# KITCHEN (main, x 2.5..8, z -6..0)
# ============================================================
func _build_kitchen() -> void:
	bx(4.5, 0.9, 0.8, 0xe0e0e0, 5.6, 0.45, -5.4)                           # counter
	bx(0.7, 0.05, 0.5, 0xb8c4cc, 5.9, 0.92, -5.45)                         # sink basin
	cy(0.03, 0.03, 0.28, 0x99a4ac, 5.9, 1.05, -5.68)                       # faucet riser
	bx(0.2, 0.04, 0.05, 0x99a4ac, 5.83, 1.18, -5.68)                       # faucet spout
	# fridge
	var fridge := gp(7.5, 0, -5.4)
	bx(0.9, 1.8, 0.8, 0xd8d8d8, 0, 0.9, 0, fridge)
	bx(0.92, 0.03, 0.82, 0xb0b0b0, 0, 1.15, 0, fridge)
	bx(0.05, 0.35, 0.06, 0x8a8f94, -0.32, 1.42, 0.42, fridge)
	bx(0.05, 0.6, 0.06, 0x8a8f94, -0.32, 0.72, 0.42, fridge)
	# stove
	var stove := gp(3.6, 0, -5.4)
	bx(0.9, 0.9, 0.7, 0xcfd4d8, 0, 0.45, 0, stove)
	bx(0.9, 0.05, 0.7, 0x333333, 0, 0.93, 0, stove)
	var burners: Array = []
	for pos in [[-0.22, -0.16], [0.22, -0.16], [-0.22, 0.16], [0.22, 0.16]]:
		burners.append(cy(0.11, 0.11, 0.035, 0x222222, pos[0], 0.96, pos[1], stove))
	for i in range(4):
		var k := cy(0.035, 0.035, 0.05, 0xeeeeee, -0.3 + i * 0.2, 0.82, 0.37, stove)
		k.rotation.x = PI / 2.0
	add_toggle_hazard("stove", stove, {
		"name": "stove burner", "anim": "sniffHigh", "armed": false, "rearm": true, "tier": 2,
		"fixHint": "Turn off the stove", "armHint": "Stove is off",
		"dangerText": "The cat is sniffing the HOT STOVE!",
		"armMsg": "You left the stove on again...",
		"on_vis": func(a): for b in burners: (b as MeshInstance3D).material_override = Geom.mat(0xff5522 if a else 0x222222)})
	# knives on a cutting board
	var knives := gp(4.6, 0.92, -5.4)
	bx(0.55, 0.03, 0.4, 0xc9a678, 0, 0.015, 0, knives)                     # cutting board
	for i in range(3):
		bx(0.32, 0.015, 0.05, 0xd8dde2, -0.08, 0.045, -0.12 + i * 0.12, knives)  # blade
		bx(0.15, 0.035, 0.045, 0x222222, 0.16, 0.05, -0.12 + i * 0.12, knives)   # handle
	hit_pad(knives, 0.38, 0, 0.06, 0)
	add_item_hazard("knives", knives, {"name": "kitchen knives", "anim": "paw", "label": "kitchen knives", "tier": 2,
		"dangerText": "The cat is batting the KNIVES around!",
		"surface": {"x": 4.6, "z": -5.35, "h": 0.9, "ax": 0.0, "az": 1.1}})
	# chocolate bar
	var chocolate := gp(6.6, 0.9, -5.4)
	bx(0.3, 0.04, 0.16, 0x5a3a22, 0, 0.03, 0, chocolate)
	for i in range(3):
		for j in range(2):
			bx(0.07, 0.02, 0.055, 0x6b4630, -0.09 + i * 0.09, 0.06, -0.04 + j * 0.08, chocolate)
	bx(0.12, 0.06, 0.18, 0xcc3355, 0.18, 0.03, 0, chocolate)               # wrapper end
	hit_pad(chocolate, 0.28, 0, 0.05, 0)
	add_item_hazard("chocolate", chocolate, {"name": "chocolate bar", "anim": "eat", "label": "chocolate bar", "tier": 2,
		"dangerText": "The cat is licking the CHOCOLATE!",
		"surface": {"x": 6.6, "z": -5.35, "h": 0.9, "ax": 0.0, "az": 1.1}})
	var kplant := build_plant(7.6, 0, -2.5)
	hit_pad(kplant, 0.42, 0, 0.35, 0)
	add_item_hazard("kplant", kplant, {"name": "houseplant", "anim": "eat", "label": "houseplant (toxic!)", "tier": 2,
		"dangerText": "The cat is chewing the HOUSEPLANT!"})
	# trash can with a flip lid
	var trash := gp(3.0, 0, -0.6)
	cy(0.26, 0.21, 0.7, 0x778899, 0, 0.35, 0, trash)
	var trash_lid := cy(0.29, 0.29, 0.05, 0x556677, 0, 0.73, 0, trash)
	add_toggle_hazard("trash", trash, {
		"name": "trash can", "anim": "headIn", "armed": false, "rearm": true, "tier": 2,
		"fixHint": "Close the trash lid", "armHint": "Trash lid closed",
		"dangerText": "The cat is headfirst in the TRASH eating chicken bones!",
		"armMsg": "The trash lid popped open.",
		"on_vis": func(a):
			trash_lid.rotation.z = 1.0 if a else 0.0
			trash_lid.position = Vector3(0.26 if a else 0.0, 0.82 if a else 0.73, 0.0)})
	# cupboard + drawer
	var cupboard := gp(6.9, 0, -5.55)
	bx(1.2, 1.0, 0.5, 0x8a6a4a, 0, 2.0, 0, cupboard)
	bx(0.03, 0.96, 0.02, 0x6a4a2a, 0, 2.0, 0.26, cupboard)                 # door split
	bx(0.04, 0.16, 0.05, 0xd9c9a0, -0.1, 2.0, 0.27, cupboard)             # handles
	bx(0.04, 0.16, 0.05, 0xd9c9a0, 0.1, 2.0, 0.27, cupboard)
	add_container("cupboard", cupboard, "kitchen cupboard", 2)
	var drawer := gp(4.6, 0, -5.35)
	bx(1.0, 0.3, 0.6, 0x7a5a3a, 0, 0.6, 0, drawer)
	bx(0.3, 0.05, 0.05, 0xd9c9a0, 0, 0.6, 0.31, drawer)                    # handle
	add_container("drawer", drawer, "kitchen drawer", 2)
	# kitchen window frame
	bx(1.34, 0.07, 0.12, 0xf5f0e0, 5.0, 2.06, -6)
	bx(1.34, 0.07, 0.12, 0xf5f0e0, 5.0, 0.97, -6)
	bx(0.07, 1.16, 0.12, 0xf5f0e0, 4.42, 1.52, -6)
	bx(0.07, 1.16, 0.12, 0xf5f0e0, 5.58, 1.52, -6)
	# kitchen window (escape hazard)
	var win_kitchen := win_mesh(1.2, 1.0, 0.08, 0xaaddff, 0.45, 5.0, 1.5, -6)
	add_toggle_hazard("winKitchen", win_kitchen, {
		"name": "kitchen window", "anim": "climb", "armed": false, "rearm": true, "isWindow": true, "tier": 2,
		"outsidePos": Vector3(5.0, 0, -8.0), "outsideText": "THE CAT GOT OUT THE KITCHEN WINDOW!",
		"fixHint": "Close the kitchen window", "armHint": "Window closed",
		"dangerText": "The cat is halfway out the KITCHEN WINDOW!",
		"armMsg": "The wind blew the kitchen window open!",
		"on_vis": func(a): win_kitchen.position.y = 2.3 if a else 1.5})
	# food & water bowls
	bx(1.1, 0.02, 0.6, 0x5577aa, 3.5, 0.01, -4.6)                          # mat
	bowl = gp(3.2, 0, -4.6)
	cy(0.2, 0.14, 0.11, 0xd0d0e8, 0, 0.06, 0, bowl)
	bowl_food = cy(0.15, 0.15, 0.06, 0x9a6a3a, 0, 0.11, 0, bowl)
	bowl_food.visible = false
	hit_pad(bowl, 0.28, 0, 0.1, 0)
	register_interact(bowl, {"act": "bowl"})
	var water_bowl := gp(3.8, 0, -4.6)
	cy(0.2, 0.14, 0.11, 0x88aadd, 0, 0.06, 0, water_bowl)
	cy(0.15, 0.15, 0.04, 0x3d6dc9, 0, 0.1, 0, water_bowl)                  # water
	# treat jar on a side table
	bx(0.5, 0.8, 0.5, 0x8a6a4a, 7.5, 0.4, -0.4)                            # side table
	var treats := gp(7.5, 0.8, -0.4)
	cy(0.13, 0.13, 0.32, 0xdd8833, 0, 0.16, 0, treats)
	cy(0.145, 0.145, 0.06, 0x8a5522, 0, 0.35, 0, treats)                   # lid
	bx(0.22, 0.14, 0.02, 0xfff2cc, 0, 0.17, 0.125, treats)                 # label
	hit_pad(treats, 0.3, 0, 0.18, 0)
	add_distraction("treats", treats, "treat jar (shake it)", 10, null, "eat",
		{"x": 7.5, "z": -0.4, "h": 0.8, "ax": -1.0, "az": 0.0})

# ============================================================
# MAIN BATHROOM (hall end)
# ============================================================
func _build_main_bath() -> void:
	var t1 := build_toilet(-1.6, 5.3, 0)
	add_toggle_hazard("toilet1", t1["g"], {
		"name": "toilet", "anim": "fish", "armed": true, "rearm": true, "tier": 1,
		"fixHint": "Close the toilet lid", "armHint": "Lid closed",
		"dangerText": "The cat is fishing in the TOILET!",
		"armMsg": "Someone left the toilet lid up. It was you.",
		"on_vis": func(a): toilet_vis(t1, a)})
	# pedestal sink + faucet
	var sink1 := gp(0.8, 0, 5.5)
	cy(0.12, 0.16, 0.7, 0xe8e8e8, 0, 0.35, 0, sink1)
	cy(0.3, 0.22, 0.16, 0xffffff, 0, 0.78, 0, sink1)
	cy(0.025, 0.025, 0.2, 0x99a4ac, 0, 0.92, -0.18, sink1)
	bx(0.05, 0.03, 0.14, 0x99a4ac, 0, 1.0, -0.12, sink1)
	sink1.rotation.y = PI
	# pill bottle
	var meds := gp(0.8, 0.86, 5.42)
	cy(0.06, 0.06, 0.18, 0xff8844, 0, 0.09, 0, meds)
	cy(0.065, 0.065, 0.05, 0xffffff, 0, 0.2, 0, meds)
	bx(0.1, 0.1, 0.005, 0xfff6ee, 0, 0.1, 0.06, meds)                      # label
	hit_pad(meds, 0.26, 0, 0.1, 0)
	add_item_hazard("meds", meds, {"name": "medicine bottle", "anim": "paw", "label": "medicine bottle", "tier": 2,
		"dangerText": "The cat knocked over your MEDICINE!",
		"surface": {"x": 0.8, "z": 5.4, "h": 0.86, "ax": 0.0, "az": -1.2}})
	# medicine cabinet with mirror
	var med_cab := gp(0.8, 0, 5.85)
	bx(0.7, 0.5, 0.18, 0xcccccc, 0, 1.8, 0, med_cab)
	bx(0.6, 0.4, 0.02, 0xbfe0ec, 0, 1.8, -0.1, med_cab)                    # mirror face
	bx(0.04, 0.12, 0.04, 0x8a8f94, -0.26, 1.8, -0.11, med_cab)
	add_container("medcab", med_cab, "medicine cabinet", 1)

# ============================================================
# TV ROOM (main, x -8..-2.5, z 0..6)
# ============================================================
func _build_tv_room() -> void:
	# couch
	var couch := gp(-6.5, 0, 5.2)
	bx(2.4, 0.35, 1.0, 0x6a5acd, 0, 0.3, 0, couch)
	bx(2.4, 0.6, 0.25, 0x5a4abd, 0, 0.68, 0.38, couch)
	bx(0.25, 0.55, 1.0, 0x5a4abd, -1.08, 0.48, 0, couch)
	bx(0.25, 0.55, 1.0, 0x5a4abd, 1.08, 0.48, 0, couch)
	bx(1.0, 0.12, 0.8, 0x7a6add, -0.52, 0.42, -0.06, couch)
	bx(1.0, 0.12, 0.8, 0x7a6add, 0.52, 0.42, -0.06, couch)
	# TV on a media console
	bx(1.8, 0.4, 0.45, 0x7a5a3a, -3.9, 0.2, 0.35)                          # console
	bx(1.6, 1.0, 0.1, 0x1a1a22, -3.9, 1.0, 0.35)                           # TV frame
	bx(1.5, 0.88, 0.02, 0x2a3a55, -3.9, 1.0, 0.41)                         # screen
	# tangled TV cables + power strip
	var cords := gp(-3.9, 0, 0.75)
	for i in range(4):
		var c := bx(0.5, 0.03, 0.03, 0x222222, -0.35 + i * 0.22, 0.03, (i % 2) * 0.14, cords)
		c.rotation.y = i * 0.8
	bx(0.22, 0.08, 0.09, 0xf0f0f0, 0.4, 0.04, 0.05, cords)                 # power strip
	hit_pad(cords, 0.42, 0, 0.05, 0.05)
	add_toggle_hazard("cords", cords, {
		"name": "TV cables", "anim": "tangle", "armed": false, "rearm": false, "tier": 2,
		"fixHint": "Tuck away the TV cables", "armHint": "Cables tucked",
		"dangerText": "The cat is CHEWING THE TV CABLES!",
		"on_vis": func(a): cords.visible = a})
	# coffee table
	var ctab := gp(-4.6, 0, 3.0)
	bx(1.2, 0.06, 0.7, 0x8a6a4a, 0, 0.42, 0, ctab)
	for l in [[-0.52, -0.28], [0.52, -0.28], [-0.52, 0.28], [0.52, 0.28]]:
		bx(0.07, 0.42, 0.07, 0x7a5a3a, l[0], 0.21, l[1], ctab)
	# ribbon toy — a tier-1 starter hazard
	var ribbon := gp(-4.4, 0.45, 3.1)
	Geom.torus(0.11, 0.03, 0xff44aa, 0, 0.12, 0, ribbon)
	hit_pad(ribbon, 0.32, 0, 0.12, 0)
	add_item_hazard("ribbon", ribbon, {"name": "ribbon toy", "anim": "paw", "label": "ribbon toy (choking hazard)", "tier": 1,
		"dangerText": "The cat is SWALLOWING THE RIBBON!"})
	# laser pointer
	var laser_mesh := gp(-4.9, 0.45, 2.85)
	var laser_body := cy(0.035, 0.035, 0.26, 0x333333, 0, 0.05, 0, laser_mesh)
	laser_body.rotation.z = PI / 2.0
	sp(0.032, 0xff2222, 0.13, 0.05, 0, laser_mesh)                         # emitter
	bx(0.04, 0.02, 0.035, 0xff2222, -0.04, 0.09, 0, laser_mesh)            # button
	hit_pad(laser_mesh, 0.26, 0, 0.06, 0)
	add_item_hazard("laser", laser_mesh, {"name": "laser pointer", "label": "laser pointer", "tool": true, "safeItem": true})
	# window blinds + dangling pull cord with tassel
	var blinds := gp(-7.85, 0, 4.0)
	bx(0.08, 1.4, 1.1, 0xf0e4c0, 0, 1.9, 0, blinds)
	for i in range(5):
		bx(0.1, 0.02, 1.1, 0xe0d4b0, 0, 1.4 + i * 0.25, 0, blinds)
	var blind_cord := bx(0.025, 1.2, 0.025, 0xeeddaa, 0.09, 1.4, 0.45, blinds)
	var tassel := sp(0.05, 0xcc9944, 0.09, 0.78, 0.45, blinds)
	hit_pad(blinds, 0.4, 0.12, 1.05, 0.45)
	add_toggle_hazard("blinds", blinds, {
		"name": "blind cord", "anim": "tangle", "armed": false, "rearm": true, "tier": 2,
		"fixHint": "Tie up the blind cord", "armHint": "Cord tied up",
		"dangerText": "The cat is TANGLED IN THE BLIND CORD!",
		"armMsg": "The blind cord came loose again.",
		"on_vis": func(a):
			blind_cord.scale.y = 1.0 if a else 0.35
			blind_cord.position.y = 1.4 if a else 1.9
			tassel.position.y = 0.78 if a else 1.68})
	# birthday balloon on a string
	var balloon := gp(-3.2, 0, 5.0)
	sp(0.3, 0xff6688, 0, 1.95, 0, balloon)
	var knot := cn(0.07, 0.12, 0xee5577, 0, 1.62, 0, balloon)
	knot.rotation.z = PI
	bx(0.015, 1.5, 0.015, 0xdddddd, 0, 0.85, 0, balloon)                   # string
	hit_pad(balloon, 0.42, 0, 1.9, 0)
	add_toggle_hazard("balloon", balloon, {
		"name": "birthday balloon", "anim": "pounce", "armed": false, "rearm": false, "tier": 2,
		"fixHint": "Pop the balloon (sorry, balloon)", "armHint": "",
		"dangerText": "The cat is attacking the BALLOON! If it pops in its face...",
		"on_vis": func(a): balloon.visible = a})
	# fern
	var tvplant := gp(-2.9, 0, 1.2)
	cy(0.16, 0.12, 0.26, 0x8a5a3a, 0, 0.13, 0, tvplant)
	for i in range(5):
		var f := cn(0.055, 0.5, 0x2a7a2a, cos(i * 1.26) * 0.12, 0.42, sin(i * 1.26) * 0.12, tvplant)
		f.rotation = Vector3(sin(i * 1.26) * 0.6, 0, -cos(i * 1.26) * 0.6)
	hit_pad(tvplant, 0.4, 0, 0.3, 0)
	add_item_hazard("tvplant", tvplant, {"name": "fern", "anim": "eat", "label": "fern (cats love to eat these)", "tier": 2,
		"dangerText": "The cat is eating the FERN!"})
	# toy chest
	var toy_chest := gp(-7.5, 0, 2.0)
	bx(1.0, 0.5, 0.6, 0xaa7744, 0, 0.25, 0, toy_chest)
	bx(1.04, 0.12, 0.64, 0x8a5a30, 0, 0.56, 0, toy_chest)
	bx(0.08, 0.1, 0.04, 0xddbb44, 0, 0.5, 0.32, toy_chest)                 # latch
	add_container("chest", toy_chest, "toy chest", 3)
	# cat tower
	var tower := gp(-3.0, 0, 4.2)
	bx(0.7, 0.08, 0.7, 0xc2a678, 0, 0.04, 0, tower)
	cy(0.09, 0.09, 0.7, 0xb08a5a, 0, 0.43, 0, tower)
	bx(0.55, 0.07, 0.55, 0xc2a678, 0, 0.81, 0, tower)
	cy(0.08, 0.08, 0.58, 0xb08a5a, 0.14, 1.13, 0.14, tower)
	bx(0.5, 0.07, 0.5, 0x9a6aa0, 0.14, 1.45, 0.14, tower)
	add_distraction("tower", tower, "cat tower", 18, {"price": 40, "unlock": 1}, "sit")
	# open cardboard box
	var cardboard := gp(-5.5, 0, 1.5)
	bx(0.7, 0.45, 0.7, 0xb08a5a, 0, 0.23, 0, cardboard)
	bx(0.6, 0.02, 0.6, 0x3a2a18, 0, 0.44, 0, cardboard)                    # dark inside
	for i in range(4):
		var f := bx(0.6, 0.02, 0.22, 0xc09a6a, 0, 0.5, 0, cardboard)
		f.rotation.y = i * PI / 2.0
		f.translate_object_local(Vector3(0, 0, 0.44))
		f.rotate_object_local(Vector3(1, 0, 0), -0.7)
	add_distraction("boxx", cardboard, "cardboard box (irresistible)", 12, null, "curl")

# ============================================================
# DINING (main, x 2.5..8, z 0..6)
# ============================================================
func _build_dining() -> void:
	var dtable := gp(5.5, 0, 3.5)
	bx(2.0, 0.08, 1.2, 0x8a6a4a, 0, 0.78, 0, dtable)
	for l in [[-0.9, -0.5], [0.9, -0.5], [-0.9, 0.5], [0.9, 0.5]]:
		bx(0.09, 0.78, 0.09, 0x7a5a3a, l[0], 0.39, l[1], dtable)
	for dx in [-1.4, 1.4]:
		var ch := gp(5.5 + dx, 0, 3.5)
		bx(0.42, 0.06, 0.42, 0x9a7248, 0, 0.45, 0, ch)
		bx(0.42, 0.55, 0.06, 0x9a7248, 0, 0.75, -0.18, ch)
		ch.rotation.y = PI / 2.0 if dx < 0 else -PI / 2.0
		for l in [[-0.17, -0.17], [0.17, -0.17], [-0.17, 0.17], [0.17, 0.17]]:
			bx(0.05, 0.45, 0.05, 0x7a5a3a, l[0], 0.22, l[1], ch)
	# candle with a flame
	var candle := gp(5.5, 0.82, 3.5)
	cy(0.05, 0.05, 0.26, 0xf4ead0, 0, 0.13, 0, candle)
	cy(0.09, 0.09, 0.03, 0xb8a888, 0, 0.015, 0, candle)                    # dish
	var flame := cn(0.035, 0.11, 0xffaa22, 0, 0.32, 0, candle)
	hit_pad(candle, 0.28, 0, 0.18, 0)
	add_toggle_hazard("candle", candle, {
		"name": "lit candle", "anim": "sniffHigh", "armed": false, "rearm": true, "tier": 2,
		"fixHint": "Blow out the candle", "armHint": "Candle out",
		"dangerText": "The cat's TAIL IS OVER THE CANDLE FLAME!",
		"armMsg": "The scented candle is somehow lit again.",
		"surface": {"x": 5.15, "z": 3.5, "h": 0.82, "ax": 0.0, "az": 1.3},
		"on_vis": func(a): flame.visible = a})
	# lily bouquet
	var lilies := gp(6.4, 0.82, 3.5)
	cy(0.09, 0.06, 0.3, 0x7799bb, 0, 0.15, 0, lilies)
	for i in range(3):
		var a := i * 2.1
		bx(0.02, 0.28, 0.02, 0x5a8a4a, cos(a) * 0.06, 0.4, sin(a) * 0.06, lilies)
		var fl := cn(0.07, 0.13, 0xffffff, cos(a) * 0.09, 0.56, sin(a) * 0.09, lilies, 6)
		fl.rotation = Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4)
		sp(0.025, 0xffcc44, cos(a) * 0.09, 0.6, sin(a) * 0.09, lilies)
	hit_pad(lilies, 0.34, 0, 0.35, 0)
	add_item_hazard("lilies", lilies, {"name": "lily bouquet", "anim": "eat", "label": "lilies (VERY toxic to cats)", "tier": 2,
		"dangerText": "The cat is nibbling the LILIES! Those are super toxic!",
		"surface": {"x": 6.05, "z": 3.5, "h": 0.82, "ax": 0.0, "az": 1.3}})
	# crumpled plastic bag
	var plastic_bag := gp(3.2, 0, 5.2)
	bx(0.4, 0.28, 0.3, 0xeeeeee, 0, 0.14, 0, plastic_bag)
	bx(0.3, 0.2, 0.24, 0xf6f6f6, 0.1, 0.3, 0.04, plastic_bag)
	bx(0.04, 0.18, 0.03, 0xe0e0e0, -0.12, 0.42, 0, plastic_bag)            # handle loops
	bx(0.04, 0.18, 0.03, 0xe0e0e0, 0.12, 0.42, 0, plastic_bag)
	hit_pad(plastic_bag, 0.34, 0, 0.2, 0)
	add_item_hazard("bag", plastic_bag, {"name": "plastic bag", "anim": "headIn", "label": "plastic bag (suffocation hazard)", "tier": 2,
		"dangerText": "The cat has its HEAD IN THE PLASTIC BAG!"})
	# scratching post
	var post := gp(1.8, 0, 1.0)
	bx(0.5, 0.06, 0.5, 0x8a6a4a, 0, 0.03, 0, post)
	for i in range(6):
		cy(0.09, 0.09, 0.16, 0xc9b28a if i % 2 else 0xb9a077, 0, 0.14 + i * 0.16, 0, post)
	bx(0.34, 0.06, 0.34, 0x8a6a4a, 0, 1.1, 0, post)
	add_distraction("post", post, "scratching post", 12, {"price": 25, "unlock": 1}, "scratch")

# ============================================================
# UPSTAIRS: BEDROOM (x -8..-1, z -6..0)
# ============================================================
func _build_bedroom() -> void:
	var bed := gp(-6.5, 3, -4.9)
	bed.rotation.y = PI / 2.0
	bx(2.0, 0.25, 1.6, 0x7a5a3a, 0, 0.13, 0, bed)
	bx(1.9, 0.2, 1.5, 0xf0f0f0, 0, 0.35, 0, bed)
	bx(1.3, 0.1, 1.52, 0x88aacc, -0.32, 0.46, 0, bed)                      # blanket
	bx(0.4, 0.12, 0.55, 0xffffff, 0.65, 0.5, -0.35, bed)                   # pillows
	bx(0.4, 0.12, 0.55, 0xffffff, 0.65, 0.5, 0.35, bed)
	bx(0.12, 0.9, 1.6, 0x6a4a2a, 0.95, 0.45, 0, bed)                       # headboard
	register_interact(bed, {"act": "bed"})
	# nightstand with a little lamp
	var nstand := gp(-5.2, 3, -5.5)
	bx(0.6, 0.6, 0.5, 0x7a5a3a, 0, 0.3, 0, nstand)
	cy(0.03, 0.06, 0.2, 0x555555, -0.15, 0.7, 0, nstand)
	cn(0.12, 0.15, 0xffe9a8, -0.15, 0.85, 0, nstand)                       # lampshade
	# hair ties
	var bands := gp(-5.2, 3.6, -5.35)
	var bandc := [0xcc44cc, 0x44cccc, 0xcccc44]
	for i in range(3):
		var r := Geom.torus(0.05, 0.018, bandc[i], -0.08 + i * 0.08, 0.02, (i % 2) * 0.06, bands)
		r.rotation.x = PI / 2.0
	hit_pad(bands, 0.3, 0, 0.03, 0)
	add_item_hazard("bands", bands, {"name": "hair ties", "anim": "paw", "label": "hair ties (cats swallow these)", "tier": 3,
		"dangerText": "The cat is SWALLOWING YOUR HAIR TIES!",
		"surface": {"x": -5.2, "z": -5.4, "h": 0.6, "ax": 0.0, "az": 1.1}})
	var win_bed := win_mesh(0.08, 1.0, 1.2, 0xaaddff, 0.45, -8, 4.5, -4)
	add_toggle_hazard("winBed", win_bed, {
		"name": "bedroom window", "anim": "climb", "armed": false, "rearm": true, "isWindow": true, "tier": 3,
		"outsidePos": Vector3(-10, 3.1, -4), "outsideText": "THE CAT IS OUT ON THE ROOF!",
		"fixHint": "Close the bedroom window", "armHint": "Window closed",
		"dangerText": "The cat is climbing out the BEDROOM WINDOW onto the roof!",
		"armMsg": "The bedroom window blew open!",
		"on_vis": func(a): win_bed.position.y = 5.3 if a else 4.5})
	# bedroom window frame
	bx(0.12, 0.07, 1.34, 0xf5f0e0, -8, 5.06, -4)
	bx(0.12, 0.07, 1.34, 0xf5f0e0, -8, 3.97, -4)
	bx(0.12, 1.16, 0.07, 0xf5f0e0, -8, 4.52, -4.58)
	bx(0.12, 1.16, 0.07, 0xf5f0e0, -8, 4.52, -3.42)
	# window perch
	var perch := gp(-7.6, 3, -3.2)
	bx(0.7, 0.1, 0.55, 0x9a6aa0, -0.05, 0.72, 0, perch)
	bx(0.6, 0.06, 0.45, 0xc9a9d0, -0.05, 0.8, 0, perch)                    # cushion
	bx(0.06, 0.35, 0.06, 0x7a5a3a, -0.3, 0.5, -0.18, perch)
	bx(0.06, 0.35, 0.06, 0x7a5a3a, -0.3, 0.5, 0.18, perch)
	add_distraction("perch", perch, "window perch (bird watching)", 22, {"price": 35, "unlock": 2}, "watch")

# ============================================================
# UPSTAIRS: GUEST BEDROOM (x -8..-1, z 0..6)
# ============================================================
func _build_guest_bedroom() -> void:
	var gbed := gp(-6.5, 3, 5.0)
	gbed.rotation.y = -PI / 2.0
	bx(1.8, 0.22, 1.5, 0x7a5a3a, 0, 0.11, 0, gbed)
	bx(1.7, 0.18, 1.4, 0xf0f0f0, 0, 0.3, 0, gbed)
	bx(1.2, 0.09, 1.42, 0xaa88cc, -0.25, 0.4, 0, gbed)
	bx(0.4, 0.12, 0.5, 0xffffff, 0.6, 0.44, 0, gbed)
	# sewing kit
	var sewing := gp(-3.0, 3.22, 5.0)
	bx(0.34, 0.09, 0.26, 0xdd4444, 0, 0.05, 0, sewing)
	sp(0.07, 0xee6666, -0.07, 0.13, 0, sewing)                             # pincushion
	for i in range(3):
		bx(0.008, 0.09, 0.008, 0xd8dde2, -0.1 + i * 0.035, 0.21, 0.01 * i, sewing)  # pins
	cy(0.035, 0.035, 0.07, 0x4466cc, 0.09, 0.13, 0.04, sewing)
	cy(0.045, 0.045, 0.01, 0xd9c9a0, 0.09, 0.17, 0.04, sewing)
	hit_pad(sewing, 0.3, 0, 0.1, 0)
	add_item_hazard("sewing", sewing, {"name": "sewing kit", "anim": "paw", "label": "sewing kit (needles + thread!)", "tier": 3,
		"dangerText": "The cat found the SEWING NEEDLES!"})
	var gplant := build_plant(-1.8, 3, 1.0, 0x2f9a4f, 0.75)
	hit_pad(gplant, 0.42, 0, 0.4, 0)
	add_item_hazard("gplant", gplant, {"name": "monstera", "anim": "eat", "label": "monstera (toxic to cats)", "tier": 3,
		"dangerText": "The cat is destroying (and eating) the MONSTERA!"})

# ============================================================
# UPSTAIRS: BATHROOM (x 2.5..8, z 2..6)
# ============================================================
func _build_up_bath() -> void:
	var tub := gp(6.5, 3, 5.2)
	bx(1.6, 0.5, 0.9, 0xffffff, 0, 0.3, 0, tub)
	bx(1.7, 0.08, 1.0, 0xf0f0f0, 0, 0.56, 0, tub)                          # rim
	var tub_water := bx(1.4, 0.05, 0.7, 0x66aadd, 0, 0.53, 0, tub)
	cy(0.035, 0.035, 0.35, 0x99a4ac, 0.7, 0.75, 0, tub)                    # faucet riser
	bx(0.2, 0.05, 0.06, 0x99a4ac, 0.6, 0.92, 0, tub)
	for f in [[-0.7, -0.35], [0.7, -0.35], [-0.7, 0.35], [0.7, 0.35]]:
		sp(0.07, 0xd0d0d0, f[0], 0.05, f[1], tub)                          # feet
	add_toggle_hazard("tub", tub, {
		"name": "guest bathtub", "anim": "fish", "armed": false, "rearm": false, "tier": 3,
		"fixHint": "Drain the bathtub", "armHint": "Tub drained",
		"dangerText": "The cat fell in the FULL BATHTUB!",
		"on_vis": func(a): tub_water.visible = a})
	var t2 := build_toilet(3.4, 5.3, 3)
	add_toggle_hazard("toilet2", t2["g"], {
		"name": "upstairs toilet", "anim": "fish", "armed": false, "rearm": true, "tier": 3,
		"fixHint": "Close the toilet lid", "armHint": "Lid closed",
		"dangerText": "The cat is drinking from the UPSTAIRS TOILET!",
		"armMsg": "The upstairs toilet lid is up again.",
		"on_vis": func(a): toilet_vis(t2, a)})

# ============================================================
# UPSTAIRS: CLOSET (x 2.5..8, z -6..-1)
# ============================================================
func _build_closet() -> void:
	var duct := gp(7.9, 3.15, -3.5)
	bx(0.06, 0.5, 0.62, 0x111111, 0.02, 0.3, 0, duct)                      # dark duct hole
	var grate := gp(0, 0.3, 0, duct)
	bx(0.04, 0.55, 0.68, 0x999999, -0.04, 0, 0, grate)                     # frame
	for i in range(4):
		bx(0.05, 0.06, 0.6, 0x777777, -0.05, -0.18 + i * 0.12, 0, grate)
	for sc in [[-0.24, -0.3], [-0.24, 0.3], [0.24, -0.3], [0.24, 0.3]]:
		sp(0.02, 0xffcc00, -0.07, sc[0], sc[1], grate)                     # screw heads
	add_toggle_hazard("duct", duct, {
		"name": "air duct vent", "anim": "headIn", "armed": false, "rearm": false, "needTool": "screwdriver", "tier": 3,
		"fixHint": "Screw the vent shut", "armHint": "Vent secured",
		"needToolHint": "Loose air vent — you need a SCREWDRIVER (try the basement workbench)",
		"dangerText": "The cat crawled INTO THE AIR DUCT!",
		"on_vis": func(a):
			grate.rotation.z = -0.55 if a else 0.0
			grate.position = Vector3(-0.14 if a else 0.0, 0.24 if a else 0.3, 0.0)})
	# ironing board + iron
	var iboard := gp(4.0, 3, -5.3)
	bx(1.2, 0.06, 0.4, 0xcfd8dd, 0, 0.72, 0, iboard)
	var bl1 := bx(0.05, 0.75, 0.05, 0x8a8f94, -0.2, 0.36, 0, iboard)
	bl1.rotation.z = 0.4
	var bl2 := bx(0.05, 0.75, 0.05, 0x8a8f94, 0.2, 0.36, 0, iboard)
	bl2.rotation.z = -0.4
	var iron := gp(4.0, 3.75, -5.3)
	var sole := bx(0.3, 0.03, 0.16, 0xb8c0c8, 0, 0.015, 0, iron)
	bx(0.26, 0.1, 0.13, 0x4477aa, 0, 0.08, 0, iron)
	bx(0.16, 0.05, 0.06, 0x335588, 0, 0.17, 0, iron)                       # handle
	var iron_light := sp(0.025, 0xff3300, 0.12, 0.1, 0, iron)
	hit_pad(iron, 0.3, 0, 0.08, 0)
	add_toggle_hazard("iron", iron, {
		"name": "hot iron", "anim": "paw", "armed": false, "rearm": false, "tier": 3,
		"fixHint": "Unplug the iron", "armHint": "Iron unplugged",
		"dangerText": "The cat is about to knock the HOT IRON onto itself!",
		"surface": {"x": 4.4, "z": -5.3, "h": 0.75, "ax": 0.0, "az": 1.2},
		"on_vis": func(a):
			iron_light.visible = a
			sole.material_override = Geom.mat(0xff7744 if a else 0xb8c0c8)})
	# mothballs
	var mothballs := gp(6.5, 3, -5.3)
	bx(0.2, 0.18, 0.14, 0xd9c9a0, 0, 0.09, 0, mothballs)                   # bag
	for i in range(5):
		sp(0.035, 0xf0f0f0, -0.12 + (i % 3) * 0.11, 0.035, 0.12 + (i / 3) * 0.09, mothballs)
	hit_pad(mothballs, 0.3, 0, 0.08, 0.06)
	add_item_hazard("mothballs", mothballs, {"name": "mothballs", "anim": "eat", "label": "mothballs (toxic)", "tier": 3,
		"dangerText": "The cat is licking the MOTHBALLS!"})
	# high shelf
	var shelf := gp(6.5, 4.55, -5.6)
	bx(1.4, 0.08, 0.45, 0x8a6a4a, 0, 0.25, 0, shelf)
	bx(0.06, 0.25, 0.3, 0x7a5a3a, -0.5, 0.1, 0.05, shelf)
	bx(0.06, 0.25, 0.3, 0x7a5a3a, 0.5, 0.1, 0.05, shelf)
	bx(0.3, 0.25, 0.3, 0xaa8855, -0.4, 0.42, 0, shelf)                     # a stored box
	add_container("shelf", shelf, "high closet shelf", 2)

# ============================================================
# BASEMENT: LAUNDRY (z < 0)
# ============================================================
func _build_laundry() -> void:
	var dryer := gp(-6.5, -3, -5.3)
	bx(0.9, 0.95, 0.8, 0xe8e8e8, 0, 0.48, 0, dryer)
	bx(0.8, 0.14, 0.06, 0x9aa4ac, 0, 0.88, 0.4, dryer)                     # control panel
	var d_knob := cy(0.05, 0.05, 0.05, 0x445566, 0.25, 0.88, 0.44, dryer)
	d_knob.rotation.x = PI / 2.0
	var d_hole := cy(0.26, 0.26, 0.04, 0x111111, 0, 0.45, 0.4, dryer)
	d_hole.rotation.x = PI / 2.0
	var d_door := cy(0.29, 0.29, 0.05, 0xc8d4dc, 0, 0.45, 0.42, dryer)
	d_door.rotation.x = PI / 2.0
	add_toggle_hazard("dryer", dryer, {
		"name": "dryer", "anim": "headIn", "armed": false, "rearm": true, "tier": 3,
		"fixHint": "Close the dryer door", "armHint": "Dryer closed",
		"dangerText": "The cat climbed INTO THE DRYER!",
		"armMsg": "You left the dryer open with warm towels inside. Cat magnet.",
		"on_vis": func(a):
			d_hole.visible = a
			if a:
				d_door.position = Vector3(0.48, 0.45, 0.6)
				d_door.rotation = Vector3(PI / 2.0, 0, 0.9)
			else:
				d_door.position = Vector3(0, 0.45, 0.42)
				d_door.rotation = Vector3(PI / 2.0, 0, 0)})
	# washer (closed, blue porthole)
	var washer := gp(-5.4, -3, -5.3)
	bx(0.9, 0.95, 0.8, 0xd8d8e8, 0, 0.48, 0, washer)
	var w_door := cy(0.26, 0.26, 0.05, 0x6688bb, 0, 0.45, 0.41, washer)
	w_door.rotation.x = PI / 2.0
	bx(0.8, 0.14, 0.06, 0x9aa4ac, 0, 0.88, 0.4, washer)
	# detergent pods
	var pods := gp(-4.4, -3, -5.3)
	cy(0.16, 0.14, 0.26, 0xff8822, 0, 0.13, 0, pods)
	cy(0.17, 0.17, 0.04, 0xdd6600, 0, 0.28, 0, pods)                       # lid ajar
	sp(0.05, 0x44ddaa, 0.2, 0.05, 0.08, pods)
	sp(0.05, 0x4488ee, 0.28, 0.05, -0.04, pods)
	sp(0.05, 0xffcc44, 0.22, 0.05, -0.14, pods)
	hit_pad(pods, 0.34, 0.08, 0.12, 0)
	add_item_hazard("pods", pods, {"name": "detergent pods", "anim": "eat", "label": "detergent pods (look like candy!)", "tier": 3,
		"dangerText": "The cat is biting a DETERGENT POD!"})
	# workbench with pegboard + tools
	bx(2.0, 0.9, 0.7, 0x7a5a3a, 5.5, -2.55, -5.4)                          # bench
	bx(1.8, 1.0, 0.06, 0x9a7a4a, 5.5, -1.5, -5.85)                         # pegboard
	bx(0.06, 0.3, 0.06, 0x8a4a2a, 5.0, -1.4, -5.8)                         # hammer handle
	bx(0.2, 0.1, 0.08, 0x666666, 5.0, -1.22, -5.8)                         # hammer head
	bx(0.05, 0.35, 0.03, 0x888888, 6.0, -1.35, -5.8)                       # wrench
	# the screwdriver
	bx(0.5, 0.02, 0.3, 0xcc3333, 5.5, -2.09, -5.35)                        # tool mat
	var screwdriver := gp(5.5, -2.08, -5.35)
	var sd_handle := cy(0.05, 0.05, 0.18, 0xffcc00, -0.11, 0.05, 0, screwdriver)
	sd_handle.rotation.z = PI / 2.0
	var sd_shaft := cy(0.018, 0.018, 0.26, 0xc8d0d8, 0.11, 0.05, 0, screwdriver)
	sd_shaft.rotation.z = PI / 2.0
	bx(0.04, 0.012, 0.03, 0xc8d0d8, 0.24, 0.05, 0, screwdriver)            # flat tip
	hit_pad(screwdriver, 0.3, 0, 0.05, 0)
	add_item_hazard("screwdriver", screwdriver, {"name": "screwdriver", "label": "screwdriver", "tool": true, "safeItem": true})
	# mousetrap
	var trap := gp(2.0, -3, -3.0)
	bx(0.3, 0.03, 0.5, 0xb08a5a, 0, 0.015, 0, trap)
	var trap_bar := bx(0.26, 0.02, 0.03, 0x999999, 0, 0.05, -0.18, trap)
	bx(0.06, 0.05, 0.06, 0xffd744, 0, 0.055, 0.1, trap)                    # cheese
	hit_pad(trap, 0.3, 0, 0.08, 0)
	add_toggle_hazard("trap", trap, {
		"name": "mousetrap", "anim": "paw", "armed": false, "rearm": false, "tier": 3,
		"fixHint": "Disarm the mousetrap", "armHint": "Trap disarmed",
		"dangerText": "The cat is pawing at the MOUSETRAP!",
		"on_vis": func(a): trap_bar.position.z = -0.18 if a else 0.1})
	# dangling string lights
	var lights := gp(-2.0, -3, -5.85)
	bx(1.5, 0.03, 0.03, 0x333333, 0, 2.4, 0, lights)
	var bulbc := [0xff5555, 0x55cc55, 0x5588ff, 0xffee88]
	var bulbs: Array = []
	for i in range(6):
		bulbs.append(sp(0.045, bulbc[i % 4], -0.62 + i * 0.25, 2.32, 0, lights))
	hit_pad(lights, 0.55, 0, 2.32, 0)
	add_toggle_hazard("lights", lights, {
		"name": "string lights cord", "anim": "tangle", "armed": false, "rearm": false, "tier": 3,
		"fixHint": "Unplug the dangling string lights", "armHint": "Lights unplugged",
		"dangerText": "The cat is chewing the STRING LIGHTS. While plugged in.",
		"on_vis": func(a):
			for i in range(bulbs.size()):
				(bulbs[i] as MeshInstance3D).material_override = Geom.mat(bulbc[i % 4] if a else 0x555544)})
	# basement storage shelf
	var bshelf := gp(7.4, -3, -3.0)
	bx(1.6, 0.06, 0.5, 0x8a6a4a, 0, 1.0, 0, bshelf)
	bx(1.6, 0.06, 0.5, 0x8a6a4a, 0, 1.6, 0, bshelf)
	bx(0.06, 1.7, 0.5, 0x7a5a3a, -0.77, 0.85, 0, bshelf)
	bx(0.06, 1.7, 0.5, 0x7a5a3a, 0.77, 0.85, 0, bshelf)
	cy(0.09, 0.09, 0.25, 0x8899aa, -0.4, 1.16, 0, bshelf)                  # jars
	cy(0.09, 0.09, 0.25, 0xaa8899, -0.15, 1.16, 0, bshelf)
	add_container("bshelf", bshelf, "basement shelf", 2)

# ============================================================
# BASEMENT: DEN (z > 0)
# ============================================================
func _build_den() -> void:
	var fireplace := gp(0, -3, 5.7)
	bx(1.8, 1.6, 0.5, 0x883322, 0, 0.8, 0, fireplace)
	bx(2.0, 0.12, 0.65, 0x6a4a3a, 0, 1.64, -0.05, fireplace)               # mantel
	bx(1.0, 0.9, 0.1, 0x111111, 0, 0.55, -0.22, fireplace)                 # firebox
	var fp_glass := MeshInstance3D.new()
	var fp_mesh := BoxMesh.new()
	fp_mesh.size = Vector3(1.0, 0.9, 0.04)
	fp_glass.mesh = fp_mesh
	fp_glass.material_override = Geom.translucent(0xaaccdd, 0.35)
	fp_glass.position = Vector3(0, 0.55, -0.29)
	fireplace.add_child(fp_glass)
	var flames := gp(0, 0.2, -0.24, fireplace)
	cn(0.12, 0.4, 0xff6622, 0, 0.2, 0, flames)
	cn(0.08, 0.3, 0xffaa22, -0.18, 0.15, 0, flames)
	cn(0.08, 0.32, 0xffaa22, 0.18, 0.16, 0, flames)
	add_toggle_hazard("fireplace", fireplace, {
		"name": "fireplace", "anim": "curl", "armed": false, "rearm": true, "tier": 3,
		"fixHint": "Close the fireplace door", "armHint": "Fireplace door closed",
		"dangerText": "The cat turned on the FIREPLACE and is sitting IN it!",
		"armMsg": "The cat figured out the fireplace switch. Again.",
		"on_vis": func(a):
			flames.visible = a
			fp_glass.position.x = 0.7 if a else 0.0})
	# old basement couch
	var bcouch := gp(-4.0, -3, 4.5)
	bx(2.2, 0.32, 0.9, 0x8a4a6a, 0, 0.28, 0, bcouch)
	bx(2.2, 0.5, 0.22, 0x7a3a5a, 0, 0.6, 0.34, bcouch)
	bx(0.22, 0.45, 0.9, 0x7a3a5a, -1.0, 0.42, 0, bcouch)
	bx(0.22, 0.45, 0.9, 0x7a3a5a, 1.0, 0.42, 0, bcouch)
	# catnip mouse
	var catnip := gp(3.5, -3, 3.0)
	var mouse_body := sp(0.09, 0x777788, 0, 0.07, 0, catnip)
	mouse_body.scale = Vector3(1.4, 0.9, 1)
	sp(0.055, 0x777788, 0.14, 0.08, 0, catnip)                             # head
	cn(0.025, 0.05, 0xffaacc, 0.16, 0.14, -0.03, catnip)
	cn(0.025, 0.05, 0xffaacc, 0.16, 0.14, 0.03, catnip)
	var mtail := bx(0.16, 0.015, 0.015, 0xffaacc, -0.18, 0.06, 0, catnip)
	mtail.rotation.y = 0.5
	for i in range(4):
		sp(0.02, 0x55cc55, -0.1 + i * 0.08, 0.01, 0.12 - (i % 2) * 0.24, catnip)
	hit_pad(catnip, 0.3, 0, 0.08, 0)
	add_distraction("catnip", catnip, "catnip mouse", 20, {"price": 30, "unlock": 2}, "roll")

# ============================================================
# CAT CARRIER (intro prop, in the hallway)
# ============================================================
func _build_carrier() -> void:
	carrier = gp(-0.6, 0, 1.4)
	bx(0.62, 0.06, 0.44, 0xd9cfc0, 0, 0.03, 0, carrier)                    # base
	bx(0.62, 0.34, 0.44, 0xc7b8a4, 0, 0.25, 0, carrier)                    # shell
	bx(0.56, 0.16, 0.38, 0xb5a48e, 0, 0.48, 0, carrier)                    # top
	bx(0.26, 0.06, 0.08, 0x8a7a64, 0, 0.58, 0, carrier)                    # handle
	for sx in [-0.28, 0.28]:
		bx(0.04, 0.22, 0.3, 0x9a8a74, sx, 0.28, 0, carrier)               # side vents
	carrier_door = gp(-0.2, 0.26, 0.225, carrier)                          # hinge at left edge
	bx(0.38, 0.3, 0.02, 0xaab4bc, 0.19, 0, 0, carrier_door)               # wire door
	for i in range(3):
		bx(0.02, 0.28, 0.03, 0x8a949c, 0.08 + i * 0.1, 0, 0.01, carrier_door)
	hit_pad(carrier, 0.55, 0, 0.3, 0)
	register_interact(carrier, {"act": "carrier"})

# ============================================================
# SHOP-ONLY DISTRACTIONS (hidden until purchased)
# ============================================================
func _build_shop_distractions() -> void:
	# robotic mouse
	var robo := gp(1.4, 0, 2.7)
	cy(0.14, 0.16, 0.07, 0xdddddd, 0, 0.04, 0, robo)
	sp(0.07, 0xff4444, 0, 0.11, 0, robo)
	bx(0.16, 0.015, 0.015, 0x333333, -0.17, 0.07, 0, robo)                 # antenna tail
	hit_pad(robo, 0.3, 0, 0.08, 0)
	add_distraction("robo", robo, "robotic mouse", 30, {"price": 45, "unlock": 3}, "pounce")
	# cat TV
	var cat_tv := gp(-6.9, 0, 2.4)
	bx(0.3, 0.4, 0.22, 0x8a6a4a, 0, 0.2, 0, cat_tv)                        # stand
	bx(0.52, 0.36, 0.05, 0x222222, 0, 0.58, 0.02, cat_tv)                  # tablet
	bx(0.46, 0.3, 0.02, 0x55aa77, 0, 0.58, 0.055, cat_tv)                  # "bird video"
	sp(0.05, 0xcc5533, 0.08, 0.61, 0.075, cat_tv)                          # the bird
	hit_pad(cat_tv, 0.36, 0, 0.5, 0)
	add_distraction("cattv", cat_tv, "cat TV (bird channel)", 40, {"price": 60, "unlock": 4}, "watch")
	# deluxe cat condo
	var condo := gp(-4.6, 3, 2.0)
	bx(0.9, 0.1, 0.9, 0xc2a678, 0, 0.05, 0, condo)
	bx(0.5, 0.5, 0.5, 0x9a6aa0, -0.15, 0.35, 0.1, condo)                   # cubby
	bx(0.24, 0.28, 0.02, 0x111111, -0.15, 0.32, 0.36, condo)              # cubby door hole
	cy(0.1, 0.1, 0.8, 0xb08a5a, 0.3, 0.5, -0.25, condo)
	bx(0.55, 0.08, 0.55, 0xc2a678, 0.2, 0.94, -0.2, condo)
	cy(0.1, 0.1, 0.6, 0xb08a5a, -0.2, 1.28, 0.15, condo)
	bx(0.5, 0.08, 0.5, 0x9a6aa0, -0.15, 1.62, 0.1, condo)
	hit_pad(condo, 0.6, 0, 0.7, 0)
	add_distraction("condo", condo, "deluxe cat condo", 60, {"price": 100, "unlock": 5}, "curl")

# ============================================================
# DAILY TRAPS (scattered to random spots each morning)
# ============================================================
func daily_trap(id: String, label: String, anim: String, danger_text: String, build: Callable):
	var g := gp(0, 0, 0)
	build.call(g)
	hit_pad(g, 0.32, 0, 0.1, 0)
	var h = add_item_hazard(id, g, {"name": label.split(" (")[0], "anim": anim, "label": label,
		"tier": 1, "dangerText": danger_text, "daily": true})
	h["stashed"] = true
	g.visible = false
	return h

func _build_daily_traps() -> void:
	daily_trap("bandball", "rubber band ball (cats swallow these)", "paw",
		"The cat is unraveling the RUBBER BAND BALL!", func(g):
			sp(0.09, 0xcc5544, 0, 0.08, 0, g)
			bx(0.02, 0.14, 0.02, 0x5577cc, 0.09, 0.05, 0.04, g)
			bx(0.02, 0.12, 0.02, 0xcccc55, -0.08, 0.04, -0.05, g))
	daily_trap("tinsel", "tinsel strand (deadly if eaten)", "eat",
		"The cat is EATING THE TINSEL!", func(g):
			for i in range(5):
				var t := bx(0.14, 0.015, 0.03, 0xd8e8f8 if i % 2 else 0xaac8e8, -0.2 + i * 0.1, 0.02, (i % 2) * 0.08 - 0.04, g)
				t.rotation.y = i * 0.7)
	daily_trap("pill", "dropped pill (very toxic)", "eat",
		"The cat is licking the DROPPED PILL!", func(g):
			var p := cy(0.03, 0.03, 0.07, 0xee8899, 0, 0.03, 0, g)
			p.rotation.z = PI / 2.0
			cy(0.028, 0.028, 0.03, 0xffffff, 0.02, 0.03, 0, g))
	daily_trap("charger", "phone charger cable", "tangle",
		"The cat is CHEWING THE CHARGER CABLE!", func(g):
			for i in range(4):
				var cbl := bx(0.22, 0.02, 0.02, 0xf0f0f0, -0.15 + i * 0.1, 0.02, sin(i * 2) * 0.08, g)
				cbl.rotation.y = i * 1.1
			bx(0.07, 0.03, 0.05, 0xdddddd, 0.25, 0.02, 0, g))
	daily_trap("twistties", "twist ties (choking hazard)", "paw",
		"The cat is batting the TWIST TIES everywhere!", func(g):
			var cols := [0xcc4444, 0x44aa44, 0xeeeeee]
			for i in range(3):
				var t := bx(0.1, 0.012, 0.012, cols[i], -0.06 + i * 0.06, 0.015, (i % 2) * 0.06 - 0.03, g)
				t.rotation.y = i * 1.3)
	daily_trap("floss", "floss pick (string + plastic)", "eat",
		"The cat is swallowing the FLOSS PICK!", func(g):
			bx(0.09, 0.015, 0.025, 0x88ccee, 0, 0.02, 0, g)
			bx(0.03, 0.012, 0.04, 0x88ccee, 0.055, 0.02, 0, g))
	daily_trap("peanuts", "packing peanuts (styrofoam snack)", "eat",
		"The cat is eating the PACKING PEANUTS!", func(g):
			for i in range(6):
				bx(0.05, 0.03, 0.035, 0xf4f0e4, -0.12 + (i % 3) * 0.1, 0.02, (i / 3) * 0.09 - 0.04, g))
	daily_trap("earring", "dropped earring (shiny, swallowable)", "paw",
		"The cat is about to SWALLOW YOUR EARRING!", func(g):
			var r := Geom.torus(0.03, 0.008, 0xffd700, 0, 0.02, 0, g)
			r.rotation.x = PI / 2.0
			sp(0.015, 0xeeeeff, 0.03, 0.025, 0, g))
	daily_trap("shoelace", "stray shoelace", "tangle",
		"The cat is tangled in the SHOELACE!", func(g):
			for i in range(4):
				var l := bx(0.16, 0.015, 0.02, 0xeeeedd, -0.15 + i * 0.1, 0.015, cos(i * 2.2) * 0.06, g)
				l.rotation.y = 0.5 + i * 0.9
			bx(0.03, 0.02, 0.02, 0xbbaa88, 0.24, 0.015, 0, g))
	daily_trap("tape", "roll of sticky tape", "paw",
		"The cat is stuck to the STICKY TAPE! It is escalating!", func(g):
			var r := Geom.torus(0.06, 0.02, 0xd8d0b8, 0, 0.03, 0, g)
			r.rotation.x = PI / 2.0
			bx(0.1, 0.012, 0.03, 0xe8e0c8, 0.1, 0.02, 0, g))

# ============================================================
# interaction behaviours that live on the props themselves
# ============================================================
## Swing the carrier door open. Spawning the kitten out of it is Phase 3.
func open_carrier() -> void:
	if carrier_open:
		Global.msg("The carrier is already open. (It is also empty — the kitten arrives in a later phase.)")
		return
	carrier_open = true
	carrier_door.rotation.y = -PI * 0.6
	Global.msg("You pop the carrier door open.", "good")

## Fill the food bowl. Cats coming running / morning→work gating is Phase 3/5;
## for now this just toggles the bowl's food visual.
func fill_bowl() -> void:
	if bowl_full:
		Global.msg("The bowl is already full.")
		return
	bowl_full = true
	bowl_food.visible = true
	Global.msg("You filled the food bowl.", "good")

# ============================================================
# local AABB of a prop (over all descendant meshes, in the node's own space)
# ============================================================
func _local_aabb(node: Node3D) -> AABB:
	var inv := node.global_transform.affine_inverse()
	var acc := AABB()
	var have := false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var rel := inv * mi.global_transform
			var ta := _xform_aabb(rel, mi.mesh.get_aabb())
			if have:
				acc = acc.merge(ta)
			else:
				acc = ta
				have = true
	if not have:
		return AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
	return acc

func _xform_aabb(t: Transform3D, a: AABB) -> AABB:
	var out := AABB(t * a.position, Vector3.ZERO)
	for i in range(1, 8):
		out = out.expand(t * a.get_endpoint(i))
	return out
