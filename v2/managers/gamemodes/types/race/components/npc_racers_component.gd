@tool
## Fills the grid slots humans don't take with AI racers (events with enable_npcs) and registers
## them as racers in the RaceTask. Spawns from the back — humans keep the front rows.
class_name NPCRacersComponent extends RaceComponent

@export var npc_race_manager: NPCRaceManager


func race_start() -> void:
	if !race_mode.get_definition().enable_npcs:
		return
	var grid_markers := race_mode.get_route().get_grid_markers()
	var npc_count := grid_markers.size() - race_mode.lobby_manager.lobby_players.size()
	if npc_count <= 0:
		return
	npc_race_manager.race_task = race_mode.race_task
	for i in npc_count:
		var marker: Marker3D = grid_markers[maxi(0, grid_markers.size() - 1 - i)]
		var npc_id := npc_race_manager.spawn_npc(marker.global_position, marker.global_basis)
		race_mode.race_task.register_npc(npc_id)


func race_end() -> void:
	var race_task := npc_race_manager.race_task
	if race_task != null:
		for npc_id in npc_race_manager.get_npc_ids():
			race_task.unregister_npc(npc_id)
		npc_race_manager.race_task = null
	npc_race_manager.despawn_all_npcs()


func get_npcs() -> Array[NPCRiderEntity]:
	var npcs: Array[NPCRiderEntity] = []
	for npc_id in npc_race_manager.get_npc_ids():
		npcs.append(npc_race_manager.get_npc(npc_id))
	return npcs


func sync_to_peer(peer_id: int) -> void:
	npc_race_manager.sync_npcs_to_peer(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if npc_race_manager == null:
		issues.append("npc_race_manager must not be empty")
	return issues
