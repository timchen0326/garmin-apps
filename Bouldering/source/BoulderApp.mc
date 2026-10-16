import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BoulderApp extends Application.AppBase {

    private var _model as BoulderSession;

    function initialize() {
        AppBase.initialize();
        _model = new BoulderSession();
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
        return [new BoulderView(_model), new BoulderDelegate(_model)];
    }
}
