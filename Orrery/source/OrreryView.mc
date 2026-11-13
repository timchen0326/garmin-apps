import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// A clock as a tiny solar system. The hour is a planet on the outer orbit,
// the minute is a planet on the inner orbit, and the seconds are a moon
// orbiting the minute planet. Colors follow the sun through the day, the
// bezel fills with your steps, and the moon glyph shows the real lunar phase.
// Raise your wrist and everything spins in from the center.
class OrreryView extends WatchFace {
    private const DEG = 0.017453292;
    private const HOUR_ORBIT = 104;
    private const MIN_ORBIT = 80;
    private const MOON_ORBIT = 15;
    private const SYNODIC = 2551442.8;
    private const NEW_MOON_EPOCH = 947182440; // 2000-01-06 18:14 UTC
    private const ANIM_STEP = 0.045;

    private var _stars as Array<Number> = [] as Array<Number>;
    private var _timer as Timer.Timer?;
    private var _anim as Float = 1.0;
    private var _awake as Boolean = true;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        // Deterministic starfield (x, y, brightness) so it never shifts.
        var seed = 20260;
        var w = dc.getWidth();
        var h = dc.getHeight();
        var stars = [] as Array<Number>;
        while (stars.size() < 120) {
            seed = (seed * 1103 + 12345) % 65521;
            var x = seed % w;
            seed = (seed * 1103 + 12345) % 65521;
            var y = seed % h;
            seed = (seed * 1103 + 12345) % 65521;
            var dx = x - w / 2;
            var dy = y - h / 2;
            if (dx * dx + dy * dy < 118 * 118) {
                stars.add(x);
                stars.add(y);
                stars.add(seed % 3);
            }
        }
        _stars = stars;
    }

    function onShow() as Void {
        startAnimation();
    }

    function onHide() as Void {
        stopTimer();
    }

    function onExitSleep() as Void {
        _awake = true;
        startAnimation();
    }

    function onEnterSleep() as Void {
        _awake = false;
        stopTimer();
        _anim = 1.0;
        WatchUi.requestUpdate();
    }

    private function startAnimation() as Void {
        _anim = 0.0;
        stopTimer();
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:onTick), 70, true);
    }

    private function stopTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        _anim += ANIM_STEP;
        if (_anim >= 1.0) {
            _anim = 1.0;
            stopTimer();
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var cx = w / 2;
        var cy = dc.getHeight() / 2;
        var clock = System.getClockTime();
        var t = _anim;
        var ease = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
        var accent = sunColor(clock.hour + clock.min / 60.0);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawStars(dc, clock.sec);
        drawBezel(dc, cx, cy, clock.hour);
        drawOrbitDots(dc, cx, cy, (HOUR_ORBIT * ease).toNumber(), 4, 0x555555);
        drawOrbitDots(dc, cx, cy, (MIN_ORBIT * ease).toNumber(), 5, 0x555555);

        // Planets spin in from the center on wake: extra rotation fades to 0.
        var spin = (1.0 - ease) * -540.0;

        // Hour planet and its comet trail.
        var hourAngle = ((clock.hour % 12) + clock.min / 60.0) * 30.0 + spin;
        var hr = HOUR_ORBIT * ease;
        drawTrail(dc, cx, cy, hr, hourAngle, 70.0 * ease, accent);
        var hx = cx + hr * Math.sin(hourAngle * DEG);
        var hy = cy - hr * Math.cos(hourAngle * DEG);
        drawPlanet(dc, hx.toNumber(), hy.toNumber(), 8, accent);

        // Minute planet and its trail.
        var minAngle = (clock.min + (_awake ? clock.sec / 60.0 : 0.0)) * 6.0 + spin * 1.5;
        var mr = MIN_ORBIT * ease;
        drawTrail(dc, cx, cy, mr, minAngle, 60.0 * ease, 0x55FFFF);
        var mx = (cx + mr * Math.sin(minAngle * DEG)).toNumber();
        var my = (cy - mr * Math.cos(minAngle * DEG)).toNumber();
        drawPlanet(dc, mx, my, 5, 0x55FFFF);

        // Seconds moon, only while the watch is awake (low power ticks once a minute).
        if (_awake) {
            drawOrbitDots(dc, mx, my, MOON_ORBIT, 24, 0x555555);
            var moonAngle = clock.sec * 6.0 + spin * 2.0;
            var sx = mx + MOON_ORBIT * Math.sin(moonAngle * DEG);
            var sy = my - MOON_ORBIT * Math.cos(moonAngle * DEG);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(sx.toNumber(), sy.toNumber(), 2);
        }

        drawReadout(dc, cx, cy, clock, accent);

        if (t < 1.0) {
            drawShootingStar(dc, w, t);
        }
    }

    // --- Pieces -----------------------------------------------------------

    private function drawStars(dc as Dc, sec as Number) as Void {
        var palette = [0x555555, 0xAAAAAA, 0xFFFFFF] as Array<Number>;
        for (var i = 0; i < _stars.size(); i += 3) {
            var level = _stars[i + 2];
            if (_awake && ((i / 3) + sec) % 9 == 0 && level > 0) {
                level -= 1; // twinkle
            }
            dc.setColor(palette[level], Graphics.COLOR_TRANSPARENT);
            dc.drawPoint(_stars[i], _stars[i + 1]);
            if (_stars[i + 2] == 2) {
                dc.drawPoint(_stars[i] + 1, _stars[i + 1]);
            }
        }
    }

    private function drawBezel(dc as Dc, cx as Number, cy as Number, hour as Number) as Void {
        // Steps ring, filling clockwise from 12 o'clock.
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var goal = info.stepGoal;
        if (steps != null && goal != null && goal > 0) {
            var frac = steps.toFloat() / goal;
            dc.setPenWidth(4);
            dc.setColor(0x005500, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, 127);
            dc.setColor(frac >= 1.0 ? 0x00FF55 : 0x00FFAA, Graphics.COLOR_TRANSPARENT);
            if (frac >= 1.0) {
                dc.drawCircle(cx, cy, 127);
            } else if (frac > 0.01) {
                dc.drawArc(cx, cy, 127, Graphics.ARC_CLOCKWISE, 90, 90 - frac * 360.0);
            }
        }

        // Hour ticks; the current hour glows.
        for (var i = 0; i < 12; i++) {
            var a = i * 30 * DEG;
            var current = (i == hour % 12);
            dc.setPenWidth(current ? 3 : 2);
            dc.setColor(current ? 0xFFFFFF : 0x555555, Graphics.COLOR_TRANSPARENT);
            var r1 = current ? 114 : 117;
            dc.drawLine(cx + r1 * Math.sin(a), cy - r1 * Math.cos(a),
                        cx + 122 * Math.sin(a), cy - 122 * Math.cos(a));
        }
        dc.setPenWidth(1);
    }

    private function drawOrbitDots(dc as Dc, cx as Number, cy as Number, r as Number,
                                   stepDeg as Number, color as Number) as Void {
        if (r < 3) {
            return;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var a = 0; a < 360; a += stepDeg) {
            dc.drawPoint(cx + r * Math.sin(a * DEG), cy - r * Math.cos(a * DEG));
        }
    }

    // A comet tail: arc segments fading to black behind the planet.
    private function drawTrail(dc as Dc, cx as Number, cy as Number, r as Float,
                               angle as Float, span as Float, color as Number) as Void {
        if (r < 3 || span < 1.0) {
            return;
        }
        var segs = 7;
        var seg = span / segs;
        for (var i = 0; i < segs; i++) {
            var f = (i + 1.0) / segs;
            dc.setPenWidth(i < 3 ? 2 : 3);
            dc.setColor(mix(color, f * f), Graphics.COLOR_TRANSPARENT);
            var start = angle - span + i * seg;
            dc.drawArc(cx, cy, r.toNumber(), Graphics.ARC_CLOCKWISE,
                       wrap(90.0 - start), wrap(90.0 - (start + seg)));
        }
        dc.setPenWidth(1);
    }

    private function drawPlanet(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r + 2);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - r / 3, y - r / 3, r / 4 + 1);
    }

    private function drawReadout(dc as Dc, cx as Number, cy as Number, clock as System.ClockTime, accent as Number) as Void {
        // Moon phase above the time.
        var phase = moonPhase();
        drawMoon(dc, cx, cy - 50, 8, phase);

        // Time.
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        var timeStr = hour.format("%d") + ":" + clock.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 5, Graphics.FONT_NUMBER_MEDIUM, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Date.
        var d = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = (d.day_of_week as String).toUpper() + " " + d.day + " " + (d.month as String).toUpper();
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 27, Graphics.FONT_XTINY, dateStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Heart rate and battery.
        var hrVal = Activity.getActivityInfo().currentHeartRate;
        var bat = System.getSystemStats().battery;
        var hrStr = hrVal != null ? hrVal.toString() : "--";
        drawHeart(dc, cx - 38, cy + 48, 0xFF0055);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 28, cy + 48, Graphics.FONT_XTINY, hrStr,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(bat > 30 ? 0x00FF55 : (bat > 15 ? 0xFFAA00 : 0xFF0000), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 40, cy + 48, Graphics.FONT_XTINY, bat.toNumber() + "%",
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawHeart(dc as Dc, x as Number, y as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 2, y - 1, 3);
        dc.fillCircle(x + 2, y - 1, 3);
        dc.fillPolygon([[x - 5, y], [x + 5, y], [x, y + 6]]);
    }

    private function drawMoon(dc as Dc, cx as Number, cy as Number, r as Number, p as Float) as Void {
        dc.setColor(0x000055, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        dc.setColor(0xFFFFAA, Graphics.COLOR_TRANSPARENT);
        var c = Math.cos(p * 2.0 * Math.PI);
        for (var dy = -r; dy <= r; dy++) {
            var half = Math.sqrt(r * r - dy * dy);
            var xt = half * c;
            var x0 = p < 0.5 ? xt : -half;
            var x1 = p < 0.5 ? half : -xt;
            if (x1 - x0 >= 1.0) {
                dc.drawLine(cx + x0.toNumber(), cy + dy, cx + x1.toNumber(), cy + dy);
            }
        }
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
    }

    private function drawShootingStar(dc as Dc, w as Number, t as Float) as Void {
        var x = 20 + t * (w - 40);
        var y = 30 + t * 120;
        for (var i = 0; i < 6; i++) {
            dc.setColor(mix(0xFFFFFF, 1.0 - i / 6.0), Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x - i * 7, y - i * 3.5, x - (i + 1) * 7, y - (i + 1) * 3.5);
        }
    }

    // --- Math helpers -----------------------------------------------------

    private function moonPhase() as Float {
        var cycles = (Time.now().value() - NEW_MOON_EPOCH).toFloat() / SYNODIC;
        return cycles - cycles.toNumber();
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

    // The accent color follows the sun: night blue, dawn orange, noon yellow, dusk pink.
    private function sunColor(hour as Float) as Number {
        var stops = [0.0, 5.0, 7.0, 12.0, 17.0, 19.0, 21.0, 24.0] as Array<Float>;
        var colors = [0x5555FF, 0x5555FF, 0xFF5500, 0xFFFF55, 0xFFAA00, 0xFF55AA, 0x5555FF, 0x5555FF] as Array<Number>;
        for (var i = 1; i < stops.size(); i++) {
            if (hour <= stops[i]) {
                var f = (hour - stops[i - 1]) / (stops[i] - stops[i - 1]);
                return blend(colors[i - 1], colors[i], f);
            }
        }
        return colors[colors.size() - 1];
    }

    private function blend(a as Number, b as Number, f as Float) as Number {
        var r = lerp((a >> 16) & 0xFF, (b >> 16) & 0xFF, f);
        var g = lerp((a >> 8) & 0xFF, (b >> 8) & 0xFF, f);
        var bl = lerp(a & 0xFF, b & 0xFF, f);
        return (r << 16) | (g << 8) | bl;
    }

    private function lerp(a as Number, b as Number, f as Float) as Number {
        return (a + (b - a) * f).toNumber();
    }
}
