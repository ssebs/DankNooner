@tool
## Debug console helper. Drop in a level; registers these commands:
##   tp <name|index>  teleport local player to a destination
##   tp_list          list all destinations
##   max_boost        fill the local player's boost meter
##   give_item <item> collect an item as if from a pickup (host only)
##   items_list       list all give_item items
## Destinations are the author-placed `destinations` plus every EventStartCircle and GarageActivity in the level.
## Effects route through the host-authoritative SpawnManager, so they apply when the console user
## is the host; a client acting on itself only applies locally and reconciles away.
class_name DebugTeleporter extends Node3D

@export var destinations: Array[Node3D] = []

const ITEM_DEFINITIONS: Dictionary[String, PickupItemDefinition] = {
	"gas_can": preload("res://levels/components/pickups/gas_can_pickup_definition.tres"),
	"bat": preload("res://levels/components/pickups/bat_pickup_definition.tres"),
	"oil_slick": preload("res://levels/components/pickups/oil_slick_pickup_definition.tres"),
	"ramp": preload("res://levels/components/pickups/ramp_pickup_definition.tres"),
	"shotgun": preload("res://levels/components/pickups/shotgun_pickup_definition.tres"),
}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	Console.add_command(
		"tp", _teleport, ["dest"], 1, "Teleport local player to a destination (name or 1-based index)"
	)
	Console.add_command("tp_list", _tp_list, [], 0, "List all teleport destinations")
	Console.add_command("max_boost", _max_boost, [], 0, "Fill the local player's boost meter")
	Console.add_command("give_item", _give_item, ["item"], 1, "Collect an item as if from a pickup (host only)")
	Console.add_command_autocomplete_list("give_item", PackedStringArray(ITEM_DEFINITIONS.keys()))
	Console.add_command("items_list", _items_list, [], 0, "List all give_item items")
	# Deferred so every EventStartCircle has run _ready() and joined the group first.
	_refresh_autocomplete.call_deferred()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	Console.remove_command("tp")
	Console.remove_command("tp_list")
	Console.remove_command("max_boost")
	Console.remove_command("give_item")
	Console.remove_command("items_list")


func _teleport(arg: String) -> void:
	var targets := _targets()
	var target: Node3D = null
	for t in targets:
		if t.name == arg:
			target = t
			break
	if target == null and arg.is_valid_int():
		var index := int(arg) - 1
		if index >= 0 and index < targets.size():
			target = targets[index]
	if target == null:
		DebugUtils.DebugMsg("tp: no destination '%s'" % arg)
		return
	_spawn_manager().respawn_player_at.rpc(_local_peer_id(), target.global_position, target.global_basis)


func _tp_list() -> void:
	var targets := _targets()
	for i in targets.size():
		Console.print_line("%d: %s" % [i + 1, targets[i].name])


func _max_boost() -> void:
	_spawn_manager().max_boost_player.rpc(_local_peer_id())


func _items_list() -> void:
	for item in ITEM_DEFINITIONS:
		Console.print_line(item)


## Straight into ItemManager.collect, which is server-side — a client has no slots to fill.
func _give_item(arg: String) -> void:
	if !multiplayer.is_server():
		Console.print_line("give_item: host only")
		return
	if !ITEM_DEFINITIONS.has(arg):
		Console.print_line("give_item: no item '%s' (%s)" % [arg, ", ".join(PackedStringArray(ITEM_DEFINITIONS.keys()))])
		return
	if !_item_manager().collect(_local_peer_id(), ITEM_DEFINITIONS[arg]):
		Console.print_line("give_item: already holding an item")


func _local_peer_id() -> int:
	return int(get_tree().get_first_node_in_group(UtilsConstants.GROUPS["LocalPlayer"]).name)


## Author-placed destinations first (stable 1..N indices), then event circles, then garages.
func _targets() -> Array[Node3D]:
	var result := destinations.duplicate()
	for circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		result.append(circle as Node3D)
	for activity in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["FreeRoamActivities"]):
		if activity is GarageActivity:
			result.append(activity)
	return result


func _refresh_autocomplete() -> void:
	var names: PackedStringArray = []
	for t in _targets():
		names.append(t.name)
	Console.add_command_autocomplete_list("tp", names)


func _spawn_manager() -> SpawnManager:
	return _find_manager(SpawnManager)


func _item_manager() -> ItemManager:
	return _find_manager(ItemManager)


func _find_manager(type: Variant) -> BaseManager:
	for manager in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Managers"]):
		if is_instance_of(manager, type):
			return manager
	return null


func _get_configuration_warnings() -> PackedStringArray:
	if destinations.is_empty():
		return ["Add Node3Ds to destinations, or rely on EventStartCircles in the level."]
	return []
