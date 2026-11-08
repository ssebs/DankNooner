# Tours + Tutorial (WIP): spec and implementation plan

> **For the implementing agent:** read `CLAUDE.md` first; its rules apply to every task. Work
> through the tasks in order, using superpowers:executing-plans (or
> superpowers:subagent-driven-development). Steps use checkboxes (`- [ ]`). Stop after each
> **User playtest** step and hand back to the user. You never run the game yourself.

Two connected pieces, built in this order:

1. **Tours**: a reusable driver.js-style onboarding overlay that teaches one mechanic the first
   time a player reaches it.
2. **Tutorial**: a mandatory 3-mission tutorial on a new graybox map, built from tours plus
   gamemode tasks. It gates the rest of the Play menu, including StuntCity.

---

## Progress (2026-11-07)

**Tasks 1 to 5 are built; 1 to 4 are playtested.** Task 5's last round (outline-only action
steps, the read-only `*` step, the recolor snapshot) still needs a playtest. Then resume at
**Task 6**. Where the built code differs
from the task text below, this section wins:

- **Tour buttons:** no `InputPrompt`s beside Next/Back (user cut them). Back reuses
  `BACK_LABEL`; new keys are only `TOUR_NEXT`, `TOUR_SKIP`, `TOUR_DONE`.
- **Device detection** lives in `InputStateManager` (`is_gamepad` + `device_changed`), not in
  `TourManager`. Menus with no player read it; `GarageUI.open()` takes `input_state_manager`.
- **Token aliases:** `TourManager.ALIASES` maps tokens that aren't one action, per device:
  `{cursor}` (mouse / plain left stick icon) and `{click}` (`use_item` / `ui_accept`).
- **Action steps:** `TourStep.done_when: Callable`, set at runtime by the owning scene. While it's
  set, Next hides, input goes back to the saved state (menu works normally), the screen isn't
  dimmed (outline only), and the tour advances once it returns true. `TourManager.skip()` closes a
  tour whose owner is leaving. Usable for tutorial lessons too.
- **Fill-up tour:** `play_once` is `call_deferred` from `_on_session_start()`, because
  `_start_session` sets `IN_MINIGAME` after it. The input state restore on close is deferred, so
  the closing press isn't read by the minigame. The warning line is a plain Label (no tokens).
- **Customize tour** (6 steps): intro, Profile tab, loadout tabs, **add a loadout** (action,
  targets `+`), **recolor it** (action, targets the garage panel), then a read-only step on `*`
  and Set Active (targets the tabs). Not forcing Set Active was a user call.
- **Garage pad support:** LB/RB `InputPrompt`s beside the tab strip (pad only). RB past the last
  tab focuses `+` (focus shows the selected-tab underline + blue text); accept adds a loadout.
- **Debug:** `dbg_reset_tutorials` clears tours and tutorial progress.
- **Icons added:** `resources/img/Icons/xbox_stick_l.svg`, `mouse_move.svg` (from the Kenney pack).
- **Open nit:** new loadouts are named "2", "3" while the first is "Loadout 1"
  (`GarageUI._add_loadout`). Not changed.

---

## Part A: Spec

### Why

A Steam Deck playtester couldn't work out the fill-up controls; the prompt line doesn't teach
"tap, don't hold". New players also get dropped into StuntCity with nothing that teaches the bike.
Both are in the demo's scope (Next Fest, Feb '27).

### Goals

- Every mechanic that needs explaining gets a tour that's shown once and saved as done.
- A new player can't miss the basics, because the tutorial comes before anything else.
- One system serves both: a tutorial lesson is a tour plus a task that checks the player did it.

### Non-goals

- **Wider progression:** unlocks beyond the tutorial gate. "Everything but the mini bike is
  locked" belongs to [Progression](./Progression.md) and is still to be decided.
- **Images and long text in tour steps:** the layout leaves room for them, but no step uses them
  yet.
- **More tours:** only fill-up and Customize for now.

### Anti-goals

- A tour that hides what it's pointing at, or that can't be closed.
- A tour that comes back after it was finished or skipped.
- Tutorial progress saved partway through a mission.

### Decisions (user, 2026-11-07)

- **Tour style:** mockup option A, a giant intro modal that shrinks into a spotlight callout on
  each target, with Next, Back, Skip and progress dots.
- **Button icons:** tours show live button icons for the player's current device and bindings,
  never written-out "click / A" text.
- **Saving tours:** finishing or skipping a tour saves it as done. "Reset tutorials" in Settings
  clears the list, and is the first thing to cut.
- **Saving the tutorial:** progress saves only when a mission completes, so quitting
  mid-mission loses that mission. It resumes at the first unfinished mission.
- **No skipping the tutorial in the UI:** the `dbg_skip_tutorial` console command marks it
  complete.
- **Gate scope:** the gate applies in every build, demo and full game. It's separate from
  `LevelManager.is_locked_in_demo()`.
- **No save migration:** old saves get no grandfathering, so everyone without tutorial progress
  does it.
- **After the tutorial:** once the last mission's results screen closes, the session is torn
  down and the player lands on the Play menu, now fully unlocked.
- **Bike during tours:** frozen while a tutorial tour is open.
- **Map:** a basic graybox copied from `main_menu_level.tscn`'s street scenery, with no traffic.
  The user polishes it later.
- **Old tutorial:** the tutorial in `test_city_01` gets deleted.
- **Translations:** all 10 language columns of `localization.csv`, translated by the agent.
- **No StuntCity lock:** the Play menu gate covers it, because level select can't be reached
  until the tutorial is done.

### Tours: what the player sees

- **Step 1, the intro modal:** a large centered panel with the rest of the screen dimmed. It has
  a title, the goal, how to use the system, and an optional highlighted warning line.
- **Later steps, the callouts:** the panel shrinks into a smaller callout next to its target. The
  screen stays dimmed, with a spotlight cut out around the target.
- **Live button icons:**
  - Body text names controls with `{action}` tokens (the names of `InputMap` actions), rendered
    with the player's current device and bindings, exactly the way the riding HUD's
    `InputPrompt` does it.
  - The Next and Back buttons show the `ui_accept` and `ui_cancel` icons beside them.
  - If the player switches device mid-tour, the icons switch too.
- **Targets:** a `Control` (a HUD gauge, a menu tab), a `Node3D` (pump handle, gas cap, red
  button), or nothing, which centers the step.
- **Local only:** in multiplayer nobody waits for anyone else and the world doesn't pause; only
  local input is held.

### Demo tours

**Fill-up**, the first time any pump minigame opens, whether pre-race or free roam:

1. Intro: fill your tank (your boost) without spilling, and you pay by the second. Warning:
   **TAP to grab, don't hold.**
2. Handle: move the hand and tap to pick it up.
3. Gas cap: hold only while the nozzle is in the ring, and let go if it misses.
4. Tank gauge: how full the tank is, and what's been spilled.
5. Pump `$` sign: what you're paying.
6. Red button: hang the nozzle back up, then press it to finish.

**Customize**, the first time the Customize menu opens:

1. Intro: what Customize is for.
2. Profile tab: your default rider skin.
3. Loadouts: each loadout is a different bike, and can also have its own rider and horn.

### Tutorial flow

- **Before the tutorial is complete:** the Play menu has a new **Tutorial** button at the top,
  and every other Play-menu control is disabled.
- **Starting it:** Tutorial hosts a solo session, loads the tutorial map and starts
  `TutorialGameMode` straight away, with no start circle to drive into.
- **Missions:** there are 3, and each is a milestone. Lessons are a tour, then a task that checks
  the player did it.
  1. **MSF Course:** gas, brake, steering, leaning, camera, shifting, clutch, progressive braking
     (grab the brake too hard and you crash), and not hitting the gas while leaning.
  2. **Stunting 101:** wheelies (basic, the balance point, clutch-up), clutch dump, locking in a
     wheelie (it earns less $/sec), stoppies, drift, and trick mods (e.g. the wheelie
     knee-knocker).
  3. **Stunting 102:** air tricks (same controls as the camera), boost, and items.
- **Finishing:** the existing `TUT_COMPLETE` results screen shows, then the player returns to the
  Play menu with everything unlocked. The Tutorial button stays, so it can be replayed.

---

## Part B: Implementation plan

**Architecture:**
- **Tours:** `Tour` / `TourStep` nodes are authored in the scene that owns the mechanic. A new
  `TourManager` (a CanvasLayer overlay above the HUD and menus, local only) plays them and records
  them in the save.
- **Tutorial:** reuses `TutorialGameMode` and the task runners, with one `SequentialTaskRunner`
  per mission and a new `ShowTourTask` as a lesson step. Mission progress saves when a runner
  completes.

### Global constraints

- **No git:** never run `git` or `gh`, so there are no commit steps.
- **No unit tests:** the project doesn't use them (`Testing.md`). Every task verifies with:
  1. `gdlint` clean against `.gdlintrc`.
  2. A headless editor load, where no output means clean:
     `timeout 280 "<godot4 exe from .vscode/settings.json>" --headless --path . --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" -A1`
  3. A playtest checklist that the **user** runs.
- **Logging:** `DebugUtils.DebugMsg()` only, no `print`.
- **Strings:**
  - Every string goes in `localization/localization.csv` with all 10 columns translated.
  - No em dashes.
  - Controls are always `{action}` tokens, never literal key or button names.
- **No null guards:** fail loudly, with no silent early-returns on null. If null really is valid,
  comment why.
- **Wiring:** `@export` for inspector wiring, `@onready var x: Type = %Name` for internal nodes,
  and required exports checked in `_get_configuration_warnings()`.
- **Netcode:** a client-callable RPC gets a `request_*` entry point that derives the peer from the
  sender. A broadcast RPC rejects non-server senders.
- **Comments:** one-line "why" comments. Match the style of each file you touch.
- **Export-safe GDScript:** no `:=` inference from engine virtuals called on another instance,
  and no `Editor*` class names in runtime scripts.
- **Reuse first:** check for an existing function, signal or export before adding one.

### Review focus

These are risks no task's happy path covers; each one is handled in the task named:

1. **Test harness (Task 3):** `tests/test_main.gd` deletes the save every run. The fresh save is
   gated, so the bot stalls in the menu, and the fill-up tour blocks the bot at the pump. Test
   runs must bypass both.
2. **Steam invite while gated (Task 8):** `PlayMenuState._on_invite_received` calls `join_game`
   and skips past the disabled buttons. It must refuse with a toast until the tutorial is
   complete.
3. **Pause-menu level change mid-tutorial (Task 6):** the pause menu's level select calls
   `start_game` and could jump to StuntCity. It must be hidden or disabled during `TUTORIAL`.
4. **Pause during a tour (Task 3):** Start or Esc while a tour is open must not open the pause
   menu underneath it.
5. **3D target behind the camera (Task 3):** it must fall back to a centered panel with no
   spotlight, not a projected position that makes no sense.

---

### Task 1: Save API + `dbg_skip_tutorial`

**Files:**
- Modify: `managers/save_manager.gd`

**Produces**, all on `SaveManager`:
- `is_tour_done(tour_id: StringName) -> bool`
- `mark_tour_done(tour_id: StringName) -> void` (writes to disk)
- `reset_tours() -> void` (writes)
- `get_tutorial_missions_done() -> int`
- `set_tutorial_missions_done(count: int) -> void` (writes)
- `is_tutorial_complete() -> bool`
- `mark_tutorial_complete() -> void` (writes)

**Save shape:**
- `current_save["progression"]["tours_done"]`: Array of String.
- `current_save["progression"]["tutorial"]`: `{"missions_done": int, "complete": bool}`.
- `load_save` copies `progression` wholesale, so read with `.get(key, default)` and create on
  first write. No migration.

- [x] **Step 1:** Add the seven functions beside `is_owned` and `purchase`.
- [x] **Step 2:** In `deferred_init`, next to `give_money`, register
  `Console.add_command("dbg_skip_tutorial", mark_tutorial_complete, [], 0, "Mark the tutorial complete")`.
- [x] **Step 3:** Run gdlint and the headless load. Expected: clean.

---

### Task 2: `Tour` and `TourStep` nodes

**Files:**
- Create: `utils/tour/tour.gd`, `utils/tour/tour_step.gd`. Both get `@tool` so their warnings
  show in the editor.

**Produces:**
- `class_name Tour extends Node`
  - `@export var tour_id: StringName`: the save key, unique across the game.
  - `func get_steps() -> Array[TourStep]`: the child steps, in tree order.
  - Warnings: an empty `tour_id`, or no `TourStep` children.
  - The `##` docstring documents the child tree (`Tour > TourStep...`) and the `{action}` token
    syntax.
- `class_name TourStep extends Node`
  - `@export var title_key: String`
  - `@export var body_key: String`
  - `@export var warning_key: String = ""`: the optional highlighted line.
  - `@export var image: Texture2D`: optional and unused for now. The layout reserves room for it.
  - `@export var target: Node`: a `Control`, a `Node3D`, or null for a centered step. The first
    step always renders as the intro modal.
  - Warnings: an empty `title_key`, or a `target` that's none of the three allowed kinds.

- [x] **Step 1:** Write both scripts.
- [x] **Step 2:** Run gdlint and the headless load. Expected: clean.

---

### Task 3: `TourManager` overlay with live button icons

**Files:**
- Create: `managers/tour/tour_manager.gd`, `managers/tour/tour_manager.tscn`
- Modify:
  - `managers/input_state_manager.gd`: `InputState.IN_TOUR`
  - `main_game.tscn`: instance the manager, wire `input_state_manager` + `save_manager`
  - `tests/test_main.gd`: test bypass
  - `localization/localization.csv`: `TOUR_NEXT`, `TOUR_BACK`, `TOUR_SKIP`, `TOUR_DONE`

**Consumes:** Task 1's tour functions, and Task 2's nodes.

**Produces:**
- `class_name TourManager extends BaseManager`
- `signal tour_closed(tour: Tour, skipped: bool)`
- `func play(tour: Tour) -> void`: always shows the tour. On finish or skip it calls
  `mark_tour_done(tour.tour_id)` and emits `tour_closed`.
- `func play_once(tour: Tour) -> bool`: returns false and does nothing if the tour is already
  done, or if `dbg_disable_tours` is set. Otherwise calls `play` and returns true.
- `func is_open() -> bool`
- `var dbg_disable_tours: bool = false`

**Scene tree:**
- `TourManager` (Node)
  - `CanvasLayer`, set above the HUD and menu layers (check the layers in `main_game.tscn`)
    - `%UI`: full-rect Control with `mouse_filter = STOP`
      - `%Spotlight`
      - `%Panel`

**Panel:**
- `%Panel` is a `PanelContainer` with the `HUDPanel` variation from `DankNoonerNeon.tres`.
- Its children:
  - `%Title`
  - `%Warning`: hidden when empty
  - `%Image`: hidden when null
  - `%Body`: a `RichTextLabel` that autowraps and scrolls past a max height
  - `%Dots`
  - `%BackBtn`, `%SkipBtn` and `%NextBtn`. On the last step, NextBtn's text is `TOUR_DONE`.
- Next and Back each have an `InputPrompt` (`player/hud_elements/input_prompt.tscn`) beside them,
  with `action` set to `ui_accept` and `ui_cancel` respectively.

**Spotlight:**
- `%Spotlight` is a Control whose `_draw()` draws four dim rects around a hole, plus a neon
  outline on the hole (the theme accent, or `#4ef` if there's none). No shader.

**Layout:**
- **Step 0:** a wide centered panel with no hole.
- **Later steps:** a compact panel beside the target rect, on whichever side has the most room.
  - A `Control` target uses `get_global_rect()`.
  - A `Node3D` target uses `get_viewport().get_camera_3d().unproject_position()` plus fixed
    padding, recomputed every `_process`.
  - If the camera's `is_position_behind()` is true, or the point is off screen, draw no hole and
    center the panel (**Review focus 5**).

**Live button icons:**
- **Device:** track the device in `TourManager._input`. A key or mouse event means KBM, and
  `ControlBindings.is_gamepad(event)` means gamepad, matching
  `InputController._detect_gamepad_or_kbm`. Tours also run in menus, where there's no player,
  so don't read the player's `InputController`.
- **Body rendering:**
  1. Take `tr(body_key)`.
  2. Split it on `\{(\w+)\}`.
  3. Append each text run with `RichTextLabel.add_text`.
  4. For each token, resolve the event with `ControlBindings.event_for(action, gamepad)`.
     - A pad event gets an inline `add_image(ControlBindings.event_icon(event), …)` at the
       body's line height.
     - A key or mouse event gets its key text (`tr(ControlBindings.event_text(event))`), styled
       like the `GestureChipLabel` key chip.
     - An unbound action (null event) is an error, so fail loudly.
- **Refreshing:** re-render the body, and call `refresh(gamepad)` on both `InputPrompt`s, when
  the device flips and whenever a step shows.

**Input:**
- `play()` saves `input_state_manager.current_input_state`, sets `IN_TOUR`, calls
  `showhide_mouse_cursor()` and focuses `%NextBtn`. Closing restores the saved state.
- `ui_accept` and click press the focused button. `ui_cancel` is Back, or Skip on step 0.
- `InputStateManager._unhandled_input` gets an `IN_TOUR` branch that does nothing
  (**Review focus 4**).
- `showhide_mouse_cursor()` makes the cursor visible for `IN_TOUR`.
- `FuelUpMinigame` already idles when the state isn't `IN_MINIGAME`. Tutorial tours freeze the
  bike instead of gating riding input (Task 6).

**Test bypass (Review focus 1):** `tests/test_main.gd` sets `dbg_disable_tours = true` on the
TourManager and, once the save has loaded (after `deferred_init`), calls
`save_manager.mark_tutorial_complete()`.

- [x] **Step 1:** Add `IN_TOUR` to `InputStateManager`: the enum, `_unhandled_input` and
  `showhide_mouse_cursor`.
- [x] **Step 2:** Build `tour_manager.tscn` and `.gd` as above, and add the manager to
  `main_game.tscn` with its exports wired.
- [x] **Step 3:** Add the 4 button strings in all 10 languages.
- [x] **Step 4:** Add the test bypass.
- [x] **Step 5:** Run gdlint and the headless load. Expected: clean. Task 4 is the first
  playtest.

---

### Task 4: Fill-up tour

**Files:**
- Modify:
  - `levels/components/interactable/gas_pump.tscn`: a `Tour` (`tour_id = &"fuel_up"`) with 6
    `TourStep`s.
  - `managers/gamemodes/gamemodeobjects/free_roam_activity.gd`: `begin()` gains a
    `tour_manager: TourManager` parameter.
  - Every caller of `begin()` (`free_roam_gamemode.gd:411`, `fuel_up_gamemode.gd:50`) and every
    `FreeRoamActivity` subclass override (the garage activity). The callers gain a
    `tour_manager` export, wired in `main_game.tscn`.
  - `levels/components/interactable/fuel_up_minigame.gd`: call `play_once`.
  - `managers/hud/fuel_up_hud_state.gd`: add `get_gauge() -> Control`, which returns
    `%BoostGauge`.
  - `localization/localization.csv`: the `TOUR_FUELUP_*` keys, using `{action}` tokens. For
    example, grab and spray are `{use_item}`, and the cursor is the steer and lean actions.

**Steps and their targets, in order** (copy from Part A, Demo tours):
1. Intro: no target, with a warning.
2. `%HandleArea`
3. `%GasCapArea`, which `_process` keeps on the bike's gas cap.
4. The tank gauge. It's in another scene, so before `play_once` the minigame sets the step's
   `target` from `_hud_manager.fuel_up_hud_state.get_gauge()`.
5. `%SaleLabel`
6. `%EndBtn`

**Where it plays:** `play_once` goes at the end of `_on_session_start()`, after
`go_to_fuel_up_hud`.

- [x] **Step 1:** Thread `tour_manager` through `begin()` and all its callers and overrides.
- [x] **Step 2:** Author the tour, add the gauge getter, the `play_once` call and the strings.
- [x] **Step 3:** Run gdlint and the headless load. Expected: clean.
- [x] **Step 4:** **User playtest:**
  - The first pump shows the intro, then Next walks the spotlight across the handle, cap, gauge,
    price and button.
  - The icons match the device, and swapping between KBM and pad mid-tour swaps them.
  - The minigame stays idle underneath.
  - Closing hands control back to the minigame.
  - A second pump shows no tour.
  - Pre-race fuel-up shows it too.

---

### Task 5: Customize tour

**Files:**
- Modify:
  - `menus/customize_menu/customize_menu_state.tscn` / `.gd`: a `Tour`
    (`tour_id = &"customize"`) with 3 steps, plus a `tour_manager` export.
  - `menus/customize_menu/components/garage_ui.gd`: add `get_profile_tab() -> Control` and
    `get_loadout_tabs() -> Control`, returning `%ProfileTab` and `%Tabs`.
  - `localization/localization.csv`: the `TOUR_CUSTOMIZE_*` keys.

**Steps and targets:**
1. Intro, no target.
2. `get_profile_tab()`, set in `Enter()`.
3. `get_loadout_tabs()`, set in `Enter()`.

**Where it plays:** `play_once` goes at the end of `Enter()`, after `garage_ui.open(...)`.

- [x] **Step 1:** Author the tour, add the getters, the `play_once` call and the strings.
- [x] **Step 2:** Run gdlint and the headless load. Expected: clean.
- [x] **Step 3:** **User playtest:**
  - The first Customize visit runs the tour over the menu.
  - The menu ignores input while the tour is open.
  - Later visits show nothing.
  - Back still works afterwards.

---

### Task 6: `ShowTourTask` + `TutorialGameMode` milestones

**Files:**
- Create: `managers/gamemodes/tasks/show_tour_task.gd`
- Modify:
  - `managers/gamemodes/types/tutorial/tutorial_gamemode.gd`
  - `menus/pause_menu/pause_menu_state.gd`
  - `tests/coverage.gd`: add `"ShowTourTask"` to `TUTORIAL_ONLY_TASKS`.

**Consumes:** Task 1's tutorial functions, and Task 3's `TourManager.play()` + `tour_closed`.

**Produces:**
- **`class_name ShowTourTask extends GameModeTask`.** Its child is a `Tour`. It has
  `var tour_manager: TourManager`, injected by `TutorialGameMode._inject_task_deps` the same way
  as `CloseHelpTask`'s deps. Mirror `CloseHelpTask`'s RPC pair.
  - `on_enter`: `CountdownTask.freeze(player)`, then `_rpc_show_tour.rpc_id(int(player.name))`.
  - `check`: returns `state.get("closed", false)`.
  - `on_exit`: `CountdownTask.unfreeze(player)`.
  - On the client, `_rpc_show_tour` calls `tour_manager.play(tour)`. It's always `play`, never
    `play_once`, because tutorial tours always show. On `tour_closed` it calls
    `request_tour_closed.rpc_id(1)`.
  - On the server, `request_tour_closed` takes the peer from `get_remote_sender_id()` and calls
    `runner.mark_state(peer_id, "closed", true)`.
  - Objective and hint text: empty.
- **`PauseMenuState.leave_session(to: MenuState) -> void`.** Move the body of
  `_on_main_menu_pressed` into it (`end_game`, `disconnect_sp_or_mp`, the transition, `IN_MENU`).
  `_on_main_menu_pressed` then calls `leave_session(main_menu_state)`.

**`TutorialGameMode` changes:**
- **Exports:** add `tour_manager: TourManager` and `play_menu_state: MenuState`. Reuse the
  `save_manager` that `RunnerGameMode` already exports.
- **Resume:** in `Enter`, before `_start_next_runner()`, set
  `_active_runner_index = save_manager.get_tutorial_missions_done() - 1`. If every mission is
  already done, use -1 so a replay starts at mission 1.
- **Milestone save:** override `_on_runner_all_completed()` to call
  `set_tutorial_missions_done(_active_runner_index + 1)` before `super()`.
- **Complete:** `_on_last_runner_completed` also calls `mark_tutorial_complete()`.
- **Leave:** override `_return_to_free_roam()` to call
  `menu_manager.pause_menu_state.leave_session(play_menu_state)`. Results skip and the results
  countdown both go through it.
- **No cancelling:** `can_cancel_event()` returns false. Leaving mid-tutorial goes through the
  pause menu's Main Menu.

**Review focus 3:** `PauseMenuState` hides its level select while
`gamemode_manager.current_game_mode == GameModeType.Kind.TUTORIAL`. Extend the panel's existing
visibility logic; don't add a second one.

- [ ] **Step 1:** Write `ShowTourTask` and add it to `coverage.gd`.
- [ ] **Step 2:** Pull `leave_session` out of `_on_main_menu_pressed`.
- [ ] **Step 3:** Make the `TutorialGameMode` changes, inject `tour_manager`, wire the exports in
  `main_game.tscn`, and hide the pause level select.
- [ ] **Step 4:** Run gdlint and the headless load. Expected: clean. Task 8 is the first
  playtest.

---

### Task 7: Tutorial level + auto-start

**Files:**
- Create: `levels/tutorial/tutorial_level.tscn`, with a script only if `LevelDefinition` needs
  one.
- Modify:
  - `managers/level_manager.gd`: add `LevelName.TUTORIAL_LEVEL` to the enum, `possible_levels`
    and `level_name_map` (`"LEVEL_TUTORIAL"`). Leave it out of `levels_names_in_level_select`.
  - `levels/level_definition.gd`: `@export var auto_start_event: GameModeEvent`
  - `managers/gamemodes/types/free_roam/free_roam_gamemode.gd`: the auto-start.
  - `levels/test_levels/test_city_01/test_city_01.tscn`: delete `Tutorial01EventStartCircle`,
    `TestEventStartCircle/TutorialTEST` and `Stuff/Tut01Location`.
  - `localization/localization.csv`: `LEVEL_TUTORIAL`, `TUT_EVENT_NAME`, the mission names and
    the lesson tour copy (`TOUR_TUT_*`).

**Auto-start:**
- In `FreeRoamGameMode.Enter`, on the server, when `state_context` isn't a
  `GamemodeStateContext` (only `start_game` enters that way) and the level's `auto_start_event`
  is set, call
  `gamemode_manager.change_gamemode(auto_start_event.definition.target_gamemode, multiplayer.get_unique_id(), auto_start_event.get_path())`.
- Do it after the players have spawned. Read how `Enter` spawns them first, because spawning may
  be deferred.

**Level:**
- **Base:** copy the street, ground, houses, gas station, trees and mountains from
  `main_menu_level.tscn`. Leave out the `TrickDemo` rig, camera and animations.
- **No traffic:** the level has no traffic network node.
- **Graybox areas,** using `graybox_staticbody` props:
  - a straight with marked braking zones
  - corners or a loop with checkpoint gates
  - a wheelie and stoppie strip
  - ramps
  - boost and item pickups
  - a teleport marker for each lesson start
- **Event:**
  - The `GameModeEvent` (`target_gamemode = TUTORIAL`, name `TUT_EVENT_NAME`) sits under an
    `EventStartCircle`, because `GameModeEvent.get_circle()` is `get_parent()`. Park the circle
    out of reach.
  - It has 3 `SequentialTaskRunner`s: `Mission1_MSF`, `Mission2_Stunting101` and
    `Mission3_Stunting102`.
- **Lessons:** each lesson is an optional `TeleportTask`, then a `ShowTourTask` with its `Tour`
  child, then its check task(s). Name tour ids `&"tut_<lesson>"`. Use the checks that already
  exist:
  - `SpeedAboveTask`: gas.
  - `ChangeGearTask`
  - `WheelieDurationTask` / `StoppieDurationTask`
  - `PerformTrickTask` with `DRIFT`, `KNEE_KNOCKER`, an air trick, and `WHEELIE_MOD` if that's
    the locked wheelie. Verify in `TrickController` first.
  - `CheckpointTask`: steering and leaning through gates.
- **Explain-only lessons:** not gassing mid-lean and the locked wheelie's $/sec are a tour with
  no check. Task 9 adds the checks that are still missing.

- [ ] **Step 1:** Add the `LevelManager` entries, `auto_start_event` and the free-roam
  auto-start.
- [ ] **Step 2:** Build the graybox level and its event, with all 3 missions authored using the
  existing tasks.
- [ ] **Step 3:** Delete the `test_city_01` tutorial nodes. If nothing references
  `CloseHelpTask` any more, delete it, its injection in `TutorialGameMode`, its `coverage.gd`
  entry, and any of its strings that are now unused.
- [ ] **Step 4:** Write the strings in all 10 languages.
- [ ] **Step 5:** Run gdlint and the headless load. Expected: clean.

---

### Task 8: Play menu gate + Tutorial button

**Files:**
- Modify:
  - `menus/play_menu/play_menu_state.gd` / `.tscn`: `%TutorialBtn` at the top, a `save_manager`
    export, and the gate.
  - `menus/lobby_menu/lobby_menu_state.gd`: implement the `LobbyStateContext.Mode.STORY`
    branch. `NewStory` already exists.
  - `localization/localization.csv`: `TUTORIAL_BTN_LABEL`, `TOAST_FINISH_TUTORIAL_FIRST`

**Gate:**
- In `Enter`, while `!save_manager.is_tutorial_complete()`, disable `customize_btn`,
  `free_roam_btn`, `host_btn`, `join_btn`, `paste_btn`, `code_entry`, `host_mode_opt` and
  `server_browser_btn`, and focus `%TutorialBtn`.
- The Tutorial button is always enabled.

**Tutorial button:** emits
`transitioned.emit(lobby_menu_state, LobbyStateContext.NewStory(self))`.

**Lobby STORY:**
- Host with `connection_manager.start_server(true)` (solo) without showing any lobby UI, then
  call `gamemode_manager.start_game.rpc(LevelManager.LevelName.TUTORIAL_LEVEL)`.
- Follow how the `FREEROAM` branch of `_on_client_connection_succeeded` awaits `start_server`.

**Review focus 2:** in `_on_invite_received`, while the tutorial isn't complete, show
`UiToast.ShowToast(tr("TOAST_FINISH_TUTORIAL_FIRST"))` and clear
`steam_manager.pending_game_id` instead of joining.

- [ ] **Step 1:** Add the button, the gate, the STORY branch, the invite block and the strings.
- [ ] **Step 2:** Run gdlint and the headless load. Expected: clean.
- [ ] **Step 3:** **User playtest,** on a fresh save:
  - Only Tutorial is enabled, and it loads the map and starts Mission 1 with its intro tour.
  - The bike is frozen during tours.
  - Quitting partway through mission 2 resumes at mission 2.
  - Finishing returns to the Play menu with everything unlocked.
  - `dbg_skip_tutorial` on another fresh save unlocks the menu.

---

### Task 9: Missing lesson checks

**Files:**
- Create in `managers/gamemodes/tasks/`, only where no existing task covers the lesson. Copy
  `SpeedAboveTask`'s exports and objective/hint key pattern.
  - `speed_below_task.gd` (`SpeedBelowTask`), for progressive braking: brake from speed to a
    stop. A crash already resets the step.
  - `boost_task.gd` (`BoostTask`): passes once `player.boost_controller.is_boosting` has held for
    `min_duration`.
  - `use_item_task.gd` (`UseItemTask`): find the signal or state that `ItemManager` changes when
    the rider's item gets used, and reuse it. Only add a signal if none exists, and flag that in
    your summary.
- Modify:
  - `levels/tutorial/tutorial_level.tscn`: add the new tasks to their lessons.
  - `tests/coverage.gd`: add the new task names to `OPTIONAL_TASKS`.
- **Clutch dump** needs no task of its own; the wheelie check after its tour covers it.

- [ ] **Step 1:** Write the tasks, then wire them into the level and `coverage.gd`.
- [ ] **Step 2:** Run gdlint and the headless load. Expected: clean.
- [ ] **Step 3:** **User playtest:** all 3 missions complete start to finish, and every check
  fires.

---

### Task 10 (cut first): Reset tutorials in Settings

**Files:**
- Modify: the Settings tab that holds general options (find it), and
  `localization/localization.csv` (`SETTINGS_RESET_TOURS`).

**Behaviour:** a button that calls `save_manager.reset_tours()`. If Settings already has a
confirm pattern, use it.

- [ ] **Step 1:** Add the button.
- [ ] **Step 2:** Run gdlint and the headless load. Expected: clean.
- [ ] **Step 3:** **User playtest:** after a reset, the pump tour shows again.

---

### When the user's playtests pass

- Fold this doc into `Architecture.md` (TourManager), `GamemodeSystem.md` (`ShowTourTask`, the
  tutorial milestones) and `LobbyGameFlowMP.md` (the Play menu gate, `STORY`). Name tunables but
  don't give their values.
- Then delete this doc.
