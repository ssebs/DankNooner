# Skin System

The skin system allows runtime color customization of character and bike meshes using a slot-based approach.

## Overview

- **SkinSlot** - Resource defining a single color slot configuration
- **SkinColor** - Node3D that manages multiple SkinSlots on a mesh
- **SkinDefinition** - Resources storing color arrays for serialization (CharacterSkinDefinition, BikeSkinDefinition)

## Components

### SkinSlot

Resource at `entities/components/skin_slot.gd`:

| Property                | Type               | Description                                                     |
| ----------------------- | ------------------ | --------------------------------------------------------------- |
| `color`                 | Color              | The color to apply                                              |
| `use_standard_material` | bool               | If true, uses StandardMaterial3D; if false, uses ShaderMaterial |
| `surface_index`         | int                | Which mesh surface to override (for multi-material meshes)      |
| `standard_material`     | StandardMaterial3D | Material used when `use_standard_material = true`               |
| `shader_material`       | ShaderMaterial     | Material used when `use_standard_material = false`              |

### SkinColor

Node3D at `entities/components/skin_color.gd`:

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

Skins use a resource-based system: `CharacterSkin` (scene) displays a `CharacterSkinDefinition` (resource).

### CharacterSkinDefinition

Resource at `resources/entities/player/character_skin_definition.gd`:

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
5. Save resource as `resources/entities/player/skins/{skin_name}_default_skin_definition.tres`
6. Move `BackAccessoryMarker` to correct position/rotation in 3D viewport
7. Click **Save Markers to resource** button in inspector
8. Save the skin resource

### Creating Color Variants

1. Load existing skin definition
2. Change `skin_name` to new variant name (e.g. `biker_red`)
3. Modify entries in `colors` array
4. Save As -> `resources/entities/player/skins/{skin_name}_{color}_skin_definition.tres`

## Bike Skin System

Works identically to character skins: `BikeSkin` (scene) displays a `BikeSkinDefinition` (resource).

### BikeSkinDefinition

Resource at `resources/entities/bikes/bike_skin_definition.gd`:

| Property                       | Type         | Description                           |
| ------------------------------ | ------------ | ------------------------------------- |
| `skin_name`                    | String       | Name for saving to disk               |
| `mesh_res`                     | PackedScene  | The SkinColor scene to instantiate    |
| `colors`                       | Array[Color] | Slot colors (use TRANSPARENT to skip) |
| `mesh_position_offset`         | Vector3      | Mesh position adjustment              |
| `mesh_rotation_offset_degrees` | Vector3      | Mesh rotation adjustment              |
| `mesh_scale_multiplier`        | Vector3      | Mesh scale adjustment                 |
| `collision_shape`              | Shape3D      | Physics collision shape               |
| `training_wheels_marker_*`     | Vector3      | Accessory marker transforms           |

## Save/Load to User Directory

Skins can be saved/loaded from `user://skins/` for runtime customization:

**Save:**

- Click **Save skin to u:disk** button, or call `skin_definition.save_to_disk()`
- Files saved as `character_skin_{skin_name}.tres` or `bike_skin_{skin_name}.tres`

**Load:**

- Set `skin_name_for_loading_test` to a skin name found on disk
- Click **Load skin from u:disk**, or call `skin_definition.load_from_disk()`
- Loads into the inspector for editing

## Serialization

Both `CharacterSkinDefinition` and `BikeSkinDefinition` support JSON serialization via `DictJSONSaverLoader`:

```gdscript
# Save to dictionary
var data: Dictionary = skin_definition.to_dict()

# Load from dictionary
skin_definition.from_dict(data)
```

Colors are serialized as individual dictionaries with r/g/b/a components.
