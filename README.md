# Garmin Connect IQ apps

Sport apps (below) plus a set of watch faces (see [Watch faces](#watch-faces)).

Three small Connect IQ watch apps for sports the Garmin Approach S62 doesn't
track natively. Each one records a real FIT activity with heart rate, so it
syncs to Garmin Connect under the right sport.

| App | Saves as | Tracks |
|---|---|---|
| [Bouldering](Bouldering/) | Bouldering | Problems, grade (V-scale), attempts, sends, flashes; one lap per problem |
| [Badminton](Badminton/) | Badminton | Heart rate, time, calories |
| [GolfRange](GolfRange/) | Golf | Swing count (auto-detected from the accelerometer, with manual correction), heart rate, time |

Built for the **Approach S62** (`approachs62`, Connect IQ 3.0). Other devices
need to be added to each app's `manifest.xml` and checked for screen layout.

## Watch faces

| Face | Notes |
|---|---|
| [Athlete](Athlete/) | Time since last basketball / golf / badminton / bouldering / workout, via a Strava relay (`Athlete/relay/`, a Cloudflare Worker) |
| [AthleteHeat](AthleteHeat/), [AthleteHeatLite](AthleteHeatLite/), [AthleteRings](AthleteRings/) | Variants sharing code in [Shared/](Shared/source/) |
| [Orrery](Orrery/) | Standalone face |

`Tools/fit_sport.py` rewrites the sport type of an exported FIT file.

### Secrets (not in the repo)

`Athlete/source/Credentials.mc` and `Shared/source/Credentials.mc` are
gitignored. After cloning, copy each `Credentials.mc.example` to
`Credentials.mc` and fill in your relay URL and key (see
`Athlete/relay/README.md`). The Athlete faces won't build without them.

## Building

1. Install a JDK (17 works), the
   [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/), and
   the **Monkey C** VS Code extension. In the SDK Manager, download an SDK and
   the devices you want.
2. Generate a developer key (`Monkey C: Generate a Developer Key` in VS Code).
   Keep it outside the repo.
3. Build an app from its folder:

   ```
   cd Bouldering
   monkeyc -f monkey.jungle -d approachs62 -o bin/Bouldering.prg -y path/to/developer_key.der
   ```

   Add `-r` for a release build, or use `-e -o bin/Bouldering.iq` to export a
   store package.

In VS Code, open the app's folder (not the repo root) to run it in the
simulator with F5.

## Installing

- **Sideload:** copy the `.prg` file to `GARMIN/Apps/` on the watch over USB,
  then unplug it.
- **Connect IQ Store (private beta):** upload the `.iq` file at
  [apps.garmin.com/developer](https://apps.garmin.com/developer/) with
  "This app is for testing purposes only" ticked, then install it from the
  app's page. Store icons and screenshots are in each app's `store/` folder.

Garmin Connect only displays an app's custom fields (Bouldering's problem stats,
GolfRange's swing count) when the app was installed from the Connect IQ Store.
Sideloaded apps still record them in the FIT file, and heart rate, time and
calories show either way.

## Notes

- **Menus:** on the S62, the built-in `Menu2` only scrolls by swiping, so the
  buttons can't reach items below the fold. Each app uses a small custom list
  menu (`source/Menus.mc`) that works with buttons and taps.
- **No native climbing data:** Garmin Connect's own "Total Routes" and
  "Max Difficulty" come from FIT messages that Connect IQ apps can't write.
  Bouldering records its stats as developer fields and laps instead.
- **App IDs:** each `manifest.xml` has a fixed app UUID. If you fork this to
  publish your own version, generate new ones.
