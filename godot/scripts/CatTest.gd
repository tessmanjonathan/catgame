## Headless regression for Phase 3 (cats: nav, spawn, animation, AI, danger,
## distraction, collision, escapes, hiding). Drives the cat systems directly and
## deterministically (no reliance on random catDecide).
##
##   Godot --headless --path godot res://scenes/CatTest.tscn
extends Node3D

var world: World
var furniture: Furniture
var nav: Nav
var cats: Cats
var camera: Camera3D
var player: Node3D

func _ready() -> void:
	world = World.new()
	add_child(world)
	furniture = Furniture.new()
	add_child(furniture)
	nav = Nav.new(world.walls)

	camera = Camera3D.new()
	add_child(camera)
	player = Node3D.new()
	add_child(player)

	cats = Cats.new()
	cats.furniture = furniture
	cats.player = player
	cats.camera = camera
	cats.nav = nav
	cats.walls = world.walls
	add_child(cats)
	cats.set_process(false)   # we step update_cat manually for determinism

	_run_asserts()
	get_tree().quit()

# step one cat forward `steps` frames of `dt` seconds
func _sim(c: Cat, dt: float, steps: int) -> void:
	for i in range(steps):
		cats.update_cat(c, dt)

func _run_asserts() -> void:
	var ok := true
	Global.hearts = Global.HEART_MAX
	Global.vet_today = false
	Global.tutorial_done = true
	Global.phase = 3

	# --- nav grid: built for all three levels, with a mix of blocked/open ---
	ok = _check("nav has 3 levels", nav.grids.size() == 3) and ok
	var g0: PackedByteArray = nav.grids[0.0]
	var open_cnt := 0
	var blocked_cnt := 0
	for v in g0:
		if v != 0: open_cnt += 1
		else: blocked_cnt += 1
	ok = _check("nav level 0 has open cells", open_cnt > 100) and ok
	ok = _check("nav level 0 has blocked cells", blocked_cnt > 20) and ok
	# a cell inside the stairwell core wall is blocked; open office floor is not
	var wall_cell := nav.cell(0.4, -3.5)
	var open_cell := nav.cell(-5.0, -3.0)
	ok = _check("cell in a wall is blocked", g0[nav.idx(wall_cell.x, wall_cell.y)] == 0) and ok
	ok = _check("cell in open room is walkable", g0[nav.idx(open_cell.x, open_cell.y)] != 0) and ok

	# --- pathing: route across the office returns a multi-point path ---
	var path := nav.grid_path(0.0, -7.0, -5.0, -3.0, -1.0)
	ok = _check("grid_path returns a path", path.size() >= 1) and ok

	# --- spawn: cat exists, has a mesh, is registered as a clickable 'cat' ---
	var c := cats.spawn_cat("Testo", Global.CAT_COLORS[1], Global.CHAOS_LADDER[0])
	c.g.visible = true
	ok = _check("cat spawned", cats.cats.size() == 1) and ok
	ok = _check("cat has mesh parts", c.legs.size() == 4 and c.body != null) and ok
	var has_cat_click := false
	for rec in furniture.interactables:
		if rec.get("act", "") == "cat":
			has_cat_click = true
	ok = _check("cat registered as clickable", has_cat_click) and ok

	# --- animation: poses apply without error; 'sit' folds the body ---
	cats._now = 1.0
	c.mode = "wander"
	c.idle_pose = "sit"
	cats.animate_cat(c)
	ok = _check("sit pose folds body (rot.z≈0.5)", absf(c.body.rotation.z - 0.5) < 0.01) and ok
	c.mode = "walk"
	cats.animate_cat(c)   # exercises the walk pose path
	c.reset_pose()
	ok = _check("reset_pose restores body", c.body.rotation.z == 0.0) and ok

	# --- danger seeking + shared hearts: cat walks to an armed toilet, loses a heart ---
	var toilet: Dictionary = furniture.hazards["toilet1"]
	toilet["armed"] = true
	furniture.apply_toggle_vis(toilet)
	c.g.position = Vector3(-1.6, 0, 4.4)
	c.mode = "wander"
	cats.cat_go_to(c, -1.6, 0, 5.3, "danger", "toilet1")
	_sim(c, 0.1, 60)   # ~6s: walk the short distance and settle into danger
	ok = _check("cat reaches danger at the toilet", c.mode == "danger") and ok
	var hearts_before := Global.hearts
	_sim(c, 0.1, 90)   # ~9s: the 8s hurt timer elapses
	ok = _check("armed hazard costs a heart", Global.hearts < hearts_before) and ok
	# disarming the hazard frees the cat next frame
	toilet["armed"] = false
	cats.update_cat(c, 0.1)
	ok = _check("cat leaves once hazard is safe", c.mode != "danger") and ok

	# --- collision: a cat pushed into a wall gets shoved back out ---
	var col := cats.collide_cat(0.85, -3.5, 0.0)   # just east of the stairwell core wall
	ok = _check("collide_cat pushes out of wall", col.x > 0.9) and ok

	# --- distraction luring: an owned toy pulls the nearest free cat ---
	c.mode = "wander"
	c.distract_id = null
	c.g.position = Vector3(-7.0, 0, -0.8)
	cats.distract_cat("bed")   # the cat bed is an owned distraction
	ok = _check("cat lured onto the toy", c.distract_id == "bed" and (c.mode == "walk" or c.mode == "distracted")) and ok

	# --- window escape: a windowed hazard eventually puts the cat outside ---
	Global.hearts = Global.HEART_MAX
	var win: Dictionary = furniture.hazards["winKitchen"]
	win["armed"] = true
	furniture.apply_toggle_vis(win)
	c.g.position = Vector3(5.0, 0, -5.4)
	c.surf = null
	cats.enter_danger(c, win)
	_sim(c, 0.2, 70)   # >10s of danger_age → the cat climbs out
	ok = _check("cat escapes out the window", c.mode == "outside") and ok
	var out_pos: Vector3 = win["outsidePos"]
	ok = _check("escaped cat is at the outside spot", c.g.position.distance_to(out_pos) < 0.01) and ok
	# bringing it back in
	cats.end_danger(c, false)
	ok = _check("cat comes back inside", c.mode != "outside") and ok
	win["armed"] = false
	furniture.apply_toggle_vis(win)

	# --- hiding ("too quiet"): a wandering cat goes off to a secret nap ---
	c.mode = "wander"
	c.g.position = Vector3(-5.0, 0, -3.0)
	var triggered := cats.trigger_quiet()
	ok = _check("quiet event triggers", triggered) and ok
	_sim(c, 0.2, 120)   # walk to the hiding spot
	ok = _check("cat is now hiding (or already found)", c.mode == "hiddenNap" or c.mode == "distracted") and ok

	print("CAT TEST: ", "PASS" if ok else "FAIL")

func _check(label: String, cond: bool) -> bool:
	print("  [%s] %s" % ["ok" if cond else "XX", label])
	return cond
