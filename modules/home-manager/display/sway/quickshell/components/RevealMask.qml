import QtQuick
import QtQuick.Effects

// Consumer must set explicit width/height matching the wrapped content,
// since content is clipped via a mask sized to this item's own bounds.
Item {
    id: root

    required property real coverLeft
    required property real coverRight
    required property real panelWidth

    default property alias content: contentItem.data

    readonly property real originX: root.mapToItem(null, 0, 0).x

    Item {
        id: contentItem
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.0
            maskSpreadAtMin: 0.0
        }
    }

    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            // Portion lit by the left beam.
            color: "white"
            x: 0
            width: Math.max(0, Math.min(root.width, root.coverLeft - root.originX))
            height: parent.height
        }

        Rectangle {
            // Portion lit by the right beam.
            readonly property real litFromLocal: (root.panelWidth - root.coverRight) - root.originX
            color: "white"
            x: Math.max(0, Math.min(root.width, litFromLocal))
            width: root.width - x
            height: parent.height
        }
    }
}
