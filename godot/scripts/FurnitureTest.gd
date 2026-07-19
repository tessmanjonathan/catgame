## Headless regression + visual check for Phase 2 (furniture + interactables).
##
## Asserts (run always, headless-friendly):
##   - the registries populated and the interactable click-volumes built
##   - crosshair ray finds the aimed prop and the toggle/pick-up/stash flow works
##
## Screenshots (only when CATGAME_SHOTDIR is set; needs the real renderer):
##   cycles the camera through several rooms and saves <dir>/ft_<room>.png.
##
##   Godot --headless --path godot res://scenes/FurnitureTest.tscn
##   CATGAME_SHOTDIR=/abs/dir Godot --path godot res://scenes/FurnitureTest.tscn
extends Node3D

var world: World
var furniture: Furniture
var camera: Camera3D
var interactor: Interactor

const POSES := [
	["office", Vector3(-3.2, 1.6, -1.4), Vector3(-6.9, 1.0, -3.2)],
	["kitchen", Vector3(3.6, 1.6, -1.2), Vector3(5.6, 1.0, -5.2)],
	["tv", Vector3(-3.4, 1.6, 3.2), Vector3(-6.5, 0.9, 4.5)],
	["dining", Vector3(3.4, 1.6, 1.6), Vector3(5.5, 0.9, 3.5)],
]
var _shot_dir := ""
var _shot_i := 0
var _frames := 0

func _ready() -> void:
	world = World.new()
	add_child(world)
	furniture = Furniture.new()
	add_child(furniture)
	camera = Camera3D.new()
	camera.fov = 72.0
	add_child(camera)
	interactor = Interactor.new()
	interactor.camera = camera
	interactor.furniture = furniture
	interactor.player = self
	interactor.set_process(false)   # we drive the ray manually in the asserts
	add_child(interactor)

	_run_asserts()

	_shot_dir = OS.get_environment("CATGAME_SHOTDIR")
	if _shot_dir == "":
		get_tree().quit()

func _aim(from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)
	camera.force_update_transform()

func _run_asserts() -> void:
	var ok := true
	ok = _check("hazards populated", furniture.hazards.size() >= 30) and ok
	ok = _check("containers populated", furniture.containers.size() >= 6) and ok
	ok = _check("distracts populated", furniture.distracts.size() >= 8) and ok
	ok = _check("interactables built", furniture.interactables.size() >= 45) and ok

	# --- toggle flow: the main-bath toilet starts armed; look at it and disarm ---
	_aim(Vector3(-1.6, 1.45, 3.4), Vector3(-1.6, 0.45, 5.3))
	var aimed = interactor._aimed()
	ok = _check("aim finds toilet1", aimed != null and aimed.get("id", "") == "toilet1") and ok
	ok = _check("toilet1 starts armed", furniture.hazards["toilet1"]["armed"] == true) and ok
	interactor._on_left_click()
	ok = _check("toilet1 disarmed by click", furniture.hazards["toilet1"]["armed"] == false) and ok

	# --- item pick-up + stash flow: grab the ribbon, stash it in the toy chest ---
	_aim(Vector3(-4.4, 1.3, 1.6), Vector3(-4.4, 0.55, 3.1))
	aimed = interactor._aimed()
	ok = _check("aim finds ribbon", aimed != null and aimed.get("id", "") == "ribbon") and ok
	interactor._on_left_click()
	ok = _check("ribbon now held", interactor.held != null and interactor.held["id"] == "ribbon") and ok
	ok = _check("ribbon mesh hidden", not (furniture.hazards["ribbon"]["mesh"] as Node3D).visible) and ok
	_aim(Vector3(-7.5, 1.3, 3.6), Vector3(-7.5, 0.4, 2.0))
	aimed = interactor._aimed()
	ok = _check("aim finds toy chest", aimed != null and aimed.get("id", "") == "chest") and ok
	interactor._on_left_click()
	ok = _check("ribbon stashed (held cleared)", interactor.held == null) and ok
	ok = _check("chest used == 1", furniture.containers["chest"]["used"] == 1) and ok

	# --- hidden props (shop items / daily traps) are not aimable ---
	var robo_vis: bool = (furniture.distracts["robo"]["mesh"] as Node3D).visible
	ok = _check("shop item hidden until bought", not robo_vis) and ok

	print("FURNITURE TEST: ", "PASS" if ok else "FAIL")

func _check(label: String, cond: bool) -> bool:
	print("  [%s] %s" % ["ok" if cond else "XX", label])
	return cond

func _process(_delta: float) -> void:
	if _shot_dir == "":
		return
	if _shot_i >= POSES.size():
		get_tree().quit()
		return
	var pose = POSES[_shot_i]
	_frames += 1
	if _frames == 1:
		_aim(pose[1], pose[2])   # aim, then let it render a few frames
	elif _frames >= 12:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/ft_%s.png" % [_shot_dir, pose[0]])
		_shot_i += 1
		_frames = 0
