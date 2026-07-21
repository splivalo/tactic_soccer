extends RichTextLabel
## A RichTextLabel is the frontmost thing under a finger, so it's the one
## that actually receives a touch/drag — the wrapping ScrollContainer's own
## gui_input never fires for a drag that starts here (Control's default
## mouse_filter = STOP keeps the event from bubbling up past this node), so
## ScrollContainer's native scroll only ever responds to dragging its own
## thin scrollbar handle, not a swipe on the text itself. Finds the nearest
## ScrollContainer ancestor and drives its scroll position 1:1 with a
## one-finger touch/mouse drag instead, same as any native scroll view.

var _scroll: ScrollContainer
var _dragging := false
var _drag_last := Vector2.ZERO


func _ready() -> void:
	var p := get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	_scroll = p as ScrollContainer
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if _scroll == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_dragging = t.pressed
		_drag_last = t.position
	elif event is InputEventScreenDrag and _dragging:
		var d := event as InputEventScreenDrag
		_scroll.scroll_vertical -= roundi(d.position.y - _drag_last.y)
		_drag_last = d.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		_dragging = mb.pressed
		_drag_last = mb.position
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_scroll.scroll_vertical -= roundi(mm.position.y - _drag_last.y)
		_drag_last = mm.position
