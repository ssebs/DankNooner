@tool
## Drop the held item (double honk) instead of using it. Solo, like the rest of the tutorial: the
## signal is connected for this step only.
class_name DropItemTask extends GameModeTask

@export var objective_key: String = "TUT_DROP_ITEM"

## Injected by TutorialGameMode.
var item_manager: ItemManager


func on_enter(_player: PlayerEntity, _state: Dictionary) -> void:
	item_manager.item_dropped.connect(_on_item_dropped)


func check(_player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	return state.get("dropped", false)


func on_exit(_player: PlayerEntity, _state: Dictionary) -> void:
	item_manager.item_dropped.disconnect(_on_item_dropped)


func get_objective_text() -> String:
	return tr(objective_key)


func _on_item_dropped(peer_id: int) -> void:
	runner.mark_state(peer_id, "dropped", true)
