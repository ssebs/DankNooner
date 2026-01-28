# Dank Nooner

## Current status:

- Proof-of-Concept almost complete
  - Moto Player Controller
- Planning

## What is Dank Nooner?

**Dank Nooner** is a motorcycle stunt game built in Godot. The current V1 proof of concept is a simple wheelie balance challenge—hold a wheelie as long as you can and earn points to upgrade your bike.

The goal for V2 is a full rewrite expanding into an open-world 3D game. You'll progress from a bicycle up to sport bikes, learning new tricks and completing missions along the way. The physics should feel fun but challenging—managing clutch, throttle, and balance—with ragdoll crashes when you bail. Doing wheelies fills your NOS meter. Planned features include upgrades, customization, multiplayer (races, co-op, free roam), and eventually a story mode.

[V1 POC on Itch.io](https://theofficialssebs.itch.io/dank-nooner) | [GitHub](https://github.com/ssebs/danknooner)

## Rewrite / V2 / Future of the game

Differentiates itself from Ride 5 (and others) since it's not just racing, it's tricks and stunting too.

### Marketing

- [ ] how to market the game?
- [ ] figure out: why should people play Dank Nooner. Gameplay is fun, but to what end?
  - story?
  - progression? Bicycle to low power bike to dirt to sport?
  - Modes? Singleplayer/progression + quick server play like GTA Online?
- [ ] think of clippable moments for dank nooner
  - [ ] e.g. first crash & ragdoll
  - [ ] e.g. first dank wheelie fx
  - [ ] going on your phone during a ride turns into a crash
    - [ ] why do you need to do this? Some menu? Tuning?
  - [ ] E.g. wheelie => 360 flip trick in trailer w/ friend crashing during a race
- [ ] trailer + free multiplayer demo out now!
  - [ ] high quality demo, only planned jank
- [ ] hooks
  - [ ] 2-3 seconds to get attention on short form
  - [ ] do all the stupid stuff on a motorcycle from the safety of your home
  - [ ] mom said don't do wheelies
  - [ ] real bike mechanics, real crazy tricks
  - [ ] high skill ceiling to perfect your tricks
  - [ ] entertain first, then promote
  - [ ] post on EVERY platform
  - [ ] highlight what makes it different

### Stuff to Organize

- [ ] Add dopamine sounds (sfx on points, etc)
- [ ] easy to connect with friends
- [ ] easy to join open lobby
- [ ] tutorial via challenges
  - [ ] Teach how to shift, do tricks, and physics of braking via examples.
  - [ ] (Speed up to 60 then take this corner at the apex, brake progressively)
- [ ] release dank nooner v2 demo MP on itch. This is p0 to get critical feedback about game feel
  - [ ] think of what should be in the demo, what modes, etc.
  - [ ] make sure it's fun & polished
- [ ] create color palette for dank nooner
- [ ] textured low poly? Aka paint lines on 3d models

### Peer Feedback from moto-player-controller

- Pedro doesn't like:
  - the camera snaps back when letting go
- Pedro ideas:
  - helldivers like combos
  - Bobble head cosmetic
  - "Jiggle Physics" cosmetics see - Marvel Rivals
  - Upload PNG for face, or logo, etc.
- Me:
  - Reduce FOV speed change on mini bike
  - Leaning animation broken after some time
  - Transparent cosmetic - or xray / etc


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
  - MEGARAMP
  - Hillside (like real moto, for races)
  - Race Track
  - Dirt Track
- Different gameplay loops
  - Riding around the world
  - Wheelies/other trick challenges (missions)
    - e.g. start on bike, 1st challenge is do a wheelie. (learn how + unlock it + get cash for customization)
  - Street race mode (dodge traffic/weave w/ friends)
  - Upgrade menu
  - Customize menu
  - Traveling to next objective
  - Hide license plate / police chase feature
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
  - Score system for doing tricks
    - +200, combos, etc.
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
  - Neon / Night vibes
    - e.g. life could be a dream from Cars https://youtu.be/Kzy3n-8A-vA?si=4geX5_eVg_qv6hsg&t=107
    - e.g. tuner scene from Cars https://www.youtube.com/watch?v=tVm6OWbUTG0
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

- **Multiplayer POC** - [COMPLETE]
  - > Start on separate project
  - See [multiplayer-poc-godot](https://github.com/ssebs/multiplayer-poc-godot.git)
  - Create lobby
  - Sync 2 players in game
- **Inverse Kinematics POC** - [COMPLETE]
  - > Start on separate project
  - See [inverse-kinematics-poc](./inverse-kinematics-poc/README.md)
  - Learn how IK works in godot
- **Player controller + Simple animations** - [IN_PROGRESS]
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

#### Full game

- **Tricks** (in air tricks, more than just wheelie)
- **Unlocks / Customization**
- **Quests**
- **Cutscenes / Story**
- **Polish / Add life (NPCs)**

### All Tricks

- [ ] Basic Wheelie (sitting)
- [ ] Basic stoppie
- [ ] Standing wheelie
- [ ] One leg over wheelie
- [ ] Stoppie to 180
- [ ] two legs up doing a wheelie
- [ ] Drift
- [ ] Burnout
- [ ] Biker Boyz w/ 2 legs over the side (sparks)
- [ ] FMX tricks (only off **Ramps**)
  - [ ] Back / Front flip
  - [ ] 360 / 180 turns
  - [ ] Whip (table)
  - [ ] Superman (no hand spread eagle)
- [ ] Skate tricks for memez (only off **Ramps**)
  - > hop on top of bike, then do it like skater
  - [ ] kickflip/heelflip
  - [ ] pop shuvit
  - [ ] hardflip
  - [ ] 360flip
  - [ ] nollie lazerflip

## Timeline

1-2 years, from 1/1/2026

## License

[AGPL](./LICENSE)
