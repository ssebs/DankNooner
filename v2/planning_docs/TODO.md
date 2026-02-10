# TODO

> Don't forget, have fun :D

## In Progress 🚀

- [ ] Create NetworkManager
  - [x] Create lobby
    - [x] players can join / be seen
  - [x] plan MP authority
    - [x] only host can start game
    - [x] host chooses level, others can see
  - [ ] Create SpawnManager & sync players
  - [ ] refactor if needed
    - [ ] cleanup player_entity so only local cams are used, etc.
      - [ ] set username
    - [ ] multiplayer / spawn mgr cleanup

## Up Next 📋

- [ ] Create Test Level - Gym - player controller, with tp. Basically in game documentation.
  - (E.g. How far can you jump)

  - [ ] spawn players in game
    - [ ] Should show their customizations
  - [ ] Singleplayer / Multiplayer player_entity code separation
  - [ ] sync player positions
  - [ ] sync animations (tricks)

- [ ] Create Player Part 2
  - [ ] physics
  - [ ] gearing
  - [ ] basic character selection (select male/female)
- [ ] Create Player Part 3
  - [ ] IK https://youtu.be/MbaPDWfbNLo?si=p5ybcrLUJje_nBgd animations
  - [ ] **Basic customization**
    - [ ] character accessories (cosmetics, etc.)
    - [ ] bike mods (color, actual mods) (**basic customization**)
  - [ ] **BikeDefinition** with component definitions under it
    - [ ] base mesh **MeshDefinition**
    - [ ] color override
    - [ ] BikeMod list
      - [ ] **ModDefinition**
        - [ ] **MeshDefinition**
        - [ ] **Marker3D**
        - [ ] script

since I will have multiple bike types, colors, and mods for each type.

- [ ] Trick Manager + tricks
  - [ ] trick system
  - [ ] wheelie / stoppie tricks
  - [ ] ramp tricks
  - [ ] ground tricks
- [ ] Create Test Level - Zoo - all relevant models/scenes in 3d space to easily compare
  - (E.g. diff bikes/mods on each bike)
  - There's a godot plugin for this
  - https://binbun3d.itch.io/godot-ultimate-toon-shader

## Backlog

- [ ] nat punch

- [ ] text chat

- [ ] camera control
- [ ] Audio Manager
- [ ] Create TrickManager
  - [ ] connect w/ NetworkManager
  - [ ] trick detection in player component
  - [ ] trick scoring in own script
- [ ] Create Save System
- [ ] Create traffic / AI system
  - [ ] basic traffic sim
  - [ ] implement A\* pathfinding? w/ state machine?
    - [ ] drive, stopped at light, parked, etc.
  - [ ] create sequence system?
- [ ] Create GamemodeManager
  - [ ] create system
  - [ ] free roam w/ friends
  - [ ] street race in traffic as demo mode (+fps mode)
  - [ ] stunt race? Or high score mode?
- [ ] Create basic SettingsMenu scene/ui

  - [ ] Make this work with pause menu (compose this somehow)

  - [x] Create scene
  - [x] Improve the UI
  - [ ] Add all components
  - [ ] Functional settings

- [ ] Customization

  - [ ] Add customize menu UI
  - [ ] Add customize menu background scene
  - [ ] More Character customization
  - [ ] More Bike customization
  - [ ] Save on client for now - but make abstract enough for future server saving

- [ ] Create Test Level - Museum - functionally show how systems work, text explaining the systems.
  - (E.g. showing physics demos, how scripted sequences work)
- [ ] Create Island Level
  - [ ] render trees/etc. with multi mesh

## Polish / Bugs

- [ ] Web RTC?

- [ ] Setup cloudflare image upload in vscode
- [ ] Quit on Web should just escape fullscreen
- [ ] Add transition animations (e.g. circle in/out) between Menu States / Loading states

## Done ✅

- [x] Connect _on_peer_connected to add_player_to_lobby

- [x] Create Player Part 1
  - > no animations for now
  - [x] Player scene + component scripts
    - [x] movement
  - [x] basic bike selection (select bike)
  - [x] InputManager in game
    - [x] bike control

- [x] 21x9 support

- [x] format on save

- [x] Move planning docs to v2 folder (also update README.md)

- [x] mouse capture broken

- [x] Git LFS

- [x] Create basic PauseMenu scene/ui

  - [x] Create scene/script
  - [x] Option to go back to main menu
  - [x] Pause / resume functionality

- [x] Create InputManager

  - [x] Mouse / Gamepad switching
  - [x] Gamepad to control Menus
  - [x] Show/Hide the cursor

- [x] Connect signals between all managers in ManagerManager

- [x] Create LevelManager

  - [x] base class / states
  - [x] Move BGClear Rect as a level type
  - [x] create first 3d test level
  - [x] auto validation
  - [x] Make level select work
  - [x] Update Architecture.md

- [x] Add toast UI

- [x] Finish UI routing

  - [x] Pass params to states via context
  - [x] nav to lobby / level select depending on which button you choose
  - [x] connect all the buttons

- [x] Create basic LobbyMenu scene/ui

  - [x] Create scene
  - [x] Improve the UI
  - [x] Add all components

- [x] Create basic PlayMenu scene/ui

  - [x] Create scene / ui
  - [x] create all components (see excalidraw)

- [x] PrimaryBtn style

- [x] create menu uidiagram

- [x] Create UI Theme

- [x] Create basic MainMenu scene/ui

  - [x] Create scene
  - [x] Improve the UI

- [x] Fix Menu HACKS / Cleanup
  - [x] Update Architecture doc w/ final setup
- [x] Create MenuManager
- [x] Navigate between Menus
- [x] Basic Localization
- [x] Create ManagerManager
- [x] Create StateMachine
- [x] Update project plan
- [x] Create godot 4.6 project
- [x] Create folder structure
- [x] Create planning docs
