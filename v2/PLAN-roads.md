# PLAN: Marker-Based Track System

Replace the curve-based road (`levels/components/road_path.gd`) with a
**marker-driven track builder**, with per-segment runoff/walls whose material
and collision layers reuse the GrayBox preset system.

## Why

- **Banking via a real gizmo.** Curve3D banking is the `tilt` float array — awful
  to edit. A `Marker3D` control point banks by *rolling the node*; read its
  up-vector. Live, visual.
- **Properties live on the node.** Each control point carries its own runoff/wall
  config — dissolves the "how do I assign per-segment settings in the inspector"
  problem.
- **Per-segment material/collision is free.** Each segment generates its own
  `MeshInstance3D` + `StaticBody3D` child, so a different material or collision
  layer per segment is just a property on that generated node — no mesh
  surface-splitting to engineer.

## Current state (to be replaced)

- `levels/components/road_path.gd` — `@tool Path3D` that extrudes a road + runoff
  + wall strips from a `Curve3D` via `sample_baked_with_rotation`. Already has:
  `_build_flat_strip(off_a, off_b)`, `_build_wall_strip(off, height, skip)`,
  `_segment_boundaries()`, per-side runoff (width, material) + wall (height,
  material, skip-segments) exports.
- `levels/assets/graybox/graybox_staticbody.gd` — `GrayBoxColor` enum +
  `COLOR_VALUES` tint table + `apply_color()`; `.tscn` uses a triplanar
  `StandardMaterial3D` (kenney `texture_04`) and per-instance `collision_layer`.
- `levels/racetracks/racetrack_level_01.tscn` — uses curve `RoadPath` for the
  main `TrackPiece`, the `PitRoad`, and `GarageGround`.

## Target architecture

### `TrackPoint extends Marker3D` (@tool, class_name)

A control point. Its transform *is* the path data:
- **position** = where the track goes
- **roll the marker = banking** (builder reads `global_transform.basis.y` as up)

Exports (per-point / per-segment config; segment = this point → next):
- `straight: bool` — skip Catmull-Rom for this segment, lerp linearly (pit lane,
  straights).
- Left side: `left_runoff_width`, `left_runoff: SurfaceConfig`,
  `left_wall_height`, `left_wall: SurfaceConfig`.
- Right side: mirror.

Where `SurfaceConfig` bundles `{ material_preset, texture (optional override),
collision_layer }` — see Material & Collision below. (Start inline; promote to a
shared `RoadSegmentConfig` resource only if reuse across corners is wanted.)

### `Track extends Node3D` (@tool, class_name)

The builder. Collects ordered `TrackPoint` children and regenerates geometry.

Exports: `road_width` (default), `step`, `tension`, `closed`, default road
material/preset/collision layer, default `texture`.

Build algorithm:
1. Gather ordered `TrackPoint` children.
2. Sample the **whole** path once into a frame array `[(origin, basis), ...]`:
   - position via **Catmull-Rom** — `Vector3.cubic_interpolate(next, prev,
     next_next, t)` (passes through every point, no handles). `straight` points
     lerp linearly.
   - forward = path tangent; up = slerp of adjacent markers' up-vectors;
     right = up × forward. (Banking flows between corners.)
   - tag each sample with its segment index + interpolated config (lerp
     continuous values like runoff width; discrete values like material/layer
     switch at the boundary).
3. For each segment, build road + runoff + wall strips from the tagged frames,
   committing **one `MeshInstance3D` + `StaticBody3D` per segment per feature**.
   Generated nodes are owner-less (regenerated on `_ready`, NOT saved to .tscn).

**Continuity:** sampling the whole path once and slicing per segment means
adjacent segments share the exact boundary samples → no gaps or kinks.

## Material & collision system (reuse GrayBox)

The "repeating texture" in GrayBox is `uv1_triplanar = true` (world-space tiling,
works on any mesh) + a color-preset tint. Reuse it for road sides.

### Extract a shared helper: `utils/material_presets.gd`

Move the enum + tint table out of `graybox_staticbody.gd` into a neutral,
static-only `@tool class_name MaterialPresets`:

```gdscript
@tool
class_name MaterialPresets

# Keep member ORDER identical to the old GrayBoxColor — existing scenes store
# color_preset as ints, so order-preserving rename keeps them valid.
enum Preset { DARK_GRAY, LIGHT_GRAY, GREEN, BLUE, RED, PURPLE, TAN }

const COLOR_VALUES: Dictionary = { ... }  # moved verbatim

static func make_material(preset: Preset, texture: Texture2D) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = texture
    mat.uv1_triplanar = true
    mat.albedo_color = COLOR_VALUES.get(preset, Color.WHITE)
    return mat
```

- Refactor `graybox_staticbody.gd` to use `MaterialPresets.Preset` /
  `MaterialPresets.make_material()` (replaces its local enum + `apply_color`
  body). This is the only edit to working graybox code, sanctioned by the
  "reuse" request.

### Per-side application

Each generated runoff/wall feature node:
- **Material**: `MeshInstance3D` gets `MaterialPresets.make_material(preset,
  texture)` (default `texture_04`, overridable per side). Triplanar = repeats
  automatically regardless of strip size — no per-strip UV math needed.
- **Collision layer**: set the generated `StaticBody3D`'s `collision_layer` from
  the side's `SurfaceConfig` (mirrors how GrayBox sets it per instance).

This gives: road-wide defaults on `Track`, overridden per `TrackPoint` per side
— so a sand-trap corner with no wall on a specific collision layer is just that
point's config.

## What carries over (no rewrite)

`_build_flat_strip` / `_build_wall_strip` only need a **frame (origin + basis) per
step**. Today that comes from `curve.sample_baked_with_rotation`; swap in the
marker-spline frame array and the winding / UV / double-sided-wall logic comes
along nearly unchanged. With triplanar materials, the per-strip UV code can even
be dropped.

## Build phases (each independently verifiable)

1. **`MaterialPresets` extraction** — move enum/table, refactor graybox to use it.
   → *verify: existing graybox instances render identically (preset ints intact).*
2. **`TrackPoint` + `Track`: Catmull-Rom road** from N markers, banking from
   marker roll, single mesh. → *verify: smooth banked road follows markers.*
3. **Per-point runoff + walls** (width lerped along segment), still single mesh
   per feature. → *verify: runoff/walls follow, banking inherited.*
4. **Per-segment child mesh + body split**; apply `MaterialPresets` material +
   per-side `collision_layer`. → *verify: a sand corner with a different layer
   and no wall.*
5. **`straight` flag** → linear segment. → *verify: pit-lane-style straight.*
6. **Migrate** `racetrack_level_01` (TrackPiece + PitRoad + GarageGround) to the
   new system, then retire `road_path.gd` + `road_path.tscn`.

## Decisions 

1. **Config storage**: inline exports on `TrackPoint` to start
2. **Banking source**: marker's roll (up-vector) only, tangent always from the
   path — or should the marker's forward override the tangent too?
3. **Texture per preset**: single shared triplanar texture tinted by preset (pure
   GrayBox parity)

## Open risks

- Catmull-Rom is not arc-length parameterized; fixed `step` subdivision per
  segment is fine for a road mesh but spacing varies slightly with segment
  length. Acceptable; revisit only if texture stretch shows.
- Up-vector slerp near near-180° banking changes could flip; clamp / shortest-arc
  the slerp.
- Closed-loop wrap: first/last neighbor indices must wrap for Catmull-Rom tangents.
