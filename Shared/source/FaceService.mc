import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Runs in the background every 15 minutes: sport history from the Strava relay
// (see Athlete/relay) and weather from Open-Meteo at the watch's own last GPS
// fix (or the default location in Credentials until it has one).
// The background process only has 64 KB, so nothing big is kept around.
//
// Result keys: "w" weather, "s" {sport => last start epoch},
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
            fetchWeather();
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
        fetchWeather();
    }

    private function fetchWeather() as Void {
        var lat = Application.Storage.getValue("lat");
        var lon = Application.Storage.getValue("lon");
        if (lat == null || lon == null) {
            lat = Credentials.DEFAULT_LAT;
            lon = Credentials.DEFAULT_LON;
        }
        Communications.makeWebRequest(
            "https://api.open-meteo.com/v1/forecast",
            {
                "latitude" => lat,
                "longitude" => lon,
                "current" => "temperature_2m,weather_code,is_day",
                "daily" => "temperature_2m_max,temperature_2m_min",
                "models" => "gem_seamless",
                "forecast_days" => 1,
                "timezone" => "auto"
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onWeather)
        );
    }

    function onWeather(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            var cur = data["current"] as Dictionary;
            var daily = data["daily"] as Dictionary;
            _result["w"] = {
                "t" => cur["temperature_2m"],
                "c" => cur["weather_code"],
                "d" => cur["is_day"],
                "hi" => (daily["temperature_2m_max"] as Array)[0],
                "lo" => (daily["temperature_2m_min"] as Array)[0],
                "ts" => Time.now().value()
            };
        }
        Background.exit(_result);
    }
}
