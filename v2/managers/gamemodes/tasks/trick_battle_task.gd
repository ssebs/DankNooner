@tool
## The battle itself: free riding that never completes. TrickBattleGameMode owns the clock and the
## scoring; this only gives the event pane its objective.
class_name TrickBattleTask extends GameModeTask

@export var objective_key: String = "TRICK_BATTLE_OBJECTIVE"


func get_objective_text() -> String:
	return tr(objective_key)
