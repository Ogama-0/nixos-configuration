import QtQuick
import Quickshell
import Quickshell.Wayland
import "components/panel"

// Bodies carrying markup. The WhatsApp ones arrive the way KDE Connect
// really sends them - with the phone app's tags escaped - and must come out
// bold and broken across lines anyway. The selected row is expanded, so it
// honours the breaks; the others have one line to spend and flatten them.
// Thunderbird sends its tags unescaped, the ordinary case.
//
// "&amp;lt;3" is the control: a message that really is about the characters
// keeps them, because only the spec's own tags are put back.
//
// Pane at 100,100, 262x400, uiScale 1.
Scope {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#FF2040A0"
        focusable: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay

        NotificationPane {
            x: 100
            y: 100
            width: 262
            height: 400
            uiScale: 1
            expanded: ({ "relay-whatsapp": true })
            selectedUids: ["w1", "w2"]
            groups: [
                { key: "relay-whatsapp", app: "WhatsApp", relay: true, count: 2, items: [
                    { uid: "w1", appName: "KDE Connect", summary: "WhatsApp",
                      body: "Au 119 L.O.M (2 messages): &lt;b&gt;H&#233;l&#233;na&lt;/b&gt;&lt;br/&gt;je t&#39;aime &lt;3" },
                    { uid: "w2", appName: "KDE Connect", summary: "WhatsApp",
                      body: "Sibling All Over The World (2 messages): &lt;b&gt;H&#233;l&#233;na&lt;/b&gt;&lt;br/&gt;Est ce que vous &#234;tes tjrs abo au 1?&lt;br/&gt;j voulais lire celui l&#224;" } ] },
                { key: "Thunderbird", app: "Thunderbird", count: 1, items: [
                    { uid: "t1", appName: "Thunderbird", summary: "<i>oscar.cornut@epita.fr</i>",
                      body: "<b>[EPITA]</b> 2627_I_INF_FISE_S05_A<br>second line" } ] }
            ]
        }
    }
}
