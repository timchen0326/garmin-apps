import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

// Drawing and data helpers shared by the Heat and Rings watch faces.
module Common {
    const YELLOW = 0xFFFF55;
    const ORANGE = 0xFFAA00;
    const GRAY = 0x555555;
    const LIGHT = 0xAAAAAA;
    const STEPS = 0x55AAFF;
    const PINK = 0xFF0055;

    // basketball, golf, badminton, bouldering, workout (same keys as the relay)
    const SPORT_KEYS = ["b", "g", "m", "c", "w"] as Array<String>;
    const SPORT_COLORS = [0xFF5500, 0x55AA00, 0xFFFFFF, 0xAAAAAA, 0x55AAAA] as Array<Number>;

    const HR_SLOT = 1800; // seconds per bar: 48 bars cover 24 h
    const HR_LOW = 40;
    const HR_HIGH = 140;

    // --- Data -------------------------------------------------------------

    // The last 24 h of heart rate as 48 half-hour averages, oldest first, 0 where
    // there is no data. byClock = false: the last bar is "now". byClock = true:
    // bar n is the time of day n / 2 (midnight first); readings from yesterday
    // (the part of the day that has not happened yet) are stored negative.
    function heartRateBars(now as Number, byClock as Boolean) as Array<Number> {
        var sums = new [48];
        var counts = new [48];
        var out = new [48];
        for (var i = 0; i < 48; i++) {
            sums[i] = 0;
            counts[i] = 0;
            out[i] = 0;
        }
        if (!(SensorHistory has :getHeartRateHistory)) {
            return out as Array<Number>;
        }
        var it = SensorHistory.getHeartRateHistory({
            :period => new Time.Duration(86400),
            :order => SensorHistory.ORDER_OLDEST_FIRST
        });
        if (it == null) {
            return out as Array<Number>;
        }
        var clock = System.getClockTime();
        var offset = clock.timeZoneOffset + clock.dst;
        var today = (now + offset) / 86400;
        var yesterday = new [48];
        for (var i = 0; i < 48; i++) {
            yesterday[i] = false;
        }

        var s = it.next();
        while (s != null) {
            var bpm = s.data;
            if (bpm != null && bpm > 0) {
                var t = s.when.value();
                var idx = byClock ? (((t + offset) % 86400) / HR_SLOT) : (47 - (now - t) / HR_SLOT);
                if (idx >= 0 && idx < 48) {
                    if (byClock) {
                        // Oldest first, so today's readings replace yesterday's in a slot.
                        if ((t + offset) / 86400 != today) {
                            yesterday[idx] = true;
                        } else if (yesterday[idx]) {
                            yesterday[idx] = false;
                            sums[idx] = 0;
                            counts[idx] = 0;
                        }
                    }
                    sums[idx] += bpm;
                    counts[idx] += 1;
                }
            }
            s = it.next();
        }
        for (var i = 0; i < 48; i++) {
            if (counts[i] > 0) {
                var avg = sums[i] / counts[i];
                out[i] = yesterday[i] ? -avg : avg;
            }
        }
        return out as Array<Number>;
    }

    // The last span seconds of heart rate as n averages, oldest first, 0 where
    // there is no data. The last bar is "now".
    function recentHeartRate(now as Number, span as Number, n as Number) as Array<Number> {
        var sums = new [n];
        var counts = new [n];
        var out = new [n];
        for (var i = 0; i < n; i++) {
            sums[i] = 0;
            counts[i] = 0;
            out[i] = 0;
        }
        if (!(SensorHistory has :getHeartRateHistory)) {
            return out as Array<Number>;
        }
        var it = SensorHistory.getHeartRateHistory({
            :period => new Time.Duration(span),
            :order => SensorHistory.ORDER_OLDEST_FIRST
        });
        if (it == null) {
            return out as Array<Number>;
        }
        var slot = span / n;
        var s = it.next();
        while (s != null) {
            var bpm = s.data;
            if (bpm != null && bpm > 0) {
                var idx = (n - 1) - (now - s.when.value()) / slot;
                if (idx >= 0 && idx < n) {
                    sums[idx] += bpm;
                    counts[idx] += 1;
                }
            }
            s = it.next();
        }
        for (var i = 0; i < n; i++) {
            if (counts[i] > 0) {
                out[i] = sums[i] / counts[i];
            }
        }
        return out as Array<Number>;
    }

    // --- Drawing ----------------------------------------------------------

    // Draw a clockwise arc between two clock angles (0 = 12 o'clock).
    function arcClock(dc as Dc, cx as Number, cy as Number, r as Number,
                      a0 as Float or Number, a1 as Float or Number) as Void {
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, wrap(90.0 - a0), wrap(90.0 - a1));
    }

    function wrap(deg as Float) as Number {
        var n = deg.toNumber() % 360;
        return n < 0 ? n + 360 : n;
    }

    // A ring of width w filled clockwise from startDeg to startDeg + sweep * frac.
    function progressArc(dc as Dc, cx as Number, cy as Number, r as Number, w as Number,
                         startDeg as Number, sweep as Number, frac as Float, color as Number) as Void {
        if (frac > 1.0) {
            frac = 1.0;
        }
        dc.setPenWidth(w);
        dc.setColor(mix(color, 0.3), Graphics.COLOR_TRANSPARENT);
        arcClock(dc, cx, cy, r, startDeg, startDeg + sweep);
        if (frac > 0.01) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            arcClock(dc, cx, cy, r, startDeg, startDeg + sweep * frac);
        }
        dc.setPenWidth(1);
    }

    // Scale a color toward black: f = 0 is black, f = 1 is the full color.
    function mix(color as Number, f as Float) as Number {
        var r = (((color >> 16) & 0xFF) * f).toNumber();
        var g = (((color >> 8) & 0xFF) * f).toNumber();
        var b = ((color & 0xFF) * f).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    // 8214 -> "8214", 12345 -> "12.3k"
    function compact(n as Number) as String {
        if (n < 10000) {
            return n.toString();
        }
        return (n / 1000.0).format("%.1f") + "k";
    }

    function hourValue(clock as System.ClockTime) as Number {
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return hour;
    }

    function hourText(clock as System.ClockTime) as String {
        return hourValue(clock).format("%d") + ":" + clock.min.format("%02d");
    }

    function drawHeart(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 3, y - 2, 4);
        dc.fillCircle(x + 3, y - 2, 4);
        dc.fillPolygon([[x - 7, y - 1], [x + 7, y - 1], [x, y + 7]]);
    }

    // Battery as a curved gauge hugging the edge: a ring segment from a0 to a1 (clock
    // degrees, a0 the upper end) that fills from a1 upward, with a small nub past a0.
    function drawBatteryArc(dc as Dc, cx as Number, cy as Number, r as Number, w as Number,
                            a0 as Number, a1 as Number, pct as Float, color as Number) as Void {
        var frac = pct / 100.0;
        dc.setPenWidth(w);
        dc.setColor(mix(color, 0.3), Graphics.COLOR_TRANSPARENT);
        arcClock(dc, cx, cy, r, a0, a1);
        if (frac > 0.02) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            arcClock(dc, cx, cy, r, a1 - (a1 - a0) * frac, a1);
        }
        dc.setPenWidth(w / 2);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        arcClock(dc, cx, cy, r, a0 - 5, a0);
        dc.setPenWidth(1);
    }

    // Green, then orange and red as the charge runs down.
    function batteryColor(pct as Float) as Number {
        return pct > 30 ? 0x00FF55 : (pct > 15 ? ORANGE : 0xFF0000);
    }

    // The watch's current conditions in the shape drawWeather reads
    // (t, c = weather code for the icon, d = day, hi, lo); null if it has none.
    function garminWeather() as Dictionary? {
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
    function wmoCode(cond as Number?) as Number {
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

    // Icon, temperature and the day's high / low on one line, centered on cx.
    // compact drops the H / L letters so the row fits inside the Rings face.
    function drawWeather(dc as Dc, cx as Number, y as Number, w as Dictionary?, compact as Boolean) as Void {
        if (w == null) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY, "--", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var hi = (w["hi"] as Number).toFloat().format("%.0f");
        var lo = (w["lo"] as Number).toFloat().format("%.0f");
        drawWeatherIcon(dc, compact ? cx - 40 : cx - 58, y, w["c"] as Number, (w["d"] as Number) == 1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(compact ? cx - 26 : cx - 42, y, Graphics.FONT_TINY, (w["t"] as Number).toFloat().format("%.0f") + "\u00B0",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(LIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 12, y, Graphics.FONT_XTINY, compact ? hi + "/" + lo : "H" + hi + " L" + lo,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Icons by WMO-style weather code (see wmoCode).
    function drawWeatherIcon(dc as Dc, x as Number, y as Number, code as Number, day as Boolean) as Void {
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
            if (day) {
                drawSun(dc, x - 4, y - 5, 4);
            } else {
                drawMoon(dc, x - 4, y - 5, 5);
            }
            // A gray cloud at night so it stays distinct from the white moon.
            drawCloud(dc, x + 1, y + 2, day ? Graphics.COLOR_WHITE : LIGHT);
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

    // A crescent: a white disc with a black disc cut out of its upper right.
    function drawMoon(dc as Dc, x as Number, y as Number, r as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r * 0.6, y - r * 0.4, r * 0.85);
    }

    function drawSun(dc as Dc, x as Number, y as Number, r as Number) as Void {
        dc.setColor(YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        for (var a = 0; a < 360; a += 45) {
            var rad = a * 0.017453292;
            dc.drawLine(x + (r + 2) * Math.sin(rad), y - (r + 2) * Math.cos(rad),
                        x + (r + 5) * Math.sin(rad), y - (r + 5) * Math.cos(rad));
        }
    }

    function drawCloud(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 5, y + 2, 5);
        dc.fillCircle(x + 1, y - 2, 6);
        dc.fillCircle(x + 7, y + 2, 4);
        dc.fillRectangle(x - 5, y + 2, 12, 5);
    }
}
