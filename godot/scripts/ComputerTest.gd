## Headless regression for Phase 4 (computer: task list, the five minigames,
## progress saving, X/Backspace navigation, payouts, cat-on-keyboard block).
## Drives Computer through its real key-routing (_handle_typing) with synthetic
## key events, solving each game deterministically.
##
##   Godot --headless --path godot res://scenes/ComputerTest.tscn
extends Node3D

var world: World
var furniture: Furniture
var nav: Nav
var cats: Cats
var camera: Camera3D
var player: Node3D
var computer: Computer

func _ready() -> void:
	Global.day = 1
	Global.money = 0
	Global.day_stage = "work"
	Global.in_computer = false
	Global.tutorial_done = true
	Global.phase = 1

	world = World.new()
	add_child(world)
	furniture = Furniture.new()
	add_child(furniture)
	nav = Nav.new(world.walls)

	camera = Camera3D.new()
	add_child(camera)
	# seat the camera right at the monitor so enter()'s distance gate passes
	camera.position = Computer.MONITOR_POS + Vector3(0, 0, 0.75)
	player = Node3D.new()
	add_child(player)

	cats = Cats.new()
	cats.furniture = furniture
	cats.player = player
	cats.camera = camera
	cats.nav = nav
	cats.walls = world.walls
	add_child(cats)
	cats.set_process(false)

	computer = Computer.new()
	computer.furniture = furniture
	computer.player = player
	computer.camera = camera
	computer.cats = cats
	add_child(computer)
	computer.set_process(false)   # no camera glide in the headless test

	_run_asserts()
	get_tree().quit()

# ---- synthetic key press through the real handler ----
func _press(s: String) -> void:
	var e := InputEventKey.new()
	e.pressed = true
	if s == "Backspace":
		e.keycode = KEY_BACKSPACE
	elif s == "Escape":
		e.keycode = KEY_ESCAPE
	else:
		e.unicode = s.unicode_at(0)
	computer._handle_typing(e)

# ---- the correct next key for whatever the current game is showing ----
func _solve_key(gkey: String, st: Dictionary) -> String:
	match gkey:
		"report":
			return String(st["word"])[int(st["idx"])]
		"calendar":
			var keys: Array = st["keys"]
			return str(keys[int(st["day"])])
		"mail":
			return "d" if bool(st["spam"]) else "r"
		"sheet":
			var target := String(st["target"])
			return target[0] if int(st["stage"]) == 0 else target[1]
		"call":
			st["show_until"] = 0   # skip the memorize countdown
			var opts: Array = st["opts"]
			var words: Array = st["words"]
			return str(opts.find(words[int(st["picked"])]) + 1)
	return ""

# solve the on-screen task to completion, driving it key by key
func _solve_current_task() -> void:
	var guard := 0
	while computer.comp == "game" and guard < 2000:
		guard += 1
		var t: Dictionary = computer.day_tasks[computer.cur_task_i]
		var st: Dictionary = t["st"]
		_press(_solve_key(String(t["key"]), st))

func _run_asserts() -> void:
	var ok := true

	# --- task list: day 1 makes 3 non-Bob tasks ---
	computer.enter()
	ok = _check("enter() seats the player at the computer", Global.in_computer) and ok
	ok = _check("day 1 has 3 tasks", computer.day_tasks.size() == 3) and ok
	var any_bob := false
	for t in computer.day_tasks:
		if bool(t["bob"]):
			any_bob = true
	ok = _check("no Bob task on day 1", not any_bob) and ok
	ok = _check("starts on the task list", computer.comp == "tasks") and ok

	# --- start + complete task 1 → payout ---
	var money_before := Global.money
	_press("1")
	ok = _check("selecting a task opens the game", computer.comp == "game" and computer.cur_task_i == 0) and ok
	_solve_current_task()
	ok = _check("finishing pays out (+TASK_PAY)", Global.money == money_before + Global.TASK_PAY) and ok
	ok = _check("finished task is marked done", bool(computer.day_tasks[0]["done"])) and ok
	ok = _check("back on the task list after completing", computer.comp == "tasks") and ok

	# --- progress saving: partial work survives Backspace, resumes on reselect ---
	_press("2")
	var st2: Dictionary = computer.day_tasks[1]["st"]
	# advance at least one unit of progress
	var guard := 0
	while int(st2["done"]) == 0 and guard < 500:
		guard += 1
		_press(_solve_key(String(computer.day_tasks[1]["key"]), st2))
	var saved := int(st2["done"])
	ok = _check("made partial progress on task 2", saved > 0) and ok
	_press("Backspace")
	ok = _check("Backspace returns to the task list", computer.comp == "tasks" and computer.cur_task_i == -1) and ok
	ok = _check("progress is preserved on the task", computer.day_tasks[1]["st"] != null and int(computer.day_tasks[1]["st"]["done"]) == saved) and ok
	_press("2")
	ok = _check("reselecting resumes saved progress", computer.comp == "game" and int(st2["done"]) == saved) and ok

	# --- X steps away from the computer ---
	_press("x")
	ok = _check("X exits the computer", not Global.in_computer) and ok

	# --- all five games individually start + solve to completion ---
	for gkey in Computer.GAME_KEYS:
		var st := {}
		computer._game_start(gkey, st)
		ok = _check("%s starts with total>0" % gkey, int(st["total"]) > 0 and int(st["done"]) == 0) and ok
		var g2 := 0
		while int(st["done"]) < int(st["total"]) and g2 < 4000:
			g2 += 1
			computer._game_key(gkey, st, _solve_key(gkey, st))
		ok = _check("%s solvable to 100%%" % gkey, int(st["done"]) >= int(st["total"])) and ok

	# --- report: a wrong key flags but does not advance ---
	var rst := {}
	computer._game_start("report", rst)
	var idx0 := int(rst["idx"])
	# find a key that is NOT the expected char
	var expected := String(rst["word"])[idx0]
	var bad := "z" if expected != "z" else "q"
	computer._game_key("report", rst, bad)
	ok = _check("wrong key does not advance", int(rst["idx"]) == idx0 and bool(rst["wrong"])) and ok

	# --- cat-on-keyboard block ---
	Global.hearts = Global.HEART_MAX
	var c := cats.spawn_cat("Blocky", Global.CAT_COLORS[0], Global.CHAOS_LADDER[0])
	player.global_position = Vector3(-6.8, 0.0, -2.2)
	c.g.position = Vector3(-6.8, 0.0, -2.4)   # right on top of the keyboard
	c.mode = "pester"
	ok = _check("a pestering cat blocks the keyboard", computer._cat_blocking()) and ok
	c.g.position = Vector3(4.0, 0.0, 4.0)      # shooed away
	ok = _check("a distant cat does not block", not computer._cat_blocking()) and ok

	print("COMPUTER TEST: ", "PASS" if ok else "FAIL")

func _check(label: String, cond: bool) -> bool:
	print("  [%s] %s" % ["ok" if cond else "XX", label])
	return cond
