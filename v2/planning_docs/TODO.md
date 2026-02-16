# TODO

> Don't forget, have fun :D

## In Progress 🚀

- [ ] on spawn, make players virtually press c

  - [ ] by default they're looking at the hosts camera

- [ ] Create settings json w/ save loader
  - [ ] add noray relay host in config file for game
- [ ] respawn in pause menu

- [ ] multiplayer / spawn mgr cleanup
  - [x] close server when going to main menu
  - [ ] review all code & cleanup to call authority done
  - [ ] update Architecture.md

## Up Next 📋

- [ ] Audio Manager

  - [ ] Client side
    - [ ] Global audio buses (music, sfx)
  - [ ] Server side
    - [ ] 3D spatial audio bus (for bikes in world)

- [ ] Create Player Part 2

  - [ ] import features from moto-player-controller
    - [ ] gearing
    - [ ] physics
    - [ ] sound
    - [ ] dont worry about tricks other than wheelies

- [ ] Create Player Part 3

  - [ ] IK animations https://youtu.be/MbaPDWfbNLo?si=p5ybcrLUJje_nBgd
  - [ ] **Basic customization**
    - [ ] Choose a bike + color
    - [ ] Choose a character (male/female)

- [ ] Create Save System

  - [ ] Save bike definitions on disk
  - [ ] Save custom username for lobbies

## Backlog

- [ ] software is open source, but assets aren't public

- [ ] level select img
- [ ] Customization UI / menu

  - [ ] Add customize menu UI
  - [ ] Add customize menu background scene
  - [ ] Save on client- but make abstract enough for future server saving
  - [ ] when spawning player in game, show their customizations
  - [ ] Add Bike customization
    - [ ] **BikeDefinition** with component definitions under it since I will have multiple bike types, colors, and mods for each type.
      - [ ] character accessories (cosmetics, etc.)
      - [ ] bike mods (color, actual mods) (**basic customization**)
      - [ ] base mesh **MeshDefinition**
      - [ ] color override
      - [ ] BikeMod list
        - [ ] **ModDefinition**
          - [ ] **MeshDefinition**
          - [ ] **Marker3D**
          - [ ] script
  - [ ] Add Character customization (choose character for now)

- [ ] Trick Manager + tricks

  - [ ] trick system
  - [ ] wheelie / stoppie tricks
  - [ ] ramp tricks
  - [ ] ground tricks
  - [ ] trick detection in player component
  - [ ] trick scoring in own script

- [ ] Create Test Level - Gym - player controller, with tp. Basically in game documentation. (E.g. How far can you jump)

  - [] Make the world fit around the player controller.
  - [ ] [ramp physics](https://www.reddit.com/r/godot/s/O6aKthtk9i)

- [ ] Create Test Level - Zoo - all relevant models/scenes in 3d space to easily compare

  - (E.g. diff bikes/mods on each bike)
  - There's a godot plugin for this
  - https://binbun3d.itch.io/godot-ultimate-toon-shader

- [ ] Camera control

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

- [ ] Create Test Level - Museum - functionally show how systems work, text explaining the systems.
  - (E.g. showing physics demos, how scripted sequences work)
- [ ] Create Island Level

  - [ ] render trees/etc. with multi mesh

## Polish / Bugs

- [ ] reactive sounds (play when player does something) = juice
- [ ] Add transition animations (e.g. circle in/out) between Menu States / Loading states
- [ ] Add text chat
- [ ] Web
  - [ ] WebRTC (?)
  - [ ] Quit on Web should just escape fullscreen

## Done ✅

- [x] when host ALT+F4's run server_disconnect.

- [x] Noray / lobby improvements
  - [x] noray bug on client connect sometimes: Invalid access of index '1' on a base object of type: 'PackedStringArray'.
    - [x] maybe when game id is wrong?
  - [x] auto detect game join code or ip address
  - [x] toggle between port/ip & noray mode
  - [x] noray timeout
  - [x] client doesnt see invite code/ip
  - [x] dont allow players to select menu levels
  - [x] copy game id when hosting right away
  - [x] leave game = reset network settings to default
- [x] on server disconnect, reload bg-menu-level for clients

- [x] deploy noray server

- [x] Add nat punch (netfox.noray) to make lobbies

- [x] singleplayer mode logic (just host! & be a server)

- [x] camera switching
- [x] Make server authoritative
  > cleanup player_entity so only local cams are used, etc.
  - [x] Change `PlayerEntity._enter_tree()` to `set_multiplayer_authority(1)` (server owns all)
  - [x] Add `receive_input()` RPC to `InputController`
  - [x] In `InputController._process()`: if local, send input to server via `receive_input.rpc_id(1, ...)`
  - [x] Store received input per-player on server (Dictionary keyed by peer ID)
  - [x] Move `MovementController._physics_process()` to only run on server
  - [x] `MovementController` reads input from server's input buffer instead of local `InputController`
  - [x] Add `MultiplayerSynchronizer` to `PlayerEntity` for position/rotation
  - [x] (Later) Integrate netfox for client prediction + rollback reconciliation
- [x] Create NetworkManager
  - [x] Create lobby
    - [x] players can join / be seen
  - [x] plan MP authority
    - [x] only host can start game
    - [x] host chooses level, others can see
  - [x] Create SpawnManager & sync players
  - [x] set username
- [x] Connect \_on_peer_connected to add_player_to_lobby
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
