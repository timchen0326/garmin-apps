import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.WatchUi;

// FIT sport value; Garmin Connect shows sport 25 as "Golf"
const FIT_SPORT_GOLF = 25;

// The S62 switches GPS on for any recorded activity, even if the app never
// asks for location, so the activity gets a map. Explicitly turn it off.
function disableGps() as Void {
    Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
}

// Developer field id, must match resources/fitcontributions/fitcontributions.xml
const FIELD_SWINGS = 0;

// Swing detection: a swing is any accelerometer sample above the threshold,
// with a lockout afterwards so one swing (and its follow-through) counts once.
// Thresholds are in milli-g, indexed by sensitivity (0 = Off).
const SENSITIVITY_LABELS = ["Off", "Low", "Medium", "High"];
const SWING_THRESHOLDS = [0, 5000, 3500, 2500];
const SWING_LOCKOUT_MS = 2500;
const SAMPLE_RATE = 25;

class GolfRangeApp extends Application.AppBase {

    private var _model as GolfRangeSession;

    function initialize() {
        AppBase.initialize();
        _model = new GolfRangeSession();
    }

    function onStart(state as Dictionary?) as Void {
    }

    // If the app is closed mid-session (e.g. low battery), keep the data
    function onStop(state as Dictionary?) as Void {
        if (_model.isStarted()) {
            _model.save();
        }
    }

    function getInitialView() {
        return [new GolfRangeView(_model), new GolfRangeDelegate(_model)];
    }
}

// Owns the recording session and the swing count. Heart rate and calories
// are recorded by the session itself.
class GolfRangeSession {

    private var _session as ActivityRecording.Session?;
    private var _swingsField;
    private var _lastSwingTime as Number = 0;

    var swings as Number = 0;
    var sensitivity as Number = 2;

    // Captured just before saving, for the summary screen
    var totalTime as Number = 0;
    var avgHeartRate as Number? = null;
    var maxHeartRate as Number? = null;
    var calories as Number? = null;

    function initialize() {
        var saved = Application.Storage.getValue("sensitivity");
        if (saved instanceof Number && saved >= 0 && saved < SWING_THRESHOLDS.size()) {
            sensitivity = saved;
        }
    }

    function isStarted() as Boolean {
        return _session != null;
    }

    function isRecording() as Boolean {
        var session = _session;
        return session != null && session.isRecording();
    }

    function start() as Void {
        if (_session != null) {
            return;
        }
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        var session = ActivityRecording.createSession({
            :name => "Golf Range",
            :sport => FIT_SPORT_GOLF as Activity.Sport
        });
        _swingsField = session.createField("swings", FIELD_SWINGS, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _swingsField.setData(0);
        session.start();
        disableGps();
        _session = session;

        Sensor.registerSensorDataListener(method(:onSensorData), {
            :period => 1,
            :accelerometer => {:enabled => true, :sampleRate => SAMPLE_RATE}
        });
    }

    function pause() as Void {
        var session = _session;
        if (session != null && session.isRecording()) {
            session.stop();
        }
    }

    function resume() as Void {
        var session = _session;
        if (session != null && !session.isRecording()) {
            session.start();
            disableGps();
        }
    }

    function addSwing() as Void {
        swings += 1;
        _swingsField.setData(swings);
    }

    function undoSwing() as Void {
        if (swings > 0) {
            swings -= 1;
            _swingsField.setData(swings);
        }
    }

    function setSensitivity(value as Number) as Void {
        sensitivity = value;
        Application.Storage.setValue("sensitivity", value);
    }

    // Called once a second with the last second of accelerometer samples
    function onSensorData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (accel == null || !isRecording() || sensitivity == 0) {
            return;
        }
        var now = System.getTimer();
        if (now - _lastSwingTime < SWING_LOCKOUT_MS) {
            return;
        }
        var threshold = SWING_THRESHOLDS[sensitivity] as Number;
        var limit = threshold * threshold;
        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        for (var i = 0; i < xs.size(); i++) {
            var x = xs[i];
            var y = ys[i];
            var z = zs[i];
            if (x * x + y * y + z * z > limit) {
                _lastSwingTime = now;
                addSwing();
                buzz(60);
                WatchUi.requestUpdate();
                return;
            }
        }
    }

    function save() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        Sensor.unregisterSensorDataListener();
        var info = Activity.getActivityInfo();
        if (info != null) {
            totalTime = info.timerTime != null ? info.timerTime : 0;
            avgHeartRate = info.averageHeartRate;
            maxHeartRate = info.maxHeartRate;
            calories = info.calories;
        }
        if (session.isRecording()) {
            session.stop();
        }
        session.save();
        _session = null;
    }

    function discard() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        Sensor.unregisterSensorDataListener();
        if (session.isRecording()) {
            session.stop();
        }
        session.discard();
        _session = null;
    }
}
