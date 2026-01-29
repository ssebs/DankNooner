class_name State extends Node

signal transitioned(new_state: State)

## The name of this state
var state_name: String:
    set(val):
        state_name = UtilsStrings.clean_for_node_name(val)
        name = state_name
var state_machine_ref: StateMachine

func _init():
    if name != state_name:
        state_name = name
    else:
        printerr("name already set in state init")

#region lifecycle
func Enter():
    pass

func Update(_delta: float):
    pass

func Physics_Update(_delta: float):
    pass

func Exit():
    pass
#endregion

func _to_string() -> String:
    return state_name

func _hide_lint_warning():
    transitioned.emit(self , null)
