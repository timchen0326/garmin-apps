import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Runs in the background every 15 minutes: sport history and calendar events
// from the Strava relay (see Athlete/relay). Weather is not fetched here; the
// faces read it from the watch (Weather.getCurrentConditions).
// The background process only has 64 KB, so nothing big is kept around.
//
// Result keys: "s" {sport => last start epoch},
// "d" {sport => bitmask of days with a session}, "m" {sport => [week min, best week min]},
// "a" [code, start epoch, minutes, label] newest activity, "k" 7 day codes,
// "e" [[start epoch, end epoch, title], ...] next calendar events (HeatLite).
(:background)
class FaceService extends System.ServiceDelegate {
    private var _result as Dictionary = {};

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        if (Credentials.RELAY_URL.length() == 0) {
            Background.exit(_result);
            return;
        }
        Communications.makeWebRequest(
            Credentials.RELAY_URL,
            { "key" => Credentials.RELAY_KEY, "x" => "2" },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onSports)
        );
    }

    function onSports(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            if (data.hasKey("d")) {
                _result["d"] = data["d"];
                data.remove("d");
            }
            if (data.hasKey("m")) {
                _result["m"] = data["m"];
                data.remove("m");
            }
            if (data.hasKey("a")) {
                _result["a"] = data["a"];
                data.remove("a");
            }
            if (data.hasKey("k")) {
                _result["k"] = data["k"];
                data.remove("k");
            }
            if (data.hasKey("e")) {
                _result["e"] = data["e"];
                data.remove("e");
            }
            _result["s"] = data;
        }
        Background.exit(_result);
    }
}
