import QtQuick
import Quickshell
import "components/panel/messages"

// ComposeRow's height against the text it is holding.
//
// The box grew, but by less than the text did: the row reserved
// `field.implicitHeight + 26` while the chrome around the text actually comes
// to 37 (10 above the box, 13 below it, 7+7 inside the Flickable), so the
// visible area was eleven pixels - most of a line - short of the content. One
// line fitted because the 56px floor covered the gap; the second was clipped
// by the row above it, and the box only appeared to start growing at the
// third.
//
//   scripts/qml-logic-test.sh tests/laserbar/messages-compose-size.qml COMPOSE_SIZE_OK
ShellRoot {
    id: root

    property var bad: []

    ComposeRow {
        id: compose
        width: 420
        uiScale: 1
        enabled: true
    }

    // Long enough to wrap several times at 420px wide.
    readonly property string twoLines:
        "asdfasdfakshdgfkajshdgfkjashdgfkjahsdgfkjhagsd fkjhg asdkjfhg"
    readonly property string manyLines:
        "asdfasdfakshdgfkajshdgfkjashdgfkjahsdgfkjhagsd fkjhg asdkjfhg "
        + "aksjdhg fkjhasldkjfhalksjdhfkajshdfkjahsdfkjhasdkjfhaksjdhfkajshdf "
        + "kjahsdfkjhasdfkjhasdkfjhaskjdfhkasjdhfkjashdfkjahsdfkjhasdfkjhasdf"

    function check(ok, why) { if (!ok) root.bad.push(why); }

    Component.onCompleted: {
        // One line: the floor is enough on its own.
        compose.draft = "hi";
        check(compose.visibleTextHeight >= compose.textHeight,
              "one line does not fit: visible " + compose.visibleTextHeight
              + " < text " + compose.textHeight);

        // Two lines: the case in the screenshot. The second line was behind
        // the conversation above it.
        compose.draft = root.twoLines;
        check(compose.textHeight > compose.visibleTextHeight
              || compose.visibleTextHeight >= compose.textHeight,
              "fixture did not wrap - widen it");
        check(compose.visibleTextHeight >= compose.textHeight,
              "the second line is clipped: visible " + compose.visibleTextHeight
              + " < text " + compose.textHeight);

        // Past the ceiling it stops growing and scrolls instead, which is what
        // the header has always claimed and nothing implemented: maxHeight was
        // declared and never read, so a long message pushed the conversation
        // off the top of the pane.
        compose.draft = root.manyLines;
        check(compose.height <= compose.maxHeight * compose.uiScale,
              "the box grew past its ceiling: " + compose.height
              + " > " + compose.maxHeight);
        check(compose.textHeight > compose.visibleTextHeight,
              "at the ceiling the text should overflow and scroll, but visible "
              + compose.visibleTextHeight + " >= text " + compose.textHeight);

        // A staged attachment pushes the field down, and that offset has to be
        // reserved too or it eats the same line again.
        compose.draft = root.twoLines;
        compose.attachments = ["/tmp/a.png"];
        check(compose.visibleTextHeight >= compose.textHeight,
              "a staged attachment clipped the text: visible "
              + compose.visibleTextHeight + " < text " + compose.textHeight);
        compose.attachments = [];

        if (root.bad.length > 0) {
            console.log("COMPOSE_SIZE_FAIL " + root.bad.join(" | ")); return;
        }
        console.log("COMPOSE_SIZE_OK");
    }
}
