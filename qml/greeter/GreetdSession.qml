import QtQuick
import Quickshell.Io

// The whole greetd conversation, kept out of the greeter surfaces so
// GreeterDark.qml and GreeterLight.qml differ only in visual design.
//
// Talks newline-delimited JSON to greetd-proxy (pkgs/greetd-proxy), which owns
// the length-prefixed socket framing - see the spec for why that framing
// cannot live in QML.
Item {
    id: session
    visible: false

    property bool busy: false
    property bool failed: false
    property string errorText: ""

    // The last `info`/`error` auth_message PAM sent - "Scanning face",
    // "Face not recognised" and so on. Distinct from errorText, which is the
    // final verdict: this is PAM narrating a conversation that is still in
    // progress, and howdy takes about four seconds to decide, so it is the
    // only thing that can tell the user why the greeter is sitting there.
    // Nothing renders it yet; the surfaces show the busy spinner.
    property string noticeText: ""

    // Held only long enough to answer greetd's auth_message, then cleared.
    property string pendingPassword: ""

    // Whether pendingPassword is a real answer the user typed, as opposed to
    // the empty string it resets to. Needed because "" is both "not set yet"
    // and a (rejected) password, and answering a secret prompt with the
    // wrong one of those costs a bogus PAM attempt and its fail delay.
    property bool havePassword: false

    // PAM has asked for a secret and there is nothing to answer it with yet.
    // The reply is deferred until providePassword() arrives rather than sent
    // empty, because the whole point of starting authentication before a
    // password exists is to let a `sufficient` module - howdy - get there
    // first.
    property bool awaitingPassword: false

    // PAM wants a password. The surfaces use this to move focus; the
    // conversation is already open and waiting.
    signal passwordRequested()

    // `running: true` is declarative: Quickshell spawns the process after
    // component completion, and anything written before onStarted is silently
    // discarded. Queue until the process is actually up so the component does
    // not depend on when its caller happens to fire.
    property var outbox: []


    signal authenticated()

    function send(message) {
        const line = JSON.stringify(message) + "\n"
        if (proxy.running) {
            proxy.write(line)
        } else {
            session.outbox.push(line)
            proxy.running = true
        }
    }

    // Open the conversation with a username and nothing else.
    //
    // This is what makes face unlock usable. Authentication used to start
    // only once a password had been typed, so pam_howdy - which is
    // `sufficient` and runs first - would scan, approve, and discard a
    // password the user had already entered: four seconds of delay for no
    // benefit. Starting here lets PAM decide what it needs, and the password
    // field is only ever consulted if howdy declines.
    function begin(username) {
        if (session.busy) return
        if (username === "") return
        session.busy = true
        session.failed = false
        session.errorText = ""
        session.noticeText = ""
        session.pendingPassword = ""
        session.havePassword = false
        session.awaitingPassword = false
        session.send({ type: "create_session", username: username })
    }

    // Hand a typed password to a conversation that is already open. If PAM is
    // already waiting on the secret this answers it immediately; otherwise it
    // is held until PAM asks, which is the case where the user types ahead
    // while howdy is still looking at them.
    function providePassword(password) {
        if (password === "") return
        session.pendingPassword = password
        session.havePassword = true
        if (session.awaitingPassword) {
            session.awaitingPassword = false
            session.answerSecret()
        }
    }

    function answerSecret() {
        proxy.write(JSON.stringify({
            type: "post_auth_message_response",
            response: session.pendingPassword
        }) + "\n")
        session.pendingPassword = ""
        session.havePassword = false
    }

    // Latched once start_session is away: greetd is tearing the greeter
    // down from here on, and nothing else should be sent.
    property bool starting: false

    // The greeter exits and greetd starts the real session.
    function startSession() {
        if (session.starting) return
        session.starting = true
        session.send({ type: "start_session", cmd: [ "@sessionBin@" ] })
    }

    Process {
        id: proxy
        command: [ "@greetdProxyBin@" ]
        running: true
        stdinEnabled: true

        onStarted: {
            while (session.outbox.length > 0) {
                proxy.write(session.outbox.shift())
            }
        }

        onExited: {
            // Exiting while idle is normal - greetd kills the greeter once
            // start_session succeeds. Exiting mid-authentication is not, and
            // would otherwise leave busy stuck true, disabling the password
            // field for good with no way back. The agreety fallback does not
            // cover this: quickshell itself is still running fine.
            // send() restarts the process on the next attempt.
            if (!session.busy) return
            session.pendingPassword = ""
            session.havePassword = false
            session.awaitingPassword = false
            session.busy = false
            session.errorText = "login helper stopped"
            session.failed = true
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim() === "") return

                let message
                try {
                    message = JSON.parse(line)
                } catch (e) {
                    // A proxy emitting garbage is a bug, not a user error;
                    // drop the line rather than wedging the greeter.
                    return
                }

                if (message.type === "auth_message") {
                    // EVERY auth_message has to be answered, whatever its
                    // type. greetd will not advance the PAM conversation
                    // until it gets a post_auth_message_response, so a type
                    // this handler ignores is not "skipped" - it is a
                    // deadlock, with the greeter sitting there looking
                    // broken and greetd waiting forever.
                    //
                    // That is exactly what enabling howdy did. pam_howdy is
                    // `sufficient` and runs before pam_unix, and it talks:
                    //
                    //   -> create_session username='ogama'
                    //   <- auth_message type=info      (and nothing ever again)
                    //
                    // Only `secret` was handled, so the greeter never
                    // replied and face unlock could not be used at all -
                    // nor could a password, because the conversation was
                    // already wedged. The getty login worked the whole time,
                    // which is what made it look like a greeter bug rather
                    // than a howdy one. It was.
                    const kind = message.auth_message_type

                    if (kind === "secret") {
                        // Answer now if the user has already typed a
                        // password, otherwise leave the prompt open and ask
                        // the surface for one. Answering an unanswerable
                        // prompt with "" would burn a PAM attempt and its
                        // several-second fail delay on a password nobody
                        // entered - which is precisely what reaching this
                        // point without a password means after howdy has
                        // declined.
                        if (session.havePassword) {
                            session.answerSecret()
                        } else {
                            session.awaitingPassword = true
                            session.passwordRequested()
                        }
                        return
                    }

                    // `info` and `error` are PAM talking at the user, not
                    // asking: "Scanning face", "Face not recognised". They
                    // carry no input, so the response field is omitted
                    // entirely - greetd-proxy traces that as
                    // `response=absent` - and the conversation moves on to
                    // whatever PAM does next, which for a failed howdy is
                    // pam_unix asking for the password.
                    //
                    // An `error` here is NOT a failed login. PAM keeps going
                    // to the next module; the final verdict still arrives as
                    // a top-level "error" or "success" below, which is why
                    // this does not touch `failed`.
                    if (kind === "info" || kind === "error") {
                        session.noticeText = message.auth_message || ""
                        proxy.write(JSON.stringify({
                            type: "post_auth_message_response"
                        }) + "\n")
                        return
                    }

                    // `visible` is a prompt with echo on - a username, or a
                    // challenge from some module this stack does not have.
                    // There is no UI for it, so answer empty rather than
                    // hang: an empty answer fails the auth, and failing is
                    // recoverable in a way that a wedged greeter is not.
                    proxy.write(JSON.stringify({
                        type: "post_auth_message_response",
                        response: ""
                    }) + "\n")
                    return
                }

                if (message.type === "success") {
                    session.pendingPassword = ""
                    session.havePassword = false
                    session.awaitingPassword = false
                    session.busy = false
                    // greetd acks start_session with a success of its own.
                    // That is the ack for the session already underway, not
                    // a fresh authentication - without this guard
                    // success -> authenticated -> startSession -> success
                    // spins forever, and in production is only cut short by
                    // greetd killing the greeter out from under it.
                    if (session.starting) return
                    session.authenticated()
                    return
                }

                if (message.type === "error") {
                    session.pendingPassword = ""
                    session.havePassword = false
                    session.awaitingPassword = false
                    session.busy = false
                    session.errorText = message.description || "authentication failed"
                    session.failed = true
                }
            }
        }
    }
}
