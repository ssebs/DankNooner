@tool
## Grindable rail between two posts. %Rail is on collision layer 9 (grind); see
## planning_docs/PlayerController.md#grinding.
extends Node3D

## Rail length in meters, end to end. The posts stay flush with its ends.
@export var length: float = 50.0:
	set(v):
		length = v
		apply_length()

## Metres above the rail's origin its "RAIL" TrickSpotLabel floats during events.
const LABEL_HEIGHT: float = 3.0

@onready var rail: GrayBoxStaticBody = %Rail
@onready var post_1: GrayBoxStaticBody = %Post1
@onready var post_2: GrayBoxStaticBody = %Post2


func _ready():
	apply_length()
	if Engine.is_editor_hint():
		return
	var label := TrickSpotLabel.new("SPOT_RAIL")
	label.position = Vector3.UP * LABEL_HEIGHT
	add_child(label)


func apply_length():
	if not is_node_ready():
		return

	rail.depth = length
	post_1.position.z = -(length - post_1.depth) * 0.5
	post_2.position.z = (length - post_2.depth) * 0.5
