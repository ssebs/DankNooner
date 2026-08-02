@tool
## All Level objects should inherit from this
## levels are defined in level_manager.gd
class_name LevelDefinition extends Node3D

## Hack - for ui background levels where the player doesn't need to spawn
@export var no_player_spawn_needed: bool
@export var player_entity_scene: PackedScene = preload("res://player/player_entity.tscn")
@export var player_spawn_pos: Marker3D
@export var player_spawn_pos_debug: Marker3D
## Optional grid for FreeRoamGameMode to distribute peers across on entry.
## Empty → all peers stack on player_spawn_pos (legacy behavior).
@export var grid_markers: Array[Marker3D] = []
## Per-map traffic density. Swap in a different .tres to make this map busier,
## quieter, or car-heavy. Maps with no RoadManager get no traffic regardless.
@export var traffic_settings: TrafficSettings = preload(
	"res://resources/traffic/settings/default_traffic_settings.tres"
)

## Set in level_manager
var level_manager: LevelManager
var level_name: LevelManager.LevelName


func _ready():
	if Engine.is_editor_hint():
		return
	if OS.has_feature("debug"):
		player_spawn_pos = player_spawn_pos_debug

	# The server simulates EVERY player's physics, but Terrain3D's default dynamic
	# collision only builds around one tracked camera (the local player's — see
	# CameraController.switch_to_cam). Remote players ride over collision-less
	# terrain on the host and fall through the map. Full collision on the server
	# trades memory for correctness; clients keep the cheap camera-tracked mode.
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		for terrain in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Terrain3D"]):
			terrain.collision.mode = Terrain3DCollision.FULL_GAME


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if no_player_spawn_needed:
		return issues

	if player_entity_scene == null:
		issues.append("player_entity_scene must not be empty")
	if player_spawn_pos == null:
		issues.append("player_spawn_pos must not be empty")

	return issues
