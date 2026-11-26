import QtQuick
import QtQuick.LocalStorage

// The local half of the mirror. Non-visual.
//
// KDE Connect will hand over any conversation on request, but every request
// is a round-trip to a phone that might be asleep, on mobile data, or across
// the house. Scrolling a thread cannot wait for that, and searching the text
// of a message is impossible without having the text.
//
// So: SQLite, filled lazily. Empty on first run. Opening a conversation
// fetches its newest @msgPageSize@ messages and writes them here; scrolling
// past the oldest cached one fetches the next page. A conversation you have
// not opened in @msgRetentionDays@ days has its bodies dropped - the thread
// stays in the list, because the list is cheap and comes from the phone, but
// the text goes.
//
// That makes "nothing cached" and "nothing older" two different answers, and
// the difference matters: the first means fetch, the second means stop. They
// are told apart by oldestTimestamp() returning 0 only in the first case.
//
// FTS5 is compiled into Qt's bundled SQLite (checked, on this machine) so the
// search is a real index rather than a LIKE scan over every body.
Item {
    id: root

    // Overridden by fixtures so a test never writes into the user's history.
    property string dbName: "@msgDbName@"

    readonly property int pageSize: @msgPageSize@
    readonly property int retentionDays: @msgRetentionDays@

    property bool ready: false

    readonly property int schemaVersion: 3

    function db() {
        // 5MB. A text is ~100 bytes and the retention window keeps this to a
        // few thousand of them; the estimate only reserves, it does not
        // allocate, so there is nothing to win by trimming it.
        return LocalStorage.openDatabaseSync(root.dbName, "1.0",
                                             "Quickshell Messages", 5000000);
    }

    function init(): void {
        root.db().transaction(tx => {
            tx.executeSql('CREATE TABLE IF NOT EXISTS messages ('
                + 'id TEXT PRIMARY KEY, convId TEXT NOT NULL, body TEXT, '
                + 'ts INTEGER NOT NULL, outgoing INTEGER NOT NULL DEFAULT 0, '
                + 'address TEXT, attachments TEXT)');
            tx.executeSql('CREATE INDEX IF NOT EXISTS messages_conv_ts '
                + 'ON messages(convId, ts DESC)');
            tx.executeSql('CREATE TABLE IF NOT EXISTS conversations ('
                + 'convId TEXT PRIMARY KEY, lastOpened INTEGER NOT NULL DEFAULT 0, '
                + 'pinned INTEGER NOT NULL DEFAULT 0, pinnedAt INTEGER NOT NULL DEFAULT 0, '
                + 'unread INTEGER NOT NULL DEFAULT 0, '
                + 'removed INTEGER NOT NULL DEFAULT 0, blocked INTEGER NOT NULL DEFAULT 0)');
            // Not content='messages': an external-content table has to be kept
            // in sync by triggers, and the delete side of that is exactly what
            // eviction does in bulk. A plain table costs a second copy of the
            // bodies and is one less thing to get subtly wrong.
            tx.executeSql('CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts '
                + 'USING fts5(id UNINDEXED, convId UNINDEXED, body)');
            // Fetched attachment files, keyed by the uniqueIdentifier the
            // attachment carries and attachmentReceived names it with. A
            // separate table rather than a column on the message, because
            // one message can hold several and the signal that announces the
            // file knows nothing about which message asked.
            tx.executeSql('CREATE TABLE IF NOT EXISTS attachment_files ('
                + 'uid TEXT PRIMARY KEY, path TEXT NOT NULL)');
            tx.executeSql('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)');

            // `removed`/`blocked` on a conversations table that predates
            // them: CREATE TABLE IF NOT EXISTS just above is a no-op against
            // a table that already exists, so a real db with real history
            // still lacks both columns until this runs.
            //
            // Driven by the columns that are actually there, not by the
            // stored schemaVersion and not by catching SQLite's "duplicate
            // column" - exception-driven control flow here depended on the
            // wording of an error message, and on a FRESH db (where the
            // CREATE TABLE above already made both columns) it threw twice
            // on the happy path. PRAGMA answers the question directly.
            let have = {};
            const cols = tx.executeSql('PRAGMA table_info(conversations)');
            for (let i = 0; i < cols.rows.length; i++)
                have[cols.rows.item(i).name] = true;
            if (!have.removed)
                tx.executeSql('ALTER TABLE conversations ADD COLUMN '
                    + 'removed INTEGER NOT NULL DEFAULT 0');
            if (!have.blocked)
                tx.executeSql('ALTER TABLE conversations ADD COLUMN '
                    + 'blocked INTEGER NOT NULL DEFAULT 0');

            // Recorded, not consulted - the migration above reads the real
            // columns instead, which is the only thing that stays true when
            // a db has been through a version this code has never seen. It
            // is written so a FUTURE migration that cannot be expressed as
            // "is this column present" has a number to branch on; until one
            // exists, treat this as a stamp and not as a gate.
            tx.executeSql('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
                          ['schemaVersion', String(root.schemaVersion)]);
        });
        root.sweepEchoedPending();
        root.ready = true;
    }

    // Every row this store owns. For fixtures and for a cache that has gone
    // wrong; the phone is the source of truth, so this costs refetching and
    // never data.
    //
    // attachment_files goes too. It used to be left behind - which made
    // "wiped" mean something different for it than for everything else, so a
    // message re-fetched afterwards picked its old path back up out of a
    // table that had supposedly been cleared, pointing at a file that may
    // well be gone. The schema itself stays; only rows go.
    function wipe(): void {
        root.db().transaction(tx => {
            tx.executeSql('DELETE FROM messages');
            tx.executeSql('DELETE FROM messages_fts');
            tx.executeSql('DELETE FROM conversations');
            tx.executeSql('DELETE FROM attachment_files');
        });
    }

    // Idempotent by message id. The same message arrives again every time a
    // thread is reopened and on every conversationUpdated, so "insert" is
    // never the right verb here.
    function putMessages(convId: string, msgs: var): void {
        if (!msgs || msgs.length === 0) return;
        root.db().transaction(tx => {
            for (const m of msgs) {
                const id = String(m.id);
                const atts = m.attachments ? JSON.stringify(m.attachments) : "";
                tx.executeSql('INSERT OR REPLACE INTO messages '
                    + '(id, convId, body, ts, outgoing, address, attachments) '
                    + 'VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [id, convId, m.body || "", m.ts || 0,
                     m.outgoing ? 1 : 0, m.address || "", atts]);
                // The fts table has no primary key to REPLACE against, so the
                // old row goes first. Skipped for an empty body: indexing ""
                // gains nothing and makes every photo-only message a hit for
                // an empty query.
                tx.executeSql('DELETE FROM messages_fts WHERE id = ?', [id]);
                if (m.body)
                    tx.executeSql('INSERT INTO messages_fts (id, convId, body) VALUES (?, ?, ?)',
                                  [id, convId, m.body]);
            }
            tx.executeSql('INSERT OR IGNORE INTO conversations (convId) VALUES (?)', [convId]);
        });
    }

    // Every message, whatever conversation it belongs to, in ONE transaction.
    //
    // putMessages per conversation means a transaction per conversation, and
    // a refresh brings back fifty of them at once. SQLite's per-transaction
    // cost is the whole cost here; the inserts are nothing.
    function putAll(msgs: var): void {
        if (!msgs || msgs.length === 0) return;
        root.db().transaction(tx => {
            let convs = {};
            for (const m of msgs) {
                const id = String(m.id);
                const atts = m.attachments ? JSON.stringify(m.attachments) : "";
                tx.executeSql('INSERT OR REPLACE INTO messages '
                    + '(id, convId, body, ts, outgoing, address, attachments) '
                    + 'VALUES (?, ?, ?, ?, ?, ?, ?)',
                    [id, m.convId, m.body || "", m.ts || 0,
                     m.outgoing ? 1 : 0, m.address || "", atts]);
                tx.executeSql('DELETE FROM messages_fts WHERE id = ?', [id]);
                if (m.body)
                    tx.executeSql('INSERT INTO messages_fts (id, convId, body) VALUES (?, ?, ?)',
                                  [id, m.convId, m.body]);
                convs[m.convId] = true;
            }
            for (const c in convs)
                tx.executeSql('INSERT OR IGNORE INTO conversations (convId) VALUES (?)', [c]);
        });
    }

    // The echo arrived, so the local copy is not news - it is a duplicate.
    //
    // There is no delivery receipt: send() writes a pending-<ts> row so the
    // bubble appears the moment you hit Enter, and the phone echoes the same
    // text back about a second later carrying its real uID. Both are real
    // rows, and nothing used to remove the first - so every message sent
    // from this panel ended up on screen TWICE. Twenty of the ninety-nine
    // rows in the real cache were orphaned pendings.
    //
    // Matched on the body inside a time window, because replyToConversation
    // returns nothing at all: there is no id to correlate against. The window
    // is symmetric - the timestamp on the echo is the PHONE's clock and the
    // pending row's is this machine's, and they do not agree to the second.
    //
    // A pending row nobody echoed is left alone. "Sent" forever is the honest
    // state when the phone never confirmed, which is what
    // docs/messages-panel.md promises.
    readonly property int pendingWindow: 120000

    // `echoId` is the row that SURVIVES - the message the phone just echoed
    // back. It is passed in rather than re-found here, which is the bug this
    // used to have: it looked the echo up again by body and time window, and
    // a photo with no caption has body "", so the lookup matched every
    // empty-bodied outgoing message in the +/-2 minute window and took
    // rows.item(0) with no ORDER BY at all.
    function resolvePending(convId: string, body: string, ts: real,
                            echoId: string): void {
        root.db().transaction(tx => {
            // ONE pending row per echo, the nearest in time. It used to take
            // every match and delete them all: send the same text (or two
            // uncaptioned photos, both body "") twice inside the window and
            // the first echo swept away the second message's pending row
            // too, so that message vanished from the thread until its own
            // echo arrived - and its photo was written onto the FIRST echo
            // on the way past.
            const r = tx.executeSql(
                "SELECT id, attachments FROM messages WHERE convId = ? AND outgoing = 1 "
                + "AND id LIKE 'pending-%' AND body = ? AND ts > ? AND ts < ? "
                + "ORDER BY ABS(ts - ?) ASC LIMIT 1",
                [convId, body || "", ts - root.pendingWindow,
                 ts + root.pendingWindow, ts]);
            if (r.rows.length === 0) return;
            const pending = r.rows.item(0);

            // The pending row carries the ORIGINAL file this machine staged
            // (see MessagesModel.send). The echo carries whatever the
            // phone's MMS send pass recompressed that photo down to -
            // visibly softer - and once the pending row goes there is no way
            // back to the original, so the local path has to come across now.
            //
            // MERGED, not assigned over the top. Replacing the echo's whole
            // attachments column with the pending one's threw away the
            // phone's partId, mime, uid and inline bytes - and `uid` is the
            // only handle requestAttachmentFile has, so a sent photo whose
            // staged copy was a clipboard paste (/tmp/qs-paste-*.png, gone
            // after a reboot) became unrenderable AND unfetchable, for good.
            if (pending.attachments && echoId) {
                const e = tx.executeSql('SELECT attachments FROM messages WHERE id = ?',
                                        [String(echoId)]);
                if (e.rows.length > 0)
                    tx.executeSql('UPDATE messages SET attachments = ? WHERE id = ?',
                                  [root.mergeLocalPaths(e.rows.item(0).attachments,
                                                        pending.attachments),
                                   String(echoId)]);
            }
            tx.executeSql('DELETE FROM messages WHERE id = ?', [pending.id]);
            tx.executeSql('DELETE FROM messages_fts WHERE id = ?', [pending.id]);
        });
    }

    // The echo's own attachment records, each given the local file the
    // matching pending record was staged from. Positional: the n-th
    // attachment of a message is the n-th either way, since both lists are
    // the same send. Everything else on the echo's record is left exactly as
    // the phone announced it.
    //
    // Returns the echo's JSON unchanged if anything about the pair does not
    // parse or line up - a merge that cannot be done confidently is not one
    // worth guessing at, and the phone's version is the safer of the two to
    // keep.
    function mergeLocalPaths(echoJson: string, pendingJson: string): string {
        let echo = [], local = [];
        try {
            echo = JSON.parse(echoJson || "[]");
            local = JSON.parse(pendingJson || "[]");
        } catch (e) {
            return echoJson || "";
        }
        if (!Array.isArray(echo) || !Array.isArray(local) || echo.length === 0)
            return echoJson || "";
        const merged = echo.map((a, i) => {
            const mine = local[i];
            if (!mine || !mine.path || a.path) return a;
            return Object.assign({}, a, { path: mine.path });
        });
        return JSON.stringify(merged);
    }

    // The same thing for a cache written before any of the above existed:
    // every pending row whose echo is already sitting next to it. Runs once,
    // from init(), because a duplicate already on disk is not fixed by
    // reconciling the next one.
    function sweepEchoedPending(): int {
        let n = 0;
        root.db().transaction(tx => {
            const r = tx.executeSql(
                "SELECT p.id AS id FROM messages p JOIN messages m "
                + "ON m.convId = p.convId AND m.body = p.body "
                + "WHERE p.id LIKE 'pending-%' AND m.id NOT LIKE 'pending-%' "
                + "AND m.outgoing = 1 AND p.outgoing = 1 "
                + "AND m.ts > p.ts - ? AND m.ts < p.ts + ?",
                [root.pendingWindow, root.pendingWindow]);
            for (let i = 0; i < r.rows.length; i++) {
                const id = r.rows.item(i).id;
                tx.executeSql('DELETE FROM messages WHERE id = ?', [id]);
                tx.executeSql('DELETE FROM messages_fts WHERE id = ?', [id]);
                n++;
            }
        });
        return n;
    }

    // How many of the newest messages the PHONE has given us for a thread.
    //
    // This is the index requestConversation() pages from, and it has to be
    // counted here rather than taken from the length of what is on screen:
    // that is capped at one page and padded with local pending rows, so
    // "give me the next 30 after what I have" asked for a page we already
    // held and the older ones were never reached.
    function fetchedCount(convId: string): int {
        let n = 0;
        root.db().readTransaction(tx => {
            const r = tx.executeSql("SELECT COUNT(*) AS n FROM messages "
                + "WHERE convId = ? AND id NOT LIKE 'pending-%'", [convId]);
            if (r.rows.length > 0) n = r.rows.item(0).n;
        });
        return n;
    }

    // The file attachmentReceived handed over, against the attachment it
    // belongs to. Outlives the message row deliberately: eviction drops
    // bodies, and the file on disk is still the file on disk.
    function putAttachmentFile(uid: string, path: string): void {
        if (!uid || !path) return;
        root.db().transaction(tx => {
            tx.executeSql('INSERT OR REPLACE INTO attachment_files (uid, path) '
                + 'VALUES (?, ?)', [String(uid), String(path)]);
        });
    }

    function attachmentFiles(): var {
        let out = {};
        root.db().readTransaction(tx => {
            const r = tx.executeSql('SELECT uid, path FROM attachment_files');
            for (let i = 0; i < r.rows.length; i++)
                out[r.rows.item(i).uid] = r.rows.item(i).path;
        });
        return out;
    }

    // Do we already hold this message?
    //
    // `seen` in MessagesModel answers the same question for the current
    // session only, and a session starts on every reboot and every rebuild.
    // The disk is what remembers across those, and it has to: priming the
    // daemon re-announces the newest message of all fifty threads as
    // conversationCreated signals, and forty-two of those would otherwise
    // toast texts read days ago.
    function has(id: string): bool {
        let found = false;
        root.db().readTransaction(tx => {
            const r = tx.executeSql('SELECT 1 AS n FROM messages WHERE id = ?',
                                    [String(id)]);
            found = r.rows.length > 0;
        });
        return found;
    }

    // Newest first. beforeTs of 0 means "from the newest"; anything else means
    // strictly older than that, which is what paging backwards needs.
    function messages(convId: string, limit: int, beforeTs: real): var {
        let out = [];
        root.db().readTransaction(tx => {
            const r = beforeTs > 0
                ? tx.executeSql('SELECT * FROM messages WHERE convId = ? AND ts < ? '
                    + 'ORDER BY ts DESC LIMIT ?', [convId, beforeTs, limit])
                : tx.executeSql('SELECT * FROM messages WHERE convId = ? '
                    + 'ORDER BY ts DESC LIMIT ?', [convId, limit]);
            // Parsed first, so the attachment lookup below can ask for the
            // uids this page actually carries and nothing else.
            let parsed = [];
            let uids = [];
            for (let i = 0; i < r.rows.length; i++) {
                const row = r.rows.item(i);
                const atts = row.attachments ? JSON.parse(row.attachments) : [];
                for (const a of atts)
                    if (a.uid && uids.indexOf(a.uid) < 0) uids.push(a.uid);
                parsed.push({ row: row, atts: atts });
            }
            // One read for the page, as before - but for the page's OWN
            // uids. This used to pull the whole attachment_files table back
            // on every call, and nothing ever deletes from that table
            // (evictStale drops bodies and leaves the files, deliberately),
            // so opening a thread got slower with every attachment ever
            // received. refreshActive() calls this once per incoming
            // message, so a page burst paid for it thirty times over.
            const files = uids.length > 0 ? root.attachmentFilesFor(tx, uids) : ({});
            for (const e of parsed) {
                const row = e.row;
                out.push({ id: row.id, convId: row.convId, body: row.body,
                           ts: row.ts, outgoing: row.outgoing === 1,
                           address: row.address,
                           attachments: e.atts.map(a => {
                               // The stored path, if that attachment has
                               // since been fetched. Written by
                               // attachmentReceived, which arrives long
                               // after the message it belongs to.
                               const f = files[a.uid];
                               return f ? Object.assign({}, a, { path: f }) : a;
                           }) });
            }
        });
        return out;
    }

    // The fetched files for a named set of uids, inside a transaction the
    // caller already holds. attachmentFiles() above still answers for the
    // whole table; this is the form the page read wants.
    function attachmentFilesFor(tx: var, uids: var): var {
        let out = {};
        const marks = uids.map(() => "?").join(",");
        const r = tx.executeSql('SELECT uid, path FROM attachment_files '
                                + 'WHERE uid IN (' + marks + ')', uids);
        for (let i = 0; i < r.rows.length; i++)
            out[r.rows.item(i).uid] = r.rows.item(i).path;
        return out;
    }

    // 0 means nothing cached - which is not the same as nothing older, and is
    // why this is a separate call rather than reading the last page's tail.
    function oldestTimestamp(convId: string): real {
        let ts = 0;
        root.db().readTransaction(tx => {
            const r = tx.executeSql('SELECT MIN(ts) AS t FROM messages WHERE convId = ?',
                                    [convId]);
            if (r.rows.length > 0 && r.rows.item(0).t !== null) ts = r.rows.item(0).t;
        });
        return ts;
    }

    // `when` is injectable so retention can be tested without a clock that
    // runs for a month.
    function touch(convId: string, when: real): void {
        const t = when > 0 ? when : Date.now();
        root.db().transaction(tx => {
            tx.executeSql('INSERT INTO conversations (convId, lastOpened) VALUES (?, ?) '
                + 'ON CONFLICT(convId) DO UPDATE SET lastOpened = excluded.lastOpened',
                [convId, t]);
        });
    }

    // Drops bodies, never conversations. The row in the list survives because
    // the list comes from the phone and costs nothing; what goes is the text,
    // which is the only part that takes space and the only part that is stale.
    function evictStale(): int {
        const cutoff = Date.now() - root.retentionDays * 24 * 60 * 60 * 1000;
        let n = 0;
        root.db().transaction(tx => {
            const r = tx.executeSql(
                'SELECT convId FROM conversations WHERE lastOpened > 0 AND lastOpened < ?',
                [cutoff]);
            for (let i = 0; i < r.rows.length; i++) {
                const id = r.rows.item(i).convId;
                tx.executeSql('DELETE FROM messages WHERE convId = ?', [id]);
                tx.executeSql('DELETE FROM messages_fts WHERE convId = ?', [id]);
                n++;
            }
        });
        return n;
    }

    // What a person typed into a search box is a phrase, not a query language.
    // Wrapping it as one FTS5 string literal - with embedded quotes doubled -
    // makes `*` search for a literal asterisk and `OR` search for the word
    // "OR", which is what they meant, and makes it impossible for any input to
    // be a syntax error.
    function ftsLiteral(query: string): string {
        return '"' + String(query).replace(/"/g, '""') + '"';
    }

    function search(query: string, limit: int): var {
        let out = [];
        const q = String(query || "").trim();
        if (!q) return out;
        root.db().readTransaction(tx => {
            try {
                const r = tx.executeSql(
                    'SELECT f.id, f.convId, f.body, m.ts FROM messages_fts f '
                    + 'JOIN messages m ON m.id = f.id '
                    + 'WHERE messages_fts MATCH ? ORDER BY m.ts DESC LIMIT ?',
                    [root.ftsLiteral(q), limit]);
                for (let i = 0; i < r.rows.length; i++) {
                    const row = r.rows.item(i);
                    out.push({ convId: row.convId, msgId: row.id,
                               body: row.body, timestamp: row.ts });
                }
            } catch (e) {
                // A query that is only punctuation tokenises to nothing, which
                // FTS5 rejects outright. No results is the honest answer to
                // "find me messages containing *".
                out = [];
            }
        });
        return out;
    }

    function setPinned(convId: string, pinned: bool): void {
        root.db().transaction(tx => {
            tx.executeSql('INSERT INTO conversations (convId, pinned, pinnedAt) VALUES (?, ?, ?) '
                + 'ON CONFLICT(convId) DO UPDATE SET pinned = excluded.pinned, '
                + 'pinnedAt = excluded.pinnedAt',
                [convId, pinned ? 1 : 0, pinned ? Date.now() : 0]);
        });
    }

    // In pin order, oldest pin first, so the grid does not reshuffle itself
    // every time a message arrives.
    function pinnedIds(): var {
        let out = [];
        root.db().readTransaction(tx => {
            const r = tx.executeSql('SELECT convId FROM conversations WHERE pinned = 1 '
                + 'ORDER BY pinnedAt ASC');
            for (let i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).convId);
        });
        return out;
    }

    function setUnread(convId: string, unread: bool): void {
        root.db().transaction(tx => {
            tx.executeSql('INSERT INTO conversations (convId, unread) VALUES (?, ?) '
                + 'ON CONFLICT(convId) DO UPDATE SET unread = excluded.unread',
                [convId, unread ? 1 : 0]);
        });
    }

    function unreadIds(): var {
        let out = [];
        root.db().readTransaction(tx => {
            const r = tx.executeSql('SELECT convId FROM conversations WHERE unread = 1');
            for (let i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).convId);
        });
        return out;
    }

    // Removed: hidden from the list now, but a conversation the panel's own
    // idea of - the phone has no "hide this thread" concept, same as
    // pinning - un-hides itself the moment a fresh message arrives, which is
    // why ingestMessage clears this rather than leaving it to the person to
    // notice a text they can't see landed. Never cleared by opening the
    // thread from search, on purpose: finding it on purpose is not the same
    // as it coming back on its own.
    function setRemoved(convId: string, removed: bool): void {
        root.db().transaction(tx => {
            tx.executeSql('INSERT INTO conversations (convId, removed) VALUES (?, ?) '
                + 'ON CONFLICT(convId) DO UPDATE SET removed = excluded.removed',
                [convId, removed ? 1 : 0]);
        });
    }

    function removedIds(): var {
        let out = [];
        root.db().readTransaction(tx => {
            const r = tx.executeSql('SELECT convId FROM conversations WHERE removed = 1');
            for (let i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).convId);
        });
        return out;
    }

    // Blocked: removed, AND never comes back on a new message either -
    // ingestMessage checks this and drops the fold (and the toast) for the
    // number entirely, forever, rather than treating a new text as the
    // un-hide signal the way a merely-removed conversation does.
    function setBlocked(convId: string, blocked: bool): void {
        root.db().transaction(tx => {
            // Blocking also removes and unpins, in one write - unblocking
            // (not reachable from the UI yet, but the function should still
            // be honest) touches only its own column and leaves whatever the
            // person did with removed/pinned alone.
            if (blocked) {
                tx.executeSql('INSERT INTO conversations (convId, blocked, removed, pinned, pinnedAt) '
                    + 'VALUES (?, 1, 1, 0, 0) ON CONFLICT(convId) DO UPDATE SET '
                    + 'blocked = 1, removed = 1, pinned = 0, pinnedAt = 0',
                    [convId]);
            } else {
                tx.executeSql('INSERT INTO conversations (convId, blocked) VALUES (?, 0) '
                    + 'ON CONFLICT(convId) DO UPDATE SET blocked = 0',
                    [convId]);
            }
        });
    }

    function blockedIds(): var {
        let out = [];
        root.db().readTransaction(tx => {
            const r = tx.executeSql('SELECT convId FROM conversations WHERE blocked = 1');
            for (let i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).convId);
        });
        return out;
    }
}
