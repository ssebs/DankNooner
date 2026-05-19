# Scratch Pad
---


## Cleanup gamemode objective / events

**Problems**:
- tutorial_gamemode.gd:31 Enter() - should not be setting _gamemode var here, instead do in event start circle
- tutorial_gamemode.gd:36 _wire_objective_signals() - should not be specific to the tutorial, move this somewhere generic
- tutorial_gamemode.gd:388 _on_trigger_entered - same as above
- Confusion between `GameMode`, `GameModeObjective`, `GameModeObject`, `GameModeEvent`, `GamemodeStateContext`
  - Too many classes!
- Code Folder Structure is not ideal, too many diff places for 1 system, and should prob not all be under managers/gamemodes/

**What I want**:
- `GameMode` => Rename to `GameModeType`
  - e.g. Tutorial, Race, TrickBattle, FreeRoam
- `GameModeEvent` => Rename to `GameModeEventDefinition`
  - Just metadata about an event
  - e.g. Tutorial 01, City Race, Trick Line 01. 
  - New: can have type: `sequential`, `concurrent`
- `EventStartCircle` has a `GameModeEventDefinition`, and `GameModeObjective`s / `GameModeRENAMEME`s under it
- `GameModeRENAMEME` => To be named, but lives under `EventStartCircle` & controls the gamemode
  - e.g. Teleport player, countdown timer, play sound, play cutscene/anim on objects, update UI (e.g. leaderboard)
- `GameModeObjective` => Goals / things to check depending on `GameModeEventDefinition` type
  - e.g. Wheelie duration, max speed, button pressed
  - This could be renamed, and be the same type as `GameModeRENAMEME`?
- `GameModeObject` => Scenes/Nodes that are used in `GameModeObjective`s / `GameModeRENAMEME`s
  - e.g. `CheckPointMarker`

**Existing Files**:
```
managers/gamemodes/gamemode.gd
managers/gamemodes/tutorial/tutorial_gamemode.gd
managers/gamemodes/components/event_start_circle.gd
managers/gamemodes/gamemode_objectives/gamemode_objective.gd
managers/gamemodes/components/checkpoint_marker.gd
managers/gamemodes/components/gamemode_object.gd
managers/gamemodes/gamemode_objectives/countdown_obj.gd
managers/gamemodes/gamemode_objectives/teleport_obj.gd
managers/gamemodes/gamemode_objectives/speed_above_obj.gd
managers/gamemodes/gamemode_objectives/change_gear_obj.gd
utils/state_machine/gamemode_state_context.gd
```
