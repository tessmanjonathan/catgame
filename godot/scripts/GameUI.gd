## HUD + all full-screen overlays. Port of the HTML in index.html and the HUD /
## MESSAGES helpers in game.js (updateHearts/updateEcon/flashHearts/msg/bossSay/
## setObjective/updateLockHint) plus the start / tutorial / pause / end / day-
## summary / adopt / confirm overlays.
##
## The web build was DOM; here every element is a Godot Control on a CanvasLayer.
## process_mode is ALWAYS so overlay buttons still work while the sim is paused
## (opening any modal sets get_tree().paused = true, freezing the 3D world).
class_name GameUI
extends CanvasLayer

var game                      # Game orchestrator (button callbacks route here)

const GOLD := Color("ffb347")
const GREEN := Color("9df09d")
const RED := Color("ff6b6b")
const CREAM := Color("ffe9a8")

# ---- HUD nodes ----
var _hearts: Label
var _cat_status: Label
var _objective: Label
var _day_label: Label
var _money_label: Label
var _task_label: Label
var _work_fill: ColorRect
var _work_pct: Label
var _away_warn: Label
var _crosshair: Label
var _hint: Label
var _held: Label
var _messages: VBoxContainer
var _boss_banner: Label
var _lock_hint: Label
var _comp_exit: Label
var _hud: Control

# ---- overlays ----
var _start: Control
var _tutorial: Control
var _pause: Control
var _end: Control
var _day_ov: Control
var _adopt: Control
var _confirm: Control

var _start_name: LineEdit
var _tut_title: Label
var _tut_goal: Label
var _end_title: Label
var _end_text: Label
var _day_title: Label
var _day_text: RichTextLabel
var _day_btn: Button
var _adopt_name: LineEdit
var _adopt_price: Label
var _adopt_chips: HBoxContainer
var _confirm_title: Label
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button

var chosen_color: Dictionary
var adopt_color: Dictionary

var _day_action: Callable = Callable()
var _confirm_yes_cb: Callable = Callable()
var _confirm_no_cb: Callable = Callable()

# ============================================================
# build
# ============================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	chosen_color = Global.CAT_COLORS[0]
	adopt_color = Global.CAT_COLORS[0]
	_build_hud()
	_build_start()
	_build_tutorial()
	_build_pause()
	_build_end()
	_build_day_overlay()
	_build_adopt()
	_build_confirm()
	# connect the message bus so any emitter reaches the HUD
	Global.message_posted.connect(func(t, k): msg(t, k))
	Global.held_changed.connect(func(t): set_held(t))
	Global.hearts_changed.connect(func(_h): update_hearts())
	Global.cat_status.connect(func(lines): set_cat_status(lines))

func _full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

func _panel(bg: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _label(text: String, color: Color, size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = align
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

func _btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(0, 44)
	return b

# ---------- HUD ----------
func _build_hud() -> void:
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(_hud)
	_hud.visible = false
	add_child(_hud)

	_hearts = _label("", Color.WHITE, 22)
	_hearts.position = Vector2(16, 12)
	_hud.add_child(_hearts)

	_cat_status = _label("", Color("ffd0d0"), 14)
	_cat_status.position = Vector2(16, 50)
	_cat_status.size = Vector2(560, 200)
	_hud.add_child(_cat_status)

	_objective = _label("", GREEN, 15, HORIZONTAL_ALIGNMENT_CENTER)
	_objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_objective.position = Vector2(-300, 12)
	_objective.size = Vector2(600, 26)
	_hud.add_child(_objective)

	# work panel (top-right)
	var wp := VBoxContainer.new()
	wp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	wp.position = Vector2(-236, 12)
	wp.custom_minimum_size = Vector2(220, 0)
	wp.alignment = BoxContainer.ALIGNMENT_END
	_hud.add_child(wp)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_day_label = _label("DAY 1", Color.WHITE, 15)
	_money_label = _label(" · 💰 $0", CREAM, 15)
	row.add_child(_day_label)
	row.add_child(_money_label)
	wp.add_child(row)
	_task_label = _label("TASKS DONE: —", Color.WHITE, 15, HORIZONTAL_ALIGNMENT_RIGHT)
	wp.add_child(_task_label)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.2)
	bar.custom_minimum_size = Vector2(220, 12)
	wp.add_child(bar)
	_work_fill = ColorRect.new()
	_work_fill.color = Color("6fd66f")
	_work_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_work_fill.size = Vector2(0, 12)
	bar.add_child(_work_fill)
	_work_pct = _label("0% of current task", Color.WHITE, 13, HORIZONTAL_ALIGNMENT_RIGHT)
	wp.add_child(_work_pct)
	_away_warn = _label("⚠ BOSS IS CALLING — ANSWER THE DESK PHONE!", RED, 15, HORIZONTAL_ALIGNMENT_RIGHT)
	_away_warn.visible = false
	wp.add_child(_away_warn)

	_crosshair = _label("+", Color(1, 1, 1, 0.85), 18, HORIZONTAL_ALIGNMENT_CENTER)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.position = Vector2(-8, -12)
	_crosshair.size = Vector2(16, 24)
	_hud.add_child(_crosshair)

	_hint = _label("", CREAM, 15, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hint.position = Vector2(-300, 40)
	_hint.size = Vector2(600, 24)
	_hint.visible = false
	_hud.add_child(_hint)

	_held = _label("", Color("cfe8ff"), 15, HORIZONTAL_ALIGNMENT_RIGHT)
	_held.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_held.position = Vector2(-600, -34)
	_held.size = Vector2(584, 24)
	_hud.add_child(_held)

	_messages = VBoxContainer.new()
	_messages.alignment = BoxContainer.ALIGNMENT_END
	_messages.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_messages.position = Vector2(-360, -320)
	_messages.size = Vector2(720, 260)
	_hud.add_child(_messages)

	# boss banner (own layer so it sits above the HUD)
	_boss_banner = _label("", CREAM, 19, HORIZONTAL_ALIGNMENT_CENTER)
	var bb := _panel(Color(0.08, 0.04, 0.04, 0.9))
	bb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bb.position = Vector2(-260, 60)
	bb.size = Vector2(520, 52)
	bb.visible = false
	_boss_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boss_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bb.add_child(_boss_banner)
	_boss_banner.set_meta("panel", bb)
	_hud.add_child(bb)

	_lock_hint = _label("Click to grab the mouse — WASD still moves you", CREAM, 16, HORIZONTAL_ALIGNMENT_CENTER)
	var lh := _panel(Color(0, 0, 0, 0.7))
	lh.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lh.position = Vector2(-220, -120)
	lh.size = Vector2(440, 36)
	lh.visible = false
	_lock_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lock_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lh.add_child(_lock_hint)
	_lock_hint.set_meta("panel", lh)
	_hud.add_child(lh)

	_comp_exit = _label("X — step away from the computer", Color("8ab4e8"), 14, HORIZONTAL_ALIGNMENT_CENTER)
	_comp_exit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_comp_exit.position = Vector2(-160, -40)
	_comp_exit.size = Vector2(320, 24)
	_comp_exit.visible = false
	_hud.add_child(_comp_exit)

# ---------- overlays ----------
func _overlay(bg: Color) -> Control:
	var o := Control.new()
	_full(o)
	o.visible = false
	var dim := ColorRect.new()
	dim.color = bg
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	add_child(o)
	return o

func _center_box(parent: Control, width: float) -> VBoxContainer:
	var card := _panel(Color("23233c"))
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(width, 0)
	parent.add_child(card)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 24; vb.offset_right = -24
	vb.offset_top = 20; vb.offset_bottom = -20
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	# keep the card sized to its content
	card.custom_minimum_size = Vector2(width, 0)
	return vb

func _color_row(on_pick: Callable, initial: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for cd in Global.CAT_COLORS:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(40, 40)
		sw.flat = false
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.hex((int(cd["body"]) << 8) | 0xff)
		sb.set_corner_radius_all(20)
		if cd == initial:
			sb.set_border_width_all(3); sb.border_color = GOLD
		sw.add_theme_stylebox_override("normal", sb)
		sw.add_theme_stylebox_override("hover", sb)
		sw.add_theme_stylebox_override("pressed", sb)
		sw.pressed.connect(func():
			for other in row.get_children():
				var osb: StyleBoxFlat = other.get_theme_stylebox("normal")
				osb.set_border_width_all(0)
			sb.set_border_width_all(3); sb.border_color = GOLD
			on_pick.call(cd))
		row.add_child(sw)
	return row

func _name_chips(box: HBoxContainer, names: Array, target: LineEdit) -> void:
	for n in box.get_children():
		n.queue_free()
	for nm in names:
		var s := Button.new()
		s.text = String(nm)
		s.add_theme_font_size_override("font_size", 13)
		s.pressed.connect(func(): target.text = String(nm))
		box.add_child(s)

func _build_start() -> void:
	_start = _overlay(Color("1a1a2e"))
	var vb := _center_box(_start, 560)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_label("🐈 cat HAS STOPPED WORKING", GOLD, 34, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_label("You just adopted a kitten. You also have a job, rent, and vet bills.", Color("aaaaaa"), 15, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_label("What's your kitten's name?", Color("ffd9a0"), 16, HORIZONTAL_ALIGNMENT_CENTER))
	_start_name = LineEdit.new()
	_start_name.text = "Whiskers"
	_start_name.max_length = 14
	_start_name.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_name.custom_minimum_size = Vector2(260, 40)
	_start_name.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_start_name)
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(chips)
	_name_chips(chips, Global.NAME_POOL.slice(0, 6), _start_name)
	vb.add_child(_label("Pick a coat", Color("ffd9a0"), 16, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_color_row(func(cd): chosen_color = cd, Global.CAT_COLORS[0]))
	var start_btn := _btn("🏠 BRING KITTY HOME")
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.pressed.connect(func(): if game: game.start_game(_start_name.text, chosen_color))
	vb.add_child(start_btn)
	_continue_btn = _btn("▶ CONTINUE")
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_btn.visible = false
	_continue_btn.pressed.connect(func(): if game: game.continue_game())
	vb.add_child(_continue_btn)

var _continue_btn: Button

func _build_tutorial() -> void:
	_tutorial = _overlay(Color(0.05, 0.05, 0.1, 0.9))
	var vb := _center_box(_tutorial, 560)
	_tut_title = _label("Welcome home!", GOLD, 24, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_tut_title)
	var keys := "WASD  move\nMouse  look around\nLeft click  pick up / fix / rescue cat\nRight click  drop what you're holding\nComputer  click it to sit down and type\nX  step away from the computer\nP  pause the game"
	vb.add_child(_label(keys, Color("dddddd"), 15))
	_tut_goal = _label("📋 First goal: go to the OFFICE and click the computer — today's work tasks are on it. Finish them all to get PAID, then shop and go to bed.\nListen for meowing — louder means closer, and closer means trouble.", GREEN, 14, HORIZONTAL_ALIGNMENT_CENTER)
	_tut_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_goal.custom_minimum_size = Vector2(500, 0)
	vb.add_child(_tut_goal)
	var b := _btn("GOT IT — TIME TO WORK")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): if game: game.dismiss_tutorial())
	vb.add_child(b)

func _build_pause() -> void:
	_pause = _overlay(Color(0.04, 0.04, 0.08, 0.85))
	var vb := _center_box(_pause, 480)
	vb.add_child(_label("⏸ PAUSED", GOLD, 40, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_label("The cats are frozen mid-scheme. Press P to resume.", Color("cccccc"), 16, HORIZONTAL_ALIGNMENT_CENTER))

func _build_end() -> void:
	_end = _overlay(Color(0.04, 0.04, 0.08, 0.92))
	var vb := _center_box(_end, 600)
	_end_title = _label("", RED, 34, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_end_title)
	_end_text = _label("", Color("cccccc"), 17, HORIZONTAL_ALIGNMENT_CENTER)
	_end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_text.custom_minimum_size = Vector2(540, 0)
	vb.add_child(_end_text)
	var b := _btn("TRY AGAIN")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): if game: game.restart())
	vb.add_child(b)

func _build_day_overlay() -> void:
	_day_ov = _overlay(Color(0.05, 0.05, 0.1, 0.85))
	var vb := _center_box(_day_ov, 620)
	_day_title = _label("", GOLD, 28, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_day_title)
	_day_text = RichTextLabel.new()
	_day_text.bbcode_enabled = true
	_day_text.fit_content = true
	_day_text.custom_minimum_size = Vector2(560, 0)
	_day_text.add_theme_color_override("default_color", Color("dddddd"))
	_day_text.add_theme_font_size_override("normal_font_size", 16)
	vb.add_child(_day_text)
	_day_btn = _btn("")
	_day_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_day_btn.pressed.connect(_on_day_btn)
	vb.add_child(_day_btn)

func _on_day_btn() -> void:
	_day_ov.visible = false
	if game:
		game.set_overlay_open(false)
	if _day_action.is_valid():
		var f := _day_action
		_day_action = Callable()
		f.call()

func _build_adopt() -> void:
	_adopt = _overlay(Color(0.05, 0.05, 0.1, 0.92))
	var vb := _center_box(_adopt, 480)
	vb.add_child(_label("🐈 Adopt another cat", GOLD, 24, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_label("Name the new troublemaker", Color("ffd9a0"), 16, HORIZONTAL_ALIGNMENT_CENTER))
	_adopt_name = LineEdit.new()
	_adopt_name.max_length = 14
	_adopt_name.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_adopt_name.custom_minimum_size = Vector2(240, 40)
	_adopt_name.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_adopt_name)
	_adopt_chips = HBoxContainer.new()
	_adopt_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_adopt_chips)
	vb.add_child(_label("Pick a coat", Color("ffd9a0"), 16, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_color_row(func(cd): adopt_color = cd, Global.CAT_COLORS[0]))
	_adopt_price = _label("", GREEN, 14, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_adopt_price)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 12)
	var buy := _btn("ADOPT")
	buy.pressed.connect(func(): if game: game.confirm_adopt(_adopt_name.text, adopt_color))
	var cancel := _btn("CANCEL")
	cancel.pressed.connect(func(): if game: game.cancel_adopt())
	brow.add_child(buy)
	brow.add_child(cancel)
	vb.add_child(brow)

func _build_confirm() -> void:
	_confirm = _overlay(Color(0.05, 0.05, 0.1, 0.85))
	var vb := _center_box(_confirm, 520)
	_confirm_title = _label("", GOLD, 26, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_confirm_title)
	_confirm_text = _label("", Color("dddddd"), 16, HORIZONTAL_ALIGNMENT_CENTER)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(460, 0)
	vb.add_child(_confirm_text)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 12)
	_confirm_yes = _btn("")
	_confirm_yes.pressed.connect(_on_confirm_yes)
	_confirm_no = _btn("")
	_confirm_no.pressed.connect(_on_confirm_no)
	brow.add_child(_confirm_yes)
	brow.add_child(_confirm_no)
	vb.add_child(brow)

# ============================================================
# HUD API
# ============================================================
func show_hud() -> void:
	_hud.visible = true

func update_hearts() -> void:
	var h: int = maxi(0, Global.hearts)
	_hearts.text = "❤️".repeat(h) + "🖤".repeat(Global.HEART_MAX - h)

func update_econ(done_n: int, req_n: int, bob_open: bool) -> void:
	_day_label.text = "DAY %d" % Global.day
	_money_label.text = " · 💰 $%d" % Global.money
	if req_n > 0:
		_task_label.text = "TASKS DONE: %d/%d%s" % [done_n, req_n, (" (+Bob?)" if bob_open else "")]
	else:
		_task_label.text = "TASKS DONE: —"

func flash_hearts() -> void:
	_hearts.scale = Vector2(1.3, 1.3)
	var tw := create_tween()
	tw.tween_property(_hearts, "scale", Vector2.ONE, 0.3)

func set_work_progress(pct: float) -> void:
	_work_fill.size.x = 220.0 * clampf(pct, 0.0, 1.0)
	_work_pct.text = "%d%% of current task" % int(pct * 100.0)

func set_objective(text: String) -> void:
	_objective.text = text
	_objective.visible = text != ""

func set_away_warn(v: bool) -> void:
	_away_warn.visible = v

func set_comp_exit(v: bool) -> void:
	_comp_exit.visible = v

func set_crosshair(v: bool) -> void:
	_crosshair.visible = v

func set_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = text != ""

func set_held(text: String) -> void:
	_held.text = text

func set_cat_status(lines: Array) -> void:
	_cat_status.text = "\n".join(PackedStringArray(lines))

func update_lock_hint(v: bool) -> void:
	(_lock_hint.get_meta("panel") as Control).visible = v

func msg(text: String, kind: String = "") -> void:
	var col := Color.WHITE
	match kind:
		"danger": col = Color("ff8a8a")
		"good": col = GREEN
		"talk": col = CREAM
	var m := _label(text, col, 17, HORIZONTAL_ALIGNMENT_CENTER)
	var p := _panel(Color(0, 0, 0, 0.72))
	p.custom_minimum_size = Vector2(0, 34)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(m)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_messages.add_child(p)
	_messages.move_child(p, 0)
	while _messages.get_child_count() > 4:
		var old := _messages.get_child(_messages.get_child_count() - 1)
		_messages.remove_child(old)   # remove_child is synchronous; queue_free alone isn't
		old.queue_free()
	get_tree().create_timer(6.5).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func boss_say(text: String) -> void:
	var p := _boss_banner.get_meta("panel") as Control
	_boss_banner.text = text
	p.visible = true
	get_tree().create_timer(6.0).timeout.connect(func(): if is_instance_valid(p): p.visible = false)

# ============================================================
# overlay API
# ============================================================
func show_start(has_save: bool) -> void:
	_continue_btn.visible = has_save
	_start.visible = true

func hide_start() -> void:
	_start.visible = false

func show_tutorial(title: String) -> void:
	_tut_title.text = title
	_tutorial.visible = true

func hide_tutorial() -> void:
	_tutorial.visible = false

func set_pause(v: bool) -> void:
	_pause.visible = v

func show_end(title: String, text: String) -> void:
	_end_title.text = title
	_end_text.text = text
	_end.visible = true

func show_day_overlay(title: String, color: Color, text: String, btn: String, on_ok: Callable) -> void:
	_day_title.text = title
	_day_title.add_theme_color_override("font_color", color)
	_day_text.text = text
	_day_btn.text = btn
	_day_action = on_ok
	_day_ov.visible = true

func is_day_overlay_open() -> bool:
	return _day_ov.visible

func open_adopt(default_name: String, chip_names: Array) -> void:
	_adopt_name.text = default_name
	_name_chips(_adopt_chips, chip_names, _adopt_name)
	_adopt_price.text = "Adoption is FREE · arrives tomorrow morning · each cat is more chaotic than the last"
	_adopt.visible = true

func close_adopt() -> void:
	_adopt.visible = false

func show_confirm(title: String, text: String, yes: String, no: String, on_yes: Callable, on_no: Callable) -> void:
	_confirm_title.text = title
	_confirm_text.text = text
	_confirm_yes.text = yes
	_confirm_no.text = no
	_confirm_yes_cb = on_yes
	_confirm_no_cb = on_no
	_confirm.visible = true

func _on_confirm_yes() -> void:
	_confirm.visible = false
	if game:
		game.set_overlay_open(false)
	if _confirm_yes_cb.is_valid():
		_confirm_yes_cb.call()

func _on_confirm_no() -> void:
	_confirm.visible = false
	if game:
		game.set_overlay_open(false)
	if _confirm_no_cb.is_valid():
		_confirm_no_cb.call()
