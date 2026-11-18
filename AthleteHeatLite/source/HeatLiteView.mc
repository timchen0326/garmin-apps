import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Heat without steps and calories, for a watch that is not the main tracker:
// battery as an arc across the top, weather under it, 1 h of heart rate behind a
// big clock, and your latest Strava activity with a 7-day dot strip. When a
// calendar event starts within 2 hours (or is on now), it takes the Strava line.
class HeatLiteView extends WatchFace {
    // Set to true to preview the layout with fake data (simulator screenshots).
    private const DEMO = false;
    private const HR_REFRESH = 60;
    private const HR_SPAN = 3600; // the chart covers the last hour
    private const HR_BARS = 40;   // 90 s per bar, 6 px wide
    private const CLOCK_Y = 112;
    private const CHART_BASE = 148;
    private const CHART_HEIGHT = 52;
    private const ACT_Y = 162;
    private const DOT_Y = 202;
    private const LINE_MAX = 212; // widest the headline line may be
    private const STRAVA = 0xFC4C02;
    private const CAL = 0x55AAFF;
    private const SCROLL_PX_S = 28; // marquee speed
    private const SOON = 7200; // show an event from 2 h before it starts

    private var _hr as Array<Number>? = null;
    private var _hrAt as Number = 0;

    private var _awake as Boolean = false;
    private var _wakeAt as Number = 0;

    function initialize() {
        WatchFace.initialize();
    }

    // The long event title scrolls only while the watch is awake (raised wrist).
    // The system redraws about once a second while awake; the scroll position
    // follows the time since waking.
    function onExitSleep() as Void {
        _awake = true;
        _wakeAt = System.getTimer();
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var clock = System.getClockTime();
        var now = Time.now().value();

        Common.refreshLocation(now);
        refreshHeartRate(now);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawHeartRateChart(dc);
        drawBattery(dc, cx);
        drawWeather(dc, cx);
        drawClock(dc, cx, clock);
        drawHeartRate(dc);
        drawStrava(dc, cx, now);
    }

    // --- Data -------------------------------------------------------------

    private function refreshHeartRate(now as Number) as Void {
        if (_hr != null && now - _hrAt < HR_REFRESH) {
            return;
        }
        _hrAt = now;
        if (DEMO) {
            var fake = new [HR_BARS];
            for (var i = 0; i < HR_BARS; i++) {
                fake[i] = (62 + 16 * Math.sin(i / 5.0) + (i * 7) % 13 + ((i > 25 && i < 32) ? 45 : 0)).toNumber();
            }
            _hr = fake as Array<Number>;
            return;
        }
        _hr = Common.recentHeartRate(now, HR_SPAN, HR_BARS);
    }

    // --- Sections ---------------------------------------------------------

    // The last hour of heart rate as bars with a line along the top; the right edge is now.
    private function drawHeartRateChart(dc as Dc) as Void {
        var hr = _hr as Array<Number>;
        var bw = 6;
        var prevX = -1;
        var prevY = 0;
        for (var i = 0; i < HR_BARS; i++) {
            if (hr[i] <= 0) {
                prevX = -1;
                continue;
            }
            var h = (hr[i] - Common.HR_LOW) * CHART_HEIGHT / (Common.HR_HIGH - Common.HR_LOW);
            h = h < 3 ? 3 : (h > CHART_HEIGHT ? CHART_HEIGHT : h);
            var x = i * bw;
            dc.setColor(Common.mix(Common.PINK, 0.3), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, CHART_BASE - h, bw, h);
            var y = CHART_BASE - h;
            if (prevX >= 0) {
                dc.setColor(Common.PINK, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawLine(prevX, prevY, x + bw / 2, y);
                dc.setPenWidth(1);
            }
            prevX = x + bw / 2;
            prevY = y;
        }
    }

    // Battery as an arc across the top, filled left to right, with its percentage below.
    private function drawBattery(dc as Dc, cx as Number) as Void {
        var bat = System.getSystemStats().battery;
        if (DEMO) {
            bat = 84.0;
        }
        var color = Common.batteryColor(bat);
        Common.progressArc(dc, cx, cx, 114, 7, -60, 120, bat / 100.0, color);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 38, Graphics.FONT_XTINY, bat.toNumber() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawWeather(dc as Dc, cx as Number) as Void {
        var w = Application.Storage.getValue("w") as Dictionary?;
        if (DEMO) {
            w = { "t" => 17.6, "c" => 2, "d" => 1, "hi" => 21.0, "lo" => 11.0 };
        }
        Common.drawWeather(dc, cx, 66, w, false);
    }

    private function drawClock(dc as Dc, cx as Number, clock as System.ClockTime) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        Common.drawSegmentTime(dc, cx, CLOCK_Y + 2, Common.hourText(clock), 44, Graphics.COLOR_WHITE);
    }

    private function drawHeartRate(dc as Dc) as Void {
        var hr = Activity.getActivityInfo().currentHeartRate;
        if (DEMO) {
            hr = 72;
        }
        Common.drawHeart(dc, 24, 88, Common.PINK);
        dc.setColor(Common.PINK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(34, 88, Graphics.FONT_XTINY, hr != null ? hr.toString() : "--",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Newest Strava activity as the headline (sport, age, duration, weekday), then
    // one dot per day for the last 7 days, colored by that day's main sport.
    private function drawStrava(dc as Dc, cx as Number, now as Number) as Void {
        var a = Application.Storage.getValue("a") as Array?;
        var k = Application.Storage.getValue("k") as Array?;
        if (DEMO) {
            a = ["c", now - 5 * 3600, 72, "Bouldering"];
            k = [["c", now - 5 * 3600, 72], ["w", now - 3 * 86400, 50], ["m", now - 5 * 86400, 60],
                 ["g", now - 6 * 86400, 270], ["b", now - 6 * 86400 - 3600, 40]];
        }

        // Sort the activities into calendar days of the watch's own timezone; the
        // longest one of a day sets that day's dot color.
        var clock = System.getClockTime();
        var off = clock.timeZoneOffset + clock.dst;
        var today = (now + off) / 86400;
        var codes = ["", "", "", "", "", "", ""];
        var best = [-1, -1, -1, -1, -1, -1, -1];
        if (k != null) {
            for (var i = 0; i < k.size(); i++) {
                if (!(k[i] instanceof Array)) {
                    continue; // old format from an earlier build
                }
                var e = k[i] as Array;
                var d = today - ((e[1] as Number) + off) / 86400;
                if (d >= 0 && d < 7 && (e[2] as Number) > (best[d] as Number)) {
                    codes[d] = e[0] as String;
                    best[d] = e[2] as Number;
                }
            }
        }

        var ev = upcomingEvent(dc, now, off);
        if (ev != null) {
            drawHeadline(dc, cx, CAL, true, ev[0] as String, ev[1] as String, ev[2] as String);
        } else if (a != null) {
            var ts = a[1] as Number;
            var day = Gregorian.info(new Time.Moment(ts), Time.FORMAT_MEDIUM).day_of_week as String;
            drawHeadline(dc, cx, sportColor(a[0] as String), false, a[3] as String, ageText(now - ts),
                         durationText(a[2] as Number) + " · " + day);
        } else {
            dc.setColor(Common.GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, ACT_Y, Graphics.FONT_TINY, "--", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Oldest day on the left, today on the right with a ring around it.
        for (var j = 0; j < 7; j++) {
            var n = 6 - j;
            var x = cx - 66 + j * 22;
            var code = codes[n] as String;
            var on = code.length() > 0;
            dc.setColor(on ? sportColor(code) : 0x2A2A2A, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, DOT_Y, 5);
            if (n == 0) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawCircle(x, DOT_Y, 8);
                dc.setPenWidth(1);
            }
            var dow = Gregorian.info(new Time.Moment(now - n * 86400), Time.FORMAT_SHORT).day_of_week as Number;
            dc.setColor(on ? Graphics.COLOR_WHITE : 0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, DOT_Y + 14, Graphics.FONT_XTINY, "SMTWTFS".substring(dow - 1, dow),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // One centered line: marker, name (white), tail right after it (orange for
    // Strava, blue for calendar), and a gray line under it. The name drops to the
    // smaller font, then loses letters, if the line is too wide.
    private function drawHeadline(dc as Dc, cx as Number, color as Number, calendar as Boolean,
                                  name as String, tail as String, sub as String) as Void {
        var tailW = dc.getTextWidthInPixels(tail, Graphics.FONT_TINY);
        var nameFont = Graphics.FONT_TINY;
        var scrollW = 0; // > 0: the name is wider than its slot and scrolls (marquee)
        var slot = LINE_MAX - 14 - 8 - tailW;
        if (dc.getTextWidthInPixels(name, nameFont) > slot) {
            nameFont = Graphics.FONT_XTINY;
            if (dc.getTextWidthInPixels(name, nameFont) > slot) {
                scrollW = dc.getTextWidthInPixels(name, nameFont);
            }
        }
        var nameW = scrollW > 0 ? slot : dc.getTextWidthInPixels(name, nameFont);
        var x0 = cx - (14 + nameW + 8 + tailW) / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (calendar) {
            // a small calendar page
            dc.fillRectangle(x0, ACT_Y - 6, 10, 12);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0 + 2, ACT_Y - 2, 6, 6);
        } else {
            dc.fillCircle(x0 + 5, ACT_Y, 5);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (scrollW > 0) {
            // Loop the name through the slot: pause at the start, then slide left.
            var period = scrollW + 24;
            var pauseMs = 1500;
            var cycleMs = pauseMs + period * 1000 / SCROLL_PX_S;
            var t = _awake ? (System.getTimer() - _wakeAt) % cycleMs : 0;
            var shift = t > pauseMs ? (t - pauseMs) * SCROLL_PX_S / 1000 : 0;
            dc.setClip(x0 + 14, ACT_Y - 16, nameW, 32);
            dc.drawText(x0 + 14 - shift, ACT_Y, nameFont, name,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(x0 + 14 - shift + period, ACT_Y, nameFont, name,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.clearClip();
        } else {
            dc.drawText(x0 + 14, ACT_Y, nameFont, name,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.setColor(calendar ? CAL : STRAVA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + 14 + nameW + 8, ACT_Y, Graphics.FONT_TINY, tail,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Common.LIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ACT_Y + 17, Graphics.FONT_XTINY, sub,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The next calendar event if it is on now or starts within SOON, as
    // [title, "in 1h 22m" or "now", "11:30 - 13:00 · +2 today"]; null otherwise.
    // Events come from the relay soonest first: [start, end, title].
    private function upcomingEvent(dc as Dc, now as Number, off as Number) as Array? {
        var list = Application.Storage.getValue("e") as Array?;
        if (DEMO) {
            list = [[now + 82 * 60, now + 172 * 60, "Climbing gym"], [now + 232 * 60, now + 277 * 60, "Groceries"],
                    [now + 532 * 60, now + 652 * 60, "Dinner"]];
        }
        if (list == null) {
            return null;
        }
        var today = (now + off) / 86400;
        var pickAt = -1;
        var more = 0;
        for (var i = 0; i < list.size(); i++) {
            if (!(list[i] instanceof Array) || (list[i] as Array).size() < 3) {
                continue;
            }
            var e = list[i] as Array;
            var start = e[0] as Number;
            if ((e[1] as Number) <= now) {
                continue; // already over
            }
            if (pickAt < 0) {
                if (start - now > SOON) {
                    return null; // the soonest one is still far off
                }
                pickAt = i;
            } else if ((start + off) / 86400 == today) {
                more += 1;
            }
        }
        if (pickAt < 0) {
            return null;
        }
        var pick = list[pickAt] as Array;
        var start = pick[0] as Number;
        var end = pick[1] as Number;
        var tail = start <= now ? "now" : "in " + countdownText(start - now);
        var times = start <= now ? "until " + clockText(end) : clockText(start) + " - " + clockText(end);
        var sub = more > 0 ? times + " · +" + more + " today" : times;
        if (dc.getTextWidthInPixels(sub, Graphics.FONT_XTINY) > LINE_MAX) {
            sub = more > 0 ? times + " · +" + more : times;
        }
        return [pick[2] as String, tail, sub];
    }

    // --- Formatting -------------------------------------------------------

    // Time of day of an epoch, in the watch's 12 / 24 h setting.
    private function clockText(t as Number) as String {
        var info = Gregorian.info(new Time.Moment(t), Time.FORMAT_SHORT);
        var h = info.hour as Number;
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12 == 0 ? 12 : h % 12;
        }
        return h + ":" + (info.min as Number).format("%02d");
    }

    // Minutes only ("82m"): events show at most SOON ahead, and it leaves room for the title.
    private function countdownText(secs as Number) as String {
        return ((secs + 59) / 60) + "m";
    }

    // The five tracked sports use their usual colors; run, ride, swim, hike and
    // yoga get their own, anything else is Strava orange.
    private function sportColor(code as String) as Number {
        for (var i = 0; i < Common.SPORT_KEYS.size(); i++) {
            if (code.equals(Common.SPORT_KEYS[i])) {
                return Common.SPORT_COLORS[i];
            }
        }
        if (code.equals("r")) { return 0xFF3C6E; }
        if (code.equals("k")) { return 0x55AAFF; }
        if (code.equals("s")) { return 0x00C8FF; }
        if (code.equals("h")) { return 0x88CC44; }
        if (code.equals("y")) { return 0xCC88FF; }
        return STRAVA;
    }

    private function ageText(age as Number) as String {
        if (age < 3600) {
            return (age < 0 ? 0 : age / 60) + "m";
        }
        if (age < 86400) {
            return (age / 3600) + "h";
        }
        if (age < 14 * 86400) {
            return (age / 86400) + "d";
        }
        return (age / (7 * 86400)) + "w";
    }

    private function durationText(mins as Number) as String {
        if (mins < 60) {
            return mins + "m";
        }
        return (mins / 60) + "h " + (mins % 60) + "m";
    }
}
