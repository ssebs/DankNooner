@tool
## Gate / ring that fires `entered` when a PlayerEntity passes through.
## Reused by tutorial checkpoint objectives and by race routes (a GameModeEvent's checkpoints group).
class_name CheckPointMarker extends GameModeObject

@export var width: float = 20.0:
	set(value):
		width = value
		_apply_layout()

@export var spawn_width: float = 16.0:
	set(value):
		spawn_width = value
		_apply_layout()

## Which side of the road crashed racers respawn on.
@export var side: SpawnGrid.RoadSide = SpawnGrid.RoadSide.RIGHT:
	set(value):
		side = value
		_apply_layout()

@onready var _trigger_shape: CollisionShape3D = %CollisionShape3D
@onready var _border_left: Node3D = %BorderCylLeft
@onready var _border_right: Node3D = %BorderCylRight
@onready var _respawn_points: SpawnGrid = %RespawnPoints
@onready var _anim_player: AnimationPlayer = %AnimationPlayer


func _ready():
	super()
	_trigger_shape.shape = BoxShape3D.new()
	_apply_layout()


## Respawn slots for this checkpoint, in tree order — spreads crashed racers out
## instead of stacking them on the marker origin.
func get_respawn_points() -> Array[Marker3D]:
	return _respawn_points.get_markers()


## Client-side race feedback: flashes, then hides. The pillar material is local-to-scene, so this
## only recolors this gate.
func play_passed():
	_anim_player.play(&"passed")


## Shows the gate in its unpassed color.
func reset_passed():
	_anim_player.play(&"RESET")


func _apply_layout():
	if !is_node_ready():
		return
	(_trigger_shape.shape as BoxShape3D).size = Vector3(width, 64, 1)
	_border_left.position.x = - width / 2.0
	_border_right.position.x = width / 2.0
	_respawn_points.width = spawn_width
	_respawn_points.side = side
