@tool
## Owns ambient path-walking animals (NPCAnimalEntity). One animal per Path3D the level
## tagged into the AnimalPaths group; the species is rolled per path server-side and shipped
## as a res:// path, the same way NPCTrafficManager ships vehicle skins.
##
## The walk itself never crosses the wire — every peer advances the same PathFollow3D along
## the same level-authored curve at the same speed. Only the events are broadcast: spawn,
## the kill a racer triggers, respawn, despawn.
##
## FreeRoamGameMode starts/stops it, mirroring NPCTrafficManager's lifecycle and client
## accept-gate contract (see start_animals / request_animal_sync).
class_name AnimalSpawnManager extends BaseManager

@export var level_manager: LevelManager
## Species pool, rolled per path. Empty means this map gets no animals.
@export var animal_definitions: Array[AnimalSkinDefinition] = [
	load("res://resources/npcs/horse_animal_definition.tres")
]
## How long a corpse lies there before the animal is put back on its path. Randomized so a
## player carving through a herd doesn't have the whole lot pop back at once.
@export var respawn_delay_min: float = 8.0
@export var respawn_delay_max: float = 14.0

const ANIMAL_SCENE: PackedScene = preload("res://entities/npc/npc_animal_entity.tscn")
## Race NPCs count down from -1 and traffic from -1000, so animals start far below both —
## the three rosters can never produce the same node name under one parent.
const FIRST_ID: int = -2000

var _animals: Dictionary[int, NPCAnimalEntity] = {}
## Server-side spawn args per animal, replayed to a peer whose level loaded late.
var _spawns: Dictionary[int, Dictionary] = {}
## Client-side gate: false until this peer's gamemode Enter confirms the level is loaded.
## Same contract (and same reason) as NPCTrafficManager._accept_spawns.
var _accept_spawns: bool = false
var _next_id: int = FIRST_ID

#region Animal lifecycle (server only)


## Put one animal on every Path3D this map tagged for them.
func start_animals() -> void:
	_purge_freed()
	if animal_definitions.is_empty():
		return
	for path in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["AnimalPaths"]):
		# LevelManager.despawn_level() queue_free()s the outgoing level, which stays in the
		# tree — and in this group — until the end of the frame. Unscoped, we would spawn
		# half the herd into a level that is about to be freed, and get_path_to would hand
		# the survivors a ../.. path that resolves to nothing on the other peers.
		if !level_manager.current_level.is_ancestor_of(path):
			continue
		var animal_id := _next_id
		_next_id -= 1
		# Dropped at a random point along the curve rather than at its start, so a map's
		# animals aren't all lined up at their path origins when the level opens.
		var spawn := {
			"definition": animal_definitions.pick_random().resource_path,
			"path": level_manager.current_level.get_path_to(path),
			"progress_ratio": randf(),
			"dead": false,
		}
		_spawns[animal_id] = spawn
		rpc_spawn_animal.rpc(animal_id, spawn)


func stop_animals() -> void:
	_purge_freed()
	for animal_id in _animals.keys():
		rpc_despawn_animal.rpc(animal_id)
	_spawns.clear()


## Drop roster entries whose node already died with its level. A map change tears the old
## level down without necessarily reaching us first, and a freed animal left in the roster
## takes the next despawn or resync with it.
func _purge_freed() -> void:
	for animal_id in _animals.keys():
		if !is_instance_valid(_animals[animal_id]):
			_animals.erase(animal_id)
			_spawns.erase(animal_id)


#endregion

#region Client spawn sync


## Client-side, from gamemode Enter once THIS peer's level is loaded: accept spawn
## broadcasts from here on and pull whatever the server spawned before that. Covers both
## the fresh-start timing race and late join — see NPCTrafficManager.request_traffic_sync.
func request_animal_sync() -> void:
	# Entries freed with their old level would otherwise hit the has() dedupe in
	# rpc_spawn_animal and block their own resync.
	_purge_freed()
	_accept_spawns = true
	_rpc_request_animal_sync.rpc_id(1)


## Client-side, from gamemode Exit: stop accepting spawns and drop local animals. The
## server's stop_animals despawns normally do the freeing — this covers orderings where
## our Exit runs before those despawn RPCs arrive.
func reset_local_animals() -> void:
	_accept_spawns = false
	_purge_freed()
	for animal_id in _animals:
		_free_locally(animal_id)
	_animals.clear()


## A peer's level just finished loading — resend every animal at its CURRENT point along
## the path, and dead if it is currently dead, so the newcomer sees what everyone else does.
@rpc("any_peer", "reliable")
func _rpc_request_animal_sync() -> void:
	if !multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	for animal_id in _animals:
		var spawn := _spawns[animal_id].duplicate()
		spawn["progress_ratio"] = _animals[animal_id].path_follow.progress_ratio
		rpc_spawn_animal.rpc_id(peer_id, animal_id, spawn)


#endregion

#region Spawn / despawn (broadcast RPCs, mirrors NPCTrafficManager)

@rpc("call_local", "reliable")
func rpc_spawn_animal(animal_id: int, spawn: Dictionary):
	# Our level isn't loaded yet (spawn broadcast raced our spawn_level) — dropped here,
	# recovered by request_animal_sync once the gamemode enters.
	if !multiplayer.is_server() and !_accept_spawns:
		return
	# Broadcast and resync can both deliver the same animal — first one wins.
	if _animals.has(animal_id):
		return
	DebugUtils.DebugMsg("Adding animal locally: %s - %s" % [animal_id, spawn["definition"]])

	# Resolved per peer off the level, which is identical everywhere — the NodePath is the
	# only thing that needs shipping, and the curve itself never crosses the wire.
	var path3d := level_manager.current_level.get_node(spawn["path"]) as Path3D
	var follow := PathFollow3D.new()
	follow.name = str(animal_id)
	follow.loop = true
	# Yaw only. An animal stays upright: letting the curve's tilt through would roll it
	# onto its side wherever a level author banked the path.
	follow.rotation_mode = PathFollow3D.ROTATION_Y
	path3d.add_child(follow, true)

	var animal := ANIMAL_SCENE.instantiate() as NPCAnimalEntity
	animal.name = str(animal_id)
	animal.animal_skin_definition = load(spawn["definition"])
	# Before add_child so the entity is never briefly parented without knowing its follower.
	animal.path_follow = follow
	follow.add_child(animal)
	follow.progress_ratio = spawn["progress_ratio"]
	animal.walking = true
	_animals[animal_id] = animal

	# Late joiner arriving mid-corpse — drop it straight into the death pose rather than
	# showing it walking until the respawn timer everyone else is already waiting on fires.
	if spawn["dead"]:
		animal.die()

	if !multiplayer.is_server():
		return
	animal.hit_by_racer.connect(_on_animal_hit.bind(animal_id))


@rpc("call_local", "reliable")
func rpc_despawn_animal(animal_id: int):
	# This peer may never have accepted the spawn (late join / level still loading) —
	# skip is intentional.
	if !_animals.has(animal_id):
		return
	_free_locally(animal_id)
	_animals.erase(animal_id)


## Free the PathFollow3D we created under the level's Path3D, not just the animal —
## otherwise every level change leaves a pile of empty followers behind.
func _free_locally(animal_id: int) -> void:
	_animals[animal_id].path_follow.queue_free()


#endregion

#region Kill / respawn (server decides, every peer plays it)


func _on_animal_hit(_hitter: Node3D, animal_id: int) -> void:
	rpc_kill_animal.rpc(animal_id)
	get_tree().create_timer(randf_range(respawn_delay_min, respawn_delay_max)).timeout.connect(
		_respawn_animal.bind(animal_id), CONNECT_ONE_SHOT
	)


func _respawn_animal(animal_id: int) -> void:
	# Animal may have been despawned while the timer ran (level change) — skip is intentional.
	if !_animals.has(animal_id):
		return
	# Somewhere else along the path, so a player camped on the kill spot doesn't get a
	# fresh animal walking into them every respawn.
	rpc_respawn_animal.rpc(animal_id, randf())


@rpc("call_local", "reliable")
func rpc_kill_animal(animal_id: int):
	# Never accepted the spawn — skip is intentional (see rpc_despawn_animal).
	if !_animals.has(animal_id):
		return
	_animals[animal_id].die()
	if multiplayer.is_server():
		_spawns[animal_id]["dead"] = true


@rpc("call_local", "reliable")
func rpc_respawn_animal(animal_id: int, progress_ratio: float):
	if !_animals.has(animal_id):
		return
	_animals[animal_id].respawn(progress_ratio)
	if multiplayer.is_server():
		_spawns[animal_id]["progress_ratio"] = progress_ratio
		_spawns[animal_id]["dead"] = false


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if level_manager == null:
		issues.append("level_manager must not be empty")
	return issues
