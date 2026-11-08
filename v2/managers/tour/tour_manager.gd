@tool
## Plays Tours: a dimmed overlay whose panel opens as a centered intro modal, then shrinks into a
## callout beside each later step's target. Local only; nothing here is networked.
class_name TourManager extends BaseManager

signal tour_closed(tour: Tour, skipped: bool)

@export var input_state_manager: InputStateManager
@export var save_manager: SaveManager

const INTRO_WIDTH: float = 900.0
const CALLOUT_WIDTH: float = 480.0
const BODY_MAX_HEIGHT: float = 360.0
## Between the spotlight hole and the panel.
const PANEL_GAP: float = 24.0
## Hole half-size around a Node3D target's projected point.
const TARGET_3D_PADDING: float = 64.0
const DIM_COLOR: Color = Color(0, 0, 0, 0.7)
const OUTLINE_WIDTH: float = 3.0
const DOT_SIZE: Vector2 = Vector2(12, 12)
## Input ignored for this long after a tour opens, so a rider still mashing buttons can't skip it.
const OPEN_GRACE_MSEC: int = 1000

@onready var _ui: Control = %UI
@onready var _spotlight: Control = %Spotlight
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _image: TextureRect = %Image
@onready var _body: RichTextLabel = %Body
@onready var _dots: HBoxContainer = %Dots
@onready var _back_btn: Button = %BackBtn
@onready var _skip_btn: Button = %SkipBtn
@onready var _next_btn: Button = %NextBtn

## Set by the test harness so tours never block the bot.
var dbg_disable_tours: bool = false

var _tour: Tour
var _steps: Array[TourStep]
var _step_idx: int = 0
var _hole: Rect2
var _saved_input_state: InputStateManager.InputState
var _opened_msec: int = 0
## The menu's focus, handed back on close and during action steps. Null while riding, where
## nothing has focus.
var _saved_focus: Control


func _ready():
	super()
	set_process(false)
	if Engine.is_editor_hint():
		return
	# Tutorial tours pause the game (ShowTourTask); the overlay still has to run.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spotlight.draw.connect(_draw_spotlight)
	_back_btn.pressed.connect(func(): _show_step(_step_idx - 1))
	_skip_btn.pressed.connect(_close.bind(true))
	_next_btn.pressed.connect(_on_next_pressed)
	input_state_manager.device_changed.connect(_on_device_changed)


func _input(event: InputEvent):
	if Engine.is_editor_hint():
		return
	# Action steps leave input to the menu underneath.
	if !is_open() or _is_action_step():
		return
	if Time.get_ticks_msec() - _opened_msec < OPEN_GRACE_MSEC:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _step_idx == 0:
			_close(true)
		else:
			_show_step(_step_idx - 1)
	elif _is_body_action(event):
		# Trying a control the step teaches counts as Next.
		get_viewport().set_input_as_handled()
		_on_next_pressed()


func _process(_delta: float):
	if _is_action_step() and _steps[_step_idx].done_when.call():
		_on_next_pressed()
		return
	_layout()


## Always shows the tour. Finishing or skipping saves it as done.
func play(tour: Tour) -> void:
	_tour = tour
	_steps = tour.get_steps()
	_saved_input_state = input_state_manager.current_input_state
	_saved_focus = null
	_opened_msec = Time.get_ticks_msec()
	_ui.show()
	set_process(true)
	_show_step(0)


## Plays the tour unless it's already done. Returns whether it plays.
func play_once(tour: Tour) -> bool:
	if dbg_disable_tours or save_manager.is_tour_done(tour.tour_id):
		return false
	play(tour)
	return true


func is_open() -> bool:
	return _tour != null


## Closes the open tour as skipped, for an owner that's going away mid-tour.
func skip() -> void:
	_close(true)


func _is_action_step() -> bool:
	return is_open() and _steps[_step_idx].done_when.is_valid()


## Whether `event` presses an {action} token in the step's text. TOKEN_ALIASES aren't one action.
func _is_body_action(event: InputEvent) -> bool:
	var step := _steps[_step_idx]
	for action in ControlBindings.tokens_in(tr(step.body_key) + tr(step.highlight_key)):
		if !ControlBindings.TOKEN_ALIASES.has(action) and event.is_action_pressed(action):
			return true
	return false


func _on_device_changed(_is_gamepad: bool):
	if is_open():
		_render_body()


func _on_next_pressed():
	if _step_idx == _steps.size() - 1:
		_close(false)
	else:
		_show_step(_step_idx + 1)


func _show_step(idx: int):
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and !_panel.is_ancestor_of(focus):
		_saved_focus = focus
	_step_idx = idx
	var step := _steps[idx]
	var is_last := idx == _steps.size() - 1
	_title.text = tr(step.title_key)
	_image.texture = step.image
	_image.visible = step.image != null
	_panel.custom_minimum_size.x = INTRO_WIDTH if idx == 0 else CALLOUT_WIDTH
	_next_btn.text = tr("TOUR_DONE") if is_last else tr("TOUR_NEXT")
	_back_btn.visible = idx > 0
	var is_action := _is_action_step()
	_next_btn.visible = !is_action
	# An action step hands input back so the player can do it; done_when moves the tour on.
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_action else Control.MOUSE_FILTER_STOP
	# The setter shows the cursor (showhide_mouse_cursor).
	input_state_manager.current_input_state = (
		_saved_input_state if is_action else InputStateManager.InputState.IN_TOUR
	)
	_rebuild_dots()
	_render_body()
	if is_action:
		_restore_focus()
	else:
		_next_btn.grab_focus()
	_layout()


func _close(skipped: bool):
	var tour := _tour
	_tour = null
	_ui.hide()
	set_process(false)
	# Deferred so whatever polls Input this frame doesn't also read the press that closed it.
	input_state_manager.set_deferred("current_input_state", _saved_input_state)
	_restore_focus()
	save_manager.mark_tour_done(tour.tour_id)
	tour_closed.emit(tour, skipped)


## Freed when the menu rebuilt its rows during an action step; it focuses the new ones itself.
func _restore_focus():
	if is_instance_valid(_saved_focus):
		_saved_focus.grab_focus()


#region Live button icons
func _rebuild_dots():
	for dot in _dots.get_children():
		dot.free()
	for i in _steps.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = DOT_SIZE
		dot.color = UtilsConstants.UI_BLUE if i == _step_idx else UtilsConstants.UI_TRACK
		_dots.add_child(dot)


## The body, then the highlighted line under it, with live button icons for {action} tokens.
func _render_body():
	var step := _steps[_step_idx]
	var gamepad := input_state_manager.is_gamepad
	_body.clear()
	ControlBindings.append_tokens(_body, tr(step.body_key), gamepad)
	if step.highlight_key.is_empty():
		return
	_body.append_text("\n\n")
	_body.push_color(UtilsConstants.UI_GOLD)
	ControlBindings.append_tokens(_body, tr(step.highlight_key), gamepad)
	_body.pop()


#endregion


#region Layout
func _layout():
	var screen := _ui.size
	var hole := Rect2() if _step_idx == 0 else _target_rect(_steps[_step_idx])
	_hole = hole.intersection(Rect2(Vector2.ZERO, screen))
	_spotlight.queue_redraw()

	# Converges a frame after the text changes, once the label has wrapped at its new width.
	_body.custom_minimum_size.y = minf(_body.get_content_height(), BODY_MAX_HEIGHT)
	_panel.reset_size()
	var pos := (screen - _panel.size) / 2.0
	if _hole.has_area():
		pos = _beside(_hole, _panel.size, screen)
	_panel.position = pos


## Screen rect of the step's target. Empty centers the step with no hole.
func _target_rect(step: TourStep) -> Rect2:
	if step.target is Control:
		return (step.target as Control).get_global_rect()
	if step.target is Node3D:
		var camera := get_viewport().get_camera_3d()
		var world_pos := (step.target as Node3D).global_position
		if camera.is_position_behind(world_pos):
			return Rect2()
		var point := camera.unproject_position(world_pos)
		if !Rect2(Vector2.ZERO, _ui.size).has_point(point):
			return Rect2()
		return Rect2(point, Vector2.ZERO).grow(TARGET_3D_PADDING)
	return Rect2()


## Panel position beside the hole, on whichever side has the most room.
func _beside(hole: Rect2, panel_size: Vector2, screen: Vector2) -> Vector2:
	var room := {
		Vector2.LEFT: hole.position.x,
		Vector2.RIGHT: screen.x - hole.end.x,
		Vector2.UP: hole.position.y,
		Vector2.DOWN: screen.y - hole.end.y,
	}
	var side: Vector2 = room.keys().reduce(func(a, b): return a if room[a] >= room[b] else b)
	# Center on the hole, then push out past its edge on that side.
	var pos := hole.get_center() - panel_size / 2.0
	pos += side * ((hole.size + panel_size) / 2.0 + Vector2(PANEL_GAP, PANEL_GAP))
	return pos.clamp(Vector2.ZERO, (screen - panel_size).max(Vector2.ZERO))


## Four dim rects around the hole plus a neon outline. No hole dims the whole screen.
## Action steps only outline: the player works outside the hole too (e.g. the color picker).
func _draw_spotlight():
	var screen := _spotlight.size
	if _is_action_step():
		if _hole.has_area():
			_spotlight.draw_rect(_hole, UtilsConstants.UI_BLUE, false, OUTLINE_WIDTH)
		return
	if !_hole.has_area():
		_spotlight.draw_rect(Rect2(Vector2.ZERO, screen), DIM_COLOR)
		return
	_spotlight.draw_rect(Rect2(0, 0, screen.x, _hole.position.y), DIM_COLOR)
	_spotlight.draw_rect(Rect2(0, _hole.end.y, screen.x, screen.y - _hole.end.y), DIM_COLOR)
	_spotlight.draw_rect(Rect2(0, _hole.position.y, _hole.position.x, _hole.size.y), DIM_COLOR)
	_spotlight.draw_rect(
		Rect2(_hole.end.x, _hole.position.y, screen.x - _hole.end.x, _hole.size.y), DIM_COLOR
	)
	_spotlight.draw_rect(_hole, UtilsConstants.UI_BLUE, false, OUTLINE_WIDTH)


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if save_manager == null:
		issues.append("save_manager must not be empty")
	return issues
