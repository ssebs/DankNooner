# Gamemode System Cleanup Plan

Refactor of the GameMode / GameModeObjective / GameModeEvent stack. Driven by [_ScratchPad.md](./_ScratchPad.md). Companion docs: [GamemodeSystem.md](./GamemodeSystem.md)

## READ FIRST — before touching anything

Re-read every one of these in full. Docs describe intent, not reality — the code is the source of truth and may be mid-refactor.

```
managers/gamemodes/gamemode.gd
managers/gamemodes/gamemode_manager.gd
managers/gamemodes/tutorial/tutorial_gamemode.gd
managers/gamemodes/free_roam/free_roam_gamemode.gd
managers/gamemodes/street_race/street_race_gamemode.gd
managers/gamemodes/components/event_start_circle.gd
managers/gamemodes/components/gamemode_object.gd
managers/gamemodes/components/checkpoint_marker.gd
managers/gamemodes/gamemode_objectives/gamemode_objective.gd
managers/gamemodes/gamemode_objectives/countdown_obj.gd
managers/gamemodes/gamemode_objectives/teleport_obj.gd
managers/gamemodes/gamemode_objectives/speed_above_obj.gd
managers/gamemodes/gamemode_objectives/change_gear_obj.gd
managers/gamemodes/gamemode_objectives/close_help_obj.gd
managers/gamemodes/gamemode_objectives/wheelie_duration_obj.gd
managers/gamemodes/gamemode_objectives/stoppie_duration_obj.gd
resources/events/gamemode_event.gd
utils/state_machine/gamemode_state_context.gd
main_game.tscn (for how nodes are wired)
levels/test_levels/test_01/test_01_level.tscn  contains an EventStartCircle (Tutorial01, etc.)
```

Also grep for usages before each rename — names referenced from `.tscn` files won't surface in code search alone.

## Decisions (locked)

- **`GameMode` (class) → `GameModeType`**. Enum `TGameMode` moves from `GamemodeManager` into `gamemode.gd` and is renamed `Kind`. Usage: `GameModeType.Kind.TUTORIAL`.
- **`GameModeEvent` (resource) → `GameModeEventDefinition`**. Adds `event_type: EventType { SEQUENTIAL, CONCURRENT }` field. Data only — no logic this pass.
- **Merge `GameModeObjective` + the proposed `GameModeRENAMEME` from the scratchpad** into one class: **`GameModeTask`**. Covers both "checks" (reach speed, change gear) and "actions" (teleport, countdown, play sound). Order-neutral name on purpose.
- **`GameModeObject` keeps its name.** Level-authored props (rings, gates) — rename later if it still feels wrong after the surrounding noise is gone.
- **`*TutorialStep` class names → `*Task`** (since `Step` implies sequence and we're adding `CONCURRENT` events).
- **Files `*_obj.gd` → `*_task.gd`.**
- **Folder consolidation** under `managers/gamemodes/`:
  ```
  managers/gamemodes/
    gamemode.gd                       (class GameModeType)
    gamemode_manager.gd
    state_context.gd                  (moved from utils/state_machine/)
    types/
      free_roam/
      tutorial/
      street_race/
    tasks/                            (was gamemode_objectives/)
      gamemode_task.gd                (was gamemode_objective.gd)
      countdown_task.gd
      teleport_task.gd
      speed_above_task.gd
      change_gear_task.gd
      close_help_task.gd
      wheelie_duration_task.gd
      stoppie_duration_task.gd
    gamemodeobjects/                  (was components/)
      gamemode_object.gd
      event_start_circle.gd
      checkpoint_marker.gd
    resources/
      gamemode_event_definition.gd    (was resources/events/gamemode_event.gd)
  ```

## Out of scope (defer)

- Implementing CONCURRENT event traversal — only adding the enum field this pass.
- Lifting `set_respawn_marker` / `mark_objective_state` / `show_countdown` to base `GameModeType` to kill the `as TutorialGameMode` casts. **Will be addressed reactively** as renames force the issue, but no preemptive design. remind the user
- Renaming `GameModeObject`.
- Splitting CourseGameMode out of base. One-class hierarchy stays.

## Execution order

Each phase ends in a runnable, testable state. Do not bundle phases.

### Phase 1 — Enum + base class rename (`GameMode` → `GameModeType`)

1. Re-read `gamemode.gd`, `gamemode_manager.gd`, every `_gamemode.gd` subclass, every `.tscn` that names a `GameMode` node.
2. Move `enum TGameMode { ... }` from `GamemodeManager` into `gamemode.gd`. Rename to `Kind`.
3. Rename `class_name GameMode` → `GameModeType`.
4. Update every `GamemodeManager.TGameMode.X` reference to `GameModeType.Kind.X`.
5. Update every `extends GameMode` → `extends GameModeType`.
6. Update `_gamemode: GameMode` typed var on `gamemode_objective.gd` → `GameModeType`.
7. **Verify:** project loads in editor with no parse errors; `_get_configuration_warnings()` clean on all gamemode nodes; tutorial entry from free roam works.

### Phase 2 — Resource rename (`GameModeEvent` → `GameModeEventDefinition`)

1. Re-read `resources/events/gamemode_event.gd` and every consumer (`event_start_circle.gd`, `gamemode_state_context.gd`, free_roam gamemode).
2. Rename class + file. Add `enum EventType { SEQUENTIAL, CONCURRENT }` and `@export var event_type: EventType = EventType.SEQUENTIAL`.
3. Update typed references (`@export var gamemode_event: GameModeEvent` → `GameModeEventDefinition`).
4. Update every `.tres` resource's `script` reference. Check `Tutorial01EventDefinition.tres` (and any others) load correctly.
5. **Verify:** confirm HUD pops up on event circle entry; tutorial still launches.

### Phase 3 — Merge to `GameModeTask`

1. Re-read `gamemode_objective.gd` and every `*_obj.gd` subclass.
2. Rename `class_name GameModeObjective` → `GameModeTask`. File: `gamemode_task.gd`.
3. Rename each subclass file `*_obj.gd` → `*_task.gd`, class `*TutorialStep` (or `*Objective`) → `*Task` (`CountdownTask`, `TeleportTask`, `SpeedAboveTask`, `ChangeGearTask`, `CloseHelpTask`, `WheelieDurationTask`, `StoppieDurationTask`).
4. Update `EventStartCircle.get_objectives()` → `get_tasks()` returning `Array[GameModeTask]`.
5. Update `_objectives` / `_objective` locals in `tutorial_gamemode.gd` → `_tasks` / `_task`. (Includes uncommenting the `_tasks = _start_circle.get_tasks()` assignment — was commented out during review.)
6. Update `_gamemode` typed var; update `mark_objective_state` callers (method name stays for now — comes off in the future decoupling pass).
7. Update every `.tscn` that has a `*TutorialStep` or `*Objective` node — script references need repath, class names need replacement. Grep `.tscn` for old names.
8. **Verify:** full tutorial playthrough — countdown, close help, speed gates, wheelie, gear change, stoppie, results screen.

### Phase 4 — Folder consolidation

1. Move `utils/state_machine/gamemode_state_context.gd` → `managers/gamemodes/state_context.gd`.
2. Move `resources/events/gamemode_event_definition.gd` → `managers/gamemodes/resources/`.
3. Move `managers/gamemodes/components/` → `managers/gamemodes/gamemodeobjects/`.
4. Rename `managers/gamemodes/gamemode_objectives/` → `managers/gamemodes/tasks/`.
5. Move `free_roam/`, `tutorial/`, `street_race/` under `types/`.
6. Fix every `preload(...)`, `load(...)`, `.tscn` `ext_resource` path. Editor will surface broken refs on load.
7. **Verify:** clean project re-open, no missing scripts, tutorial still runs.

### Phase 5 — Update docs

1. `GamemodeSystem.md` — refresh class names, file paths, code snippets.
2. `GamemodeEventAndGameModeLessonAndTutorial.md` — refresh, retitle (no more "Lesson", maybe → `GamemodeEventAndTaskAuthoring.md`).
3. `_ScratchPad.md` — strike through the section (it's done).
4. `CLAUDE.md` — update the Gamemode System section if names there are stale.

## Bug fixes done opportunistically

These surface during the refactor — fix in place:
- `tutorial_gamemode.gd:31` `_tasks = _start_circle.get_tasks()` and the `_gamemode = self` loop — uncomment (was review-state only).
- Any `as TutorialGameMode` cast that's trivially fixable without designing a new base API stays. Hard ones get a `# TODO: decouple — see PLAN.md "out of scope"` comment and are deferred.

## Verify-at-end checklist

- [ ] Project loads with no parse errors and no missing script refs.
- [ ] Free roam → enter `Tutorial01EventStartCircle` → confirm HUD → tutorial starts.
- [ ] Tutorial completes end-to-end on host.
- [ ] Tutorial completes end-to-end with a joined client (late-join intentionally not in scope, but normal join must still work).
- [ ] Street race mode still transitions in/out (no regression from base-class rename).
- [ ] Grep for stale names returns nothing: `TGameMode`, `GameModeEvent\b`, `GameModeObjective\b`, `class_name.*TutorialStep`, `_obj\.gd`.
