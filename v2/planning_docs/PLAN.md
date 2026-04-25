# Color Mod Picker — Customize Menu

## Goal

Add a "Color Mod" `OptionButton` to the customize menu so players can choose a color mod per bike skin. The selection persists between sessions.

## Architecture

### Data flow

1. On menu open → `_load_current_selections()` reads `player_def.bike_skin.mods`, finds the first `ColorMod` in the list, matches its `resource_path` against the scanned mod dictionary, and pre-selects it in the OptionButton.
2. On save → duplicate `player_def.bike_skin`, set `mods = [selected_mod]` (or `[]` for "None"), save duplicate to `user://skins/bike_skin_{skin_name}.tres` via `ResourceSaver.save()`, reload that path into `player_def.bike_skin`, then call `save_manager.update_save(...)` as usual.
3. At spawn → no changes needed. `BikeSkin._apply_mods()` already reads from `skin_definition.mods` at spawn; the `user://` copy has the mod baked in.

### Why duplicate + save to user://

`res://` is read-only in exported builds. Duplicating the definition and saving to `user://` lets us persist the mod without mutating the shared resource. `PlayerDefinition.to_dict()` stores `bike_skin.resource_path`, so a `user://` path round-trips correctly through save/load.

### Color mod selection updates when bike skin changes

When the user picks a different bike skin in the OptionButton (before saving), the color mod OptionButton must refresh to show that bike's active mod. Logic: check if `user://skins/bike_skin_{skin_name}.tres` exists; if so, load it and read its `mods`; otherwise fall back to the res:// definition's `mods`. Connect to `bike_skin_btn.item_selected` in `Enter()` / disconnect in `Exit()`.

### Display names

File name without extension, underscores replaced with spaces, title-cased.
`black_red_color.tres` → `"Black Red Color"`. "None" is always index 0.

## Files Changed

- `menus/customize_menu/customize_menu_state.gd` — scan `color_mods/` dir, load/save selection, duplicate + save definition on save
- `menus/customize_menu/customize_menu_state.tscn` — add `ColorModLabel` (Label) + `ColorModBtn` (OptionButton)

`resources/player/player_definition.gd` — **no changes needed**.

## Future Constraints (not in scope now)

Color mods should eventually be filtered by how many color slots the selected bike skin supports (some bikes use 1 slot, some 2+). A `ColorMod` with 2 slot entries shouldn't appear for a 1-slot bike. A `slot_count` property on `BikeSkinDefinition` or `SkinColor` would enable this filtering.
