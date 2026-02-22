# Plan: CharacterSkinDefinition Resource with Editor Save Button

## Goal

Create a resource-based system for storing CharacterSkin configuration (mesh, colors, marker positions) with a visual editing workflow using a "save to resource" button.

## Design Decisions

- Marker positions are **local/relative** to the CharacterSkin origin
- Workflow: Edit markers in 3D viewport → press save button → values persist to `.tres`

## Files to Create/Modify

### 1. Create: `resources/entities/player/character_skin_definition.gd`

```gdscript
@tool
class_name CharacterSkinDefinition extends Resource

## The SkinColor scene to instantiate
@export var mesh_res: PackedScene:
    set(value):
        if value:
            var instance = value.instantiate()
            assert(instance is SkinColor, "Wrong scene type!")
            instance.free()
        mesh_res = value

## Primary color (use TRANSPARENT to skip)
@export var primary_color: Color = Color.TRANSPARENT

## Secondary color - only used if mesh has_secondary
@export var secondary_color: Color = Color.TRANSPARENT

## Marker positions
@export_group("Markers")
@export var back_marker_position: Vector3 = Vector3.ZERO
@export var back_marker_rotation_degrees: Vector3 = Vector3.ZERO
```

### 2. Modify: `entities/player/characters/scripts/character_skin.gd`

```gdscript
@tool
class_name CharacterSkin extends Node3D

@export var skin_definition: CharacterSkinDefinition:
    set(value):
        skin_definition = value
        if Engine.is_editor_hint() and is_node_ready():
            _apply_definition()

@export_tool_button("Save Markers to Resource") var save_markers_btn = _save_markers_to_resource
@export_tool_button("Load Markers from Resource") var load_markers_btn = _load_markers_from_resource

const HEIGHT: float = 2.0

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var mesh_node: Node3D = %MeshNode
@onready var back_marker: Marker3D = %BackAccessoryMarker

var mesh_skin: SkinColor


func _ready():
    _apply_definition()


func _apply_definition():
    spawn_mesh()
    set_mesh_colors()
    _load_markers_from_resource()


func set_marker_positions():

    back_marker.position = skin_definition.back_marker_position
    back_marker.rotation_degrees = skin_definition.back_marker_rotation_degrees

func _load_markers_from_resource():
    set_marker_positions()

func _save_markers_to_resource():
    skin_definition.back_marker_position = back_marker.position
    skin_definition.back_marker_rotation_degrees = back_marker.rotation_degrees

    var err = ResourceSaver.save(skin_definition)
    if err == OK:
        print("CharacterSkin: Saved marker positions to ", skin_definition.resource_path)
    else:
        push_error("CharacterSkin: Failed to save resource, error: ", err)


func set_mesh_colors():
    if skin_definition.primary_color != Color.TRANSPARENT:
        mesh_skin.update_primary_color(skin_definition.primary_color)
    if mesh_skin.has_secondary and skin_definition.secondary_color != Color.TRANSPARENT:
        mesh_skin.update_secondary_color(skin_definition.secondary_color)


func spawn_mesh():
    for child in mesh_node.get_children():
        child.queue_free()
    mesh_skin = skin_definition.mesh_res.instantiate()
    mesh_node.add_child(mesh_skin)

    scale_to_height(mesh_skin, HEIGHT)

   	# NOTE - retarget AnimationMixer => Root Node to new mesh
    anim_player.root_node = mesh_skin.get_path()
    anim_player.play("Biker/reset")


# ... keep existing scale_to_height and get_combined_aabb functions ...


func _get_configuration_warnings() -> PackedStringArray:
    var issues = []
    if skin_definition == null:
        issues.append("skin_definition must be set")
    return issues
```

## Additional Considerations

- Uses `@export_tool_button` for proper editor buttons (Godot 4.x feature)
- `ResourceSaver.save()` writes to disk immediately
- Works in editor due to `@tool` and `Engine.is_editor_hint()` checks
