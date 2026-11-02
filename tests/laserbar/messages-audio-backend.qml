import QtQuick
import Quickshell
import QtMultimedia

ShellRoot {
    MediaPlayer {
        id: player
        audioOutput: AudioOutput { muted: true }
    }
    Component.onCompleted: {
        // error === MediaPlayer.NoError is the whole assertion: with the QML
        // module present but the ffmpeg plugin missing, construction logs
        // "Failed to initialize QMediaPlayer" and this is not NoError.
        if (player.error !== MediaPlayer.NoError) {
            console.log("BACKEND_FAIL " + player.errorString); return;
        }
        console.log("BACKEND_OK");
    }
}
