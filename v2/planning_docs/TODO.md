# TODO
> Don't forget, have fun :D

## In Progress 🚀 — Current Sprint

- [ ] [new roads](../PLAN-roads.md)
  - [ ] Just use Terrain3D instead of creating all this complexity

## Playtest bugs

- [ ] add delete button to Customize Bikes Loadout menu
- [ ] host can't go to customize bc others will leave
- [ ] height is offset for some clients

## HI-PRI (next sprint candidates) ‼️
- [ ] New maps for gamemodes
  - [ ] Make racetrack map
  - [ ] Make drag strip map
  - [ ] Make stunt playground map
  - [ ] Then copy them to the main city map once working
- [ ] track tricks in race
  - [ ] for bonus score
  - [ ] for boost?
- [ ] Trick Battle / Score Attack gamemode
  - [ ] 3 rounds, highest score in 60s wins round, best 2/3 wins game
  - [ ] Live scoreboard / trickfeed
  - [ ] 2 locations for variety
- [ ] add ground detection to animation controller
  - [ ] `two_left_feet` — feet follow ground
  - [ ] hand drag scraper wheelie
  - [ ] Make two_left_feet also work on the right
    - [ ] add anim when switching between them to hop over whole bike
- [ ] More tricks (depends on Phase 2 refactor):
  - [ ] Superman / no-handed spread eagle
  - [ ] Whip / table
  - [ ] Drift
  - [ ] Burnout (stationary)
- [ ] Wings as mod for sport bike
- [ ] Start enemy AI — wants to go to next checkpoint location
- [ ] Fade out intro sound quicker, make 3 sec version
- [ ] Gamemode switching cleanup:
  - [ ] controller support on HUD buttons in event start circle / win-lose screen (move to menu system?)
  - [ ] tutorial gamemode `_ctx` doesn't make sense

### Code review followups (separate cleanup sprint)
- [ ] [code review time](./code-review-20260430.md)
  - [ ] split bikeskindefinition
  - [ ] signal mismatches
  - [ ] resource paths `user://`
  - [ ] duplicate logic
  - [ ] missing `_get_configuration_warnings`
  - [ ] todos & dead code

---

## Backlog 📋

### Gameplay modes (future)
- [ ] Crash Launch gamemode (drag race → low fence → furthest body wins)
- [ ] Wheelie Battle gamemode (longest wheelie / most combo tricks)
- [ ] Stunt Race (mario-kart-like — tricks earn items)
- [ ] Pizza Delivery
- [ ] Follow the Leader / H.O.R.S.E.
- [ ] Cops & Robbers
- [ ] Bowling gamemode?
- [ ] Endless mode (arcade-style)

### Tutorials (post-Challenge-system)
> Most of these become challenges (see Phase 3). Keep this list only for true newbie onboarding.
- [ ] basic movement
- [ ] progressive braking
- [ ] how to power wheelie & stoppie
- [ ] how to clutch up
- [ ] balance point
- [ ] trick mods
- [ ] ramps & air tricks
- [ ] clutch-up tutorial & speed management
- [ ] crashing during tutorial doesn't stop timers
- [ ] tutorial press RT/B should depend on controlscheme

### Tricks
- [ ] trick scoring & combos
- [ ] trick tweaks
  - [ ] Land into wheelie / stoppie should be a trick
  - [ ] Wheelie + RIGHT animation (hand grab) — IK hand twd ground
- [ ] once speed hits 0 mid-air, lose all ability to rotate fwd/back
- [ ] Scraper mod — add sparks

### Animation
- [ ] Broader cleanup of `animation_controller.gd` (Phase 2 only narrowly refactors trick dispatch)
- [ ] AnimationController + Trick tweak integration
- [ ] AnimationController + Crash integration
  - [ ] Create crash animation (procedural)
- [ ] backflip landing is snappy, always lands in wheelie/stoppie
- [ ] wheelie turning animation should yaw

### Multiplayer / netcode
- [ ] Move respawn logic to gamemode controller using new signals
- [ ] return to lobby (force everyone)
- [ ] review all code & cleanup to call authority done
- [ ] update Architecture.md
- [ ] Review WebRTC gen code for security

### Customization / progression
- [ ] Save System for in-game
  - [ ] player score / $ / progression
  - [ ] gamemode outcomes
  - [ ] total trick history (total time played, total wheelies, etc.)
  - [ ] unlocked tricks, mods, etc.
- [ ] Basic customization menu / UI
  - [ ] Add constraints to mods (certain skins require 2 colors, etc.)
  - [x] Custom colors option
  - [x] Subviewport to make icons (bike skin selection)
  - [ ] Customize menu background scene (garage?)
  - [x] show character
  - [x] show bike
  - [ ] Shop tab (purchase bike + character skins)
  - [ ] My Stuff tab (choose bike + character skin)
- [ ] More Customization UI 
  - [x] grid w/ icons
  - [ ] character customization
  - [ ] color picker
- [ ] Unlock skins w/ Score from disk & spend
- [ ] Score / XP / $ v2 (challenges, leaderboards, weekly)
- [ ] 2 difficulties (arcade vs sim — sim 1.5× score)

### Audio
- [ ] Soundscapes for ambient sounds
- [ ] Tire Screech SFX
- [ ] Music
- [ ] [Web audio fix](https://github.com/utopia-rise/fmod-gdextension/pull/210#issuecomment-3717948490)
- [ ] Audio Manager v2 (FMOD RPM blending, record bike, per-bike samples)

### AI / traffic
- [ ] Basic Traffic AI (collisions, loops, near-miss trick → wheelie variant)
- [ ] Complex traffic / AI system (A* pathfinding, state machine, sequence system)

### Levels / map
- [ ] Gamemode select on map select (tutorial 01 plays specific gamemode on specific map)
- [ ] Island Level (multimesh trees)
- [ ] Test Levels: Gym, Zoo, Museum
- [ ] Outline of island = F1 track shape (drivable perimeter; Brazil, Moon, 3D printer maps)

### Polish / bugs
- [ ] Pause => show lobby
- [ ] mute option in settings
- [ ] mute when out of focus
- [ ] find hook for dank nooner — what makes it cool!
- [ ] broken back button via: play → lobby → back → customize → back
- [ ] back from lobby → customize goes to play menu instead of lobby menu
- [ ] Free play → back → host game broken (creates dupe multiplayer init)
- [ ] add to MenuState validation ("set return_state on Enter()")
- [ ] Camera zoom out FOV w/ speed / current_trick
- [ ] Update settings via controller
- [ ] Add loading UI (show when switching levels)
- [ ] reactive sounds = juice
- [ ] Transition animations between menu states
- [ ] Add text chat
- [ ] First launch is v slow (compiling shaders); freezes on Mac in exported binary
- [ ] Remap controls for leaning back/fwd (mouse / arrow keys)
- [ ] Improve CrashController
  - [ ] Brake danger
  - [ ] Sync w/ players (crashing into player = both affected)
  - [ ] Swap to rigidbody, bounding box of mesh + velocity
  - [ ] Emit signals to gamemode controller
- [ ] Camera should not rotate with player (loops, ramps)

### Meta / misc
- [ ] Meme mode setting (for sfx)
- [ ] incentivize being on road part 2 (`unstable_surface_factor` + VFX from `_on_unstable_surface`)
- [ ] Option to change localization language
- [ ] Android keystore + github secrets + build.yml
- [ ] https://docs.discord.com/developers/resources/invite
- [ ] Slow time on ramp launches (client side somehow?)
- [ ] Friends + invites + server browser
- [ ] Dedicated server (matchmaking, quick join, open lobby gamemode)
- [ ] software is open source, but assets aren't public
- [ ] Vibe code a painterly shader pass (brush stroke lines)
- [ ] Gamemodeobjects (show/hide things, call generic functions)
- [ ] Competitive modes

## Done ✅

- [x] XSR900 sounds

- [x] Use Curves to create roads (godot or blender?)

- [x] character card selector

- [x] Loadout card should have set active btn below select

- [x] add ability to ride specific bike that is not saved
  - [x] See [plan](./PLAN-bike-save.md)
  - [x] select from saved bikes?
  - [x] force bike per event?

- [x] Reusable 3D Thumbnail System
  - [x] See [plan](./PLAN-bike-save.md)

- [x] ~~Make lobby invite code stay the same when going to main menu~~

- [x] change map within lobby possible 

- [x] In-world UI - speech bubble

- [x] work on playtest bugs

- [x] starting the gamemode for everyone doesn't work as expected

- [x] add ability to stop race (see restart race)

- [x] **Phase 2:** [PLAN-animcontroller-refac.md](./PLAN-animcontroller-refac.md) — adding a new trick should be ONE edit, not five

- [x] Jose — controls too hard to do a wheelie
  - [x] fall return speed too fast

- [x] Resizing window should save in settings

- [x] **Phase 1:** [PLAN-bug-fixes.md](./PLAN-bug-fixes.md) — stabilize playtest bugs

- [x] if one player crashes during countdown, they need to manually respawn before they can start

- [x] restart race btn (for jump)

- [x] respawning in race doesn't work

- [x] crashing during race kills engine audio / can still move in spawn

- [x] trick sounds happen for everyone → make local-only

- [x] all spawned under map → use `GridSpawnTask` in free roam

- [x] Add purple color

- [x] Add grom sound

- [x] when coming back from a stoppie, the angle is not fully reset until i start doing a wheelie, so the rear tire is off the ground.

- [x] incentivize being on road part 1
  - > make going on certain collision layer slower / less stable.
  - [x] `unstable_collision` layer 5
  - [x] make it unstable

- [x] Basic lap / race mode
  - [x] checkpoints / lapping system
  - [x] work w/ multiplayer (spawns)

- [x] Respawn locations depend on last TP location

- [x] switching bike crashes game

- [x] clutch dump wheelie is perfectly balanced

- [x] Should not be able to clutch up in 4th gear going 1mph

- [x] Play tada when completing a trick

- [x] Use %GromRevs

- [x] add 3 2 1 countdown from 5 sec clip

- [x] Cleanup gamemode objective / review code
  - [x] See scratchpad.md
  - [x] create PLAN.md
  - [x] Code / refactor
  - [x] Update GamemodeSystem.md

- [x] add option to play / stop sound for `GameModeTask`
  - [x] Countdown sfx

- [x] Be able to reverse (play animation)
  - [x] Hold clutch, brake to reverse

- [x] [FMOD on web export](./fmod-web-fix.md) — build `libGodotFmod.web.*.wasm32.wasm` from PR #210 branch & wire it in

- [x] Use checkpoint marker in a step

- [x] Is gamemode_objective just a StateMachine?

- [x] Finish / create [PLAN-gamemode-objective-collapse](./PLAN-gamemode-objective-collapse.md) system
  - [x] **half-way thru, see branch** `mid-vibe`
  - [x] Add TPObjective type - so we can respawn at different locations
    - [x] Respawn after get up to speed
    - [x] Move change gears next,
  - [x] add option to countdown_tutorial_step to not show timer
  - [x] Move teleport_tutorial_step and countdown_tutorial_step to generic, non tutorial
  - [x] rename tutorial in gamemmodemanager to sequential?

- [x] Fix sparks when crashing during 2 foot trick mid way

- [x] add sparks to two_left_feet

- [x] Always crash after landing a heel clicker, not just during

- [x] player is leaning back while doing the idle anim, it shouldnt be

- [x] Trick Manager + tricks
  - [x] wheelie / stoppie detection
  - [x] flip detection
  - [x] in-air tricks
    - [x] Create Heel clicker / other trick animations (RB+DOWN)
  - [x] more ground tricks
  - [ ] Cleanup trick / animation / movement code (at least review!)
  - [ ] trick scoring & combos
  - [ ] trick tweaks
    - [ ] Land into wheelie / stoppie should be a trick
    - [ ] Create wheelie + RIGHT animation (hand grab)
      - [ ] IK hand twd ground, not just backwds
  - [ ] once speed hits 0 mid air, i lose all ability to rotate fwd/back
   - [ ] related to wheelie / playerent angle being diff?
   - [ ] easier on KBM

- [x] Game won't launch with skin loading

- [x] Update customization menu
  - [x] Show bike + list of all color_mods(gotta check for multiple colors for bike type, so set that as a var in the skin_definition & make the color_mod have a matching count. constraints?)

- [x] Animation Controller:
  - [x] Create trick animations to use in trick manager
    - [x] `heel_clicker`
    - [x] `high_chair` 
  - [x] Fix wheelie rotation / placement (puts you in the ground - find / fix solution)
  - [x] Better IK
    - [x] debug bike IK placement / playing procedural w/ offsets
    - [x] arms must follow handlebars
    - [x] Learn how the steering/wheel spinning animations work
    - [x] animation controller cleanup
    - [x] Create stopped/idle animation
    - [x] init IK does not save per bike, switching positions from sportbike to mini is broken, uses prev value!
    - [x] wheelie => 0 speed in wheelie => idle animation => starts floating?!
    - [x] idle animation janky af, doesn't mix with procedural leaning/etc very well.
    - [x] Blend animations (AnimationTree?)
    - [x] Fix jerkyness from transitioning between IK animation & procedural, do some blending?
      - [x] e.g. steering, then going to idle, butt shifts weird
      - [x] e.g. leaning during steering, then going to idle

- [x] Delete bike_def.colors

- [x] Save a few variants

- [x] Delete other variants

- [x] **impl planning_docs/PLAN.md**

- [x] Review AI code - there are bugs!

- [x] account for wheelie angle when doing flips & landing, aka once in air turn off wheelie, make it complete & set wheelie angle to 0

- [x] Crash animation follow camera

- [x] fix clutch dump from 0 speed

- [x] Loading Menu

- [x] Organize todos

- [x] Review Animation Controller & Create animations
  - [x] Create lean (turning) animation
  - [x] Create wheelie/stoppie animation
  - [x] Add pull/lean back animation when starting a wheelie
  - [x] claude created a system
  - [x] Review planning_docs/AnimationController.md
  - [x] Create way to play specific animations

- [x] GamemodeEvent System & First tutorial
  - [x] vibe code tutorial / connect systems from [GamemodeSystem.md](./GamemodeSystem.md)
  - [x] Review tutorial code
  - [x] Review gamemode transition code when entering circle to starting tutorial mode
  - [x] Single/multiplayer support

- [x] Update tutorial mode to choose tutorial steps

- [x] speed it capped at 30 in 1st gear, but RPM keeps climbing these should happen at the same time

- [x] Lean back/fwd animation

- [x] Crash on the back of ramps

- [x] reduce brake amount

- [x] when crashing upside down, the wheelie balance bar shows up on respawn

- [x] Mouse cursor showing/hiding in gamemode event should be handled in gamemodeeventconfirmhud via rpc insetad of in freeroamgamemode
  - [x] start circle hud, leaving doesn't reset mouse back to original captured state

- [x] Bug: Crash respawn when client messes up rotation/animation

- [x] uncheck ip/port btn when going from free roam to play menu

- [x] Add colors to redline RPM

- [x] gamemode select hud shows on all clients
  - [x] basic

- [x] trick started keeps emitting/printing during the trick, should only happen once...

- [x] mobile, move LB to left..

- [ ] Move respawn logic to gamemode controller, using new signals

- [x] Improved (non-text) HUD

  - [x] add rpm guage from pics
  - [x] Overlay layer for tutorial
  - Ideas:
    - In-world UI
    - Bottom right has guages like IRL bike (analog)
    - Center has guages like TFT (digital)
    - Grip / danger:
      - Bottom, wide red line
      - Red overlay like COD dmg
      - Guages have red overlay & change size
    - Mini Map? or Compass w/ arrow

- [x] touchscreen controls for mobile

- [x] Redo movement_controller

  - [x] Improve RPM Blending
  - [x] Launching off ramp kills speed
  - [x] player can fly if leaning when launching off loop
  - [x] Stop Wheelie-ing by riding then tapping clutch once will hold it perfectly
  - [x] Super laggy when riding w/ friends
    - [x] Rubber banding is crazy here
  - [x] WASD support

- [x] disable current option when using help / controls menu, change type to radio/toggle

- [x] Basic show controls UI

- [x] on clients:

  - [ ] When crashing into something during a wheelie, you respawn broken.
    - [ ] in half wheelie anim, without body
    - [ ] "Crashed...respawning" in HUD
  - [x] cant change gears after going from 1=>2

- [x] web mobile seems to crash? Spawn in with no controls hud or body

- [x] don't copy IP to clipboard if free play

- [x] can't crash upside down anymore, look at backflip code in crash_controller

- [x] Reduce air drag, test on mega ramp

- [x] Touch controls don't work

  - [x] Should work on web on phone
  - [x] Maybe build apk too

- [x] Stoppie balance bar broken

- [x] Balance point showed like grinding balance in tony hawks pro skater in HUD

- [x] Make loopdeloop larger

- [x] more wheelie angle overall

- [x] adjust pitch mid air

- [x] movement_controller updates

  - [x] finish cleanup (function split)
  - [x] basic wheelies / stoppies
  - [x] improve physics
  - [x] be able to ride up ramps
    - [x] (maybe raycast to rotate to normal?) one for each wheel?
    - [x] Use speed/momentup to stay on ramps (e.g. loop)
    - [x] handle gravity manually.
    - [x] Slow down as you go up in angle
  - [x] Launch off ramps to catch "hang time" (adjust gravity)
  - [x] loop de loop code

- [x] WebRTC doesn't ALWAYS work?

  - [x] Lobby code works, but TURN/STUN doesn't
  - [x] Check connection outside of home wifi

- [x] Camera improvements

  - [x] Fix camera follows wrong person!
  - [x] Pausing loses mouse for rotating camera
  - [x] rotate w/ mouse/joystick
  - [x] settings for sensitivity/invert/tps|fps mode
  - [ ] Camera should not rotate with player (e.g. loops, ramps)

- [x] Add HUD for player

  - ![ride-hud.png](./img/ride-hud.png)
  - See [tps-hud.excalidraw](./diagrams/tps-hud.excalidraw)
  - [x] Basic text only HUD
  - Reqd:
    - [x] Throttle
    - [x] Speed
    - [x] Brake
    - [x] Clutch
    - [x] Gear
    - [x] Grip (danger)
    - [x] Place for trick messages
    - [x] Place for gamemode messages (place, lap time, etc.)
    - [x] Place for challenges panel

- [x] signal relay host setting update doesn't save ? Double check!

- [x] Create Player Part 2

  - [x] ~~**Delete** all imported stuff and start clean. Use old code as reference~~
  - [x] Refactor/cleanup
  - [x] Fix collision
  - [x] Decide what should be client side vs server side
  - [x] Make sure MP authority is set properly
  - [ ] New netcode changes / authority:

    - [x] InputController
    - [x] GearingController
    - [x] MovementController
      - [ ] Move pitch_angle/lean_angle out to player_entity since they're sync'd
    - [x] AnimationController

  - [x] Sync as little as possible
    - no input/movement/gear calculations
    - no sound for other players for now
    - sync animations (procedural position)
    - sync bike pos/rot
  - [x] Update [doc](./PlayerController.md)

- [x] Sync clutch inputs & gear changes w/ server

- [x] holding clutch while reving makes you move when it shouldn't

- [x] Mac build won't run

- [x] bikeskin have front & rear wheel markers for wheelie / stoppie offsets

- [x] web updates:

  - [x] rm quit button, replace with Press ESC x2 to quit
  - [x] don't go fullscreen in default settings

- [x] Web

  - [x] WebRTC (?)
  - [x] Quit on Web should just escape fullscreen

- [x] Deploy web to github.io

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
