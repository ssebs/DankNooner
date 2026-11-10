@tool
## Fills the grid slots humans don't take with AI racers (events with enable_npcs) and registers
## them as racers in the RaceTask. Spawns from the back — humans keep the front rows. A bot that
## finishes counts in every component's standings, like a human.
class_name NPCRacersComponent extends RaceComponent

@export var npc_race_manager: NPCRaceManager


func race_start() -> void:
	race_mode.race_task.lap_completed.connect(_on_lap_completed)
	if !race_mode.get_definition().enable_npcs:
		return
	var grid_markers := race_mode.get_event().get_spawn_markers()
	var npc_count := grid_markers.size() - race_mode.lobby_manager.lobby_players.size()
	if npc_count <= 0:
		return
	npc_race_manager.race_task = race_mode.race_task
	for i in npc_count:
		var slot := maxi(0, grid_markers.size() - 1 - i)
		var marker: Marker3D = grid_markers[slot]
		var npc_id := npc_race_manager.spawn_npc(marker.global_position, marker.global_basis)
		race_mode.race_task.register_npc(npc_id, slot)
	npc_race_manager.bake_racing_line(race_mode.get_event())


func race_end() -> void:
	race_mode.race_task.lap_completed.disconnect(_on_lap_completed)
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


## Humans finish through the runner (RaceGameMode._on_runner_player_completed); bots only here.
func _on_lap_completed(racer_id: int, _lap_ms: int) -> void:
	if racer_id >= 0 or race_mode.race_task.get_completion_time_ms(racer_id) < 0.0:
		return
	for component in race_mode.get_components():
		component.racer_finished(racer_id)


func sync_to_peer(peer_id: int) -> void:
	npc_race_manager.sync_npcs_to_peer(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if npc_race_manager == null:
		issues.append("npc_race_manager must not be empty")
	return issues
