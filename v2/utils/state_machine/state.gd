## The name of this state is "name", so be sure to name the node after the class_name!
class_name State extends Node

signal transitioned(new_state: State)

var state_machine_ref: StateMachine

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
    return name

func _hide_lint_warning():
    transitioned.emit(self , null)
