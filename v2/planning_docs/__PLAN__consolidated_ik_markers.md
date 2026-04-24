# Consolidated IK Marker System

## Problem

Three marker owners (CharacterSkin, BikeSkin, PlayerEntity proxies) make the IK system confusing. Rider pose data in .tres files is copy-pasted between bikes instead of authored per-bike. Animations only work for the specific bike loaded in the editor.

## Design

### Marker Ownership

All 11 IK target markers live on `PlayerEntity/VisualRoot/IKTargets/`:

| Marker | Was | Now |
|--------|-----|-----|
| ButtTarget | BikeSkin SeatMarker | IKTargets child (NEW) |
| LeftHandTarget | PlayerEntity LeftHandProxy | IKTargets child (renamed) |
| RightHandTarget | PlayerEntity RightHandProxy | IKTargets child (renamed) |
| LeftFootTarget | PlayerEntity LeftFootProxy | IKTargets child (renamed) |
| RightFootTarget | PlayerEntity RightFootProxy | IKTargets child (renamed) |
| ChestTarget | CharacterSkin/IKTargets | IKTargets child (moved) |
| HeadTarget | CharacterSkin/IKTargets | IKTargets child (moved) |
| LeftArmMagnet | CharacterSkin/IKTargets | IKTargets child (moved) |
| RightArmMagnet | CharacterSkin/IKTargets | IKTargets child (moved) |
| LeftLegMagnet | CharacterSkin/IKTargets | IKTargets child (moved) |
| RightLegMagnet | CharacterSkin/IKTargets | IKTargets child (moved) |

**BikeSkin marker nodes removed**: SeatMarker, LeftHandleBarMarker, LeftPegMarker, all wheel Marker3Ds, TrainingWheelsModsMarker. Also `_load_markers_from_resource()` and `_save_markers_to_resource()`.

**BikeSkin keeps**: MeshNode, mesh spawning, colors, steering handlebar proxy (created from `bike_definition` values instead of marker nodes).

**CharacterSkin IKTargets node removed**: All marker children gone. IKController no longer has @export markers.

**All marker DATA stays in BikeSkinDefinition .tres** (fields unchanged):
- `seat_marker_position` — positions ButtTarget
- `left_handlebar_marker_position/rotation` — used by AnimationController for steering proxy + hand sync
- `left_peg_marker_position/rotation` — used by AnimationController for foot sync
- `front/rear_wheel_ground_position`, `front_wheel_front_position`, `rear_wheel_back_position` — used by AnimationController for pivot offset calcs
- `training_wheels_marker_position` — read when training wheels mod is implemented
- Rider pose: chest, head, magnet absolute positions + hand/foot rotations

### Init Flow

1. BikeSkin spawns mesh + colors, creates steering handlebar proxy from definition values
2. `PlayerEntity._init_ik()`:
   - Positions ButtTarget from `bike_definition.seat_marker_position`
   - Calls `IKController.set_targets()` with all 11 markers
   - Calls `_apply_rider_pose_from_definition()` to set absolute positions from BikeSkinDefinition
3. IKController creates FABRIK chains using PlayerEntity's markers

### Runtime Flow

- **Hands/feet**: `AnimationController._sync_targets_from_bike()` reads handlebar/peg positions from BikeSkinDefinition + steering proxy, copies to hand/foot targets each tick
- **Butt**: ButtTarget positioned from definition, IKController drives hips to it
- **Chest/head/magnets**: AnimationController applies procedural offsets (lean, pitch) relative to base positions
- **Wheel positions**: Read directly from `_bd.rear_wheel_ground_position` etc. for pivot calcs (no nodes needed)
- **Default pose**: stored as `_base_*` vars in `AnimationController.initialize()`

### Animation System

- AnimationPlayer animates markers directly (move markers in editor, see IK update live)
- "Save Default Pose" saves absolute positions to BikeSkinDefinition .tres
- At runtime: `marker.position = base_position + animation_offset`
- Same animation works across bikes because offsets are relative to each bike's default pose

### Editor Workflow

1. Set desired `bike_definition` on PlayerEntity
2. Click "Init IK from Bike" — markers positioned from definition values
3. Move markers in editor, see IK update in real time
4. Click "Save Default Pose" — saves absolute positions to BikeSkinDefinition .tres
5. Switch `bike_definition` → repeat for each bike

### Coordinate Space

Each bike mesh has different transforms (mini: Y=0.575 scale=0.35, naked: scale=0.85). Marker positions are in VisualRoot local space. BikeSkin local space = VisualRoot local space (identity transform), so same position values work. `_sync_targets_from_bike()` uses `global_transform` math for steering rotation. Per-bike authoring via the editor workflow ensures correct values regardless of mesh origin.

## Files Changed

| File | Change |
|------|--------|
| `player_entity.tscn` | Add IKTargets node under VisualRoot with all 11 markers. Remove old proxy markers. |
| `player_entity.gd` | Add @export for all 11 markers, update `_init_ik()` to pass all to IKController |
| `character_skin.tscn` | Remove IKTargets node and all children |
| `character_skin.gd` | Remove IKTargets-related code |
| `ik_controller.gd` | Remove @export magnets/chest/head, add `set_targets()` taking all 11 markers |
| `bike_skin.tscn` | Remove all Marker3D nodes (SeatMarker, HandleBarMarker, PegMarker, wheel markers) |
| `bike_skin.gd` | Remove marker @onready refs, `_load/_save_markers_from/to_resource()`. Update `_create_steering_handlebar_proxy()` to read from definition. |
| `animation_controller.gd` | Rename proxy→target refs, update sync + save/load to use definition values, offset-based animation |
| Sport/naked .tres files | Will need re-authoring with correct values per-bike (editor workflow) |
