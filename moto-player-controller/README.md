# Moto Player Controller

## In Progress:
- [ ] Basic Movement / input system
  - [ ] throttle / brake
  - [ ] lean


## TODO:
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
- [x] Import motorcycle 3d model
- [x] Create basic world
- [x] Create godot project
- [x] Control map:
  - Gamepad
    - Throttle `throttle_pct`
      - Gamepad: **RT**
      - KBM: **W**
    - Front Brake `brake_front_pct`
      - Gamepad: **LT** 
      - KBM: **S**
    - Rear Brake `brake_rear`
      - > Note: input is cumulative - amount builds based on how long you hold it
      - Gamepad: **A**
      - KBM: **Space**
    - Steering `steer_pct`
      - > Note: steering causes a horizontal lean
      - Gamepad: **Left Stick X Axis** 
      - KBM: **A/D**
    - Lean body `lean_pct`
      - Gamepad: **Left Stick Y Axis**
      - KBM: **Arrow Keys**
    - Clutch `clutch`
      - Gamepad: **LB**
      - KBM: **CTRL**
    - Shift Gears `gear_up` `gear_down`
      - Gamepad: **DPAD Up/Down**
      - KBM: **Q/E**
    - Camera movement `cam_x` `cam_y`
      - Gamepad: **Right Stick X / Y Axis** 
      - KBM: **Mouse**
    - Trick `trick`
      - Gamepad: **RB**
      - KBM: **Shift + Arrow keys**
      - Hold **RB** while moving right joystick (**RB+Down** => Wheelie, etc.)
    - Pause: `pause`
      - Gamepad: **Start**
      - KBM: `ESC`

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
