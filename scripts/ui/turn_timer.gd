@tool
extends Control

@export var fill_color: Color = Color("f7c41c")
@export var border_color: Color = Color.BLACK
@export var border_width: float = 0.0


func _ready():
	queue_redraw()


func _process(_delta):
	if Engine.is_editor_hint():
		queue_redraw()


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw():
	if size.x <= 0 or size.y <= 0:
		return

	var points := PackedVector2Array([
		Vector2(18, 0),
		Vector2(size.x - 18, 0),
		Vector2(size.x, size.y * 0.5),
		Vector2(size.x - 18, size.y),
		Vector2(18, size.y),
		Vector2(0, size.y * 0.5)
	])

	draw_colored_polygon(points, fill_color)

	if border_width > 0.0:
		for i in range(points.size()):
			draw_line(
				points[i],
				points[(i + 1) % points.size()],
				border_color,
				border_width
			)