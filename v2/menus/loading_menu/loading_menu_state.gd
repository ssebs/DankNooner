@tool
class_name LoadingMenuState extends MenuState

@onready var spinner: Spinner = %Spinner


func Enter(_state_context: StateContext):
	ui.show()
	spinner.status = Spinner.Status.SPINNING


func Exit(_state_context: StateContext):
	ui.hide()
