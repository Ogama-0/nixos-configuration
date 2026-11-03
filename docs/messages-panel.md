# The Messages panel

SMS from the phone, inside the control panel. Read `docs/kdeconnect-sms-payload.md`
first — it is the field reference everything here maps from, and it was
captured off the real device rather than guessed.

Design: `docs/superpowers/specs/2026-10-25-messages-panel-design.md`.
Approved visual reference: `docs/previews/messages-panel.html`.

## The shape of it

```
MessagesCore          one per shell: contacts, hues, store, the DBus model
├── ContactsModel     number -> name, out of the synced vCards
├── MessageHue        number -> one palette colour, forever
├── MessageStore      SQLite cache: pages, retention, FTS5 search
├── MessagesModel     the KDE Connect bridge
└── MessageAudio      the one voice-note player

MessagesPane          one per screen: a view, holds no state
├── ThreadList        search, pinned grid, conversation list
├── ConversationView  bubbles, day separators, lazy scrollback
└── ComposeRow        type, attach, paste, send

MessageToasts         its own layer surface; MessageToast per thread
PictureViewer         its own layer surface; grown from a tapped photo
```

**`MessagesCore` is instantiated once, outside the `Variants`.** This is not
a style preference. `ControlPanel`'s window is inside a `Variants` over
`Quickshell.screens`, so anything declared in the pane exists once per
monitor — the first version gave a two-screen session two SQLite
connections, two reads of the 229 vCards, and two `busctl monitor` processes
both ingesting every message.

## Two DBus objects, and the useful one is not the obvious one

You **ask** on `/modules/kdeconnect/devices/<id>/sms`. Everything **arrives**
on the device object itself, `org.kde.kdeconnect.device.conversations`.

That interface does not exist until the phone has answered once. If it is
missing, the Android app has not been granted the SMS permission — which is
exactly how this started, with `requestAllConversations` going out and
nothing at all coming back. `scripts/kdeconnect-sms-probe.sh` is the
one-command check and says so in those words.

**And the daemon's own list starts empty.** `activeConversations()` reads
kdeconnectd's cache, not the phone; only `requestAllConversationThreads()`
fills it. kdeconnectd restarts with a reboot *and* with a rebuild, so reading
without asking meant the first open after either showed "No conversations
yet." next to a reachable phone — and opening the Android SMS app "fixed" it
because that app makes the same call for itself. `MessagesModel.ingestList`
fires `primeThreads()` when the list comes back empty, and only then: the
answer is a store write and a re-sort per thread, which is not worth doing on
every open.

That burst is also why freshness is asked of the **store** and not only of
`MessagesModel.seen`. `seen` is session memory and a session begins at every
reboot, so against an empty one all fifty re-announced threads read as news
and toasted texts read days ago.

**Everything the phone sends back is a signal, so the unwrap has to be right.**
`requestConversation` returns nothing and answers as a burst of
`conversationUpdated`; `busctl monitor` wraps those twice, and the ten fields
are `payload.data[0].data` (the shapes are in the payload reference). The
first version tested `.data` on the variant's array — undefined, because
arrays have no such property — and fell through to the wrapper itself, a
one-field "message" that `usable()` then rejected. Every signal was dropped
without a word, so the conversation list only ever filled from
`activeConversations`, **no toast had ever fired**, and every page
`fetchOlder()` asked for answered into the void. `handleSignal` is split out
of the Process for exactly this reason: a `SplitParser` cannot be handed a
fixture, and this is the seam that broke.

Paging is by **index** (`requestConversation(threadId, start, end)`), not by
timestamp. The `/sms` object has a timestamp form; it is on the other
interface and is not the one that answers.

**Nothing announces that a page has arrived.** `conversationLoaded` fires only
when the range exhausts the thread (the payload reference has the measurement),
so the in-flight guard cannot be hung off it: `loadingOlder`, set by the
request `openConversation` fires, was never cleared on any thread longer than
a page, and `fetchOlder()` returned at its first line for the rest of the
session. Scrollback was dead on exactly the threads long enough to need it.
The end of a page is inferred from the thread going quiet instead —
`pageSettleMs`, restarted by every message belonging to the open thread, so
the window is a gap between messages and not a deadline for the whole page.
`conversationLoaded` still clears it at once when it does come.

That index is `MessageStore.fetchedCount(convId)` — how many non-pending
messages the cache holds for the thread — and not the length of what is on
screen. On screen is capped at one page and padded with local `pending-`
rows that do not exist on the phone at all, so paging from it asked for a
page already held and never reached the older ones. The matching half is
`MessagesModel.pageLimit`: `refreshActive()` reads *that many* rows back out,
because when it always re-read the newest page it threw away the page
`fetchOlder()` had just written and a thread was stuck at @msgPageSize@
messages however far you scrolled.

## One player, not one per bubble

`MessageAudio` is instantiated once on `MessagesCore`, for the same reason
`ContactsModel`/`MessageStore` are: a bubble per voice note owning its own
`MediaPlayer` would mean two screens fighting over the same sound-card
handle, and a second bubble's play would not stop the first's. One player
means `playingId` is unambiguous — it is either this bubble's id or it is
not — and starting a different note always stops whatever was sounding
first.

`player` is injectable (`property var player: internalPlayer`, overridden by
a fixture's stub carrying `position`/`duration`/`playbackState` and counting
`play()`/`pause()`/`stop()`), the same pattern `contacts`/`palette`/`store`
already use on `MessagesModel`: the state machine — one id, one outstanding
fetch, a seek clamp, a fetch timeout — is tested without a sound card or an
ffmpeg plugin. The real `MediaPlayer` + `AudioOutput` is trusted; nothing in
CI plays an actual sound.

**The panel stops it on the way out, not the bubble.** Every path that puts
Messages away — Escape, `mod+m`, the pane's close button, dismissing the
whole control panel while it is open — routes through
`ControlPanel.closeMessages()`, and that is the one place `messages.audio.stop()`
is called. `MessagesCore.openConversation()` stops it too, for the narrower
case of switching threads while a note from the old one is still playing —
a dead bubble must not go on sounding under the thread that replaced it.

A voice note with no local file yet raises `fetchAsked(partId, uid)` instead
of playing, and `awaiting` is true until either `fileArrived(uid, path)`
names that same uid (it plays) or `fetchTimeoutMs` runs out with nothing
arriving (`missing` becomes true, and the bubble should say so rather than
spin forever). `partId` is carried all the way through from
`toggle(msgId, path, uid, partId)` — the voice bubble holds the full
attachment struct (`{partId, mime, data, uid, path}`) and passes the real
value, which matters: `requestAttachmentFile` on the bus takes the
attachment's own part id (`MessagesModel.parseMessage`'s `a[0]`), unrelated
to the message id, and the wrong one asks kdeconnectd for the wrong part or
one that does not exist.

## Paired is not reachable

Two different questions, and conflating them cost a whole cache.

- `kdeconnect-cli -a` lists **reachable** devices. The Mobile zone uses it,
  correctly — a battery readout for a phone that is not there is a lie.
- `kdeconnect-cli -l` lists **paired** devices. Messages uses that, through
  `MobileModel.pairedId`, because knowing *which* phone is what names the
  cached conversations and finds the contact cards.

So `MessagesModel` takes `deviceId` and `reachable` as separate inputs and
`connected` is both. A sleeping phone still gives you every conversation you
have already downloaded, read-only, and says so in those words rather than
telling you to pair a phone you have already paired.

The signal monitor is gated on `deviceId`, not on `connected`: an idle
monitor costs nothing and is already in place when the phone wakes, where
waiting for reachability would miss the first message every time.

## Things the interface cannot do

- **No `markRead`.** Unread is the panel's own state, kept in `conversations.unread`,
  and it will drift from the phone. Nothing can be done about this.
- **No delivery receipt.** `replyToConversation` returns nothing. A sent
  message is stored with a `pending-<ts>` id and only becomes real when the
  phone echoes it back with a proper `uID`. It is never promoted on a timer —
  if you see "Sent" rather than "Delivered" forever, that is the truth being
  reported, not a bug.

  The echo is a **new row**, so something has to remove the pending one or
  every message you send appears twice — which it did, for twenty of the
  ninety-nine rows in the real cache. `MessageStore.resolvePending` does it
  on the body inside a ±2 minute window, because with nothing returned from
  the call there is no id to correlate against and the two timestamps come
  from two different clocks. `sweepEchoedPending()` runs once from `init()`
  for duplicates already on disk. An unechoed pending row is left alone.
- **Attachments are three states, not two.** `base64EncodedFile` is populated
  inline for images on the first announcement, so a photo is usually
  renderable the moment it lands — as a `data:` URI, with no fetch at all.
  What is *not* inline (voice notes, video) needs
  `requestAttachmentFile(partID, uniqueIdentifier)`, and the file comes back
  on `attachmentReceived`, whose `fileName` **is** that `uniqueIdentifier`.
  `MessageStore.attachment_files` keys on it and `messages()` fills the path
  in on the way out, because the signal arrives long after the message it
  belongs to and knows nothing about which bubble asked.
- **No contact photos.** All 229 vCards carry `FN` and `TEL` and not one
  `PHOTO`. That is why avatars are two letters and a colour.

Those cards are vCard **2.1**, and thirty of them write the name as
`FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=53=61=6D=C3=BC...` — which is
every contact whose name carries an accent or an emoji, i.e. most of the
people you actually text. Match on the property *name*, never on the literal
`"FN:"`. Two continuations exist and the cards use both: RFC 2425 folding (a
leading space) and the quoted-printable soft break (a trailing `=`).
`ContactsModel.unfold` joins them; `decodeQP` goes through
`decodeURIComponent` because that is the only UTF-8 decoder in QML's
JavaScript and `ü` is two bytes, not one.

## Refreshes are not news

Opening the pane re-reads every conversation off the phone, and the daemon
also re-emits `conversationCreated` for threads it has already announced. Two
rules keep that from shouting your whole inbox at you:

- `ingestBatch` (the refresh path) raises nothing, and does one SQLite
  transaction and one re-sort for the whole lot. The per-message path did a
  write, a re-sort and a re-render each — fifty of those during the open
  animation is a visible freeze.
- `ingestMessage(raw, fromSignal)` only raises `messageArrived` when the
  message is both off the wire **and** unseen, tracked by `uID` in
  `MessagesModel.seen`. "Arrived as a signal" alone is not enough.

`conversationLoaded` also fires once per thread — fifty in a burst — so the
re-read it triggers is coalesced through a 120ms timer.

## Adding a field to a message

1. Find it in `docs/kdeconnect-sms-payload.md`, or re-run the probe.
2. Map it in `MessagesModel.parseMessage` — the ten-field struct is decoded
   there and nowhere else.
3. Add a column in `MessageStore.init` and bump `schemaVersion`.
4. Store it in `putMessages`, read it back in `messages`.

## Colour

One pool, `@msgHues@`, per variant, hashed from the phone number so a contact
keeps their colour forever.

**The light pool is corrected before use.** Measured against the cream sheet,
six of Horizon light's seven usable slots fall below 4.5:1 — `base0B` is
1.38:1 — so initials were unreadable and the 2px ring invisible. `MessageHue.legible`
darkens each slot until it clears, once at load. Excluding them instead would
have left four colours for the whole address book. `tests/laserbar/messages-hue.qml`
asserts the ratio and fails against the uncorrected pool.

Watch for the polarity trap, which bit three times here: `@glassBg@` and
anything else built from `base00` **inverts** between variants, because
light's `base00` is the cream ground. For a wash that darkens in both, use
`@msgAccentInk@` at low alpha.

## The compose box's height

Two numbers that have to agree and once did not. `ComposeRow.implicitHeight`
reserves `field.implicitHeight + chrome`, and `chrome` is the real sum of what
sits around the text — 10 above the box, 13 below it, 7+7 inside the
Flickable, plus 20 when an attachment is staged. It was a hardcoded 26 against
an actual 37, so the visible area was eleven pixels short: one line fitted
because the 56px floor covered the gap, the second was hidden behind the
conversation, and the box looked like it only began growing at the third line.
Derive the reservation from the same properties the layout uses, never from a
re-counted constant.

The ceiling is counted in **lines**, not pixels (`maxLines`), because a pixel
ceiling cuts the last line in half — the same artifact one level up. Past it
the Flickable scrolls, and `followCursor()` has to keep up: a Flickable does
not track the cursor of a TextEdit inside it, so without that you type the
fourth line into a region you cannot see. `maxHeight` spent a long time
declared and never read, which is why a long message used to push the
conversation off the top of the pane.

`tests/laserbar/messages-compose-size.qml` asserts the content fits the
visible area at one, two and many lines, and that the ceiling holds.

## Focus, which is unlike the rest of the panel

Every other zone is read with your hands still on whatever you were typing
in. The panel never takes the keyboard, so sway intercepts Escape for it
through `modes.panel`.

Messages cannot work that way — a compose field needs the keyboard. So:

- the surface switches to `WlrKeyboardFocus.Exclusive` while Messages is up;
- `ControlPanel.syncSwayMode` **leaves** `modes.panel` at the same time,
  because a sway mode binding fires before the focused client sees the key
  and Escape would dismiss the whole panel instead of collapsing Messages;
- the draft is kept in `MessagesPane.keptDraft` across a collapse, so Escape
  is not frightening.

## The picture viewer, and the Escape chain it adds

Tapping a photo opens `PictureViewer` full in the panel, over Messages
rather than instead of it — `ControlPanel.pictureLayer` sits at `z: 110`
against `messagesLayer`'s `z: 100`, grown out of the bubble exactly the way
`messagesLayer` itself grows out of the mobile zone or a toast (same
`Behavior on t`, same `NumberAnimation { duration: 210; easing.type:
Easing.OutCubic }` — one animation feel, not two).

That stacking makes Escape a three-step chain, and each step has to peel off
exactly one layer:

```
picture open  →  Escape  →  Messages (still open)
Messages open →  Escape  →  control panel (still open)
panel open    →  Escape  →  gone
```

**The interlock that makes the first step work:** both `messagesLayer` and
`pictureLayer` hold `Exclusive` keyboard focus while they are up, and QML
grants active focus to whichever of several `focus: true` Items last had
that binding evaluate true. `pictureLayer.focus` is just `root.pictureOpen`
— it is the layer ABOVE everything else, so wanting focus unconditionally
whenever it is open is correct. `messagesLayer.focus`, underneath it, is
**not** just `root.messagesOpen` — it is
`root.messagesOpen && !root.pictureOpen`. Without the second half, both
layers claim focus while a picture is open and whichever one QML happens to
resolve to could take Escape — on a bad resolution, closing Messages (and
the picture with it, since the picture lives inside Messages' DOM-level
expansion) instead of just the picture on top. The same shape would repeat
for any future layer stacked on top of these two: the one underneath always
has to explicitly cede focus to whatever can sit above it, not just assert
its own half of the condition.

**The origin rect has to be mapped, not read.** The bubble that was tapped
lives in a delegate inside `ConversationView`'s `river` `ListView`, which is
flipped (`verticalLayoutDirection: ListView.BottomToTop` — see that file's
header comment for why) and sits inside `MessagesPane` inside `messagesBox`'s
interpolated rect. The delegate's own `x`/`y` are local to that chain and
mean nothing as an animation origin. `ConversationView`'s `pictureAsked`
handlers call `attItem.mapToItem(null, 0, 0, attItem.width, attItem.height)`
to escape all of that in one step, landing in the WINDOW's own coordinates;
`MessagesPane` forwards the signal untouched, and `ControlPanel.openPicture`
is the one place that converts it back — `zones.mapFromItem(null, ...)`
undoes the `null` escape into `zones`' own space (the same unscaled
940×700 stage `messagesOrigin` already lives in), then divides out
`zones.s` to get back to the units `pictureOrigin` and the expansion math
expect. Reading the delegate's `x`/`y` directly instead would make the
photo fly in from whatever corner the flipped list happened to put that
delegate at, not from the bubble — the kind of wrong that only shows up to
a human looking at the animation, never to a probe.

**`source` can be `""`.** An image attachment arrives with its bytes inline
on the first announcement or not at all (`ConversationView`'s `src`
comment) — there is no fetch to ask for the way there is for a voice note,
so the bubble's own recess for an image reads "not sent" rather than "click
to fetch", and tapping it raises `pictureAsked("", ...)` straight away
instead of calling `attachmentAsked`. `PictureViewer.missing` is a plain
property the caller sets (`ControlPanel.openPicture` sets it to
`source === ""`), not something the viewer derives from `source` itself —
Review Focus 5 is that this state says so in the frame itself ("Your phone
did not send this picture.") rather than holding an empty rectangle forever.

**The viewer closes with the panel too.** `ControlPanel.dismiss()` calls
`closePicture()` and `closeMessages()` before it starts the sheet's own
closing animation — there is no picture-viewer state worth restoring across
a dismissal, and leaving one open (or a voice note still sounding —
`closeMessages()` is the one place `messages.audio.stop()` is called)
behind a panel that just went invisible is the spec's named anti-goal, not
a nicety. This covers every dismissal route — IPC, Escape at the panel's
own level, a workspace switch, `lockActive` — not just the ones that
happened to call `closeMessages()` for themselves already.

## The keyboard

Messages already holds the keyboard exclusively (above), so it may as well be
drivable from it. The pane opens with the **conversation list** live, not the
search box — the arrows have to do something on the first press.

| | |
|---|---|
| `↑` `↓` | previous/next conversation. Moving the selection **opens** the thread: the selection *is* `activeId`, there is no second highlight to disagree with it. The cache is served at once and the phone is asked 180ms later (`openSettle`), so walking past a dozen threads is one request, not twelve. |
| `→` `Tab` `Enter` | into the compose field of the selected thread |
| `←` `Shift+Tab` | out to the search box |
| in search: `↓` `Tab` `Enter` | back to the list (`Enter` selects the top hit first) |
| in compose: `Shift+Tab` | back to the list. `←` does it too, but **only on an empty field** — in a draft the left arrow is the cursor. `Tab` carries round to the search box. |
| `←` `→` while a voice note plays | skip ±5s instead, **except with the compose field focused** — there the arrow stays the text cursor (or, on an empty field, the `←` above), because listening to a note while typing a reply is ordinary and the shortcut should not cost you the caret. `MessagesPane.arrowsBorrowed(playingId, composeFocused)` computes the decision and is bound down into `ThreadList`, which declines the event when it is true; `MessagesPane`'s own root handler then performs the skip once the event bubbles back up to it. |
| `Escape` | collapses the pane, from anywhere |

`Escape` is the trap: a `TextInput` or `TextEdit` swallows it by default, so
both of them have to say `event.accepted = false` explicitly or Escape is
dead whenever the cursor is in a field.

## Ways in

| | |
|---|---|
| `mod+m` | `quickshell ipc -c widgets call panel messages` — a toggle: pressing it with Messages up dismisses the whole panel, where Escape collapses back to the control panel |
| Mobile zone button | `MobilePane.messagesAsked` → `ControlPanel.openMessages("")` |
| Toast, double-clicked | `MessageToasts.paneAsked` → `openMessages(convId)` |

Escape collapses, replaying whichever expansion brought you in, backwards.

## Testing

Two harnesses, and they answer different questions.

```
scripts/qml-logic-test.sh tests/laserbar/messages-<x>.qml <SENTINEL>
scripts/laserbar-preview.sh tests/laserbar/messages-<x>.qml /tmp/out.png
scripts/laserbar-probe.sh /tmp/out.png <x> <y> <w> <h> --near '#rrggbb'
```

Logic: `messages-contacts`, `messages-hue`, `messages-store`,
`messages-model`, `messages-compose`, `messages-compose-size`, `messages-nav`,
`messages-audio`. `messages-audio-backend` is separate: it only asserts that
`QtMultimedia` can actually construct a `MediaPlayer` under the wrapped
`quickshell` binary (ffmpeg plugin present) — `messages-audio` never touches
a real player at all.
Render: `messages-avatar`, `messages-sidebar`, `messages-thread`,
`messages-pane`, `messages-toast`, `messages-voice`, `messages-viewer`.

Run the render ones with `LASERBAR_VARIANT=light` too. Several bugs here were
only ever visible in one variant.

**`scripts/laserbar-preview.sh real` is the check that matters most.** A
fixture instantiates one component; the real shell instantiates all of them
together, and it is the only thing that catches a missing
`import "panel/messages"` or a property removed from a component that
something else still assigns.

Probe the **padding** of a filled shape, never its middle: the middle is
text, and a region average over glyphs is the font's opinion. An incoming
bubble reads `#131312` across its padding and `#565451` across its words.

## When it goes wrong

| What you see | What it is |
|---|---|
| No conversations, phone connected | SMS permission on Android. Run the probe. If the probe is happy, check `activeConversations` on the bus: an empty `[[]]` is a daemon nobody primed. |
| No conversations after a reboot or a rebuild, and opening the Android SMS app fills them in | `primeThreads()` did not fire. The daemon's cache is empty and the SMS app is asking on its own behalf. |
| Mobile zone empty, `--list-devices` finds the phone | Paired but not **reachable**. The zone runs `kdeconnect-cli -a`, which lists reachable devices only; `--list-devices` lists paired ones. Check `isReachable` on the device object. Messages still opens and shows the cache. |
| Every thread named by its number | The vCard read failed, or `relabel()` did not fire. |
| *Some* threads named by their number, and the KDE notification has the name | Those cards are quoted-printable. The phone resolves the name itself for notifications; the panel parses the vCards. See the FN note above. |
| A message you sent appears twice | A pending row the echo did not replace. Reconciliation is on the body — if you sent the same text twice inside two minutes, the second is not a duplicate and is kept. |
| A thread stops at thirty messages | In order: is `loadingOlder` stuck true (then `pageSettle` is not firing and `fetchOlder()` is returning at its guard), does `handleSignal` still unwrap `conversationUpdated` (the pages arrive as nothing else), is `pageLimit` growing, is `fetchedCount` being skipped for the on-screen length again. |
| Nothing at all, and `busctl` from a terminal works fine | Check the object path the command was built with. Anything derived from `deviceId` as a *binding* can still be the empty-device version inside `onConnectedChanged` — `devPathFor()` exists because of that. The symptom is `Invalid object path: /modules/kdeconnect/devices/` on stderr, which nothing reads. |
| An attachment sits on "click to fetch" forever | Either the inline bytes are being ignored (images carry them), or `attachmentReceived` is not reaching `putAttachmentFile`, or the click has nothing behind it — it had no `MouseArea` at all for a while. |
| Escape on a picture closes Messages too | `messagesLayer.focus` lost its `&& !root.pictureOpen` half — see "The picture viewer, and the Escape chain it adds" above. Both layers end up claiming focus and whichever one loses closes two things at once. |
| A photo expands from the wrong corner | The origin rect reached `ControlPanel.openPicture` as the delegate's own local `x`/`y` instead of `attItem.mapToItem(null, ...)`, or `openPicture` is reading it without the `zones.mapFromItem(null, ...)` round-trip back into stage units. |
| All shortcode senders one colour | A normaliser regression — alphanumeric ids have no digits and must fold to an `id:` key. |
| A message stuck on "Sent" | Honest. The phone never echoed it back. |
| A thread opens blank and stays blank | Evicted cache plus a phone that is not answering. `oldestTimestamp` returning 0 is what should trigger the refetch. |
| A line of the draft is hidden behind the conversation | `chrome` and the layout have drifted apart again — the row must reserve exactly what the box below it takes. |
| `wl-paste`/`zenity` not found | Both are declared in the quickshell module's `home.packages`. Check you switched. |
