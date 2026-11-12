# Changelog

## v0.1.2 - 2026-11-12

- Red triangles over enemy racers head
- baked nav fix
- npc improvements
- customize bike glow color
- visual racing line + npc tweaks

## v0.1.1 - 2026-11-11

- consistent menus finally
- ui improvements
- new theme for all
- customize menu ui
- improve ui for saves
- new btn design + profile / save btn + rm gray by from splash imgs
- save load menu

## v0.1.0 - 2026-11-10

- start progression
- main menu: random bike, profile's rider
- Scroll wheel now moves the highlight in the loadout bar while you hold the loadouts button
- fix scooter wheel spin
- add cruiser bike
- add vespa
- fix  burnout doesn't do donut fast enough when steering
- finish tutorials
- rewrite grind instructions
- Spill gas if holding past max fill

## v0.0.169 - 2026-11-09

- cleanup advanced tutorial + Don't allow skate flip tricks during wheelie
- rename stunt city in files
- - [x] move checkpoint / race spawns on right side of road - [x] add reusable spawn grid component
- - [x] move checkpoint / race spawns on right side of road - [x] add reusable spawn grid component
- jank art studio + change spawn/checkpoints
- exit garage / fillup should not say end event
- new horns
- adjust `BELLY_GRIND_TILT_DEG: float = 20.0` by current lean so it doesn't snap so much, try to blend with existing pitch like tailslide/other grinds not in `BELLY_GRINDS`
- add lazerflip, tre flip, 360 shuvits

## v0.0.168 - 2026-11-08

- improve salad grind
- adv tut start
- loadout ui tweaks
- d-pad menu to swap loadouts
- tutorial tweaks + set respawn point
- tut fix
- grinds
- smith/feeble/willy grinds nice
- improved ragdolls + new smith/feeble/willy grinds
- fix backflip not counting unless you rotate allll the way
- add visual feedback when getting an item
- ragdoll interacts w/ traffic
- rm red bar part of fillup mini game, increase price instead + add a popup when you crash "Press R to respawn"
- improved tutorial
- improved tutorial
- improve tutorial
- tutorial
- verbiage
- start Adding product feature tour / walk thru for tutorials
- start Adding product feature tour / walk thru for tutorials
- start Adding product feature tour / walk thru for tutorials
- start Adding product feature tour / walk thru for tutorials
- plan: Add product feature tour / walk thru for tutorials

## v0.0.167 - 2026-11-07

- Create/join public/private lobbies w/ Steam
- Create/join public/private lobbies w/ Steam
- start working on steam lobbies
- performance tweaks
- replace houses with mesh
- basic racing npcs done
- more langs
- fr
- Localize more text + more langs
- graphics quality settings
- some graphical performance tweaks + settings

## v0.0.166 - 2026-11-03

- - [ ] lowside when gassing it during corner
- - [ ] lowside when gassing it during corner
- better grind snap
- improve: slow speed turning anim doesn't look right (front wheel going into ground, not sharp enough turn / realistic counter leaning, player leans super far going 2mph - theyd crash irl)
- tweak grinding tricks
- tweak grinding tricks
- start creating grinding tricks
- tweak drifting physics + fix pickup spawners dont work in stunt battle arena
- fix not enough feedback for brakedanger / helping the user know they should be progressively braking instead of braking hard quickly
- shouldnt be so easy to drift & steer on gamepad, only drift from rear brake, not lean fwd except burnout
- keep vibrating controller after a crash til you respawn + respawn timer => 15s max for CrashLaunch, during stuntrace =>3s, free roam => 5s
- crash respawn timer => 15s max for CrashLaunch, during stuntrace =>3s, free roam => 5s
- ramp should spawn right in front of you
- minimap rotate w/ cam

## v0.0.165 - 2026-11-02

- npc racers can trick + boost + boost VFX prework
- npc racers can trick + boost + boost VFX prework
- fix cant start stunt battle bc arrow walls are in the way before you drive to it
- add disable hud dbg option for recording clips

## v0.0.164 - 2026-10-31

- vibrate on near miss
- riding hud adjustments
- RMB + move mouse = T + Arrow keys
- improved npc racers
- npc race use items
- npc race: difficulty, crashing, item use,, nav improvements
- cleaned up crash launch mode
- fix colliders in city
- fix ground colliders in blender for stunt city
- fix props collision between races
- give cars headlights since they're impossible to see during a race
- doc tweaks
- migrate other maps (might be broken)
- separate props per game mode under an event start circle
- start ragdoll launch game mode
- fix backing up steering / going uphill is jittery
- fix backing up steering / going uphill is jittery

## v0.0.163 - 2026-10-29

- better wheelie cam
- consistent camera delay
- ramp item needed outline, traffic density setting
- show $ on time attack
- cleanup settings menu
- reduce hitbox on vehicles a bit
- rm glow fx from color sliders in customization
- Add ramp on bridge so if you land on top you can drive off both ways

## v0.0.162 - 2026-10-28

- filling up - pay per second of fuel, so spilling costs $. show in diagetic UI on pump

## v0.0.161 - 2026-10-28

- Wheelie scoring now depends on the angle, it should.
- bike wreck reacts to cars
- combo sound
- Grinding sound should be in 3d space
- free ride => host private lobby of default type, can invite friends but no need to wait in lobby.
- cleanup hud mor
- todo + theme tweaks

## v0.0.160 - 2026-10-27

- transparent top neon theme
- HUD: add Horn hint (with "double tap to drop current item" sub-hint) to action hints; move Use Item hint beside RPM gauge; both item hints only show while holding an item
- new models
- better showing of items in hud
- better showing of items in hud
- hud rework contd
- Fix steam tags
- more hud/ui tweaks, still not 100% done
- cleaner theme
- major hud changes w/ new emoji font
- migrate hud / ui overrides to their own components in the theme
- trick feed
- improve traffic density

## v0.0.159 - 2026-10-26

- test new changelog system
- set_traffic console command
- fix fill up spil hud height changes
