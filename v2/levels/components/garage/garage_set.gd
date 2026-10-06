## Local-only preview of a GarageUI selection, turned by cam look input or a mouse drag: the rider
## seated, turning with the bike, or on character pages stepped off and turning alone. No camera,
## no gameplay. Hidden at runtime until something is previewed, so peers never see another
## rider's garage.
class_name GarageSet extends Node3D

## Turn speed from cam_left / cam_right (rad/s).
const TURN_SPEED: float = 3.0
## Turn per pixel of mouse drag (rad).
const DRAG_TURN: float = 0.01
## CharacterSkin's T-pose; "off" in the pose cycle.
const REST_ANIM := "Biker/reset"
## Where the rider stands when off the bike.
const STAND_OFFSET := Vector3(1.2, 0, 0)

@onready var _preview_spot: Marker3D = %PreviewSpot
@onready var _rider: RiderVisual = %RiderVisual

## Index into the character's Biker/* anims; -1 = REST_ANIM.
var _anim_index: int = -1
var _seated: bool = false
## The last preview was a character page.
var _is_character: bool = false


func _ready():
	visible = false


func _process(delta: float):
	if !visible:
		return
	_turning().rotate_y(Input.get_axis("cam_left", "cam_right") * TURN_SPEED * delta)


## Hidden on every peer but the one previewing, so only that rider's input counts.
func _unhandled_input(event: InputEvent):
	if !visible:
		return
	if event.is_action_pressed("boost"):
		cycle_pose()
	# Unhandled, so only drags over the scene; the UI panels stop the mouse.
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_turning().rotate_y(event.relative.x * DRAG_TURN)


## Cycles the rider through every Biker/* anim, then back to the T-pose.
func cycle_pose():
	var anims := _character_anims()
	_anim_index = _anim_index + 1 if _anim_index + 1 < anims.size() else -1
	_play_anim()
	_update_seated(false)


func _character_anims() -> Array[String]:
	var anims: Array[String] = []
	for anim in _rider.character_skin.anim_player.get_animation_list():
		if anim.begins_with("Biker/") and anim != REST_ANIM:
			anims.append(anim)
	return anims


func _play_anim():
	var anim := REST_ANIM if _anim_index < 0 else _character_anims()[_anim_index]
	_rider.character_skin.anim_player.play(anim)


func show_preview(bike_def: BikeSkinDefinition, char_def: CharacterSkinDefinition, is_character: bool):
	visible = true
	_is_character = is_character
	var bike_rebuilt := _show(_rider.bike_skin, bike_def)
	var rider_rebuilt := _show(_rider.character_skin, char_def)
	_update_seated(bike_rebuilt or rider_rebuilt)


func hide_preview():
	visible = false


## Same mesh: repaint only, since color drags preview every frame. Else rebuild, returning true.
func _show(skin: Node3D, def: Resource) -> bool:
	if skin.skin_definition == def:
		return false
	var same_mesh: bool = skin.skin_definition.mesh_res == def.mesh_res
	skin.skin_definition = def
	if same_mesh and !def.colors.is_empty():
		skin.mesh_skin.update_all_colors(def.colors)
		return false
	skin.apply_definition()
	# A rebuilt rider restarts at the T-pose.
	if skin == _rider.character_skin:
		_play_anim()
	return true


## Seated, the bike and rider turn together; standing, just the rider.
func _turning() -> Node3D:
	return _preview_spot if _seated else _rider.character_skin


## Seated only at rest on a bike page; posing or a character page steps the rider off.
func _update_seated(rebuilt: bool):
	var seated := !_is_character and _anim_index < 0
	# A rebuilt skin needs its IK re-created against the new skeleton / seat.
	if seated != _seated or (seated and rebuilt):
		_set_seated(seated)


func _set_seated(seated: bool):
	_seated = seated
	var character := _rider.character_skin
	if seated:
		character.transform = Transform3D.IDENTITY
		_rider.seat()
	else:
		character.disable_ik()
		character.transform = Transform3D(Basis.IDENTITY, STAND_OFFSET)
		# Re-pose so the hips IK moved onto the seat snap back.
		_play_anim()
	# A rider rebuilt while standing frees its IK modifier with the old skeleton; seat() makes a new one.
	character.ik_controller.set_physics_process(seated)
