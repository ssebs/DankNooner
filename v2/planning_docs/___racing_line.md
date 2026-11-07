# Player-visible racing line — plan (not built)

Show the racing line the bots ride (`NPCRacingLine`) to players during a race, using the
`RacingLine` prop (`levels/assets/props/racing_line.tscn`).

## Decided

- **Scope:** only races with bots, so only when the line is already baked (`NPCRacersComponent.race_start`).
- **Network:** the server sends the baked points, and every peer sees the line the bots ride.
  Late joiners get it from `sync_to_peer`.
- **Colour:** the whole line changes colour with your speed, using the prop's existing
  `semantic_color` fade. Red when you're over the line's target speed, gold when you're
  within `WARN_RATIO` of it, otherwise blue.
- **Toggle:** a "Show racing line" setting, default on.

## Plan

### 1. `NPCRacingLine`: make it buildable without the navmesh

- `_init(is_closed, spacing)` only stores those two fields.
- `static func bake(...)` takes the current `_init` body (corridor → smooth → widen → fit →
  samples). The server calls it in place of `.new(...)`.
- `static func from_baked(points, corner_speed, is_closed, spacing)` builds a display-only copy:
  it fits the curve and copies the corner speeds. It has no curvature or road-room data, so bot
  code that calls `half_width_at` on it errors loudly.
- `get_points()` returns the curve's control points, which is what the server sends.

### 2. `NPCRaceManager`: "Player racing line" region, following the `rpc_spawn_npc` pattern

- When the bake lands, the server calls `rpc_show_racing_line.rpc(points, corner_speed, closed, spacing)`
  (reliable, call_local).
- `sync_npcs_to_peer` also sends the line to the late joiner, if it has been baked.
- `despawn_all_npcs` calls `rpc_hide_racing_line` to remove it.
- The handler instances `racing_line.tscn` under the level, where NPCs go, sets an identity
  global transform (see the CSG `path_local` quirk), and gives it the line's curve.
- `_process` runs on every peer and is display only:
  - It shows or hides the line from the `show_racing_line` setting.
  - It finds your offset on the line with `closest_offset`.
  - It compares `movement_controller.speed` with `profile_speed` from
    `braking_profile(bike_definition.brake_strength, 1.0)`, computed lazily once the local player exists.
- The line is freed with the level when a client disconnects mid-race, so `_process` checks
  `is_instance_valid`, with a comment explaining why.
- New export: `hud_manager`, for `local_player`. It gets wired in `main_game.tscn`.

### 3. `RacingLine` prop

- A one-line guard in the `semantic_color` setter that skips the update when the value hasn't
  changed. Without it, setting the colour every frame keeps restarting the fade.

### 4. Settings

- Add `"show_racing_line": true` to `SettingsManager.default_settings`.
- Add a checkbox on the Gameplay tab: `settings_menu_state.tscn`, `load_settings_into_ui`,
  `_settings_from_ui`, and `TAB_SETTING_KEYS[2]`.
- Add a `SHOW_RACING_LINE_LABEL` localization key.

### 5. Docs

- Add an Architecture.md note.

## Open

- **Strip offset:** the prop's polygon starts at the path and extends to one side, so the strip
  sits beside the line, not centred on it. Centre it?
- **Height:** the points sit at navmesh height and the strip is thin, so it may sink into the road
  or float. Check in a playtest.
- **Crossovers:** `closest_offset` searches the whole curve, so where the track crosses itself
  the colour can jump to the other pass. Tracking from the last offset (like `track_offset`)
  avoids that, but needs a reseed after respawn. Left out for now.
- **Target speed:** it comes from `corner_grip`, a bot tuning value, so it may run cautious or
  aggressive for players.
