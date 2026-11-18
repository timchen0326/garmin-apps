import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Runs in the background every 15 minutes: the last time per sport from the
// Strava relay. The background process only has 64 KB, so nothing big is kept
// around.
//
// Result keys: "s" {sport => start epoch}.
(:background)
class AthleteService extends System.ServiceDelegate {
    private var _result as Dictionary = {};

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        fetchSports();
    }

    // --- Sport history ----------------------------------------------------

    // A small relay (see relay/README.md) talks to Strava and answers with
    // {"b": epoch, "g": epoch, ...}: Connect IQ 3.0 can't parse Strava's
    // top-level JSON array, and the payload would not fit in background memory.
    private function fetchSports() as Void {
        if (Credentials.RELAY_URL.length() == 0) {
            Background.exit(_result);
            return;
        }
        Communications.makeWebRequest(
            Credentials.RELAY_URL,
            { "key" => Credentials.RELAY_KEY },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onSports)
        );
    }

    function onSports(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            _result["s"] = data;
        }
        Background.exit(_result);
    }
}
