import Quickshell
import "components"

Scope {
    Wallpaper {}
    Clock {}
    Music {}
    Calendar {}
    Lock { id: lock }
    LaserBar {}
    StatusPanel {}
    // An open panel must not survive into the lock screen.
    ControlPanel { lockActive: lock.locked }
}
