import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
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

function valueOrDash(value as Number?) as String {
    return value != null ? value.toString() : "--";
}

// Main screen: elapsed time, heart rate (large), calories
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
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var info = Activity.getActivityInfo();
        var heartRate = info != null ? info.currentHeartRate : null;

        if (!_model.isStarted()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.28, Graphics.FONT_MEDIUM, "Bouldering", center);
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.48, Graphics.FONT_SMALL, "HR " + valueOrDash(heartRate), center);
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.70, Graphics.FONT_SMALL, "START to begin", center);
            return;
        }

        var timerTime = 0;
        var calories = null;
        if (info != null) {
            if (info.timerTime != null) {
                timerTime = info.timerTime;
            }
            calories = info.calories;
        }

        if (_model.isRecording()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.20, Graphics.FONT_MEDIUM, formatDuration(timerTime), center);
        } else {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.20, Graphics.FONT_MEDIUM, "PAUSED", center);
        }

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.47, Graphics.FONT_NUMBER_HOT, valueOrDash(heartRate), center);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.64, Graphics.FONT_XTINY, "bpm", center);

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.80, Graphics.FONT_SMALL, valueOrDash(calories) + " kcal", center);
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
        dc.drawText(cx, h * 0.36, Graphics.FONT_SMALL, formatDuration(_model.totalTime), center);
        dc.drawText(cx, h * 0.50, Graphics.FONT_SMALL, "Avg HR " + valueOrDash(_model.avgHeartRate), center);
        dc.drawText(cx, h * 0.64, Graphics.FONT_SMALL, "Max HR " + valueOrDash(_model.maxHeartRate), center);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.80, Graphics.FONT_SMALL, valueOrDash(_model.calories) + " kcal", center);
    }
}
