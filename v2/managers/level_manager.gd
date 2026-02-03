class_name LevelManager extends Node

enum LevelName {
	TEST_LEVEL_01,
}

# @export var state_machine: StateMachine
@export var spawn_node: Node3D

## PackedScene of type LevelDefinition
@export var possible_levels: Dictionary[LevelName, PackedScene] = {
	LevelName.TEST_LEVEL_01: preload("res://levels/test_levels/test_01/test_01_level.tscn")
}
## LevelName enum => localization.csv's key name
var level_name_map: Dictionary[LevelName, String] = {LevelName.TEST_LEVEL_01: "LEVEL_TEST_1_LABEL"}

var current_level: LevelName

# func _ready():
# 	for child in state_machine.get_children():
# 		if !child is LevelState:
# 			continue
# 		level_name_state_map[child.name] = child


func spawn_level(level_name: LevelName):
	if !possible_levels.has(level_name):
		printerr("Could not find LevelName.%s in possible_levels" % level_name)

	for child in spawn_node.get_children():
		child.queue_free()

	var spawned_level = possible_levels[level_name].instantiate()
	spawned_level.name = level_name_map.get(level_name)
	spawned_level.level_manager = self
	spawn_node.add_child(spawned_level)

# ## Get a map of LevelName => LevelState for all children of this mgr
# func get_all_levels() -> Dictionary[String, LevelState]:
# 	return level_name_state_map

# func get_level_by_name(name_to_check: String) -> LevelState:
# 	return level_name_state_map.get(name_to_check)
