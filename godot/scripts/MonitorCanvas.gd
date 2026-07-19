## The 2D surface of the office monitor. Lives inside the Computer's SubViewport
## and its texture is mapped onto the screen quad in the 3D world.
##
## Port of the web build's `scrCtx` 2D-canvas drawing: the helpers below mirror
## the handful of canvas ops the CORP-OS screen + minigames use (fillRect,
## strokeRect, fillText with left/center/right align, measureText). `_draw` just
## forwards to Computer.draw_screen(self) so all the screen logic stays in one place.
class_name MonitorCanvas
extends Control

var computer            # Computer (set on creation)
var font: Font          # monospace, shared from Computer

func _draw() -> void:
	if computer != null:
		computer.draw_screen(self)

# ---- canvas-style helpers (y is the text baseline, matching canvas fillText) ----
func rect(x, y, w, h, color: Color) -> void:
	draw_rect(Rect2(x, y, w, h), color, true)

func stroke_rect(x, y, w, h, color: Color, width := 1.0) -> void:
	draw_rect(Rect2(x, y, w, h), color, false, width)

func measure(s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

func text(x, y, s: String, color: Color, size: int, align := "left") -> void:
	var lx: float = x
	if align == "center":
		lx = x - measure(s, size) * 0.5
	elif align == "right":
		lx = x - measure(s, size)
	draw_string(font, Vector2(lx, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Blit a texture into a rect (the web build's drawImage for shop thumbnails).
func img(tex: Texture2D, x, y, w, h, alpha := 1.0) -> void:
	if tex == null:
		return
	draw_texture_rect(tex, Rect2(x, y, w, h), false, Color(1, 1, 1, alpha))
