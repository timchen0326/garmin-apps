import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

// Training-focused face: time, weather, heart rate / steps / calories, and how
// long since you last did each sport. Data comes from the background service.
class AthleteView extends WatchFace {
    // Set to true to preview the layout with fake data (simulator screenshots).
    private const DEMO = false;

    private const YELLOW = 0xFFFF55;
    private const ORANGE = 0xFFAA00;
    private const GRAY = 0x555555;
    private const LIGHT = 0xAAAAAA;
    private const STEPS = 0x55AAFF;
    private const PINK = 0xFF0055;
    private const MAX_HR = 190;

    // The five sports share an arc across the top of the ring (left to right),
    // each with a segment and its own color.
    // The segment drains over SPAN_DAYS since you last did the sport.
    private const SPAN_DAYS = 14;
    private const SEG = 28;
    private const SEG_SPAN = 26;
    private const SEG_START = -69; // clock degrees, negative = left of 12
    private const SPORTS = [
        ["b", 0xFF5500], // basketball: ball orange
        ["g", 0x55AA00], // golf: turf green
        ["m", 0xFFFFFF], // badminton: white feathers
        ["c", 0xAAAAAA], // bouldering: stone gray
        ["w", 0x55AAAA]  // workout: steel plates
    ] as Array<Array>;


    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var clock = System.getClockTime();
        var now = Time.now().value();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawStepsRing(dc, cx, cy);
        drawSportRing(dc, cx, cy, now);
        drawSideGauges(dc, cx, cy);
        drawDate(dc, cx);
        drawTime(dc, cx, clock);
        drawVitals(dc, cx);
    }

    // --- Data -------------------------------------------------------------

    // --- Sections ---------------------------------------------------------

    // Steps fill the bottom of the ring, left to right through 6 o'clock.
    private function drawStepsRing(dc as Dc, cx as Number, cy as Number) as Void {
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var goal = info.stepGoal;
        if (DEMO) {
            steps = 8214;
            goal = 10000;
        }
        if (steps == null || goal == null || goal <= 0) {
            return;
        }
        var frac = steps.toFloat() / goal;
        if (frac > 1.0) {
            frac = 1.0;
        }
        dc.setPenWidth(9);
        dc.setColor(mix(STEPS, 0.3), Graphics.COLOR_TRANSPARENT);
        arcClock(dc, cx, cy, 117, 122, 238);
        if (frac > 0.01) {
            dc.setColor(STEPS, Graphics.COLOR_TRANSPARENT);
            arcClock(dc, cx, cy, 117, 238 - 116 * frac, 238);
        }
        dc.setPenWidth(1);
    }

    // Five colored ring segments, one per sport. The lit part shrinks as the
    // days since the last session grow; the icon and age sit just inside.
    private function drawSportRing(dc as Dc, cx as Number, cy as Number, now as Number) as Void {
        var last = Application.Storage.getValue("s") as Dictionary?;
        if (DEMO) {
            last = { "b" => now - 3 * 3600, "g" => now - 5 * 86400, "m" => now - 2 * 86400,
                     "c" => now - 9 * 86400, "w" => now - 20 * 3600 };
        }
        for (var i = 0; i < SPORTS.size(); i++) {
            var key = SPORTS[i][0] as String;
            var color = SPORTS[i][1] as Number;
            var start = SEG_START + i * SEG;
            var t = (last != null && last.hasKey(key)) ? (last[key] as Number) : null;
            var age = t != null ? now - t : -1;

            dc.setPenWidth(9);
            dc.setColor(mix(color, 0.3), Graphics.COLOR_TRANSPARENT);
            arcClock(dc, cx, cy, 117, start, start + SEG_SPAN);
            if (age >= 0) {
                var f = 1.0 - age.toFloat() / (SPAN_DAYS * 86400);
                if (f > 0.03) {
                    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                    arcClock(dc, cx, cy, 117, start, start + SEG_SPAN * f);
                }
            }
            dc.setPenWidth(1);

            var mid = (start + SEG_SPAN / 2) * 0.017453292;
            var lx = (cx + 90 * Math.sin(mid)).toNumber();
            var ly = (cy - 90 * Math.cos(mid)).toNumber();
            drawSportIcon(dc, key, lx, ly - 9, age >= 0);
            dc.setColor(age >= 0 ? color : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(lx, ly + 12, Graphics.FONT_XTINY, ageText(age),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Left side: heart rate against max. Right side: battery.
    private function drawSideGauges(dc as Dc, cx as Number, cy as Number) as Void {
        var hr = Activity.getActivityInfo().currentHeartRate;
        var bat = System.getSystemStats().battery;
        if (DEMO) {
            hr = 72;
            bat = 84.0;
        }
        var batColor = bat > 30 ? 0x00FF55 : (bat > 15 ? ORANGE : 0xFF0000);

        // Left gauge fills up from the bottom of its arc.
        gauge(dc, cx, cy, 244, 284, hr != null ? hr.toFloat() / MAX_HR : 0.0, PINK, false);
        // Right gauge fills from the top down.
        gauge(dc, cx, cy, 76, 116, bat / 100.0, batColor, false);

        var lx = (cx + 94 * Math.sin(264 * 0.017453292)).toNumber();
        var ly = (cy - 94 * Math.cos(264 * 0.017453292)).toNumber();
        drawHeart(dc, lx, ly - 8, PINK);
        dc.setColor(PINK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, ly + 12, Graphics.FONT_XTINY, hr != null ? hr.toString() : "--",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var rx = (cx + 94 * Math.sin(96 * 0.017453292)).toNumber();
        var ry = (cy - 94 * Math.cos(96 * 0.017453292)).toNumber();
        drawBattery(dc, rx, ry - 8, bat, batColor);
        dc.setColor(batColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rx, ry + 12, Graphics.FONT_XTINY, bat.toNumber().toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // A ring segment from a0 to a1 (clock degrees) filled to frac. fromEnd fills from a1 backwards.
    private function gauge(dc as Dc, cx as Number, cy as Number, a0 as Number, a1 as Number,
                           frac as Float, color as Number, fromEnd as Boolean) as Void {
        if (frac > 1.0) {
            frac = 1.0;
        }
        dc.setPenWidth(9);
        dc.setColor(mix(color, 0.3), Graphics.COLOR_TRANSPARENT);
        arcClock(dc, cx, cy, 117, a0, a1);
        if (frac > 0.02) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            var len = (a1 - a0) * frac;
            if (fromEnd) {
                arcClock(dc, cx, cy, 117, a1 - len, a1);
            } else {
                arcClock(dc, cx, cy, 117, a0, a0 + len);
            }
        }
        dc.setPenWidth(1);
    }

    private function drawBattery(dc as Dc, x as Number, y as Number, pct as Float, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x - 9, y - 5, 16, 10);
        dc.fillRectangle(x + 7, y - 2, 2, 4);
        dc.fillRectangle(x - 7, y - 3, (12 * pct / 100.0).toNumber(), 6);
    }

    private function drawDate(dc as Dc, cx as Number) as Void {
        var d = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var s = (d.day_of_week as String).toUpper() + " " + d.day;
        dc.setColor(LIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 78, Graphics.FONT_XTINY, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawTime(dc as Dc, cx as Number, clock as System.ClockTime) as Void {
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        var s = hour.format("%d") + ":" + clock.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 120, Graphics.FONT_NUMBER_HOT, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Bottom of the face: weather, then steps + calories.
    private function drawVitals(dc as Dc, cx as Number) as Void {
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var cals = info.calories;
        if (DEMO) {
            steps = 8214;
            cals = 1954;
        }

        drawWeather(dc, cx, 168);

        var y2 = 200;
        drawFootprints(dc, cx - 68, y2, STEPS);
        drawValue(dc, cx - 58, y2, steps != null ? compact(steps) : "--", STEPS);
        drawFlame(dc, cx + 20, y2, ORANGE);
        drawValue(dc, cx + 30, y2, cals != null ? compact(cals) : "--", ORANGE);
    }

    // The watch's current conditions in the shape drawWeather reads
    // (t, c = weather code for the icon, d = day, hi, lo); null if it has none.
    private function garminWeather() as Dictionary? {
        if (!(Toybox has :Weather)) {
            return null;
        }
        var cc = Weather.getCurrentConditions();
        if (cc == null || cc.temperature == null) {
            return null;
        }
        var t = cc.temperature as Number;
        var hi = cc.highTemperature != null ? cc.highTemperature as Number : t;
        var lo = cc.lowTemperature != null ? cc.lowTemperature as Number : t;
        var hour = System.getClockTime().hour;
        return { "t" => t, "c" => wmoCode(cc.condition), "d" => (hour >= 6 && hour < 20) ? 1 : 0,
                 "hi" => hi, "lo" => lo };
    }

    // Garmin condition -> the weather code the icons are drawn from.
    private function wmoCode(cond as Number?) as Number {
        if (cond == null) {
            return 3;
        }
        switch (cond) {
            case Weather.CONDITION_CLEAR:
            case Weather.CONDITION_FAIR:
            case Weather.CONDITION_MOSTLY_CLEAR:
            case Weather.CONDITION_PARTLY_CLEAR:
                return 0;
            case Weather.CONDITION_PARTLY_CLOUDY:
            case Weather.CONDITION_THIN_CLOUDS:
                return 2;
            case Weather.CONDITION_FOG:
            case Weather.CONDITION_MIST:
            case Weather.CONDITION_HAZY:
            case Weather.CONDITION_HAZE:
            case Weather.CONDITION_SMOKE:
            case Weather.CONDITION_DUST:
                return 45;
            case Weather.CONDITION_THUNDERSTORMS:
            case Weather.CONDITION_SCATTERED_THUNDERSTORMS:
            case Weather.CONDITION_CHANCE_OF_THUNDERSTORMS:
            case Weather.CONDITION_TORNADO:
            case Weather.CONDITION_SQUALL:
            case Weather.CONDITION_HURRICANE:
            case Weather.CONDITION_TROPICAL_STORM:
                return 95;
            case Weather.CONDITION_SNOW:
            case Weather.CONDITION_LIGHT_SNOW:
            case Weather.CONDITION_HEAVY_SNOW:
            case Weather.CONDITION_CHANCE_OF_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW:
            case Weather.CONDITION_FLURRIES:
            case Weather.CONDITION_WINTRY_MIX:
            case Weather.CONDITION_RAIN_SNOW:
            case Weather.CONDITION_LIGHT_RAIN_SNOW:
            case Weather.CONDITION_HEAVY_RAIN_SNOW:
            case Weather.CONDITION_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_ICE_SNOW:
            case Weather.CONDITION_ICE:
            case Weather.CONDITION_HAIL:
                return 71;
            case Weather.CONDITION_RAIN:
            case Weather.CONDITION_LIGHT_RAIN:
            case Weather.CONDITION_HEAVY_RAIN:
            case Weather.CONDITION_SHOWERS:
            case Weather.CONDITION_LIGHT_SHOWERS:
            case Weather.CONDITION_HEAVY_SHOWERS:
            case Weather.CONDITION_SCATTERED_SHOWERS:
            case Weather.CONDITION_CHANCE_OF_SHOWERS:
            case Weather.CONDITION_DRIZZLE:
            case Weather.CONDITION_FREEZING_RAIN:
            case Weather.CONDITION_SLEET:
            case Weather.CONDITION_UNKNOWN_PRECIPITATION:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN:
                return 61;
        }
        return 3; // cloudy, windy and anything else: overcast
    }

    // Icon, temperature and the day's high / low, centered on cx.
    private function drawWeather(dc as Dc, cx as Number, y as Number) as Void {
        var w = garminWeather();
        if (DEMO) {
            w = { "t" => 17.6, "c" => 2, "d" => 1, "hi" => 21.0, "lo" => 11.0 };
        }
        if (w == null) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_TINY, "--", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        drawWeatherIcon(dc, cx - 62, y, w["c"] as Number, (w["d"] as Number) == 1);
        drawValue(dc, cx - 46, y, (w["t"] as Number).toFloat().format("%.0f") + "\u00B0", Graphics.COLOR_WHITE);
        dc.setColor(LIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 12, y - 8, Graphics.FONT_XTINY, "H " + (w["hi"] as Number).toFloat().format("%.0f"),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + 12, y + 9, Graphics.FONT_XTINY, "L " + (w["lo"] as Number).toFloat().format("%.0f"),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawValue(dc as Dc, x as Number, y as Number, s as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_TINY, s, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- Formatting -------------------------------------------------------

    private function ageText(age as Number) as String {
        if (age < 0) {
            return "--";
        }
        if (age < 3600) {
            return (age / 60) + "m";
        }
        if (age < 86400) {
            return (age / 3600) + "h";
        }
        if (age < 14 * 86400) {
            return (age / 86400) + "d";
        }
        return (age / (7 * 86400)) + "w";
    }

    // 1954 -> "1.9k", 640 -> "640"
    private function kilo(n as Number) as String {
        if (n < 1000) {
            return n.toString();
        }
        return (n / 1000.0).format("%.1f") + "k";
    }

    // 8214 -> "8214", 12345 -> "12.3k"
    private function compact(n as Number) as String {
        if (n < 10000) {
            return n.toString();
        }
        return (n / 1000.0).format("%.1f") + "k";
    }

    // Draw a clockwise arc between two clock angles (0 = 12 o'clock).
    private function arcClock(dc as Dc, cx as Number, cy as Number, r as Number,
                              a0 as Float or Number, a1 as Float or Number) as Void {
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, wrap(90.0 - a0), wrap(90.0 - a1));
    }

    private function wrap(deg as Float) as Number {
        var n = deg.toNumber() % 360;
        return n < 0 ? n + 360 : n;
    }

    // Scale a color toward black: f = 0 is black, f = 1 is the full color.
    private function mix(color as Number, f as Float) as Number {
        var r = (((color >> 16) & 0xFF) * f).toNumber();
        var g = (((color >> 8) & 0xFF) * f).toNumber();
        var b = ((color & 0xFF) * f).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    // --- Icons (all drawn with primitives, centered on x, y) ---------------

    // Icons use each sport's real colors; a sport never done is drawn all gray.
    private function drawSportIcon(dc as Dc, key as String, x as Number, y as Number, active as Boolean) as Void {
        dc.setPenWidth(2);
        if (key.equals("b")) { // orange ball, black seams
            dc.setColor(active ? 0xFF5500 : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 9);
            dc.setColor(active ? Graphics.COLOR_BLACK : 0x000000, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x - 9, y, x + 9, y);
            dc.drawLine(x, y - 9, x, y + 9);
            dc.drawArc(x - 12, y, 9, Graphics.ARC_CLOCKWISE, 50, 310);
            dc.drawArc(x + 12, y, 9, Graphics.ARC_CLOCKWISE, 230, 130);
        } else if (key.equals("g")) { // green, red flag on a pole
            dc.setColor(active ? 0x55AA00 : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - 4, y + 7, 3);
            dc.fillCircle(x + 5, y + 7, 3);
            dc.fillRectangle(x - 4, y + 4, 10, 6);
            dc.setColor(active ? Graphics.COLOR_BLACK : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - 1, y + 7, 2);
            dc.setColor(active ? 0xAAAAAA : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x - 1, y - 10, x - 1, y + 6);
            dc.setColor(active ? 0xFF0000 : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x, y - 10], [x + 9, y - 6], [x, y - 2]]);
        } else if (key.equals("m")) { // white shuttle, orange cork band
            dc.setColor(active ? Graphics.COLOR_WHITE : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x - 3, y + 2], [x + 4, y - 9], [x + 10, y - 3], [x - 1, y + 5]]);
            dc.fillCircle(x - 6, y + 6, 4);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(x, y - 1, x + 6, y - 7);
            dc.drawLine(x + 2, y + 1, x + 8, y - 5);
            dc.setColor(active ? 0xFFAA00 : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawLine(x - 4, y + 1, x + 1, y + 6);
        } else if (key.equals("c")) { // white climber on a wall
            dc.setColor(active ? 0xAAAAAA : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x + 7, y - 10, x + 7, y + 10);
            dc.drawLine(x - 2, y - 10, x + 7, y - 10);
            dc.setColor(active ? Graphics.COLOR_WHITE : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - 4, y - 5, 3);
            dc.drawLine(x - 4, y - 2, x - 2, y + 3);
            dc.drawLine(x - 4, y - 2, x + 3, y - 9);
            dc.drawLine(x - 2, y + 3, x + 5, y + 1);
            dc.drawLine(x - 2, y + 3, x - 5, y + 9);
        } else { // steel dumbbell
            dc.setColor(active ? Graphics.COLOR_WHITE : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x - 5, y - 2, 10, 4);
            dc.setColor(active ? 0x55AAAA : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x - 10, y - 7, 4, 14);
            dc.fillRectangle(x + 6, y - 7, 4, 14);
            dc.fillRectangle(x - 12, y - 4, 2, 8);
            dc.fillRectangle(x + 10, y - 4, 2, 8);
        }
        dc.setPenWidth(1);
    }

    private function drawHeart(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 3, y - 2, 4);
        dc.fillCircle(x + 3, y - 2, 4);
        dc.fillPolygon([[x - 7, y - 1], [x + 7, y - 1], [x, y + 7]]);
    }

    private function drawFootprints(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 3, y - 4, 3);
        dc.fillCircle(x - 3, y + 1, 2);
        dc.fillCircle(x + 4, y + 1, 3);
        dc.fillCircle(x + 4, y + 6, 2);
    }

    private function drawFlame(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 3, 5);
        dc.fillPolygon([[x - 5, y + 2], [x + 5, y + 2], [x + 1, y - 9]]);
        dc.setColor(YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + 4, 2);
    }

    // Icons by WMO-style weather code (see wmoCode).
    private function drawWeatherIcon(dc as Dc, x as Number, y as Number, code as Number, day as Boolean) as Void {
        if (code == 0 || code == 1) {
            if (day) {
                drawSun(dc, x, y, 6);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, 8);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x + 5, y - 3, 7);
            }
        } else if (code == 2) {
            drawSun(dc, x - 4, y - 5, 4);
            drawCloud(dc, x + 1, y + 2, Graphics.COLOR_WHITE);
        } else if (code == 45 || code == 48) {
            dc.setColor(LIGHT, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x - 9, y - 5, x + 9, y - 5);
            dc.drawLine(x - 9, y, x + 9, y);
            dc.drawLine(x - 9, y + 5, x + 9, y + 5);
            dc.setPenWidth(1);
        } else if (code >= 95) {
            drawCloud(dc, x, y - 3, LIGHT);
            dc.setColor(YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x + 1, y + 1], [x - 4, y + 8], [x, y + 8], [x - 2, y + 13], [x + 5, y + 5], [x + 1, y + 5]]);
        } else if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
            drawCloud(dc, x, y - 3, LIGHT);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x - 5, y + 8, 1);
            dc.fillCircle(x, y + 10, 1);
            dc.fillCircle(x + 5, y + 8, 1);
        } else if (code >= 51) {
            drawCloud(dc, x, y - 3, LIGHT);
            dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x - 5, y + 5, x - 7, y + 11);
            dc.drawLine(x, y + 5, x - 2, y + 11);
            dc.drawLine(x + 5, y + 5, x + 3, y + 11);
            dc.setPenWidth(1);
        } else { // overcast
            drawCloud(dc, x, y, LIGHT);
        }
    }

    private function drawSun(dc as Dc, x as Number, y as Number, r as Number) as Void {
        dc.setColor(YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        for (var a = 0; a < 360; a += 45) {
            var rad = a * 0.017453292;
            dc.drawLine(x + (r + 2) * Math.sin(rad), y - (r + 2) * Math.cos(rad),
                        x + (r + 5) * Math.sin(rad), y - (r + 5) * Math.cos(rad));
        }
    }

    private function drawCloud(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 5, y + 2, 5);
        dc.fillCircle(x + 1, y - 2, 6);
        dc.fillCircle(x + 7, y + 2, 4);
        dc.fillRectangle(x - 5, y + 2, 12, 5);
    }
}
