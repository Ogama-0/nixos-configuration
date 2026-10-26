# KDE Connect SMS payload reference

Captured 2026-10-26 from KDE Connect 26.04.3, device `Ogama phone`, with
`scripts/kdeconnect-sms-probe.sh`. Re-run it if any of this stops matching.

## The correction that matters

The design doc said the conversations interface lives on the `sms` object. It
does not. There are **two objects**, and the useful one is the device itself:

| | object | interface |
|---|---|---|
| asking | `/modules/kdeconnect/devices/<id>/sms` | `org.kde.kdeconnect.device.sms` |
| **everything else** | `/modules/kdeconnect/devices/<id>` | `org.kde.kdeconnect.device.conversations` |

The conversations interface does not exist until the phone first answers,
which is why `busctl introspect` showed nothing while the Android app lacked
the SMS permission. Granting it is what unblocked this.

## org.kde.kdeconnect.device.conversations

```
activeConversations()                     -> av    every thread's newest message
requestAllConversationThreads()           -> -     ask the phone to (re)send them
requestConversation(x threadId, i start, i end) -> -
replyToConversation(x threadId, s message, av attachments) -> -
sendWithoutConversation(av addresses, s message, av attachments) -> -
requestAttachmentFile(x partId, s uniqueIdentifier) -> -

conversationCreated(v)      a thread appeared        payload = one message
conversationUpdated(v)      a thread changed         payload = one message
conversationLoaded(x threadId, t count)   a requestConversation finished
conversationRemoved(x threadId)
attachmentReceived(s filePath, s fileName)
```

**`requestConversation` pages by INDEX, not timestamp.** `start` and `end` are
positions in the thread, newest first. The `/sms` object's three-argument
`requestConversation(xxx)` takes a timestamp; this one does not, and this one
is the interface that answers.

**`conversationLoaded` carries no content.** It is a completion notice: the
thread id and how many messages arrived. The messages themselves come through
`conversationCreated` / `conversationUpdated`, one message per signal.

**Replying does not need `sendSms`.** `replyToConversation(threadId, text,
attachments)` is the path for an existing thread; `sendWithoutConversation`
takes addresses instead, for a new one.

## ConversationMessage

Signature `(isa(s)xiixixa(xsss))`, ten fields, in order:

| # | Field | Type | Meaning |
|---|---|---|---|
| 0 | `eventField` | `i` | `1` plain text, `2` multimedia (MMS) |
| 1 | `body` | `s` | the text; **empty for an attachment-only message** |
| 2 | `addresses` | `a(s)` | list of one-field structs. More than one means a group |
| 3 | `date` | `x` | **milliseconds** since epoch |
| 4 | `type` | `i` | Android's SMS type: **`1` received, `2` sent** |
| 5 | `read` | `i` | `1` read on the phone. Read-only — there is no way to set it |
| 6 | `threadID` | `x` | the conversation id. This is what `requestConversation` takes |
| 7 | `uID` | `i` | unique per message. The primary key for the cache |
| 8 | `subID` | `x` | SIM subscription; `-1` when unknown |
| 9 | `attachments` | `a(xsss)` | see below |

### Attachment, `(xsss)`

| # | Field | Type | Meaning |
|---|---|---|---|
| 0 | `partID` | `x` | first argument to `requestAttachmentFile` |
| 1 | `mimeType` | `s` | e.g. `audio/amr`, `image/jpeg` |
| 2 | `base64EncodedFile` | `s` | **empty until fetched** |
| 3 | `uniqueIdentifier` | `s` | e.g. `PART_1792262330991_Audio%20Mes1.amr`; second argument to `requestAttachmentFile` |

The fetched file arrives later on `attachmentReceived(filePath, fileName)`.

## Two real messages

A received text:

```json
[1, "[Uber] Votre code : 1358. Ne le divulguez jamais.",
 [["Uber"]], 1790539013048, 1, 1, 30, 243, 1, []]
```

A sent MMS with a voice note, in a two-address thread — note `eventField` 2,
an empty `body`, and the empty base64 field:

```json
[2, "", [["+33662843597"], ["+33616561744"]], 1792262331000, 1, 1, 6, 10, 1,
 [[14, "audio/amr", "", "PART_1792262330991_Audio%20Mes1.amr"]]]
```

## What this machine actually holds

50 threads from `activeConversations`: 42 whose newest message was received,
8 sent, 1 with an attachment, 1 with more than one address. Addresses are a
mix of real numbers (`+33766417775`), shortcodes (`38984`) and alphanumeric
sender IDs (`Uber`, `SIGNAL`, `imagine R`) — the last of these have no digits
at all, which any number-normalising code has to survive.
