@tool
class_name MenuManager extends Node

@export var menus: Control
@export var state_machine: StateMachine

enum MenuGameState {
    OutOfGame,
    InGame
}

var menu_game_state: MenuGameState = MenuGameState.OutOfGame

func _ready():
    hide_all_menus()
    
    if Engine.is_editor_hint():
        return
    
    state_machine.state_transitioned.connect(_on_state_transitioned)

func _on_state_transitioned(_new_state: State):
    pass

## Will hide all menus
func hide_all_menus():
    for child in menus.get_children():
        if !child is BaseMenu:
            continue
        child.hide()
