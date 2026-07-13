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
## Flip if the kicking foot ends up on the wrong side for the incoming ball.
@export var invert_kick_foot := false
## Minimum time (s) for the opening roll to the first figure, so it has room for
## the (now short) wind-up and strikes the ball on arrival rather than waiting.
@export var first_touch_windup := 0.3
## After a move/combo settles, only players within this many cells of the ball
## turn to face it; everyone else eases back to formation. Keeps a few players
## watching the ball instead of all 20 spinning in place like sunflowers.
@export var track_radius := 2
## Max random delay (s) before each player settles, so they don't turn as one.
@export var settle_stagger := 0.35
## How high a full-power ball lofts at mid-flight (world units). Scales with the
## hop's power, so short balls stay on the ground and long balls arc over.
@export var max_ball_arc := 0.7

# --- Ball --------------------------------------------------------------------
@export var spawn_ball := true
@export var ball_scene: PackedScene = load("res://assets/models/ball.glb")
@export var ball_start_cell := Vector2i(3, 8) # empty cell by the home GK (ball never sits on a figure)
@export var ball_scale := 1.0
@export var goals_to_win := 2 # match ends when a team reaches this

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

# --- Goal cinematic ----------------------------------------------------------
## On a goal, cut to a low side camera by the goal (background blurred) for the
## final strike + the keeper's dive, like a replay angle, then restore & kick off.
## The "make the last shot gorgeous" polish comes later; this is the scaffolding.
@export_group("Goal Cinematic")
@export var enable_goal_cam := true
@export var goal_cam_hold := 1.6           # seconds to hold on the goal
@export var goal_cam_side := 6.5           # offset to the side of the goal (X)
@export var goal_cam_height := 2.0         # camera height
@export var goal_cam_back := 2.0           # offset behind the goal line
@export var goal_cam_fov := 42.0
@export_range(0.0, 0.5, 0.01) var goal_cam_blur := 0.12  # background DoF (0 = off)
## Time scale during the goal strike + celebration (1 = no slow-mo). The whole
## winning shot and keeper dive play in slow motion, then snap back to normal.
@export_range(0.15, 1.0, 0.05) var goal_slowmo := 0.4
@export_group("")

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
var _node_at: Dictionary = {} # Vector2i(cell) -> Node3D (figure standing there)
var _ball: Node3D = null
var _ball_last_pos := Vector3.ZERO  # for rolling-spin (see _spin_ball)
var _move_from := Vector2i(-1, -1) # figure selected to move (view only)
var _busy := false # true while the ball animates (ignore input)
var _fx: BoardFx = null
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
@export_range(0.2, 5.0, 0.1) var offside_flash_seconds := 1.8

@export_group("Board FX Tuning")
@export var fx_tile_size := 0.92
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
# Separate cinematic camera used only during goal celebrations.
var _goal_cam: Camera3D = null


func _ready() -> void:
	# Screens before this one (team select) store their picks on the GameFlow
	# autoload; empty string means "unset", so the @export defaults above
	# still apply when this scene is run standalone in the editor.
	if GameFlow.home_country != "":
		home_country = GameFlow.home_country
	if GameFlow.away_country != "":
		away_country = GameFlow.away_country
	_grid_origin = _read_field_origin()
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
	if enable_camera_fit:
		get_viewport().size_changed.connect(_fit_camera)
		_fit_camera_deferred()
	if enable_goal_cam:
		_setup_goal_cam()
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
	_build_match("HomeTeam")


# The ball node is created inside _build_match; this stays for the _ready toggle.
func _spawn_ball() -> void:
	pass


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
	# Home defends the bottom goal (faces -Z); away defends the top (faces +Z).
	_build_team("HomeTeam", Formations.home(), kits["home"], 180.0)
	_build_team("AwayTeam", Formations.away(), kits["away"], 0.0)
	var ball_cell := _kickoff_cell(kickoff_team)
	_place_ball(ball_cell)
	if _state.pieces.is_empty():
		_state.setup(Formations.home(), Formations.away(), ball_cell, kickoff_team, goals_to_win)
	else:
		_state.reset(Formations.home(), Formations.away(), ball_cell, kickoff_team)
	_refresh_turn_view()


func _build_team(team_name: String, pieces: Array[Dictionary], kit: Dictionary, facing: float) -> void:
	var root := Node3D.new()
	root.name = team_name
	add_child(root)
	var gk_side := 0 if team_name == "HomeTeam" else 1
	var index := 0
	for piece in pieces:
		var cell: Vector2i = piece["cell"]
		var fig := player_scene.instantiate() as Node3D
		root.add_child(fig)
		fig.position = _cell_world(cell.x, cell.y)
		fig.rotation_degrees = Vector3(0.0, facing + player_facing_offset, 0.0)
		fig.set_meta("base_yaw", deg_to_rad(facing + player_facing_offset))  # formation facing
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
		_node_at[cell] = fig
		index += 1


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


# --- Input: tap vs drag -------------------------------------------------------
# A TAP always (re)starts the chain at the tapped figure, or rewinds to it if
# it's already in the chain, or fires a shot if it's a shoot cell — never
# ambiguous, never depends on geometry. A DRAG (real finger movement) from
# wherever your finger is toward a highlighted target is the only way to
# CONNECT two figures (a pass) or aim a shot with live snap feedback.
func _unhandled_input(event: InputEvent) -> void:
	if _busy or _state == null:
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
	if not _pressed:
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


# --- COMBO: a plain tap (re)starts the chain or rewinds it -------------------
# Figures (cylinder hit-test) are ALWAYS checked before empty target tiles
# (flat hit-test): a tap on a tall figure's body can visually overlap a
# nearby empty tile under the tilted camera, so if we checked tiles first, a
# tap clearly meant for a figure could get misread as tapping the tile behind
# it. Checking figures first means the figure always wins when both match.
func _combo_tap(screen_pos: Vector2) -> void:
	if not _state.chain.is_empty():
		var rewind_cell := _resolve_target(screen_pos, _state.chain, TAP_HIT_RADIUS)
		if rewind_cell != NO_CELL:
			_state.rewind(rewind_cell)
			_draw_combo()
			return
	var starter := _resolve_target(screen_pos, _state.combo_starters(), TAP_HIT_RADIUS)
	if starter != NO_CELL:
		if _state.begin(starter):
			_draw_combo()
		return
	if not _state.chain.is_empty():
		var shoot_cell := _resolve_target(screen_pos, _state.combo_shoot_targets(), TAP_HIT_RADIUS)
		if shoot_cell != NO_CELL:
			_do_combo(shoot_cell) # direct tap-to-shoot still works, no ambiguity


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
	_busy = true
	_fx.clear()
	print("COMBO -> shoot %s (goal=%s)" % [shoot_cell, res["goal"]])
	# path = [ball_cell, chain_fig_0, ... chain_fig_n (shooter), shoot_cell]
	var path: Array = res["path"]
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
	#    starting the windup earlier, overlapping the incoming roll.
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
		if kicker is PlayerRig:
			contact = (kicker as PlayerRig).contact_delay(kind, power)
		var start: float = maxf(arrive[i] - contact, 0.0)
		_schedule_kick(start, from_cell, path[i - 1], to_cell, kind, power)
		# Cut to the cinematic angle + slow-mo as the scorer begins the strike.
		if is_final and res["goal"] and enable_goal_cam:
			_schedule(start, _begin_goal_drama.bind(to_cell))

	# 4) One uninterrupted ball tween through the whole path. Each segment lofts
	#    into an arc scaled by its power (short = grounded roll, long = high ball);
	#    only the final approach eases out as it settles.
	var tween := create_tween()
	_ball.position = _ball_world(path[0])
	_ball_last_pos = _ball.position
	for k in range(n - 1):
		var a := _ball_world(path[k])
		var b := _ball_world(path[k + 1])
		var h := max_ball_arc * _power(_cells(path[k], path[k + 1]))
		var tw := tween.tween_method(_set_ball_arc.bind(a, b, h), 0.0, 1.0, durs[k])
		if k == n - 2:
			tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			tw.set_trans(Tween.TRANS_LINEAR)
	await tween.finished
	await _after_combo(res)


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
	return clampf(d * 0.05 * _ball_pace(_cells(a, b)), 0.08, 0.7)


# Runs `cb` after `delay` seconds (or now if it's already due).
func _schedule(delay: float, cb: Callable) -> void:
	if delay <= 0.001:
		cb.call()
	else:
		get_tree().create_timer(delay).timeout.connect(cb)


func _schedule_kick(delay: float, at_cell: Vector2i, from_cell: Vector2i, to_cell: Vector2i, kind: String, power: float) -> void:
	_schedule(delay, _fire_kick.bind(at_cell, from_cell, to_cell, kind, power))


# Fired at windup-start: the figure turns to the target and swings; its contact
# frame is timed to land as the continuously-rolling ball reaches its cell.
func _fire_kick(at_cell: Vector2i, from_cell: Vector2i, to_cell: Vector2i, kind: String, power: float) -> void:
	var kicker: Node3D = _node_at.get(at_cell)
	if kicker is PlayerRig:
		_face_toward(kicker, from_cell, to_cell)
		var left := _incoming_on_left(at_cell, from_cell, to_cell)
		(kicker as PlayerRig).kick(kind, power, left)


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


# Called once the ball has SETTLED after a move/combo: players within
# track_radius of the ball calmly turn to watch it; everyone else eases back to
# formation. Staggered so they don't move in unison; keepers stay forward. This
# is the whole facing system — no continuous per-frame tracking (that read as a
# creepy sunflower spin since the figures don't step).
func _settle_facing() -> void:
	if _ball == null or _state == null:
		return
	var ball_cell: Vector2i = _state.ball
	for cell in _node_at:
		var fig = _node_at[cell]
		if not (fig is PlayerRig):
			continue
		var rig := fig as PlayerRig
		if rig.is_goalkeeper():
			continue
		var target_yaw: float = rig.get_meta("base_yaw", 0.0)  # formation by default
		if _cells(cell, ball_cell) <= track_radius:
			var dir := _ball.position - rig.position
			dir.y = 0.0
			if dir.length_squared() > 0.0001:
				target_yaw = atan2(dir.x, dir.z) + deg_to_rad(player_facing_offset)
		rig.turn_to(target_yaw, randf() * settle_stagger)


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
	if res["offside"]:
		print("OFFSIDE — goal not given")
		_show_offside(res["offside_shooter"], res["offside_line_row"])
	if res["card"] == "yellow":
		print("YELLOW CARD: %s (same figure shot twice in a row)" % _state.current)
	elif res["card"] == "red":
		print("RED CARD: %s — choose a figure to remove" % _state.current)
	if res["goal"]:
		print("%s %s  ->  Home %d : %d Away"
			% ["AUTOGOL!" if res.get("own_goal", false) else "GOAL!", res["scorer"],
				_state.score["HomeTeam"], _state.score["AwayTeam"]])
		if res["win"]:
			print("=== %s WINS THE MATCH ===" % res["scorer"])
		# Stay busy through the celebration so the torn-down board can't take input.
		if enable_goal_cam and _goal_cam != null:
			await _celebrate_goal(res)
		_build_match(res["kickoff"])
		_busy = false
	else:
		_busy = false
		_refresh_turn_view()
		_settle_facing()  # players near the ball's new resting cell turn to watch it


# --- Goal cinematic ----------------------------------------------------------
# A separate camera we cut to on a goal; the main Camera3D stays as authored.
func _setup_goal_cam() -> void:
	_goal_cam = Camera3D.new()
	_goal_cam.name = "GoalCam"
	_goal_cam.fov = goal_cam_fov
	_goal_cam.current = false
	if goal_cam_blur > 0.0:
		var attr := CameraAttributesPractical.new()
		attr.dof_blur_far_enabled = true
		attr.dof_blur_amount = goal_cam_blur
		_goal_cam.attributes = attr
	add_child(_goal_cam)


# Places the cinematic camera low and to the side of the scored-on goal, aimed
# at the goal mouth, with the crowd/background thrown out of focus.
func _activate_goal_cam(goal_cell: Vector2i) -> void:
	if _goal_cam == null:
		return
	var target := _cell_world(goal_cell.x, goal_cell.y) + Vector3(0, 0.6, 0)
	# Push the camera outward past the goal line (which end depends on the goal).
	var out_dir := -1.0 if goal_cell.y * 2 < Board.ROWS else 1.0
	var pos := target + Vector3(goal_cam_side, goal_cam_height, out_dir * goal_cam_back)
	_goal_cam.global_position = pos
	_goal_cam.look_at(target, Vector3.UP)
	if _goal_cam.attributes is CameraAttributesPractical:
		var attr := _goal_cam.attributes as CameraAttributesPractical
		attr.dof_blur_far_distance = pos.distance_to(target) + 1.5
		attr.dof_blur_far_transition = 1.5
	_goal_cam.current = true


# Cut to the cinematic angle AND drop into slow motion as the winning strike
# begins, so the whole shot + keeper dive play out like a replay.
func _begin_goal_drama(goal_cell: Vector2i) -> void:
	_activate_goal_cam(goal_cell)
	if goal_slowmo < 1.0:
		Engine.time_scale = goal_slowmo


# Beaten keeper dives; hold on the slow-mo moment (real time), then snap back to
# normal speed and hand the view back.
func _celebrate_goal(res: Dictionary) -> void:
	var defender: String = "AwayTeam" if res["scorer"] == "HomeTeam" else "HomeTeam"
	var gk := _find_gk(defender)
	if gk is PlayerRig:
		(gk as PlayerRig).gk_miss()
	# ignore_time_scale so the hold is real seconds even during slow-mo.
	await get_tree().create_timer(goal_cam_hold, true, false, true).timeout
	Engine.time_scale = 1.0
	_restore_camera()


func _restore_camera() -> void:
	if _goal_cam != null:
		_goal_cam.current = false
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.current = true


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
	# Turn and jog to the new cell, then settle back into idle on arrival.
	_face_toward(fig, from, to)
	if fig is PlayerRig:
		(fig as PlayerRig).jog()
	var tween := create_tween()
	tween.tween_property(fig, "position", _cell_world(to.x, to.y), 0.28).set_trans(Tween.TRANS_SINE)
	if fig is PlayerRig:
		tween.tween_callback((fig as PlayerRig).idle.bind(false))
	_refresh_turn_view()
	_settle_facing()  # nearby players watch the new position, rest hold formation


# --- View refresh (mirror MatchState) ---------------------------------------
func _refresh_turn_view() -> void:
	_move_from = NO_CELL
	if _state.phase == MatchState.Phase.COMBO:
		_draw_combo()
	elif _state.phase == MatchState.Phase.REMOVE:
		_draw_remove()
	else:
		_fx.clear()
	print("TURN: %s  phase=%s" % [_state.current, MatchState.Phase.keys()[_state.phase]])


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
	# Energy trail: ball -> each chosen figure -> (live) drag preview.
	var pts := PackedVector3Array()
	pts.append(_cell_world(_state.ball.x, _state.ball.y))
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
		_fx.add_tile(_cell_world(c.x, c.y), color_shoot) # green = shoot cell
	if preview != NO_CELL:
		var col := color_chain
		if preview in _state.combo_shoot_targets():
			col = color_shoot
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
