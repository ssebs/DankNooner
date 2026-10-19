# Scratch Pad
---

## Feedback

> playtest_logs/*.log

### NOW

Steps 0 and 1 are in. Both pass gdlint and the headless editor load with no errors. Nothing has been run in the editor yet, so the step 1 check is yours.

Step 0: road layer
- project.godot now has 3d_physics/layer_7="road".
- stunt_track_01's RoadManager has collision_layer = 65 (layer 1 plus road). No container in the project overrides collision layers, so every road body should pick it up. If old bodies are still on layer 1 only, reopen the scene to make the roads regenerate.

Step 1: authoring nodes, in levels/components/traffic/:
- TrafficNetwork: has show_in_editor. In the editor it draws all roads and intersections each frame and checks every node's config warnings twice a second (only changed warnings get pushed, so the scene dock isn't rebuilt every time). At runtime its _process is off.
- TrafficRoad: has lane_width. It draws a white polyline through its points. It warns if it has fewer than 2 points, if an end isn't linked by any intersection, or if it isn't under a network.
- TrafficRoadPoint: has lane_count. Its label shows the actual count, white if set on that point and grey if inherited. A red sphere means the ray down from 5 m above the point didn't hit the road layer. It warns on an odd count, or if it's the first point and the count isn't set.
- TrafficIntersection: has the 4 slots, radius, control, green_duration and amber_duration. It draws a yellow box with the control name over it. Each slot gets an arm: a short grey stub if empty, green if the road's near end is in reach, red if not. In reach means within 2× radius and within about 45° of the slot's direction.

Where I departed from the spec:
- No .tscn files. These are scripts with class_name only, so you add them through Create Node. Tell me if you want scenes you can drag in.
- Text labels instead of a Label3D for control. I used DebugDraw3D.draw_text, so nothing extra is saved into the scene and nothing shows at runtime.
- Moved to step 2: the Bake button, the lane preview with arrows, and the network's "no bake / stale bake" warnings, because they need the bake data.

For you to check: add a TrafficNetwork to stunt_track_01, then build a 3-way with a few roads and one intersection. Leave one slot empty, link one road properly and link one badly, and see whether the stub, green and red arms read correctly. I haven't confirmed that DebugDraw3D draws in the editor viewport when called from these @tool scripts; it isn't used anywhere else in the project. If nothing appears, that's the first thing to look at.

I'll start step 2 (the bake) once you've confirmed this works.



### NEXT
- [ ] holding T pose should not grant so many points / score
  - [ ] need some penalty for simple tricks vs combos


- [ ] add some form of gamba (spin wheel / roulette / random game)
- [ ] Make hud simpler/intuitive 
  - [ ] remove throttle bar

- [ ] free roam wheelie challenge/points scoring should be longer than 1min and explain what it is

- [ ] Fill up => race is not obvious where to go/not consistent across all races 
- [ ] must be easier to know what the controls are / how to do tricks
  - [ ] add btn prompts/hints
- [ ] need to know when race is completed (single player is done vs entire lobby)
