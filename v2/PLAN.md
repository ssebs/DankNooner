# Tutorial Multiplayer Redesign — Design Spec

## Problem

`TutorialGameMode` tracks a single player's state (`_ctx.peer_id`). Multiple players share one `TutorialSteps` instance, so only one player's tricks/progress are monitored. No results screen exists — it auto-returns to free roam after 3 seconds.

## Goals

1. Host-only event start (non-host gets no popup)
2. All players enter tutorial together
3. Per-player independent progress tracking
4. Reusable results screen with timer countdown, then return to free roam

## Design

### 1. TutorialPlayerState (new resource)

Per-player state encapsulating all tutorial progress:

```
TutorialPlayerState (extends Resource)
├── tutorial_steps: TutorialSteps      # own instance per player
├── current_index: int                 # which step they're on
├── started: bool
├── completed: bool
├── start_time: float                  # Time.get_ticks_msec() when countdown ends
├── completion_time_ms: float          # filled when they finish all steps
```

Factory: `TutorialPlayerState.create(sequence: Array[TutorialSteps.Step]) -> TutorialPlayerState`

Each player gets a fresh `TutorialSteps` with independent `_wheelie_time`, `_stoppie_time`, etc.

Crash resets only that player's `tutorial_steps._wheelie_time` / `_stoppie_time`.

Active trick is read from `player.trick_controller` directly — not tracked in state.

### 2. GameModeEvent — Step Sequence Export

```gdscript
@export var tutorial_sequence: Array[TutorialSteps.Step]
```

Added to `GameModeEvent` resource. Wired per event circle in the editor. If empty, `TutorialGameMode` falls back to `TutorialSteps.THE_BASICS`.

Flow: `EventStartCircle` → `GamemodeStateContext.gamemode_event` → `TutorialGameMode.Enter()` reads `ctx.gamemode_event.tutorial_sequence`.

### 3. Host-Only Event Circle Restriction

In `GameModeEventConfirmHUD.on_player_entered_circle()` (server-side RPC): if the calling peer is not the host, skip calling `set_gamemode_hud_and_show_ui` back to them. No changes to `EventStartCircle`.

### 4. TutorialGameMode Rework

Server holds `var _player_states: Dictionary[int, TutorialPlayerState]`.

**Enter():**
- Build `_player_states`: for each peer_id in `lobby_manager.lobby_players`, create `TutorialPlayerState` with sequence from `ctx.gamemode_event.tutorial_sequence` (or `THE_BASICS`)
- Disable input for all, teleport to start marker, start 3s countdown
- When countdown ends: enable input, set `started = true` and `start_time` on all states

**Update():**
- Clean dispatch loop — `Update()` iterates `_player_states`, calls focused helpers:
  - `_update_player_tutorial(peer_id, state, delta)` — runs the current step check
  - `_advance_player_step(peer_id, state)` — moves to next step, RPCs HUD update
  - `_complete_player(peer_id, state)` — marks complete, records time, RPCs "waiting" message
  - `_check_all_complete()` — if all done, trigger results screen

**Step check changes:**
- `TutorialSteps` check callables drop `active_trick` param
- Read trick from `player.trick_controller` inside the callable

**No more trick signal connections** — `trick_started`/`trick_ended` connections removed entirely.

**Crash handler:**
- Reset crashed player's `tutorial_steps._wheelie_time` / `_stoppie_time` only
- Respawn at start marker (same as now)

### 5. ResultsMenuState (new, reusable)

Generic results screen for any gamemode.

**Data format:**
```gdscript
# ResultsData (Resource)
var title: String              # e.g. "Tutorial Complete", "Race Results"
var columns: Array[String]     # e.g. ["Username", "Time"]
var rows: Array[Dictionary]    # e.g. [{ "peer_id": 1, "Username": "P1", "Time": "12.3s" }]
```

Keys are freeform — races can pass `{ "position": 2, "best_lap": "1:23.4" }` later.

**UI:**
- Title label
- Player list (VBoxContainer or similar) showing each row's metadata
- Countdown timer label (e.g. 10s) visible and ticking down
- Sorted by gamemode (tutorial: by completion time)

**Flow:**
1. Server detects all complete → builds `ResultsData` sorted by `completion_time_ms` → RPCs to all peers
2. All peers: show `ResultsMenuState`, switch input to `IN_MENU`
3. Countdown timer ticks (shown to players)
4. Timer expires → server transitions everyone back to free roam

### 6. End-to-End Flow

1. Host enters event circle → server checks `is_server()`, shows confirm HUD to host only
2. Host confirms → `change_gamemode` RPC with `GamemodeStateContext` carrying `GameModeEvent`
3. All peers enter `TutorialGameMode` → server builds `_player_states`, disables input, teleports all, starts 3s countdown
4. Countdown ends → enable input, record `start_time`
5. Server `Update()` loop → per non-completed player, run step check, advance individually, RPC HUD updates per peer
6. Player crashes → reset that player's trick accumulators, respawn at start
7. Player finishes all steps → mark completed, record `completion_time_ms`, RPC "waiting for others"
8. All complete → server builds results data (sorted by time), RPCs to all
9. `ResultsMenuState` shown → title, player list with times, countdown timer
10. Timer expires → server transitions everyone back to free roam

## Files

**New:**
- `TutorialPlayerState` — per-player state resource
- `ResultsMenuState` + scene — reusable results screen
- `ResultsData` — data resource for results

**Modified:**
- `GameModeEvent` — add `tutorial_sequence` export
- `TutorialGameMode` — per-player state dict, loop all players, clean helpers
- `TutorialSteps` — drop `active_trick` param from check callables
- `GameModeEventConfirmHUD` — host-only filter in `on_player_entered_circle`

**Unchanged:**
- `EventStartCircle`, `GamemodeManager`, `FreeRoamGameMode`, `SpawnManager`

## Relevant File Paths

**Will be modified:**
- `managers/gamemodes/tutorial/tutorial_gamemode.gd` — per-player state loop
- `managers/gamemodes/tutorial/tutorial_steps.gd` — drop `active_trick` param from checks
- `managers/gamemodes/tutorial/tutorial_hud.gd` — per-peer RPC targets
- `managers/gamemodes/tutorial/tutorial_hud.tscn` — scene for tutorial HUD
- `managers/gamemodes/hud/game_mode_event_confirm_hud.gd` — host-only filter
- `resources/events/gamemode_event.gd` — add `tutorial_sequence` export

**Will be created:**
- `managers/gamemodes/tutorial/tutorial_player_state.gd` — per-player state resource
- `menus/results/results_menu_state.gd` — reusable results screen script
- `menus/results/results_menu_state.tscn` — results screen scene
- `resources/results_data.gd` — results data resource

**Reference (unchanged, but need to understand):**
- `managers/gamemodes/gamemode_manager.gd` — match state, gamemode transitions
- `managers/gamemodes/base/gamemode.gd` — base GameMode class
- `managers/gamemodes/free_roam/free_roam_gamemode.gd` — event circle signal wiring
- `managers/spawn_manager.gd` — spawn/respawn RPCs
- `managers/network/lobby_manager.gd` — lobby_players dict
- `managers/menu_manager.gd` — menu state management
- `menus/menu_state.gd` — base MenuState class
- `utils/state_machine/gamemode_state_context.gd` — carries GameModeEvent through transitions
- `utils/constants.gd` — global constants/enums
- `managers/gamemodes/hud/game_mode_event_confirm_hud.tscn` — confirm HUD scene

---

# Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign tutorial gamemode so each player has independent progress tracking, only the host can start events, and a reusable results screen shows completion data before returning to free roam.

**Architecture:** Per-player state resources owned by the server-side TutorialGameMode. Server loops all players in Update(), RPCs HUD updates per-peer. A generic ResultsHUD (Control) displays results with a countdown timer, reusable by any future gamemode.

**Tech Stack:** Godot 4.6, GDScript, netfox rollback, RPC multiplayer

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `managers/gamemodes/tutorial/tutorial_player_state.gd` | Per-player tutorial progress resource |
| Create | `resources/results_data.gd` | Generic results data container |
| Create | `menus/results/results_hud.gd` | Reusable results screen (Control) |
| Create | `menus/results/results_hud.tscn` | Results screen scene |
| Modify | `resources/events/gamemode_event.gd` | Add `tutorial_sequence` export |
| Modify | `managers/gamemodes/tutorial/tutorial_steps.gd` | Drop `active_trick` param from checks |
| Modify | `managers/gamemodes/hud/game_mode_event_confirm_hud.gd` | Host-only filter |
| Modify | `managers/gamemodes/tutorial/tutorial_hud.gd` | Add "waiting for others" RPC |
| Modify | `managers/gamemodes/tutorial/tutorial_gamemode.gd` | Per-player state loop rewrite |
| Modify | `player/controllers/trick_controller.gd` | Expose `current_trick` property |

---

### Task 1: Expose current_trick on TrickController

**Files:**
- Modify: `player/controllers/trick_controller.gd`

The tutorial step checks need to read the active trick from the player. `_current_trick` is private by convention. Add a public read-only property.

- [ ] **Step 1: Add public property**

In `player/controllers/trick_controller.gd`, rename `_current_trick` to `current_trick`:

```gdscript
var current_trick: Trick = Trick.NONE
```

Also update every reference to `_current_trick` in the file to `current_trick` (in `on_movement_rollback_tick`, `_detect_current_trick`, `do_reset`).

- [ ] **Step 2: Update external references**

Search for `_current_trick` across the codebase and update any external references to `current_trick`. (There should be none — only internal to trick_controller.gd.)

---

### Task 2: Create TutorialPlayerState Resource

**Files:**
- Create: `managers/gamemodes/tutorial/tutorial_player_state.gd`

- [ ] **Step 1: Write TutorialPlayerState**

```gdscript
class_name TutorialPlayerState extends RefCounted

var tutorial_steps: TutorialSteps
var current_index: int = 0
var started: bool = false
var completed: bool = false
var start_time: float = 0.0
var completion_time_ms: float = 0.0


static func create() -> TutorialPlayerState:
	var state := TutorialPlayerState.new()
	state.tutorial_steps = TutorialSteps.new()
	return state
```

Note: `TutorialSteps` already creates its `defs` dict in `_init()`, so each `TutorialPlayerState` gets an independent instance with its own `_wheelie_time`, `_stoppie_time`, etc. The step sequence itself is stored on `TutorialGameMode._sequence`, not per-player — all players run the same steps.

---

### Task 3: Add tutorial_sequence Export to GameModeEvent

**Files:**
- Modify: `resources/events/gamemode_event.gd`

- [ ] **Step 1: Add the export**

Add after the existing exports:

```gdscript
@export var tutorial_sequence: Array[TutorialSteps.Step]
```

Full file becomes:

```gdscript
@tool
class_name GameModeEvent extends Resource

## Will use localization in rendering
@export var name: String
@export
var description: String = "Sunt nisi id proident veniam ad laboris pariatur minim eu commodo aliquip."
@export var target_gamemode: GamemodeManager.TGameMode
@export var tutorial_sequence: Array[TutorialSteps.Step]
```

- [ ] **Step 2: Human — update existing .tres event resources**

In the Godot editor, open any existing `GameModeEvent` `.tres` files that target the tutorial gamemode and set their `tutorial_sequence` to the desired steps (e.g. `THE_BASICS` order: SHOW_HELP, PRESS_RT, REACH_SPEED, DO_WHEELIE, CHANGE_GEAR, DO_STOPPIE).

---

### Task 4: Drop active_trick Param from TutorialSteps Checks

**Files:**
- Modify: `managers/gamemodes/tutorial/tutorial_steps.gd`

- [ ] **Step 1: Update StepDef.check signature comment**

Change the comment on `check` in `StepDef`:

```gdscript
var check: Callable  # (player: PlayerEntity, delta: float) -> bool
```

- [ ] **Step 2: Update check_is_wheelie and check_is_stoppie helpers**

Change them to accept a `PlayerEntity` instead of a trick enum:

```gdscript
func check_is_wheelie(player: PlayerEntity) -> bool:
	return (
		player.trick_controller.current_trick
		in [TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD]
	)


func check_is_stoppie(player: PlayerEntity) -> bool:
	return player.trick_controller.current_trick == TrickController.Trick.STOPPIE
```

- [ ] **Step 3: Update all _check_ functions to 2-param signature**

Remove `active_trick` param from every check function. Functions that use tricks now call the updated helpers with `player`:

```gdscript
func _check_show_help(_player: PlayerEntity, _delta: float) -> bool:
	return _help_closed


func _check_press_rt(player: PlayerEntity, _delta: float) -> bool:
	return check_speed_above(player, 2.0)


func _check_reach_speed(player: PlayerEntity, _delta: float) -> bool:
	return check_speed_above(player, 30)


func _check_change_gear(player: PlayerEntity, _delta: float) -> bool:
	if _initial_gear == -1:
		_initial_gear = player.gearing_controller.current_gear
	return player.gearing_controller.current_gear != _initial_gear


func _check_wheelie(_player: PlayerEntity, delta: float) -> bool:
	if check_is_wheelie(_player):
		_wheelie_time += delta
		return _wheelie_time >= 3.0
	_wheelie_time = 0.0
	return false


func _check_stoppie(_player: PlayerEntity, delta: float) -> bool:
	if check_is_stoppie(_player):
		_stoppie_time += delta
		return _stoppie_time >= 1.0
	_stoppie_time = 0.0
	return false
```

---

### Task 5: Host-Only Filter in GameModeEventConfirmHUD

**Files:**
- Modify: `managers/gamemodes/hud/game_mode_event_confirm_hud.gd`

- [ ] **Step 1: Add host check in on_player_entered_circle**

In `on_player_entered_circle`, after the server check, add a host-only gate:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func on_player_entered_circle(peer_id: int, gamemode_name: String, gamemode_description: String):
	if !multiplayer.is_server():
		return

	# Only show event popup to the host
	if peer_id != 1:
		return

	set_gamemode_hud_and_show_ui.rpc_id(peer_id, gamemode_name, gamemode_description)
```

---

### Task 6: Create ResultsData Resource

**Files:**
- Create: `resources/results_data.gd`

- [ ] **Step 1: Write ResultsData**

```gdscript
class_name ResultsData extends RefCounted

var title: String
var columns: Array[String]
var rows: Array[Dictionary]


static func create(p_title: String, p_columns: Array[String], p_rows: Array[Dictionary]) -> ResultsData:
	var data := ResultsData.new()
	data.title = p_title
	data.columns = p_columns
	data.rows = p_rows
	return data


func to_dict() -> Dictionary:
	return {
		"title": title,
		"columns": columns,
		"rows": rows,
	}


static func from_dict(d: Dictionary) -> ResultsData:
	var data := ResultsData.new()
	data.title = d["title"]
	data.columns = Array(d["columns"], TYPE_STRING, "", null)
	data.rows = Array(d["rows"], TYPE_DICTIONARY, "", null)
	return data
```

Serialization via `to_dict()`/`from_dict()` is needed because RPC can't send custom Resources — only built-in types.

---

### Task 7: Create ResultsHUD

**Files:**
- Create: `menus/results/results_hud.gd`
- Create: `menus/results/results_hud.tscn`

- [ ] **Step 1: Write ResultsHUD script**

```gdscript
@tool
class_name ResultsHUD extends Control

@onready var title_label: Label = %TitleLabel
@onready var results_container: VBoxContainer = %ResultsContainer
@onready var countdown_label: Label = %CountdownLabel

var _countdown: float = -1.0


func _ready():
	hide()


func _process(delta: float):
	if _countdown <= 0.0:
		return
	_countdown -= delta
	countdown_label.text = "%d" % ceili(_countdown)
	if _countdown <= 0.0:
		_countdown = -1.0


@rpc("call_local", "reliable")
func rpc_show_results(results_dict: Dictionary, countdown_seconds: float):
	var data := ResultsData.from_dict(results_dict)
	title_label.text = data.title

	for child in results_container.get_children():
		child.queue_free()

	for row in data.rows:
		var row_label := Label.new()
		var parts: Array[String] = []
		for col in data.columns:
			parts.append(str(row.get(col, "")))
		row_label.text = "  ".join(parts)
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		results_container.add_child(row_label)

	_countdown = countdown_seconds
	countdown_label.text = "%d" % ceili(countdown_seconds)
	show()


@rpc("call_local", "reliable")
func rpc_hide():
	_countdown = -1.0
	hide()
```

- [ ] **Step 2: Create results_hud.tscn**

Create the scene file. Structure mirrors `tutorial_hud.tscn` — full-screen Control with centered panel:

```
ResultsHUD (Control) — script: results_hud.gd, full-screen anchors, mouse_filter=IGNORE
└── AspectRatioContainer — 16:9 ratio
    └── CenterContainer
        └── PanelContainer — styled panel (dark bg, blue border)
            └── VBoxContainer
                ├── TitleLabel (Label, unique name, Heading1)
                ├── ResultsContainer (VBoxContainer, unique name)
                └── CountdownLabel (Label, unique name, centered)
```

Human should create this scene in the Godot editor using the DankNooner theme, matching the style of `tutorial_hud.tscn`.

---

### Task 8: Add "Waiting" State to TutorialHUD

**Files:**
- Modify: `managers/gamemodes/tutorial/tutorial_hud.gd`

- [ ] **Step 1: Add rpc_show_waiting method**

Add after `rpc_show_complete`:

```gdscript
@rpc("call_local", "reliable")
func rpc_show_waiting():
	step_label.hide()
	objective_label.hide()
	hint_label.hide()
	complete_label.text = tr("TUT_WAITING_FOR_OTHERS")
	complete_label.show()
	self.show()
```

- [ ] **Step 2: Human — add localization key**

Add `TUT_WAITING_FOR_OTHERS` to `localization/localization.csv` with value like "Waiting for other players..."

---

### Task 9: Rewrite TutorialGameMode

**Files:**
- Modify: `managers/gamemodes/tutorial/tutorial_gamemode.gd`

This is the largest task. The full rewritten file:

- [ ] **Step 1: Replace the entire TutorialGameMode script**

```gdscript
@tool
class_name TutorialGameMode extends GameMode

@export var tutorial_hud: TutorialHUD
@export var results_hud: ResultsHUD
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager
@export var menu_manager: MenuManager
@export var help_menu_state: HelpMenuState

var _player_states: Dictionary[int, TutorialPlayerState] = {}
var _sequence: Array[TutorialSteps.Step] = []
var _respawn_delay: float = 3.0
var _countdown: float = -1.0
var _countdown_total: float = 3.0
var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GamemodeManager.TGameMode.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	_sequence = _get_sequence(state_context)
	_build_player_states()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	if multiplayer.is_server():
		_set_all_players_input_disabled(true)
		_teleport_players_to_start()
		_countdown = _countdown_total
		_rpc_show_countdown.rpc(ceili(_countdown))


func Update(delta: float):
	if !multiplayer.is_server():
		return

	if _update_countdown(delta):
		return

	if _update_results_countdown(delta):
		return

	for peer_id in _player_states:
		var state := _player_states[peer_id]
		if state.completed or !state.started:
			continue
		_update_player_tutorial(peer_id, state, delta)

	_check_all_complete()


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)

	if multiplayer.is_server():
		_set_all_players_input_disabled(false)
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_hide.rpc()
	_player_states.clear()


#region Setup helpers

func _get_sequence(state_context: StateContext) -> Array[TutorialSteps.Step]:
	if state_context is GamemodeStateContext:
		var ctx := state_context as GamemodeStateContext
		if ctx.gamemode_event and ctx.gamemode_event.tutorial_sequence.size() > 0:
			return ctx.gamemode_event.tutorial_sequence
	return TutorialSteps.THE_BASICS


func _build_player_states():
	_player_states.clear()
	for peer_id in lobby_manager.lobby_players:
		_player_states[peer_id] = TutorialPlayerState.create()


func _get_start_marker() -> Marker3D:
	return gamemode_manager.level_manager.current_level.get_node("%Tutorial01StartMarker")


func _teleport_players_to_start():
	var marker := _get_start_marker()
	for peer_id in lobby_manager.lobby_players:
		spawn_manager.respawn_player_at.rpc(peer_id, marker.global_position, marker.global_basis)

#endregion


#region Countdown phases

func _update_countdown(delta: float) -> bool:
	if _countdown <= 0.0:
		return false

	var prev_sec := ceili(_countdown)
	_countdown -= delta
	var curr_sec := ceili(_countdown)
	if curr_sec != prev_sec and curr_sec > 0:
		_rpc_show_countdown.rpc(curr_sec)
	if _countdown <= 0.0:
		_countdown = -1.0
		_on_countdown_finished()
	return true


func _on_countdown_finished():
	_set_all_players_input_disabled(false)
	var now := Time.get_ticks_msec() as float
	for peer_id in _player_states:
		var state := _player_states[peer_id]
		state.started = true
		state.start_time = now
	_start_step_for_all()


func _update_results_countdown(delta: float) -> bool:
	if _results_countdown <= 0.0:
		return false
	_results_countdown -= delta
	if _results_countdown <= 0.0:
		_results_countdown = -1.0
		_return_to_free_roam()
	return true

#endregion


#region Per-player tutorial logic

func _update_player_tutorial(peer_id: int, state: TutorialPlayerState, delta: float):
	# Player may not be spawned yet during late-join sync — skip is intentional
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	if player == null:
		return

	var step_def := state.tutorial_steps.defs[_sequence[state.current_index]]

	if step_def.get_progress.is_valid():
		tutorial_hud.rpc_update_progress.rpc_id(peer_id, step_def.get_progress.call())

	if step_def.check.call(player, delta):
		if step_def.on_exit.is_valid():
			step_def.on_exit.call()
		_advance_player_step(peer_id, state)


func _advance_player_step(peer_id: int, state: TutorialPlayerState):
	state.current_index += 1
	if state.current_index >= _sequence.size():
		_complete_player(peer_id, state)
	else:
		_start_step_for_peer(peer_id, state)


func _complete_player(peer_id: int, state: TutorialPlayerState):
	state.completed = true
	state.completion_time_ms = Time.get_ticks_msec() - state.start_time
	tutorial_hud.rpc_show_waiting.rpc_id(peer_id)


func _start_step_for_all():
	for peer_id in _player_states:
		_start_step_for_peer(peer_id, _player_states[peer_id])


func _start_step_for_peer(peer_id: int, state: TutorialPlayerState):
	var step_enum := _sequence[state.current_index]
	var step_def := state.tutorial_steps.defs[step_enum]
	if step_def.on_enter.is_valid():
		step_def.on_enter.call()
	tutorial_hud.rpc_show_step.rpc_id(
		peer_id, state.current_index, _sequence.size(), step_def.objective_text, step_def.hint_text
	)
	if step_enum == TutorialSteps.Step.SHOW_HELP:
		_rpc_show_help_menu.rpc_id(peer_id)

#endregion


#region All-complete check & results

func _check_all_complete():
	if _results_countdown > 0.0:
		return
	for peer_id in _player_states:
		if !_player_states[peer_id].completed:
			return
	_show_results()


func _show_results():
	var rows: Array[Dictionary] = []
	for peer_id in _player_states:
		var state := _player_states[peer_id]
		var username: String = lobby_manager.lobby_players[peer_id].username
		var time_sec := state.completion_time_ms / 1000.0
		rows.append({
			"Username": username,
			"Time": "%.1fs" % time_sec,
			"_sort_key": state.completion_time_ms,
		})
	rows.sort_custom(func(a, b): return a["_sort_key"] < b["_sort_key"])

	var data := ResultsData.create(
		tr("TUT_COMPLETE"), ["Username", "Time"], rows
	)
	_results_countdown = _results_countdown_total
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_show_results.rpc(data.to_dict(), _results_countdown_total)

#endregion


#region Help menu (per-player)

@rpc("call_local", "reliable")
func _rpc_show_help_menu():
	var player := spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id())
	player.input_controller.input_disabled = true

	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	menu_manager.enable_input_and_processing()
	help_menu_state.ui.show()
	help_menu_state._show_controls_for_current_device()

	help_menu_state.close_help_btn.pressed.connect(_on_tutorial_help_closed, CONNECT_ONE_SHOT)
	input_state_manager.unpause_requested.connect(_on_tutorial_help_closed, CONNECT_ONE_SHOT)


func _on_tutorial_help_closed():
	if help_menu_state.close_help_btn.pressed.is_connected(_on_tutorial_help_closed):
		help_menu_state.close_help_btn.pressed.disconnect(_on_tutorial_help_closed)
	if input_state_manager.unpause_requested.is_connected(_on_tutorial_help_closed):
		input_state_manager.unpause_requested.disconnect(_on_tutorial_help_closed)

	help_menu_state.ui.hide()
	menu_manager.disable_input_and_processing()
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME

	var player := spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id())
	player.input_controller.input_disabled = false

	_rpc_help_menu_closed.rpc_id(1, multiplayer.get_unique_id())


@rpc("call_local", "any_peer", "reliable")
func _rpc_help_menu_closed(peer_id: int):
	if !_player_states.has(peer_id):
		return
	_player_states[peer_id].tutorial_steps._help_closed = true

#endregion


#region Player event handlers

func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return

	if _player_states.has(peer_id):
		var state := _player_states[peer_id]
		state.tutorial_steps._wheelie_time = 0.0
		state.tutorial_steps._stoppie_time = 0.0

	var marker := _get_start_marker()
	get_tree().create_timer(_respawn_delay).timeout.connect(
		func():
			spawn_manager.respawn_player_at.rpc(
				peer_id, marker.global_position, marker.global_basis
			),
		CONNECT_ONE_SHOT
	)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)

	_player_states.erase(peer_id)

	# If the only remaining players are all complete, show results
	if multiplayer.is_server() and _player_states.size() > 0:
		_check_all_complete()

#endregion


#region Navigation

func _return_to_free_roam():
	gamemode_manager._rpc_transition_gamemode.rpc(
		GamemodeManager.TGameMode.FREE_FROAM, multiplayer.get_unique_id()
	)

#endregion


#region Input helpers

func _set_all_players_input_disabled(disabled: bool):
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet — skip is intentional
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null:
			continue
		player.input_controller.input_disabled = disabled
		if disabled:
			player.input_controller.nfx_throttle = 0.0
			player.input_controller.nfx_front_brake = 0.0
			player.input_controller.nfx_rear_brake = 0.0
			player.input_controller.nfx_steer = 0.0
			player.input_controller.nfx_lean = 0.0

#endregion


@rpc("call_local", "reliable")
func _rpc_show_countdown(seconds: int):
	tutorial_hud.rpc_show_countdown(seconds)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if tutorial_hud == null:
		issues.append("tutorial_hud must not be empty")
	if results_hud == null:
		issues.append("results_hud must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")
	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if help_menu_state == null:
		issues.append("help_menu_state must not be empty")

	return issues
```

---

### Task 10: Scene Wiring (Human)

These steps must be done by the human in the Godot editor.

- [ ] **Step 1: Create `menus/results/results_hud.tscn`**

Create the scene as described in Task 7 Step 2. Root node is `ResultsHUD` (Control), attach `results_hud.gd`. Add `%TitleLabel`, `%ResultsContainer` (VBoxContainer), `%CountdownLabel` with unique names. Use the DankNooner theme and match the styling of `tutorial_hud.tscn`.

- [ ] **Step 2: Add ResultsHUD to the scene tree**

In `main_game.tscn`, add a `ResultsHUD` instance as a child of the `GamemodeManager` node (or wherever `TutorialHUD` lives — it should be at the same level).

- [ ] **Step 3: Wire the @export on TutorialGameMode**

In the inspector, set the new `results_hud` export on `TutorialGameMode` to point to the `ResultsHUD` instance.

- [ ] **Step 4: Update tutorial GameModeEvent .tres resources**

Open each tutorial `GameModeEvent` `.tres` file in the inspector and populate the `tutorial_sequence` array with the desired step order.

- [ ] **Step 5: Add localization keys**

In `localization/localization.csv`, add:
- `TUT_WAITING_FOR_OTHERS` → "Waiting for other players..."
- `TUT_COMPLETE` should already exist; verify it does

- [ ] **Step 6: Test the full flow**

1. Host a lobby with 2 players
2. Verify non-host cannot see event circle popup
3. Host starts tutorial event
4. Both players get countdown, then independent step tracking
5. First player to finish sees "Waiting for others..."
6. Second player finishes → results screen shows for both with completion times
7. 10s countdown expires → both return to free roam
8. Test crash during tutorial resets only crashed player's progress
9. Test player disconnect during tutorial (remaining players should still complete)
