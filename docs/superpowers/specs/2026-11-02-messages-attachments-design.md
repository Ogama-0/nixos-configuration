# Messages attachments — playing and viewing — design

Date: 2026-11-02
Builds on `docs/superpowers/specs/2026-10-25-messages-panel-design.md`.
Field reference: `docs/kdeconnect-sms-payload.md`. Subsystem notes:
`docs/messages-panel.md`.

## Intent

Attachments arrive in the pane and stop there. A photo renders as a thumbnail
in its bubble and a voice note renders as the words "Voice message" — and
neither does anything when clicked. The complaint was precise: *"I would like
to be able to click on audio msg to hear them and pictures to see them,
escape to go out of the pic."*

So: clicking a voice note plays it in place, and clicking a photo opens it
full inside the panel as a layer over Messages, with Escape unwinding one
layer at a time.

It is not a media player bolted onto the panel. It is the same surface, the
same material, the same expansion gesture Messages already uses over the
control panel, themed from the same `palette.nix`.

## Goals

- Click a voice note to play it, in the bubble, without anything else opening.
- A progress bar you can scrub, elapsed time, and ±5s on the arrow keys.
- Click a photo to see it full inside the panel, with the panel's own
  expansion animation.
- `Escape` leaves the picture and returns to Messages — one layer, not all of
  them.
- An attachment that has not been downloaded yet is fetched on the click that
  wants it, not on a second one.
- Dark and light, from the one palette, like everything else.

## Non-goals

- **No waveform.** Explicitly rejected: *"i don't care about the wave form i
  think it will be overkill."* A plain bar, no decode pass, no cached peaks.
- **No zoom, pan, rotate, save, or next/previous in the viewer.** The user
  screenshots with their normal tool and leaves. Asked directly what else the
  viewer should do: *"screen shot but that's all."*
- **No video playback.** `video/*` attachments keep the existing labelled
  recess. MMS video is rare on this phone and a video surface is a different
  piece of work.
- **No playback queue, no continue-to-next, no speed control.**
- **Nothing new in the toasts.** A toast keeps showing "Voice message" or
  "Photo" as its preview. Playing out of a surface that disappears on a timer
  is its own design problem.
- **No second media backend.** If QtMultimedia cannot be reached, this
  feature does not ship; it does not fall back to spawning `mpv`.

## Anti-goals

Things that would make this a failure even if it technically worked:

- **Taking down the shell.** Importing `QtMultimedia` into a quickshell that
  cannot resolve it is not a broken widget, it is a dead config: no bar, no
  panel, no lock screen. This is a real, documented failure mode (see
  Constraints) and the single biggest risk in the work.
- **A panel that holds audio hostage.** Dismissing the panel must stop
  playback. A voice note still playing out of an invisible surface, with no
  way to reach the pause button, is worse than not playing it at all.
- **Escape that overshoots.** If Escape closes the picture *and* Messages, or
  dismisses the whole panel, the layer was not worth adding.
- **A second copy of the player per monitor.** `MessagesCore` exists because
  the first version of the pane instantiated its models once per screen. A
  `MediaPlayer` inside the pane would do the same thing, and two of them
  would play the same voice note twice, slightly out of sync.

## Constraints

**QtMultimedia is not in quickshell's import path.** quickshell is built with
its QML import path baked in — qtdeclarative, qtwayland, qtbase — and nothing
else. Importing `QtMultimedia` from a shell component fails the whole
configuration, not the component. The same problem, on another NixOS config,
is written up at <https://github.com/olafkfreund/nixos_config/issues/1915>;
the fix there and here is to wrap the binary with `--prefix QML_IMPORT_PATH`
(and `QT_PLUGIN_PATH`, for the ffmpeg media backend) pointing at
`qt6.qtmultimedia`.

**The versions have to match.** The running quickshell comes from the
`quickshell` flake input, which follows `nixpkgs-unstable`, and is built
against Qt 6.12.0. `pkgs.qt6.qtmultimedia` from the repo's default nixpkgs is
6.11.2 and is the wrong one. The right one is
`inputs.nixpkgs-unstable.legacyPackages.${system}.qt6.qtmultimedia`, which is
6.12.0.

**Verified by spike, not assumed.** A throwaway widget, run against the real
wrapped environment and one of the user's own voice notes:

```
duration = 22812   seekable = true   error = 0
state=1  pos=900 → 1800 → 2700        (real time, 40ms granularity)
seeked +5s -> 7700                     (instant, exact)
```

So: QtMultimedia loads, ffmpeg decodes AMR-NB, duration is known, seeking is
exact, and `position` updates often enough for a bar that moves smoothly.

**The filename contains a literal percent-escape.** Voice notes are saved as
`PART_1793468251539_Audio%20Mes1.amr` — the `%20` is part of the name on
disk, not an encoding of a space. A `file://` URL for it must encode the `%`
itself (`%2520`) or the file is simply not found. This bit the spike and will
bite the implementation.

**Attachments are three states, not two** (already documented in
`docs/messages-panel.md`): images usually arrive with their bytes inline as
base64 and need no fetch at all; everything else needs
`requestAttachmentFile(partID, uniqueIdentifier)` and arrives later on
`attachmentReceived`, whose `fileName` is the `uniqueIdentifier`.
`MessageStore.attachment_files` already keys on that and `messages()` already
fills the path in.

**A `MediaPlayer` cannot play base64.** Inline bytes are enough to *render* an
image (`data:` URI) but not to play audio. Audio always needs the file on
disk, so a voice note always needs the fetch.

**Messages holds the keyboard exclusively**, and sway's `modes.panel` is left
while it is up (see the focus section of `docs/messages-panel.md`). The
viewer inherits that: it is inside the same surface, so it needs no new focus
mechanism, only a place earlier in the Escape chain.

## The shape of it

Three new pieces and one wrapper change.

```
MessagesCore                     (exists)
└── MessageAudio                 NEW. One player for the shell. Non-visual.

ConversationView                 (exists)
└── VoiceBubble                  NEW. Play/pause, bar, elapsed. Per message.

ControlPanel                     (exists)
└── PictureViewer                NEW. Third expansion layer over Messages.
```

**`MessageAudio` is instantiated once, inside `MessagesCore`**, for the same
reason everything else there is: the pane lives inside a `Variants` over
`Quickshell.screens`. It owns the `MediaPlayer`, the `AudioOutput`, and
`playingId` — the message id of whatever is playing, or `""`. A `VoiceBubble`
is a view: it reads `core.audio.playingId === myId` and renders accordingly.
That also gives "only one voice note at a time" for free, since starting one
sets `playingId` and the previous bubble stops being the playing one.

## The voice bubble

Layout, chosen from three mocked options — play, bar, time, one row:

```
┌──────────────────────────────────┐
│  (▶)  ──────●──────────────  0:07 │
└──────────────────────────────────┘
```

- **Click the bubble** (anywhere not on the bar) toggles play/pause. Clicking
  a different voice note stops this one and starts that one.
- **Click or drag the bar** seeks to that point. *Builder's note: this is the
  designer's call, not the user's request — the handle implies it, and
  `seek(duration * mouse.x / width)` is one line.*
- **Elapsed time** while playing or paused; **total duration** before it has
  been played at all, which is the more useful number when deciding whether
  to listen.
- **No skip buttons.** The ±5s live on the arrow keys (below). Rejected
  layouts: skips flanking the bar in one row (bar too narrow to scrub), and a
  two-row bubble with the controls underneath (too tall next to text).
- **Not yet downloaded:** the first click fetches and plays when it lands.
  The bubble says so in the meantime. *Builder's note: also the designer's
  call — the alternative is clicking once to fetch and again to play.*
- **The file never arrives:** the bubble goes back to being clickable and
  says the phone did not send it. It does not spin forever.

Drawn shapes, not emoji, for the play/pause glyph: the mockup used ⏯︎-class
characters and the font rendered them as colour emoji, orange, against the
accent fill.

## The picture viewer

A layer over Messages, mocked and chosen with the meta strip:

```
┌─────────────────────┐
│                     │
│      [ photo ]      │
│                     │
├─────────────────────┤
│ Krikri · 16:41   Esc│
└─────────────────────┘
```

- Fills the panel, `PreserveAspectFit`, on the panel's own sheet.
- A 44px strip at the foot: sender and time at the left, "Esc to close" at the
  right, in the muted ink.
- Opens with the panel's expansion animation, growing from the bubble that
  was clicked — the same mechanism `ControlPanel.messagesOrigin` already uses
  to grow Messages from the mobile zone or from a toast. The origin rect has
  to be mapped out of the bubble, which sits in a delegate inside a flipped
  `ListView` inside the pane: `mapToItem` against whatever item the layer's
  geometry is expressed in, not the delegate's own `x`/`y`.
- Source is the same three-state resolution the bubble uses: the inline
  `data:` URI if the bytes came with the message, the fetched file if not,
  and a fetch if neither.

## The keyboard

One new rule, and one new link in a chain that exists.

| | |
|---|---|
| `Escape` | closes the picture and returns to Messages. Only then does a second Escape collapse Messages, and a third dismiss the panel. |
| `←` `→` **while a voice note is playing, and the compose field does not have focus** | −5s / +5s. The user's words: *"yes borrow it."* |
| `←` `→` otherwise | unchanged — out to search, into compose, as documented. |

**The compose exception is the designer's call, not the user's.** The borrow
as stated would have taken the cursor keys away mid-draft: the pane's
existing rule is that in a draft the left arrow *is* the cursor, and only an
empty field sends it back to the list. A voice note playing while you type a
reply is an ordinary thing to do, and silently moving the playhead instead of
the caret would be a bug in every reading. So the borrow applies everywhere
the compose field is not focused — which is where you are when you are
listening.

The borrow is deliberately scoped to *playing*, not to "a voice note is
selected": the pane has no notion of a selected bubble and inventing one for
this is a bigger change than the feature. Pausing or finishing hands the keys
straight back.

**Screenshotting works and needs nothing.** `ControlPanel.syncSwayMode`
already leaves `modes.panel` while Messages is up, so sway is in its default
mode and the user's own screenshot binding is live; a compositor binding is
handled before the key reaches the focused surface, exclusive keyboard focus
or not. Nothing in this work should touch that.

## Dismissal

Dismissing the panel, collapsing Messages, or switching conversation stops
playback. The viewer closes with the panel too — there is no state worth
restoring, and reopening into a photo you have forgotten about is worse than
reopening into the thread.

## Testing

The two harnesses, as in `docs/messages-panel.md`, plus one new problem:
**audio cannot be asserted from a render or a pixel probe.**

- **Logic** (`scripts/qml-logic-test.sh`): a `messages-audio` fixture over
  `MessageAudio` with the transport stubbed — seek clamping at both ends,
  `mm:ss` formatting across a minute boundary, one-at-a-time replacement of
  `playingId`, the arrow-key borrow going back when playback stops, and the
  fetch-then-play state machine including the file that never arrives.
- **Render** (`scripts/laserbar-preview.sh` + `laserbar-probe.sh`): a
  `messages-voice` fixture for the bubble at idle / playing / fetching, and
  `messages-viewer` for the layer, **both variants** — the bubble draws on the
  accent fill when outgoing and on the plate when incoming, and that is
  exactly the polarity trap that has bitten this panel three times.
- **The real shell** (`laserbar-preview.sh real`) is the check that matters
  most here, because the import-path change is global: if it is wrong, this
  is what says so, and it says so before the switch rather than after.
- **The spike is not a test.** It proved the backend decodes AMR; nothing in
  CI will ever play a sound. The fixture asserts the state machine around the
  player, and the player itself is trusted.

## What is left to the builder

- Where exactly the wrapper lives (the quickshell home-manager module's
  package definition vs. a `symlinkJoin` wrapper in `pkgs/`), and how the
  `nixpkgs-unstable` qtmultimedia is threaded through to it — `flake.nix`
  already builds `lpkgs`/`upkgs` sets and already has the input.
- Whether `MessageAudio` polls `position` or binds it, and at what rate the
  bar is redrawn. The measured granularity is 40ms; the bar does not need
  every tick, and this panel has prior scar tissue about doing work per frame.
- The exact easing and duration of the viewer's expansion — match whatever
  Messages already does rather than inventing a second feel.
- Whether the viewer is a sibling layer in `ControlPanel` or a child of the
  Messages layer. The Escape chain is the thing that has to come out right;
  the nesting is the builder's call.
- Pixel values for the bubble beyond the chosen layout.
