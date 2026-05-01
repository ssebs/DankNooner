# Code Review — 2026-04-30

> Scope: `.gd` / `.tscn` / `.tres` only, excluding `addons/`. Reviewed against `CLAUDE.md` standards (fail loudly, no duplicate logic, surgical/simple, reuse existing) and the planning docs in `planning_docs/`.

Subsystem reviews dispatched in parallel: player controllers, managers/gamemodes, menus/state machine, levels/skins/utils.

---

# Architecural

"Code in _rollback_tick may not call randf*, Time.get_ticks_*, or read non-synced state. Use a seeded RNG that's part of synced state if you   
  ▎ need randomness."  



  4. Late-join contract for gamemodes.                                                                                                             
  Your existing TODO has tutorial finished MP => clients dont respawn back in free roam — that's a symptom of the bigger pattern. When you add     
  Trick Battle, the same class of bug returns (round timer, scores, etc. don't sync to late joiners). Bake serialize_state_for_late_joiner() /     
  apply_state_from_host() into the base GameMode class once, before adding modes 3-4.                                                            
                                                                                                                                                   
  5. Split BikeSkinDefinition now.                                                                                                                 
  You have 3 bikes. You're adding mods, performance mods, color variants. The longer you wait, the more .tres files you migrate. This is the single
   architecture refactor with the best ROI right now.      
    - TODO: separate diff parts to new resources, like powerstats, ikpositions, etc. make more composed





1. BikeSkinDefinition is a god-resource                                                                                                          
   
  It owns: visuals + collision + rider IK pose + wheel markers + gearing + physics tuning + trick limits. That's five conceptual axes glued        
  together. Implications:
                                                                                                                                                   
  - Modding/cosmetic skins: ColorMod works, but a "performance mod" (e.g. swap power curve) means duplicating the whole .tres for every visual     
  variant.
  - Cross-bike tuning sweeps: changing physics for all sport bikes means editing N skins rather than one tuning resource.                          
  - Network sync: when serializing for MP, you ship a giant blob — already a known concern (the to_dict only ships the path, but per-mod tuning    
  swap isn't possible).                                                                                                                            
  - Authoring: your Save Default Pose button writes back into the same resource that owns physics constants. Easy to clobber.                      
                                                                                                                                                   
  Split into BikeVisualDefinition (mesh, colors, rider pose markers) + BikeTuningDefinition (gearing, physics, trick limits) +                     
  BikeChassisDefinition (collision, wheel markers). A bike entity composes one of each. Mods can target one axis without affecting the others. Do  
  this before you have 20 bikes — refactoring 3 is cheap, refactoring 20 is not. 


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

