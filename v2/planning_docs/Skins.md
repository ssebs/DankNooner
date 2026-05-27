# Skin System

The skin system allows runtime color customization of character and bike meshes using a slot-based approach. `BikeSkinDefinition` also stores per-bike rider pose, wheel markers, and physics/gearing/trick tuning.

## Overview

- **SkinSlot** - Resource defining a single color slot configuration
- **SkinColor** - Node3D that manages multiple SkinSlots on a mesh
- **SkinDefinition** - Resources storing colors + per-bike data (CharacterSkinDefinition, BikeSkinDefinition)

## Components

### SkinSlot

Resource at `components/skin_slot.gd`. Pure data spec — runtime state lives on `SkinColor`.

| Property                | Type               | Description                                                     |
| ----------------------- | ------------------ | --------------------------------------------------------------- |
| `color`                 | Color              | Default color baked into the runtime material at spawn          |
| `use_standard_material` | bool               | If true, uses StandardMaterial3D; if false, uses ShaderMaterial |
| `surface_index`         | int                | Which mesh surface to override (for multi-material meshes)      |
| `standard_material`     | StandardMaterial3D | Material used when `use_standard_material = true`               |
| `shader_material`       | ShaderMaterial     | Material used when `use_standard_material = false`              |

Helpers: `make_runtime_material()` returns a fresh duplicate of the configured material; `apply_color_to(mat, color)` writes a color into a runtime material (albedo for standard, `replacement_color` shader param for shader).

### SkinColor

Node3D at `components/skin_color.gd`. Owns the per-instance runtime materials, so a single `SkinSlot` resource can safely drive multiple meshes — and shared slot resources don't leak state across `SkinColor` instances.

| Property | Type                  | Description                                                                        |
| -------- | --------------------- | ---------------------------------------------------------------------------------- |
| `slots`  | Array[SkinSlot]       | Slot palette. The **same** SkinSlot may appear at multiple positions               |
| `meshes` | Array[MeshInstance3D] | Mesh per slot-position (must match slots length). Different positions ⇒ different mesh/surface, even if the slot resource is the same |

On `_ready`, each position duplicates its slot's material, assigns it to `meshes[i].surface_override(slot.surface_index)`, and stores the material in a private per-position array.

**Methods:**

- `update_slot_color(index: int, color: Color)` — applies `color` to **every** position whose slot ref matches `slots[index]`. This is what makes "one slot drives N meshes" work.
- `update_all_colors(colors: Array[Color])` — palette update with two modes:
  - `colors.size() == 1`: broadcast that single color to every unique slot (a 1-color mod paints every mesh on a 2-slot bike).
  - `colors.size() >= 2`: pair `colors[i]` → i-th **unique** slot (in order of first appearance), truncated to `min(colors.size(), unique_slots.size())`. So a 2-color mod on a bike whose `slots = [A, A]` uses only `colors[0]`; on `slots = [A, B]` it gives slot A = colors[0], slot B = colors[1].

## Creating a New SkinColor Scene (skin scene)

### For Textured Meshes (Shader-Based)

1. Import model to Godot, ensure textures are exported
2. Edit the albedo/diffuse texture in Photoshop/GIMP:
   - **Select > Color Range** - pick the area to make dynamic
   - **Edit > Fill** with `#FF00FF` (magenta)
   - This magenta color is what the shader replaces at runtime
3. Save the modified texture
4. Open `resources/shaders/skin_color.tres`, Save As new material
5. Update the textures on the new material for your mesh
6. Create inherited scene from the `.glb`, save to appropriate folder
7. Attach `SkinColor` script to the root node
8. Configure `slots` and `meshes` arrays (see below)
9. Save the scene

### For Untextured Meshes (Standard Material)

1. Create inherited scene from the model
2. Attach `SkinColor` script to root
3. Create SkinSlot resources with `use_standard_material = true`
4. Assign a `StandardMaterial3D` to each slot (duplicated at runtime)
5. The slot's color will set the material's `albedo_color`

(`resource_local_to_scene` on the slot SubResources is no longer required — `SkinColor` owns the runtime materials per-instance.)

### Single Slot, Multiple Meshes

To make one color drive several meshes, list the **same** SkinSlot resource at multiple positions in `slots` and put the corresponding `MeshInstance3D` at each matching position in `meshes`. Example (`mini_bike.tscn`): `slots = [A, A]`, `meshes = [Frontfender, PaintedBody]` — a single-color mod paints both meshes; `update_slot_color(0, c)` propagates to both. Use this when you want one configurable color across visually distinct meshes.

### Configuring SkinSlots in Inspector

1. Set `slots` array size to number of color slots needed
2. For each slot index, create a new `SkinSlot` resource inline:
   - Set `color` (initial/default color)
   - Set `use_standard_material` based on your material type
   - Set `surface_index` if targeting a specific surface on multi-material meshes
   - Assign either `standard_material` or `shader_material`
3. Set `meshes` array to same size as slots
4. Drag the `MeshInstance3D` node for each slot into the corresponding array index

## Character Skin System

`CharacterSkin` (scene) displays a `CharacterSkinDefinition` (resource).

### CharacterSkinDefinition

Resource at `resources/player/character_skin_definition.gd`:

| Property                       | Type         | Description                           |
| ------------------------------ | ------------ | ------------------------------------- |
| `skin_name`                    | String       | Name for saving to disk               |
| `mesh_res`                     | PackedScene  | The SkinColor scene to instantiate    |
| `colors`                       | Array[Color] | Slot colors (use TRANSPARENT to skip) |
| `back_marker_position`         | Vector3      | Accessory marker position             |
| `back_marker_rotation_degrees` | Vector3      | Accessory marker rotation             |

### Creating a New Character Skin

1. Open `character_skin.tscn`
2. Create new `CharacterSkinDefinition` resource in inspector
3. Set `skin_name`, assign `mesh_res` (must be a SkinColor scene)
4. Set `colors` array with desired slot colors
5. Save resource as `resources/player/skins/{skin_name}_default_skin_definition.tres`
6. Move `BackAccessoryMarker` to correct position/rotation in 3D viewport
7. Click **Save Markers to resource** button in inspector
8. Save the skin resource

### Creating Color Variants

1. Load existing skin definition
2. Change `skin_name` to new variant name (e.g. `biker_red`)
3. Modify entries in `colors` array
4. Save As -> `resources/player/skins/{skin_name}_{color}_skin_definition.tres`

## Bike Skin System

`BikeSkin` (scene) displays a `BikeSkinDefinition` (resource). Unlike characters, the bike definition is the **single source of truth for per-bike tuning** — visuals, collision, rider pose, wheel markers, gearing, physics, and trick limits all live here.

### BikeSkinDefinition

Resource at `resources/bikes/bike_skin_definition.gd`. Grouped in the inspector:

**Mesh** — `mesh_res`, `mesh_position_offset`, `mesh_rotation_offset_degrees`, `mesh_scale_multiplier`, `colors`

**Mods** — `mods: Array[BikeMod]` — applied after base colors at spawn (see [Mods](#mods) below)

**Collision** — `collision_shape`, `collision_position_offset`, `collision_rotation_offset_degrees`, `collision_scale_multiplier`

**Markers** — `seat_marker_position`, `front_wheel_ground_position`, `rear_wheel_ground_position`, `front_wheel_front_position`, `rear_wheel_back_position`, `training_wheels_marker_*`. Wheel positions feed raycasts (`PlayerEntity._init_raycasts`) and the wheelie/stoppie pivot arc.

**Rider Pose** — chest/head/magnet/hand/foot positions+rotations and arm/leg magnets. Hand and foot transforms are stored in **handlebar-parent / `bike_skin` local space**, so they survive steering rotation when reapplied each tick by `AnimationController._sync_targets_from_bike()`. Authored via the editor tools on `AnimationController` (Save Default Pose / Play Default Pose). See [AnimationController](./AnimationController.md).

**Animation** — `lean_multiplier`, `weight_shift_multiplier`

**Gearing** — `gear_ratios`, `num_gears`, `max_rpm`, `idle_rpm`, `stall_rpm`

**Physics** — `max_speed`, `acceleration`, `brake_strength`, `friction`, `engine_brake_strength`, `max_lean_angle_deg`, `lean_speed`, `turn_speed`, `lean_curve`, `steer_curve`

**Tricks** — `wheelie_balance_point_deg`, `max_wheelie_angle_deg`, `max_stoppie_angle_deg`, `wheelie_rpm_threshold`, `wheelie_balance_point_width_deg`, `rotation_speed`, `return_speed`

### Authoring Per-Bike Pose / Markers

IK markers and wheel markers are nodes on `PlayerEntity` (not the bike). To tune them for a specific bike:

1. Open `player_entity.tscn`, set `bike_definition` to the target `.tres`.
2. Drag IK markers (`IKTargets/*`) and wheel markers (`WheelMarkers/*`) in the viewport.
3. On `AnimationController`, click **Save Default Pose** — writes all transforms back into the `BikeSkinDefinition`.
4. Save the `.tres`.

`PlayerEntity._apply_rider_pose_from_definition()` reapplies these on init / bike swap.

## Mods

`BikeMod` (`resources/bikes/mods/bike_mod.gd`) is a base `Resource` with a single `apply(bike_skin: BikeSkin)` method. Subclass it to create composable overrides that stack on top of the base `BikeSkinDefinition`.

`BikeSkin._apply_definition()` calls `_apply_mods()` after `_set_mesh_colors()`, so mods always win over base colors.

### ColorMod

`ColorMod` (`resources/bikes/mods/color_mod.gd`) overrides slot colors via `SkinColor.update_all_colors(colors)`. The matrix:

| `colors.size()` | Bike unique slots | Result |
| --- | --- | --- |
| 1 | any N | Broadcast — every unique slot gets `colors[0]` (a `purple` mod paints both meshes of a 1-slot/2-mesh bike AND both surfaces of a 2-slot bike) |
| 2+ | 1 | Only `colors[0]` is used (extras are dropped) |
| 2+ | 2+ | Pair `colors[i]` → i-th unique slot in order of first appearance; truncated to `min(colors, unique_slots)` |

Color variants are standalone `.tres` files under `resources/bikes/mods/color_mods/`. Add a `ColorMod` to a `BikeSkinDefinition.mods` array to apply it on top of the base definition.

### Creating a Color Variant

1. Right-click in the FileSystem → **New Resource** → `ColorMod`, save to `resources/bikes/skins/color_mods/{name}_color_mod.tres`.
2. Set `colors` with the slot values you want to override (TRANSPARENT = skip).
3. In any `BikeSkinDefinition`, expand **Mods** and add the `ColorMod` to the array.

## Save/Load to User Directory

Skins can be saved/loaded from `user://skins/` for runtime customization:

**Save:**

- Click **Save skin to u:disk** button, or call `skin_definition.save_to_disk()`
- Files saved as `character_skin_{skin_name}.tres` or `bike_skin_{skin_name}.tres`

**Load:**

- Set `skin_name_for_loading_test` to a skin name found on disk
- Click **Load skin from u:disk**, or call `skin_definition.load_from_disk()`
- Loads into the inspector for editing

Both `CharacterSkinDefinition` and `BikeSkinDefinition` support save/load + dict serialization.

`BikeSkinDefinition.to_dict()` ships only the **base bike res:// path** + **mod res:// paths** — never `resource_path`, which can be a local `user://` file. `from_dict()` loads the base, applies the mods, then writes the rebuilt def to `user://skins/` on the receiving peer for caching. This is what enables customized bikes to sync across the lobby.

## Loadouts

A player owns a flat list of named bike loadouts (cap 8) on `PlayerDefinition.loadouts`, with `active_loadout_index` picking which is in use. `player_def.bike_skin` is a getter/setter that reads/writes `loadouts[active_loadout_index]` so existing callers (SpawnManager, lobby sync, etc.) keep working.

- First run: `SaveManager._seed_default_loadouts()` scans `res://resources/bikes/skins/` and creates one loadout per base bike, no mods.
- Legacy saves (pre-loadouts) are migrated by `PlayerDefinition.from_dict()` — the old single `bike_skin_dict` becomes `loadouts[0]`.
- The Customize menu (`menus/customize_menu/`) shows a grid of loadout cards (each rendering via `Thumbnail3D`) and an edit panel for name / base bike / color mod.

## Reusable 3D Thumbnail

`utils/components/thumbnail_3d.{tscn,gd}` is a `@tool` `SubViewportContainer` that renders any skin definition into its own `SubViewport` (transparent bg, own world 3D, dedicated camera + directional light).

| Export | Notes |
| --- | --- |
| `type: Type` | `BIKE` (default), `CHARACTER`, or `GENERIC`. Dispatches to `bike_skin.tscn` or `character_skin.tscn`; `GENERIC` leaves `spawn_parent` empty for external callers |
| `skin_definition: Resource` | `BikeSkinDefinition` for BIKE, `CharacterSkinDefinition` for CHARACTER, any Resource for GENERIC. Live-rebuilds in-editor when set |
| `camera_position`, `camera_look_at`, `camera_fov` | Per-instance camera framing — applied to the live `Camera3D` whenever changed |

Convenience runtime helper: `set_skin(type, def)`. The component is `@tool`, so opening `loadout_card.tscn` and setting `preview_definition` previews the bike inside the inspector.

Used by the customize menu's `LoadoutCard` scene to render each saved loadout.

## Forced Base Bike (events)

`GameModeEventDefinition.forced_base_bike: BikeSkinDefinition` is an optional per-event field. When the player enters an `EventStartCircle` whose event has it set, `GamemodeManager._rpc_transition_gamemode` calls `PlayerEntity.update_skins(forced_bike, …)` on every spawned player. Each peer runs this locally so all peers see the swap. On the transition back to free roam (no event context), `_restore_lobby_bikes()` reapplies each player's selected loadout from `lobby_manager.lobby_players`.

## Serialization

`CharacterSkinDefinition` supports JSON serialization via `DictJSONSaverLoader`:

```gdscript
var data: Dictionary = skin_definition.to_dict()
skin_definition.from_dict(data)
```

Colors are serialized as individual dictionaries with r/g/b/a components.
