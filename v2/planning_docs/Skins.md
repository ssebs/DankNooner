# Skin System

The skin system allows runtime color customization of character and bike meshes using a slot-based approach. `BikeSkinDefinition` also stores per-bike rider pose, wheel markers, and physics/gearing/trick tuning.

## Overview

- **SkinSlot** - Resource defining a single color slot configuration
- **SkinColor** - Node3D that manages multiple SkinSlots on a mesh
- **SkinDefinition** - Resources storing colors + per-bike data (CharacterSkinDefinition, BikeSkinDefinition)

## Components

### SkinSlot

Resource at `components/skin_slot.gd`:

| Property                | Type               | Description                                                     |
| ----------------------- | ------------------ | --------------------------------------------------------------- |
| `color`                 | Color              | The color to apply                                              |
| `use_standard_material` | bool               | If true, uses StandardMaterial3D; if false, uses ShaderMaterial |
| `surface_index`         | int                | Which mesh surface to override (for multi-material meshes)      |
| `standard_material`     | StandardMaterial3D | Material used when `use_standard_material = true`               |
| `shader_material`       | ShaderMaterial     | Material used when `use_standard_material = false`              |

### SkinColor

Node3D at `components/skin_color.gd`:

| Property | Type                  | Description                                                  |
| -------- | --------------------- | ------------------------------------------------------------ |
| `slots`  | Array[SkinSlot]       | The slot configurations                                      |
| `meshes` | Array[MeshInstance3D] | Corresponding meshes for each slot (must match slots length) |

**Methods:**

- `update_slot_color(index: int, color: Color)` - Update a specific slot
- `update_all_colors(colors: Array[Color])` - Update all slots at once

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
6. Make sure the Resource is Local to Scene in the SkinColor scene!

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

`ColorMod` (`resources/bikes/mods/color_mod.gd`) overrides slot colors. Set `colors: Array[Color]` — use `Color.TRANSPARENT` to skip a slot (same convention as `BikeSkinDefinition.colors`).

Color variants are standalone `.tres` files under `resources/bikes/skins/color_mods/`. Example: `sport_black_color_mod.tres` replaces the old `sport_black_skin_definition.tres` — add it to a `BikeSkinDefinition.mods` array to apply the black color on top of any base definition.

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

> `BikeSkinDefinition` save/load + dict serialization is still TODO (see comment in source); `CharacterSkinDefinition` has both.

## Serialization

`CharacterSkinDefinition` supports JSON serialization via `DictJSONSaverLoader`:

```gdscript
var data: Dictionary = skin_definition.to_dict()
skin_definition.from_dict(data)
```

Colors are serialized as individual dictionaries with r/g/b/a components.
