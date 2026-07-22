extends Control
## Instructions screen: same header/footer layout as team_select.tscn (title
## top, content fills the middle, Back pinned to the bottom) with a
## swipeable card area in the middle. Each rule card is its own hand-authored
## Page1..Page4 subtree under CardMargin (own images/rich text per card).
## Arrow taps and horizontal swipes both slide the cards left/right; no text
## is set from code.

const PAGE_COUNT := 4
const COLOR_DOT_ACTIVE := Color(0.97, 0.76, 0.15, 1)  # yellow, matches theme's button/selection color
const COLOR_DOT_INACTIVE := Color(0.55, 0.85, 0.4, 1)  # light green
const SLIDE_DURATION := 0.32
const SWIPE_THRESHOLD := 60.0 # px of horizontal drag before it counts as a page swipe

@onready var _pages: Array[Control] = [%Page1, %Page2, %Page3, %Page4]
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _back_button: Button = %BackButton
@onready var _dots: HBoxContainer = %PageDots
@onready var _card_panel: Control = %CardPanel

var _page := 0
var _sliding := false
var _drag_start := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	_back_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.MAIN_MENU))
	_prev_button.pressed.connect(func(): _go_to_page(_page - 1, -1))
	_next_button.pressed.connect(func(): _go_to_page(_page + 1, 1))
	_card_panel.gui_input.connect(_on_card_gui_input)
	# Wait for layout (and, on real devices, the SystemFont resources — those
	# resolve to the OS's actual font and can load a frame or two late on
	# Android, unlike the editor where it's already cached) to settle before
	# measuring. Skipping this reads each RichTextLabel's minimum height
	# against a not-yet-final font, which under-reserves room on a real phone
	# even though it looked fine in the editor — the concrete bug behind a
	# user having to fight a RichTextLabel's own tiny internal scrollbar
	# (mouse-only, not touch-drag-friendly) instead of the page just fitting.
	await get_tree().process_frame
	await get_tree().process_frame
	# PageStage (a plain Control) doesn't propagate its children's minimum size
	# upward the way CardPanel (a Container) used to when pages were its direct
	# children — without this, CardPanel is only as tall as the VBox's generic
	# flex distribution gives it, which can be shorter than the tallest page
	# (Page4's 5-row rules list), clipping it against clip_contents. Reserve
	# room for the tallest page up front so every page fits identically.
	var stage := _pages[0].get_parent() as Control
	var max_h := 0.0
	for p in _pages:
		max_h = maxf(max_h, p.get_combined_minimum_size().y)
	var page4_natural_h: float = _pages[3].get_combined_minimum_size().y
	stage.custom_minimum_size.y = max_h
	_go_to_page(0, 0)
	_scale_rules_list(page4_natural_h)


## Page4 ("SPECIAL RULES") is the TALLEST page — its natural size is what
## `max_h` above reserves for every page — so on a screen taller than the
## project's 1080x1920 reference (canvas_items+expand stretch gives extra
## vertical room there, see project.godot), CardPanel still grows past even
## that reservation, but Page4's own rules list stays fixed-size: the result
## reads as tiny, hard-to-read text floating in a big empty card. Scale the
## whole rules list (icon size, font size, row spacing) to whatever space it
## ACTUALLY ends up with — up on a spacious screen, down on a cramped one —
## clamped so it never gets comically large or unreadably small either way.
const RULES_SCALE_MIN := 0.75
const RULES_SCALE_MAX := 1.15
const RULE_ICON_SIZE := 95.0
const RULE_FONT_SIZE := 27
const RULE_LIST_SEPARATION := 12


func _scale_rules_list(natural_h: float) -> void:
	if natural_h <= 0.0:
		return
	# custom_minimum_size only takes effect on the container tree's NEXT
	# layout pass, and CardPanel expanding to its own final size (governed by
	# the outer VBox, not this script) needs another pass on top of that —
	# wait for it to fully settle before reading Page4's real, final height.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var page4: Control = _pages[3]
	var scale_factor := clampf(page4.size.y / natural_h, RULES_SCALE_MIN, RULES_SCALE_MAX)
	if absf(scale_factor - 1.0) < 0.03: # close enough to natural size — not worth touching
		return
	var rules_list := page4.get_node_or_null("RulesList") as VBoxContainer
	if rules_list == null:
		return
	rules_list.add_theme_constant_override("separation", roundi(RULE_LIST_SEPARATION * scale_factor))
	for row in rules_list.get_children():
		var hbox := row.get_node_or_null("Margin/HBox")
		if hbox == null:
			continue
		var icon := hbox.get_node_or_null("Icon") as Control
		if icon != null:
			icon.custom_minimum_size = Vector2.ONE * (RULE_ICON_SIZE * scale_factor)
		var text := hbox.get_node_or_null("Text") as RichTextLabel
		if text != null:
			text.add_theme_font_size_override("normal_font_size", roundi(RULE_FONT_SIZE * scale_factor))


## direction: -1 = came from Prev (new page slides in from the left),
## +1 = came from Next (slides in from the right), 0 = first page, no animation.
func _go_to_page(index: int, direction: int) -> void:
	var new_page := wrapi(index, 0, PAGE_COUNT)
	if direction == 0:
		_page = new_page
		for i in _pages.size():
			_pages[i].visible = (i == _page)
		_update_dots()
		return
	if _sliding or new_page == _page:
		return
	_slide_to(new_page, direction)


func _update_dots() -> void:
	for i in _dots.get_child_count():
		var dot: Control = _dots.get_child(i)
		dot.modulate = COLOR_DOT_ACTIVE if i == _page else COLOR_DOT_INACTIVE


func _slide_to(new_page: int, direction: int) -> void:
	_sliding = true
	var old := _pages[_page]
	var incoming := _pages[new_page]
	_page = new_page
	_update_dots()

	# Pages live under PageStage, a plain Control (not a Container), so nothing
	# re-sorts/snaps their position back mid-tween. But the FIRST time a page
	# turns visible, its own RichTextLabel (fit_content=true) needs a frame to
	# measure wrapped-text height before it's laid out correctly — wait for
	# that to land before offsetting it off-screen as the tween's start point.
	incoming.visible = true
	await get_tree().process_frame
	# Travel the full VIEWPORT width (not just the card's own width) so the
	# outgoing page is always well clear of the (now clipped) card before it's
	# hidden — no risk of an under-travel "pop" if the card is narrower than
	# expected. CardPanel has clip_contents=true, so the slide reads as a clean
	# cut at the card edge the whole way, like a normal web carousel.
	var w: float = get_viewport_rect().size.x
	incoming.position.x = w * direction

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(old, "position:x", -w * direction, SLIDE_DURATION)
	tween.tween_property(incoming, "position:x", 0.0, SLIDE_DURATION)
	await tween.finished
	old.visible = false
	old.position.x = 0.0
	_sliding = false


func _on_card_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_drag_start = t.position
			_dragging = true
		elif _dragging:
			_dragging = false
			_check_swipe(t.position - _drag_start)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_drag_start = mb.position
			_dragging = true
		elif _dragging:
			_dragging = false
			_check_swipe(mb.position - _drag_start)


func _check_swipe(delta: Vector2) -> void:
	if absf(delta.x) > SWIPE_THRESHOLD and absf(delta.x) > absf(delta.y):
		if delta.x < 0.0:
			_go_to_page(_page + 1, 1) # swiped left -> next
		else:
			_go_to_page(_page - 1, -1) # swiped right -> prev
