@tool
## Debug console helper. Drop in a level; registers these commands:
##   tp <name|index>  teleport local player to a destination
##   tp_list          list all destinations
##   max_boost        fill the local player's boost meter
## Destinations are the author-placed `destinations` plus every EventStartCircle in the level.
## Effects route through the host-authoritative SpawnManager, so they apply when the console user
## is the host; a client acting on itself only applies locally and reconciles away.
class_name DebugTeleporter extends Node3D

@export var destinations: Array[Node3D] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	Console.add_command(
		"tp", _teleport, ["dest"], 1, "Teleport local player to a destination (name or 1-based index)"
	)
	Console.add_command("tp_list", _tp_list, [], 0, "List all teleport destinations")
	Console.add_command("max_boost", _max_boost, [], 0, "Fill the local player's boost meter")
	# Deferred so every EventStartCircle has run _ready() and joined the group first.
	_refresh_autocomplete.call_deferred()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	Console.remove_command("tp")
	Console.remove_command("tp_list")
	Console.remove_command("max_boost")


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


func _local_peer_id() -> int:
	return int(get_tree().get_first_node_in_group(UtilsConstants.GROUPS["LocalPlayer"]).name)


## Author-placed destinations first (stable 1..N indices), then event circles.
func _targets() -> Array[Node3D]:
	var result := destinations.duplicate()
	for circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		result.append(circle as Node3D)
	return result


func _refresh_autocomplete() -> void:
	var names: PackedStringArray = []
	for t in _targets():
		names.append(t.name)
	Console.add_command_autocomplete_list("tp", names)


func _spawn_manager() -> SpawnManager:
	for manager in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Managers"]):
		if manager is SpawnManager:
			return manager
	return null


func _get_configuration_warnings() -> PackedStringArray:
	if destinations.is_empty():
		return ["Add Node3Ds to destinations, or rely on EventStartCircles in the level."]
	return []
