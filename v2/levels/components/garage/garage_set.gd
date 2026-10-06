## Local-only preview of a GarageUI selection: a BikeSkin + CharacterSkin on a slow turntable.
## No camera, no gameplay. Hidden at runtime until something is previewed, so peers never see
## another rider's garage.
class_name GarageSet extends Node3D

## Turntable speed (rad/s).
const TURN_SPEED: float = 0.3
## CharacterSkin's T-pose; "off" in the boost-button anim cycle.
const REST_ANIM := "Biker/reset"

@onready var _preview_spot: Marker3D = %PreviewSpot
@onready var _bike_skin: BikeSkin = %BikeSkin
@onready var _character_skin: CharacterSkin = %CharacterSkin

## Index into the character's Biker/* anims; -1 = REST_ANIM.
var _anim_index: int = -1


func _ready():
	visible = false


func _process(delta: float):
	if !visible:
		return
	_preview_spot.rotate_y(TURN_SPEED * delta)


## Boost cycles the rider through every Biker/* anim, then back to the T-pose. Hidden on every
## peer but the one previewing, so only that rider's press counts.
func _unhandled_input(event: InputEvent):
	if !visible or !event.is_action_pressed("boost"):
		return
	var anims := _character_anims()
	_anim_index = _anim_index + 1 if _anim_index + 1 < anims.size() else -1
	_play_anim()


func _character_anims() -> Array[String]:
	var anims: Array[String] = []
	for anim in _character_skin.anim_player.get_animation_list():
		if anim.begins_with("Biker/") and anim != REST_ANIM:
			anims.append(anim)
	return anims


func _play_anim():
	var anim := REST_ANIM if _anim_index < 0 else _character_anims()[_anim_index]
	_character_skin.anim_player.play(anim)


func show_preview(bike_def: BikeSkinDefinition, char_def: CharacterSkinDefinition):
	visible = true
	_show(_bike_skin, bike_def)
	_show(_character_skin, char_def)


func hide_preview():
	visible = false


## Same mesh: repaint only, since color drags preview every frame. Else rebuild.
func _show(skin: Node3D, def: Resource):
	if skin.skin_definition == def:
		return
	var same_mesh: bool = skin.skin_definition.mesh_res == def.mesh_res
	skin.skin_definition = def
	if same_mesh and !def.colors.is_empty():
		skin.mesh_skin.update_all_colors(def.colors)
	else:
		skin.apply_definition()
		# A rebuilt rider restarts at the T-pose.
		if skin == _character_skin:
			_play_anim()
