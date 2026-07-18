extends SceneTree

## One-off: removes the corner-tile "OwnTeamMarkerBorder"/"OwnTeamMarkerFill"
## pair (they still stole attention next to the tap/move/shoot squares) and
## replaces them with a single, VERY faint rounded-square glow centred under
## the whole figure — same superellipse shape as BoardFx's own tile glow
## (see gen_tile_glow_texture.gd), sized to match a full cell, at low alpha.
## Low alpha is the whole point this time: when a bright, saturated Board FX
## tile (tap/move/shoot/etc.) lands on the SAME cell, it simply overpowers
## this faint tint underneath instead of visually fighting it — the marker
## only needs to read clearly when NOTHING else is highlighting that cell.
##
## A real scene node ("OwnTeamTileGlow"): select it in the editor, tweak
## Mesh/Size and the material's Albedo Color — BOTH the colour AND its alpha —
## directly in the Inspector. Fully hands-off from code: main.gd only ever
## flips this node's `.visible` (own team vs opponent), nothing here recolours
## it at runtime. Whatever you set in the Inspector is exactly what shows in
## the actual match.
##
## Run: godot --headless -s res://scripts/tools/add_player_tile_glow.gd --path <project>

const SCENE_PATH := "res://scenes/player_rigged.tscn"
const TEX_PATH := "res://assets/textures/effects/player_tile_glow.png"
const GLOW_SIZE := 0.92 # matches main.gd's fx_tile_size default, same footprint as a Board FX tile
const GLOW_COLOR := Color(1.0, 1.0, 1.0, 0.2) # "jako blago prozirni" white — deliberately low alpha so it never fights the tap/move/shoot tiles
const GLOW_Y := 0.015   # below BoardFx's TILE_Y (0.03) so an active tile always draws on top


func _initialize() -> void:
	var tex := load(TEX_PATH) as Texture2D
	if tex == null:
		push_error("player_tile_glow.png not found/imported — run gen_tile_glow_texture.gd + reimport first.")
		quit(1)
		return

	var packed_in := load(SCENE_PATH) as PackedScene
	var root := packed_in.instantiate()

	for old_name in ["OwnTeamMarkerBorder", "OwnTeamMarkerFill", "OwnTeamTileGlow"]:
		var old := root.get_node_or_null(old_name)
		if old != null:
			old.free()

	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * GLOW_SIZE
	var glow := MeshInstance3D.new()
	glow.name = "OwnTeamTileGlow"
	glow.mesh = mesh
	glow.position = Vector3(0, GLOW_Y, 0)
	glow.visible = false # main.gd turns this on only for the player's own figures
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = GLOW_COLOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = mat
	root.add_child(glow)
	glow.owner = root

	var packed_out := PackedScene.new()
	packed_out.pack(root)
	var err := ResourceSaver.save(packed_out, SCENE_PATH)
	print("scene save -> ", err)
	root.free()
	quit(0)
