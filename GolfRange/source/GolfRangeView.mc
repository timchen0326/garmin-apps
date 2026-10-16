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

// Main screen: elapsed time, swing count (large), heart rate, calories
class GolfRangeView extends WatchUi.View {

    private var _model as GolfRangeSession;
    private var _timer as Timer.Timer?;

    function initialize(model as GolfRangeSession) {
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
        var sensitivity = SENSITIVITY_LABELS[_model.sensitivity] as String;

        if (!_model.isStarted()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.26, Graphics.FONT_MEDIUM, "Golf Range", center);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.44, Graphics.FONT_XTINY, "Auto count: " + sensitivity, center);
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.56, Graphics.FONT_SMALL, "HR " + valueOrDash(heartRate), center);
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.74, Graphics.FONT_SMALL, "START to begin", center);
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
            dc.drawText(cx, h * 0.16, Graphics.FONT_SMALL, formatDuration(timerTime), center);
        } else {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.16, Graphics.FONT_SMALL, "PAUSED", center);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.42, Graphics.FONT_NUMBER_HOT, _model.swings.toString(), center);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.59, Graphics.FONT_XTINY, "swings  (auto: " + sensitivity + ")", center);

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.73, Graphics.FONT_SMALL, "HR " + valueOrDash(heartRate), center);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, valueOrDash(calories) + " kcal", center);
    }
}

// Shown after saving
class SummaryView extends WatchUi.View {

    private var _model as GolfRangeSession;

    function initialize(model as GolfRangeSession) {
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
        dc.drawText(cx, h * 0.16, Graphics.FONT_SMALL, "Saved", center);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.32, Graphics.FONT_SMALL, _model.swings + " swings", center);
        dc.drawText(cx, h * 0.46, Graphics.FONT_SMALL, formatDuration(_model.totalTime), center);
        dc.drawText(cx, h * 0.60, Graphics.FONT_SMALL,
            "HR " + valueOrDash(_model.avgHeartRate) + " / " + valueOrDash(_model.maxHeartRate), center);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.70, Graphics.FONT_XTINY, "avg / max", center);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.83, Graphics.FONT_SMALL, valueOrDash(_model.calories) + " kcal", center);
    }
}
