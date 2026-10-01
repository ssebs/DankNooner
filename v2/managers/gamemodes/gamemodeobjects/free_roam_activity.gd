## Level-placed, per-rider event that FreeRoamGameMode hosts without leaving free roam. Entering
## %PlayerStartCircle opens the event picker; only the submitting rider runs it. Server-auth: the
## server holds the one-rider-at-a-time lock and runs the server_* hooks, the rider's own client
## runs begin()/end(). Subclasses fill in the hooks (see FuelUpMinigame).
@abstract
class_name FreeRoamActivity extends Node3D

signal entered_activity(peer_id: int, activity: FreeRoamActivity)
signal exited_activity(peer_id: int, activity: FreeRoamActivity)
## Client-side: the rider completed it and the activity already handed them back.
signal finished

## Localization keys shown in the event picker.
@export var event_name: String
@export var event_description: String

@onready var _start_circle: Area3D = %PlayerStartCircle


func _ready():
	add_to_group(UtilsConstants.GROUPS["FreeRoamActivities"])
	_start_circle.body_entered.connect(_on_start_circle_body_entered)
	_start_circle.body_exited.connect(_on_start_circle_body_exited)


## Server: the rider's start was accepted. Runs after begin() was sent to their client.
func server_start(_peer_id: int, _spawn_manager: SpawnManager):
	pass


## Server: the rider finished or cancelled with get_result(), or free roam is ending (0.0).
func server_end(_peer_id: int, _result: float, _spawn_manager: SpawnManager):
	pass


## Client: run it for the local rider.
@abstract func begin(
	player: PlayerEntity,
	input_state_manager: InputStateManager,
	audio_manager: AudioManager,
	hud_manager: HUDManager
)


## Client: hand the rider back. Also the cancel path, so it must be safe at any point after begin().
@abstract func end()


## Client: the outcome reported to server_end.
@abstract func get_result() -> float


func _on_start_circle_body_entered(body: Node3D):
	if body is PlayerEntity:
		entered_activity.emit(int(body.name), self)


func _on_start_circle_body_exited(body: Node3D):
	if body is PlayerEntity:
		exited_activity.emit(int(body.name), self)
