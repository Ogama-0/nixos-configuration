# Messages panel — design

Date: 2026-10-25
Approved visual reference: `docs/previews/messages-panel.html` (open in a browser)

## Intent

Texts arrive on the desktop today as a KDE Connect notification and stop
there. Reading one is possible; answering it is not, short of picking up the
phone or launching `kdeconnect-sms`, whose UI the user does not want to live
in. The complaint that started this was precise: *"I wanted to be able to
click on a notification to answer easily."*

This builds a Messages pane inside the existing Quickshell control panel. It
mirrors the phone's SMS — every conversation, as far back as you care to
scroll — and it lets you answer from the desktop, either from the toast the
moment a text lands or from the full pane.

It is not a second KDE Connect GUI bolted onto the panel. It is the panel's
own surface, in the panel's own material, reached by the panel's own
gestures, themed by the same `palette.nix` as everything else.

## Goals

- Read and send SMS/MMS from the desktop, including attachments: pick a file,
  or paste an image straight into the compose field and send it.
- A full mirror of the phone's conversations — nothing hidden, nothing
  truncated to "recent".
- Reply inline from an incoming toast, without the panel ever opening.
- Three ways in, all landing in the same pane: a button in the control
  panel's KDE Connect zone, a double-click on a message toast, and `mod+m`.
- Dark and light, from the one palette, flipped by darkman like everything
  else.
- Search your conversations, including the text of messages you have read.

## Non-goals

- **Not a KDE Connect replacement.** `kdeconnect-app` stays installed and the
  Mobile zone keeps its existing button. This pane owns messaging and nothing
  else — no file transfer UI, no device management, no pairing.
- **Not a second device's messages.** `MobileModel` already takes the first
  reachable device and says so in its comments; Messages inherits that. A
  second phone belongs in the GUI.
- **Not RCS, not iMessage, not a unified inbox.** Whatever KDE Connect's SMS
  plugin hands over is the whole scope.
- **Not a read-state sync.** See Constraints — it is not available.
- **Not a full-text index of your entire SMS history.** The database fills
  lazily; search covers what has been fetched. This is a deliberate choice,
  not a limitation to be fixed later.

## Anti-goals

Things that would make this a failure even if every feature worked:

- **A panel that stutters.** The control panel's performance rules are scar
  tissue (`docs/adding-a-bar-widget.md`). A conversation list that re-renders
  on every poll, or a thread that hitches while scrolling, is worse than no
  Messages pane at all.
- **A pane that looks imported.** If it reads as a chat app someone dropped
  into the panel rather than as part of the panel, the design has failed.
  That is why the avatars are glass and rings rather than iOS-style filled
  circles with photos.
- **Motion used as decoration.** The expansion, the collapse and the unread
  ring sweep are the only non-user-triggered motion. Anything that fades or
  slides because it can is out. The user has said before, on this codebase,
  that render artifacts are not to be fixed by slowing an animation down.
- **Silent data loss.** A message typed into the compose field or a toast and
  not actually delivered must say so. `sendSms` is fire-and-forget; see
  Constraints.

## Constraints

### What the KDE Connect DBus surface actually offers

Probed on this machine, KDE Connect 26.04.3, device
`cde4f091ac3e4d658934b9a63d8e20f5`:

Service `org.kde.kdeconnect`, object
`/modules/kdeconnect/devices/<id>/sms`, interface
`org.kde.kdeconnect.device.sms`:

```
requestAllConversations()
requestConversation(x)              # conversationID
requestConversation(xx)             # + rangeStartTimestamp
requestConversation(xxx)            # + numberToRequest
sendSms(av addresses, s message, av attachments)
sendSms(av addresses, s message, av attachments, x subID)
requestAttachment(x partID, s uniqueIdentifier)
getAttachment(x partID, s uniqueIdentifier)
launchApp()
```

Replies arrive on interface `org.kde.kdeconnect.device.conversations`
(signals `conversationCreated`, `conversationUpdated`, `conversationRemoved`,
`conversationLoaded`), which `kdeconnect-sms` consumes via
`OrgKdeKdeconnectDeviceConversationsInterface`. **This interface did not
appear under `busctl introspect` on the sms object during design.** See
Preconditions.

Three things are absent and shape the design:

1. **No `markRead`.** Reading a thread in the panel cannot mark it read on
   the phone. Unread state is therefore the panel's own, kept locally, and
   will drift from the phone's. The pane must not pretend otherwise.
2. **No contact photos.** 229 contacts are already synced to disk as vCards
   under `~/.local/share/kpeoplevcard/kdeconnect-<id>/`, carrying `FN` and
   `TEL` but **zero `PHOTO` fields**. Number → name resolution is a local
   file read, no round-trip. Faces do not exist, which is why the avatar
   system is colour and letterform.
3. **No delivery receipt on send.** `sendSms` returns nothing. "Delivered"
   can only be inferred from the message reappearing in a subsequent
   `conversationUpdated`. Until it does, the bubble is pending.

### The palette is not symmetrical

`modules/lib/palette.nix` is the only source of colour, per
`docs/theming.md`. Horizon light is not a recolour of the dark set:

- light `base0D` is `#DA103F` (crimson), not a blue — the outgoing bubble is
  crimson in light mode and that is correct, not a bug;
- light `base0A` is `#FBE0D9`, nearly white, and is **excluded** from the
  identity-hue pool because initials on it would be invisible.

So the hue pool is per variant, and the palette file's warning applies: the
contrast ratios in its comments were computed by hand and nothing enforces
them. Any new colour pairing introduced here must be measured by hand.

### The panel's own rules

- Everything is rendered through the `@token@` substitution in
  `modules/lib/qml-theme.nix`, twice, once per variant. There is no runtime
  theme switch inside the QML.
- Anything darkman rewrites at runtime must **not** be managed by
  `xdg.configFile` — it becomes a read-only store symlink darkman cannot
  replace (`docs/theming.md`).
- `nix flake check` does not force the generated `xdg.configFile` text, so a
  green check is compatible with QML that does not evaluate. Verify with
  `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`.
- Flakes only see tracked files. New `.nix` and `.qml` files must be
  `git add`ed by name before any check means anything. Never `git add -A` in
  this tree.

## Preconditions

**The phone must actually answer.** During design, `requestAllConversations`
was called and the session bus monitored for eleven seconds: the outbound
call appeared, and no `conversations` traffic came back. Both ends advertise
the plugin (`kdeconnect_sms` is in the device's `loadedPlugins`), so pairing
is not the problem; the likely cause is the Android app lacking SMS
permission or the plugin being disabled phone-side.

Step one of implementation is to make this round-trip work and capture one
real `conversationCreated` / `conversationLoaded` payload. **Nothing else in
this document can be built honestly until that payload has been seen** — the
exact shape of a `ConversationMessage` (field names, address list format,
attachment part IDs, the group-conversation flag) is the schema everything
downstream depends on, and guessing it from `kdeconnect-sms`'s symbol table
is not good enough.

## The design

### Layout

One sheet on the control panel's existing 940×700 stage, two panes, per the
approved reference:

**Sidebar, 340px.** A search field and a compose button at the top. Below
them the pinned people as a 3-wide grid of 62px discs with names under them.
Below that, the conversation list — avatar, name, two-line preview, relative
time.

**Conversation, the rest.** A header with the correspondent's small avatar,
their name, and the thread's actions. The message river: day separators,
bubbles left for incoming and right for outgoing, inline photos, a delivery
line under the last outgoing message. A compose row at the bottom: `+` for
attachments, the field, send.

### The avatar system

No photos exist, so identity is carried by colour and letterform, in the
panel's vocabulary rather than a chat app's.

A contact's hue comes from hashing their phone number onto the palette's
accent slots, so a person keeps one colour forever, across restarts and
across both variants (same slot, different value). The pool is per variant;
light excludes `base0A`.

- **Resting** — the panel's glass material, initials in the hue, a 2px ring
  at 34% opacity.
- **Unread** — the ring sweeps once around, the same travelling edge the bar
  uses to reveal its capsules, then rests at full strength. The list row
  additionally gains the notification pane's 2px left accent rail.
- **Open** — the disc fills with the hue and the initials flip to the
  on-accent ink. This is exactly what `ToggleTile` already does with
  `@greenColor@` and `@onAccentInk@`.
- **Group** — two discs stacked, the front one cut out of the ground with a
  3px ring of the sheet colour.
- **No contact card** — shortcodes and unknown numbers drop the initials and
  wear their own number in `base04`.

### Pinning

Right-click a conversation row to pin or unpin it. KDE Connect has no notion
of a pinned thread, so this is entirely local state, persisted alongside the
database. Pins are ordered by when they were pinned. The grid shows six; a
seventh pin is a design question left to the builder (see below).

### Storage

A local SQLite database, lazily filled.

- **Empty on first run.** The schema is created, nothing is fetched.
- **Opening a conversation fetches its last 30 messages** via
  `requestConversation(id, rangeStart, 30)` and writes them in. Scrolling
  back past the oldest cached message fetches the next 30.
- **Retention: 30 days.** A conversation not opened for 30 days has its
  cached messages dropped on next startup. Its row in the conversation list
  survives — the list itself is cheap and comes from
  `requestAllConversations` — only the message bodies go.
- **Search covers what is cached.** Names and numbers always resolve from
  the vCards; message text is searchable only where it has been fetched. The
  empty-search state must say which, in the interface's own voice, rather
  than silently returning nothing.

**On "everything declarative in Nix":** the database is mutable state and
belongs in `~/.local/state/quickshell/`, not the store — the same place
`panel-notifications.json` already lives. What is declarative is the module
that creates it: schema, page size (30), retention window (30 days), database
path, and every colour token are all set in Nix and substituted into the QML.
Changing the retention window is a `nixos-rebuild`, not a setting in a UI.
There is no imperative configuration anywhere in this feature.

### Entry and exit

Three doors, one destination.

- **The panel button.** The KDE Connect zone grows a Messages button. Pressing
  it expands that zone outward until it has taken the whole stage and become
  the Messages pane. The expansion starts from the zone's real geometry, so it
  grows out of the thing you pressed rather than fading in over it.
- **A toast, double-clicked.** The pane opens already on that person's
  thread. The expansion originates from the toast's position.
- **`mod+m`.** Opens the panel and the pane together, from closed. Expansion
  originates from the panel's usual origin.

**Escape**, while Messages has focus, plays whichever expansion brought you
in, backwards. After a toast, that means collapsing back toward where the
toast was. Escape from the panel-button route returns to the normal panel
with its zones intact; Escape from `mod+m` closes the panel outright, because
that is where it came from.

`mod+m` is free — nothing in `modules/home-manager/display/sway/default.nix`
binds it. The house pattern for reaching Quickshell from a binding is
`exec quickshell ipc -c widgets call panel <method>`, as `mod+n` and
`mod+Shift+z` already do.

### Focus, which is the hard part

**Messages is the first part of the panel that has to hold keyboard focus,
and the panel is built on the opposite assumption.**

Correction to an earlier reading of this: `ControlPanel.qml` does set
`focusable: true` with `WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand`,
so the surface *can* take focus when clicked. What it never does is take
focus unprompted, and that is the gap `mod+m` falls into — it opens the pane
with no click to grant focus.

The control panel deliberately never takes focus unasked — you are meant to carry on
typing into the window underneath it. Because a layer surface cannot receive
a key it does not have focus for, Escape is handled by `modes.panel`, a sway
mode that exists for exactly one key: it intercepts Escape, copies in every
normal binding so nothing else stops working, and `ControlPanel.qml` enters
and leaves it as the panel opens and closes.

A compose field cannot live in that world. Typing requires real keyboard
focus, which means the Messages pane must request it, and while it has it:

- `modes.panel`'s Escape interception is the wrong mechanism — the key
  arrives at the pane directly, and the pane handles it;
- entering and leaving the mode has to stay consistent anyway, because
  collapsing Messages returns you to a normal panel that still needs its
  Escape;
- every other sway binding is, correctly, unreachable while you are typing a
  text message. That is the point of focus.

The same applies to the toast's reply field, which is a second layer surface
with the same problem and no panel around it.

How the focus grab and release is sequenced against the expand and collapse
animations — and what happens if the pane is closed by a click outside while
the compose field has focus — is the first thing to get right, not the last.

### The toast

An incoming SMS stops looking like a generic app notification and becomes
message-shaped: the beam-ring avatar, the sender's name, the message text,
and a reply field with a send button. Typing into it and sending calls
`sendSms` directly — the panel never opens. Double-clicking anywhere else on
the toast opens the pane on that thread.

Quickshell already owns `org.freedesktop.Notifications` outright (mako is
gone), so every KDE Connect SMS notification already passes through
`NotificationServer.qml` before it reaches `NotificationToasts.qml`. Messages
does not race anything or scrape a log; it recognises a text as a text inside
code this repo already owns. `NotificationToasts.qml` has the `MouseArea` to
hang the double-click on.

Do-not-disturb keeps its existing meaning: it suppresses the toast and not
the collecting.

### Theming

Nothing new. The pane is rendered twice through
`modules/lib/qml-theme.nix` like every other component, reading
`sheetBg`, `capsuleFill`, `capsuleInk`, `mutedColor`, `onAccentInk` and the
base16 slots. The identity-hue pool is a new token, passed per variant from
`modules/home-manager/display/sway/quickshell/default.nix` the same way
`statusColorsFor` and `capsuleColorsFor` already pass polarity-correct
values — because, as those functions' comments explain, no single base16 slot
means the same thing in both schemes.

### Smaller calls, made here rather than asked

These were settled while writing so the builder does not have to guess. Each
is reversible and none changes what gets built.

- **Read state.** A conversation becomes read, locally, when its thread is
  opened. There is no other trigger, and it never travels back to the phone.
- **No phone.** With the device unreachable, Messages still opens and shows
  what is cached, read-only, and says the phone is away in the plain register
  `MobilePane` already uses for this ("No phone connected. Pair one in KDE
  Connect."). The compose field is disabled rather than hidden. With no
  device ever paired, the Messages button is not drawn at all.
- **Conversation list refresh.** `requestAllConversations` fires when the
  pane opens and when a message arrives — not on a timer. `MobileModel`'s
  10-second poll is for a battery readout that nothing else can push; this
  has a push path and should use it.
- **Search.** Filters the sidebar list in place rather than opening a results
  view. Matches on contact name, number, and cached message text.

## What is left to the builder

- **File layout.** Presumably
  `modules/home-manager/display/sway/quickshell/components/panel/messages/`,
  with the model/pane split the panel already uses everywhere
  (`MobileModel` + `MobilePane`). Remember `treeFor` in
  `quickshell/default.nix` — a new QML file that is not listed there does not
  reach the store.
- **The database layer.** Settled: `QtQuick.LocalStorage` was run inside
  this machine's Quickshell and works, and **FTS5 is compiled in** — a
  `CREATE VIRTUAL TABLE ... USING fts5` plus a `MATCH` query both succeeded.
  Search uses FTS5. No helper process, no extra dependency.
- **Fetch orchestration.** How `requestConversation` calls are debounced,
  what happens when two threads are opened quickly, and how a reply that
  never arrives is timed out. The plugin's own source warns
  `"Not allowing two threads to wait for conversationID"`, so concurrency
  here is already known to be touchy.
- **The seventh pin.** Six discs fill two rows cleanly. Whether the grid
  scrolls, grows a third row and pushes the list down, or caps pinning at
  some number, is a layout call — made in the pane, not asked of the user.
- **Virtualisation.** The conversation list and the message river both need
  to not instantiate everything they hold. The performance rules in
  `docs/adding-a-bar-widget.md` apply in full.
- **The render fixture.** `tests/laserbar/` is the pixel half of this: a QML
  scene screenshotted headlessly by `scripts/laserbar-preview.sh` and
  asserted on with `scripts/laserbar-probe.sh`. At least one fixture for the
  Messages pane — populated list, open thread, unread ring — is expected, in
  both variants.
- **Logic tests are possible after all.** Quickshell runs under
  `QT_QPA_PLATFORM=offscreen` and `console.log` reaches stdout, verified on
  this machine. That gives the store, the contact resolver and the hue
  function real assertions without rendering anything, which the pixel
  harness cannot do. The plan adds a small runner for it.
- **Group conversation addressing.** `sendSms` takes a list of addresses;
  how a group reply is assembled from a `ConversationMessage`'s address list
  is determined by the real payload captured in Preconditions.
- **Pasting an image.** Getting clipboard image bytes into an attachment
  argument for `sendSms` — whether that goes through a temp file or inline —
  depends on what the `av attachments` argument actually wants. Same payload,
  same answer.

## Verification

- `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`
  after `git add`ing every new file by name. `nix flake check` alone is not
  evidence (`docs/theming.md`, and the note in `CLAUDE.md`).
- Both variants rendered through the laserbar preview harness and compared
  against `docs/previews/messages-panel.html`.
- A real text sent to a real phone, and a real text received and answered
  from the toast.
- Switching to the personal host is the user's call and is asked for
  explicitly, never run unprompted.
