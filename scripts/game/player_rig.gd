class_name PlayerRig
extends Node3D

## Drives ONE player's Mixamo animation set. Attached to player_rigged.tscn.
## main.gd owns the game flow and grid position; this owns only what the body
## is doing (idle / jog / kick / GK) and — crucially — signals the exact frame
## the boot meets the ball so the ball launches in sync, never off a dead foot.

## Fires at the foot-ball contact moment inside a kick (see kick()).
signal kick_contact

## The two standing idles. Outfield players randomly get one of these AND a
## random phase + speed, so a whole team never breathes in lockstep.
const IDLE_CLIPS := ["idle", "idle_breath"]

## Seconds into each kick clip when the boot actually meets the ball. Measured
## from the clips (pass reach-peak ~40%, strike ~46%); exported so you can nudge
## them by eye until the launch looks glued to the foot.
@export var pass_contact_time := 0.55
@export var strike_contact_time := 0.56
## Playback speed of the kicks. Passes below 1.0 read as a gentle push-pass
## instead of an aggressive strike; the shot stays punchy at ~1.0.
@export_range(0.4, 1.5, 0.01) var pass_speed := 0.72
@export_range(0.4, 1.5, 0.01) var strike_speed := 1.0
## Per-kick random speed spread, so a team never plays the exact same pass twice
## (the one clip, but never identically timed).
@export_range(0.0, 0.4, 0.01) var kick_speed_jitter := 0.16
## ±fraction of idle playback speed, so idles drift out of phase over time.
@export_range(0.0, 0.3, 0.01) var idle_speed_jitter := 0.08
## Crossfade times (s) between states — short so turns stay snappy.
@export var idle_blend := 0.3
@export var action_blend := 0.12

## The hips carry forward travel in the jog/kick clips; treated as root motion
## those animate IN PLACE (our tween owns the cell). But the idles need their
## hip sway APPLIED or the planted feet skate — so root motion is toggled per
## clip, on for locomotion, off for idles.
const HIPS_TRACK := "Skeleton3D:mixamorig_Hips"

var _ap: AnimationPlayer
var _is_gk := false
## Every pass-family clip (pass, pass_soft, pass_mirror, ...). A pass picks one
## at random so a team never shows the exact same swing/foot twice in a row.
var _pass_pool: PackedStringArray = []


func is_goalkeeper() -> bool:
	return _is_gk


func _set_root_motion(on: bool) -> void:
	if _ap != null:
		_ap.root_motion_track = NodePath(HIPS_TRACK) if on else NodePath("")


func _ready() -> void:
	_ap = _find_ap(self)
	if _ap == null:
		push_warning("PlayerRig on '%s' found no AnimationPlayer." % name)
		return
	_ap.animation_finished.connect(_on_finished)
	for a in _ap.get_animation_list():
		if a.begins_with("pass"):
			_pass_pool.append(a)


## Called once after spawn. Picks the right resting animation and desyncs it.
func setup(goalkeeper: bool) -> void:
	_is_gk = goalkeeper
	idle(true)


## Return to (or start) the resting pose. `desync` randomises phase + speed so
## neighbouring players never share the exact same breath.
func idle(desync: bool = false) -> void:
	if _ap == null:
		return
	_set_root_motion(false)  # idles keep their hip sway so feet stay planted
	var clip: String = "gk_idle" if _is_gk else IDLE_CLIPS[randi() % IDLE_CLIPS.size()]
	var jitter := 0.0
	if desync:
		jitter = randf_range(-idle_speed_jitter, idle_speed_jitter)
	_ap.speed_scale = 1.0 + jitter
	_ap.play(clip, idle_blend)
	if desync:
		_ap.seek(randf() * _ap.get_animation(clip).length, true)


## Loop the run cycle while the figure tweens between cells.
func jog() -> void:
	if _ap == null or _is_gk:
		return
	_set_root_motion(true)  # strip forward travel; the tween owns the cell move
	_ap.speed_scale = 1.0
	_ap.play("jog", action_blend)


## Play a kick and await the boot-meets-ball instant. The caller does:
##     await rig.kick("pass"); launch_the_ball()
## so the ball leaves exactly on contact. The clip keeps playing its
## follow-through; it auto-returns to idle when finished.
func kick(kind: String) -> void:  # "pass" | "strike"
	if _ap == null:
		return
	_set_root_motion(true)  # kicks may lunge forward; keep the figure on its cell
	# Pick a random pass pose (dampened / mirrored foot); shot stays the strike.
	var clip := kind
	if kind == "pass" and not _pass_pool.is_empty():
		clip = _pass_pool[randi() % _pass_pool.size()]
	# Softer, slightly-random speed so the pass isn't a violent identical strike.
	var base_speed: float = pass_speed if kind == "pass" else strike_speed
	var speed: float = base_speed * randf_range(1.0 - kick_speed_jitter, 1.0 + kick_speed_jitter)
	_ap.speed_scale = 1.0
	_ap.play(clip, action_blend, speed)
	# Contact time is authored at 1x, so scale the wait by the actual speed.
	var contact: float = pass_contact_time if kind == "pass" else strike_contact_time
	await get_tree().create_timer(contact / speed).timeout
	kick_contact.emit()


## Goalkeeper reaction when a shot beats him.
func gk_miss() -> void:
	if _ap == null:
		return
	_ap.speed_scale = 1.0
	_ap.play("gk_miss", action_blend)


func _on_finished(anim: StringName) -> void:
	# One-shots (any pass variant / strike / GK dive) settle back into idle.
	var n := String(anim)
	if n.begins_with("pass") or n == "strike" or n == "gk_miss":
		idle()


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null
