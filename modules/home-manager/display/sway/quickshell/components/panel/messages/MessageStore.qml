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

    readonly property int schemaVersion: 1

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
                + 'unread INTEGER NOT NULL DEFAULT 0)');
            // Not content='messages': an external-content table has to be kept
            // in sync by triggers, and the delete side of that is exactly what
            // eviction does in bulk. A plain table costs a second copy of the
            // bodies and is one less thing to get subtly wrong.
            tx.executeSql('CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts '
                + 'USING fts5(id UNINDEXED, convId UNINDEXED, body)');
            tx.executeSql('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)');
            tx.executeSql('INSERT OR IGNORE INTO meta VALUES (?, ?)',
                          ['schemaVersion', String(root.schemaVersion)]);
        });
        root.ready = true;
    }

    // Everything, including the schema. For fixtures and for a cache that has
    // gone wrong; the phone is the source of truth, so this costs refetching
    // and never data.
    function wipe(): void {
        root.db().transaction(tx => {
            tx.executeSql('DELETE FROM messages');
            tx.executeSql('DELETE FROM messages_fts');
            tx.executeSql('DELETE FROM conversations');
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
            for (let i = 0; i < r.rows.length; i++) {
                const row = r.rows.item(i);
                out.push({ id: row.id, convId: row.convId, body: row.body,
                           ts: row.ts, outgoing: row.outgoing === 1,
                           address: row.address,
                           attachments: row.attachments
                               ? JSON.parse(row.attachments) : [] });
            }
        });
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
}
