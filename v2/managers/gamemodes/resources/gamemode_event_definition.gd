@tool
class_name GameModeEventDefinition extends Resource

enum EventType { SEQUENTIAL, CONCURRENT }

## Will use localization in rendering
@export var name: String
@export
var description: String = "Sunt nisi id proident veniam ad laboris pariatur minim eu commodo aliquip."
@export var target_gamemode: GameModeType.Kind
@export var event_type: EventType = EventType.SEQUENTIAL

## If set, every participating player's bike is swapped to this for the duration of the event.
## Restored from lobby_players on exit back to free roam. Leave null for no override.
@export var forced_base_bike: BikeSkinDefinition = null
