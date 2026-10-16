import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

function buzz(ms as Number) as Void {
    if (Attention has :vibrate) {
        Attention.vibrate([new Attention.VibeProfile(50, ms)]);
    }
}

// Buttons on the main screen:
//   START   start session / pause and open the menu
//   BACK    add a swing by hand; exits only before the session starts
//   MENU    (hold UP) before starting: set auto-count sensitivity
class GolfRangeDelegate extends WatchUi.BehaviorDelegate {

    private var _model as GolfRangeSession;

    function initialize(model as GolfRangeSession) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    function onSelect() as Boolean {
        if (!_model.isStarted()) {
            _model.start();
            buzz(300);
        } else {
            _model.pause();
            buzz(100);
            pushEndMenu(_model);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() as Boolean {
        if (!_model.isStarted()) {
            pushSensitivityMenu(_model);
        }
        return true;
    }

    function onBack() as Boolean {
        if (!_model.isStarted()) {
            return false;
        }
        if (_model.isRecording()) {
            _model.addSwing();
            buzz(60);
        } else {
            pushEndMenu(_model);
        }
        WatchUi.requestUpdate();
        return true;
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        System.exit();
    }

    function onBack() as Boolean {
        System.exit();
    }
}
