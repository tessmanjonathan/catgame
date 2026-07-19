## Root of the game. Sets up environment, lights, the house, and the player.
## Port of the three.js scene/renderer/lights setup at the top of game.js.
extends Node3D

const SKY := Color(0.529, 0.71, 0.878)  # 0x87b5e0

var world: World
var furniture: Furniture
var player: Player
var interactor: Interactor
var nav: Nav
var cats: Cats
var computer: Computer
var ui: GameUI
var audio: GameAudio
var game: Game

func _ready() -> void:
	_setup_environment()
	_setup_lights()

	world = World.new()
	add_child(world)

	furniture = Furniture.new()
	add_child(furniture)

	player = Player.new()
	# start position from game.js: {x:-0.5, y:0, z:-1.2, yaw:PI, pitch:-0.14}
	player.position = Vector3(-0.5, 0.9, -1.2)
	player.yaw = PI
	player.pitch = -0.14
	add_child(player)

	# synthesized audio, then the HUD/overlay layer
	audio = GameAudio.new()
	audio.camera = player.camera
	add_child(audio)
	ui = GameUI.new()
	add_child(ui)

	# the cats: nav grid off the world's wall AABBs, then the manager
	nav = Nav.new(world.walls)
	cats = Cats.new()
	cats.furniture = furniture
	cats.player = player
	cats.camera = player.camera
	cats.nav = nav
	cats.walls = world.walls
	cats.audio = audio
	add_child(cats)

	# the office computer + its five minigames, rendered onto the monitor
	computer = Computer.new()
	computer.furniture = furniture
	computer.player = player
	computer.camera = player.camera
	computer.cats = cats
	computer.ui = ui
	computer.audio = audio
	add_child(computer)

	# crosshair look-at → hint → click, over the furniture's interactables
	interactor = Interactor.new()
	interactor.camera = player.camera
	interactor.furniture = furniture
	interactor.player = player
	interactor.cats = cats
	interactor.computer = computer
	interactor.audio = audio
	add_child(interactor)
	cats.interactor = interactor
	computer.interactor = interactor

	# the flow orchestrator: day loop, boss, shop routing, save, pacing
	game = Game.new()
	game.furniture = furniture
	game.player = player
	game.cats = cats
	game.computer = computer
	game.interactor = interactor
	game.ui = ui
	game.audio = audio
	add_child(game)
	cats.game = game
	interactor.game = game
	game.boot()

	# Debug: CATGAME_SHOT=/path.png captures a frame then quits (dev smoke test).
	# Auto-start a game (skipping the intro) so there's live play to screenshot.
	var shot := OS.get_environment("CATGAME_SHOT")
	if shot != "":
		game.debug_quickstart()
		_shot_path = shot
		_shot_frames = 30

var _shot_path := ""
var _shot_frames := 0

func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_shot_frames -= 1
	if _shot_frames <= 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		_shot_path = ""
		get_tree().quit()

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.65
	# fog: three.js Fog(0x87b5e0, 30, 70) — linear-ish depth fog
	env.fog_enabled = true
	env.fog_light_color = SKY
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 70.0
	env.fog_density = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _setup_lights() -> void:
	# sun: DirectionalLight(0xfff2d8, 0.9) at (12,20,8)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color.hex(0xfff2d8ff)
	sun.light_energy = 0.9
	sun.look_at_from_position(Vector3(12, 20, 8), Vector3.ZERO, Vector3.UP)
	add_child(sun)
	# fill: DirectionalLight(0xaac4ff, 0.3) at (-8,6,-10)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color.hex(0xaac4ffff)
	fill.light_energy = 0.3
	fill.look_at_from_position(Vector3(-8, 6, -10), Vector3.ZERO, Vector3.UP)
	add_child(fill)
