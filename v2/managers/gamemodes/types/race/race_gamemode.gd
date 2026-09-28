@tool
## Checkpoint race — every race event runs here. race_type fixes the standing (RACE: race position,
## STUNT_RACE: summed component scores, TIME_ATTACK: best lap); everything beyond the shared race loop lives in the
## RaceComponent children wired below. main_game has one instance per race_type.
class_name RaceGameMode extends RunnerGameMode

enum RaceType { RACE, STUNT_RACE, TIME_ATTACK }

@export var race_type: RaceType = RaceType.RACE:
	set(value):
		race_type = value
		update_configuration_warnings()
@export var results_hud: ResultsHUDState
@export var input_state_manager: InputStateManager
@export var riding_hud_state: RidingHUDState
## When true, finishing the race teleports everyone back to the grid; otherwise they stay
## where they finished and only the results HUD closes.
@export var teleport_to_start_on_finish: bool = false

@export_group("Components")
@export var traffic: TrafficComponent
@export var npc_racers: NPCRacersComponent
@export var pickups: PickupsComponent
@export var style_scoring: StyleScoringComponent
@export var finish_bonus: FinishBonusComponent
@export var challenges: ChallengesComponent
@export var time_attack: TimeAttackComponent
@export var leaderboard: LeaderboardComponent

const RESULTS_REFRESH_SECS: float = 1.0

## Components each race_type needs; the rest are optional.
const REQUIRED_COMPONENTS: Dictionary[RaceType, Array] = {
	RaceType.RACE: ["leaderboard"],
	RaceType.STUNT_RACE: ["style_scoring", "finish_bonus", "challenges", "pickups", "leaderboard"],
	RaceType.TIME_ATTACK: ["pickups", "time_attack", "leaderboard"],
}

## Server only — the event's RaceTask, the single source of race position and finish times.
var race_task: RaceTask
var _components: Array[RaceComponent] = []
var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0
var _results_refresh_accum: float = 0.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	DebugUtils.DebugMsg("Race Mode: %s" % RaceType.keys()[race_type])

	super(state_context)
	results_hud.skip_pressed.connect(_on_results_skip_pressed)
	results_hud.restart_pressed.connect(_on_results_restart_pressed)
	results_hud.retry_pressed.connect(_on_results_retry_pressed)

	# Hook order: traffic before NPCs (the route graph must exist before riders circulate),
	# scoring before the leaderboard reads it.
	_components.assign(
		[
			traffic, npc_racers, pickups, style_scoring, finish_bonus, challenges, time_attack,
			leaderboard
		]
		.filter(func(c): return c != null)
	)

	if multiplayer.is_server():
		race_task = _event.find_children("*", "RaceTask", true, false)[0]
		_race_start()
		_start_next_runner()
	elif traffic != null:
		traffic.client_enter()


func Update(delta: float):
	if !multiplayer.is_server():
		return
	_push_checkpoint_markers()
	if _update_results_countdown(delta):
		return
	if _active_runner != null:
		for component in _components:
			component.tick(delta)
	super(delta)


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	results_hud.skip_pressed.disconnect(_on_results_skip_pressed)
	results_hud.restart_pressed.disconnect(_on_results_restart_pressed)
	results_hud.retry_pressed.disconnect(_on_results_retry_pressed)

	if multiplayer.is_server():
		_race_end()
		_clear_checkpoint_markers()
		race_task = null
	elif traffic != null:
		traffic.client_exit()

	if results_hud.ui.visible:
		input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	results_hud.hide_ui()
	super(state_context)
	_components = []


func get_definition() -> GameModeEventDefinition:
	return _event.definition


func get_route() -> EventRoute:
	return _event.route


## A human's STUNT_RACE standing: every component's score summed.
func score(peer_id: int) -> float:
	var total := 0.0
	for component in _components:
		total += component.score(peer_id)
	return total


func get_components() -> Array[RaceComponent]:
	return _components


func _race_start():
	for component in _components:
		component.race_start()


func _race_end():
	for component in _components:
		component.race_end()


#region Checkpoint markers (server only)


## Push each human's next checkpoint to their own minimap (green marker).
## get_target_checkpoint returns null pre-race/finished — that clears it.
func _push_checkpoint_markers():
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null:
			continue
		var pos := Vector3.ZERO
		var has_target := false
		if race_task.has_racer(peer_id):
			var ckpt := race_task.get_target_checkpoint(peer_id)
			if ckpt != null:
				pos = ckpt.global_position
				has_target = true
		riding_hud_state.push_checkpoint_marker(peer_id, pos, has_target)


func _clear_checkpoint_markers():
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null:
			continue
		riding_hud_state.push_checkpoint_marker(peer_id, Vector3.ZERO, false)


#endregion

#region Results


func _update_results_countdown(delta: float) -> bool:
	if _results_countdown <= 0.0:
		return false
	_results_countdown -= delta
	_results_refresh_accum -= delta
	# NPCs keep racing through the countdown — refresh so a late finisher gets its time.
	if _results_refresh_accum <= 0.0:
		_results_refresh_accum = RESULTS_REFRESH_SECS
		results_hud.rpc_update_rows.rpc(leaderboard.build_results().to_dict())
	if _results_countdown <= 0.0:
		_results_countdown = -1.0
		_return_to_free_roam()
	return true


#override
func _on_last_runner_completed(_runner: TaskRunner):
	_results_countdown = _results_countdown_total
	_results_refresh_accum = RESULTS_REFRESH_SECS
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_show_results.rpc(leaderboard.build_results().to_dict(), _results_countdown_total)


func _on_results_skip_pressed():
	if !multiplayer.is_server():
		return
	_results_countdown = -1.0
	_return_to_free_roam()


func _on_results_restart_pressed():
	if !multiplayer.is_server():
		return
	_results_countdown = -1.0
	results_hud.rpc_hide.rpc()
	# Already stopped (results show only after all_completed), unless restart races the countdown.
	_stop_active_runner()
	_active_runner_index = -1
	_inject_runner_deps()
	_race_end()
	_race_start()
	_start_next_runner()


## Any peer: only time attack's run-finished prompt shows the retry button.
func _on_results_retry_pressed():
	time_attack.request_retry.rpc_id(1)


#endregion


#override
func _on_runner_player_completed(peer_id: int):
	# Only the last runner's completion is crossing the race's finish line.
	if _is_last_runner():
		for component in _components:
			component.racer_finished(peer_id)


#override
func _on_player_latejoined(peer_id: int):
	super(peer_id)
	if npc_racers != null:
		npc_racers.sync_to_peer(peer_id)


#override
func _return_to_free_roam():
	gamemode_manager.change_gamemode(
		GameModeType.Kind.FREE_ROAM, multiplayer.get_unique_id(), ^"",
		not teleport_to_start_on_finish
	)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if results_hud == null:
		issues.append("results_hud must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")
	for component_name: String in REQUIRED_COMPONENTS[race_type]:
		if get(component_name) == null:
			issues.append(
				"%s must not be empty for %s" % [component_name, RaceType.keys()[race_type]]
			)
	return issues
