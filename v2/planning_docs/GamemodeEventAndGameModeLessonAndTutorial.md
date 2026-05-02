# GameModeEvent / GameModeLesson / Objective

How tutorials (and future per-mode courses like races) are authored.

## The four pieces

| Piece | Type | What it is |
| ----- | ---- | ---------- |
| `GameModeEvent` | Resource | Metadata for the event: name, description, target gamemode, countdown. No logic. |
| `EventStartCircle` | Node (Area3D) | Trigger in the world. When a player drives in, free roam offers them this event. **Also acts as the course root** — its child lessons are the steps. |
| `GameModeLesson` | Node | One step. Holds an `Objective` + when to evaluate it + an optional trigger node. |
| `Objective` | Resource | The actual rule (wheelie 3s, speed > 30, etc.). Pure logic, reusable across gamemodes. |

## Flow

1. Player enters an `EventStartCircle` in free roam → confirm HUD pops up.
2. Player confirms → `TutorialGameMode` starts, receives the start circle via `GamemodeStateContext`.
3. Tutorial reads `start_circle.start_marker` (teleport target) and `start_circle.get_lessons()` (children, in tree order).
4. Per peer, walks lessons. For each: calls `objective.check(player, delta, state)` according to `eval_when`. On true → advance.
5. All peers done → results screen.

## Authoring a tutorial — `Tutorial01EventStartCircle2` example

This is the "Moto 101" course, 6 lessons.

```
Tutorial01EventStartCircle2 (EventStartCircle)
├─ gamemode_event   = Resource_asds5  ("Tutorial: Moto 101", target=TUTORIAL)
├─ start_marker     = ../Stuff/Tut01Location/Tutorial01StartMarker
│
├─ Lesson_ShowHelp     (GameModeLesson, objective=CloseHelpObjective)
├─ Lesson_PressRT      (GameModeLesson, objective=SpeedAboveObjective(min_speed=2.0))
├─ Lesson_ReachSpeed   (GameModeLesson, objective=SpeedAboveObjective(min_speed=30.0))
├─ Lesson_Wheelie      (GameModeLesson, objective=WheelieObjective(duration=3.0))
├─ Lesson_ChangeGear   (GameModeLesson, objective=ChangeGearObjective)
└─ Lesson_Stoppie      (GameModeLesson, objective=StoppieObjective(duration=1.0))
```

Steps to build a new one in the editor:

1. Drop an `EventStartCircle` instance in your level scene.
2. Set `gamemode_event` (inline new sub-resource or reuse). Set `start_marker` (any `Marker3D` in the scene).
3. Add `GameModeLesson` child Nodes in order. On each, drag in an `Objective` resource (existing or new).

That's it. No registration, no group, no enum.

## `eval_when` — three policies

| Mode | When `check()` runs | Use for |
| ---- | ------------------- | ------- |
| `ALWAYS` | Every tick (legacy behavior) | Time-based checks (wheelie 3s anywhere) |
| `ON_ENTER` | Once, when the trigger's `entered` signal fires | "Wheelie through this gate" — pass-through gates |
| `WHILE_INSIDE` | Every tick, but only while inside the trigger zone | "Stoppie 1s inside this zone" — bounded checks |

`ON_ENTER` and `WHILE_INSIDE` require the `trigger` field to point at a `GameModeObject` (typically a `CheckpointMarker` or `TriggerZone`).

## Using triggers (CheckpointMarker / TriggerZone)

Both extend `GameModeObject`, which auto-wires a child `Area3D` to fire `entered` / `exited` signals (filtered to `PlayerEntity`).

### CheckpointMarker (gate / ring)

Gate the player passes *through*. One-shot signal.

```
EventStartCircle
├─ Marker3D (start_marker)
├─ CheckpointMarker  (instance .tscn — has Area3D + visible posts)
└─ Lesson_GateWheelie (GameModeLesson)
   ├─ objective  = WheelieObjective(3.0)
   ├─ eval_when  = ON_ENTER
   └─ trigger    = (drag in the CheckpointMarker above)
```

Player must be wheelying *at the moment they pass through the gate*.

### TriggerZone (volumetric area)

Box-shaped zone. Continuous in/out tracking.

`TriggerZone` has no `.tscn` — you place it as a Node3D, give it a `Script = trigger_zone.gd`, and add an `Area3D + CollisionShape3D` child yourself.

```
EventStartCircle
├─ TriggerZone  (with Area3D + Box CollisionShape3D children)
└─ Lesson_StoppieInZone (GameModeLesson)
   ├─ objective  = StoppieObjective(1.0)
   ├─ eval_when  = WHILE_INSIDE
   └─ trigger    = (drag in the TriggerZone above)
```

Stoppie timer only ticks while the player is inside the zone.

## Adding a new Objective

A new mechanic = one `.gd` file, ~20 lines.

```gdscript
# managers/gamemodes/<mode>/objectives/my_objective.gd
class_name MyObjective extends Objective

@export var some_threshold: float = 5.0

func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
    state["t"] = state.get("t", 0.0) + delta
    return state["t"] >= some_threshold

func get_progress(state: Dictionary) -> String:
    return "%.1f / %.1fs" % [state.get("t", 0.0), some_threshold]

func get_objective_text() -> String: return "MY_OBJECTIVE_KEY"
func get_hint_text() -> String:      return "MY_HINT_KEY"
```

Then in the inspector, on any `GameModeLesson`, click `objective` → New `MyObjective` → tweak exports.

### The `state` dictionary

- Owned by the gamemode, scoped to **one player + one lesson**.
- Cleared on lesson advance and on crash.
- Mutate freely. Pick your own keys.
- Use it for accumulators (`state["t"]`), one-time captures (`state["initial_gear"]`), flags (`state["closed"]`).

### The four override hooks

| Hook | When | Common use |
| ---- | ---- | ---------- |
| `on_enter(player, state)` | When this lesson becomes the current one for a peer | Init `state` keys; capture initial values |
| `check(player, delta, state) -> bool` | Per `eval_when` policy | Return true when the objective is complete |
| `on_exit(player, state)` | Right before advancing to the next lesson | Cleanup; rare |
| `get_progress(state) -> String` | Every tick (HUD) | "1.4 / 3.0s" — return `""` for no progress display |
| `get_objective_text()` / `get_hint_text()` | Once on lesson start | Return localization keys for the HUD |

## Reusing this for non-tutorial gamemodes

Same shape works for race, future modes:

- Race lap: `PassThroughObjective` (returns true on any tick) + `eval_when=ON_ENTER` + `CheckpointMarker`. Player drives through → done.
- "Stay in zone for 10s": `StayInZoneObjective(duration=10)` + `WHILE_INSIDE` + `TriggerZone`.
- Combo trick: `LandTrickObjective(trick_type=...)` + `ON_ENTER` (zone is the landing area).

The gamemode's `Enter()` reads its `EventStartCircle` from ctx, walks `get_lessons()`, and runs the same loop.

## Common gotchas

- **Lessons are children of the `EventStartCircle`**, not of a separate course node. Tree order = play order.
- **`ON_ENTER` is one-shot.** The flag clears the moment `check()` is called. If `check()` returns false, the player has to leave and re-enter.
- **`WHILE_INSIDE` clears state on lesson advance and on crash** — so a teleport-back can't strand you "inside."
- **The `trigger` ref must be a `GameModeObject` subclass** (`CheckpointMarker`, `TriggerZone`, etc.). Plain `Area3D` won't work.
- **`gamemode_event.target_gamemode` controls which gamemode runs.** For tutorial courses, set it to `TUTORIAL`. The lessons are picked up regardless of target.
