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

## The other half: logic fixtures

Pixels cannot answer every question. Whether `normalize()` folds
`+33 6 76 72 48 57` onto `076-724-8570` can only be seen on screen by drawing
the answer as text and probing a glyph, which asserts on the font as much as
on the code.

Quickshell runs under `QT_QPA_PLATFORM=offscreen` and `console.log` reaches
stdout, so a fixture can simply say what it found:

    scripts/qml-logic-test.sh tests/laserbar/<fixture>.qml <SENTINEL>

The fixture prints the sentinel only when every case passed. The runner kills
quickshell the moment it appears, so a green run costs a fraction of a second;
a fixture that never prints costs the full timeout, which is the right way
round — failure is the slow path.

On failure the whole captured output is printed. A fixture that failed to load
prints no sentinel either, and that output is where the QML import error is.
