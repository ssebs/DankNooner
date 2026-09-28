@tool
## Ambient traffic during events with enable_traffic, at TrafficSettings.race_traffic_amount
## rather than the free-roam count. Racers spawn on grid markers, not lanes, so the two don't
## fight over spawn points.
class_name TrafficComponent extends RaceComponent

## Optional — unlinked in main_game while traffic is disabled for perf; null skips traffic.
@export var npc_traffic_manager: NPCTrafficManager


func race_start() -> void:
	if _enabled():
		npc_traffic_manager.start_traffic(true)


func race_end() -> void:
	if _enabled():
		npc_traffic_manager.stop_traffic()


## Client-side Enter: same pull as FreeRoamGameMode — see that Enter for why.
func client_enter() -> void:
	if _enabled():
		npc_traffic_manager.request_traffic_sync()


func client_exit() -> void:
	if _enabled():
		npc_traffic_manager.reset_local_traffic()


func _enabled() -> bool:
	return npc_traffic_manager != null and race_mode.get_definition().enable_traffic
