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
        onLockRequested: lock.lock()
    }
}
