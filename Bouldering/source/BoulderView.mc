import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

function formatDuration(ms as Number) as String {
    var secs = ms / 1000;
    var h = secs / 3600;
    var m = (secs % 3600) / 60;
    var s = secs % 60;
    if (h > 0) {
        return h + ":" + m.format("%02d") + ":" + s.format("%02d");
    }
    return m + ":" + s.format("%02d");
}

// Main in-session screen: elapsed time, current problem grade and attempts,
// running totals, rest timer and heart rate.
class BoulderView extends WatchUi.View {

    private var _model as BoulderSession;
    private var _timer as Timer.Timer?;

    function initialize(model as BoulderSession) {
        View.initialize();
        _model = model;
    }

    function onShow() as Void {
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 1000, true);
        _timer = timer;
    }

    function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (!_model.isStarted()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.25, Graphics.FONT_MEDIUM, "Bouldering", center);
            dc.drawText(cx, h * 0.47, Graphics.FONT_LARGE, gradeLabel(_model.grade), center);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.62, Graphics.FONT_XTINY, "UP/DOWN: grade", center);
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.77, Graphics.FONT_SMALL, "START to begin", center);
            return;
        }

        var info = Activity.getActivityInfo();
        var timerTime = 0;
        var heartRate = null;
        if (info != null) {
            if (info.timerTime != null) {
                timerTime = info.timerTime;
            }
            heartRate = info.currentHeartRate;
        }

        // Elapsed time, or PAUSED
        if (_model.isRecording()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.13, Graphics.FONT_SMALL, formatDuration(timerTime), center);
        } else {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.13, Graphics.FONT_SMALL, "PAUSED", center);
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.27, Graphics.FONT_XTINY, "Problem " + (_model.problems + 1), center);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.44, Graphics.FONT_LARGE, gradeLabel(_model.grade), center);

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.60, Graphics.FONT_SMALL, "Attempts " + _model.attempts, center);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.74, Graphics.FONT_XTINY,
            "Sends " + _model.sends + "  Flash " + _model.flashes, center);

        var rest = formatDuration(System.getTimer() - _model.lastActionTime);
        var hr = heartRate != null ? heartRate.toString() : "--";
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, "Rest " + rest + "  HR " + hr, center);
    }
}

// Shown after saving
class SummaryView extends WatchUi.View {

    private var _model as BoulderSession;

    function initialize(model as BoulderSession) {
        View.initialize();
        _model = model;
    }

    function onUpdate(dc as Dc) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.18, Graphics.FONT_SMALL, "Saved", center);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.36, Graphics.FONT_SMALL, "Problems " + _model.problems, center);
        dc.drawText(cx, h * 0.50, Graphics.FONT_SMALL,
            "Sends " + _model.sends + "  Flash " + _model.flashes, center);
        dc.drawText(cx, h * 0.64, Graphics.FONT_SMALL, "Top " + gradeLabel(_model.topGrade), center);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY, "Attempts " + _model.totalAttempts, center);
    }
}
