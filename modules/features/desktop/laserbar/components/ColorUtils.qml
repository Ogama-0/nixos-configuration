import QtQuick

// Small shared color helper, instantiated where needed (see BeamSide.qml,
// ClockModule.qml) instead of duplicating the function in each file.
QtObject {
    // Blends an "#AARRGGBB" color toward white by `amt` (0-1), so strands
    // drawn in a side's accent color can read as a lighter tint against the
    // (same-hue, more saturated) glow behind them instead of blending in.
    function lightenColor(argb, amt) {
        const a = argb.substr(1, 2)
        const r = parseInt(argb.substr(3, 2), 16)
        const g = parseInt(argb.substr(5, 2), 16)
        const b = parseInt(argb.substr(7, 2), 16)
        const nr = Math.round(r + (255 - r) * amt)
        const ng = Math.round(g + (255 - g) * amt)
        const nb = Math.round(b + (255 - b) * amt)
        const hex = v => v.toString(16).padStart(2, "0")
        return "#" + a + hex(nr) + hex(ng) + hex(nb)
    }
}
