# Movement User Stories

> Things that players should be able to do & how the "feel" should be.

## Wheelies

### Starting

- User can accelerate while pulling back to start a wheelie
- User can shift weight forward, then back while giving gas to start wheelie
- User can shift weight forward, then back while doing a clutch dump to start a BIG wheelie
- User can clutch dump to start wheelie

## Stopping

- User can lean too far back and crash
- User can lean forward again, if front wheel hits ground, then wheelie is over

### During

- User can find balance point, where the bike likes to stay upright instead of falling one way or the other
- User can add trick tweak, by pressing `RB` + `DIRECTION` during a wheelie

## Flat Ground Riding

### Starting

- User starts from standstill, with 1 leg on the floor. Pressing `FWD` will put them in 1st gear and start moving

### During

- User can shift up and down, changing top speed & acceleration
- User can throttle / brake to speed up / slow down
- Front brake must be progressive
  - Will skid out if pressed too fast
  - If turning while doing this then low side crash starts
  - More steering (lean angle), the easier to low-side
- Rear brake will start fishtail

### Steering

- Bell curve: speed x steer amount
  - 1mph => can't steer much
  - 20mph => max steering amount
  - 55mph => middle steer amount
  - 120mph => can't steer much

## Ramp Riding

- Speed decreases with road angle from world UP \* time
- Bike angle follows contour of road, if sharp snap, then blend & find mid point between 2
  - Use 2 raycasts
- If speed stays above threshold, stick to ramp. Change player up direction to contour normal, so gravity pulls them twd that.
- If speed drops below threshold, fall off ramp, player up is world up
- User launches off ramp, their velocity should follow parabolic path from player FWD, like IRL
- User falls off loop-de-loop, they fall on their head
