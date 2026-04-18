@tool
class_name ResultsHUD extends Control

signal skip_pressed

@export var input_state_manager: InputStateManager

@onready var title_label: Label = %TitleLabel
@onready var results_container: VBoxContainer = %ResultsContainer
@onready var countdown_label: Label = %CountdownLabel
@onready var skip_btn: Button = %SkipBtn

var _countdown: float = -1.0


func _ready():
	hide()
	skip_btn.pressed.connect(func(): skip_pressed.emit())


func _process(delta: float):
	if _countdown <= 0.0:
		return
	_countdown -= delta
	countdown_label.text = "%d" % ceili(_countdown)
	if _countdown <= 0.0:
		_countdown = -1.0


@rpc("call_local", "reliable")
func rpc_show_results(results_dict: Dictionary, countdown_seconds: float):
	var data := ResultsData.from_dict(results_dict)
	title_label.text = data.title

	for child in results_container.get_children():
		child.queue_free()

	for row in data.rows:
		var row_label := Label.new()
		var parts: Array[String] = []
		for col in data.columns:
			parts.append(str(row.get(col, "")))
		row_label.text = "  ".join(parts)
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_container.add_child(row_label)

	_countdown = countdown_seconds
	countdown_label.text = "%d" % ceili(countdown_seconds)
	skip_btn.visible = multiplayer.is_server()
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	show()


@rpc("call_local", "reliable")
func rpc_hide():
	_countdown = -1.0
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	hide()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	return issues
