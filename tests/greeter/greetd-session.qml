import QtQuick
import Quickshell

// Drives GreetdSession through the howdy sequence with no UI at all.
ShellRoot {
    id: root
    property bool sawPasswordRequest: false
    property bool gotAuthenticated: false

    GreetdSession {
        id: session
        onPasswordRequested: {
            root.sawPasswordRequest = true
            console.log("EVENT passwordRequested notice=" + session.noticeText)
            // Exactly what the surface does: hand over the typed password.
            session.providePassword("hunter2")
        }
        onAuthenticated: {
            root.gotAuthenticated = true
            console.log("EVENT authenticated")
            session.startSession()
        }
        onFailedChanged: if (session.failed) console.log("EVENT failed: " + session.errorText)
    }

    // No password up front - this is the whole point: begin() opens the
    // conversation on a username alone and lets PAM decide.
    Component.onCompleted: session.begin("ogama")

    Timer {
        interval: 6000; running: true; repeat: false
        onTriggered: {
            console.log("RESULT passwordRequested=" + root.sawPasswordRequest
                        + " authenticated=" + root.gotAuthenticated)
            Qt.quit()
        }
    }
}
