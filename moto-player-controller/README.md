# Moto Player Controller

## In Progress:

- [ ] Tweak values til they feel good

  - [ ] Gearing / speed
  - [ ] rpm / sound
  - [x] Steering at low speeds
  - [ ] falling at low speeds (fix idle tip in)
  - [ ] wheelie / stoppie control

- [ ] Fix bugs / understand the refactored code
- [ ] User stories:
  - [ ] bike should fall when too slow
  - [ ] bike should lean up when accelerating
  - [ ] bike should tip-in / countersteer when leaning
  - [ ] the steer angle + lean angle should be based on speed
  - [ ] crash detection and respawn
  - [x] wheelies / stoppies - pitch control during each
  - [x] Skidding / fishtail - rear brake skids, fishtail drift physics w/ skidmarks
  - [x] engine sound pitch based on RPM
  - [x] tire screech on skids/stoppies
  - [x] gear grind sound
  - [x] gear display, speedometer, throttle bar (with redline color), brake danger bar
  - [x] Controller vibration - brake danger, fishtail, redline

## TODO:

- [ ] Create rigged character
- [ ] Animate character
- [ ] Complex movement / input system
  - [ ] State machine
  - [ ] Sync'd animations
  - [ ] tricks
  - [ ] Ragdoll
- [ ] if the front tire skids and regains traction, the bike should porpoise. causing a high-side crash.

## Done:

- [x] Cleanup / refactor vibe coded `player_controller.gd`
  - [x] Move to its own node/script
- [x] Basic Movement / input system
  - [x] throttle / brake
  - [x] lean
  - [x] clutch / gears
  - [x] crashing (fall off bike, collision)
- [x] Basic sounds
- [x] Skidmarks / drifts
- [x] Import motorcycle 3d model
- [x] Create basic world
- [x] Create godot project
- [x] Control map:
  - [ ] IMG: https://www.padcrafter.com/?templates=Controller+Scheme+1&leftTrigger=Front+Brake&rightTrigger=Throttle&leftBumper=Clutch&leftStick=Steer+%26+Lean&dpadUp=Shift+Up&dpadRight=Shift+Down&aButton=Rear+Brake
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
