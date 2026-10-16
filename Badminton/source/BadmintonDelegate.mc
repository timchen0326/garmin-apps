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
//   START   start session / pause and open the Resume / Save / Discard menu
//   BACK    exits only before the session starts; ignored while recording
class BadmintonDelegate extends WatchUi.BehaviorDelegate {

    private var _model as BadmintonSession;

    function initialize(model as BadmintonSession) {
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

    function onBack() as Boolean {
        if (!_model.isStarted()) {
            return false;
        }
        if (!_model.isRecording()) {
            pushEndMenu(_model);
        }
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
