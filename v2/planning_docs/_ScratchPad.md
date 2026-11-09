# Scratch Pad
---

Vid: where we started, where we are now 


Trailer= hook + vibes. Show what the game will feel like
Description has gifs for unique features 

   
Ads at FHK? Print out? Merch?

Red triangles over enemy head


- [ ] d-pad menu to swap loadouts. have it slide out & let you choose a class (like vertical minecraft hotbar w/ person on the bike for the icon)
- [ ] add sound / visual feedback when getting an item to direct the user to look to see what they got.
  - [ ] prob is i got a ramp and didnt realize.
---

## NOW
- [ ] Flips (BACKFLIP/FRONTFLIP) are current_trick for only one rollback tick, but task check()s poll it once per rendered frame, so a frame that runs 2+ ticks can miss the flip. The fix is to latch flips in TrickController the way tap tricks are (_tap_trick / TAP_TRICK_DURATION) rather than special-casing them in tasks.
- [ ] grinding - smith should lower so the center of the tank is whats grinding & not floating in the air
- [ ] Add product feature tour / walk thru for tutorials
  - [ ] `planning_docs/____TUTORIAL_WIP.md`
  - [x] add fill up giant warning (DO NOT HOLD, TAP A, CLICK and RELEASE)
  - [x] Each one saves saying it's done
  - [ ] customization warning
  - [x] tutorial level / tutorials + lock out main game until tut is done
    - [x] working level
    - [x] working steps / explainations
    - [x] improve tutorial feel
    - [x] improve tutorial level map
    - [ ] fix backflip not counting unless you rotate allll the way
    - [ ] grab gas can => just check boost used, not full amount. (ended up grabbing next item & being confused)
    - [ ] using shotgun but missing needs to reset you but say you were too far away
    - [ ] shorten tutorial
    - [ ] exit garage / fillup should not say end event
    - [ ] reset tutorial doesnt work for customization
- [ ] my ragdoll when crashing should interact w/ npc traffic like the bike does

--
###
## NEXT

- [ ] [Progression/Challenges](./Progression.md)

- [ ] move checkpoint / race spawns on right side of road
  - [ ] checkpoint should have left/right/full enum to move the repawn locations



