# Customization Garage POC — Spec (WIP)

> Delete this file once the garage ships and its content lives in Skins.md, FreeRoamActivity.md and
> Architecture.md.

## Goal

Replace the card-grid Customize menu with a GTA V–style garage: the bike + rider sit in a real 3D
scene and a list UI edits them live. Same garage in the main menu (as a level) and in free roam (as a
`FreeRoamActivity`). Bikes and characters cost money; colors are free.

Success:

- Main / Play / Lobby → Customize opens the 3D garage; Back saves and returns.
- Host launches while a client is in the garage → client's edits save, the launched level loads.
- Free roam: ride into the garage bay, pick it from the event picker, edit, leave → every peer sees
  the new bike/rider.
- Buying deducts money and unlocks the item for every loadout; can't buy what you can't afford.
- `give_money <amount>` console command.

## Decisions

| Topic | Decision |
| --- | --- |
| Loadouts | Min 1, max 8. No "default bikes always available" rule. |
| Starting state | $15,000. One loadout: naked + clanker, both owned. |
| Prices | mini $3,000 · naked $9,000 · sport $12,000 · every character $1,000 |
| Ownership | Unlock once, globally. Keyed by the skin definition's res path. Price 0 = owned by default. |
| Colors | Free. Godot `ColorPicker` per unique slot + shared preset swatches. Replaces `ColorMod` for players (NPCs keep `ColorMod`). |
| Character variants | `biker_red/blue`, `clanker_red/blue` deleted; their colors become presets. |
| Pause menu | Customize button removed. Mid-game you use the free-roam garage. |
| Hotkeys 1–8 | Swap the whole loadout (bike + character). |
| Tab input | New `ui_tab_prev` / `ui_tab_next` (LB/RB + Q/E), routed to every menu. |
| Stats bars | Not now. |

## §1 Data model

### `Loadout` (new Resource, `resources/player/loadout.gd`)

```
name: String
bike: BikeSkinDefinition             # base + colors
character: CharacterSkinDefinition   # null = profile default
```

`PlayerDefinition`:

- `loadouts: Array[Loadout]`, `active_loadout_index`, `default_character: CharacterSkinDefinition`.
- `bike_skin` getter → `active loadout.bike`. `character_skin` getter →
  `active loadout.character if set else default_character`. Existing callers (SpawnManager,
  GamemodeManager, ItemManager, InputStateManager, lobby) only use these two, so they don't change.
- `to_dict()` ships the full character dict (not just `character_skin_res`) so custom colors sync.

### Colors

- `BikeSkinDefinition.colors: Array[Color]`, one per **unique** slot. `BikeSkin` applies them before
  mods. `to_dict()` / `from_dict()` carry them next to `mod_paths`.
- Defaults come from the bike scene's `SkinSlot.color`s via new `SkinColor.get_unique_slot_colors()`,
  so "required + defaulted" always matches the mesh.
- `CharacterSkinDefinition.colors` already exists and serializes.
- `SKIN_COLOR_PRESETS: Array[Color]` in `utils/constants.gd` = the 4 deleted variant colors + the
  colors in `resources/bikes/mods/color_mods/`.

### Ownership + money

- `@export var price: int` on `BikeSkinDefinition` and `CharacterSkinDefinition`.
- `owned: Array[String]` (res paths) under the existing `"progression"` save key — not networked,
  peers don't need your inventory. `money` stays on `PlayerDefinition`.
- `SaveManager`: `is_owned(path)`, `purchase(path, price) -> bool`, and the `give_money <amount>`
  console command (always alive, owns the data).
- `_seed_default_loadouts()` → one `Loadout{naked, character = null}`, `default_character =
  clanker_default`, owned = [naked, clanker], money = 15000 (from `default_player_definition.tres`).

### Migration (`PlayerDefinition.from_dict`, existing legacy branch)

- Old `loadouts: [bike dict]` → `Loadout{name = bike.skin_name, bike, character = null}`.
- Old `character_skin_res` → `default_character`. Deleted variant paths map to their base def with
  the variant's color written into `colors`.
- Everything referenced by a migrated save is granted as owned.

### Variant deletion — repoint first

`npc_rider_entity.tscn`, `test_01_level.tscn` (×2), `default_player_definition.tres`,
`player_definition.gd` fallback paths → `clanker_default` / `biker_default`. NPC riders lose those 4
recolors (they scan the skins dir).

## §2 `GarageUI` (GTA-style list)

```
┌──────────────────────────────┐                      $15,000
│ PROFILE │ Loadout 1 │ Loadout 2 │ + │   ← tabs (LB/RB, Q/E, click)
├──────────────────────────────┤
│ BIKE                    3 / 5│
│ * Naked                 OWNED│   ← * + bold = current choice
│   Mini                 $3,000│   ← focused/hovered row = live preview
│   Sport               $12,000│
├──────────────────────────────┤
│ Mid-weight naked bike.       │
└──────────────────────────────┘
```

Page tree (stack; Back pops, Back at root exits):

- **Profile:** Username · Character ▸ · Character Colors ▸
- **Loadout N:** Name · Bike ▸ · Bike Colors ▸ (one row per unique slot) · Character ▸ ("Profile
  default", then list) · Character Colors ▸ (only when overridden) · Set Active · Delete (disabled
  on the last loadout)
- **`+` tab:** new loadout copied from the active one (cap 8), jumps to it.

Behavior:

- Focus **or mouse hover** previews (`mouse_entered` → `grab_focus()`, one path through
  `focus_entered`). Leaving a list reverts the preview to the real selection.
- Accept: owned → apply. Unowned → confirm "Buy X for $N?" → purchase + apply. Unaffordable →
  price in red, not selectable.
- Color rows open a `ColorPicker` side panel with `SKIN_COLOR_PRESETS`. `color_changed` previews
  live; closing applies.
- Edits + purchases mutate the in-memory `PlayerDefinition`. `commit()` does one
  `save_manager.update_save("player_definition", …, true, true)` — one lobby push, one skin sync.

Units:

- `GarageUI` (Control) — page stack + edits. Takes a `SaveManager`. Emits
  `preview_changed(bike_def, char_def)`. `commit()`.
- `GarageRow` (Button) — label, `*`, price/OWNED.
- `GarageSet` (Node3D) — listens to `preview_changed`, rebuilds a local `BikeSkin` + `CharacterSkin`
  on `%PreviewSpot`, slow turntable. Preview only — no camera, no gameplay.

Deleted: `loadout_card`, `new_loadout_card`, `character_card`, the old Customize UI tree.

### Tab input (all menus)

- `ui_tab_prev` / `ui_tab_next` actions (LB/RB + Q/E).
- `InputStateManager`'s `IN_MENU` branch routes them to `current_state.on_tab_key_pressed(dir)`, like
  `ui_cancel` → `on_cancel_key_pressed()`.
- `MenuState.on_tab_key_pressed` is a no-op default; tricks + help cycle their `TabContainer`; the
  garage cycles its tabs.

## §3 Hosts + flow

### Menu: `CustomizeMenuState` (thin host)

- `Enter`: `level_manager.spawn_level(GARAGE_LEVEL, IN_MENU)`, show `GarageUI`, wire
  `preview_changed` → the level's `GarageSet`. New `level_manager` export.
- Back at root: `commit()` → `spawn_menu_level()` → return state.
- `Exit`: `commit()` only. Never spawns a level — on launch, `spawn_level()` already freed the garage
  and `switch_to_pause_menu()` is what called `Exit`.
- Pause loses its Customize button + `customize_menu_state` export.
- `GARAGE_LEVEL` (`levels/menu_levels/garage/garage_level.tscn`): `LevelDefinition`,
  `no_player_spawn_needed`, instances the same `garage.tscn` prop used in free roam. The menu host
  uses that bay's `%Camera3D` + `GarageSet` (its start circle is inert outside free roam), so the
  garage is designed once. Added to `LevelName`, `possible_levels`, `level_name_map`.

### Scenes (graybox, ready to dress)

- `levels/components/garage/garage_set.tscn` — `%PreviewSpot` > `%BikeSkin`, `%CharacterSkin`;
  key light.
- `levels/components/interactable/garage_bay.tscn` — `%BikeSpot` > `%GarageSet`, `%Camera3D`,
  `%PlayerStartCircle`. Gets the `GarageActivity` script during implementation.
- `levels/components/garage/garage.tscn` — the building (`THE_GARAGE` sign) + `Bay1/GarageBay`.
  Placed in `stunt_track_01`.
- `levels/menu_levels/garage/garage_level.tscn` — `LevelDefinition` + `garage.tscn`.

### Free roam: `GarageActivity extends FreeRoamActivity`

Scene: `levels/components/interactable/garage_bay.tscn`, inside `garage.tscn` (in `stunt_track_01`).
Localization keys `GARAGE_EVENT_NAME` / `GARAGE_EVENT_DESC` for the picker (mirrors `FUELUP_EVENT_*`).

- Uses the lifted base session (below).
- `_on_session_start`: hide the local `PlayerEntity`, `hud_manager.go_to_garage_hud(self)`.
  `GarageHUDState` holds a `GarageUI`, `@export save_manager`, wires `preview_changed` → the bay's
  `GarageSet`.
- Back at root → `end()` + `finished`. Pause → Cancel Event → `end()`. `end()` calls `commit()`.
- `server_end`: base unfreeze only. `get_result()` returns `0.0`.
- Live sync is already there: commit → `LobbyManager._push_player_metadata` →
  `_sync_lobby_players` → `lobby_players_updated` → `SpawnManager._on_lobby_players_updated` →
  `update_skins` on every peer.

### Lifted `FreeRoamActivity` base

Today ~30 lines of session plumbing live in `FuelUpMinigame`. Move to the base:

- **Server:** default `server_start` = park at `%BikeSpot` (`respawn_player_in_place`) + freeze.
  Default `server_end` = unfreeze. Fuel-up overrides `server_end` for boost and calls `super`.
- **Client:** `begin()` stores managers, waits for `player.respawned`, then sets the camera override,
  enters `IN_MINIGAME` (re-asserted on `input_state_changed`), calls `_on_session_start()`.
  `end()` undoes it (safe before the teleport lands), calls `_on_session_end()`.
- Base requires `%Camera3D`, `%BikeSpot`, `%PlayerStartCircle`.

### Camera override (`CameraController`)

Replaces `FuelUpMinigame._process`'s `camera.current = true` every frame.
`set_override_cam(cam)` / `clear_override_cam()`; while set, `switch_to_cam()` (called by respawn,
the cam-switch key, settings reload, `force_tps`) makes the override current instead. Clearing
restores `current_cam_mode`.

## Docs

- New `planning_docs/FreeRoamActivity.md`: lifecycle, server/client split, how to add one, fuel-up +
  garage as examples. `GamemodeSystem.md`'s entry shrinks to a link.
- `Skins.md`: Loadout, colors, ownership; drop the stale "bike `colors`" claim and ColorMod-for-players.
- `Architecture.md`: garage + tab input.

## Testing

- Extend `utils/validation/serialization_checks.gd`: Loadout roundtrip, bike `colors`, legacy save
  migration, deleted-variant migration.
- Manual playtest (human):
  1. Main menu garage: tabs via LB/RB + Q/E + click, hover previews, buy, can't buy unaffordable,
     back saves.
  2. Lobby client in garage when host launches → edits saved, correct level loads.
  3. Free roam garage in MP: other peer sees the new bike/rider after you leave.
  4. Pause → Cancel Event in the garage saves and hands back.
  5. Hotkeys 1–8 swap bike + rider.
  6. Fuel-up still works after the base lift (camera, cursor, unpause, cancel).
  7. `give_money 5000`.

## Open

- None. First garage lives in `stunt_track_01`.
