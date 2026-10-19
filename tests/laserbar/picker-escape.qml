import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// Control experiment: the wallpaper picker is known to dismiss on Escape on
// the real session. If it does not here either, the harness is the problem.
Scope {
    Wallpaper { id: wp; Component.onCompleted: wp.pickerOpen = true }
}
