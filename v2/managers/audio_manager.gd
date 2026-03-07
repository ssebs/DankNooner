@tool
class_name AudioManager extends BaseManager

@export_tool_button("Play Startup") var tool_btn_1 = play_startup

@onready var sounds_container: Node = %Sounds
@onready var startup: FmodEventEmitter3D = %Startup
@onready var ninja500_revs: FmodEventEmitter3D = %Ninja500Revs


func _ready():
	if Engine.is_editor_hint():
		return

	# Disable audio if arg is passed
	var args := OS.get_cmdline_user_args()
	if "--disable-audio" in args:
		FmodServer.mute_all_events()


func play_ninja500_revs(volume: float = 0.6):
	ninja500_revs.volume = volume
	ninja500_revs.play()


func update_ninja500_rpm(val: float):
	ninja500_revs.set_parameter("RPM", val)


func play_startup():
	startup.play()


func stop_all():
	for sound in sounds_container.get_children():
		if sound is FmodEventEmitter3D || sound is FmodEventEmitter2D:
			sound.stop()
