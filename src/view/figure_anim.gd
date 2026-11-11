## How a drawn figure moves, for the walk and the battle screen alike: which frame of which action shows now, and what its body does on top
## (a breath, a hop's arc, a shake). Every reaction in the art starts from the resting pose, so a change of mood plays the old one
## backwards to rest and the new one forwards, and the eyes never jump. A hit or a lunge cuts in, as a hit does; on a blank face
## (`hollow`) it is drawn in code instead, because the hurt and lunge drawings have eyes.
extends RefCounted

const Sprites = preload("res://src/view/sprites.gd")

const FACE_ACTS := {"happy": "happy", "angry": "angry", "scared": "scared", "hollow": "hollow"} # what shows a mood; calm is `idle`
const BLINK_EVERY := [2.6, 6.5] # seconds between blinks
const BLINK_S := 0.16
const BREATH_S := 1.5 # seconds a breath takes
const HOLD_S := 0.42 # how fast a held face rocks between its last two frames
const HOP_S := 0.32 # a hop drawn in code, for a face the hop's drawing can't show
const HOP_LIFT := 0.22 # how high it goes, as a share of the body
const LAND_S := 0.13
const NOTICE_FRAME := 2 # how far into `happy` a start goes: the eyes wide and the lines over the head
const SHAKE_S := 0.4
const FLINCH_S := 0.22 # a blank face takes a hit by squashing, not by the hurt drawing
const FLINCH := 0.14
const LURCH_S := 0.42 # and lunges by swelling toward you, not by the lunge drawing
const LURCH := 0.16

var sheet := ""
var body_h := 1.0 # the body's height in whatever the caller measures in, for the hop drawn in code

var _face := "idle" # the action showing the mood
var _want := "idle" # the one that should be
var _dir := 1 # 1 going in, 0 held, -1 going back out to rest
var _t0 := 0.0
var _shot := "" # a one-off over the face
var _shot_t0 := 0.0
var _shot_to := -1 # the frame it turns back at, -1 for its end
var _code_hop := -10.0
var _land := -10.0
var _next_blink := 0.0
var _phase := 0.0 # so two of a kind don't breathe together
var _shake := -10.0
var _flinch := -10.0
var _lurch := -10.0


func _init(sheet_name: String, seed_value := 0) -> void:
	sheet = sheet_name
	_phase = float(absi(seed_value) % 1000) / 1000.0
	_next_blink = _phase * BLINK_EVERY[1]


## The mood to show: "calm", "happy", "angry", "scared" or "hollow". A figure without that action stays calm.
func set_mood(mood: String, now: float) -> void:
	var want: String = FACE_ACTS.get(mood, "idle")
	if not Sprites.has_action(sheet, want):
		want = "idle"
	if want == _want:
		return
	_want = want
	if _face == "idle":
		_face = want
		_dir = 1
		_t0 = now
	elif _dir != -1:
		_dir = -1
		_t0 = now


## What it is showing now, for a test or a tag.
func mood_act() -> String:
	return _want


## Play one action through once over the face; `to_frame` turns it back there and plays it out again (a start, not the whole reaction).
func play(act: String, now: float, to_frame := -1) -> void:
	if not Sprites.has_action(sheet, act):
		return
	_shot = act
	_shot_t0 = now
	_shot_to = to_frame


## A hop: drawn when the face at rest can be, or else the body arcs in code and keeps its face.
func hop(now: float) -> void:
	if _in_air(now):
		return
	if _want == "idle" and _face == "idle" and _shot == "" and Sprites.has_action(sheet, "hop"):
		play("hop", now)
	else:
		_code_hop = now


## A start: the eyes go wide and the lines show over its head, and it settles back.
func notice(now: float) -> void:
	if _want == "idle" and _face == "idle":
		play("happy", now, NOTICE_FRAME)
	_code_hop = now


## A hit: the hurt drawing cuts in, shaking. A blank face keeps its blank frame and only shakes and flinches, so no eyes come back.
func hurt(now: float) -> void:
	_shake = now
	if blank():
		_flinch = now
		print_verbose("figure_anim: %s hurt with a blank face, drawn in code" % sheet)
		return
	play("hurt", now)


## An attack: the lunge drawing, or on a blank face a lurch toward you drawn in code.
func lunge(now: float) -> void:
	if blank():
		_lurch = now
		return
	play("lunge", now)


## Whether the face it is showing, or turning to, is the blank one.
func blank() -> bool:
	return _want == "hollow"


func _in_air(now: float) -> bool:
	return _shot == "hop" or now - _code_hop < HOP_S


## Where it stands now: {act, frame, sx, sy, lift, lean, shake}. `lift` is a share of the body's height.
func tick(now: float) -> Dictionary:
	var out := {"act": "idle", "frame": 0, "sx": 1.0, "sy": 1.0, "lift": 0.0, "lean": 0.0, "shake": 0.0}
	if not _shot_frame(now, out):
		_face_frame(now, out)
	var hop_p := (now - _code_hop) / HOP_S
	if hop_p >= 0.0 and hop_p < 1.0:
		out.lift = sin(hop_p * PI) * HOP_LIFT
		out.sy = 1.0 + sin(hop_p * PI) * 0.1
		out.sx = 1.0 - sin(hop_p * PI) * 0.07
		_land = now + HOP_S * (1.0 - hop_p)
	var land_p := (now - _land) / LAND_S
	if land_p >= 0.0 and land_p < 1.0:
		var squash := sin(land_p * PI) * 0.12
		out.sy = 1.0 - squash
		out.sx = 1.0 + squash * 0.8
	var shake_p := (now - _shake) / SHAKE_S
	if shake_p >= 0.0 and shake_p < 1.0:
		out.shake = sin(now * 47.0) * (1.0 - shake_p)
	var flinch_p := (now - _flinch) / FLINCH_S
	if flinch_p >= 0.0 and flinch_p < 1.0:
		var give := sin(flinch_p * PI) * FLINCH
		out.sy *= 1.0 - give
		out.sx *= 1.0 + give * 0.6
	var lurch_p := (now - _lurch) / LURCH_S
	if lurch_p >= 0.0 and lurch_p < 1.0:
		var swell := sin(lurch_p * PI) * LURCH
		out.sx *= 1.0 + swell
		out.sy *= 1.0 + swell
	return out


func _shot_frame(now: float, out: Dictionary) -> bool:
	if _shot == "":
		return false
	var a := Sprites.action(sheet, _shot)
	var p := (now - _shot_t0) * float(a.fps)
	var last: int = int(a.count) - 1
	var f := floori(p)
	if _shot_to >= 0:
		f = _shot_to - absi(f - _shot_to) if f <= _shot_to * 2 else -1
	elif f > last:
		f = -1
	if f < 0:
		_shot = ""
		return false
	out.act = _shot
	out.frame = f
	return true


func _face_frame(now: float, out: Dictionary) -> void:
	if _dir == -1:
		var a := Sprites.action(sheet, _face)
		var f := int(a.count) - 1 - floori((now - _t0) * float(a.fps))
		if f > 0:
			out.act = _face
			out.frame = f
			return
		_face = _want
		_dir = 1
		_t0 = now
	if _face == "idle":
		_idle_frame(now, out)
		return
	var a := Sprites.action(sheet, _face)
	var last: int = int(a.count) - 1
	var f := floori((now - _t0) * float(a.fps))
	out.act = _face
	if f < last:
		out.frame = f
		return
	_dir = 0
	# a face that stays rocks between its last two frames, as long as they differ
	out.frame = last if _face == "hollow" or int((now + _phase) / HOLD_S) % 2 == 0 else last - 1
	var breath := sin((now / BREATH_S + _phase) * TAU) * 0.012
	out.sy = 1.0 + breath
	out.sx = 1.0 - breath * 0.6


## Breathing: the first frames rock back and forth, and now and then the last two blink.
func _idle_frame(now: float, out: Dictionary) -> void:
	out.act = "idle"
	if now >= _next_blink:
		if now < _next_blink + BLINK_S:
			out.frame = 5 if now < _next_blink + BLINK_S * 0.6 else 4
			return
		_next_blink = now + lerpf(BLINK_EVERY[0], BLINK_EVERY[1], fposmod(now * 7.13 + _phase, 1.0))
	var breath := (sin((now / BREATH_S + _phase) * TAU) + 1.0) * 0.5
	out.frame = 2 if breath > 0.72 else (1 if breath > 0.3 else 0)
