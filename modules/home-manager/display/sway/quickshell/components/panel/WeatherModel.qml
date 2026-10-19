import QtQuick
import Quickshell.Io

// Where the laptop is, and what the sky is doing there.
//
// Two steps, because neither service does both: geoclue says where (wifi
// trilateration, so it follows the machine rather than guessing from an IP),
// Open-Meteo says what. Open-Meteo needs no key and no account.
//
// The place NAME comes free: asking Open-Meteo for timezone=auto returns
// something like "Europe/Paris", and the last segment of that is a better
// label than a pair of coordinates. It saves a third request to a
// reverse-geocoder.
//
// Gated on `active` like everything else in the panel. Two subprocesses and
// a network round trip have no business running for a panel nobody opened.
Item {
    id: root

    property bool active: false

    property real tempC: 0
    property string condition: ""
    property string place: ""
    property bool ok: false
    property string failure: "No location yet"

    property real latitude: NaN
    property real longitude: NaN

    // WMO weather codes, grouped the way a person reads a sky rather than
    // the way the standard enumerates it.
    function describe(code) {
        if (code === 0) return "Clear";
        if (code <= 2) return "Partly cloudy";
        if (code === 3) return "Overcast";
        if (code <= 48) return "Fog";
        if (code <= 57) return "Drizzle";
        if (code <= 67) return "Rain";
        if (code <= 77) return "Snow";
        if (code <= 82) return "Showers";
        if (code <= 86) return "Snow showers";
        return "Thunderstorm";
    }

    Process {
        id: locate
        command: ["@whereAmIBin@", "-t", "8"]
        stdout: StdioCollector {
            onStreamFinished: {
                // where-am-i prints a human report, not JSON:
                //   Latitude:    48.856600°
                const lat = /Latitude:\s*(-?[\d.]+)/.exec(this.text);
                const lon = /Longitude:\s*(-?[\d.]+)/.exec(this.text);
                if (!lat || !lon) {
                    root.ok = false;
                    // geoclue refuses an app that is not in its appConfig by
                    // never returning a fix, which reads identically to no
                    // signal. Say both.
                    root.failure = "No location";
                    return;
                }
                root.latitude = parseFloat(lat[1]);
                root.longitude = parseFloat(lon[1]);
                root.fetchWeather();
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && isNaN(root.latitude)) {
                root.ok = false;
                root.failure = "No location";
            }
        }
    }

    function fetchWeather() {
        weather.command = [
            "curl", "-s", "--max-time", "6",
            "https://api.open-meteo.com/v1/forecast"
                + "?latitude=" + root.latitude.toFixed(4)
                + "&longitude=" + root.longitude.toFixed(4)
                + "&current=temperature_2m,weather_code&timezone=auto"
        ];
        weather.running = true;
    }

    Process {
        id: weather
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    root.tempC = d.current.temperature_2m;
                    root.condition = root.describe(d.current.weather_code);
                    const tz = (d.timezone || "").split("/");
                    root.place = tz.length > 1
                        ? tz[tz.length - 1].replace(/_/g, " ")
                        : "";
                    root.ok = true;
                } catch (e) {
                    root.ok = false;
                    root.failure = "No weather";
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.ok = false;
                root.failure = "Offline";
            }
        }
    }

    Timer {
        // Weather does not move fast, and a fix costs a wifi scan. Once on
        // open, then every ten minutes for as long as the panel stays up.
        interval: 600000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (isNaN(root.latitude)) locate.running = true;
            else root.fetchWeather();
        }
    }
}
