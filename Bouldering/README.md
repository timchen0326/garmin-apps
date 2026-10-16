# Bouldering

Records a bouldering session as a **Bouldering** activity (FIT sport 31,
sub-sport 69). Each problem is saved as a lap with its grade, attempt count and
whether it was sent.

## Controls

| Button | Before start | During session |
|---|---|---|
| START | Start session | Menu: Sent! / Fell / Give up / Pause / End session |
| BACK | Exit app | Log a fall (+1 attempt) |
| UP / DOWN | Lower / raise grade | Lower / raise grade of the current problem |
| Hold UP | — | Same menu as START |

- **Sent!** closes the problem as a lap. The send counts as an attempt, and a
  send on the first attempt counts as a flash.
- **Give up** closes the problem as a lap marked not sent.
- **End session** pauses, then offers Save / Resume / Discard. Any unfinished
  problem with attempts is saved as not sent.
- Grades run VB to V17. The last grade used is remembered.

The main screen shows elapsed time, problem number, grade, attempts, sends and
flashes, a rest timer (time since your last fall or send) and heart rate.

## Data in Garmin Connect

| Where | Fields |
|---|---|
| Activity summary | Problems, Sends, Flashes, Attempts, Top V Grade |
| Laps | V Grade, Attempts, Sent (1/0) |

These are developer fields, so Connect only shows them when the app is
installed from the Connect IQ Store. VB is recorded as -1.
