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
## TODO — placeholder wobble kick for the stubbed bat; tune once the real weapon lands.
const BAT_WOBBLE_STRENGTH: float = 6.0

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
	# Only players collect — NPC riders are Racers too but have no boost, so granting to them derefs a null player.
	if !_active or not body is PlayerEntity:
		return
	_apply_effect(int(body.name), _current.pickup_item_definition)
	_spawn_manager.play_pickup_sfx.rpc_id(int(body.name))
	_rpc_despawn.rpc()
	get_tree().create_timer(timeout).timeout.connect(_on_respawn_timer, CONNECT_ONE_SHOT)


## Server-only. Grants the collected item's effect to the rider, keyed on its type.
func _apply_effect(peer_id: int, definition: PickupItemDefinition) -> void:
	match definition.item_type:
		PickupItemDefinition.PickupItemType.GAS_CAN:
			_spawn_manager.grant_boost.rpc(peer_id)
		PickupItemDefinition.PickupItemType.BAT:
			# TODO — BAT is a stub. The real bat is a swung weapon: it needs a swing animation
			# and a hitbox that wobbles whichever rider it connects with (via wobble_player).
			# None of that exists yet. For now, picking it up just wobbles the collector so the
			# wobble_player callable is exercised end-to-end. Swap the placeholder gas_can mesh,
			# add the swing + hitbox, then target the rider the hitbox hits instead of `peer_id`.
			DebugUtils.DebugMsg("BAT PICKED UP — TODO: swing anim + hitbox; wobbling collector for now")
			_spawn_manager.wobble_player.rpc(peer_id, BAT_WOBBLE_STRENGTH)


func _on_respawn_timer() -> void:
	# Race may have ended during the respawn wait — deactivate() cleared _active.
	if _active:
		_spawn_random()


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if items.is_empty():
		issues.append("items must have at least one PickupItemDefinition")
	return issues
