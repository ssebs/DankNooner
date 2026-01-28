# Goals & Requirements for Dank Nooner

> Stuff that should be included in the game

## MVP

- Stuff from https://github.com/ssebs/moto-player-controller-godot/:
  - Controls
  - Physics/Gearing/etc
  - Animations (IK)
  - Ragdoll
  - Tricks
- Multiplayer:
  - lobby / peer to peer joining
  - easy to connect with friends
  - easy to join open lobby (like GTAO lobby)
- Game modes:
  - free-ride
  - stunt race
  - Street race mode (dodge traffic/weave w/ friends)
  - S.K.A.T.E equivelent (trick challenges)
  - track race
  - Missions (like simpsons hit & run)
    - Singleplayer - start on bike, 1st challenge is do a wheelie. (learn how + unlock it + get cash for customization)
- Art:
  - create color palette for dank nooner
  - Low-poly style?
    - Painterly shaders?
    - cell shading?
    - outine glow? (tron)
    - Cars neon?
      - https://youtu.be/Kzy3n-8A-vA?si=4geX5_eVg_qv6hsg&t=107
      - https://www.youtube.com/watch?v=tVm6OWbUTG0
  - Open world map (Island w/ ...)
    - Mountain twisty roads
    - City
    - Suburbs
    - Race track
    - Dirt / jump track
    - Megaramp
- Localization
- Sounds:
  - Better sounding engines / sfx than current
  - dopamine sounds (sfx on points, etc)
- Progression:
  - Customization via $$
  - Bike unlocks
  - Trick unlocks
- Tricks:
  - Score for doing tricks
  - Base for doing a trick, holding a trick gives addl.
  - Combos for doing tricks back-to-back
  - Base tricks (wheelie) + modifier tricks (wheelie + heel clicker)
  - See [tricks list](#tricks-list)
- Mechanics (already implemented in `moto-player-controller-godot`)
  - Fun but challenging
    - Multiple difficult levels
      - **Easy** - Automatic, can't fall off bike unless crashing
      - **Medium** - Manual, can't fall easily from mistakes (e.g. lowside)
      - **Hard** - Manual, can fall (e.g. low side crash if leaning and grabbing a fist full of brake)
  - Manage clutch, balancing, throttle, steering (need to be smooth, don't just slam it.)
  - Falling / crashing has ragdoll physics, player goes flying until they stop moving (or press btn)

## Misc fun ideas:

- Hide license plate / police chase feature

## Tricks

### List

> Base is nested level 1, complex is nested level 2
> All tricks can be tweaked with rotations / flips (180/backflips)

- Wheelie
  - standing wheelie
  - Y shaped legs wheelie (2 feet over bars)
  - legs left/right wheelie
  - Biker Boyz w/ 2 legs over the side (sparks)
- Stoppie
- Drift
- Burnout
- Whip (table)
- Superman (no hand spread eagle)
- Flip/Rotate only\*
  - Back / Front flip
  - 360 / 180 turns
- Skate tricks for memez (only off **Ramps**)
  - > hop on top of bike, then do it like skater
  - kickflip/heelflip
  - pop shuvit
  - hardflip
  - 360flip
  - nollie lazerflip

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

## Full Release
