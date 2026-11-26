import QtQuick
import Quickshell
import "panel/mainpanel"

// ToggleModel.countFullscreen, against the shape sway's get_tree actually has.
//
// This exists for one reason: every workspace node in sway's tree carries
// `fullscreen_mode: 1` of its own accord, all the time, whether or not
// anything in it is fullscreen. A walk that trusts that field alone reports
// the machine as permanently fullscreen, and the idle tile then permanently
// claims that fullscreen is holding the lock off. Verified against a live
// tree while writing this: seven workspaces, seven ones, nothing fullscreen.
//
// So the type filter is the assertion. The rest pins the conditions sway's own
// `inhibit_idle fullscreen` applies: fullscreen AND actually on screen.
//
// Logic fixture, not a render fixture: run it with
//   scripts/qml-logic-test.sh tests/laserbar/panel-idle-fullscreen.qml IDLEFS_OK
ShellRoot {
    id: root

    ToggleModel { id: m; active: false }

    // A workspace carrying the field, holding one ordinary window. This is
    // the resting state of a real desktop, and it must count as zero.
    readonly property string workspaceOnly: JSON.stringify({
        type: "root",
        nodes: [{
            type: "output", name: "eDP-1", fullscreen_mode: 0,
            nodes: [{
                type: "workspace", name: "1", fullscreen_mode: 1, nodes: [
                    { type: "con", app_id: "Alacritty", fullscreen_mode: 0, visible: true }
                ]
            }]
        }]
    })

    // The same tree with the window actually fullscreen.
    readonly property string realFullscreen: JSON.stringify({
        type: "root",
        nodes: [{
            type: "output", name: "eDP-1", fullscreen_mode: 0,
            nodes: [{
                type: "workspace", name: "1", fullscreen_mode: 1, nodes: [
                    { type: "con", app_id: "zen-beta", fullscreen_mode: 1, visible: true }
                ]
            }]
        }]
    })

    // Fullscreen on a workspace that is NOT on screen. sway does not inhibit
    // idle for this one, so neither may the tile: a video left fullscreen on
    // workspace 9 must not stop the laptop locking for the rest of the day.
    readonly property string hiddenFullscreen: JSON.stringify({
        type: "root",
        nodes: [{
            type: "output", name: "eDP-1", fullscreen_mode: 0,
            nodes: [
                { type: "workspace", name: "1", fullscreen_mode: 1, nodes: [
                    { type: "con", app_id: "Alacritty", fullscreen_mode: 0, visible: true }
                ]},
                { type: "workspace", name: "9", fullscreen_mode: 1, nodes: [
                    { type: "con", app_id: "mpv", fullscreen_mode: 1, visible: false }
                ]}
            ]
        }]
    })

    // Floating windows hang off floating_nodes, a sibling list the walk has to
    // descend as well - a tree walked through `nodes` alone misses every
    // floating window there is.
    readonly property string floatingFullscreen: JSON.stringify({
        type: "root",
        nodes: [{
            type: "output", name: "eDP-1", fullscreen_mode: 0,
            nodes: [{
                type: "workspace", name: "1", fullscreen_mode: 1,
                nodes: [],
                floating_nodes: [
                    { type: "floating_con", app_id: "mpv", fullscreen_mode: 1, visible: true }
                ]
            }]
        }]
    })

    Component.onCompleted: {
        let bad = [];

        const check = (label, json, want) => {
            const got = m.countFullscreen(json);
            if (got !== want)
                bad.push(label + " = " + got + ", wanted " + want);
        };

        check("workspace nodes alone", root.workspaceOnly, 0);
        check("one visible fullscreen window", root.realFullscreen, 1);
        check("fullscreen on a hidden workspace", root.hiddenFullscreen, 0);
        check("fullscreen floating window", root.floatingFullscreen, 1);

        // Garbage must read as "not fullscreen", never as fullscreen: a
        // truncated tree labelling the tile with a cause that is not there is
        // worse than missing one, because it sends you looking for a
        // fullscreen window you do not have.
        check("not json at all", "swaymsg: command not found", 0);
        check("empty", "", 0);
        check("truncated json", '{"type":"root","nodes":[{"type":"wo', 0);

        if (bad.length === 0) console.log("IDLEFS_OK");
        else console.log("IDLEFS_BAD: " + bad.join(" | "));
    }
}
