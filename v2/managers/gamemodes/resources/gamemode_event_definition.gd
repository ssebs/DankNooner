@tool
class_name GameModeEventDefinition extends Resource

enum EventType { SEQUENTIAL, CONCURRENT }

## Will use localization in rendering
@export var name: String
@export
var description: String = "Sunt nisi id proident veniam ad laboris pariatur minim eu commodo aliquip."
@export var target_gamemode: GameModeType.Kind
@export var event_type: EventType = EventType.SEQUENTIAL
