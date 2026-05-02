# PLAN — Tutorial × GameModeObject (v2: Objective resources + StartCircle-as-course)

## Status

Designed. Ready to implement.

## What changes vs. v1

v1 introduced `GameModeObject`, `TutorialLesson`, `TutorialCourse`, and a group-lookup that matched courses to events by resource identity. Working but ugly:

- Group-walk + resource-match was duck typing.
- `TutorialLesson.step` was a tutorial-specific enum into a global dispatch table (`TutorialSteps.defs`). Not reusable for race / future modes.
- `TutorialCourse` was a thin organizational wrapper redundant with the start circle.

v2 collapses all of that:

1. **Objective resources** replace `TutorialSteps.Step`. Each objective is a small `Resource` subclass with `check / on_enter / on_exit / get_progress`. Reusable across gamemodes.
2. **EventStartCircle becomes the course root.** Lessons + checkpoints + start marker live as children. Discovered via `get_children()` + type filter. No `TutorialCourse` node.
3. **Explicit wiring through context.** `EventStartCircle` reference rides through `GamemodeStateContext`. No group lookup.
4. **Per-player state lives in the gamemode.** A `Dictionary` per player for the current lesson; passed into `objective.check(...)`. Cleared on advance + crash.

## Architecture

### Objective (Resource, generic)

`levels/components/objective.gd`:

```gdscript
class_name Objective extends Resource

# `state` is a per-player Dictionary owned by the gamemode.
# Mutate freely. Cleared on lesson advance / crash.
func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool: return false
func on_enter(_player: PlayerEntity, _state: Dictionary) -> void: pass
func on_exit(_player: PlayerEntity, _state: Dictionary) -> void: pass
func get_progress(_state: Dictionary) -> String: return ""
func get_objective_text() -> String: return ""
func get_hint_text() -> String: return ""
```

Tutorial-flavored subclasses (`managers/gamemodes/tutorial/objectives/`):

| File | Replaces enum | Notes |
| ---- | ------------- | ----- |
| `wheelie_objective.gd` | `DO_WHEELIE` | `@export duration: float = 3.0` |
| `stoppie_objective.gd` | `DO_STOPPIE` | `@export duration: float = 1.0` |
| `speed_above_objective.gd` | `REACH_SPEED`, `PRESS_RT` | `@export min_speed: float`, `@export objective_key/hint_key` for text reuse |
| `change_gear_objective.gd` | `CHANGE_GEAR` | tracks initial gear in state |
| `close_help_objective.gd` | `SHOW_HELP` | `on_enter` triggers help menu via signal; `check` returns `state["closed"]` |

Future race objective (`managers/gamemodes/race/objectives/`): `pass_through_objective.gd` — `check` always returns true. Lesson uses `eval_when=ON_ENTER` + a `CheckpointMarker`. The trigger fires once → predicate evaluates once → done.

### GameModeLesson (Node, generic)

`levels/components/game_mode_lesson.gd`:

```gdscript
class_name GameModeLesson extends Node

enum EvalWhen { ALWAYS, ON_ENTER, WHILE_INSIDE }

@export var objective: Objective
@export var eval_when: EvalWhen = EvalWhen.ALWAYS
@export var trigger: GameModeObject  # required for ON_ENTER / WHILE_INSIDE
```

Replaces `TutorialLesson`. No more `step` enum or `trigger_objects` array — single objective + single trigger.

### EventStartCircle (course root)

`levels/components/event_start_circle.gd` gains:

```gdscript
@export var start_marker: Marker3D    # where players teleport to begin
# (children of this node) → lessons in order + GameModeObject props
```

Helper:

```gdscript
func get_lessons() -> Array[GameModeLesson]:
    var out: Array[GameModeLesson] = []
    for c in get_children():
        if c is GameModeLesson: out.append(c)
    return out
```

Signal widens to also pass the source circle:

```gdscript
signal entered_event_circle(peer_id: int, event_start_circle: EventStartCircle)
signal exited_event_circle(peer_id: int, event_start_circle: EventStartCircle)
```

Consumers pull `.gamemode_event` off the circle. (Smaller signal, more info — `gamemode_event` is one field of many we may need later.)

### Context plumbing

`utils/state_machine/gamemode_state_context.gd`:

```gdscript
var gamemode_event: GameModeEvent
var event_start_circle: EventStartCircle  # NEW — null for non-event entry
var peer_id: int = -1
```

`gamemode_manager.gd`:

```gdscript
var pending_event_start_circle: EventStartCircle  # NEW
# in _rpc_transition_gamemode: copy + clear, same as pending_gamemode_event
```

`free_roam_gamemode.gd`:

- `_on_event_circle_entered` stores `_ctx.event_start_circle = source_circle` (and `gamemode_event = source_circle.gamemode_event`).
- `_on_game_mode_event_confirm_hud_submitted` sets `gamemode_manager.pending_event_start_circle = _ctx.event_start_circle` alongside the existing `pending_gamemode_event`.

### TutorialGameMode

- Drops `_course`, `_find_course_for_event()`, `TutorialCourses` group.
- New: `_start_circle: EventStartCircle` (from ctx), `_lessons: Array[GameModeLesson]` (from `_start_circle.get_lessons()`).
- `_get_start_marker()` returns `_start_circle.start_marker`. (Falls back to legacy `%Tutorial01StartMarker` lookup only if start_circle is null — i.e. legacy code path.)
- `_update_player_tutorial`: pulls current lesson by index, calls `lesson.objective.check(player, delta, state.lesson_state)`. HUD text from `objective.get_objective_text/get_hint_text`. Progress from `objective.get_progress(state.lesson_state)`.
- `_advance_player_step`: clears `state.lesson_state` (was: `prop_event_fired` / `inside_zone` flags).
- `_should_eval_predicate`: same logic but based on `lesson.eval_when`.
- Wire signals: walk every unique `lesson.trigger` (filtered to non-null), connect entered/exited.
- `_on_player_crashed`: clear `state.lesson_state` (single cleanup, no per-mechanic timer fields).

### TutorialPlayerState

```gdscript
class_name TutorialPlayerState extends RefCounted

var current_index: int = 0
var started: bool = false
var completed: bool = false
var start_time: float = 0.0
var completion_time_ms: float = 0.0

# Per-lesson scratchpad. Cleared on advance + on crash.
# Keys/values owned by whichever Objective is running.
var lesson_state: Dictionary = {}

# Bookkeeping for the lesson trigger gating
var prop_event_fired: bool = false
var inside_zone: bool = false
```

`TutorialSteps` and the `tutorial_steps` field on the state are deleted. The `_help_closed` flag moves into the close-help objective's `state["closed"]`.

### Help menu integration

The old SHOW_HELP path called `_rpc_show_help_menu` from `_start_step_for_peer` based on enum match. New: `CloseHelpObjective.on_enter(player, state)` triggers the help open via a signal that the gamemode listens to (or simpler — the gamemode checks `objective is CloseHelpObjective` in `_start_step_for_peer` and calls the existing RPC). Going with the latter: one `is`-check, no new signal plumbing.

### GameModeEvent

`tutorial_sequence: Array[TutorialSteps.Step]` — **deleted**. Lessons live in the scene now. Migrate all three sub-resources in `test_city_01.tscn` accordingly.

## Files

### New

- `levels/components/objective.gd`
- `levels/components/game_mode_lesson.gd`
- `managers/gamemodes/tutorial/objectives/wheelie_objective.gd`
- `managers/gamemodes/tutorial/objectives/stoppie_objective.gd`
- `managers/gamemodes/tutorial/objectives/speed_above_objective.gd`
- `managers/gamemodes/tutorial/objectives/change_gear_objective.gd`
- `managers/gamemodes/tutorial/objectives/close_help_objective.gd`

### Edit

- `levels/components/event_start_circle.gd` — `@export start_marker`, `get_lessons()`, widen signal to pass source circle.
- `utils/state_machine/gamemode_state_context.gd` — add `event_start_circle`.
- `managers/gamemodes/gamemode_manager.gd` — `pending_event_start_circle` field + pack into ctx.
- `managers/gamemodes/free_roam/free_roam_gamemode.gd` — adapt to new signal sig; set `pending_event_start_circle`.
- `managers/gamemodes/tutorial/tutorial_gamemode.gd` — full rewrite of sequence / wiring sections; objectives drive HUD + checks.
- `managers/gamemodes/tutorial/tutorial_player_state.gd` — drop `tutorial_steps`, add `lesson_state`.
- `resources/events/gamemode_event.gd` — drop `tutorial_sequence`.
- `utils/constants.gd` — remove `TutorialCourses` group.
- `levels/test_levels/test_city_01/test_city_01.tscn` — restructure as below.

### Delete

- `managers/gamemodes/tutorial/tutorial_steps.gd`
- `managers/gamemodes/tutorial/tutorial_lesson.gd`
- `managers/gamemodes/tutorial/tutorial_course.gd`

## test_city_01.tscn migration

Three event circles exist today. Each becomes a course root.

**`Tutorial01EventStartCircle`** (was: `tutorial_sequence=[PRESS_RT]`):
```
Tutorial01EventStartCircle
├─ start_marker (Marker3D, @export)  ← reuse existing %Tutorial01StartMarker
└─ Lesson_PressRT (GameModeLesson, ALWAYS, objective=SpeedAboveObjective(2.0, "TUT_PRESS_RT"))
```

**`Tutorial01EventStartCircle2`** (was: `[SHOW_HELP, PRESS_RT, REACH_SPEED, CHANGE_GEAR, DO_WHEELIE, DO_STOPPIE]`):
```
Tutorial01EventStartCircle2
├─ start_marker (Marker3D)
├─ Lesson_ShowHelp     (ALWAYS,  CloseHelpObjective)
├─ Lesson_PressRT      (ALWAYS,  SpeedAboveObjective(2.0,  "TUT_PRESS_RT"))
├─ Lesson_ReachSpeed   (ALWAYS,  SpeedAboveObjective(30.0, "TUT_REACH_SPEED"))
├─ Lesson_ChangeGear   (ALWAYS,  ChangeGearObjective)
├─ Lesson_Wheelie      (ALWAYS,  WheelieObjective(3.0))
└─ Lesson_Stoppie      (ALWAYS,  StoppieObjective(1.0))
```
(Migrations to PROP_EVENT / WHILE_INSIDE come later, once we have placed CheckpointMarker / TriggerZone instances.)

**`TutorialCourse01` node + `Resource_rgqfv` event** — old wrapper. Delete the TutorialCourse01 node. The third event circle this was tied to (if any) gets its lessons inlined the same way.

## Migration sequence (commits)

1. Add `Objective` base + 5 tutorial objective subclasses. Add `GameModeLesson`. Compiles, unused.
2. Widen `EventStartCircle` signal + add `start_marker` / `get_lessons()`. Update free_roam + gamemode_manager + ctx. Compiles, behavior unchanged (no lessons under any circle yet).
3. Rewrite `TutorialGameMode` to consume `event_start_circle` + objectives. Drop `TutorialSteps` import. Delete `tutorial_steps.gd`, `tutorial_lesson.gd`, `tutorial_course.gd`. Drop `tutorial_sequence` from `GameModeEvent`. Drop `TutorialCourses` group.
4. Migrate `test_city_01.tscn`: restructure all three start circles, delete `TutorialCourse01`. Verify in-editor.

## Open / deferred

- Visual polish (active vs inactive lesson props): unchanged from v1 plan.
- Per-peer prop activation: still global. Multi-peer visual feedback unsolved.
- `GroundArrow` subclass: not in this slice.
- Skip / fast-track courses: trivial later — just an alternate course root with fewer lessons.
- Trigger UID/path uniqueness: lessons may now reference the *same* `GameModeObject` from multiple lessons (e.g. one zone for both wheelie-in-zone and stoppie-in-zone). Wiring uses a `seen` set, same as v1.
