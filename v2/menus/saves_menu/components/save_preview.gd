## A still of a save's active loadout: poses a RiderVisual in its own SubViewport, draws a few frames,
## then freezes on the last one. Used by the Saves menu cards and the main menu's current save.
class_name SavePreview extends TextureRect

## Frames the preview draws before it freezes, so the rider's IK settles onto the seat.
const PREVIEW_FRAMES := 5

@onready var _viewport: SubViewport = %PreviewViewport
@onready var _rider: RiderVisual = %RiderVisual

## Frames left before the preview freezes.
var _frames_left: int = 0


func _ready():
	set_process(false)
	texture = _viewport.get_texture()


func _process(_delta: float):
	_frames_left -= 1
	if _frames_left <= 0:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(false)


## Seat the rider like TrickDemo and redraw.
func show_player(player_def: PlayerDefinition) -> void:
	_rider.bike_skin.skin_definition = player_def.bike_skin
	_rider.character_skin.skin_definition = player_def.character_skin
	_rider.bike_skin.apply_definition()
	_rider.character_skin.apply_definition()
	_rider.seat()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_frames_left = PREVIEW_FRAMES
	set_process(true)
