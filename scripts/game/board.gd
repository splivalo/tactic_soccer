class_name Board
extends RefCounted

## Pure logic for the 7x10 pitch grid — no visuals, no nodes.
## Maps between grid cells (col,row) and world positions so the imported
## `field` mesh in stadium.glb lines up 1:1 with the game maths.
##
## Imported `field` mesh spans X:[-3.5,3.5] (7 wide) and Z:[-5,5] (10 deep),
## centred on the origin, top surface at Y ~= 0.2322. That matches these consts.

const COLS := 7           # tiles across (X): cols 0..6
const ROWS := 10          # tiles deep   (Z): rows 0..9
const TILE_SIZE := 1.0    # world units per tile
const SURFACE_Y := 0.2322 # top of the imported field mesh (pieces stand here)


## Centre of a cell in world space (Y sits on the pitch surface).
static func grid_to_world(col: int, row: int) -> Vector3:
	var x := (col - (COLS - 1) / 2.0) * TILE_SIZE
	var z := (row - (ROWS - 1) / 2.0) * TILE_SIZE
	return Vector3(x, SURFACE_Y, z)


## Nearest cell for a world position (Y ignored).
static func world_to_grid(pos: Vector3) -> Vector2i:
	var col := roundi(pos.x / TILE_SIZE + (COLS - 1) / 2.0)
	var row := roundi(pos.z / TILE_SIZE + (ROWS - 1) / 2.0)
	return Vector2i(col, row)


static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS


## Which half a row belongs to: -1 = first player's half, +1 = second's, 0 = middle.
## ROWS is even (10) so there is no exact middle row; this splits 0-4 / 5-9.
static func half_of_row(row: int) -> int:
	if row * 2 < ROWS:  # avoids integer-division warning
		return -1
	return 1


# --- Straight-line movement (horizontal / vertical / diagonal) ----------------
## The 8 legal directions the ball may travel (h, v, d). No knight/L moves.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


## True if b lies on a straight line (h/v/d) from a (and is not a itself).
static func is_straight(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return false
	var d := b - a
	return d.x == 0 or d.y == 0 or absi(d.x) == absi(d.y)


## Unit step from a toward b if the line is straight, else Vector2i.ZERO.
static func step_dir(a: Vector2i, b: Vector2i) -> Vector2i:
	if not is_straight(a, b):
		return Vector2i.ZERO
	return Vector2i(signi(b.x - a.x), signi(b.y - a.y))


## Cells strictly between a and b along a straight line
## (empty if not straight, or if they are adjacent / equal).
static func cells_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dir := step_dir(a, b)
	if dir == Vector2i.ZERO:
		return out
	var c := a + dir
	while c != b:
		out.append(c)
		c += dir
	return out


## True if the straight line a->b is clear of occupied cells (endpoints excluded).
## `occupied` is a Dictionary keyed by Vector2i (value ignored).
static func path_clear(a: Vector2i, b: Vector2i, occupied: Dictionary) -> bool:
	if step_dir(a, b) == Vector2i.ZERO:
		return false
	for c in cells_between(a, b):
		if occupied.has(c):
			return false
	return true


## Every empty in-bounds cell reachable from `a` along the 8 directions, stopping
## at (and excluding) the first occupied cell on each ray. These are the legal
## "shoot the ball to here" targets from `a` (see rule ISPUCAVANJE LOPTE).
static func reachable_from(a: Vector2i, occupied: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in DIRS:
		var c: Vector2i = a + dir
		while in_bounds(c) and not occupied.has(c):
			out.append(c)
			c += dir
	return out


# --- Tap/drag hit-testing -----------------------------------------------------
## Closest approach (in the XZ/horizontal plane) of a 3D ray to the vertical
## line at (target_x, target_z). Returns {"xz_dist": float, "y": float} — how
## close the ray gets to that vertical column, and the ray's height there.
## Used to test "did this tap/drag ray hit a FIGURE" (which has height), as
## opposed to a flat ground-plane intersection (which only works for tiles).
## Pure geometry — no scene, no camera object, just vectors — so it's testable.
static func ray_vertical_closest(ray_origin: Vector3, ray_dir: Vector3, target_x: float, target_z: float) -> Dictionary:
	var dx := ray_origin.x - target_x
	var dz := ray_origin.z - target_z
	var denom := ray_dir.x * ray_dir.x + ray_dir.z * ray_dir.z
	if denom < 0.000001:
		return {"xz_dist": INF, "y": ray_origin.y}
	var t := -(ray_dir.x * dx + ray_dir.z * dz) / denom
	var point := ray_origin + ray_dir * t
	var xz_dist := Vector2(point.x - target_x, point.z - target_z).length()
	return {"xz_dist": xz_dist, "y": point.y}


# --- Drag-and-snap targeting --------------------------------------------------
## Which `candidates` cell centre (in XZ world space) is closest to `point`,
## within `max_dist` world units. Returns Vector2i(-1,-1) if none qualify or
## `candidates` is empty. Pure/testable — no scene, no input, just geometry.
## Used to let the player drag toward a target instead of tapping it exactly.
static func nearest_cell(point: Vector2, candidates: Array[Vector2i], max_dist: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := max_dist
	for cell in candidates:
		var world := grid_to_world(cell.x, cell.y)
		var d := Vector2(world.x, world.z).distance_to(point)
		if d <= best_dist:
			best_dist = d
			best = cell
	return best
