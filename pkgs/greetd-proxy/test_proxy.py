import datetime
import io
import json
import socket
import struct
import threading

import proxy

PARIS = (48.8566, 2.3522)


# --- variant selection ------------------------------------------------------


def test_resolve_timezone_reads_localtime_symlink(tmp_path):
    zoneinfo = tmp_path / "zoneinfo" / "Europe" / "Paris"
    zoneinfo.parent.mkdir(parents=True)
    zoneinfo.write_text("")
    link = tmp_path / "localtime"
    link.symlink_to(zoneinfo)
    assert proxy.resolve_timezone(str(link)) == "Europe/Paris"


def test_resolve_timezone_returns_none_when_missing(tmp_path):
    assert proxy.resolve_timezone(str(tmp_path / "nope")) is None


def test_resolve_timezone_returns_none_for_plain_file(tmp_path):
    plain = tmp_path / "localtime"
    plain.write_text("not a symlink into zoneinfo")
    assert proxy.resolve_timezone(str(plain)) is None


def test_paris_midsummer_sunrise_is_early_morning_utc():
    june = datetime.date(2026, 6, 21)
    sunrise = proxy.sun_event_utc(PARIS[0], PARIS[1], june, rising=True)
    # Paris sunrise on the solstice is 03:47 UTC; the almanac algorithm is
    # accurate to a couple of minutes, so assert a generous window rather
    # than an exact value.
    assert 3.5 < sunrise < 4.2


def test_paris_midsummer_sunset_is_late_evening_utc():
    june = datetime.date(2026, 6, 21)
    sunset = proxy.sun_event_utc(PARIS[0], PARIS[1], june, rising=False)
    assert 19.6 < sunset < 20.3


def test_paris_midwinter_sunrise_is_much_later_than_midsummer():
    june = datetime.date(2026, 6, 21)
    december = datetime.date(2026, 12, 21)
    summer = proxy.sun_event_utc(PARIS[0], PARIS[1], june, rising=True)
    winter = proxy.sun_event_utc(PARIS[0], PARIS[1], december, rising=True)
    assert winter > summer + 2.5


def test_pick_theme_is_light_at_local_noon():
    noon = datetime.datetime(2026, 6, 21, 12, 0, tzinfo=datetime.timezone.utc)
    assert proxy.pick_theme(PARIS[0], PARIS[1], noon) == "light"


def test_pick_theme_is_dark_at_midnight():
    midnight = datetime.datetime(2026, 6, 21, 0, 30, tzinfo=datetime.timezone.utc)
    assert proxy.pick_theme(PARIS[0], PARIS[1], midnight) == "dark"


def test_pick_theme_is_dark_just_after_sunset():
    sunset = proxy.sun_event_utc(PARIS[0], PARIS[1], datetime.date(2026, 6, 21), rising=False)
    just_after = datetime.datetime(2026, 6, 21, tzinfo=datetime.timezone.utc) + datetime.timedelta(
        hours=sunset + 0.25
    )
    assert proxy.pick_theme(PARIS[0], PARIS[1], just_after) == "dark"


def test_pick_theme_falls_back_to_dark_in_polar_night():
    # Longyearbyen in December: the sun never rises, so the algorithm has no
    # solution. The greeter must still get a usable answer.
    midwinter = datetime.datetime(2026, 12, 21, 12, 0, tzinfo=datetime.timezone.utc)
    assert proxy.pick_theme(78.22, 15.63, midwinter) == "dark"


TABLE = {
    "coords": {
        "Europe/Paris": {"lat": "48.8566", "lng": "2.3522"},
        "America/Mazatlan": {"lat": "23.2494", "lng": "-106.4111"},
    },
    "fallback": {"lat": "48.8566", "lng": "2.3522"},
}


def _localtime_pointing_at(tmp_path, zone):
    zoneinfo = tmp_path / "zoneinfo" / zone
    zoneinfo.parent.mkdir(parents=True, exist_ok=True)
    zoneinfo.write_text("")
    link = tmp_path / "localtime"
    link.symlink_to(zoneinfo)
    return str(link)


def test_coordinates_for_host_uses_the_matching_timezone(tmp_path):
    link = _localtime_pointing_at(tmp_path, "America/Mazatlan")
    assert proxy.coordinates_for_host(TABLE, link) == (23.2494, -106.4111)


def test_coordinates_for_host_falls_back_for_an_unknown_timezone(tmp_path):
    link = _localtime_pointing_at(tmp_path, "Antarctica/Troll")
    assert proxy.coordinates_for_host(TABLE, link) == (48.8566, 2.3522)


def test_coordinates_for_host_falls_back_when_localtime_is_missing(tmp_path):
    # A greeter with no /etc/localtime must still pick a variant rather than
    # crash into a blank screen.
    assert proxy.coordinates_for_host(TABLE, str(tmp_path / "nope")) == (48.8566, 2.3522)


# --- greetd IPC bridge ------------------------------------------------------


def _read_framed(conn):
    header = conn.recv(4)
    if len(header) < 4:
        return None
    (length,) = struct.unpack("=I", header)
    payload = b""
    while len(payload) < length:
        chunk = conn.recv(length - len(payload))
        if not chunk:
            return None
        payload += chunk
    return json.loads(payload.decode("utf-8"))


def _write_framed(conn, obj):
    payload = json.dumps(obj).encode("utf-8")
    conn.sendall(struct.pack("=I", len(payload)) + payload)


class FakeGreetd:
    """A greetd that accepts exactly one password, over a socketpair."""

    def __init__(self, password):
        self.password = password
        self.server, self.client = socket.socketpair()
        self.received = []
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        while True:
            request = _read_framed(self.server)
            if request is None:
                return
            self.received.append(request)
            kind = request.get("type")
            if kind == "create_session":
                _write_framed(
                    self.server,
                    {
                        "type": "auth_message",
                        "auth_message_type": "secret",
                        "auth_message": "Password: ",
                    },
                )
            elif kind == "post_auth_message_response":
                if request.get("response") == self.password:
                    _write_framed(self.server, {"type": "success"})
                else:
                    _write_framed(
                        self.server,
                        {
                            "type": "error",
                            "error_type": "auth_error",
                            "description": "authentication failed",
                        },
                    )
            elif kind in ("cancel_session", "start_session"):
                _write_framed(self.server, {"type": "success"})


def _drive(fake, lines):
    stdin = io.StringIO("".join(line + "\n" for line in lines))
    stdout = io.StringIO()
    proxy.run_bridge(fake.client, stdin, stdout)
    return [json.loads(line) for line in stdout.getvalue().splitlines()]


def test_bridge_round_trips_a_successful_login():
    fake = FakeGreetd("hunter2")
    out = _drive(
        fake,
        [
            json.dumps({"type": "create_session", "username": "ogama"}),
            json.dumps({"type": "post_auth_message_response", "response": "hunter2"}),
        ],
    )
    assert out[0]["type"] == "auth_message"
    assert out[0]["auth_message_type"] == "secret"
    assert out[1]["type"] == "success"


def test_bridge_reports_auth_error_for_a_wrong_password():
    fake = FakeGreetd("hunter2")
    out = _drive(
        fake,
        [
            json.dumps({"type": "create_session", "username": "ogama"}),
            json.dumps({"type": "post_auth_message_response", "response": "wrong"}),
        ],
    )
    assert out[1]["type"] == "error"
    assert out[1]["error_type"] == "auth_error"


def test_bridge_survives_a_password_past_the_single_byte_length_boundary():
    # The whole reason this helper exists instead of hand-rolled QML framing:
    # a payload of 128 bytes or more cannot be length-prefixed by writing the
    # length as a UTF-8 character. 300 chars puts the frame well past it.
    long_password = "a" * 300
    fake = FakeGreetd(long_password)
    out = _drive(
        fake,
        [
            json.dumps({"type": "create_session", "username": "ogama"}),
            json.dumps({"type": "post_auth_message_response", "response": long_password}),
        ],
    )
    assert out[1]["type"] == "success"
    assert fake.received[1]["response"] == long_password


def test_bridge_passes_non_ascii_passwords_through_unchanged():
    password = "pate-字-\U0001f511"
    fake = FakeGreetd(password)
    out = _drive(
        fake,
        [
            json.dumps({"type": "create_session", "username": "ogama"}),
            json.dumps({"type": "post_auth_message_response", "response": password}),
        ],
    )
    assert out[1]["type"] == "success"


def test_bridge_cancels_before_recreating_a_session():
    # greetd refuses create_session while one is pending, so a retry after a
    # failure must cancel first or the second attempt never authenticates.
    fake = FakeGreetd("hunter2")
    _drive(
        fake,
        [
            json.dumps({"type": "create_session", "username": "ogama"}),
            json.dumps({"type": "post_auth_message_response", "response": "wrong"}),
            json.dumps({"type": "create_session", "username": "ogama"}),
            json.dumps({"type": "post_auth_message_response", "response": "hunter2"}),
        ],
    )
    kinds = [r["type"] for r in fake.received]
    assert kinds == [
        "create_session",
        "post_auth_message_response",
        "cancel_session",
        "create_session",
        "post_auth_message_response",
    ]


def test_bridge_rejects_an_empty_username_without_touching_the_socket():
    fake = FakeGreetd("hunter2")
    out = _drive(fake, [json.dumps({"type": "create_session", "username": ""})])
    assert out[0]["type"] == "error"
    assert out[0]["error_type"] == "auth_error"
    assert fake.received == []


def test_bridge_ignores_malformed_input_lines():
    fake = FakeGreetd("hunter2")
    out = _drive(
        fake,
        [
            "{not json at all",
            json.dumps({"type": "create_session", "username": "ogama"}),
        ],
    )
    assert out[0]["type"] == "auth_message"
    assert len(fake.received) == 1
