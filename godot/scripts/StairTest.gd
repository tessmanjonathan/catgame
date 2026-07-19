## Headless stair-traversal test. Places the player at the base of each
## staircase, drives it forward, and logs height so we can confirm it climbs
## to the upstairs level (~3) and descends to the basement (~-3).
extends Node3D

var player: Player
var phase := 0
var frames := 0
var start_y := 0.0

func _ready() -> void:
	var world := World.new()
	add_child(world)
	player = Player.new()
	add_child(player)
	_place_up()

func _place_up() -> void:
	# up-stairs: cx ~1.6, base at z=-1.9 (main floor, y=0), top y=3
	player.position = Vector3(1.6, 1.0, -1.6)
	player.velocity = Vector3.ZERO
	player.yaw = 0.0            # yaw 0 => forward is world -Z
	player.rotation.y = 0.0
	player.auto_move = Vector2(0, -1)  # walk forward (-Z), up the run
	start_y = player.position.y
	print("[UP] start ", player.position)

func _place_down() -> void:
	# down-stairs: cx ~-1.45, base at z=-1.9 (main floor, y=0), bottom y=-3
	player.position = Vector3(-1.45, 1.0, -1.6)
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.rotation.y = 0.0
	player.auto_move = Vector2(0, -1)
	start_y = player.position.y
	print("[DOWN] start ", player.position)

func _physics_process(_delta: float) -> void:
	frames += 1
	if frames % 20 == 0:
		var p := player.position
		print("  f=%d  y=%.2f  z=%.2f  on_floor=%s" % [frames, p.y, p.z, str(player.is_on_floor())])
	if phase == 0 and frames >= 240:
		var reached: float = player.position.y
		print("[UP] end y=%.2f (want ~3.0) => %s" % [reached, "PASS" if reached > 2.5 else "FAIL"])
		phase = 1
		frames = 0
		_place_down()
	elif phase == 1 and frames >= 240:
		var reached: float = player.position.y
		print("[DOWN] end y=%.2f (want ~-3.0) => %s" % [reached, "PASS" if reached < -2.5 else "FAIL"])
		get_tree().quit()
