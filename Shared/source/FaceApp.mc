import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Base app for the Heat and Rings faces: the background service caches sport
// history and calendar events in Storage, the face only ever reads the cache.
(:background)
class FaceApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    // First run: fetch right away instead of waiting a full interval.
    protected function scheduleFetch() as Void {
        if (Application.Storage.getValue("s") == null) {
            Background.registerForTemporalEvent(Time.now());
        } else {
            Background.registerForTemporalEvent(new Time.Duration(900));
        }
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new FaceService()];
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Dictionary) {
            var store = Application.Storage;
            var plain = ["d", "m", "a", "k", "e"];
            for (var i = 0; i < plain.size(); i++) {
                if (data.hasKey(plain[i])) {
                    store.setValue(plain[i], data[plain[i]]);
                }
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
