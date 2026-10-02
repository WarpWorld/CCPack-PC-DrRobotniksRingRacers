# Dr. Robotnik's Ring Racers

## Pack metadata
- **Game display name:** Dr. Robotnik's Ring Racers
- **Crowd Control game ID:** `DrRobotniksRingRacers`
- **Connector type:** `FileConnector`


This pack connects Crowd Control to **Dr. Robotnik's Ring Racers** through the
bundled `SL_CrowdControl.pk3` Lua mod. Communication is file-based.

> **Multiplayer warning:** this mod is not supported for multiplayer and may
> cause desyncs. The Lua connection code also explicitly does not support
> dedicated servers. Use it in a local, non-dedicated session.

## Requirements

- Crowd Control with the **Dr. Robotnik's Ring Racers** effect pack.
- Dr. Robotnik's Ring Racers.
- `SL_CrowdControl.pk3`, included in this directory.

## Setup

1. Select the Dr. Robotnik's Ring Racers effect pack in Crowd Control and set
   its game path to the Ring Racers executable.
2. Load `SL_CrowdControl.pk3` using the game's normal PK3 loading process.
3. Start a local, non-dedicated game session. The mod initializes the
   connector files and Crowd Control can then communicate with it.

## Connection behavior

The pack exchanges requests and responses with the Lua mod through the game's
local `luafiles\client\crowd_control` directory:

- `connector.txt` contains the current state;
- `input.txt` receives Crowd Control requests; and
- `output.txt` contains effect responses.

The Lua mod writes `READY` when initialized. The Crowd Control pack also maps
the state file to ready, menu, paused, or unknown, so effects can wait while
the race is not in a playable state.

## Troubleshooting

- **No connection:** confirm that the executable path is correct, the PK3 is
  loaded, and `connector.txt` exists beneath
  `luafiles\client\crowd_control`.
- **Effects are unavailable:** leave menus or pause and return to a playable
  race state.
- **You started a dedicated or multiplayer session:** use a local,
  non-dedicated session instead; those modes are not supported by this mod.
- **File access fails:** ensure the game can create and update its local
  `input.txt` and `output.txt` files.

## Building the PK3

For contributors, open `SL_CrowdControl` with
[SLADE](http://slade.mancubus.net/index.php?page=downloads) and use
**Archive → Build Archive** to export a PK3. See the
<https://wiki.srb2.org/wiki/PK3> for PK3 resources.

## Repository layout

- `DrRobotniksRingRacers.cs` defines the pack.
- `SL_CrowdControl/` and `Graphics/` contain the game-side source and artwork.
