@tool
## All player objects should be defined from this
class_name PlayerDefinition extends Resource

@export var ui_icon: Texture
@export var username: String
@export var money: int
@export var xp: int

@export var character_skin: CharacterSkinDefinition
@export var bike_skin: BikeSkinDefinition
