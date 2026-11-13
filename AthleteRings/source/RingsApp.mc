import Toybox.Lang;
import Toybox.WatchUi;

(:background)
class RingsApp extends FaceApp {
    function initialize() {
        FaceApp.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        scheduleFetch();
        return [new RingsView()];
    }
}
