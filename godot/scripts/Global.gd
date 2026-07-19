## Global game constants and shared state (autoload singleton "G").
## Mirrors the constants and world-state block at the top of the web build's game.js.
extends Node

# ---------- world geometry constants ----------
const FLOOR_Y := {"basement": -3.0, "main": 0.0, "up": 3.0}
const LEVELS := [-3.0, 0.0, 3.0]
const WALL_H := 2.8
const EYE := 1.55
const PLAYER_R := 0.32

# ---------- gameplay constants ----------
const RING_LIMIT := 18.0          # seconds to answer phone
const HEART_MAX := 9
const TASK_PAY := 35              # $ per completed work task
const BOB_PAY := 55              # $ for covering Bob's work
const NO_HEART_BONUS := 20       # end-of-day bonus if no hearts were lost
const NIGHT_HEAL := 3            # hearts recovered per night of sleep
const DISTRACT_MIN := 5.0        # seconds — a bored cat's attention floor

const CHAOS_LADDER := [0.9, 1.3, 1.65, 2.0]
const MAX_CATS := 4
const CAT_AVAILABLE_DAYS := [1, 3, 6, 10]

const NAME_POOL := ["Whiskers", "Shadow", "Luna", "Toast", "Chaos", "Beans", "Mochi", "Pickle", "Noodle", "Gizmo"]
const CAT_COLORS := [
	{"key": "orange", "body": 0xe8933a, "dark": 0xd0782a, "eye": 0x222222},
	{"key": "gray",   "body": 0x8a8f98, "dark": 0x6c7078, "eye": 0x222222},
	{"key": "black",  "body": 0x33333a, "dark": 0x232328, "eye": 0xddcc44},
	{"key": "white",  "body": 0xf2f0ea, "dark": 0xd8d4c8, "eye": 0x222222},
	{"key": "calico", "body": 0xb07040, "dark": 0x7a4a28, "eye": 0x222222},
]

# stairs: enter at z0 (low end), exit at z1 (high end)
const STAIRS := [
	{"minX": 0.75, "maxX": 2.45, "z0": -1.9, "z1": -5.0, "y0": 0.0, "y1": 3.0},   # up
	{"minX": -2.3, "maxX": -0.6, "z0": -1.9, "z1": -5.0, "y0": 0.0, "y1": -3.0},  # down
]

# room name lookup
const ROOMS := [
	{"name": "the office",           "lvl": 0,  "minX": -8, "maxX": -2.5, "minZ": -6, "maxZ": 0},
	{"name": "the TV room",          "lvl": 0,  "minX": -8, "maxX": -2.5, "minZ": 0,  "maxZ": 6},
	{"name": "the kitchen",          "lvl": 0,  "minX": 2.5, "maxX": 8,   "minZ": -6, "maxZ": 0},
	{"name": "the dining room",      "lvl": 0,  "minX": 2.5, "maxX": 8,   "minZ": 0,  "maxZ": 6},
	{"name": "the main bathroom",    "lvl": 0,  "minX": -2.5, "maxX": 2.5, "minZ": 3.6, "maxZ": 6},
	{"name": "the hallway",          "lvl": 0,  "minX": -2.5, "maxX": 2.5, "minZ": -6, "maxZ": 3.6},
	{"name": "the bedroom",          "lvl": 3,  "minX": -8, "maxX": -1,   "minZ": -6, "maxZ": 0},
	{"name": "the guest bedroom",    "lvl": 3,  "minX": -8, "maxX": -1,   "minZ": 0,  "maxZ": 6},
	{"name": "the closet",           "lvl": 3,  "minX": 2.5, "maxX": 8,   "minZ": -6, "maxZ": -1},
	{"name": "the upstairs bathroom","lvl": 3,  "minX": 2.5, "maxX": 8,   "minZ": 2,  "maxZ": 6},
	{"name": "upstairs",             "lvl": 3,  "minX": -8, "maxX": 8,    "minZ": -6, "maxZ": 6},
	{"name": "the laundry room",     "lvl": -3, "minX": -8, "maxX": 8,    "minZ": -6, "maxZ": 0},
	{"name": "the basement den",     "lvl": -3, "minX": -8, "maxX": 8,    "minZ": 0,  "maxZ": 6},
]

# ---------- runtime state ----------
var day := 1
var money := 0
var hearts := HEART_MAX
var hearts_lost_today := 0
var day_stage := "intro"  # "intro" | "morning" | "work" | "evening"

# Flags the cat AI + flow read.
var started := false      # the start screen has been dismissed / a game is live
var phase := 0            # 0 = intro, then 1..3 progressive chaos (Game paces this)
var play_clock := 0.0     # seconds since this day's chaos began
var tutorial_done := false # cleared until the intro tutorial is dismissed
var in_computer := false  # set while sitting at the monitor
var game_over := false
var vet_today := false    # cleared each morning

# Adoption / delivery bookkeeping (persisted in the save).
var pending_adopts: Array = []      # [{name, color_def}] — new cats arrive next morning
var adopt_announced := {}           # set of cat indexes whose shelter call already happened
var bought_today: Array = []        # distraction/container records ordered today

func next_cat_idx(cat_count: int) -> int:
	return cat_count + pending_adopts.size()

func cat_available(cat_count: int) -> bool:
	var i := next_cat_idx(cat_count)
	return i < MAX_CATS and day >= CAT_AVAILABLE_DAYS[i]

## Hazard-arming window [min,max] seconds — tighter with more cats.
func risk_window(cat_count: int) -> Array:
	var n := cat_count
	return [maxf(16.0, 34.0 - 7.0 * (n - 1)), maxf(30.0, 56.0 - 9.0 * (n - 1))]

func color_by_key(key: String) -> Dictionary:
	for cd in CAT_COLORS:
		if cd["key"] == key:
			return cd
	return CAT_COLORS[0]

## Reset everything for a brand-new game (New Game from the start screen).
func reset_new_game() -> void:
	day = 1
	money = 0
	hearts = HEART_MAX
	hearts_lost_today = 0
	day_stage = "intro"
	started = false
	phase = 0
	play_clock = 0.0
	tutorial_done = false
	in_computer = false
	game_over = false
	vet_today = false
	pending_adopts.clear()
	adopt_announced.clear()
	bought_today.clear()

# ---------- lightweight message bus ----------
# The web build pushed player-facing text into HUD elements (#msg, #held, #hint).
# The real HUD is Phase 5; for now msg()/hint carry the same text to stdout and a
# signal, so gameplay code can talk without depending on UI that doesn't exist yet.
signal message_posted(text: String, kind: String)
signal held_changed(text: String)
signal hearts_changed(hearts: int)
signal cat_status(lines: Array)   # per-frame cat status strings (HUD lands in Phase 5)

func msg(text: String, kind: String = "") -> void:
	var tag := ("[%s] " % kind) if kind != "" else ""
	print(tag, text)
	message_posted.emit(text, kind)

## Ground height at (x,z) given the current y — flat floors plus the two stair
## ramps. Cats and dropped items sit on this (the player uses real physics).
func ground_y(x: float, z: float, cur_y: float) -> float:
	for s in STAIRS:
		if x >= s.minX and x <= s.maxX and z <= s.z0 and z >= s.z1:
			var t: float = (s.z0 - z) / (s.z0 - s.z1)
			var y: float = s.y0 + (s.y1 - s.y0) * t
			if abs(cur_y - y) < 1.9:
				return y
	return nearest_level(cur_y)

func nearest_level(y: float) -> float:
	var best := 0.0
	var bd := 1e9
	for f in LEVELS:
		var d: float = abs(y - f)
		if d < bd:
			bd = d
			best = f
	return best

func room_name(x: float, y: float, z: float) -> String:
	var lvl := nearest_level(y)
	for r in ROOMS:
		if float(r.lvl) == lvl and x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ:
			return r.name
	if lvl == 3.0:
		return "upstairs"
	elif lvl == -3.0:
		return "the basement"
	return "somewhere"
