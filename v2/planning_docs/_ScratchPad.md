# Scratch Pad
---

## Feedback

> playtest_logs/*.log

### NOW

The profile also says the expensive work is gone. What's left is mostly per-call overhead, and three things would cut it. In order of value for effort:

1. One transform write per rider per tick.
   - Each traffic rider currently moves its node three times per tick: _physics_process restores sync_transform, ride_to sets global_position, and _face_velocity sets rotation.y.
   - Each write probably marks the rider's whole child tree (skin, IK, label, area) for a transform update. That's likely a large part of ride_to (0.43 ms) and _physics_process (0.33 ms).
   - The fix: keep yaw in a variable and write global_transform once. Traffic wouldn't need the restore step any more.
   - It's a small change with no behaviour difference.
2. Batch the tick in NPCTrafficManager.
   - One loop over all riders, in place of 128 separate StateMachine._physics_process → Physics_Update dispatches.
   - Riders' own physics processing gets switched off.
   - On its own this only saves the dispatch overhead, roughly 0.3–0.6 ms. Its real value is that it makes step 3 easy.
3. Distance LOD: the step that lets you scale.
   - The manager ticks riders near any player every tick. Riders far from every player tick every Nth tick with N · delta, staggered round-robin so the work spreads across frames.
   - Rails make this safe: advance(speed · dt) doesn't care about a larger step. The gate and blocker logic just react a bit later, which nobody sees far away.
   - Far riders could also skip _process smoothing (0.62 ms), and clients receive fewer transform updates for them.
   - Two tunables: a near radius and a far tick interval. Under this, cost grows with riders near players, not total riders.

`
 these all sound good, including LOD. far riders can just be a position without rendering or having collision checks. but, this MUST work on online as well. so if players are scattered around the map, the ones nearest each client will render, but the server must calculate all
`

traffic AI

- [ ] add near miss
- [ ] add 180 / 360 / 720 tricks
- [ ] add hardflip / mix backflip / 180 tricks
- [ ] filling up - pay per second of fuel, so spilling costs $. show in diagetic UI on pump
- [ ] give cars headlights
- [ ] stop syncing duplicate skin definitions (npcs, etc)

- [ ] tell the users when changing colors that they have to press done (or change that)
- [ ] change spawn rate for diff items
- [ ] animate lowside crash
- [ ] animate car crash

### NEXT
- [ ] pause when out of focus
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
