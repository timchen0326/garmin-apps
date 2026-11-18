// Reads an iCal (.ics) feed (Google / iCloud / Outlook "secret address") and
// returns the next few timed events as [startEpoch, endEpoch, title], soonest
// first. All-day events are skipped (they would always count as "now").
//
// Handles what calendar apps actually export: TZID times (via Intl), UTC and
// floating times, DURATION, repeating events (DAILY / WEEKLY / MONTHLY /
// YEARLY with INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY), EXDATE, edited
// single occurrences (RECURRENCE-ID) and cancelled events.

const TITLE_MAX = 40;
const LOOKAHEAD_S = 26 * 3600; // a little over a day; the watch filters to "today"
const MAX_EVENTS = 4;

// Outlook writes Windows zone names; map the common ones to IANA.
const WINDOWS_TZ = {
  "Pacific Standard Time": "America/Los_Angeles",
  "Mountain Standard Time": "America/Denver",
  "US Mountain Standard Time": "America/Phoenix",
  "Central Standard Time": "America/Chicago",
  "Eastern Standard Time": "America/New_York",
  "Atlantic Standard Time": "America/Halifax",
  "Newfoundland Standard Time": "America/St_Johns",
  "Alaskan Standard Time": "America/Anchorage",
  "Hawaiian Standard Time": "Pacific/Honolulu",
  "GMT Standard Time": "Europe/London",
  "W. Europe Standard Time": "Europe/Berlin",
  "Romance Standard Time": "Europe/Paris",
  "Central European Standard Time": "Europe/Warsaw",
  "China Standard Time": "Asia/Shanghai",
  "Taipei Standard Time": "Asia/Taipei",
  "Tokyo Standard Time": "Asia/Tokyo",
  "Korea Standard Time": "Asia/Seoul",
  "Singapore Standard Time": "Asia/Singapore",
  "AUS Eastern Standard Time": "Australia/Sydney",
  "India Standard Time": "Asia/Kolkata",
  "UTC": "UTC",
};

const DAY_CODES = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

export async function nextEvents(icsUrl, nowS) {
  const res = await fetch(icsUrl.replace(/^webcal:/i, "https:"), { cf: { cacheTtl: 300 } });
  if (!res.ok) return null;
  return eventsFromIcs(await res.text(), nowS);
}

export function eventsFromIcs(text, nowS) {
  const lines = nearbyBlocks(text, nowS).replace(/\r\n[ \t]/g, "").replace(/\n[ \t]/g, "").split(/\r?\n/);
  let calTz = "UTC";
  const events = [];
  let cur = null;
  let depth = 0; // skip nested blocks such as VALARM inside VEVENT
  for (const line of lines) {
    if (line === "BEGIN:VEVENT") { cur = { exdates: [] }; depth = 0; continue; }
    if (line === "END:VEVENT") { if (cur) events.push(cur); cur = null; continue; }
    if (!cur) {
      if (line.startsWith("X-WR-TIMEZONE:")) calTz = zoneName(line.slice(14).trim()) || calTz;
      continue;
    }
    if (line.startsWith("BEGIN:")) { depth++; continue; }
    if (line.startsWith("END:")) { depth--; continue; }
    if (depth > 0) continue;
    const p = parseLine(line);
    if (!p) continue;
    switch (p.name) {
      case "SUMMARY": cur.title = unescape(p.value); break;
      case "UID": cur.uid = p.value; break;
      case "STATUS": cur.status = p.value.toUpperCase(); break;
      case "DTSTART": cur.start = p; break;
      case "DTEND": cur.end = p; break;
      case "DURATION": cur.duration = parseDuration(p.value); break;
      case "RRULE": cur.rrule = parseRule(p.value); break;
      case "EXDATE": for (const v of p.value.split(",")) cur.exdates.push({ ...p, value: v }); break;
      case "RECURRENCE-ID": cur.recurrenceId = p; break;
    }
  }

  const from = nowS - 86400;
  const to = nowS + LOOKAHEAD_S;

  // Edited single occurrences replace the matching occurrence of the series.
  const overridden = new Set();
  for (const ev of events) {
    if (ev.recurrenceId && ev.uid) {
      const t = toEpoch(ev.recurrenceId, calTz);
      if (t != null) overridden.add(ev.uid + "@" + t);
    }
  }

  const out = [];
  for (const ev of events) {
    if (!ev.start || ev.status === "CANCELLED") continue;
    if (isDate(ev.start)) continue; // all-day
    const s0 = toEpoch(ev.start, calTz);
    if (s0 == null) continue;
    let len = 3600;
    if (ev.end) {
      const e0 = toEpoch(ev.end, calTz);
      if (e0 != null) len = Math.max(0, e0 - s0);
    } else if (ev.duration != null) {
      len = ev.duration;
    }
    // The watch fonts can't draw emoji (they show as boxes and eat the length limit).
    const clean = (ev.title || "").replace(/[\p{Extended_Pictographic}\uFE0F\u200D]/gu, "").replace(/\s+/g, " ").trim();
    const title = Array.from(clean || "Busy").slice(0, TITLE_MAX).join("");

    if (!ev.rrule || ev.recurrenceId) {
      if (s0 < to && s0 + len > from) out.push([s0, s0 + len, title]);
      continue;
    }
    const ex = new Set(ev.exdates.map((d) => toEpoch(d, calTz)));
    const tz = zoneOf(ev.start, calTz);
    for (const t of occurrences(ev.start, ev.rrule, tz, s0, from, to)) {
      if (t + len <= from) continue;
      if (ex.has(t) || (ev.uid && overridden.has(ev.uid + "@" + t))) continue;
      out.push([t, t + len, title]);
    }
  }

  return out
    .filter((e) => e[1] > nowS && e[0] < to)
    .sort((a, b) => a[0] - b[0])
    .slice(0, MAX_EVENTS);
}

// --- Parsing ---------------------------------------------------------------

// Work calendars hold years of history (a few MB). Fully parsing it all costs
// far more CPU than a free Worker gets, so first drop one-off events whose
// dates (DTSTART / RECURRENCE-ID) are nowhere near today. Repeating events are
// always kept. The +-3 day margin covers any time zone.
function nearbyBlocks(text, nowS) {
  const ymd = (s) => new Date(s * 1000).toISOString().slice(0, 10).replace(/-/g, "");
  const lo = ymd(nowS - 3 * 86400);
  const hi = ymd(nowS + 3 * 86400);
  const parts = text.split("BEGIN:VEVENT");
  const keep = [parts[0]];
  const dateRe = /\n(?:DTSTART|RECURRENCE-ID)[^:\r\n]*:(\d{8})/g;
  for (let i = 1; i < parts.length; i++) {
    const b = parts[i];
    if (/\nDTSTART;VALUE=DATE:/.test(b)) continue; // all-day, skipped later anyway
    const rule = /\nRRULE:([^\r\n]*)/.exec(b);
    const until = rule && /UNTIL=(\d{8})/.exec(rule[1]);
    if (until && until[1] < lo) continue; // a series that has ended
    let near = !!rule;
    if (!near) {
      dateRe.lastIndex = 0;
      for (let m; (m = dateRe.exec(b)) && !near;) near = m[1] >= lo && m[1] <= hi;
    }
    if (near) keep.push(b);
  }
  return keep.join("BEGIN:VEVENT");
}

function parseLine(line) {
  const colon = findValueColon(line);
  if (colon < 0) return null;
  const head = line.slice(0, colon).split(";");
  const params = {};
  for (const part of head.slice(1)) {
    const eq = part.indexOf("=");
    if (eq > 0) params[part.slice(0, eq).toUpperCase()] = part.slice(eq + 1).replace(/^"|"$/g, "");
  }
  return { name: head[0].toUpperCase(), params, value: line.slice(colon + 1) };
}

// The first colon that is not inside a quoted parameter value.
function findValueColon(line) {
  let q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') q = !q;
    else if (c === ":" && !q) return i;
  }
  return -1;
}

function unescape(v) {
  return v.replace(/\\n/gi, " ").replace(/\\([,;\\])/g, "$1");
}

function parseDuration(v) {
  const m = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(v.trim());
  if (!m) return null;
  const s = (+m[2] || 0) * 604800 + (+m[3] || 0) * 86400 + (+m[4] || 0) * 3600 + (+m[5] || 0) * 60 + (+m[6] || 0);
  return m[1] === "-" ? -s : s;
}

function parseRule(v) {
  const r = {};
  for (const part of v.split(";")) {
    const [k, val] = part.split("=");
    if (k && val != null) r[k.toUpperCase()] = val;
  }
  return r;
}

function isDate(p) {
  return p.params.VALUE === "DATE" || /^\d{8}$/.test(p.value.trim());
}

function zoneName(tzid) {
  if (!tzid) return null;
  const name = WINDOWS_TZ[tzid] || tzid.replace(/^\/.*?\/(?=[A-Za-z]+\/)/, ""); // strip "/mozilla.org/..." prefixes
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: name });
    return name;
  } catch {
    return null;
  }
}

function zoneOf(p, calTz) {
  if (/Z$/.test(p.value.trim())) return "UTC";
  return zoneName(p.params.TZID) || calTz;
}

// Wall-clock parts of a DATE-TIME value.
function parts(v) {
  const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?)?/.exec(v.trim());
  if (!m) return null;
  return { y: +m[1], mo: +m[2], d: +m[3], h: +(m[4] || 0), mi: +(m[5] || 0), s: +(m[6] || 0) };
}

function toEpoch(p, calTz) {
  const w = parts(p.value);
  if (!w) return null;
  return wallToEpoch(w, zoneOf(p, calTz));
}

// --- Time zones --------------------------------------------------------------

const fmtCache = {};
function offsetAt(ms, tz) {
  if (tz === "UTC") return 0;
  const f = fmtCache[tz] || (fmtCache[tz] = new Intl.DateTimeFormat("en-US", {
    timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }));
  const o = {};
  for (const x of f.formatToParts(new Date(ms))) o[x.type] = x.value;
  const asUtc = Date.UTC(+o.year, +o.month - 1, +o.day, +o.hour % 24, +o.minute, +o.second);
  return asUtc - Math.floor(ms / 1000) * 1000;
}

function wallToEpoch(w, tz) {
  const guess = Date.UTC(w.y, w.mo - 1, w.d, w.h, w.mi, w.s);
  let t = guess - offsetAt(guess, tz);
  t = guess - offsetAt(t, tz);
  return Math.floor(t / 1000);
}

// --- Recurrence --------------------------------------------------------------

// Start times (epoch s) of a repeating event from its first start up to `to`.
// Steps through wall-clock dates so the time of day stays put across DST.
function* occurrences(startProp, rule, tz, s0, from, to) {
  const w = parts(startProp.value);
  const freq = (rule.FREQ || "").toUpperCase();
  const interval = Math.max(1, parseInt(rule.INTERVAL || "1", 10));
  const count = rule.COUNT ? parseInt(rule.COUNT, 10) : Infinity;
  let until = Infinity;
  if (rule.UNTIL) {
    const u = parts(rule.UNTIL);
    if (u) until = /Z$/.test(rule.UNTIL) ? Date.UTC(u.y, u.mo - 1, u.d, u.h, u.mi, u.s) / 1000
      : wallToEpoch(rule.UNTIL.length === 8 ? { ...u, h: 23, mi: 59, s: 59 } : u, tz);
  }
  const byDay = rule.BYDAY ? rule.BYDAY.split(",").map((x) => {
    const m = /^([+-]?\d+)?([A-Z]{2})$/.exec(x.trim().toUpperCase());
    return m ? { n: m[1] ? parseInt(m[1], 10) : 0, wd: DAY_CODES.indexOf(m[2]) } : null;
  }).filter((x) => x && x.wd >= 0) : null;
  const byMonthDay = rule.BYMONTHDAY ? rule.BYMONTHDAY.split(",").map((x) => parseInt(x, 10)) : null;

  // Dates as day numbers (days since 1970-01-01, wall clock)
  const dayNum = (y, mo, d) => Math.floor(Date.UTC(y, mo - 1, d) / 86400000);
  const fromDay = (n) => { const dt = new Date(n * 86400000); return { y: dt.getUTCFullYear(), mo: dt.getUTCMonth() + 1, d: dt.getUTCDate(), wd: dt.getUTCDay() }; };
  const startDay = dayNum(w.y, w.mo, w.d);

  let emitted = 0;
  const firstUseful = Math.floor(from / 86400) - 2;
  const emit = function* (day) {
    if (day < startDay) return false;
    // Without COUNT, days well before the window don't matter; skip the time zone math
    if (count === Infinity && day < firstUseful) return false;
    const c = fromDay(day);
    const t = wallToEpoch({ y: c.y, mo: c.mo, d: c.d, h: w.h, mi: w.mi, s: w.s }, tz);
    if (t < s0) return false;
    emitted++;
    if (t > until || emitted > count || t >= to) return true;
    yield t;
    return false;
  };

  // Candidate days for one period, sorted
  const periodDays = (p) => {
    if (freq === "DAILY") return [startDay + p * interval];
    if (freq === "WEEKLY") {
      const s = fromDay(startDay);
      const weekStart = startDay - ((s.wd + 6) % 7) + p * interval * 7; // Monday
      if (!byDay) return [weekStart + ((s.wd + 6) % 7)];
      return byDay.map((b) => weekStart + ((b.wd + 6) % 7)).sort((a, b) => a - b);
    }
    if (freq === "MONTHLY" || freq === "YEARLY") {
      const s = fromDay(startDay);
      const months = freq === "MONTHLY" ? [s.mo + p * interval] : [s.mo];
      const year = freq === "YEARLY" ? s.y + p * interval : s.y;
      const out = [];
      for (const m0 of months) {
        const y = year + Math.floor((m0 - 1) / 12);
        const mo = ((m0 - 1) % 12) + 1;
        const first = dayNum(y, mo, 1);
        const len = dayNum(y + (mo === 12 ? 1 : 0), mo === 12 ? 1 : mo + 1, 1) - first;
        if (byDay) {
          for (const b of byDay) {
            const all = [];
            for (let i = 0; i < len; i++) if (fromDay(first + i).wd === b.wd) all.push(first + i);
            if (b.n === 0) out.push(...all);
            else { const pick = b.n > 0 ? all[b.n - 1] : all[all.length + b.n]; if (pick != null) out.push(pick); }
          }
        } else if (byMonthDay) {
          for (const md of byMonthDay) { const d = md > 0 ? md : len + md + 1; if (d >= 1 && d <= len) out.push(first + d - 1); }
        } else if (s.d <= len) {
          out.push(first + s.d - 1);
        }
      }
      return out.sort((a, b) => a - b);
    }
    return null;
  };

  if (!periodDays(0)) { // unsupported FREQ: just the first occurrence
    if (s0 < to) yield s0;
    return;
  }
  const lastDay = Math.floor(to / 86400) + 2;
  for (let p = 0; p < 20000; p++) {
    const days = periodDays(p);
    if (days.length && days[0] > lastDay) return;
    for (const day of days) {
      const it = emit(day);
      let r = it.next();
      while (!r.done) { yield r.value; r = it.next(); }
      if (r.value === true) return;
    }
  }
}
