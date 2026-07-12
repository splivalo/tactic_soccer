class_name StyledButton
extends Button
## Button whose own text is invisible; a full-rect overlay Label (with
## LabelSettings) draws the visible text instead. Button has no shadow
## theme item (only font_outline_color/outline_size) while Label does —
## this is the only way to get a real emboss/highlight on button text in
## Godot 4. toggle_mode/button_group/signals/.text/min-size all keep
## working exactly like a normal Button; only the drawn glyphs are swapped.
##
## Reads font_color/font_size/outline_* from the theme ONCE at startup
## (before hiding the native text, which would otherwise contaminate the
## reading with its own now-transparent override) — a later live theme
## swap on this button won't retint the overlay text. Not a concern here
## since my_theme_gold.tres is assigned once at scene-author time.

const FONT_PATH := "res://assets/fonts/BebasNeue-Regular.ttf"

## Light "highlight ridge" offset upward — the emboss trick: a dark outline
## for edge definition plus a light shadow offset the wrong way (up instead
## of down) reads as a raised bevel on top of each glyph.
@export var shadow_color := Color(1.0, 0.97, 0.88, 0.35)
@export var shadow_offset := Vector2(0, -2)
@export var shadow_size := 1

var _label: Label


func _ready() -> void:
	var font_color: Color = get_theme_color("font_color")
	var outline_color: Color = get_theme_color("font_outline_color")
	var font_size: int = get_theme_font_size("font_size")
	var outline_size: int = get_theme_font_size("outline_size")

	_hide_native_text()

	_label = Label.new()
	_label.name = "__TextOverlay"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	var settings := LabelSettings.new()
	settings.font = load(FONT_PATH)
	settings.font_size = font_size
	settings.font_color = font_color
	settings.outline_size = outline_size
	settings.outline_color = outline_color
	settings.shadow_size = shadow_size
	settings.shadow_color = shadow_color
	settings.shadow_offset = shadow_offset
	_label.label_settings = settings
	_label.text = text

	add_child(_label)


func _process(_delta: float) -> void:
	if _label.text != text:
		_label.text = text


func _hide_native_text() -> void:
	var transparent := Color(0, 0, 0, 0)
	for item in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_hover_pressed_color", "font_focus_color", "font_outline_color"]:
		add_theme_color_override(item, transparent)
