# Track / Road Builder

How to build drivable roads and racetracks.

> **Use the `Track` node for all roads.** It replaced the old curve-based
> `RoadPath` (`levels/components/road_path.gd`, now removed) — banking is a visual
> gizmo, per-segment settings live on the points, and per-segment
> material/collision is built in.

## Components

| Script | Class | Role |
|---|---|---|
| `levels/components/track.gd` | `Track extends Node3D` | The builder. Collects its `TrackPoint` children and regenerates the geometry. |
| `levels/components/track_point.gd` | `TrackPoint extends Marker3D` | One control point. Its transform *is* the path data; it also owns the config for the segment from itself to the next point. |
| `levels/components/surface_config.gd` | `SurfaceConfig extends Resource` | Per-side material + collision settings for a runoff or wall. |
| `utils/material_presets.gd` | `MaterialPresets` | Shared color-preset + triplanar material helper (also used by `GrayBoxStaticBody`). |

## How a track is built

1. `Track` gathers its ordered `TrackPoint` children.
2. Each **segment** runs from a point to the next one (the **owner** is the
   first point of the pair). For a `closed` track the last point wraps to the first.
3. The centerline follows a **Catmull-Rom spline** through the points (so the
   road passes through every marker — no bezier handles to fiddle with).
4. Per segment, the builder commits one `StaticBody3D` (with a `MeshInstance3D` +
   trimesh `CollisionShape3D`) **per feature** (road, left/right runoff,
   left/right wall).

**Generated geometry is owner-less** — it is *not* saved into the `.tscn` and is
regenerated on `_ready` and whenever you edit a point or a Track property. Only
the `Track` node and its `TrackPoint` children are saved. Don't hand-edit or
re-parent the generated bodies; they get wiped on every rebuild.

## Building one in the editor

1. Add a `Node3D`, attach `track.gd` (or it'll show as a `Track` type).
2. Add `Marker3D` children, attach `track_point.gd` to each (they show as
   `TrackPoint`). Order in the tree = order along the road.
3. Move the points to lay out the path. The road rebuilds live as you drag.
4. Set the road-wide defaults on the `Track` (width, material, etc.), then
   override per side/segment on individual points as needed.
5. Tick **`closed`** on the `Track` for a loop (start joins back to the end).

## Banking, slope, and shape

- **Banking = ROLL the marker.** Rotate a `TrackPoint` about its **forward**
  axis and that section of road tilts into the turn. The builder reads each
  marker's up-vector and blends (slerps) it between points, so banking flows
  smoothly between corners.
  - **Roll only.** Do **not** pitch or yaw a marker to "aim" it — the builder
    derives travel direction from the path itself, and a pitched/yawed marker
    only distorts the road surface.
- **Slope (uphill/downhill) = the marker's Y position.** Just raise/lower the
  point; the road ramps between heights automatically. No rotation needed.
- **Curviness** (per point, `0.0`–`1.0`): how much that segment curves.
  - `1.0` = full Catmull-Rom (default), matches the rest of the track.
  - Lower values flatten the segment toward a straight chord — use for
    straightaways.
  - Any value **above 0 stays gap-free** with its neighbours; only an exact `0`
    (a hard straight chord) can leave a small gap where it meets a curved
    segment. For a straight-but-seamless straightaway use something like `0.1`.
- **`tension`** (on the `Track`, global): slackens *every* segment toward its
  chords. Raise it to tame Catmull-Rom overshoot between widely-spaced points.

## Sharp corners (hairpins, the Corkscrew)

Catmull-Rom always rounds a point into a smooth swoop — `curviness`/`tension`
only change the tangent *magnitude*, never its direction, so you can't get a
defined apex by tuning them. For that, mark the point **`sharp`**:

- **`sharp`** (per point): the road runs *straight in → tight curve → straight
  out* of the point instead of swooping. The two neighbouring segments become
  straight chords and a quadratic-Bézier **apex curve** joins them.
- **`corner_radius`** (per point, meters): controls how far back the curve
  starts (its tightness). Smaller = tighter. Auto-reduced if it won't fit
  between the neighbours. The trim length is driven by the **plan-view** turn
  angle, so a steep grade through the corner doesn't change it.
- The apex curve interpolates height between its endpoints, so a sharp corner
  taken *while descending* (drop the next point's Y) stays tight as it goes
  downhill without plunging — that's the Laguna Seca Corkscrew: two sharp points
  (left then right) with a
  short straight between and a steep elevation drop. Bank by rolling the apex
  point; the arc uses that point's bank.
- An **S / chicane** is just two adjacent sharp points turning opposite ways.

Limitations:
- **Walls don't fill the corner** at a sharp point (road + runoff only). A walled
  sharp corner will show a gap in the wall at the apex — leave sharp corners
  wall-free for now.
- **Open-track first/last points can't be sharp** (no incoming/outgoing chord);
  the flag is ignored there.
- A near-180° single point won't fillet (the tangent length explodes) — build a
  true U-turn from a few sharp points, or leave it rounded.

## Ground apron (tying the track into the ground)

When the track climbs, its runoff edges float above the flat ground. Enable the
**ground apron** on the `Track` to generate a skirt that ramps from each
runoff/road outer edge down to a flat ground level:

- **`ground_apron`** (Track): turn it on.
- **`ground_y`** (Track): the world height the skirt levels off to — set it to
  your surrounding ground's height.
- **`apron_width`** (Track): how far out (meters, horizontal) the skirt reaches
  before it's flat at `ground_y`.

The skirt is generated from the same banked frames, so it auto-matches the road
height, banking, and the sharp corners, and rebuilds live. Each side uses that
side's **runoff `SurfaceConfig`** (so it blends with the runoff; null = road
defaults). It grades the band *near* the track — use Blender terrain beyond it
for distant scenery. Note: it assumes the track sits **above** `ground_y`; where
the track dips below it the skirt ramps upward instead.

## Runoff and walls (per point, per side)

Each `TrackPoint` carries Left and Right config for the segment it owns:

- `left_runoff_width` / `right_runoff_width` — flat strip extending outward from
  the road edge (sand/grass), inheriting the road's height + banking. Width
  lerps to the next point's, so it stays seamless. `0` = none.
- `left_runoff` / `right_runoff` — a `SurfaceConfig` for that runoff's material
  and collision layer.
- `left_wall_height` / `right_wall_height` — vertical wall at the **outer** edge
  of the runoff (road edge if no runoff). `0` = no wall on that segment.
- `left_wall` / `right_wall` — a `SurfaceConfig` for that wall.

A `SurfaceConfig` left **null** falls back to the `Track`'s road defaults. So:
road-wide defaults on the `Track`, and you only attach a `SurfaceConfig` where a
segment side needs something different (e.g. a green sand-trap on its own
collision layer, or a corner with no wall).

## Material & collision (`MaterialPresets`)

`SurfaceConfig` and the `Track` defaults use the same preset system as the
GrayBox blockout:

- `material_preset` — a `MaterialPresets.Preset` tint (`DARK_GRAY`, `GREEN`,
  `RED`, …). Applied as a triplanar `StandardMaterial3D`, so the texture tiles in
  world space on any strip size — no UV setup needed.
- `texture` — optional override; null uses the `Track`'s default texture
  (kenney `texture_04`).
- `collision_layer` — physics layer for that feature's `StaticBody3D`.

## `Track` properties (defaults)

- `road_width` — road width in meters.
- `step` — approximate sample spacing (smaller = smoother curves, more tris).
- `tension` — global curve slackness (see above).
- `closed` — wrap the loop.
- `texture` / `road_preset` / `collision_layer` — road defaults, and the
  fallback for any runoff/wall side with a null `SurfaceConfig`.

## Gotchas / tips

- **Tight inner corners self-intersect.** A wide road or wide runoff on a corner
  whose radius is smaller than the strip's outer reach will fold through itself.
  Fix by adding more `TrackPoint`s around the corner, narrowing the runoff on
  that point, or raising `tension`.
- **Sparse points overshoot.** Catmull-Rom bulges between far-apart points. Add
  points or raise `tension`.
- **Don't pitch/yaw markers** (see Banking). Roll for banking, position for slope.

## History: the old `RoadPath`

`Track` replaced a curve-based `RoadPath` (`Path3D` extruding the same
road/runoff/wall strips from a `Curve3D`). Banking there was the curve's `tilt`
float array (awkward to edit) and segment settings were flat exports with index
arrays (`straight_segments`, `right_wall_skip_segments`, …). It has been removed
— mentioned here only so old commits/screenshots make sense.
