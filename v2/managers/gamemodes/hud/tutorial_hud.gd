@tool
class_name TutorialHUD extends Control

@onready var step_label: Label = %StepLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var hint_label: Label = %HintLabel
@onready var complete_label: Label = %CompleteLabel


func _ready():
	rpc_hide()


@rpc("call_local", "reliable")
func rpc_show_step(step_index: int, total: int, objective_key: String, hint_key: String):
	complete_label.hide()
	step_label.text = "%d / %d" % [step_index + 1, total]
	objective_label.text = tr(objective_key)
	hint_label.text = tr(hint_key)
	step_label.show()
	objective_label.show()
	hint_label.show()
	self.show()


@rpc("call_local", "reliable")
func rpc_show_complete():
	step_label.hide()
	objective_label.hide()
	hint_label.hide()
	complete_label.text = tr("TUT_COMPLETE")
	complete_label.show()
	self.show()


@rpc("call_local", "reliable")
func rpc_hide():
	self.hide()
