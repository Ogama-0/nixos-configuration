import QtQuick
import Quickshell
import Quickshell.Io
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
        // The real MediaPlayer needs `source` set before play(); declared
        // here so the production code can assign it unconditionally instead
        // of guarding against a stub that doesn't have the property.
        property string source: ""
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

    // A real VoiceBubble, not a further stub - seekAt()'s guard (round 1)
    // is proven both directions against it below: an ACTIVE bubble's press
    // must still reach seekTo, not just an idle one being blocked.
    VoiceBubble {
        id: seekProbe
        width: 224
        height: 48
        audio: audio
        msgId: "seek-target"
        attachment: ({ partId: 9, mime: "audio/amr", data: "",
                       uid: "PART_seek.amr", path: "" })
    }

    property var bad: []
    // A scratch path under /tmp, created and removed by this fixture (see
    // the playable() re-stat proof below) - distinct from realFile, which
    // must stay present for the whole run.
    property string restatPath: "/tmp/messages-audio-playable-"
        + Date.now() + ".probe"
    // toggle() now stats the path before playing it (see MessageAudio's
    // playable() gate) - the state-machine assertions below need a path
    // that genuinely exists so that gate is not what they are testing.
    // /etc/os-release is present on every Linux this fixture runs on; its
    // content is never read.
    property string realFile: "/etc/os-release"

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
        //
        // partId only matters on the no-path (fetchAsked) branch, exercised
        // below - these calls already have a path, so the value here is
        // never read. Still non-zero so a bug that started reading it on
        // this branch would be visible rather than accidentally correct.
        audio.toggle("a", root.realFile, "a.amr", 1);
        check(audio.playingId === "a",
              "toggle did not start playing a: " + audio.playingId);
        audio.toggle("b", root.realFile, "b.amr", 2);
        check(audio.playingId === "b",
              "starting a second note did not take over");
        check(stub.stops === 1, "the first note was not stopped: " + stub.stops);

        // --- same id toggles rather than restarts -----------------------------
        audio.toggle("b", root.realFile, "b.amr", 2);
        check(audio.paused === true && audio.playingId === "b",
              "toggling the same id did not pause it in place");

        // --- a note that plays to its own end must clear itself, not just
        // pause rendering forever ------------------------------------------
        //
        // The stub never moves its own playbackState - nothing here decodes
        // audio - so this drives it by hand to StoppedState (0) the way a
        // real MediaPlayer would once decoding runs out, with a trip through
        // PlayingState (1) first so the property actually changes and the
        // Connections handler fires (QML suppresses a changed signal on a
        // no-op assignment, and the stub already starts at 0).
        audio.toggle("g", root.realFile, "g.amr", 1);
        check(audio.playingId === "g",
              "toggle did not start playing g: " + audio.playingId);
        audio.position = 3000;
        audio.duration = 3000;
        stub.playbackState = 1;
        stub.playbackState = 0;
        check(audio.playingId === "" && audio.position === 0 && audio.duration === 0,
              "playback reaching its own end left playingId/position/duration "
                  + "behind - playingId=" + audio.playingId
                  + " position=" + audio.position
                  + " duration=" + audio.duration);

        // And the bubble must not need two taps to replay: toggle() on the
        // SAME id right after must START it again, not pause an already-
        // stopped player (the "same id toggles rather than restarts" branch
        // above, misfiring because playingId was never cleared).
        const playsBeforeReplay = stub.plays;
        audio.toggle("g", root.realFile, "g.amr", 1);
        check(audio.playingId === "g" && stub.plays === playsBeforeReplay + 1,
              "replaying a note right after it ended paused instead of "
                  + "starting it");

        // --- REVIEW FOCUS 3: the panel going away stops it --------------------
        //
        // Relative, not a hardcoded count: the block above already asked the
        // stub to stop() both when "g" took over from "b" and when the
        // simulated end-of-track fired, so the absolute count a straight
        // read of this fixture's history would suggest is not 1 any more -
        // what actually matters is that THIS stop() call moves it by
        // exactly one, same as REVIEW FOCUS 4 below already checks it.
        const stopsBeforeFocus3 = stub.stops;
        audio.stop();
        check(audio.playingId === "" && stub.stops === stopsBeforeFocus3 + 1,
              "stop() did not stop the player and clear playingId");

        // --- REVIEW FOCUS 4: the open thread changes while a note is playing --
        //
        // What actually happens on a thread switch is
        // MessagesCore.openConversation() calling audio.stop() before
        // model.openConversation() - a two-line wrapper this fixture cannot
        // drive directly, because MessagesCore hardcodes its MessageStore to
        // @msgDbName@ (the real device's cache path, not overridable), and
        // instantiating one here would mean a test touching production data.
        // The honest thing to assert at this level is what that wrapper's
        // stop() call depends on: that it silences a note that is genuinely
        // mid-playback (position/duration non-zero, actually sounding) and
        // not merely a relabelling of playingId, which would pass even with
        // a stop() that forgot to touch the player at all.
        audio.toggle("c", root.realFile, "c.amr", 3);
        audio.position = 4500;
        audio.duration = 9000;
        const stopsBeforeFocus4 = stub.stops;
        audio.stop();
        check(audio.playingId === "" && audio.position === 0 && audio.duration === 0
                  && stub.stops === stopsBeforeFocus4 + 1,
              "stop() left a mid-playback note's state behind, or never told "
                  + "the player to stop");

        // --- no file yet: ask, do not play, and play when it lands ------------
        let asked = [];
        audio.fetchAsked.connect((p, u) => asked.push(u));
        const playsBefore = stub.plays;
        audio.toggle("d", "", "PART_d.amr", 46);
        check(asked.length === 1 && asked[0] === "PART_d.amr" && audio.awaiting === true,
              "toggling a note with no file did not raise fetchAsked / set awaiting");
        check(stub.plays === playsBefore,
              "it tried to play a file it does not have");

        // A fetch for a DIFFERENT uid, arriving while "d" is still the one
        // outstanding, must be recognised as someone else's and ignored -
        // this is the uid !== pendingUid branch, not the "nothing pending"
        // one below.
        audio.fileArrived("PART_other.amr", "/c/other.amr");
        check(audio.playingId === "" && audio.awaiting === true,
              "an unrelated attachment in flight was mistaken for the one "
                  + "being waited on");

        // The right one, arriving after, plays.
        audio.fileArrived("PART_d.amr", "/c/d.amr");
        check(audio.playingId === "d" && audio.awaiting === false,
              "the fetched note did not start on arrival");

        // And with nothing outstanding at all - the pendingUid === "" branch -
        // an attachment landing is a no-op.
        audio.stop();
        audio.fileArrived("PART_other.amr", "/c/other.amr");
        check(audio.playingId === "",
              "an attachment arrived with nothing pending and started playing");

        // --- REVIEW FOCUS 2: duration 0 while it loads must not make a NaN width
        check(audio.progressAt(0, 0) === 0,
              "a zero duration produced " + audio.progressAt(0, 0));
        check(audio.progressAt(5000, 0) === 0,
              "a zero duration produced " + audio.progressAt(5000, 0));
        check(audio.progressAt(5000, 10000) === 0.5,
              "progressAt(5000, 10000) was " + audio.progressAt(5000, 10000));

        // --- REVIEW FOCUS 1: the row says we have it, the disk says otherwise --
        check(audio.playable("/c/definitely-not-here.amr") === false,
              "a nonexistent path was reported playable");
        audio.toggle("e", "/c/definitely-not-here.amr", "PART_e.amr", 99);
        check(audio.playingId === "" && audio.missing === true,
              "a vanished file left the bubble spinning");

        // --- VoiceBubble.seekAt: the active guard (round 1), both directions ---
        //
        // Round 1 added the isActive-only guard; nothing proved it lets the
        // ACTIVE case through, only that it blocks the idle one - a guard
        // keyed off the wrong property, or simply inverted, would have
        // passed everything that existed then. seekAt(x) computes
        // `audio.duration * x / track.width`; track.width is internal to
        // VoiceBubble and not observable from here, so rather than compute
        // an exact expected offset, a wildly oversized x is used - on any
        // positive track.width that drives the ms argument past
        // audio.duration, and seekTo() clamps to the max. That is a robust
        // "did this reach the player at all" signal without reaching into
        // VoiceBubble's internals.
        audio.playingId = "seek-target";
        audio.duration = 20000;
        stub.position = 0;
        seekProbe.seekAt(999999);
        check(stub.position === stub.duration,
              "an ACTIVE bubble's seek did not reach the player - "
                  + "stub.position=" + stub.position
                  + " stub.duration=" + stub.duration);

        audio.playingId = "someone-else";
        stub.position = 777;
        seekProbe.seekAt(999999);
        check(stub.position === 777,
              "an IDLE bubble's seek moved the player anyway - stub.position="
                  + stub.position);

        // --- playable() re-stats on a REPEAT query of the SAME path ------------
        //
        // The path setter it probes through is a no-op on an unchanged
        // value, which is exactly why playable() routes through "" before
        // the real path on every call (see its own comment). Proving that
        // needs the SAME path asked twice in a row with its existence
        // changing in between - two different paths (the first version of
        // this check) never exercises the no-op-on-same-value case at all.
        // That needs a real file on disk, so it is async: a Process
        // creates it, playable() is asked, a Process removes it, playable()
        // is asked again. Counterfactual checked by hand while writing
        // this: delete the `existsProbe.path = ""` reset in
        // MessageAudio.playable() and the "after-create" check below goes
        // red (stays false, replaying the pre-create answer).
        check(audio.playable(root.restatPath) === false,
              "a path was reported playable before it was ever created");
        restatCreate.running = true;
    }

    Process {
        id: restatCreate
        command: ["touch", root.restatPath]
        onExited: restatAfterCreate.start()
    }

    Process {
        id: restatRemove
        command: ["rm", "-f", root.restatPath]
        onExited: restatAfterRemove.start()
    }

    Timer {
        id: restatAfterCreate
        interval: 50
        repeat: false
        onTriggered: {
            const check = (ok, why) => { if (!ok) root.bad.push(why); };
            check(audio.playable(root.restatPath) === true,
                  "playable() still said missing right after the SAME "
                      + "path was created - a cached first answer, not a "
                      + "re-stat");
            restatRemove.running = true;
        }
    }

    Timer {
        id: restatAfterRemove
        interval: 50
        repeat: false
        onTriggered: {
            const check = (ok, why) => { if (!ok) root.bad.push(why); };
            check(audio.playable(root.restatPath) === false,
                  "playable() kept saying present after the SAME path was "
                      + "deleted - a cached first answer, not a re-stat");

            // --- the fetch that never lands, closed by a Timer -------------
            audio.fetchTimeoutMs = 200;
            audio.toggle("f", "", "PART_never.amr", 7);
            settleWait.start();
        }
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
