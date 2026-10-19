import Quickshell
import "components"

Scope {
    Wallpaper {}
    Clock {}
    Music {}
    Calendar {}
    Lock { id: lock }
    LaserBar { id: bar; onPanelRequested: controlPanel.summon() }
    StatusPanel {}
    // An open panel must not survive into the lock screen.
    ControlPanel {
        id: controlPanel
        lockActive: lock.locked
        barVisible: bar.active
        // lock.locked, not lock.lock(). That function is defined on Lock's
        // IpcHandler and not on Lock itself, so calling it threw TypeError
        // every time and the tile did nothing. Its whole body is
        // `root.locked = true`, which is this - and without a subprocess.
        onLockRequested: lock.locked = true
    }
}
