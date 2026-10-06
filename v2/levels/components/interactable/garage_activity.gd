## Free-roam garage bay: park in it to edit your profile and loadouts in GarageHUDState's GarageUI.
## The preview is this bay's local GarageSet; the live bike syncs on commit, through the lobby.
## The menu garage level reuses the bay's camera and GarageSet (its start circle is inert there).
class_name GarageActivity extends FreeRoamActivity

@onready var garage_set: GarageSet = %GarageSet


#override
func get_result() -> float:
	return 0.0


#override
## Local only — the GarageSet preview takes the rider's place.
func _on_session_start():
	_player.visible = false
	_hud_manager.go_to_garage_hud(self)


#override
## Leaving GarageHUDState commits the edits.
func _on_session_end():
	_player.visible = true
	_hud_manager.go_to_riding_hud()
