import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Heart rate for the last 24 h drawn behind a big clock, steps and calories as
// arcs along the top, weather under them, and a 28-day heatmap of your sports.
class HeatView extends WatchFace {
    // Set to true to preview the layout with fake data (simulator screenshots).
    private const DEMO = false;
    private const HR_REFRESH = 300;
    private const CLOCK_Y = 112;
    private const CAL_GOAL = 2500;
    private const CHART_BASE = 148;
    private const CHART_HEIGHT = 52;
    private const HEAT_TOP = 160;
    private const HEAT_ROW = 9;
    private const HEAT_X = 50;
    private const HEAT_CELL = 5.4;

    private var _hr as Array<Number>? = null;
    private var _hrAt as Number = 0;

    function initialize() {
        WatchFace.initialize();
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
        drawTopArcs(dc, cx);
        drawWeather(dc, cx);
        drawClock(dc, cx, clock);
        drawBattery(dc);
        drawHeartRate(dc);
        drawHeatmap(dc, cx);
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
                fake[i] = (62 + 16 * Math.sin(i / 5.0) + (i * 7) % 13 + ((i > 30 && i < 38) ? 45 : 0)).toNumber();
            }
            _hr = fake as Array<Number>;
            return;
        }
        _hr = Common.heartRateBars(now, false);
    }

    // --- Sections ---------------------------------------------------------

    // 24 h of heart rate as bars with a line along the top; the right edge is now.
    private function drawHeartRateChart(dc as Dc) as Void {
        var hr = _hr as Array<Number>;
        var bw = 5;
        var prevX = -1;
        var prevY = 0;
        for (var i = 0; i < 48; i++) {
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

    // Steps on the outer arc, calories just inside it.
    private function drawTopArcs(dc as Dc, cx as Number) as Void {
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var goal = info.stepGoal;
        var cals = info.calories;
        if (DEMO) {
            steps = 8214;
            goal = 10000;
            cals = 1954;
        }
        var stepFrac = (steps != null && goal != null && goal > 0) ? steps.toFloat() / goal : 0.0;
        var calFrac = cals != null ? cals.toFloat() / CAL_GOAL : 0.0;
        Common.progressArc(dc, cx, cx, 114, 6, -60, 120, stepFrac, Common.STEPS);
        Common.progressArc(dc, cx, cx, 105, 4, -48, 96, calFrac, Common.ORANGE);

        dc.setColor(Common.STEPS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 5, 41, Graphics.FONT_XTINY, steps != null ? Common.compact(steps) : "--",
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Common.ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 5, 41, Graphics.FONT_XTINY, cals != null ? Common.compact(cals) : "--",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
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
        dc.drawText(cx, CLOCK_Y, Graphics.FONT_NUMBER_HOT, Common.hourText(clock),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Curved battery gauge along the right edge of the screen.
    private function drawBattery(dc as Dc) as Void {
        var bat = System.getSystemStats().battery;
        if (DEMO) {
            bat = 84.0;
        }
        Common.drawBatteryArc(dc, 120, 120, 113, 7, 74, 112, bat, Common.batteryColor(bat));
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

    // One row per sport, one cell per day: the right edge is the last 24 h.
    private function drawHeatmap(dc as Dc, cx as Number) as Void {
        var masks = Application.Storage.getValue("d") as Dictionary?;
        if (DEMO) {
            masks = { "b" => 0x0A4A1B2, "g" => 0x0040820, "m" => 0x0102412, "c" => 0x0020841, "w" => 0x0B52A4B };
        }
        var total = 0;
        for (var i = 0; i < Common.SPORT_KEYS.size(); i++) {
            var color = Common.SPORT_COLORS[i];
            var mask = (masks != null && masks.hasKey(Common.SPORT_KEYS[i])) ? masks[Common.SPORT_KEYS[i]] as Number : 0;
            var y = HEAT_TOP + i * HEAT_ROW;
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(HEAT_X - 9, y + 3, 3);
            for (var j = 0; j < 28; j++) {
                var on = ((mask >> (27 - j)) & 1) == 1;
                if (on) {
                    total++;
                }
                dc.setColor(on ? color : 0x2A2A2A, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(HEAT_X + (j * HEAT_CELL).toNumber(), y, 4, 7);
            }
        }
        dc.setColor(Common.LIGHT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 216, Graphics.FONT_XTINY, masks != null ? total + " sessions / 28d" : "--",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
