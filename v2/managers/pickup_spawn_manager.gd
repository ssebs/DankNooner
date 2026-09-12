@tool
## Server authority for the level's free-roam pickup spawners (the gas-station props, etc.).
## Race spawners live under an EventStartCircle and are driven by their own StuntRaceTask, so
## they stay race-only — this skips them and owns just the world pickups.
##
## Lifecycle mirrors NPCTrafficManager: FreeRoamGameMode calls activate/deactivate (server) and
## request_pickup_sync (client). The spawners are level nodes at the same path on every peer, so
## there's nothing to spawn on join — only the item currently showing needs catching up on.
class_name PickupSpawnManager extends BaseManager

@export var level_manager: LevelManager
## Handed to each spawner so it can grant collected item effects (server broadcast RPCs).
@export var spawn_manager: SpawnManager

## Spawners turned on this session (server-side), kept so a peer whose level loaded after the
## activate broadcast can be resynced (see request_pickup_sync).
var _active: Array[PickupSpawner] = []


#region Lifecycle (FreeRoamGameMode drives)


## Server-side, from FreeRoamGameMode.Enter.
func activate_pickups() -> void:
	_active = _free_roam_spawners()
	for spawner in _active:
		spawner.activate(spawn_manager)


## Server-side, from FreeRoamGameMode.Exit — broadcasts a despawn to every peer.
func deactivate_pickups() -> void:
	for spawner in _active:
		spawner.deactivate()
	_active = []


## Client-side, from FreeRoamGameMode.Enter once THIS peer's level is loaded: pull whatever the
## server spawned before we were ready (the fresh-start race and late join both miss it).
func request_pickup_sync() -> void:
	_rpc_request_pickup_sync.rpc_id(1)


@rpc("any_peer", "reliable")
func _rpc_request_pickup_sync() -> void:
	if !multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	for spawner in _active:
		spawner.sync_to_peer(peer_id)


#endregion


## Free-roam pickups are the level's PickupSpawners not parented under an EventStartCircle;
## owned=false so spawners inside instanced props (the gas station) are found too.
func _free_roam_spawners() -> Array[PickupSpawner]:
	var out: Array[PickupSpawner] = []
	for spawner: PickupSpawner in level_manager.current_level.find_children(
		"*", "PickupSpawner", true, false
	):
		if _event_circle_ancestor(spawner) == null:
			out.append(spawner)
	return out


func _event_circle_ancestor(node: Node) -> EventStartCircle:
	var parent := node.get_parent()
	while parent != null:
		if parent is EventStartCircle:
			return parent
		parent = parent.get_parent()
	return null


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	return issues
