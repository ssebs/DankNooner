@tool
class_name SplashMenuState extends MenuState

@export var menu_manager: MenuManager
@export var main_menu_state: MenuState

@export var debug_skip_ok: bool = true
@export var splash_duration: float = 1.0

@onready var splashes_to_show: Control = %SplashesToShow
@onready var timer: Timer = %Timer

var current_splash_index: int = 0
var splash_children: Array[Node] = []
var is_showing_splashes: bool = false


func Enter(_state_context: StateContext):
	ui.show()
	current_splash_index = 0
	splash_children = []
	is_showing_splashes = true

	# Gather and hide all splash children
	for child in splashes_to_show.get_children():
		if child is Control:
			splash_children.append(child)
			child.hide()

	# Start showing splashes
	if splash_children.size() > 0:
		timer.timeout.connect(_on_timer_timeout)
		_show_current_splash()
	else:
		printerr("splash_children not populated!")
		_finish_splashes()


func Exit(_state_context: StateContext):
	ui.hide()
	is_showing_splashes = false
	timer.stop()
	timer.timeout.disconnect(_on_timer_timeout)


func _on_timer_timeout():
	_hide_current_splash()

	current_splash_index += 1

	if current_splash_index < splash_children.size():
		_show_current_splash()
	else:
		_finish_splashes()


func _show_current_splash():
	splash_children[current_splash_index].show()
	timer.start(splash_duration)


func _hide_current_splash():
	splash_children[current_splash_index].hide()


func _finish_splashes():
	timer.stop()
	for child in splash_children:
		child.hide()
	splash_children.clear()
	transitioned.emit(main_menu_state, null)


func _unhandled_input(event: InputEvent):
	if Engine.is_editor_hint():
		return
	if !is_showing_splashes:
		return
	if !debug_skip_ok:
		return

	# Skip to end on any button press
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.is_pressed():
			_finish_splashes()


#override
func on_cancel_key_pressed():
	if debug_skip_ok:
		_finish_splashes()
