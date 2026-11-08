@tool
## Pauses the game and plays its Tour on the active peer's screen until they close it. A pause, not
## a freeze, so the rider keeps their speed for the step after (e.g. braking from speed). Solo only:
## the pause stops every peer, which the tutorial's solo session makes safe.
##
## Tree: ShowTourTask > Tour > TourStep (one or more). Its check task is the next sibling.
## Tutorial tours always show, even when already done. tour_manager lives in main_game.tscn while
## this task lives in a level scene, so TutorialGameMode injects it after instancing.
class_name ShowTourTask extends GameModeTask

var tour_manager: TourManager


func on_enter(player: PlayerEntity, state: Dictionary) -> void:
	state["closed"] = false
	# One more tick first, so a TeleportTask right before this has landed the rider.
	await NetworkTime.after_tick_loop
	get_tree().paused = true
	_rpc_show_tour.rpc_id(int(player.name))


func check(_player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	return state.get("closed", false)


## Null only in the editor, for the warning below.
func get_tour() -> Tour:
	for child in get_children():
		if child is Tour:
			return child
	return null


@rpc("call_local", "reliable")
func _rpc_show_tour():
	tour_manager.tour_closed.connect(_on_tour_closed, CONNECT_ONE_SHOT)
	tour_manager.play(get_tour())


func _on_tour_closed(_tour: Tour, _skipped: bool):
	request_tour_closed.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_tour_closed():
	get_tree().paused = false
	runner.mark_state(multiplayer.get_remote_sender_id(), "closed", true)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if get_tour() == null:
		issues.append("Add a Tour child")
	return issues
