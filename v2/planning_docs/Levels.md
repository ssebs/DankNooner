# Levels

Stuff about levels

TODO - add info here!

## Traffic Density

`LevelDefinition.traffic_settings` is a `TrafficSettings` resource
(`resources/traffic/traffic_settings.gd`) holding this map's rider count, car/bike
mix, cruise speed, and vehicle rosters. It defaults to the shared
`resources/traffic/settings/default_traffic_settings.tres` — assign a per-map
`.tres` instead to make a level busier, quieter, or car-heavy.

Read once on level entry, in `NPCTrafficManager.start_traffic()`, so edits need a
re-entry of free roam to take effect. Two caveats:

- Rider count is capped by the level's distinct AI lanes — traffic spawns one rider
  per lane to spread them out, so a small road network silently ignores the excess.
- Maps with no `RoadManager` get no traffic at all, whatever the settings say.

Per-map vehicle *rosters* live on the same resource: `bike_roster` / `car_roster`
limit which skins that map rolls (city spawns cars, racetrack spawns bikes). Leave a
roster empty and traffic rolls every skin in the global folder instead. A roster only
narrows the pool — `car_chance` still decides whether a car or a bike comes up.

`paint_colors` on the same resource is the map's paint pool: every spawned NPC
repaints its mesh's **first color slot** with one entry, picked off the `hash(name)`
rng `NPCRiderEntity._ready` already seeds — so every peer rolls the same paint with
nothing synced. Empty leaves the skin's authored color alone. This also covers race
bots, not just traffic (`NPCRaceManager` reads the same field). Meshes that must keep
their authored livery (taxi, cop car) set `do_not_use_color` on their `SkinColor` root
and are skipped — see Skins.md.

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
