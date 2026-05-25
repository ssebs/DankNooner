# PLAN — Playtest Bug Fixes (Sprint Phase 1)

Stabilize what exists before adding anything new. Source list: playtest bugs from `TODO.md`.

## Goal

Race and free roam are playable end-to-end with friends, no broken-state escape hatches needed.

## Out of scope

- Any new features, tricks, modes, animations
- Code-review TODOs (BikeSkinDefinition split, signal mismatches, `user://` paths, etc.) — separate sprint
- Console commands for broken race start — cut from sprint (the *real* fix is the underlying respawn bug below)
- Tutorial expansion, customization v2

## Bug list (priority order)

### B1. All players spawn under map
**Fix:** Reuse `GridSpawnTask` (currently used by `StreetRaceGameMode`) in `FreeRoamGameMode`.
- `FreeRoamGameMode` runs a leading `GridSpawnTask` on entry, assigning each peer a unique spawn slot.
- Grid markers live on the level; `FreeRoamGameMode` reads them off the active `LevelDefinition`.
- Existing `SpawnManager.respawn_player_at` is the only spawn primitive needed.
- Files: `managers/gamemodes/types/free_roam/free_roam_gamemode.gd`, `managers/gamemodes/tasks/grid_spawn_task.gd`, `levels/test_levels/*/`.

### B2. Race respawn doesn't work
**Investigate first:** trace what `notify_crashed → respawn_requested → SpawnManager.respawn_player` actually does mid-race. Likely the persistent `rb_respawn_transform` isn't being honored OR the race state machine is fighting the spawn.
- See `StreetRaceMode.md` "Crash respawn" section — the design is correct, so this is a bug not a redesign.
- Files: `managers/gamemodes/types/street_race/street_race_gamemode.gd`, `managers/gamemodes/tasks/race_task.gd`, `managers/spawn_manager.gd`, `player/player_entity.gd` (`rb_do_respawn`).

### B3. Crashing during race kills audio + lets you move in spawn
**Investigate:** likely two bugs.
- Audio death = something in `AudioManager` or `CrashController` is not resetting FMOD state on respawn.
- "Can still move in spawn" = input is still being processed pre-spawn or `is_crashed` flag isn't fully clearing.
- Files: `managers/audio_manager.gd`, `player/controllers/crash_controller.gd`, `player/controllers/input_controller.gd`.

### B4. Trick sounds play for everyone (should be local-only)
**Fix:** Trick SFX should play only on the player local to that peer, not broadcast.
- Check where the trick sound is triggered (likely `trick_controller.gd` or `hud_controller.gd`).
- Gate behind `is_multiplayer_authority()` or `player_entity.is_local_player()`.
- Files: `player/controllers/trick_controller.gd`, `player/controllers/hud_controller.gd`, `managers/audio_manager.gd`.

### B5. Height offset for some clients
**Investigate:** likely a rollback-state mismatch — visual_root or bike_skin pos not properly synced/reset.
- Check `RollbackSynchronizer` config on `PlayerEntity`. Compare what's synced vs what's locally derived.
- Reproduce by host-spawn vs client-late-join.
- Files: `player/player_entity.gd`, `player/controllers/animation_controller.gd`.

### B6. Countdown crash → player must manually respawn before start
**Fix:** During race countdown phase, if a player is `is_crashed`, auto-respawn them so the race can start cleanly.
- Either: auto-clear crash on countdown enter, OR force-respawn-all on race-start.
- Files: `managers/gamemodes/tasks/race_task.gd`, `managers/gamemodes/tasks/grid_spawn_task.gd`, and whichever runs the countdown.

### B7. Host can't go to Customize (others get kicked / leave)
**Investigate:** going to customize is currently tearing down the server. Two possible fixes:
- a) Allow customize from pause without leaving the lobby (preferred — keep server alive).
- b) Block the host customize button with a clear UI message.
- Files: `menus/customize_menu/`, `menus/pause_menu/`, `managers/network/connection_manager.gd`.

### B8. Wheelies are too hard
**Tuning, not a code change.** Tweak in `BikeSkinDefinition` `.tres` files: clutch-kick window, throttle threshold, max wheelie angle, balance damping.
- Run with a friend after tuning to confirm.
- Files: `resources/*.tres`, possibly `player/controllers/trick_controller.gd` for the detection thresholds.

### B9. Restart race button
- Add a button to the race results HUD (or pause menu while in a race) that re-runs the current `EventStartCircle`'s runners from the top.
- Server-authoritative; client request → host re-enters the race gamemode.
- Files: `managers/gamemodes/hud/results_hud.gd`, `managers/gamemodes/types/street_race/street_race_gamemode.gd`.

### B10. Starting the gamemode for everyone doesn't work as expected
**Investigate:** symptoms unclear from TODO entry. Get a repro from a playtest before implementing — write the repro into this doc when found.
- Files: `managers/gamemodes/gamemode_manager.gd`, `managers/gamemodes/gamemodeobjects/event_start_circle.gd`.

## Verification

For each bug, the human plays the relevant flow (solo + with one friend at minimum) and confirms the bug is gone. Document any new repros found along the way.

## Sequencing suggestion

1. B1 (spawns) — unblocks every other test
2. B2, B3, B6 (race respawn cluster) — these likely share root causes
3. B5 (height offset) — host/client desync, may overlap with B3
4. B4 (trick sounds) — small, isolated
5. B7 (host customize) — UX, can ship separately
6. B9 (restart race) — small feature
7. B8 (wheelie tuning) — last, requires the rest to be stable to playtest properly
8. B10 — only if a repro surfaces during the sprint
