# Strava relay for the Athlete watch face

The watch face shows time since your last basketball / golf / badminton /
bouldering / workout. It gets that from this small Cloudflare Worker, which
reads your Strava activities and returns one timestamp per sport. Garmin to
Strava auto-sync must be on.

Sport mapping (done in `worker.js`): Golf, Badminton, RockClimbing (or a name
containing "bouldering"), Workout / WeightTraining / Crossfit / HIIT, and
basketball by activity name or type "Basketball" (Strava has no basketball type,
so name your Garmin basketball activities with "Basketball" if it shows `--`).

## 1. Strava API app

1. https://www.strava.com/settings/api: create an app. Set the callback domain to `localhost`.
2. Open this in a browser (replace `CLIENT_ID`) and click Authorize:
   `https://www.strava.com/oauth/authorize?client_id=CLIENT_ID&response_type=code&redirect_uri=http://localhost&approval_prompt=force&scope=activity:read_all`
3. The browser lands on a dead `localhost` page. Copy the `code=...` value from the address bar.
4. Exchange it for a refresh token:
   ```
   curl -X POST https://www.strava.com/oauth/token -d client_id=CLIENT_ID -d client_secret=CLIENT_SECRET -d code=CODE -d grant_type=authorization_code
   ```
   Keep the `refresh_token` from the response.

## 2. Deploy the Worker (free tier)

```
npm i -g wrangler
wrangler login
cd relay
wrangler kv namespace create STATE        # paste the printed id into wrangler.toml
wrangler secret put STRAVA_CLIENT_ID
wrangler secret put STRAVA_CLIENT_SECRET
wrangler secret put STRAVA_REFRESH_TOKEN
wrangler secret put RELAY_KEY             # any long random string
wrangler deploy
```

Test: `curl "https://athlete-relay.<you>.workers.dev/?key=YOUR_RELAY_KEY"`

## 3. Point the watch face at it

Edit `source/Credentials.mc` (gitignored): set `RELAY_URL` to the Worker URL and
`RELAY_KEY` to the same key. Rebuild and copy `bin/Athlete.prg` to the watch.

## 4. Phone location for weather (optional)

An iOS Shortcut sends your phone's position to the Worker, which then returns
weather for that spot (Open-Meteo, Environment Canada GEM model) along with the
Strava data. Without it the watch uses its own last GPS fix.

Shortcuts app, Automation tab, create a Personal Automation (Time of Day,
hourly, or Arrive / Leave), set it to Run Immediately, with these actions:

1. Get Current Location
2. Get Contents of URL:
   `https://athlete-relay.<you>.workers.dev/loc?key=YOUR_RELAY_KEY&lat=` + Latitude of Current Location + `&lon=` + Longitude of Current Location (method GET)

Test it: open `.../?key=YOUR_RELAY_KEY` and look for the `wx` field.

## Extra data for the Heat and Rings faces

`AthleteHeat` and `AthleteRings` call the Worker with `&x=1`, and it then also
returns `d` (per sport, a bitmask of the last 28 days with a session) and `m`
(per sport, minutes in the last 7 days and the best of the last 8 such weeks).
Redeploy the Worker (`wrangler deploy`) before installing them. The Athlete face
does not send `x`, so it is unaffected. Both faces read `Shared/source/Credentials.mc`
(copy it from `Credentials.mc.example`, same values as Athlete's).
