## The office computer: sitting at the monitor, the day's task list, and the five
## work minigames. Faithful port of the COMPUTER / TYPING MINIGAME section of
## game.js (~1961-2339, 2508-2564).
##
## The web build drew the monitor with a 2D canvas painted onto a three.js
## texture; here a SubViewport holds a MonitorCanvas Control and its texture is
## mapped onto the screen quad — the Godot equivalent of that canvas texture.
##
## Live now: the task list, all five games (report / calendar / mail / sheet /
## call) + Bob reskins, per-task progress saving, Backspace/X navigation, and
## payouts. The camera glides to the monitor while working.
##
## Stubbed for Phase 5 (same pattern as earlier phases): the shop screen, the
## boss away-phone, the full morning→work→evening→sleep day loop (completeTask
## here just pays out and returns to the task list — finishWorkDay / evening /
## shop transitions land with the day loop), audio (beeps), and the HUD.
class_name Computer
extends Node3D

# ---- wired by Main ----
var furniture: Furniture
var player                      # Player (Node3D; untyped so headless tests can pass a stub)
var camera: Camera3D
var cats                        # Cats manager (for the cat-on-keyboard block)
var interactor                  # Interactor (to check the hands-full-of-cat gate)
var game                        # Game orchestrator (day loop / shop routing / adopt)
var ui: GameUI                  # HUD (econ + work-progress + objective)
var audio: GameAudio            # synthesized beeps

# ---- monitor render surface ----
const SCREEN_W := 512
const SCREEN_H := 320
const MONITOR_POS := Vector3(-6.9, 1.5, -3.35)
var vp: SubViewport
var canvas: MonitorCanvas

# ---- camera glide (compBlend in the web build) ----
var comp_blend := 0.0
var _monitor_xf: Transform3D

# ---- task / screen state ----
var day_tasks: Array = []       # [{key,label,pay,done,bob,st}]
var cur_task_i := -1            # task currently on screen (-1 = none)
var comp := "tasks"            # what the monitor shows: tasks | game | shop
var first_task_started := false
var earned_today := 0
var screen_blocked := false     # a cat is on the keyboard right now

# ---- shop ----
var shop_scroll := 0
var _thumbs := {}               # catalog id -> Texture2D (rendered 3D product shots)
var _thumbs_made := false
var _thumb_vps: Array = []      # keep the SubViewports alive so the textures persist

# ============================================================
# minigame content tables (verbatim from game.js)
# ============================================================
# no letter 'x' in any syllable — X is the "step away from the computer" key
const SYL := ["syn", "erg", "lev", "blorp", "quar", "flim", "den", "corp", "zam", "plu", "gran", "yeet", "stak", "vio", "merg", "holt", "bram", "chur", "kip", "wonk", "fiz", "dram", "lum", "pon", "trab"]
const MEET_POOL := ["Standup", "Budget Sync", "1:1 w/ Boss", "Sprint Review", "All Hands", "Retro", "Vibes Check", "Q3 Kickoff"]
const DAYS_W := ["MON", "TUE", "WED", "THU", "FRI"]
const MAIL_REAL := [
	["boss@corp.biz", "Re: re: re: those numbers"],
	["hr@corp.biz", "Mandatory Fun Day logistics"],
	["bob@corp.biz", "quick favor?? pls"],
	["it@corp.biz", "Your password expires TODAY"],
	["ceo@corp.biz", "Thoughts on our synergy journey"],
	["facilities@corp.biz", "Fridge cleanout Friday"],
]
const MAIL_SPAM := [
	["prince@definitely.real", "URGENT inheritance 4 U"],
	["pills@meds4.less", "FREE PILLS no vet needed"],
	["winner@lotto.wow", "You WON $10,000,000!!!"],
	["hotsingles@ur.area", "CATS in your area want to meet"],
	["crypto@moon.gg", "CatCoin going 1000x. trust me"],
]
const CALL_WORDS := ["SYNERGY", "PIVOT", "DEADLINE", "BUDGET", "ALIGNMENT", "ROADMAP", "STAKEHOLDER", "DELIVERABLE", "BANDWIDTH", "LEVERAGE"]
const SHEET_ITEMS := ["CAT FOOD", "VET FUND", "TREATS", "RENT", "COFFEE", "LASER PENS", "CAT TOYS", "CATNIP", "LINT ROLLERS", "SCRATCH POST"]
const SHEET_COLS := "BCEFGH"
const GAME_KEYS := ["report", "calendar", "mail", "sheet", "call"]
const GAME_LABEL := {
	"report": "Write the report",
	"calendar": "Organize the calendar",
	"mail": "Clear the inbox",
	"sheet": "Fill in the spreadsheet",
	"call": "Call with the boss",
}
const GAME_HINT := {
	"report": "type the letters",
	"calendar": "press the number shown under the right day",
	"mail": "R = reply · D = delete spam",
	"sheet": "WASD scroll · type the highlighted cell: letter, then number",
	"call": "memorize, then press the numbers IN ORDER · A = ask again",
}

# ============================================================
# setup
# ============================================================
func _ready() -> void:
	# camera close-up pose: eye at compCamPos looking at the monitor
	var eye := Vector3(-6.9, 1.5, -2.62)
	_monitor_xf = Transform3D(Basis.looking_at(MONITOR_POS - eye, Vector3.UP), eye)

	# monospace font for the CORP-OS look; falls back to the engine default headless
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "Menlo", "Courier New", "DejaVu Sans Mono"])

	vp = SubViewport.new()
	vp.size = Vector2i(SCREEN_W, SCREEN_H)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	canvas = MonitorCanvas.new()
	canvas.computer = self
	canvas.font = f
	canvas.size = Vector2(SCREEN_W, SCREEN_H)
	vp.add_child(canvas)

	if furniture != null and furniture.monitor != null:
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.0, 0.62)
		quad.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = vp.get_texture()
		quad.material_override = mat
		quad.position = Vector3(0, 0.6, 0.061)
		furniture.monitor.add_child(quad)

# ============================================================
# per-frame: camera glide to / from the monitor
# ============================================================
func _process(delta: float) -> void:
	var target := 1.0 if Global.in_computer else 0.0
	comp_blend += (target - comp_blend) * minf(1.0, delta * 5.0)
	if absf(comp_blend - target) < 0.002:
		comp_blend = target
	if comp_blend <= 0.0001:
		# player fully owns the camera again — restore its rest local transform
		camera.transform = Transform3D.IDENTITY
		return
	var t01 := comp_blend * comp_blend * (3.0 - 2.0 * comp_blend)  # smoothstep
	var fp: Transform3D = player.head.global_transform
	camera.global_transform = fp.interpolate_with(_monitor_xf, t01)

# ============================================================
# input while seated (consumes keys so movement / pause don't leak through)
# ============================================================
func _input(event: InputEvent) -> void:
	if not Global.in_computer:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_typing(event)
		get_viewport().set_input_as_handled()

# ============================================================
# enter / exit
# ============================================================
func enter() -> void:
	if Global.in_computer:
		return
	if not Global.tutorial_done:
		return
	if interactor != null and interactor.held != null and interactor.held is Cat:
		Global.msg("You can't type while holding a cat. (It would love that though.)")
		return
	if camera.global_position.distance_to(MONITOR_POS) > 3.2:
		return
	if day_tasks.is_empty():
		make_day_tasks()
	Global.in_computer = true
	if ui != null:
		ui.set_comp_exit(true)
	if cur_task_i >= 0 and not bool(day_tasks[cur_task_i]["done"]):
		comp = "game"           # resume mid-task
	elif Global.day_stage == "evening" and not _bob_open():
		comp = "shop"
	else:
		comp = "tasks"
	if Global.day_stage == "work" and not first_task_started and game != null:
		game.set_objective("")
	_redraw()

func exit() -> void:
	Global.in_computer = false
	if ui != null:
		ui.set_comp_exit(false)
	_redraw()

## Is there an unfinished optional Bob task? (gates the evening shop routing)
func _bob_open() -> bool:
	for t in day_tasks:
		if bool(t["bob"]) and not bool(t["done"]):
			return true
	return false

# ============================================================
# the day's task list
# ============================================================
func make_day_tasks() -> void:
	# duplicates are allowed — some days it's just reports, reports, reports
	var n := 3 if Global.day <= 2 else 4
	day_tasks = []
	for i in range(n):
		var k: String = _pick(GAME_KEYS)
		day_tasks.append({"key": k, "label": String(GAME_LABEL[k]), "pay": Global.TASK_PAY, "done": false, "bob": false, "st": null})
	if Global.day >= 2 and randf() < 0.45:
		var k: String = _pick(GAME_KEYS)
		var lbl := "Bob's \"%s\" (cover for him)" % String(GAME_LABEL[k]).to_lower()
		day_tasks.append({"key": k, "label": lbl, "pay": Global.BOB_PAY, "done": false, "bob": true, "st": null})
	cur_task_i = -1

func complete_task() -> void:
	var t: Dictionary = day_tasks[cur_task_i]
	t["done"] = true
	Global.money += int(t["pay"])
	earned_today += int(t["pay"])
	Global.msg("✅ %s — done! +$%d" % [t["label"], int(t["pay"])], "good")
	if bool(t["bob"]) and game != null:
		game.boss_say("📎 Bob: \"omg thank u!! i owe you. again. still.\"")
	if audio != null:
		audio.beep(1250, 0.2, 0.1, "sine")
	cur_task_i = -1
	comp = "shop" if (Global.day_stage == "evening" and _all_done()) else "tasks"
	if Global.day_stage == "work" and _all_required_done() and game != null:
		game.finish_work_day()
	if game != null:
		game.update_econ()
	_redraw()

func _all_done() -> bool:
	for t in day_tasks:
		if not bool(t["done"]):
			return false
	return true

func _all_required_done() -> bool:
	for t in day_tasks:
		if not bool(t["bob"]) and not bool(t["done"]):
			return false
	return true

# ============================================================
# keyboard handling while seated (port of handleTyping)
# ============================================================
func _handle_typing(e: InputEventKey) -> void:
	var k := _key_str(e)
	if k == "Escape" or k.to_lower() == "x":
		exit()
		return
	if comp == "game":
		if k == "Backspace":
			cur_task_i = -1
			comp = "tasks"
			_redraw()
			return  # progress is saved on the task
		if _cat_blocking():
			return
		var t: Dictionary = day_tasks[cur_task_i]
		var st: Dictionary = t["st"]
		_game_key(String(t["key"]), st, k)
		if int(st["done"]) >= int(st["total"]):
			complete_task()
			return
		_redraw()
	elif comp == "tasks":
		if k.to_lower() == "b" and Global.day_stage == "evening":
			comp = "shop"
			_redraw()
			return
		if not k.is_valid_int():
			return
		var n := int(k)
		if n >= 1 and n <= day_tasks.size():
			var t: Dictionary = day_tasks[n - 1]
			if bool(t["done"]):
				Global.msg("That one is already done. Nice.")
				return
			if Global.day_stage == "morning":
				Global.msg("Feed the cat first! You can't think through this meowing.", "danger")
				return
			cur_task_i = n - 1
			if t["st"] == null:
				var st := {}
				_game_start(String(t["key"]), st)
				t["st"] = st
			comp = "game"
			if not first_task_started:
				first_task_started = true
				Global.msg("You're on the clock now. Don't go idle too long...")
			_redraw()
	elif comp == "shop":
		var lk := k.to_lower()
		if lk == "t":
			comp = "tasks"
			_redraw()
			return
		if lk == "s":
			shop_scroll += 1
			_redraw()
			return
		if lk == "w":
			shop_scroll = maxi(0, shop_scroll - 1)
			_redraw()
			return
		if k.is_valid_int():
			var n := int(k)
			if n >= 1:
				buy_item(n - 1)

## Is a cat physically on the keyboard right now? (blocks typing until dealt with)
func _cat_blocking() -> bool:
	if cats == null or player == null:
		return false
	for c in cats.cats:
		if c.mode != "pester" and c.mode != "held":
			continue
		var pp: Vector3 = player.global_position
		var d := Vector2(c.g.position.x - pp.x, c.g.position.z - pp.z).length()
		if d < 2.2 and absf(c.g.position.y - pp.y) < 1.8:
			return true
	return false

# ============================================================
# the five games — start(st) / key(st) / draw(st, cv). progress = done/total.
# ============================================================
func _game_start(key: String, st: Dictionary) -> void:
	match key:
		"report":
			st["total"] = 20; st["done"] = 0; st["word"] = _gibberish(); st["idx"] = 0; st["wrong"] = false
		"calendar":
			st["total"] = 12; st["done"] = 0; _calendar_next(st)
		"mail":
			st["total"] = 14; st["done"] = 0; _mail_next(st)
		"sheet":
			st["total"] = 8; st["done"] = 0; st["cells"] = {}; st["px"] = 0; st["py"] = 0; _sheet_next(st)
		"call":
			st["total"] = 4; st["done"] = 0; _call_next(st)

func _calendar_next(st: Dictionary) -> void:
	# days stay MON..FRI, but the key numbers under them shuffle every meeting
	st["meeting"] = _pick(MEET_POOL)
	st["day"] = randi() % 5
	st["keys"] = _shuffled([1, 2, 3, 4, 5])
	st["wrong"] = -1

func _mail_next(st: Dictionary) -> void:
	st["spam"] = randf() < 0.5
	st["mail"] = _pick(MAIL_SPAM if bool(st["spam"]) else MAIL_REAL)
	st["wrong"] = false

func _sheet_next(st: Dictionary) -> void:
	var cells: Dictionary = st["cells"]
	var free: Array = []
	for col_i in range(SHEET_COLS.length()):
		var col := SHEET_COLS[col_i]
		for r in range(1, 7):
			if not cells.has(col + str(r)):
				free.append(col + str(r))
	st["target"] = _pick(free)
	st["entry"] = {"label": _pick(SHEET_ITEMS), "val": "$" + str(5 + randi() % 95)}
	st["stage"] = 0  # 0 = waiting for the column letter, 1 = waiting for the row number
	st["wrong"] = false

func _call_next(st: Dictionary) -> void:
	var pool: Array = _shuffled(CALL_WORDS)
	st["words"] = pool.slice(0, 3)
	st["opts"] = _shuffled(pool.slice(0, 6))
	st["picked"] = 0
	st["show_until"] = Time.get_ticks_msec() + 4200

func _game_key(key: String, st: Dictionary, k: String) -> void:
	match key:
		"report":
			if k.length() != 1:
				return
			var word := String(st["word"])
			if k.to_lower() == word[int(st["idx"])]:
				st["idx"] = int(st["idx"]) + 1
				st["wrong"] = false
				if int(st["idx"]) >= word.length():
					st["done"] = int(st["done"]) + 1
					st["idx"] = 0
					st["word"] = _gibberish()
			else:
				st["wrong"] = true
		"calendar":
			if not k.is_valid_int():
				return
			var n := int(k)
			if n < 1 or n > 5:
				return
			var keys: Array = st["keys"]
			var i := keys.find(n)
			if i == int(st["day"]):
				st["done"] = int(st["done"]) + 1
				_calendar_next(st)
			else:
				st["wrong"] = i
		"mail":
			var lk := k.to_lower()
			if lk != "r" and lk != "d":
				return
			var right := "d" if bool(st["spam"]) else "r"
			if lk == right:
				st["done"] = int(st["done"]) + 1
				_mail_next(st)
			else:
				st["wrong"] = true
		"sheet":
			_sheet_key(st, k)
		"call":
			_call_key(st, k)

func _sheet_key(st: Dictionary, k: String) -> void:
	if k.length() != 1:
		return
	var lk := k.to_lower()
	# WASD scroll the 3x3 window — never a cell guess (cols BCEFGH skip A/D, rows are digits)
	if lk == "a":
		st["px"] = 0; return
	if lk == "d":
		st["px"] = 1; return
	if lk == "w":
		st["py"] = 0; return
	if lk == "s":
		st["py"] = 1; return
	var K := k.to_upper()
	var target := String(st["target"])
	if int(st["stage"]) == 0:
		if not SHEET_COLS.contains(K):
			return
		if K == target[0]:
			st["stage"] = 1
			st["wrong"] = false
		else:
			st["wrong"] = true
	else:
		if not "123456".contains(K):
			return
		if K == target[1]:
			var cells: Dictionary = st["cells"]
			cells[target] = st["entry"]
			st["done"] = int(st["done"]) + 1
			if int(st["done"]) < int(st["total"]):
				_sheet_next(st)
		else:
			st["wrong"] = true
			st["stage"] = 0

func _call_key(st: Dictionary, k: String) -> void:
	if Time.get_ticks_msec() < int(st["show_until"]):
		return
	if k.to_lower() == "a":
		# "sorry, could you repeat that?" — boss re-lists, you start over
		st["show_until"] = Time.get_ticks_msec() + 4200
		st["picked"] = 0
		return
	if not k.is_valid_int():
		return
	var n := int(k)
	if n < 1 or n > 6:
		return
	var opts: Array = st["opts"]
	var words: Array = st["words"]
	if opts[n - 1] == words[int(st["picked"])]:
		st["picked"] = int(st["picked"]) + 1
		if int(st["picked"]) >= 3:
			st["done"] = int(st["done"]) + 1
			_call_next(st)
	else:
		st["picked"] = 0

# ============================================================
# drawing the monitor (port of drawScreen + each game's draw)
# ============================================================
func draw_screen(cv: MonitorCanvas) -> void:
	screen_blocked = _cat_blocking()
	var W := SCREEN_W
	cv.rect(0, 0, W, SCREEN_H, _col("#081426"))
	cv.rect(0, 0, W, 28, _col("#12233f"))
	cv.text(8, 18, "CORP-OS 95 · day %d · $%d" % [Global.day, Global.money], _col("#8ab4e8"), 13, "left")

	var done_n := 0
	var req_n := 0
	for t in day_tasks:
		if not bool(t["bob"]):
			req_n += 1
			if bool(t["done"]):
				done_n += 1

	if not Global.in_computer:
		var evening := Global.day_stage == "evening"
		var s1 := "off the clock 😌" if evening else ("tasks done: %d/%s" % [done_n, str(req_n) if req_n > 0 else "?"])
		cv.text(W / 2.0, 135, s1, _col("#4a6a9a"), 19, "center")
		cv.text(W / 2.0, 175, "Click the monitor to SHOP" if evening else "Click the monitor to work", _col("#ffd9a0"), 19, "center")
	elif comp == "game" and screen_blocked:
		cv.rect(0, 90, W, 130, _col("#3a1520"))
		cv.text(W / 2.0, 150, "🐈 A CAT IS ON THE KEYBOARD", _col("#ff8a8a"), 26, "center")
		cv.text(W / 2.0, 185, "Deal with it. (X to step away, then pick it up or distract it)", _col("#ffd0d0"), 16, "center")
	elif comp == "game":
		var t: Dictionary = day_tasks[cur_task_i]
		var st: Dictionary = t["st"]
		var gkey := String(t["key"])
		cv.text(W / 2.0, 50, ("📎 " if bool(t["bob"]) else "") + String(t["label"]).to_upper(), _col("#ffd9a0"), 15, "center")
		_game_draw(gkey, st, cv)
		cv.rect(66, 252, 380, 13, _col("#1a2f52"))
		cv.rect(66, 252, 380.0 * (float(st["done"]) / float(st["total"])), 13, _col("#6fd66f"))
		cv.text(W / 2.0, 285, "%d / %d" % [int(st["done"]), int(st["total"])], _col("#8ab4e8"), 14, "center")
		cv.text(W / 2.0, 306, String(GAME_HINT[gkey]) + " — Bksp task list — X step away", _col("#555566"), 12, "center")
	elif comp == "tasks":
		cv.text(W / 2.0, 55, "📋 TODAY'S TASKS — DAY %d" % Global.day, _col("#ffd9a0"), 17, "center")
		for i in range(day_tasks.size()):
			var t: Dictionary = day_tasks[i]
			var y := 90 + i * 34
			cv.rect(46, y - 20, W - 92, 28, _col("#12331a") if bool(t["done"]) else _col("#16305a"))
			cv.text(58, y, str(i + 1), _col("#ffe9a8"), 15, "left")
			var lbl := ("✔ " if bool(t["done"]) else "") + "%s  ($%d)" % [t["label"], int(t["pay"])]
			cv.text(82, y, lbl, _col("#6fd66f") if bool(t["done"]) else _col("#cfe8ff"), 15, "left")
		var y0 := 100 + day_tasks.size() * 34
		if Global.day_stage == "morning":
			cv.text(W / 2.0, y0, "⚠ feed the cat first — the meowing is unbearable", _col("#ff8a8a"), 14, "center")
		elif Global.day_stage == "evening":
			if done_n >= req_n:
				cv.text(W / 2.0, y0, "all required tasks done! press B for the SHOP", _col("#9df09d"), 14, "center")
		else:
			cv.text(W / 2.0, y0, "press a number to start a task", _col("#9df09d"), 14, "center")
	elif comp == "shop":
		_draw_shop(cv)

	# HUD work-progress mirror (workFill / workPct in the web build)
	if ui != null:
		var p := 0.0
		if cur_task_i >= 0 and day_tasks[cur_task_i]["st"] != null:
			var cst: Dictionary = day_tasks[cur_task_i]["st"]
			p = float(cst["done"]) / float(cst["total"])
		ui.set_work_progress(p)

func _game_draw(key: String, st: Dictionary, cv: MonitorCanvas) -> void:
	var W := SCREEN_W
	match key:
		"report":
			var size := 40
			var word := String(st["word"])
			var idx := int(st["idx"])
			var done_s := word.substr(0, idx)
			var rest_s := word.substr(idx)
			var x := (W - cv.measure(word, size)) / 2.0
			cv.text(x, 150, done_s, _col("#6fd66f"), size, "left")
			x += cv.measure(done_s, size)
			var wrong := bool(st["wrong"])
			cv.text(x, 150, rest_s, _col("#ff6b6b") if wrong else _col("#cfe8ff"), size, "left")
			if wrong:
				cv.rect(x, 158, cv.measure(rest_s, size), 3, _col("#ff6b6b"))
		"calendar":
			var day_i := int(st["day"])
			var wrong := int(st["wrong"])
			var keys: Array = st["keys"]
			cv.text(W / 2.0, 90, "Move the meeting to the right day:", _col("#cfe8ff"), 17, "center")
			cv.text(W / 2.0, 125, "\"%s\"  →  %s" % [st["meeting"], DAYS_W[day_i]], _col("#ffd9a0"), 20, "center")
			for i in range(5):
				var x := 36 + i * 90
				cv.rect(x, 160, 78, 60, _col("#5a2030") if i == wrong else _col("#16305a"))
				cv.text(x + 39, 185, DAYS_W[i], _col("#8ab4e8"), 14, "center")
				cv.text(x + 39, 210, str(keys[i]), _col("#ffe9a8"), 18, "center")
		"mail":
			var mail: Array = st["mail"]
			var wrong := bool(st["wrong"])
			cv.rect(46, 70, W - 92, 110, _col("#16305a"))
			cv.text(62, 100, "FROM: " + String(mail[0]), _col("#8ab4e8"), 14, "left")
			cv.text(62, 130, "SUBJ: " + String(mail[1]), _col("#cfe8ff"), 17, "left")
			var line := "Nope! Look closer at the sender..." if wrong else "[R] reply politely     [D] delete (spam)"
			cv.text(W / 2.0, 165, line, _col("#ff8a8a") if wrong else _col("#9df09d"), 15, "center")
		"sheet":
			_draw_sheet(st, cv)
		"call":
			_draw_call(st, cv)

func _draw_sheet(st: Dictionary, cv: MonitorCanvas) -> void:
	var W := SCREEN_W
	var target := String(st["target"])
	var entry: Dictionary = st["entry"]
	var wrong := bool(st["wrong"])
	var stage := int(st["stage"])
	var px := int(st["px"])
	var py := int(st["py"])
	var cells: Dictionary = st["cells"]
	cv.text(W / 2.0, 66, "Enter  %s %s  into the highlighted cell" % [entry["label"], entry["val"]], _col("#cfe8ff"), 13, "center")
	var l2 := "nope — read the headers again" if wrong else ("%s _" % target[0] if stage == 1 else "type the cell: column letter, then row number")
	cv.text(W / 2.0, 83, l2, _col("#ff8a8a") if wrong else _col("#ffd9a0"), 13, "center")
	var t_col := SHEET_COLS.find(target[0])
	var t_row := int(target[1]) - 1
	@warning_ignore("integer_division")
	var tpx := t_col / 3
	@warning_ignore("integer_division")
	var tpy := t_row / 3
	var x0 := 108
	var y0 := 104
	var cw := 108
	var ch := 44
	cv.text(W - 14, 72, "cols %s–%s · rows %d–%d" % [SHEET_COLS[px * 3], SHEET_COLS[px * 3 + 2], py * 3 + 1, py * 3 + 3], _col("#55688a"), 11, "right")
	for i in range(3):
		cv.text(x0 + cw * i + cw / 2.0, y0 - 5, SHEET_COLS[px * 3 + i], _col("#8ab4e8"), 13, "center")
	for j in range(3):
		var r := py * 3 + j + 1
		cv.text(x0 - 10, y0 + j * ch + 27, str(r), _col("#8ab4e8"), 13, "right")
		for i in range(3):
			var id := SHEET_COLS[px * 3 + i] + str(r)
			var filled = cells.get(id, null)
			var is_target := id == target
			var col: Color = _col("#12331a") if filled != null else (_col("#8a5a10") if is_target else _col("#16305a"))
			cv.rect(x0 + cw * i + 2, y0 + j * ch + 2, cw - 4, ch - 4, col)
			if is_target and filled == null:
				cv.stroke_rect(x0 + cw * i + 3.5, y0 + j * ch + 3.5, cw - 7, ch - 7, _col("#ffd9a0"), 3)
			if filled != null:
				var fd: Dictionary = filled
				cv.text(x0 + cw * i + cw / 2.0, y0 + j * ch + 19, String(fd["label"]), _col("#9df09d"), 10, "center")
				cv.text(x0 + cw * i + cw / 2.0, y0 + j * ch + 33, String(fd["val"]), _col("#9df09d"), 10, "center")
	# off-page? point the way (with the key to press)
	var ax := x0 + 3 * cw + 14
	var gy := y0 + 1.5 * ch + 5
	if tpy < py:
		cv.text(ax, gy - 26, "▲ W", _col("#ffb347"), 15, "left")
	if tpx < px:
		cv.text(ax, gy, "◀ A", _col("#ffb347"), 15, "left")
	if tpx > px:
		cv.text(ax, gy, "D ▶", _col("#ffb347"), 15, "left")
	if tpy > py:
		cv.text(ax, gy + 26, "▼ S", _col("#ffb347"), 15, "left")

func _draw_call(st: Dictionary, cv: MonitorCanvas) -> void:
	var W := SCREEN_W
	var words: Array = st["words"]
	var opts: Array = st["opts"]
	var picked := int(st["picked"])
	if Time.get_ticks_msec() < int(st["show_until"]):
		cv.text(W / 2.0, 85, "📞 The boss says (MEMORIZE THE ORDER):", _col("#9df09d"), 15, "center")
		for i in range(words.size()):
			cv.text(W / 2.0, 125 + i * 36, "%d. %s" % [i + 1, words[i]], _col("#ffd9a0"), 24, "center")
	else:
		var tail := " — keep going" if picked > 0 else ""
		cv.text(W / 2.0, 82, "\"So what were my three points?\"  (%d/3%s)" % [picked, tail], _col("#cfe8ff"), 15, "center")
		cv.text(W / 2.0, 240, "A = \"sorry, could you repeat that?\"", _col("#555566"), 12, "center")
		for i in range(opts.size()):
			var col_i := i % 2
			@warning_ignore("integer_division")
			var row := i / 2
			var x := 60 + col_i * 200
			var y := 105 + row * 42
			cv.rect(x, y, 190, 32, _col("#16305a"))
			cv.text(x + 10, y + 22, str(i + 1), _col("#ffe9a8"), 15, "left")
			cv.text(x + 105, y + 22, String(opts[i]), _col("#cfe8ff"), 15, "center")

# ============================================================
# the shop (buy tonight, delivered tomorrow morning)
# ============================================================
func shop_catalog() -> Array:
	var list: Array = []
	for d in furniture.distracts.values():
		if not bool(d["owned"]):
			list.append({"kind": "toy", "rec": d, "id": d["id"], "label": d["label"], "price": int(d["price"]),
				"locked": Global.day < int(d["unlock"]), "unlock": int(d["unlock"]), "pending": bool(d["pending"]), "time": d["time"]})
	for b in furniture.containers.values():
		if not bool(b["owned"]):
			list.append({"kind": "storage", "rec": b, "id": b["id"], "label": b["label"], "price": int(b["price"]),
				"locked": Global.day < int(b["unlock"]), "unlock": int(b["unlock"]), "pending": bool(b["pending"]), "cap": int(b["cap"])})
	list.sort_custom(func(a, b): return int(a["price"]) < int(b["price"]))
	if cats != null and Global.cat_available(cats.cats.size()):
		list.append({"kind": "cat", "id": "adopt", "label": "a whole entire cat", "price": 0,
			"locked": false, "unlock": 1, "pending": false})
	return list

func buy_item(i: int) -> void:
	var list := shop_catalog()
	if i < 0 or i >= list.size():
		return
	var it: Dictionary = list[i]
	if it["kind"] == "cat":
		if game != null:
			game.open_adopt()
		return
	var d: Dictionary = it["rec"]
	if Global.day < int(d["unlock"]):
		Global.msg("Out of stock — CATS-R-US restocks it on day %d." % int(d["unlock"]))
		return
	if bool(d["pending"]):
		Global.msg("Already ordered — it arrives tomorrow morning.")
		return
	if Global.money < int(d["price"]):
		Global.msg("Not enough money for the %s ($%d)." % [d["label"], int(d["price"])], "danger")
		if audio != null:
			audio.beep(180, 0.1, 0.08)
		return
	Global.money -= int(d["price"])
	d["pending"] = true
	Global.bought_today.append(d)
	Global.msg("🛒 Ordered: %s — arrives tomorrow morning!" % d["label"], "good")
	if audio != null:
		audio.beep(900, 0.12, 0.1, "triangle")
	if game != null:
		game.update_econ()
	_redraw()

func _draw_shop(cv: MonitorCanvas) -> void:
	_make_thumbs()
	var W := SCREEN_W
	var list := shop_catalog()
	cv.text(W / 2.0, 45, "🛒 CATS-R-US EXPRESS — overnight delivery", _col("#ffd9a0"), 15, "center")
	if list.is_empty():
		cv.text(W / 2.0, 150, "You own EVERYTHING. Your cats are landlords now.", _col("#9df09d"), 14, "center")
	@warning_ignore("integer_division")
	var rows := int(ceil(list.size() / 3.0))
	shop_scroll = maxi(0, mini(shop_scroll, maxi(0, rows - 2)))
	var card_w := 156
	var card_h := 104
	var x0 := 15
	var y0 := 54
	for i in range(list.size()):
		var it: Dictionary = list[i]
		@warning_ignore("integer_division")
		var row := i / 3 - shop_scroll
		var col := i % 3
		if row < 0 or row > 1:
			continue
		var x := x0 + col * (card_w + 10)
		var y := y0 + row * (card_h + 6)
		var pending := bool(it["pending"])
		var locked := bool(it["locked"])
		cv.rect(x, y, card_w, card_h, _col("#12331a") if pending else (_col("#0e1728") if locked else _col("#16305a")))
		cv.stroke_rect(x + 0.5, y + 0.5, card_w - 1, card_h - 1, _col("#2f6a3a") if pending else _col("#2a4a7a"))
		cv.text(x + 6, y + 14, str(i + 1), _col("#ffe9a8"), 12, "left")
		var th = _thumbs.get(it["id"], null)
		if th != null:
			cv.img(th, x + card_w / 2.0 - 26, y + 3, 52, 52, 0.28 if locked else 1.0)
		var nm := String(it["label"]).split(" (")[0]
		if nm.length() > 22:
			nm = nm.substr(0, 21) + "…"
		cv.text(x + card_w / 2.0, y + 66, nm, _col("#55688a") if locked else _col("#cfe8ff"), 11, "center")
		var sub := "permanent. very permanent." if it["kind"] == "cat" \
			else ("cat-proof storage · %d slots" % int(it["cap"]) if it["kind"] == "storage" \
			else "holds a cat ~%ds" % int(it["time"]))
		cv.text(x + card_w / 2.0, y + 78, sub, _col("#3d4d68") if locked else _col("#8ab4e8"), 9, "center")
		if pending:
			cv.text(x + card_w / 2.0, y + 94, "✓ ORDERED", _col("#6fd66f"), 12, "center")
		elif locked:
			cv.text(x + card_w / 2.0, y + 90, "OUT OF STOCK", _col("#ff8a8a"), 12, "center")
			cv.text(x + card_w / 2.0, y + 101, "restock: day %d" % int(it["unlock"]), _col("#55688a"), 9, "center")
		else:
			var pcol: Color = _col("#9df09d") if Global.money >= int(it["price"]) else _col("#ff8a8a")
			cv.text(x + card_w / 2.0, y + 94, "FREE" if it["kind"] == "cat" else "$" + str(int(it["price"])), pcol, 12, "center")
	if shop_scroll > 0:
		cv.text(W - 12, 62, "▲ more", _col("#ffd9a0"), 12, "right")
	if rows - shop_scroll > 2:
		cv.text(W - 12, 268, "▼ more", _col("#ffd9a0"), 12, "right")
	var bob_left := _bob_open()
	var scroll_hint := " · W/S scroll" if rows > 2 else ""
	var bob_hint := " (Bob still needs help!)" if bob_left else ""
	cv.text(W / 2.0, 305, "number = buy%s · T = tasks%s · X = done (go to bed)" % [scroll_hint, bob_hint], _col("#8ab4e8"), 12, "center")

# ---- product thumbnails: each item rendered once, offscreen, into a SubViewport ----
func _make_thumbs() -> void:
	if _thumbs_made:
		return
	_thumbs_made = true
	for d in furniture.distracts.values():
		_thumbs[d["id"]] = _snap(d["mesh"])
	for b in furniture.containers.values():
		if int(b["price"]) > 0:
			_thumbs[b["id"]] = _snap(b["mesh"])
	# a display-model cat for the adoption card
	var holder := Node3D.new()
	add_child(holder)
	var disp := Cat.new("disp", Global.CAT_COLORS[1], 1.0, holder)
	disp.g.visible = true
	_thumbs["adopt"] = _snap(disp.g)
	holder.queue_free()

func _snap(src: Node3D) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	_thumb_vps.append(vp)
	var clone := src.duplicate()
	clone.position = Vector3.ZERO
	clone.rotation = Vector3(0, -0.6, 0)
	_show_all(clone)
	vp.add_child(clone)
	var cam := Camera3D.new()
	cam.fov = 38.0
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.85
	cam.environment = env
	vp.add_child(cam)
	var dl := DirectionalLight3D.new()
	dl.light_color = Color.hex(0xfff2d8ff)
	dl.light_energy = 0.9
	vp.add_child(dl)
	var aabb := _node_aabb(clone)
	var ctr := aabb.get_center()
	var r := aabb.size.length() / 2.0
	if r <= 0.0:
		r = 1.0
	cam.position = ctr + Vector3(r * 1.5, r * 0.9, r * 1.5)
	cam.look_at(ctr, Vector3.UP)
	dl.look_at_from_position(ctr + Vector3(2, 3, 4), ctr, Vector3.UP)
	return vp.get_texture()

func _show_all(n: Node) -> void:
	if n is Node3D:
		(n as Node3D).visible = true
	for c in n.get_children():
		_show_all(c)

func _node_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for m in _all_meshes(root):
		var a: AABB = m.global_transform * m.get_aabb()
		if first:
			acc = a
			first = false
		else:
			acc = acc.merge(a)
	return acc

func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out

# ============================================================
# helpers
# ============================================================
func _redraw() -> void:
	if canvas != null:
		canvas.queue_redraw()

func _col(hex: String) -> Color:
	return Color.html(hex)

func _key_str(e: InputEventKey) -> String:
	match e.keycode:
		KEY_BACKSPACE:
			return "Backspace"
		KEY_ESCAPE:
			return "Escape"
	if e.unicode != 0:
		return char(e.unicode)
	return ""

func _pick(a: Array):
	return a[randi() % a.size()]

func _shuffled(a: Array) -> Array:
	var r := a.duplicate()
	for i in range(r.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = r[i]
		r[i] = r[j]
		r[j] = tmp
	return r

func _gibberish() -> String:
	var w := ""
	var n := 2 + randi() % 2
	for i in range(n):
		w += SYL[randi() % SYL.size()]
	return w
