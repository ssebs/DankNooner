@tool
class_name AudioManager extends BaseManager

@export_tool_button("Play Startup") var _ps_btn = play_startup

@onready var startup: FmodEventEmitter3D = %Startup


func _ready():
	if Engine.is_editor_hint():
		return


func play_startup():
	if startup:
		startup.play()
	else:
		print("startup var empty")
