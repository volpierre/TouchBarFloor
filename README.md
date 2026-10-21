# TouchBarFloor

Stops the Touch Bar on M1 MacBook Pros from flickering in dark rooms by keeping its brightness from dropping too low.

## The problem

On some Touch Bar MacBook Pros, the Touch Bar flickers when the room is dark. The Touch Bar sets its own brightness from the ambient light sensor, and it ignores the "Automatically adjust brightness" setting for the main display. In the dark it dims to its lowest level, and on affected units that is exactly where the flickering happens.

A quick way to check if this is your problem: when the Touch Bar flickers, shine your phone's flashlight at the top of the screen near the camera. If the flickering stops, this tool should help.

## What it does

TouchBarFloor runs quietly in the background and checks the Touch Bar brightness twice a second. If macOS dims it below the level you choose (the "floor"), it raises it back up. The default floor is maximum brightness.

Brightness changes are temporary by design: no settings are saved, and if you stop or uninstall the tool, macOS takes back control on its own.

## Requirements

- A MacBook Pro with a Touch Bar
- Xcode Command Line Tools (install with `xcode-select --install`)
- No sudo or admin password needed

## Install

1. Download this repository and open Terminal in its folder.
2. Optional but recommended, test first:
   ```
   bash install.sh --build-only
   ~/Library/Application\ Support/TouchBarFloor/tbfloor set 1.0
   ```
   If the Touch Bar brightens, it works on your Mac.
3. Install it so it runs at every login:
   ```
   bash install.sh
   ```
   To use a lower floor instead of maximum, pass a value from 0.0 to 1.0:
   ```
   bash install.sh 0.5
   ```

## Uninstall

```
bash uninstall.sh
```

## Other commands

```
~/Library/Application\ Support/TouchBarFloor/tbfloor status
```
Shows the current Touch Bar brightness, display state and driver brightness in nits.

The log is at `~/Library/Logs/TouchBarFloor.log`. If it shows the brightness being raised very often, macOS is fighting the tool, and a lower floor may feel smoother.

## Caveats

- **Tested on one machine only:** a 13-inch M1 MacBook Pro (MacBookPro17,1) on macOS 27.0.1. Other models and macOS versions may behave differently.
- **Uses private Apple APIs** (DFRBrightness and CoreBrightness). Any macOS update could break it. If it stops working after an update, try running `bash install.sh` again to rebuild.
- **Burn-in:** the Touch Bar is an OLED display. Running it at full brightness all the time may speed up burn-in of icons that stay in one place. If you are worried, use a lower floor such as 0.5.
- **This is a workaround, not a repair.** If your Touch Bar also flickers in bright light, it is likely a hardware fault.
- This project was written with help from an AI assistant (Claude). Use it at your own risk.

## Credits

The method for reading and setting the Touch Bar brightness comes from [TouchBarController](https://github.com/skimmilk/TouchBarController) (MIT License). Parts of `tbfloor.m` are adapted from its source. See `LICENSE`.
