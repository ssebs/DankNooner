@tool
class_name AudioManager extends BaseManager

# @export var vca_master: FmodVCA

@export_tool_button("Play Startup") var tool_btn_1 = play_startup

const VCA_SETTING_MAP = {
	"MASTER": "master_vol",
	"vca:/Menu": "menu_vol",
	"vca:/SFX": "sfx_vol",
	"vca:/Music": "music_vol",
}

@onready var sounds_container: Node = %Sounds
@onready var startup: FmodEventEmitter3D = %Startup
@onready var ninja500_revs: FmodEventEmitter3D = %Ninja500Revs

# TODO - use InputState to switch VCA/busses


func _ready():
	if Engine.is_editor_hint():
		return

	# Set volume buses
	for vca in FmodServer.get_all_vca():
		vca = vca as FmodVCA
		# vca.volume
		print(vca.get_path())

	for bus in FmodServer.get_all_buses():
		bus = bus as FmodBus
		print(bus.get_path())

	# Disable audio if arg is passed
	var args := OS.get_cmdline_user_args()
	if "--disable-audio" in args:
		FmodServer.mute_all_events()


func play_ninja500_revs():
	ninja500_revs.play()


func update_ninja500_rpm(val: float):
	ninja500_revs.set_parameter("RPM", val)


func play_startup():
	startup.play()


func stop_all():
	for sound in sounds_container.get_children():
		if sound is FmodEventEmitter3D || sound is FmodEventEmitter2D:
			sound.stop()
