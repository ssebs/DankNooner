## Level-placed, per-rider event that FreeRoamGameMode hosts without leaving free roam. Entering
## %PlayerStartCircle opens the event picker; only the submitting rider runs it. Server-auth: the
## server holds the one-rider-at-a-time lock (unless is_shared) and runs the server_* hooks, the
## rider's own client runs begin()/end(). The base parks the rider at %BikeSpot, views them through %Camera3D in
## IN_MINIGAME, and hands them back; subclasses fill in _on_session_start/_on_session_end.
@abstract
class_name FreeRoamActivity extends Node3D

signal entered_activity(peer_id: int, activity: FreeRoamActivity)
signal exited_activity(peer_id: int, activity: FreeRoamActivity)
## Client-side: the rider completed it and the activity already handed them back.
signal finished

## Localization keys shown in the event picker.
@export var event_name: String
@export var event_description: String
## Charged to start it, pre-race fuel-ups included. Riders who can't pay are turned away.
@export var price: int = 0

@onready var camera: Camera3D = %Camera3D
## Where the rider's bike is parked.
@onready var bike_spot: Marker3D = %BikeSpot
@onready var _start_circle: Area3D = %PlayerStartCircle

## All set by begin() while the session runs.
var _player: PlayerEntity
var _input_state_manager: InputStateManager
var _audio_manager: AudioManager
var _hud_manager: HUDManager


func _ready():
	add_to_group(UtilsConstants.GROUPS["FreeRoamActivities"])
	_start_circle.body_entered.connect(_on_start_circle_body_entered)
	_start_circle.body_exited.connect(_on_start_circle_body_exited)


## Server: whether several riders can run it at once.
func is_shared() -> bool:
	return false


## Server: the rider's start was accepted. Runs after begin() was sent to their client.
## Parks them at bike_spot and holds them there.
func server_start(peer_id: int, spawn_manager: SpawnManager):
	spawn_manager.respawn_player_in_place.rpc(
		peer_id, bike_spot.global_position, bike_spot.global_basis
	)
	CountdownTask.freeze(spawn_manager.get_player_by_peer_id(peer_id))


## Server: the rider finished or cancelled with get_result(), or free roam is ending (0.0).
func server_end(peer_id: int, _result: float, spawn_manager: SpawnManager):
	CountdownTask.unfreeze(spawn_manager.get_player_by_peer_id(peer_id))


## Client: run it for the local rider. The session starts once their teleport onto bike_spot
## lands, since that respawn flips the HUD back to riding.
func begin(
	player: PlayerEntity,
	input_state_manager: InputStateManager,
	audio_manager: AudioManager,
	hud_manager: HUDManager
):
	_player = player
	_input_state_manager = input_state_manager
	_audio_manager = audio_manager
	_hud_manager = hud_manager
	player.respawned.connect(_start_session, CONNECT_ONE_SHOT)


## Client: hand the rider back. Also the cancel path, so it's safe at any point after begin(),
## even before the teleport landed.
func end():
	if _player.respawned.is_connected(_start_session):
		_player.respawned.disconnect(_start_session)
		_player = null
		return
	_input_state_manager.input_state_changed.disconnect(_on_input_state_changed)
	_input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	_on_session_end()
	_audio_manager.play_revs(_player.bike_definition)
	_player.camera_controller.clear_override_cam()
	_player = null


## Client: the outcome reported to server_end.
@abstract func get_result() -> float


## Client: the rider is parked and viewed through camera, in IN_MINIGAME.
@abstract func _on_session_start()


## Client: undo _on_session_start. Runs before the rider's camera and input are handed back.
@abstract func _on_session_end()


func _start_session():
	_audio_manager.stop_revs()
	_player.camera_controller.set_override_cam(camera)
	_on_session_start()
	_input_state_manager.input_state_changed.connect(_on_input_state_changed)
	_input_state_manager.current_input_state = InputStateManager.InputState.IN_MINIGAME


## Unpause always lands on IN_GAME — put the cursor back while the session is still up.
func _on_input_state_changed(new_state: InputStateManager.InputState):
	if new_state == InputStateManager.InputState.IN_GAME:
		_input_state_manager.current_input_state = InputStateManager.InputState.IN_MINIGAME


func _on_start_circle_body_entered(body: Node3D):
	if body is PlayerEntity:
		entered_activity.emit(int(body.name), self)


func _on_start_circle_body_exited(body: Node3D):
	if body is PlayerEntity:
		exited_activity.emit(int(body.name), self)
