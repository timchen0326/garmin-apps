import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Weather and Strava history are fetched by a background service every 15
// minutes and cached in Storage; the watch face only ever reads the cache.
(:background)
class AthleteApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        // First run: fetch right away instead of waiting a full interval.
        if (Application.Storage.getValue("w") == null) {
            Background.registerForTemporalEvent(Time.now());
        } else {
            Background.registerForTemporalEvent(new Time.Duration(900));
        }
        return [new AthleteView()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new AthleteService()];
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            var store = Application.Storage;
            if (data.hasKey("w")) {
                store.setValue("w", data["w"]);
            }
            if (data.hasKey("s")) {
                // Keep the newest timestamp per sport across fetches.
                var merged = store.getValue("s") as Dictionary?;
                if (merged == null) {
                    merged = {};
                }
                var fresh = data["s"] as Dictionary;
                var keys = fresh.keys();
                for (var i = 0; i < keys.size(); i++) {
                    var k = keys[i];
                    if (!merged.hasKey(k) || fresh[k] > merged[k]) {
                        merged[k] = fresh[k];
                    }
                }
                store.setValue("s", merged);
            }
        }
        Background.registerForTemporalEvent(new Time.Duration(900));
        WatchUi.requestUpdate();
    }
}
