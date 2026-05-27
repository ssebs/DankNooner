# Bike Loadout Save Slots — Design

Flat list of named bike loadouts (base bike + ColorMods). Players pick which loadout is active. Events can force a base bike and filter the picker to matching loadouts. Includes a reusable 3D thumbnail system used in the loadout picker.

## Scope

**In:**
- N bike loadouts per player (cap 8), each = base bike + ColorMod
- Pre-seeded default loadout per base bike on first run
- Reworked Customize menu with grid of loadout cards + edit panel
- Reusable `Thumbnail3D` component
- `forced_base_bike` field on gamemodes (filter only; consumers wired later)

**Out (deferred):**
- Per-bike mods beyond ColorMod
- Character skin slots
- Level icons / pre-baked images
- Unlock gating / progression

## Data Model

`PlayerDefinition`:

```gdscript
@export var loadouts: Array[BikeSkinDefinition] = []
@export var active_loadout_index: int = 0

# `bike_skin` becomes a getter: loadouts[active_loadout_index]
# Setter kept for compatibility (writes to loadouts[active_loadout_index]).
```

All readers of `player_def.bike_skin` (SpawnManager, lobby sync, BikeSkin spawn, etc.) keep working through the getter.

### Serialization

`PlayerDefinition.to_dict()`:
- Replace `bike_skin_dict` with `loadouts: Array[Dictionary]` (each via `BikeSkinDefinition.to_dict()`)
- Add `active_loadout_index: int`

`from_dict()`:
- If `loadouts` key present: rebuild each via `BikeSkinDefinition.from_dict()`, read `active_loadout_index`
- Else (legacy save with `bike_skin_dict` or `bike_skin_res`): wrap that single bike into `loadouts[0]`, set `active_loadout_index = 0`. Migration runs once on load; the next `save_save()` writes the new shape.

### First-Run Seeding

When `loadouts` is empty after load/migration:
- Scan `res://resources/bikes/skins/` (same logic as `customize_menu_state._scan_skin_dir`)
- For each base bike found, create a `BikeSkinDefinition` with `base_res_path` set and no mods
- Name = the skin's `skin_name`

Lives in `PlayerDefinition` or `SaveManager` — pick whichever keeps `PlayerDefinition` free of FS access. SaveManager is the better home.

## Customize Menu Rework

`menus/customize_menu/customize_menu_state.{gd,tscn}`.

Layout:
- **Left pane:** scrollable grid of loadout cards. Each card = `Thumbnail3D` + name label. Active card has a visual highlight. `+ New` tile at end (disabled when `loadouts.size() >= 8`).
- **Right pane:** edit panel for the selected card — Name (`LineEdit`), Base Bike (`OptionButton`), Color Mod (`OptionButton`), `Save`, `Delete`, `Set Active`.

Behavior:
- Selecting a card loads its values into the edit panel.
- `Save` writes the edit panel state back into `loadouts[selected_index]` and calls `save_manager.update_save("player_definition", player_def, true, true)`.
- `Delete` removes the loadout; if it was active, `active_loadout_index` clamps to 0. Deleting the last loadout is blocked (always need ≥1).
- `Set Active` sets `active_loadout_index` to selected, saves.
- `+ New` adds a default-configured `BikeSkinDefinition` (first base bike, no mods) named e.g. `"Loadout N"`, selects it.

Existing `_save_color_mod` becomes the per-loadout save path — same dup + take_over_path logic, just writes into the array slot.

Username field stays where it is (not per-loadout).

## Reusable 3D Thumbnail

`ui/components/thumbnail_3d.tscn` + `.gd`:

- `SubViewport` (transparent bg, own world 3d) + `Camera3D` + `DirectionalLight3D` + spawn parent
- API:
  ```gdscript
  func set_bike_loadout(def: BikeSkinDefinition) -> void
  ```
  Instantiates `BikeSkin` scene under spawn parent, calls `_apply_definition(def)`, frames the camera.
- Exposes the viewport texture for a `TextureRect` to display.
- v1 uses static rendering (one frame on set). No rotation/animation yet.

Generic enough to extend with `set_character_skin(def)` later without rework.

## Event-Forced Bikes

Add to `GameModeType` base:

```gdscript
@export var forced_base_bike: BikeSkinDefinition = null
```

Filter logic (lives in customize menu / loadout picker when shown in a forced-bike context):
- If `forced_base_bike` set, hide loadout cards whose `base_res_path != forced_base_bike.resource_path`.
- If zero matching loadouts: build a transient `BikeSkinDefinition` for that base (no mods, not saved), use it for the session.

No consumers are wired in v1 — the field is added and the filter helper exists, but no current gamemode sets it. This keeps the door open without dragging in gamemode rework.

## Touch List

| File | Change |
|---|---|
| `resources/player/player_definition.gd` | Add `loadouts`, `active_loadout_index`, `bike_skin` getter/setter, update `to_dict`/`from_dict` with migration |
| `managers/save_manager.gd` | First-run seeding helper (scan `res://resources/bikes/skins/`) |
| `menus/customize_menu/customize_menu_state.gd` | Rewrite around grid + edit panel; reuse `_scan_skin_dir`/`_scan_color_mods`/`_save_color_mod` |
| `menus/customize_menu/customize_menu_state.tscn` | New layout (left grid, right edit panel) |
| `ui/components/thumbnail_3d.{tscn,gd}` | New |
| `managers/gamemodes/game_mode_type.gd` (or base) | Add `forced_base_bike` export |
| `planning_docs/Skins.md` | Document loadouts + thumbnail |
| `localization/localization.csv` | New keys for menu labels |

## Verification

1. Fresh save (no `savegame.json`): customize menu shows one loadout per base bike, all selectable. → manual check
2. Legacy save (pre-loadouts): loads, becomes a single loadout, marked active. → manual check
3. Save → reload → loadouts and active index persist. → manual check
4. Multiplayer: peer joins, my active bike + mods render correctly on their client. → manual check (existing `BikeSkinDefinition.to_dict` path)
5. Cap: cannot add a 9th loadout. → UI disables `+ New`
6. Delete last loadout is blocked. → UI disables `Delete` when `loadouts.size() == 1`
7. Thumbnail renders the correct base bike + mod. → visual check
