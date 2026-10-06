# Quickshell Greeter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the getty login on the `personal` NixOS profile with a Quickshell greeter on `greetd` that mirrors the existing dark/light lockscreen designs and picks its variant from local sunrise/sunset.

**Architecture:** A Python helper (`greetd-proxy`) translates newline-delimited JSON on stdio to and from greetd's length-prefixed socket protocol, and also computes the dark/light variant from the system timezone. Two new QML files (`GreeterDark.qml`, `GreeterLight.qml`) reuse the already-extracted lockscreen components and drive the helper through Quickshell's `Process`. A new NixOS module installs all of it to `/etc/greeter/` and configures `greetd` to launch `sway` running the greeter, with an `agreety` fallback so a crash can never lock the machine out.

**Tech Stack:** Nix / NixOS modules / home-manager, Quickshell 0.3.0 (QML, Qt 6), greetd, sway, Python 3 (stdlib only).

**Spec:** `docs/superpowers/specs/2026-10-06-quickshell-greeter-design.md`

## Global Constraints

- Target profile is `personal` only. Do not touch `oserv`, `epita`, or `epita-light`.
- The `greeter` user must never read anything under `/home/ogama`. All greeter assets, fonts, and QML resolve to Nix store paths or `/etc/greeter/`.
- `greetd-proxy` uses the Python standard library only. No third-party dependencies.
- The existing lockscreens must behave identically after every task. `LockDark.qml` and `LockLight.qml` are not edited by this plan.
- The palette single-source-of-truth is `theme-colors.nix`. No new hex literals for base16 colors anywhere.
- The lat/lng table single-source-of-truth is `timezone-coords.nix`. Paris (`48.8566`, `2.3522`) is the fallback for an unknown or missing timezone.
- `services.greetd.vt = 1`. Other VTs stay plain gettys.
- Never run `nixos-rebuild switch` without asking the user first. `nixos-rebuild test` is the validation command in this plan.

## Review Focus

- **A password of 128 bytes or more.** This is the exact failure the helper exists to prevent; the framing must survive a payload crossing the single-byte-length boundary. Pinned in Task 3.
- **An unknown or missing `/etc/localtime`.** Must fall back to Paris and still print a variant, never crash the greeter into a blank screen. Pinned in Task 2.
- **An empty username or empty password submitted with Enter.** Must not send a malformed `create_session` or hang the field in a permanently disabled state. Pinned in Task 3 (proxy) and Task 7 (QML).
- **A wifi link not yet associated when the weather `curl` fires.** The temperature must render as empty, not as an error string or a stuck placeholder. Pinned in Task 7.
- **A second login attempt after a failed one.** greetd rejects a `create_session` while a session is already pending; the proxy must `cancel_session` first or the second attempt silently never authenticates. Pinned in Task 3.

---

## File Structure

| File | Responsibility |
|---|---|
| `modules/lib/theme-colors.nix` | Base16 palettes (moved, unchanged content) |
| `modules/lib/timezone-coords.nix` | Timezone → lat/lng table (extracted from `darkman.nix`) |
| `modules/lib/qml-theme.nix` | `@token@` substitution function, shared by HM and NixOS |
| `modules/qml/components/*.qml` | Shared QML primitives (moved from the quickshell dir) |
| `modules/qml/GreeterDark.qml` | Dark greeter surface + auth wiring |
| `modules/qml/GreeterLight.qml` | Light greeter surface + auth wiring |
| `pkgs/greetd-proxy/proxy.py` | stdio ↔ greetd IPC, plus `--theme` and `--mock` |
| `pkgs/greetd-proxy/test_proxy.py` | Unit tests for the above |
| `pkgs/greetd-proxy.nix` | Derivation wrapping `proxy.py` |
| `modules/nixosconf/greetd.nix` | greetd service, `/etc/greeter` contents, fonts, polkit |

---

## Task 1: Extract the shared pure-data Nix libs

Moves `theme-colors.nix` up out of home-manager and pulls the timezone table out of `darkman.nix`, so the NixOS greeter module can read both without evaluating home-manager. No behavior change.

**Files:**
- Create: `modules/lib/theme-colors.nix` (moved from `modules/home-manager/lib/theme-colors.nix`)
- Create: `modules/lib/timezone-coords.nix`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix` (the `lockThemeColors` import path)
- Modify: `modules/home-manager/darkman.nix` (replace the inlined `timezoneCoords`)

**Interfaces:**
- Consumes: nothing.
- Produces: `modules/lib/theme-colors.nix` → `{ dark = { base00 = "1C1E26"; ... }; light = { ... }; }`. `modules/lib/timezone-coords.nix` → `{ coords = { "Europe/Paris" = { lat = "48.8566"; lng = "2.3522"; }; ... }; fallback = { lat = "48.8566"; lng = "2.3522"; }; }`.

- [ ] **Step 1: Move the palette file**

```bash
git mv modules/home-manager/lib/theme-colors.nix modules/lib/theme-colors.nix
```

- [ ] **Step 2: Repoint the one importer**

In `modules/home-manager/display/sway/quickshell/default.nix`, the line reading

```nix
  lockThemeColors = import ../../../lib/theme-colors.nix;
```

becomes

```nix
  lockThemeColors = import ../../../../lib/theme-colors.nix;
```

(The file sits at `modules/home-manager/display/sway/quickshell/default.nix`; `../../../../lib` resolves to `modules/lib`. Verify with `nix eval` in step 5, do not eyeball the dot count.)

- [ ] **Step 3: Create the timezone table**

Create `modules/lib/timezone-coords.nix`:

```nix
# Coordinates used for local sunrise/sunset computation. Mirrors
# host/personal/configuration.nix's time.timeZone and its two commented-out
# travel alternates. Consumed by modules/home-manager/darkman.nix and by
# pkgs/greetd-proxy (via modules/nixosconf/greetd.nix).
{
  coords = {
    "Europe/Paris" = { lat = "48.8566"; lng = "2.3522"; };
    "America/Monterrey" = { lat = "25.6866"; lng = "-100.3161"; };
    "America/Mazatlan" = { lat = "23.2494"; lng = "-106.4111"; };
  };

  # Paris is the fallback for an unrecognized or missing timezone.
  fallback = { lat = "48.8566"; lng = "2.3522"; };
}
```

- [ ] **Step 4: Consume it from darkman.nix**

In `modules/home-manager/darkman.nix`, delete the `timezoneCoords`, `fallbackLat`, and `fallbackLng` bindings (lines 10-18) and replace them with:

```nix
  tzTable = import ../lib/timezone-coords.nix;
  timezoneCoords = tzTable.coords;
  fallbackLat = tzTable.fallback.lat;
  fallbackLng = tzTable.fallback.lng;
```

Leave `timezoneCases`, `syncScript`, and everything below untouched — they read those three names and keep working.

- [ ] **Step 5: Verify both files still evaluate and produce identical output**

Run:

```bash
nix eval --impure --expr '(import ./modules/lib/theme-colors.nix).dark.base00'
nix eval --impure --expr '(import ./modules/lib/timezone-coords.nix).coords."Europe/Paris".lat'
nix flake check
```

Expected: `"1C1E26"`, `"48.8566"`, and a clean `nix flake check`.

- [ ] **Step 6: Verify the generated darkman config is byte-identical**

Run:

```bash
nix build .#homeConfigurations.personal.activationPackage --no-link --print-out-paths
```

Expected: builds successfully. Record the store path; it should differ from before only if the quickshell QML changed, which it has not in this task.

- [ ] **Step 7: Commit**

```bash
git add modules/lib/ modules/home-manager/darkman.nix modules/home-manager/display/sway/quickshell/default.nix
git commit -m "refactor: lift theme palette and timezone table into modules/lib"
```

---

## Task 2: greetd-proxy — sunrise/sunset variant selection

The `--theme` mode, built and tested before any socket code exists. This is the piece that must never crash: if it fails, the greeter has no QML file to load.

**Files:**
- Create: `pkgs/greetd-proxy/proxy.py`
- Create: `pkgs/greetd-proxy/test_proxy.py`

**Interfaces:**
- Consumes: `modules/lib/timezone-coords.nix` values, passed in as `--lat` / `--lng` defaults at build time by Task 4.
- Produces: `resolve_timezone(localtime_path) -> str | None`, `sun_event_utc(lat, lng, date, rising) -> float | None` (hours UTC, `None` when the sun does not cross the horizon that day), `pick_theme(lat, lng, now_utc) -> str` returning `"dark"` or `"light"`.

- [ ] **Step 1: Write the failing tests**

Create `pkgs/greetd-proxy/test_proxy.py`:

```python
import datetime
import os
import tempfile

import pytest

import proxy

PARIS = (48.8566, 2.3522)


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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cd pkgs/greetd-proxy && nix shell nixpkgs#python3Packages.pytest -c pytest test_proxy.py -v
```

Expected: collection error, `ModuleNotFoundError: No module named 'proxy'`.

- [ ] **Step 3: Implement the theme half of proxy.py**

Create `pkgs/greetd-proxy/proxy.py`:

```python
#!/usr/bin/env python3
"""stdio <-> greetd IPC bridge and dark/light variant picker for the
Quickshell greeter.

Two unrelated-looking jobs live in one script on purpose: the greeter needs
exactly one extra executable on the system, and both jobs are a handful of
stdlib calls. See docs/superpowers/specs/2026-10-06-quickshell-greeter-design.md
"""

import argparse
import datetime
import math
import os
import sys

ZENITH_OFFICIAL = 90.833


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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
cd pkgs/greetd-proxy && nix shell nixpkgs#python3Packages.pytest -c pytest test_proxy.py -v
```

Expected: 10 passed.

- [ ] **Step 5: Commit**

```bash
git add pkgs/greetd-proxy/
git commit -m "feat(greeter): add sunrise/sunset variant picker for greetd-proxy"
```

---

## Task 3: greetd-proxy — the IPC bridge

Translates newline-delimited JSON on stdio to greetd's length-prefixed socket protocol, and adds the `--mock` mode the QML is developed against.

**Files:**
- Modify: `pkgs/greetd-proxy/proxy.py`
- Modify: `pkgs/greetd-proxy/test_proxy.py`

**Interfaces:**
- Consumes: `pick_theme`, `resolve_timezone` from Task 2.
- Produces: `send_message(sock, obj) -> None`, `recv_message(sock) -> dict | None`, `run_bridge(sock, stdin, stdout) -> None`, and the CLI contract: `greetd-proxy --theme` prints `dark`/`light`; `greetd-proxy` bridges `$GREETD_SOCK`; `greetd-proxy --mock PASSWORD` bridges against an in-process fake that accepts only `PASSWORD`.

- [ ] **Step 1: Write the failing tests**

Append to `pkgs/greetd-proxy/test_proxy.py`:

```python
import io
import json
import socket
import struct
import threading


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
    password = "pâté-字-🔑"
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cd pkgs/greetd-proxy && nix shell nixpkgs#python3Packages.pytest -c pytest test_proxy.py -v
```

Expected: the eight new tests fail with `AttributeError: module 'proxy' has no attribute 'run_bridge'`. The ten from Task 2 still pass.

- [ ] **Step 3: Implement the bridge**

Append to `pkgs/greetd-proxy/proxy.py`:

```python
import json
import socket
import struct


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
        self.thread = __import__("threading").Thread(target=self._serve, daemon=True)
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--theme",
        action="store_true",
        help="print 'dark' or 'light' for the current time and exit",
    )
    parser.add_argument("--lat", type=float, required=False)
    parser.add_argument("--lng", type=float, required=False)
    parser.add_argument(
        "--mock",
        metavar="PASSWORD",
        help="bridge against an in-process fake greetd accepting PASSWORD",
    )
    args = parser.parse_args(argv)

    if args.theme:
        now = datetime.datetime.now(datetime.timezone.utc)
        print(pick_theme(args.lat, args.lng, now))
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
```

Note: `--lat` and `--lng` are declared without defaults because Task 4 bakes the real ones in through a wrapper. Running `--theme` without them is a programming error that raises, which is the correct loud failure.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
cd pkgs/greetd-proxy && nix shell nixpkgs#python3Packages.pytest -c pytest test_proxy.py -v
```

Expected: 18 passed.

- [ ] **Step 5: Verify the mock mode by hand**

Run:

```bash
cd pkgs/greetd-proxy && printf '%s\n%s\n' \
  '{"type":"create_session","username":"ogama"}' \
  '{"type":"post_auth_message_response","response":"letmein"}' \
  | nix shell nixpkgs#python3 -c python3 proxy.py --mock letmein
```

Expected output, one JSON object per line:

```
{"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "}
{"type": "success"}
```

- [ ] **Step 6: Commit**

```bash
git add pkgs/greetd-proxy/
git commit -m "feat(greeter): bridge stdio JSON to greetd's framed socket protocol"
```

---

## Task 4: Package greetd-proxy

**Files:**
- Create: `pkgs/greetd-proxy.nix`
- Modify: `flake.nix` (the `packages.${system}` set and the `lpkgs` set)

**Interfaces:**
- Consumes: `pkgs/greetd-proxy/proxy.py`, `modules/lib/timezone-coords.nix`.
- Produces: `lpkgs.greetd-proxy`, a derivation exposing `bin/greetd-proxy` with `--lat`/`--lng` already bound to the host's timezone coordinates.

- [ ] **Step 1: Read how an existing package is wired**

Run:

```bash
cat pkgs/corpta-font.nix
grep -n "lpkgs\|packages\." flake.nix
```

Match the style you find there. Do not invent a different convention.

- [ ] **Step 2: Write the derivation**

Create `pkgs/greetd-proxy.nix`:

```nix
# stdio <-> greetd IPC bridge and dark/light variant picker for the
# Quickshell greeter. The coordinates are baked in at build time from
# modules/lib/timezone-coords.nix rather than read at runtime, because the
# greeter must not depend on a config file it could fail to find.
{ pkgs, lib, ... }:

let
  tzTable = import ../modules/lib/timezone-coords.nix;

  # The greeter resolves /etc/localtime at runtime; this is only the
  # fallback baked into the wrapper's default arguments.
  lat = tzTable.fallback.lat;
  lng = tzTable.fallback.lng;

  coordCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (tz: c: ''
      if [ "$TZ_VALUE" = "${tz}" ]; then LAT="${c.lat}"; LNG="${c.lng}"; fi
    '') tzTable.coords
  );

  rawProxy = pkgs.writers.writePython3Bin "greetd-proxy-raw" { } (
    builtins.readFile ./greetd-proxy/proxy.py
  );
in
pkgs.writeShellApplication {
  name = "greetd-proxy";
  runtimeInputs = [ rawProxy pkgs.coreutils ];
  text = ''
    TZ_VALUE=""
    if [ -L /etc/localtime ]; then
      REALPATH=$(readlink -f /etc/localtime)
      TZ_VALUE="''${REALPATH##*/zoneinfo/}"
    fi
    LAT="${lat}"
    LNG="${lng}"
    ${coordCases}
    exec greetd-proxy-raw --lat "$LAT" --lng "$LNG" "$@"
  '';
}
```

- [ ] **Step 3: Expose it from the flake**

Add `greetd-proxy` to `packages.${system}` and to the `lpkgs` set in `flake.nix`, following exactly the pattern used by the existing entries you read in step 1.

- [ ] **Step 4: Build and verify the baked coordinates**

Run:

```bash
nix build .#greetd-proxy --no-link --print-out-paths
nix run .#greetd-proxy -- --theme
```

Expected: a build path, then `dark` or `light` matching `darkman get`.

- [ ] **Step 5: Verify it agrees with darkman right now**

Run:

```bash
echo "proxy: $(nix run .#greetd-proxy -- --theme)   darkman: $(darkman get)"
```

Expected: the two agree. If they disagree, check whether darkman was manually toggled before treating it as a bug — the spec documents that divergence as accepted.

- [ ] **Step 6: Commit**

```bash
git add pkgs/greetd-proxy.nix flake.nix
git commit -m "feat(greeter): package greetd-proxy with host timezone coordinates"
```

---

## Task 5: Move the shared QML components

Relocates the primitives both the lockscreen and the greeter need, so the NixOS module can read them without reaching into the home-manager tree. The lockscreen must be visually and behaviorally unchanged afterwards.

**Files:**
- Create: `modules/qml/components/{BeamSide,GlassPill,ColorUtils,ClockModule,CollisionEffects,RevealMask,LaserBar}.qml` (moved)
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: Task 1's layout.
- Produces: `modules/qml/components/` as the canonical location for shared QML primitives.

- [ ] **Step 1: Confirm the working tree is clean for these files**

Run:

```bash
git status --short modules/home-manager/display/sway/quickshell/components/
```

Expected: no output. If any of the seven files listed above show as modified or staged, STOP and tell the user — their in-flight LaserBar/ClockModule work must land first, because `git mv` on a dirty file is how that work gets lost.

- [ ] **Step 2: Move the seven files**

```bash
mkdir -p modules/qml/components
for f in BeamSide GlassPill ColorUtils ClockModule CollisionEffects RevealMask LaserBar; do
  git mv "modules/home-manager/display/sway/quickshell/components/$f.qml" "modules/qml/components/$f.qml"
done
```

Note `Wallpaper.qml`, `Clock.qml`, `Music.qml`, `Calendar.qml`, `LockDark.qml`, and `LockLight.qml` stay where they are — they are lockscreen/bar specific and the greeter does not use them.

- [ ] **Step 3: Repoint the home-manager module**

In `modules/home-manager/display/sway/quickshell/default.nix`, the seven `xdg.configFile` entries for the moved files change their source path from `./components/X.qml` to `../../../../qml/components/X.qml`. For example:

```nix
    "quickshell/widgets/components/BeamSide.qml" = themedQmlFile ../../../../qml/components/BeamSide.qml;
```

The destination paths under `quickshell/widgets/components/` do not change, so no QML import statements need editing.

- [ ] **Step 4: Verify the generated QML is byte-identical to before the move**

Run:

```bash
nix build .#homeConfigurations.personal.activationPackage --no-link --print-out-paths
```

Then compare the generated LaserBar against the current live one:

```bash
diff <(cat ~/.config/quickshell/widgets/components/LaserBar.qml) \
     <(nix build .#homeConfigurations.personal.activationPackage --no-link --print-out-paths | head -1)/home-files/.config/quickshell/widgets/components/LaserBar.qml
```

Expected: no differences. A difference means the substitution inputs changed, which this task must not do.

- [ ] **Step 5: Verify the lockscreen still works**

Ask the user to run `home-manager switch --flake .#personal`, then lock with Mod+Shift+Escape and unlock. Do not run the switch yourself without asking.

Expected: the lockscreen appears and unlocks exactly as before.

- [ ] **Step 6: Commit**

```bash
git add modules/qml/ modules/home-manager/display/sway/quickshell/default.nix
git commit -m "refactor(quickshell): move shared QML primitives to modules/qml/components"
```

---

## Task 6: Factor out the QML theme substitution

The `@token@` replacement currently lives inline in the home-manager quickshell module and closes over home-manager's `config`. The NixOS greeter module needs the same substitution with different inputs, so it moves into a plain function. Pure refactor: generated output must be byte-identical.

**Files:**
- Create: `modules/lib/qml-theme.nix`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: `modules/lib/theme-colors.nix`.
- Produces: `modules/lib/qml-theme.nix` → a function

```nix
{ colors, laserColor, lockscreenImage, systemctlBin, corptaFontPath }: qmlText -> string
```

  where `colors` is one palette attrset (`{ base00 = "1C1E26"; ... }`) and the result is the QML text with every `@token@` replaced.

- [ ] **Step 1: Write the substitution function**

Create `modules/lib/qml-theme.nix`:

```nix
# Single implementation of the @token@ substitution used to theme the
# Quickshell QML. Called by the home-manager quickshell module (passing home
# paths) and by modules/nixosconf/greetd.nix (passing Nix store paths,
# because the greeter user cannot read /home).
{ colors
, laserColor
, lockscreenImage
, systemctlBin
, corptaFontPath
}:
builtins.replaceStrings
  [
    "@cardBg@"
    "@cardBorder@"
    "@clockColor@"
    "@dateColor@"
    "@dividerColor@"
    "@tempColor@"
    "@lockBg@"
    "@systemctlBin@"
    "@lockscreenImage@"
    "@laserColor@"
    "@greenColor@"
    "@redColor@"
    "@glassBg@"
    "@glassBorder@"
    "@corptaFontPath@"
  ]
  [
    "#B3${colors.base00}"
    "#33${colors.base05}"
    "#FF${colors.base05}"
    "#CC${colors.base04}"
    "#22${colors.base03}"
    "#FF${colors.base0D}"
    "#FF${colors.base00}"
    systemctlBin
    lockscreenImage
    laserColor
    "#FF${colors.base0B}"
    "#FF${colors.base08}"
    "#66${colors.base00}"
    "#59${colors.base05}"
    corptaFontPath
  ]
```

Note the token list is the superset from `withThemeColors`. `withLockThemeColors` handled a shorter list; the extra three tokens (`@glassBg@`, `@glassBorder@`, `@corptaFontPath@`) simply do not appear in the lock QML, so replacing them there is a no-op and the output is unchanged.

- [ ] **Step 2: Rewrite the home-manager module to call it**

In `modules/home-manager/display/sway/quickshell/default.nix`, replace the `withThemeColors`, `withLockThemeColors`, `lockVariant`, and `themedQmlFile` bindings with:

```nix
  qmlTheme = import ../../../../lib/qml-theme.nix;

  barTheme = qmlTheme {
    colors = config.lib.stylix.colors;
    laserColor = laserColor;
    lockscreenImage = "${config.home.homeDirectory}/nixos-configuration/assets/lockscreen/nausicaa.png";
    systemctlBin = "${pkgs.systemd}/bin/systemctl";
    corptaFontPath = "${config.home.homeDirectory}/nixos-configuration/assets/fonts/Corpta-DEMO.otf";
  };

  themedQmlFile = path: { text = barTheme (builtins.readFile path); };

  lockVariant = variant: lockComponent: image: {
    text = qmlTheme {
      colors = lockThemeColors.${variant};
      laserColor = if variant == "light" then "#FFFFFF" else "#000000";
      lockscreenImage = image;
      systemctlBin = "${pkgs.systemd}/bin/systemctl";
      corptaFontPath = "${config.home.homeDirectory}/nixos-configuration/assets/fonts/Corpta-DEMO.otf";
    } (builtins.readFile lockComponent);
  };
```

Keep the existing explanatory comment above `lockThemeColors` about the lock-only scope — it is still accurate and still worth having.

- [ ] **Step 3: Verify every generated QML file is byte-identical**

Run:

```bash
OLD=$(ls -d /nix/store/*-home-manager-files | tail -1)
NEW=$(nix build .#homeConfigurations.personal.activationPackage --no-link --print-out-paths)/home-files
diff -r "$HOME/.config/quickshell/widgets" "$NEW/.config/quickshell/widgets"
```

Expected: no differences at all. Any difference means the refactor changed behavior and must be fixed before committing.

- [ ] **Step 4: Commit**

```bash
git add modules/lib/qml-theme.nix modules/home-manager/display/sway/quickshell/default.nix
git commit -m "refactor(quickshell): extract the QML theme substitution into modules/lib"
```

---

## Task 7: GreetdSession QML component

The auth conversation, isolated from any visual design so both greeter variants share exactly one implementation of the protocol.

**Files:**
- Create: `modules/qml/components/GreetdSession.qml`

**Interfaces:**
- Consumes: `greetd-proxy` from Task 4, via the `@greetdProxyBin@` token.
- Produces: a component with properties `busy` (bool), `failed` (bool), `errorText` (string); methods `authenticate(username, password)` and `reset()`; signal `authenticated()`.

- [ ] **Step 1: Write the component**

Create `modules/qml/components/GreetdSession.qml`:

```qml
import QtQuick
import Quickshell.Io

// The whole greetd conversation, kept out of the greeter surfaces so
// GreeterDark.qml and GreeterLight.qml differ only in visual design.
//
// Talks newline-delimited JSON to greetd-proxy (pkgs/greetd-proxy), which
// owns the length-prefixed socket framing - see the spec for why that
// framing cannot live in QML.
Item {
    id: session
    visible: false

    property bool busy: false
    property bool failed: false
    property string errorText: ""

    // Set by the caller before authenticate(); the password is held only
    // long enough to answer greetd's auth_message.
    property string pendingPassword: ""

    signal authenticated()

    function authenticate(username, password) {
        if (session.busy) return
        session.busy = true
        session.failed = false
        session.errorText = ""
        session.pendingPassword = password
        proxy.write(JSON.stringify({ type: "create_session", username: username }) + "\n")
    }

    function reset() {
        session.busy = false
        session.failed = false
        session.errorText = ""
        session.pendingPassword = ""
    }

    Process {
        id: proxy
        command: [ "@greetdProxyBin@" ]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim() === "") return

                let message
                try {
                    message = JSON.parse(line)
                } catch (e) {
                    // A proxy that emits garbage is a bug, not a user error;
                    // drop the line rather than wedging the greeter.
                    return
                }

                if (message.type === "auth_message") {
                    if (message.auth_message_type === "secret") {
                        proxy.write(JSON.stringify({
                            type: "post_auth_message_response",
                            response: session.pendingPassword
                        }) + "\n")
                        session.pendingPassword = ""
                    }
                    return
                }

                if (message.type === "success") {
                    session.pendingPassword = ""
                    session.busy = false
                    session.authenticated()
                    return
                }

                if (message.type === "error") {
                    session.pendingPassword = ""
                    session.busy = false
                    session.failed = true
                    session.errorText = message.description || "authentication failed"
                }
            }
        }
    }

    // The greeter exits and greetd starts the real session. Called by the
    // surfaces from onAuthenticated.
    function startSession() {
        proxy.write(JSON.stringify({ type: "start_session", cmd: [ "@swayBin@" ] }) + "\n")
    }
}
```

- [ ] **Step 2: Verify the component parses**

Run:

```bash
quickshell -p modules/qml/components/GreetdSession.qml 2>&1 | head -20
```

Expected: it will complain that there is no window to show, but must NOT report a QML syntax or type error. If you see `Unable to assign` or a parse error, fix it here before the surfaces depend on it. The `@greetdProxyBin@` token being a non-existent command is expected at this stage.

- [ ] **Step 3: Commit**

```bash
git add modules/qml/components/GreetdSession.qml
git commit -m "feat(greeter): add GreetdSession QML component for the auth conversation"
```

---

## Task 8: GreeterDark.qml

The dark surface, derived from `LockDark.qml`'s design language, with the auth backend swapped and the keyboard behavior the user specified.

**Files:**
- Create: `modules/qml/GreeterDark.qml`
- Read for reference: `modules/home-manager/display/sway/quickshell/components/LockDark.qml`

**Interfaces:**
- Consumes: `GreetdSession` (Task 7), the components in `modules/qml/components/`.
- Produces: a `PanelWindow`-based greeter surface loaded as `quickshell -p /etc/greeter/GreeterDark.qml`.

- [ ] **Step 1: Derive the file from LockDark.qml**

```bash
cp modules/home-manager/display/sway/quickshell/components/LockDark.qml modules/qml/GreeterDark.qml
```

Then apply exactly these changes. Do not edit `LockDark.qml` itself.

**Remove:**
- `import Quickshell.Services.Pam` and the whole `PamContext` block.
- `import Quickshell.Services.Mpris`, the `Mpris.players` helper function, the `playerctl position` `Process`, and every UI element that reads them.
- The `Process` whose command is `[ "@systemctlBin@", "--user", "restart", "quickshell-widgets" ]`.
- The `locked`, `unlocking`, and `unlockInProgress` properties and `unlockFadeTimer`.

**Replace the window wrapper:** the `WlSessionLock` / `WlSessionLockSurface` pair becomes a layer-shell panel, because a greeter is not locking an existing session. Keep the outer `Scope { id: root }` exactly as it is — every `root.accentMagenta` / `root.withAlpha(...)` reference in the visual tree resolves against it, and deleting it would break all of them:

```qml
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    // ... the existing readonly color properties and withAlpha() stay here ...

        PanelWindow {
        id: surface
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "@lockBg@"
        // ... the existing visual tree moves inside here unchanged ...
    }
}
```

**Keep unchanged:** the artwork `Image`, the clock, the date, the temperature `Process` and its display, the stencil panel geometry, `accentMagenta` / `accentCyan` / `accentAmber` / `paperWhite` / `smokeLavender`, and the `withAlpha` helper.

- [ ] **Step 2: Add the session object and the two fields**

Inside the panel, replace the single password field with this block. `usernameField` and `passwordField` are siblings so the arrow-key navigation can reach both.

```qml
    GreetdSession {
        id: session
        onAuthenticated: session.startSession()
    }

    property int focusedField: 0  // 0 = username, 1 = password

    function submitUsername() {
        if (usernameField.text.trim() === "") return
        surface.focusedField = 1
        passwordField.forceActiveFocus()
    }

    function submitPassword() {
        if (session.busy) return
        session.authenticate(usernameField.text.trim(), passwordField.text)
    }

    Connections {
        target: session
        function onFailedChanged() {
            if (!session.failed) return
            passwordField.text = ""
            surface.focusedField = 1
            passwordField.forceActiveFocus()
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            surface.focusedField = surface.focusedField === 0 ? 1 : 0
            if (surface.focusedField === 0) usernameField.forceActiveFocus()
            else passwordField.forceActiveFocus()
            event.accepted = true
        }
    }
```

- [ ] **Step 3: Add the username field with the dark selection treatment**

```qml
    TextInput {
        id: usernameField
        text: "ogama"
        font.family: "Inter"
        font.pixelSize: 18
        color: surface.focusedField === 0 ? root.paperWhite : root.withAlpha(root.paperWhite, 0.35)

        // Selection as a hard-edged stencil block, not a rounded highlight:
        // the glyphs knock out of the accent, matching the angular panels
        // this design is built from.
        selectionColor: root.accentMagenta
        selectedTextColor: "#1C1E26"

        enabled: !session.busy
        focus: true
        onAccepted: surface.submitUsername()
        onActiveFocusChanged: if (activeFocus) surface.focusedField = 0

        Keys.onPressed: event => {
            if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                usernameField.selectAll()
                event.accepted = true
            }
        }

        HoverHandler { cursorShape: Qt.ArrowCursor }

        // 2px magenta tick marking the focused field.
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            anchors.leftMargin: -10
            width: 2
            color: root.accentMagenta
            visible: surface.focusedField === 0
        }
    }
```

- [ ] **Step 4: Adapt the password field**

Keep the existing `TextInput` with `color: "transparent"` and the paint-drip `Repeater`. Change exactly these things:

```qml
        // was: onAccepted: root.tryUnlock()
        onAccepted: surface.submitPassword()

        // was: enabled: !root.unlockInProgress
        enabled: !session.busy

        onActiveFocusChanged: if (activeFocus) surface.focusedField = 1

        Keys.onPressed: event => {
            if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                passwordField.selectAll()
                event.accepted = true
            }
        }
```

and in the drip-dot delegate, make selection visible on dots rather than glyphs:

```qml
                    delegate: Rectangle {
                        id: dot
                        width: 9
                        height: 9
                        radius: 4.5
                        // All dots go magenta when the field is fully
                        // selected - the field renders no glyphs, so a
                        // normal selection rectangle would highlight nothing.
                        color: passwordField.selectedText.length > 0
                            ? root.accentMagenta
                            : (index % 2 === 0 ? root.accentMagenta : root.accentCyan)
                    }
```

and add the cyan selection rule beneath the dot row:

```qml
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.bottom }
                    anchors.topMargin: 4
                    height: 2
                    color: root.accentCyan
                    visible: passwordField.selectedText.length > 0
                }
```

- [ ] **Step 5: Add the power control row**

```qml
    Row {
        id: powerRow
        spacing: 18
        anchors { right: parent.right; bottom: parent.bottom; margins: 32 }

        Repeater {
            model: [
                { label: "suspend", arg: "suspend" },
                { label: "restart", arg: "reboot" },
                { label: "shut down", arg: "poweroff" }
            ]

            delegate: Text {
                text: modelData.label
                color: powerArea.containsMouse ? root.accentAmber : root.withAlpha(root.smokeLavender, 0.65)
                font.family: "Inter"
                font.pixelSize: 14

                Process { id: powerProc; command: [ "@systemctlBin@", modelData.arg ] }

                MouseArea {
                    id: powerArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: powerProc.running = true
                }
            }
        }
    }
```

- [ ] **Step 6: Make the weather element degrade to empty**

Find the temperature `Text` carried over from `LockDark.qml` and confirm it reads an empty string when the `curl` produced nothing. If it currently shows a placeholder or an error string, change it to:

```qml
            text: root.temperature === "" ? "" : root.temperature
            visible: root.temperature !== ""
```

The wifi link may not be associated yet when the greeter starts; an empty slot is correct, an error string is not.

- [ ] **Step 7: Verify it runs against the mock**

Run:

```bash
sed -e "s|@greetdProxyBin@|$(nix build .#greetd-proxy --no-link --print-out-paths)/bin/greetd-proxy|" \
    -e "s|@swayBin@|/run/current-system/sw/bin/sway|" \
    -e "s|@systemctlBin@|$(command -v systemctl)|" \
    modules/qml/GreeterDark.qml > /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/GreeterDark.qml
```

Then hand-substitute the remaining `@token@` colors with the dark palette from `modules/lib/theme-colors.nix` and run:

```bash
quickshell -p /tmp/claude-1000/-home-ogama-nixos-configuration/scratchpad/GreeterDark.qml
```

Expected, checked by eye and by keyboard:
- The surface renders with the Jinx artwork, clock, and date.
- Username field focused on start, containing `ogama`.
- Enter moves to password; the magenta tick follows the focused field; the unfocused field drops to 35% opacity.
- Ctrl+A in username shows the flat magenta stencil block with knocked-out glyphs.
- Ctrl+A in password turns every drip dot magenta and shows the cyan rule.
- Up/Down moves between the fields.
- A wrong password clears the field and returns focus to it.

- [ ] **Step 8: Commit**

```bash
git add modules/qml/GreeterDark.qml
git commit -m "feat(greeter): add the dark greeter surface"
```

---

## Task 9: GreeterLight.qml

The light surface, same behavior, the frosted-glass treatment instead of the stencil one.

**Files:**
- Create: `modules/qml/GreeterLight.qml`
- Read for reference: `modules/home-manager/display/sway/quickshell/components/LockLight.qml`, `modules/qml/GreeterDark.qml`

**Interfaces:**
- Consumes: `GreetdSession` (Task 7).
- Produces: `/etc/greeter/GreeterLight.qml`'s source.

- [ ] **Step 1: Derive the file from LockLight.qml**

```bash
cp modules/home-manager/display/sway/quickshell/components/LockLight.qml modules/qml/GreeterLight.qml
```

Apply the same structural changes listed in Task 8 steps 1 and 2 — remove `PamContext`, MPRIS, the widgets-restart `Process`, and the lock state properties; swap `WlSessionLock`/`WlSessionLockSurface` for the `PanelWindow` wrapper; add the `GreetdSession`, `focusedField`, `submitUsername`, `submitPassword`, the failure `Connections`, and the `Keys.onPressed` arrow handler, all verbatim from Task 8 step 2. Keep the Nausicaa artwork, glass panels, clock, date, and temperature unchanged.

- [ ] **Step 2: Add the username field with the light selection treatment**

```qml
    TextInput {
        id: usernameField
        text: "ogama"
        font.family: "Inter"
        font.pixelSize: 18
        color: "@clockColor@"

        // Frosted band over the text rather than an inversion: the glyphs
        // stay their normal color and a translucent pane sits on top, which
        // is the language the rest of this variant is built in.
        selectionColor: "@glassBg@"
        selectedTextColor: "@clockColor@"

        enabled: !session.busy
        focus: true
        opacity: surface.focusedField === 0 ? 1.0 : 0.55
        onAccepted: surface.submitUsername()
        onActiveFocusChanged: if (activeFocus) surface.focusedField = 0

        Keys.onPressed: event => {
            if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                usernameField.selectAll()
                event.accepted = true
            }
        }

        HoverHandler { cursorShape: Qt.ArrowCursor }

        // Hairline underline marking the focused field.
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.bottom }
            anchors.topMargin: 3
            height: 1
            color: "@tempColor@"
            visible: surface.focusedField === 0
        }
    }
```

- [ ] **Step 3: Adapt the password field**

Apply the same three behavioral changes as Task 8 step 4 (`onAccepted: surface.submitPassword()`, `enabled: !session.busy`, `onActiveFocusChanged`, and the Ctrl+A handler). For the selection treatment, dim and unify the dots under a frosted band:

```qml
                    delegate: Rectangle {
                        width: 9
                        height: 9
                        radius: 4.5
                        color: "@clockColor@"
                        opacity: passwordField.selectedText.length > 0 ? 0.55 : 1.0
                    }
```

```qml
                Rectangle {
                    anchors.fill: dotRow
                    anchors.margins: -4
                    radius: 2
                    color: "@glassBg@"
                    border.width: 1
                    border.color: "@glassBorder@"
                    visible: passwordField.selectedText.length > 0
                    z: -1
                }
```

(`dotRow` is the `id` of the `Row` holding the `Repeater`; add that `id` if `LockLight.qml` does not already have one.)

- [ ] **Step 4: Add the power control row**

Same structure as Task 8 step 5, with the light palette:

```qml
    Row {
        spacing: 18
        anchors { right: parent.right; bottom: parent.bottom; margins: 32 }

        Repeater {
            model: [
                { label: "suspend", arg: "suspend" },
                { label: "restart", arg: "reboot" },
                { label: "shut down", arg: "poweroff" }
            ]

            delegate: Text {
                text: modelData.label
                color: powerArea.containsMouse ? "@tempColor@" : "@dateColor@"
                font.family: "Inter"
                font.pixelSize: 14

                Process { id: powerProc; command: [ "@systemctlBin@", modelData.arg ] }

                MouseArea {
                    id: powerArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: powerProc.running = true
                }
            }
        }
    }
```

- [ ] **Step 5: Verify it runs against the mock**

Repeat Task 8 step 7 with `GreeterLight.qml` and the `light` palette from `modules/lib/theme-colors.nix`.

Expected: the same keyboard behavior, with the frosted selection band and hairline focus underline instead of the stencil block and magenta tick.

- [ ] **Step 6: Commit**

```bash
git add modules/qml/GreeterLight.qml
git commit -m "feat(greeter): add the light greeter surface"
```

---

## Task 10: The NixOS greetd module

**Files:**
- Create: `modules/nixosconf/greetd.nix`
- Modify: `flake.nix` (add `lpkgs`/`upkgs` to `nixosConfigurations.personal.specialArgs`)

**Interfaces:**
- Consumes: `modules/qml/*`, `modules/lib/qml-theme.nix`, `modules/lib/theme-colors.nix`, `lpkgs.greetd-proxy`, `lpkgs.corpta-font`, `lpkgs.orbitron-font`.
- Produces: `/etc/greeter/{GreeterDark.qml,GreeterLight.qml,components/*.qml,sway.conf,launch.sh}` and a configured `services.greetd`.

- [ ] **Step 1: Write the module**

Create `modules/nixosconf/greetd.nix`:

```nix
# Graphical login for the personal profile: greetd runs sway, sway runs a
# Quickshell greeter that mirrors the lockscreen design. See
# docs/superpowers/specs/2026-10-06-quickshell-greeter-design.md
#
# Everything the greeter touches resolves to the Nix store or /etc/greeter.
# The greeter user must never depend on reading /home/ogama.
{ pkgs, lpkgs, upkgs, lib, ... }:

let
  qmlTheme = import ../lib/qml-theme.nix;
  palettes = import ../lib/theme-colors.nix;

  greetdProxy = "${lpkgs.greetd-proxy}/bin/greetd-proxy";
  swayBin = "${pkgs.sway}/bin/sway";
  systemctlBin = "${pkgs.systemd}/bin/systemctl";
  corptaFont = ../../assets/fonts/Corpta-DEMO.otf;

  # The greeter-specific tokens the lock substitution never had to handle.
  withGreeterBins = builtins.replaceStrings
    [ "@greetdProxyBin@" "@swayBin@" ]
    [ greetdProxy swayBin ];

  themeGreeter = variant: image: path:
    withGreeterBins (qmlTheme {
      colors = palettes.${variant};
      laserColor = if variant == "light" then "#FFFFFF" else "#000000";
      lockscreenImage = "${image}";
      systemctlBin = systemctlBin;
      corptaFontPath = "${corptaFont}";
    } (builtins.readFile path));

  sharedComponents = [
    "BeamSide" "GlassPill" "ColorUtils" "ClockModule"
    "CollisionEffects" "RevealMask" "LaserBar" "GreetdSession"
  ];

  componentFiles = lib.listToAttrs (map (name: {
    name = "greeter/components/${name}.qml";
    value.text = themeGreeter "dark" ../../assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg
      (../qml/components + "/${name}.qml");
  }) sharedComponents);

  launcher = pkgs.writeShellScript "greeter-launch" ''
    # If quickshell cannot start, fall back to a text greeter rather than
    # leaving the machine with no way in. This is the primary lockout guard.
    VARIANT=$(${greetdProxy} --theme || echo dark)
    if ! ${upkgs.quickshell}/bin/quickshell \
        -p "/etc/greeter/Greeter''${VARIANT^}.qml"; then
      exec ${pkgs.greetd.greetd}/bin/agreety --cmd ${swayBin}
    fi
  '';

  swayConf = pkgs.writeText "greeter-sway.conf" ''
    # Mirrors modules/home-manager/keyboard.nix so Caps behaves the same at
    # the login screen as it does inside the session.
    input "type:keyboard" {
        xkb_options caps:escape
    }

    exec_always ${launcher}
  '';
in
{
  environment.etc = componentFiles // {
    "greeter/GreeterDark.qml".text =
      themeGreeter "dark" ../../assets/lockscreen/dark-lockscreen-arcane-jinx.jpeg ../qml/GreeterDark.qml;
    "greeter/GreeterLight.qml".text =
      themeGreeter "light" ../../assets/lockscreen/nausicaa.png ../qml/GreeterLight.qml;
    "greeter/sway.conf".source = swayConf;
  };

  # The greeter user cannot see home-manager's font packages.
  fonts.packages = [ lpkgs.corpta-font lpkgs.orbitron-font pkgs.inter ];

  services.greetd = {
    enable = true;
    vt = 1;
    settings.default_session = {
      command = "${swayBin} -c /etc/greeter/sway.conf";
      user = "greeter";
    };
  };

  # Power controls on the greeter surface.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.user == "greeter" &&
          (action.id == "org.freedesktop.login1.power-off" ||
           action.id == "org.freedesktop.login1.reboot" ||
           action.id == "org.freedesktop.login1.suspend")) {
        return polkit.Result.YES;
      }
    });
  '';
}
```

- [ ] **Step 2: Pass `lpkgs` and `upkgs` into the NixOS configuration**

The module above takes `{ pkgs, lpkgs, upkgs, lib, ... }`, but `nixosConfigurations.personal` currently receives only `cfg`:

```nix
        personal = lib.nixosSystem {
          inherit pkgs;
          specialArgs = {
            cfg = cfg-perso;
          };
          modules = [ ./host/personal/configuration.nix ];
        };
```

`lpkgs` and `upkgs` are today passed only to the home-manager configurations (`flake.nix:100-101`). Without this change the module fails to evaluate with `called without required argument 'lpkgs'`. In `flake.nix`, change that block to:

```nix
        personal = lib.nixosSystem {
          inherit pkgs;
          specialArgs = {
            cfg = cfg-perso;
            inherit lpkgs upkgs;
          };
          modules = [ ./host/personal/configuration.nix ];
        };
```

Leave `nixosConfigurations.oserv` alone — it does not import this module and does not need them.

Verify nothing else broke:

```bash
nix flake check
```

- [ ] **Step 3: Verify the component list matches reality**

Run:

```bash
ls modules/qml/components/
```

Expected: exactly the eight names in `sharedComponents`. If `GreeterDark.qml` imports a component not in that list, the greeter will fail to load at boot with no diagnostic on screen. Cross-check:

```bash
grep -oE '^\s*(BeamSide|GlassPill|ColorUtils|ClockModule|CollisionEffects|RevealMask|LaserBar|GreetdSession|[A-Z][A-Za-z]+)\s*\{' modules/qml/GreeterDark.qml | sort -u
```

Every custom (non-Qt, non-Quickshell) type in that output must be in `sharedComponents`.

- [ ] **Step 4: Verify the module evaluates**

Run:

```bash
nix flake check
```

Expected: clean. Note the module is not yet imported anywhere, so this only proves it parses; Task 11 proves it evaluates in context.

- [ ] **Step 5: Commit**

```bash
git add modules/nixosconf/greetd.nix flake.nix
git commit -m "feat(greeter): add the NixOS greetd module"
```

---

## Task 11: Wire it into the personal host and validate on hardware

The only task that can lock the user out. Every step here is reversible until the final one.

**Files:**
- Modify: `host/personal/configuration.nix`

**Interfaces:**
- Consumes: everything above.
- Produces: a working graphical login.

- [ ] **Step 1: Import the module**

In `host/personal/configuration.nix`, add to the `imports` list, after `../../modules/nixosconf/gtklock`:

```nix
    ../../modules/nixosconf/greetd.nix
```

- [ ] **Step 2: Verify the whole system builds**

Run:

```bash
nix flake check
nixos-rebuild build --flake .#personal
```

Expected: both succeed. Do not proceed until they do.

- [ ] **Step 3: Verify the generated greeter QML has no unsubstituted tokens**

Run:

```bash
SYS=$(nixos-rebuild build --flake .#personal --no-link --print-out-paths 2>/dev/null || echo ./result)
grep -n '@[a-zA-Z]*@' $SYS/etc/greeter/*.qml $SYS/etc/greeter/components/*.qml
```

Expected: no output. A surviving `@token@` is a greeter that renders with a literal string where a color or a binary path should be, and it will not be obvious on screen.

- [ ] **Step 4: Verify the fallback path exists**

Run:

```bash
grep -n "agreety" $SYS/etc/greeter/sway.conf $(grep -oE '/nix/store/\S+greeter-launch' $SYS/etc/greeter/sway.conf)
```

Expected: the launcher script contains the `agreety` exec. This is the guard that makes the next step safe.

- [ ] **Step 5: Apply with `test`, not `switch`**

Ask the user to run:

```bash
sudo nixos-rebuild test --flake .#personal
```

`test` activates without touching the bootloader, so a reboot reverts to the current working configuration. Do not run this yourself without asking.

- [ ] **Step 6: Verify on a spare VT first**

Before logging out, from the running session:

```bash
systemctl status greetd
journalctl -u greetd -n 50 --no-pager
```

Expected: `greetd` active, no quickshell errors in the log.

- [ ] **Step 7: Verify the real login**

Ask the user to switch to VT1 (Ctrl+Alt+F1) and confirm:
- The greeter renders in the variant matching the time of day.
- Username pre-filled, Enter moves to password, Enter logs in, sway starts.
- A wrong password clears the field and refocuses it.
- Ctrl+A and Up/Down behave as designed.
- Ctrl+Alt+F2 still gives a plain getty (the lockout escape hatch).

- [ ] **Step 8: Make it permanent**

Only after step 7 passes completely, ask the user whether to run:

```bash
sudo nixos-rebuild switch --flake .#personal
```

Never run this without explicit confirmation.

- [ ] **Step 9: Commit**

```bash
git add host/personal/configuration.nix
git commit -m "feat(personal): use the Quickshell greeter for login"
```
