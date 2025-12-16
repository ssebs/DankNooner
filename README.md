# Dank Nooner

## Current status:
- Testing / learning multiplayer
- Planning

## What is Dank Nooner?
**Dank Nooner** is a motorcycle stunt game built in Godot. The current V1 proof of concept is a simple wheelie balance challenge—hold a wheelie as long as you can and earn points to upgrade your bike.

The goal for V2 is a full rewrite expanding into an open-world 3D game. You'll progress from a bicycle up to sport bikes, learning new tricks and completing missions along the way. The physics should feel fun but challenging—managing clutch, throttle, and balance—with ragdoll crashes when you bail. Doing wheelies fills your NOS meter. Planned features include upgrades, customization, multiplayer (races, co-op, free roam), and eventually a story mode.

[V1 POC on Itch.io](https://theofficialssebs.itch.io/dank-nooner) | [GitHub](https://github.com/ssebs/danknooner)

## Rewrite / V2 / Future of the game

### Who's the target audience?
- Moto guys
- Open world enjoyers
- GTA enjoyers

### Goals
- Have more stunts
- Animations
  - IK to animate to hold on to handlebars / lean
  - Ragdoll when you fall off
- Plan Gameplay Loop w/ Flowcharts
- Plan Code Structure
  - SignalBuses
  - How features will be implemented
  - e.g. don't have a single UI object that has 50 methods
- Story?
  - Progress from bicycle to scooter to dirt bike to sport bike
- Open world
    - City
    - Hillside (like real moto, for races)
    - Race Track
    - Dirt Track
- Different gameplay loops
  - Riding around the world
  - Wheelies/other trick challenges (missions)
    - e.g. start on bike, 1st challenge is do a wheelie. (learn how + unlock it + get cash for customization)
  - Upgrade menu
  - Customize menu
  - Traveling to next objective
- Mechanics
  - Fun but challenging
  - Manage clutch, balancing, throttle, steering
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
- Multiplayer
  - Races (around mountain + drag race + around track)
  - Coop missions
  - Ride around together
- Target platform
  - PC (Windows+Linux) w/ Gamepad
- Artstyle:
  - Low Poly
  - Cute/Bubbly?
  - Aggressive/Sharp?
- Race duration 2-5 mins
- End goals for gamer:
  - Be the best racer in town 😎
    - Start on crappy races
    - Upgrade bike
    - Do harder races
      - Need to do tricks to get NOS, needed to win
    - Get golds / trophies


### Milestones
#### POC
- **Multiplayer POC**
  - > Start on separate project
  - See [multiplayer-poc-godot](./multiplayer-poc-godot/README.md)
  - Create lobby
  - Sync 2 players in game
- **Project Planning**
  - Use Markdown Kanban for tasks
  - Create subfolder for each mini project
  - Use Excalidraw for diagrams
- **Player controller** 
  - > Start on separate project
  - (gas, steer, brake, cluch, gears)
- **Basic animations with IK**
  - > continue from player controller project
  - Riding bike (lean, steer, wheelie)
  - Ragdoll

#### MVP
- **Start "real" project**
  - Import Scenes from past 2 projects (multiplayer, player controller)
  - Create code structure / processes
  - Create UI / Game managers
- **Basic objectives**
  - (fill up gas, NOS/boost unlocks, ramps, wheelies)
- **Multiplayer riding around town** 
  - (lobby, in game, sync)
- **Multiplayer races**

#### Full game
- **Tricks** (in air tricks, more than just wheelie)
- **Unlocks / Customization**
- **Quests**
- **Cutscenes / Story**
- **Polish / Add life (NPCs)**

## Timeline
1-2 years, from 1/1/2026

## License
[AGPL](./LICENSE)
