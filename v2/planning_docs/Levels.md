# Levels

Stuff about levels

TODO - add info here!

## Level Preview Image

- Open the `LevelDefinition` Scene
- Create a new `Node`, attach `take_screenshot.gd` script to it
- PreSteps:
  - Click **⋮ Perspective**
  - Uncheck:
    - **View Gizmos**
    - **View Transform Gizmo**
    - **View Grid**
  - Check:
    - **View Information**
    - Change window for resolution to be **1280x720**
  - Uncheck:
    - **View Information**
- Place the viewport camera where you'd like it
- Click the new Node > Take screenshot
- A file exporer opens, rename the image to the level name (localization.csv's key name)
- Delete the node
- Add to the `level_img_map`
- Revert PreSteps to reenable gizmos
