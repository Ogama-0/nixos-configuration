# Session lock robustness — design

2026-11-23 · medium change · `modules/features/desktop/laserbar/`, `modules/features/desktop/sway-idle.nix`

## Intent and why

Closing the lid sometimes gives back a solid red screen that takes no input.
Keyboard does nothing, mouse does nothing, no password prompt. The only way
out is holding the power button.

That red screen is not a GPU fault or a crashed compositor. It is sway doing
exactly what `ext-session-lock-v1` tells it to. The protocol says that if the
lock client dies while the session is locked, the compositor **must not**
unlock in response — the whole point is that killing the lock screen cannot be
a way past it. sway's policy for that state is to leave its lock-output
background up, which is a solid red rect, and keep refusing input. The lock is
"abandoned": nothing is left to authenticate against.

So the red screen is a symptom with exactly one cause — *the process holding
the lock died while it held it* — and the work is to enumerate the ways that
happens here and close them.

The reason it felt random is in the journal. On 2026-11-23 the lid closed at
08:08 (dark mode) and opened at 09:18, and darkman decided the mode had
changed to light while the machine slept:

```
08:08:50  Lid closed → before-sleep → quickshell ipc -c widgets call lock lock
09:18:11  Lid opened, PM: suspend exit
09:18:11  darkman: "Wanted mode is: light mode"
09:18:11  darkman: Running quickshell-theme
09:18:11  systemd: Stopping Quickshell desktop widgets...      ← kills the lock client
09:18:32  greetd.service: Deactivated                          ← power-button reboot
```

Every resume that *worked* that day — 13:44, 14:05, 16:50, 18:01 — has no
darkman line at all, because darkman only re-runs its scripts when the mode
actually changed. Resume inside the same mode: fine. Resume across sunrise or
sundown: locked out. That is the "sometimes".

## Goals

- A dark/light transition must never be able to strand the session behind an
  abandoned lock.
- A crash anywhere in the shell must cost at most the bar, never the ability
  to get back into the machine.
- Closing the lid must keep locking, whatever else is switched off.

## Non-goals

- Fixing the upstream quickshell bugs. They are real and they are listed
  below, but they are fixed on master and unreleased; this repo's job is to
  stop walking into them.
- Replacing the lock screen with swaylock. The quickshell lock is the design;
  swaylock stays only as the hand-bound `Mod+Shift+Escape` escape hatch.

## Anti-goals

- Any "recovery" that can be triggered from outside the lock. A path that
  clears an abandoned lock without a password is a path past the lock screen.
  The red screen is infuriating and it is also the protocol working.
- Making `before-sleep` conditional on anything a toggle can switch off. A lid
  that suspends to an unlocked desktop is a worse bug than the one being fixed.

## The three ways the lock client dies

**1. darkman restarts it.** `modules/features/desktop/darkman.nix` ends both
theme scripts with `systemctl --user restart quickshell-widgets.service`, and
`quickshell-widgets` is the process hosting `WlSessionLock`. This is the one
that actually bit, repeatedly, and the only one that is purely self-inflicted.

**2. pipewire takes it down.** pipewire's `module-x11-bell` segfaults the whole
audio daemon whenever Xwayland goes away — Xlib calls its I/O error handler
twice and the second call destroys an already-removed event source:

```
#0  loop_destroy_source        (libspa-support.so + 0x8cac)
#1  x11_io_error_exit_handler  (libpipewire-module-x11-bell.so + 0x2ad2)
#5  display_io                 (libpipewire-module-x11-bell.so + 0x25e9)
```

quickshell holds pipewire objects for the bar's audio pane and goes down with
it (quickshell-mirror/quickshell#1435, "SIGSEGV on resume from suspend during
PipeWire object teardown"). On 2026-11-23 this fired at 09:18:33, immediately
after cause 1, which is why that incident ended with
`Quickshell crashed within 10 seconds of launching. Not restarting to avoid a
crash loop` — nothing left on screen at all.

**3. quickshell 0.3.2 crashes when outputs vanish under an active lock.**
quickshell-mirror/quickshell#1155 and #1401: suspend/resume, DPMS and monitor
hotplug all produce `There are no outputs - creating placeholder screen`
followed by a fatal Wayland error. Commit `afb2c27c` (2026-08-25) fixes it and
landed four days after the 0.3.1 tag, so no release contains it. #1054 is the
follow-on: a restarted instance that tries to re-lock over the orphan aborts
with `Tried to show lockscreen surfaces without active lock`, and the pattern
that triggers it — setting `locked = true` imperatively from an IPC call
rather than as an initial binding — is exactly what `LockDark.qml`'s
`IpcHandler` does.

## Done

**Cause 1 — darkman asks before it restarts.** `LockDark.qml` and
`LockLight.qml` gained `function isLocked(): bool` on the existing `lock` IPC
target, returning `locked || unlocking` (the fade still has a surface up).
darkman's `quickshellTheme` helper relinks the tree unconditionally — that only
affects the next start — and restarts only on an exact `false`:

```sh
if [ "$(quickshell ipc -c widgets call lock isLocked 2>/dev/null)" = "false" ]; then
  systemctl --user restart quickshell-widgets.service || true
fi
```

Fail closed. A dead shell, a timed-out IPC or any unexpected output leaves the
restart undone, which costs a stale palette until the next transition; the
other way costs a reboot. Nothing is lost by skipping, because the lock already
restarts the shell itself 500ms after a successful unlock
(`postUnlockRestart`), and that pass picks up the newly-linked tree.

**Cause 2 — the x11 bell module is off.**
`modules/features/system/pipewire-x11-bell.nix` sets
`module.x11.bell = false`, pipewire's own documented knob. The module only
plays the X11 bell through libcanberra, which nothing here uses.

**Fewer chances to be locked while vulnerable.** `sway-idle.nix` had a
two-stage idle lock — swaylock at 3min, `pkill -x swaylock` then quickshell at
5min. Two lock clients in sequence, with the first killed while it holds the
lock, is the abandoned-lock shape on purpose. It is now one client, one stage.

## Still open

**Cause 3 needs the lock in its own process.** Today the lock shares one
quickshell instance with the clock, wallpaper, laser bar, notification panel,
messages pane, weather and pipewire/MPRIS. Any fault in any of those — the
`ConversationView` binding loop fires several times a day — is a potential
lockout, and `Restart=on-failure` cannot help because a fresh instance hits
#1054 trying to take the orphan over.

The shape: a second config (`quickshell -c lock`) under its own
`quickshell-lock.service` that darkman never touches and that imports none of
the bar. `before-sleep` and `Mod+Escape` retarget to `ipc -c lock`. The theme
tree still gets relinked for it, but its restart waits for an unlock, the same
rule the widgets side now follows. That reduces cause 3 from "lockout" to "the
lock screen flickers", because the only thing in the process is the lock.

Upgrading quickshell past `afb2c27c` would address cause 3 directly, but needs
a master build via overlay — worth doing only after the split, which is what
makes the remaining exposure survivable.

## How it was checked

- `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath` and
  the NixOS toplevel, with every new file `git add`ed — `nix flake check` only
  shallow-checks `homeConfigurations` and never forces the generated QML text.
- The generated `Lock.qml` contains `isLocked`, and no `@token@` survives in
  any generated panel component.
- The built pipewire drop-in is
  `/etc/pipewire/pipewire.conf.d/99-disable-x11-bell.conf` containing
  `"module.x11.bell": false`.
- swayidle's rendered `ExecStart` carries guarded `timeout` commands and an
  **unguarded** `before-sleep`.

A real suspend/resume across a sunrise boundary is the only end-to-end proof,
and it cannot be forced from a build — the next such resume is the test.
