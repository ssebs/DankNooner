@tool
class_name RacingLine extends Path3D

@export var semantic_color := SemanticColors.Value.OK:
	set(v):
		semantic_color = v
		if not is_node_ready():
			return
		if Engine.is_editor_hint():
			apply_color(SemanticColors.COLOR_VALUES[v])
		else:
			_from_color = _material().albedo_color
			_elapsed = 0.0

const TRANSITION_DURATION := 0.5

@onready var csgpolygon: CSGPolygon3D = %CSGPolygon3D

var _from_color := Color.WHITE
var _elapsed := TRANSITION_DURATION


func _ready():
	apply_color(SemanticColors.COLOR_VALUES[semantic_color])


func _process(delta: float):
	if _elapsed >= TRANSITION_DURATION:
		return
	_elapsed = minf(_elapsed + delta, TRANSITION_DURATION)
	var t := _elapsed / TRANSITION_DURATION
	apply_color(_from_color.lerp(SemanticColors.COLOR_VALUES[semantic_color], t))


func apply_color(color: Color):
	_material().albedo_color = color


func _material() -> StandardMaterial3D:
	return csgpolygon.material as StandardMaterial3D
