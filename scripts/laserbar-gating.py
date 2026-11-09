#!/usr/bin/env python3
"""Assert that nothing in the control panel polls while the panel is shut.

Rule 1 of docs/adding-a-bar-widget.md, enforced rather than remembered. The
panel runs khal, df, curl, geoclue, nmcli, bluetoothctl and powerprofilesctl;
it is closed almost all of the time, and a repeating Timer that forgot its
`running:` is invisible until you go looking at CPU.

Checks the GENERATED tree, not the source, so a @token@ that expanded wrong
is caught too.

  python3 scripts/laserbar-gating.py          # exit 1 if anything is ungated

A repeating Timer must have `running:` bound to `active` or `isOpen`, either
directly or through one `property bool` in the same file - MusicWidget's
`running: root.running` is `active && hasPlayer` one line up, and reading only
the literal binding called it ungated.

A Timer repeats only when it says `repeat: true`. QML's own default is false,
so a Timer that simply omits the property is a one-shot and is skipped. This
used to look for a literal `repeat: false` and flagged every one-shot that
relied on the default - which is most of them.

Covers the bar as well as the panel. Rule 1's founding story is the desktop
clock's 1Hz tick re-rendering an FBO nobody could see, and that is a bar file;
checking only `/panel/` left every widget on the beam unexamined.

The always-on surfaces are exempt by name, each for a stated reason: a
standalone desktop widget that only updated while you were looking at it would
be showing you the past.
"""
import json
import re
import subprocess
import sys

EXEMPT_FILES = {
    # A notification centre that only listened while you were looking at it
    # would be a list of things you had already seen.
    "NotificationServer.qml",
    # Toasts exist precisely to appear when the panel is shut. The sweep is
    # gated on there being a toast up, which is the real bound.
    "NotificationToasts.qml",
    # The same thing for texts, and for the same reason - a toast for a
    # message that arrived while the panel was shut is the entire point.
    "MessageToasts.qml",
    # The voice-note progress tick. Gated on something actually sounding
    # (`playingId !== "" && !paused`), which is the real bound: every path
    # out of Messages routes through ControlPanel.closeMessages(), and that
    # is the one place audio.stop() is called.
    "MessageAudio.qml",
    # ---- always-on desktop surfaces, not panel or bar zones ----
    # These are their own layer-shell windows, on screen whenever the
    # desktop is. There is no "shut" for them to be quiet during; gating
    # them on `active` would mean a clock that stops when unobserved.
    "Clock.qml",          # the desktop clock: shows seconds
    "Calendar.qml",       # the desktop diary card
    "Music.qml",          # the desktop music card
    "Wallpaper.qml",
    "StatusModel.qml",    # backs StatusPanel, an ambient server-status widget
    # The lock surface, gated on `locked` - which is the same shape as
    # `active` for something that only exists while the screen is locked.
    "LockDark.qml",
    "LockLight.qml",
    # Driven from shell.qml (`running: mpris.remote && mpris.playing`), so
    # its own binding is a plain property with no gate to find here.
    "RemoteSpectrum.qml",
}

APPLY = (
    'cf: let ns = builtins.filter (n: builtins.match '
    '"quickshell/widgets-dark/components/(panel/)?.*qml" n != null) '
    '(builtins.attrNames cf); in builtins.listToAttrs '
    '(map (n: { name = n; value = cf.${n}.text; }) ns)'
)


GATE = re.compile(r"\b(active|isOpen|locked)\b")


def gated(expr, props):
    """Does this `running:` expression reach a gate, directly or via one
    `property bool` declared in the same file?"""
    if GATE.search(expr):
        return True
    for ident in set(re.findall(r"\b([a-z][A-Za-z0-9_]*)\b", expr)):
        if ident in props and GATE.search(props[ident]):
            return True
    return False


def main():
    proc = subprocess.run(
        ["nix", "eval", "--json",
         ".#homeConfigurations.personal.config.xdg.configFile",
         "--apply", APPLY],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        print(proc.stderr.strip()[-500:], file=sys.stderr)
        return 2

    findings = []
    inspected = 0
    for name, text in json.loads(proc.stdout).items():
        base = name.split("/")[-1]
        if base in EXEMPT_FILES:
            continue
        # One level of indirection: `property bool running: root.active && ...`
        props = dict(re.findall(
            r"property\s+bool\s+([A-Za-z0-9_]+)\s*:\s*(.+)", text))
        for match in re.finditer(r"Timer\s*\{(.*?)\n\s*\}", text, re.S):
            body = match.group(1)
            # QML's own default. A Timer that does not say `repeat: true`
            # fires once and cannot poll.
            if not re.search(r"repeat:\s*true", body):
                continue
            inspected += 1
            running = re.search(r"running:\s*(.+)", body)
            if not running:
                findings.append((base, "repeating Timer with no running:"))
            elif not gated(running.group(1), props):
                findings.append((base, "running: " + running.group(1).strip()))

    print(f"repeating timers inspected: {inspected}")
    for base, why in findings:
        print(f"  UNGATED  {base}: {why}")
    if findings:
        return 1
    print("every repeating panel timer is gated on the panel being open")
    return 0


if __name__ == "__main__":
    sys.exit(main())
