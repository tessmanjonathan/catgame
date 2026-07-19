## First-person player controller. Port of the PLAYER section + the movement
## block of the main loop in game.js. Uses a CharacterBody3D (real physics
## collision) instead of the web build's manual AABB sweep.
class_name Player
extends CharacterBody3D

const WALK_SPEED := 3.6
const SPRINT_SPEED := 5.4
const MOUSE_SENS := 0.0023
const GRAVITY := 22.0
const PITCH_LIMIT := 1.45

var head: Node3D
var camera: Camera3D

var yaw := PI
var pitch := -0.14
var auto_move := Vector2.ZERO  # debug: forces input_dir when nonzero

func _ready() -> void:
	# collision capsule: radius = PLAYER_R, standing height ~ 1.7m
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Global.PLAYER_R
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)

	head = Node3D.new()
	head.position = Vector3(0, Global.EYE, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 120.0
	head.add_child(camera)

	# The staircases are ~44deg ramps, right at the default 45deg floor limit.
	# Raise the limit and keep floor snapping so the player walks up/down them
	# smoothly instead of the ramp reading as a wall (or sliding back down).
	floor_max_angle = deg_to_rad(55)
	floor_snap_length = 0.6
	floor_stop_on_slope = true
	floor_block_on_wall = false

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_look()

func _unhandled_input(event: InputEvent) -> void:
	if Global.in_computer:
		return   # seated at the computer — the monitor owns input
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch -= event.relative.y * MOUSE_SENS
		pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
		_apply_look()

func _apply_look() -> void:
	rotation.y = yaw
	head.rotation.x = pitch

func _physics_process(delta: float) -> void:
	# gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	if Global.in_computer:
		input_dir = Vector2.ZERO   # seated — the monitor close-up owns the camera
	if auto_move != Vector2.ZERO:  # debug/test hook (headless stair traversal)
		input_dir = auto_move
	var dir := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		# forward is -Z in Godot; rotate input by yaw
		var forward := -transform.basis.z
		var right := transform.basis.x
		dir = (right * input_dir.x + forward * -input_dir.y).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
