extends Node3D

## Sandbox for the turn-based football game.
## Uses the `stadium` node YOU placed in the scene (main.tscn) — it does NOT
## spawn its own. It reads the imported `field` mesh to line the logical 7x10
## grid (Board) up with wherever you put the stadium, and can optionally draw a
## debug overlay of the 70 cells so you can eyeball the mapping.

# --- Grid debug overlay (OFF by default so it never clutters your scene) ------
@export var show_grid_debug := false
@export var label_cells := false

# --- Teams -------------------------------------------------------------------
@export var spawn_teams := true
## Rigged Mixamo character (built by scripts/tools/build_player.gd). Carries the
## full animation set + PlayerRig controller. Revert to the old static
## player.glb here if you ever need the pre-animation look.
@export var player_scene: PackedScene = load("res://scenes/player_rigged.tscn")
@export var home_country := "Croatia"
@export var away_country := "Brazil"
@export var player_scale := 1.0
## Correction if the model's "front" isn't already +Z (home faces -Z, away +Z).
@export var player_facing_offset := 0.0
## A MOVE now slides like a shot (straight line, any distance to the first
## obstruction — see MatchState.move_targets), not just one cell, so the jog
## needs to cover that ground at a believable running pace instead of the old
## fixed 0.28s tween (which read as a teleport/skate for anything longer than
## 1 cell). Duration = max(move_min_duration, move_duration_per_cell * cells);
## the min keeps a 1-cell move feeling exactly like it always did.
@export var move_duration_per_cell := 0.22
@export var move_min_duration := 0.35
## The "jog" clip has no baked forward speed of its own (in-place treadmill
## cycle — see PlayerRig.jog's doc comment), so distance/urgency has to be
## sold by the STRIDE RATE instead: a short 1-cell hop plays relaxed, a long
## cross-pitch run plays with a faster, more urgent cadence. Ramps linearly
## from jog_speed_scale_min at 1 cell to jog_speed_scale_max at
## jog_speed_scale_max_cells (and clamps beyond that).
@export var jog_speed_scale_min := 0.85
@export var jog_speed_scale_max := 1.35
@export var jog_speed_scale_max_cells := 8
## Kick strength scales with distance ("broj polja"). A 1-cell ball is a soft
## tap (power 0); at this many cells or more it's a full-power kick (power 1).
@export var full_power_cells := 7
## The FINAL shot uses the powerful 'strike' if it travels at least this many
## cells (or scores); shorter tap-in shots stay a normal pass swing.
@export var shot_strike_cells := 4
## Ball travel pace by power: gentle (short/soft) rolls slow, strong (long) balls
## fly. Interpolated by the distance-driven power. >1 = slower, <1 = snappier.
@export var ball_pace_gentle := 1.9
@export var ball_pace_strong := 0.55
## Per-segment ball travel time = clamp(distance * ball_roll_time_scale *
## ball_pace, ball_roll_min_duration, ball_roll_max_duration) — see
## _roll_dur. The MAX especially matters now that passes can cross the whole
## pitch in one hop (unlimited sliding movement): without a generous ceiling,
## a cross-pitch ball and a 2-cell tap take almost the same time, so a long
## pass never actually reads as covering real distance.
@export var ball_roll_time_scale := 0.065
@export var ball_roll_min_duration := 0.12
@export var ball_roll_max_duration := 1.1
## Flip if the kicking foot ends up on the wrong side for the incoming ball.
@export var invert_kick_foot := false
## Minimum time (s) for the opening roll to the first figure, so it has room for
## the (now short) wind-up and strikes the ball on arrival rather than waiting.
@export var first_touch_windup := 0.3
## How high a full-power ball lofts at mid-flight (world units). Scales with the
## hop's power, so short balls stay on the ground and long balls arc over.
@export var max_ball_arc := 0.7

# --- Ball --------------------------------------------------------------------
@export var spawn_ball := true
@export var ball_scene: PackedScene = load("res://assets/models/ball.glb")
@export var ball_start_cell := Vector2i(3, 8) # empty cell by the home GK (ball never sits on a figure)
@export var ball_scale := 1.0
@export var goals_to_win := 2 # match ends when a team reaches this
## Seconds a team has for its WHOLE turn — COMBO (build+shoot) and the MOVE or
## REMOVE that follows it share this one pool, however the player splits their
## thinking between the two, instead of each phase getting its own separate
## clock. Runs out with no move made = forfeit. Keeps ticking in real time even
## behind the pause modal, so pausing can't be used to stall the clock.
## 40s, raised from 30s (2026-07-28): one budget for the WHOLE turn is the
## right model — the player sees a single number and budgeting it is part of
## the skill — but a combo can run to several passes before the shot is even
## chosen, and letting the MOVE half of the turn expire is now a bookable
## offence (see MatchState.forfeit), so there has to be room to think about
## the attack without the clock turning that into a card.
@export var turn_time_limit := 40.0

## Shorter than a normal turn on purpose: picking which of your own to lose is
## one tap on a board where every choice is already lit, not a decision to plan.
## The full 40 here would leave the other player waiting through a punishment
## that isn't theirs.
@export var remove_time_limit := 15.0
## Loudness of the countdown tick (assets/audio/sfx/timer.mp3) — one play per
## whole-second tick while the HUD's big center-pitch countdown is showing
## (see hud.gd's TIMER_URGENT_AT / _update_turn_timer_display below). Same
## tuning knob pattern as goal_sfx_volume_db/kick_sfx_volume_db.
@export_range(-24.0, 24.0, 0.5) var timer_tick_volume_db := 0.0
## Loudness of the referee whistle (assets/audio/sfx/whistle.mp3), played on
## a yellow or red card (see _after_combo's card branches below) — same
## tuning knob pattern as the other Match SFX volumes.
@export_range(-24.0, 24.0, 0.5) var whistle_sfx_volume_db := 0.0
## Loudness of board-tap feedback (assets/audio/sfx/field_tap.mp3) — see
## FIELD_TAP_SOUND / _move_click. Boosted like kick_sfx_volume_db (the
## source clip reads very quiet at 0dB, near-inaudible per a real playtest)
## — Godot doesn't expose a way to measure a stream's actual loudness from
## GDScript (AudioStreamPlayback.mix() isn't scriptable for MP3 playback),
## so this is an estimate; pulled back from the original 14dB guess (that
## read as too loud in practice) — nudge further if it's still off.
@export_range(-24.0, 24.0, 0.5) var field_tap_volume_db := 5.0

# --- Path debug --------------------------------------------------------------
## Green markers = every cell the piece on `reach_from_cell` could shoot the
## ball to (straight lines, stopping before the first other piece).
@export var show_reach_debug := false
@export var reach_from_cell := Vector2i(3, 7)

# --- Optional test figure ----------------------------------------------------
@export var spawn_test_character := false
@export var character_scene: PackedScene = load("res://assets/models/player.glb")
@export var character_cell := Vector2i(3, 5) # (col, row) on the 7x10 grid
@export var character_facing_offset := 0.0
@export var character_scale := 1.0

# --- Appearance test ----------------------------------------------------------
@export var test_country := "Croatia"
@export_enum("home", "away") var test_kit_variant := "home"
@export var test_hair_index := 0
@export var test_number := 7

# --- Banner fix --------------------------------------------------------------
## The banner texture stores its text only in the alpha channel (black RGB), so
## the OPAQUE material renders solid black. We rebake it as an opaque plate:
## a solid background with the text painted on top.
@export var fix_banner := true
@export var banner_bg := Color("f4c20d") # jersey/ad yellow
@export var banner_text := Color("101010") # near-black text

# --- Stadium dressing ----------------------------------------------------------
## The stadium.glb "crowd dressing" — stands bowl, fence, sponsor banner, seat
## rows, floodlight rig — everything except the pitch/lines/goal frames+nets
## (those stay visible always; they're the actual playing surface). On tall
## phone aspect ratios a sliver of the dressing always peeked in at the screen
## edges during normal top-down play, competing with the HUD for attention —
## not worth it outside the one moment it's actually a nice backdrop: the goal
## cinematic pull-back. Hidden by default; _begin_goal_drama/_restore_camera
## reveal/re-hide it around that cinematic.
@export var hide_stadium_dressing_during_play := true
const STADIUM_DRESSING := ["arena", "fence", "banner", "seats", "reflectors"]

# --- Goal cinematic ----------------------------------------------------------
## On a goal: an EDIT, not a moving/rotating shot — two STATIC cameras, hard-cut
## between them, like a broadcast replay. No camera ever rotates or tweens
## mid-shot; all the energy comes from the ball's own motion crossing a locked
## frame plus the cut itself. Cam A ("launch") is set once, behind the shooter
## looking down the shot line; partway through the flight we hard-cut to Cam B
## ("net"), parked beside the goal mouth watching the ball arrive and hit the
## net. Both are positioned once per goal from the shot axis (shooter cell ->
## goal, see _begin_goal_drama's _goal_shot_dir/_goal_side_dir), so the angles
## read the same regardless of which column/angle the shot came from.
@export_group("Goal Cinematic")
@export var enable_goal_cam := true
@export var goal_cam_hold := 1.8           # seconds to hold on Cam B (after impact, normal speed)
## Cam A ("launch"): set ONCE at the moment of the strike — behind the shooter
## along the shot axis (goal_cam_back back, goal_cam_side to the side for an
## over-the-shoulder angle instead of dead-center-behind), looking toward the
## goal. Never moves again; the ball racing away IS the motion.
@export var goal_cam_back := 2.5           # how far behind the shooter, along the shot axis
@export var goal_cam_side := 1.3           # sideways (over-the-shoulder) offset, perpendicular to the shot axis
@export var goal_cam_side_sign := 1.0      # flip to -1.0 if the shoulder offset ends up on the awkward side
## Camera height ABOVE THE PITCH SURFACE (not world Y=0) — keep this clear of
## BOTH the stands (seats mesh spans world Y 0.6-2.2) AND the floodlight towers
## (reflectors span world Y 2.6-4.0) — total must stay under ~2.6 (this + the
## ~0.83 base) or it clips straight into a reflector tower.
@export var goal_cam_height := 1.5
@export var goal_cam_fov := 62.0 # wide at the start — the keeper's dive fires the instant the shot is struck, but a tight FOV cropped it out of frame until the camera panned in
@export_range(0.0, 0.5, 0.01) var goal_cam_blur := 0.12  # background DoF (0 = off)
## Cam B ("net"): set once, parked to the side of the goal MOUTH at net height,
## looking back across it — a fixed broadcast-style goal-line angle the ball
## flies INTO. goal_cam2_depth is measured along the shot axis, negative =
## pulled back from the goal line into the pitch a bit (avoids sitting inside
## the net mesh); goal_cam2_side is perpendicular to the axis, same as Cam A's.
@export var goal_cam2_side := 3.6
@export var goal_cam2_depth := -3.0
@export var goal_cam2_height := 1.4
@export var goal_cam2_fov := 50.0
## Ball progress (0 = still at the shooter, 1 = at the goal) along the shot
## axis at which we hard-cut from Cam A to Cam B — cutting partway through the
## flight, not right at the strike, so Cam A gets to establish before the cut.
@export_range(0.1, 0.95, 0.01) var goal_cam_cut_progress := 0.6
## Time scale WHILE THE BALL IS IN FLIGHT toward goal (1 = no slow-mo). Snaps
## back to normal speed the instant the ball reaches the net — the impact,
## fall, and keeper reaction all play at normal speed, not in slow motion.
@export_range(0.15, 1.0, 0.05) var goal_slowmo := 0.28
## Cam B slowly pushes in (FOV only, never rotates/moves) from goal_cam2_fov
## to this tighter FOV once the ball has landed, for a dramatic close finish.
@export var goal_cam_zoom_fov := 22.0
## The scoring shot flies THROUGH the goal line into the net: this deep, at this
## height, with this arc — so you see the ball hit the netting, not stop on the line.
@export var net_depth := 0.5
@export var net_hit_height := 0.7
@export var goal_shot_arc := 0.9
## The net bulges where the ball hits and springs back: push distance, affected
## radius, and settle time. Needs assets/shaders/net_dent.gdshader on the nets.
@export var net_dent_strength := 0.45
@export var net_dent_radius := 0.8
@export var net_dent_time := 0.7
## After the net-hit, the ball isn't held in the air — it FALLS under gravity
## (accelerating) to the ground inside the net, then rolls back a touch toward
## the goal line as the net's give settles it (net elasticity), instead of
## freezing in place. goal_cam_hold should comfortably cover drop+roll.
@export var goal_drop_time := 0.35
@export var goal_settle_roll := 0.22
## Loudness of the goal SFX (assets/audio/sfx/goal.mp3), played the instant
## the ball reaches the net (see _celebrate_goal) — same tuning knob pattern
## as PlayerRig's kick_sfx_volume_db, so both can be balanced against each
## other by ear once there's more than one sound in the game.
@export_range(-24.0, 24.0, 0.5) var goal_sfx_volume_db := 0.0
@export_group("")

# --- Goal replay ---------------------------------------------------------------
## ONE more beat after the cinematic above finishes: a fixed top-down
## broadcast-style replay of the FULL build-up (every pass in the chain, not
## just the final strike) in slow motion — fullscreen, HUD hidden, a blinking
## "R" in the corner. Purely visual: match state is already fully applied
## (see execute_combo/_do_combo) — this just re-tweens the ball back along its
## already-recorded path under a second, different, single static camera.
@export_group("Goal Replay")
@export var enable_goal_replay := true
@export_range(0.05, 1.0, 0.05) var replay_slowmo := 0.18
## Straight down, centred over the pitch. Only the ANGLE (locked, straight
## down) and FOV are author-set here — the HEIGHT auto-fits every screen from
## replay_fov + camera_fit_margin, same principle as the main camera's own
## fit (see _fit_camera): never a fixed guessed distance that ends up
## cropping the pitch on some aspect ratio.
@export var replay_fov := 40.0
@export var replay_hold_after := 0.5 # pause on the settled ball before cutting back
@export_range(0.5, 4.0, 0.1) var replay_r_blink_hz := 2.0
## Broadcast-style "cut to replay": a quick white flash, at NORMAL speed
## (before the slow-mo kicks in), the instant the top-down camera cuts in.
@export_range(0.0, 0.6, 0.01) var replay_flash_time := 0.15
## Colour drained from the replay's OWN camera only (a duplicate of the main
## WorldEnvironment, so lighting/sky stay identical) — 1 = normal colour,
## 0 = full black & white. Broadcast replays read as "replay" partly from
## this even before you consciously notice the R/slow-mo.
@export_range(0.0, 1.0, 0.05) var replay_saturation := 0.35
@export_range(0.0, 1.0, 0.05) var replay_vignette_strength := 0.55
@export_group("")

# --- Grid alignment ----------------------------------------------------------
## The logical grid is mathematically centred on the field mesh's geometry (a
## true 7x10 of 1.0-unit cells), so cell centres land dead-centre of each cell.
## But if the CHECKERBOARD pattern painted onto the imported field mesh sits a
## hair off from that geometric centre, EVERYTHING placed by cell (players,
## ball, all FX tiles, own-team markers — they all go through _cell_world) will
## look slightly shifted from the visual squares. This nudges the whole grid
## origin in world XZ so you can line them all up by eye against the squares —
## one knob, shifts everything together (no per-element offset to keep in sync).
@export var grid_visual_offset := Vector2.ZERO

# --- Camera auto-fit ---------------------------------------------------------
## Keeps the field fully visible (and not too small) on every screen aspect.
## YOU tune the camera's angle/composition in the editor; this only slides the
## camera along its own view axis so the whole field always fits.
@export var enable_camera_fit := true
## Extra breathing room around the field (0.08 = 8% padding).
@export_range(0.0, 0.5, 0.01) var camera_fit_margin := 0.08

# World-space centre + surface height of the pitch (read from the scene stadium).
var _grid_origin := Vector3.ZERO
# The imported field mesh (used for grid alignment).
var _field_mesh: MeshInstance3D = null
# Everything the camera fit must keep fully on-screen: the pitch PLUS the goal
# frames/nets, which stick out past the pitch's own bounding box — fitting the
# pitch alone doesn't guarantee a goal can't clip off-screen on an off-centre
# composition (e.g. camera pushed up to leave room for a HUD).
var _fit_meshes: Array[MeshInstance3D] = []

# Pure game logic lives in MatchState; the view below just mirrors it.
var _state: MatchState = null
var _hud: Control = null # HUD/Hud — shields, score, card counts (see _refresh_hud)
var _turn_timer: Timer = null # per-turn pooled countdown (see _refresh_turn_view / _on_turn_timeout)
var _pool_team := "" # which team the running _turn_timer pool belongs to (see _refresh_turn_view)
var _pool_seconds_left := 0.0 # snapshot of the pool while _turn_timer is stopped mid-combo-animation
var _shown_time_left := -1 # last whole-second value pushed to the HUD (avoid redundant sets)
var _node_at: Dictionary = {} # Vector2i(cell) -> Node3D (figure standing there)
var _ball: Node3D = null
var _ball_last_pos := Vector3.ZERO  # for rolling-spin (see _spin_ball)
var _move_from := Vector2i(-1, -1) # figure selected to move (view only)
# True once the human has tapped a NON-ball-adjacent figure with an empty
# chain (see _combo_tap) — declining the ball this turn in favour of just
# moving that figure. From there, input handling (_on_release/
# _move_click) treats it exactly like Phase.MOVE's tap flow even though
# _state.phase is still COMBO, and _apply_move's `as_hold` gets this value so
# the move actually goes through MatchState.hold_and_move instead of
# do_move. Reset once the hold-move completes, or the player deselects by
# tapping the same figure again (see _move_click).
var _holding := false
var _busy := false # true while the ball animates (ignore input)
var _fx: BoardFx = null

# --- Pre-match placement (formation setup, see _start_placement) -------------
const PLACEMENT_ROLE_ORDER: Array[String] = ["gk", "field", "field", "field", "field", "field"]
var _placement_active := false
var _placement_root: Node3D = null # holds figures placed so far, freed once _build_match spawns the real teams
var _placement_index := 0 # which slot in PLACEMENT_ROLE_ORDER is being placed next
var _placement_result: Array[Dictionary] = [] # built up into GameFlow.player_formation
var _placement_kit: Dictionary = {}
var _placement_gk_side := 0
# A second, separate BoardFx layer for transient effects (offside line, etc.)
# that must NOT get wiped by the normal tap/drag redraws on _fx.
var _fx_effects: BoardFx = null
const BALL_RADIUS := 0.15 # ball.glb is 0.3 units across
const NO_CELL := Vector2i(-1, -1)

# --- Input: taps, and only taps ------------------------------------------------
# Dragging is gone (2026-08-04). It was never needed — a tap already begins a
# chain, passes, shoots, picks a figure up, moves it and removes it — and it
# cost more than it gave: on a phone the tap/drag threshold was smaller than the
# roll of a thumb, so ordinary taps arrived as drags, and the snap radius was
# nearly a whole tile, so a finger still resting on a figure had already latched
# onto the square beside it. Tapping a man to select him walked him off on his
# own. One input path cannot disagree with itself.
var _pressed := false
var _press_screen_pos := Vector2.ZERO
const TAP_HIT_RADIUS := 0.55 # world units — forgiveness for a tap
const FIGURE_HEIGHT := 1.6 # a bit over the model's real height (~1.45 @ scale 1)

# --- Board FX (tunable in the Inspector on this node) -------------------------
# All feedback uses the same rounded-square tile shape (see BoardFx), just
# different colours, so it reads as one visual language.
@export_group("Board FX Colors")
@export var color_move := Color(0.28, 1.0, 0.45, 0.9) # move target cell
@export var color_shoot := Color(0.30, 1.0, 0.5, 0.9) # shoot target cell
@export var color_tap := Color(0.30, 0.65, 1.0, 0.95) # blue: a man you can WALK — never one the ball can go through

## The "these are yours" pool under each figure of the team on the move.
##
## Was a very dark green (0.09, 0.20, 0.08) on green grass, which is close to no
## contrast at all — it read as the figure's shadow rather than as a marker, and
## with a chain running it was the only thing left saying which men were yours.
## Pale rather than dark for that reason: white is the one hue no action colour
## uses, so it separates from the pitch without competing with orange or blue.
## Alpha stays low so an FX tile landing on the same cell still overpowers it.
##
## Set from code (see _set_own_marker_visible) rather than in player_rigged.tscn,
## so it stays tunable here alongside the colours it has to sit beside.
@export var own_marker_color := Color(1.0, 1.0, 1.0, 0.34)
## The ONE figure currently selected/held (see _draw_move) — the original
## cyan-blue "selected mover" colour from before color_tap_selected existed
## as a separate variable, so it stands out from the plain-blue tappable
## figures around it.
@export var color_tap_selected := Color(0.2, 0.95, 1.0, 0.95) # #33F2FF
@export var color_chain := Color(1.0, 0.6, 0.15, 0.95) # chosen chain figure
@export var color_trail := Color(0.45, 0.9, 1.0, 0.95) # energy trail
@export var color_remove := Color(1.0, 0.15, 0.15, 0.95) # figure removable after a red card
@export var color_offside := Color(1.0, 0.85, 0.1, 0.95) # offside line + flagged figure
@export_range(0.2, 5.0, 0.1) var offside_flash_seconds := 1.8

@export_group("Board FX Tuning")
@export var fx_tile_size := 0.82
@export var fx_pulse_hz := 1.4
@export var fx_trail_width := 0.16
@export var fx_trail_scroll := 1.6
@export var fx_dash_period := 0.5
@export_range(1.0, 12.0, 0.5) var fx_trail_density := 4.0
@export_range(0.05, 1.0, 0.01) var fx_trail_fill := 0.55
@export_enum("Dash", "Dot") var fx_trail_pattern := 0
@export_range(0.0, 3.0, 0.01) var fx_trail_emission := 0.0
@export_range(0.0, 1.0, 0.01) var fx_trail_rim := 0.6

# The camera transform you tuned in the editor — used as the fit reference.
var _cam_ref := Transform3D.IDENTITY
## The transform tuned in the editor, captured ONCE and never overwritten.
## _cam_ref is derived from it every fit, because the away-side flip depends on
## which side we turn out to be — and online, that isn't known until an opponent
## accepts, long after the first fit has run.
var _cam_authored := Transform3D.IDENTITY
var _cam_ref_set := false
# Two STATIC cinematic cameras used only during goal celebrations — see the
# "Goal Cinematic" export group's comment. Neither ever moves/rotates once
# positioned; _goal_cam_cut_done just gates the one-shot hard cut between them.
var _goal_cam: Camera3D = null   # Cam A: "launch" — behind the shooter
var _goal_cam2: Camera3D = null  # Cam B: "net" — beside the goal mouth
var _goal_cam_follow := false    # true while the flight is live (watching for the A->B cut trigger)
var _goal_cam_cut_done := false  # true once we've hard-cut from Cam A to Cam B this goal
var _goal_center := Vector3.ZERO    # goal-mouth point the cams frame
var _goal_net_point := Vector3.ZERO # where the scoring ball flies into the net
var _goal_flight_d0 := 1.0           # ball->goal distance at strike start (for zoom)
var _goal_ground_y := 0.0            # resting height inside the net (for the gravity drop)
var _goal_out_dir := 1.0             # which way "into the goal" is for this net (+1 or -1 on Z)
var _goal_cam_base_y := 0.0          # pitch-surface Y the camera height is measured from
# The shot axis (shooter cell -> goal, flattened to the pitch plane) both cams
# are built on — see _begin_goal_drama. _goal_side_dir is perpendicular to it
# (the over-the-shoulder / goal-mouth-side offset direction); _goal_shooter_flat
# /_flat_dist let the cut-trigger measure the ball's progress along the axis.
var _goal_shot_dir := Vector3(0, 0, 1)
var _goal_side_dir := Vector3(1, 0, 0)
var _goal_shooter_flat := Vector3.ZERO
var _goal_shot_flat_dist := 1.0
var _net_mats := {}                  # net node name -> its ShaderMaterial (dent)

# --- Goal replay (see the "Goal Replay" export group) -------------------------
var _replay_cam: Camera3D = null
var _replay_tag: CanvasLayer = null      # blinking "R" — separate from _hud, which gets hidden
var _replay_tag_tween: Tween = null
var _goal_replay_path: Array = []        # the last goal's full path — see _do_combo
var _goal_replay_scorer := ""            # the last goal's scoring team — for the GK dive on replay


func _ready() -> void:
	# Screens before this one (team select) store their picks on the GameFlow
	# autoload; empty string means "unset", so the @export defaults above
	# still apply when this scene is run standalone in the editor.
	if GameFlow.home_country != "":
		home_country = GameFlow.home_country
	if GameFlow.away_country != "":
		away_country = GameFlow.away_country
	_hud = get_node_or_null("HUD/Hud")
	_turn_timer = Timer.new()
	_turn_timer.name = "TurnTimer"
	_turn_timer.one_shot = true
	_turn_timer.timeout.connect(_on_turn_timeout)
	add_child(_turn_timer)
	_grid_origin = _read_field_origin() + Vector3(grid_visual_offset.x, 0.0, grid_visual_offset.y)
	_fx = BoardFx.new()
	_fx.name = "BoardFx"
	_fx.tile_size = fx_tile_size
	_fx.pulse_hz = fx_pulse_hz
	_fx.trail_width = fx_trail_width
	_fx.trail_scroll = fx_trail_scroll
	_fx.dash_period = fx_dash_period
	_fx.trail_density = fx_trail_density
	_fx.trail_fill = fx_trail_fill
	_fx.trail_pattern = fx_trail_pattern
	_fx.trail_emission = fx_trail_emission
	_fx.trail_rim = fx_trail_rim
	add_child(_fx)
	_fx_effects = BoardFx.new()
	_fx_effects.name = "BoardFxEffects"
	_fx_effects.tile_size = fx_tile_size
	_fx_effects.pulse_hz = fx_pulse_hz
	_fx_effects.trail_width = fx_trail_width
	_fx_effects.trail_scroll = fx_trail_scroll
	_fx_effects.dash_period = fx_dash_period
	_fx_effects.trail_density = fx_trail_density
	_fx_effects.trail_fill = fx_trail_fill
	_fx_effects.trail_pattern = fx_trail_pattern
	_fx_effects.trail_emission = fx_trail_emission
	_fx_effects.trail_rim = fx_trail_rim
	add_child(_fx_effects)
	_setup_match_sfx()
	_setup_crowd_ambience()
	_setup_running_sfx()
	if fix_banner:
		_fix_banner()
	if hide_stadium_dressing_during_play:
		_set_stadium_dressing_visible(false)
	if enable_camera_fit:
		get_viewport().size_changed.connect(_fit_camera)
		_fit_camera_deferred()
	if enable_goal_cam:
		_setup_goal_cam()
		_setup_nets()
	if enable_goal_replay:
		_setup_replay_cam()
		_setup_replay_tag()
	if spawn_teams:
		_spawn_teams()
	if spawn_ball:
		_spawn_ball()
	if spawn_test_character:
		_spawn_character()
		_apply_test_appearance()
	if show_reach_debug:
		_build_reach_debug()
	if show_grid_debug:
		_build_grid_debug()
	# Players now drive their own animation (PlayerRig); no blanket autoplay.


# --- Field / grid ------------------------------------------------------------
# World position of grid cell (col,row), relative to the placed field.
func _cell_world(col: int, row: int) -> Vector3:
	return _grid_origin + Board.grid_to_world(col, row) - Vector3(0, Board.SURFACE_Y, 0)


# Reads the `field` mesh from the scene's `stadium` node: returns its world
# centre with Y at the top surface. Falls back to origin if not found.
func _read_field_origin() -> Vector3:
	var stadium := get_node_or_null("stadium")
	if stadium == null:
		push_warning("No 'stadium' node in the scene — place stadium.glb as a child named 'stadium'.")
		return Vector3.ZERO
	var field := _find_node_named(stadium, "field") as MeshInstance3D
	if field == null:
		push_warning("No 'field' mesh under the stadium — check the object name in the glb.")
		return Vector3.ZERO
	_field_mesh = field
	_fit_meshes = [field]
	var lines_mesh := _find_node_named(stadium, "field_lines") as MeshInstance3D
	if lines_mesh != null:
		_fit_meshes.append(lines_mesh) # now bigger than `field` itself — keep it guaranteed on-screen too
	for goal_name in ["goal1_frame", "goal2_frame", "goal1_net", "goal2_net"]:
		var goal_mesh := _find_node_named(stadium, goal_name) as MeshInstance3D
		if goal_mesh != null:
			_fit_meshes.append(goal_mesh)
		else:
			push_warning("No '%s' mesh under the stadium — camera fit won't guarantee it stays on-screen." % goal_name)
	var aabb := field.get_aabb()
	var xf := field.global_transform
	var local_centre := aabb.position + aabb.size * 0.5
	var centre := xf * local_centre
	# Top surface = same centre but at the AABB's max Y.
	var top := xf * Vector3(local_centre.x, aabb.position.y + aabb.size.y, local_centre.z)
	# Verify size still matches the logical grid.
	var x_ok: bool = absf(aabb.size.x - Board.COLS * Board.TILE_SIZE) < 0.05
	var z_ok: bool = absf(aabb.size.z - Board.ROWS * Board.TILE_SIZE) < 0.05
	print("GRID: field %.2fx%.2f (X x Z) => X %s, Z %s"
		% [aabb.size.x, aabb.size.z, "OK" if x_ok else "MISMATCH", "OK" if z_ok else "MISMATCH"])
	return Vector3(centre.x, top.y, centre.z)


# --- Grid debug overlay ------------------------------------------------------
func _build_grid_debug() -> void:
	var overlay := Node3D.new()
	overlay.name = "GridDebug"
	add_child(overlay)

	var dot := SphereMesh.new()
	dot.radius = 0.06
	dot.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.9, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for row in Board.ROWS:
		for col in Board.COLS:
			var pos := _cell_world(col, row)
			var marker := MeshInstance3D.new()
			marker.mesh = dot
			marker.material_override = mat
			marker.position = pos + Vector3(0, 0.02, 0)
			marker.name = "Cell_%d_%d" % [col, row]
			overlay.add_child(marker)
			if label_cells:
				var lbl := Label3D.new()
				lbl.text = "%d,%d" % [col, row]
				lbl.font_size = 48
				lbl.pixel_size = 0.004
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lbl.outline_size = 8
				lbl.position = pos + Vector3(0, 0.25, 0)
				overlay.add_child(lbl)


# --- Match setup (view builds nodes; MatchState owns the logic) --------------
func _spawn_teams() -> void:
	if player_scene == null:
		push_warning("No player_scene assigned — cannot spawn teams.")
		return
	_state = MatchState.new()
	if GameFlow.tutorial_mode:
		_start_tutorial()
	elif GameFlow.player_formation.is_empty():
		_start_placement()
	elif GameFlow.online_mode and GameFlow.online_room == "":
		# Online with a formation already laid out but no opponent yet — this is
		# the "find another one" case after a match ended. Straight back to the
		# overlay, skipping both the country picker and the placement phase.
		_show_online_overlay()
	else:
		_start_coin_toss()


# The ball node is created inside _build_match; this stays for the _ready toggle.
func _spawn_ball() -> void:
	pass


## Whichever side is GameFlow.player_side uses the formation they just placed
## (see _start_placement); the other side (and both, before any placement has
## happened — e.g. local test runs) falls back to the fixed Formations layout.
func _my_layout() -> Array[Dictionary]:
	return _my_formation if not _my_formation.is_empty() else GameFlow.player_formation


func _home_formation() -> Array[Dictionary]:
	if GameFlow.tutorial_mode:
		return Tutorial.home_formation()
	if GameFlow.player_side == "HomeTeam" and not _my_layout().is_empty():
		return _my_layout()
	if GameFlow.player_side != "HomeTeam" and not _remote_formation.is_empty():
		return _remote_formation
	return Formations.home()


func _away_formation() -> Array[Dictionary]:
	if GameFlow.tutorial_mode:
		return Tutorial.away_formation()
	if GameFlow.player_side == "AwayTeam" and not _my_layout().is_empty():
		return _my_layout()
	if GameFlow.player_side != "AwayTeam" and not _remote_formation.is_empty():
		return _remote_formation
	return Formations.away()


# (Re)build both teams + the ball, then init or reset the logic (score kept).
func _build_match(kickoff_team: String) -> void:
	Engine.time_scale = 1.0  # always restore normal speed on a (re)build
	for node_name in ["HomeTeam", "AwayTeam", "Ball"]:
		var old := get_node_or_null(node_name)
		if old != null:
			old.free()
	_node_at.clear()
	_move_from = NO_CELL
	var kits := CountryKits.resolve_match(home_country, away_country)
	var home_formation := _home_formation()
	var away_formation := _away_formation()
	# Home defends the bottom goal (faces -Z); away defends the top (faces +Z).
	_build_team("HomeTeam", home_formation, kits["home"], 180.0)
	_build_team("AwayTeam", away_formation, kits["away"], 0.0)
	var ball_cell := _kickoff_cell(kickoff_team,
		home_formation if kickoff_team == "HomeTeam" else away_formation)
	# MatchState first, ball second. _ball_world asks _state.pieces whether a man
	# is standing on that square, to decide whether to tuck the ball into the
	# corner of it — and at this moment _state still holds the PREVIOUS match's
	# board, or nothing at all on the first build. So the kickoff ball was placed
	# against a board that didn't exist yet and always came out dead centre,
	# under whoever was standing there. That is why the corner offset looked like
	# it wasn't happening: during play it was, at kickoff it never could.
	if _state.pieces.is_empty():
		_state.setup(home_formation, away_formation, ball_cell, kickoff_team, goals_to_win)
	else:
		_state.reset(home_formation, away_formation, ball_cell, kickoff_team)
	_place_ball(ball_cell)
	# HUD names (used by the footer's team-code text) must be set before the
	# turn view reads them, or kickoff briefly shows the previous match's code.
	_refresh_hud()
	_refresh_turn_view()


# Single call point that mirrors MatchState (shields/names/score/cards) onto the HUD.
func _refresh_hud() -> void:
	if _hud != null:
		# Told before refresh: it decides which side owns the LEFT shield, so the
		# local player's crest sits on the same side as their own figures.
		_hud.set_local_side(GameFlow.player_side)
		var labels := _online_labels()
		_hud.refresh(_state, home_country, away_country, labels["home"], labels["away"])


func _build_team(team_name: String, pieces: Array[Dictionary], kit: Dictionary, facing: float) -> void:
	var root := Node3D.new()
	root.name = team_name
	add_child(root)
	var gk_side := 0 if team_name == "HomeTeam" else 1
	var is_own_team := team_name == GameFlow.player_side
	var index := 0
	for piece in pieces:
		var cell: Vector2i = piece["cell"]
		var fig := player_scene.instantiate() as Node3D
		root.add_child(fig)
		fig.position = _cell_world(cell.x, cell.y)
		fig.rotation_degrees = Vector3(0.0, facing + player_facing_offset, 0.0)
		fig.scale = Vector3.ONE * player_scale
		fig.name = "%s_%d" % [piece["role"], piece["number"]]
		# Goalkeepers wear a distinct kit — never the outfield country colours.
		var is_gk: bool = piece.get("role", "field") == "gk"
		var piece_kit := PlayerAppearance.gk_kit(gk_side) if is_gk else kit
		PlayerAppearance.apply(fig, piece_kit, PlayerAppearance.hair_for(index), piece["number"])
		# Kick off this figure's animation (idle desynced from its team-mates, or
		# the keeper's own idle) — see PlayerRig.
		if fig is PlayerRig:
			(fig as PlayerRig).setup(is_gk)
		_set_own_marker_visible(fig, is_own_team)
		_node_at[cell] = fig
		index += 1


## Every player_scene instance ships its own "OwnTeamTileGlow" child — a
## rounded-square glow centred under the figure, at deliberately LOW alpha. Low
## alpha is the point: when a bright Board FX tile lands on the same cell, it
## simply overpowers this faint tint instead of visually fighting it.
##
## The marker's SHAPE and SIZE come from the SAME single source as the tap/
## move/shoot tiles — BoardFx.make_tile_texture (shape) and fx_tile_size
## (footprint) — set here, once, so tuning either one moves ALL of them
## together (no separate PNG/mesh to keep in sync by hand). Only the marker's
## COLOUR/alpha stays a per-node Inspector property (its faint tint is its
## own look). Own-team only; the opponent's kit already reads as "not mine".
func _set_own_marker_visible(fig: Node3D, is_own: bool) -> void:
	var glow := fig.get_node_or_null("OwnTeamTileGlow") as MeshInstance3D
	if glow == null:
		return
	glow.visible = is_own
	var plane := glow.mesh as PlaneMesh
	if plane != null:
		plane.size = Vector2(fx_tile_size, fx_tile_size) # SAME footprint as the FX tiles
	var mat := glow.material_override as StandardMaterial3D
	if mat != null and mat.albedo_texture == null: # shared resource — generate once
		mat.albedo_texture = BoardFx.make_tile_texture() # SAME shape as the FX tiles
	if mat != null:
		mat.albedo_color = own_marker_color


## _set_own_marker_visible's is_own only decides "is this the local player's
## figure at all" (set once at build time, used for its initial state and
## the pre-match placement screen) — this is the REAL per-turn sync, and
## deliberately NOT scoped to just GameFlow.player_side: it lights up
## whichever team is actually _state.current (yours or the opponent's/AI's),
## on THEIR figures, during THEIR turn — a human reported the opponent's
## side never getting this glow at all felt inconsistent once their own
## side had it. Also skips any cell a Board FX tile is ALSO covering right
## now (see _draw_combo/_draw_move/_draw_remove/_refresh_turn_view's MOVE
## branch, each passing the cells THEY just put a tile on) — the glow
## visibly blended with the FX tile's colour during the pulse animation's
## dim point (alpha dips as low as 20%, letting the marker show through and
## muddy the hue), so overlap is avoided entirely rather than relying on
## "faint enough to not matter".
func _update_own_team_markers(covered: Array[Vector2i] = []) -> void:
	for cell in _state.pieces:
		var fig: Node3D = _node_at.get(cell)
		if fig == null:
			continue
		var glow := fig.get_node_or_null("OwnTeamTileGlow") as MeshInstance3D
		if glow != null:
			glow.visible = _state.pieces[cell]["team"] == _state.current and not (cell in covered)


# --- Ball helpers ------------------------------------------------------------
# Ball starts on an empty cell by the kicking team's goalkeeper.
## `formation` is the kicking side's line-up, needed only for the underfoot rule
## and read from the array rather than from _state, because the board is built
## before MatchState is told about it.
func _kickoff_cell(team: String, formation: Array = []) -> Vector2i:
	var cell := ball_start_cell
	if team != "HomeTeam":
		cell = Vector2i(ball_start_cell.x, Board.ROWS - 1 - ball_start_cell.y) # mirror
	if not MatchState.experiment_underfoot or formation.is_empty():
		return cell
	# Underfoot: the ball has to start AT somebody's feet, or the match opens
	# with nobody owning it and both sides scrambling for a loose ball — which
	# is exactly how the first attempt at this rule opened, and read as a bug
	# rather than as a rule. Whoever of the kicking side stands nearest the usual
	# spot takes it, so a hand-placed formation works as well as the default one.
	# The KEEPER takes it, which is what was asked for and is how a football
	# match restarts anyway — he distributes. I briefly excluded him on my own
	# reasoning that he should never start with the ball; that was wrong and it
	# put kickoff on whichever midfield man happened to be nearest, which reads
	# as arbitrary. Falls back to the nearest man of that side if a line-up
	# somehow has no keeper.
	var best := cell
	var best_dist := 9999
	for p in formation:
		var c: Vector2i = p["cell"]
		if String(p.get("role", "field")) == "gk":
			return c
		var d: int = maxi(absi(c.x - cell.x), absi(c.y - cell.y))
		if d < best_dist:
			best_dist = d
			best = c
	return best


func _place_ball(cell: Vector2i) -> void:
	if ball_scene == null:
		return
	_ball = ball_scene.instantiate() as Node3D
	add_child(_ball)
	_ball.name = "Ball"
	_ball.scale = Vector3.ONE * ball_scale
	_ball.position = _ball_world(cell)
	_ball_last_pos = _ball.position


## How far toward the corner the ball sits when a man is standing on its square.
## Applied on BOTH screen axes, so the true distance from the tile's centre is
## this times root two — 0.34 each way is 0.48, which is the corner of a 1.0
## tile. It was 0.26 first, giving 0.37, and that left the ball still touching a
## figure whose silhouette from above is most of its square: applied but not
## visibly applied, which is worse than not applied at all.
@export var ball_hold_offset := 0.34


func _ball_world(cell: Vector2i) -> Vector3:
	var pos := _cell_world(cell.x, cell.y) + Vector3(0, BALL_RADIUS * ball_scale, 0)
	# Underfoot: a figure can be standing ON the ball's square, and both centred
	# on the same point puts the ball inside him.
	#
	# Pushed into the corner of the man's square NEAREST THE CAMERA, and to one
	# side. Which corner is not a taste call, it is decided by the geometry: the
	# figure is an upright model seen at a tilt, so its body is drawn extending
	# AWAY from the viewer up the screen. Everything on that side of its base is
	# behind it; the side toward the viewer is always clear.
	#
	# The evidence is the first attempt at this, which offset along world Z by
	# whichever goal that man's side attacks. One team got the toward-camera
	# direction and its ball was visible, the other got away-from-camera and its
	# ball was behind the man — reported at the time as "it shows for some
	# players and not others", which is exactly what a team-decided direction
	# produces. Taking both axes from the camera makes it the same corner for
	# everybody, on both devices, whichever way the board is spun.
	# Screen up and screen right, both taken from the camera's UP and RIGHT axes —
	# NOT from the direction it looks.
	#
	# main.tscn's camera is Transform3D(1,0,0, 0,-4.4e-08,1, 0,-1,-4.4e-08, ...):
	# a dead vertical top-down view. Its forward axis is therefore straight down,
	# and flattening that onto the pitch gives 0.0000000437 — under the guard
	# that follows. Earlier versions took the forward axis, so the guard failed
	# and NEITHER offset was applied. The ball sat dead centre under the man, and
	# raising the distance could not help, because the distance was being
	# multiplied by nothing. The camera's up axis has the opposite property: it
	# lies flat exactly when the camera points down.
	#
	# Top-right, as asked. An earlier note here argued for the bottom corner on
	# the grounds that an upright figure hides what is behind it — true of a
	# tilted camera and irrelevant to this one, which is vertical and so has no
	# hidden side at all.
	if _state != null and _state.pieces.has(cell):
		var cam := get_node_or_null("Camera3D") as Camera3D
		if cam != null:
			var screen_up := cam.global_transform.basis.y
			var screen_right := cam.global_transform.basis.x
			screen_up.y = 0.0
			screen_right.y = 0.0
			if screen_up.length() > 0.001:
				pos += screen_up.normalized() * ball_hold_offset
			if screen_right.length() > 0.001:
				pos += screen_right.normalized() * ball_hold_offset
	return pos


# --- Match SFX -----------------------------------------------------------------
# One-shot sounds tied to match events (not to a specific player/position —
# those live on PlayerRig instead, see its _kick_sfx). ONE shared player,
# stream swapped per event — these essentially never overlap in practice
# (the rare exception: a shot that's both a card-triggering violation AND a
# goal would fire the whistle then immediately cut it off with the goal
# sound, since the card branch in _after_combo runs first and is awaited
# before the goal branch — acceptable, not worth a second player over).
# Add more here as more sounds arrive — const + an @export_range volume_db
# is the pattern (see goal_sfx_volume_db in the "Goal Cinematic" group,
# timer_tick_volume_db/whistle_sfx_volume_db near turn_time_limit).
const GOAL_SOUND: AudioStream = preload("res://assets/audio/sfx/goal.mp3")
const TICK_SOUND: AudioStream = preload("res://assets/audio/sfx/timer.mp3")
const WHISTLE_SOUND: AudioStream = preload("res://assets/audio/sfx/whistle.mp3")
## Board-tap feedback (picking up a figure / confirming a move destination —
## see _move_click) — the pitch equivalent of GameFlow's menu tap.mp3, kept
## separate/renamed from the deliberately quieter crowd loop below so board
## feedback stays clearly audible over the ambience.
const FIELD_TAP_SOUND: AudioStream = preload("res://assets/audio/sfx/field_tap.mp3")
## Combo-starter selection (tapping a figure next to the ball to begin
## building a chain — "taking possession"/see _combo_tap's begin() calls).
## Deliberately reuses GameFlow's own tap.mp3 (menu button click) rather than
## FIELD_TAP_SOUND, at the user's request — a separate const/volume here
## (not a call into GameFlow) so it can be tuned independently and matches
## this file's existing const+export_range pattern.
const SELECT_SOUND: AudioStream = preload("res://assets/audio/sfx/tap.mp3")
@export_range(-24.0, 24.0, 0.5) var select_sfx_volume_db := 5.0 # matches field_tap_volume_db/running_sfx_volume_db
var _match_sfx: AudioStreamPlayer = null


func _setup_match_sfx() -> void:
	_match_sfx = AudioStreamPlayer.new()
	_match_sfx.bus = &"SFX"
	add_child(_match_sfx)


func _play_sfx(stream: AudioStream, volume_db: float) -> void:
	if _match_sfx == null or stream == null:
		return
	_match_sfx.stream = stream
	_match_sfx.volume_db = volume_db
	_match_sfx.play()


## Crowd ambience: loops continuously for as long as the match scene is
## alive (started here in _ready(), never explicitly stopped — it's freed
## along with everything else in this scene the moment GameFlow.goto()
## swaps to WIN_SCREEN/LOSE_SCREEN). On the "Music" bus, not "SFX" —
## deliberately: it's continuous background atmosphere, the same ROLE
## GameFlow's menu intro.mp3 plays before the match starts, not a discrete
## event cue like the sounds above. Keeping it on a separate bus also means
## it has its OWN independent volume, so kick/whistle/tick (SFX) can stay
## clearly louder/more prominent without the crowd's level being coupled to
## theirs on a shared slider — crowd_volume_db defaults quieter than the
## other SFX for exactly that reason. Started at -6dB (quieter than the
## foreground SFX on principle) but a real playtest found it near-inaudible
## at that level — same "source clip reads quiet" issue as field_tap_volume_
## db above — so boosted to +4dB net; still meant to sit under kick/whistle/
## tick, just not silent under them. Adjust by ear from here.
const CROWD_SOUND: AudioStream = preload("res://assets/audio/sfx/crowd.mp3")
@export_range(-24.0, 24.0, 0.5) var crowd_volume_db := 4.0
var _crowd: AudioStreamPlayer = null


func _setup_crowd_ambience() -> void:
	_crowd = AudioStreamPlayer.new()
	_crowd.bus = &"Music"
	_crowd.stream = CROWD_SOUND
	if _crowd.stream is AudioStreamMP3:
		(_crowd.stream as AudioStreamMP3).loop = true
	_crowd.volume_db = crowd_volume_db
	add_child(_crowd)
	_crowd.play()


## Footstep run sound: a short 2-step clip, played ONCE PER CELL the move
## covers (not trimmed/stretched — the old approach here tried to trim ONE
## long 8-step clip down by distance, replaced per the user's own new,
## shorter source file) — repetitions are spaced evenly across the move's
## actual jog duration (see _apply_move's move_duration) so a longer slide
## reads as continuous running instead of every footstep bunching up at the
## start. Re-triggering .play() on the same player for each rep is fine even
## if an interval ends up shorter than the clip itself — it just restarts
## the clip, same as any rapid one-shot SFX retrigger elsewhere in this file.
## TEMPORARILY pointed at field_tap.mp3, not running.mp3 — testing whether
## the repeat-a-short-clip-per-cell APPROACH itself feels right using a clip
## already confirmed short/clean-sounding, before hunting down a dedicated
## footstep sound. Swap back to running.mp3 (or a new short single-step
## clip) once the direction's confirmed.
const RUNNING_SOUND: AudioStream = preload("res://assets/audio/sfx/field_tap.mp3")
## Same clip as field_tap right now (see RUNNING_SOUND above). Matches
## field_tap_volume_db/select_sfx_volume_db — all three set equal at the
## user's request.
@export_range(-24.0, 24.0, 0.5) var running_sfx_volume_db := 5.0
var _running_sfx: AudioStreamPlayer = null


func _setup_running_sfx() -> void:
	_running_sfx = AudioStreamPlayer.new()
	_running_sfx.bus = &"SFX"
	_running_sfx.stream = RUNNING_SOUND
	add_child(_running_sfx)


## `cells` = how many cells this move covers, `move_duration` = the jog
## tween's own duration (see _apply_move) — one full play of the clip per
## cell, spaced across that time. NOT perfectly even, and NOT identical every
## time — dead-even spacing plus the exact same clip on every repeat read as
## a metronome/robot instead of footsteps (reported after the first version
## of this), so both the gap AND the pitch/volume of each repeat get a small
## random jitter, the standard fix for a looped/repeated one-shot SFX
## sounding mechanical. Each step keeps its OWN evenly-spaced "slot"
## (interval * i) and only jitters WITHIN half a slot either way, then gets
## hard-clamped to [0, move_duration] — an earlier version accumulated the
## jitter step over step, which could drift the total past move_duration
## and fire footsteps audibly AFTER the figure had already stopped moving
## (reported as "steps run late"); this can't drift since every step's
## timing is computed from its own fixed slot, never the previous step's
## jittered result.
@export_range(0.0, 0.5, 0.05) var running_step_jitter := 0.25
func _play_running_sound(cells: int, move_duration: float) -> void:
	if _running_sfx == null or _running_sfx.stream == null or cells <= 0:
		return
	var interval := move_duration / float(cells)
	for i in range(cells):
		var slot := interval * i
		var jitter := interval * running_step_jitter * randf_range(-0.5, 0.5)
		var delay := clampf(slot + jitter, 0.0, move_duration)
		if delay <= 0.0:
			_trigger_running_step()
		else:
			var timer := get_tree().create_timer(delay)
			timer.timeout.connect(_trigger_running_step)


func _trigger_running_step() -> void:
	if _running_sfx == null:
		return
	# No pitch jitter — a short percussive clip pitch-shifted at all came out
	# harsh/tinny ("pištavo"), worse than the robotic sameness it was meant
	# to fix. Timing jitter (running_step_jitter) alone stays.
	_running_sfx.pitch_scale = 1.0
	_running_sfx.volume_db = running_sfx_volume_db + randf_range(-1.5, 1.0)
	_running_sfx.play()


# --- Pre-match placement (formation setup) ------------------------------------
# Runs INSIDE the match scene (reusing its already-fitted camera/stadium/HUD)
# instead of a separate screen, so a later "searching for opponent" step can
# just be another footer state — see main.gd's chat log for why this beat a
# standalone 2D setup screen. Only the LOCAL player's own side is placed here;
# the opponent stays on the fixed Formations layout until real online exists.
func _start_placement() -> void:
	_placement_active = true
	_placement_index = 0
	_placement_result = []
	var kits := CountryKits.resolve_match(home_country, away_country)
	var team := GameFlow.player_side
	_placement_kit = kits["home"] if team == "HomeTeam" else kits["away"]
	_placement_gk_side = 0 if team == "HomeTeam" else 1
	_placement_root = Node3D.new()
	_placement_root.name = "PlacementRoot"
	add_child(_placement_root)
	_refresh_hud()
	_refresh_placement_view()


## Every cell the CURRENT placement slot's role may legally go on — the
## keeper only the 3 goal cells on the player's own goal line, field players
## any empty, non-goal cell on the player's own half, EXCLUDING the kickoff
## ball cell itself (_kickoff_cell — the GK goal line never overlaps it, so
## only the field-player branch needs the check). Mirrors the same
## confinement rules MatchState already enforces during play (own_goal_row /
## is_goal_cell / Board.half_of_row), so a placed team is never in a spot the
## rules would forbid moving them to later, and never spawns literally on top
## of the ball at kickoff (see _kickoff_cell/_build_match).
func _placement_valid_cells(role: String) -> Array[Vector2i]:
	var team := GameFlow.player_side
	var out: Array[Vector2i] = []
	if role == "gk":
		var row := _state.own_goal_row(team)
		for col in MatchState.GOAL_COLS:
			var cell := Vector2i(col, row)
			if not _node_at.has(cell):
				out.append(cell)
		return out
	var own_half := 1 if team == "HomeTeam" else -1
	var ball_cell := _kickoff_cell(team)
	for row in range(Board.ROWS):
		if Board.half_of_row(row) != own_half:
			continue
		for col in range(Board.COLS):
			var cell := Vector2i(col, row)
			if _node_at.has(cell) or _state.is_goal_cell(cell) or cell == ball_cell:
				continue
			out.append(cell)
	return out


func _refresh_placement_view() -> void:
	var role: String = PLACEMENT_ROLE_ORDER[_placement_index]
	var remaining := PLACEMENT_ROLE_ORDER.size() - _placement_index
	var text := "Place your goalkeeper" if role == "gk" else "Place a player (%d left)" % remaining
	if _hud != null:
		_hud.set_footer_text(text, _placement_kit.get("primary", Color.WHITE))
	_fx.clear()
	for cell in _placement_valid_cells(role):
		_fx.add_tile(_cell_world(cell.x, cell.y), color_move)


func _placement_tap(screen_pos: Vector2) -> void:
	var role: String = PLACEMENT_ROLE_ORDER[_placement_index]
	var cell := _resolve_target(screen_pos, _placement_valid_cells(role), TAP_HIT_RADIUS)
	if cell == NO_CELL:
		return
	_play_sfx(SELECT_SOUND, select_sfx_volume_db)
	_place_piece(cell, role)


## Spawns one figure immediately at `cell` (visual feedback as you place,
## matching _build_team's own per-piece setup) and records it for the final
## Array[Dictionary] handed to GameFlow.player_formation once placement ends.
func _place_piece(cell: Vector2i, role: String) -> void:
	var number := _placement_index + 1
	var fig := player_scene.instantiate() as Node3D
	_placement_root.add_child(fig)
	fig.position = _cell_world(cell.x, cell.y)
	var facing := 180.0 if GameFlow.player_side == "HomeTeam" else 0.0
	fig.rotation_degrees = Vector3(0.0, facing + player_facing_offset, 0.0)
	fig.scale = Vector3.ONE * player_scale
	fig.name = "%s_%d" % [role, number]
	var is_gk := role == "gk"
	var piece_kit := PlayerAppearance.gk_kit(_placement_gk_side) if is_gk else _placement_kit
	PlayerAppearance.apply(fig, piece_kit, PlayerAppearance.hair_for(_placement_index), number)
	if fig is PlayerRig:
		(fig as PlayerRig).setup(is_gk)
	_set_own_marker_visible(fig, true) # placement is always the local player's own figures
	_node_at[cell] = fig
	_placement_result.append({"cell": cell, "role": role, "number": number})
	_placement_index += 1
	if _placement_index >= PLACEMENT_ROLE_ORDER.size():
		_finish_placement()
	else:
		_refresh_placement_view()


## All 6 placed: hand the layout to GameFlow, show the (placeholder, no real
## matchmaking yet) "searching" footer state briefly, then tear down the
## placement-preview figures and let _build_match spawn the real match.
func _finish_placement() -> void:
	_placement_active = false
	GameFlow.player_formation = _placement_result
	_fx.clear()
	if _hud != null:
		_hud.set_footer_text("Searching for opponent...", _placement_kit.get("primary", Color.WHITE))
	await get_tree().create_timer(1.0).timeout
	if _placement_root != null:
		_placement_root.free()
		_placement_root = null

	# Online looks for an opponent HERE, as an overlay on this very pitch, so
	# that accepting an invite drops straight into play with nothing to load and
	# nobody to wait for (GAME_DESIGN.md §11).
	if GameFlow.online_mode:
		_show_online_overlay()
		return
	_start_coin_toss()


# --- Tutorial ------------------------------------------------------------------
# Learning by doing, on the real board, through the real rules. The lesson
# itself (steps, what may be tapped, what advances) lives in Tutorial — this is
# only the view side: build the small scenario, strip the HUD to its footer, and
# refuse taps that aren't part of the current step.

## How long a step may go nowhere before an escape hatch appears. Deliberately
## not a Next button from the start: a step that can be clicked past is a step
## that gets clicked past, and then the tutorial teaches nothing — which is
## exactly how the written instructions failed.
const TUTORIAL_STUCK_SECONDS := 8.0

## How long a correction stays in the footer before the instruction comes back.
const TUTORIAL_SAY_SECONDS := 2.5

## Height of the HUD's top strip — hud.tscn's Background ends and its Footer
## begins at exactly this y. The tutorial heading takes that strip over once the
## bar is hidden, and must not spill past it into the footer.
const HUD_TOP_STRIP := 241.0

const UI_THEME := preload("res://my_theme.tres")

## What every screen in the game titles itself at — see difficulty_screen.tscn,
## team_select.tscn, legal_screen.tscn, the instructions cards, win/lose.
const TITLE_FONT_SIZE := 96

## And what the rules cards set their PROSE at — instructions_screen.tscn's
## Page4 CardBody, in the system font rather than the theme's display face.
const BODY_FONT_SIZE := 34

var _tutorial: Tutorial = null
var _tutorial_stuck := 0.0
var _tutorial_layer: CanvasLayer = null
var _tutorial_title: Label = null
var _tutorial_lesson: Label = null


func _start_tutorial() -> void:
	# Marked on OPENING, not on finishing. The main menu keeps the two play modes
	# closed until this has happened (see main_menu.gd), and a lock that only
	# lifts on completion would strand anyone who backs out halfway in a menu
	# whose one live button is the thing they just walked away from.
	Settings.mark_tutorial_seen()
	_tutorial = Tutorial.new()
	ball_start_cell = Tutorial.ball_start()
	if _hud != null:
		_hud.show_match_chrome(false)
	_build_tutorial_banner()
	_build_match("HomeTeam")
	_tutorial_refresh()


## A heading and a wrapped explanation, built in code so hud.tscn stays as the
## author left it — same approach as the online overlay.
##
## The heading exists because the tutorial otherwise just... starts, with no
## indication of what this screen suddenly is. And the explanation lives up here
## rather than in the footer because the footer is one narrow strip: a full
## sentence there ran off both edges of the screen.
func _build_tutorial_banner() -> void:
	_tutorial_layer = CanvasLayer.new()
	_tutorial_layer.layer = 9
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Bounded to the strip the HUD bar normally fills, and no further. Left free
	# to grow, the second wrapped line of a lesson ran straight down into the
	# footer and printed on top of the prompt sitting there.
	margin.offset_bottom = HUD_TOP_STRIP
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 60)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	# Built in code, so it inherits nothing — without the game's theme these two
	# labels came out in Godot's default font while every other word on screen
	# was Bebas.
	margin.theme = UI_THEME
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	# The heading is the SECTION, not the screen. "How to play" told the player
	# what they were looking at once and then said nothing for the rest of the
	# lesson; the section name answers that AND tells them where they are inside
	# it — and it is what lets the refusals stop arguing (see Tutorial.title).
	#
	# 96 is what every other screen titles itself at — Choose Difficulty, Choose
	# Country, the rules cards, Legal, the result screens.
	_tutorial_title = Label.new()
	_tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	box.add_child(_tutorial_title)

	# Body text, not display text — so the same system font the rules cards set
	# their prose in, at the same 34 (see instructions_screen.tscn's Page4).
	# The theme's Bebas is a condensed display face: right for the title above,
	# wrong for a sentence, which is why this read as small and cramped at a size
	# that would have been fine in the card's font.
	#
	# Wrapping stays on, because a longer translation must push down rather than
	# run off the sides, and two lines still clear the footer.
	_tutorial_lesson = Label.new()
	_tutorial_lesson.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_lesson.add_theme_font_override("font", SystemFont.new())
	_tutorial_lesson.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	box.add_child(_tutorial_lesson)

	_tutorial_layer.add_child(margin)
	add_child(_tutorial_layer)


## Only the cells the current step is about. A stray tap during a lesson must not
## produce a result, because an unexplained result is exactly what the tutorial
## exists to prevent.
func _tutorial_blocks(cell: Vector2i) -> bool:
	if _tutorial == null or _tutorial.finished():
		return false
	if not _tutorial.allows(cell):
		# Say why. The board is the game's REAL board here — every own figure is
		# lit, because in a real match every one of them is a choice — so tapping
		# the wrong one is a fair mistake, and answering it with nothing is
		# exactly what made the game feel broken to a first-time player.
		_tutorial_say(_tutorial.nudge(cell))
		return true
	var why := _tutorial.refusal(cell)
	if why == "":
		return false
	# Refused ON PURPOSE, with the reason — the risky square is offered rather
	# than hidden, because "don't leave it there" only lands if you could have.
	_tutorial_say(why)
	return true


## Answers a wrong tap in the footer, then puts the instruction back. Without the
## second half the player reads why they were wrong and is left staring at it,
## with the thing they were actually asked to do now gone from the screen.
func _tutorial_say(text: String) -> void:
	_tutorial_stuck = 0.0
	if text == "" or _hud == null:
		return
	_hud.set_footer_text(text, Color.WHITE)
	var said_at := _tutorial.step
	await get_tree().create_timer(TUTORIAL_SAY_SECONDS).timeout
	# Only if they haven't since got it right — otherwise this would overwrite
	# the NEXT step's instruction with the previous one's.
	if _tutorial != null and _tutorial.step == said_at and _hud != null:
		_hud.set_footer_text(_tutorial.prompt(), Color.WHITE)


func _tutorial_did(kind: String, cell: Vector2i) -> void:
	if _tutorial == null:
		return
	if _tutorial.on_action(kind, cell):
		_tutorial_refresh()


func _tutorial_refresh() -> void:
	_tutorial_stuck = 0.0
	if _tutorial_title != null:
		_tutorial_title.text = _tutorial.title()
	if _tutorial_lesson != null:
		_tutorial_lesson.text = _tutorial.lesson()
	if _hud != null:
		_hud.set_footer_text(_tutorial.prompt(), Color.WHITE)
	if _tutorial.finished():
		await get_tree().create_timer(1.6).timeout
		_finish_tutorial()
		return


## The tutorial used to fan the eight straight lines out of the ball-carrier in
## the trail colour, on top of whatever the match had already drawn. It was the
## picture the lesson was built around — and it was still a tile painted in a
## colour that means nothing anywhere else in the game, which is the one thing
## this screen must not do. The board teaches straight lines on its own: the
## position is arranged so exactly one teammate lights up, which is the same
## fact shown in the game's own language.
func _finish_tutorial() -> void:
	_tutorial = null
	if _tutorial_layer != null:
		_tutorial_layer.queue_free()
		_tutorial_layer = null
		_tutorial_title = null
		_tutorial_lesson = null
	GameFlow.tutorial_mode = false
	# Ends on the rules card — scoring, offside, the keeper, cards. None of that
	# fits in one turn, and it is the only instruction page the tutorial didn't
	# make redundant. Closing mode drops the arrows and the other three cards
	# with them: they describe in words what the player has just done.
	GameFlow.instructions_page = 3
	GameFlow.instructions_closing = true
	GameFlow.goto(GameFlow.Screen.INSTRUCTIONS)


# --- Online: finding an opponent, without leaving the pitch -------------------

const ONLINE_OVERLAY_SCENE := preload("res://scenes/ui/online_screen.tscn")
const NET_MATCH_SCENE := preload("res://scripts/net/net_match.gd")
const NetAction := preload("res://scripts/net/net_action.gd")

var _online_overlay: CanvasLayer = null
var _net_match: Node = null
## The opponent's placed figures, fetched once before kick-off so both clients
## build an identical board. Empty offline.
var _remote_formation: Array[Dictionary] = []
## OUR figures as used for THIS match — the same layout the player placed, but
## rotated when we turn out to be the guest.
##
## Kept apart from GameFlow.player_formation, which stays the canonical
## home-half layout the player actually drew. Overwriting that with the mirrored
## copy looked harmless until a second match: play once as guest, then host, and
## the saved layout would already be on the wrong half.
var _my_formation: Array[Dictionary] = []
## True while we are replaying the OPPONENT's action locally. Without it, every
## remote action would be echoed straight back as if we had played it — the two
## clients would keep bouncing the same turn at each other forever.
var _applying_remote := false
## Opponent actions waiting their turn, and whether the drain loop is running.
## Actions MUST be applied one at a time and in order — see _on_remote_action.
var _remote_queue: Array = []
var _remote_busy := false
## Whether the HUD is currently showing the "not your clock" dash.
var _timer_dash_shown := false
## When the opponent's turn runs out, in SERVER epoch ms. Both clients count
## down to this same instant, so the two displays can't drift apart.
var _remote_deadline_ms := 0.0
## Set when the player hits Leave in the moment between an opponent accepting
## and play starting. Starting a match is not instant (formations have to be
## swapped), so the abort has to be checked after those awaits rather than
## assumed impossible.
var _online_aborted := false


func _show_online_overlay() -> void:
	_busy = true # no board input while the overlay owns the screen
	_online_overlay = CanvasLayer.new()
	_online_overlay.layer = 10 # above the HUD
	var ui := ONLINE_OVERLAY_SCENE.instantiate()
	ui.match_ready.connect(_on_online_match_ready)
	ui.cancelled.connect(_on_online_cancelled)
	ui.left_room.connect(func(): _online_aborted = true)
	_online_overlay.add_child(ui)
	add_child(_online_overlay)


func _hide_online_overlay() -> void:
	if _online_overlay != null:
		_online_overlay.queue_free()
		_online_overlay = null
	_busy = false


## The formation was placed BEFORE we knew which side we would end up on, so a
## player who turns out to be the guest has laid their figures out on the home
## half. Rotating the layout 180 degrees moves it to the away half while keeping
## its shape exactly as drawn — and since the guest's camera is turned around
## too, it looks identical to what they placed.
func _mirror_formation(layout: Array) -> Array:
	var out: Array[Dictionary] = []
	for entry in layout:
		var c: Vector2i = entry["cell"]
		# Explicitly typed: `layout` is an untyped Array, so its elements are
		# Variant and duplicate() has nothing to infer from.
		var flipped: Dictionary = entry.duplicate()
		flipped["cell"] = Vector2i(Board.COLS - 1 - c.x, Board.ROWS - 1 - c.y)
		out.append(flipped)
	return out


func _on_online_match_ready(room: String, opponent_name: String, opponent_country: String, is_host: bool) -> void:
	_online_aborted = false
	GameFlow.online_room = room
	GameFlow.online_opponent_name = opponent_name
	GameFlow.online_is_host = is_host

	# Host is always HomeTeam. That single fixed rule is what lets both clients
	# work out the kits without exchanging a word: CountryKits.resolve_match
	# already puts the away side in its alternative strip whenever the two
	# primaries clash — which two identical countries always do.
	GameFlow.player_side = "HomeTeam" if is_host else "AwayTeam"
	_my_formation = GameFlow.player_formation.duplicate()
	if is_host:
		home_country = Settings.player_country
		if opponent_country != "":
			away_country = opponent_country
	else:
		away_country = Settings.player_country
		if opponent_country != "":
			home_country = opponent_country
		_my_formation = _mirror_formation(GameFlow.player_formation)
	GameFlow.home_country = home_country
	GameFlow.away_country = away_country

	# Swap formations before anything is built. Without this each client fills
	# the opponent's half with the default layout and the two boards differ from
	# the very first move.
	if not await _exchange_formations(room):
		return
	# Leave may have been pressed while those round trips were in flight — the
	# overlay is already back on the player list, so don't start a match behind
	# it.
	if _online_aborted:
		GameFlow.clear_online_match()
		return

	_hide_online_overlay()
	# The side is only known now, so the camera has to be refitted: the first fit
	# ran back in _ready, when this client still assumed it was the home side.
	_fit_camera()
	_start_net_match(room)
	_start_coin_toss()


## Publishes our formation and waits for the opponent's.
##
## Both sides write at almost the same moment (one on accepting, the other on
## noticing the guest joined), so this normally resolves in a poll or two. If it
## never arrives we ABANDON rather than fall back to a default layout: playing on
## against a board the opponent isn't looking at is worse than not starting.
func _exchange_formations(room: String) -> bool:
	const FORMATION_WAIT_SECONDS := 20.0
	const FORMATION_POLL := 1.0

	# The layout as it will actually stand on the board, already rotated if we
	# are the guest — the opponent uses these cells as they arrive.
	var mine := NetAction.formation_to_json(_my_layout())
	var put: Dictionary = await Net.db_put("rooms/%s/formations/%s" % [room, Net.uid], mine)
	if not put["ok"]:
		_net_opponent_left("Could not start the match: %s" % put["error"])
		return false

	var waited := 0.0
	while waited < FORMATION_WAIT_SECONDS:
		var res: Dictionary = await Net.db_get("rooms/%s/formations" % room)
		if res["ok"] and res["data"] is Dictionary:
			for uid in res["data"]:
				if String(uid) == Net.uid:
					continue
				var parsed := NetAction.formation_from_json(res["data"][uid])
				if not parsed.is_empty():
					_remote_formation = parsed
					return true
		await get_tree().create_timer(FORMATION_POLL).timeout
		waited += FORMATION_POLL

	_net_opponent_left("Opponent never finished setting up.")
	return false


func _start_net_match(room: String) -> void:
	# Without this line a frozen-match report is unreadable: every TURN: printed
	# afterwards names a side, and nothing says which of them is the person
	# holding the phone — so "it was their turn and I waited" and "it was my turn
	# and I was locked out" look identical in the log.
	print("NET START room=%s  I am %s  opponent=%s" \
		% [room, GameFlow.player_side, GameFlow.online_opponent_uid])
	_net_match = NET_MATCH_SCENE.new()
	add_child(_net_match)
	_net_match.action_received.connect(_on_remote_action)
	_net_match.desync.connect(_net_desync)
	# Resigning arrives as an action; somebody who just closes the app doesn't
	# send anything at all, and only presence catches that.
	_net_match.opponent_lost.connect(_net_opponent_left)
	# Was connected to nothing. A poll that keeps failing looks exactly like a
	# frozen game — the board simply stops changing — and the player had no way
	# to tell that apart from a bug, nor did the log.
	_net_match.sync_failed.connect(_on_sync_failed)
	_net_match.sync_recovered.connect(_on_sync_recovered)
	_net_match.deadline_changed.connect(func(ms: float):
		_remote_deadline_ms = ms
		_remote_stall_said = false)
	_net_match.start(room, null, GameFlow.online_opponent_uid)
	# Measured once, before any deadline is read: the shared deadline is stored
	# in SERVER time, and a device whose clock is a minute out would otherwise
	# read it as a minute of extra thinking time.
	Net.sync_clock()


## True when the networked opponent, not this player, is the one to act. Mirrors
## _is_ai_turn exactly, because a remote opponent IS just a third source of
## input alongside taps and the AI (§10) — same gate, same functions, same
## animations.
func _is_remote_turn() -> bool:
	if not GameFlow.online_mode or _state == null:
		return false
	return _state.current != GameFlow.player_side


## Sends an action we just played. Fire-and-forget on purpose: the local game
## has already moved on, and making the animation wait for a round trip is what
## makes networked games feel sluggish.
func _net_send(action: Dictionary) -> void:
	if _net_match == null or _applying_remote:
		return
	var res: Dictionary = await _net_match.send_action(action)
	if not res["ok"]:
		_net_desync("could not send our own turn: %s" % res["error"])


## How many polls in a row may fail before the player is told. Below this it is
## a blip on a phone network and saying anything would be noise; above it, their
## opponent's turns have genuinely stopped arriving.
const SYNC_COMPLAIN_AFTER := 3

## How far past the opponent's own published deadline we wait before admitting
## nothing is coming. Generous: it covers their animation, their upload, and our
## next poll on top.
const REMOTE_STALL_GRACE := 15.0

var _sync_troubled := false
var _remote_stall_said := false


func _on_sync_failed(_reason: String, streak: int) -> void:
	if streak < SYNC_COMPLAIN_AFTER or _sync_troubled:
		return
	_sync_troubled = true
	if _hud != null:
		_hud.set_footer_text("Connection trouble — reconnecting", Color.WHITE)


func _on_sync_recovered() -> void:
	if not _sync_troubled:
		return
	_sync_troubled = false
	# Only the footer. A full _refresh_turn_view() here re-enters the timer
	# branches with the same team still on the clock, takes the "same team
	# continuing" path, and restarts their turn on whatever fraction of a second
	# was last snapshotted — so recovering from a network blip could hand the
	# player 0.05 seconds and forfeit their turn for them.
	if _hud != null and _state != null:
		_hud.update_turn_hint(_state.current, _state.phase, "", _state.moves_left)


## Replays the opponent's action through the SAME functions a tap would call, so
## it animates identically. Every step is checked against our own MatchState
## first: this is the only real defence against a tampered client, since
## database rules cannot run the rules of the game (see net.gd).
func _on_remote_action(action: Dictionary) -> void:
	if _state == null:
		return
	# Queued, never applied straight away.
	#
	# One turn produces TWO log entries (the combo, then the compulsory move), so
	# a single poll routinely delivers both at once. _play_remote_action is a
	# coroutine that returns at its first await, which meant the second action
	# started replaying in the middle of the first one's animation, against a
	# board still mid-change. That is the intermittent "he moved and I never saw
	# it, then nothing worked" — it only showed up when the poll happened to
	# catch two entries together.
	# Printed alongside the TURN/MOVE lines the match already logs, so a report of
	# "it froze" can be read afterwards: whether the opponent's action arrived at
	# all, and whether we were still chewing on the last one when it did.
	print("NET RECV %s (queued=%d busy=%s remote_busy=%s)" \
		% [String(action.get("t", "?")), _remote_queue.size(), _busy, _remote_busy])
	_remote_queue.append(action)
	if _remote_busy:
		return

	_remote_busy = true
	while not _remote_queue.is_empty():
		# Let any animation already running finish first, including one started
		# by the previous queued action.
		var guard := 0
		while _busy and guard < 1200:
			await get_tree().process_frame
			guard += 1

		var next: Dictionary = _remote_queue.pop_front()
		_applying_remote = true
		var ok := await _play_remote_action(next)
		_applying_remote = false
		if not ok:
			_remote_queue.clear()
			_remote_busy = false
			_net_desync("opponent played something our rules refuse: %s" % JSON.stringify(next))
			return
	_remote_busy = false


func _play_remote_action(action: Dictionary) -> bool:
	match String(action.get("t", "")):
		"combo":
			var chain = action.get("chain", [])
			if not (chain is Array) or chain.is_empty():
				return false
			if not _state.begin(NetAction.cell_from_json(chain[0])):
				return false
			for i in range(1, chain.size()):
				if not _state.extend(NetAction.cell_from_json(chain[i])):
					return false
			var shoot := NetAction.cell_from_json(action.get("shoot", null))
			if not (shoot in _state.combo_shoot_targets()):
				return false
			await _do_combo(shoot)
			return true
		"move", "hold":
			var from := NetAction.cell_from_json(action.get("from", null))
			var to := NetAction.cell_from_json(action.get("to", null))
			if not (to in _state.move_targets(from)):
				return false
			# Awaited. _apply_move is a coroutine that holds _busy for the whole
			# slide; returning before it finished told the drain loop this action
			# was done while the board was still mid-change, which is the same
			# class of overlap the queue exists to prevent.
			await _apply_move(from, to, String(action["t"]) == "hold")
			return true
		"remove":
			var cell := NetAction.cell_from_json(action.get("cell", null))
			if not _state.is_own(cell):
				return false
			_remove_at(cell)
			return true
		"forfeit":
			_state.forfeit(true)
			await _announce_stalling_card()
			_refresh_turn_view()
			return true
		"resign":
			_net_opponent_left("Opponent resigned.")
			return true
	return false


## The two clients no longer agree on the board. There is nothing safe to do but
## stop: continuing would leave both players making moves against a position the
## other one isn't looking at.
func _net_desync(reason: String) -> void:
	push_error("ONLINE DESYNC: %s" % reason)
	_net_opponent_left("Connection problem — match abandoned.")


func _net_opponent_left(message: String) -> void:
	if _net_match != null:
		_net_match.stop()
		_net_match.queue_free()
		_net_match = null
	_busy = true
	if _hud != null:
		_hud.set_footer_text(message, Color.WHITE)
	await get_tree().create_timer(2.5).timeout

	# Back to looking for an opponent, NOT out to the main menu. Losing your
	# opponent shouldn't cost you the country you picked and the formation you
	# laid out — reloading the match scene with the room cleared drops straight
	# onto the player list again (see _spawn_teams).
	GameFlow.clear_online_match()
	if GameFlow.online_mode:
		GameFlow.goto(GameFlow.Screen.MATCH)
	else:
		GameFlow.goto(GameFlow.Screen.MAIN_MENU)


## Back from the overlay: this one DOES leave online for good, so it clears the
## mode as well and returns to the country picker the player came through.
func _on_online_cancelled() -> void:
	_hide_online_overlay()
	GameFlow.reset_online()
	GameFlow.online_country_picker = true
	GameFlow.goto(GameFlow.Screen.TEAM_SELECT)


## Pre-match coin toss deciding who kicks off first (mirrors the original
## 2006 game's shield-flip) — replaces the previously-hardcoded
## _build_match("HomeTeam"). Keeps _busy=true through the flip animation so
## no stray tap can interact with the empty pitch, then clears it BEFORE
## _build_match, not after: _build_match -> _refresh_turn_view can hand the
## kickoff straight to the AI (_maybe_ai_turn), which bails out immediately
## if _busy is still true when it checks (same lesson as _after_combo's goal
## branch above).
func _start_coin_toss() -> void:
	if _hud == null:
		_build_match("HomeTeam")
		return
	_busy = true
	var home_code := CountryKits.get_code(home_country)
	var away_code := CountryKits.get_code(away_country)
	var labels := _online_labels()
	var winner: String = await _hud.play_coin_toss(home_code, away_code, home_country,
		away_country, _online_kickoff(), labels["home"], labels["away"])
	_busy = false
	_build_match(winner)


## Player names for the two sides, or empty strings offline.
##
## Used by BOTH the coin toss and the match shields so the two never disagree —
## and needed at all because duplicate countries are allowed online, where two
## "CRO" labels would identify nobody.
func _online_labels() -> Dictionary:
	if not GameFlow.online_mode:
		return {"home": "", "away": ""}
	var mine := Settings.player_name
	var theirs := GameFlow.online_opponent_name
	if GameFlow.player_side == "HomeTeam":
		return {"home": mine, "away": theirs}
	return {"home": theirs, "away": mine}


## Who kicks off in an online match — derived from the room code so BOTH clients
## reach the same answer without exchanging anything.
##
## The toss used to be a plain randi() on each device, which meant host and guest
## began with different teams to move and the first turn played was already
## illegal by the other's rules. Hashing the room code keeps it unpredictable per
## match while being identical on both sides, and needs no extra field in the
## room (so the database rules stay as they are).
##
## Empty string offline: the toss stays a real roll there.
func _online_kickoff() -> String:
	if not GameFlow.online_mode or GameFlow.online_room == "":
		return ""
	return "HomeTeam" if absi(GameFlow.online_room.hash()) % 2 == 0 else "AwayTeam"


# --- Input: tap vs drag -------------------------------------------------------
# A TAP always (re)starts the chain at the tapped figure, or rewinds to it if
# it's already in the chain, or fires a shot if it's a shoot cell — never
# ambiguous, never depends on geometry. A DRAG (real finger movement) from
# wherever your finger is toward a highlighted target is the only way to
# CONNECT two figures (a pass) or aim a shot with live snap feedback.
func _unhandled_input(event: InputEvent) -> void:
	if _busy or _state == null:
		return
	# Single Player: never let a tap act on the AI's own turn — normally
	# _busy already covers the AI's think-time + animation, but if the AI
	# ever fails to decide anything (see _maybe_ai_turn's fallback forfeit),
	# this is the hard backstop so the human can't step in and play the AI's
	# pieces for it.
	# Online has the same problem with the same answer: while the opponent is to
	# move, taps must not touch the board.
	if _is_ai_turn() or _is_remote_turn():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_on_press(mb.position)
		else:
			_on_release(mb.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_on_press(st.position)
		else:
			_on_release(st.position)


func _on_press(screen_pos: Vector2) -> void:
	_pressed = true
	_press_screen_pos = screen_pos



func _on_release(screen_pos: Vector2) -> void:
	if not _pressed:
		return
	_pressed = false
	if _placement_active:
		_placement_tap(screen_pos)
		return
	# A tap — resolved against phase-specific candidate sets (see below),
	# not a single raw raycast cell, so tapping a tall figure's body works too.
	if _holding:
		_move_click(screen_pos)
	elif _state.phase == MatchState.Phase.COMBO:
		_combo_tap(screen_pos)
	elif _state.phase == MatchState.Phase.REMOVE:
		_remove_tap(screen_pos)
	else:
		_move_click(screen_pos)


# --- REMOVE: after a red card, the carded team taps one of its own figures
# to permanently remove it (spends that team's turn — see MatchState.remove_figure).
func _remove_tap(screen_pos: Vector2) -> void:
	var cell := _resolve_target(screen_pos, _state.own_cells(), TAP_HIT_RADIUS)
	if cell == NO_CELL:
		return
	_remove_at(cell)


## Cell-based core of _remove_tap, shared with the AI (see _maybe_ai_turn),
## which already knows the target cell and has no screen position to resolve.
func _remove_at(cell: Vector2i) -> void:
	if not _state.remove_figure(cell):
		return
	_net_send(NetAction.remove(cell))
	var fig: Node3D = _node_at.get(cell)
	if fig != null:
		fig.queue_free()
	_node_at.erase(cell)
	print("REMOVED: figure at %s" % cell)
	_refresh_turn_view()


# Resolves a tap/drag screen point against `candidates`, accounting for figure
# height: occupied cells are hit-tested as a vertical column (tapping anywhere
# on a figure's visible body OR the flat tile it stands on both work — a tap
# purely on the flat ground-plane raycast alone can miss a tall figure under a
# tilted camera, so occupied cells are hit-tested BOTH ways and whichever is
# closer wins). Empty cells only have the flat ground-plane test (no body).
func _resolve_target(screen_pos: Vector2, candidates: Array[Vector2i], radius: float) -> Vector2i:
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return NO_CELL
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var best := NO_CELL
	var best_dist := radius
	for cell in candidates:
		var world := _cell_world(cell.x, cell.y)
		var d := INF
		if _node_at.has(cell):
			var r := Board.ray_vertical_closest(origin, dir, world.x, world.z)
			var y: float = r["y"]
			if y >= world.y - 0.1 and y <= world.y + FIGURE_HEIGHT * player_scale:
				d = r["xz_dist"]  # hit the figure's body
		var plane := Plane(Vector3.UP, world.y)
		var hit = plane.intersects_ray(origin, dir)
		if hit != null:
			var flat_d := Vector2((hit as Vector3).x - world.x, (hit as Vector3).z - world.z).length()
			d = minf(d, flat_d)  # or hit the tile itself, whichever is closer
		if d <= best_dist:
			best_dist = d
			best = cell
	return best



# --- COMBO: a plain tap (re)starts the chain, rewinds it, extends it with a
# pass, or shoots --------------------------------------------------------------
# Figures (cylinder hit-test) are ALWAYS checked before empty target tiles
# (flat hit-test): a tap on a tall figure's body can visually overlap a
# nearby empty tile under the tilted camera, so if we checked tiles first, a
# tap clearly meant for a figure could get misread as tapping the tile behind
# it. Checking figures first means the figure always wins when both match.
# Priority order resolves the one real ambiguity (a teammate who is BOTH a
# valid starter — adjacent to the ball — AND a valid pass target in a straight
# line from the chain): a tap on a valid STARTER always (re)starts the chain
# there, even if that same cell would also read as a pass target from the
# current chain — switching who you're playing through wins over extending
# the existing pick. Rewind is checked first regardless (tapping something
# ALREADY in the chain truncates back to it, same as ever — that's a
# different, well-established gesture, not this ambiguity). Only once none
# of rewind/starter/pass/shoot match does... well, they cover every legal
# tap between them; this ordering just decides which ONE wins when a cell
# qualifies as more than one.
func _combo_tap(screen_pos: Vector2) -> void:
	if not _state.chain.is_empty():
		# Tapping the chain's ACTIVE figure (the one just picked, always the
		# LAST entry) again steps the chain back ONE — "reconsider that last
		# choice" — same gesture whether it's the sole starter (steps back
		# to empty/neutral) or the 2nd+ figure (steps back to whichever came
		# before it). Tapping an EARLIER chain figure instead (below) still
		# jumps straight back to that point (MatchState.rewind), unchanged.
		if _resolve_target(screen_pos, [_state.chain[-1]], TAP_HIT_RADIUS) != NO_CELL:
			var was: Vector2i = _state.chain[-1]
			_state.step_back()
			# Underfoot: the man with the ball at his feet is the ONLY figure who
			# can open a chain, so a tap on him always started one and there was
			# no gesture left that reached "walk with it". Dribbling existed in
			# the rules and could not be performed. Tapping him a second time now
			# switches from playing the ball to carrying it: pass and shoot on
			# the first tap, his own move squares on the second.
			if MatchState.experiment_underfoot and _state.chain.is_empty() \
					and was == _state.ball and _state.is_own(was):
				_holding = true
				_move_from = was
				_draw_move(was)
				_play_sfx(SELECT_SOUND, select_sfx_volume_db)
				return
			_draw_combo()
			return
		var rewind_cell := _resolve_target(screen_pos, _state.chain, TAP_HIT_RADIUS)
		if rewind_cell != NO_CELL:
			_state.rewind(rewind_cell)
			_draw_combo()
			return
		var restart_cell := _resolve_target(screen_pos, _state.combo_starters(), TAP_HIT_RADIUS)
		if restart_cell != NO_CELL:
			if _state.begin(restart_cell):
				_play_sfx(SELECT_SOUND, select_sfx_volume_db)
				_draw_combo()
			return
		var pass_cell := _resolve_target(screen_pos, _state.combo_pass_targets(), TAP_HIT_RADIUS)
		if pass_cell != NO_CELL:
			if _tutorial_blocks(pass_cell):
				return
			_state.extend(pass_cell) # tap-to-pass — connects the chain, same as a drag
			_draw_combo()
			_tutorial_did("extend", pass_cell)
			return
		var shoot_cell := _resolve_target(screen_pos, _state.combo_shoot_targets(), TAP_HIT_RADIUS)
		if shoot_cell != NO_CELL:
			if _tutorial_blocks(shoot_cell):
				return
			_tutorial_did("shoot", shoot_cell)
			_do_combo(shoot_cell) # direct tap-to-shoot still works, no ambiguity
			return
		return
	# Nothing engaged yet: tap the ball-adjacent figure to begin a combo, OR
	# tap ANY other own figure to move IT instead — declining the ball this
	# turn (see MatchState.hold_and_move). Every own figure is highlighted
	# here (see _draw_combo), not just the ball-adjacent ones, so this is a
	# real, always-visible choice, not a hidden fallback. From here on,
	# taps/drags route through the exact same flow a real Phase.MOVE uses
	# (see _on_release/_move_click) — `_holding` just means
	# "resolve the eventual move via hold_and_move, not do_move".
	var starter := _resolve_target(screen_pos, _state.combo_starters(), TAP_HIT_RADIUS)
	if starter != NO_CELL:
		if _tutorial_blocks(starter):
			return
		if _state.begin(starter):
			_play_sfx(SELECT_SOUND, select_sfx_volume_db)
			_draw_combo()
			_tutorial_did("begin", starter)
			return
	var hold_fig := _resolve_target(screen_pos, _state.own_cells(), TAP_HIT_RADIUS)
	if hold_fig != NO_CELL:
		# The tutorial has to gate this branch too. It was the one way into a real
		# action that wasn't checked, so "tap that player" could be answered by
		# tapping a DIFFERENT one and walking him off — declining the ball, which
		# is a rule the tutorial hasn't got to yet and never asked for.
		if _tutorial_blocks(hold_fig):
			return
		_holding = true
		_move_from = hold_fig
		_draw_move(hold_fig)
		_play_sfx(SELECT_SOUND, select_sfx_volume_db)
		return
	_hint_ball_carriers(screen_pos)


## Tapping the BALL answers "so how do I get it?" instead of doing nothing.
##
## Watching a first-time player, the very first thing they did was tap the ball —
## and the game replied with silence, which reads as broken rather than as
## wrong. The answer it gives depends on whether anyone can play the ball at
## all, and so does the colour it gives it in — see the two halves below.
func _hint_ball_carriers(screen_pos: Vector2) -> void:
	if _state == null:
		return
	if _resolve_target(screen_pos, [_state.ball], TAP_HIT_RADIUS) == NO_CELL:
		return

	# COMBO: whoever may start the chain. Orange is the truth there — the ball
	# really can go through them, this turn.
	if _state.phase == MatchState.Phase.COMBO:
		var carriers := _state.combo_starters()
		if carriers.is_empty():
			return
		_fx.clear()
		for cell in carriers:
			_fx.add_tile(_cell_world(cell.x, cell.y), color_chain, -1.0, true)
		_update_own_team_markers(carriers)
		_play_sfx(SELECT_SOUND, select_sfx_volume_db)
		return

	# MOVE: nobody can play the ball at all, so orange here was a lie — and a
	# loud one, since a two-square move reaches the ball from most of the pitch
	# and lit nearly the whole team as if they were all on it. Reported as
	# "I tapped the ball with nobody near it and everyone went orange".
	#
	# The honest answer to "how do I get it?" here is a WALK, so it is blue, and
	# the men who cannot get there this turn stay blue but go steady — the same
	# way the board already separates "you can act on this" from "still yours".
	var movers := _state.move_from_cells()
	var can_reach: Array[Vector2i] = []
	for cell in movers:
		for target in _state.move_targets(cell):
			# What "getting there" means depends on what possession is: standing
			# ON the ball underfoot, standing next to it under the old rule.
			var got := target == _state.ball if MatchState.experiment_underfoot \
				else maxi(absi(target.x - _state.ball.x), absi(target.y - _state.ball.y)) <= 1
			if got:
				can_reach.append(cell)
				break
	if can_reach.is_empty():
		return
	_fx.clear()
	for cell in movers:
		var reaches := cell in can_reach
		_fx.add_tile(_cell_world(cell.x, cell.y), color_tap, -1.0, reaches)
	# Clearing the board took the tiles away but left every own figure's glow
	# suppressed, because the draw before this one had reported those cells as
	# covered. The result was a team standing on nothing until the next redraw —
	# the answer blanked the rest of the answer. Hand the markers back to
	# everyone this draw isn't already sitting on.
	_update_own_team_markers(movers)
	_play_sfx(SELECT_SOUND, select_sfx_volume_db)


# A combo plays as ONE continuous ball motion through the whole chain — the ball
# never stops. Each chain figure starts its windup EARLY (in anticipation) so its
# boot meets the ball exactly as it arrives and strikes it on in one touch. This
# kills the old "roll, stop, wind up, roll" stutter and stops the ball parking
# under the receiver. Strength (swing + ball speed) scales with distance; the
# kicking foot matches the side the ball comes from.
func _do_combo(shoot_cell: Vector2i) -> void:
	# Snapshot BEFORE executing — execute_combo consumes the chain, and the
	# chain is what the opponent needs to replay this move.
	var chain_played: Array = _state.chain.duplicate()
	var res := _state.execute_combo(shoot_cell)
	if not res["ok"]:
		return
	_net_send(NetAction.combo(chain_played, shoot_cell))
	# Already decided — don't let the old countdown fire mid-animation. This team's
	# turn isn't over though (MOVE/REMOVE still to come): snapshot whatever's left
	# of their pool so _refresh_turn_view can resume it, not hand out a fresh 30s.
	_pool_seconds_left = _turn_timer.time_left
	_turn_timer.stop()
	_busy = true
	_fx.clear()
	print("COMBO -> shoot %s (goal=%s)" % [shoot_cell, res["goal"]])
	# path = [ball_cell, chain_fig_0, ... chain_fig_n (shooter), shoot_cell]
	var path: Array = res["path"]
	if res["goal"]:
		_goal_replay_path = path.duplicate() # see _play_goal_replay
		_goal_replay_scorer = res["scorer"]
	var tween := _play_combo_choreography(path, res, true)
	await tween.finished
	await _after_combo(res)


# Drives the shared kick+ball choreography for a combo's full path: one
# continuous ball motion through the whole chain — the ball never stops, each
# chain figure starts its windup EARLY (in anticipation) so its boot meets the
# ball exactly as it arrives and strikes it on in one touch. Strength (swing +
# ball speed) scales with distance; the kicking foot matches the side the ball
# comes from. Used TWICE for a scoring combo: once for the live action
# (trigger_goal_cam=true, may hard-cut to the goal cinematic cameras), and
# again, unmodified, by _play_goal_replay() for the top-down instant replay
# (trigger_goal_cam=false — same kicks/contacts/arcs/keeper dive, just no
# camera cut/slow-mo/decluttering, since the replay uses its own fixed camera
# and shows everyone). Returns the ball's tween; caller awaits .finished.
func _play_combo_choreography(path: Array, res: Dictionary, trigger_goal_cam: bool) -> Tween:
	var n := path.size()

	# 1) Per-segment ball travel times; the opening roll gets room for a windup.
	var durs: Array[float] = []
	for k in range(n - 1):
		durs.append(_roll_dur(path[k], path[k + 1]))
	durs[0] = maxf(durs[0], first_touch_windup)

	# 2) When the ball reaches each cell (cumulative).
	var arrive: Array[float] = [0.0]
	for k in range(n - 1):
		arrive.append(arrive[k] + durs[k])

	# 3) Schedule every chain figure's kick to CONTACT the ball on arrival —
	#    starting the windup earlier, overlapping the incoming roll. Also work
	#    out the REAL point the ball should meet at each kicker: not the cell
	#    center, but the kicker's actual toe-bone position at contact (measured
	#    offline, see PlayerRig.get_contact_offset), rotated by the same facing
	#    _face_toward() will give them — otherwise the timing can be perfect and
	#    the ball still visually connects with the wrong part of the leg (or
	#    misses it) because it was never aimed at where the boot actually is.
	var ball_points: Array[Vector3] = []
	for cell in path:
		ball_points.append(_ball_world(cell))
	for i in range(1, n - 1):
		var from_cell: Vector2i = path[i]
		var to_cell: Vector2i = path[i + 1]
		var is_final: bool = i == n - 2
		var cells := _cells(from_cell, to_cell)
		var power := _power(cells)
		var kind := "pass"
		if is_final and (res["goal"] or cells >= shot_strike_cells):
			kind = "strike"
			power = maxf(power, 0.6)  # a shot always reads as powerful, even up close
		var kicker: Node3D = _node_at.get(from_cell)
		var contact := 0.0
		var jitter := 1.0
		if kicker is PlayerRig:
			# Roll the jitter ONCE and reuse it for both the schedule estimate
			# and the actual playback, so the real contact lands exactly when
			# predicted instead of drifting by up to kick_speed_jitter.
			var rig := kicker as PlayerRig
			jitter = rig.roll_kick_jitter()
			contact = rig.contact_delay(kind, power, jitter)
			if not rig.is_goalkeeper():
				var left := _incoming_on_left(from_cell, path[i - 1], to_cell)
				var d := _cell_world(to_cell.x, to_cell.y) - _cell_world(path[i - 1].x, path[i - 1].y)
				if Vector2(d.x, d.z).length() >= 0.001:
					var yaw := atan2(d.x, d.z) + deg_to_rad(player_facing_offset)
					var offset := rig.get_contact_offset(kind, left)
					# offset is the TOE's position — the ball's CENTER must sit one
					# radius above that (same convention as _ball_world()), or a low
					# contact point (the strike's toe offset is only 0.05 up) sinks
					# the ball's rendered sphere down into the pitch mesh.
					ball_points[i] = (_cell_world(from_cell.x, from_cell.y) + Basis(Vector3.UP, yaw) * offset
						+ Vector3(0, BALL_RADIUS * ball_scale, 0))
		# Never start this figure's windup before the PREVIOUS kicker has actually
		# struck the ball (arrive[i - 1]) — on fast/short chained passes the
		# anticipation lead can otherwise exceed the gap between touches, so two
		# (or more) figures end up winding up at the same time, all swinging
		# their leg at once like a chaotic mob instead of one clean chain.
		var start: float = clampf(arrive[i] - contact, arrive[i - 1], arrive[i])
		_schedule_kick(start, from_cell, path[i - 1], to_cell, kind, power, jitter)
		if is_final and res["goal"]:
			_schedule(start, _trigger_gk_dive.bind(res["scorer"]))
			# Cut to the cinematic angle + slow-mo as the scorer begins the strike —
			# the replay pass (trigger_goal_cam=false) skips this: fixed top-down
			# camera throughout, no cut, no hidden figures.
			if trigger_goal_cam and enable_goal_cam:
				_schedule(start, _begin_goal_drama.bind(to_cell, res["scorer"], from_cell))

	# 4) One uninterrupted ball tween through the whole path. Each segment lofts
	#    into an arc scaled by its power (short = grounded roll, long = high ball);
	#    only the final approach eases out as it settles.
	var tween := create_tween()
	_ball.position = ball_points[0]
	_ball_last_pos = _ball.position
	for k in range(n - 1):
		var a := ball_points[k]
		var b := ball_points[k + 1]
		var h := max_ball_arc * _power(_cells(path[k], path[k + 1]))
		# The scoring shot flies THROUGH the line into the net, with a bigger arc.
		if k == n - 2 and res["goal"]:
			b = _net_point(path[k + 1])
			h = goal_shot_arc
		var tw := tween.tween_method(_set_ball_arc.bind(a, b, h), 0.0, 1.0, durs[k])
		if k == n - 2:
			tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			tw.set_trans(Tween.TRANS_LINEAR)
	return tween


# The point INSIDE the net a scoring ball flies to: past the goal line (outward),
# up at net height. Which way is "into the goal" depends on which end it is.
func _net_point(goal_cell: Vector2i) -> Vector3:
	var out_dir := -1.0 if goal_cell.y * 2 < Board.ROWS else 1.0
	return _cell_world(goal_cell.x, goal_cell.y) + Vector3(0.0, net_hit_height, out_dir * net_depth)


# Places the ball along segment a->b at progress t, lofted into an arc of peak
# height h (0 = flat roll). Driven by the combo tween.
func _set_ball_arc(t: float, a: Vector3, b: Vector3, h: float) -> void:
	if _ball == null:
		return
	_ball.position = a.lerp(b, t) + Vector3.UP * (h * sin(PI * t))


# Continuous-ball helpers -----------------------------------------------------
# Time for the ball to cross one segment (distance * pace, clamped so it reads).
func _roll_dur(a: Vector2i, b: Vector2i) -> float:
	var d := _ball_world(a).distance_to(_ball_world(b))
	return clampf(d * ball_roll_time_scale * _ball_pace(_cells(a, b)), ball_roll_min_duration, ball_roll_max_duration)


# Runs `cb` after `delay` seconds (or now if it's already due).
func _schedule(delay: float, cb: Callable) -> void:
	if delay <= 0.001:
		cb.call()
	else:
		get_tree().create_timer(delay).timeout.connect(cb)


func _schedule_kick(delay: float, at_cell: Vector2i, from_cell: Vector2i, to_cell: Vector2i, kind: String, power: float, jitter: float) -> void:
	_schedule(delay, _fire_kick.bind(at_cell, from_cell, to_cell, kind, power, jitter))


# Fired at windup-start: the figure turns to the target and swings; its contact
# frame is timed to land as the continuously-rolling ball reaches its cell.
func _fire_kick(at_cell: Vector2i, from_cell: Vector2i, to_cell: Vector2i, kind: String, power: float, jitter: float) -> void:
	var kicker: Node3D = _node_at.get(at_cell)
	if kicker is PlayerRig:
		_face_toward(kicker, from_cell, to_cell)
		var left := _incoming_on_left(at_cell, from_cell, to_cell)
		(kicker as PlayerRig).kick(kind, power, left, jitter)


# Straight-line distance in cells ("broj polja").
func _cells(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(b.x - a.x), absi(b.y - a.y))


# Distance -> kick power in 0..1 (1-cell tap = 0, full_power_cells+ = 1).
func _power(cells: int) -> float:
	return clampf(float(cells - 1) / float(maxi(full_power_cells - 1, 1)), 0.0, 1.0)


# Ball travel pace for a hop of `cells`: gentle when short/soft, quick when long.
func _ball_pace(cells: int) -> float:
	return lerpf(ball_pace_gentle, ball_pace_strong, _power(cells))


# Does the ball arrive on the kicker's LEFT (facing the target)? Picks the foot.
func _incoming_on_left(at: Vector2i, from: Vector2i, target: Vector2i) -> bool:
	var fwd := _cell_world(target.x, target.y) - _cell_world(at.x, at.y)
	var inc := _cell_world(from.x, from.y) - _cell_world(at.x, at.y)
	fwd.y = 0.0
	inc.y = 0.0
	if fwd.length() < 0.001:
		return false
	var right := Vector3(fwd.z, 0.0, -fwd.x)  # forward rotated -90° about Y
	var on_left := inc.dot(right) < 0.0
	return on_left != invert_kick_foot


func _process(_delta: float) -> void:
	_spin_ball()
	_update_goal_cam()
	_update_turn_timer_display()


# Pushes the whole-seconds countdown to the HUD, only when it actually ticks
# over (avoid poking the label every frame for no reason).
## Tells the opponent when this turn falls due, as an absolute moment in SERVER
## time. Only the player on the clock publishes it — they are the one who rules
## that time is up (see _on_turn_timeout), so they are also the one who says when
## it falls due.
func _publish_turn_deadline(seconds: float) -> void:
	if _net_match == null:
		return
	_net_match.publish_deadline(Net.server_now_ms() + seconds * 1000.0)


func _update_turn_timer_display() -> void:
	if _hud == null:
		return
	if _turn_timer.is_stopped():
		# One clock, always showing whoever is actually on the move — there is no
		# need to label it, since the footer already says whose turn it is.
		#
		# While the opponent is on the clock this counts down to the deadline
		# THEY published rather than to a stopwatch we started ourselves. Both
		# devices are then watching the same instant approach; timing it locally
		# from whenever we learned their turn began is exactly what produced 18
		# seconds here and 10 there.
		if GameFlow.online_mode and _is_remote_turn():
			_show_remote_countdown()
		return
	_timer_dash_shown = false
	var seconds_left: int = ceili(_turn_timer.time_left)
	if seconds_left != _shown_time_left:
		_shown_time_left = seconds_left
		_hud.update_timer(seconds_left)
		# Same "urgent" window as the HUD's big center-pitch countdown (see
		# hud.gd's TIMER_URGENT_AT) — one tick per second while it's showing.
		if seconds_left > 0 and seconds_left <= _hud.TIMER_URGENT_AT:
			_play_sfx(TICK_SOUND, timer_tick_volume_db)



# Rolls the ball visually: spins it about the axis across its travel, by the
# distance covered over its radius. Only horizontal motion drives the spin.
func _spin_ball() -> void:
	if _ball == null:
		return
	var d := _ball.position - _ball_last_pos
	d.y = 0.0
	var dist := d.length()
	if dist > 0.00001:
		var axis := Vector3.UP.cross(d / dist)
		_ball.transform.basis = Basis(axis, dist / (BALL_RADIUS * ball_scale)) * _ball.transform.basis
	_ball_last_pos = _ball.position


# Snaps a figure to face a target cell, so a kick swings toward the ball's
# destination. Same yaw convention as the team's base facing / ball tracking.
func _face_toward(fig: Node3D, from_cell: Vector2i, to_cell: Vector2i) -> void:
	# Goalkeepers always stay facing forward (their spawn facing) — they shuffle
	# along the line and punt the ball out without ever turning their back.
	if fig is PlayerRig and (fig as PlayerRig).is_goalkeeper():
		return
	var d := _cell_world(to_cell.x, to_cell.y) - _cell_world(from_cell.x, from_cell.y)
	if Vector2(d.x, d.z).length() < 0.001:
		return
	fig.rotation_degrees.y = rad_to_deg(atan2(d.x, d.z)) + player_facing_offset


func _after_combo(res: Dictionary) -> void:
	_refresh_hud() # score + card counts, right as MatchState changed them
	# Big center-pitch flash for the calls the footer hint alone reads too
	# quietly for. Awaited, so the banner fully plays (and blocks input via the
	# still-set _busy) before the goal celebration / turn handover below.
	if res["offside"]:
		print("OFFSIDE — goal not given")
		_show_offside(res["offside_shooter"], res["offside_line_row"])
		_play_sfx(WHISTLE_SOUND, whistle_sfx_volume_db)
		Settings.vibrate()
		if _hud != null:
			await _hud.play_announcement("offside")
	# A non-scoring shot ends the turn via next_turn() -> start_turn() inside
	# execute_combo (see its doc comment), same as do_move/hold_and_move — so
	# it can just as easily hand the NEXT team a 3rd-repeated position and
	# card them. A goal instead resets() for kickoff further below (fresh
	# positions, no repetition possible), so this only matters here.
	if not res["goal"]:
		await _announce_stalling_card()
	if res["goal"]:
		print("%s %s  ->  Home %d : %d Away"
			% ["AUTOGOL!" if res.get("own_goal", false) else "GOAL!", res["scorer"],
				_state.score["HomeTeam"], _state.score["AwayTeam"]])
		# Independent of enable_goal_cam — a goal should always be audible,
		# even with the cinematic camera off. Fired here, once, rather than
		# inside _celebrate_goal() (only called when the cam is enabled).
		_play_sfx(GOAL_SOUND, goal_sfx_volume_db)
		Settings.vibrate(120) # longer/stronger than a card buzz — a goal is the biggest moment in the match
		# Stay busy through the celebration so the torn-down board can't take input.
		if enable_goal_cam and _goal_cam != null:
			await _celebrate_goal()
		if enable_goal_replay:
			await _play_goal_replay()
		if res["win"]:
			print("=== %s WINS THE MATCH ===" % res["scorer"])
			GameFlow.last_winner = res["scorer"]
			GameFlow.last_score = _state.score.duplicate()
			# Perspective: the viewing player's own side determines which
			# screen they see — real per-device perspective once Online
			# (Firebase) exists; for now GameFlow.player_side anchors it.
			if GameFlow.player_side == res["scorer"]:
				GameFlow.goto(GameFlow.Screen.WIN_SCREEN)
			else:
				GameFlow.goto(GameFlow.Screen.LOSE_SCREEN)
			return # leaving the scene — stay _busy so no stray input sneaks in first
		# Clear _busy BEFORE _build_match, not after: _build_match ->
		# _refresh_turn_view may immediately hand the new kickoff to the AI
		# (_maybe_ai_turn), which itself starts with "if _busy: return" as
		# its OWN re-entrancy guard — if _busy were still true from this
		# combo/celebration at that point, the AI would silently bail out
		# and never act, leaving its turn stuck forever (this was the actual
		# "AI skips its turn after conceding" bug — clearing busy AFTER
		# _build_match looked safer but actually starved _maybe_ai_turn
		# before it could even start).
		_busy = false
		_build_match(res["kickoff"])
	else:
		_busy = false
		_refresh_turn_view()


# --- Goal cinematic ----------------------------------------------------------
# Two separate cameras we hard-cut between on a goal; the main Camera3D stays
# as authored and untouched.
func _setup_goal_cam() -> void:
	_goal_cam = _make_goal_camera("GoalCamLaunch", goal_cam_fov)
	_goal_cam2 = _make_goal_camera("GoalCamNet", goal_cam2_fov)


func _make_goal_camera(cam_name: String, fov: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = cam_name
	cam.fov = fov
	cam.current = false
	if goal_cam_blur > 0.0:
		var attr := CameraAttributesPractical.new()
		attr.dof_blur_far_enabled = true
		attr.dof_blur_amount = goal_cam_blur
		cam.attributes = attr
	add_child(cam)
	return cam


# --- Goal cam: static shot positioning + cut trigger --------------------------
# How far the ball has travelled from the shooter toward the goal, along the
# shot axis, as a 0..1 fraction (0 = still at the shooter, 1 = at the goal) —
# the ONLY thing either camera's transform depends on at runtime is whether
# this has crossed goal_cam_cut_progress (see _update_goal_cam); neither
# camera's position/orientation is ever recomputed once set.
func _goal_shot_progress(ball_pos: Vector3) -> float:
	var flat_ball := Vector3(ball_pos.x, 0.0, ball_pos.z)
	var s := (flat_ball - _goal_shooter_flat).dot(_goal_shot_dir)
	return clampf(s / _goal_shot_flat_dist, 0.0, 1.0)


# Cam A ("launch"): behind the SHOOTER's cell along the shot axis, offset to
# one side for an over-the-shoulder angle, looking toward goal centre. Set
# once at the strike and never touched again.
func _place_goal_cam_launch() -> void:
	var behind := _goal_shooter_flat - _goal_shot_dir * goal_cam_back + _goal_side_dir * goal_cam_side
	var pos := Vector3(
		clampf(behind.x, -6.3, 6.3),
		_goal_cam_base_y + goal_cam_height,
		clampf(behind.z, -7.5, 7.5))
	_goal_cam.global_position = pos
	_goal_cam.look_at(_goal_center, Vector3.UP)
	_goal_cam.fov = goal_cam_fov
	_set_goal_cam_dof(_goal_cam)


# Cam B ("net"): beside the goal MOUTH at net height, looking back across it —
# a fixed broadcast-style angle the ball flies INTO. Set once at the strike
# (positioned already, just not yet `current`) and never touched again except
# for the post-impact FOV push-in (see _celebrate_goal).
func _place_goal_cam_net() -> void:
	var goal_flat := Vector3(_goal_center.x, 0.0, _goal_center.z)
	var beside := goal_flat + _goal_shot_dir * goal_cam2_depth + _goal_side_dir * goal_cam2_side
	var pos := Vector3(
		clampf(beside.x, -6.3, 6.3),
		_goal_cam_base_y + goal_cam2_height,
		clampf(beside.z, -7.5, 7.5))
	_goal_cam2.global_position = pos
	_goal_cam2.look_at(_goal_center, Vector3.UP)
	_goal_cam2.fov = goal_cam2_fov
	_set_goal_cam_dof(_goal_cam2)


# Both shots are static now, so the DoF far-blur distance can be set ONCE from
# the camera's fixed distance to the goal, instead of recomputed every frame.
func _set_goal_cam_dof(cam: Camera3D) -> void:
	if cam.attributes is CameraAttributesPractical:
		var attr := cam.attributes as CameraAttributesPractical
		attr.dof_blur_far_distance = cam.global_position.distance_to(_goal_center) + 1.5
		attr.dof_blur_far_transition = 1.5


# Cut to the cinematic angle AND drop into slow motion as the winning strike
# begins, so the whole shot + keeper dive play out like a replay.
# Swaps each goal net's material for the dent shader (keeps the white look, adds
# a bulge uniform). Dense net meshes (~8k verts) deform smoothly.
func _setup_nets() -> void:
	var shader := load("res://assets/shaders/net_dent.gdshader") as Shader
	if shader == null:
		return
	for net_name in ["goal1_net", "goal2_net"]:
		var node := _find_node_named(self, net_name) as MeshInstance3D
		if node == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		node.set_surface_override_material(0, mat)
		_net_mats[net_name] = mat


# Bulges the struck net at the ball's contact point, then springs it back.
func _hit_net() -> void:
	var net_name := "goal1_net" if _goal_net_point.z < 0.0 else "goal2_net"
	var mat: ShaderMaterial = _net_mats.get(net_name)
	if mat == null:
		return
	mat.set_shader_parameter("hit_point", _goal_net_point)
	mat.set_shader_parameter("hit_radius", net_dent_radius)
	mat.set_shader_parameter("push_dir", Vector3(0.0, -0.15, signf(_goal_net_point.z)))
	var tw := create_tween()
	tw.tween_method(_set_net_strength.bind(mat), 0.0, net_dent_strength, 0.04)
	tw.tween_method(_set_net_strength.bind(mat), net_dent_strength, 0.0, net_dent_time) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _set_net_strength(v: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("hit_strength", v)


# The ball doesn't freeze mid-air where it struck the net — gravity takes over:
# an accelerating fall straight down to the ground inside the net, then a short
# settle roll back toward the goal line (the net's give nudging it back), so it
# reads as a real object landing instead of a held pose. _spin_ball (in
# _process) picks up the roll's horizontal motion automatically.
func _drop_ball_to_ground() -> void:
	if _ball == null:
		return
	var landed := Vector3(_goal_net_point.x, _goal_ground_y, _goal_net_point.z)
	var tw := create_tween()
	tw.tween_property(_ball, "position", landed, goal_drop_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)  # accelerating = gravity
	if goal_settle_roll > 0.0:
		var back_dir := -signf(_goal_net_point.z - _goal_center.z)
		var settle := landed + Vector3(0.0, 0.0, back_dir * goal_settle_roll)
		tw.tween_property(_ball, "position", settle, 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# Send the keeper into the dive AS the shot is struck, not after it's already
# in the net — so the miss reads as a beaten attempt, not a late reaction.
# Shared by the live shot and the top-down replay (see _play_combo_choreography) —
# the dive itself isn't cinematic-camera-specific, only _begin_goal_drama's
# framing/hiding/slow-mo below is.
func _trigger_gk_dive(scorer_team: String) -> void:
	var defender: String = "AwayTeam" if scorer_team == "HomeTeam" else "HomeTeam"
	var gk := _find_gk(defender)
	if gk is PlayerRig:
		(gk as PlayerRig).gk_miss()


func _begin_goal_drama(goal_cell: Vector2i, scorer_team: String, shooter_cell: Vector2i) -> void:
	_goal_out_dir = -1.0 if goal_cell.y * 2 < Board.ROWS else 1.0
	_goal_center = _cell_world(goal_cell.x, goal_cell.y) + Vector3(0.0, net_hit_height, 0.0)
	_goal_net_point = _net_point(goal_cell)
	_goal_ground_y = _ball_world(goal_cell).y
	_goal_cam_base_y = _cell_world(goal_cell.x, goal_cell.y).y + 0.6
	_goal_flight_d0 = maxf(_ball.position.distance_to(_goal_center), 0.5)
	# The shot axis (shooter -> goal, flattened) both cams are built on.
	var shooter_pos: Vector3 = _cell_world(shooter_cell.x, shooter_cell.y)
	_goal_shooter_flat = Vector3(shooter_pos.x, 0.0, shooter_pos.z)
	var goal_flat := Vector3(_goal_center.x, 0.0, _goal_center.z)
	var flat_to_goal := goal_flat - _goal_shooter_flat
	_goal_shot_flat_dist = maxf(flat_to_goal.length(), 0.5)
	_goal_shot_dir = flat_to_goal.normalized() if flat_to_goal.length() > 0.01 else Vector3(0, 0, _goal_out_dir)
	_goal_side_dir = Vector3(-_goal_shot_dir.z, 0.0, _goal_shot_dir.x) * goal_cam_side_sign
	# Place both static shots now, THEN hard-cut to Cam A — Cam B sits ready
	# and armed, waiting for _update_goal_cam to cut to it once the ball
	# crosses goal_cam_cut_progress.
	_place_goal_cam_launch()
	_place_goal_cam_net()
	_goal_cam.current = true
	_goal_cam2.current = false
	_goal_cam_cut_done = false
	_goal_cam_follow = true
	if hide_stadium_dressing_during_play:
		_set_stadium_dressing_visible(true) # this is the one moment it's worth seeing
	if goal_slowmo < 1.0:
		Engine.time_scale = goal_slowmo
	# Declutter the cinematic: hide every figure except the shooter and the
	# keeper being beaten, so nobody else can stand between the camera and the
	# action. Happens on the exact frame the camera hard-cuts to the goal cam
	# (no pan/fade to notice it in), and _build_match() throws every figure
	# away and respawns fresh ones once the celebration ends, so there's
	# nothing to un-hide afterward. (The top-down replay that follows shows
	# everyone again — see _play_goal_replay.)
	var shooter: Node3D = _node_at.get(shooter_cell)
	var gk := _find_gk("AwayTeam" if scorer_team == "HomeTeam" else "HomeTeam")
	for cell in _node_at:
		var fig = _node_at[cell]
		if fig is PlayerRig and fig != shooter and fig != gk:
			fig.visible = false


# Each frame during the scoring flight: NEITHER camera moves — this only
# watches the ball's progress along the shot axis and, the single time it
# crosses goal_cam_cut_progress, hard-cuts from Cam A to Cam B (an edit, not a
# pan). Cam A holds the "launch" framing right up to the cut; Cam B was
# already parked at the goal mouth the whole time, waiting.
func _update_goal_cam() -> void:
	if not _goal_cam_follow or _goal_cam_cut_done or _goal_cam2 == null or _ball == null:
		return
	if _goal_shot_progress(_ball.position) >= goal_cam_cut_progress:
		_goal_cam_cut_done = true
		_goal_cam.current = false
		_goal_cam2.current = true


# The ball has just reached the net: slow-mo ends HERE (impact, fall, and the
# keeper's reaction all play at normal speed) — only the flight was slow-mo.
# Cam B (already the current camera, or cut to it now if the shot was too
# short/close to ever cross goal_cam_cut_progress) holds on the settling ball
# while its FOV slowly pushes in for a dramatic close finish — a lens zoom
# only, never a position/rotation change — then hands the view back.
func _celebrate_goal() -> void:
	Engine.time_scale = 1.0
	if not _goal_cam_cut_done and _goal_cam2 != null:
		_goal_cam_cut_done = true
		_goal_cam.current = false
		_goal_cam2.current = true
	_hit_net()  # the ball has just reached the net — bulge it
	_drop_ball_to_ground()  # ...and gravity takes it from there
	if _goal_cam2 != null:
		create_tween().tween_property(_goal_cam2, "fov", goal_cam_zoom_fov, goal_cam_hold) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(goal_cam_hold).timeout
	_restore_camera()


func _restore_camera() -> void:
	_goal_cam_follow = false
	if _goal_cam != null:
		_goal_cam.current = false
	if _goal_cam2 != null:
		_goal_cam2.current = false
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.current = true
	if hide_stadium_dressing_during_play:
		_set_stadium_dressing_visible(false)


# --- Goal replay (see the "Goal Replay" export group) -------------------------
func _setup_replay_cam() -> void:
	_replay_cam = Camera3D.new()
	_replay_cam.name = "GoalReplayCam"
	_replay_cam.fov = replay_fov
	_replay_cam.current = false
	# A duplicate of the main WorldEnvironment (same sky/lighting/tonemap),
	# with only saturation pulled down — Camera3D.environment overrides the
	# scene's WorldEnvironment for this camera alone, so live gameplay is
	# untouched and only the replay reads desaturated.
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env := world_env.environment.duplicate() as Environment
		env.adjustment_enabled = true
		env.adjustment_saturation = replay_saturation
		_replay_cam.environment = env
	add_child(_replay_cam)


# The "R"/REPLAY tag, vignette and flash are real scene nodes (GoalReplayTag/*
# in main.tscn, a sibling of HUD so they stay visible while HUD gets hidden) —
# select RLabel in the Scene dock to tune font/colour/position. The
# vignette's actual texture is procedural (depends on the
# tunable replay_vignette_strength export), so it's generated here at runtime,
# same pattern as BoardFx's tile texture.
func _setup_replay_tag() -> void:
	_replay_tag = get_node_or_null("GoalReplayTag")
	if _replay_tag == null:
		return
	var vignette := _replay_tag.get_node_or_null("Vignette") as TextureRect
	if vignette != null:
		vignette.texture = _make_vignette_tex(replay_vignette_strength)


# Straight down, centred over the pitch — computed from two opposite corner
# cells (not a hand-tuned position) so it stays centred if the pitch/grid
# origin ever moves. Never touched again once placed, same as the cinematic's
# two cams: only the ball moves during the replay.
## Same distance-only auto-fit as _fit_camera(), just for a LOCKED straight-down
## angle instead of the editor-tuned one: the whole pitch (+goal frames/nets,
## same _fit_meshes/_field_corners the main camera fits against) must stay in
## frame on every screen, never a fixed guessed height that ends up cropping
## it — that read as "zoomed in" compared to the normal gameplay view.
func _place_replay_cam() -> void:
	_replay_cam.fov = replay_fov
	if _fit_meshes.is_empty():
		return
	var center := (_cell_world(0, 0) + _cell_world(Board.COLS - 1, Board.ROWS - 1)) * 0.5
	# Straight down, but yawed with the player: the replay must read the same way
	# round as the match they just watched, or the away player sees the goal
	# they conceded played back from the other end.
	var replay_yaw := PI if GameFlow.player_side == "AwayTeam" else 0.0
	var cam_basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), replay_yaw, 0.0))
	var right := cam_basis.x
	var up := cam_basis.y
	var fwd := -cam_basis.z # Godot cameras look down -Z
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var t := tan(deg_to_rad(replay_fov) * 0.5)
	var tan_h: float
	var tan_v: float
	if _replay_cam.keep_aspect == Camera3D.KEEP_HEIGHT:
		tan_v = t
		tan_h = t * aspect
	else:
		tan_h = t
		tan_v = t / aspect
	var m := 1.0 + camera_fit_margin
	var s := 0.0
	for corner in _field_corners():
		var v := corner - center
		var a := v.dot(fwd)
		s = maxf(s, absf(v.dot(right)) * m / tan_h - a)
		s = maxf(s, absf(v.dot(up)) * m / tan_v - a)
	_replay_cam.global_transform = Transform3D(cam_basis, center - fwd * s)


func _show_replay_tag(v: bool) -> void:
	if _replay_tag == null:
		return
	_replay_tag.visible = v
	if _replay_tag_tween != null and _replay_tag_tween.is_valid():
		_replay_tag_tween.kill()
	if not v:
		return
	var label := _replay_tag.get_node("RLabel") as Label
	label.modulate.a = 1.0
	var half := 0.5 / maxf(replay_r_blink_hz, 0.1)
	# ignore_time_scale: this is a UI overlay, not part of the slow-mo'd 3D
	# scene — without it, Engine.time_scale (replay_slowmo, as low as 0.05)
	# stretches each half-cycle so far that the replay is often over before a
	# single blink completes, reading as "just sitting there dim" rather than
	# an actual blink.
	_replay_tag_tween = create_tween().set_loops()
	_replay_tag_tween.set_ignore_time_scale(true)
	_replay_tag_tween.tween_property(label, "modulate:a", 0.15, half)
	_replay_tag_tween.tween_property(label, "modulate:a", 1.0, half)


# Radial black-to-transparent gradient (opaque near the corners, clear at
# centre) — same procedural-Image technique as BoardFx's tile texture, just
# radial instead of a rounded square. Alpha-blended over everything else on
# GoalReplayTag, so it darkens the edges without needing a shader/blend mode.
func _make_vignette_tex(strength: float) -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var center := Vector2(s, s) * 0.5
	var max_d := center.length()
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(center) / max_d
			var a := clampf((d - 0.35) / 0.65, 0.0, 1.0) * strength
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a))
	return ImageTexture.create_from_image(img)


# Broadcast-style "cut to replay": a quick white flash at NORMAL speed (called
# before Engine.time_scale drops for the slow-mo) as the top-down camera cuts
# in. Awaited, so the choreography/slow-mo only starts once the flash has
# actually cleared.
func _flash_replay_transition() -> void:
	if _replay_tag == null:
		return
	var rect := _replay_tag.get_node_or_null("FlashRect") as ColorRect
	if rect == null:
		return
	rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, replay_flash_time)
	await tw.finished


## ONE more beat after the cinematic: a fixed top-down slow-mo retrace of the
## FULL build-up (every pass, not just the final strike), fullscreen with the
## HUD hidden and a blinking "R" — a broadcast instant-replay beat. Purely
## visual: match state is already fully applied (see execute_combo/_do_combo)
## — this just re-tweens the ball back along its already-recorded path, this
## time under the second, separate, single static top-down camera.
func _play_goal_replay() -> void:
	if _goal_replay_path.size() < 2 or _replay_cam == null or _ball == null:
		return
	# The cinematic (see _begin_goal_drama) hid every figure but the shooter
	# and keeper to declutter its close shots — the replay shows the WHOLE
	# build-up from above, so everyone needs to be back on screen for it.
	for cell in _node_at:
		_node_at[cell].visible = true
	if _hud != null:
		_hud.visible = false
	_show_replay_tag(true)
	_place_replay_cam()
	_replay_cam.current = true
	await _flash_replay_transition() # normal speed — the cut itself, before slow-mo
	Engine.time_scale = replay_slowmo
	# Same choreography as the live shot (kicks, contact timing, ball arcs, the
	# keeper's dive) — replayed a second time under the fixed top-down camera,
	# just without the cinematic's own camera cut/hiding (trigger_goal_cam=false).
	var replay_res := {"goal": true, "scorer": _goal_replay_scorer}
	var tween := _play_combo_choreography(_goal_replay_path, replay_res, false)
	await tween.finished
	# Back to normal speed BEFORE the hold, not after: the keeper's gk_miss
	# dive is scheduled mid-flight (see _play_combo_choreography) and can
	# still be mid-animation when the ball tween itself finishes — if the
	# hold stayed in slow-mo too, its real-world length (and whether the dive
	# visibly finishes at all) would silently depend on replay_slowmo. This
	# way replay_hold_after is always a fixed, predictable pause that gives
	# any tail-end animation time to actually complete before the cut back.
	Engine.time_scale = 1.0
	await get_tree().create_timer(replay_hold_after).timeout
	_replay_cam.current = false
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.current = true
	_show_replay_tag(false)
	if _hud != null:
		_hud.visible = true


func _find_gk(team_name: String) -> Node3D:
	var root := get_node_or_null(team_name)
	if root == null:
		return null
	for c in root.get_children():
		if String(c.name).begins_with("gk"):
			return c as Node3D
	return null


# Draws the "offside line" (dashed, full pitch width) at the defensive line's
# row — like the linesman's flag line — plus a highlight on the flagged
# figure, so it's visually obvious WHY it was offside, not just a console
# print. Fades out after `offside_flash_seconds` so it doesn't linger.
func _show_offside(shooter: Vector2i, line_row: int) -> void:
	_fx_effects.clear()
	if line_row >= 0:
		var left := _cell_world(0, line_row)
		var right := _cell_world(Board.COLS - 1, line_row)
		_fx_effects.set_trail(PackedVector3Array([left, right]), color_offside)
	if shooter != NO_CELL:
		_fx_effects.add_tile(_cell_world(shooter.x, shooter.y), color_offside)
	var timer := get_tree().create_timer(offside_flash_seconds)
	timer.timeout.connect(_fx_effects.clear)


# --- MOVE: move one figure by one cell --------------------------------------
# Figures (cylinder hit-test) are ALWAYS checked before empty target tiles
# (flat hit-test) — see the comment on _combo_tap for why: otherwise tapping
# the already-selected figure again can get misread as tapping a nearby
# target tile its tall body visually overlaps under the tilted camera.
func _move_click(screen_pos: Vector2) -> void:
	var pickable := _state.own_cells() if _holding else _state.move_from_cells()
	if _move_from == NO_CELL:
		var fig_cell := _resolve_target(screen_pos, pickable, TAP_HIT_RADIUS)
		if fig_cell != NO_CELL:
			_move_from = fig_cell
			_draw_move(fig_cell)
			_play_sfx(FIELD_TAP_SOUND, field_tap_volume_db)
			return
		# Nothing picked and the tap landed on the ball — this is the "how do I
		# get it?" moment, and it deserves an answer rather than silence.
		_hint_ball_carriers(screen_pos)
		return
	var fig_hit := _resolve_target(screen_pos, pickable, TAP_HIT_RADIUS)
	if fig_hit != NO_CELL:
		if fig_hit != _move_from:
			# While hold-selecting some OTHER figure, tapping the one that's
			# actually adjacent to the ball always means "start a combo on
			# THIS one instead" — same as tapping it fresh from neutral (see
			# _combo_tap) — not just "hold this one too". Without this it
			# read as just another blue hold candidate instead of properly
			# (re)entering the chain (orange), which is what tapping a
			# starter is supposed to look like everywhere else.
			if _holding and fig_hit in _state.combo_starters() and _state.begin(fig_hit):
				_holding = false
				_move_from = NO_CELL
				_play_sfx(SELECT_SOUND, select_sfx_volume_db)
				_draw_combo()
				return
			_move_from = fig_hit # reselect a different figure
			_draw_move(fig_hit)
			_play_sfx(FIELD_TAP_SOUND, field_tap_volume_db)
		elif _holding:
			# Tapping the SAME figure again while it's a hold-move candidate
			# (not a real reactive move) deselects it entirely, back to the
			# neutral "every figure is tappable" combo view — same gesture as
			# tapping the ball-adjacent starter again (see _combo_tap).
			_holding = false
			_move_from = NO_CELL
			_draw_combo()
		else:
			# Same gesture during a real MOVE. It used to be a deliberate no-op,
			# on the grounds that you have to move SOMEBODY so letting go leads
			# nowhere — but one gesture that sometimes releases and sometimes
			# doesn't is worse than one that always does, and tapping a different
			# figure already changed the selection anyway.
			_move_from = NO_CELL
			_draw_movable()
		return
	var dest := _resolve_target(screen_pos, _state.move_targets(_move_from), TAP_HIT_RADIUS)
	if dest != NO_CELL:
		_play_sfx(FIELD_TAP_SOUND, field_tap_volume_db)
		var was_holding := _holding
		_holding = false
		_apply_move(_move_from, dest, was_holding)
		return
	if _holding:
		# A miss (tap that hit neither a figure nor a move target) must NOT
		# lose the selection while holding — figures near the ball are often
		# boxed in tight (ball + other pieces + the move-range cap), so a
		# slightly-off tap trying to confirm a target was reading as "cancel"
		# and dropping the whole selection. Only tapping the SAME figure
		# again (handled above) or a real target backs out now.
		return
	_move_from = NO_CELL # cancel selection
	_fx.clear()
	# Same as the ball hint above: the figure that was selected had its glow
	# suppressed while it wore an FX tile, and clearing the tile has to hand it
	# back or cancelling leaves that one player standing on bare grass.
	_update_own_team_markers()


## Shared by every action that can end a turn (execute_combo/do_move/
## hold_and_move/remove_figure/forfeit, via _do_combo/_apply_move/_remove_at/
## _on_turn_timeout) — checks MatchState.last_move_card/last_card_team (fresh
## after EVERY one of those calls, see start_turn()) and, if a card just
## fired, plays the yellow/red banner + whistle for whichever team
## last_card_team names — not necessarily whoever's action just ran, see
## hold_and_move's doc comment. Exactly one offence is bookable: letting a
## MOVE's clock run out (MatchState.forfeit).
func _announce_stalling_card() -> void:
	# Both devices show this banner, so it has to say WHO was booked. Unnamed, a
	# player who had merely been waiting out the opponent's clock could easily
	# read it as their own card.
	var who := _carded_label()
	if _state.last_move_card == "yellow":
		print("YELLOW CARD: %s" % _state.last_card_team)
		_play_sfx(WHISTLE_SOUND, whistle_sfx_volume_db)
		Settings.vibrate()
		if _hud != null:
			await _hud.play_announcement("yellow", who)
	elif _state.last_move_card == "red":
		print("RED CARD: %s" % _state.last_card_team)
		_play_sfx(WHISTLE_SOUND, whistle_sfx_volume_db)
		Settings.vibrate(90) # a notch stronger than yellow — matches the higher severity
		if _hud != null:
			await _hud.play_announcement("red", who)


## Name (online) or country code (offline) of whoever the card belongs to.
## Counts down the opponent's turn from the shared deadline.
##
## Shows a dash only until their first deadline arrives (the very start of a
## match, before anyone has published one) — a number would be a guess there.
func _show_remote_countdown() -> void:
	if _remote_deadline_ms <= 0.0:
		if not _timer_dash_shown:
			_timer_dash_shown = true
			_hud.update_timer(-1)
		return
	_timer_dash_shown = false
	var raw := (_remote_deadline_ms - Net.server_now_ms()) / 1000.0
	var left := maxi(ceili(raw), 0)
	if left != _shown_time_left:
		_shown_time_left = left
		_hud.update_timer(left)
	# Their clock ran out and their forfeit never reached us. Whatever the cause,
	# the board will not change again on its own, and the player deserves to be
	# told that rather than left tapping at a game that has quietly stopped.
	if raw < -REMOTE_STALL_GRACE and not _remote_stall_said:
		_remote_stall_said = true
		push_warning("REMOTE STALL: %.0fs past their deadline, nothing received (applied=%s)" \
			% [-raw, _net_match.applied if _net_match != null else -1])
		_hud.set_footer_text("Still waiting for your opponent...", Color.WHITE)


func _carded_label() -> String:
	var team := _state.last_card_team
	if team == "":
		return ""
	if GameFlow.online_mode:
		var labels := _online_labels()
		return String(labels["home"] if team == "HomeTeam" else labels["away"])
	return CountryKits.get_code(home_country if team == "HomeTeam" else away_country)


## `as_hold`: use MatchState.hold_and_move (declining to shoot, see there)
## instead of the reactive MatchState.do_move — same animation either way,
## just a different underlying rules call. The card announcement below reads
## _state.last_card_team, NOT whoever made this particular move: a stalling
## card now comes from position repetition (see MatchState's "cards /
## stalling" doc comment), which can card the OTHER team — e.g. this reactive
## move hands a 3rd-repeated position straight back to the team that already
## has the ball, carding them, not the mover.
func _apply_move(from: Vector2i, to: Vector2i, as_hold: bool = false) -> void:
	var moved: bool = _state.hold_and_move(from, to) if as_hold else _state.do_move(from, to)
	if not moved: # also advances the turn
		return
	_net_send(NetAction.hold(from, to) if as_hold else NetAction.move(from, to))
	# Same reason _do_combo snapshots+stops here: do_move() may have already
	# flipped _state.current to the OTHER team (a reactive move that used up
	# moves_left, or a mandatory tidy-up move ending the turn) — if left
	# running, the OLD team's countdown keeps ticking, unmanaged, for the
	# whole slide animation below and could even fire _on_turn_timeout() for
	# the wrong team mid-animation. And when do_move() DIDN'T change teams
	# (still mid reactive-move-pair), _refresh_turn_view()'s "same team
	# continuing" branch needs an accurate _pool_seconds_left to resume from
	# — without this snapshot it was reading whatever _do_combo (a DIFFERENT
	# action) last left there, sometimes its 0.0 default, handing the next
	# decision only a ~0.05s timer instead of the real time left. This was
	# the concrete "next player gets the previous player's last few seconds"
	# bug a human reported.
	_pool_seconds_left = _turn_timer.time_left
	_turn_timer.stop()
	_tutorial_did("move", to)
	var fig: Node3D = _node_at[from]
	_node_at.erase(from)
	_node_at[to] = fig
	print("MOVE: %s -> %s" % [from, to])
	_move_from = NO_CELL
	# Stay busy for the WHOLE slide, same as _do_combo does for a shot —
	# without this, nothing stopped the next decision (another AI move, or
	# even the human's own next tap) from firing before this figure had
	# visually finished sliding, so moves could overlap/cut each other off
	# and the whole turn sequence read as sped-up no matter how long
	# move_duration was tuned to.
	_busy = true
	# Turn and jog to the new cell, then settle back into idle on arrival. A
	# slide can now cover many cells (see MatchState.move_targets), so the
	# jog's duration scales with distance — a fixed 0.28s regardless of length
	# would have made anything past 1 cell read as a skate/teleport. The
	# stride RATE also ramps with distance (see jog_speed_scale_min/max) since
	# the clip itself has no baked ground speed to sync duration against.
	_face_toward(fig, from, to)
	var move_cells := maxi(absi(to.x - from.x), absi(to.y - from.y))
	var move_duration := maxf(move_min_duration, move_duration_per_cell * move_cells)
	_play_running_sound(move_cells, move_duration)
	if fig is PlayerRig:
		var jog_t := clampf(float(move_cells - 1) / float(maxi(jog_speed_scale_max_cells - 1, 1)), 0.0, 1.0)
		(fig as PlayerRig).jog(lerpf(jog_speed_scale_min, jog_speed_scale_max, jog_t))
	var tween := create_tween()
	tween.tween_property(fig, "position", _cell_world(to.x, to.y), move_duration).set_trans(Tween.TRANS_SINE)
	# The ball travels alongside him whenever this move touched it — he dribbled
	# it there, or he walked onto a loose one and it settled at his feet. Without
	# this it stays put through the whole slide and then teleports on arrival,
	# which reads as the ball being kicked by nobody.
	if _ball != null:
		var ball_rest := _ball_world(_state.ball)
		if not _ball.position.is_equal_approx(ball_rest):
			tween.parallel().tween_property(_ball, "position", ball_rest, move_duration) \
				.set_trans(Tween.TRANS_SINE)
	if fig is PlayerRig:
		tween.tween_callback((fig as PlayerRig).idle.bind(false))
	await tween.finished
	await _announce_stalling_card()
	_busy = false
	_refresh_turn_view()


# --- View refresh (mirror MatchState) ---------------------------------------
func _refresh_turn_view() -> void:
	_move_from = NO_CELL
	if _state.phase == MatchState.Phase.COMBO:
		_draw_combo()
	elif _state.phase == MatchState.Phase.REMOVE:
		_draw_remove()
	else:
		# Phase.MOVE, nothing picked up yet — highlight whichever figures are
		# actually tappable (MatchState.move_from_cells: every own figure for
		# a REACTIVE move, only the shooter for a BONUS move — see do_move).
		# Without this the pitch reads as frozen whenever a MOVE step follows
		# another MOVE step (moves_left still > 0 but nothing drawn), and the
		# player can time out never realizing a figure — or a second reactive
		# move — was still theirs to take.
		_draw_movable()
	print("TURN: %s  phase=%s" % [_state.current, MatchState.Phase.keys()[_state.phase]])
	_shown_time_left = -1
	if _tutorial != null:
		# No clock while you are being taught. A countdown here books you for
		# time-wasting for reading the instructions — the tutorial asks you to
		# stop and take in a sentence, then punishes you for doing it. There is
		# also nothing to be fair about: no opponent is waiting on you.
		_turn_timer.stop()
		if _hud != null:
			_hud.update_timer(-1)  # also clears the big centre-pitch countdown
	elif _state.phase == MatchState.Phase.REMOVE and not (GameFlow.online_mode and _is_remote_turn()):
		# REMOVE used to have no clock at all, because timing it out would have
		# run forfeit() — which cancels pending_removal, so waiting would have
		# DELETED the punishment. That reasoning was sound and the conclusion
		# wasn't: online it left the other player staring at a board that would
		# never change, for as long as the carded one felt like it.
		#
		# It has a clock now, and running it out doesn't cancel anything — it
		# picks for you (see _on_turn_timeout). Waiting is still no escape hatch;
		# it just isn't a hostage situation either.
		#
		# ONLY on the device being punished. This branch used to come before the
		# remote check, so the player merely WAITING for the removal also started
		# a clock and published a deadline over the top of the carded player's —
		# and, because their own timer was then running, the stalled-opponent
		# warning never fired, which is exactly the case it exists for.
		_pool_team = _state.current
		_turn_timer.start(remove_time_limit)
		_publish_turn_deadline(remove_time_limit)
	elif GameFlow.online_mode and _is_remote_turn():
		# No LOCAL timer while the opponent is on the clock — running our own
		# stopwatch from whenever we happened to learn their turn began is what
		# made one device read 18 seconds and the other 10.
		#
		# The display still counts down: it uses the shared deadline they
		# published, so both of us are watching the same instant approach rather
		# than two independent stopwatches. See _update_turn_timer_display.
		_pool_team = _state.current
		_turn_timer.stop()
	elif _state.current != _pool_team:
		# A genuinely new team's turn (next_turn() ran since the last refresh) —
		# fresh full pool. Same team continuing COMBO -> MOVE/REMOVE instead just
		# resumes whatever was left of theirs (see _do_combo's snapshot above).
		_pool_team = _state.current
		_turn_timer.start(turn_time_limit)
		_publish_turn_deadline(turn_time_limit)
	else:
		var carried := maxf(_pool_seconds_left, 0.05)
		_turn_timer.start(carried)
		_publish_turn_deadline(carried)
	if _hud != null:
		# During the tutorial the footer belongs to the lesson. The normal
		# "BRA: move a player" hint was overwriting it the moment the turn view
		# refreshed, so the instruction the player was meant to follow vanished
		# and was replaced by something about a country they aren't playing.
		#
		# Including the finished step: the closing line stays up for a beat
		# before the screen changes, and the move that ended the lesson triggers
		# one more refresh in that window — which is exactly when the turn hint
		# was slipping back in with the last word.
		if _tutorial != null:
			_hud.set_footer_text(_tutorial.prompt(), Color.WHITE)
		else:
			_hud.update_turn_hint(_state.current, _state.phase, "", _state.moves_left)
	_holding = false
	_maybe_ai_turn()


## Single Player only: true when it's currently the AI's own turn to act
## (used both to gate input and to protect _busy from being stomped — see
## _after_combo's use of this right after _build_match()).
func _is_ai_turn() -> bool:
	if not GameFlow.single_player or _state == null:
		return false
	return _state.current != GameFlow.player_side


## If it's now the AI's turn, decide (AIPlayer, pure logic) and execute
## through the SAME functions a human tap would call
## (_do_combo/_apply_move/_remove_at), so it animates identically. A short
## "thinking" pause avoids the move reading as an instant, jarring snap.
const AI_THINK_TIME := 0.6

func _maybe_ai_turn() -> void:
	if _busy or not _is_ai_turn():
		return
	_busy = true
	await get_tree().create_timer(AI_THINK_TIME).timeout
	_busy = false
	var acted := false
	match _state.phase:
		MatchState.Phase.COMBO:
			var shoot := AIPlayer.decide_combo(_state, GameFlow.ai_difficulty)
			if shoot != NO_CELL:
				acted = true
				# Shooting is no longer mandatory (see MatchState.hold_and_move) —
				# should_hold checks whether THIS shot looks bad enough to decline
				# in favour of just repositioning instead.
				if AIPlayer.should_hold(_state, shoot):
					var hold := AIPlayer.decide_move(_state, GameFlow.ai_difficulty)
					if hold.has("from"):
						_apply_move(hold["from"], hold["to"], true)
					else:
						_do_combo(shoot) # no legal hold move somehow — shoot anyway
				else:
					_do_combo(shoot)
		MatchState.Phase.MOVE:
			var decision := AIPlayer.decide_move(_state, GameFlow.ai_difficulty)
			if decision.has("from"):
				acted = true
				_apply_move(decision["from"], decision["to"])
		MatchState.Phase.REMOVE:
			var cell := AIPlayer.decide_removal(_state, GameFlow.ai_difficulty)
			if cell != NO_CELL:
				acted = true
				_remove_at(cell)
	if not acted:
		# Shouldn't happen (the rules guarantee at least one legal action in
		# every phase) — but if AIPlayer ever fails to find one, forfeit
		# rather than leave the turn stuck on the AI with nobody able to act.
		push_warning("AI (%s, phase=%s) found no legal action — forfeiting its turn." \
			% [_state.current, MatchState.Phase.keys()[_state.phase]])
		_state.forfeit()
		_refresh_turn_view()


# Ran out of time to act — forfeit this decision with no move made and move
# straight on to whatever comes next. `true` marks this as a REAL clock
# expiry (the AI's no-legal-action forfeit above deliberately doesn't), which
# is what books a team for time-wasting when a MOVE is what expired — see
# MatchState.forfeit. The announcement goes through the shared card channel,
# same as any other booking.
func _on_turn_timeout() -> void:
	# Online: ONLY the device actually on the clock rules that time is up, and
	# sends that as an action like any other. The waiting player's countdown is
	# information, not a verdict.
	#
	# This is why the turn clock needs no server timestamps at all. If both
	# clients timed the turn themselves they could disagree — one forfeits, the
	# other doesn't, and from there they are playing different games. Asking
	# exactly one device removes the disagreement instead of trying to keep two
	# clocks in step. (A frozen or malicious client that never sends anything is
	# caught by presence — see NetMatch.)
	if GameFlow.online_mode and _is_remote_turn():
		return
	# A red card's removal is not forfeitable — forfeit() cancels the pending
	# removal, so timing out would erase the punishment. Choose for them instead,
	# by the same rule the AI uses: the outfield figure standing furthest from
	# the ball, never the keeper. It is the least damaging piece to lose, so
	# letting the clock run costs you nothing extra beyond the choice itself.
	if _state.phase == MatchState.Phase.REMOVE:
		var cell := AIPlayer.decide_removal(_state, "Hard")
		if cell != NO_CELL:
			print("TIME UP: %s did not choose — removing %s" % [_state.current, cell])
			# _remove_at refreshes the turn view itself. Calling it again here
			# would re-enter the timer branches with the NEW team already set as
			# _pool_team, take the "same team continuing" path, and start their
			# turn on the fraction of a second left over from the last snapshot.
			_remove_at(cell)
			return
	print("TIME UP: %s forfeits (phase=%s)" % [_state.current, MatchState.Phase.keys()[_state.phase]])
	_state.forfeit(true)
	_net_send(NetAction.forfeit())
	await _announce_stalling_card()
	_refresh_turn_view()




## Phase.MOVE with nothing picked up yet: whichever figures are actually
## tappable (MatchState.move_from_cells — every own figure for a REACTIVE move,
## only the shooter for a BONUS move). Without this the pitch reads as frozen
## whenever a MOVE follows another MOVE and nothing is drawn, and the player can
## time out never realising a figure was still theirs to take.
##
## Its own function because deselecting has to get back to exactly this view,
## and a second copy of it would be a second thing to keep in step.
func _draw_movable() -> void:
	_fx.clear()
	var own := _state.move_from_cells()
	for c in own:
		_fx.add_tile(_cell_world(c.x, c.y), color_tap)
	_update_own_team_markers(own)


# Highlights every one of the carded team's figures as a removable target.
func _draw_remove() -> void:
	_fx.clear()
	var own := _state.own_cells()
	for c in own:
		_fx.add_tile(_cell_world(c.x, c.y), color_remove)
	_update_own_team_markers(own)


# `preview` is the cell a live drag is currently snapped to (NO_CELL if none) —
# it gets an extra trail segment and a bigger highlight so the drag feels "live".
func _draw_combo(preview: Vector2i = NO_CELL) -> void:
	_fx.clear()
	if _state.chain.is_empty():
		# EVERY own figure is a real, tappable choice here (see _combo_tap) —
		# tapping a ball-adjacent one begins a combo, any other one starts a
		# hold-move instead (declining the ball this turn) — not just the
		# combo starters, so all of them light up equally. No card-risk
		# warning at THIS stage: tapping a figure here doesn't end the turn
		# by itself (it either opens the chain for a pass/shoot pick, or
		# opens the hold-move target pick) — see combo_shoot_targets/
		# _draw_move below for where the actual risky targets get flagged,
		# right at the point an actual card-triggering action is on offer.
		# The two taps available here do COMPLETELY different things — tap a man
		# beside the ball and you take it and open a chain; tap any other and you
		# decline the ball and simply walk him. They used to look identical, so a
		# player tapping around got possession sometimes and a stroll other
		# times, with nothing on the board to say which was which. That is why
		# people came out of the tutorial still not knowing how to take the ball.
		#
		# No new colour to learn: orange ALREADY means "the ball goes through
		# this one" — it is what a chosen chain figure turns, and what tapping
		# the ball blinks under whoever can play it (see _hint_ball_carriers).
		# This just shows it before you have to guess. The rest stay blue and go
		# steady rather than pulsing, which is this layer's existing way of
		# saying "still yours, but not the thing you're acting on".
		var own := _state.own_cells()
		var carriers := _state.combo_starters()
		for cell in own:
			var on_the_ball := cell in carriers
			_fx.add_tile(_cell_world(cell.x, cell.y),
				color_chain if on_the_ball else color_tap, -1.0, on_the_ball)
		_update_own_team_markers(own)
		return
	# Energy trail: figure -> figure -> (live) drag preview. Deliberately skips
	# the ball itself — it's already visually obvious on its own (a real 3D
	# ball sitting there), so a line TO it only adds a segment that looks
	# awkward crossing behind the shooter whenever they're facing away from
	# it, without conveying anything the eye doesn't already see.
	var pts := PackedVector3Array()
	for c in _state.chain:
		pts.append(_cell_world(c.x, c.y))
	if preview != NO_CELL:
		pts.append(_cell_world(preview.x, preview.y))
	_fx.set_trail(pts, color_trail)
	for c in _state.chain:
		_fx.add_tile(_cell_world(c.x, c.y), color_chain) # orange = chosen chain (active receiver)
	# Orange, not blue. It means one thing everywhere now — the ball can go
	# through this man — and a pass target is exactly that. Blue was left over
	# from when it meant "tappable", and mid-chain that was a lie twice over: you
	# cannot walk anyone here, the turn is already committed to the ball.
	#
	# What separates a man the ball has ALREADY gone through from one it still
	# could is the trail, not the colour — the ribbon is drawn along the chain
	# just above. If that reads too faintly on a phone, this is where to look.
	var pass_targets := _state.combo_pass_targets()
	for c in pass_targets:
		_fx.add_tile(_cell_world(c.x, c.y), color_chain)
	# The ball-adjacent men you did NOT pick. Tapping one of them restarts the
	# chain there (see _combo_tap), so the ball can go through them too — they
	# were simply never drawn at all, which made switching a hidden move.
	var restarts: Array[Vector2i] = []
	for c in _state.combo_starters():
		if not (c in _state.chain):
			restarts.append(c)
			_fx.add_tile(_cell_world(c.x, c.y), color_chain)
	# No target can be flagged as "this one books you" any more: the only
	# bookable offence left is time-wasting (see MatchState.forfeit), which is
	# about the clock, not about where the ball goes — so every shoot target
	# is just a shoot target.
	for c in _state.combo_shoot_targets():
		_fx.add_tile(_cell_world(c.x, c.y), color_shoot)
	if preview != NO_CELL:
		var col := color_chain
		if preview in _state.combo_shoot_targets():
			col = color_shoot
		_fx.add_tile(_cell_world(preview.x, preview.y), col.lightened(0.35), fx_tile_size * 1.1)
	# Chain figures + pass targets are own cells wearing an FX tile right
	# now (shoot targets are always empty cells — see combo_shoot_targets,
	# never a figure) — suppress OwnTeamTileGlow under just those, see
	# _update_own_team_markers's doc comment for why.
	var covered: Array[Vector2i] = []
	covered.append_array(_state.chain)
	covered.append_array(pass_targets)
	covered.append_array(restarts)
	_update_own_team_markers(covered)


# `preview` is the cell a live drag is currently snapped to (NO_CELL if none).
func _draw_move(from: Vector2i, preview: Vector2i = NO_CELL) -> void:
	_fx.clear()
	_fx.add_tile(_cell_world(from.x, from.y), color_tap_selected)
	# No "this one books you" flagging here either — see _draw_combo.
	for c in _state.move_targets(from):
		_fx.add_tile(_cell_world(c.x, c.y), color_move)
	if preview != NO_CELL:
		var pts := PackedVector3Array([_cell_world(from.x, from.y), _cell_world(preview.x, preview.y)])
		_fx.set_trail(pts, color_trail)
		_fx.add_tile(_cell_world(preview.x, preview.y), color_move.lightened(0.35), fx_tile_size * 1.1)
	# move_targets are always EMPTY cells (never a figure) — only `from`
	# itself is an own figure wearing an FX tile right now, see
	# _update_own_team_markers's doc comment for why that matters.
	_update_own_team_markers([from])


func _clear_markers() -> void:
	if _fx != null:
		_fx.clear()


# --- Path debug --------------------------------------------------------------
# Green marker on every cell the piece at `reach_from_cell` could shoot to.
func _build_reach_debug() -> void:
	var overlay := Node3D.new()
	overlay.name = "ReachDebug"
	add_child(overlay)

	var dot := SphereMesh.new()
	dot.radius = 0.12
	dot.height = 0.24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var occupied := {}
	if _state != null:
		for c in _state.pieces:
			occupied[c] = true
	for cell in Board.reachable_from(reach_from_cell, occupied):
		var marker := MeshInstance3D.new()
		marker.mesh = dot
		marker.material_override = mat
		marker.position = _cell_world(cell.x, cell.y) + Vector3(0, 0.1, 0)
		overlay.add_child(marker)
	print("REACH: %d target cells from %s" % [overlay.get_child_count(), reach_from_cell])


# --- Character ----------------------------------------------------------------
func _spawn_character() -> void:
	if character_scene == null:
		return
	var character := character_scene.instantiate()
	add_child(character)
	if character is Node3D:
		var node3d := character as Node3D
		node3d.position = _cell_world(character_cell.x, character_cell.y)
		node3d.rotation_degrees = Vector3(0.0, character_facing_offset, 0.0)
		node3d.scale = Vector3.ONE * character_scale
	character.name = "Character"


func _apply_test_appearance() -> void:
	var character := get_node_or_null("Character") as Node3D
	if character == null:
		return
	var kit := CountryKits.get_kit(test_country, test_kit_variant)
	var hair := PlayerAppearance.hair_for(test_hair_index)
	PlayerAppearance.apply(character, kit, hair, test_number)


# --- Banner fix --------------------------------------------------------------
func _fix_banner() -> void:
	var stadium := get_node_or_null("stadium")
	if stadium == null:
		return
	var banner := _find_node_named(stadium, "banner") as MeshInstance3D
	if banner == null:
		push_warning("No 'banner' mesh under the stadium.")
		return
	var mat := banner.get_active_material(0) as BaseMaterial3D
	if mat == null or mat.albedo_texture == null:
		push_warning("Banner has no albedo texture to rebake.")
		return
	var plate := _composite_decal(mat.albedo_texture, banner_bg, banner_text)
	var m := mat.duplicate() as BaseMaterial3D
	m.albedo_texture = plate
	m.albedo_color = Color.WHITE
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	banner.set_surface_override_material(0, m)


# --- Stadium dressing ----------------------------------------------------------
## Toggles visibility of every STADIUM_DRESSING mesh under the `stadium` node
## (see that const's comment) — off for normal top-down play, on only around
## the goal cinematic pull-back. Silently no-ops for whichever names aren't
## found (keeps this robust if stadium.glb's node set ever changes).
func _set_stadium_dressing_visible(v: bool) -> void:
	var stadium := get_node_or_null("stadium")
	if stadium == null:
		return
	for n in STADIUM_DRESSING:
		var node := stadium.get_node_or_null(n)
		if node != null:
			node.visible = v


# Bakes an OPAQUE texture: solid `bg`, with the source's ALPHA used as a mask to
# paint `fg` on top. (The source's own RGB is ignored — text lives in alpha.)
static func _composite_decal(src: Texture2D, bg: Color, fg: Color) -> Texture2D:
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(bg.r, bg.g, bg.b, 1.0))
	for y in h:
		for x in w:
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				out.set_pixel(x, y, bg.lerp(fg, a))
	return ImageTexture.create_from_image(out)


# --- Camera auto-fit ---------------------------------------------------------
# Runs the first fit one frame late: right after _ready(), the embedded editor
# Game panel (and some platforms) may not have resized the viewport to its
# real size yet, so fitting immediately can read a bogus aspect and send the
# camera flying off. One frame later the size is accurate.
func _fit_camera_deferred() -> void:
	await get_tree().process_frame
	_fit_camera()


# Slides the camera along its own view axis (keeping the angle you set) so the
# whole field fits the current screen aspect, with a margin. Re-runs on resize.
func _fit_camera() -> void:
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam == null or _fit_meshes.is_empty():
		return
	# Capture the transform you tuned in the editor ONCE, before any fit has
	# slid the camera along its own axis.
	if not _cam_ref_set:
		_cam_authored = cam.global_transform
		_cam_ref_set = true

	# Everyone sees their OWN figures at the bottom. The board logic is NOT
	# mirrored for this — only the camera is spun 180 degrees about the pitch
	# centre (the world origin, see Board). That matters: taps are raycast
	# against the real 3D world, so a genuinely turned camera keeps every bit of
	# the tap/drag hit-testing working untouched, whereas mirroring coordinates
	# would have broken all of it (GAME_DESIGN.md §11).
	#
	# Recomputed on EVERY fit rather than once at capture time. Online, the side
	# isn't known until an opponent accepts — which happens long after the first
	# fit — so deciding this once left the guest looking at the board upside
	# down for the whole match.
	_cam_ref = _cam_authored
	if GameFlow.player_side == "AwayTeam":
		_cam_ref = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * _cam_ref

	var cam_basis := _cam_ref.basis.orthonormalized()
	var p0 := _cam_ref.origin
	var right := cam_basis.x
	var up := cam_basis.y
	var fwd := -cam_basis.z # Godot cameras look down -Z

	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return
	var aspect := vp.x / vp.y
	if aspect < 0.15 or aspect > 6.0:
		# A transitional/bogus viewport read (e.g. before the window has
		# settled to its real size) — skip rather than fling the camera off
		# to satisfy a nonsense aspect. The next resize/frame will retry.
		return
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var tan_h: float
	var tan_v: float
	if cam.keep_aspect == Camera3D.KEEP_HEIGHT:
		tan_v = t
		tan_h = t * aspect
	else:
		tan_h = t
		tan_v = t / aspect

	# Smallest pull-back `s` so every field corner stays inside the frustum.
	var m := 1.0 + camera_fit_margin
	var s := -INF
	for corner in _field_corners():
		var v := corner - p0
		var a := v.dot(fwd)
		s = maxf(s, absf(v.dot(right)) * m / tan_h - a)
		s = maxf(s, absf(v.dot(up)) * m / tan_v - a)

	cam.global_transform = Transform3D(cam_basis, p0 - fwd * s)
	print("CAMERA FIT: aspect=%.3f pullback=%.2f pos=%s" % [aspect, s, cam.global_position])


# The 8 world-space corners of every mesh the camera fit must keep on-screen
# (field + goal frames/nets — see _fit_meshes).
func _field_corners() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for mesh in _fit_meshes:
		var aabb := mesh.get_aabb()
		var xf := mesh.global_transform
		for sx in [0.0, 1.0]:
			for sy in [0.0, 1.0]:
				for sz in [0.0, 1.0]:
					var local := aabb.position + Vector3(aabb.size.x * sx, aabb.size.y * sy, aabb.size.z * sz)
					pts.append(xf * local)
	return pts


# --- Helpers ------------------------------------------------------------------
func _find_node_named(root: Node, wanted: String) -> Node:
	if root.name == wanted:
		return root
	for child in root.get_children():
		var found := _find_node_named(child, wanted)
		if found != null:
			return found
	return null


func _autoplay_animations(node: Node) -> void:
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		var names := player.get_animation_list()
		if not names.is_empty():
			var chosen: String = names[0]
			for n in names:
				if n.to_lower().contains("idle"):
					chosen = n
					break
			var anim := player.get_animation(chosen)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			player.play(chosen)
	for child in node.get_children():
		_autoplay_animations(child)
