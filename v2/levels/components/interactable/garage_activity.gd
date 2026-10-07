## Free-roam garage bay: park in it to edit your profile and loadouts in GarageHUDState's GarageUI.
## The preview is this bay's local GarageSet; the live bike syncs on commit, through the lobby.
## The menu garage level reuses the bay's camera and GarageSet (its start circle is inert there).
class_name GarageActivity extends FreeRoamActivity

@onready var garage_set: GarageSet = %GarageSet


#override
## Every rider parks on the same spot, hidden and without collision.
func is_shared() -> bool:
	return true


#override
func server_start(peer_id: int, spawn_manager: SpawnManager):
	super(peer_id, spawn_manager)
	spawn_manager.set_player_hidden.rpc(peer_id, true)


#override
## Turned around on the spot, so the rider rides back out instead of facing the wall.
func server_end(peer_id: int, result: float, spawn_manager: SpawnManager):
	spawn_manager.respawn_player_in_place.rpc(
		peer_id, bike_spot.global_position, bike_spot.global_basis * Basis(Vector3.UP, PI)
	)
	spawn_manager.set_player_hidden.rpc(peer_id, false)
	super(peer_id, result, spawn_manager)


#override
func get_result() -> float:
	return 0.0


#override
## The GarageSet preview takes the rider's place.
func _on_session_start():
	_hud_manager.go_to_garage_hud(self)


#override
## Leaving GarageHUDState commits the edits.
func _on_session_end():
	_hud_manager.go_to_riding_hud()
