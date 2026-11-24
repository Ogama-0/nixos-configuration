# Greeter output race, and the fallback that does not work — design

2026-11-23 · small change · `modules/features/desktop/greeter.nix`

## Intent and why

On 2026-11-22 the machine booted to a greeter that never appeared. greetd sat
there for five and a half minutes and then logged:

```
18:09:23  Started greetd.service
18:09:29  pam_unix(greetd:session): session opened for user greeter
18:15:05  error: check_children: greeter exited without creating a session
```

`/tmp/greeter-quickshell.log` has the cause, from the `debugTrace` run that
was on at the time:

```
INFO: Configuration Loaded
INFO qt.qpa.wayland: There are no outputs - creating placeholder screen
wl_registry#2: error 0: global wl_output (60) is unavailable
WARN: The Wayland connection experienced a fatal error: Protocol error
```

`greeter.nix` launches quickshell from sway's `exec_always`, which runs as soon
as sway reads its config — before the eDP output is enabled. Qt sees zero
outputs, invents a placeholder screen, and the bare `PanelWindow` in
`GreeterDark.qml` binds to it. When the real output arrives the placeholder's
`wl_output` global is already gone, the compositor sends a protocol error, and
quickshell is killed.

This is the same zero-output fragility as
quickshell-mirror/quickshell#1155/#1401 — see
`2026-11-23-session-lock-robustness.md`, cause 3 — reached from the other end:
not an output disappearing under a running surface, but a surface created
before any output exists.

Then the guard failed too. `greeter.nix` falls back to
`agreety --cmd sway` when quickshell exits without requesting a session, which
is the right trigger. But the fallback is `exec`'d from *inside* sway, so
agreety writes its prompt to a VT that sway is holding in graphical mode.
It is running; it is invisible. That is the five minutes.

## Goals

- quickshell must not start until sway has a real output to put it on.
- If quickshell dies anyway, the text fallback has to be *visible* — the whole
  point of it is being the last way in.

## Non-goals

- Making `PanelWindow` resilient to screens coming and going. That is the
  upstream fix (`afb2c27c`, unreleased); this is about not provoking it.
- Touching the authentication path. The `debugTrace` logs from 2026-11-22/23
  show `create_session → auth_message → response → success → start_session`
  behaving correctly every time, including the "first login is always
  rejected" case that trace was added for. That investigation is closed.

## Anti-goals

- A fixed `sleep` before launching quickshell. It is a guess that is either
  too short on a cold boot or wasted on every warm one, and it turns a
  deterministic condition into a flaky one.
- Any fallback that bypasses PAM. The greeter not drawing is an inconvenience;
  a greeter that lets someone in without a password is not.

## Shape

**Wait for an output.** In the `greeter-launch` script, poll
`swaymsg -t get_outputs` until it reports at least one active output, with a
bounded number of attempts, before `exec`ing quickshell. sway's own IPC is the
authority on when its output is up, and the bound keeps a genuinely
headless boot from hanging forever instead of reaching the fallback.

**Make the fallback visible.** Two candidates, in preference order:

1. Run agreety on a VT sway is not holding — `chvt` to a free VT and start it
   there — so the text lands on a console that is actually on screen.
2. Run it inside a terminal emulator under sway (`foot -e agreety ...`), which
   keeps everything on VT1 at the cost of pulling a terminal into the greeter's
   closure.

(1) is closer to what the fallback is *for*: it should work when the graphical
path is the thing that is broken, which argues against depending on sway still
being healthy enough to map a window.

Ctrl+Alt+F2 remains a plain getty either way — `services.greetd` sets no `vt`,
so current nixpkgs pins greetd to VT1 and leaves the rest alone. That is the
last-resort route in and it is already correct.

## Smaller things the same logs turned up

- `Fontconfig error: No writable cache directories` and
  `Failed to create /var/empty/.cache for shader cache`, repeatedly. The
  greeter user's home is `/var/empty`. Cosmetic, but it is most of the log
  volume, and it costs a font-cache rebuild on every greeter start.
- `Failed to register with host portal ... App info not found for
  'org.quickshell'`. Harmless; the greeter has no portal to talk to.
- One `error: a session is already scheduled`, from Enter arriving twice.
  `GreetdSession.qml`'s `session.busy` guard caught it and the login proceeded;
  no change needed, recorded so the next reader of that log does not chase it.

## Status

Not implemented. `debugTrace` has been turned back off in `greeter.nix` now
that it has answered the question it was added for — turn it back on while
working this, because the greeter surface has nowhere else to log.
