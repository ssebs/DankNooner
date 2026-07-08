# Minimap HUD

> Client-side, visual-only top-down minimap with racer blips. No netfox/RPCs.

## Goal

A corner minimap on the player HUD showing a live top-down camera view of the
track that follows the local player, with colored dots for every racer:

- **White** — self (local player)
- **Blue** — other human players (`PlayerEntity`)
- **Purple** — NPCs (`NPCRiderEntity`)

Orientation is **heading-up**: the map rotates so the local player always faces
up.

## Scope / non-goals

- Purely client-side and visual. Reads the world passively — no sync, no RPCs.
- Only the **local** player's HUD runs it (mirrors `is_local_client` HUD gating).
- No blip heading/shape — plain filled circles. Self is white so it's findable.
- Does **not** touch `NPCRiderEntity`, `player_entity.gd` logic, the main
  camera, gamemodes, or `NPCRaceManager`.

## Components

### `Minimap` (`player/controllers/minimap/minimap.gd` + `.tscn`)

`class_name Minimap extends Control` — instanced into the HUD in
`player_entity.tscn`, corner-anchored square (~220x220).

Scene tree:

```
Minimap (Control)
 ├─ SubViewportContainer (stretch = true)
 │   └─ SubViewport
 │       └─ Camera3D (orthographic, top-down)   # %MinimapCamera
 └─ DotOverlay (Control)                         # %DotOverlay, draws blips
```

Key setup:

- `SubViewport.world_3d = get_viewport().world_3d` so it renders the **actual
  live track**, not an empty world.
- Camera3D: `projection = ORTHOGONAL`, exported `zoom` (ortho `size`) and
  `height` (metres above player). Dormant until `activate()`.

Exports:

- `@export var zoom: float` — camera ortho size (world units across the view).
- `@export var height: float` — camera height above the player.

API:

- `activate(local_player: PlayerEntity)` — stores the local player ref, enables
  the SubViewport rendering, starts processing. Called from
  `HUDController.show_hud()` (only runs on the local client).

Per-frame (`_process`), only when active:

- Position `MinimapCamera` at `local_player.global_position + Vector3.UP * height`,
  looking straight down.
- Set camera yaw to the local player's heading (heading-up).
- `DotOverlay.queue_redraw()`.

`DotOverlay._draw()`:

- For each racer in the `"Racers"` group (`UtilsConstants.GROUPS["Racers"]`):
  - `color = white` if `racer == local_player`, `purple` if
    `racer is NPCRiderEntity`, else `blue`.
  - `var p := minimap_camera.unproject_position(racer.global_position)` →
    viewport pixels; because `SubViewportContainer` stretches the viewport 1:1
    to the control, `p` maps directly to overlay coords.
  - Skip if `p` falls outside the overlay rect; otherwise `draw_circle(p, r, color)`.

### `HUDController` change

- Add `@onready var _minimap: Minimap = %Minimap`.
- In `show_hud()`, call `_minimap.activate(player_entity)`.
- Minimap defaults to inactive, so remote player HUDs (`hide_hud()`) never run it.

## Verification

- Run a race with NPCs. Minimap shows the live track from above, spinning
  heading-up as you steer. Self = white dot centered-ish, NPCs = purple,
  any other humans = blue. Dots track their entities. Remote clients see their
  own local view; no minimap camera runs for non-local player instances.
