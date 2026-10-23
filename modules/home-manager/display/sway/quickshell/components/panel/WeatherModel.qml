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
    property real fixedAt: 0
    property real fetchedAt: 0

    // How long a fix is trusted. The whole point of asking geoclue rather
    // than hardcoding coordinates is that the machine moves; a fix taken
    // once per session is a hardcoded city with extra steps.
    readonly property int fixTtlMs: 3600000

    function needsFix(lat, fixAt, ttl) {
        if (isNaN(lat)) return true;
        return Date.now() - fixAt >= ttl;
    }

    // The same idea one step down, and the step that was missing: the fix
    // had a TTL and the fetch did not, so the poll below - triggeredOnStart,
    // gated on `active` - put a curl on the wire every time the panel
    // opened. That is dozens an hour for a number that moves on the scale of
    // ten minutes, and the in-flight guard in fetchWeather() only stops them
    // overlapping, not happening.
    //
    // Deliberately under the poll interval rather than equal to it: fetchedAt
    // is stamped when the reply LANDS, so at a 600000 TTL the tick 600s later
    // is a round trip short of the threshold and the periodic refresh would
    // skip every other turn.
    readonly property int fetchTtlMs: 540000

    function needsFetch(at, ttl) {
        return Date.now() - at >= ttl;
    }

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

    // A cold geoclue is much slower than a warm one: the wifi scan and the
    // trilateration round trip both have to happen before it answers at all.
    // 8 seconds was enough warm and not enough cold, and cold is exactly the
    // case that matters - a login, a nixos switch, or darkman restarting the
    // shell at sunrise. Every surface on the desktop reads this one model
    // now, so a fix that times out is a blank temperature everywhere.
    property int fixTimeoutSec: 20

    Process {
        id: locate
        command: ["@whereAmIBin@", "-t", "" + root.fixTimeoutSec]
        stdout: StdioCollector {
            onStreamFinished: {
                // where-am-i prints a human report, not JSON:
                //   Latitude:    48.856600°
                const lat = /Latitude:\s*(-?[\d.]+)/.exec(this.text);
                const lon = /Longitude:\s*(-?[\d.]+)/.exec(this.text);
                if (!lat || !lon) {
                    // Only blank a reading we never had. Re-fixing on a
                    // machine that already knows where it is must not wipe
                    // the temperature, same rule the fetch below follows.
                    if (isNaN(root.latitude)) {
                        root.ok = false;
                        // geoclue refuses an app that is not in its appConfig
                        // by never returning a fix, which reads identically
                        // to no signal. Say both.
                        root.failure = "No location";
                    }
                    fixRetry.restart();
                    return;
                }
                root.latitude = parseFloat(lat[1]);
                root.longitude = parseFloat(lon[1]);
                root.fixedAt = Date.now();
                fixRetry.attempt = 0;
                root.fetchWeather();
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && isNaN(root.latitude)) {
                root.ok = false;
                root.failure = "No location";
                fixRetry.restart();
            }
        }
    }

    // A fix that failed retries in seconds, not at the next poll.
    //
    // The poll is ten minutes apart, which is right for weather and absurd
    // for "we still do not know where we are" - and the fix most likely to
    // fail is the cold one at startup, so without this a restart meant a
    // blank temperature on every surface for ten full minutes. That is the
    // regression that came with sharing one model: the old desktop clock
    // asked Open-Meteo directly and never depended on a fix at all.
    //
    // Backed off, and capped, so a machine where geoclue is broken or
    // disabled settles into a slow retry instead of scanning wifi forever.
    Timer {
        id: fixRetry
        property int attempt: 0
        interval: Math.min(300000, 15000 * Math.pow(2, attempt))
        repeat: false
        onTriggered: {
            attempt = Math.min(attempt + 1, 5);
            if (root.active && !locate.running
                && root.needsFix(root.latitude, root.fixedAt, root.fixTtlMs))
                locate.running = true;
        }
    }

    function fetchWeather() {
        // Never restart one in flight. Opening the panel re-triggers the
        // poll, and reassigning command on a running Process kills it -
        // the aborted run reports a non-zero exit, which read as
        // "Offline" even though nothing was wrong with the network. Two
        // opens inside one round trip was all it took.
        if (weather.running) return;
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
                    root.fetchedAt = Date.now();
                } catch (e) {
                    if (!root.ok) {
                        root.ok = false;
                        root.failure = "No weather";
                    }
                }
            }
        }
        onExited: exitCode => {
            // A failed fetch does not erase a good reading. The sky has
            // not changed because one request was cut short, and blanking
            // 13 degrees to a dash is a worse answer than showing the
            // temperature from four minutes ago.
            if (exitCode !== 0 && !root.ok) {
                root.ok = false;
                root.failure = "Offline";
            }
        }
    }

    Timer {
        // Weather does not move fast, and a fix costs a wifi scan. Ticks on
        // every open and then every ten minutes, but only actually fetches
        // when the reading it holds has aged past fetchTtlMs - so reopening
        // the panel four times in a minute costs nothing.
        interval: 600000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.needsFix(root.latitude, root.fixedAt, root.fixTtlMs)) {
                if (!locate.running) locate.running = true;
            } else if (root.needsFetch(root.fetchedAt, root.fetchTtlMs)) {
                root.fetchWeather();
            }
        }
    }
}
