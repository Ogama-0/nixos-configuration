# KDE Connect SMS payload reference

> **STATUS: BLOCKED — no payload captured yet.**
>
> Run `scripts/kdeconnect-sms-probe.sh`. While it exits 1, the field table
> below is empty and **Tasks 4, 5, 9 and 12 of the Messages plan cannot be
> built honestly** — they read column names out of this file.

## What the desktop can ask for

Verified on KDE Connect 26.04.3. Service `org.kde.kdeconnect`, object
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

Note what is *not* there: no `markRead`. Read state is the panel's own and
never travels back to the phone.

## Where the answers arrive

Not on that interface. `org.kde.kdeconnect.device.conversations`, signals
`conversationCreated`, `conversationUpdated`, `conversationRemoved`,
`conversationLoaded` — the set `kdeconnect-sms` consumes through
`OrgKdeKdeconnectDeviceConversationsInterface`.

That interface does **not** appear under `busctl introspect` on the sms
object. It is registered by the plugin when the phone first replies, so the
only way to see its shape is to watch the bus while asking. That is what the
probe does.

## Current state of the round-trip

Last run: 2026-10-26.

```
device: Ogama phone (cde4f091ac3e4d658934b9a63d8e20f5)
asking for all conversations, listening 15s...
NOTHING CAME BACK.
```

The pairing is fine and both ends advertise the plugin — `kdeconnect_sms` is
in the device's `loadedPlugins`, alongside `kdeconnect_telephony` and
`kdeconnect_mmtelephony`. The request leaves the desktop; the phone says
nothing.

Remaining cause, in likelihood order:

1. Android has not granted KDE Connect the SMS permission
   (Settings > Apps > KDE Connect > Permissions > SMS).
2. The SMS plugin is switched off for this desktop in the phone's KDE Connect
   plugin list.

## Field table

Empty until the probe succeeds. One row per `ConversationMessage` field: name,
DBus type, meaning. Specifically needed downstream:

| Field | DBus type | Meaning | Used by |
|---|---|---|---|
| _conversation id_ | ? | groups messages into a thread | Task 4 schema, Task 5 |
| _body_ | ? | the text | Task 4, Task 8 |
| _timestamp_ | ? | ms or s since epoch — **check which** | Task 4 retention, Task 8 day separators |
| _direction flag_ | ? | sent vs received | Task 8 bubble side |
| _addresses_ | ? | list shape decides group reply addressing | Task 5, Task 9 |
| _group flag_ | ? | one-to-one vs group | Task 6 avatar, Task 7 |
| _attachment part ids_ | ? | argument to `getAttachment` | Task 8, Task 9 |
