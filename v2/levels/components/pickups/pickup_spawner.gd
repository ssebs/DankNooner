@tool
## Spawns a row of `count` PickupItems along this marker's local Z (centered on it) while a race is
## running; each slot respawns `timeout` seconds after a rider collects it. Server-authoritative:
## the server picks each slot's item and drives collect/respawn, broadcasting spawn/despawn to every
## peer (mirrors AnimalSpawnManager's RPC-by-path model — the spawner is a level node at the same
## path on all peers).
##
## Driven by RaceGameMode's PickupsComponent via activate() / deactivate(), so pickups only exist during the race.
class_name PickupSpawner extends Marker3D

## Item definitions this spawner can produce; one is picked per spawn, weighted by each item's weight.
@export var items: Array[PickupItemDefinition] = []:
	set(value):
		items = value
		if Engine.is_editor_hint() and is_node_ready():
			_refresh_preview()
## Items in the row, laid out along local Z so riders crossing along local X see each one's profile.
@export_range(1, 32) var count: int = 1:
	set(value):
		count = value
		if Engine.is_editor_hint() and is_node_ready():
			_refresh_preview()
## Meters between neighboring items in the row.
@export var spacing: float = 4.5:
	set(value):
		spacing = value
		if Engine.is_editor_hint() and is_node_ready():
			_refresh_preview()
## Seconds after a pickup before the next one appears in that slot.
@export var timeout: float = 3.0

const PICKUP_ITEM_SCENE := preload("res://levels/components/pickups/pickup_item.tscn")

var _active: bool = false
var _rng := RandomNumberGenerator.new()
## Per slot: the item showing, null between collect and respawn.
var _current: Array[PickupItem] = []
## Per slot: item index showing, resent on a late-join/load-race sync so every peer builds the same one.
var _current_index: Array[int] = []
## Injected on activate() — a collect goes through it (instant effect, or the rider's held slot).
var _item_manager: ItemManager
## Editor-only preview of the first item in every slot so placement is visible; never saved / spawned at runtime.
var _previews: Array[PickupItem] = []


func _ready() -> void:
	_current.resize(count)
	_current_index.resize(count)
	if Engine.is_editor_hint():
		_refresh_preview()


func activate(item_manager: ItemManager) -> void:
	if !multiplayer.is_server():
		return
	_item_manager = item_manager
	_active = true
	for slot in count:
		_spawn_random(slot)


func deactivate() -> void:
	if !multiplayer.is_server():
		return
	_active = false
	for slot in count:
		_rpc_despawn.rpc(slot)


## Server-side. Re-send the items currently showing to a peer whose level loaded after our
## activate broadcast. A slot is null between collect and respawn — that peer just catches the next one.
func sync_to_peer(peer_id: int) -> void:
	for slot in count:
		if _current[slot] != null:
			_rpc_spawn.rpc_id(peer_id, slot, _current_index[slot])


#region spawn / despawn (server drives, all peers apply)


## Server picks the slot's item by weight; the index is broadcast so every peer builds the same one.
func _spawn_random(slot: int) -> void:
	var weights := PackedFloat32Array(
		items.map(func(item: PickupItemDefinition) -> float: return item.weight)
	)
	_rpc_spawn.rpc(slot, _rng.rand_weighted(weights))


@rpc("call_local", "reliable")
func _rpc_spawn(slot: int, item_index: int) -> void:
	_clear_slot(slot)
	_current_index[slot] = item_index
	_current[slot] = _make_item(slot, items[item_index])
	# Only the server decides a collect — clients just show the bubble.
	if multiplayer.is_server():
		_current[slot].body_entered.connect(_on_item_body_entered.bind(slot))


@rpc("call_local", "reliable")
func _rpc_despawn(slot: int) -> void:
	_clear_slot(slot)


func _clear_slot(slot: int) -> void:
	if _current[slot] != null:
		_current[slot].queue_free()
		_current[slot] = null


func _make_item(slot: int, definition: PickupItemDefinition) -> PickupItem:
	var item: PickupItem = PICKUP_ITEM_SCENE.instantiate()
	item.pickup_item_definition = definition
	item.position = Vector3(0, 0, (slot - (count - 1) / 2.0) * spacing)
	add_child(item)
	return item


#endregion


## Editor-only: show the first item in every slot. Not owned, so they aren't saved to the scene.
func _refresh_preview() -> void:
	for preview in _previews:
		preview.queue_free()
	_previews.clear()
	if items.is_empty() or items[0] == null:
		return
	for slot in count:
		_previews.append(_make_item(slot, items[0]))


func _on_item_body_entered(body: Node3D, slot: int) -> void:
	# Only players collect — NPC riders are Racers too but have no boost, so granting to them derefs a null player.
	if !_active or not body is PlayerEntity:
		return
	# Rider's slot is full — the bubble stays for someone else.
	if !_item_manager.collect(int(body.name), _current[slot].pickup_item_definition):
		return
	_rpc_despawn.rpc(slot)
	get_tree().create_timer(timeout).timeout.connect(_on_respawn_timer.bind(slot), CONNECT_ONE_SHOT)


func _on_respawn_timer(slot: int) -> void:
	# Race may have ended during the respawn wait — deactivate() cleared _active.
	if _active:
		_spawn_random(slot)


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if items.is_empty():
		issues.append("items must have at least one PickupItemDefinition")
	return issues
