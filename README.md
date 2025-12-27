# Dank Nooner

## Current status:
- Planning

## What is Dank Nooner?
**Dank Nooner** is a motorcycle stunt game built in Godot. The current V1 proof of concept is a simple wheelie balance challenge—hold a wheelie as long as you can and earn points to upgrade your bike.

The goal for V2 is a full rewrite expanding into an open-world 3D game. You'll progress from a bicycle up to sport bikes, learning new tricks and completing missions along the way. The physics should feel fun but challenging—managing clutch, throttle, and balance—with ragdoll crashes when you bail. Doing wheelies fills your NOS meter. Planned features include upgrades, customization, multiplayer (races, co-op, free roam), and eventually a story mode.

[V1 POC on Itch.io](https://theofficialssebs.itch.io/dank-nooner) | [GitHub](https://github.com/ssebs/danknooner)

## Rewrite / V2 / Future of the game

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
- Multiplayer
  - Races (around mountain + drag race + around track)
  - Coop missions
  - Ride around together
- Target platform
  - PC (Windows+Linux) w/ Gamepad
- Artstyle:
  - Cell Shaded (not just overlay like Guac & Load, but built in to materials)
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
- **Multiplayer POC** - **[COMPLETE]**
  - > Start on separate project
  - See [multiplayer-poc-godot](https://github.com/ssebs/multiplayer-poc-godot.git)
  - Create lobby
  - Sync 2 players in game
- **Project Planning** - **[IN PROGRESS]**
  - Use Markdown Kanban for tasks
  - Create subfolder for each mini project
  - Use Excalidraw for diagrams
- **Player controller + Simple animations** 
  - > Start on separate project
  - > think about what should be sync'd over the network
  - Basic controls / movement (gas, steer, brake, cluch?, gears?)
  - State machine to sync animations to movement state
  - Riding bike Animations (lean/steer, wheelie, start/stop w/ leg down)
  - Sync'd animations w/ state machine
  - Code cleanup
- **Complex animations**
  - > continue from player controller project
  - With IK?
  - More bike animations (brakes, clutch, gear shift, throttle)
  - Tricks (stoppie, ramp + backflip, can-can?, tabletop?)
  - Ragdoll (crash + ragdoll)
  - Code cleanup
#### MVP
- **Start "real" project**
  - > Start on separate (main) project
  - Major planning:
    - Gameplay planning
      - Map design
      - Different Bikes / balancing
      - Progression (unlock bikes, how will xp work, $ for upgrades, etc.)
      - Customization (color, mods per bike, stat boosts)
      - Game modes (race, wheelie race, stunt race, S.K.A.T.E. game, free roam, delivery (pizza? paper route?))
      - Potential story for singleplayer mode (start as a kid with bicycle, do wheelies with a paper route, progress to scooter,etc .)
      - Art style / vibe of the game
    - Code structure (what files will control what, separation of concerns, etc.)
    - Coding Processes (where to use state machines, how to sync data, interactions, etc.)
    - Flow of Multiplayer auth, who sends what
    - Create diagrams
- **Implement Player Controller & Multiplayer**
  - Import Scenes from past 2 projects (multiplayer, player controller)
  - Create UI / Game managers / Globals / Lobby / etc
  - Follow the plan... (and update this doc)
- **Freeroam + tricks MP demo**
  - Playable demo with:
    - Multiplayer (can play with friends)
    - 1 bike choice with some customization
    - NPCs (driving around)
    - Open world map (race track, city, mountains)
    - Ramps
    - Tricks (basics)
- **Basic gameplay**
  - Progression
  - Game modes (free roam, race, wheelie race, etc...)
  - tbd

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
