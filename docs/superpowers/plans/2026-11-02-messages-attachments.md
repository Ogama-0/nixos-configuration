# Messages attachments — playing and viewing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Click a voice note in the Messages pane to play it in the bubble, and click a photo to open it full inside the panel, with Escape unwinding one layer.

**Architecture:** One `MediaPlayer`, owned by `MessagesCore` and injected into per-message views, so a two-monitor session gets one player rather than two. The picture viewer is a third expansion layer in `ControlPanel`, copying the `messagesLayer` pattern exactly. QtMultimedia reaches quickshell through a wrapped binary exposed as a flake package, so the wrapper itself can be built and exercised before any switch.

**Tech Stack:** QML/Quickshell, QtMultimedia 6.12.0 (ffmpeg backend), Nix (`symlinkJoin` + `makeWrapper`), the repo's two QML harnesses in `scripts/`.

**Spec:** `docs/superpowers/specs/2026-11-02-messages-attachments-design.md`

## Global Constraints

- **`upkgs.quickshell` is nixpkgs-unstable's quickshell, not the flake input's.** `upkgs = ({ quickshell = inputs.quickshell…; } // import nixpkgs-unstable {…})` and `//` lets the right side win. Measured: `upkgs.quickshell` → `/nix/store/c4nf9y2s5almvvlr4x5cyqmkqvjvdwip-quickshell-0.3.2`, which is the running process. The flake input's `quickshell-wrapped-0.3.2` is shadowed and unused. Build the wrapper from the **same** package set that provides `qt6.qtmultimedia` or the Qt versions will not match.
- **Both environment variables are required.** Measured with `QML_IMPORT_PATH` alone: `No QtMultimedia backends found` / `Failed to initialize QMediaPlayer "Not available"`. `QT_PLUGIN_PATH` carries the ffmpeg media backend.
- **Qt paths:** `${qt6.qtmultimedia}/lib/qt-6/qml` and `${qt6.qtmultimedia}/lib/qt-6/plugins`.
- **A `file://` URL must encode the `%` in the filename.** Voice notes are stored as `PART_1793468251539_Audio%20Mes1.amr`; the URL needs `%2520`. Use `encodeURIComponent` on the basename, or `encodeURI(path).replace(/%25/g, "%25")` as the spike did.
- **Theme tokens only.** No literal colours in components; fixtures read `MessageTokens`. Every render fixture runs in both variants (`LASERBAR_VARIANT=light`).
- **Never `git add -A`.** Stage files by name; this tree habitually holds unrelated in-progress work.
- **Do not switch.** The user runs `nixos-rebuild`/`home-manager switch` themselves. Always ask.

## Review Focus

Five things the spec implies that no task's happy-path test covers. Each line's test is added to the task that owns the code.

1. **A cached path whose file is gone** (`attachment_files` row survives a cleared cache) — the bubble must return to clickable and say the file is not there, not spin. → Task 3.
2. **`duration === 0`** (still loading, or `InvalidMedia`) — the progress bar divides by it. Must render an empty bar, not a `NaN` width that makes the delegate vanish. → Task 3.
3. **The panel dismissed mid-playback** — must stop. A voice note playing out of an invisible surface with no reachable pause button is the spec's anti-goal. → Task 2.
4. **Switching conversation while playing** — the delegate holding the playing bubble is destroyed. `playingId` must not keep a dead bubble "playing", and playback stops. → Task 2.
5. **A picture that is neither inline nor fetchable** — the viewer must say so rather than hold an empty frame forever. → Task 5.

---

### Task 1: QtMultimedia reaches quickshell

Nothing user-visible. Unblocks every later task, and proves the one change that can kill the whole shell.

**Files:**
- Create: `pkgs/quickshell-multimedia.nix`
- Modify: `flake.nix` (`packages.${system}`, `lpkgs`)
- Modify: `modules/home-manager/display/sway/quickshell/default.nix:140` (`home.packages`), `:288` (`ExecStart`)
- Modify: `scripts/qml-logic-test.sh`, `scripts/laserbar-preview.sh`
- Test: `tests/laserbar/messages-audio-backend.qml`

**Interfaces:**
- Consumes: nothing.
- Produces: `lpkgs.quickshell-multimedia` (a derivation whose `/bin/quickshell` resolves `import QtMultimedia`); both harness scripts run fixtures under it.

- [ ] **Step 1: Write the failing test**

`tests/laserbar/messages-audio-backend.qml` — a fixture that imports QtMultimedia and proves the *backend*, not just the import, because the import alone succeeds while the player stays dead:

```qml
import QtQuick
import Quickshell
import QtMultimedia

ShellRoot {
    MediaPlayer {
        id: player
        audioOutput: AudioOutput { muted: true }
    }
    Component.onCompleted: {
        // error === MediaPlayer.NoError is the whole assertion: with the QML
        // module present but the ffmpeg plugin missing, construction logs
        // "Failed to initialize QMediaPlayer" and this is not NoError.
        if (player.error !== MediaPlayer.NoError) {
            console.log("BACKEND_FAIL " + player.errorString); return;
        }
        console.log("BACKEND_OK");
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/qml-logic-test.sh tests/laserbar/messages-audio-backend.qml BACKEND_OK`
Expected: FAIL — the captured output carries `module "QtMultimedia" is not installed`.

- [ ] **Step 3: Write `pkgs/quickshell-multimedia.nix`**

`{ symlinkJoin, makeWrapper, quickshell, qt6 }:` producing `symlinkJoin` over `[ quickshell ]` with `nativeBuildInputs = [ makeWrapper ]`. In `postBuild`, remove the linked `$out/bin/quickshell` and `makeWrapper ${quickshell}/bin/quickshell $out/bin/quickshell` with `--prefix QML_IMPORT_PATH :` and `--prefix QT_PLUGIN_PATH :` set to the two paths in Global Constraints. Keep the comment short and say *why* both variables are there — the measured failure with only one is the reason.

- [ ] **Step 4: Wire it into `flake.nix`**

Add to `packages.${system}`:
`quickshell-multimedia = (import nixpkgs-unstable { inherit system; }).callPackage ./pkgs/quickshell-multimedia.nix { };`
— unstable's `callPackage`, so `quickshell` and `qt6` come from the set that `upkgs.quickshell` actually resolves to. Add `quickshell-multimedia = self.packages.${system}.quickshell-multimedia;` to `lpkgs`.

- [ ] **Step 5: Verify it builds and the wrapper is right**

Run: `nix build --no-link --print-out-paths .#quickshell-multimedia`
Then: `grep -c QML_IMPORT_PATH <result>/bin/quickshell`
Expected: a store path, and the wrapper script mentioning both variables.

- [ ] **Step 6: Point both harness scripts at it**

In `scripts/qml-logic-test.sh` and `scripts/laserbar-preview.sh`, resolve the binary once near the top:
`QS="$(nix build --no-link --print-out-paths "$REPO#quickshell-multimedia")/bin/quickshell"`
and invoke `"$QS"` instead of bare `quickshell`. Honour an override (`QS_BIN`) so a tight loop can skip the build. Comment why: the fixtures import QtMultimedia, and the `quickshell` on `PATH` is whatever the last switch installed — which is exactly the unwrapped one this task exists to replace.

- [ ] **Step 7: Run the test to verify it passes**

Run: `./scripts/qml-logic-test.sh tests/laserbar/messages-audio-backend.qml BACKEND_OK`
Expected: PASS.

- [ ] **Step 8: Swap the module over**

In `modules/home-manager/display/sway/quickshell/default.nix`, replace `upkgs.quickshell` with `lpkgs.quickshell-multimedia` in `home.packages` and in the `ExecStart` of `systemd.user.services.quickshell-widgets`. Add `lpkgs` to the module's argument list if it is not already there.

- [ ] **Step 9: Prove the real shell still loads under the wrapper**

Run: `./scripts/laserbar-preview.sh real /tmp/real.png`
Expected: `wrote /tmp/real.png`. This is the check that stands between this change and a dead shell.
Then: `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`
Expected: a `.drv` path.

- [ ] **Step 10: Commit**

```bash
git add pkgs/quickshell-multimedia.nix flake.nix \
        modules/home-manager/display/sway/quickshell/default.nix \
        scripts/qml-logic-test.sh scripts/laserbar-preview.sh \
        tests/laserbar/messages-audio-backend.qml
git commit -m "feat(messages): reach QtMultimedia through a wrapped quickshell"
```

---

### Task 2: MessageAudio, the one player

**Files:**
- Create: `modules/home-manager/display/sway/quickshell/components/panel/messages/MessageAudio.qml`
- Modify: `modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesCore.qml`
- Modify: `docs/messages-panel.md`
- Test: `tests/laserbar/messages-audio.qml`

**Interfaces:**
- Consumes: `lpkgs.quickshell-multimedia` (Task 1).
- Produces, on `MessageAudio`:
  - `property string playingId` — message id, `""` when nothing plays
  - `property bool paused`
  - `property real position`, `property real duration` (ms)
  - `property var player` — the `MediaPlayer`, **injectable**; a fixture assigns a stub
  - `property var store` — for `attachmentFiles()` lookups
  - `function toggle(msgId: string, path: string, uid: string): void`
  - `function seekTo(ms: real): void` — clamped to `[0, duration]`
  - `function skip(deltaMs: real): void`
  - `function stop(): void`
  - `function fileUrl(path: string): string` — the `%`-encoding rule
  - `function clock(ms: real): string` — `m:ss`
  - `signal fetchAsked(int partId, string uid)`
  - `function fileArrived(uid: string, path: string): void` — plays it if this is the uid we are waiting on, ignores it otherwise
  - `readonly property bool awaiting` — a fetch is outstanding
  - `property int fetchTimeoutMs: 15000`
  - On `MessagesCore`: `readonly property alias audio: audio`; the existing `attachmentReceived` handling routes into `audio.fileArrived`

  `player` is injected for the same reason `contacts`/`palette`/`store` already are on `MessagesModel`: the fixture drives the state machine without a sound card, and the real player is trusted (spec, Testing).

- [ ] **Step 1: Write the failing test**

`tests/laserbar/messages-audio.qml`, with a stub player (`QtObject` carrying `position`, `duration`, `playbackState`, and counting `play()`/`pause()`/`stop()`), printing `AUDIO_OK`:

```qml
// clock
check(audio.clock(0) === "0:00", ...);
check(audio.clock(7000) === "0:07", ...);
check(audio.clock(61000) === "1:01", ...);     // the minute boundary
check(audio.clock(599000) === "9:59", ...);

// the percent-escape in the filename, which is not an encoding of a space
check(audio.fileUrl("/c/Audio%20Mes1.amr").indexOf("%2520") > 0,
      "the literal %20 in the name was decoded away: " + ...);

// seek clamps at both ends
stub.duration = 22812;
audio.seekTo(-5000);  check(stub.position === 0, ...);
audio.seekTo(99999);  check(stub.position === 22812, ...);
audio.skip(5000);     check(stub.position === 22812, ...);   // no overrun

// one at a time
audio.toggle("a", "/c/a.amr", "a.amr");
check(audio.playingId === "a", ...);
audio.toggle("b", "/c/b.amr", "b.amr");
check(audio.playingId === "b", "starting a second note did not take over");
check(stub.stops === 1, "the first note was not stopped");

// same id toggles rather than restarts
audio.toggle("b", "/c/b.amr", "b.amr");
check(audio.paused === true && audio.playingId === "b", ...);

// REVIEW FOCUS 3: the panel going away stops it
audio.stop();
check(audio.playingId === "" && stub.stops === 2, ...);

// REVIEW FOCUS 4: the open thread changes while a note is playing
audio.toggle("c", "/c/c.amr", "c.amr");
audio.stop();
check(audio.playingId === "", "a dead bubble stayed the playing one");

// no file yet: ask, do not play, and play when it lands
let asked = [];
audio.fetchAsked.connect((p, u) => asked.push(u));
audio.toggle("d", "", "PART_d.amr");
check(asked.length === 1 && audio.awaiting === true, ...);
check(stub.plays === <n>, "it tried to play a file it does not have");
audio.fileArrived("PART_d.amr", "/c/d.amr");
check(audio.playingId === "d" && audio.awaiting === false,
      "the fetched note did not start on arrival");

// a fetch for a note we are no longer waiting on must not start playing
audio.stop();
audio.fileArrived("PART_other.amr", "/c/other.amr");
check(audio.playingId === "", "an unrelated attachment started playing");
```

...and the fetch that never lands, which needs the event loop, so it closes
the fixture the way `messages-model.qml` already closes its settle test — a
`Timer` that asserts and then prints the sentinel:

```qml
audio.fetchTimeoutMs = 200;
audio.toggle("f", "", "PART_never.amr");
// in the Timer, 700ms later:
check(audio.awaiting === false && audio.missing === true,
      "a fetch that never landed left the bubble waiting forever");
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/qml-logic-test.sh tests/laserbar/messages-audio.qml AUDIO_OK`
Expected: FAIL — `MessageAudio is not a type`.

- [ ] **Step 3: Implement `MessageAudio.qml`**

An `Item` with the Interfaces above. The internal `MediaPlayer` + `AudioOutput` is the default value of `player`. `toggle` branches three ways — same id (pause/resume), no path (raise `fetchAsked`, set `awaiting`), otherwise play. Keep `position`/`duration` as plain properties updated from the player rather than bindings into the delegate, so the bar's repaint rate is decided in Task 3 rather than by the player's 40ms tick.

- [ ] **Step 4: Run the test to verify it passes**

Run: `./scripts/qml-logic-test.sh tests/laserbar/messages-audio.qml AUDIO_OK`
Expected: PASS.

- [ ] **Step 5: Hang it off `MessagesCore` and stop it on dismissal**

Instantiate `MessageAudio { id: audio; store: store }` in `MessagesCore.qml`, expose the alias, and route `fetchAsked` to the existing `model.fetchAttachment`. Call `audio.stop()` from `openConversation` (Review Focus 4). In `ControlPanel.qml`, call `messages.audio.stop()` from `closeMessages()` and wherever the panel dismisses (Review Focus 3).

- [ ] **Step 6: Verify nothing else moved**

Run: `./scripts/qml-logic-test.sh tests/laserbar/messages-model.qml MODEL_OK` and `./scripts/laserbar-preview.sh real /tmp/real.png`
Expected: PASS, and the real shell still loads.

- [ ] **Step 7: Document it**

In `docs/messages-panel.md`, extend the shape diagram with `MessageAudio` and add a short section saying why the player is owned once and injectable, and that the panel stops it on the way out.

- [ ] **Step 8: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/MessageAudio.qml \
        modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesCore.qml \
        modules/home-manager/display/sway/quickshell/components/ControlPanel.qml \
        tests/laserbar/messages-audio.qml docs/messages-panel.md
git commit -m "feat(messages): one audio player for the shell"
```

---

### Task 3: The voice bubble

**Files:**
- Create: `modules/home-manager/display/sway/quickshell/components/panel/messages/VoiceBubble.qml`
- Modify: `.../messages/ConversationView.qml` (the attachment `Repeater` delegate, around `:240-300`), `.../messages/MessagesPane.qml`
- Test: `tests/laserbar/messages-voice.qml` (render), extend `tests/laserbar/messages-audio.qml` (logic)

**Interfaces:**
- Consumes: `MessageAudio` (Task 2) via `ConversationView.audio`.
- Produces: `VoiceBubble` with `uiScale`, `outgoing`, `audio`, `msgId`, `attachment` (the `{partId, mime, data, uid, path}` record), `label`; emits nothing — it drives `audio` directly. `ConversationView` gains `property var audio: null`, forwarded by `MessagesPane` from `core.audio`.

- [ ] **Step 1: Write the failing render fixture**

`tests/laserbar/messages-voice.qml` — four bubbles in a column: incoming idle, outgoing idle, playing at ~34%, and fetching. Give the played-progress fill a probe target by rendering at a known width.

- [ ] **Step 2: Write the failing logic assertions**

Append to `tests/laserbar/messages-audio.qml`:

```qml
// REVIEW FOCUS 2: duration 0 while it loads must not make a NaN width
check(audio.progressAt(0, 0) === 0, "a zero duration produced " + audio.progressAt(0, 0));
check(audio.progressAt(5000, 0) === 0, ...);
check(audio.progressAt(5000, 10000) === 0.5, ...);

// REVIEW FOCUS 1: the row says we have it, the disk says otherwise
check(audio.playable("/c/definitely-not-here.amr") === false, ...);
audio.toggle("e", "/c/definitely-not-here.amr", "PART_e.amr");
check(audio.playingId === "" && audio.missing === true,
      "a vanished file left the bubble spinning");
```

- [ ] **Step 3: Run both to verify they fail**

Run: `./scripts/qml-logic-test.sh tests/laserbar/messages-audio.qml AUDIO_OK` and `./scripts/laserbar-preview.sh tests/laserbar/messages-voice.qml /tmp/v.png`
Expected: FAIL on `progressAt`, and the render fails on `VoiceBubble is not a type`.

- [ ] **Step 4: Add `progressAt(position, duration) -> real`, `playable(path) -> bool` and `property bool missing` to `MessageAudio`**

`progressAt` returns `0` when `duration <= 0`. `playable` is an existence check on the path — use the `Quickshell.Io` facility the repo already uses for file reads rather than shelling out.

- [ ] **Step 5: Implement `VoiceBubble.qml`**

Layout C from the spec: a round play/pause button, a wide bar with a handle, elapsed (or total before first play) at the right. Colours come from the message direction exactly as the existing bubble does — accent fill with `@msgAccentInk@` ink when outgoing, `@plateBg@` with `@clockColor@` when incoming. The play/pause glyph is **drawn**, not a font glyph: the mockup's `⏵`-class characters rendered as colour emoji. A `MouseArea` over the bubble toggles; a separate one over the bar seeks with `audio.seekTo(audio.duration * mouse.x / width)` and keeps seeking on drag.

- [ ] **Step 6: Use it from `ConversationView`**

In the attachment delegate, branch on `mime.startsWith("audio/")` → `VoiceBubble`, leaving the existing image/recess paths alone. Thread `audio` down from `MessagesPane`.

- [ ] **Step 7: Run everything**

Run the two commands from Step 3, plus `LASERBAR_VARIANT=light ./scripts/laserbar-preview.sh tests/laserbar/messages-voice.qml /tmp/v-light.png`, then probe the played-progress fill in both.
Expected: PASS; the fill reads the accent ink in dark and in light.

- [ ] **Step 8: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/VoiceBubble.qml \
        modules/home-manager/display/sway/quickshell/components/panel/messages/ConversationView.qml \
        modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesPane.qml \
        modules/home-manager/display/sway/quickshell/components/panel/messages/MessageAudio.qml \
        tests/laserbar/messages-voice.qml tests/laserbar/messages-audio.qml
git commit -m "feat(messages): play a voice note from its bubble"
```

---

### Task 4: The arrows, borrowed

**Files:**
- Modify: `.../messages/MessagesPane.qml` (the key handling the nav fixture drives)
- Modify: `tests/laserbar/messages-nav.qml`, `docs/messages-panel.md`

**Interfaces:**
- Consumes: `MessageAudio.playingId`, `skip()` (Task 2).
- Produces: `MessagesPane.arrowsBorrowed(playingId: string, composeFocused: bool): bool`.

**Nothing in this harness synthesises a key press** — `messages-nav.qml` says
so in its own header, and it tests `ThreadList.step()` rather than bindings.
So the decision has to come out of the handler as a function the fixture can
call, and the handler becomes the four lines that call it. That is the same
split the nav fixture already documents.

- [ ] **Step 1: Write the failing test**

Extend `tests/laserbar/messages-nav.qml` — four combinations, no key events:

```qml
check(pane.arrowsBorrowed("a", false) === true,
      "playing, hands off the compose field: the arrows are the skips");
check(pane.arrowsBorrowed("a", true) === false,
      "the caret key would have moved the playhead mid-draft");
check(pane.arrowsBorrowed("", false) === false,
      "nothing is playing and the arrows did not come back");
check(pane.arrowsBorrowed("", true) === false, ...);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/qml-logic-test.sh tests/laserbar/messages-nav.qml NAV_OK`
Expected: FAIL — `arrowsBorrowed is not a function`.

- [ ] **Step 3: Implement the borrow**

Add `arrowsBorrowed` to `MessagesPane` — `playingId !== "" && !composeFocused`.
Call it from the existing left/right handlers before the focus moves; when it
returns true, `audio.skip(∓5000)` and accept the event. The compose exception
is the spec's, and the spec says why.

- [ ] **Step 4: Run the test to verify it passes**

Run: `./scripts/qml-logic-test.sh tests/laserbar/messages-nav.qml NAV_OK`
Expected: PASS.

- [ ] **Step 5: Document it** — add the row to the keyboard table in `docs/messages-panel.md`, including the compose exception.

- [ ] **Step 6: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesPane.qml \
        tests/laserbar/messages-nav.qml docs/messages-panel.md
git commit -m "feat(messages): left/right skip 5s while a voice note plays"
```

---

### Task 5: The picture viewer

**Files:**
- Create: `modules/home-manager/display/sway/quickshell/components/panel/messages/PictureViewer.qml`
- Modify: `.../components/ControlPanel.qml` (a `pictureLayer` beside `messagesLayer` at `:864-945`), `.../messages/ConversationView.qml`, `.../messages/MessagesPane.qml`
- Modify: `docs/messages-panel.md`
- Test: `tests/laserbar/messages-viewer.qml` (render)

**Interfaces:**
- Consumes: `ConversationView`'s attachment record and `MessagesPane`'s geometry.
- Produces:
  - `PictureViewer` with `uiScale`, `source` (a resolved URL), `who`, `when`, `missing`
  - `ConversationView` → `signal pictureAsked(string source, string who, real ts, rect origin)`
  - `MessagesPane` → same signal, forwarded
  - `ControlPanel` → `property bool pictureOpen`, `property rect pictureOrigin`, `function openPicture(...)`, `function closePicture()`

- [ ] **Step 1: Write the failing render fixture**

`tests/laserbar/messages-viewer.qml` — the viewer at full size with a local test image, and a second instance with `missing: true`. Probe the 44px foot strip for the sheet ground and the image area for the picture.

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/laserbar-preview.sh tests/laserbar/messages-viewer.qml /tmp/pv.png`
Expected: FAIL — `PictureViewer is not a type`.

- [ ] **Step 3: Implement `PictureViewer.qml`**

Sheet ground, `Image` with `fillMode: Image.PreserveAspectFit` above a 44px strip carrying `who · when` at the left in `@mutedColor@` and `Esc to close` at the right at lower alpha. When `missing`, the frame says the phone did not send the picture instead of holding an empty rectangle (Review Focus 5).

- [ ] **Step 4: Add the layer to `ControlPanel`**

Copy the `messagesLayer` pattern: an `Item` at `z: 110`, `visible: root.pictureOpen || t > 0.001`, a click-swallowing `MouseArea`, a clipped `Rectangle` interpolating from `root.pictureOrigin` to the full 940×700 stage on the same `t`, the same `NumberAnimation { duration: 210; easing.type: Easing.OutCubic }`, and `focus: root.pictureOpen` with `Keys.onEscapePressed` calling `closePicture()`.

**Change `messagesLayer.focus` to `root.messagesOpen && !root.pictureOpen`**, or Escape is taken by the layer underneath and closes Messages instead of the picture.

- [ ] **Step 5: Raise it from the bubble**

In `ConversationView`'s image delegate, a `MouseArea` raising `pictureAsked` with the resolved source and the origin rect **mapped out of the delegate** — `mapToItem(null, …)` against the item the layer's geometry is expressed in, not the delegate's own `x`/`y`, because the bubble sits in a delegate inside a flipped `ListView` inside the pane. Forward through `MessagesPane` to `ControlPanel.openPicture`.

- [ ] **Step 6: Verify the Escape chain by hand-driving it**

Run: `./scripts/laserbar-preview.sh real /tmp/real.png`, plus the viewer fixture in both variants with probes.
Expected: the real shell loads; the strip and the image probe as expected in dark and light.

- [ ] **Step 7: Document it** — the Escape chain (picture → Messages → panel) and the `messagesLayer.focus` interlock, in `docs/messages-panel.md`.

- [ ] **Step 8: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/PictureViewer.qml \
        modules/home-manager/display/sway/quickshell/components/ControlPanel.qml \
        modules/home-manager/display/sway/quickshell/components/panel/messages/ConversationView.qml \
        modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesPane.qml \
        tests/laserbar/messages-viewer.qml docs/messages-panel.md
git commit -m "feat(messages): open a photo full in the panel"
```

---

### Task 6: The whole thing, together

**Files:** none new. `docs/messages-panel.md` final pass.

- [ ] **Step 1: Run every fixture**

```bash
for t in model store contacts hue compose compose-size nav audio audio-backend; do
  ./scripts/qml-logic-test.sh tests/laserbar/messages-$t.qml <SENTINEL>; done
for f in avatar sidebar pane toast thread voice viewer; do
  ./scripts/laserbar-preview.sh tests/laserbar/messages-$f.qml /tmp/$f.png; done
```
Expected: every one green, and the render set repeated with `LASERBAR_VARIANT=light`.

- [ ] **Step 2: The real shell, and the evaluation**

Run: `./scripts/laserbar-preview.sh real /tmp/real.png` then `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`
Expected: both succeed. A failure here is a dead shell after the switch.

- [ ] **Step 3: Update the "When it goes wrong" table**

Rows for: the whole shell failing to start after a switch (the import path — first thing to check), a voice note that will not play (backend vs. missing file), and Escape closing Messages instead of the picture (the `focus` interlock).

- [ ] **Step 4: Commit, and hand back**

```bash
git add docs/messages-panel.md
git commit -m "docs(messages): attachments, playback and the viewer"
```

Then **ask the user to switch** — this is the first change in the series that replaces the quickshell binary itself, so the shell restarts and the new binary is what comes back.
