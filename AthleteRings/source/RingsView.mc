import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Rings from the outside in: steps, 24 h of heart rate (midnight at the top),
// calories, then one thin ring per sport filling with this week's minutes
// against your best recent week. Clock and weather sit in the middle.
class RingsView extends WatchFace {
    // Set to true to preview the layout with fake data (simulator screenshots).
    private const DEMO = false;
    private const HR_REFRESH = 300;
    private const CAL_GOAL = 2500;
    private const HR_INNER = 97;
    private const HR_DEPTH = 12;
    private const SPORT_OUTER = 81;
    private const SPORT_STEP = 4;

    private var _hr as Array<Number>? = null;
    private var _hrAt as Number = 0;

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var clock = System.getClockTime();
        var now = Time.now().value();

        Common.refreshLocation(now);
        refreshHeartRate(now);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawStepsRing(dc, cx, cy);
        drawHeartRateRing(dc, cx, cy);
        drawCaloriesRing(dc, cx, cy);
        drawSportRings(dc, cx, cy);
        drawCenter(dc, cx, cy, clock);
    }

    // --- Data -------------------------------------------------------------

    private function refreshHeartRate(now as Number) as Void {
        if (_hr != null && now - _hrAt < HR_REFRESH) {
            return;
        }
        _hrAt = now;
        if (DEMO) {
            var fake = new [48];
            for (var i = 0; i < 48; i++) {
                var v = (62 + 16 * Math.sin(i / 5.0) + (i * 7) % 13 + ((i > 30 && i < 38) ? 45 : 0)).toNumber();
                fake[i] = i < 21 ? v : -v;
            }
            _hr = fake as Array<Number>;
            return;
        }
        _hr = Common.heartRateBars(now, true);
    }

    // --- Rings ------------------------------------------------------------

    private function drawStepsRing(dc as Dc, cx as Number, cy as Number) as Void {
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var goal = info.stepGoal;
        if (DEMO) {
            steps = 8214;
            goal = 10000;
        }
        var frac = (steps != null && goal != null && goal > 0) ? steps.toFloat() / goal : 0.0;
        Common.progressArc(dc, cx, cy, 116, 6, 0, 360, frac, Common.STEPS);
    }

    // 48 half-hour bars around the ring, midnight at the top. Today is bright,
    // the part of the day that has not happened yet shows yesterday dimmed.
    private function drawHeartRateRing(dc as Dc, cx as Number, cy as Number) as Void {
        var hr = _hr as Array<Number>;
        dc.setPenWidth(3);
        for (var i = 0; i < 48; i++) {
            var v = hr[i];
            if (v == 0) {
                continue;
            }
            var fresh = v > 0;
            v = fresh ? v : -v;
            var depth = (v - Common.HR_LOW) * HR_DEPTH / (Common.HR_HIGH - Common.HR_LOW);
            depth = depth < 2 ? 2 : (depth > HR_DEPTH ? HR_DEPTH : depth);
            var a = (i * 7.5 + 3.75) * 0.017453292;
            var s = Math.sin(a);
            var c = Math.cos(a);
            dc.setColor(fresh ? Common.PINK : Common.mix(Common.PINK, 0.35), Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx + HR_INNER * s, cy - HR_INNER * c,
                        cx + (HR_INNER + depth) * s, cy - (HR_INNER + depth) * c);
        }
        dc.setPenWidth(1);
    }

    private function drawCaloriesRing(dc as Dc, cx as Number, cy as Number) as Void {
        var cals = ActivityMonitor.getInfo().calories;
        if (DEMO) {
            cals = 1954;
        }
        Common.progressArc(dc, cx, cy, 91, 3, 0, 360, cals != null ? cals.toFloat() / CAL_GOAL : 0.0, Common.ORANGE);
    }

    // One ring per sport, in SPORT_KEYS order from the outside in.
    private function drawSportRings(dc as Dc, cx as Number, cy as Number) as Void {
        var weeks = Application.Storage.getValue("m") as Dictionary?;
        if (DEMO) {
            weeks = { "b" => [95, 150], "g" => [60, 200], "m" => [110, 120], "c" => [0, 100], "w" => [150, 180] };
        }
        for (var i = 0; i < Common.SPORT_KEYS.size(); i++) {
            var key = Common.SPORT_KEYS[i];
            var frac = 0.0;
            if (weeks != null && weeks.hasKey(key)) {
                var pair = weeks[key] as Array<Number>;
                if (pair[1] > 0) {
                    frac = pair[0].toFloat() / pair[1];
                    // A session this week always shows at least a stub.
                    if (pair[0] > 0 && frac < 0.04) {
                        frac = 0.04;
                    }
                }
            }
            Common.progressArc(dc, cx, cy, SPORT_OUTER - i * SPORT_STEP, 3, 0, 360, frac, Common.SPORT_COLORS[i]);
        }
    }

    // --- Center -----------------------------------------------------------

    private function drawCenter(dc as Dc, cx as Number, cy as Number, clock as System.ClockTime) as Void {
        var info = ActivityMonitor.getInfo();
        var hr = Activity.getActivityInfo().currentHeartRate;
        var steps = info.steps;
        var cals = info.calories;
        var w = Application.Storage.getValue("w") as Dictionary?;
        if (DEMO) {
            hr = 72;
            steps = 8214;
            cals = 1954;
            w = { "t" => 17.6, "c" => 2, "d" => 1, "hi" => 21.0, "lo" => 11.0 };
        }

        Common.drawHeart(dc, cx - 14, cy - 42, Common.PINK);
        dc.setColor(Common.PINK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 4, cy - 42, Graphics.FONT_XTINY, hr != null ? hr.toString() : "--",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 8, Graphics.FONT_NUMBER_MEDIUM, Common.hourText(clock),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        Common.drawWeather(dc, cx, cy + 24, w, true);

        dc.setColor(Common.STEPS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 3, cy + 45, Graphics.FONT_XTINY, steps != null ? Common.compact(steps) : "--",
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Common.ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 3, cy + 45, Graphics.FONT_XTINY, cals != null ? Common.compact(cals) : "--",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
