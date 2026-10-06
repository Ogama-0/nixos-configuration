#!/usr/bin/env python3
"""stdio <-> greetd IPC bridge and dark/light variant picker for the
Quickshell greeter.

Two unrelated-looking jobs live in one script on purpose: the greeter needs
exactly one extra executable on the system, and both jobs are a handful of
stdlib calls. See docs/superpowers/specs/2026-10-06-quickshell-greeter-design.md
"""

import datetime
import math
import os

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
