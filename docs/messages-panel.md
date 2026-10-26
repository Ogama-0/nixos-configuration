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
└── MessagesModel     the KDE Connect bridge

MessagesPane          one per screen: a view, holds no state
├── ThreadList        search, pinned grid, conversation list
├── ConversationView  bubbles, day separators, lazy scrollback
└── ComposeRow        type, attach, paste, send

MessageToasts         its own layer surface; MessageToast per thread
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

Paging is by **index** (`requestConversation(threadId, start, end)`), not by
timestamp. The `/sms` object has a timestamp form; it is on the other
interface and is not the one that answers.

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
- **No contact photos.** All 229 vCards carry `FN` and `TEL` and not one
  `PHOTO`. That is why avatars are two letters and a colour.

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

## Ways in

| | |
|---|---|
| `mod+m` | `quickshell ipc -c widgets call panel messages` |
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
`messages-model`, `messages-compose`.
Render: `messages-avatar`, `messages-sidebar`, `messages-thread`,
`messages-pane`, `messages-toast`.

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
| No conversations, phone connected | SMS permission on Android. Run the probe. |
| Mobile zone empty, `--list-devices` finds the phone | Paired but not **reachable**. The zone runs `kdeconnect-cli -a`, which lists reachable devices only; `--list-devices` lists paired ones. Check `isReachable` on the device object. Messages still opens and shows the cache. |
| Every thread named by its number | The vCard read failed, or `relabel()` did not fire. |
| All shortcode senders one colour | A normaliser regression — alphanumeric ids have no digits and must fold to an `id:` key. |
| A message stuck on "Sent" | Honest. The phone never echoed it back. |
| A thread opens blank and stays blank | Evicted cache plus a phone that is not answering. `oldestTimestamp` returning 0 is what should trigger the refetch. |
| `wl-paste`/`zenity` not found | Both are declared in the quickshell module's `home.packages`. Check you switched. |
