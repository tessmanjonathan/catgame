## Crosshair look-at, hint text, and click handling. Port of the INTERACTION
## and HINT sections of game.js (~2889-3233).
##
## The web build ray-cast three.js meshes; here we ray-test the simple
## sphere/AABB click volumes Furniture recorded (Godot node metadata + a plain
## GDScript ray test — no physics layer needed, and invisible props are skipped
## exactly like the web build's treeVisible() filter).
##
## Live now: toggle hazards (arm/disarm, tool gate), item pick-up / drop / stash,
## containers, and every hint. Stubbed until their systems land: computer (P4),
## phone / bowl-feeding / bed / distractions / cats (P3-P5). Item drop uses a
## simplified in-front-of-player placement; surface-aware placement (cats hopping
## onto counters) returns with the cats in Phase 3.
class_name Interactor
extends Node3D

const REACH := 3.0

var camera: Camera3D
var furniture: Furniture
var player: Node3D
var cats                   # Cats manager (set by Main once Phase 3 is wired)
var computer               # Computer (set by Main once Phase 4 is wired)
var game                   # Game orchestrator (carrier intro / phone / sleep)
var audio: GameAudio       # treat-shake beep

var held = null            # the item hazard record — or the held Cat — in hand (or null)
var _last_hint := ""

func _process(_delta: float) -> void:
	_update_hint()

func _unhandled_input(event: InputEvent) -> void:
	if Global.in_computer:
		return   # the monitor owns all input while seated
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if held != null:
			_drop_held()
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		_on_left_click()

# ---------- crosshair ray ----------
func _aimed():
	if camera == null or furniture == null:
		return null
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var best = null
	var best_d := REACH
	for rec in furniture.interactables:
		var node: Node3D = rec["node"]
		if not node.is_visible_in_tree():
			continue
		var d := _ray_hit(rec, origin, dir)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = rec
	return best

func _ray_hit(rec: Dictionary, origin: Vector3, dir: Vector3) -> float:
	var node: Node3D = rec["node"]
	if rec["kind"] == "sphere":
		var center: Vector3 = node.to_global(rec["center"])
		var oc := origin - center
		var r: float = rec["r"]
		var b := oc.dot(dir)
		var c := oc.length_squared() - r * r
		var disc := b * b - c
		if disc < 0.0:
			return -1.0
		var t := -b - sqrt(disc)
		if t < 0.0:
			t = -b + sqrt(disc)
		return t if t >= 0.0 else -1.0
	# box: test in the node's local (unscaled) frame
	var inv := node.global_transform.affine_inverse()
	var lo := inv * origin
	var ld := inv.basis * dir
	var mn: Vector3 = rec["center"] - rec["half"]
	var mx: Vector3 = rec["center"] + rec["half"]
	var tmin := -1e20
	var tmax := 1e20
	for a in range(3):
		if absf(ld[a]) < 1e-8:
			if lo[a] < mn[a] or lo[a] > mx[a]:
				return -1.0
		else:
			var t1 := (mn[a] - lo[a]) / ld[a]
			var t2 := (mx[a] - lo[a]) / ld[a]
			if t1 > t2:
				var tmp := t1; t1 = t2; t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	if tmax < 0.0:
		return -1.0
	return tmin if tmin > 0.0 else tmax

# ---------- left click dispatch ----------
func _on_left_click() -> void:
	var rec = _aimed()

	# laser pointer: click floor / nothing while holding it → lure the cats
	if held != null and not _held_is_cat() and held.get("id", "") == "laser" and (rec == null or rec.get("act", "") == ""):
		if cats != null:
			cats.fire_laser(_floor_point())
		else:
			Global.msg("The red dot dances across the floor.")
		return
	if rec == null:
		return
	var act: String = rec["act"]
	var id: String = rec.get("id", "")

	match act:
		"cat":
			if held != null:
				Global.msg("Hands full! Right-click to drop first.")
			elif cats != null:
				cats.pick_up_cat(rec["cat_ref"])
		"barf":
			var h: Dictionary = furniture.hazards[id]
			h["cleaned"] = true
			(h["mesh"] as Node3D).visible = false
			for i in range(furniture.interactables.size()):
				var r: Dictionary = furniture.interactables[i]
				if r.get("id", "") == id and r.get("act", "") == "barf":
					furniture.interactables.remove_at(i)
					break
			Global.msg("You cleaned up the barf. Peak work-from-home experience.", "good")
		"carrier":
			if game != null:
				game.open_carrier()
			else:
				furniture.open_carrier()
		"computer":
			if not furniture.carrier_open:
				Global.msg("Let the kitten out of the carrier first!")
			elif computer != null:
				computer.enter()
		"phone":
			if game != null:
				game.answer_phone()
			else:
				Global.msg("The phone is quiet. Ominously quiet.")
		"toggle":
			_toggle(id)
		"item":
			if held != null:
				Global.msg("Your hands are full. Right-click to drop.")
			else:
				_pick_up_item(furniture.hazards[id])
		"container":
			_use_container(id)
		"distract":
			if cats != null:
				cats.distract_cat(id)
			else:
				Global.msg("You wave the %s around." % rec.get("label", "toy"))
			if id == "treats" and audio != null:
				audio.beep(1300, 0.15, 0.1, "triangle")
		"bowl":
			furniture.fill_bowl()
			if cats != null:
				cats.on_bowl_filled()
			if game != null:
				game.on_fed()
		"bed":
			if Global.day_stage == "evening":
				if game != null:
					game.try_sleep()
			elif Global.day_stage == "morning":
				Global.msg("No going back to bed — the cat is starving (allegedly).")
			else:
				Global.msg("No napping. You have work to do.")

func _toggle(id: String) -> void:
	var h: Dictionary = furniture.hazards[id]
	if h.get("needTool", "") != "" and h["armed"]:
		var holding_tool: bool = held != null and held.get("id", "") == h["needTool"]
		if not holding_tool:
			Global.msg(h["needToolHint"], "danger")
			return
	if h["armed"]:
		h["armed"] = false
		h["everFixed"] = true
		furniture.apply_toggle_vis(h)
		Global.msg("✔ %s — safe now." % h["name"], "good")
	else:
		var arm_hint: String = h.get("armHint", "")
		Global.msg(arm_hint if arm_hint != "" else "Already safe.")

func _pick_up_item(h: Dictionary) -> void:
	held = h
	h["held"] = true
	(h["mesh"] as Node3D).visible = false
	var text := "🤚 Holding: %s" % h["label"]
	if not h.get("safeItem", false):
		text += " — stash it in a cupboard/drawer/chest/shelf"
	if h["id"] == "laser":
		text = "🤚 Holding: laser pointer — left-click the floor to lure the cats"
	elif h["id"] == "screwdriver":
		text = "🤚 Holding: screwdriver — use it on the loose air vent"
	_set_held_text(text)

func _use_container(id: String) -> void:
	var box: Dictionary = furniture.containers[id]
	if _held_is_cat():
		Global.msg("You can't stash a cat. (It would fit. Don't.)")
	elif held != null and not held.get("safeItem", false):
		if box["used"] >= box["cap"]:
			Global.msg("The %s is FULL (max %d). Find somewhere else." % [box["label"], box["cap"]], "danger")
			return
		box["used"] += 1
		_stash_held(box["label"])
	elif held != null and held.get("safeItem", false):
		Global.msg("That's a tool, keep it or drop it (right-click).")
	else:
		Global.msg("The %s. Cat-proof storage (%d/%d used)." % [box["label"], box["used"], box["cap"]])

func _stash_held(container_label: String) -> void:
	var h = held
	held = null
	_set_held_text("")
	h["stashed"] = true
	h["held"] = false
	Global.msg("✔ %s stashed in the %s. Permanently cat-proofed." % [h["label"], container_label], "good")

func _held_is_cat() -> bool:
	return held != null and held is Cat

## The floor point under the crosshair, at the player's current level.
func _floor_point() -> Vector3:
	var cam := camera.global_position
	var dir := -camera.global_transform.basis.z
	var floor_y := Global.nearest_level(player.global_position.y) + 0.03
	if absf(dir.y) < 1e-4:
		return Vector3(cam.x, floor_y, cam.z)
	var t := (floor_y - cam.y) / dir.y
	t = clampf(t, 0.0, 20.0)
	return cam + dir * t

func _drop_held() -> void:
	if _held_is_cat():
		if cats != null:
			cats.drop_cat_at(held)
		return
	var h = held
	held = null
	_set_held_text("")
	h["held"] = false
	# Simplified drop: set the item on the ground just in front of the player.
	# (Surface-aware placement returns with the cats in Phase 3.)
	var fwd := -camera.global_transform.basis.z
	var base := player.global_position
	var gy := Global.nearest_level(base.y)
	var mesh := h["mesh"] as Node3D
	mesh.global_position = Vector3(base.x + fwd.x * 0.9, gy + 0.15, base.z + fwd.z * 0.9)
	h["curSurface"] = null
	mesh.visible = true
	if not h.get("safeItem", false):
		Global.msg("You dropped the %s. It is once again a cat magnet." % h["label"], "danger")

# ---------- hint ----------
func _update_hint() -> void:
	if Global.in_computer or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_emit_hint("")
		return
	var rec = _aimed()
	if rec == null:
		_emit_hint("")
		return
	var act: String = rec["act"]
	var id: String = rec.get("id", "")
	var text := ""
	match act:
		"carrier":
			text = "the (empty) cat carrier" if furniture.carrier_open else "📦 Click — open the carrier"
		"computer":
			text = "Click — open the SHOP" if Global.day_stage == "evening" else "Click — get to work"
		"phone":
			text = "desk phone"
		"toggle":
			var h: Dictionary = furniture.hazards[id]
			text = ("⚠ " + h["fixHint"]) if h["armed"] else h.get("armHint", "safe")
		"item":
			text = "Pick up: " + furniture.hazards[id]["label"]
		"container":
			var box: Dictionary = furniture.containers[id]
			if held != null and not held.get("safeItem", false):
				text = ("%s — FULL (%d/%d)" % [box["label"], box["used"], box["cap"]]) if box["used"] >= box["cap"] \
					else ("Stash the %s here (%d/%d)" % [held["label"], box["used"], box["cap"]])
			else:
				text = "%s (%d/%d)" % [box["label"], box["used"], box["cap"]]
		"distract":
			text = "Distract the cats: " + rec.get("label", "")
		"bed":
			text = "🛏 Click — SLEEP (end day %d)" % Global.day if Global.day_stage == "evening" else "your bed (no naps allowed)"
		"bowl":
			text = "Food bowl (full)" if furniture.bowl_full \
				else ("🍽 FEED THE CAT — fill the bowl" if Global.day_stage == "morning" else "Fill the food bowl")
	_emit_hint(text)

func _emit_hint(text: String) -> void:
	if text == _last_hint:
		return
	_last_hint = text
	if text != "":
		print("[hint] ", text)

func _set_held_text(text: String) -> void:
	Global.held_changed.emit(text)
	print("[held] ", text if text != "" else "(empty)")
