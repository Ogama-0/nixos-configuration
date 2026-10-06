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

    // Held only long enough to answer greetd's auth_message, then cleared.
    property string pendingPassword: ""

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

    function authenticate(username, password) {
        if (session.busy) return
        session.busy = true
        session.failed = false
        session.errorText = ""
        session.pendingPassword = password
        session.send({ type: "create_session", username: username })
    }

    // The greeter exits and greetd starts the real session.
    function startSession() {
        session.send({ type: "start_session", cmd: [ "@swayBin@" ] })
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
                    if (message.auth_message_type === "secret") {
                        proxy.write(JSON.stringify({
                            type: "post_auth_message_response",
                            response: session.pendingPassword
                        }) + "\n")
                        session.pendingPassword = ""
                    }
                    return
                }

                if (message.type === "success") {
                    session.pendingPassword = ""
                    session.busy = false
                    session.authenticated()
                    return
                }

                if (message.type === "error") {
                    session.pendingPassword = ""
                    session.busy = false
                    session.errorText = message.description || "authentication failed"
                    session.failed = true
                }
            }
        }
    }
}
