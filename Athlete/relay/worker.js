// Cloudflare Worker: asks Strava for your recent activities and answers with
// just the last start time (epoch seconds) per sport, e.g.
//   {"b":1760500000,"g":1760100000,"m":...,"c":...,"w":...}
// The watch can't parse Strava's raw response (top-level JSON array, too big).
//
// With ?x=2 (HeatLite) and the CAL_ICS_URL secret set, it also adds your next
// calendar events (see calendar.js):
//   "e": [[start epoch, end epoch, "title"], ...]   soonest first, at most 4

import { nextEvents } from "./calendar.js";

function classify(a) {
  const type = a.sport_type || a.type || "";
  const name = (a.name || "").toLowerCase();
  if (type === "Basketball" || name.includes("basketball")) return "b";
  if (type === "Golf") return "g";
  if (type === "Badminton") return "m";
  if (type === "RockClimbing" || name.includes("bouldering")) return "c";
  if (["Workout", "WeightTraining", "Crossfit", "HighIntensityIntervalTraining"].includes(type)) return "w";
  return null;
}

// Last-activity display (x=2, HeatLite): a short sport code for the dot color
// and a label of at most 11 characters for any Strava sport type.
const LABELS = {
  b: "Basketball", g: "Golf", m: "Badminton", c: "Bouldering",
  WeightTraining: "Weights", HighIntensityIntervalTraining: "HIIT", Crossfit: "Crossfit", Workout: "Workout",
};
const EXTRA_CODES = {
  Run: "r", TrailRun: "r", VirtualRun: "r",
  Ride: "k", MountainBikeRide: "k", GravelRide: "k", EBikeRide: "k", VirtualRide: "k",
  Swim: "s", Walk: "h", Hike: "h", Yoga: "y", Pilates: "y",
};

function codeOf(a) {
  return classify(a) || EXTRA_CODES[a.sport_type || a.type] || "o";
}

function labelOf(a, code) {
  const type = a.sport_type || a.type || "";
  const label = LABELS[code] || LABELS[type] || type.replace(/([a-z])([A-Z])/g, "$1 $2") || "Activity";
  return label.slice(0, 11);
}

// Parsing a big calendar costs CPU, so the result is kept in KV for 10 min
// (events reach 26 h ahead, so a slightly old list is still right; ones that
// have ended are dropped on the way out).
async function cachedEvents(env) {
  const now = Math.floor(Date.now() / 1000);
  const hit = env.STATE && (await env.STATE.get("cal", "json"));
  if (hit && now - hit.ts < 600) return hit.e.filter((e) => e[1] > now);
  const e = await nextEvents(env.CAL_ICS_URL, now);
  if (e && env.STATE) await env.STATE.put("cal", JSON.stringify({ ts: now, e }));
  return e;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.searchParams.get("key") !== env.RELAY_KEY) {
      return new Response("unauthorized", { status: 401 });
    }

    // Calendar runs alongside Strava; a broken feed only drops the "e" key.
    const calPromise = url.searchParams.get("x") === "2" && env.CAL_ICS_URL
      ? cachedEvents(env).catch(() => null)
      : Promise.resolve(null);

    // Strava may rotate the refresh token, so the newest one lives in KV.
    const refresh = (env.STATE && (await env.STATE.get("refresh"))) || env.STRAVA_REFRESH_TOKEN;
    const tokenRes = await fetch("https://www.strava.com/oauth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: env.STRAVA_CLIENT_ID,
        client_secret: env.STRAVA_CLIENT_SECRET,
        grant_type: "refresh_token",
        refresh_token: refresh,
      }),
    });
    if (!tokenRes.ok) return new Response("strava token error", { status: 502 });
    const token = await tokenRes.json();
    if (env.STATE && token.refresh_token && token.refresh_token !== refresh) {
      await env.STATE.put("refresh", token.refresh_token);
    }

    const after = Math.floor(Date.now() / 1000) - 120 * 86400;
    const actsRes = await fetch(
      `https://www.strava.com/api/v3/athlete/activities?per_page=200&after=${after}`,
      { headers: { Authorization: `Bearer ${token.access_token}` } }
    );
    if (!actsRes.ok) return new Response("strava activities error", { status: 502 });

    // With ?x=1 (the Heat / Rings faces) also send "d" and "m". Older faces
    // would choke on the extra keys, so they stay opt-in.
    //   d: {sport: bitmask}, bit n set = a session in the n-th 24 h before now (n = 0..27)
    //   m: {sport: [minutes in the last 7 days, best of the last 8 such weeks]}
    // With ?x=2 (HeatLite) also send the newest activity of any sport and every
    // activity of the last 8 days (the watch sorts them into its own calendar days):
    //   a: [sport code, start epoch, minutes, label]
    //   k: [[sport code, start epoch, moving minutes], ...], newest first
    const x = url.searchParams.get("x");
    const ext = x === "1" || x === "2";
    const nowS = Math.floor(Date.now() / 1000);
    const days = {};
    const weeks = {};
    const recent = [];
    let latest = null;

    const out = {};
    for (const a of await actsRes.json()) {
      const key = classify(a);
      const ts = Math.floor(Date.parse(a.start_date) / 1000);
      if (x === "2") {
        const code = codeOf(a);
        const mins = Math.round((a.moving_time || 0) / 60);
        // The headline shows elapsed time, which is what Strava shows for golf
        // (moving time only counts the walking).
        const total = Math.round((a.elapsed_time || a.moving_time || 0) / 60);
        if (!latest || ts > latest[1]) latest = [code, ts, total, labelOf(a, code)];
        if (nowS - ts < 8 * 86400) recent.push([code, ts, mins]);
      }
      if (key && (!out[key] || ts > out[key])) out[key] = ts;
      if (key && ext) {
        const ago = Math.floor((nowS - ts) / 86400);
        if (ago >= 0 && ago < 28) days[key] = (days[key] || 0) | (1 << ago);
        if (ago >= 0 && ago < 56) {
          weeks[key] = weeks[key] || new Array(8).fill(0);
          weeks[key][Math.floor(ago / 7)] += (a.moving_time || 0) / 60;
        }
      }
    }
    if (ext) {
      out.d = days;
      out.m = {};
      for (const k of Object.keys(weeks)) {
        out.m[k] = [Math.round(weeks[k][0]), Math.round(Math.max(...weeks[k]))];
      }
    }
    if (x === "2") {
      if (latest) out.a = latest;
      out.k = recent.sort((p, q) => q[1] - p[1]).slice(0, 24);
    }
    const cal = await calPromise;
    if (cal) out.e = cal;
    return Response.json(out, { headers: { "Cache-Control": "max-age=300" } });
  },
};
