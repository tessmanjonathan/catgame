## The game-flow orchestrator. Ports the GAME FLOW + BOSS/AWAY sections of
## game.js plus the pacing half of the main tick() loop (phase progression, the
## away/boss desk phone, the "…it's too quiet" event, paced hazard arming, the
## meow loop, and the seated-screen refresh).
##
## It owns the endless day loop (intro → morning → work → evening → sleep), the
## start/tutorial/pause/end/day-summary/adopt/confirm modals (driving GameUI),
## the emergency-vet routing, and the save system. Movement lives in Player, the
## camera glide in Computer, and the cat sim in Cats; this node coordinates them.
##
## process_mode is ALWAYS so it can still catch the pause key and run its guard
## while get_tree().paused freezes the 3D world during any modal.
class_name Game
extends Node

const SAVE_PATH := "user://catgame_save.json"

# ---- wired by Main ----
var furniture: Furniture
var player: Player
var cats: Cats
var computer: Computer
var interactor: Interactor
var ui: GameUI
var audio: GameAudio

# ---- boss / away ----
var away_time := 0.0
var ringing := false
var ring_t := 0.0
var ring_beep_t := 0.0

# ---- pacing ----
var risk_t := 20.0
var quiet_t := -1.0
var quiet_done := false
var _p2 := false
var _p3 := false
var meow_loop_t := 2.1
var _was_in_computer := false

# ---- modal / freeze bookkeeping ----
var _freeze := {}          # reason -> true; sim is frozen while any is set
var _paused := false

const BOSS_LINES := [
	"📞 \"Hey, saw you went idle — just circling back!\" You survived the boss call.",
	"📞 \"Quick ping! You there? Great.\" The boss hangs up, suspicious.",
	"📞 \"Do you have a sec? Never mind, keep grinding.\" Close one.",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Called once Main has wired every subsystem: show the start screen.
func boot() -> void:
	ui.game = self
	computer.game = self
	ui.show_start(has_save())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ============================================================
# start / continue / restart
# ============================================================
func start_game(name_: String, color_def: Dictionary) -> void:
	var nm := name_.strip_edges()
	if nm == "":
		nm = "Whiskers"
	nm = nm.substr(0, 14)
	cats.spawn_cat(nm, color_def, Global.CHAOS_LADDER[0])
	ui.hide_start()
	ui.show_hud()
	Global.started = true
	computer.make_day_tasks()
	update_hearts()
	update_econ()
	_unfreeze_all()
	set_objective("📦 Set %s free — walk up and click the carrier" % cats.cat_names_joined())
	Global.msg("You just got home from the shelter. The carrier is meowing.")

func continue_game() -> void:
	if not load_game():
		return
	ui.hide_start()
	ui.show_hud()
	Global.started = true
	Global.tutorial_done = true
	day_setup()          # wakes the loaded day up as a fresh morning
	_unfreeze_all()

func restart() -> void:
	Global.reset_new_game()
	get_tree().paused = false
	get_tree().reload_current_scene()

## Dev/screenshot helper: start a default game and skip the carrier intro so the
## house has live, active cats immediately (used under CATGAME_SHOT).
func debug_quickstart() -> void:
	start_game("Whiskers", Global.CAT_COLORS[0])
	furniture.carrier_open = true
	cats.release_cats()
	dismiss_tutorial()

# ============================================================
# the carrier intro → tutorial
# ============================================================
func open_carrier() -> void:
	if furniture.carrier_open:
		Global.msg("The carrier is empty now. It still smells like adventure.")
		return
	furniture.carrier_open = true
	furniture.carrier_door.rotation.y = -1.9
	Global.msg("You open the carrier door...", "good")
	cats.release_cats()
	var n := cats.cats.size()
	for i in range(n):
		var pitch := 1.25 + i * 0.12
		_after(0.6 + i * 1.0, func():
			if not Global.game_over:
				audio.meow(0.5, pitch))
	_after(1.4 + n * 1.0, func():
		if Global.game_over:
			return
		Global.msg("\"Alright %s, time for me to get some work done. Be good!\"" % cats.cat_names_joined(), "talk")
		show_tutorial())

func show_tutorial() -> void:
	ui.show_tutorial("Welcome home, %s!" % cats.cat_names_joined())
	_set_freeze("tutorial", true)

func dismiss_tutorial() -> void:
	Global.tutorial_done = true
	Global.day_stage = "work"
	ui.hide_tutorial()
	_set_freeze("tutorial", false)
	set_objective("💻 Go to the OFFICE and click the computer — today's tasks are on it")
	cats.begin_play()   # arm the starter toilet hazard + flip intro cats to active

# ============================================================
# work day → evening → sleep
# ============================================================
func finish_work_day() -> void:
	Global.day_stage = "evening"
	ringing = false
	away_time = 0.0
	ui.set_away_warn(false)
	if Global.hearts_lost_today == 0:
		Global.money += Global.NO_HEART_BONUS
		computer.earned_today += Global.NO_HEART_BONUS
		Global.msg("🎉 Work day done! Zero-hearts-lost bonus: +$%d!" % Global.NO_HEART_BONUS, "good")
	else:
		Global.msg("🎉 Work day done! You are off the clock.", "good")
	var bob_left := computer._bob_open()
	computer.comp = "tasks" if bob_left else "shop"
	if bob_left:
		Global.msg("📎 Bob's task is still open — do it for the extra cash, or ignore him (again).")
		set_objective("📎 Optional: finish Bob's task · 🛒 SHOP on the computer · then go to BED")
	else:
		set_objective("🛒 SHOP on the computer (optional) — then go UPSTAIRS and click your BED to sleep")
	update_econ()

## Bed clicked in the evening: nudge the player if they can still afford to shop.
func try_sleep() -> void:
	var buyable := 0
	for it in computer.shop_catalog():
		if not bool(it["pending"]) and not bool(it["locked"]) and int(it["price"]) <= Global.money:
			buyable += 1
	if buyable > 0:
		var thing := "is 1 thing" if buyable == 1 else "are %d things" % buyable
		show_confirm("🛒 Wait — the shop is still open",
			"Are you sure you don't want to buy anything else for your cat? You have $%d, and there %s you can afford." % [Global.money, thing],
			"🛏 SLEEP ANYWAY", "🛒 KEEP SHOPPING",
			func(): go_to_sleep(), Callable())
	else:
		go_to_sleep()

func go_to_sleep() -> void:
	if Global.in_computer:
		computer.exit()
	# put down whatever (or whoever) you're carrying
	if interactor.held != null:
		if not (interactor.held is Cat):
			var h = interactor.held
			h["held"] = false
			var mesh: Node3D = h["mesh"]
			mesh.visible = true
			mesh.position = Vector3(-5.6, 3.15, -2.6)
		interactor.held = null
		interactor._set_held_text("")
	# the cats settle down for the night
	for c in cats.cats:
		cats.end_danger(c, false)
		c.mode = "distracted"
		c.distract_t = 9999.0
		c.distract_id = null
		c.waypoints = []
	var healed: int = mini(Global.HEART_MAX - Global.hearts, Global.NIGHT_HEAL)
	Global.hearts += healed
	var names := cats.cat_names_joined()
	var done_all := 0
	var has_bob_done := false
	for t in computer.day_tasks:
		if bool(t["done"]):
			done_all += 1
			if bool(t["bob"]):
				has_bob_done = true
	var lines: Array = []
	lines.append("💼 Tasks finished: %d/%d%s" % [done_all, computer.day_tasks.size(), (" (including Bob's!)" if has_bob_done else "")])
	lines.append("💰 Earned today: $%d — wallet: $%d" % [computer.earned_today, Global.money])
	lines.append("💔 Hearts lost today: %d" % Global.hearts_lost_today)
	if Global.vet_today:
		lines.append("🏥 Emergency vet visit. It cost literally everything.")
	if healed > 0:
		lines.append("😴 %s slept 16 hours and recovered %d heart%s (%d/%d ❤️)" % [names, healed, ("s" if healed > 1 else ""), Global.hearts, Global.HEART_MAX])
	else:
		lines.append("😴 %s slept 16 hours. Hearts already full (%d/%d ❤️)" % [names, Global.hearts, Global.HEART_MAX])
	if not Global.bought_today.is_empty():
		var labels: Array = []
		for d in Global.bought_today:
			labels.append(String(d["label"]))
		lines.append("📦 Arriving tomorrow: %s" % ", ".join(PackedStringArray(labels)))
	update_hearts()
	_open_day_overlay("🌙 DAY %d COMPLETE" % Global.day, GameUI.GOLD, "\n".join(PackedStringArray(lines)),
		"☀ WAKE UP — DAY %d" % (Global.day + 1),
		func(): Global.day += 1; day_setup())

# ============================================================
# a fresh morning
# ============================================================
func day_setup() -> void:
	computer.make_day_tasks()
	Global.play_clock = 0.0
	risk_t = 20.0
	computer.first_task_started = false
	Global.hearts_lost_today = 0
	computer.earned_today = 0
	Global.vet_today = false
	Global.bought_today.clear()
	quiet_done = false
	quiet_t = 90.0 + randf() * 120.0
	_p2 = false
	_p3 = false
	ringing = false
	away_time = 0.0
	ui.set_away_warn(false)
	furniture.bowl_full = false
	furniture.bowl_food.visible = false

	# overnight housekeeping: everything re-secured, barf mysteriously gone
	for h in furniture.hazards.values():
		if h["type"] == "toggle":
			h["armed"] = false
			h["everFixed"] = false
			furniture.apply_toggle_vis(h)
		elif h["type"] == "barf" and not bool(h.get("cleaned", false)):
			h["cleaned"] = true
			(h["mesh"] as Node3D).visible = false
	# …but the cats unpacked every cupboard: stashed items are back out
	var had_stashed := false
	for b in furniture.containers.values():
		if int(b["used"]) > 0:
			had_stashed = true
	for h in furniture.hazards.values():
		if h["type"] == "item" and not bool(h.get("daily", false)):
			h["stashed"] = false
			h["held"] = false
			var mesh: Node3D = h["mesh"]
			mesh.visible = true
			mesh.position = h["home"]
			h["curSurface"] = h.get("surface", null)
	for b in furniture.containers.values():
		b["used"] = 0
	if had_stashed:
		Global.msg("🙄 The cats unpacked everything you stashed. It's all back out.", "danger")
	# deal today's random traps — a fresh mix at fresh spots, on every floor
	var daily_pool: Array = []
	for h in furniture.hazards.values():
		if bool(h.get("daily", false)):
			h["stashed"] = true
			h["held"] = false
			(h["mesh"] as Node3D).visible = false
			h["curSurface"] = null
			daily_pool.append(h)
	var todays := _shuffled(daily_pool)
	var count: int = 3 + mini(Global.day - 1, 3)
	todays = todays.slice(0, count)
	var lvl_order := _shuffled(Global.LEVELS)
	for i in range(todays.size()):
		var h: Dictionary = todays[i]
		var lvl: float = lvl_order[i % lvl_order.size()]
		var pt := cats.nav.random_nav_point(lvl)
		(h["mesh"] as Node3D).position = Vector3(pt.x, lvl, pt.y)
		h["stashed"] = false
		(h["mesh"] as Node3D).visible = true
	if not todays.is_empty():
		Global.msg("🪤 New hazards are lying around the house somewhere. The cats already know.", "danger")
	# overnight deliveries
	for d in furniture.distracts.values():
		if bool(d["pending"]):
			d["pending"] = false
			d["owned"] = true
			(d["mesh"] as Node3D).visible = true
			Global.msg("📦 Delivered overnight: %s!" % d["label"], "good")
	for b in furniture.containers.values():
		if bool(b["pending"]):
			b["pending"] = false
			b["owned"] = true
			(b["mesh"] as Node3D).visible = true
			Global.msg("📦 Installed overnight: the %s!" % b["label"], "good")
	# overnight adoptions arrive hungry
	for a in Global.pending_adopts:
		var chaos: float = Global.CHAOS_LADDER[mini(cats.cats.size(), Global.CHAOS_LADDER.size() - 1)]
		cats.spawn_cat(String(a["name"]), a["color_def"], chaos)
		Global.msg("🐈 %s has arrived! (chaos level: %.1f×)" % [a["name"], chaos], "good")
	Global.pending_adopts.clear()
	# cats wake up fresh and LOUDLY hungry in the kitchen
	for c in cats.cats:
		c.distract_uses = {}
		c.distract_id = null
		c.full = 0.0
		c.morning_eat = false
		c.mode = "waitFood"
		c.waypoints = []
		c.idle_t = 0.0
		c.outside = false
		c.outside_haz = null
		c.surf = null
		c.after_hop = null
		c.go_after_hop = null
		c.perch = null
		c.g.position = Vector3(3.0 + randf() * 1.0, 0.0, -4.0 + randf() * 0.8)
		c.g.visible = true
	# you wake up in bed
	player.global_position = Vector3(-5.2, 3.9, -3.2)
	player.velocity = Vector3.ZERO
	player.yaw = -PI / 2.0
	player.pitch = 0.1
	player._apply_look()
	Global.day_stage = "morning"
	computer.cur_task_i = -1
	computer.comp = "tasks"
	update_econ()
	update_hearts()
	computer._redraw()
	set_objective("😾 %s is meowing in the KITCHEN — go downstairs and fill the food bowl!" % cats.cat_names_joined())
	Global.msg("☀ Day %d. The meowing started at 6am sharp." % Global.day)
	save_game()
	# the shelter calls when a new cat becomes available (adoption is free)
	var idx := Global.next_cat_idx(cats.cats.size())
	if Global.cat_available(cats.cats.size()) and not Global.adopt_announced.has(idx):
		Global.adopt_announced[idx] = true
		show_confirm("🐈 The shelter called!",
			"Oh how cute — a new cat is available for adoption. Are you going to rescue it? (It's free. The chaos is also free.)",
			"🐈 RESCUE IT", "MAYBE LATER",
			func(): open_adopt(), Callable())

# ============================================================
# the cats fed you (bowl filled in the morning) → work unlocks
# ============================================================
func on_fed() -> void:
	if Global.day_stage == "morning":
		Global.day_stage = "work"
		set_objective("💻 Cats fed! Get to the OFFICE computer and pick a task.")
		Global.msg("Breakfast is served. Blessed silence incoming.", "good")

# ============================================================
# emergency vet (cats.vet_visit does the reset, then calls this)
# ============================================================
func on_vet(c: Cat, bill: int) -> void:
	ringing = false
	away_time = 0.0
	ui.set_away_warn(false)
	if Global.in_computer:
		computer.exit()
	computer.cur_task_i = -1
	computer.comp = "shop"
	update_econ()
	update_hearts()
	var text := "%s was down to its LAST heart. You dropped everything, grabbed the carrier, and RAN.\n\n" % c.cat_name
	text += "The vet fixed everything. The bill came to [b]$%d[/b] — mysteriously, the exact amount of money you had.\n\n" % bill
	text += "%s is back to %d/%d hearts and back to plotting. The work day is a write-off. Go home and sleep." % [c.cat_name, Global.HEART_MAX, Global.HEART_MAX]
	_open_day_overlay("🏥 VET EMERGENCY", GameUI.RED, text, "🐈 TAKE KITTY HOME",
		func(): set_objective("🛏 Exhausted. Go UPSTAIRS and click your BED to sleep."))

# ============================================================
# boss desk phone
# ============================================================
func answer_phone() -> void:
	if ringing:
		ringing = false
		ring_t = 0.0
		away_time = 0.0
		ui.set_away_warn(false)
		boss_say(BOSS_LINES[randi() % BOSS_LINES.size()])
	else:
		Global.msg("The phone is quiet. Ominously quiet.")

func _away_limit() -> float:
	return 55.0 if Global.phase <= 1 else (45.0 if Global.phase == 2 else 35.0)

func end_game() -> void:
	if Global.game_over:
		return
	Global.game_over = true
	ui.set_comp_exit(false)
	ui.update_lock_hint(false)
	var first := cats.cats[0].cat_name if not cats.cats.is_empty() else "the cat"
	var text := "You didn't answer the boss's call. HR has been looped in. You survived %d day%s and saved $%d. %s, at least, looks pleased — you can play with cats full-time now." % [Global.day, ("s" if Global.day > 1 else ""), Global.money, first]
	ui.show_end("📞 YOU'RE FIRED", text)
	_set_freeze("end", true)

# ============================================================
# adoption
# ============================================================
func open_adopt() -> void:
	if not Global.cat_available(cats.cats.size()):
		Global.msg("The shelter has no cats available right now. Check back in a few days.")
		return
	var used := {}
	for c in cats.cats:
		used[c.cat_name.to_lower()] = true
	for a in Global.pending_adopts:
		used[String(a["name"]).to_lower()] = true
	var avail: Array = []
	for n in Global.NAME_POOL:
		if not used.has(String(n).to_lower()):
			avail.append(n)
	var default_name: String = avail[randi() % avail.size()] if not avail.is_empty() else "Trouble"
	ui.open_adopt(default_name, avail.slice(0, 6))
	_set_freeze("adopt", true)

func confirm_adopt(name_: String, color_def: Dictionary) -> void:
	if not Global.cat_available(cats.cats.size()):
		cancel_adopt()
		return
	var nm := name_.strip_edges()
	if nm == "":
		nm = "Trouble"
	nm = nm.substr(0, 14)
	Global.pending_adopts.append({"name": nm, "color_def": color_def})
	Global.msg("🐈 Adoption approved! %s arrives tomorrow morning." % nm, "good")
	audio.beep(900, 0.12, 0.1, "triangle")
	update_econ()
	cancel_adopt()

func cancel_adopt() -> void:
	ui.close_adopt()
	_set_freeze("adopt", false)
	computer._redraw()

# ============================================================
# generic confirm + day overlay (freeze the sim while open)
# ============================================================
func show_confirm(title: String, text: String, yes: String, no: String, on_yes: Callable, on_no: Callable) -> void:
	_set_freeze("confirm", true)
	var wrapped_yes := func(): _set_freeze("confirm", false); if on_yes.is_valid(): on_yes.call()
	var wrapped_no := func(): _set_freeze("confirm", false); if on_no.is_valid(): on_no.call()
	ui.show_confirm(title, text, yes, no, wrapped_yes, wrapped_no)

func _open_day_overlay(title: String, color: Color, text: String, btn: String, on_ok: Callable) -> void:
	_set_freeze("day", true)
	ui.show_day_overlay(title, color, text, btn, on_ok)

## GameUI calls this from the day-overlay / confirm button handlers.
func set_overlay_open(open: bool) -> void:
	if not open:
		_set_freeze("day", false)

# ============================================================
# HUD proxies (so Cats / Computer can talk to the HUD via `game`)
# ============================================================
func update_hearts() -> void:
	ui.update_hearts()

func update_econ() -> void:
	var done_n := 0
	var req_n := 0
	var bob_open := false
	for t in computer.day_tasks:
		if bool(t["bob"]):
			if not bool(t["done"]):
				bob_open = true
		else:
			req_n += 1
			if bool(t["done"]):
				done_n += 1
	ui.update_econ(done_n, req_n, bob_open)

func flash_hearts() -> void:
	ui.flash_hearts()

func set_objective(text: String) -> void:
	ui.set_objective(text)

func boss_say(text: String) -> void:
	ui.boss_say(text)
	audio.beep(520, 0.12, 0.12, "triangle")

# ============================================================
# input: pause + click-to-recapture
# ============================================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		return
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if Global.started and not Global.game_over and not get_tree().paused and not Global.in_computer \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle_pause() -> void:
	if not Global.started or Global.game_over:
		return
	# can't pause while another modal is up (matches the web dayOverlay guard)
	var other := false
	for r in _freeze:
		if r != "pause":
			other = true
	if other and not _paused:
		return
	_paused = not _paused
	ui.set_pause(_paused)
	_set_freeze("pause", _paused)

# ============================================================
# per-frame pacing (the tick() body, minus movement/camera/cats)
# ============================================================
func _process(dt: float) -> void:
	if not Global.started or Global.game_over or get_tree().paused:
		_was_in_computer = Global.in_computer
		return
	dt = minf(0.05, dt)

	# clocks & phases (later days start meaner)
	Global.phase = 0 if not Global.tutorial_done else (
		(1 if Global.play_clock < 160 else (2 if Global.play_clock < 460 else 3)) if Global.day == 1 else (
		(2 if Global.play_clock < 300 else 3) if Global.day == 2 else 3))
	if Global.phase == 2 and not _p2:
		_p2 = true
		Global.msg("😼 The cats are getting bolder. Watch the stairs.", "danger")
	if Global.phase == 3 and not _p3:
		_p3 = true
		Global.msg("🔥 Full chaos hours. Everything is a hazard now.", "danger")

	# HUD crosshair / lock hint
	ui.set_crosshair(not Global.in_computer)
	ui.update_lock_hint(_should_show_lock_hint())

	# sitting down resets the away timer (but not a ringing phone)
	if Global.in_computer and not _was_in_computer:
		away_time = 0.0
	_was_in_computer = Global.in_computer

	# away / boss (only while on the clock)
	if Global.day_stage == "work" and computer.first_task_started and not Global.in_computer:
		away_time += dt
		if not ringing and away_time > _away_limit():
			ringing = true
			ring_t = 0.0
			ui.set_away_warn(true)
			boss_say("📞 Your status went AWAY. The boss is calling your desk phone!")
	if ringing:
		ring_t += dt
		ring_beep_t -= dt
		if ring_beep_t <= 0.0:
			var d := 6.0
			if furniture.phone != null:
				d = player.camera.global_position.distance_to(furniture.phone.global_position)
			audio.beep(1150, 0.25, minf(0.3, 1.6 / (1.0 + d * 0.35)))
			ring_beep_t = 0.7
		if ring_t > Global.RING_LIMIT:
			end_game()
			return

	# "…it's too quiet" (from day 2 on, once per day)
	if Global.day_stage == "work" and computer.first_task_started and Global.day >= 2 and not quiet_done:
		quiet_t -= dt
		if quiet_t <= 0.0:
			if cats.trigger_quiet():
				quiet_done = true
			else:
				quiet_t = 20.0

	# paced hazard arming
	if Global.day_stage == "work" and computer.first_task_started:
		risk_t -= dt
		if risk_t <= 0.0:
			_arm_a_hazard()

	# meow loop (louder when closer)
	meow_loop_t -= dt
	if meow_loop_t <= 0.0:
		meow_loop_t = 2.1
		for c in cats.cats:
			if c.mode == "danger" or c.mode == "outside" or c.mode == "waitFood":
				audio.meow_at(c.g.position, 2.2, 1.15 if c.mode == "waitFood" else 1.0)

	# the seated monitor refreshes live (call countdown, cat-on-keyboard, etc.)
	if Global.in_computer:
		computer._redraw()

func _arm_a_hazard() -> void:
	var n: int = cats.cats.size()
	var window: Array = Global.risk_window(n)
	risk_t = window[0] + randf() * (window[1] - window[0]) - (Global.phase - 1) * 4.0
	var cap: int = (2 if Global.phase == 1 else (4 if Global.phase == 2 else 8)) + (n - 1)
	var toggles: Array = []
	var armed_count := 0
	var cands: Array = []
	for h in furniture.hazards.values():
		if h["type"] != "toggle":
			continue
		toggles.append(h)
		if bool(h["armed"]):
			armed_count += 1
		elif int(h.get("tier", 99)) <= Global.phase and (bool(h.get("rearm", false)) or not bool(h["everFixed"])):
			cands.append(h)
	if armed_count < cap and not cands.is_empty():
		var h: Dictionary = cands[randi() % cands.size()]
		h["armed"] = true
		furniture.apply_toggle_vis(h)
		var arm_msg: String = h.get("armMsg", "The %s is a hazard again!" % h.get("name", "thing"))
		Global.msg("⚠ " + arm_msg, "danger")
		var mp: Vector3 = (h["mesh"] as Node3D).position
		Global.msg("(coming from %s)" % Global.room_name(mp.x, mp.y, mp.z))

func _should_show_lock_hint() -> bool:
	return Global.started and not Global.game_over and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
		and not Global.in_computer and not get_tree().paused and _freeze.is_empty()

# ============================================================
# freeze helpers (any reason freezes the 3D sim + frees the mouse)
# ============================================================
func _set_freeze(reason: String, on: bool) -> void:
	if on:
		_freeze[reason] = true
	else:
		_freeze.erase(reason)
	var frozen := not _freeze.is_empty()
	get_tree().paused = frozen
	if frozen:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif Global.started and not Global.game_over:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unfreeze_all() -> void:
	_freeze.clear()
	_paused = false
	get_tree().paused = false
	if Global.started and not Global.game_over:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _after(secs: float, cb: Callable) -> void:
	var t := get_tree().create_timer(secs)
	t.timeout.connect(cb)

func _shuffled(a: Array) -> Array:
	var r := a.duplicate()
	for i in range(r.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = r[i]
		r[i] = r[j]
		r[j] = tmp
	return r

# ============================================================
# save / load  (the web build had none)
# ============================================================
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var roster: Array = []
	for c in cats.cats:
		roster.append({"name": c.cat_name, "color": c.color_key, "chaos": c.chaos})
	var owned_d: Array = []
	var pend_d: Array = []
	for d in furniture.distracts.values():
		if bool(d["owned"]):
			owned_d.append(d["id"])
		if bool(d["pending"]):
			pend_d.append(d["id"])
	var owned_c: Array = []
	var pend_c: Array = []
	for b in furniture.containers.values():
		if bool(b["owned"]) and int(b["price"]) > 0:
			owned_c.append(b["id"])
		if bool(b["pending"]):
			pend_c.append(b["id"])
	var adopts: Array = []
	for a in Global.pending_adopts:
		adopts.append({"name": a["name"], "color": String(a["color_def"]["key"])})
	var data := {
		"day": Global.day, "money": Global.money, "hearts": Global.hearts,
		"cats": roster,
		"owned_distracts": owned_d, "pending_distracts": pend_d,
		"owned_containers": owned_c, "pending_containers": pend_c,
		"pending_adopts": adopts,
		"adopt_announced": Global.adopt_announced.keys(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	Global.day = int(data.get("day", 1))
	Global.money = int(data.get("money", 0))
	Global.hearts = int(data.get("hearts", Global.HEART_MAX))
	# rebuild the cat roster
	for c in cats.cats:
		c.g.queue_free()
	cats.cats.clear()
	for entry in data.get("cats", []):
		cats.spawn_cat(String(entry["name"]), Global.color_by_key(String(entry["color"])), float(entry["chaos"]))
	# shop ownership / pending deliveries
	var owned_d: Array = data.get("owned_distracts", [])
	var pend_d: Array = data.get("pending_distracts", [])
	for d in furniture.distracts.values():
		var was_shop := int(d["price"]) > 0
		if was_shop:
			d["owned"] = d["id"] in owned_d
			d["pending"] = d["id"] in pend_d
			(d["mesh"] as Node3D).visible = bool(d["owned"]) and not bool(d["pending"])
	var owned_c: Array = data.get("owned_containers", [])
	var pend_c: Array = data.get("pending_containers", [])
	for b in furniture.containers.values():
		if int(b["price"]) > 0:
			b["owned"] = b["id"] in owned_c
			b["pending"] = b["id"] in pend_c
			(b["mesh"] as Node3D).visible = bool(b["owned"]) and not bool(b["pending"])
	Global.pending_adopts.clear()
	for a in data.get("pending_adopts", []):
		Global.pending_adopts.append({"name": String(a["name"]), "color_def": Global.color_by_key(String(a["color"]))})
	Global.adopt_announced.clear()
	for k in data.get("adopt_announced", []):
		Global.adopt_announced[int(k)] = true
	return true
