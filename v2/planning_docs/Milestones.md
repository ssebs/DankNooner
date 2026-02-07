# Milestones

> Overall project milestone status

## POC - [COMPLETE]

- **Multiplayer POC** - [COMPLETE]
  - > Start on separate project
  - See [multiplayer-poc-godot](https://github.com/ssebs/multiplayer-poc-godot.git)
  - Create lobby
  - Sync 2 players in game
- **Inverse Kinematics POC** - [COMPLETE]
  - > Start on separate project
  - See [inverse-kinematics-poc](https://github.com/ssebs/inverse-kinematics-poc)
  - Learn how IK works in godot
- **Player controller + Simple animations** - [COMPLETE]
  - > Start on separate project
  - > think about what should be sync'd over the network
  - See [moto-player-controller-godot](https://github.com/ssebs/moto-player-controller-godot/)
  - Basic controls / movement (gas, steer, brake, cluch?, gears?)
  - State machine to sync animations to movement state
  - Riding bike Animations (lean/steer, wheelie, start/stop w/ leg down)
  - Sync'd animations w/ state machine
  - Code cleanup
  - > continue from player controller project
  - With IK?
  - More bike animations (brakes, clutch, gear shift, throttle)
  - Tricks (stoppie, ramp + backflip, can-can?, tabletop?)
  - Ragdoll (crash + ragdoll)
  - Code cleanup

## MVP - [IN_PROGRESS]

- **Start "real" project** - [IN_PROGRESS]
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
  - Play with art style, try to make it look good
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

## Full game

- **Tricks** (in air tricks, more than just wheelie)
- **Unlocks / Customization**
- **Quests**
- **Cutscenes / Story**
- **Polish / Add life (NPCs)**
