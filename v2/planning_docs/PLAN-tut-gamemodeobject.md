# PLAN — Tutorial × GameModeObject

> Status: brainstormed, not yet implemented. See `tutorial_steps.gd`, `tutorial_gamemode.gd`, `event_start_circle.gd`, `gamemode_event.gd` for current state.

## Goal

Make the tutorial dynamic by placing physical, level-authored objects (gates, zones, ground arrows, checkpoints) that the tutorial sequences and reacts to. Reuse the same prop layer for other gamemodes (Street Race, future modes).

Constraints:

- Tutorial logic stays in tutorial code (`tutorial_gamemode.gd` / `tutorial_steps.gd`). GameModeObjects are **dumb**: they emit signals, expose vars, and offer `activate()` / `deactivate()`. They do not decide completion.
- Keep existing time-based / input-based checks (`hold wheelie 3s`, `press throttle`, `change gear`, `close help menu`). New prop-triggered checks are **added** alongside, not a replacement.
- Use existing `@export` wiring pattern — refs are wired in the inspector, not by name lookup.

## Architecture

### Layer 1 — `GameModeObject` (generic, reused across modes)

Base class: `class_name GameModeObject extends Node3D` (or `Area3D` where needed).

Common API:

- `activate()` / `deactivate()` — toggle visibility, collision, VFX. Inactive objects are inert.
- `is_active: bool`
- Generic signals — concrete subclass picks what fits:
  - `entered(player: PlayerEntity)` — body entered an area
  - `exited(player: PlayerEntity)`
  - `hit(player: PlayerEntity)` — discrete trigger
- Concrete subclasses (initial set):
  - `CheckpointMarker` — ring/gate, fires `entered` when a player passes through. Reused by Street Race.
  - `TriggerZone` — Area3D that fires `entered` / `exited`. Used to scope predicate checks (e.g., "stoppie zone").
  - `GroundArrow` — visual only, has `set_lit(on: bool)` / `point_to(target: Node3D)`. Driven by tutorial code.
  - (later) `TargetCone`, `BrakeZone` with painted distance markers, etc.

Folder: `levels/components/gamemode_objects/`.

### Layer 2 — Tutorial sequencing (tutorial-only)

Two new resources/nodes:

- **`TutorialLesson`** (Node, placed in level OR child of a `TutorialCourse`):
  - `@export step: TutorialSteps.Step` — which mechanic predicate to use (reuses existing enum)
  - `@export trigger_mode: TriggerMode { TIME, PROP_EVENT, PROP_BOUNDED }`
    - `TIME` — current behavior (e.g., wheelie 3s anywhere). No prop refs needed.
    - `PROP_EVENT` — completes when a referenced GameModeObject fires its signal AND the predicate is true at that moment. e.g., "wheelie through this gate".
    - `PROP_BOUNDED` — predicate accumulates only while inside a referenced `TriggerZone`. e.g., "stoppie ≥ 1s while inside the stoppie zone".
  - `@export trigger_objects: Array[GameModeObject]` — gates, zones, etc. May be empty for `TIME` mode.
  - `@export hint_arrows: Array[GroundArrow]` — lit during this lesson, dimmed after.
  - `@export objective_text_key: String` — overrides default per-Step text if set.
- **`TutorialCourse`** (Node, placed in level):
  - `@export lessons: Array[TutorialLesson]` — ordered sequence for this course.
  - `@export start_marker: Marker3D` — replaces the current `%Tutorial01StartMarker` lookup.
  - Multiple courses can exist per level (Basics course, Tricks course, etc.).
- **`GameModeEvent`** gains:
  - `@export tutorial_course: TutorialCourse` — replaces `tutorial_sequence: Array[Step]` for prop-driven courses. Keep the old field for back-compat / TIME-only courses, or migrate fully.

### Layer 3 — Tutorial gamemode wiring

`tutorial_gamemode.gd` changes:

- On `Enter()`, read `TutorialCourse` off the event (fallback to legacy `tutorial_sequence` if course is null).
- For each peer, walk lessons in order. For each lesson:
  - Call `activate()` on its `trigger_objects` and `hint_arrows`.
  - Connect to relevant signals (`entered` / `exited` / `hit`) per `trigger_mode`.
  - Per tick:
    - `TIME` — call existing predicate every tick (current behavior).
    - `PROP_EVENT` — wait for signal; on fire, evaluate predicate once.
    - `PROP_BOUNDED` — track "inside zone" via `entered` / `exited`; only accumulate predicate time while inside.
  - On completion: deactivate that lesson's objects, advance.
- All check logic (`check_is_wheelie`, `check_speed_above`, `_wheelie_time` accumulation) stays in `tutorial_steps.gd`. The new `trigger_mode` is just **when** to evaluate / accumulate.

## Existing step migration

| Step           | Trigger mode (recommended)                        |
| -------------- | ------------------------------------------------- |
| `SHOW_HELP`    | `TIME` (no change)                                |
| `PRESS_RT`     | `TIME` (no change)                                |
| `REACH_SPEED`  | `PROP_EVENT` — `CheckpointMarker` + speed check   |
| `CHANGE_GEAR`  | `TIME` (no change)                                |
| `DO_WHEELIE`   | `PROP_EVENT` — gate(s) + `is_wheelie` predicate, OR `PROP_BOUNDED` zone for old "hold 3s in area" feel |
| `DO_STOPPIE`   | `PROP_BOUNDED` — `TriggerZone` + accumulate ≥ 1s  |

## Open / TBD

- How are lessons visualized in 3D when active vs inactive? (color, glow, billboard arrow above) — design pass before authoring scenes.
- Multi-player: do all peers share one course instance, or does each peer get their own props? Current tutorial is per-peer state; props are level-shared. Likely fine since lessons are independent per peer's progress, but visual feedback ("this gate is lit for me") needs per-peer treatment or a "shared lit when any peer is on this lesson" rule.
- Per-peer lesson activation: today `activate()` is global. May need `activate_for(peer_id)` or a per-peer visual layer.
- Skip / fast-track for skilled players (item D from the original brainstorm) — not in this plan, but the per-lesson structure makes it easy to add later (a "test-out" course = one lesson with several gates in fast succession).
- Ghost-rider demo overlay (item C) — out of scope here; future `GameModeObject` subclass could replay a path.

## First implementation slice

Smallest viable build to prove the system end-to-end:

1. `GameModeObject` base + `CheckpointMarker` + `TriggerZone` (no `GroundArrow` yet).
2. `TutorialLesson` + `TutorialCourse` nodes.
3. Add `tutorial_course` to `GameModeEvent`; tutorial gamemode reads it if set, falls back to legacy `tutorial_sequence` otherwise.
4. Migrate `REACH_SPEED` to `PROP_EVENT` (one checkpoint) and `DO_STOPPIE` to `PROP_BOUNDED` (one zone) in the test_city_01 level. Leave the others on `TIME`.
5. Visual polish + remaining migrations after the shape proves out.
