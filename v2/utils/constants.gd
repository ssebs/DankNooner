class_name UtilsConstants extends Node

const PORT = 42068

## Godot Group names.
const GROUPS = {
	"Managers": "Managers",
	"Validate": "Validate",
	"InputStateManager": "InputStateManager",
	"EventCircles": "EventCircles",
	"Racers": "Racers",
	## Ambient free-roam traffic. A subset of Racers (they still queue behind each other
	## and crash into things), tagged so HUD/scoring can tell them from actual competitors.
	"Traffic": "Traffic",
	## Path3Ds a level wants ambient animals walking along. AnimalSpawnManager puts one
	## animal on each, so adding a walk route is a level-authoring job, not a code one.
	"AnimalPaths": "AnimalPaths",
	"Terrain3D": "Terrain3D",
}
