# HighwayCrawl

An iOS SpriteKit driving game in landscape. You steer a car down a four-lane highway.

## What’s in so far

- Landscape-only iPhone/iPad app
- Scrolling highway with 4 driveable lanes
- Shoulders on both sides (about half a lane wide), with solid edge lines
- Red rectangle as a stand-in for the player car
- Lane changes via on-screen Left/Right buttons or keyboard arrow keys
- You can drive on the shoulders; speed slowly drops until you stop
- Stopping on a shoulder is game over
- Getting back on asphalt speeds you up again

The Action button is on screen (bottom right) but does nothing yet.

## How to play

1. Open `HighwayCrawl.xcodeproj` in Xcode (one folder up from this file)
2. Pick an iPhone simulator (or a device) and press **Cmd+R**
3. **Left / Right** buttons or **← / →** keys change lanes
4. Stay on the asphalt. Linger on a shoulder too long and you stall out

Click the simulator window first if keyboard controls don’t respond.

## Not built yet

Traffic, collisions, scoring, and whatever the Action button will do.
