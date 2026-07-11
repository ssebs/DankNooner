# Code Review — 2026-04-30

> Scope: `.gd` / `.tscn` / `.tres` only, excluding `addons/`. Reviewed against `CLAUDE.md` standards (fail loudly, no duplicate logic, surgical/simple, reuse existing) and the planning docs in `planning_docs/`.

## Triage status — 2026-07-10

🔴 Critical items re-verified against current code:

- ✅ **FIXED — non-determinism in rollback**: `_calc_balance_point_target` (with its `randf_range`) no longer exists; the remaining violation was `randf()` in `_handle_player_collision` — replaced with a deterministic per-peer golden-angle push.
- ✅ **FIXED — `rb_gear_up/down_pressed` float/bool flags**: removed entirely. Gear shifts now sync an absolute `nfx_target_gear` input (edge-triggered flags were being dropped/double-applied by netfox stale-input reuse on the server — root cause of the client 50%-speed-cap bug).
- ✅ **FIXED — `player_spawned.emit(player.name)` type mismatch**: now emits `int`.
- ❌ **STALE — tutorial `@rpc` arg order (:297) & direct `_rpc_transition_gamemode` call (:351)**: gamemodes were refactored into `types/`; the `@rpc` line is gone (and Godot 4 `@rpc` string args are order-insensitive anyway). Direct `_rpc_transition_gamemode.rpc()` calls still exist in `types/{tutorial,challenge,street_race}` — see authority holes below.
- ❌ **STALE — `state_machine.gd` `Dictionary.set()` void check**: `Dictionary.set()` returns `bool` in Godot 4.4+; harmless either way.
- ⏳ **OPEN — RPC authority holes**: `spawn_manager` respawn/set-respawn family (now 5 `any_peer` RPCs), `gamemode_manager.start_game` / `_sync_game_to_late_joiner`. Griefing hardening, not a bug players hit — tracked in TODO backlog ("cleanup to call authority done").
- ⏳ **OPEN — `user://` path leaks**: `character_skin_definition.to_dict` / `player_definition.to_dict` still ship raw `resource_path`. Failure mode is a fallback to default skin on remote peers (not a crash). Awaiting owner decision per note in that section.
- ⏳ **OPEN — shared mutable curves**: `_copy_from` still shares `power_curve` / `lean_curve` / `steer_curve`. Benign today (curves are only sampled, never mutated at runtime).
- ⏳ **OPEN — `WINDOW_MODES` mapping**: unchanged; Godot's `WINDOW_MODE_FULLSCREEN` *is* borderless, so this is a labeling question, not a broken setting.

🟠/🟡 sections not re-verified — treat line numbers as approximate after the `types/` refactor.

Subsystem reviews dispatched in parallel: player controllers, managers/gamemodes, menus/state machine, levels/skins/utils.

---

## 🏛️ Architectural decisions to lock in

> Decisions to make *before* building further `TODO.md` items, so you don't redo them. Skipping items already on the TODO (scoring v2, race lap system, ragdoll-in-MP, traffic, friends/server browser, dedicated server, text chat, `update Architecture.md`, `cleanup to call authority done`) — those are *implementation* work. The three below are **shape** decisions that gate them.

### 1. Determinism rules in `_rollback_tick`

Define the rule explicitly so future rollback code can be checked against it. Suggested wording for [`planning_docs/PlayerController.md`](./PlayerController.md) (or a new `Determinism.md`):

> Code reachable from `_rollback_tick` may not call `randf*`, `randi*`, `Time.get_ticks_*`, or read non-synced global state (mouse position, OS clock, `Engine.get_process_frames()`, etc.). When randomness is needed, use a seeded `RandomNumberGenerator` whose seed is part of synced state.

**Existing violation:** [`player/controllers/movement_controller.gd:492`](../player/controllers/movement_controller.gd#L492) — `randf_range(...)` inside `_calc_balance_point_target()`.

**Audit surface as you grow rollback code:**
- Everything called from [`player/player_entity.gd:141`](../player/player_entity.gd#L141) (`_rollback_tick`) — currently movement → gearing → trick → crash.
- Any `nfx_*` derivation in [`movement_controller.gd`](../player/controllers/movement_controller.gd), [`gearing_controller.gd`](../player/controllers/gearing_controller.gd), [`trick_controller.gd`](../player/controllers/trick_controller.gd), [`crash_controller.gd`](../player/controllers/crash_controller.gd).
- The `do_reset()` paths invoked by [`player_entity.gd:333`](../player/player_entity.gd#L333) (`do_respawn`) — also re-run during rollback.

**Visibility:** add a debug overlay surfacing netfox's correction count per second. When Trick Battle ships and feels jittery under latency, you'll have a number to check rather than a vibe. Netfox already exposes the data via its rollback events; thin HUD overlay is enough.

### 2. Late-join contract for gamemodes

Today [`managers/gamemodes/gamemode_manager.gd:157`](../managers/gamemodes/gamemode_manager.gd#L157) (`_sync_game_to_late_joiner`) only ships `level_name`. The TODO item *"tutorial finished MP => clients dont respawn back in free roam"* is one symptom of this missing contract; round timers, scoreboards, and checkpoint progress will hit the same class of bug as more modes land.

Bake the contract into the base [`managers/gamemodes/gamemode.gd`](../managers/gamemodes/gamemode.gd) once (it's already `## Should only be running on server`):

```gdscript
# Override in subclasses to ship/restore mid-match state to late joiners.
func serialize_state_for_late_joiner() -> Dictionary: return {}
func apply_state_from_host(state: Dictionary) -> void: pass
```

[`gamemode_manager.gd`](../managers/gamemodes/gamemode_manager.gd) calls `serialize` on the active mode before the existing late-join RPC, and `apply` on the receiving peer.

**Concrete state each existing/planned mode would carry:**

| Mode                                                                                   | State to sync                                                   |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| [`tutorial_gamemode.gd`](../managers/gamemodes/tutorial/tutorial_gamemode.gd)          | `_sequence`, per-peer `current_index`, countdown remaining      |
| [`free_roam_gamemode.gd`](../managers/gamemodes/free_roam/free_roam_gamemode.gd)       | None today (intentional)                                        |
| [`street_race_gamemode.gd`](../managers/gamemodes/street_race/street_race_gamemode.gd) | Per-peer checkpoints completed, lap count, race start tick      |
| Trick Battle (HI-PRI)                                                                  | Round timer, per-peer score, current round, scoreboard snapshot |
| Crash Launch (HI-PRI)                                                                  | Round phase (drag/launch/scoring), best distance per peer       |

Bake this in **before** mode #3 lands, otherwise each mode reinvents its own ad-hoc late-join sync and the bug pattern keeps repeating.

### 3. Split `BikeSkinDefinition`

TODO: separate diff parts to new resources, like powerstats, ikpositions, etc. make more composed


[`resources/bikes/bike_skin_definition.gd`](../resources/bikes/bike_skin_definition.gd) currently owns five conceptual axes glued together. The `@export_group` blocks in the file already mark the seams:

| `@export_group` in file                                                                                                                     | Conceptual axis |
| ------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `Mesh`, `Mods`, `colors` (lines [12](../resources/bikes/bike_skin_definition.gd#L12), [64](../resources/bikes/bike_skin_definition.gd#L64)) | Visual          |
| `Collision` (line [25](../resources/bikes/bike_skin_definition.gd#L25))                                                                     | Chassis         |
| `Markers`, `Rider Pose` (lines [33](../resources/bikes/bike_skin_definition.gd#L33), [43](../resources/bikes/bike_skin_definition.gd#L43))  | Pose / IK       |
| `Animation`, `Physics`, `Gearing`, `Tricks`                                                                                                 | Tuning          |

**Implications you're already hitting:**

- A "performance mod" (e.g. swap `power_curve`) requires duplicating the whole `.tres` for every visual variant. [`resources/bikes/mods/color_mod.gd`](../resources/bikes/mods/color_mod.gd) only handles colors today; adding a `PowerCurveMod` is awkward when the curve is on the same resource as the mesh.
- The "Save Default Pose" editor button at [`animation_controller.gd:24`](../player/controllers/animation_controller.gd#L24) writes back into the same `.tres` that owns physics tuning → easy to clobber gearing/physics constants while authoring poses.
- [`bike_skin_definition.gd:_copy_from`](../resources/bikes/bike_skin_definition.gd#L187) has to deep-copy more state as the resource grows. It already missed `power_curve` / `lean_curve` / `steer_curve` (see Critical → Shared mutable resources).
- Network sync via [`bike_skin_definition.gd:to_dict`](../resources/bikes/bike_skin_definition.gd#L228) ships the base path + mods. Per-axis mod swaps (e.g. "stock chassis with sport tuning") aren't expressible because there's only one base resource.
- [`Skins.md`](./Skins.md) calls `BikeSkinDefinition` "the single source of truth for per-bike tuning" — that's exactly the problem.

**Proposed split:**

| Resource                | Owns                                                                                                                                                | Consumers                                                                                                                                                                                                   |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BikeVisualDefinition`  | `mesh_res`, mesh offsets, `colors`, `mods`                                                                                                          | [`bike_skin.gd`](../player/bikes/scripts/bike_skin.gd)                                                                                                                                                      |
| `BikeChassisDefinition` | `collision_shape` + offsets, wheel markers (front/rear ground/edge)                                                                                 | [`player_entity._init_raycasts`](../player/player_entity.gd), `bike_skin.gd`                                                                                                                                |
| `BikePoseDefinition`    | rider pose markers (chest / head / hand / foot / butt / arm + leg magnets)                                                                          | [`animation_controller.gd`](../player/controllers/animation_controller.gd)                                                                                                                                  |
| `BikeTuningDefinition`  | `gear_ratios`, `max_rpm`, `power_curve`, `acceleration`, `max_speed`, lean/steer curves, `max_wheelie_angle_deg`, `wheelie_balance_point_deg`, etc. | [`movement_controller`](../player/controllers/movement_controller.gd), [`gearing_controller`](../player/controllers/gearing_controller.gd), [`trick_controller`](../player/controllers/trick_controller.gd) |

`BikeSkinDefinition` becomes a thin composer that just holds `@export var visual / chassis / pose / tuning` references. Existing 3 base bikes ([`mini_default`](../resources/bikes/skins/mini_default_skin_definition.tres), [`naked_default`](../resources/bikes/skins/naked_default_skin_definition.tres), [`sport_default`](../resources/bikes/skins/sport_default_skin_definition.tres)) migrate by hand — cheap now, painful at 20.

**Wins:**

- [`BikeMod`](../resources/bikes/mods/bike_mod.gd) subclasses can target one axis (`PowerCurveMod`, `WheelieLimitMod`, `MeshOverrideMod`) without touching unrelated state.
- "Save Default Pose" only writes to the `BikePoseDefinition`. Tuning constants stay safe.
- Future server-side anti-cheat just whitelists `res://` paths for `BikeTuningDefinition`. Visual customization remains free for players.
- [`bike_skin_definition.gd:to_dict / from_dict`](../resources/bikes/bike_skin_definition.gd#L228) becomes per-axis: ship one path for each, plus mods. No more giant blob.

**Do this before** the customization shop / mod-purchase UI lands ([TODO.md HI-PRI](./TODO.md)) — that's when this resource shape gets baked into save data and migrating becomes painful.

---

## 🔴 Critical (correctness / netcode)

### Non-determinism in rollback tick

- [`player/controllers/movement_controller.gd:492`](../player/controllers/movement_controller.gd#L492) — `randf_range(...)` inside `_calc_balance_point_target()` runs in `_rollback_tick`. Server and client resimulate to different states → constant rollback corrections / desync.

### RPC authority holes

- [`managers/spawn_manager.gd:56`](../managers/spawn_manager.gd#L56) — `respawn_player` is `any_peer` with no server guard. Any client can force everyone to respawn any player.
- [`managers/spawn_manager.gd:65`](../managers/spawn_manager.gd#L65) — `respawn_player_at` same problem.
- [`managers/gamemodes/gamemode_manager.gd:59`](../managers/gamemodes/gamemode_manager.gd#L59) — `start_game` accepts any peer.
- [`managers/gamemodes/gamemode_manager.gd:157`](../managers/gamemodes/gamemode_manager.gd#L157) — `_sync_game_to_late_joiner` missing server guard / `authority`.
- [`managers/gamemodes/tutorial/tutorial_gamemode.gd:351`](../managers/gamemodes/tutorial/tutorial_gamemode.gd#L351) — calls `gamemode_manager._rpc_transition_gamemode.rpc(...)` directly, bypassing the authority check in `change_gamemode`.
- [`managers/gamemodes/tutorial/tutorial_gamemode.gd:297`](../managers/gamemodes/tutorial/tutorial_gamemode.gd#L297) — `@rpc("call_local", "any_peer", "reliable")` — wrong arg order; mode must come first in Godot 4.

### Type / signal mismatches

- [`player/controllers/input_controller.gd:28`](../player/controllers/input_controller.gd#L28) and [:29](../player/controllers/input_controller.gd#L29) — `rb_gear_up_pressed` / `rb_gear_down_pressed` declared `float` but defaulted to `false`. Already a known TODO in `Architecture.md`.
- [`managers/gamemodes/gamemode_manager.gd:121`](../managers/gamemodes/gamemode_manager.gd#L121) — emits `player.name` (String) on a signal declared `player_spawned(peer_id: int)`. Unresolved `# TODO - verify`.
- [`utils/state_machine/state_machine.gd:38`](../utils/state_machine/state_machine.gd#L38) — checks return value of `Dictionary.set()` which is `void`. Registration error log never fires.
- [`managers/settings_manager.gd:21`](../managers/settings_manager.gd#L21) — `WINDOW_MODES` keys swapped: `"fullscreen"` → `WINDOW_MODE_FULLSCREEN`, `"borderless"` → `WINDOW_MODE_EXCLUSIVE_FULLSCREEN`. Godot's `EXCLUSIVE_FULLSCREEN` is true exclusive, not borderless. Window mode setting will be wrong.

### `user://` resource path leaks (multiplayer sync risk)

- Manually read the code here so i understand / can decide what i want to do with saving skins to disk/across the net.

- [`resources/player/character_skin_definition.gd:68`](../resources/player/character_skin_definition.gd#L68) — `to_dict()` ships `mesh_res.resource_path` raw.
- [`resources/player/player_definition.gd:22`](../resources/player/player_definition.gd#L22) — `to_dict()` ships `character_skin.resource_path`.
- Both can be `user://` paths post-customize, breaking the pattern `BikeSkinDefinition` correctly avoids.

### Shared mutable resources

- [`resources/bikes/bike_skin_definition.gd:187`](../resources/bikes/bike_skin_definition.gd#L187), [:196](../resources/bikes/bike_skin_definition.gd#L196), [:197](../resources/bikes/bike_skin_definition.gd#L197) — `_copy_from()` does NOT `.duplicate()` `power_curve`, `lean_curve`, `steer_curve`. Two skins share the same Curve; mutating one mutates the other. (`gear_ratios` is correctly duplicated.)

---

## 🟠 Standards violations

### Silent null returns without justifying comment (CLAUDE.md fail-loudly)

- [`managers/spawn_manager.gd:58`](../managers/spawn_manager.gd#L58), [:65](../managers/spawn_manager.gd#L65) — player lookup → respawn, no comment.
- [`menus/settings_menu/settings_menu_state.gd:40`](../menus/settings_menu/settings_menu_state.gd#L40) — unguarded `state_context.return_state` access.
- [`menus/help_menu/help_menu_state.gd:12`](../menus/help_menu/help_menu_state.gd#L12) — same pattern.
- [`menus/customize_menu/customize_menu_state.gd:31`](../menus/customize_menu/customize_menu_state.gd#L31) — same pattern.
- [`menus/lobby_menu/lobby_menu_state.gd:35`](../menus/lobby_menu/lobby_menu_state.gd#L35) — silent `return` on bad context type leaves UI hidden.
- [`menus/play_menu/play_menu_state.gd:127`](../menus/play_menu/play_menu_state.gd#L127) — `await` after `transitioned.emit` (host path) — Exit() already disconnected, await resumes in dead context.
- [`utils/components/skin_slot.gd:34`](../utils/components/skin_slot.gd#L34) — `runtime_material == null` bail with no comment.
- [`menus/splash_menu/splash_menu_state.gd:40`](../menus/splash_menu/splash_menu_state.gd#L40) — connect inside conditional; `Exit()` always disconnects → error if early path runs.
- [`player/controllers/hud_controller.gd:38`](../player/controllers/hud_controller.gd#L38) — uses `input_state_mgr` immediately after `get_first_node_in_group()` with no null check (the inverse of fail-loudly: it'll crash, but with an opaque message).

### Signal connect/disconnect asymmetry (leaks)

- [`managers/network/lobby_manager.gd`](../managers/network/lobby_manager.gd) — connection_manager + save_manager signals connected in `_ready`, never disconnected.
- [`managers/gamemodes/gamemode_manager.gd:52`](../managers/gamemodes/gamemode_manager.gd#L52) — four signals connected, never disconnected.
- [`managers/gamemodes/free_roam/free_roam_gamemode.gd:59`](../managers/gamemodes/free_roam/free_roam_gamemode.gd#L59) — `hud_submitted` leak path on `Exit` while inside event circle.

### Duplicated logic

- [`player/controllers/animation_controller.gd:482`](../player/controllers/animation_controller.gd#L482) — `_sync_targets_from_bike()` duplicates the math in [`_apply_bike_to_pose()`](../player/controllers/animation_controller.gd#L207). Per `AnimationController.md`, only the editor tool should use the legacy path.
- [`managers/save_manager.gd`](../managers/save_manager.gd) and [`managers/settings_manager.gd`](../managers/settings_manager.gd) — near-identical JSON-versioned stores (~60 lines duplicated).
- [`managers/network/multiplayer_noray.gd:25`](../managers/network/multiplayer_noray.gd#L25) — `_on_setting_updated` and `_on_all_settings_changed` are functionally identical; both ignore args and re-read settings.
- [`menus/customize_menu/customize_menu_state.gd`](../menus/customize_menu/customize_menu_state.gd) — `_scan_skin_dir` and `_scan_color_mods` are near-duplicates.
- [`player/controllers/hud_controller.gd:110`](../player/controllers/hud_controller.gd#L110) — uses `TrickController.Trick.keys()[trick_type]` instead of the existing `trick_to_str()`.

### Group strings / shared enums

- [`levels/assets/graybox/graybox_staticbody.gd`](../levels/assets/graybox/graybox_staticbody.gd) — local enum `GrayBoxColor`; planning doc says shared enums in `utils/constants.gd`.
- [`managers/gamemodes/gamemode_manager.gd:15`](../managers/gamemodes/gamemode_manager.gd#L15) — typo `FREE_FROAM`; dead `STUNT_RACE` enum value with no `_gamemode_map` entry.

### Missing `_get_configuration_warnings()`

- [`menus/main_menu/main_menu_state.gd`](../menus/main_menu/main_menu_state.gd) — 6 `@export` deps, no validation.
- [`menus/settings_menu/settings_menu_state.gd`](../menus/settings_menu/settings_menu_state.gd) — same.
- [`menus/help_menu/help_menu_state.gd`](../menus/help_menu/help_menu_state.gd) — same.
- [`menus/pause_menu/pause_menu_state.gd`](../menus/pause_menu/pause_menu_state.gd) — 8 `@export` deps, no validation.
- [`levels/components/event_start_circle.gd`](../levels/components/event_start_circle.gd) — `@tool` node with no warnings.

### Hardcoded UI strings (need `tr()`)

- [`menus/main_menu/main_menu_state.gd:22`](../menus/main_menu/main_menu_state.gd#L22) — assigns translation-key-looking literals as text instead of `tr(...)`.
- [`menus/lobby_menu/lobby_menu_state.gd:121`](../menus/lobby_menu/lobby_menu_state.gd#L121), [:155](../menus/lobby_menu/lobby_menu_state.gd#L155), [:176](../menus/lobby_menu/lobby_menu_state.gd#L176) — toast strings.
- [`menus/play_menu/play_menu_state.gd:138`](../menus/play_menu/play_menu_state.gd#L138), [:160](../menus/play_menu/play_menu_state.gd#L160) — toast strings.
- [`menus/customize_menu/customize_menu_state.gd:69`](../menus/customize_menu/customize_menu_state.gd#L69) — `"None"`.
- [`levels/components/checkpoint_marker.gd`](../levels/components/checkpoint_marker.gd) — `sign_text: String = "REPLACE_ME"`.

### Authority leaks via private accessors

- [`player/controllers/trick_controller.gd:51`](../player/controllers/trick_controller.gd#L51) — reads `movement_controller._is_on_floor`.
- [`player/controllers/crash_controller.gd:49`](../player/controllers/crash_controller.gd#L49), [:56](../player/controllers/crash_controller.gd#L56), [:63](../player/controllers/crash_controller.gd#L63) — same.
- [`managers/gamemodes/free_roam/free_roam_gamemode.gd:29`](../managers/gamemodes/free_roam/free_roam_gamemode.gd#L29) — calls `spawn_manager._get_player_by_peer_id`.
- [`managers/gamemodes/tutorial/tutorial_gamemode.gd:166`](../managers/gamemodes/tutorial/tutorial_gamemode.gd#L166), [:269](../managers/gamemodes/tutorial/tutorial_gamemode.gd#L269), [:291](../managers/gamemodes/tutorial/tutorial_gamemode.gd#L291), [:364](../managers/gamemodes/tutorial/tutorial_gamemode.gd#L364) — same.

### Manager wiring drift

- [`managers/manager_manager.gd`](../managers/manager_manager.gd) — only 5 of ~10 managers tracked as typed refs; others use ad-hoc `@export` fan-out (e.g. `SpawnManager`, `SaveManager`, `SettingsManager`, `ConnectionManager`, `LobbyManager`, `GamemodeManager`).
- [`managers/base_manager.gd`](../managers/base_manager.gd) — `_ready()` adds to Validate group, but no subclass calls `super._ready()` → registration silently skipped for everyone except `BaseManager` itself.

### Misc real bugs

- [`player/characters/scripts/ik_controller.gd:111`](../player/characters/scripts/ik_controller.gd#L111) — calls `_rotate_bone_to_marker` for chest/head unconditionally while guarding hands/feet — crashes if init order changes.
- [`player/controllers/camera_controller.gd:35`](../player/controllers/camera_controller.gd#L35) — `invert_cam: int = -1` setter coerces via `1 if value else -1` — initial `-1` is truthy, gets reset to `1` on first setter call.
- [`player/controllers/camera_controller.gd:239`](../player/controllers/camera_controller.gd#L239) — `_on_cam_switch_pressed` hardcodes `1 if current_cam_mode == 0 else 0`; if `CameraMode.NONE` is current, it silently switches to FPS.
- [`player/controllers/crash_controller.gd:42`](../player/controllers/crash_controller.gd#L42) — `_prev_trick` written never read.
- [`player/controllers/gearing_controller.gd:23`](../player/controllers/gearing_controller.gd#L23) — `_rpm_ratio` declared, never written.
- [`managers/gamemodes/tutorial/tutorial_hud.gd:41`](../managers/gamemodes/tutorial/tutorial_hud.gd#L41) — `rpc_show_complete` declared, never called.
- [`managers/gamemodes/hud/game_mode_event_confirm_hud.gd:21`](../managers/gamemodes/hud/game_mode_event_confirm_hud.gd#L21) — only shows for `peer_id == 1`; clients never see the confirm.
- [`managers/gamemodes/tutorial/tutorial_gamemode.gd:84`](../managers/gamemodes/tutorial/tutorial_gamemode.gd#L84) — `_get_event` returns null on clients silently → out-of-bounds crash downstream at line 176.
- [`menus/play_menu/play_menu_state.gd:133`](../menus/play_menu/play_menu_state.gd#L133) — connect-failure path leaves user on Lobby with an error toast and no way back.
- [`resources/bikes/bike_skin_definition.gd:250`](../resources/bikes/bike_skin_definition.gd#L250) — `from_dict()` always calls `save_to_disk()` at end — receiver-side surprise write per network deserialize.
- [`utils/dictjsonsaverloader.gd:29`](../utils/dictjsonsaverloader.gd#L29) — `load_json_from_file` doesn't `file.close()` on the parse-error path.
- [`utils/utils_mesh.gd`](../utils/utils_mesh.gd) — `get_combined_aabb()` recurses into `MeshInstance3D` children twice (matches both `is MeshInstance3D` and `is Node3D`).
- [`player/player_entity.gd:300`](../player/player_entity.gd#L300) — `OS.has_feature("debug") and false` — log permanently silenced.
- [`player/player_entity.gd:326`](../player/player_entity.gd#L326) — `do_respawn()` falls back to `get_parent().global_transform`; in MP that's the `Players` container, not a spawn marker.
- [`resources/results_data.gd:26`](../resources/results_data.gd#L26) — `from_dict()` direct `d["title"]` etc. without `.get()`.
- [`resources/events/gamemode_event.gd:5`](../resources/events/gamemode_event.gd#L5) — `name` shadows `Node.name`. Rename to `event_name` / `display_name`.
- [`levels/assets/graybox/graybox_staticbody.gd:59`](../levels/assets/graybox/graybox_staticbody.gd#L59) — `apply_color()` `if not mat` and `else` both call `mat.duplicate()`. The else branch duplicates an already-overridden material. Wasted allocation + logic smell.

---

## 🟡 Style / nits

### Stale TODOs

- [`player/controllers/input_controller.gd:21`](../player/controllers/input_controller.gd#L21), [:26](../player/controllers/input_controller.gd#L26)
- [`player/controllers/camera_controller.gd:52`](../player/controllers/camera_controller.gd#L52), [:192](../player/controllers/camera_controller.gd#L192) (misleading "HACK" comment)
- [`player/controllers/movement_controller.gd:37`](../player/controllers/movement_controller.gd#L37), [:62](../player/controllers/movement_controller.gd#L62)
- [`managers/audio_manager.gd:23`](../managers/audio_manager.gd#L23)
- [`managers/settings_manager.gd:37`](../managers/settings_manager.gd#L37), [:41](../managers/settings_manager.gd#L41), [:66](../managers/settings_manager.gd#L66)
- [`managers/save_manager.gd:40`](../managers/save_manager.gd#L40)
- [`resources/bikes/bike_skin_definition.gd:27`](../resources/bikes/bike_skin_definition.gd#L27), [:35](../resources/bikes/bike_skin_definition.gd#L35) — `# TODO: use this` exports
- [`managers/gamemodes/free_roam/free_roam_gamemode.gd:64`](../managers/gamemodes/free_roam/free_roam_gamemode.gd#L64)

### Commented-out dead code

- [`menus/pause_menu/pause_menu_state.gd:89`](../menus/pause_menu/pause_menu_state.gd#L89)
- [`menus/play_menu/play_menu_state.gd:19`](../menus/play_menu/play_menu_state.gd#L19)
- [`menus/lobby_menu/lobby_menu_state.gd:70`](../menus/lobby_menu/lobby_menu_state.gd#L70), [:126](../menus/lobby_menu/lobby_menu_state.gd#L126)
- [`managers/network/multiplayer_webrtc.gd:25`](../managers/network/multiplayer_webrtc.gd#L25) — ~30 lines
- [`managers/level_manager.gd:50`](../managers/level_manager.gd#L50)
- [`player/player_entity.gd:11`](../player/player_entity.gd#L11), [:122](../player/player_entity.gd#L122)
- [`player/player_entity.gd:333`](../player/player_entity.gd#L333) — commented-out explicit `do_reset` calls below dynamic loop
- [`levels/components/event_start_circle.gd:24`](../levels/components/event_start_circle.gd#L24), [:30](../levels/components/event_start_circle.gd#L30)

### Other nits

- [`utils/validation/auto_validator.gd`](../utils/validation/auto_validator.gd) — uses 4-space indent (rest of codebase uses tabs).
- [`utils/dictjsonsaverloader.gd:16`](../utils/dictjsonsaverloader.gd#L16) — bare `print()` instead of `DebugUtils.DebugMsg()`.
- [`utils/debug_utils.gd`](../utils/debug_utils.gd) — `DebugMsg` doesn't actually gate on `OS.is_debug_build()` despite docstring; the `should_print` bool is a confusing API.
- [`managers/gamemodes/gamemode_manager.gd:15`](../managers/gamemodes/gamemode_manager.gd#L15) — `TGameMode` non-standard prefix.
- [`managers/gamemodes/tutorial/tutorial_steps.gd:179`](../managers/gamemodes/tutorial/tutorial_steps.gd#L179) — magic numbers `"%.1f / 3.0s"` duplicate hardcoded thresholds in checks.
- [`player/controllers/gearing_controller.gd:43`](../player/controllers/gearing_controller.gd#L43) — comment "Called from MovementController._rollback_tick" is wrong; called from PlayerEntity.
- [`utils/ui_toast.gd`](../utils/ui_toast.gd) — no `class_name`, inconsistent with other autoloads.
- [`utils/state_machine/state_context.gd:4`](../utils/state_machine/state_context.gd#L4) — base class field typed as `MenuState`, leaks menu concept into non-menu contexts.
- [`utils/state_machine/gamemode_state_context.gd:6`](../utils/state_machine/gamemode_state_context.gd#L6) — commented-out static factory stub.
- [`managers/input_state_manager.gd:21`](../managers/input_state_manager.gd#L21) — `current_input_state` missing type annotation.
- [`managers/network/multiplayer_ipport.gd:47`](../managers/network/multiplayer_ipport.gd#L47) — `get_addr()` missing return type annotation.
- [`resources/player/character_skin_definition.gd:34`](../resources/player/character_skin_definition.gd#L34) — `push_error("...", err)` two-arg form is wrong; `push_error` takes only one String.
- [`utils/strings.gd`](../utils/strings.gd) — `clean_for_node_name()` is a trivial wrapper, adds no semantic value.
- [`utils/editor_tools/take_screenshot.gd`](../utils/editor_tools/take_screenshot.gd) — hardcoded `Screenshot_RenameMe.jpg`; repeated runs silently overwrite.
