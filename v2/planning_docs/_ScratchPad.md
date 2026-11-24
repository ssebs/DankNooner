# Scratch Pad
---

## Marketing

Vid: where we started, where we are now

Clip: backflip off a deployed ramp onto Smith grind in first 5 sec, then add kick flip or other trick back to the race
Clip: kickflip, heelflip, tre flip, lazerflip, drifting to shuvit then crash

Must make good Steam trailer + marketing materials before publishing demo
- hook + vibes
- Show what the game will feel like
- Description has gifs for unique features 

Ask Eddie if I can put up a sign with a QR code
Make a hoodie

- [ ] Improved Steam art assets / game press kit
- [ ] Better / Offical Trailer (concise, hook-y)
- [ ] Keymailer once demo stuff is ready

---

## NOW
---


- [x] rally up item shouldnt affect player who used it
- [x] fuel up minigame refactor to be part of drive to start runner instead of its own gamemode
- [x] stop making players wait when doing fill up before race that you have to drive to, once they hit the btn they can start moving.
- [x] friend names are too big/in the way (maybe move them to a hight set by viewport Y?)
- [x] player names should be diff color in leaderboard/trick feed
- [x] btn to open menu should go away once new menu pops up / merge these
- [x] invite btn on pause menu for clients
- [x] change stoppie challenge from 3s to 2.5s
- [x] customize menu "All" skins should be explained if not already in tour
- [x] show player level on race finish screen
- [x] lobby scroll list of players can be longer + adjust spacing
- [x] customize leave txt => exit
- [x] mute other players horn option or cooldown after 5x
- [x] dont play horn while ded

- [ ] menu navigation needs to be smoother
  - [ ] change a color in customize inaccessible via controller
  - [ ] general controller UX is bad when trying to switch menus / do stuff
  - [ ] Look to GTA vi for hud/menu ideas (smoothness vs what it looks like)

- [ ] joining another lobby while in game doesn't back you out first, so you never join
- [ ] joining from customize menu doesnt let you til you leave
- [ ] starting event in customize menu doesnt TP them properly

- [ ] preview audio values in settings, but only save on save.
- [ ] when host starts an event have a smol countdown telling players whats starting / transition

- [ ] can't do a wheelie while going fast on the mini bike

- [ ] pinned trick should be more obvious (glow when doing wrong trick in tutorial)
- [ ] tutorial "now land it" pink text not obvious enough
- [ ] tutorial shouldnt do progression

- [ ] Hdr / sdr testing with multiple monitors 

- [ ] Slow down racers, but make it feel fast. 
- [ ] Racers too fast if you crash you don't see anyone. Come catch up needed, more incentive to do tricks needed too. Dynamic speed?

- [ ] add /tp command like MC / other in-game useful commands




- [ ] naked bike in tutorial?
---


- [ ] Demo/mvp
  - [x] cant navigate save slots / choose to del on gamepad
  - [x] land 3 backflips daily doesnt count when doing a flip?
    - [x] landing on front wheel, trick shout says wheelie
    - [x] wheelie to backflip doesnt count as flick
  - [x] stop lowering boost fill by 2 bars when starting an event
  - [x] Limit content in the game, too much for a demo tbh
  - [x] Add thanks for playing the demo to the demo version when you unlock everything, but players can keep playing 
  - [x] change order of shown items in customize menu, should always show unlocked first, then order by unlock type (mini bike challenge, naked challenge, etc.)
  - [x] in customize, hovering the item should show the challenge card
  - [x] too easy to crash when steering a stoppie, allow some steering
  - [x] wire up trick battle arena @ eventstartcircle4
  

  - [ ] add more incentive to doing stunts and driving around the map instead of just going from checkpoint to checkpoint
    - [ ] score is a reason but not obvious enough
    - [ ] need to give $ per trick done too?
    - [ ] Maybe during stunt race you have to land a specific tricks off a ramp for 4x points like CS2 bonus weapon in death match?
  - [ ] more wheelie tricks (air/ground are good for now, need wheelie variants)
  - [ ] disable some `dbg_` commands (progression), but keep TP/helpers

- [ ] tweaks
  - [ ] time attack race 1 shouldnt make you drive there first
  - [ ] add sounds when body hits the ground

- [ ] new skin popup when doing a challenge
  - [ ] should show thumb right of the count in profilecard
  - [ ] popup should last 2sec

- [ ] stunt city map tweaks
  - [ ] more ramps & garages & grinds in the level
	- [ ] perma add the stunt arena to map somewhere

- [ ] skins
  - [ ] add glow to naked bike
  - [ ] boost trail color

- [ ] engine upgrade unlocks? change level 1 is mini, level 2 is naked, level 3 is sport, level 4 is sport+ or something


- [ ] sentry.io log shipping for crash logs
  - [ ] they have free tier
---
##
## NEXT

- [ ] tweak dirt bike / adv bike models

- [ ] Mods
  - [ ] Wings as mod for sport bike 
    - [x] mesh
    - [ ] (more air time(slow down gravity so you get more air time)) effect
  - [ ] Scraper/12 bar mod
    - [x] mesh
    - [ ] add sparks during wheelie / loopout prevention effect
      - [ ] when at balance point do sparks, dont actually check if its touching the ground
  - [ ] Training wheels
    - [x] mesh
    - [ ] (lowside prevention) effect
  - [ ] Underglow on bike?
  - [ ] exhaust?

- [ ] find a way to record my gameplay but play it back from another camera angle/slowmo
  - [ ] Replay studio for trailer footage: review the "Calls I made" section, then plan. Spec: [____REPLAY_WIP.md](./____REPLAY_WIP.md)
  - [ ] also see `resources/img/marketing` and `scripts/key_art`. currently exists but jank! getting better, but not library header

### Full game scope

- [ ] gas station minimap icon looks like gun store
- [ ] Do specific tricks in a line mode? S.T.U.N.T?
- [ ] Gamba: spin the wheel (or roulette / random game) to win unique prizes when leveling up? Can buy with $

- [ ] wheelie bar as item in stunt race
  - [ ] add wheelie bar for a few seconds
  - [ ] can lock in wheelie with item on
  - [ ] same with training wheels / wings

