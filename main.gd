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
@export var turn_time_limit := 30.0

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

# --- Input: tap vs drag --------------------------------------------------------
# TAP always (re)starts the COMBO chain or rewinds it; DRAG is the only way to
# connect two figures (a real pass) or aim a shot — see _on_press/_motion/_release.
var _pressed := false
var _press_screen_pos := Vector2.ZERO
var _dragging := false
var _drag_candidate := NO_CELL
const DRAG_TAP_THRESHOLD_PX := 20.0 # finger movement below this = a tap, not a drag
const DRAG_SNAP_RADIUS := 0.9 # world units — how close for the live preview highlight
const DRAG_COMMIT_RADIUS := 0.38 # tighter — "arrived": auto-connect without releasing
const TAP_HIT_RADIUS := 0.55 # world units — forgiveness for a plain tap
const FIGURE_HEIGHT := 1.6 # a bit over the model's real height (~1.45 @ scale 1)

# --- Board FX (tunable in the Inspector on this node) -------------------------
# All feedback uses the same rounded-square tile shape (see BoardFx), just
# different colours, so it reads as one visual language.
@export_group("Board FX Colors")
@export var color_move := Color(0.28, 1.0, 0.45, 0.9) # move target cell
@export var color_shoot := Color(0.30, 1.0, 0.5, 0.9) # shoot target cell
@export var color_tap := Color(0.30, 0.65, 1.0, 0.95) # tappable figure
@export var color_chain := Color(1.0, 0.6, 0.15, 0.95) # chosen chain figure
@export var color_select := Color(0.2, 0.95, 1.0, 0.95) # selected mover
@export var color_trail := Color(0.45, 0.9, 1.0, 0.95) # energy trail
@export var color_remove := Color(1.0, 0.15, 0.15, 0.95) # figure removable after a red card
@export var color_offside := Color(1.0, 0.85, 0.1, 0.95) # offside line + flagged figure
## Shoot target that WOULD trip the stalling foul (MatchState.would_violate_stall)
## if tapped — close to the HUD's yellow-card colour on purpose, so the meaning
## reads instantly ("yellow" tile = yellow-card risk) without a legend. Pushed
## a bit more toward pure yellow (less gold/brown) than the HUD's exact shade
## so it stays clearly distinct from color_chain's orange as a glowing tile.
@export var color_stall_warning := Color(1.0, 0.92, 0.1, 0.95)
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
	if _hud != null:
		_hud.end_move_requested.connect(_on_end_move_requested)
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
	if GameFlow.player_formation.is_empty():
		_start_placement()
	else:
		_start_coin_toss()


# The ball node is created inside _build_match; this stays for the _ready toggle.
func _spawn_ball() -> void:
	pass


## Whichever side is GameFlow.player_side uses the formation they just placed
## (see _start_placement); the other side (and both, before any placement has
## happened — e.g. local test runs) falls back to the fixed Formations layout.
func _home_formation() -> Array[Dictionary]:
	if GameFlow.player_side == "HomeTeam" and not GameFlow.player_formation.is_empty():
		return GameFlow.player_formation
	return Formations.home()


func _away_formation() -> Array[Dictionary]:
	if GameFlow.player_side == "AwayTeam" and not GameFlow.player_formation.is_empty():
		return GameFlow.player_formation
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
	var ball_cell := _kickoff_cell(kickoff_team)
	_place_ball(ball_cell)
	if _state.pieces.is_empty():
		_state.setup(home_formation, away_formation, ball_cell, kickoff_team, goals_to_win)
	else:
		_state.reset(home_formation, away_formation, ball_cell, kickoff_team)
	# HUD names (used by the footer's team-code text) must be set before the
	# turn view reads them, or kickoff briefly shows the previous match's code.
	_refresh_hud()
	_refresh_turn_view()


# Single call point that mirrors MatchState (shields/names/score/cards) onto the HUD.
func _refresh_hud() -> void:
	if _hud != null:
		_hud.refresh(_state, home_country, away_country)


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


# --- Ball helpers ------------------------------------------------------------
# Ball starts on an empty cell by the kicking team's goalkeeper.
func _kickoff_cell(team: String) -> Vector2i:
	if team == "HomeTeam":
		return ball_start_cell
	return Vector2i(ball_start_cell.x, Board.ROWS - 1 - ball_start_cell.y) # mirror to away side


func _place_ball(cell: Vector2i) -> void:
	if ball_scene == null:
		return
	_ball = ball_scene.instantiate() as Node3D
	add_child(_ball)
	_ball.name = "Ball"
	_ball.scale = Vector3.ONE * ball_scale
	_ball.position = _ball_world(cell)
	_ball_last_pos = _ball.position


func _ball_world(cell: Vector2i) -> Vector3:
	return _cell_world(cell.x, cell.y) + Vector3(0, BALL_RADIUS * ball_scale, 0)


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
## any empty, non-goal cell on the player's own half. Mirrors the same
## confinement rules MatchState already enforces during play (own_goal_row /
## is_goal_cell / Board.half_of_row), so a placed team is never in a spot the
## rules would forbid moving them to later.
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
	for row in range(Board.ROWS):
		if Board.half_of_row(row) != own_half:
			continue
		for col in range(Board.COLS):
			var cell := Vector2i(col, row)
			if _node_at.has(cell) or _state.is_goal_cell(cell):
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
	_start_coin_toss()


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
	var winner: String = await _hud.play_coin_toss(home_code, away_code, home_country, away_country)
	_busy = false
	_build_match(winner)


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
	if _is_ai_turn():
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
	elif event is InputEventMouseMotion and _pressed:
		_on_motion((event as InputEventMouseMotion).position)
	elif event is InputEventScreenDrag:
		_on_motion((event as InputEventScreenDrag).position)


func _on_press(screen_pos: Vector2) -> void:
	_pressed = true
	_press_screen_pos = screen_pos
	_dragging = false
	_drag_candidate = NO_CELL


func _on_motion(screen_pos: Vector2) -> void:
	if not _pressed or _placement_active: # placement is tap-only, no drag
		return
	if not _dragging and screen_pos.distance_to(_press_screen_pos) > DRAG_TAP_THRESHOLD_PX:
		_dragging = true
		# Starting a drag right on one of your own figures "picks it up" —
		# same effect as tapping it first, so a single press-drag-release can
		# select AND move it, instead of needing two separate taps.
		if _state.phase == MatchState.Phase.MOVE:
			var picked := _resolve_target(_press_screen_pos, _state.own_cells(), TAP_HIT_RADIUS)
			if picked != NO_CELL:
				_move_from = picked
				_draw_move(_move_from)
	if not _dragging:
		return

	if _state.phase == MatchState.Phase.MOVE:
		if _move_from == NO_CELL:
			return # nothing picked up/selected — nothing to drag toward
		_drag_candidate = _resolve_target(screen_pos, _state.move_targets(_move_from), DRAG_SNAP_RADIUS)
		_draw_move(_move_from, _drag_candidate)
		return

	if _state.phase != MatchState.Phase.COMBO or _state.chain.is_empty():
		return # only mid-combo dragging has anything to snap to

	# Auto-connect: once the finger actually ARRIVES at a pass target (or an
	# earlier chain figure, for rewind), commit it right away — without
	# waiting for a release. Lets one continuous drag chain through several
	# figures (1->2->3->...) instead of needing a separate drag per hop.
	# Shooting still always needs an explicit release (see _on_release).
	var connectable: Array[Vector2i] = []
	connectable.append_array(_state.chain)
	connectable.append_array(_state.combo_pass_targets())
	var arrived := _resolve_target(screen_pos, connectable, DRAG_COMMIT_RADIUS)
	if arrived != NO_CELL and arrived != _state.chain[-1]:
		if arrived in _state.chain:
			_state.rewind(arrived)
		else:
			_state.extend(arrived)
		_drag_candidate = NO_CELL
		_draw_combo()
		return # re-evaluate fresh candidates on the next motion event

	_drag_candidate = _resolve_target(screen_pos, _drag_candidates(), DRAG_SNAP_RADIUS)
	_draw_combo(_drag_candidate)


func _on_release(screen_pos: Vector2) -> void:
	if not _pressed:
		return
	_pressed = false
	if _placement_active:
		_placement_tap(screen_pos)
		return
	if _dragging:
		_dragging = false
		var candidate := _drag_candidate
		_drag_candidate = NO_CELL
		if _state.phase == MatchState.Phase.MOVE:
			if candidate != NO_CELL and _move_from != NO_CELL:
				_apply_move(_move_from, candidate)
			elif _move_from != NO_CELL:
				_draw_move(_move_from) # dragged into a dead zone — stay selected
			return
		if candidate != NO_CELL:
			_commit_combo_target(candidate)
		else:
			_draw_combo() # dragged into a dead zone — cancel, nothing changes
		return
	# A plain tap — resolved against phase-specific candidate sets (see below),
	# not a single raw raycast cell, so tapping a tall figure's body works too.
	if _state.phase == MatchState.Phase.COMBO:
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


# Every cell a drag could usefully snap to right now: chain members (rewind),
# pass targets (extend) and shoot targets (execute).
func _drag_candidates() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(_state.chain)
	out.append_array(_state.combo_pass_targets())
	out.append_array(_state.combo_shoot_targets())
	return out


func _commit_combo_target(cell: Vector2i) -> void:
	if cell in _state.chain:
		_state.rewind(cell)
		_draw_combo()
	elif cell in _state.combo_pass_targets():
		_state.extend(cell)
		_draw_combo()
	elif cell in _state.combo_shoot_targets():
		_do_combo(cell)


# --- COMBO: a plain tap (re)starts the chain, rewinds it, extends it with a
# pass, or shoots --------------------------------------------------------------
# Figures (cylinder hit-test) are ALWAYS checked before empty target tiles
# (flat hit-test): a tap on a tall figure's body can visually overlap a
# nearby empty tile under the tilted camera, so if we checked tiles first, a
# tap clearly meant for a figure could get misread as tapping the tile behind
# it. Checking figures first means the figure always wins when both match.
# Priority order resolves the one real ambiguity (a teammate who is BOTH a
# valid starter — adjacent to the ball — AND a valid pass target in a straight
# line from the chain): while a chain is already going, rewind/pass/shoot are
# checked FIRST — matching _on_motion's drag-to-connect, which only ever
# considers chain+pass targets, never starters — so that cell means "pass
# here", not "restart here". Only once none of those match (or the chain was
# empty to begin with) does a tap fall through to (re)starting at a starter.
func _combo_tap(screen_pos: Vector2) -> void:
	if not _state.chain.is_empty():
		var rewind_cell := _resolve_target(screen_pos, _state.chain, TAP_HIT_RADIUS)
		if rewind_cell != NO_CELL:
			_state.rewind(rewind_cell)
			_draw_combo()
			return
		var pass_cell := _resolve_target(screen_pos, _state.combo_pass_targets(), TAP_HIT_RADIUS)
		if pass_cell != NO_CELL:
			_state.extend(pass_cell) # tap-to-pass — connects the chain, same as a drag
			_draw_combo()
			return
		var shoot_cell := _resolve_target(screen_pos, _state.combo_shoot_targets(), TAP_HIT_RADIUS)
		if shoot_cell != NO_CELL:
			_do_combo(shoot_cell) # direct tap-to-shoot still works, no ambiguity
			return
	# Empty chain (or a tap that matched none of the above): (re)start here.
	var starter := _resolve_target(screen_pos, _state.combo_starters(), TAP_HIT_RADIUS)
	if starter != NO_CELL and _state.begin(starter):
		_draw_combo()


# A combo plays as ONE continuous ball motion through the whole chain — the ball
# never stops. Each chain figure starts its windup EARLY (in anticipation) so its
# boot meets the ball exactly as it arrives and strikes it on in one touch. This
# kills the old "roll, stop, wind up, roll" stutter and stops the ball parking
# under the receiver. Strength (swing + ball speed) scales with distance; the
# kicking foot matches the side the ball comes from.
func _do_combo(shoot_cell: Vector2i) -> void:
	var res := _state.execute_combo(shoot_cell)
	if not res["ok"]:
		return
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
func _update_turn_timer_display() -> void:
	if _hud == null or _turn_timer.is_stopped():
		return
	var seconds_left: int = ceili(_turn_timer.time_left)
	if seconds_left != _shown_time_left:
		_shown_time_left = seconds_left
		_hud.update_timer(seconds_left)



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
		if _hud != null:
			await _hud.play_announcement("offside")
	# yellow (1st) -> red (2nd) -> forced sending-off (3rd, card=="" +
	# must_remove) — the last two both read as a "red" dismissal to the player.
	if res["card"] == "yellow":
		print("YELLOW CARD: %s (same figure shot twice in a row)" % _state.current)
		if _hud != null:
			await _hud.play_announcement("yellow")
	elif res["card"] == "red" or res["must_remove"] != "":
		print("RED CARD: %s" % _state.current)
		if _hud != null:
			await _hud.play_announcement("red")
	if res["goal"]:
		print("%s %s  ->  Home %d : %d Away"
			% ["AUTOGOL!" if res.get("own_goal", false) else "GOAL!", res["scorer"],
				_state.score["HomeTeam"], _state.score["AwayTeam"]])
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
# select RLabel in the Scene dock to tune font/colour/position, same as
# EndMoveButton. The vignette's actual texture is procedural (depends on the
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
	var cam_basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), 0.0, 0.0)) # straight down
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
	if _move_from == NO_CELL:
		var fig_cell := _resolve_target(screen_pos, _state.own_cells(), TAP_HIT_RADIUS)
		if fig_cell != NO_CELL:
			_move_from = fig_cell
			_draw_move(fig_cell)
		return
	var fig_hit := _resolve_target(screen_pos, _state.own_cells(), TAP_HIT_RADIUS)
	if fig_hit != NO_CELL:
		if fig_hit != _move_from:
			_move_from = fig_hit # reselect a different figure
			_draw_move(fig_hit)
		return # tapping the already-selected figure again is a harmless no-op
	var dest := _resolve_target(screen_pos, _state.move_targets(_move_from), TAP_HIT_RADIUS)
	if dest != NO_CELL:
		_apply_move(_move_from, dest)
		return
	_move_from = NO_CELL # cancel selection
	_fx.clear()


func _apply_move(from: Vector2i, to: Vector2i) -> void:
	if not _state.do_move(from, to): # also advances the turn
		return
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
	if fig is PlayerRig:
		var jog_t := clampf(float(move_cells - 1) / float(maxi(jog_speed_scale_max_cells - 1, 1)), 0.0, 1.0)
		(fig as PlayerRig).jog(lerpf(jog_speed_scale_min, jog_speed_scale_max, jog_t))
	var tween := create_tween()
	tween.tween_property(fig, "position", _cell_world(to.x, to.y), move_duration).set_trans(Tween.TRANS_SINE)
	if fig is PlayerRig:
		tween.tween_callback((fig as PlayerRig).idle.bind(false))
	await tween.finished
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
		# Phase.MOVE, nothing picked up yet — highlight every one of the
		# current team's figures as tappable (mirrors _draw_combo's
		# combo_starters highlight). Without this the pitch reads as frozen
		# whenever a MOVE step follows another MOVE step (moves_left still
		# > 0 but nothing drawn), and the player can time out never
		# realizing a figure — or a second reactive move — was still theirs
		# to take.
		_fx.clear()
		for c in _state.own_cells():
			_fx.add_tile(_cell_world(c.x, c.y), color_tap)
	print("TURN: %s  phase=%s" % [_state.current, MatchState.Phase.keys()[_state.phase]])
	_shown_time_left = -1
	if _state.phase == MatchState.Phase.REMOVE:
		# No timer here, on purpose: REMOVE is the actual PENALTY for a 3rd
		# stalling violation, not a normal decision — if it timed out like
		# every other phase, forfeit() would just cancel pending_removal and
		# the penalty would vanish. Waiting it out must not be an escape
		# hatch, so there's simply nothing to wait out.
		_turn_timer.stop()
	elif _state.current != _pool_team:
		# A genuinely new team's turn (next_turn() ran since the last refresh) —
		# fresh full pool. Same team continuing COMBO -> MOVE/REMOVE instead just
		# resumes whatever was left of theirs (see _do_combo's snapshot above).
		_pool_team = _state.current
		_turn_timer.start(turn_time_limit)
	else:
		_turn_timer.start(maxf(_pool_seconds_left, 0.05))
	if _hud != null:
		_hud.update_turn_hint(_state.current, _state.phase, "", _state.moves_left)
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


# Ran out of time to act — forfeit this decision with no move made (see
# MatchState.forfeit) and move straight on to whatever comes next.
func _on_turn_timeout() -> void:
	print("TIME UP: %s forfeits (phase=%s)" % [_state.current, MatchState.Phase.keys()[_state.phase]])
	_state.forfeit()
	_refresh_turn_view()


## "End Move" button (HUD) — skip any remaining reactive move(s) this turn
## (see MatchState.moves_left/end_move_phase) instead of being forced to use
## them. Ignored outside Phase.MOVE or while busy/not the human's turn.
func _on_end_move_requested() -> void:
	if _busy or _state == null or _is_ai_turn():
		return
	if _state.end_move_phase():
		_refresh_turn_view()


# Highlights every one of the carded team's figures as a removable target.
func _draw_remove() -> void:
	_fx.clear()
	for c in _state.own_cells():
		_fx.add_tile(_cell_world(c.x, c.y), color_remove)


# `preview` is the cell a live drag is currently snapped to (NO_CELL if none) —
# it gets an extra trail segment and a bigger highlight so the drag feels "live".
func _draw_combo(preview: Vector2i = NO_CELL) -> void:
	_fx.clear()
	if _state.chain.is_empty():
		for cell in _state.combo_starters():
			_fx.add_tile(_cell_world(cell.x, cell.y), color_tap)
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
	for c in _state.combo_pass_targets():
		_fx.add_tile(_cell_world(c.x, c.y), color_tap) # blue = next pass
	for c in _state.combo_shoot_targets():
		# green = shoot cell; yellow = would trip the stalling foul (see
		# MatchState.would_violate_stall) — same colour as the HUD's yellow
		# card, so the risk reads instantly without needing a legend.
		var shoot_col := color_stall_warning if _state.would_violate_stall(c) else color_shoot
		_fx.add_tile(_cell_world(c.x, c.y), shoot_col)
	if preview != NO_CELL:
		var col := color_chain
		if preview in _state.combo_shoot_targets():
			col = color_stall_warning if _state.would_violate_stall(preview) else color_shoot
		elif preview in _state.combo_pass_targets():
			col = color_tap
		_fx.add_tile(_cell_world(preview.x, preview.y), col.lightened(0.35), fx_tile_size * 1.1)


# `preview` is the cell a live drag is currently snapped to (NO_CELL if none).
func _draw_move(from: Vector2i, preview: Vector2i = NO_CELL) -> void:
	_fx.clear()
	_fx.add_tile(_cell_world(from.x, from.y), color_select)
	for c in _state.move_targets(from):
		_fx.add_tile(_cell_world(c.x, c.y), color_move)
	if preview != NO_CELL:
		var pts := PackedVector3Array([_cell_world(from.x, from.y), _cell_world(preview.x, preview.y)])
		_fx.set_trail(pts, color_trail)
		_fx.add_tile(_cell_world(preview.x, preview.y), color_move.lightened(0.35), fx_tile_size * 1.1)


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
	# Capture the transform you tuned in the editor as the fixed reference.
	if not _cam_ref_set:
		_cam_ref = cam.global_transform
		_cam_ref_set = true

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
