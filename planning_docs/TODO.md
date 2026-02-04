# TODO

> Don't forget, have fun :D

## In Progress 🚀

- [ ] Create basic PauseMenu scene/ui
  - [x] Create scene/script
  - [ ] Option to go back to main menu
  - [ ] Pause / resume functionality

## Up Next 📋

- [ ] Git LFS https://www.youtube.com/watch?v=4Ln6iRh_LTo
- [ ] Create Player pt 1
  - [ ] Player scene + component script
    - [ ] See moto-player-controller
- [ ] Create InputManager
  - [ ] camera control
  - [ ] bike control
- [ ] Create Test Level - Zoo - all relevant models/scenes in 3d space to easily compare
  - (E.g. diff bikes/mods on each bike)
  - There's a godot plugin for this
- [ ] Create Player pt 2
  - [ ] character from selection
    - [ ] character base (select male/female)
    - [ ] accessories (cosmetics, etc.) (**basic customization**)
  - [ ] bike from selection
    - [ ] bike base (select bike)
    - [ ] mods (color, actual mods) (**basic customization**)
- [ ] Create Test Level - Gym - player controller, with tp. Basically in game documentation.
  - (E.g. How far can you jump)
- [ ] Player pt 3
  - [ ] bike physics / movement / gearing
  - [ ] animation w/ IK
  - [ ] few tricks 

## Backlog

- [ ] Create NetworkManager
  - [ ] Create lobby
    - [ ] Web RTC if possible for web export?
    - [ ] players can join / be seen
    - [ ] text chat
  - [ ] plan MP authority
    - [ ] only host can start game
    - [ ] host chooses level, others can see
  - [ ] refactor if needed
- [ ] Create SpawnManager
  - [ ] spawn players in game
    - [ ] Should show their customizations
  - [ ] sync player positions
  - [ ] sync animations (tricks)
- [ ] Create TrickManager
  - [ ] connect w/ NetworkManager
  - [ ] trick detection in player component
  - [ ] trick scoring in own script
- [ ] Create Save System
- [ ] Create GamemodeManager
  - [ ] free roam w/ friends
  - [ ] race
- [ ] Create basic SettingsMenu scene/ui
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

## Polish / Bugs

- [ ] Setup cloudflare image upload in vscode
- [ ] Quit on Web should just escape fullscreen
- [ ] Add transition animations (e.g. circle in/out) between Menu States / Loading states

## Done ✅

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
