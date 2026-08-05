@tool
## Server authority for the animals a level authored (`NPCAnimalEntity`).
##
## It does NOT spawn them — parenting does that, in the level scene: an animal under a
## Path3D walks it, one parked anywhere else idles. This owns only the part the peers
## cannot each decide for themselves: who is currently dead, and when they get back up.
##
## Animals are addressed by their NodePath under the level. That path ships inside the
## level scene, so it is identical on every peer with nothing to reconcile — no id roster,
## no spawn broadcast, no accept gate. Hooked from GamemodeManager on level load, so it
## applies to every gamemode.
class_name AnimalSpawnManager extends BaseManager

@export var level_manager: LevelManager
## How long a corpse lies there before the animal gets up. Randomized so a player carving
## through a herd doesn't have the whole lot pop back at once.
@export var respawn_delay_min: float = 8.0
@export var respawn_delay_max: float = 14.0

## Level-relative paths of the animals currently down. Server-side only — it exists to
## bring a late joiner's level into line with everyone else's (see request_animal_sync).
var _dead: Dictionary[NodePath, bool] = {}

#region Level lifecycle


## Server-side, once a level is loaded: listen to every animal it authored. The
## connections die with the level, so there is no matching teardown to forget.
func bind_level_animals() -> void:
	_dead.clear()
	for animal: NPCAnimalEntity in _level_animals():
		animal.hit_by_racer.connect(_on_animal_hit.bind(animal))


## Server-side, on returning to the lobby. The animals are already gone with their level;
## this just stops a stale corpse list following us into the next match.
func release_level_animals() -> void:
	_dead.clear()


## Client-side, once THIS peer's level is loaded. Every animal arrived alive inside the
## level scene, so unlike traffic there is nothing to spawn — only the ones that died
## before we got here need catching up on.
func request_animal_sync() -> void:
	_rpc_request_animal_sync.rpc_id(1)


@rpc("any_peer", "reliable")
func _rpc_request_animal_sync() -> void:
	if !multiplayer.is_server():
		return
	_rpc_sync_dead_animals.rpc_id(multiplayer.get_remote_sender_id(), _dead.keys())


@rpc("reliable")
func _rpc_sync_dead_animals(paths: Array) -> void:
	for path: NodePath in paths:
		# Server's list can name an animal from the level we were on a moment ago — skip
		# is intentional (the same late-RPC race the kill/respawn handlers guard).
		var animal := _animal_at(path)
		if animal == null:
			continue
		animal.die()


#endregion

#region Kill / respawn (server decides, every peer plays it)


func _on_animal_hit(_hitter: Node3D, animal: NPCAnimalEntity) -> void:
	var path := level_manager.current_level.get_path_to(animal)
	rpc_kill_animal.rpc(path)
	get_tree().create_timer(randf_range(respawn_delay_min, respawn_delay_max)).timeout.connect(
		_respawn_animal.bind(path), CONNECT_ONE_SHOT
	)


func _respawn_animal(path: NodePath) -> void:
	# Level changed while the timer ran, taking the animal with it — skip is intentional.
	if _animal_at(path) == null:
		return
	rpc_respawn_animal.rpc(path)


@rpc("call_local", "reliable")
func rpc_kill_animal(path: NodePath):
	# This peer has already moved on to another level — skip is intentional.
	var animal := _animal_at(path)
	if animal == null:
		return
	animal.die()
	if multiplayer.is_server():
		_dead[path] = true


@rpc("call_local", "reliable")
func rpc_respawn_animal(path: NodePath):
	var animal := _animal_at(path)
	if animal == null:
		return
	animal.respawn()
	if multiplayer.is_server():
		_dead.erase(path)


#endregion


## Every animal the current level authored, at any depth — under a Path3D or parked loose.
func _level_animals() -> Array[Node]:
	return level_manager.current_level.find_children("*", "NPCAnimalEntity", true, false)


## Null when the path names an animal from a level this peer no longer has loaded.
func _animal_at(path: NodePath) -> NPCAnimalEntity:
	return level_manager.current_level.get_node_or_null(path) as NPCAnimalEntity


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if level_manager == null:
		issues.append("level_manager must not be empty")
	return issues
