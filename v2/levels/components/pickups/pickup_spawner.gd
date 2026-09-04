@tool
## Spawns a PickupItem at this marker while a race is running, respawning it `timeout` seconds
## after a rider collects it. Server-authoritative: the server picks the item and drives
## collect/respawn, broadcasting spawn/despawn to every peer (mirrors AnimalSpawnManager's
## RPC-by-path model — the spawner is a level node at the same path on all peers).
##
## Driven by StuntRaceTask via activate() / deactivate(), so pickups only exist during the race.
class_name PickupSpawner extends Marker3D

## Item definitions this spawner can produce; one is picked at random per spawn.
@export var items: Array[PickupItemDefinition] = []:
	set(value):
		items = value
		if Engine.is_editor_hint() and is_node_ready():
			_refresh_preview()
## Seconds after a pickup before the next one appears.
@export var timeout: float = 3.0

const PICKUP_ITEM_SCENE := preload("res://levels/components/pickups/pickup_item.tscn")

var _active: bool = false
var _current: PickupItem
## Injected by StuntRaceTask on activate() — used to grant item effects (server broadcast RPCs).
var _spawn_manager: SpawnManager
## Editor-only preview of the first item so placement is visible; never saved / spawned at runtime.
var _preview: PickupItem


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()


func activate(spawn_manager: SpawnManager) -> void:
	if !multiplayer.is_server():
		return
	_spawn_manager = spawn_manager
	_active = true
	_spawn_random()


func deactivate() -> void:
	if !multiplayer.is_server():
		return
	_active = false
	_rpc_despawn.rpc()


#region spawn / despawn (server drives, all peers apply)


## Server picks the item; the index is broadcast so every peer builds the same one.
func _spawn_random() -> void:
	_rpc_spawn.rpc(randi() % items.size())


@rpc("call_local", "reliable")
func _rpc_spawn(item_index: int) -> void:
	_clear_current()
	_current = PICKUP_ITEM_SCENE.instantiate()
	_current.pickup_item_definition = items[item_index]
	add_child(_current)
	# Only the server decides a collect — clients just show the bubble.
	if multiplayer.is_server():
		_current.body_entered.connect(_on_item_body_entered)


@rpc("call_local", "reliable")
func _rpc_despawn() -> void:
	_clear_current()


func _clear_current() -> void:
	if _current != null:
		_current.queue_free()
		_current = null


#endregion


## Editor-only: show the first item where it'll spawn. Not owned, so it isn't saved to the scene.
func _refresh_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null
	if items.is_empty() or items[0] == null:
		return
	_preview = PICKUP_ITEM_SCENE.instantiate()
	_preview.pickup_item_definition = items[0]
	add_child(_preview)


func _on_item_body_entered(body: Node3D) -> void:
	if !_active or !body.is_in_group(UtilsConstants.GROUPS["Racers"]):
		return
	_apply_effect(int(body.name), _current.pickup_item_definition)
	_rpc_despawn.rpc()
	get_tree().create_timer(timeout).timeout.connect(_on_respawn_timer, CONNECT_ONE_SHOT)


## Server-only. Grants the collected item's effect to the rider, keyed on its type.
func _apply_effect(peer_id: int, definition: PickupItemDefinition) -> void:
	match definition.item_type:
		PickupItemDefinition.PickupItemType.GAS_CAN:
			_spawn_manager.grant_boost.rpc(peer_id)


func _on_respawn_timer() -> void:
	# Race may have ended during the respawn wait — deactivate() cleared _active.
	if _active:
		_spawn_random()


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if items.is_empty():
		issues.append("items must have at least one PickupItemDefinition")
	return issues
