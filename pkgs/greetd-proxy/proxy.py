"""stdio <-> greetd IPC bridge and dark/light variant picker for the
Quickshell greeter.

Two unrelated-looking jobs live in one script on purpose: the greeter needs
exactly one extra executable on the system, and both jobs are a handful of
stdlib calls. See docs/superpowers/specs/2026-10-06-quickshell-greeter-design.md

The bridge exists because greetd frames every message with a native-endian
u32 length prefix. Quickshell's Socket is text-oriented, and writing that
prefix from QML only works while the payload stays under 128 bytes -- above
that the length byte is no longer representable as a single UTF-8 byte and
authentication breaks silently. So QML speaks newline-delimited JSON to this
script over a pipe, and this script owns the framing.
"""

import argparse
import datetime
import json
import math
import os
import socket
import struct
import sys
import threading

ZENITH_OFFICIAL = 90.833


# --- variant selection ------------------------------------------------------


def resolve_timezone(localtime_path="/etc/localtime"):
    """Return e.g. "Europe/Paris", or None if it cannot be determined.

    Mirrors what modules/home-manager/darkman.nix's darkman-timezone-sync
    does: follow /etc/localtime and take everything after "/zoneinfo/".
    """
    if not os.path.islink(localtime_path):
        return None
    try:
        target = os.path.realpath(localtime_path)
    except OSError:
        return None
    marker = "/zoneinfo/"
    index = target.find(marker)
    if index == -1:
        return None
    return target[index + len(marker):]


def sun_event_utc(lat, lng, date, rising):
    """Hours UTC of sunrise (rising=True) or sunset for `date` at lat/lng.

    The standard almanac sunrise/sunset approximation, accurate to a couple
    of minutes, which is far finer than a theme switch needs. Returns None
    when the sun does not cross the horizon that day (polar day or night),
    because there is no solution to return.
    """
    day_of_year = date.timetuple().tm_yday
    lng_hour = lng / 15.0

    approx_hour = 6.0 if rising else 18.0
    t = day_of_year + ((approx_hour - lng_hour) / 24.0)

    mean_anomaly = (0.9856 * t) - 3.289
    true_lng = (
        mean_anomaly
        + (1.916 * math.sin(math.radians(mean_anomaly)))
        + (0.020 * math.sin(math.radians(2 * mean_anomaly)))
        + 282.634
    ) % 360.0

    right_ascension = math.degrees(math.atan(0.91764 * math.tan(math.radians(true_lng)))) % 360.0
    # Right ascension has to land in the same quadrant as the true longitude.
    right_ascension += (math.floor(true_lng / 90.0) * 90.0) - (
        math.floor(right_ascension / 90.0) * 90.0
    )
    right_ascension /= 15.0

    sin_dec = 0.39782 * math.sin(math.radians(true_lng))
    cos_dec = math.cos(math.asin(sin_dec))

    cos_hour_angle = (
        math.cos(math.radians(ZENITH_OFFICIAL)) - (sin_dec * math.sin(math.radians(lat)))
    ) / (cos_dec * math.cos(math.radians(lat)))

    if cos_hour_angle > 1.0 or cos_hour_angle < -1.0:
        return None

    hour_angle = math.degrees(math.acos(cos_hour_angle))
    if rising:
        hour_angle = 360.0 - hour_angle
    hour_angle /= 15.0

    local_mean_time = hour_angle + right_ascension - (0.06571 * t) - 6.622
    return (local_mean_time - lng_hour) % 24.0


def pick_theme(lat, lng, now_utc):
    """Return "dark" or "light" for the given instant.

    Dark is the fallback whenever there is no sunrise/sunset to compare
    against: a greeter that always comes up is worth more than one that is
    correct about polar daylight.
    """
    today = now_utc.date()
    sunrise = sun_event_utc(lat, lng, today, rising=True)
    sunset = sun_event_utc(lat, lng, today, rising=False)
    if sunrise is None or sunset is None:
        return "dark"

    now_hours = now_utc.hour + (now_utc.minute / 60.0) + (now_utc.second / 3600.0)
    if sunrise < sunset:
        return "light" if sunrise <= now_hours < sunset else "dark"
    # Sunset before sunrise in UTC terms: daylight spans the UTC midnight.
    return "light" if (now_hours >= sunrise or now_hours < sunset) else "dark"


def coordinates_for_host(table, localtime_path="/etc/localtime"):
    """Pick lat/lng for this machine from a {coords, fallback} table.

    The table comes from modules/lib/timezone-coords.nix, the same file
    darkman reads, so the greeter and the desktop agree on where "here" is.
    """
    timezone = resolve_timezone(localtime_path)
    entry = table.get("coords", {}).get(timezone) if timezone else None
    if entry is None:
        entry = table["fallback"]
    return float(entry["lat"]), float(entry["lng"])


# --- greetd IPC bridge ------------------------------------------------------


def send_message(sock, obj):
    """Write one greetd frame: native-endian u32 length, then JSON."""
    payload = json.dumps(obj).encode("utf-8")
    sock.sendall(struct.pack("=I", len(payload)) + payload)


def _recv_exactly(sock, count):
    buffer = b""
    while len(buffer) < count:
        chunk = sock.recv(count - len(buffer))
        if not chunk:
            return None
        buffer += chunk
    return buffer


def recv_message(sock):
    """Read one greetd frame, or None if the peer closed."""
    header = _recv_exactly(sock, 4)
    if header is None:
        return None
    (length,) = struct.unpack("=I", header)
    payload = _recv_exactly(sock, length)
    if payload is None:
        return None
    return json.loads(payload.decode("utf-8"))


def run_bridge(sock, stdin, stdout):
    """Pump newline-delimited JSON from stdin to greetd and back to stdout.

    Tracks whether a session is pending so a retry after a failed password
    cancels first; greetd rejects create_session while one is open, and the
    QML has no way to know that.
    """
    session_pending = False

    def emit(obj):
        stdout.write(json.dumps(obj) + "\n")
        stdout.flush()

    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            continue

        if request.get("type") == "create_session":
            if not request.get("username"):
                emit(
                    {
                        "type": "error",
                        "error_type": "auth_error",
                        "description": "username is empty",
                    }
                )
                continue
            if session_pending:
                send_message(sock, {"type": "cancel_session"})
                recv_message(sock)
                session_pending = False

        send_message(sock, request)
        response = recv_message(sock)
        if response is None:
            emit(
                {
                    "type": "error",
                    "error_type": "error",
                    "description": "greetd closed the connection",
                }
            )
            return

        kind = request.get("type")
        if kind == "create_session":
            session_pending = True
        elif kind in ("cancel_session", "start_session"):
            session_pending = False
        elif response.get("type") == "success":
            session_pending = False

        emit(response)


class _MockGreetd:
    """An in-process greetd accepting one password, for visual QML work."""

    def __init__(self, password):
        self.password = password
        self.server, self.client = socket.socketpair()
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        while True:
            request = recv_message(self.server)
            if request is None:
                return
            kind = request.get("type")
            if kind == "create_session":
                send_message(
                    self.server,
                    {
                        "type": "auth_message",
                        "auth_message_type": "secret",
                        "auth_message": "Password: ",
                    },
                )
            elif kind == "post_auth_message_response":
                if request.get("response") == self.password:
                    send_message(self.server, {"type": "success"})
                else:
                    send_message(
                        self.server,
                        {
                            "type": "error",
                            "error_type": "auth_error",
                            "description": "authentication failed",
                        },
                    )
            else:
                send_message(self.server, {"type": "success"})


def main(argv=None):
    parser = argparse.ArgumentParser(description="greetd bridge and theme picker")
    parser.add_argument(
        "--theme",
        action="store_true",
        help="print 'dark' or 'light' for the current time and exit",
    )
    parser.add_argument(
        "--coords",
        help='JSON {"coords": {"<tz>": {"lat": .., "lng": ..}}, "fallback": {..}}',
    )
    parser.add_argument(
        "--mock",
        metavar="PASSWORD",
        help="bridge against an in-process fake greetd accepting PASSWORD",
    )
    args = parser.parse_args(argv)

    if args.theme:
        if not args.coords:
            print("--theme requires --coords", file=sys.stderr)
            return 1
        lat, lng = coordinates_for_host(json.loads(args.coords))
        print(pick_theme(lat, lng, datetime.datetime.now(datetime.timezone.utc)))
        return 0

    if args.mock:
        run_bridge(_MockGreetd(args.mock).client, sys.stdin, sys.stdout)
        return 0

    sock_path = os.environ.get("GREETD_SOCK")
    if not sock_path:
        print("GREETD_SOCK is not set", file=sys.stderr)
        return 1
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(sock_path)
        run_bridge(sock, sys.stdin, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
