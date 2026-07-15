extends Control
## Instructions screen: same header/footer layout as team_select.tscn (title
## top, content fills the middle, Back pinned to the bottom) with a
## swipeable card area in the middle. Each rule card is its own hand-authored
## Page1..Page4 subtree under CardMargin (own images/rich text per card) —
## swiping just toggles which one is visible, no text is set from code.

const PAGE_COUNT := 4
const COLOR_DOT_ACTIVE := Color(0.97, 0.76, 0.15, 1)  # yellow, matches theme's button/selection color
const COLOR_DOT_INACTIVE := Color(0.55, 0.85, 0.4, 1)  # light green

@onready var _pages: Array[Control] = [%Page1, %Page2, %Page3, %Page4]
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _back_button: Button = %BackButton
@onready var _dots: HBoxContainer = %PageDots

var _page := 0


func _ready() -> void:
	_back_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.MAIN_MENU))
	_prev_button.pressed.connect(func(): _go_to_page(_page - 1))
	_next_button.pressed.connect(func(): _go_to_page(_page + 1))
	_go_to_page(0)


func _go_to_page(index: int) -> void:
	_page = wrapi(index, 0, PAGE_COUNT)
	for i in _pages.size():
		_pages[i].visible = (i == _page)
	for i in _dots.get_child_count():
		var dot: Control = _dots.get_child(i)
		dot.modulate = COLOR_DOT_ACTIVE if i == _page else COLOR_DOT_INACTIVE
