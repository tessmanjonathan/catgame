## Synthesized sound effects. Port of the AUDIO helpers in game.js (audio() /
## meow() / beep() / playHurtMeow()).
##
## The web build used the Web Audio API (oscillator + gain + biquad nodes).
## Godot has no such graph, so each call bakes a short PCM buffer by hand
## (oscillator + envelope, matching the web parameters exactly) into an
## AudioStreamWAV and plays it on a pooled AudioStreamPlayer. process_mode is
## ALWAYS so overlay/purchase beeps still sound while the sim is paused.
class_name GameAudio
extends Node

const RATE := 22050
const POOL := 10

var camera: Camera3D                 # for distance-attenuated meows
var _players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players.append(p)

# ============================================================
# public API (verbatim behaviour of the web build's meow/beep)
# ============================================================
func meow(volume: float, pitch: float = 1.0) -> void:
	# sawtooth with a 620→780→330 Hz sweep, 1200 Hz lowpass, 0.6 s bell envelope
	var dur := 0.65
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var lp := 0.0
	var a := _lp_coeff(1200.0)
	var dt := 1.0 / RATE
	for i in range(n):
		var t := i * dt
		var f := _ramp(t, [[0.0, 620.0 * pitch], [0.12, 780.0 * pitch], [0.55, 330.0 * pitch]])
		phase += f * dt
		var saw: float = 2.0 * (phase - floor(phase + 0.5))
		lp += a * (saw - lp)
		var g := _ramp(t, [[0.0, 0.0001], [0.08, volume * 0.28], [0.6, 0.0001]])
		buf[i] = lp * g
	_play(buf)

func beep(freq: float, dur: float, vol: float = 0.15, type: String = "square") -> void:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var dt := 1.0 / RATE
	for i in range(n):
		var t := i * dt
		phase += freq * dt
		var ph: float = phase - floor(phase)          # 0..1
		var s := 0.0
		match type:
			"sine":
				s = sin(ph * TAU)
			"triangle":
				s = 4.0 * absf(ph - 0.5) - 1.0
			_:  # "square"
				s = 1.0 if ph < 0.5 else -1.0
		# linear gain decay vol → ~0 over dur (matches setValueAtTime→linearRamp)
		var g := vol * (1.0 - t / dur)
		buf[i] = s * g
	_play(buf)

func play_hurt_meow(pos: Vector3) -> void:
	var d := 6.0
	if camera != null:
		d = pos.distance_to(camera.global_position)
	meow(minf(1.0, 2.5 / (1.0 + d * 0.4)), 1.35)

## Distance-attenuated meow at a world position (the tick meow loop).
func meow_at(pos: Vector3, base: float, pitch: float) -> void:
	var d := 6.0
	if camera != null:
		d = pos.distance_to(camera.global_position)
	meow(minf(1.0, base / (1.0 + d * 0.45)), pitch)

# ============================================================
# helpers
# ============================================================
## Piecewise-linear value at time t over [[t0,v0],[t1,v1],...] (clamped ends).
func _ramp(t: float, pts: Array) -> float:
	if t <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(pts.size() - 1):
		var t0 := float(pts[i][0])
		var t1 := float(pts[i + 1][0])
		if t <= t1:
			var f := (t - t0) / maxf(1e-6, t1 - t0)
			return lerpf(float(pts[i][1]), float(pts[i + 1][1]), f)
	return float(pts[pts.size() - 1][1])

func _lp_coeff(fc: float) -> float:
	var dt := 1.0 / RATE
	var rc := 1.0 / (TAU * fc)
	return dt / (rc + dt)

func _play(buf: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in range(buf.size()):
		var v := int(clampf(buf[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = wav
	p.play()
