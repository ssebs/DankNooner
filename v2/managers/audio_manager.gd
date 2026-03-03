@tool
class_name AudioManager extends BaseManager

@export_tool_button("Play Startup") var tool_btn_1 = play_startup

@onready var sounds_container: Node = %Sounds
@onready var startup: FmodEventEmitter3D = %Startup


func _ready():
	if Engine.is_editor_hint():
		return

	var args := OS.get_cmdline_user_args()
	if "--disable-audio" in args:
		FmodServer.mute_all_events()


func play_startup():
	startup.play()


func stop_all():
	for sound in sounds_container.get_children():
		if sound is FmodEventEmitter3D || sound is FmodEventEmitter2D:
			sound.stop()
