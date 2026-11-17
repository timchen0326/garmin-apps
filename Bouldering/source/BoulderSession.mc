import Toybox.ActivityRecording;
import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.WatchUi;

// FIT sport / sub-sport values. Garmin Connect shows sport 31 + sub-sport 69
// as a "Bouldering" activity.
const FIT_SPORT_CLIMBING = 31;
const FIT_SUB_SPORT_BOULDERING = 69;

// The S62 switches GPS on for any recorded activity, even if the app never
// asks for location, so the activity gets a map. Explicitly turn it off.
function disableGps() as Void {
    Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
}

// Owns the recording session. Heart rate and calories are recorded by the
// session itself; this only starts, pauses and saves it.
class BoulderSession {

    private var _session as ActivityRecording.Session?;

    // Captured just before saving, for the summary screen
    var totalTime as Number = 0;
    var avgHeartRate as Number? = null;
    var maxHeartRate as Number? = null;
    var calories as Number? = null;

    function initialize() {
        // Left over from versions that tracked V grades
        Application.Storage.deleteValue("grade");
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
            :name => "Bouldering",
            :sport => FIT_SPORT_CLIMBING as Activity.Sport,
            :subSport => FIT_SUB_SPORT_BOULDERING as Activity.SubSport
        });
        session.start();
        disableGps();
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
            disableGps();
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
