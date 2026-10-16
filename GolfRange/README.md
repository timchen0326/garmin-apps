# Golf Range

Counts swings at the driving range and records heart rate and time as a
**Golf** activity (FIT sport 25).

## Controls

| Button | Before start | During session |
|---|---|---|
| START | Start session | Pause and open menu: Resume / Save / Undo swing / Auto count / Discard |
| BACK | Exit app | Add a swing by hand |
| Hold UP | Set auto-count sensitivity | — |

## Swing detection

The app samples the accelerometer at 25 Hz. A swing is counted when any sample
exceeds a threshold, followed by a 2.5 s lockout so the follow-through doesn't
count twice. The watch buzzes briefly on each counted swing.

| Auto count | Threshold |
|---|---|
| Off | Manual only (BACK) |
| Low | 5 g |
| Medium (default) | 3.5 g |
| High | 2.5 g |

The thresholds are a starting point and haven't been tuned on real swings yet.
If it counts practice swings or waggles, use Low; if it misses chips, use High.
Constants are in `source/GolfRangeApp.mc`.

## Data in Garmin Connect

The swing count is saved as a developer field (**Swings**) in the activity
summary. Connect only shows it when the app is installed from the Connect IQ
Store. Heart rate, time and calories show either way.
