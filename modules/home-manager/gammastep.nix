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
  services.gammastep = {
    enable = true;
    provider = "geoclue2";
    temperature = {
      day = 6500;
      night = 3700;
    };
  };

  # home-manager's module wants the unit in the graphical session; the point
  # of this one is that it only runs when asked.
  systemd.user.services.gammastep.Install.WantedBy = pkgs.lib.mkForce [ ];
}
