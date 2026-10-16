import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;

// FIT sport / sub-sport values. Garmin Connect shows sport 31 + sub-sport 69
// as a "Bouldering" activity.
const FIT_SPORT_CLIMBING = 31;
const FIT_SUB_SPORT_BOULDERING = 69;

// V-scale bounds; -1 is displayed as "VB"
const GRADE_MIN = -1;
const GRADE_MAX = 17;
const NO_GRADE = -2;

// Developer field ids, must match resources/fitcontributions/fitcontributions.xml
const FIELD_PROBLEMS = 0;
const FIELD_SENDS = 1;
const FIELD_FLASHES = 2;
const FIELD_ATTEMPTS = 3;
const FIELD_TOP_GRADE = 4;
const FIELD_LAP_GRADE = 5;
const FIELD_LAP_ATTEMPTS = 6;
const FIELD_LAP_SENT = 7;

function gradeLabel(grade as Number) as String {
    if (grade == NO_GRADE) {
        return "--";
    }
    return grade < 0 ? "VB" : "V" + grade;
}

// Owns the recording session and the climbing stats for it.
// Each problem is written as a FIT lap with grade / attempts / sent fields.
class BoulderSession {

    private var _session as ActivityRecording.Session?;

    private var _problemsField;
    private var _sendsField;
    private var _flashesField;
    private var _attemptsField;
    private var _topGradeField;
    private var _lapGradeField;
    private var _lapAttemptsField;
    private var _lapSentField;

    var grade as Number = 3;
    var attempts as Number = 0;
    var problems as Number = 0;
    var sends as Number = 0;
    var flashes as Number = 0;
    var totalAttempts as Number = 0;
    var topGrade as Number = NO_GRADE;
    var lastActionTime as Number = 0;

    function initialize() {
        var saved = Application.Storage.getValue("grade");
        if (saved instanceof Number) {
            grade = saved;
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
            :name => "Bouldering",
            :sport => FIT_SPORT_CLIMBING as Activity.Sport,
            :subSport => FIT_SUB_SPORT_BOULDERING as Activity.SubSport
        });

        var summary = FitContributor.MESG_TYPE_SESSION;
        var lap = FitContributor.MESG_TYPE_LAP;
        _problemsField = session.createField("problems", FIELD_PROBLEMS, FitContributor.DATA_TYPE_UINT16, {:mesgType => summary});
        _sendsField = session.createField("sends", FIELD_SENDS, FitContributor.DATA_TYPE_UINT16, {:mesgType => summary});
        _flashesField = session.createField("flashes", FIELD_FLASHES, FitContributor.DATA_TYPE_UINT16, {:mesgType => summary});
        _attemptsField = session.createField("attempts", FIELD_ATTEMPTS, FitContributor.DATA_TYPE_UINT16, {:mesgType => summary});
        _topGradeField = session.createField("top_grade", FIELD_TOP_GRADE, FitContributor.DATA_TYPE_SINT8, {:mesgType => summary});
        _lapGradeField = session.createField("grade", FIELD_LAP_GRADE, FitContributor.DATA_TYPE_SINT8, {:mesgType => lap});
        _lapAttemptsField = session.createField("lap_attempts", FIELD_LAP_ATTEMPTS, FitContributor.DATA_TYPE_UINT8, {:mesgType => lap});
        _lapSentField = session.createField("sent", FIELD_LAP_SENT, FitContributor.DATA_TYPE_UINT8, {:mesgType => lap});

        _session = session;
        updateSessionFields();
        session.start();
        lastActionTime = System.getTimer();
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

    function changeGrade(delta as Number) as Void {
        var g = grade + delta;
        if (g < GRADE_MIN || g > GRADE_MAX) {
            return;
        }
        grade = g;
        Application.Storage.setValue("grade", grade);
    }

    // A failed attempt on the current problem
    function addFall() as Void {
        attempts += 1;
        totalAttempts += 1;
        lastActionTime = System.getTimer();
    }

    // Close the current problem as a lap. A send counts as one more attempt.
    function finishProblem(sent as Boolean) as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        if (sent) {
            attempts += 1;
            totalAttempts += 1;
        }
        lastActionTime = System.getTimer();
        if (attempts == 0) {
            return;
        }

        _lapGradeField.setData(grade);
        _lapAttemptsField.setData(attempts);
        _lapSentField.setData(sent ? 1 : 0);
        session.addLap();

        problems += 1;
        if (sent) {
            sends += 1;
            if (attempts == 1) {
                flashes += 1;
            }
            if (grade > topGrade) {
                topGrade = grade;
            }
        }
        attempts = 0;
        updateSessionFields();
    }

    function save() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        // Keep an unfinished problem that already has attempts
        if (attempts > 0) {
            finishProblem(false);
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

    private function updateSessionFields() as Void {
        _problemsField.setData(problems);
        _sendsField.setData(sends);
        _flashesField.setData(flashes);
        _attemptsField.setData(totalAttempts);
        // SINT8 has no "none" value; report 0 until something is sent
        _topGradeField.setData(topGrade == NO_GRADE ? 0 : topGrade);
    }
}
