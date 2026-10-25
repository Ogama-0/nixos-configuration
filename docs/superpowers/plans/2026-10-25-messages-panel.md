# Messages Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Messages pane inside the Quickshell control panel that mirrors the phone's SMS over KDE Connect and lets you answer from the pane or straight from the toast.

**Architecture:** A non-visual `MessagesModel` bridges KDE Connect's DBus SMS interface to a local SQLite cache (`MessageStore`, via `QtQuick.LocalStorage` + FTS5), both feeding a `MessagesPane` built from the panel's existing material. The pane lives on the control panel's 940×700 stage and expands out of the Mobile zone. Every QML file is rendered twice, once per palette variant, through the existing `@token@` substitution.

**Tech Stack:** Quickshell 0.3.x / Qt 6.11 QML, `QtQuick.LocalStorage` (SQLite with FTS5, verified present), `busctl` over the session bus for KDE Connect, Nix + Home Manager for all configuration.

**Spec:** `docs/superpowers/specs/2026-10-25-messages-panel-design.md`

## Global Constraints

- Colour comes only from `modules/lib/palette.nix`, substituted as `@token@`. No literal hex in QML. (`docs/theming.md`)
- Every new `.qml` file must be added to `treeFor` in `modules/home-manager/display/sway/quickshell/default.nix` **in the same task that creates it**, or it never reaches the store.
- `git add` new files **by name**. Never `git add -A` in this tree — it always holds unrelated in-progress work.
- `nix flake check` is not evidence. Verify with `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`.
- Light `base0A` (`#FBE0D9`) is excluded from the identity-hue pool. Light `base0D` is crimson `#DA103F`, not blue; that is correct.
- Database path: `~/.local/state/quickshell/messages.sqlite`. Page size: **30 messages**. Retention: **30 days** since a conversation was last opened. All three are set in Nix and substituted in.
- Never run `nixos-rebuild switch` or `home-manager switch` without asking first.
- Device object: `/modules/kdeconnect/devices/<id>/sms`, interfaces `org.kde.kdeconnect.device.sms` (methods) and `org.kde.kdeconnect.device.conversations` (signals).

## Review Focus

Input classes the spec implies that no feature task naturally exercises. Each has its test assigned to the task that owns the code.

1. **A number with no contact card** (shortcode `32665`, or an unknown mobile) must render as the number itself in `@mutedColor@`, never as empty initials or a crash — Task 2.
2. **A conversation whose cached page is empty** after retention eviction must re-fetch on open rather than showing a blank thread forever — Task 4.
3. **`sendSms` called while the phone is unreachable** must leave the bubble visibly pending and never silently drop the text — Task 9.
4. **A search query containing FTS5 syntax** (`"`, `*`, `OR`, a bare `-`) must return results or nothing, never raise — Task 4.
5. **Escape pressed while the compose field has focus and text in it** must collapse the pane and keep the draft, not leak the key to the window underneath — Task 11.

---

### Task 1: Headless test runner, and the conversations round-trip

The precondition. Nothing downstream is honest until a real payload has been seen.

**Files:**
- Create: `scripts/qml-logic-test.sh`
- Create: `scripts/kdeconnect-sms-probe.sh`
- Create: `docs/kdeconnect-sms-payload.md`
- Modify: `tests/laserbar/README.md` (add the logic-test half)

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/qml-logic-test.sh <fixture.qml> <expected-substring>` — runs the fixture under `QT_QPA_PLATFORM=offscreen quickshell -p`, greps stdout for the substring, exits 0 on match and 1 otherwise. Every later task's logic tests use it.

- [ ] **Step 1: Write `scripts/qml-logic-test.sh`**

Run `QT_QPA_PLATFORM=offscreen timeout 25 quickshell -p "$1"`, capture combined output, `grep -qF "$2"`. On failure print the full captured output before exiting 1 — a silent failure here is indistinguishable from a fixture that never loaded. Model the header comment on `scripts/laserbar-probe.sh`.

- [ ] **Step 2: Verify the runner against a fixture that must pass and one that must fail**

Write a throwaway fixture that `console.log`s `RUNNER_OK`, run the script expecting `RUNNER_OK` (expect exit 0), then expect `RUNNER_NOPE` (expect exit 1, and the captured output printed).

- [ ] **Step 3: Write `scripts/kdeconnect-sms-probe.sh`**

Resolve the first device id as `MobileModel.qml` does (`kdeconnect-cli -a --id-name-only`), start `busctl --user monitor org.kde.kdeconnect` in the background, call `requestAllConversations`, wait 15s, and print every captured message whose interface is `org.kde.kdeconnect.device.conversations`. Exit 1 with a plain-language message if nothing came back.

- [ ] **Step 4: Run the probe**

Run: `scripts/kdeconnect-sms-probe.sh`
Expected: at least one `conversationCreated` or `conversationLoaded` message. **If it exits 1, stop and tell the user to enable SMS and grant SMS permission in KDE Connect on the phone.** Do not proceed on a guess.

- [ ] **Step 5: Record the payload in `docs/kdeconnect-sms-payload.md`**

The verbatim captured payload, plus a field table for `ConversationMessage`: every field name, its DBus type, and what it means — specifically the conversation id, the body, the timestamp, the sent/received direction flag, the address list shape, the group-conversation flag, and the attachment part ids. Later tasks read column names out of this file.

- [ ] **Step 6: Commit**

```bash
git add scripts/qml-logic-test.sh scripts/kdeconnect-sms-probe.sh docs/kdeconnect-sms-payload.md tests/laserbar/README.md
git commit -m "test(messages): headless logic runner, and capture the real SMS payload"
```

---

### Task 2: Contact resolution from the synced vCards

**Files:**
- Create: `modules/home-manager/display/sway/quickshell/components/panel/messages/ContactsModel.qml`
- Create: `tests/laserbar/messages-contacts.qml`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix` (treeFor)

**Interfaces:**
- Consumes: `scripts/qml-logic-test.sh` from Task 1.
- Produces:
  - `property bool ready`
  - `function load(deviceId: string): void` — reads `~/.local/share/kpeoplevcard/kdeconnect-<deviceId>/*.vcf` once, sets `ready`.
  - `function resolve(number: string): var` — returns `{ name, initials, number, known }`. For an unknown number, `name` is the number as given, `initials` is `""`, and `known` is `false`.
  - `function normalize(number: string): string` — strips spaces, dots, dashes and parens, keeps a leading `+`, and compares on the last 9 digits so `+33 6 76 72 48 57` and `076-724-8570` resolve to one contact.

- [ ] **Step 1: Write the failing test** — `tests/laserbar/messages-contacts.qml`

```qml
// A real card from the synced set, plus the cases that have no card.
const cases = [
    { in: "076-724-8570", name: "Benjamin Poussart", initials: "BP", known: true },
    { in: "+33767248570", name: "Benjamin Poussart", initials: "BP", known: true },
    { in: "32665",        name: "32665",             initials: "",   known: false },
    { in: "",             name: "",                  initials: "",   known: false }
];
// logs CONTACTS_OK when every case matches, CONTACTS_FAIL <case> otherwise
```

The fixture must point `ContactsModel` at a vCard directory it writes itself under `/tmp`, not at the user's real one — the real set changes.

- [ ] **Step 2: Run it and watch it fail**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-contacts.qml CONTACTS_OK`
Expected: exit 1, output naming the missing `ContactsModel`.

- [ ] **Step 3: Implement `ContactsModel.qml`**

Parse `FN:` and every `TEL`-prefixed line (the cards use `TEL;CELL:`). Build one number→contact map keyed by `normalize`. Initials are the first letter of the first and last whitespace-separated words of `FN`, uppercased; a single-word `FN` gives one letter. Read the directory with a `Process` running `cat` over the glob rather than one `Process` per file — there are 229 of them.

- [ ] **Step 4: Run it and watch it pass**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-contacts.qml CONTACTS_OK`
Expected: exit 0.

- [ ] **Step 5: Add the treeFor line and verify the tree still evaluates**

Run: `git add` the new files by name, then `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`
Expected: a store path, no evaluation error.

- [ ] **Step 6: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/ContactsModel.qml tests/laserbar/messages-contacts.qml modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): resolve numbers to names from the synced vCards"
```

---

### Task 3: Identity hues, per variant

**Files:**
- Create: `modules/home-manager/display/sway/quickshell/components/panel/messages/MessageHue.qml`
- Create: `tests/laserbar/messages-hue.qml`
- Modify: `modules/lib/qml-theme.nix` (new `msgHues`, `msgAccent`, `msgAccentInk` arguments and tokens)
- Modify: `modules/home-manager/display/sway/quickshell/default.nix` (`msgHuesFor`, `msgAccentFor`, treeFor)

**Interfaces:**
- Produces: `function hueFor(number: string): color` — deterministic, stable across restarts, drawn from the `@msgHues@` token.

- [ ] **Step 1: Write the failing test** — `tests/laserbar/messages-hue.qml`

Assert three properties and log `HUE_OK` only if all hold: the same number yields the same colour across two calls; two different numbers in a sample of 50 produce at least 5 distinct hues; every returned colour is a member of the `@msgHues@` list.

- [ ] **Step 2: Run it and watch it fail**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-hue.qml HUE_OK`
Expected: exit 1.

- [ ] **Step 3: Add the `msgHues` token**

In `modules/lib/qml-theme.nix`, add a `msgHues` argument defaulting to the dark pool, substituted as `@msgHues@`. Read the comment above `capsuleFill` first: `replaceStrings` takes the first match, so the token name must not collide with an existing one.

The panel exposes `@greenColor@` (`base0B`) as its accent, but the spec pins the outgoing bubble to **`base0D`** — `#008DF8` dark, `#DA103F` light. There is no token for it, so add two: `@msgAccent@` for the fill and `@msgAccentInk@` for text on it (`base00` dark, `base07` light, for the reason `onAccentInkFor` already documents). Use these, not `@greenColor@`, wherever the plan says the accent.

In `default.nix`, add `msgHuesFor = variant: ...` and `msgAccentFor = variant: ...` beside `capsuleColorsFor`, emitting a comma-separated `#AARRGGBB` list:
- dark: `base08 base09 base0A base0B base0C base0D base0E base0F`
- light: the same **minus `base0A`**, which is `#FBE0D9` and would leave initials invisible

- [ ] **Step 4: Implement `hueFor` in `MessageHue.qml`**

Hash `ContactsModel.normalize(number)` with a small stable string hash (FNV-1a or djb2 — not `String.hashCode`, which QML does not have), then index the parsed `@msgHues@` list. Parse the list once into a `readonly property var`, not per call.

- [ ] **Step 5: Run it and watch it pass**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-hue.qml HUE_OK`
Expected: exit 0.

- [ ] **Step 6: Verify both variants substitute**

Run: `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`, then grep the built light tree for `#FBE0D9`
Expected: the path builds, and `FBE0D9` does not appear in the light `MessageHue.qml`.

- [ ] **Step 7: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/MessageHue.qml tests/laserbar/messages-hue.qml modules/lib/qml-theme.nix modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): one stable palette hue per contact, per variant"
```

---

### Task 4: The message store

**Files:**
- Create: `modules/home-manager/display/sway/quickshell/components/panel/messages/MessageStore.qml`
- Create: `tests/laserbar/messages-store.qml`
- Modify: `modules/lib/qml-theme.nix` (`msgDbPath`, `msgPageSize`, `msgRetentionDays` tokens)
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `function init(): void`
  - `function putMessages(convId: string, msgs: var): void` — upsert by message id, idempotent
  - `function messages(convId: string, limit: int, beforeTs: real): var` — newest-first array, `beforeTs` of `0` meaning "from newest"
  - `function oldestTimestamp(convId: string): real` — `0` when nothing cached
  - `function touch(convId: string): void` — records the open, for retention
  - `function evictStale(): int` — drops messages for conversations untouched for `@msgRetentionDays@`, returns the count evicted
  - `function search(query: string, limit: int): var` — `[{ convId, msgId, body, timestamp }]`
  - `function setPinned(convId: string, pinned: bool): void` / `function pinnedIds(): var`
  - `function setUnread(convId: string, unread: bool): void` / `function unreadIds(): var`

- [ ] **Step 1: Write the failing test** — `tests/laserbar/messages-store.qml`

Against a `/tmp` database, asserting and logging `STORE_OK` only if all hold:
- `putMessages` twice with the same message yields one row, not two
- `messages(id, 30, 0)` returns newest-first and honours the limit
- `messages(id, 30, ts)` returns only messages older than `ts`
- `oldestTimestamp` on an unknown conversation is `0`
- `evictStale` drops a conversation touched 31 days ago and keeps one touched yesterday
- **after eviction, `messages()` returns empty and `oldestTimestamp` is `0`** so the caller can tell "nothing cached" from "nothing older" (Review Focus 2)
- `search("world")` finds a body containing `world`
- **`search()` with each of `"`, `*`, `OR`, `-` returns an array and does not throw** (Review Focus 4)
- `setPinned` / `pinnedIds` and `setUnread` / `unreadIds` round-trip

- [ ] **Step 2: Run it and watch it fail**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-store.qml STORE_OK`
Expected: exit 1.

- [ ] **Step 3: Implement the schema and functions in `MessageStore.qml`**

Four tables: `messages(id TEXT PRIMARY KEY, convId TEXT, body TEXT, ts INTEGER, outgoing INTEGER, address TEXT, attachments TEXT)`, `conversations(convId TEXT PRIMARY KEY, lastOpened INTEGER, pinned INTEGER DEFAULT 0, pinnedAt INTEGER, unread INTEGER DEFAULT 0)`, an FTS5 virtual table `messages_fts(body, content='messages', content_rowid=...)`, and `meta(key, value)` for the schema version. Column names for the message fields come from `docs/kdeconnect-sms-payload.md`.

FTS5 is present (verified). Sanitise the query by quoting it as a single FTS5 string literal rather than trying to escape operators — that makes a query of `*` a literal search for `*`, which is the honest reading of what a person typed into a search box.

- [ ] **Step 4: Run it and watch it pass**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-store.qml STORE_OK`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/MessageStore.qml tests/laserbar/messages-store.qml modules/lib/qml-theme.nix modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): lazy sqlite cache with fts5 search and 30-day retention"
```

---

### Task 5: The KDE Connect bridge

**Files:**
- Create: `modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesModel.qml`
- Create: `tests/laserbar/messages-model.qml`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: `MessageStore` (Task 4), `ContactsModel` (Task 2).
- Produces:
  - `property bool active` — gates all polling, as `MobileModel` does
  - `property string deviceId`, `property bool connected`
  - `property var conversations` — `[{ convId, title, addresses, isGroup, preview, ts, unread, pinned }]`, pinned first then newest
  - `property string activeId`, `property var activeMessages`
  - `property bool loadingOlder`
  - `function refresh(): void` — `requestAllConversations`
  - retention runs here: `MessageStore.evictStale()` is called once on `init`, never on a timer
  - `function openConversation(convId: string): void` — sets `activeId`, `touch`es, serves the cache immediately, then requests a page
  - `function fetchOlder(): void` — requests 30 more before `oldestTimestamp`, no-op while `loadingOlder`
  - `function send(addresses: var, text: string, attachments: var): string` — returns a local pending message id
  - `signal messageArrived(var record)`

- [ ] **Step 1: Write the failing test** — `tests/laserbar/messages-model.qml`

Drive the model with a **fake transport**: a `property var transport` the model calls instead of `busctl` directly, so the test can feed it the payload captured in Task 1 verbatim. Log `MODEL_OK` only if: a `conversationCreated` payload lands in `conversations` with pinned ordering applied; `openConversation` serves cached messages synchronously before the transport replies; `fetchOlder` is a no-op while `loadingOlder`; and a second `fetchOlder` after the reply does request the next page.

- [ ] **Step 2: Run it and watch it fail**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-model.qml MODEL_OK`
Expected: exit 1.

- [ ] **Step 3: Implement `MessagesModel.qml`**

Follow `MobileModel.qml`'s shape exactly: a non-visual `Item`, `active` gating everything, one `Process` per concern, every failure landing in a stated empty state rather than an invented one. The default transport shells out to `busctl --user --json=short`; signals are received by a long-lived `busctl --user monitor --json=short` process filtered to the conversations interface, parsed per line. Refresh on open and on arrival only — no timer (the spec's "Smaller calls" section).

- [ ] **Step 4: Run it and watch it pass**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-model.qml MODEL_OK`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesModel.qml tests/laserbar/messages-model.qml modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): bridge kde connect's sms dbus surface to the store"
```

---

### Task 6: The avatar

**Files:**
- Create: `modules/home-manager/display/sway/quickshell/components/panel/messages/MessageAvatar.qml`
- Create: `tests/laserbar/messages-avatar.qml`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: `MessageHue.hueFor` (Task 3), `ContactsModel.resolve` (Task 2).
- Produces: an `Item` with `property real uiScale`, `property string number`, `property string groupSecondNumber`, `property bool unread`, `property bool open`, `property real size`.

- [ ] **Step 1: Write the failing render fixture** — `tests/laserbar/messages-avatar.qml`

Four avatars at known coordinates on a flat ground, at `uiScale: 1`, `size: 62`: resting, unread, open, and a shortcode with no contact card. Document each one's rectangle in the header comment as the other fixtures do.

- [ ] **Step 2: Render it and watch it fail**

Run: `scripts/laserbar-preview.sh tests/laserbar/messages-avatar.qml /tmp/av.png`
Expected: failure, `MessageAvatar` not found.

- [ ] **Step 3: Implement `MessageAvatar.qml`**

Per the approved reference (`docs/previews/messages-panel.html`): glass disc in the panel's capsule material; initials in the contact hue; ring at 34% resting, full when unread, disc filled with initials in `@onAccentInk@` when open. The unread sweep is **one** `NumberAnimation` on a `Canvas` arc or a `ConicalGradient` rotation, fired once on the transition into unread — not a loop. Group avatars stack two discs, the front cut out with a 3px ring of `@sheetBg@`. No contact card means no initials: the number itself in `@mutedColor@`, shrunk to fit.

- [ ] **Step 4: Render and probe**

Run: `scripts/laserbar-preview.sh tests/laserbar/messages-avatar.qml /tmp/av.png`, then probe the open avatar's centre with `--near` its hue and the resting avatar's centre with `--near` the sheet ground.
Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/MessageAvatar.qml tests/laserbar/messages-avatar.qml modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): the beam-ring avatar"
```

---

### Task 7: The sidebar

**Files:**
- Create: `.../panel/messages/ThreadList.qml`
- Create: `tests/laserbar/messages-sidebar.qml`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: `MessageAvatar` (6), `MessagesModel.conversations` (5), `MessageStore.setPinned` / `search` (4).
- Produces: `property var conversations`, `property string activeId`, `property real uiScale`; signals `conversationPicked(string convId)`, `pinToggled(string convId)`.

- [ ] **Step 1: Write the failing render fixture** — `tests/laserbar/messages-sidebar.qml`

A 340×700 sidebar fed a stub list of six pinned and five unpinned conversations, one unread, one selected, one a shortcode. Fixed data in the fixture, no model.

- [ ] **Step 2: Render it and watch it fail**

Run: `scripts/laserbar-preview.sh tests/laserbar/messages-sidebar.qml /tmp/side.png`
Expected: failure.

- [ ] **Step 3: Implement `ThreadList.qml`**

Search field and compose button on one row at the top; the pinned grid, 3 wide, below; the conversation list under a hairline. The list is a `ListView` — it must not instantiate every row (`docs/adding-a-bar-widget.md`). A right-click on a row raises `pinToggled`; reuse `ToggleTip.qml`'s material for the menu rather than inventing one. Search filters the list in place, matching name, number and `MessageStore.search`; when the query matches a name but no cached body, say so in the empty line rather than returning nothing silently.

- [ ] **Step 4: Render and probe**

Run: the preview, then probe the unread row's left edge with `--near` the contact hue (the 2px rail) and the selected row's background with `--near` the selected plate.
Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/ThreadList.qml tests/laserbar/messages-sidebar.qml modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): sidebar with pinned grid, search and right-click pinning"
```

---

### Task 8: The conversation view

**Files:**
- Create: `.../panel/messages/ConversationView.qml`
- Create: `tests/laserbar/messages-thread.qml`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: `MessagesModel.activeMessages`, `fetchOlder`, `loadingOlder` (5).
- Produces: `property var messages`, `property string title`, `property string number`, `property bool loadingOlder`, `property real uiScale`; signal `olderWanted()`.

- [ ] **Step 1: Write the failing render fixture** — `tests/laserbar/messages-thread.qml`

A 600×700 thread with a day separator, two incoming bubbles, two outgoing, one inline image, a "Delivered" line, and the "Loading earlier messages…" pill at the top.

- [ ] **Step 2: Render it and watch it fail**

Run: `scripts/laserbar-preview.sh tests/laserbar/messages-thread.qml /tmp/thread.png`
Expected: failure.

- [ ] **Step 3: Implement `ConversationView.qml`**

A bottom-anchored `ListView`, newest at the bottom, virtualised. Incoming bubbles take the muted plate and sit left; outgoing take `@msgAccent@` with `@msgAccentInk@` text and sit right; both cap at 64% width and square off the corner nearest their tail. Day separators are section headers, not rows injected into the data. Reaching the top raises `olderWanted()` once per page, guarded by `loadingOlder`. Inline images are fetched through `MessagesModel`'s attachment path and drawn at their aspect ratio inside a 17px-radius rounded clip; a missing attachment shows a stated placeholder, not a broken image.

- [ ] **Step 4: Render and probe**

Run: the preview, then probe one outgoing bubble with `--near "@msgAccent@"`'s value and one incoming with `--near` the muted plate.
Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/ConversationView.qml tests/laserbar/messages-thread.qml modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): the thread, with lazy scrollback and inline images"
```

---

### Task 9: Composing and sending

**Files:**
- Create: `.../panel/messages/ComposeRow.qml`
- Create: `tests/laserbar/messages-compose.qml`
- Modify: `.../panel/messages/MessagesModel.qml` (attachment plumbing)
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: `MessagesModel.send` (5).
- Produces: `property string draft`, `property bool enabled`, `property real uiScale`; signals `sendRequested(string text, var attachments)`, `attachmentPicked(string path)`.

- [ ] **Step 1: Write the failing logic test** — `tests/laserbar/messages-compose.qml`

Logs `COMPOSE_OK` only if: a send while `MessagesModel.connected` is false still produces a pending record and raises no error (Review Focus 3); a pending record that is never confirmed stays pending rather than flipping to delivered on a timer; and a confirmed record flips to delivered exactly once.

- [ ] **Step 2: Run it and watch it fail**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-compose.qml COMPOSE_OK`
Expected: exit 1.

- [ ] **Step 3: Implement `ComposeRow.qml` and the attachment plumbing**

`+` opens `zenity --file-selection`, in the single-shell pattern `MobileModel.sendFile` already uses so a cancelled picker sends nothing. Ctrl+V with an image on the clipboard writes it to a temp file via `wl-paste --type image/png` and attaches that — the `av attachments` argument's exact shape comes from `docs/kdeconnect-sms-payload.md`. Enter sends, Shift+Enter inserts a newline. The field is disabled, not hidden, when the phone is unreachable, and says why.

A sent message appears immediately as a pending bubble with its own local id, and only becomes delivered when a matching record comes back through `conversationUpdated`. It never flips on a timeout — an unconfirmed message stays visibly unconfirmed, because `sendSms` gives no receipt.

- [ ] **Step 4: Run it and watch it pass**

Run: `scripts/qml-logic-test.sh tests/laserbar/messages-compose.qml COMPOSE_OK`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/ComposeRow.qml tests/laserbar/messages-compose.qml modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesModel.qml modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): compose, attach, paste an image, and never lie about delivery"
```

---

### Task 10: Assembling the pane

**Files:**
- Create: `.../panel/messages/MessagesPane.qml`
- Create: `tests/laserbar/messages-pane.qml`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: Tasks 2–9.
- Produces: `property real uiScale`, `property bool active`, `property string pendingConvId`; signals `closeAsked()`.

- [ ] **Step 1: Write the failing render fixture** — `tests/laserbar/messages-pane.qml`

The whole 940×700 pane with stub data matching `docs/previews/messages-panel.html`, so the render can be compared against the approved reference side by side.

- [ ] **Step 2: Render it and watch it fail**

Run: `scripts/laserbar-preview.sh tests/laserbar/messages-pane.qml /tmp/pane.png`
Expected: failure.

- [ ] **Step 3: Implement `MessagesPane.qml`**

Sidebar at 340px, conversation filling the rest, the conversation header carrying the small avatar and name. `pendingConvId` opens straight onto a thread — that is how the toast route lands. `active` gates `MessagesModel.active` so nothing polls while the pane is closed.

- [ ] **Step 4: Render both variants and compare against the reference**

Run: the preview for dark, then with the light tree; open both PNGs next to `docs/previews/messages-panel.html`.
Expected: layout and colour match the reference in both.

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/messages/MessagesPane.qml tests/laserbar/messages-pane.qml modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): assemble the pane, both variants"
```

---

### Task 11: Expansion, focus, and the ways in

**Files:**
- Modify: `.../components/ControlPanel.qml` (mobile zone button, expansion, IPC)
- Modify: `.../components/panel/MobilePane.qml` (the Messages button)
- Modify: `modules/home-manager/display/sway/default.nix` (`mod+m`, `modes.panel`)

**Interfaces:**
- Consumes: `MessagesPane` (10).
- Produces: IPC `quickshell ipc -c widgets call panel messages` (opens the pane) and `... call panel messagesFor <convId>` (opens it on a thread).

- [ ] **Step 1: Write the failing render fixture** — extend `tests/laserbar/messages-pane.qml` with a mid-expansion frame

A fixture that holds the expansion at 50% and renders it, so the geometry can be probed: at half expansion the pane's rectangle must be between the mobile zone's and the full stage's, not already at full size with an opacity ramp.

- [ ] **Step 2: Render it and watch it fail**

Run: `scripts/laserbar-preview.sh tests/laserbar/messages-expand.qml /tmp/exp.png`
Expected: failure.

- [ ] **Step 3: Add the Messages button to the mobile zone**

A third `MobileAction` in `MobilePane.qml`, icon plus the word "Messages", raising a new `messagesAsked` signal. Unlike `guiAsked` and `fileAsked` it does **not** dismiss the panel — it expands it. It is not drawn at all when no device has ever been paired; with a device paired but unreachable it is drawn and disabled, matching the compose field's behaviour in Task 9.

- [ ] **Step 4: Implement the expansion in `ControlPanel.qml`**

One animated rectangle interpolating from the mobile zone's geometry to the full stage, with `MessagesPane` clipped inside it. The origin is a property so the toast route can set it to the toast's position. Collapse replays it backwards. Honour the panel's existing durations and easings — this is a user-triggered reveal, not decoration, and it does not get slowed down to hide artifacts.

- [ ] **Step 5: Handle focus and Escape**

`ControlPanel.qml` already sets `focusable: true` with `WlrKeyboardFocus.OnDemand`. Messages needs focus even when opened without a click, so the pane requests it on expand and releases it on collapse. While Messages holds focus, Escape is handled **in the pane**, not by `modes.panel`, and must collapse the pane while preserving the draft (Review Focus 5). The panel still enters and leaves `modes.panel` as it does today, so a normal panel keeps its own Escape.

- [ ] **Step 6: Bind `mod+m`**

In `modules/home-manager/display/sway/default.nix`, beside `${modifier}+n`:
`"${modifier}+m" = "exec quickshell ipc -c widgets call panel messages";`
`mod+m` is currently unbound — verified.

- [ ] **Step 7: Verify**

Run: `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`, then the expansion fixture probe.
Expected: evaluates; the half-expansion rectangle is between the two geometries.

- [ ] **Step 8: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/ControlPanel.qml modules/home-manager/display/sway/quickshell/components/panel/MobilePane.qml modules/home-manager/display/sway/default.nix tests/laserbar/messages-expand.qml
git commit -m "feat(messages): expand out of the mobile zone, take focus, leave on escape"
```

---

### Task 12: The message toast

**Files:**
- Modify: `.../components/panel/NotificationToasts.qml`
- Create: `.../panel/messages/MessageToast.qml`
- Create: `tests/laserbar/messages-toast.qml`
- Modify: `modules/home-manager/display/sway/quickshell/default.nix`

**Interfaces:**
- Consumes: `MessageAvatar` (6), `MessagesModel.send` (5), the `messagesFor` IPC (11).
- Produces: `MessageToast` with `property var record`, `property real uiScale`; signals `replySent(string text)`, `paneAsked()`.

- [ ] **Step 1: Write the failing render fixture** — `tests/laserbar/messages-toast.qml`

Both variants of the toast from the approved reference: avatar, sender, body, reply field with send button.

- [ ] **Step 2: Render it and watch it fail**

Run: `scripts/laserbar-preview.sh tests/laserbar/messages-toast.qml /tmp/toast.png`
Expected: failure.

- [ ] **Step 3: Recognise an SMS in `NotificationToasts.qml`**

Match on the KDE Connect SMS notification's `appName` and whatever field carries the sender — both come from the capture in Task 1. A matching record renders `MessageToast`; everything else keeps the existing row. Do-not-disturb keeps its current meaning: it suppresses the toast and not the collecting.

- [ ] **Step 4: Implement `MessageToast.qml`**

The reply field takes focus on click only — a toast that stole the keyboard the moment a text arrived would eat whatever you were typing. Sending calls `MessagesModel.send` directly and the toast confirms in place; the panel never opens. A double-click anywhere outside the reply field raises `paneAsked()`, which calls `messagesFor <convId>` and expands from the toast's position.

- [ ] **Step 5: Render and probe both variants**

Run: the preview for dark and light; probe the send button with `--near "@msgAccent@"`'s per-variant value.
Expected: both pass.

- [ ] **Step 6: Full-tree verification**

Run: `git add` every new file by name, then `nix eval --raw .#homeConfigurations.personal.activationPackage.drvPath`
Expected: a store path.

- [ ] **Step 7: Commit**

```bash
git add modules/home-manager/display/sway/quickshell/components/panel/NotificationToasts.qml modules/home-manager/display/sway/quickshell/components/panel/messages/MessageToast.qml tests/laserbar/messages-toast.qml modules/home-manager/display/sway/quickshell/default.nix
git commit -m "feat(messages): message-shaped toast with inline reply"
```

---

### Task 13: The runbook

**Files:**
- Create: `docs/messages-panel.md`
- Modify: `CLAUDE.md` (one line in the `docs/` paragraph)

- [ ] **Step 1: Write `docs/messages-panel.md`**

In the register of `docs/calendar-stack.md` and `docs/greeter.md`: the DBus surface and where the payload reference lives, the store's schema and retention, how to add a field to a message, the focus constraint and why it is unlike the rest of the panel, and the failure modes — the phone not answering, an unconfirmed send, a conversation evicted out from under an open thread.

- [ ] **Step 2: Add the line to `CLAUDE.md`**

One sentence in the paragraph listing `docs/calendar-stack.md`, `docs/greeter.md` and `docs/status-widget.md`.

- [ ] **Step 3: Ask before switching**

Ask the user whether to run `sudo nixos-rebuild switch --flake .#personal`. Do not run it unasked.

- [ ] **Step 4: Commit**

```bash
git add docs/messages-panel.md CLAUDE.md
git commit -m "docs(messages): runbook for the sms panel"
```
