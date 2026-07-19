## Headless regression for Phase 5 (day loop, boss/away phone, shop, adoption,
## sleep→wake, emergency-vet routing, and the save system). Builds the full
## subsystem stack like Main, then drives the flow through Game's real methods.
##
##   Godot --headless --path godot res://scenes/FlowTest.tscn
extends Node3D

var world: World
var furniture: Furniture
var nav: Nav
var cats: Cats
var computer: Computer
var interactor: Interactor
var ui: GameUI
var audio: GameAudio
var game: Game
var player: Player

func _ready() -> void:
	Global.reset_new_game()

	world = World.new()
	add_child(world)
	furniture = Furniture.new()
	add_child(furniture)
	nav = Nav.new(world.walls)

	player = Player.new()
	player.position = Vector3(-0.5, 0.9, -1.2)
	add_child(player)
	player.set_physics_process(false)

	audio = GameAudio.new()
	audio.camera = player.camera
	add_child(audio)
	ui = GameUI.new()
	add_child(ui)

	cats = Cats.new()
	cats.furniture = furniture
	cats.player = player
	cats.camera = player.camera
	cats.nav = nav
	cats.walls = world.walls
	cats.audio = audio
	add_child(cats)
	cats.set_process(false)

	computer = Computer.new()
	computer.furniture = furniture
	computer.player = player
	computer.camera = player.camera
	computer.cats = cats
	computer.ui = ui
	computer.audio = audio
	add_child(computer)
	computer.set_process(false)

	interactor = Interactor.new()
	interactor.camera = player.camera
	interactor.furniture = furniture
	interactor.player = player
	interactor.cats = cats
	interactor.computer = computer
	interactor.audio = audio
	add_child(interactor)
	interactor.set_process(false)
	cats.interactor = interactor
	computer.interactor = interactor

	game = Game.new()
	game.furniture = furniture
	game.player = player
	game.cats = cats
	game.computer = computer
	game.interactor = interactor
	game.ui = ui
	game.audio = audio
	add_child(game)
	game.set_process(false)
	cats.game = game
	interactor.game = game
	game.boot()

	_run_asserts()
	get_tree().paused = false
	get_tree().quit()

func _run_asserts() -> void:
	var ok := true

	# --- start a game: one cat, HUD up, still in the intro ---
	game.start_game("Milo", Global.CAT_COLORS[1])
	ok = _check("start_game marks the game started", Global.started) and ok
	ok = _check("start spawns one cat", cats.cats.size() == 1) and ok
	ok = _check("first cat took the entered name", cats.cats[0].cat_name == "Milo") and ok
	ok = _check("day loop starts in intro", Global.day_stage == "intro") and ok

	# --- carrier intro → tutorial dismissed → work begins ---
	game.open_carrier()
	ok = _check("opening the carrier flags it open", furniture.carrier_open) and ok
	game.dismiss_tutorial()
	ok = _check("dismissing the tutorial sets tutorial_done", Global.tutorial_done) and ok
	ok = _check("tutorial → work stage", Global.day_stage == "work") and ok
	ok = _check("starter toilet hazard is armed", bool(furniture.hazards["toilet1"]["armed"])) and ok

	# --- morning feeding gates the work day ---
	Global.day_stage = "morning"
	game.on_fed()
	ok = _check("feeding in the morning unlocks work", Global.day_stage == "work") and ok

	# --- finishing the required work → evening + zero-hearts bonus ---
	Global.day_stage = "work"
	Global.hearts_lost_today = 0
	var money0 := Global.money
	game.finish_work_day()
	ok = _check("finishing work moves to evening", Global.day_stage == "evening") and ok
	ok = _check("zero-hearts bonus paid", Global.money == money0 + Global.NO_HEART_BONUS) and ok
	ok = _check("no Bob task → shop screen queued", computer.comp == "shop") and ok

	# --- shop: order an affordable in-stock item (delivered tomorrow) ---
	Global.day = 1
	Global.money = 100
	var buy_i := -1
	var target_id := ""
	var list := computer.shop_catalog()
	for i in range(list.size()):
		var it: Dictionary = list[i]
		if it["kind"] != "cat" and not bool(it["locked"]) and not bool(it["pending"]) and int(it["price"]) <= Global.money:
			buy_i = i
			target_id = String(it["id"])
			break
	ok = _check("an affordable item is in stock", buy_i >= 0) and ok
	if buy_i >= 0:
		var price := int(list[buy_i]["price"])
		var m1 := Global.money
		computer.buy_item(buy_i)
		ok = _check("buying deducts the price", Global.money == m1 - price) and ok
		var rec = _catalog_rec(target_id)
		ok = _check("ordered item is pending delivery", rec != null and bool(rec["pending"])) and ok
		ok = _check("purchase logged in bought_today", Global.bought_today.size() == 1) and ok

	# --- adoption: a second cat becomes available on day 3 ---
	Global.day = 3
	ok = _check("cat #2 available on day 3", Global.cat_available(cats.cats.size())) and ok
	game.open_adopt()
	game.confirm_adopt("Trouble", Global.CAT_COLORS[2])
	ok = _check("adoption is queued for tomorrow", Global.pending_adopts.size() == 1) and ok

	# --- sleep → wake: heal, deliver orders + adoption, roll to next day ---
	Global.hearts = 5
	game.go_to_sleep()
	ok = _check("sleeping heals up to NIGHT_HEAL", Global.hearts == 8) and ok
	ok = _check("day-summary overlay is up", ui.is_day_overlay_open()) and ok
	var day_before := Global.day
	ui._on_day_btn()   # press WAKE UP
	ok = _check("waking advances the day", Global.day == day_before + 1) and ok
	ok = _check("new day starts in the morning", Global.day_stage == "morning") and ok
	ok = _check("overnight adoption arrived (2 cats)", cats.cats.size() == 2) and ok
	ok = _check("pending adoptions cleared", Global.pending_adopts.is_empty()) and ok
	if target_id != "":
		var rec2 = _catalog_rec(target_id)
		ok = _check("ordered item delivered (owned, not pending)", rec2 != null and bool(rec2["owned"]) and not bool(rec2["pending"])) and ok
	ok = _check("bowl reset for the new morning", not furniture.bowl_full) and ok
	ok = _check("player wakes upstairs in bed", player.global_position.y > 2.5) and ok

	# --- save/load round-trips the run ---
	ok = _check("a save exists after the morning autosave", game.has_save()) and ok
	var saved_day := Global.day
	var saved_money := Global.money
	Global.money = 99999
	Global.day = 999
	ok = _check("load restores saved money", game.load_game() and Global.money == saved_money) and ok
	ok = _check("load restores saved day", Global.day == saved_day) and ok
	ok = _check("load restores the roster", cats.cats.size() == 2) and ok

	# --- boss phone: answering a ringing phone clears the alarm ---
	game.ringing = true
	game.ring_t = 5.0
	game.away_time = 40.0
	game.answer_phone()
	ok = _check("answering the phone stops the ring", not game.ringing) and ok
	ok = _check("answering resets the away timer", game.away_time == 0.0) and ok

	# --- away-limit tightens with the chaos phase ---
	Global.phase = 1
	var l1 := game._away_limit()
	Global.phase = 3
	var l3 := game._away_limit()
	ok = _check("away limit shrinks in later phases", l1 > l3) and ok

	# --- emergency vet routing zeroes the wallet and routes to evening ---
	Global.money = 250
	Global.hearts = Global.HEART_MAX
	var vc: Cat = cats.cats[0]
	cats.hurt_cat(vc, "test — cat is in danger")   # from full hearts this won't trigger vet
	Global.hearts = 2
	cats.hurt_cat(vc, "test — down to the wire")    # drops to 1 → vet run
	ok = _check("vet emergency zeroes the wallet", Global.money == 0) and ok
	ok = _check("vet restores full hearts", Global.hearts == Global.HEART_MAX) and ok
	ok = _check("vet writes off the day into evening", Global.day_stage == "evening") and ok

	# --- getting fired ends the game ---
	game.end_game()
	ok = _check("end_game sets game over", Global.game_over) and ok

	print("FLOW TEST: ", "PASS" if ok else "FAIL")

func _catalog_rec(id: String):
	if furniture.distracts.has(id):
		return furniture.distracts[id]
	if furniture.containers.has(id):
		return furniture.containers[id]
	return null

func _check(label: String, cond: bool) -> bool:
	print("  [%s] %s" % ["ok" if cond else "XX", label])
	return cond
