#!/usr/bin/env python3
"""Assert that nothing in the control panel polls while the panel is shut.

Rule 1 of docs/adding-a-bar-widget.md, enforced rather than remembered. The
panel runs khal, df, curl, geoclue, nmcli, bluetoothctl and powerprofilesctl;
it is closed almost all of the time, and a repeating Timer that forgot its
`running:` is invisible until you go looking at CPU.

Checks the GENERATED tree, not the source, so a @token@ that expanded wrong
is caught too.

  python3 scripts/laserbar-gating.py          # exit 1 if anything is ungated

A repeating Timer must have `running:` bound to `active` or `isOpen`. A
one-shot (`repeat: false`) is exempt: it cannot poll, and the panel uses one
to hold the window open while the dismiss animation finishes.

NotificationServer is exempt by name and on purpose: a notification centre
that only listened while you were looking at it would be a list of things you
had already seen.
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
}

APPLY = (
    'cf: let ns = builtins.filter (n: builtins.match '
    '"quickshell/widgets-dark/components/(panel/)?.*qml" n != null) '
    '(builtins.attrNames cf); in builtins.listToAttrs '
    '(map (n: { name = n; value = cf.${n}.text; }) ns)'
)


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
        if "/panel/" not in name and base != "ControlPanel.qml":
            continue
        for match in re.finditer(r"Timer\s*\{(.*?)\n\s*\}", text, re.S):
            body = match.group(1)
            inspected += 1
            if re.search(r"repeat:\s*false", body):
                continue
            running = re.search(r"running:\s*(.+)", body)
            if not running:
                findings.append((base, "repeating Timer with no running:"))
            elif not re.search(r"\b(active|isOpen)\b", running.group(1)):
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
