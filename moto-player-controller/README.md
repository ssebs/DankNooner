# Moto Player Controller

## In Progress:

## TODO:
- [ ] Create godot project
- [ ] Import motorcycle 3d model
- [ ] Create basic world
- [ ] Basic Movement / input system
  - [ ] throttle / brake
  - [ ] lean
- [ ] Create rigged character
- [ ] Animate character
- [ ] Complex movement / input system
  - [ ] State machine
  - [ ] Sync'd animations
  - [ ] tricks
  - [ ] clutch / gears
  - [ ] crashing (fall off bike, collision)
  - [ ] Ragdoll

## Done:


## Notes copied from ../README.md

### To implement
- Basic controls / movement (gas, steer, brake, cluch?, gears?)
- State machine to sync animations to movement state
- Riding bike Animations (lean/steer, wheelie, start/stop w/ leg down)
- Sync'd animations w/ state machine

### Goals
- Animations
  - IK to animate to hold on to handlebars / lean
  - Ragdoll when you fall off
- Mechanics
  - Fun but challenging
    - Multiple difficult levels
      - **Easy** - Automatic, can't fall off bike unless crashing
      - **Medium** - Manual, can't fall easily from mistakes (e.g. lowside)
      - **Hard** - Manual, can fall (e.g. low side crash if leaning and grabbing a fist full of brake)
  - Manage clutch, balancing, throttle, steering (need to be smooth, don't just slam it.)
  - Falling / crashing has ragdoll physics, player goes flying until they stop moving (or press btn)
- Gameplay
  - Doing wheelies gives you NOS
  - Controls:
    - Gamepad preferred
      - Front Brake `LT`
      - Gas `RT`
      - Steer (lean) `Right Stick`
      - Clutch `LB`
      - Trick `RB`
        - Hold `RB` while pressing other buttons (A,B,X,Y) (maybe flick eventually)
      - Shift Gears `DPAD Up/Down`
      - Rear Brake `A`