# TODO

> Don't forget, have fun :D

## In Progress 🚀

- [ ] Create Player Part 2

  - [x] ~~**Delete** all imported stuff and start clean. Use old code as reference~~
  - [x] Refactor/cleanup
  - [x] Fix collision
  - [ ] Decide what should be client side vs server side
    - [ ] Make sure MP authority is set properly
    - [ ] Sync as little as possible
      - no input/movement/gear calculations
      - no sound for other players for now
      - sync animations (procedural position)
      - sync bike pos/rot
  - [ ] Update [doc](./PlayerController.md)

- [ ] Redo movement_controller

  - [ ] finish cleanup (function split)
  - [ ] improve physics
  - [ ] be able to ride up ramps
    - [ ] (maybe raycast to rotate to normal?) one for each wheel?
    - [ ] Use speed/momentup to stay on ramps (e.g. loop)
    - [ ] ignore 15deg for wall
    - [ ] handle gravity manually.
    - [ ] Slow down as you go up in angle
  - [ ] 2 difficulties, arcade & sim. Sim grants 1.5x score
    - [ ] arcade still has gear changes, no clutch except to start wheelie
      - [ ] WASD support

- [ ] Create Player part 3

  - [ ] Add HUD
  - [ ] AnimationController + Trick integration
    - [ ] debug wheelie animation
    - [ ] debug naked bike init ik / load default animation not working
  - [ ] AnimationController + Crash integration
    - [ ] Create crash animation (procedural)
  - [ ] Improve crash_controller
    - [ ] Brake danger
    - [ ] Layer 2 collision (with objects)

- [ ] Review Animation Controller & Create animations
  - [ ] Create lean (turning) animation
  - [ ] Create stopped/idle animation
  - [ ] Create wheelie/stoppie animation
  - [x] claude created a system
  - [x] Review planning_docs/AnimationController.md
  - [x] Create way to play specific animations
- [ ] signal relay host setting update doesn't save ? Double check!
- [ ] review webrtc gen code myself (security)

## Up Next (Finish POC MP Gameplay Demo) 📋

> POC = playable gamemodes w/ friends, see if core gameplay loop works
> video record this once playing with everyone, save log files

- [ ] Trick Manager + tricks

  - [ ] trick system
    - [ ] migrate wheelie / stoppie tricks
    - [ ] ramp tricks
    - [ ] ground tricks
  - [ ] trick detection in trick_controller
  - [ ] trick scoring in separate system
    - [ ] e.g. player emits trick_done & gamemode manager does something with it.
      - [ ] e.g. race/freeroam => boost
      - [ ] e.g. stunt race => combo counter
  - [ ] Create wheelie + DOWN animation (wheelie + right hand touches ground)
  - [ ] Create Heel clicker / other trick animations

- [ ] Basic customization menu / UI

  - [x] Super basic customize ui
  - [x] Save chosen skin to disk
    - [x] path to skin_def for now, no custom json yet
    - [x] player_entity
      - [x] save_skin
      - [x] load_skin
    - [x] when spawning player in game, show their customizations via load_skin
  - [ ] Create customize menu background scene
    - [ ] Garage scene
    - [ ] show character
    - [ ] show bike
  - [ ] Create customize menu UI
    - [ ] Tab for shop
      - [ ] List purchasable skins
      - [ ] Purchase bike skins
      - [ ] Purchase character skins
    - [ ] Tab for "my stuff"
      - [ ] List purchasedskins
      - [ ] Choose a bike skin
      - [ ] Choose a character skin

- [ ] Basic Traffic AI

  - [ ] Collisions w/ bikers (causes a crash)
  - [ ] Navigates in Loops, dumb AI
    - [ ] Maybe along path?
    - [ ] Maybe use AnimationPlayer?

- [ ] Create Save System for in-game

  - [x] Save bike definitions on disk
  - [ ] save unlocked tricks, mods, etc.
  - [x] Save levels / player stuff

- [ ] Basic core gameplay loop / implement gamemodes

  - [ ] start gamemodes via map select
  - [ ] Game modes:
    - [ ] Free roam
      - [ ] Get Score saved to disk for tricks
    - [ ] Street race
      - [ ] w/ and w/o traffic
      - [ ] Podium scene after race ends
      - [ ] Get Score saved to disk w/ bonus for podium
    - [ ] Stunt race
      - [ ] Mario kart like - get items to attack players or help self, but do tricks to get items. More complex tricks = better items
  - [ ] Unlock Skins w/ Score from disk & spend

- [ ] More audio
  - [ ] add clunk sound when changing gears
  - [ ] Crash SFX
  - [ ] Tire Screetch SFX
  - [ ] Menu click sounds
  - [ ] Music?

## Backlog

- [ ] Gamemode / Score / XP / $ v2

  - [ ] Collect via challenges in gamemodes
    - [ ] Freeroam:
      - [ ] Collect items
      - [ ] Lobby Leaderboard Challenges (longest wheelie on server, biggest crash, etc.)
      - [ ] Weekly Challenges (5x crashes, hold wheelie for 20s, etc.)
    - [ ] Race:
      - [ ] Podium finish
      - [ ] Lobby Leaderboard Challenges (fastest lap time, top speed, most crashes)
      - [ ] Weekly Challenges (wheelie during a race, boost 5 times, etc.)
  - [ ] Spend
    - [ ] Unlock tricks
    - [ ] Unlock cosmetics
    - [ ] Unlock performance mods

- [ ] Audio Manager v2

  - [ ] Use fmod to blend sounds @ rpm
  - [ ] Record my bike for sounds
    - [ ] Wind sounds at high speed
    - [x] startup
    - [x] idle
    - [ ] holding rev at diff rpm, switch files in game
    - [ ] full rev
    - [ ] exhaust pops
    - [ ] downshift/rev match
    - [ ] shifting gears
  - [x] Make audio buses
    - [x] 2d - SFX (ui sounds, timers, etc.)
    - [x] 3d - SFX (RPM / bike)
    - [x] 2d - Music
  - [ ] Different bikes use different audio samples

- [ ] Multiplayer improvements
  - [ ] return to lobby (force everyone)
  - [ ] review all code & cleanup to call authority done
  - [ ] update Architecture.md
  - [x] saving settings doesnt update noray host
- [ ] software is open source, but assets aren't public
- [ ] Pizza Delivery game mode

  - [ ] start at Pizza shop & use scooter to make deliveries across town in time.
  - [ ] Multiplayer too, they have different houses to go to
    - [ ] Or compete to get there first

- [ ] map

  - [ ] Outline of island is the shape of an F1 track, and is drivable. The inside is the island map itself
    - [ ] Brazil track
    - [ ] Moom map? Low gravity
    - [ ] 3D printer map => level is 3d printed in real time
    - [ ] start with graybox/repeating grid texture to plan out maps before are is decided , use multiple colors & labels

- [ ] More Customization UI / menu

  - [ ] Add Bike customization
    - [ ] **BikeDefinition** with component definitions under it since I will have multiple bike types, colors, and mods for each type.
      - [ ] character accessories (cosmetics, etc.)
        - [ ] helmet
        - [ ] backpack
      - [ ] bike mods (color, actual mods) (**basic customization**)
      - [ ] base mesh **MeshDefinition**
      - [ ] color override
      - [ ] BikeMod list
        - [ ] **ModDefinition**
          - [ ] **MeshDefinition**
          - [ ] **Marker3D**
          - [ ] script
  - [ ] Add Character customization (choose character for now)
  - [ ] Change color w/ color picker

- [ ] Vibe code a painterly shader I can add as an extra pass. Add brush stroke lines

- [ ] Tutorial level 1
  - [ ] Explain how to progressively brake
  - [ ] Go this fast & brake, don't squeeze hard asap, slowly squeeze.
  - [ ] Force them to try again til they get it
- [ ] Create Test Level - Gym - player controller, with tp. Basically in game documentation. (E.g. How far can you jump)

  - [] Make the world fit around the player controller.
  - [ ] [ramp physics](https://www.reddit.com/r/godot/s/O6aKthtk9i)

- [ ] Create Test Level - Zoo - all relevant models/scenes in 3d space to easily compare

  - (E.g. diff bikes/mods on each bike)
  - There's a godot plugin for this
  - https://binbun3d.itch.io/godot-ultimate-toon-shader

- [ ] Camera control
- [ ] Dedicated server

  - [ ] Lobby is created, then sends it's IP to a matchmaking server (http)
  - [ ] When creating lobby, add invite only mode or open lobby
  - [ ] Server browser can list all servers that register
  - [ ] Add game mode for open lobby (for server to reset to with 0 players) or just go to free roam?
  - [ ] Quick join lobby

- [ ] Create complex traffic / AI system

  - [ ] basic traffic sim
  - [ ] implement A\* pathfinding? w/ state machine?
    - [ ] drive, stopped at light, parked, etc.
  - [ ] create sequence system?

- [ ] Create Test Level - Museum - functionally show how systems work, text explaining the systems.
  - (E.g. showing physics demos, how scripted sequences work)
- [ ] Create Island Level

  - [ ] render trees/etc. with multi mesh

## Polish / Bugs

- [ ] reactive sounds (play when player does something) = juice
- [ ] Add transition animations (e.g. circle in/out) between Menu States / Loading states
- [ ] Add text chat
- [ ] Web
  - [x] WebRTC (?)
  - [ ] Quit on Web should just escape fullscreen

## Done ✅

- [x] disconnect after some period of time

  - [x] Lobby closes?

- [x] customize skin from pause menu

  - [x] menu context
  - [x] actually update in game

- [x] fix webrtc WAN not connecting => it was dns

- [x] noray => WebRTC

  - Use webrtc for nat punch thru with stun/turn server
  - Coturn docker to host
    - https://github.com/coturn/coturn/blob/master/docker/coturn/README.md
  - Signaling / matchmaking server in go? or is this possible in godot?
  - https://github.com/godotengine/godot-demo-projects/tree/master/networking/webrtc_signaling
    - server/
    - client/
  - https://github.com/jonandrewdavis/andoodev-godot-web-rtc-p2p
    - full demo, but not using std tools
  - https://www.reddit.com/r/gamedev/comments/1872muu/nat_traversal_solutions_for_multiplayer_in_godot/

- [x] cleanup lobby / joining w/ player definition

- [x] Create PlayerDefinition & Save system

  - [x] save selected skins
  - [x] save username
  - [x] save money

- [x] move spawn to spawn manager from level manager

- [x] Make SettingsMenu work with pause menu (compose this somehow)

- [x] level select img

  - [x] Load folder's images in menu
  - [x] Add doc

- [x] Create basic SettingsMenu scene/ui

  - [x] Create scene
  - [x] Improve the UI
  - [x] Add all components
  - [x] Functional settings

- [x] make working volume settings

- [x] fix github actions ci

- [x] customization resources aren't found at export/build time

- [x] Audio Manager

  - [x] fmod bike sounds
    - [x] Seamless loop w/ RPM

- [x] bugs

  - [x] Add version # + version check in game
  - [x] set max char limit for name
  - [x] First launch noray setting is not working, can't host properly. 2nd launch it works
    - [x] implement
    - [ ] TEST

- [x] saving not loading into selected item in ui

- [x] window settings, not updating ui when saving

- [x] Basic test map

  - zylann/godot_heightmap_plugin
  - [ ] big enough for game modes w/ friends
  - [ ] Option to enable/disable traffic
  - [ ] test_street_race_01
  - [ ] test_freeroam_01

- [x] Create Player Part 3

  - [x] place characterskin on the bike
  - [x] create bikeskin the same way characterskin works
  - [x] IK animations https://youtu.be/MbaPDWfbNLo?si=p5ybcrLUJje_nBgd

- [x] Bike definition

  - [x] bike model
  - [x] color
  - [x] markers (hand, pegs, seat/butt pos , mods)
  - [x] actually use the skins in player entity
  - [x] fix player entity

- [x] Splash screen / animation

  - [x] Add as the splash_loading_menu
  - [x] Option to press any btn to skip

- [x] singleplayer doesn't spawn

- [x] CharacterSkin / mesh

  - [x] move butt w/ marker

  - [x] Find a good way to import meshes with rigs
  - [x] Import animations in a uniform way
  - [x] document
  - [x] change material (colors)
  - [x] use resources to control
  - [x] add marker3d in resource to place accessories
  - [x] add ragdoll
  - [x] add IK
    - [x] generation process
    - [x] arms
    - [x] legs
    - [x] head/look at
  - [x] add basic test animation

- [x] multiplayer / spawn mgr cleanup

  - [x] close server when going to main menu
  - [x] join game during play
    - [x] WIP - **MUST REVIEW THE CODE MYSELF**

- [x] Create GamemodeManager

  - [x] create system
  - [x] Move spawning logic from level manager to gamemode manager
    - [x] Make test level default free roam mode

- [x] username in lobby

- [x] Create settings save system

  - [x] Save custom username for lobbies
  - [x] add noray relay host in config file for game
  - [x] window settings (fullscreen or not)

- [x] on spawn, make players virtually press c

  - [ ] by default they're looking at the hosts camera

- [x] respawn in pause menu

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
