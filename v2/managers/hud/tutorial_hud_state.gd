@tool
class_name TutorialHUDState extends HUDState

@export var hud_manager: HUDManager


@onready var step_label: Label = %StepLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var hint_label: Label = %HintLabel
@onready var complete_label: Label = %CompleteLabel
@onready var warning_label: Label = %WarningLabel
@onready var warning_anim_player: AnimationPlayer = %WarningAnimationPlayer


func _ready():
	rpc_hide()


func rpc_show_countdown(seconds: int):
	step_label.hide()
	hint_label.hide()
	complete_label.hide()
	objective_label.text = str(seconds)
	objective_label.show()
	ui.show()


@rpc("call_local", "reliable")
func rpc_show_step(step_index: int, total: int, objective_text: String, hint_text: String):
	# objective_text/hint_text are pre-localized by the step (so it can interpolate
	# its @export values like duration/min_speed). Don't tr() again.
	complete_label.hide()
	step_label.text = "%d / %d" % [step_index + 1, total]
	objective_label.text = objective_text
	hint_label.text = hint_text
	step_label.show()
	objective_label.show()
	hint_label.show()
	ui.show()


@rpc("call_local", "unreliable")
func rpc_update_progress(progress_text: String):
	hint_label.text = progress_text


## Race: flash a warning (missed checkpoint, wrong way) under the progress line.
## Restarts if already flashing; `looping` keeps flashing until rpc_stop_warning.
@rpc("call_local", "reliable")
func rpc_flash_warning(text_key: String, looping: bool = false):
	warning_label.text = tr(text_key)
	warning_anim_player.stop()
	warning_anim_player.play(&"flash_loop" if looping else &"flash")


@rpc("call_local", "reliable")
func rpc_stop_warning():
	warning_anim_player.play(&"RESET")


## Hide the "step X / N" indicator. Used by single-step modes (e.g. race) where
## the counter is meaningless.
@rpc("call_local", "reliable")
func rpc_hide_step_label():
	step_label.hide()


@rpc("call_local", "reliable")
func rpc_show_complete(text_key: String = "TUT_COMPLETE"):
	step_label.hide()
	objective_label.hide()
	hint_label.hide()
	complete_label.text = tr(text_key)
	complete_label.show()
	ui.show()


@rpc("call_local", "reliable")
func rpc_show_waiting():
	step_label.hide()
	objective_label.hide()
	hint_label.hide()
	complete_label.text = tr("TUT_WAITING_FOR_OTHERS")
	complete_label.show()
	ui.show()


@rpc("call_local", "reliable")
func rpc_hide():
	rpc_stop_warning()
	ui.hide()
