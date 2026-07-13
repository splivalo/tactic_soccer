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
## Extra swing speed at full power (long ball) vs a 1-cell tap — a stronger kick
## whips through a touch faster. 0.15 = +15% at full power.
@export_range(0.0, 0.6, 0.01) var kick_power_speedup := 0.15
## Skip this many seconds of the clip's wind-up so the figure does a quick
## receive-and-strike as the ball arrives, instead of cocking its leg long
## before. Higher = snappier / less anticipation. Contact sits at ~0.55s, so
## 0.42 leaves ~0.13s of leg coming through before the boot meets the ball.
@export_range(0.0, 0.55, 0.01) var pass_windup_skip := 0.42
@export_range(0.0, 0.55, 0.01) var strike_windup_skip := 0.3
## Per-kick random speed spread, so passes at the same distance still aren't
## identically timed. Kept small so the anticipation timing stays tight.
@export_range(0.0, 0.4, 0.01) var kick_speed_jitter := 0.06
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
var _acting := false  # mid kick/jog — see is_busy()
## Which clips actually exist in the library (the left-foot mirrors may be absent
## if the mirror self-check failed at build time — we fall back to right foot).
var _available := {}


func is_goalkeeper() -> bool:
	return _is_gk


## True while playing a kick/jog — main.gd's ball-tracking leaves these alone so
## the action's own facing (toward the target) isn't fought.
func is_busy() -> bool:
	return _acting


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
		_available[a] = true


## Called once after spawn. Picks the right resting animation and desyncs it.
func setup(goalkeeper: bool) -> void:
	_is_gk = goalkeeper
	idle(true)


## Return to (or start) the resting pose. `desync` randomises phase + speed so
## neighbouring players never share the exact same breath.
func idle(desync: bool = false) -> void:
	if _ap == null:
		return
	_acting = false
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
	_acting = true
	_set_root_motion(true)  # strip forward travel; the tween owns the cell move
	_ap.speed_scale = 1.0
	_ap.play("jog", action_blend)


## Play a kick and await the boot-meets-ball instant. The caller does:
##     await rig.kick("pass", power, left); launch_the_ball()
## so the ball leaves exactly on contact. `power` (0..1) is how far the ball
## travels — it picks the swing strength (gentle tap -> full swing) and nudges
## the speed. `left` uses the left foot (ball arriving from the left). The clip
## keeps playing its follow-through and auto-returns to idle when finished.
func kick(kind: String, power: float = 1.0, left: bool = false) -> void:  # kind: "pass" | "strike"
	if _ap == null:
		return
	_acting = true
	_set_root_motion(true)  # kicks may lunge forward; keep the figure on its cell
	var is_strike := kind == "strike"
	var clip := _pick_clip(kind, power, left)
	var skip: float = strike_windup_skip if is_strike else pass_windup_skip
	# Softer base for passes; stronger/longer kicks whip through a touch faster,
	# plus a little random spread so equal-distance passes aren't identical.
	var base_speed: float = strike_speed if is_strike else pass_speed
	base_speed *= 1.0 + power * kick_power_speedup
	var speed: float = base_speed * randf_range(1.0 - kick_speed_jitter, 1.0 + kick_speed_jitter)
	_ap.speed_scale = 1.0
	_ap.play(clip, action_blend, speed)
	_ap.seek(skip, true)  # start past the wind-up: a quick strike, not a long cock
	# Contact time is authored at 1x, so scale the remaining wait by the speed.
	var contact: float = strike_contact_time if is_strike else pass_contact_time
	await get_tree().create_timer(maxf(contact - skip, 0.02) / speed).timeout
	kick_contact.emit()


# Chooses the clip from the swing-strength ladder and the kicking foot, falling
# back to the right foot if a mirror clip wasn't built.
func _pick_clip(kind: String, power: float, left: bool) -> String:
	var base := "strike"
	if kind != "strike":
		if power < 0.34:
			base = "pass_soft2"   # 1-2 cells: gentle tap
		elif power < 0.67:
			base = "pass_soft"    # mid-range
		else:
			base = "pass"         # long ball: full swing
	if left and _available.has(base + "_L"):
		return base + "_L"
	return base


## How long (s) from the START of a kick until the boot meets the ball, at this
## kick's nominal speed. main.gd uses it to start the windup EARLY so the ball is
## struck the instant it arrives — a one-touch pass with no dead stop.
func contact_delay(kind: String, power: float = 1.0) -> float:
	var is_strike := kind == "strike"
	var base: float = strike_speed if is_strike else pass_speed
	base *= 1.0 + power * kick_power_speedup
	var contact: float = strike_contact_time if is_strike else pass_contact_time
	var skip: float = strike_windup_skip if is_strike else pass_windup_skip
	return maxf(contact - skip, 0.02) / maxf(base, 0.05)


## Goalkeeper reaction when a shot beats him.
func gk_miss() -> void:
	if _ap == null:
		return
	_ap.speed_scale = 1.0
	_ap.play("gk_miss", action_blend)


func _on_finished(anim: StringName) -> void:
	# One-shots (any pass variant / strike / GK dive) settle back into idle.
	var n := String(anim)
	if n.begins_with("pass") or n.begins_with("strike") or n == "gk_miss":
		idle()


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null
