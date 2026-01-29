class_name MenuManager extends Node

@export var menus: Control

enum MenuGameState {
    OutOfGame,
    InGame
}

var menu_game_state: MenuGameState = MenuGameState.OutOfGame
var state_machine: StateMachine
