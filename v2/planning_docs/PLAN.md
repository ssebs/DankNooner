# Color Mod Picker — Customize Menu — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Color Mod OptionButton to the customize menu that persists the player's chosen color mod per bike skin to disk.

**Architecture:** On save, duplicate the selected `BikeSkinDefinition`, set its `mods` array to the chosen `ColorMod` (or clear it for "None"), save the duplicate to `user://skins/bike_skin_{skin_name}.tres` via `ResourceSaver.save()`, and reload that path into `PlayerDefinition.bike_skin`. The `user://` resource path round-trips correctly through `PlayerDefinition.to_dict/from_dict`, and `BikeSkin._apply_mods()` at spawn picks up the mod automatically with no spawn-flow changes.

**Tech Stack:** Godot 4.6, GDScript, `ResourceSaver`, `ResourceLoader`, `DirAccess`

---

## Files

- **Modify:** `menus/customize_menu/customize_menu_state.gd`
- **Modify:** `menus/customize_menu/customize_menu_state.tscn`

---

### Task 1: Add Color Mod UI nodes to the scene

**Files:**
- Modify: `menus/customize_menu/customize_menu_state.tscn`

The new nodes go inside `UI/AspectContainer/MarginContainer/VBoxContainer2`, after the `CharacterSkinBtn` node (line 85), matching the exact pattern of the existing Bike/Character skin label+button pairs.

- [ ] **Step 1: Add `ColorModLabel` and `ColorModBtn` nodes**

In `menus/customize_menu/customize_menu_state.tscn`, insert after the `CharacterSkinBtn` node block (after line 85):

```
[node name="ColorModLabel" type="Label" parent="UI/AspectContainer/MarginContainer/VBoxContainer2" unique_id=1234567890]
layout_mode = 2
text = "Color Mod"

[node name="ColorModBtn" type="OptionButton" parent="UI/AspectContainer/MarginContainer/VBoxContainer2" unique_id=1234567891]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 4
size_flags_vertical = 4
mouse_default_cursor_shape = 2
```

> Use unique IDs that don't conflict with existing ones. Godot will assign real UIDs when you save the scene in the editor — it's fine to open the scene in the editor, add these nodes there, and save. The text content is what matters.

- [ ] **Step 2: Open scene in Godot editor and verify the nodes appear**

Open `menus/customize_menu/customize_menu_state.tscn` in the Godot editor. Confirm `ColorModLabel` and `ColorModBtn` appear below `CharacterSkinBtn` in the VBoxContainer2. Save the scene.

---

### Task 2: Wire `@onready` reference and add constants

**Files:**
- Modify: `menus/customize_menu/customize_menu_state.gd`

- [ ] **Step 1: Add `COLOR_MODS_DIR` constant and `color_mods` dict**

In `customize_menu_state.gd`, after line 8 (`const CHARACTER_SKINS_DIR`):

```gdscript
const COLOR_MODS_DIR := "res://resources/bikes/mods/color_mods/"
```

After line 22 (`var character_skins: Dictionary = {}`):

```gdscript
var color_mods: Dictionary = {}  # display_name -> res_path
```

- [ ] **Step 2: Add `@onready` reference for `color_mod_btn`**

After line 14 (`@onready var character_skin_btn`):

```gdscript
@onready var color_mod_btn: OptionButton = %ColorModBtn
```

---

### Task 3: Scan `color_mods/` and populate OptionButton

**Files:**
- Modify: `menus/customize_menu/customize_menu_state.gd`

- [ ] **Step 1: Add `_scan_color_mods()` function**

Add after `_scan_skin_dir()`:

```gdscript
func _scan_color_mods() -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(COLOR_MODS_DIR)
	if dir == null:
		DebugUtils.DebugErrMsg("Failed to open color_mods directory: %s" % COLOR_MODS_DIR)
		return result

	var is_exported := !OS.has_feature("editor")
	var extension := ".tres.remap" if is_exported else ".tres"

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(extension):
			var res_path := COLOR_MODS_DIR + file_name.replace(".remap", "")
			var display_name := (
				file_name.replace(extension, "").replace("_", " ").capitalize()
			)
			result[display_name] = res_path
		file_name = dir.get_next()
	dir.list_dir_end()
	return result
```

- [ ] **Step 2: Populate `ColorModBtn` in `_populate_skins()`**

In `_populate_skins()`, after the `character_skin_btn` population block, add:

```gdscript
	color_mods = _scan_color_mods()

	color_mod_btn.clear()
	color_mod_btn.add_item("None")
	for mod_name in color_mods.keys():
		color_mod_btn.add_item(mod_name)
```

- [ ] **Step 3: Run in editor and verify the OptionButton populates**

Enter Play mode, open the Customize menu. The Color Mod OptionButton should list "None" plus one entry per file in `resources/bikes/mods/color_mods/` (e.g., "Black Blue Color", "Red Color", etc.).

---

### Task 4: Load the active color mod selection on Enter

**Files:**
- Modify: `menus/customize_menu/customize_menu_state.gd`

The active mod lives in `player_def.bike_skin.mods`. We find the first `ColorMod` in that array, match its `resource_path` against the scanned `color_mods` dict values, and select the matching item.

- [ ] **Step 1: Add `_refresh_color_mod_selection()` function**

Add after `_select_option_by_value()`:

```gdscript
func _refresh_color_mod_selection(skin_def: BikeSkinDefinition):
	color_mod_btn.select(0)  # default: None
	if skin_def == null:
		return
	for mod in skin_def.mods:
		if not mod is ColorMod:
			continue
		for i in color_mod_btn.item_count:
			var display_name := color_mod_btn.get_item_text(i)
			if color_mods.get(display_name, "") == mod.resource_path:
				color_mod_btn.select(i)
				return
		break
```

- [ ] **Step 2: Call it from `_load_current_selections()`**

At the end of `_load_current_selections()`, after the two `_select_option_by_value` calls:

```gdscript
	_refresh_color_mod_selection(player_def.bike_skin)
```

- [ ] **Step 3: Run in editor and verify**

Enter Play mode with a saved player definition that already has a color mod (e.g., sport_default has `white_red_color` in its mods). Open Customize — the Color Mod button should pre-select "White Red Color". If no mod is saved, it should show "None".

---

### Task 5: Refresh color mod selection when bike skin dropdown changes

**Files:**
- Modify: `menus/customize_menu/customize_menu_state.gd`

When the user picks a different bike skin before saving, we reload the definition for that skin (checking `user://` first) and refresh the mod selection.

- [ ] **Step 1: Add `_on_bike_skin_changed()` handler**

Add after `_refresh_color_mod_selection()`:

```gdscript
func _on_bike_skin_changed(_idx: int):
	var bike_name := bike_skin_btn.get_item_text(bike_skin_btn.selected)
	var skin_def := load(bike_skins[bike_name]) as BikeSkinDefinition
	var user_path := "user://skins/bike_skin_%s.tres" % skin_def.skin_name
	if ResourceLoader.exists(user_path):
		skin_def = load(user_path)
	_refresh_color_mod_selection(skin_def)
```

- [ ] **Step 2: Connect and disconnect the signal in `Enter()` / `Exit()`**

In `Enter()`, after `_load_current_selections()`:

```gdscript
	bike_skin_btn.item_selected.connect(_on_bike_skin_changed)
```

In `Exit()`, after the existing disconnect calls:

```gdscript
	bike_skin_btn.item_selected.disconnect(_on_bike_skin_changed)
```

- [ ] **Step 3: Run in editor and verify**

Open Customize, switch the bike skin dropdown. Confirm the Color Mod dropdown updates to reflect that bike's saved mod (or "None" if no mod was saved for it).

---

### Task 6: Save the color mod selection

**Files:**
- Modify: `menus/customize_menu/customize_menu_state.gd`

On save, duplicate the `BikeSkinDefinition`, set its `mods`, save to `user://`, and reload the path into `player_def.bike_skin` before the existing `save_manager.update_save()` call.

- [ ] **Step 1: Replace `_on_save_pressed()` with the updated version**

Replace the entire `_on_save_pressed()` function:

```gdscript
func _on_save_pressed():
	var player_def := save_manager.get_player_definition()
	player_def.username = username_entry.text

	var bike_idx := bike_skin_btn.selected
	var char_idx := character_skin_btn.selected

	if bike_idx >= 0:
		var bike_name := bike_skin_btn.get_item_text(bike_idx)
		player_def.bike_skin = load(bike_skins[bike_name])

	if char_idx >= 0:
		var char_name := character_skin_btn.get_item_text(char_idx)
		player_def.character_skin = load(character_skins[char_name])

	_save_color_mod(player_def)

	save_manager.update_save("player_definition", player_def, true, true)
	UiToast.ShowToast(tr("SAVED_SETTINGS_LABEL"))
```

- [ ] **Step 2: Add `_save_color_mod()` helper**

Add after `_on_save_pressed()`:

```gdscript
func _save_color_mod(player_def: PlayerDefinition):
	var skin_def: BikeSkinDefinition = player_def.bike_skin
	var duplicate := skin_def.duplicate(true) as BikeSkinDefinition

	var mod_name := color_mod_btn.get_item_text(color_mod_btn.selected)
	if mod_name == "None":
		duplicate.mods.clear()
	else:
		var mod := load(color_mods[mod_name]) as BikeMod
		duplicate.mods = [mod] as Array[BikeMod]

	var user_path := "user://skins/bike_skin_%s.tres" % skin_def.skin_name
	ResourceSaver.save(duplicate, user_path)
	player_def.bike_skin = load(user_path)
```

- [ ] **Step 3: Run in editor and verify save + reload round-trip**

1. Open Customize, select "Sport Default" bike, pick "Red Color" mod, click Save. Toast appears.
2. Close and reopen Customize. Confirm "Red Color" is pre-selected.
3. Select a different bike (if available), save with "None". Reopen — confirm that bike shows "None".
4. Start a game session. Confirm the bike skin uses the selected color (visually).

- [ ] **Step 4: Verify the `user://` file was written**

In the Godot editor, open **FileSystem → user://** (or check `%APPDATA%/Godot/app_userdata/<project>/skins/` on Windows). Confirm `bike_skin_sport_default.tres` exists after saving.

---

## Self-Review Checklist

- Spec: data flow (open → read mods → select), save → duplicate → user://, bike-skin-change refresh — all covered. ✓
- Spec: "None" = index 0, display names from file name — covered in Task 3. ✓
- Spec: future slot-count filtering — documented in design, intentionally not implemented. ✓
- Type consistency: `color_mods: Dictionary`, `color_mod_btn: OptionButton`, `_refresh_color_mod_selection(skin_def: BikeSkinDefinition)`, `_save_color_mod(player_def: PlayerDefinition)` — consistent across all tasks. ✓
- `Array[BikeMod]` cast in `_save_color_mod` matches `BikeSkinDefinition.mods: Array[BikeMod]`. ✓
- Signal connect/disconnect both present in Enter/Exit. ✓
