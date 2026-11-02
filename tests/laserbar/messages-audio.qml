import QtQuick
import Quickshell
import "components/panel/messages"

// MessageAudio, the one player every voice-note bubble shares.
//
// Driven with a stub player instead of a real QtMultimedia MediaPlayer, for
// the same reason MessagesModel's fixture hands it fake contacts: nothing
// here is testing whether ffmpeg can decode an .amr file (that is
// messages-audio-backend.qml's whole job), only whether the state machine -
// one playing id, one pending fetch, a clamp, a timeout - does the right
// thing. The stub counts play()/pause()/stop() and lets position/duration
// be poked directly, standing in for what a real MediaPlayer would do when
// seeked or finished loading.
//
// Logic fixture, not a render fixture:
//   scripts/qml-logic-test.sh tests/laserbar/messages-audio.qml AUDIO_OK
ShellRoot {
    id: root

    QtObject {
        id: stub
        property real position: 0
        property real duration: 0
        property int playbackState: 0
        property int plays: 0
        property int pauses: 0
        property int stops: 0
        function play() { stub.plays += 1; }
        function pause() { stub.pauses += 1; }
        function stop() { stub.stops += 1; }
    }

    MessageAudio {
        id: audio
        player: stub
    }

    property var bad: []

    function finish(): void {
        if (root.bad.length > 0) {
            console.log("AUDIO_FAIL " + root.bad.join(" | ")); return;
        }
        console.log("AUDIO_OK");
    }

    Component.onCompleted: {
        const check = (ok, why) => { if (!ok) root.bad.push(why); };

        // --- clock: m:ss, no leading zero on the minute --------------------
        check(audio.clock(0) === "0:00",
              "clock(0) was " + audio.clock(0));
        check(audio.clock(7000) === "0:07",
              "clock(7000) was " + audio.clock(7000));
        check(audio.clock(61000) === "1:01",
              "clock(61000) did not cross the minute boundary: "
                  + audio.clock(61000));
        check(audio.clock(599000) === "9:59",
              "clock(599000) was " + audio.clock(599000));

        // --- the percent-escape in the filename -----------------------------
        //
        // Voice notes land on disk as PART_..._Audio%20Mes1.amr - a LITERAL
        // "%20" in the filename, not a space that got encoded. encodeURI
        // alone escapes the "%" itself (it is not in encodeURI's safe set),
        // turning that literal "%20" into "%2520" - which is exactly what a
        // file:// URL needs so the one decode a media backend performs lands
        // back on "%20Mes1.amr" rather than a decoded space.
        const url = audio.fileUrl("/c/Audio%20Mes1.amr");
        check(url.indexOf("%2520") > 0,
              "the literal %20 in the name was decoded away: " + url);

        // --- seek clamps at both ends, skip cannot overrun ------------------
        stub.duration = 22812;
        audio.seekTo(-5000);
        check(stub.position === 0, "seekTo did not clamp at 0: " + stub.position);
        audio.seekTo(99999);
        check(stub.position === 22812,
              "seekTo did not clamp at duration: " + stub.position);
        audio.skip(5000);
        check(stub.position === 22812,
              "skip overran past duration: " + stub.position);

        // --- one at a time ---------------------------------------------------
        audio.toggle("a", "/c/a.amr", "a.amr");
        check(audio.playingId === "a",
              "toggle did not start playing a: " + audio.playingId);
        audio.toggle("b", "/c/b.amr", "b.amr");
        check(audio.playingId === "b",
              "starting a second note did not take over");
        check(stub.stops === 1, "the first note was not stopped: " + stub.stops);

        // --- same id toggles rather than restarts -----------------------------
        audio.toggle("b", "/c/b.amr", "b.amr");
        check(audio.paused === true && audio.playingId === "b",
              "toggling the same id did not pause it in place");

        // --- REVIEW FOCUS 3: the panel going away stops it --------------------
        audio.stop();
        check(audio.playingId === "" && stub.stops === 2,
              "stop() did not stop the player and clear playingId");

        // --- REVIEW FOCUS 4: the open thread changes while a note is playing --
        audio.toggle("c", "/c/c.amr", "c.amr");
        audio.stop();
        check(audio.playingId === "", "a dead bubble stayed the playing one");

        // --- no file yet: ask, do not play, and play when it lands ------------
        let asked = [];
        audio.fetchAsked.connect((p, u) => asked.push(u));
        const playsBefore = stub.plays;
        audio.toggle("d", "", "PART_d.amr");
        check(asked.length === 1 && audio.awaiting === true,
              "toggling a note with no file did not raise fetchAsked / set awaiting");
        check(stub.plays === playsBefore,
              "it tried to play a file it does not have");
        audio.fileArrived("PART_d.amr", "/c/d.amr");
        check(audio.playingId === "d" && audio.awaiting === false,
              "the fetched note did not start on arrival");

        // A fetch for a note we are no longer waiting on must not start it.
        audio.stop();
        audio.fileArrived("PART_other.amr", "/c/other.amr");
        check(audio.playingId === "",
              "an unrelated attachment started playing");

        // --- the fetch that never lands, closed by a Timer ---------------------
        audio.fetchTimeoutMs = 200;
        audio.toggle("f", "", "PART_never.amr");
        settleWait.start();
    }

    Timer {
        id: settleWait
        interval: 700
        repeat: false
        onTriggered: {
            const check = (ok, why) => { if (!ok) root.bad.push(why); };
            check(audio.awaiting === false && audio.missing === true,
                  "a fetch that never landed left the bubble waiting forever");
            root.finish();
        }
    }
}
