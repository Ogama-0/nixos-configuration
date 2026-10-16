# Laser bar render fixtures

This repo has no unit-test framework. The laser bar is verified instead by
rendering it for real and asserting on pixels:

    scripts/laserbar-preview.sh tests/laserbar/<fixture>.qml /tmp/out.png [battery]
    scripts/laserbar-probe.sh /tmp/out.png <x> <y> <w> <h> --dominant g 18

`laserbar-preview.sh` evaluates the themed `widgets-dark` tree out of the
**working tree** with `nix eval` (not the installed `~/.config` copy, which is
whatever the last home-manager switch produced), drops the fixture in as
`shell.qml`, runs nested sway on the wlroots headless backend, reveals the bar
over its IPC, and screenshots with `grim`.

Each fixture instantiates as little as possible, so a probe failure points at
one component.

Battery is pinned through `LASERBAR_FAKE_BATTERY` so the beams always collide
at the same x; without it the collision moves with the real charge and every
probe becomes machine-dependent.
