import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Runs in the background every 15 minutes: the last time per sport from the
// Strava relay, plus weather from Open-Meteo at the watch's own last GPS fix. The background process only has 64 KB, so nothing big is kept around.
//
// Result keys: "w" weather, "s" {sport => start epoch}.
(:background)
class AthleteService extends System.ServiceDelegate {
    private var _result as Dictionary = {};

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        fetchSports();
    }

    // --- Weather ----------------------------------------------------------

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

    // --- Sport history ----------------------------------------------------

    // A small relay (see relay/README.md) talks to Strava and answers with
    // {"b": epoch, "g": epoch, ...}: Connect IQ 3.0 can't parse Strava's
    // top-level JSON array, and the payload would not fit in background memory.
    private function fetchSports() as Void {
        if (Credentials.RELAY_URL.length() == 0) {
            fetchWeather();
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
        fetchWeather();
    }
}
