# Plan: Gamemode System + Tutorial Gamemode

## Context

The game currently hard-codes FreeRoam as the only gamemode. The event circle submit button is stubbed. We need:
1. **Dynamic gamemode transitions** — event circles trigger whole-lobby gamemode changes
2. **Tutorial gamemode** — guided objectives for a specific player, steps defined via enums + callables in a single script

---

## Step 1: GamemodeStateContext

**New file**: `utils/state_machine/gamemode_state_context.gd`

Extends `StateContext`:
- `gamemode_event: GameModeEvent`
- `peer_id: int` — the player who triggered the transition

## Step 2: GameModeEvent — add target gamemode

**Modify**: `resources/events/gamemode_event.gd`

Add `@export var target_gamemode: GamemodeManager.TGameMode`

## Step 3: Make GamemodeManager dynamic

**Modify**: `managers/gamemodes/gamemode_manager.gd`

- `start_game()` — add `gamemode: TGameMode = TGameMode.FREE_FROAM` param, use `_gamemode_map[gamemode]`
- New RPC `change_gamemode(gamemode_enum: int, peer_id: int)`:
  - Server receives, builds `GamemodeStateContext` (with peer_id)
  - Broadcasts transition via `call_local` RPC so state machine transitions on all peers
  - Updates `current_game_mode`
- Update late-joiner sync to include current gamemode

## Step 4: Wire up FreeRoamGameMode event submission

**Modify**: `managers/gamemodes/free_roam/free_roam_gamemode.gd`

- Add `var _pending_event: GameModeEvent`
- `_on_event_circle_entered()`: store `gamemode_event` in `_pending_event`
- `_on_game_mode_event_confirm_hud_submitted(peer_id)`: call `gamemode_manager.change_gamemode.rpc_id(1, _pending_event.target_gamemode, peer_id)`

## Step 5: Tutorial steps — enums + callables, common checks

**New file**: `managers/gamemodes/tutorial/tutorial_steps.gd`

```gdscript
class_name TutorialSteps extends RefCounted

## Every possible tutorial step
enum Step {
    PRESS_RT,
    REACH_SPEED,
    DO_WHEELIE,
    DO_STOPPIE,
}

## Inner class — one step definition
class StepDef:
    var step: Step
    var objective_text: String   # localization key
    var hint_text: String        # localization key
    var check: Callable          # (player: PlayerEntity, delta: float) -> bool
    var on_enter: Callable       # optional setup
    var on_exit: Callable        # optional cleanup

## Step registry, keyed by enum
var defs: Dictionary[Step, StepDef] = {}

## --- Duration tracking for common checks ---
var _wheelie_time: float = 0.0
var _stoppie_time: float = 0.0

func _init():
    _register_all()

func _register_all():
    defs[Step.PRESS_RT] = _make(Step.PRESS_RT, "TUT_PRESS_RT", "TUT_HINT_PRESS_RT", _check_press_rt)
    defs[Step.REACH_SPEED] = _make(Step.REACH_SPEED, "TUT_REACH_SPEED", "TUT_HINT_REACH_SPEED", _check_reach_speed)
    defs[Step.DO_WHEELIE] = _make(Step.DO_WHEELIE, "TUT_DO_WHEELIE", "TUT_HINT_DO_WHEELIE", _check_wheelie, _reset_wheelie)
    defs[Step.DO_STOPPIE] = _make(Step.DO_STOPPIE, "TUT_DO_STOPPIE", "TUT_HINT_DO_STOPPIE", _check_stoppie, _reset_stoppie)

func _make(s, obj, hint, check, on_enter = Callable(), on_exit = Callable()) -> StepDef:
    var d = StepDef.new()
    d.step = s; d.objective_text = obj; d.hint_text = hint
    d.check = check; d.on_enter = on_enter; d.on_exit = on_exit
    return d

## ========== COMMON REUSABLE CHECKS ==========
## These can be called by any tutorial/gamemode that needs them

## Returns true if player speed > threshold (m/s)
func check_speed_above(player: PlayerEntity, threshold: float) -> bool:
    return player.movement_controller.speed > threshold

## Returns true if player speed < threshold
func check_speed_below(player: PlayerEntity, threshold: float) -> bool:
    return player.movement_controller.speed < threshold

## Returns true if player is doing a wheelie (sitting or mod)
func check_is_wheelie(player: PlayerEntity) -> bool:
    return player.trick_controller._current_trick in [
        TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD
    ]

## Returns true if player is doing a stoppie
func check_is_stoppie(player: PlayerEntity) -> bool:
    return player.trick_controller._current_trick == TrickController.Trick.STOPPIE

## ========== STEP CHECK FUNCTIONS ==========
## Each takes (player: PlayerEntity, delta: float) -> bool
## Only checks the specific peer's player, NOT all players

func _check_press_rt(player: PlayerEntity, _delta: float) -> bool:
    return check_speed_above(player, 2.0)

func _check_reach_speed(player: PlayerEntity, _delta: float) -> bool:
    return check_speed_above(player, 8.0)  # ~30 km/h

func _check_wheelie(player: PlayerEntity, delta: float) -> bool:
    if check_is_wheelie(player):
        _wheelie_time += delta
        return _wheelie_time >= 3.0
    _wheelie_time = 0.0
    return false

func _check_stoppie(player: PlayerEntity, delta: float) -> bool:
    if check_is_stoppie(player):
        _stoppie_time += delta
        return _stoppie_time >= 1.0
    _stoppie_time = 0.0
    return false

func _reset_wheelie(): _wheelie_time = 0.0
func _reset_stoppie(): _stoppie_time = 0.0

## ========== TUTORIAL SEQUENCES ==========
## Each tutorial selects steps in order

const THE_BASICS: Array[Step] = [Step.PRESS_RT, Step.REACH_SPEED, Step.DO_WHEELIE, Step.DO_STOPPIE]
```

## Step 6: TutorialHUD

**New file**: `managers/gamemodes/hud/tutorial_hud.gd` + `.tscn`

Shows:
- Step counter: "Step 1 / 4"
- Objective text (translated)
- Hint text (translated, smaller)
- Completion message

RPCs (call_local, reliable):
- `rpc_show_step(step_index: int, total: int, objective_key: String, hint_key: String)`
- `rpc_show_complete()`
- `rpc_hide()`

## Step 7: TutorialGameMode

**Modify**: `managers/gamemodes/tutorial/tutorial_gamemode.gd`

```gdscript
class_name TutorialGameMode extends GameMode

@export var tutorial_hud: TutorialHUD
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager

var _steps_lib: TutorialSteps
var _current_sequence: Array[TutorialSteps.Step] = []
var _current_index: int = 0
var _target_peer_id: int = -1  # the player doing the tutorial
var _respawn_delay: float = 3.0
```

**Enter(state_context: GamemodeStateContext)**:
- `gamemode_manager.current_game_mode = TUTORIAL`
- `_target_peer_id = state_context.peer_id`
- Connect signals (crashed, disconnected, latejoined)
- `_steps_lib = TutorialSteps.new()`
- `_current_sequence = TutorialSteps.THE_BASICS`
- `_current_index = 0`
- Spawn all players
- Call first step's `on_enter`, show on HUD

**Update(delta)** (server only):
- Get current StepDef from `_steps_lib.defs[_current_sequence[_current_index]]`
- Get the target player: `spawn_manager._get_player_by_peer_id(_target_peer_id)`
- Call `step.check.call(player, delta)`
- If true → call `step.on_exit` if valid, advance `_current_index`, call next `on_enter`, update HUD
- If `_current_index >= _current_sequence.size()` → complete, show HUD, delay, transition back to FreeRoam

**Exit(state_context)**:
- Disconnect signals, hide HUD

Crash/late-join/disconnect: same pattern as FreeRoamGameMode.

---

## Files Summary

| Action | File |
|--------|------|
| NEW | `utils/state_machine/gamemode_state_context.gd` |
| NEW | `managers/gamemodes/tutorial/tutorial_steps.gd` — enums, step defs, common checks, sequences |
| NEW | `managers/gamemodes/hud/tutorial_hud.gd` + `.tscn` |
| MODIFY | `resources/events/gamemode_event.gd` — add `target_gamemode` |
| MODIFY | `managers/gamemodes/gamemode_manager.gd` — dynamic `start_game`, add `change_gamemode` RPC |
| MODIFY | `managers/gamemodes/free_roam/free_roam_gamemode.gd` — wire submit → transition |
| MODIFY | `managers/gamemodes/tutorial/tutorial_gamemode.gd` — full implementation |
| MODIFY | `localization/localization.csv` — tutorial strings |

## Verification

1. Start game → FreeRoam → ride to tutorial event circle → Submit
2. All players transition to TutorialGameMode, tracking the submitting peer
3. HUD shows "Step 1/4: Press RT to accelerate" — checks only that player
4. Complete each step → HUD advances
5. After final step → "Tutorial Complete!" → back to FreeRoam
6. Crash during tutorial → respawn, step progress preserved
7. Late-joiner → syncs into current gamemode
