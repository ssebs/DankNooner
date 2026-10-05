# Importing

## Models

> Should be rigged like Mixamo! Quaternius rigs get converted in Blender first.

### Blender (Quaternius rigs)

- Open the source .glb in Blender (File > Import > glTF)
- Select the armature > Object Data > Pose > Rest Position
- Scripting tab > Open `quaternius_to_mixamo.py` > Run Script
  - Safe to re-run; renames bones to Mixamo, fixes hips/spine/feet/head, bakes the FBX scale
- File > Export > glTF 2.0 into the character's folder
  - Untick Animation

### Godot

- Drag the exported .glb to its folder in godot
- Double click .glb to open advanced import
- Materials Extract > Extract Once
  - Pick Folder
  - Import
- Double click .glb to open advanced import again
- Click Skeleton
  - Retarget > Create BoneMap
  - Click BoneMap > SkeletonProfileHumanoid
  - Change Skeleton Name => Skeleton
- Reimport

## Animation

- Download FBX to assets/anim/
- Right click in godot/filesystem >
- Retarget Mixamo Animations
- Add this new .res file to the animation library
