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

## Where the RIGHT toe bone actually is, in this rig's own local space, at the
## instant of peak swing speed (see pass_contact_time/strike_contact_time) —
## measured with scripts/tools/measure_kick_contact.gd (played the clip frame
## by frame and tracked the real bone, instead of assuming the ball meets a
## generic point like the cell center). main.gd rotates this by the kicker's
## facing and adds it to their position to get the exact spot the ball should
## be at on contact, so the ball touches the boot instead of the sole/shin.
const PASS_CONTACT_OFFSET := Vector3(-0.379285, 0.150959, -0.192152)
const STRIKE_CONTACT_OFFSET := Vector3(-0.287865, 0.050565, 0.267526)

## Seconds into each kick clip when the boot actually meets the ball. Measured
## by tracking the toe bone's position relative to the hip through the whole
## clip (scripts/tools/measure_kick_contact.gd) and finding PEAK SWING SPEED —
## the instant the foot is driving fastest through where the ball would be.
## The old values (and their "~40%/~46%" comment) were actually measuring the
## leg's point of MAXIMUM REACH — the fully-stretched follow-through pose,
## which happens well AFTER real contact (0.64s/0.60s vs the real 0.33s/0.46s)
## — so the ball was launching after the boot had already swung past the ball.
## Exported so you can still nudge them by eye if it ever looks off.
@export var pass_contact_time := 0.33
@export var strike_contact_time := 0.46
## Playback speed of the kicks. Passes below 1.0 read as a gentle push-pass
## instead of an aggressive strike; the shot stays punchy at ~1.0.
@export_range(0.4, 1.5, 0.01) var pass_speed := 0.72
@export_range(0.4, 1.5, 0.01) var strike_speed := 1.0
## Extra swing speed at full power (long ball) vs a 1-cell tap — a stronger kick
## whips through a touch faster. 0.15 = +15% at full power.
@export_range(0.0, 0.6, 0.01) var kick_power_speedup := 0.15
## Skip this many seconds of the clip's wind-up so the figure does a quick
## receive-and-strike as the ball arrives, instead of cocking its leg long
## before. Higher = snappier / less anticipation, but too high hides the leg
## swing entirely so the strike doesn't read as hitting the ball. Pass contact
## sits at 0.33s (0.15 leaves ~0.18s of leg coming through); strike at 0.46s
## (0.18 leaves ~0.28s).
@export_range(0.0, 0.33, 0.01) var pass_windup_skip := 0.15
@export_range(0.0, 0.46, 0.01) var strike_windup_skip := 0.18
## Per-kick random speed spread, so passes at the same distance still aren't
## identically timed. Kept small so the anticipation timing stays tight.
@export_range(0.0, 0.4, 0.01) var kick_speed_jitter := 0.06
## Real seconds the follow-through (contact -> clip end) is fast-forwarded to
## once kick_contact fires. The ball is already gone by then — without this,
## the arms just ride out the mocap's own slow natural recovery at normal
## speed and hang raised for a long time (reads as the figure freezing
## mid-swing). Small, not zero: still plays the actual end pose, just quickly.
@export_range(0.05, 0.4, 0.01) var follow_through_time := 0.15
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

## Calm turn rate (deg/s) when settling toward a facing between turns.
@export var turn_speed := 200.0

var _ap: AnimationPlayer
var _is_gk := false
var _acting := false  # mid kick/jog — see is_busy()
# A settle-turn requested by main (face the ball / return to formation).
var _target_yaw := 0.0
var _turning := false
var _turn_delay := 0.0
## Which clips actually exist in the library (the left-foot mirrors may be absent
## if the mirror self-check failed at build time — we fall back to right foot).
var _available := {}


func is_goalkeeper() -> bool:
	return _is_gk


## True while playing a kick/jog — settle-turns wait for the action to finish so
## its own aim isn't fought.
func is_busy() -> bool:
	return _acting


## Request a calm turn toward `yaw` (radians), after an optional stagger `delay`
## (s). main calls this on each settle so nearby players face the ball and the
## rest ease back to formation — not a continuous in-place sunflower spin.
func turn_to(yaw: float, delay: float = 0.0) -> void:
	_target_yaw = yaw
	_turn_delay = delay
	_turning = true


func _process(delta: float) -> void:
	if not _turning or _acting:
		return
	if _turn_delay > 0.0:
		_turn_delay -= delta
		return
	var diff := angle_difference(rotation.y, _target_yaw)
	var step := deg_to_rad(turn_speed) * delta
	if absf(diff) <= step:
		rotation.y = _target_yaw
		_turning = false
	else:
		rotation.y += clampf(diff, -step, step)


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


## Rolls one random speed-jitter factor for a kick. Call ONCE per kick and pass
## the same value to both contact_delay() (used to schedule the windup start)
## and kick() (used to actually play it) — otherwise the two independently
## roll their own randomness, and the predicted vs. actual contact instant
## drift apart by up to kick_speed_jitter, which reads as the boot missing the
## ball (sometimes early, sometimes late, never quite lined up).
func roll_kick_jitter() -> float:
	return randf_range(1.0 - kick_speed_jitter, 1.0 + kick_speed_jitter)


## Play a kick and await the boot-meets-ball instant. The caller does:
##     await rig.kick("pass", power, left); launch_the_ball()
## so the ball leaves exactly on contact. `power` (0..1) is how far the ball
## travels — it picks the swing strength (gentle tap -> full swing) and nudges
## the speed. `left` uses the left foot (ball arriving from the left). `jitter`
## must be the SAME value passed to contact_delay() for this kick (see
## roll_kick_jitter) so the actual contact lands exactly when scheduled. The
## clip keeps playing its follow-through and auto-returns to idle when finished.
func kick(kind: String, power: float = 1.0, left: bool = false, jitter: float = 1.0) -> void:  # kind: "pass" | "strike"
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
	var speed: float = base_speed * jitter
	_ap.speed_scale = 1.0
	_ap.play(clip, action_blend, speed)
	_ap.seek(skip, true)  # start past the wind-up: a quick strike, not a long cock
	# Contact time is authored at 1x, so scale the remaining wait by the speed.
	var contact: float = strike_contact_time if is_strike else pass_contact_time
	await get_tree().create_timer(maxf(contact - skip, 0.02) / speed).timeout
	kick_contact.emit()
	_fast_forward_follow_through(clip, speed)


## Contact just happened — the ball is away. Ramp playback speed up (never
## down) so the remaining clip-time to the animation's own end plays out in
## about follow_through_time real seconds instead of at normal kick speed,
## then the usual animation_finished -> idle() blend takes it from there.
func _fast_forward_follow_through(clip: String, current_speed: float) -> void:
	if _ap == null or _ap.current_animation != clip:
		return
	var remaining: float = maxf(_ap.current_animation_length - _ap.current_animation_position, 0.05)
	_ap.speed_scale = maxf(remaining / follow_through_time, current_speed)


## The measured contact offset (local space, relative to this rig's own
## position/facing) for a kick of this `kind`. `left` mirrors the X component,
## since the "_L" clips are the right-foot clip mirrored across the body.
func get_contact_offset(kind: String, left: bool) -> Vector3:
	var offset: Vector3 = STRIKE_CONTACT_OFFSET if kind == "strike" else PASS_CONTACT_OFFSET
	if left:
		offset.x = -offset.x
	return offset


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
## struck the instant it arrives — a one-touch pass with no dead stop. `jitter`
## must be the same value later passed to kick() (see roll_kick_jitter).
func contact_delay(kind: String, power: float = 1.0, jitter: float = 1.0) -> float:
	var is_strike := kind == "strike"
	var base: float = strike_speed if is_strike else pass_speed
	base *= 1.0 + power * kick_power_speedup
	var speed: float = base * jitter
	var contact: float = strike_contact_time if is_strike else pass_contact_time
	var skip: float = strike_windup_skip if is_strike else pass_windup_skip
	return maxf(contact - skip, 0.02) / maxf(speed, 0.05)


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
