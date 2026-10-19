{ pkgs, ... }:
{
  # Blue-light filter for the sway session, driven by the panel's night-light
  # toggle (quickshell/components/panel/ToggleModel.qml).
  #
  # Deliberately NOT auto-started. The toggle starts and stops
  # gammastep.service, and a unit that came up with the session would make
  # the tile lie about its state on the first open.
  #
  # Replaces the old Hyprland-era script, which drove hyprsunset and has no
  # equivalent here: scripts/swaync/night-shift-toggle.sh.
  # Day and night temperatures are the SAME on purpose. This is a manual
  # blue-light toggle, not a sunset schedule: when you press the tile you
  # want a warm screen now, whatever the hour. Equal endpoints make the sun
  # calculation irrelevant, which is what lets the provider be manual.
  #
  # It was geoclue2 first, and gammastep died on every start with "Unable to
  # get location from provider" - so the tile toggled a unit that exited
  # immediately and the screen never changed colour.
  services.gammastep = {
    enable = true;
    provider = "manual";
    latitude = 48.86;
    longitude = 2.35;
    temperature = {
      day = 3700;
      night = 3700;
    };
  };

  # home-manager's module wants the unit in the graphical session; the point
  # of this one is that it only runs when asked.
  systemd.user.services.gammastep.Install.WantedBy = pkgs.lib.mkForce [ ];
}
