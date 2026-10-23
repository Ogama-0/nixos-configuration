import Quickshell
import "components"
import "components/panel"

Scope {
    // ONE weather reader for the whole session, and the only one that knows
    // where the laptop actually is.
    //
    // The desktop clock, the lock surface and the panel each used to run
    // their own curl on their own timer, and all but the panel's hardcoded
    // 48.8566/2.3522 - they printed "Paris" from Lyon, from a train, from
    // anywhere. Everything below is one process (this Scope), so sharing is
    // a property binding; no daemon and no cache file is involved.
    //
    // The greeter keeps its own, unavoidably: it runs as the greetd user and
    // cannot read /home, so it can share nothing of ours.
    //
    // Not gated on anything. The desktop clock shows weather at all times,
    // so there is no window in which this would be idle - and WeatherModel
    // only actually fetches when its reading has aged past fetchTtlMs, so
    // "always on" is still one request per ten minutes for all three.
    WeatherModel { id: weather; active: true }

    // ONE MPRIS choice for the whole session: the music card, the bar
    // capsule and the progress poll all obey this, so a button on the bar
    // cannot address a different player than the card is showing. See
    // MprisModel.qml for why the choice has to remember anything at all.
    MprisModel { id: mpris }

    // The phone's audio never reaches this machine, so when the phone is the
    // player the wave gets generated bands instead of cava's - see
    // RemoteSpectrum.qml. One generator, so the card and the bar capsule
    // move together rather than drifting a frame apart.
    RemoteSpectrum { id: remoteWave; running: mpris.remote && mpris.playing }

    Wallpaper {}
    Clock {
        tempC: weather.tempC
        place: weather.place
        weatherOk: weather.ok
    }
    Music {
        activePlayer: mpris.player
        playerctlName: mpris.playerctlName
        remote: mpris.remote
        remoteLevels: remoteWave.levels
    }
    Calendar {}
    Lock {
        id: lock
        activePlayer: mpris.player
        playerctlName: mpris.playerctlName
        tempC: weather.tempC
        place: weather.place
        weatherOk: weather.ok
    }
    LaserBar {
        id: bar
        mprisPlayer: mpris.player
        mprisRemote: mpris.remote
        mprisRemoteLevels: remoteWave.levels
        onPanelRequested: controlPanel.summon()
    }
    StatusPanel {}
    // An open panel must not survive into the lock screen.
    ControlPanel {
        id: controlPanel
        lockActive: lock.locked
        barVisible: bar.active
        weatherTempC: weather.tempC
        weatherCondition: weather.condition
        weatherPlace: weather.place
        weatherOk: weather.ok
        weatherFailure: weather.failure
        // lock.locked, not lock.lock(). That function is defined on Lock's
        // IpcHandler and not on Lock itself, so calling it threw TypeError
        // every time and the tile did nothing. Its whole body is
        // `root.locked = true`, which is this - and without a subprocess.
        onLockRequested: lock.locked = true
    }
}
