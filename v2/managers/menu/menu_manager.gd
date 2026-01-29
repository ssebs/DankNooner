class_name MenuManager extends Node

@export var menus: Control
@export var state_machine: StateMachine

enum MenuGameState {
    OutOfGame,
    InGame
}

var menu_game_state: MenuGameState = MenuGameState.OutOfGame

func _ready():
    hide_all_menus(state_machine.current_state)

## Will hide all menus except `except_this_one`, if exists. 
func hide_all_menus(except_this_one: State):
    for child in menus.get_children():
        child.hide()
        
        # HACK - not sure if this works.
        if child == except_this_one:
            child.show()
