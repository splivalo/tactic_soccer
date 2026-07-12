class_name PlayerAppearance
extends RefCounted

## Applies a kit + hair colour to a character and puts the shirt number ON THE
## JERSEY (via the `number_front` / `number_back` materials the model exports
## from Blender). Everything is per-instance (duplicated materials), so two
## players can look different even though they share one imported model.

## Small hair palette — assigned per player for on-pitch readability.
const HAIR_COLORS := [
	Color("1c1310"),  # black
	Color("3b2a1a"),  # dark brown
	Color("6b4a2b"),  # brown
	Color("c9a227"),  # blond
]

## Material name (lowercase substring) -> which kit colour it takes.
## Only these get recoloured; `skin`, `eyes`, `shoes`… stay as authored.
const KIT_SLOTS := ["primary", "secondary", "hair"]

## Materials (exact, lowercase) that carry the jersey number.
const NUMBER_SLOTS := ["number_front", "number_back"]

## Jersey-number digit textures. The glyphs are WHITE on transparent, so we can
## tint them to any colour (black on white kits, white on dark kits).
## Only single digits 1-7 exist right now; multi-digit numbers need a fuller set.
const NUMBER_TEXTURES := {
	1: "res://assets/textures/numbers/numbers_0006_1.png",
	2: "res://assets/textures/numbers/numbers_0005_2.png",
	3: "res://assets/textures/numbers/numbers_0004_3.png",
	4: "res://assets/textures/numbers/numbers_0003_4.png",
	5: "res://assets/textures/numbers/numbers_0002_5.png",
	6: "res://assets/textures/numbers/numbers_0001_6.png",
	7: "res://assets/textures/numbers/numbers_0000_7.png",
}


## Goalkeeper kits — always distinct from outfield kits (and from each other),
## since real GK jerseys never match either team's outfield colours.
const GK_KITS := [
	{"primary": Color("1a1a1a"), "secondary": Color("f4c20d"), "number": Color("f4c20d")},  # black/yellow
	{"primary": Color("00a651"), "secondary": Color("ffffff"), "number": Color("ffffff")},  # green/white
]


static func hair_for(player_index: int) -> Color:
	return HAIR_COLORS[player_index % HAIR_COLORS.size()]


## side_index: 0 for the home goalkeeper, 1 for the away goalkeeper.
static func gk_kit(side_index: int) -> Dictionary:
	return GK_KITS[side_index % GK_KITS.size()]


## kit = {primary, secondary, number}. hair = Color. number = shirt number.
static func apply(character: Node3D, kit: Dictionary, hair: Color, number: int) -> void:
	var colors := {
		"primary": kit.get("primary", Color.WHITE),
		"secondary": kit.get("secondary", Color.WHITE),
		"hair": hair,
	}
	var number_color: Color = kit.get("number", Color.BLACK)
	# One opaque plate: jersey-colour background + the digit in the number colour.
	var number_tex := _number_plate(number, colors["primary"], number_color)

	for mesh in _find_mesh_instances(character):
		for i in mesh.get_surface_override_material_count():
			var mat := mesh.get_active_material(i)
			if mat == null:
				continue
			var name := mat.resource_name.to_lower()

			# Kit colours (primary / secondary / hair).
			var recoloured := false
			for slot in KIT_SLOTS:
				if name.contains(slot):
					var m := mat.duplicate() as BaseMaterial3D
					if m != null:
						m.albedo_color = colors[slot]
						mesh.set_surface_override_material(i, m)
					recoloured = true
					break
			if recoloured:
				continue

			# Jersey number plate: OPAQUE, so there is no hole around the digit.
			if name in NUMBER_SLOTS and number_tex != null:
				var m := mat.duplicate() as BaseMaterial3D
				if m != null:
					m.albedo_texture = number_tex
					m.albedo_color = Color.WHITE  # colour is baked into the plate
					m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					mesh.set_surface_override_material(i, m)


## Builds an OPAQUE texture: fills the whole plate with the jersey colour, then
## paints the (white, transparent-background) digit glyph over it in `fg`.
## No hole — transparent areas of the source become jersey colour.
static func _number_plate(number: int, bg: Color, fg: Color) -> Texture2D:
	if not NUMBER_TEXTURES.has(number):
		push_warning("No number texture for '%d' (have single digits 1-7)." % number)
		return null
	var tex := load(NUMBER_TEXTURES[number]) as Texture2D
	if tex == null:
		return null
	var glyph := tex.get_image()
	if glyph.is_compressed():
		glyph.decompress()
	glyph.convert(Image.FORMAT_RGBA8)

	var w := glyph.get_width()
	var h := glyph.get_height()
	var plate := Image.create(w, h, false, Image.FORMAT_RGBA8)
	plate.fill(Color(bg.r, bg.g, bg.b, 1.0))
	for y in h:
		for x in w:
			var a := glyph.get_pixel(x, y).a
			if a > 0.0:
				plate.set_pixel(x, y, bg.lerp(fg, a))  # blend digit over jersey colour
	return ImageTexture.create_from_image(plate)


static func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result
