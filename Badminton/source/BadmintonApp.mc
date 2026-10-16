import Toybox.ActivityRecording;
import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.WatchUi;

// FIT sport / sub-sport values. Garmin Connect shows sport 64 + sub-sport 95
// as a "Badminton" activity.
const FIT_SPORT_RACKET = 64;
const FIT_SUB_SPORT_BADMINTON = 95;

class BadmintonApp extends Application.AppBase {

    private var _model as BadmintonSession;

    function initialize() {
        AppBase.initialize();
        _model = new BadmintonSession();
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
        return [new BadmintonView(_model), new BadmintonDelegate(_model)];
    }
}

// Owns the recording session. Heart rate and calories are recorded by the
// session itself; this only starts, pauses and saves it.
class BadmintonSession {

    private var _session as ActivityRecording.Session?;

    // Captured just before saving, for the summary screen
    var totalTime as Number = 0;
    var avgHeartRate as Number? = null;
    var maxHeartRate as Number? = null;
    var calories as Number? = null;

    function initialize() {
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
            :name => "Badminton",
            :sport => FIT_SPORT_RACKET as Activity.Sport,
            :subSport => FIT_SUB_SPORT_BADMINTON as Activity.SubSport
        });
        session.start();
        _session = session;
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
        }
    }

    function save() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
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
        if (session.isRecording()) {
            session.stop();
        }
        session.discard();
        _session = null;
    }
}
