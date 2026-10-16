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
//   START   start session / open problem menu
//   BACK    log a fall (+1 attempt); exits only before the session starts
//   UP/DOWN change grade
//   MENU    (hold UP) open problem menu
class BoulderDelegate extends WatchUi.BehaviorDelegate {

    private var _model as BoulderSession;

    function initialize(model as BoulderSession) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    function onSelect() as Boolean {
        if (!_model.isStarted()) {
            _model.start();
            buzz(300);
        } else {
            pushActionMenu(_model);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() as Boolean {
        if (_model.isStarted()) {
            pushActionMenu(_model);
        }
        return true;
    }

    function onBack() as Boolean {
        if (!_model.isStarted()) {
            return false;
        }
        if (_model.isRecording()) {
            _model.addFall();
            buzz(100);
        } else {
            pushActionMenu(_model);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _model.changeGrade(-1);
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        _model.changeGrade(1);
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
